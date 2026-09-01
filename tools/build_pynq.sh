#!/bin/bash
# Full `make pynq` with the meta-pynq layer fix in place.
# Needs root: PYNQ sdbuild stages the ARM rootfs in a chroot.
set -o pipefail
export PATH=/opt/qemu/bin:/opt/crosstool-ng/bin:$PATH
source /tools/Xilinx/Vitis/2022.1/settings64.sh
source /tools/Xilinx/PetaLinux/2022.1/settings.sh
unset LD_LIBRARY_PATH          # bitbake refuses to run otherwise

cd /home/slab/pluto/antsdr-pynq
LOG=/home/slab/pluto/antsdr-pynq/pynq_build.log
echo "Logging to $LOG"
make pynq 2>&1 | tee "$LOG"
echo "MAKE_PYNQ_EXIT=${PIPESTATUS[0]}" | tee -a "$LOG"
