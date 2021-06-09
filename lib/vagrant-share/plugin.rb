begin
  require "vagrant"
rescue LoadError
  raise "vagrant-share requires vagrant"
end

if Vagrant::VERSION < "1.5.0"
  raise "Vagrant version must be at least 1.5.0."
end

module VagrantPlugins
  module Share
    class Plugin < Vagrant.plugin("2")
      name "vagrant-share"
      description <<-DESC
      Provides the share command.
      DESC

      command("connect") do
        require_relative "cap/tinycore"
        init!
        Command::Connect
      end

      command("share") do
        require_relative "cap/tinycore"
        init!
        Command::Share
      end

      guest_capability("tinycore", "connect_proxy") do
        require_relative "cap/tinycore"
        Cap::TinyCore
      end

      guest_capability("tinycore", "share_proxy") do
        require_relative "cap/tinycore"
        Cap::TinyCore
      end

      protected

      def self.init!
        I18n.load_path << File.expand_path("locales/en.yml", Share.source_root)
        I18n.reload!
      end
    end
  end
end
