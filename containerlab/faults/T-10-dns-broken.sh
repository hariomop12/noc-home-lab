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
    step "stop pc1's DHCP client loop (a renew would rewrite the file and heal this)"
    dhcp_loop_stop pc1
    step "point pc1's resolver at an address that does not exist"
    x pc1 sh -c 'printf "nameserver 10.100.0.99\n" > /etc/resolv.conf'
    # The loop, not the client, is what heals this fault: killing only `udhcpc`
    # leaves the loop alive, and its next start re-leases and rewrites
    # /etc/resolv.conf from the (correct) DHCP option - which is how an earlier
    # run of this ticket ended up "proving" a fault that was no longer there.
    if x pc1 grep -q '10.100.0.99' /etc/resolv.conf; then
        printf '  injected: pc1 now asks 10.100.0.99 for names\n'
    else
        echo '  INJECT FAILED: the resolver is back to its real value'
        exit 1
    fi
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
    x pc1 sh -c 'printf "nameserver 10.100.0.10\n" > /etc/resolv.conf'
    dhcp_loop_start pc1
    ;;
verify)
    wait_for 30 bash -c "docker exec ${PREFIX}-pc1 nslookup web.lab.local 2>/dev/null | grep -q '10.100.0.12'" \
        && echo "T-10 verified: pc1 resolves names again" \
        || { echo "T-10 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
