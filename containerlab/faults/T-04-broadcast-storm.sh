#!/usr/bin/env bash
# T-04 - "The whole HQ is crawling, the switch CPU is pegged"  (P1)
#
# Fault: STP is disabled on both switches. The two parallel uplinks are a real
# loop again, and an Ethernet loop with no STP is an instant broadcast storm.
#
# Safety: this is the one fault that can hurt the host, so the inject step arms
# a 45-second auto-restore. The fault stops being interesting after ten.
. "$(dirname "$0")/lib.sh"
need_lab

restore() {
    x sw1 ip link set br0 type bridge stp_state 1
    x sw2 ip link set br0 type bridge stp_state 1
}

case "${1:-}" in
inject)
    step "stp_state 0 on sw1 and sw2"
    x sw1 ip link set br0 type bridge stp_state 0
    x sw2 ip link set br0 type bridge stp_state 0
    step "(safety) auto-restore in 45 s"
    nohup bash -c "sleep 45; docker exec ${PREFIX}-sw1 ip link set br0 type bridge stp_state 1; \
                            docker exec ${PREFIX}-sw2 ip link set br0 type bridge stp_state 1" \
        >/dev/null 2>&1 &
    ;;
evidence)
    hr "what the users see"
    step "ping -c10 pc1 -> srv-web (VLAN 10 -> VLAN 40)"
    x pc1 ping -c10 -i 0.2 -W2 -q 10.100.0.12 2>&1 | tail -2
    hr "why: the uplink is flooded"
    step "ip -s link show eth4   (sw1 uplink towards sw2)"
    x sw1 ip -s link show eth4 | sed -n '1,5p'
    step "cat /proc/loadavg   (sw1)"
    x sw1 cat /proc/loadavg
    hr "STP is no longer breaking the loop"
    step "blocking ports counted on both switches (expect 0)"
    printf '  blocking ports: %s\n' "$( { x sw1 bridge -d link show; x sw2 bridge -d link show; } | grep -c 'state blocking')"
    ;;
fix)
    step "stp_state 1 on sw1 and sw2"
    restore
    ;;
verify)
    sleep 8
    x pc1 ping -c4 -W2 -q 10.100.0.12 >/dev/null 2>&1 \
        && echo "T-04 verified: traffic is healthy again" \
        || { echo "T-04 STILL BROKEN"; exit 1; }
    printf '  blocking ports: %s\n' "$( { x sw1 bridge -d link show; x sw2 bridge -d link show; } | grep -c 'state blocking')"
    ;;
*) usage ;;
esac
