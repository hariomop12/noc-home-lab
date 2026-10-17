#!/usr/bin/env bash
# T-08 - "One department cannot open the internal website"  (P3)
#
# Fault: a filter rule on r1 drops TCP/80 from VLAN 10 to the web server. Ping
# still works (ICMP is not matched), another VLAN still works (the source does
# not match), and the server never sees the connection at all - the classic
# silently-blocking-ACL signature.
#
# This is the containerlab stand-in for the IOS ACL lessons: in the GNS3 labs the
# same fault is an `access-group` on the interface.
. "$(dirname "$0")/lib.sh"
need_lab

WEB=10.100.0.12

http() { x "$1" sh -c "curl -s -m 3 -o /dev/null -w '%{http_code}' http://$WEB/ 2>/dev/null || echo timeout"; }

case "${1:-}" in
inject)
    step "add an nft filter rule on r1: VLAN 10 -> web server :80 drop"
    x r1 sh -c "nft add table ip acl
                nft 'add chain ip acl forward { type filter hook forward priority filter; policy accept; }'
                nft add rule ip acl forward ip saddr 10.10.10.0/24 ip daddr $WEB tcp dport 80 drop"
    ;;
evidence)
    hr "the user's view: the page does not load"
    printf '  pc1 (VLAN 10) HTTP status: %s\n' "$(http pc1)"
    ping1 pc1 "$WEB"
    hr "it is not the server and not the network"
    printf '  pc2 (VLAN 20) HTTP status: %s\n' "$(http pc2)"
    printf '  client (VLAN 40) HTTP status: %s\n' "$(http client)"
    step "pc1 -> server, TCP SYN never leaves r1"
    x r1 sh -c "conntrack -L 2>/dev/null | grep -c \"dport=80\" | sed 's/^/  displaced flows: /'"
    hr "the rule that is doing it"
    step "nft list table ip acl   (on r1)"
    x r1 nft list table ip acl
    ;;
fix)
    step "nft delete table ip acl   (on r1)"
    x r1 nft delete table ip acl
    ;;
verify)
    printf '  pc1 HTTP status: %s\n' "$(http pc1)"
    [ "$(http pc1)" = "200" ] \
        && echo "T-08 verified: VLAN 10 can load the site again" \
        || { echo "T-08 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
