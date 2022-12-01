# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

require "spec_helper"

describe VagrantPlugins::Share::Command::Ngrok::Share do
  include_context "vagrant-unit"

  subject { Class.new { extend VagrantPlugins::Share::Command::Ngrok::Share } }

  let(:logger) { double("logger") }

  let(:ngrok_process) { double("ngrok_process") }

  before do
    allow(logger).to receive(:debug)
    subject.instance_variable_set(:@logger, logger)

    allow(ngrok_process).to receive(:execute)
  end

  describe "#start_ngrok_proxy" do
    before do
      allow(Thread).to receive(:new).and_yield
      allow(File).to receive(:exists?).with("#{ENV['HOME']}/.ngrok2/ngrok.yml").
        and_return(true)
    end

    it "includes config from user's home directory" do
      expect(Vagrant::Util::Subprocess).to receive(:new).
        with("ngrok", "start", "--config", "#{ENV['HOME']}/.ngrok2/ngrok.yml", any_args).
        and_return(ngrok_process)
      subject.start_ngrok_proxy(nil, nil, nil, {})
    end

    it "handles a base config within a directory containing a space" do
      base_config = "/Volumes/All My Users/user/.ngrok2/ngrok.yml"

      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with("~/.ngrok2/ngrok.yml").
        and_return(base_config)
      allow(File).to receive(:exists?).with(base_config).and_return(true)

      expect(Vagrant::Util::Subprocess).to receive(:new).
        with("ngrok", "start", "--config", base_config, any_args).
        and_return(ngrok_process)
      subject.start_ngrok_proxy(nil, nil, nil, {})
    end
  end
end
