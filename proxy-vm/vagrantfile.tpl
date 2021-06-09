Vagrant.configure("2") do |config|
  config.ssh.shell = "ash"
  config.ssh.username = "tc"
  config.ssh.password = "vagrant"

  # Disable synced folders because guest additions aren't available
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Attach the ISO so that it can boot
  config.vm.provider "virtualbox" do |v|
    v.customize "pre-boot", [
      "storageattach", :id,
      "--storagectl", "IDE Controller",
      "--port", "0",
      "--device", "1",
      "--type", "dvddrive",
      "--medium", File.expand_path("../proxycore.iso", __FILE__),
    ]

    # Without setting this, network access from the VM is super slow for
    # some reason.
    v.auto_nat_dns_proxy = false
    v.check_guest_additions = false
    v.memory = 128
  end

  ["vmware_fusion", "vmware_workstation"].each do |vmware|
    config.vm.provider vmware do |v|
      v.vmx["bios.bootOrder"]    = "CDROM,hdd"
      v.vmx["ide1:0.present"]    = "TRUE"
      v.vmx["ide1:0.fileName"]   = File.expand_path("../proxycore.iso", __FILE__)
      v.vmx["ide1:0.deviceType"] = "cdrom-image"
    end
  end
end
