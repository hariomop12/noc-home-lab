#!/usr/bin/env bash
# T-07 - "The internet is slow and lossy, the internal network is fine"  (P2)
#
# Fault: 300 ms of latency and 10% loss, applied with tc/netem on r1's WAN
# interface. The internal path is untouched, so the fault is localised to
# exactly one hop - and the numbers prove which one.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    step "tc qdisc add dev eth1 root netem delay 300ms 20ms loss 10%   (on r1)"
    x r1 tc qdisc del dev eth1 root 2>/dev/null || true
    x r1 tc qdisc add dev eth1 root netem delay 300ms 20ms loss 10%
    ;;
evidence)
    hr "the user's view"
    step "ping -c5 pc1 -> internet server 200.1.1.10"
    x pc1 ping -c5 -W3 -q 200.1.1.10 2>&1 | tail -3
    step "ping -c5 pc1 -> internal server 10.100.0.12"
    x pc1 ping -c5 -W3 -q 10.100.0.12 2>&1 | tail -2
    hr "the hop that carries the damage"
    step "tc -s qdisc show dev eth1   (on r1)"
    x r1 tc -s qdisc show dev eth1 | head -6
    step "traceroute from pc1 to 200.1.1.10"
    x pc1 traceroute -n -w1 -q1 200.1.1.10 2>&1 | head -5
    ;;
fix)
    step "tc qdisc del dev eth1 root   (on r1)"
    x r1 tc qdisc del dev eth1 root
    ;;
verify)
    x pc1 ping -c4 -W2 -q 200.1.1.10 >/dev/null 2>&1 \
        && { echo "T-07 verified: internet is healthy again"; x pc1 ping -c3 -W3 -q 200.1.1.10 2>&1 | tail -1; } \
        || { echo "T-07 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
