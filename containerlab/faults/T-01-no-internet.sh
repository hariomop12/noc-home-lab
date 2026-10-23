#!/usr/bin/env bash
# T-01 - "The intranet works, nothing on the internet loads"  (P1)
#
# Fault: r1's NAT ruleset is flushed. Routing is untouched, so every check that
# looks at the routing table, the interfaces or OSPF passes. Only the
# translation on the WAN interface is missing.
#
# Two traps live in this ticket, and both were found the hard way:
#
#   1. `nft flush ruleset` does not delete what conntrack has already learned.
#      An established translation keeps working until its entry expires, so
#      without `conntrack -F` the fault looks "half broken".
#   2. The simulated ISP does not filter RFC1918 addresses and it learns the
#      lab's prefixes over OSPF, so an *untranslated* packet still gets a reply
#      here - the ping succeeds even though the edge is leaking private source
#      addresses. On a real ISP that packet is dropped, which is why the fault
#      is proven on the wire by capture, not by the ping.
#
# This is the same lesson as the Lab 07 correction, deliberately re-created.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    step "nft flush ruleset   (on r1)"
    x r1 nft flush ruleset
    step "conntrack -F   (on r1, so the fault is unambiguous)"
    x r1 conntrack -F >/dev/null 2>&1 || true
    ;;
evidence)
    hr "what the user reports"
    ping1 pc1 10.100.0.12          # intranet
    ping1 pc1 200.1.1.10           # internet
    echo "  note: the reply comes back because this ISP accepts private sources -"
    echo "  the ping is NOT the proof here, the wire is."
    hr "everything that still looks healthy (the trap)"
    step "ip route on r1"
    x r1 ip route | grep -E '^(default|10\.0\.0\.12|10\.100\.0\.0)' | head -4
    hr "no translation exists at all"
    step "nft list ruleset on r1"
    x r1 nft list ruleset
    step "conntrack -L | grep 200.1.1 on r1   (after pc1 tried)"
    x r1 sh -c 'conntrack -L 2>/dev/null | grep 200.1.1 | head -3' || echo "  (no translations)"
    hr "the one check that is not healthy: the source address on the wire"
    step "tcpdump on the ISP-facing link while pc1 pings 200.1.1.10"
    capture_src isp eth1 200.1.1.10
    ;;
fix)
    step "nft -f /etc/lab/nat.nft   (on r1)"
    x r1 nft -f /etc/lab/nat.nft
    ;;
verify)
    x pc1 ping -c2 -W2 -q 200.1.1.10 >/dev/null 2>&1 \
        && echo "T-01 verified: pc1 reaches 200.1.1.10 again" \
        || { echo "T-01 STILL BROKEN"; exit 1; }
    step "and the internet edge now sees r1's WAN address, not pc1's"
    capture_src isp eth1 200.1.1.10
    x r1 sh -c 'conntrack -L 2>/dev/null | grep -m1 200.1.1' || true
    ;;
*) usage ;;
esac
