#!/usr/bin/env bash
# T-06 - "HQ loses packets for a few seconds, over and over"  (P2)
#
# Fault: sw1's uplink to r1 flaps. Every time it goes down, the whole HQ loses
# its path to the router until STP reconverges - users see bursts of loss, not
# a clean outage, which is what makes it annoying to report and easy to miss.
#
# Note on the original ticket wording: a container has no PHY, so there are no
# CRC counters to read. The counters that do tell the story are the link
# down-counts, the STP state changes and the syslog events on the collector.
. "$(dirname "$0")/lib.sh"
need_lab

PIDFILE=/tmp/flap.pid

case "${1:-}" in
inject)
    step "start a flap loop on sw1 eth1 (3 s down / 4 s up)"
    x sw1 sh -c "nohup sh -c 'while :; do ip link set eth1 down; sleep 3; ip link set eth1 up; sleep 4; done' >/dev/null 2>&1 &
                echo \$! > $PIDFILE"
    ;;
evidence)
    hr "the user's view: bursts of loss, not a dead network"
    step "ping -c15 pc1 -> srv-web"
    x pc1 ping -c15 -i 0.3 -W2 -q 10.100.0.12 2>&1 | tail -3
    hr "the flapping link"
    step "ip -s link show eth1   (sw1, uplink to r1)"
    x sw1 ip -s link show eth1 | sed -n '1p;4,5p'
    step "bridge -d link show eth1   (STP state right now)"
    x sw1 bridge -d link show | grep -A1 '^.*eth1' | head -2
    hr "the collector has the story in its own words"
    step "tail of sw1's messages on srv-syslog"
    x srv-syslog sh -c 'ls -t /var/log/remote/*.log | head -3 | xargs -r grep -h -i "link" 2>/dev/null | tail -4' || true
    ;;
fix)
    step "stop the flap loop and bring the link up"
    x sw1 sh -c "[ -f $PIDFILE ] && kill \$(cat $PIDFILE) 2>/dev/null; rm -f $PIDFILE; ip link set eth1 up"
    ;;
verify)
    sleep 5
    x pc1 ping -c10 -W2 -q 10.100.0.12 2>&1 | tail -2
    x pc1 ping -c4 -W2 -q 10.100.0.12 >/dev/null 2>&1 \
        && echo "T-06 verified: no loss over 10 packets" \
        || { echo "T-06 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
