# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

module VagrantPlugins
  module Share
    module Command
      autoload :Connect, "vagrant-share/command/connect"
      autoload :Ngrok, "vagrant-share/command/ngrok"
      autoload :Share, "vagrant-share/command/share"
    end
  end
end
