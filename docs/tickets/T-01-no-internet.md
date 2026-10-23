---
tags: [homelab, ticket, incident, nat, wan, internet]
status: done
---

# T-01 — LAN works, no internet

**Severity:** P1
**Reported:** "The intranet is fine — file shares, printers, the web app. Nothing
on the internet loads."
**Scope:** every user in every VLAN. This is one device, not one department: the
HQ edge router is the only way out.
**Lab:** containerlab `noclab`, `r1 eth1` WAN to the simulated ISP (`10.0.0.12/30`)
**Status:** closed

## Symptom

The report is "no internet", and the first thing the lab shows is that the
*symptom the users describe does not appear here*:

```
ping 10.100.0.12 from pc1 : ok        <- intranet, expected
ping 200.1.1.10  from pc1 : ok        <- internet, NOT expected
```

That is a finding, not a mistake. The simulated ISP at `200.1.1.10` does not
filter RFC1918 source addresses and it learns the HQ prefixes over OSPF, so a
packet that leaves HQ **without being translated** still gets a reply. On a real
ISP that packet is dropped at the edge, which is why this fault is proven on the
wire further down instead of by the ping. (This is the same lesson as the Lab 07
correction, where a failover drill passed for the wrong reason.)

## Impact

Nothing in the lab breaks visibly, which is exactly what makes this a good
ticket: the edge is leaking private source addresses onto the internet link, and
every internet-bound flow from every VLAN depends on a ruleset that is no longer
there. With a real ISP: no internet at all, for everyone, immediately.

## Hypothesis

Written before investigating:

1. The WAN link or the default route is gone → *but the route table shows the
   OSPF default via `10.0.0.14` and the link is up*.
2. DNS is broken so the browser cannot resolve → possible in general, but the
   user said "nothing loads", and a resolved IP is easy to test.
3. The router forwards but does not translate (NAT ruleset missing, or matching
   the wrong interface) → test with `nft list ruleset` and then look at the source
   address on the wire.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `ip route` on r1 | `default via 10.0.0.14 dev eth1 proto ospf` | routing is healthy — not the cause |
| 2 | `nft list ruleset` on r1 | *empty* | the NAT ruleset is gone entirely |
| 3 | `conntrack -L \| grep 200.1.1` on r1 | *nothing* | no translation exists for the flow that just worked |
| 4 | `tcpdump` on the ISP-facing link while pc1 pings | `IP 10.10.10.113 > 200.1.1.10: ICMP echo request` | the packet left with a **private source address** — this is the fault |
| 5 | after the fix, the same capture | `IP 10.0.0.13 > 200.1.1.10: ICMP echo request` | the edge now sees the router's WAN address |

Check 4 is the one that matters. A ping proves "something answered"; a capture
proves "the internet is being asked to route a private address", which is the
difference between a working lab and a working network.

## Root cause

One sentence: r1's nftables NAT ruleset was flushed, so the router still routed
internet-bound packets but stopped translating them — the source address the
internet link carried was the user's `10.10.10.113` instead of r1's `10.0.0.13`.

The reason the ticket exists at all is the second half of that sentence: routing
and translation are configured separately and fail separately, and every check
that only looks at routing says the network is fine.

## Fix

```bash
docker exec clab-noclab-r1 nft -f /etc/lab/nat.nft     # reload the ruleset
```

Why not "add a default route" or "restart the ISP"? Because the evidence points
at one missing table, not at connectivity. The rule of the method: fix the thing
the last check proved broken, nothing else — a reboot would have "worked" and
would have taught nothing.

One related trap, hit while writing this ticket: `nft flush ruleset` does **not**
clear what conntrack has already learned. An established translation keeps
working until its entry expires, so the fault looks half-broken until the inject
step also runs `conntrack -F`. Faults about NAT are faults about state, and the
state lives in two places.

## Verification

```
T-01 verified: pc1 reaches 200.1.1.10 again
$ and the internet edge now sees r1's WAN address, not pc1's
IP 10.0.0.13 > 200.1.1.10: ICMP echo request, id 209, seq 1, length 64
IP 200.1.1.10 > 10.0.0.13: ICMP echo reply, id 209, seq 1, length 64
icmp     1 29 src=10.10.10.113 dst=200.1.1.10 type=8 code=0 id=209 \
        src=200.1.1.10 dst=10.0.0.13 type=0 code=0 id=209 mark=0 use=1
```

The conntrack line is the translation itself: the original tuple keeps the
client's address, and the reply tuple carries r1's WAN address instead.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (NAT ruleset flushed, conntrack cleared) | 08:58:42 |
| Evidence collected (route, ruleset, conntrack, wire capture) | 08:58:49 |
| Fix applied (ruleset reloaded) | 08:58:55 |
| Verified (wire shows r1's WAN address) | 08:58:59 |
| Total | 23 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — the capture before the conclusion,
and the source address before the ping.

## Prevention

- **Monitoring alert that should have caught this:** a check that looks for
  private source addresses appearing on the internet link — the lab's own
  `baseline.sh` has exactly this (`nat-not-leaking`, "no private source on the ISP
  internet link") and it fails when this fault is live. The honest gap is that it
  is a *test run on demand*, not a monitored item: Zabbix polled the routers'
  loopbacks and interfaces but nothing about translation state, so nobody would
  have been paged.
- **Config standard or baseline change:** the NAT ruleset lives in `/etc/lab/nat.nft`
  in this repository's `configs/`, so it is versioned rather than typed on a
  console. A device-config backup would have caught the *deletion* if the backup
  ran often enough; on a real edge, a config diff alert is the practical version
  of this.
- **What would have made this obvious sooner:** asking "does the packet leave
  with the right source address" instead of "does the packet arrive". One capture
  on the WAN link, ten seconds — and it is the only check in this ticket that
  cannot be fooled by a permissive ISP.
