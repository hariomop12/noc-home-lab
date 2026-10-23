---
tags: [homelab, ticket, incident, vlan, trunk, layer2]
status: done
---

# T-03 — The two IT PCs can ping each other but not their gateway

**Severity:** P2
**Reported:** "The two PCs in IT see each other, but neither can reach the
gateway or any server. Nothing changed, it was working yesterday."
**Scope:** VLAN 30 (IT) on the second switch. The same switch's other VLANs and
the first switch's IT ports are unaffected.
**Lab:** containerlab `noclab`, pc3 and pc4 in VLAN 30 on sw2, trunk to sw1 → r1
**Status:** closed

## Symptom

Same-VLAN traffic works, everything else fails. That combination *is* the
diagnosis, if it is read properly:

```
ping 10.10.30.132 from pc3 : ok       <- pc4, same VLAN 30, same switch
ping 10.10.30.1  from pc3 : FAILED    <- the gateway on r1
ping 10.100.0.12 from pc3 : FAILED    <- a server in VLAN 40
```

Both PCs are on the same access switch, so their frames never leave it. Every
path that has to cross the uplink fails.

## Impact

Two users (the whole IT department in this small site) cannot reach anything
outside their own switch: no servers, no internet, no monitoring of those hosts.
VLAN 30 is intact on sw1 and on the router, so the fault is confined to one
switch in the middle — one physical device, and one VLAN on it.

## Hypothesis

Written before investigating:

1. The PCs have the wrong mask or gateway → would break the gateway ping for
   *both* hosts in the same way, and check 3 rules it out in one command.
2. The router's VLAN 30 interface is down or mis-addressed → check the router.
3. The VLAN exists at both ends but does not cross the trunk → **most likely**,
   because same-switch traffic needs no VLAN tag on any trunk, while everything
   else does. A missing VLAN on a trunk produces exactly this split.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `ping` pc3 → pc4 | ok | the VLAN works inside the switch |
| 2 | `ping` pc3 → gateway, server | FAILED | the failure is on the path off the switch |
| 3 | `bridge vlan show` on sw2 | VLAN 30 missing from `eth1` (the uplink) — only 10, 20, 40, 99 | the VLAN is not carried on the trunk |
| 4 | `bridge vlan show` on sw1 | VLAN 30 present on its uplink | the other end is fine, and so is the design |
| 5 | `ip -4 addr show eth2.30` on r1 | `inet 10.10.30.1/24 ... state UP` | the router and its subinterface are healthy |

## Root cause

One sentence: VLAN 30 was removed from both trunk ports on the *second* switch
(`eth1` and `eth2`), so frames in VLAN 30 had no tagged path off that switch —
they reached their neighbours on the same box and were dropped at the uplink.

## Fix

```bash
docker exec clab-noclab-sw2 sh -c 'for p in eth1 eth2; do bridge vlan add dev $p vid 30; done'
```

Both uplinks, not just the one carrying live traffic: the lab runs a redundant
pair, so "which port is active" is STP's decision and not a decision to build a
fix on. On IOS the equivalent is adding the VLAN back to the trunk's allowed list
(`switchport trunk allowed vlan add 30`), and the reason to do the whole trunk
rather than one port is the same.

## Verification

```
T-03 verified: pc3 reaches its gateway over the trunk again
```

The original failing command (`ping 10.10.30.1` from pc3) is repeated and passes.
The VLAN-30 ports on sw2's uplinks are present again in `bridge vlan show`.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (VLAN 30 removed from both sw2 uplinks) | 08:59:21 |
| Evidence collected (local works, remote fails, VLAN lists, router side) | 08:59:27 |
| Fix applied (VLAN 30 added back to both uplinks) | 08:59:35 |
| Verified (pc3 reaches its gateway) | 08:59:39 |
| Total | 19 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — the same-VLAN ping first (it localises
the fault to the boundary), the VLAN lists second.

## Prevention

- **Monitoring alert that should have caught this:** per-VLAN reachability from
  the router's side — "can r1 ping a host in each VLAN" — is what fails here,
  and it is one ICMP item per VLAN. The Lab 09 NOC watches the router and the
  switches themselves (loopbacks, SVIs, CPU), which is exactly why it would have
  stayed green through this fault: the devices are all up, one VLAN is broken.
  That gap is worth naming honestly.
- **Config standard or baseline change:** the trunk's VLAN list is defined once
  in `configs/sw2/setup.sh` and asserted by the baseline's cross-VLAN checks, so
  a wrong trunk fails the deploy self-test. What no config check catches is a
  *runtime* change, which is what this fault is.
- **What would have made this obvious sooner:** the split itself. "Local works,
  remote fails" points at the crossing point — a trunk, a tunnel, a router, a
  firewall — before any command is run. The correct first instinct is to look at
  the boundary, not at the two hosts that are complaining.
