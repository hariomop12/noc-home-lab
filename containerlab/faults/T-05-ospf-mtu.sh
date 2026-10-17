#!/usr/bin/env bash
# T-05 - "HQ lost the internet, and r1 shows an OSPF neighbour stuck"  (P2)
#
# Fault: the MTU on r1's WAN interface is lowered. FRR's OSPF MTU-mismatch
# detection then refuses to complete the database exchange, so the adjacency
# never leaves ExStart/Exchange - and with it the default route OSPF was
# teaching r1. The branch is unaffected: its own WAN link is a different cable.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    step "ip link set eth1 mtu 1400   (on r1)"
    x r1 ip link set eth1 mtu 1400
    ;;
evidence)
    hr "the user's view"
    ping1 pc1 10.100.0.12       # intranet, unaffected
    ping1 pc1 200.1.1.10        # internet through r1's WAN
    ping1 pc5 200.1.1.10        # the branch has its own WAN - still fine
    hr "the adjacency that never came up"
    step "show ip ospf neighbor   (on r1)"
    vty r1 "show ip ospf neighbor"
    hr "and the reason"
    step "mtu on r1 eth1 vs isp eth1"
    x r1 sh -c "ip link show eth1 | head -1"
    x isp sh -c "ip link show eth1 | head -1"
    step "show ip ospf interface eth1   (r1)"
    vty r1 "show ip ospf interface eth1" | grep -E "MTU mismatch|MTU |State "
    hr "r1 also lost the default route OSPF was giving it"
    step "ip route | grep default   (on r1)"
    x r1 ip route | grep default || echo "  (no default route)"
    ;;
fix)
    step "ip link set eth1 mtu 9500   (on r1)"
    x r1 ip link set eth1 mtu 9500
    ;;
verify)
    wait_for 60 bash -c "docker exec ${PREFIX}-r1 vtysh -c 'show ip ospf neighbor' | grep -q Full" \
        && echo "T-05 verified: OSPF is Full again and r1 has its default route back" \
        || { echo "T-05 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
