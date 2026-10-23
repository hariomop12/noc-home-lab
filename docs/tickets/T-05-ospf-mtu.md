---
tags: [homelab, ticket, incident, ospf, mtu, wan]
status: done
---

# T-05 — OSPF neighbour stuck in EXSTART

**Severity:** P2
**Reported:** "r1's WAN neighbour has been in EXSTART for five minutes. The
internet still works, but our traffic to the ISP is going the long way round."
**Scope:** HQ edge (r1) and its WAN link to the ISP. The branch (r2) is
unaffected — it has its own WAN link and its own adjacency.
**Lab:** containerlab `noclab`, `r1 eth1` ⇄ `isp eth1` (`10.0.0.12/30`)
**Status:** closed

## Symptom

`show ip ospf neighbor` on r1 shows the ISP adjacency never leaving the database
exchange:

```
Neighbor ID     Pri State           Up Time         Dead Time Address         Interface
100.64.0.1        1 ExStart/DR      8.192s            31.806s 10.0.0.14       eth1:10.0.0.13
10.255.0.2        1 Full/-          52m08s            31.807s 10.0.0.2        eth3:10.0.0.1
```

The intranet is fine, the internet still answers, and the *other* adjacency (the
HQ↔BR1 transit) is `Full`. Only the WAN neighbour is stuck.

## Impact

No HQ subnet lost connectivity, because OSPF fell back to the default route it
learns over the transit from r2 — `default nhid 36 via 10.0.0.2 dev eth3` — so HQ
internet traffic now crosses the branch and leaves through BR1's WAN. In the GNS3
Lab 07 build the same fault was measured as "HQ silently moved to the two-hop ISP
path". Users see nothing; an engineer sees a link that is up but not routing, a
slower path for every internet-bound flow, and a single point of failure (if r2's
WAN also fails, HQ is offline).

## Hypothesis

Written before investigating:

1. The WAN interface is down or has an addressing error → *but the neighbour
   appears in the table, so OSPF hellos are being received*.
2. OSPF authentication or area mismatch → would show a log line, and hellos would
   be rejected rather than half-accepted.
3. The link can carry small packets but not the large Database Description
   packets → an MTU mismatch. **Most likely**, because `ExStart` is exactly where
   the two routers negotiate the initial DBD exchange.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `show ip ospf neighbor` (r1) | WAN neighbour `ExStart/DR`, transit `Full` | hellos arrive; the exchange does not complete |
| 2 | `ip link show eth1` (r1 vs isp) | `mtu 1400` on r1, `mtu 9500` on isp | the mismatch |
| 3 | `show ip ospf interface eth1` (r1) | `MTU 1400 bytes`, `MTU mismatch detection: enabled` | FRR refuses to go past ExStart |
| 4 | `ip route \| grep default` (r1) | `via 10.0.0.2 dev eth3` (the transit) | the default route failed over, which is why nobody noticed |
| 5 | `ping 200.1.1.10` from pc1 and pc5 | both succeed | confirms the fallback path, not the fault |

## Root cause

One sentence: r1's WAN interface was set to a **1400-byte MTU** while the ISP end
stayed at the lab-wide 9500, and OSPF's MTU-mismatch detection refuses to finish
the database exchange, so the adjacency never becomes `Full` and the default route
that OSPF would have learned from that neighbour is never installed.

## Fix

```bash
docker exec clab-noclab-r1 ip link set eth1 mtu 9500
```

The MTU is restored to the lab standard rather than lowering the ISP's side: an
MTU is a property of a link, and both ends have to agree. Which value is correct
depends on what the link has to carry — here, OSPF's DBD packets plus the
jumbo-friendly lab fabric, so 9500 stays the standard and 1400 was the anomaly.
(Lowering *both* ends to 1400 would also produce a `Full` adjacency and would be
the right answer if the WAN really had a 1400-byte path — this is why the fix is
"restore the standard", not "make the numbers equal".)

## Verification

```
T-05 verified: OSPF is Full again and r1 has its default route back
```

`show ip ospf neighbor` on r1 was checked again afterwards: the WAN adjacency is
`Full`, and the default route is back to the one-hop path through the ISP instead
of `via 10.0.0.2` (the transit).

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (`ip link set eth1 mtu 1400` on r1) | 09:00:17 |
| Evidence collected (neighbour state, both MTUs, route, user pings) | 09:00:23 |
| Fix applied (MTU restored to 9500) | 09:00:26 |
| Verified (adjacency Full, default route back) | 09:00:31 |
| Total | 14 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — read the state name literally first,
then compare the two ends of one link.

## Prevention

- **Monitoring alert that should have caught this:** an OSPF adjacency trigger —
  "neighbour count on this interface < expected" or "adjacency not Full for 5
  minutes". The Lab 09 NOC does not have it yet; the relevant OIDs are standard
  (`OSPF-MIB::ospfNbrState`, `1.3.6.1.2.1.14.10.1.6`), which is why this ticket
  is written up as a gap rather than as a solved problem.
- **Config standard or baseline change:** `scripts/baseline.sh` asserts both
  adjacencies are `Full` on a deploy, so a permanent mismatch fails the lab's own
  health check. What it cannot do is notice a *runtime* change, which is the
  monitor's job.
- **What would have made this obvious sooner:** comparing the two ends of one link
  side by side — `ip link show eth1` on r1 *and* on isp, two commands, ten seconds.
  The instinct to look at one device at a time is what made this a puzzle.
- **Read the state name literally:** `ExStart` is a hint with a capital letter.
  It is where the database description is negotiated, so "hellos fine, exchange
  stuck" points straight at MTU, not at addressing or authentication.
