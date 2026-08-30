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
# Let the xilinx user use IIO buffers without root.
#
# Two separate things are needed. udev creates /dev/iio:deviceN root-only, and
# that is what libiio mmaps -- but its local backend also writes sysfs
# attributes (buffer/enable, buffer/length, scan_elements/*_en) which udev does
# not chmod for us. Without the second rule, iio_readdev and pyadi-iio fail with
# "Unable to allocate buffer: Permission denied (13)" even as a member of the
# group. Jupyter runs as xilinx, so pynq_iio.ipynb needs both.
groupadd -f iio
if id xilinx >/dev/null 2>&1; then
    usermod -aG iio xilinx
fi
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/90-iio.rules <<'RULES'
# Only buffer/ and scan_elements/ are touched, not the whole device tree.
SUBSYSTEM=="iio", KERNEL=="iio:device*", GROUP="iio", MODE="0660"
SUBSYSTEM=="iio", KERNEL=="iio:device*", ACTION=="add|change", RUN+="/bin/sh -c 'chgrp -R iio /sys%p/buffer /sys%p/scan_elements 2>/dev/null; chmod -R g+w /sys%p/buffer /sys%p/scan_elements 2>/dev/null'"
RULES
