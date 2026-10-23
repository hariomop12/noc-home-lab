#!/bin/sh
# sw2 - HQ distribution / server switch.
#
#   eth1  trunk  -> sw1       link A
#   eth2  trunk  -> sw1       link B
#   eth3  access -> pc3       VLAN 30 IT
#   eth4  access -> pc4       VLAN 30 IT
#   eth5  access -> client    VLAN 40 SERVERS (NOC toolbox)
#   eth6  access -> srv-dns   VLAN 40
#   eth7  access -> srv-syslog VLAN 40
#   eth8  access -> srv-web   VLAN 40
#   eth9  access -> srv-ntp   VLAN 40
#
# Management address 10.10.99.12 on VLAN 99, like the GNS3 lab.
set -eu

BR=br0
TRUNK_VIDS="10 20 30 40 99"

ip link add "$BR" type bridge
ip link set "$BR" type bridge vlan_filtering 1 \
    stp_state 1 priority 8192 forward_delay 200 hello_time 200 max_age 2000
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
add_trunk  eth2
add_access eth3 30
add_access eth4 30
add_access eth5 40
add_access eth6 40
add_access eth7 40
add_access eth8 40
add_access eth9 40
# Phase 5: the NOC stack lives in VLAN 40 next to the servers it watches.
# (The Postgres container is deliberately not here - it is a backend on the
# out-of-band network only, see containerlab/README.md.)
add_access eth10 40   # zbx-web
add_access eth11 40   # zbx-server
add_access eth12 40   # zbx-agent

bridge vlan add dev "$BR" vid 99 self pvid untagged
ip addr add 10.10.99.12/24 dev "$BR"
ip route replace default via 10.10.99.1

. /etc/lab/agents.sh

echo "sw2: bridge up, VLAN 99 SVI 10.10.99.12, STP secondary (priority 8192)"
