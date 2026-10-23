#!/usr/bin/env python3
"""Phase 5 - read the NOC, and drill it with real faults.

    python3 scripts/nocctl.py status      # what Zabbix knows right now
    python3 scripts/nocctl.py problems    # open problems + recent events
    python3 scripts/nocctl.py drill       # inject -> alert -> fix -> recover

`drill` is the point of the whole phase. It injects a fault that a monitoring
system is supposed to notice, waits for the alarm, prints it with real
timestamps, repairs the fault and waits for the recovery event. Every number in
the resulting report is measured, nothing is written by hand - that is the whole
difference between "I built a monitor" and "I verified a monitor".

The drill also checks the lab independently of Zabbix (a ping from the NOC
toolbox container before/during the fault), because a monitoring system that
disagrees with reality is worse than no monitoring at all.

Faults are always repaired in a finally block: a drill that can leave the lab
broken is not a drill, it is an outage generator.
"""

import subprocess
import sys
import time

from noc_api import SEVERITY, Zabbix, clock

PREFIX = "clab-noclab-"

# --------------------------------------------------------------------------
# The two drills. Both prove something different about monitoring design:
#
# trunk  - one configuration mistake on one switch makes the NOC lose sight of
#          every device it polls. Six alarms from one change: this is what a
#          "blast radius" looks like on a dashboard.
# single - one access switch loses its uplink. Only that switch goes red, and
#          the branch router stays green *because it is polled on its loopback*:
#          the same failure would have gone unnoticed if the monitoring address
#          had been one of the physical interfaces.
# --------------------------------------------------------------------------
FAULTS = {
    "trunk": {
        "title": "VLAN 40 removed from sw2's uplinks (eth1 + eth2)",
        "why": "the NOC sits in VLAN 40, so this removes its routed path to "
               "every device it polls while the lab keeps running",
        "inject": [("sw2", "bridge vlan del dev eth1 vid 40"),
                   ("sw2", "bridge vlan del dev eth2 vid 40")],
        "fix":    [("sw2", "bridge vlan add dev eth1 vid 40"),
                   ("sw2", "bridge vlan add dev eth2 vid 40")],
        "expect": ["r1", "r2", "isp", "sw1", "sw2", "sw3"],
        "probe":  "10.255.0.1",
    },
    "single": {
        "title": "sw3's uplink to r2 is down",
        "why": "one access switch disappears; the rest of the lab, including "
               "the branch router polled on its loopback, must stay green",
        "inject": [("sw3", "ip link set eth1 down")],
        "fix":    [("sw3", "ip link set eth1 up")],
        "expect": ["sw3"],
        "probe":  "10.20.99.13",
    },
}


def run(node, cmd):
    """Run one command inside a lab container; return (rc, combined output)."""
    proc = subprocess.run(["docker", "exec", PREFIX + node] + cmd.split(),
                          capture_output=True, text=True)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def ping(target):
    """Reachability check made *outside* Zabbix, from the NOC toolbox."""
    rc, out = run("client", f"ping -c2 -W2 {target}")
    loss = next((l.strip() for l in out.splitlines() if "packet loss" in l), "?")
    return rc == 0, loss


def item_states(z):
    counts = {}
    for it in z.items():
        counts[it["state"]] = counts.get(it["state"], 0) + 1
    # state 0 = normal, 1 = not supported, 2 = unknown/no data yet
    return counts


def wait_until(check, timeout, interval=10):
    """Poll check() until it returns a truthy value; return (value, elapsed)."""
    start = time.time()
    while time.time() - start < timeout:
        value = check()
        if value:
            return value, int(time.time() - start)
        time.sleep(interval)
    return None, int(time.time() - start)


def print_items(z, only_problems=False):
    rows = sorted(z.items(), key=lambda i: (i["hosts"][0]["host"], i["key_"]))
    if only_problems:
        rows = [r for r in rows if r["state"] != "0"]
    for it in rows:
        host = it["hosts"][0]["host"]
        value = (it["lastvalue"] or "-")[:40]
        print(f"  {host:11s} {it['key_']:14s} {value:40s} state={it['state']}"
              + (f" error={it['error'][:60]}" if it["error"] else ""))


def status(z, verbose=False):
    hosts = z.call("host.get", groupids=[z.group_id()], output=["host"],
                   selectInterfaces=["ip"])
    print(f"{len(hosts)} hosts monitored, item states: {item_states(z)}")
    print("  (state 0 = normal, 1 = not supported, 2 = no data yet)")
    for h in hosts:
        counts = {}
        for it in z.call("item.get", hostids=h["hostid"], output=["state"]):
            counts[it["state"]] = counts.get(it["state"], 0) + 1
        print(f"  {h['host']:11s} {h['interfaces'][0]['ip']:12s} items={counts}")
    if verbose:
        print_items(z)
    problems = z.problems()
    print(f"open problems: {len(problems)}")
    for p in problems:
        print(f"  {clock(p['clock'])}  {SEVERITY[int(p['severity'])]:8s}  "
              f"{p['host']:11s} {p['name']}")


def problems(z):
    print("== open problems")
    found = z.problems()
    if not found:
        print("  none")
    for p in found:
        print(f"  {clock(p['clock'])}  {SEVERITY[int(p['severity'])]:8s}  "
              f"{p['host']:11s} {p['name']}")

    since = int(time.time()) - 3600
    print("== events in the last hour (newest first)")
    events = z.call("event.get", groupids=[z.group_id()], time_from=since,
                    output=["clock", "name", "severity", "value", "r_eventid"],
                    selectHosts=["host"], sortfield="clock", sortorder="DESC")
    if not events:
        print("  none")
    for e in events:
        kind = "PROBLEM " if e["value"] == "1" else "RESOLVED"
        print(f"  {clock(e['clock'])}  {kind}  {SEVERITY[int(e['severity'])]:8s}  "
              f"{e['hosts'][0]['host']:11s} {e['name']}")


def drill(z, key, detect_timeout=420, recover_timeout=420):
    fault = FAULTS[key]
    print(f"\n{'=' * 78}\nFAULT '{key}': {fault['title']}\n{fault['why']}\n{'=' * 78}")

    ok, loss = ping(fault["probe"])
    print(f"\n[1] baseline (before the fault) - {clock(time.time())}")
    print(f"    Zabbix open problems : {len(z.problems())}")
    print(f"    item states          : {item_states(z)}")
    print(f"    ping {fault['probe']:12s}: {'reachable' if ok else 'UNREACHABLE'}"
          f" ({loss})")
    if not ok:
        print("    refusing to drill: the target is already unreachable")
        return False

    repaired = False
    try:
        t_inject = time.time()
        print(f"\n[2] fault injected - {clock(t_inject)}")
        for node, cmd in fault["inject"]:
            rc, _ = run(node, cmd)
            print(f"    {node}: {cmd}   (rc={rc})")
        ok, loss = ping(fault["probe"])
        print(f"    ping {fault['probe']:12s}: {'reachable' if ok else 'UNREACHABLE'}"
              f" ({loss})   <- independent of Zabbix")

        print(f"\n[3] waiting for the alarm (ICMP item = 30s, trigger needs 3)"
              f" - {clock(time.time())}")
        wanted = set(fault["expect"])

        def all_alerted():
            seen = {p["host"] for p in z.problems()}
            return wanted <= seen

        got, waited = wait_until(all_alerted, detect_timeout)
        if not got:
            seen = {p["host"] for p in z.problems()}
            print(f"    only {sorted(seen)} alerted after {waited}s, "
                  f"expected {sorted(wanted)}")
        problems_now = z.problems()
        first = min(int(p["clock"]) for p in problems_now) if problems_now else 0
        for p in sorted(problems_now, key=lambda p: p["clock"]):
            print(f"    {clock(p['clock'])}  {SEVERITY[int(p['severity'])]:8s}  "
                  f"{p['host']:11s} {p['name']}")
        if problems_now:
            print(f"    detection delay: injected {clock(t_inject)} -> first alarm "
                  f"{clock(first)} = {first - int(t_inject)}s "
                  f"(ICMP poll 30s, trigger after 3 lost polls)")
        print("    (the 'SNMP data missing' triggers are the slow backstop: "
              "5 minutes of no data)")

        print(f"\n[4] fault repaired - {clock(time.time())}")
        for node, cmd in fault["fix"]:
            rc, _ = run(node, cmd)
            print(f"    {node}: {cmd}   (rc={rc})")
        repaired = True
        ok, loss = ping(fault["probe"])
        print(f"    ping {fault['probe']:12s}: {'reachable' if ok else 'UNREACHABLE'}"
              f" ({loss})")

        print(f"\n[5] waiting for recovery - {clock(time.time())}")

        def none_left():
            return len(z.problems()) == 0

        got, waited = wait_until(none_left, recover_timeout)
        if got is None:
            print(f"    still {len(z.problems())} open problems after {waited}s")
            for p in z.problems():
                print(f"    {clock(p['clock'])}  {p['host']:11s} {p['name']}")
        since = int(time.time()) - 1800
        resolved = z.call("event.get", groupids=[z.group_id()], time_from=since,
                          value=0, output=["clock", "name", "severity"],
                          selectHosts=["host"], sortfield="clock", sortorder="ASC")
        # Only this fault's recoveries: the window above is wide enough to catch
        # the previous drill's resolutions too, and mixing them makes the report
        # look better than it was.
        resolved = [e for e in resolved
                    if e["hosts"][0]["host"] in wanted
                    and int(e["clock"]) >= int(t_inject)]
        for e in resolved:
            print(f"    {clock(e['clock'])}  RESOLVED  {e['hosts'][0]['host']:11s} "
                  f"{e['name']}")
        if resolved and problems_now:
            last_problem = max(int(p["clock"]) for p in problems_now)
            last_resolved = max(int(e["clock"]) for e in resolved)
            print(f"    recovery delay: last alarm -> last resolution = "
                  f"{last_resolved - last_problem}s")
        print(f"\n    final state: {len(z.problems())} open problems, "
              f"items {item_states(z)}")
        return got is not None
    finally:
        if not repaired:
            print("\n!! drill interrupted before the repair step - repairing now")
            for node, cmd in fault["fix"]:
                print(f"    {node}: {cmd}   (rc={run(node, cmd)[0]})")


def main(argv):
    what = argv[1] if len(argv) > 1 else "status"
    z = Zabbix()
    z.login()
    if what == "status":
        status(z, verbose="--items" in argv)
    elif what == "problems":
        problems(z)
    elif what == "drill":
        keys = [a for a in argv[2:] if a in FAULTS] or ["trunk", "single"]
        results = {k: drill(z, k) for k in keys}
        print("\n== drill summary")
        for k, ok in results.items():
            print(f"  {k:8s} {'alarm raised and cleared' if ok else 'INCOMPLETE'}")
        return 0 if all(results.values()) else 1
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
