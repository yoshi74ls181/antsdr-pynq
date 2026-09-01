#!/bin/bash
# Write the PYNQ image to the microSD in the reader, verify it, then install
# the boards/e200 overlay files (the `make sd` step).
set -o pipefail

REPO=/home/slab/pluto/antsdr-pynq
IMG=$REPO/PYNQ/sdbuild/output/e200-3.0.1.img
DEV=${1:-/dev/sdc}
MNT=/mnt/sdcard
IMG_BYTES=7867715584

[ "$EUID" -eq 0 ] || { echo "Run with sudo: sudo $0 $DEV"; exit 1; }
[ -f "$IMG" ] || { echo "image not found: $IMG"; exit 1; }
[ -b "$DEV" ] || { echo "$DEV is not a block device"; exit 1; }

BASE=$(basename "$DEV")
# ---- safety guards: never touch a fixed/system disk ----
[[ "$DEV" =~ [0-9]$ ]] && { echo "REFUSING: $DEV looks like a partition, want the whole disk"; exit 1; }
[ "$(cat /sys/block/$BASE/removable 2>/dev/null)" = "1" ] || {
    echo "REFUSING: $BASE is not marked removable"; exit 1; }
SZ=$(( $(cat /sys/block/$BASE/size) * 512 ))
[ "$SZ" -gt 8000000000 ] && [ "$SZ" -lt 128000000000 ] || {
    echo "REFUSING: $BASE size $SZ outside sane range for an SD card"; exit 1; }
if lsblk -no MOUNTPOINT "$DEV" | grep -qE '^/$|^/boot|^/home$'; then
    echo "REFUSING: $DEV has system mountpoints"; exit 1
fi
echo "target: $DEV  size: $SZ bytes  removable: yes"
echo "model: $(cat /sys/block/$BASE/device/model 2>/dev/null)"
echo

echo "== unmounting any partitions on $DEV =="
for p in $(lsblk -lno NAME "$DEV" | tail -n +2); do
    umount "/dev/$p" 2>/dev/null && echo "  unmounted /dev/$p"
done
umount -R $MNT 2>/dev/null

echo "== writing $IMG_BYTES bytes (this takes a few minutes) =="
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
echo "dd exit: $?"
sync
blockdev --flushbufs "$DEV" 2>/dev/null
echo 3 > /proc/sys/vm/drop_caches

echo
echo "== verifying read-back (md5 over the image's byte range) =="
CARD_MD5=$(dd if="$DEV" bs=4096 count=$((IMG_BYTES/4096)) 2>/dev/null | md5sum | awk '{print $1}')
IMG_MD5=$(awk '{print $1}' /tmp/claude-1000/-home-slab-pluto/5042d40f-2f4a-432d-9352-b6a84b1d5b33/scratchpad/image.md5 2>/dev/null)
[ -z "$IMG_MD5" ] && IMG_MD5=$(md5sum "$IMG" | awk '{print $1}')
echo "image md5: $IMG_MD5"
echo "card  md5: $CARD_MD5"
if [ "$CARD_MD5" != "$IMG_MD5" ]; then
    echo "VERIFY FAILED -- card content does not match the image. Stopping."
    exit 1
fi
echo "VERIFY OK"

echo
echo "== re-reading partition table =="
partprobe "$DEV" 2>/dev/null || blockdev --rereadpt "$DEV" 2>/dev/null
sleep 2
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"

echo
echo "== mounting and installing overlay files (the 'make sd' step) =="
mkdir -p $MNT/PYNQ $MNT/root
mount "${DEV}1" $MNT/PYNQ || { echo "could not mount ${DEV}1"; exit 1; }
mount "${DEV}2" $MNT/root || { echo "could not mount ${DEV}2"; exit 1; }
make -C "$REPO" sd SD=$MNT
echo
echo "== boot partition contents =="
ls -la $MNT/PYNQ
echo "== overlay dir on root fs =="
ls -la $MNT/root/home/xilinx/jupyter_notebooks/base

sync
umount $MNT/PYNQ $MNT/root
rmdir $MNT/PYNQ $MNT/root $MNT 2>/dev/null
echo
echo "=== DONE. Card is ready; safe to remove and put in the E200. ==="
