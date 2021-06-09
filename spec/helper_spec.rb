require "spec_helper"

require "ipaddr"
require "tempfile"
require "tmpdir"
require "webrick"

require "vagrant-share"

describe VagrantPlugins::Share::Helper do
  include_context "vagrant-unit"

  subject { described_class }

  def with_web_server(port)
    tf = Tempfile.new("vagrant-share")
    tf.close

    server = WEBrick::HTTPServer.new(
      AccessLog: [],
      Logger: WEBrick::Log.new(tf.path, 7),
      Port: port,
      DocumentRoot: Dir.mktmpdir,)
    thr = Thread.new { server.start }
    yield
  ensure
    server.shutdown if server
    thr.join if thr
  end

  describe "#acquire_ip" do
    let(:env)     { iso_env.create_vagrant_env }
    let(:iso_env) { isolated_environment }

    it "gives a random IP in the 172.16.0.0/12 subnet" do
      range = IPAddr.new("172.16.0.0/12")

      ip, f = described_class.acquire_ip(env, nil)
      expect(range).to include(ip)
      expect(f).to be_kind_of(File)
    end

    it "returns nil if an IP is taken" do
      ip, f = described_class.acquire_ip(env, "192.168.1.5")
      expect(ip).to eq("192.168.1.5")
      expect(File.file?(f.path)).to be_truthy

      results = described_class.acquire_ip(env, "192.168.1.5")
      expect(results).to be_nil
    end

    it "doesn't give the same random IP" do
      ip, _ = described_class.acquire_ip(env, nil)
      ip2, _ = described_class.acquire_ip(env, nil)

      expect(ip).to_not be_nil
      expect(ip2).to_not be_nil
      expect(ip).to_not eq(ip2)
    end
  end

  describe "#detect_ports" do
    # Can't test port 80 because requires root privs...
    [3000, 4567, 8000, 8080].each do |port|
      it "detects port #{port}" do
        with_web_server(port) do
          sleep 0.1
          result = described_class.detect_ports("127.0.0.1")
          expect(result).to be_kind_of(Array)
          expect(result[0]).to eq(port)
          expect(result[1]).to be_nil
        end
      end
    end
  end

  describe "#detect_forwarded_ports" do
    it "detects a forwarded port that has an HTTP server" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      with_web_server(4567) do
        result = described_class.detect_forwarded_ports(machine)
        expect(result).to be_kind_of(Array)
        expect(result[0]).to eq(4567)
        expect(result[1]).to be_nil
      end
    end

    it "detects a forwarded port by target" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      with_web_server(4567) do
        result = described_class.detect_forwarded_ports(machine, target: "127.0.0.1")
        expect(result).to be_kind_of(Array)
        expect(result[0]).to eq(4567)
        expect(result[1]).to be_nil
      end
    end

    it "detects a forwarded port by guest port" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      with_web_server(8080) do
        result = described_class.detect_forwarded_ports(machine, guest_port: true)
        expect(result).to be_kind_of(Array)
        expect(result[0]).to eq(8080)
        expect(result[1]).to be_nil
      end
    end
  end

  describe "#forwarded_ports" do
    it "returns all the forwarded ports" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      expect(subject.forwarded_ports(machine)).to eq({
        3000 => 8080,
        4567 => 8080,
        2222 => 22,
      })
    end

    it "uses the forwarded_ports capability if available" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)
      provider = double("provider")
      allow(machine).to receive(:provider).and_return(provider)
      expect(provider).to receive(:capability?).
        with(:forwarded_ports).and_return(true)
      expect(provider).to receive(:capability).
        with(:forwarded_ports).and_return({ 123 => 456 })

      expect(subject.forwarded_ports(machine)).to eq({
        123 => 456,
      })
    end

    it "uses the private capability if it is available" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)
      provider = double("provider")
      allow(machine).to receive(:provider).and_return(provider)
      expect(provider).to receive(:capability?).
        with(:forwarded_ports).and_return(false)
      expect(provider).to receive(:capability?).
        with(:vagrant_share__forwarded_ports).and_return(true)
      expect(provider).to receive(:capability).
        with(:vagrant_share__forwarded_ports).and_return({ 123 => 456 })

      expect(subject.forwarded_ports(machine)).to eq({
        123 => 456,
      })
    end
  end

  describe "#guest_forwarded_port" do
    it "returns the proper port" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      expect(subject.guest_forwarded_port(machine, 4567)).to eq(8080)
    end

    it "returns nil if the port is not found" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      expect(subject.guest_forwarded_port(machine, 1234)).to be_nil
    end
  end

  describe "#generate_keypair" do
    it "generates a usable keypair with no password" do
      # I don't know how to validate the final return value yet...
      pubkey, privkey, _ = described_class.generate_keypair(nil)

      pubkey  = OpenSSL::PKey::RSA.new(pubkey)
      privkey = OpenSSL::PKey::RSA.new(privkey)

      encrypted = pubkey.public_encrypt("foo")
      decrypted = privkey.private_decrypt(encrypted)

      expect(decrypted).to eq("foo")
    end

    it "generates a keypair that requires a password" do
      pubkey, privkey, _ = described_class.generate_keypair("password")

      pubkey  = OpenSSL::PKey::RSA.new(pubkey)
      privkey = OpenSSL::PKey::RSA.new(privkey, "password")

      encrypted = pubkey.public_encrypt("foo")
      decrypted = privkey.private_decrypt(encrypted)

      expect(decrypted).to eq("foo")
    end
  end

  describe "#host_forwarded_port" do
    it "returns the proper port" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
          config.vm.network "forwarded_port", guest: 8080, host: 4567
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      expect(subject.host_forwarded_port(machine, 8080)).to eq(4567)
    end

    it "returns nil if the port is not found" do
      iso_env = isolated_environment.tap do |iso|
        iso.vagrantfile(<<-RAW)
        Vagrant.configure("2") do |config|
          config.vm.network "forwarded_port", guest: 8080, host: 3000
        end
        RAW
      end

      env = iso_env.create_vagrant_env
      machine = env.machine(env.machine_names[0], :dummy)

      expect(subject.host_forwarded_port(machine, 1234)).to be_nil
    end
  end
end
