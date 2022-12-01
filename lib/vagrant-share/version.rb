# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module VagrantPlugins
  module Share
    VERSION = Gem::Version.new(File.read(File.expand_path("../../../version.txt", __FILE__)))
  end
end
