module VagrantPlugins
  module Share
    module Command
      # Ngrok specific implementation
      module Ngrok
        # Ngrok share implementation
        module Share
          # Guest port within proxy
          GUEST_PROXY_PORT = 31338

          # Start the ngrok based share
          #
          # @param [Array<String>] argv CLI arguments
          # @param [Hash] options CLI options
          def start_share(argv, options)
            validate_ngrok_installation!

            # Define variables to ensure availability within ensure block
            # Set this here so they're available in our ensure block
            vagrant_port = nil
            share_machine = nil
            share_api = nil
            share_api_runner = nil
            proxy_runner = nil
            output_runner = nil
            port_file = nil
            ui = nil
            share_info_output = Queue.new
            configuration = {
              "tunnels" => {}
            }

            begin
              with_target_vms(argv, single_target: true) do |machine|
                ui = machine.ui
                machine.ui.output(I18n.t("vagrant_share.detecting"))

                target = validate_target_machine(machine, options) || "127.0.0.1"

                restrict = false
                ports    = []

                machine.ui.detail("Local machine address: #{target}")
                if target == "127.0.0.1"
                  machine.ui.detail(" \n" + I18n.t(
                    "vagrant_share.local_address_only",
                    provider: machine.provider_name.to_s,
                  ) + "\n ")

                  # Restrict the ports that can be accessed since we're
                  # on localhost.
                  restrict = true
                  ports = Helper.forwarded_ports(machine).keys
                end

                if !options[:http_port] && !options[:disable_http]
                  begin
                    @logger.debug("No HTTP port set. Auto-detection will be attempted.")
                    # Always target localhost when using ngrok
                    detect_ports!(options, "127.0.0.1", machine)
                    options[:https_port] = nil if options[:disable_https]
                  rescue Errors::DetectHTTPForwardedPortFailed,
                      Errors::DetectHTTPCommonPortFailed
                    # If SSH isn't enabled, raise the errors. If SSH is enabled,
                    # then we can ignore that HTTP is unavailable.
                    raise if !options[:ssh]

                    machine.ui.detail(I18n.t("vagrant_share.ssh_no_http") + "\n ")
                  end
                end

                if options[:ssh]
                  options[:ssh_username], options[:ssh_port] = configure_ssh_share(machine, "127.0.0.1", options)
                  options[:ssh_password], options[:ssh_privkey] = configure_ssh_connect(machine, configuration, options)
                end

                machine.ui.detail(
                  "Local HTTP port: #{options[:http_port] || "disabled"}")
                machine.ui.detail(
                  "Local HTTPS port: #{options[:https_port] || "disabled"}")
                if options[:ssh]
                  machine.ui.detail("SSH Port: #{options[:ssh_port]}")
                end
                if restrict
                  ports.each do |port|
                    machine.ui.detail("Port: #{port}")
                  end
                end

                machine.ui.output(I18n.t("vagrant_share.creating"))

                if options[:http_port]
                  configuration["tunnels"]["http"] = {
                    "proto" => "http",
                    "bind_tls" => false,
                    "addr" => options[:http_port]
                  }
                end

                if options[:https_port]
                  configuration["tunnels"]["https"] = {
                    "proto" => "tls",
                    "addr" => options[:https_port]
                  }
                end

                if options[:full_share] || (options[:ssh] && !options[:ssh_no_password])
                  configuration["tunnels"].delete("ssh")

                  if options[:full_share]
                    options[:shared_ports] = ports
                  else
                    options[:shared_ports] = [options[:ssh_port]]
                  end

                  @logger.debug("Starting local Vagrant API")

                  share_api = setup_share_api(machine)

                  options[:vagrant_api_port] = share_api.listeners.first.addr[1]
                  proxy_port, port_file = Helper.acquire_port(@env)

                  @logger.debug("Local Vagrant API is listening on port `#{vagrant_port}`")
                  @logger.debug("Local port for proxy forwarding: `#{proxy_port}`")
                  configuration["tunnels"]["proxy"] = {
                    "proto" => "tcp",
                    "addr" => proxy_port
                  }
                  share_machine = Helper.share_machine(@env, port: {guest: GUEST_PROXY_PORT, host: proxy_port}, name: "share")

                  ui = share_machine.ui
                  proxy_ui = share_machine.ui.dup
                  proxy_ui.opts[:bold] = false
                  proxy_ui.opts[:prefix_spaces] = true
                  port_forwards = target ? options[:shared_ports] : []
                  port_forwards << options[:vagrant_api_port]

                  @logger.debug("Starting share proxy VM")
                  share_machine.with_ui(proxy_ui) do
                    share_machine.action(:up)
                    share_machine.guest.capability(:share_proxy,
                      proxy: GUEST_PROXY_PORT,
                      forwards: port_forwards,
                      target: target
                    )
                  end
                end
              end

              if share_api
                @logger.debug("Starting internal Vagrant API")
                share_api_runner = Thread.new{ share_api.start }
              end
              output_runner = start_connect_info_watcher(share_info_output, ui, options)
              ngrok_process = start_ngrok_proxy(ui, configuration, share_info_output, options)

              # Allow user to halt the share process and
              # proxy VM via ctrl-c
              Helper.signal_retrap("INT") do
                ui.warn("Halting Vagrant share!")
                ngrok_process.stop
                share_api.stop if share_api
                share_info_output.push(nil)
              end
            ensure
              if port_file
                port_file.close
                File.delete(port_file) rescue nil
              end
              output_runner.join if output_runner
              share_api_runner.join if share_api_runner
              if share_machine
                share_machine.action(:destroy, force_confirm_destroy: true)
              end
            end
          end

          # Start the ngrok proxy process
          #
          # @param [Vagrant::UI] ui UI instance for output
          # @param [Hash] configurations ngrok process configuration
          # @param [Queue] share_info_output location to push share information
          # @param [Hash] options CLI options
          def start_ngrok_proxy(ui, configuration, share_info_output, options)
            ngrok_process = nil
            base_config = File.expand_path("~/.ngrok2/ngrok.yml")
            share_config = Tempfile.new("vagrant-share")
            share_config.write(configuration.to_yaml)
            share_config.close
            if !File.exists?(base_config)
              base_config = share_config.path
            end
            @logger.debug("Generated configuration for ngrok:\n#{configuration.to_yaml}")
            @logger.debug("Starting ngrok proxy process.")

            ngrok_process = Vagrant::Util::Subprocess.new(
              *["ngrok", "start", "--config", base_config, "--config", share_config.path,
                "--all", "--log", "stdout", "--log-format", "json", "--log-level", "debug"],
              notify: [:stdout]
            )

            Thread.new do
              begin
                share_info = {}
                share_info_keys = []
                share_info_keys.push(:http) if options[:http_port]
                share_info_keys.push(:https) if options[:https_port]
                share_info_keys.push(:name) if options[:ssh] || options[:full_share]

                ngrok_process.execute do |type, data|
                  if type == :stdout
                    data.split("\n").each do |line|
                      begin
                        info = JSON.parse(line)
                        if info["msg"].to_s == "decoded response"
                          begin
                            r_info = info["resp"]
                            if !r_info["Error"].to_s.empty?
                              @logger.error("Error encountered with ngrok connection: #{r_info["Error"]}")
                              share_info_output.push(r_info["Error"])
                              Process.kill("INT", Process.pid)
                            end

                            if r_info["URL"] && r_info["Proto"]
                              share_info[:uri] = URI.parse(r_info["URL"])
                              case share_info[:uri].scheme
                              when "http"
                                share_info[:http] = share_info[:uri].to_s
                              when "https"
                                share_info[:https] = share_info[:uri].to_s
                              when "tcp"
                                connect_name = [share_info[:uri].port, options[:vagrant_api_port]].map do |item|
                                  Helper.wordify(item).join('_')
                                end
                                share_info[:tcp] = share_info[:uri].to_s
                                share_info[:name] = connect_name.join(":")
                                if share_info[:uri].host != DEFAULT_NGROK_TCP_ENDPOINT
                                  host_num = share_info[:uri].host.split(".").first
                                  host_num_word = Helper.wordify(host_num.to_i).join("_")
                                  share_info[:name] += "@#{host_num_word}"
                                end
                              else
                                @logger.warn("Unhandled URI scheme detected: #{share_info[:uri].scheme} - `#{share_info[:uri]}`")
                                share_info.delete(:uri)
                              end
                            end
                          rescue => err
                            @logger.warn("Failed to parse line: #{err}")
                          end
                        end
                        if info["err"] && info["msg"] == "start tunnel listen" && info["err"] != "<nil>"
                          @logger.error("Error encountered with ngrok connection: #{info["err"]}")
                          share_info_output.push(info["err"])
                          # Force shutdown
                          Process.kill("INT", Process.pid)
                        end
                        if share_info_keys.all?{|key| share_info.keys.include?(key)}
                          share_info_output.push(share_info.dup)
                          share_info = {}
                        end
                      rescue => e
                        @logger.warn("Failure handling ngrok process output line: #{e.class} - #{e} (`#{line}`)")
                      end
                    end
                  end
                end
              ensure
                share_config.unlink
              end
            end
            ngrok_process
          end

          # Start the share information watcher to print connect instructions
          #
          # @param [Queue] share_info_output Queue to receive share information
          # @param [Vagrant::UI] ui UI for output
          # @param [Hash] options CLI options
          def start_connect_info_watcher(share_info_output, ui, options)
            Thread.new do
              until((info = share_info_output.pop).nil?)
                begin
                  case info
                  when String
                    ui.error(info)
                  when Hash
                    if info[:name]
                      i_uri = URI.parse(info[:tcp])
                      if i_uri.host != DEFAULT_NGROK_TCP_ENDPOINT
                        driver_name = i_uri.host
                      else
                        driver_name = "ngrok"
                      end
                      ui.success("")
                      ui.success(I18n.t("vagrant_share.started", name: info[:name]))
                      if options[:full_share]
                        ui.success("")
                        ui.success(I18n.t("vagrant_share.ngrok.started_full", name: info[:name], driver: driver_name))
                      end
                      if options[:ssh]
                        ui.success("")
                        ui.success(I18n.t("vagrant_share.ngrok.started_ssh", name: info[:name], driver: driver_name))
                      end
                      ui.success("")
                    end
                    if info[:http]
                      ui.success("HTTP URL: #{info[:http]}")
                      ui.success("")
                    end
                    if info[:https]
                      ui.success("HTTPS URL: #{info[:https]}")
                      ui.success("")
                    end
                  else
                    @logger.warn("Unknown data type receied for output: #{e.class} - #{e}")
                  end
                rescue => e
                  @logger.error("Unexpected error processing connect information: #{e.class} - #{e}")
                end
              end
            end
          end

          # Validate the target machine for the share
          #
          # @param [Vagrant::Machine] machine
          # @param [Hash] options
          # @return [String, NilClass] public address
          def validate_target_machine(machine, options)
            if !machine.ssh_info
              # We use this as a flag of whether or not the machine is
              # running. We can't share a machine that is not running.
              raise Errors::MachineNotReady
            end

            if options[:ssh]
              # Do some quick checks to make sure we can setup this
              # machine for SSH access from other users.
              begin
                if !machine.guest.capability?(:insert_public_key)
                  raise Errors::SSHCantInsertKey,
                    guest: machine.guest.name.to_s
                end
              rescue Vagrant::Errors::MachineGuestNotReady
                raise Errors::SSHNotReady
              end
            end

            target = nil
            if !machine.provider.capability?(:public_address)
              machine.ui.warn(I18n.t(
                "vagrant_share.provider_unsupported",
                provider: machine.provider_name.to_s,
              ))
            else
              target = machine.provider.capability(:public_address)
            end
            target
          end

          # Configure settings for SSH sharing
          #
          # @param [Vagrant::Machine] machine
          # @param [Hash] options
          # @return [Array<String>] ssh username, ssh port
          def configure_ssh_share(machine, target, options)
            ssh_username = nil
            ssh_port = options[:ssh_port] if options[:ssh] && options[:ssh_port]
            if options[:ssh]
              ssh_info = machine.ssh_info
              raise Errors::SSHNotReady if !ssh_info

              ssh_username = ssh_info[:username]
              if !ssh_port
                ssh_port = ssh_info[:port]
                if ssh_info[:host] == "127.0.0.1" && target != "127.0.0.1"
                  # Since we're targetting ourselves, the port probably
                  # points to a forwarded port. Look it up.
                  ssh_port = Helper.guest_forwarded_port(machine, ssh_port)

                  if !ssh_port
                    raise Errors::SSHPortNotDetected
                  end
                end

                if target == "127.0.0.1" && ssh_info[:host] != "127.0.0.1"
                  # The opposite case now. We're proxying to localhost, but
                  # the SSH port is NOT on localhost. We need to look for
                  # a host forwarded port.
                  guest_port = ssh_port
                  ssh_port   = Helper.host_forwarded_port(machine, guest_port)

                  if !ssh_port
                    raise Errors::SSHHostPortNotDetected,
                      guest_port: guest_port.to_s
                  end
                end
              end
            end
            [ssh_username, ssh_port]
          end

          # Configure settings for SSH connect
          #
          # @param [Vagrant::Machine] machine Machine to share
          # @param [Hash] configuration ngrok configuration hash
          # @param [Hash] options CLI options
          # @param [Array<String>] ssh password, ssh privkey
          def configure_ssh_connect(machine, configuration, options)
            ssh_password = nil
            ssh_privkey  = nil
            machine.ui.output(I18n.t("vagrant_share.generating_ssh_key"))

            if !options[:ssh_no_password]
              while !ssh_password
                ssh_password = machine.ui.ask(
                  "#{I18n.t("vagrant_share.ssh_password_prompt")} ",
                  echo: false)
              end

              while ssh_password.length < 4
                machine.ui.warn(
                  "#{I18n.t("vagrant_share.password_not_long_enough")}")
                ssh_password = machine.ui.ask(
                  "#{I18n.t("vagrant_share.ssh_password_prompt")} ",
                  echo: false)
              end

              confirm_password = nil
              while confirm_password != ssh_password
                confirm_password = machine.ui.ask(
                  "#{I18n.t("vagrant_share.ssh_password_confirm_prompt")} ",
                  echo: false)
              end
            else
              configuration["tunnels"]["ssh"] = {
                "proto" => "tcp",
                "addr" => ssh_port
              }
            end

            _, ssh_privkey, openssh_key = Helper.generate_keypair(ssh_password)

            machine.ui.detail(I18n.t("vagrant_share.inserting_ssh_key"))
            machine.guest.capability(:insert_public_key, openssh_key)
            [ssh_password, ssh_privkey]
          end

          # Setup the local share API
          #
          # @param [Vagrant::Machine] machine
          # @return [WEBrick::HTTPServer]
          def setup_share_api(machine)
            share_api = Helper::Api.start_api(machine) do |api|
              api.mount_proc("/ping") do |req, res|
                res.status = 200
                res.body = {message: "pong"}.to_json
              end
              api.mount_proc("/share-info") do |req, res|
                res.status = 200
                res.body = {
                  ports: options[:shared_ports],
                  has_private_key: !!options[:ssh_privkey],
                  private_key_password: !options[:ssh_no_password],
                  ssh_username: options[:ssh_username],
                  ssh_port: options[:ssh_port]
                }.to_json
              end
              api.mount_proc("/shared-ports") do |req, res|
                res.body = {ports: options[:shared_ports]}.to_json
                res.status = 200
              end
              api.mount_proc("/connect-ssh") do |req, res|
                res.body = {
                  ssh_username: options[:ssh_username],
                  ssh_port: options[:ssh_port],
                  ssh_key: options[:ssh_privkey],
                  has_private_key: !!options[:ssh_privkey],
                  private_key_password: !options[:ssh_no_password]
                }.to_json
                res.status = 200
              end
            end
          end

          # Check that ngrok is available on user's PATH
          def validate_ngrok_installation!
            begin
              Vagrant::Util::Subprocess.new("ngrok")
            rescue Vagrant::Errors::CommandUnavailable
              raise Errors::NgrokUnavailable
            end
          end
        end
      end
    end
  end
end

Thread.abort_on_exception = true
