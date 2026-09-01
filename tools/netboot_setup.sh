#!/bin/bash
# Set up TFTP + NFS-root netboot of the freshly built PYNQ image for AntSDR E200.
# The board keeps booting FSBL+U-Boot from QSPI; only the kernel and rootfs come
# from this host. Nothing on the board is written to, so QSPI stays intact.
set -e

REPO=/home/slab/pluto/antsdr-pynq
IF=enx806d970e0ccb
SRV_IP=192.168.1.100
BOARD_IP=192.168.1.10
NETMASK=255.255.255.0
TFTP_DIR=/srv/tftp
NFS_DIR=/srv/nfs/pynq-e200

[ "$EUID" -eq 0 ] || { echo "Run with sudo: sudo $0"; exit 1; }

echo "== 1/6 installing tftpd-hpa and nfs-kernel-server =="
DEBIAN_FRONTEND=noninteractive apt-get install -y tftpd-hpa nfs-kernel-server >/dev/null
echo "   done"

echo "== 2/6 static $SRV_IP on $IF =="
nmcli device set "$IF" managed no 2>/dev/null || true
ip addr flush dev "$IF"
ip addr add "$SRV_IP/24" dev "$IF"
ip link set "$IF" up
ip -brief addr show "$IF"

echo "== 3/6 TFTP root: $TFTP_DIR =="
mkdir -p "$TFTP_DIR"
install -m0644 "$REPO/PYNQ/sdbuild/output/boot/e200/image.ub" "$TFTP_DIR/image.ub"
cat > /etc/default/tftpd-hpa <<EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="$TFTP_DIR"
TFTP_ADDRESS="$SRV_IP:69"
TFTP_OPTIONS="--secure"
EOF
systemctl restart tftpd-hpa
ls -l "$TFTP_DIR/image.ub"

echo "== 4/6 extracting rootfs to $NFS_DIR (217k entries, a few minutes) =="
if [ -e "$NFS_DIR/etc/hostname" ]; then
    echo "   already extracted, skipping (delete $NFS_DIR to redo)"
else
    mkdir -p "$NFS_DIR"
    tar xpf "$REPO/PYNQ/sdbuild/build/e200.tar.gz" -C "$NFS_DIR" --numeric-owner
    echo "   extracted"
fi

echo "== 5/6 adapting rootfs for NFS root =="
# SD-card mounts would fail on a netboot; drop them.
if [ -f "$NFS_DIR/etc/fstab" ]; then
    sed -i -E 's|^([^#].*mmcblk.*)$|#\1|' "$NFS_DIR/etc/fstab"
    echo "   commented out mmcblk entries in /etc/fstab"
fi
# Copy in the overlay artifacts `make sd` would have placed on the card.
OLDIR="$NFS_DIR/home/xilinx/jupyter_notebooks/base"
mkdir -p "$OLDIR"
for f in base.bit base.hwh pl.dtbo; do
    install -m0644 "$REPO/boards/e200/base/$f" "$OLDIR/$f" && echo "   installed $f"
done
install -m0644 "$REPO/boards/e200/base/notebooks/pynq_iio.ipynb" "$OLDIR/" \
    && echo "   installed pynq_iio.ipynb"

echo "== 6/6 NFS export =="
grep -q "$NFS_DIR" /etc/exports 2>/dev/null || \
  echo "$NFS_DIR ${BOARD_IP}/32(rw,sync,no_subtree_check,no_root_squash,insecure)" >> /etc/exports
exportfs -ra
exportfs -v | grep -A1 "$NFS_DIR" || true

cat <<EOF

=========================================================================
Host side ready.  Server $SRV_IP on $IF, board expected at $BOARD_IP.

Now attach to the serial console and interrupt U-Boot (hit a key during
the countdown):

    sudo picocom -b 115200 /dev/ttyUSB0      # or: screen /dev/ttyUSB0 115200

First confirm this U-Boot has networking:

    help tftpboot
    printenv

Then boot our kernel with our rootfs over NFS:

    setenv ipaddr $BOARD_IP
    setenv serverip $SRV_IP
    setenv bootargs 'console=ttyPS0,115200 root=/dev/nfs rw nfsroot=$SRV_IP:$NFS_DIR,nfsvers=3,tcp ip=$BOARD_IP:$SRV_IP::$NETMASK:pynq:eth0:off earlyprintk'
    ping $SRV_IP
    tftpboot 0x2000000 image.ub
    bootm 0x2000000

Login is xilinx/xilinx (or root/xilinx). Then verify the build:

    uname -a                       # expect 5.15.19-xilinx-v2022.1
    python3 -c "from pynq import Overlay; o=Overlay('/home/xilinx/jupyter_notebooks/base/base.bit'); print('bitstream loaded')"
    iio_info -u local:             # AD9361 should enumerate

To undo all of this:
    sudo exportfs -u $BOARD_IP:$NFS_DIR ; sudo rm -rf $NFS_DIR $TFTP_DIR/image.ub
    sudo nmcli device set $IF managed yes
=========================================================================
EOF
