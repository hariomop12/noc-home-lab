---
tags: [homelab, ticket, incident, stp, broadcast-storm, layer2]
status: done
---

# T-04 — The whole office is crawling, the switch CPU is pegged

**Severity:** P1
**Reported:** "Everything in the office is slow — file shares, the web app,
printing. The switches are working hard, the LEDs are solid."
**Scope:** the entire site, every VLAN, both access switches. Two devices, not one
department.
**Lab:** containerlab `noclab`, sw1 ⇄ sw2 with two parallel uplinks (a real loop
that STP is there to break), pc1 in VLAN 10 → `srv-web` in VLAN 40
**Status:** closed

## Symptom

Latency and loss appear without any link going down:

```
$ ping -c8 pc1 -> srv-web (VLAN 10 -> VLAN 40)
8 packets transmitted, 8 received, +1 duplicates, 0% packet loss, time 2129ms
rtt min/avg/max/mdev = 0.062/0.082/0.134/0.027 ms
```

The telling detail is `+1 duplicates`: the network is delivering the *same
packet more than once*, which no healthy switching fabric does. The uplink
counters explain where the traffic is going:

```
$ ip -s link show eth4   (sw1's uplink towards sw2, two samples 3 s apart)
    1437377406 14133131      0    4967       0       0
    1503287975 15279889      0    5728       0       0
```

66 MB and 1.15 million packets crossed that one port in three seconds — about
**382,000 packets per second** of traffic on a link carrying one ping. Both
bridges are busy doing it (`loadavg 2.74`), and STP is no longer breaking the
loop:

```
$ stp_state, and the number of blocking ports (0 while STP is off)
0
  blocking ports: 0
```

## Impact

Every user in every VLAN: degraded throughput, unusable latency for anything
interactive, and duplicated packets that some applications handle badly. This is
the classic P1 that looks like "the network is slow" and is actually "one device
is amplifying traffic". With real users generating ARP, DHCP and Bonjour traffic,
the uplinks saturate and the impact goes from "sluggish" to "the site is down".

## Hypothesis

Written before investigating:

1. The uplinks are saturated by real load → *one ping does not saturate
   anything*, and the counters are climbing with almost no offered traffic.
2. A host is faulty and transmitting garbage → possible, but the counters climb
   on the *inter-switch* port, not on an access port.
3. A Layer 2 loop exists and the fabric is flooding frames around it → explains
   the counters, the duplicates and the CPU at once. **Most likely.**

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `ping` pc1 → srv-web | replies with `+1 duplicates`, sub-millisecond RTT | packets are arriving more than once |
| 2 | `ip -s link show eth4` on sw1, twice | 66 MB / 1.15 M packets in 3 s | the inter-switch link is carrying ~382 kpps |
| 3 | `cat /proc/loadavg` on sw1 and sw2 | `2.74 1.69 1.32` on both | both bridges are busy forwarding the loop |
| 4 | `cat /sys/class/net/br0/bridge/stp_state` | `0` | STP is disabled — the loop has no protection |
| 5 | count of blocking ports | `0` | no port is in blocking, so both uplinks forward |

## Root cause

One sentence: STP was disabled on both switches *and* the ports were bounced, so
both parallel uplinks came up forwarding, the loop was closed, and every flooded
frame — a broadcast or an unknown unicast — started circulating between the two
bridges at line rate for as long as the loop stayed closed.

Two details of this fault are the actual lesson:

- **Disabling STP does not un-block a port.** The port that STP had put in
  `blocking` keeps that state, and even `bridge link set dev eth4 state 3` does
  not move it. A technician who "turned STP off to fix a loop problem" sees the
  loop stay idle. What closes it is a down/up cycle on the ports: with STP gone,
  they skip listening and learning and go straight to forwarding.
- **A storm needs something to circulate.** A quiet lab has almost no broadcast
  traffic, so a single `ping` legitimately shows 0% loss while the counters scream.
  That is why the proof here is the counter and the duplicated packet, not the
  loss percentage: on a real network a few hundred users generate the broadcast
  traffic for you, and the same fault takes the site down.

## Fix

```bash
docker exec clab-noclab-sw1 ip link set br0 type bridge stp_state 1
docker exec clab-noclab-sw2 ip link set br0 type bridge stp_state 1
```

Re-enabling STP re-runs the election, which re-blocks one of the two uplinks by
itself. Nothing else needs undoing, precisely because the port bounce left no
state behind — a manually forced port state is what would have needed cleaning up.

## Verification

```
T-04 verified: traffic is healthy again
  blocking ports: 1 (STP is breaking the loop again)
$ ip -s link show eth4   (two samples 3 s apart)
    1593270895 16404837      0    6356       0       0
    1593277471 16404858      0    6356       0       0
```

The same port that carried 1.15 million packets in three seconds now carries 21 —
a factor of 55,000 — while one uplink is blocked and the other is forwarding. The
baseline's own STP checks (`stp-loop-broken`: "exactly one uplink is blocking")
assert the same thing on every deploy.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected | 08:59:40 |
| Evidence collected (storm live) | 08:59:47 |
| Fix applied | 08:59:52 |
| Verified | 08:59:57 |
| Total | 37 s (the verification waits for STP to converge) |

These are the runner's clock, not a human's: the script already knows which
checks to run. What the ticket scores is the order — counter before guess,
measurement before opinion — and that the fault, the evidence and the repair are
one repeatable sequence.

## Prevention

- **Monitoring alert that should have caught this:** the alert that matters is
  not "CPU high" (by the time the CPU is high, the site is already slow) but
  **broadcast/multicast rate per port** — a storm is a rate problem long before it
  is a CPU problem, and it is measurable with SNMP on any switch (`ifInBroadcastPkts`
  per second). A duplicate-packet or link-rate alarm on the inter-switch links
  would also have caught it. The Lab 09 NOC monitors interface *state* and CPU but
  not rates, which is the honest gap.
- **Config standard or baseline change:** `baseline.sh` asserts STP is on and
  exactly one uplink is blocking on every deploy (`stp-loop-broken`), so this
  fault cannot survive a health check — but a health check is run on demand, not
  continuously. On a real access layer the standard is also to *not* leave two
  parallel uplinks to the same pair of switches without a deliberate design
  (port-channel or a blocking design decision), because the failure mode is a
  single command away.
- **What would have made this obvious sooner:** reading the counters before
  believing the symptom. "Slow" plus "no link events" points at the forwarding
  plane, not at a device; `ip -s link show` on the uplink is two seconds of work
  and it names the fault. A storm is the one Layer 2 fault that is visible as a
  number rather than as a state.
