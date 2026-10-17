#!/usr/bin/env sh
# Shared entrypoint logic for the lab service images.
#
# Reads:
#   LAB_IP    required, "address/prefix"   e.g. 10.100.0.10/24
#   LAB_GW    optional, gateway address     e.g. 10.100.0.1
#   LAB_IFACE optional, interface to use    e.g. eth1
#
# In the GNS3 labs a docker node has a single interface, so the address simply
# went on the default-route interface. Under containerlab the first interface is
# the out-of-band management network, so the data interface has to be named -
# LAB_IFACE=eth1 - otherwise the address would land on eth0 and cut the lab off.
#
# Applies the address, sets the default route, then execs the service.
# Sourced, not executed: the calling entrypoint does `exec "$@"` itself.

apply_lab_address() {
  if [ -z "${LAB_IP:-}" ]; then
    echo "lab-entrypoint: LAB_IP not set, keeping container default addressing"
    return 0
  fi

  iface="${LAB_IFACE:-}"

  # Under containerlab the data interface may not exist yet when the container's
  # entrypoint runs: the veth is moved in shortly after. Waiting here is what
  # makes `LAB_IFACE=eth1` reliable instead of a race.
  if [ -n "$iface" ]; then
    waited=0
    while ! ip link show "$iface" >/dev/null 2>&1; do
      waited=$((waited + 1))
      if [ "$waited" -gt 60 ]; then
        echo "lab-entrypoint: $iface never appeared" >&2
        break
      fi
      sleep 1
    done
  fi

  if [ -z "$iface" ]; then
    iface=$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)
  fi

  if [ -z "$iface" ]; then
    iface=$(ip -o link show \
      | awk -F': ' '$2 != "lo" && $2 != "" {print $2; exit}')
  fi

  if [ -z "$iface" ]; then
    echo "lab-entrypoint: no usable interface found" >&2
    return 1
  fi

  ip addr flush dev "$iface" 2>/dev/null || true
  ip link set "$iface" up
  ip addr add "$LAB_IP" dev "$iface"
  echo "lab-entrypoint: $LAB_IP applied to $iface"

  if [ -n "${LAB_GW:-}" ]; then
    ip route replace default via "$LAB_GW"
    echo "lab-entrypoint: default route via $LAB_GW"
  fi
}
