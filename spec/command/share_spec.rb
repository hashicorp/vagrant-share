# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

require "spec_helper"

describe VagrantPlugins::Share::Command::Share do
  include_context "vagrant-unit"

  let(:iso_env) do
    # We have to create a Vagrantfile so there is a root path
    env = isolated_environment
    env.vagrantfile("")
    env.create_vagrant_env
  end

  let(:machine) { iso_env.machine(iso_env.machine_names[0], :dummy) }

  let(:argv)     { ["--driver", "classic"] }

  subject { described_class.new(argv, iso_env) }

  def exit_code(code)
    Vagrant::Util::Subprocess::Result.new(code, "", "")
  end

  context "with 2+ arguments" do
    let(:argv) { ["one", "two"] }

    it "shows help" do
      expect { subject.execute }.
        to raise_error(Vagrant::Errors::CLIInvalidUsage)
    end
  end
end
