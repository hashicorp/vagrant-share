module VagrantPlugins
  module Share
    module Command
      autoload :Connect, "vagrant-share/command/connect"
      autoload :Ngrok, "vagrant-share/command/ngrok"
      autoload :Share, "vagrant-share/command/share"
    end
  end
end
