module VagrantPlugins
  module Share
    module Command
      module Ngrok
        # Default ngrok endpoint for TCP style connections
        DEFAULT_NGROK_TCP_ENDPOINT = "0.tcp.ngrok.io".freeze
        NGROK_TCP_DOMAIN = "tcp.ngrok.io".freeze

        autoload :Connect, "vagrant-share/command/ngrok/connect"
        autoload :Share, "vagrant-share/command/ngrok/share"
      end
    end
  end
end
