#!/usr/bin/env bash
# T-02 - "A new PC in Sales never gets an IP address"  (P2)
#
# Fault: the DHCP relay on r1 no longer relays VLAN 20. VLANs 10 and 30 are
# unaffected, and the server itself is fine, so the fault has to be localised to
# one relay entry rather than to "DHCP is broken".
. "$(dirname "$0")/lib.sh"
need_lab

BROKEN=/tmp/relay-broken.conf

case "${1:-}" in
inject)
    step "start the r1 relay without the VLAN 20 pair"
    x r1 sh -c "grep -v 'dhcp-relay=10.10.20.1' /etc/lab/dhcp-relay.conf > $BROKEN
                pkill dnsmasq
                dnsmasq --conf-file=$BROKEN"
    step "stop pc2's client and drop its lease, so the symptom is real"
    x pc2 sh -c 'for p in $(pgrep -f "^sh /etc/lab/setup.sh$"); do kill "$p" 2>/dev/null; done
                 pkill udhcpc 2>/dev/null
                 ip addr flush dev eth1'
    ;;
evidence)
    hr "who has a lease and who does not"
    for h in pc1 pc2 pc3; do printf '  %-4s %s\n' "$h" "$(pc_ip "$h")"; done
    hr "the relay is running - with one entry missing"
    step "ps | grep dnsmasq   (on r1)"
    x r1 sh -c 'ps | grep "[d]nsmasq"'
    step "grep dhcp-relay /tmp/relay-broken.conf   (on r1)"
    x r1 grep dhcp-relay "$BROKEN"
    hr "the client keeps asking"
    step "tail -3 /var/log/dhcp.log   (on pc2)"
    x pc2 tail -3 /var/log/dhcp.log
    hr "the server is healthy - prove it from the other VLAN"
    step "udhcpc on pc1 (VLAN 10) succeeds"
    x pc1 sh -c 'udhcpc -i eth1 -f -q -n -t 2 -T 2 -s /etc/lab/udhcpc-script.sh 2>&1 | tail -2'
    ;;
fix)
    step "restart the relay from the real config   (on r1)"
    x r1 sh -c 'pkill dnsmasq; sleep 1; dnsmasq --conf-file=/etc/lab/dhcp-relay.conf'
    x r1 rm -f "$BROKEN"
    step "restart pc2's DHCP client loop"
    x pc2 sh -c 'nohup sh -c "while :; do udhcpc -i eth1 -f -q -n -t 5 -T 3 -s /etc/lab/udhcpc-script.sh >> /var/log/dhcp.log 2>&1; sleep 20; done" >/dev/null 2>&1 &'
    ;;
verify)
    wait_for 60 bash -c "[ -n \"\$(docker exec ${PREFIX}-pc2 ip -4 addr show eth1 | awk '/inet /{print \$2}')\" ]" \
        && echo "T-02 verified: pc2 has $(pc_ip pc2)" \
        || { echo "T-02 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
