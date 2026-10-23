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
        # Deliberately no `ip addr flush` here. busybox calls this whenever the
        # client process starts, and the client loop restarts every 20 s, so a
        # flush would drop a working address and its default route twenty times
        # a minute - and any outage of the DHCP server would leave every host on
        # the lab without an address, i.e. every ticket would become two faults.
        # A real client keeps its lease while it retries; the `bound` branch
        # below replaces the address when a new lease actually arrives.
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
