require "pathname"
require "vagrant-share/plugin"

module VagrantPlugins
  module Share
    autoload :Command, "vagrant-share/command"
    autoload :Errors, "vagrant-share/errors"
    autoload :Helper, "vagrant-share/helper"
    autoload :VERSION, "vagrant-share/version"

    # This returns the path to the source of this plugin.
    #
    # @return [Pathname]
    def self.source_root
      @source_root ||= Pathname.new(File.expand_path("../../", __FILE__))
    end
  end
end
