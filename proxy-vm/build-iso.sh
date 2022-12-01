#!/bin/bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#
# This script will create the proxycore.iso file. It will place the
# file in the pwd when executing this script.
#
set -e
set -x

GO_VERSION="1.16.5"
TINYCORE_VERSION="12"
SHADOWSOCKS2_GO_VERSION="0.1.5"

# Determine the directory where we're executing from.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Work in the temporary directory
cd /tmp

#--------------------------------------------------------------------
# Prepare system
#--------------------------------------------------------------------
# Update packages and install some packages we need
export DEBIAN_FRONTEND="noninteractive"

apt-get -y update
apt-get -y install advancecomp build-essential curl genisoimage \
    squashfs-tools unzip git

# Clear out any old stuff
rm -rf /tmp/boot /tmp/extract /tmp/libevent* /tmp/red* /tmp/*.iso

# Install go so we can build shadowsocks
curl -sfL -o go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
tar -C /usr/local -xzf go.tar.gz

export PATH="${PATH}:/usr/local/go/bin"

#--------------------------------------------------------------------
# TinyCore
#--------------------------------------------------------------------
# Download the TinyCore
curl -fsL http://tinycorelinux.net/${TINYCORE_VERSION}.x/x86/release/Core-current.iso > core.iso

# Mount the core
mkdir -p /mnt/tmp
mount core.iso /mnt/tmp -o loop,ro
cp -a /mnt/tmp/boot /tmp
mv /tmp/boot/core.gz /tmp/core.gz
umount /mnt/tmp

# Extract the core filesystem
CORE_EXTRACT="/tmp/extract"
mkdir ${CORE_EXTRACT}
pushd ${CORE_EXTRACT}
zcat /tmp/core.gz | cpio -i -H newc -d
popd

# Install some TinyCore extensions
TCL_REPO_BASE="http://tinycorelinux.net/${TINYCORE_VERSION}.x/x86"
TCZ_DEPS="db iproute2 iptables libedit ncursesw ipv6-netfilter-5.10.3-tinycore openssh openssl-1.1.1 socat readline"

for dep in $TCZ_DEPS; do
    curl -fsL -o /tmp/${dep}.tcz ${TCL_REPO_BASE}/tcz/${dep}.tcz
    unsquashfs -f -d ${CORE_EXTRACT} /tmp/${dep}.tcz
    rm -f /tmp/${dep}.tcz
done

#--------------------------------------------------------------------
# Software
#--------------------------------------------------------------------
# shadowsocks-go server
rm -rf go-shadowsocks2
git clone https://github.com/shadowsocks/go-shadowsocks2
pushd go-shadowsocks2
git checkout "v${SHADOWSOCKS2_GO_VERSION}"
GOARCH=386 GOOS=linux go build -ldflags '-w -s' -o "shadowsocks2"
cp shadowsocks2 ${CORE_EXTRACT}/usr/local/bin/ss-server
cp shadowsocks2 ${CORE_EXTRACT}/usr/local/bin/ss-client
popd

# redsocks
rm -rf redsocks
git clone https://github.com/darkk/redsocks
pushd redsocks
apt-get install -y gcc-multilib libevent-dev:i386
CFLAGS="-m32 -static" make ENABLE_STATIC=1
mv redsocks ${CORE_EXTRACT}/usr/local/bin/redsocks
popd

# iptables configuration
echo "/usr/local/sbin/basic-firewall noprompt" >> ${CORE_EXTRACT}/opt/bootsync.sh
echo "/usr/local/sbin/iptables -A INPUT -p tcp --dport 22 -j ACCEPT" >> ${CORE_EXTRACT}/opt/bootsync.sh

# Setup SSH
cp ${CORE_EXTRACT}/usr/local/etc/ssh/sshd_config.orig \
    ${CORE_EXTRACT}/usr/local/etc/ssh/sshd_config
echo "/usr/local/etc/init.d/openssh start" >> ${CORE_EXTRACT}/opt/bootlocal.sh
mkdir -p ${CORE_EXTRACT}/var/lib/sshd

# Setup the password for "tc" to be "vagrant"
cat <<EOF > ${CORE_EXTRACT}/etc/shadow
root:*:13525:0:99999:7:::
lp:*:13510:0:99999:7:::
nobody:*:13509:0:99999:7:::
tc:\$1\$salt\$pK8ervpuWiljC8bbtOaau1:13646:0:99999:7:::
EOF

#--------------------------------------------------------------------
# Package
#--------------------------------------------------------------------
# Process the new kernel modules we added above and run ldconfig
# so that the libraries we may have added are usable
chroot ${CORE_EXTRACT} depmod -a 5.10.3-tinycore
ldconfig -r ${CORE_EXTRACT}

# Make the core.gz image...
pushd ${CORE_EXTRACT}
find | cpio -o -H newc | gzip -2 > /tmp/core.gz
popd
pushd /tmp
advdef -z4 core.gz
popd

# Setup our configuration for booting
cat <<EOF >/tmp/boot/isolinux/isolinux.cfg
default microcore
label microcore
        kernel /boot/vmlinuz
        initrd /boot/core.gz
        append loglevel=3
implicit 0
prompt 0
timeout 0
EOF

# Make the ISO
pushd /tmp
mv core.gz boot
mkdir newiso
mv boot newiso
mkisofs -l -J -R -V TC-custom -no-emul-boot -boot-load-size 4 \
 -boot-info-table -b boot/isolinux/isolinux.bin \
 -c boot/isolinux/boot.cat -o ${DIR}/proxycore.iso newiso
rm -rf newiso
popd
