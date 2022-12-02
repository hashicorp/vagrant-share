# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

require "spec_helper"

describe VagrantPlugins::Share::Command::Connect do
  include_context "vagrant-unit"

  let(:env) do
    # We have to create a Vagrantfile so there is a root path
    env = isolated_environment
    env.vagrantfile("")
    env.create_vagrant_env
  end

  let(:machine) { env.machine(env.machine_names[0], :dummy) }

  let(:argv)     { [] }

  subject { described_class.new(argv, env) }

  def exit_code(code)
    Vagrant::Util::Subprocess::Result.new(code, "", "")
  end

  # Returns a lambda that can be used to stub with execute_proxy
  # and invoke certain behavior.
  def proxy_proc(**opts, &procblock)
    opts[:port] ||= "1080" if !opts[:ssh_port]

    return lambda do |*args, &block|
      @proxy_started = true
      procblock.call(*args, &block) if procblock
      block.call("listen-port", [opts[:port].to_s]) if opts[:port]
      block.call("listen-port-ssh", [opts[:ssh_port].to_s]) if opts[:ssh_port]
      block.call("started")
      Vagrant::Util::Subprocess::Result.new(0, "", "")
    end
  end

  before do
    @proxy_started = false
  end

  context "with no arguments" do
    it "shows help" do
      expect { subject.execute }.
        to raise_error(Vagrant::Errors::CLIInvalidUsage)
    end
  end

  context "with 2+ arguments" do
    let(:argv) { ["one", "two"] }

    it "shows help" do
      expect { subject.execute }.
        to raise_error(Vagrant::Errors::CLIInvalidUsage)
    end
  end
end
