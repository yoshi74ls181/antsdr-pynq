#!/bin/bash
# Probe the AntSDR E200 (Pluto firmware from QSPI) over the USB-Ethernet adapter.
# Only touches enx806d970e0ccb; leaves ens33 (the VM's uplink) alone.
IF=enx806d970e0ccb

[ "$EUID" -eq 0 ] || { echo "Run with sudo: sudo $0"; exit 1; }

echo "== taking $IF away from NetworkManager (stops its DHCP retry loop) =="
nmcli device set "$IF" managed no 2>/dev/null
ip addr flush dev "$IF"
ip link set "$IF" up
sleep 1

FOUND=""
for probe in "192.168.1.100/24:192.168.1.10" \
             "192.168.2.100/24:192.168.2.1" \
             "192.168.3.100/24:192.168.3.1"; do
    myip=${probe%%:*}; target=${probe##*:}; subnet=${myip%.*}
    echo; echo "== $myip -> looking for $target =="
    ip addr flush dev "$IF"; ip addr add "$myip" dev "$IF"; sleep 1

    if ping -c2 -W1 -I "$IF" "$target" >/dev/null 2>&1; then
        echo "*** $target responds ***"; FOUND=$target; break
    fi
    echo "no reply; sweeping $subnet.0/24 ..."
    for h in $(seq 1 254); do
        ( ping -c1 -W1 "$subnet.$h" >/dev/null 2>&1 && echo "  *** host up: $subnet.$h ***" ) &
    done
    wait
    hit=$(ip neigh show dev "$IF" | grep -v -E 'FAILED|INCOMPLETE' | awk '{print $1}' | head -1)
    [ -n "$hit" ] && { echo "*** ARP found $hit ***"; FOUND=$hit; break; }
done

if [ -z "$FOUND" ]; then
    echo; echo "No host found on any candidate subnet."
    echo "ARP table:"; ip neigh show dev "$IF"
    echo "Hand back with: sudo nmcli device set $IF managed yes"
    exit 1
fi

echo; echo "===== $FOUND found: checking services ====="
for p in 22 80 30431; do
    printf '  tcp/%-6s ' "$p"
    timeout 3 bash -c "echo > /dev/tcp/$FOUND/$p" 2>/dev/null && echo OPEN || echo closed
done

echo; echo "===== iiod context (via raw socket, no libiio needed) ====="
python3 - "$FOUND" <<'PY'
import socket, sys, re
host = sys.argv[1]
try:
    s = socket.create_connection((host, 30431), timeout=5)
except Exception as e:
    print("  could not connect to iiod:", e); sys.exit(0)
s.settimeout(5)
def cmd(c):
    s.sendall((c + "\r\n").encode())
    buf = b""
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            buf += d
            if len(buf) > 400000: break
    except socket.timeout:
        pass
    return buf.decode("utf-8", "replace")

print("  VERSION:", cmd("VERSION").strip()[:120])
xml = cmd("PRINT")
devs = re.findall(r'<device id="([^"]+)"(?:\s+name="([^"]+)")?', xml)
if devs:
    print("  devices:")
    for i, n in devs:
        print(f"    {i:<12} {n or ''}")
else:
    print("  raw head:", xml[:400])
for key in ("fw_version", "model", "hw_model", "hw_serial"):
    m = re.search(r'name="%s".*?value="([^"]*)"' % key, xml)
    if m: print(f"  {key}: {m.group(1)}")
PY

echo; echo "== done. Hand $IF back with: sudo nmcli device set $IF managed yes =="
