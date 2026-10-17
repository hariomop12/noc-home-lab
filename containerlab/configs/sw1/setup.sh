#!/bin/sh
# sw1 - HQ access switch.
#
# A Linux bridge with 802.1Q filtering behaves like a managed access switch:
# access ports are untagged in one VLAN, the uplink is a trunk, and the two
# parallel links towards sw2 form a real layer-2 loop - which is why STP is on
# and why one of them ends up blocking.
#
#   eth1  trunk  -> r1        VLAN 10,20,30,40,99
#   eth2  access -> pc1       VLAN 10 HR
#   eth3  access -> pc2       VLAN 20 SALES
#   eth4  trunk  -> sw2       link A
#   eth5  trunk  -> sw2       link B
#
# The bridge itself carries the VLAN 99 management address (10.10.99.11), the
# same address the GNS3 lab gives the vios_l2 switch, so the NOC polls a switch
# and a router the same way.
set -eu

BR=br0
TRUNK_VIDS="10 20 30 40 99"

ip link add "$BR" type bridge
# vlan_filtering must be set before the first port joins the bridge.
ip link set "$BR" type bridge vlan_filtering 1 \
    stp_state 1 priority 4096 forward_delay 200 hello_time 200 max_age 2000
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
add_access eth3 20
add_trunk  eth4
add_trunk  eth5

# -------------------------------------------------- management VLAN 99 ------
# The bridge's own port is the SVI: untagged traffic on the bridge belongs to
# VLAN 99, and the address below is the switch's management address.
bridge vlan add dev "$BR" vid 99 self pvid untagged
ip addr add 10.10.99.11/24 dev "$BR"
ip route replace default via 10.10.99.1

. /etc/lab/agents.sh

echo "sw1: bridge up, VLAN 99 SVI 10.10.99.11, STP root (priority 4096)"
