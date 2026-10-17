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
