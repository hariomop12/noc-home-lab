#!/usr/bin/env bash
# =============================================================================
#  Shared helpers for the ticket fault scripts (Phase 4).
#
#  Every ticket is one file with four subcommands:
#
#      ./faults/T-01-no-internet.sh inject     break it
#      ./faults/T-01-no-internet.sh evidence   collect what a NOC engineer would
#      ./faults/T-01-no-internet.sh fix        put it back
#      ./faults/T-01-no-internet.sh verify     prove it is back
#
#  Nothing here is mocked: the fault is applied to the live containerlab lab and
#  the evidence is the real output of real commands.
# =============================================================================
set -u

PREFIX="clab-noclab"

x()   { docker exec "$PREFIX-$1" "${@:2}"; }
vty() { docker exec "$PREFIX-$1" vtysh -c "$2"; }

need_lab() {
    docker ps --format '{{.Names}}' | grep -q "^${PREFIX}-r1$" || {
        echo "lab is not deployed: sudo containerlab deploy -t topology.clab.yml"
        exit 2
    }
}

hr()   { printf '\n---- %s ----\n' "$*"; }
step() { printf '$ %s\n' "$*"; }

# ping with a one-line verdict
ping1() {
    if x "$1" ping -c2 -W2 -q "$2" >/dev/null 2>&1; then
        echo "ping $2 from $1 : ok"
    else
        echo "ping $2 from $1 : FAILED"
    fi
}

# the DHCP lease a host is currently using
pc_ip() { x "$1" ip -4 addr show eth1 | awk '/inet /{sub(/\/.*/,"",$2); print $2}'; }

# The user hosts renew in a loop, and a renewal can flush the interface. A fault
# that depends on a host *having* an address must therefore check instead of
# assume - otherwise the ticket measures two faults at once and proves nothing.
need_lease() {
    local host="$1" i=0
    while [ "$i" -lt 15 ]; do
        [ -n "$(pc_ip "$host")" ] && return 0
        x "$host" sh -c 'udhcpc -i eth1 -f -q -n -t 3 -T 2 -s /etc/lab/udhcpc-script.sh >/dev/null 2>&1' || true
        sleep 2
        i=$((i + 1))
    done
    echo "  !! $host still has no lease - fault would be confounded" >&2
    return 1
}

# Stop / restart a host's DHCP client loop. Needed whenever a fault would be
# healed by the next renewal (a new address would overwrite the injected state).
dhcp_loop_stop() {
    # Three processes matter: the loop the container started itself, the loop a
    # fault script may have started, and any `udhcpc` currently in flight.
    #
    #   * The container's own loop is a `( ... ) &` subshell of
    #     /etc/lab/setup.sh, so its command line is the inherited one - it is
    #     matched by the anchored pattern.
    #   * A loop started by a fault script runs `nohup sh -c "while :; do
    #     udhcpc ..."`, so its command line contains that text. The pattern for
    #     it is written with a character class (`whil[e]`) so that the *shell
    #     running this kill* does not match its own command line: a plain
    #     `pkill -f "while :; do udhcpc"` shoots itself before it kills anything,
    #     which is exactly how T-02's repair once failed to restart a client and
    #     T-09's and T-10's faults looked self-healing.
    #   * Killing the loop does not kill the client it started, so `udhcpc` is
    #     killed by name as well.
    x "$1" sh -c 'pkill -f "^sh /etc/lab/setup.sh$" 2>/dev/null
                 pkill -f "whil[e] :; do udhcpc" 2>/dev/null
                 pkill udhcpc 2>/dev/null
                 true'
}

dhcp_loop_start() {
    # Stop first, so a start cannot end up with two loops fighting over the lease.
    dhcp_loop_stop "$1"
    x "$1" sh -c 'sleep 1
                 nohup sh -c "while :; do udhcpc -i eth1 -f -q -n -t 5 -T 3 -s /etc/lab/udhcpc-script.sh >> /var/log/dhcp.log 2>&1; sleep 20; done" >/dev/null 2>&1 &
                 echo $! > /tmp/dhcp-loop.pid'
}

# wait up to N seconds for a condition
wait_for() {
    local secs="$1"; shift
    local i=0
    while [ "$i" -lt "$secs" ]; do
        if "$@" >/dev/null 2>&1; then return 0; fi
        sleep 2
        i=$((i + 2))
    done
    return 1
}

usage() { echo "usage: $0 {inject|evidence|fix|verify}"; exit 1; }

# Capture what a link actually carries for one flow, and print the source
# addresses. Evidence that "the packet left with the wrong source" cannot be
# faked by a ping, which is why faults about translation use this.
capture_src() {
    local node="$1" iface="$2" target="$3"
    local tmp=/tmp/capture-src.$$
    ( x "$node" sh -c "timeout 8 tcpdump -n -i $iface -c 4 icmp and host $target" >"$tmp" 2>&1 ) &
    local pid=$!
    sleep 2
    x pc1 ping -c3 -q -W2 "$target" >/dev/null 2>&1
    wait "$pid" 2>/dev/null
    grep -E '^[0-9:.]+ IP ' "$tmp" | sed 's/^[0-9:.]* //' | head -4
    rm -f "$tmp"
}
