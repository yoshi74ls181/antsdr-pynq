#!/bin/bash
# Switch the E200 between a low-power idle state and a radio-active state, and
# report die temperatures.
#
#   e200-power.sh idle     radio off  (AD9361 ALERT, TX muted)
#   e200-power.sh active   radio on   (AD9361 FDD)
#   e200-power.sh status   temperatures and current state
#   e200-power.sh idle --slow-net   also drop Ethernet to 100 Mbps
#
# Measured on hardware going idle -> active is reversible with no re-init:
#   AD9361 die  64.5 -> 38.2 C   (-26.3)
#   Zynq die    71.9 -> 65.8 C   (-6.1)
PHY=/sys/bus/iio/devices/iio:device1
XADC=/sys/bus/iio/devices/iio:device0

need_root() { [ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }; }

temps() {
    local r o s
    r=$(cat $XADC/in_temp0_raw); o=$(cat $XADC/in_temp0_offset); s=$(cat $XADC/in_temp0_scale)
    python3 -c "print(f'  zynq die   : {(($r)+($o))*($s)/1000:.1f} C')"
    python3 -c "print(f'  ad9361 die : {$(cat $PHY/in_temp0_input)/1000:.1f} C')"
}

status() {
    echo "  ensm_mode  : $(cat $PHY/ensm_mode)"
    echo "  TX atten   : ch0 $(cat $PHY/out_voltage0_hardwaregain) / ch1 $(cat $PHY/out_voltage1_hardwaregain)"
    echo "  sample rate: $(( $(cat $PHY/in_voltage_sampling_frequency) / 1000000 )) MSPS"
    echo "  eth0 speed : $(cat /sys/class/net/eth0/speed 2>/dev/null || echo '?') Mbps"
    temps
}

case "${1:-status}" in
  idle)
    need_root
    # ALERT keeps the PLLs locked but powers down the TX/RX signal paths, so
    # returning to FDD needs no re-tune. SLEEP saves a little more but takes
    # longer to come back and drops more state.
    echo alert > $PHY/ensm_mode
    # -89.75 dB is the AD9361's maximum attenuation, i.e. minimum output.
    echo -89.750000 > $PHY/out_voltage0_hardwaregain
    echo -89.750000 > $PHY/out_voltage1_hardwaregain
    if [ "${2:-}" = "--slow-net" ]; then
        # Gigabit PHYs burn noticeably more than 100 Mbps. Plenty for Jupyter,
        # but it briefly drops the link -- do not do this over the tunnel you
        # are currently using unless you can get back in over serial.
        ethtool -s eth0 speed 100 duplex full autoneg on 2>/dev/null \
            && echo "  eth0 renegotiating at 100 Mbps" \
            || echo "  (ethtool unavailable; skipped)"
    fi
    echo "idle:"; status
    ;;
  active)
    need_root
    echo fdd > $PHY/ensm_mode
    echo -20.000000 > $PHY/out_voltage0_hardwaregain
    echo -10.000000 > $PHY/out_voltage1_hardwaregain
    echo "active:"; status
    ;;
  status) status ;;
  *) echo "usage: $0 {idle|active|status} [--slow-net]"; exit 2 ;;
esac
