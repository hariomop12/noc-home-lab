#!/bin/sh
# Branch-1 user PC (VLAN 10): DHCP client, served by the HQ server two hops
# away through r2's relay. Identical logic to the HQ users - that is the point
# of the Lab 07 design: one server, one scope per subnet, chosen by giaddr.
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

. /etc/lab/agents.sh

echo "$(hostname): branch DHCP client started on eth1"
