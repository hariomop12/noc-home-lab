#!/usr/bin/env bash
# T-03 - "The two IT PCs can ping each other but not their gateway"  (P2)
#
# Fault: VLAN 30 has been removed from both sw1-sw2 uplinks. Both PCs are in
# VLAN 30 on the same switch, so they still reach each other, but the VLAN no
# longer crosses the trunk - the classic local-works/remote-fails signature.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    # The symptom is "pc3 cannot reach pc4", so pc4 must be reachable first:
    # a host whose lease has expired would confuse this ticket with a DHCP fault.
    need_lease pc4 || exit 1
    step "bridge vlan del vid 30 on both sw2 uplinks"
    x sw2 sh -c 'for p in eth1 eth2; do bridge vlan del dev $p vid 30; done'
    ;;
evidence)
    hr "the user's view"
    ping1 pc3 "$(pc_ip pc4)"          # same VLAN 30, same switch
    ping1 pc3 10.10.30.1              # the gateway on r1
    ping1 pc3 10.100.0.12             # anything off-VLAN
    hr "where the VLAN exists"
    step "bridge vlan show   (on sw2 - no 30)"
    x sw2 bridge vlan show | grep -A6 '^eth1'
    step "bridge vlan show   (on sw1 - 30 present)"
    x sw1 bridge vlan show | grep -A6 '^eth1'
    hr "the router side is fine"
    step "ip -4 addr show eth2.30   (on r1)"
    x r1 ip -4 addr show eth2.30 | grep -E 'inet|state'
    ;;
fix)
    step "bridge vlan add vid 30 on both sw2 uplinks"
    x sw2 sh -c 'for p in eth1 eth2; do bridge vlan add dev $p vid 30; done'
    ;;
verify)
    wait_for 20 bash -c "docker exec ${PREFIX}-pc3 ping -c2 -W2 -q 10.10.30.1 >/dev/null 2>&1" \
        && echo "T-03 verified: pc3 reaches its gateway over the trunk again" \
        || { echo "T-03 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
