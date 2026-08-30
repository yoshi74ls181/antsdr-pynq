#! /bin/bash

set -x
set -e

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

# Install libini
cd /root
wget https://github.com/pcercuei/libini/archive/refs/heads/master.zip
unzip -d libini master.zip
cd libini/libini-master
mkdir build
cd build
cmake ../
make
make install

# Install IIO and dependencies
cd /root
wget http://launchpadlibrarian.net/571174055/libiio-utils_0.23-2_armhf.deb
apt update
apt download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances libiio-dev | grep "^\w" | sort -u)
apt download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances iiod | grep "^\w" | sort -u)
dpkg -i *.deb
wget https://github.com/analogdevicesinc/libad9361-iio/archive/refs/tags/v0.3.zip
unzip -d libad9361-iio v0.3.zip
cd libad9361-iio/libad9361-iio-0.3
mkdir build
cd build
cmake ../
make
make install

# Install libiio Python bindings
pip3 install pylibiio pyadi-iio
# Let the xilinx user drive the AD9361 without root. Jupyter runs as xilinx.
groupadd -f iio
if id xilinx >/dev/null 2>&1; then
    usermod -aG iio xilinx
fi
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/90-iio.rules <<'RULES'
# Three things are needed, and each was found the hard way:
#   1. the /dev/iio:deviceN character device, which libiio mmaps for buffers;
#   2. buffer/ and scan_elements/ sysfs attributes, which libiio's local
#      backend writes to arm a capture -- udev does not chmod these for us.
#      Without them iio_readdev and pyadi-iio fail with
#      "Unable to allocate buffer: Permission denied (13)" even inside the group;
#   3. the device's own attributes (ensm_mode, *_hardwaregain, *_LO_frequency,
#      sampling_frequency). Without these the radio cannot be *configured* at
#      all -- pyadi-iio raises PermissionError -- so a notebook can capture but
#      not tune, which is a confusing place to land.
#
# Scoped to depth-1 attribute files plus those two subdirectories, rather than a
# blanket recursive chmod that would also loosen power/ and uevent.
#
# ACTION=="add|change" matters because the AD9361 nodes do not exist at boot;
# they appear when boot.py applies pl.dtbo.
SUBSYSTEM=="iio", KERNEL=="iio:device*", GROUP="iio", MODE="0660"
SUBSYSTEM=="iio", KERNEL=="iio:device*", ACTION=="add|change", RUN+="/bin/sh -c 'chgrp -R iio /sys%p 2>/dev/null; find /sys%p -maxdepth 1 -type f -exec chmod g+w {} + 2>/dev/null; chmod -R g+w /sys%p/buffer /sys%p/scan_elements 2>/dev/null'"
RULES
