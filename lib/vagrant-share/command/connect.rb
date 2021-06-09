require "ipaddr"
require "openssl"
require "pathname"
require "thread"
require "tempfile"
require "uri"

require "log4r"

require "vagrant/util/ssh"

module VagrantPlugins
  module Share
    module Command
      class Connect < Vagrant.plugin("2", "command")

        include Ngrok::Connect

        def self.synopsis
          "connect to a remotely shared Vagrant environment"
        end

        def execute
          @logger = Log4r::Logger.new("vagrant::share::command::connect")

          options = {}

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant connect NAME"
            o.separator ""
            o.separator "Gives you access to any Vagrant environment shared using "
            o.separator "`vagrant share`. The NAME parameter should be the unique name"
            o.separator "that was outputted with `vagrant share` on the remote side."
            o.separator ""
            o.separator "Vagrant will give you an IP that you can use to access the"
            o.separator "remote environment. You'll be able to access any ports that"
            o.separator "the shared environment has authorized."
            o.separator ""
            o.on("--disable-static-ip", "No static IP, only a SOCKS proxy") do |s|
              options[:disable_static_ip] = s
            end

            o.on("--static-ip IP", String, "Manually override static IP chosen") do |ip|
              begin
                IPAddr.new(ip)
              rescue IPAddr::InvalidAddressError
                raise Errors::IPInvalid, ip: ip
              end

              options[:static_ip] = ip
            end

            o.on("--ssh", "SSH into the remote machine") do |ssh|
              options[:ssh] = ssh
            end

            o.on("--driver DRIVER", "Deprecated option for compatibility") do |driver|
              options[:driver] = driver
            end

            o.on("--share-password", "Custom share password") do |p|
              options[:share_password] = p
            end
          end

          # Parse the options
          argv = parse_options(opts)
          return if !argv
          if argv.empty? || argv.length > 1
            raise Vagrant::Errors::CLIInvalidUsage, help: opts.help.chomp
          end

          if options[:ssh]
            return execute_ssh(argv, options)
          else
            return execute_connect(argv, options)
          end
        end
      end
    end
  end
end
