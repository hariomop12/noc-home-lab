#!/bin/sh
# -----------------------------------------------------------------------------
#  containerlab pre-entrypoint for the NOC containers (Phase 5).
#
#  The vendor Zabbix images run as uid 1997 and know nothing about the lab's
#  data interface. This wrapper runs first, as root, and does the two things
#  they cannot:
#
#    1. wait until containerlab has moved the data interface into this
#       container (the veth arrives a moment after start),
#    2. give that interface the lab address, then hand over to the vendor
#       entrypoint with the vendor CMD untouched.
#
#  Everything after the address is the unmodified upstream image behaviour.
# -----------------------------------------------------------------------------
set -u

iface="${LAB_IFACE:-eth1}"

if [ -n "${LAB_IP:-}" ]; then
    waited=0
    while ! ip link show "$iface" >/dev/null 2>&1; do
        waited=$((waited + 1))
        if [ "$waited" -gt 60 ]; then
            echo "noc-entrypoint: $iface never appeared" >&2
            break
        fi
        sleep 1
    done

    ip link set "$iface" up 2>/dev/null || true
    ip addr add "$LAB_IP" dev "$iface" 2>/dev/null || true
    if [ -n "${LAB_GW:-}" ]; then
        ip route replace default via "$LAB_GW" || true
    fi
    echo "noc-entrypoint: $LAB_IP on $iface"
fi

exec "${LAB_UPSTREAM:-/usr/bin/docker-entrypoint.sh}" "$@"
