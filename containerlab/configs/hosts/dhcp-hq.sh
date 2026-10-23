#!/bin/sh
# HQ user PC (VLAN 10/20/30): DHCP client.
#
# The lease comes from SRV-DNS in VLAN 40, relayed by r1 - the request is a
# broadcast on this VLAN, the relay turns it into a unicast with giaddr set to
# the local gateway, and the server picks the scope from that field.
#
# The client keeps retrying, so a DHCP fault (ticket T-02) has a live client to
# diagnose and the recovery is visible without touching the host.
set -eu

ip link set eth1 up
pkill udhcpc 2>/dev/null || true

(
    while :; do
        udhcpc -i eth1 -f -q -n -t 5 -T 3 -s /etc/lab/udhcpc-script.sh \
            >> /var/log/dhcp.log 2>&1 || true
        sleep 20
    done
) &
echo $! > /tmp/dhcp-loop.pid

. /etc/lab/agents.sh

echo "$(hostname): DHCP client started on eth1"
