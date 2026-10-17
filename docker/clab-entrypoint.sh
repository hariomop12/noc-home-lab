#!/bin/sh
# Shared boot hook for the containerlab lab nodes (routers, switches, hosts).
#
# containerlab wires the veth interfaces and then runs the kind's `exec` hook,
# which touches the marker file below. Waiting for it means the per-node setup
# script can create VLAN sub-interfaces on interfaces that already exist.
#
#   1. wait for the marker file
#   2. drop the management network's default route (it would shadow the lab's)
#   3. run /etc/lab/setup.sh if the node ships one
#   4. hand over to the image's real command
set -u

MARKER="${LAB_READY_MARKER:-/tmp/.lab-interfaces-ready}"
TIMEOUT="${LAB_WAIT_TIMEOUT:-90}"

waited=0
while [ ! -e "$MARKER" ] && [ "$waited" -lt "$TIMEOUT" ]; do
    sleep 1
    waited=$((waited + 1))
done
[ -e "$MARKER" ] || echo "lab-entrypoint: marker never appeared, continuing" >&2

# The containerlab management network installs a default route on eth0. The lab
# builds its own routing table, so that route is removed here. eth0 keeps its
# address: it is the out-of-band management path the NOC polls the devices on.
ip route del default dev eth0 2>/dev/null || true

if [ -f /etc/lab/setup.sh ]; then
    echo "lab-entrypoint: running /etc/lab/setup.sh"
    sh /etc/lab/setup.sh || echo "lab-entrypoint: setup.sh exited with $?" >&2
fi

exec "$@"
