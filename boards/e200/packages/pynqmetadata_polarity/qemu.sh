#! /bin/bash

set -x
set -e

. /etc/environment
for f in /etc/profile.d/*.sh; do source $f; done

python3 /home/xilinx/patch_polarity.py
rm -f /home/xilinx/patch_polarity.py
