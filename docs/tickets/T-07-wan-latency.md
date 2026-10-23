---
tags: [homelab, ticket, incident, wan, latency, tc, netem]
status: done
---

# T-07 — High latency and loss on the WAN link

**Severity:** P2
**Reported:** "The internet is slow and video calls break up, but everything
inside the building is fine."
**Scope:** every internet-bound flow through HQ's WAN link. Internal traffic
(PC → server) is untouched.
**Lab:** containerlab `noclab`, `r1 eth1` WAN to the simulated ISP
**Status:** closed

## Symptom

From a VLAN 10 PC, the internet server is ~300 ms away while the internal server
next to it answers instantly — same client, same second:

```
$ ping -c5 pc1 -> internet server 200.1.1.10
5 packets transmitted, 5 received, 0% packet loss, time 4002ms
rtt min/avg/max/mdev = 290.800/301.250/309.788/7.792 ms

$ ping -c5 pc1 -> internal server 10.100.0.12
5 packets transmitted, 5 received, 0% packet loss, time 4130ms
rtt min/avg/max/mdev = 0.082/0.107/0.153/0.029 ms
```

The five-packet sample above happens to be lossless even though the fault is a 10%
drop — five packets is a small sample, and a *shaper* does not drop on schedule.
The shaper's own counter is the honest place to read the loss, and it says the
packets are being dropped:

```
$ tc -s qdisc show dev eth1   (on r1)
qdisc netem 8004: root refcnt 13 limit 1000 delay 300ms  20ms loss 10% seed ...
 Sent 1357 bytes 15 pkt (dropped 2, overlimits 0 requeues 0)
```

`traceroute` puts the damage on one specific hop:

```
 1  10.10.10.1  0.064 ms          <- r1 (the gateway) is instantaneous
 2  10.0.0.14  312.533 ms         <- the ISP edge is where the 300 ms appears
 3  *
 4  *
```

## Verification

```
T-07 verified: internet is healthy again
rtt min/avg/max/mdev = 0.094/0.164/0.207/0.049 ms
```

The same command that showed 301 ms now shows 0.16 ms, from the same client to the
same destination.

## Impact

~300 ms added to every internet round trip plus 10% packet loss at the shaper.
Anything latency-sensitive (voice, video, interactive sessions) is unusable; file
transfers quietly drop to a fraction of their speed. The intranet and the branch
are unaffected, so most monitoring (which polls inside the lab) shows green.

## Hypothesis

Written before investigating:

1. The internal server is also affected → *no, the same-second ping is clean*, so
   the fault is on the path that the two flows do not share.
2. The ISP is overloaded → possible, but a lab ISP is idle; a *deliberately*
   shaped link is more likely than a busy one.
3. Something is intentionally shaping the WAN interface (queueing discipline) →
   test with `tc qdisc show`, which is one command.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `ping 200.1.1.10` vs `ping 10.100.0.12` from pc1 | 301 ms vs 0.11 ms, both lossless | the fault is on the internet path only |
| 2 | `traceroute 200.1.1.10` from pc1 | 0.06 ms to r1, 312 ms to the ISP | the delay is added at the first WAN hop |
| 3 | `tc -s qdisc show dev eth1` on r1 | `netem ... delay 300ms 20ms loss 10%`, `dropped 2` | the shaper is on r1's own WAN interface, and it is dropping |

## Root cause

One sentence: a `netem` queueing discipline with `delay 300ms 20ms loss 10%` was
attached to r1's WAN interface, so r1 itself was adding the delay and dropping one
packet in ten on egress — the ISP and the internal network were never involved.

In a container lab a WAN link has no serial line to degrade, so `tc netem` *is*
the physical fault: it produces exactly what a congested or erroring WAN produces
(delay, jitter, loss), and it is measurable from both ends.

## Fix

```bash
docker exec clab-noclab-r1 tc qdisc del dev eth1 root
```

Removing the qdisc removes the added delay and loss. The alternative fix — moving
traffic to a different WAN — would have hidden the symptom without removing the
cause, and would have broken again on the way back.

## Verification

```
T-07 verified: internet is healthy again
rtt min/avg/max/mdev = 0.130/0.153/0.165/0.016 ms
```

The same command that showed 302 ms now shows 0.15 ms, from the same client, with
the same destination.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (300 ms ± 20 ms delay, 10% loss on r1's WAN) | 09:01:31 |
| Evidence collected (internet vs intranet ping, qdisc, traceroute) | 09:01:37 |
| Fix applied (qdisc removed) | 09:01:47 |
| Verified (internet RTT back to normal) | 09:01:51 |
| Total | 25 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — compare the failing path with a
healthy one, then follow the damage hop by hop.

## Prevention

- **Monitoring alert that should have caught this:** this is close to the one
  fault the Lab 09 NOC *does* catch by design — it polls the ISP (`10.0.0.14`)
  with `icmppingloss` and `icmppingsec`, so the round-trip-time graph shows the
  step immediately and the loss trigger fires above 40%. The honest gap: 10% loss
  at 300 ms sits *below* that trigger, so this specific shape would appear as a
  visible RTT increase long before any alarm. A latency trigger ("RTT above twice
  the 7-day baseline") is the missing piece.
- **Config standard or baseline change:** no device configuration is involved —
  `tc` state is invisible to a config diff, which is exactly why a monitoring
  system, and not a backup system, is what catches it. Add "WAN RTT is within
  X ms of baseline" to the NOC's checks.
- **What would have made this obvious sooner:** the internal-versus-external ping
  pair. One command pair splits the whole diagram in two — "who shares this path
  with the broken flow, and who does not" — before any device is opened.
