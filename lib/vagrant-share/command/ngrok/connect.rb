module VagrantPlugins
  module Share
    module Command
      module Ngrok
        module Connect
          # Start the ngrok based connect
          #
          # @param [Array<String>] argv CLI arguments
          # @param [Hash] options CLI options
          def connect_to_share(argv, options)
            if options[:retrap_int]
              halt_queue = Queue.new
              wait_runner = Thread.new do
                until halt_queue.pop == :halt
                  @logger.debug("Connect wait runner watching for halt.")
                end
                @logger.debug("Connect wait runner received halt instruction.")
                :halt
              end
              Helper.signal_retrap("INT") do
                halt_queue << :halt
              end
            end

            name, host_info = argv.first.to_s.split("@")
            proxy_port, api_port = name.split(":").map do |word_pair|
              Helper.dewordify(word_pair.split("_"))
            end
            host_num = host_info.to_s.empty? ? "0" : Helper.dewordify(host_info.split("_")).to_s

            # Determine the static IP to use for the VM, if we're using one.
            ip   = nil
            ip_f = nil
            if !options[:disable_static_ip]
              @logger.info("Acquiring IP for connect VM")
              ip, ip_f = Helper.acquire_ip(@env, options[:static_ip])
              if ip == nil
                if options[:static_ip]
                  raise Errors::IPInUse, ip: options[:static_ip]
                else
                  raise Errors::IPCouldNotAutoAcquire
                end
              end
              @logger.info("Connect VM IP will be: #{ip}")
            end

            # Get the proxy machine we'll start
            machine  = Helper.share_machine(@env, ip: ip)
            ui       = machine.ui
            proxy_ui = machine.ui.dup
            proxy_ui.opts[:bold] = false
            proxy_ui.opts[:prefix_spaces] = true

            ui.output(I18n.t("vagrant_share.connecting", name: name))

            # Check for box updates if we have a box already...
            if machine.box
              ui.output(I18n.t("vagrant_share.box_update_check"))
              begin
                if machine.box.has_update?
                  ui.detail(I18n.t("vagrant_share.box_update"))

                  # There is an update! Delete the previous box to force
                  # an update.
                  machine.box.destroy!
                  machine.box = nil
                else
                  ui.detail(I18n.t("vagrant_share.box_up_to_date"))
                end
              rescue => e
                @logger.warn("failed to check for box update: #{e}")
              end
            end
            if options[:driver].to_s.include?("ngrok.io")
              proxy_endpoint = options[:driver]
            else
              proxy_endpoint = "#{host_num}.#{NGROK_TCP_DOMAIN}"
            end

            # Start the machine
            ui.output(I18n.t("vagrant_share.starting_proxy_vm"))
            machine.with_ui(proxy_ui) do
              machine.action(:up)
              machine.guest.capability(:connect_proxy, proxy_endpoint, proxy_port,
                type: :standalone
              )
            end

            yield name, ui, ip, proxy_port, api_port

            # NOTE: Use a timed join on wait thread to prevent deadlock being claimed
            if wait_runner
              until wait_runner.join(30) == :halt
                if Helper.ping_share(ip, api_port)
                  @logger.debug("Validated share connection alive. Waiting for halt.")
                else
                  @logger.error("Share connection state has been lost. Halting connect.")
                  ui.error(I18n.t("vagrant_share.ngrok.connection_lost", name: name))
                  Process.kill("INT", Process.pid)
                end
              end
            end
          ensure
            # If we have a machine, make sure we destroy it
            if machine
              machine.action(:destroy, force_confirm_destroy: true)
            end
            # If we acquired an IP, make sure we close and delete that file
            if ip_f
              ip_f.close
              File.delete(ip_f.path) rescue nil
            end
          end

          # Perform connection to share
          #
          # @param [Array<String>] argv CLI arguments
          # @param [Hash] options CLI options
          def execute_connect(argv, options)
            opts = options.merge(retrap_int: true)
            connect_to_share(argv, opts) do |name, ui, ip, proxy_port, api_port|
              begin
                share = Helper.share_info("share-info", ip, api_port)
              rescue => e
                @logger.error("Failed to establish connection to share `#{name}`." \
                  "#{e.class}: #{e}")
                raise Errors::ShareNotFound, name: name
              end
              ui.output(I18n.t("vagrant_share.looking_up", name: name))

              share["ports"] ||= []
              if !share["ports"].empty?
                ui.detail(I18n.t("vagrant_share.connect_restricted_ports") + "\n ")
                share["ports"].each do |port|
                  next if port.to_s == proxy_port.to_s
                  ui.detail("Port: #{port}")
                end
                ui.detail(" ")
              end

              if share["has_private_key"]
                ui.detail(I18n.t("vagrant_share.connect_ssh_available"))
                ui.detail(" ")
              end

              # Let the user know we connected and how to connect
              ui.success(I18n.t("vagrant_share.started_connect"))
              ui.success(I18n.t(
                "vagrant_share.connect_socks_port", port: proxy_port.to_s))
              ui.success(I18n.t("vagrant_share.connect_ip", ip: ip))
              ui.success(" ")
              ui.success(I18n.t("vagrant_share.connect_info"))
            end
          end

          # Perform SSH connection to share
          #
          # @param [Array<String>] argv CLI arguments
          # @param [Hash] options CLI options
          def execute_ssh(argv, options)
            private_key_path = nil
            connect_to_share(argv, options) do |name, ui, ip, proxy_port, api_port|
              # Determine information about this share
              ui.output(I18n.t("vagrant_share.looking_up", name: name))
              share = Helper.share_info("connect-ssh", ip, api_port)

              if !share["has_private_key"]
                raise Errors::SSHNotShared,
                  name: name
              end

              if share["private_key_password"]
                ui.ask(
                  I18n.t("vagrant_share.connect_password_required"),
                  color: :yellow)
              end

              # Get the private key
              private_key = share["ssh_key"]
              if share["private_key_password"]
                while true
                  password = nil
                  while !password
                    password = ui.ask(
                      "#{I18n.t("vagrant_share.connect_password_prompt")} ",
                      echo: false)
                  end

                  begin
                    private_key = OpenSSL::PKey::RSA.new(private_key, password)
                    private_key = private_key.to_pem
                    password    = nil
                    break
                  rescue OpenSSL::PKey::RSAError
                    ui.error(I18n.t("vagrant_share.connect_invalid_password"))
                  end
                end
              end

              private_key_file = Tempfile.new("vagrant-connect-key")
              private_key_path = Pathname.new(private_key_file.path)
              private_key_file.write(private_key)
              private_key_file.close

              # Nil out the private key so it can be GC'd
              private_key = nil

              # In 45 seconds, delete the private key file. 45 seconds
              # should be long enough for SSH to properly connect.
              key_thr = Thread.new do
                sleep 45
                private_key_path.unlink rescue nil
              end

              # Configure SSH
              ssh_info = {
                host: ip,
                port: share["ssh_port"],
                username: share["ssh_username"],
                private_key_path: [private_key_path.to_s],
              }
              ui.output(I18n.t("vagrant_share.executing_ssh"))
              Vagrant::Util::SSH.check_key_permissions(private_key_path)
              Vagrant::Util::SSH.exec(ssh_info, subprocess: true)
            end
          ensure
            # If the private key is still around, delete it
            if private_key_path && private_key_path.file?
              private_key_path.unlink rescue nil
            end
          end
        end
      end
    end
  end
end
