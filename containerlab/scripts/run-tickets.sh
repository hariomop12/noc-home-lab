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
    # Single-ticket mode: `run-tickets.sh T-04` must match T-04-broadcast-storm.
    # A prefix compare, not `${id%%-*}`: that expands to "T" (the longest suffix
    # match is "-04-broadcast-storm"), so the filter matched nothing and the
    # script printed "all tickets verified" without running a single fault.
    if [ -n "$only" ] && [ "${id:0:${#only}}" != "$only" ]; then continue; fi

    out="$art/$id.txt"
    nodes=$(docker ps --format '{{.Names}}' | grep -c '^clab-noclab-')
    {
        # Every phase is stamped. The ticket write-ups quote these lines as their
        # timeline, so the numbers in docs/tickets/ are the runner's, not a
        # reconstruction after the fact.
        printf '### %s\n' "$id"
        printf '#   started %s\n' "$(date -Is)"
        printf '#   containerlab lab: noclab, %s nodes running\n\n' "$nodes"

        printf '# %s   fault injected\n' "$(date +%H:%M:%S)"
        printf '$ %s.sh inject\n' "$id"
        bash "$f" inject

        sleep "$settle"

        printf '\n# %s   evidence collected (fault live)\n' "$(date +%H:%M:%S)"
        printf '$ %s.sh evidence\n' "$id"
        bash "$f" evidence

        printf '\n# %s   fix applied\n' "$(date +%H:%M:%S)"
        printf '$ %s.sh fix\n' "$id"
        bash "$f" fix
        sleep 4

        printf '\n# %s   verification\n' "$(date +%H:%M:%S)"
        printf '$ %s.sh verify\n' "$id"
        bash "$f" verify
        printf '\n# %s   done\n' "$(date +%H:%M:%S)"
    } >"$out" 2>&1

    # The verdict is the ticket script's own last word about the fix, not the
    # file's last line - the transcript now ends with a "done" timestamp, and a
    # tail -1 verdict would have reported every failure as a pass.
    verdict=$(grep -E '^T-[0-9]+ (verified.*|STILL BROKEN)' "$out" | tail -1)
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
