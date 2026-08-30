#! /bin/bash
# Stage the patcher into the image so qemu.sh can run it inside the chroot.
set -x
set -e

target=$1
sudo cp -f $(dirname ${BASH_SOURCE[0]})/patch_polarity.py $target/home/xilinx/
