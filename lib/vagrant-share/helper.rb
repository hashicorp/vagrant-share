require "base64"
require "ipaddr"
require "openssl"
require "pathname"
require "timeout"
require "thread"
require "tmpdir"
require "securerandom"
require "log4r"
require "rest_client"

require "vagrant/util/retryable"
require "vagrant/util/subprocess"
require "vagrant/vagrantfile"

module VagrantPlugins
  module Share
    # Contains helper methods that the command uses.
    class Helper
      autoload :Api, "vagrant-share/helper/api"
      autoload :WordList, "vagrant-share/helper/word_list"

      extend Vagrant::Util::Retryable

      # List of ephemeral ports
      SHARE_PORT_RANGE = (49152..65535).freeze

      # Acquires the given IP for the static IP for the machine. This
      # also cleverly uses file locks to try to make sure that IPs
      # aren't reused if multiple `connect` calls are called.
      #
      # @param [Vagrant::Environment] env
      # @param [String] requested A specific requested IP, or nil if
      #   it doesn't matter.
      # @return [Array<String, File>] The first element is the IP, and
      #   the second is a File that holds the file lock. Make sure to
      #   close this when you're done. Nil is returned if the requested
      #   IP can't be acquired.
      def self.acquire_ip(env, requested)
        if requested
          path = env.tmp_path.join("vagrant_connect_#{requested}")
          f    = path.open("w+")
          if f.flock(File::LOCK_EX | File::LOCK_NB) === false
            # Someone already has this IP.
            f.close
            return nil
          end

          return requested.to_s, f
        end

        # We just skip ".1" and ".2" because they cause problems often.
        range = IPAddr.new("172.16.0.0/12").succ.succ
        while true
          results = acquire_ip(env, range.to_s)
          return results if results
          range = range.succ
        end
      end

      # Acquires the given port if free.
      #
      # @param [Vagrant::Environment] env
      # @param [Integer] requested
      # @return [Array<Integer, File>]
      def self.acquire_port(env, requested=nil)
        if requested
          path = env.tmp_path.join("vagrant_share_#{requested}")
          handle = path.open("w+")
          if !handle.flock(File::LOCK_EX | File::LOCK_NB)
            handle.close
            nil
          else
            begin
              Socket.tcp('127.0.0.1', requested, connect_timeout: 1)
              nil
            rescue Errno::ECONNREFUSED
              [requested, handle]
            end
          end
        else
          port_list = SHARE_PORT_RANGE.to_a
          port = acquire_port(env, port_list.pop) until port || port_list.empty?
          if port.nil?
            raise Errors::PortCouldNotAcquire.new
          else
            port
          end
        end
      end

      # Detects the HTTP/HTTPs ports of the machine automatically by
      # trying a bunch of commonly used ports.
      #
      # @param [String] target IP or FQDN
      # @return [Array] Same as {#detect_forwarded_ports}
      def self.detect_ports(target)
        common = [80, 3000, 4567, 8000, 8080]

        logger  = Log4r::Logger.new("vagrant::share::helper")
        queue   = Queue.new
        workers = []
        common.each do |port|
          workers << Thread.new(port) do |p|
            Thread.current.abort_on_exception = true

            url = "http://#{target}:#{p}/"
            logger.debug("Trying: #{url}")
            queue << p if http_url?(url)
          end
        end

        # Make a thread that puts a tombstone if all the workers are dead
        workers << Thread.new(workers.dup) do |waiters|
          Thread.current.abort_on_exception = true

          begin
            waiters.map(&:join)
          ensure
            queue << nil
          end
        end

        [queue.pop, nil]
      ensure
        workers.map(&:kill)
      end

      # Detects the HTTP/HTTPs ports of the machine automatically using
      # forwarded ports.
      #
      # @param [Vagrant::Machine]
      # @return [Array] Results where first element is HTTP and second
      #   is HTTPs port. Nil elements if not detected.
      def self.detect_forwarded_ports(machine, **opts)
        logger      = Log4r::Logger.new("vagrant::share::helper")
        queue       = Queue.new
        https_queue = Queue.new
        found_https = false
        workers = []

        machine.config.vm.networks.each do |type, netopts|
          next if type != :forwarded_port
          next if !netopts[:host]

          target = opts[:target] || "127.0.0.1"
          port   = opts[:guest_port] ? netopts[:guest] : netopts[:host]

          # Try the forwarded port
          workers << Thread.new(target, port) do |t, p|
            Thread.current.abort_on_exception = true

            url = "http://#{t}:#{p}/"
            logger.debug("Trying: #{url}")
            if http_url?(url)
              logger.info("HTTP url found: #{url}")
              queue << port
            else
              logger.debug("Not an HTTP URL: #{url}")
            end
          end

          # If it is an SSL port, attempt an SSL connection...
          if netopts[:guest].to_i == 443 && !found_https
            found_https = true

            workers << Thread.new(target, port) do |t, p|
              Thread.current.abort_on_exception = true

              url = "https://#{t}:#{p}/"
              logger.debug("Trying HTTPS: #{url}")
              if http_url?(url, secure: true)
                https_queue << port
              else
                https_queue << nil
              end
            end
          end
        end

        # Make a thread that puts a tombstone if all the workers are dead
        workers << Thread.new(workers.dup) do |waiters|
          Thread.current.abort_on_exception = true

          begin
            waiters.map(&:join)
          ensure
            queue << nil
          end
        end

        if !found_https
          Thread.new do
            # We never had an https candidate, so just put a nil on it
            https_queue << nil
          end
        end

        [queue.pop, https_queue.pop]
      ensure
        workers.map(&:kill)
      end

      # Get information from vagrant internal share API
      #
      # @param [String] path
      # @param [String] ip
      # @param [Integer] port
      # @return [Hash]
      def self.share_info(path, ip, port)
        uri = URI.parse("https://#{ip}:#{port}/#{path}")
        conn = Net::HTTP.new(uri.host, uri.port)
        conn.use_ssl = true
        conn.verify_mode = OpenSSL::SSL::VERIFY_NONE
        response = conn.get(uri.path)
        JSON.parse(response.body.to_s)
      end

      # Ping share to validate connection
      #
      # @param [String] ip
      # @param [Integer] port
      # @return [TrueClass, FalseClass] connection is valid
      def self.ping_share(ip, port, **opts)
        uri = URI.parse("https://#{ip}:#{port}/#{opts.fetch(:path, "ping")}")
        begin
          conn = Net::HTTP.new(uri.host, uri.port)
          conn.use_ssl = true
          conn.verify_mode = OpenSSL::SSL::VERIFY_NONE
          response = conn.get(uri.path)
          response.code.to_s == "200"
        rescue
          false
        end
      end

      # Convert number into words
      #
      # @param [Integer] int
      # @return [Array<String>]
      def self.wordify(int)
        WordList.encode(int)
      end

      # Convert words into number
      #
      # @param [Array<String>] words
      # @return [Integer]
      def self.dewordify(words)
        WordList.decode(words)
      end

      # Trap given signal and execute given block. Reapply replaced
      # signal trap block when complete.
      #
      # @param [String] type
      # @return [Proc]
      def self.signal_retrap(type)
        initial_trap = Signal.trap(type) do
          yield
          Signal.trap(type, initial_trap)
        end
      end

      # Detects the HTTP/HTTPS ports using a hybrid approach by
      # trying both the forwarded port and common port methods.
      #
      # @return [Array]
      def self.detect_hybrid(machine, target)
        http_queue  = Queue.new
        https_queue = Queue.new

        workers = []
        workers << Thread.new do
          Thread.current.abort_on_exception = true

          results = detect_forwarded_ports(
            machine, target: target, guest_port: true)
          http_queue << results[0] if results && results[0]
          https_queue << results[1] if results && results[1]
        end

        workers << Thread.new do
          Thread.current.abort_on_exception = true

          results = detect_ports(target)
          http_queue << results[0] if results && results[0]
          https_queue << results[1] if results && results[1]
        end

        workers << Thread.new(workers.dup) do |waiters|
          Thread.current.abort_on_exception = true

          begin
            waiters.map(&:join)
          ensure
            http_queue << nil
            https_queue << nil
          end
        end

        [http_queue.pop, https_queue.pop]
      ensure
        workers.map(&:kill)
      end

      # Returns the forwarded ports (on the host) for the machine.
      #
      # @return [Hash<Integer, Integer>] Mapping of forwarded ports. The
      #   key is the host port and the value is the guest port.
      def self.forwarded_ports(machine)
        if machine.provider.capability?(:forwarded_ports)
          # This is a much more correct way, if it is available
          return machine.provider.capability(:forwarded_ports)
        end

        # This is so we can implement it for other providers while still
        # allowing them to implement it eventually. For example, we can
        # support people running older VMware plugins.
        if machine.provider.capability?(:vagrant_share__forwarded_ports)
          return machine.provider.capability(:vagrant_share__forwarded_ports)
        end

        {}.tap do |result|
          machine.config.vm.networks.each do |type, netopts|
            next if type != :forwarded_port
            next if !netopts[:host]
            result[netopts[:host]] = netopts[:guest]
          end
        end
      end

      # Looks up the guest port of a forwarded port.
      #
      # @param [Integer] port Port on the host.
      # @return [Integer]
      def self.guest_forwarded_port(machine, port)
        forwarded_ports(machine)[port]
      end

      # Looks up the host port of a forwarded port.
      #
      # @param [Integer] port Port on the guest.
      # @return [Integer]
      def self.host_forwarded_port(machine, port)
        forwarded_ports(machine).invert[port]
      end

      # Creates an SSH keypair and returns it.
      #
      # @param [String] password Password for the key, or nil for no password.
      # @return [Array<String, String, String>] PEM-encoded public and private key,
      #   respectively. The final element is the OpenSSH encoded public
      #   key.
      def self.generate_keypair(password)
        rsa_key     = OpenSSL::PKey::RSA.new(2048)
        public_key  = rsa_key.public_key
        private_key = rsa_key.to_pem

        if password
          cipher      = OpenSSL::Cipher.new('des3')
          private_key = rsa_key.to_pem(cipher, password)
        end

        # Generate the binary necessary for the OpenSSH public key.
        binary = [7].pack("N")
        binary += "ssh-rsa"
        ["e", "n"].each do |m|
          val  = public_key.send(m)
          data = val.to_s(2)

          first_byte = data[0,1].unpack("c").first
          if val < 0
            data[0] = [0x80 & first_byte].pack("c")
          elsif first_byte < 0
            data = 0.chr + data
          end

          binary += [data.length].pack("N") + data
        end

        openssh_key = "ssh-rsa #{Base64.encode64(binary).gsub("\n", "")} vagrant-share"
        public_key  = public_key.to_pem
        return [public_key, private_key, openssh_key]
      end

      # Tests if the URL given is a valid URL for HTTP access.
      #
      # @return [Boolean]
      def self.http_url?(url, **opts)
        exceptions = [
          Errno::EACCES,
          Errno::ECONNREFUSED,
          Net::HTTPBadResponse,
        ]

        begin
          args = {
            method: :get,
            url:    url,
          }

          if opts[:secure]
            args[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
          end

          retryable(on: exceptions, tries: 2) do
            Timeout.timeout(2) do
              RestClient::Request.execute(args)
            end
          end
          return true
        rescue Errno::EACCES
        rescue Errno::ECONNREFUSED
        rescue Errno::ECONNRESET
        rescue Net::HTTPBadResponse
        rescue RestClient::RequestTimeout
        rescue RestClient::ServerBrokeConnection
        rescue Timeout::Error
          # All the above are bad and should return false.
          # Below this are good exceptions.
        rescue RestClient::ExceptionWithResponse
          # This will catch any HTTP status code errors, which means
          # there is an HTTP sever on the other end, so we should accept that.
          return true
        end

        false
      end

      # Returns a {Vagrant::Machine} that is properly configured
      # and can be started/stopped for connections.
      #
      # @return [Vagrant::Machine]
      # @note This is used for Ngrok implementation
      def self.share_machine(env, **opts)
        provider = env.default_provider.to_sym
        if ![:dummy, :virtualbox, :vmware_fusion, :vmware_workstation, :vmware_desktop].include?(provider)
          raise Errors::ProxyMachineBadProvider, provider: provider.to_s
        end

        machine_name = opts.fetch(:name, "connect").to_sym

        # Our "Vagrantfile" for the proxy machine
        config = lambda do |c|
          c.vm.box = "hashicorp/vagrant-share"
          c.vm.box_version = ">= #{VERSION.segments[0,1].join(".")}, < #{VERSION.bump.version}"
          c.vm.box_check_update = false

          # Configure a DHCP network so that we can get an IP
          if opts[:ip]
            c.vm.network "private_network", ip: opts[:ip]
          end

          if opts[:port]
            c.vm.network "forwarded_port", guest: opts[:port][:guest], host: opts[:port][:host]
          end

          c.vm.provider "virtualbox" do |v|
            v.memory = opts[:memory] || 128
            v.auto_nat_dns_proxy = false
            v.check_guest_additions = false
            v.name = "#{machine_name}-#{SecureRandom.uuid}"
          end

          # NOTE: Default the vmware instances to 256MB for memory. We
          # can get away with much less on virtualbox but will get panics
          # when using less on vmware
          ["vmware_fusion", "vmware_workstation", "vmware_desktop"].each do |vmware|
            c.vm.provider vmware do |v|
              v.vmx["memsize"] = opts[:memory] || 256
              v.whitelist_verified = true
            end
          end

          # Make our only VM the connect-proxy
          c.vm.define machine_name.to_s
        end
        env.config_loader.set(machine_name, [["2", config]])

        data_path   = Pathname.new(Dir.mktmpdir)
        vagrantfile = Vagrant::Vagrantfile.new(env.config_loader, [machine_name])
        vagrantfile.machine(
          machine_name, provider, env.boxes, data_path, env)
      end
    end
  end
end
