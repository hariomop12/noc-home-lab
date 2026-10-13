#!/usr/bin/env sh
set -eu
. /usr/local/lib/lab-entrypoint.sh

apply_lab_address || true

echo "noc-tools ready. Available: tcpdump, nmap, snmpwalk, snmpget, snmpgetnext,"
echo "dig, mtr, traceroute, ping, iperf3, curl"

exec "$@"
