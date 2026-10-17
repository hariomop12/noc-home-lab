#!/usr/bin/env bash
# T-10 - "I can ping the server but the browser cannot find it"  (P3)
#
# Fault: the PC's resolver points at an address that does not exist in the lab.
# Everything at layer 3 works (the ping answers), the DNS server itself is
# healthy (a direct query to 10.100.0.10 answers), and the only broken thing is
# what the client was told to ask. That distinction is the whole ticket: prove
# the server works, then look at the client's configuration.
#
# The DHCP client loop is stopped with the fault, otherwise its periodic renew
# would rewrite /etc/resolv.conf from the (correct) DHCP option and heal it.
. "$(dirname "$0")/lib.sh"
need_lab

case "${1:-}" in
inject)
    step "stop pc1's DHCP loop, then point its resolver at a dead address"
    x pc1 sh -c 'for p in $(pgrep -f "^sh /etc/lab/setup.sh$"); do kill "$p" 2>/dev/null; done
                sleep 1
                printf "nameserver 10.100.0.99\n" > /etc/resolv.conf'
    ;;
evidence)
    hr "the user's view: the name does not resolve"
    step "nslookup web.lab.local   (pc1, using its configured resolver)"
    x pc1 nslookup web.lab.local 2>&1 | tail -4
    hr "layer 3 is fine"
    ping1 pc1 10.100.0.12
    hr "the DNS server is fine too - ask it directly"
    step "nslookup web.lab.local 10.100.0.10   (pc1, explicit server)"
    x pc1 nslookup web.lab.local 10.100.0.10 2>&1 | tail -3
    hr "so the fault is the client's configuration"
    step "cat /etc/resolv.conf   (pc1)"
    x pc1 cat /etc/resolv.conf
    step "last lease line   (pc1)"
    x pc1 tail -1 /var/log/dhcp.log
    ;;
fix)
    step "put the real resolver back and restart the DHCP client"
    x pc1 sh -c 'printf "nameserver 10.100.0.10\n" > /etc/resolv.conf
                 nohup sh -c "while :; do udhcpc -i eth1 -f -q -n -t 5 -T 3 -s /etc/lab/udhcpc-script.sh >> /var/log/dhcp.log 2>&1; sleep 20; done" >/dev/null 2>&1 &'
    ;;
verify)
    wait_for 30 bash -c "docker exec ${PREFIX}-pc1 nslookup web.lab.local 2>/dev/null | grep -q '10.100.0.12'" \
        && echo "T-10 verified: pc1 resolves names again" \
        || { echo "T-10 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
