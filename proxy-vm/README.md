# Proxy VM

This folder contains the scripts necessary to create the "proxy VM" image.
This is the lightweight virtual machine used to create the static IP for
`vagrant connect`.

## Technical Details

The proxy VM is based on [Tiny Core Linux](http://tinycorelinux.net/).
We actually remaster a custom ISO of TCL containing only what we need:

* iptables
* [redsocks](https://github.com/darkk/redsocks)
* OpenSSH

The remastered ISO is also configured to boot as fast as possible (no
boot menu, for example). It can boot in usually 2 or 3 seconds and the
built image takes up 13 MB.

With this software installed, Vagrant can take over the VM once it is
launched to configure it to proxy things.

## Build Process

To build the Vagrant boxes that `vagrant connect` uses, you have to
follow the following steps:

1. `vagrant up` to create a build environment for the remastered ISO.

2. `vagrant ssh -c "cd /vagrant && sudo ./build-iso.sh"` - This will
  build the ISO and put it in the current directory as "proxycore.iso".

3. `vagrant destroy --force`. We don't need the VM environment anymore.

4. `packer build template.json` - This will build both the VirtulBox and
  VMware images with proxycore.
