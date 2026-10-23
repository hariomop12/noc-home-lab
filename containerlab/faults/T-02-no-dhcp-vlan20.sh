#!/usr/bin/env bash
# T-02 - "No DHCP address on the new PC in Sales (VLAN 20)"  (P2)
#
# Fault: r1's relay is restarted without its VLAN 20 entry. The relay process is
# up, the DHCP server is up, other VLANs get leases - only VLAN 20's requests
# have nowhere to go. The symptom is what users report: "this PC has no address".
#
# Two things make this diagnosable rather than guessable:
#   * the relay is proven alive (ps) while its config is proven incomplete (grep)
#   * the server is proven healthy from a VLAN that *does* work
# A single ping would have proven nothing at all.
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
    dhcp_loop_stop pc2
    x pc2 sh -c 'ip addr flush dev eth1'
    ;;
evidence)
    hr "who has a lease and who does not"
    for h in pc1 pc2 pc3; do printf '  %-4s %s\n' "$h" "$(pc_ip "$h")"; done
    hr "the client keeps asking and gets nothing"
    step "a live udhcpc attempt on pc2 (VLAN 20)"
    x pc2 sh -c 'udhcpc -i eth1 -f -q -n -t 2 -T 2 -s /etc/lab/udhcpc-script.sh 2>&1; echo "  udhcpc exit=$?"'
    hr "the relay is running - with one entry missing"
    step "ps | grep dnsmasq   (on r1)"
    x r1 sh -c 'ps | grep "[d]nsmasq"'
    step "grep dhcp-relay $BROKEN   (on r1)"
    x r1 grep dhcp-relay "$BROKEN"
    hr "the server is healthy - prove it from another VLAN"
    step "udhcpc on pc1 (VLAN 10) succeeds"
    x pc1 sh -c 'udhcpc -i eth1 -f -q -n -t 2 -T 2 -s /etc/lab/udhcpc-script.sh 2>&1 | tail -2'
    ;;
fix)
    step "restart the relay from the real config   (on r1)"
    x r1 sh -c 'pkill dnsmasq; sleep 1; dnsmasq --conf-file=/etc/lab/dhcp-relay.conf'
    x r1 rm -f "$BROKEN"
    step "restart pc2's DHCP client loop"
    dhcp_loop_start pc2
    ;;
verify)
    wait_for 60 bash -c "[ -n \"\$(docker exec ${PREFIX}-pc2 ip -4 addr show eth1 | awk '/inet /{print \$2}')\" ]" \
        && echo "T-02 verified: pc2 has $(pc_ip pc2)" \
        || { echo "T-02 STILL BROKEN"; exit 1; }
    ;;
*) usage ;;
esac
