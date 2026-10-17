#!/usr/bin/env sh
set -eu
# Shared build script for the lab service images.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for img in noc-tools syslog dnsmasq web ntp clab-frr clab-host; do
  echo "==> building ${img}:lab"
  docker build -t "${img}:lab" -f "${here}/${img}/Dockerfile" "${here}"
done

echo
echo "Done. Images:"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' \
  | grep -E '^(noc-tools|syslog|dnsmasq|web|ntp|clab-frr|clab-host):lab' || true
