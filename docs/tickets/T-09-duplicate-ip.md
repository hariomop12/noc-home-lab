---
tags: [homelab, ticket, incident, arp, duplicate-ip, dhcp]
status: done
---

# T-09 — One PC keeps dropping off, and the ping to it is fine

**Severity:** P2
**Reported:** "The IT machine on the second desk keeps losing the network. I can
ping it from my desk, then a minute later I can't. Nothing has been changed."
**Scope:** one host and the traffic addressed to it. The host itself works: it can
ping out, and it holds a valid lease.
**Lab:** containerlab `noclab`, pc3 and pc4 in VLAN 30, r1's VLAN 30 subinterface
`10.10.30.1`, disputed address `10.10.30.132`
**Status:** closed

## Symptom

The same address answers ARP from two different MAC addresses — which is what a
duplicate address *is*:

```
---- the owner's own check: duplicate address detection ----
$ arping -D from pc4
Unicast reply from 10.10.30.132 [AA:C1:AB:7F:D6:9B]  0.581ms
Received 1 response(s)
```

`arping -D` sends an ARP probe from source `0.0.0.0` — the same thing an operating
system does before it adopts an address. pc4 is asking "is anyone using
`10.10.30.132`?" about *its own* address, and something answered. The MAC in the
reply is not pc4's:

```
  pc4's real MAC: aa:c1:ab:66:d0:8d   pc3's (the duplicate): aa:c1:ab:7f:d6:9b
```

And the router has cached the wrong one, which is why the owner's traffic breaks:

```
$ ping the disputed address from r1, then read r1's cache
10.10.30.132 lladdr aa:c1:ab:7f:d6:9b DELAY
```

The victim's own view is intermittent by nature — the router re-resolves the
address whenever its cache goes stale, and whichever host answers last gets the
next packet:

```
$ ping -c20 -i 0.5 -W2 pc4 -> its gateway (20 packets over 10 s)
20 packets transmitted, 20 received, 0% packet loss, time 9579ms
```

That sample happened to land inside the owner's windows. The *proof* of the fault is
the ARP reply above, not the loss percentage: a duplicate address is a race, and a
race does not fail on schedule.

## Impact

One user's traffic is partly delivered to a machine that should not have the
address. Symptoms range from intermittent loss to a wrong host answering a service
— and in the worst case the duplicate is a rogue device capturing traffic meant for
a server. Because the owner's own pings *out* work and its lease looks valid, this
is regularly misdiagnosed as a bad cable or a failing NIC.

## Hypothesis

Written before investigating:

1. The NIC or the cable is failing → *the host's own traffic works and the switch
   counters are clean*, so no.
2. The DHCP lease expired or was handed to someone else → the owner holds a valid
   `10.10.30.132`, and DHCP does not hand the same address to two clients.
3. A second host has the same address statically (or from a second DHCP server) →
   **most likely**, because the loss follows the address rather than the host.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `arping -D` from pc4 (the owner) | a reply from a MAC that is not pc4's | the address is duplicated |
| 2 | compare both MACs | pc4 `aa:...:66:d0:8d`, pc3 `aa:...:7f:d6:9b` | the duplicate is pc3, a host in the same VLAN |
| 3 | `ip neigh show <addr> dev eth2.30` on r1 | `lladdr aa:c1:ab:7f:d6:9b` — the duplicate | the router will deliver pc4's replies to pc3 |
| 4 | `ping` from pc4 to its gateway | intermittent; 0% loss in this sample | matches a cache race, not a broken link |
| 5 | `ping` from pc3 to the gateway | 0% loss | the duplicate is perfectly happy — it stole a working address |
| 6 | after the fix, `arping -D` from pc4 | `Received 0 response(s)` | the address is unique again |

## Root cause

One sentence: pc3 was given pc4's address as a second address and announced it, so
two hosts answered ARP for `10.10.30.132`, the router cached the wrong MAC, and
pc4's own traffic was partly delivered to pc3 while pc3 worked normally.

Three details make this ticket worth reading:

- **A duplicate address is a time bomb until it is announced.** A host that claims
  an address sends a gratuitous ARP (`arping -U`) — that is what poisons the
  neighbours' caches. Without the announcement, everything keeps working from cached
  ARP entries and the fault is invisible until a cache expires, which is why "it
  worked yesterday and nothing changed" is the normal report.
- **The duplicate answers ARP even though it is not the owner.** Linux replies for
  any address configured on the interface (`arp_ignore=0` by default), so the check
  that finds this is an ARP probe, not a ping.
- **The client that took the address has to stop renewing.** pc3's DHCP client was
  stopped first; otherwise its next lease would re-flush the interface and remove
  the duplicate within twenty seconds. In an earlier run of this same script the
  duplicate disappeared mid-evidence for exactly that reason and the ticket proved
  nothing — which is why the inject now refuses to continue unless the address is
  really there, and why the client loop is stopped properly (both the loop *and* the
  running client, not just one of them).

## Fix

```bash
docker exec clab-noclab-pc3 ip addr del 10.10.30.132/24 dev eth1   # hand the address back
docker exec clab-noclab-pc3 <restart the DHCP client loop>
docker exec clab-noclab-r1 ip neigh del 10.10.30.132 dev eth2.30   # clear the poisoned cache
docker exec clab-noclab-pc4 arping -U -c 2 -I eth1 10.10.30.132    # the owner re-announces itself
```

Removing the address is not enough on its own: the router (and every other
neighbour) still has the duplicate's MAC cached, and the *next* packet follows that
cache. Clearing the entry and letting the real owner announce itself is the part
that actually restores the traffic — a useful reminder that this fault lives in
other devices' state, not in the broken host.

## Verification

```
$ no duplicate answers any more (arping -D from the owner)
Received 0 response(s)
$ and the router's cache points at the owner again
  pc4's real MAC: aa:c1:ab:66:d0:8d
T-09 verified: the owner's traffic is healthy again
```

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (address claimed and announced) | 09:09:19 |
| Evidence collected (ARP reply, cache, victim, contrast) | 09:09:27 |
| Fix applied (address removed, cache cleared, owner announces) | 09:09:42 |
| Verified | 09:09:48 |
| Total | 39 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — the ARP proof before the ping, the
cache before the NIC.

## Prevention

- **Monitoring alert that should have caught this:** a duplicate-address check.
  The Lab 09 NOC does not have one — it polls routers and switches, and this fault
  is visible only in the *neighbour tables* of the devices on that segment. A
  practical check is a small script on the access switch (or the Zabbix host)
  sending `arping -D` for each known host, or reading the switch's ARP/neighbour
  table for one address with two MACs. Any switch that logs duplicate-IP events
  would also raise its own alarm. Named gap.
- **Config standard or baseline change:** on a switch that supports it, the real
  controls are **DHCP snooping** with **IP source guard** (binds IP ↔ MAC ↔ port,
  so a second host cannot use an address it did not lease) and **dynamic ARP
  inspection**. In this lab the check that exists is `baseline.sh`'s per-host lease
  assertion, which catches a *missing* lease and not a *duplicated* address.
- **What would have made this obvious sooner:** the ARP table, not the ping. "The
  ping works from the router but not from the host" is already an ARP-shaped
  symptom — the address is answering, the *right* machine is not. Two commands
  (`arping -D` and `ip neigh show`) settle it; a ping proves nothing when the
  duplicate is polite and answers everything the owner should be answering.
