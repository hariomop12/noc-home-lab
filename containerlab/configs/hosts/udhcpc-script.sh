#!/bin/sh
# udhcpc lease handler, shared by every DHCP client in the lab.
#
# busybox udhcpc calls this with `deconfig`, `bound`, `renew` or `leasefail`
# and exports the lease in the environment. Applying it with iproute2 keeps the
# result visible to `ip addr` and `ip route`, which is what the ticket labs
# inspect.
set -u

LOG=/var/log/dhcp.log
mkdir -p /var/lib/lab

case "$1" in
    deconfig)
        ip addr flush dev "$interface" 2>/dev/null || true
        echo "$(hostname): lease released on $interface" >> "$LOG"
        ;;
    bound|renew)
        ip addr flush dev "$interface" 2>/dev/null || true
        ip addr add "$ip/$mask" dev "$interface"
        for r in $router; do
            ip route replace default via "$r"
        done
        if [ -n "${dns:-}" ]; then
            printf 'nameserver %s\n' $dns > /etc/resolv.conf
        fi
        echo "$(hostname): lease $ip/$mask via $router dns ${dns:-none} domain ${domain:-none}" >> "$LOG"
        ;;
    leasefail|nak)
        echo "$(hostname): no lease ($1) on $interface" >> "$LOG"
        ;;
esac
