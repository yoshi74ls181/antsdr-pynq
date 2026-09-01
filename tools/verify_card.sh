#!/bin/bash
# Identify the microSD in the reader and prove it actually stores writes.
# DESTRUCTIVE: writes test markers. Fine for a card about to be imaged.
DEV=${1:-/dev/sdc}
[ "$EUID" -eq 0 ] || { echo "Run with sudo: sudo $0 $DEV"; exit 1; }
[ -b "$DEV" ] || { echo "$DEV is not a block device"; exit 1; }

echo "=== identity ==="
SECT=$(cat /sys/block/$(basename $DEV)/size)
echo "sectors: $SECT   bytes: $((SECT*512))"
echo
echo "=== current MBR partition entries ==="
dd if=$DEV bs=1 skip=446 count=64 2>/dev/null | hexdump -C
echo "boot signature:"; dd if=$DEV bs=1 skip=510 count=2 2>/dev/null | hexdump -C
echo
echo "(The card that failed in the E200 showed type 0x06 FAT16 @ LBA 129,"
echo " 3904383 sectors -- i.e. bytes '06 18 d8 c8 81 00 00 00 7f 93 3b 00'.)"
echo
echo "=== write/read-back test at low, mid, high offsets ==="
PASS=0; FAIL=0
for s in 100 4000000 8000000 61000000; do
    if [ "$s" -ge "$SECT" ]; then echo "  sector $s beyond device, skipping"; continue; fi
    MARK="PLUTO-VERIFY-$s-$(date +%s%N)"
    echo "$MARK" | dd of=$DEV bs=512 seek=$s count=1 conv=notrunc 2>/dev/null
    sync
    blockdev --flushbufs $DEV 2>/dev/null
    echo 3 > /proc/sys/vm/drop_caches
    GOT=$(dd if=$DEV bs=512 skip=$s count=1 2>/dev/null | tr -d '\0' | head -1)
    if [ "$GOT" = "$MARK" ]; then
        echo "  sector $s: OK"; PASS=$((PASS+1))
    else
        echo "  sector $s: FAILED  (wrote '$MARK', read '$GOT')"; FAIL=$((FAIL+1))
    fi
done

echo
if [ "$FAIL" -eq 0 ] && [ "$PASS" -gt 0 ]; then
    echo "VERDICT: card stores writes correctly at all tested offsets ($PASS/$PASS). Safe to image."
else
    echo "VERDICT: card is BAD -- $FAIL of $((PASS+FAIL)) offsets did not persist."
    echo "Do not image it; it will silently fail like the last one."
fi
