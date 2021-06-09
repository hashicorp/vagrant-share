require "log4r"

require "vagrant/util/subprocess"

module VagrantPlugins
  module Share
    module Command
      class Share < Vagrant.plugin("2", "command")

        include Ngrok::Share

        def self.synopsis
          "share your Vagrant environment with anyone in the world"
        end

        attr_reader :options

        def execute
          @logger = Log4r::Logger.new("vagrant::share::command::share")
          @options = {}

          options[:use_key_once] = false
          options[:disable_http] = false

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant share"
            o.separator ""
            o.separator "Allows anyone in the world with an internet connection to access"
            o.separator "your Vagrant environment by giving you a globally accessible"
            o.separator "URL. "
            o.separator ""
            o.separator "If the person wanting to connect to your environment also has"
            o.separator "Vagrant installed, they can use `vagrant connect` to connect to"
            o.separator "open any TCP stream to your Vagrant machine."
            o.separator ""
            o.separator "Vagrant will attempt to auto-discover your HTTP port and enable"
            o.separator "that. If you want to disable HTTP, specify the --disable-http flag"
            o.separator "directly. If you want HTTPS, specify the --https flag directly."
            o.separator ""
            o.separator "If the --ssh flag is specified, others can easily SSH into your"
            o.separator "Vagrant environment by using `vagrant connect --ssh`. We generate"
            o.separator "a new SSH key for this that you can encrypt with a password."
            o.separator "When --ssh is specified, all other SSH flags are optional."
            o.separator ""

            o.on("--disable-http", "Disable publicly visible HTTP(S) endpoint") do |d|
              options[:disable_http] = d
            end

            o.on("--disable-https", "Disable publicly visible HTTPS endpoint only") do |d|
              options[:disable_https] = d
            end

            o.on("--domain VALUE", String, "Domain the share name will be a subdomain of") do |n|
              options[:domain] = n
            end

            o.on("--http VALUE", String, "Local HTTP port to forward to") do |p|
              options[:http_port] = p
            end

            o.on("--https VALUE", String, "Local HTTPS port to forward to") do |p|
              options[:https_port] = p
            end

            o.on("--name VALUE", String, "Specific name for the share") do |n|
              options[:name] = n
            end

            o.on("--ssh", "Allow 'vagrant connect --ssh' access") do |ssh|
              options[:ssh] = ssh
            end

            o.on("--ssh-no-password", "Key won't be encrypted with --ssh") do |p|
              options[:ssh_no_password] = p
              options[:ssh_flag] = true
            end

            o.on("--ssh-port PORT", Integer, "Specific port for SSH when using --ssh") do |p|
              options[:ssh_port] = p
              options[:ssh_flag] = true
            end

            o.on("--ssh-once", "Allow 'vagrant connect --ssh' only one time") do |r|
              options[:use_key_once] = true
              options[:ssh_flag] = true
            end

            o.on("--driver DRIVER", "Deprecated option for compatibility") do |d|
              options[:driver] = d
            end

            o.on("--full", "Share entire machine") do |full|
              options[:full_share] = true
            end

            o.on("--share-password", "Custom share password") do |p|
              options[:share_password] = p
            end
          end

          # Parse the options
          argv = parse_options(opts)
          return if !argv
          if argv.length > 1
            raise Vagrant::Errors::CLIInvalidUsage, help: opts.help.chomp
          end

          # If an SSH option was specified without the --ssh flag, let
          # the user know.
          if !options[:ssh] && options[:ssh_flag]
            @env.ui.error(I18n.t("vagrant_share.ssh_flag_missing") + "\n ")
            raise Vagrant::Errors::CLIInvalidUsage, help: opts.help.chomp
          end

          # If we're not using HTTP, get rid of the ports
          if options[:disable_http]
            options[:http_port] = nil
            options[:https_port] = nil
          end

          start_share(argv, options)
        end

        protected

        def detect_ports!(options, target, machine)
          detected = nil
          if target == "127.0.0.1"
            # Use forwarded ports to detect because we're NATting
            detected = Helper.detect_forwarded_ports(machine) || []
            if !detected[0]
              raise Errors::DetectHTTPForwardedPortFailed
            end
          else
            # Try forwarded ports first because its not such a
            # shot in the dark.
            detected = Helper.detect_hybrid(machine, target)
            if !detected[0]
              raise Errors::DetectHTTPCommonPortFailed,
                target: target
            end
          end

          options[:http_port] = detected[0]
          if !options[:https_port] && detected[1]
            options[:https_port] = detected[1]
          end
        end
      end
    end
  end
end
