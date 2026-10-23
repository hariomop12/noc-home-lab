#!/usr/bin/env bash
# T-09 - "One PC keeps dropping off the network, the rest are fine"  (P2)
#
# Fault: a second host in the VLAN is given an address that is already in use.
# Both hosts answer ARP for that address, so whichever MAC the gateway and the
# neighbours cache last is where the traffic goes - and the real owner, whose
# traffic leaves with its own MAC, stops seeing its own replies.
#
# Three details make this ticket honest rather than decorative:
#
#   * The victim must actually *have* its lease before the fault is injected
#     (need_lease), or the ticket measures a missing DHCP lease and a duplicate
#     address at once and proves neither.
#   * The host that takes the address must have its DHCP client loop stopped
#     first, or the next renewal repairs the fault by itself.
#   * `arping -U` is what a real host does the moment it claims an address: it
#     announces it. Without the announcement the router keeps its old cache entry
#     for hours and the fault is invisible - which is itself the lesson, because
#     a duplicate address that nobody has cached yet is a time bomb, not an
#     outage.
#
# The proof is the ARP reply, not the ping: `arping -D` (duplicate address
# detection, run from the owner) shows the duplicate's MAC answering, and the
# owner's own outbound traffic then fails while the duplicate's works.
. "$(dirname "$0")/lib.sh"
need_lab

DUPFILE=/tmp/t09-duplicate-ip
GW=10.10.30.1

mac_of()      { x "$1" sh -c 'cat /sys/class/net/eth1/address'; }
r1_arp_of()   { x r1 sh -c "ip neigh show $1 dev eth2.30 || echo '  (no cache entry)'"; }

case "${1:-}" in
inject)
    need_lease pc4 || exit 1
    dup="$(pc_ip pc4)"
    step "stop pc3's DHCP client loop (a renewal would undo this)"
    dhcp_loop_stop pc3
    step "pc3 claims pc4's address ($dup) as a second address"
    x pc3 ip addr add "$dup/24" dev eth1
    step "pc3 announces it, as a real host would on startup (arping -U)"
    x pc3 arping -U -c 2 -I eth1 "$dup" 2>&1 | tail -1
    # A fault that is not really there produces an artifact that proves nothing,
    # so the inject refuses to continue unless the duplicate actually exists.
    if x pc3 sh -c "ip -4 addr show dev eth1 | grep -q ' $dup/'"; then
        # pc_ip prints both addresses now, one per line; keep the message to one.
        printf '  injected: pc3 holds %s as well as %s\n' "$dup" "$(pc_ip pc3 | head -1)"
    else
        echo '  INJECT FAILED: pc3 does not hold the duplicate address'
        dhcp_loop_start pc3
        exit 1
    fi
    echo "$dup" > "$DUPFILE"
    ;;
evidence)
    dup="$(cat "$DUPFILE" 2>/dev/null || pc_ip pc4)"
    printf '  the disputed address is %s\n' "$dup"
    hr "the owner's own check: duplicate address detection"
    step "arping -D from pc4"
    x pc4 arping -D -c 3 -w 3 -I eth1 "$dup" 2>&1 | grep -iE 'duplicate|reply|response' || true
    hr "and the router's cache can point at either MAC"
    step "ping the disputed address from r1, then read r1's cache"
    x r1 ping -c2 -W2 "$dup" >/dev/null 2>&1
    r1_arp_of "$dup"
    printf "  pc4's real MAC: %s   pc3's (the duplicate): %s\n" "$(mac_of pc4)" "$(mac_of pc3)"
    hr "the victim: the owner cannot rely on its own address"
    step "ping -c20 -i 0.5 -W2 pc4 -> its gateway (20 packets over 10 s)"
    x pc4 ping -c20 -i 0.5 -W2 -q "$GW" 2>&1 | tail -2
    echo "  the loss is intermittent by nature: the router re-resolves the"
    echo "  disputed address every time its cache goes stale, and whichever host"
    echo "  answers last gets the next packet."
    step "for contrast, the duplicate host is perfectly happy"
    x pc3 ping -c4 -W2 -q "$GW" 2>&1 | tail -2
    ;;
fix)
    dup="$(cat "$DUPFILE" 2>/dev/null || pc_ip pc4)"
    step "remove the duplicated address from pc3"
    x pc3 ip addr del "$dup/24" dev eth1 2>/dev/null || true
    step "restart pc3's DHCP client loop"
    dhcp_loop_start pc3
    step "clear the poisoned cache entry on r1 (the owner re-announces itself)"
    x r1 sh -c "ip neigh del $dup dev eth2.30 2>/dev/null || true"
    x pc4 arping -U -c 2 -I eth1 "$dup" 2>&1 | tail -1
    rm -f "$DUPFILE"
    ;;
verify)
    dup="$(pc_ip pc4)"
    step "no duplicate answers any more (arping -D from the owner)"
    x pc4 arping -D -c 3 -w 3 -I eth1 "$dup" 2>&1 | grep -iE 'duplicate|reply|response' \
        || echo "  (no reply - the address is unique)"
    step "and the router's cache points at the owner again"
    r1_arp_of "$dup"
    printf "  pc4's real MAC: %s\n" "$(mac_of pc4)"
    sleep 3
    x pc4 ping -c5 -W2 -q "$GW" >/dev/null 2>&1 \
        && echo "T-09 verified: the owner's traffic is healthy again" \
        || { echo "T-09 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
