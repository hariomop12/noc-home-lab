#!/usr/bin/env sh
set -eu
# Shared build script for the lab service images.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for img in noc-tools syslog dnsmasq web ntp clab-frr clab-host; do
  echo "==> building ${img}:lab"
  docker build -t "${img}:lab" -f "${here}/${img}/Dockerfile" "${here}"
done

# Phase 5 NOC stack: the vendor Zabbix images plus the small wrapper that lets
# them hold a lab address in VLAN 40 (docker/clab-noc/noc-entrypoint.sh). The
# database is not wrapped - it lives on the out-of-band network and uses the
# vendor image as-is.
for img in zbx-server zbx-web zbx-agent; do
  echo "==> building clab-${img}:lab"
  docker build -t "clab-${img}:lab" -f "${here}/clab-noc/${img}.Dockerfile" "${here}"
done

echo
echo "Done. Images:"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' \
  | grep -E '^(noc-tools|syslog|dnsmasq|web|ntp|clab-frr|clab-host|clab-zbx-[a-z]+):lab' || true
