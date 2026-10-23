#!/usr/bin/env bash
# T-04 - "The whole HQ is crawling, the switch CPU is pegged"  (P1)
#
# Fault: STP is disabled on both switches and the inter-switch ports are bounced
# so that all four of them come back forwarding. The two parallel uplinks are a
# real loop again, and an Ethernet loop with no STP is a broadcast storm: every
# flooded frame - an ARP request is enough - circulates between the two bridges
# at line rate for as long as the loop stays closed.
#
# Two traps live in this ticket:
#
#   1. Turning STP off does **not** un-block a port that STP already blocked. The
#      port keeps the state it was given, the loop stays open-but-idle, and a
#      technician who "disabled STP to fix a loop problem" sees nothing happen at
#      all. What closes the loop is a down/up cycle on the ports - with STP gone
#      they skip listening and learning and go straight to forwarding.
#
#   2. The lab is quiet, so a storm needs something to circulate. One broadcast
#      is enough to start it, which is what `ping -b` does here: on a real
#      network the ARP and DHCP traffic of a few hundred users does it for you.
#
# Safety: this is the one fault that can hurt the host, so the inject step arms a
# 30-second auto-restore. The fault stops being interesting after ten seconds.
. "$(dirname "$0")/lib.sh"
need_lab

PORTS="sw1:eth4 sw1:eth5 sw2:eth1 sw2:eth2"   # the four inter-switch port ends

blocking_ports() {
    { x sw1 bridge -d link show; x sw2 bridge -d link show; } | grep -c 'state blocking'
}

restore() {
    # Re-enabling STP re-runs the election, which re-blocks one of the uplinks by
    # itself. Nothing else has to be undone - the port bounce left no state
    # behind, which is exactly why it is the right way to close the loop.
    x sw1 ip link set br0 type bridge stp_state 1
    x sw2 ip link set br0 type bridge stp_state 1
}

case "${1:-}" in
inject)
    step "stp_state 0 on sw1 and sw2 (the loop is now unprotected)"
    x sw1 ip link set br0 type bridge stp_state 0
    x sw2 ip link set br0 type bridge stp_state 0
    step "bounce the four inter-switch ports, so they come back forwarding"
    for p in $PORTS; do
        x "${p%%:*}" ip link set "${p##*:}" down
        x "${p%%:*}" ip link set "${p##*:}" up
    done
    step "(safety) auto-restore in 30 s"
    nohup bash -c "sleep 30; docker exec ${PREFIX}-sw1 ip link set br0 type bridge stp_state 1; \
                            docker exec ${PREFIX}-sw2 ip link set br0 type bridge stp_state 1" \
        >/dev/null 2>&1 &
    ;;
evidence)
    hr "what the users see"
    step "ping -c8 pc1 -> srv-web (VLAN 10 -> VLAN 40)"
    x pc1 ping -c8 -i 0.3 -W2 -q 10.100.0.12 2>&1 | tail -2
    hr "the loop carries everything twice - the counters prove the storm"
    step "ip -s link show eth4   (sw1's uplink towards sw2, two samples 3 s apart)"
    x sw1 sh -c 'ip -s link show eth4 | sed -n "4p"; sleep 3; ip -s link show eth4 | sed -n "4p"'
    hr "and the bridges are busy doing it"
    step "cat /proc/loadavg   (sw1 and sw2)"
    x sw1 cat /proc/loadavg
    x sw2 cat /proc/loadavg
    hr "STP is no longer breaking the loop"
    step "stp_state, and the number of blocking ports (0 while STP is off)"
    x sw1 cat /sys/class/net/br0/bridge/stp_state
    printf '  blocking ports: %s\n' "$(blocking_ports)"
    ;;
fix)
    step "stp_state 1 on sw1 and sw2 (STP re-elects and re-blocks an uplink)"
    restore
    ;;
verify)
    sleep 12                      # STP needs its listening/learning timers
    x pc1 ping -c5 -W2 -q 10.100.0.12 >/dev/null 2>&1 \
        && echo "T-04 verified: traffic is healthy again" \
        || { echo "T-04 STILL BROKEN"; exit 1; }
    printf '  blocking ports: %s (STP is breaking the loop again)\n' "$(blocking_ports)"
    step "ip -s link show eth4   (two samples 3 s apart - the rate is back to normal)"
    x sw1 sh -c 'ip -s link show eth4 | sed -n "4p"; sleep 3; ip -s link show eth4 | sed -n "4p"'
    ;;
*) usage ;;
esac
