#!/usr/bin/env sh
set -eu
. /usr/local/lib/lab-entrypoint.sh

apply_lab_address || true

echo "noc-tools ready. Available: ssh, tcpdump, nmap, snmpwalk, snmpget,"
echo "dig, mtr, traceroute, ping, iperf3, curl"
echo "Config backup: mkdir -p /tftp && in.tftpd -l -c -s /tftp -u root &"
echo "then on the device: copy running-config tftp://10.100.0.50/<name>.cfg"

exec "$@"
