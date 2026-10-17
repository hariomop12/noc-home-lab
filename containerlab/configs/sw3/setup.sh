#!/bin/sh
# sw3 - Branch-1 access switch.
#
#   eth1  trunk  -> r2   VLAN 10,99
#   eth2  access -> pc5  VLAN 10
#   eth3  access -> pc6  VLAN 10
#
# Management address 10.20.99.13 on VLAN 99 - same address and same reasoning as
# the GNS3 lab: the branch is reachable from the HQ NOC even when the WAN is the
# thing being troubleshot.
set -eu

BR=br0
TRUNK_VIDS="10 99"

ip link add "$BR" type bridge
ip link set "$BR" type bridge vlan_filtering 1 \
    stp_state 1 priority 32768 forward_delay 200 hello_time 200 max_age 2000
ip link set "$BR" up

add_access() {
    ip link set "$1" master "$BR"
    ip link set "$1" up
    bridge vlan del dev "$1" vid 1 2>/dev/null || true
    bridge vlan add dev "$1" vid "$2" pvid untagged
}

add_trunk() {
    ip link set "$1" master "$BR"
    ip link set "$1" up
    bridge vlan del dev "$1" vid 1 2>/dev/null || true
    for v in $TRUNK_VIDS; do
        bridge vlan add dev "$1" vid "$v"
    done
}

add_trunk  eth1
add_access eth2 10
add_access eth3 10

bridge vlan add dev "$BR" vid 99 self pvid untagged
ip addr add 10.20.99.13/24 dev "$BR"
ip route replace default via 10.20.99.1

. /etc/lab/agents.sh

echo "sw3: bridge up, VLAN 99 SVI 10.20.99.13"
