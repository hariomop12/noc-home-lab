#!/bin/sh
# r1 boot hook - everything zebra (and the NOC) needs to find in place before
# FRR loads frr.conf.
set -eu

# ---------------------------------------------------------------- kernel ----
sysctl -qw net.ipv4.ip_forward=1
sysctl -qw net.ipv4.conf.all.rp_filter=0
sysctl -qw net.ipv4.conf.default.rp_filter=0

for i in 1 2 3; do
    ip link set "eth$i" up 2>/dev/null || true
done

# ------------------------------------------ router-on-a-stick sub-interfaces -
# The single trunk to sw1 carries five VLANs; each one becomes the default
# gateway of that VLAN.
for vlan in 10 20 30 40 99; do
    if ! ip link show "eth2.$vlan" >/dev/null 2>&1; then
        ip link add link eth2 name "eth2.$vlan" type vlan id "$vlan"
    fi
    ip link set "eth2.$vlan" up
done

# ------------------------------------------------------------------ NAT ----
# FRR has no NAT support in this build, so PAT is nftables. Lab 07's corrected
# rule: only the WAN interface translates, never the internal transit to r2.
nft flush ruleset
nft -f /etc/lab/nat.nft

# ------------------------------------------------------------ DHCP relay ----
# The FRR equivalent of `ip helper-address 10.100.0.10`: relay the HQ user
# VLANs to the DHCP server in VLAN 40 and stamp giaddr with the local gateway.
dnsmasq --conf-file=/etc/lab/dhcp-relay.conf

# ------------------------------------------------------ management plane ----
. /etc/lab/agents.sh

echo "r1: sub-interfaces up, NAT loaded, DHCP relay up"
