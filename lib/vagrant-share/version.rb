# Copyright IBM Corp. 2021, 2026
# SPDX-License-Identifier: MPL-2.0

module VagrantPlugins
  module Share
    VERSION = Gem::Version.new(File.read(File.expand_path("../../../version.txt", __FILE__)))
  end
end
