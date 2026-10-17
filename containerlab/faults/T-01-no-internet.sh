#!/usr/bin/env bash
# T-01 - "The intranet works, nothing on the internet loads"  (P1)
#
# Fault: r1's NAT ruleset is flushed. Routing is untouched, so every check that
# looks at the routing table, the interfaces or OSPF passes. Only the
# translation on the WAN interface is missing.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    step "nft flush ruleset   (on r1)"
    x r1 nft flush ruleset
    ;;
evidence)
    hr "what the user reports"
    ping1 pc1 10.100.0.12          # intranet
    ping1 pc1 200.1.1.10           # internet
    hr "everything that still looks healthy (the trap)"
    step "ip route on r1"
    x r1 ip route | grep -E '^(default|10\.0\.0\.12|10\.100\.0\.0)' | head -4
    hr "the one check that is not healthy"
    step "nft list ruleset on r1"
    x r1 nft list ruleset
    step "conntrack -L | grep 200.1.1 on r1   (after pc1 tried)"
    x r1 sh -c 'conntrack -L 2>/dev/null | grep 200.1.1 | head -3' || echo "(no translations)"
    ;;
fix)
    step "nft -f /etc/lab/nat.nft   (on r1)"
    x r1 nft -f /etc/lab/nat.nft
    ;;
verify)
    x pc1 ping -c2 -W2 -q 200.1.1.10 >/dev/null 2>&1 \
        && echo "T-01 verified: pc1 reaches 200.1.1.10 again" \
        || { echo "T-01 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
