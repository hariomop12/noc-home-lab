#!/bin/sh
# r2 boot hook - the branch side of Lab 07.
set -eu

sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv4.conf.all.rp_filter=0
sysctl -qw net.ipv4.conf.default.rp_filter=0

for i in 1 2 3; do
    ip link set "eth$i" up 2>/dev/null || true
done

for vlan in 10 99; do
    if ! ip link show "eth2.$vlan" >/dev/null 2>&1; then
        ip link add link eth2 name "eth2.$vlan" type vlan id "$vlan"
    fi
    ip link set "eth2.$vlan" up
done

# NAT overload on the branch WAN only. The transit to HQ is inside the lab and
# is deliberately not translated: HQ's 10.10/16 and 10.100/16 stay visible.
nft flush ruleset
nft -f /etc/lab/nat.nft

# Relayed DHCP for the branch users, straight from the HQ server - the Lab 07
# story, one dnsmasq for the whole lab.
dnsmasq --conf-file=/etc/lab/dhcp-relay.conf

. /etc/lab/agents.sh

echo "r2: sub-interfaces up, NAT loaded, DHCP relay up"
