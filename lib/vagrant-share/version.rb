module VagrantPlugins
  module Share
    VERSION = Gem::Version.new(File.read(File.expand_path("../../../version.txt", __FILE__)))
  end
end
