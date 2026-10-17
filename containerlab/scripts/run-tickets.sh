#!/usr/bin/env bash
# =============================================================================
#  run-tickets.sh - run every Phase 4 fault end to end.
#
#  For each ticket: inject the fault, collect the evidence a NOC engineer would
#  collect, apply the fix, verify the fix, and save the whole terminal session
#  as an artifact. The ticket documents quote these artifacts, so nothing in
#  docs/tickets/ is retyped by hand from memory.
#
#    ./scripts/run-tickets.sh          # all ten
#    ./scripts/run-tickets.sh T-04     # one of them
#
#  SETTLE=<seconds> controls how long a fault is left to bite before the
#  evidence is collected (default 6).
# =============================================================================
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$here")
art="$root/artifacts"
mkdir -p "$art"

only="${1:-}"
settle="${SETTLE:-6}"
fail=0

for f in "$root"/faults/T-*.sh; do
    id=$(basename "$f" .sh)
    if [ -n "$only" ] && [ "${id%%-*}" != "$only" ]; then continue; fi

    out="$art/$id.txt"
    {
        printf '### %s\n' "$id"
        printf '#   %s\n' "$(date -Is)"
        printf '#   containerlab lab: noclab, 18 nodes\n\n'

        printf '$ %s.sh inject\n' "$id"
        bash "$f" inject

        sleep "$settle"

        printf '\n$ %s.sh evidence\n' "$id"
        bash "$f" evidence

        printf '\n$ %s.sh fix\n' "$id"
        bash "$f" fix
        sleep 4

        printf '\n$ %s.sh verify\n' "$id"
        bash "$f" verify
    } >"$out" 2>&1

    verdict=$(tail -1 "$out")
    if printf '%s' "$verdict" | grep -qi 'still broken'; then
        fail=$((fail + 1))
        printf '%-32s %sFAIL%s  %s\n' "$id" $'\033[31m' $'\033[0m' "$verdict"
    else
        printf '%-32s %sok%s    %s\n' "$id" $'\033[32m' $'\033[0m' "$verdict"
    fi
    printf '    artifact: %s\n' "${out#"$root"/}"
done

echo
if [ "$fail" -eq 0 ]; then
    echo "all tickets: fault injected, diagnosed, fixed and verified"
else
    echo "$fail ticket(s) did not verify - read the artifact"
    exit 1
fi
