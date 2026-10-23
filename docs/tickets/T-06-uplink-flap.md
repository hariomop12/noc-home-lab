---
tags: [homelab, ticket, incident, layer2, stp, flapping, uplink]
status: done
---

# T-06 — The network drops out for a few seconds, over and over

**Severity:** P2
**Reported:** "The connection keeps dying — it comes back, then it's gone again.
It's been like this all morning."
**Scope:** the hosts on one access switch (VLAN 10 and VLAN 30 on sw1). The other
switch and the branch site are unaffected.
**Lab:** containerlab `noclab`, sw1 `eth1` ⇄ r1 `eth2` (the trunk uplink)
**Status:** closed

## Symptom

A ping that never finishes, and no link alarm anywhere:

```
$ ping -c20 -i 1 pc1 -> srv-web   (20 s, so the 3 s down / 4 s up cycle bites)
20 packets transmitted, 0 received, 100% packet loss, time 19441ms
```

From the users' side this is indistinguishable from a dead link. What separates a
flapping link from a broken one is the port's own history, sampled once a second:

```
$ cat /sys/class/net/eth1/operstate   (sw1, ten samples a second apart)
up down down down up up up up down down
```

The counters at the moment of a down sample, and the port's STP view:

```
$ ip -s link show eth1   (sw1, uplink to r1)
109: eth1@if108: <BROADCAST,MULTICAST> mtu 9500 qdisc noqueue master br0 state DOWN
     260298388  1844422      0      20       0       0
$ bridge -d link show eth1
109: eth1@if108: <BROADCAST,MULTICAST> mtu 9500 master br0 state disabled priority 32 cost 2
```

## Impact

Every host behind that switch loses connectivity for three seconds in every
seven — long enough to break SSH sessions, fail health checks and time out HTTP
requests, short enough to look "intermittent" to the people reporting it. The
other switch keeps working, which is why this reads as a host or Wi-Fi problem
rather than a link problem.

## Hypothesis

Written before investigating:

1. The uplink is dead → *a dead link does not come back on its own*, and the ping
   would fail once and stay failed.
2. One host is producing the loss → the ping runs from pc1, but the same loss hits
   every host on sw1, so it is not a host.
3. The uplink is physically unstable (cable, SFP, or a port being reconfigured by
   something) or being flapped by software → **most likely**, because the loss is
   periodic and the port cannot be pinged during the down windows.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `ping -c20 -i 1` pc1 → srv-web | 100% loss over 19.4 s | connectivity is not stable |
| 2 | `cat /sys/class/net/eth1/operstate` on sw1, 10 samples | `up down down down up up up up down down` | the port is flapping on a repeating cycle |
| 3 | `ip -s link show eth1` on sw1 | port `state DOWN` in the sample, `dropped 20` | the port really is going down |
| 4 | `bridge -d link show eth1` | `state disabled` (STP view of a down port) | the forwarding path is gone while down |
| 5 | same ping after the flap stops | 10/10, 0% loss | the link itself is healthy |

## Root cause

One sentence: a process on sw1 was flipping the uplink down for three seconds and
up for four (a "flap loop"), which makes the port unusable even while it appears
to be up — because every time it comes back, STP restarts its listening and
learning timers (~30 s of forward delay), so it never reaches forwarding inside a
four-second window.

That second half is the part that surprises people: **a flapping link behaves like
a dead link**, not like a link with partial loss. The users' symptom ("it comes
back and goes again") and the *measured* symptom (100% loss) disagree unless you
know that STP has to reconverge on every re-up.

## Fix

```bash
# stop the flapping process, then bring the port up and let STP converge
docker exec clab-noclab-sw1 sh -c 'kill "$(cat /tmp/flap.pid)"; ip link set eth1 up'
```

Stopping the flap is the fix; the port itself needed nothing. That distinction
matters in a real incident: the same symptom is caused by a bad cable, a failing
SFP, a duplex mismatch or a misconfigured port-security action, and the first
diagnostic step is not to replace hardware but to find out **whether the link state
is changing** — a state that has a history, unlike a cable.

## Verification

```
$ ping -c10 pc1 -> srv-web
10 packets transmitted, 10 received, 0% packet loss, time 9246ms
rtt min/avg/max/mdev = 0.089/0.144/0.322/0.066 ms
T-06 verified: no loss over 10 packets
```

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (flap loop starts) | 09:00:31 |
| Evidence collected (fault live) | 09:00:37 |
| Fix applied (loop stopped) | 09:01:09 |
| Verified | 09:01:13 |
| Total | 60 s, most of it the 20-second ping and the ten one-second samples |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — measure the *state over time* before
touching hardware.

## Prevention

- **Monitoring alert that should have caught this:** link-state change detection
  with a flap counter — "this port changed state more than N times in ten
  minutes". The Lab 09 NOC has an "interface down" trigger per port discovered by
  low-level discovery, but it polls every 60 seconds, and a port that is up for
  four seconds at a time can easily look *up* at every poll: this fault would have
  stayed invisible. A real switch solves it with SNMP linkUp/linkDown **traps**
  (not polling) plus what its OS logs. That is a named gap, not a solved problem.
- **Config standard or baseline change:** `baseline.sh` asserts the trunk is up
  and STP is consistent on every deploy, and the guides' verification tables
  include an interface counter check. Neither can see a *runtime* flap, which is
  exactly why the monitor needs traps.
- **What would have made this obvious sooner:** sampling a value over time instead
  of once. One `cat .../operstate` said "up"; ten of them, a second apart, showed
  the cycle and named the fault. The same trick works for CPU (poll twice),
  latency (ping for 20 seconds) and counters (read a delta, not an absolute).
- **The honest gap in this artifact:** the syslog collector has nothing to offer.
  A Linux bridge does not write a line when a port goes down, so the collector is
  silent; on a switch whose OS logs `%LINK-3-UPDOWN` (or a router logging its own
  adjacency churn) this ticket would quote that line as its written record. Where
  no device writes the event, the sampled state *is* the record.
