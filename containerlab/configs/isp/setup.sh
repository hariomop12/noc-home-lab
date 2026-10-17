#!/bin/sh
# ISP boot hook: kernel forwarding and the management-plane agents.
set -eu

sysctl -qw net.ipv4.ip_forward=1

for i in 1 2 3; do
    ip link set "eth$i" up 2>/dev/null || true
done

. /etc/lab/agents.sh

echo "isp: forwarding on, agents up"
