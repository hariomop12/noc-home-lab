#!/usr/bin/env bash
# T-09 - "One PC keeps dropping off the network, the rest are fine"  (P2)
#
# Fault: a second host in the same VLAN uses an address that is already in use.
# Both answer ARP, so the switch's MAC table and every neighbour cache in the
# VLAN keep flipping between two MACs - the victim sees intermittent loss and
# everything else looks healthy.
. "$(dirname "$0")/lib.sh"
need_lab

DUPFILE=/tmp/t09-duplicate-ip

case "${1:-}" in
inject)
    dup="$(pc_ip pc4)"
    step "pc3 takes pc4's address ($dup) as a second address"
    x pc3 ip addr add "$dup/24" dev eth1
    echo "$dup" > "$DUPFILE"
    ;;
evidence)
    dup="$(cat "$DUPFILE" 2>/dev/null || pc_ip pc4)"
    printf '  the disputed address is %s\n' "$dup"
    hr "the victim: one host reports intermittent loss"
    step "ping -c10 pc4 -> its own gateway"
    x pc4 ping -c10 -i 0.3 -W2 -q 10.10.30.1 2>&1 | tail -3
    hr "the proof the address is duplicated"
    step "arping -D from pc4 (duplicate address detection on itself)"
    x pc4 arping -D -c 3 -w 3 -I eth1 "$dup" 2>&1 | tail -4
    hr "and the neighbour cache that keeps flapping"
    step "ip neigh show   (pc1 and pc4, VLAN 30)"
    x pc4 sh -c "ip neigh show | grep -E '10.10.30.(1|$dup)' | head -4"
    x pc1 sh -c "ip neigh show | grep '$dup'" || echo "  (pc1 has no entry)"
    ;;
fix)
    dup="$(cat "$DUPFILE" 2>/dev/null || pc_ip pc4)"
    step "remove the duplicated address from pc3"
    x pc3 ip addr del "$dup/24" dev eth1
    rm -f "$DUPFILE"
    ;;
verify)
    x pc4 arping -D -c 3 -w 3 -I eth1 "$(pc_ip pc4)" >/dev/null 2>&1 \
        && { echo "T-09 verified: the address is unique again"; } \
        || echo "  (note: arping -D is quiet when there is no duplicate)"
    x pc4 ping -c5 -W2 -q 10.10.30.1 >/dev/null 2>&1 \
        && echo "  pc4 -> gateway: 0% loss" \
        || { echo "T-09 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
