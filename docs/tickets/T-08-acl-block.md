---
tags: [homelab, ticket, incident, acl, nftables, http]
status: done
---

# T-08 — The intranet page will not open for HR, but it opens for everyone else

**Severity:** P3
**Reported:** "The staff portal times out for HR. Sales and IT can open it fine.
The server people say the server is up."
**Scope:** one source VLAN (VLAN 10, HR) to one destination (the web server on
TCP 80). Everything else — ping, other VLANs, the same VLAN to other
destinations — works.
**Lab:** containerlab `noclab`, pc1 in VLAN 10, pc2 in VLAN 20, `client` in VLAN 40,
`srv-web` at `10.100.0.12:80`
**Status:** closed

## Symptom

One thing fails, and the fastest way to read the failure is what *does* work:

```
---- the user's view: the page does not load ----
  pc1 (VLAN 10) HTTP status: timeout (no response)
ping 10.100.0.12 from pc1 : ok

---- it is not the server and not the network ----
  pc2 (VLAN 20) HTTP status: 200
  client (VLAN 40) HTTP status: 200
```

A timeout is not a refusal: `connection refused` means the server answered and
said no; **a timeout means the packets were dropped or never arrived**, which
points at a filter or a route, not at the service. And the same TCP port is
healthy from two other VLANs in the same second.

## Impact

One department (HR, in this lab: pc1) cannot use the internal application, while
everyone else can. It is a P3 because nothing is down and no data is at risk, but
it is a genuinely hard ticket if you trust "the server is up" and stop there.

## Hypothesis

Written before investigating:

1. The web server is down or overloaded → *two other VLANs get HTTP 200 in the
   same minute*, so the service is fine.
2. DNS or the client's configuration → the client used the address directly
   (`http://10.100.0.12/`), so no name resolution is involved.
3. Something between the client and the server drops this specific flow → a
   filter matching source VLAN 10 and destination port 80. **Most likely**, because
   ICMP from the same host succeeds: the path works, the *port* does not.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | HTTP from pc1 (VLAN 10) | `timeout (no response)` | the flow is dropped, not refused |
| 2 | `ping 10.100.0.12` from pc1 | ok | routing and reachability are fine |
| 3 | HTTP from pc2 (VLAN 20) and `client` (VLAN 40) | `200` | the server, the port and the path are fine |
| 4 | `conntrack -L \| grep 'src=10.10.10.' \| grep -c 'dport=80'` on r1 | `0` | pc1 never completed a flow to that port |
| 5 | `conntrack -L \| grep 'src=10.10.10.'` on r1 | unreplied flows from pc1 | pc1's packets *are* tracked and then dropped |
| 6 | `nft list table ip acl` on r1 | `ip saddr 10.10.10.0/24 ip daddr 10.100.0.12 tcp dport 80 drop` | the rule doing it |

The rule is one line in a table that nothing else references — which is exactly
why it is hard to find: the router has no reason to log a drop that its
administrator intended, and the user sees a timeout that looks like a broken
server.

## Root cause

One sentence: an nftables rule on r1 dropped TCP/80 traffic from VLAN 10 to the
web server, silently and without logging, so only that flow failed while every
other protocol from the same host and every other VLAN's HTTP kept working.

The detail worth keeping: it is a *forward* hook filter at priority 0, i.e. after
conntrack. That is why check 4 shows zero completed flows (nothing to port 80 from
pc1 ever completed) while check 5 shows entries at all — the packet is seen,
tracked, and then dropped.

## Fix

```bash
docker exec clab-noclab-r1 nft delete table ip acl
```

Deleting the table removes the whole rule set at once, which is correct here
because the table exists only for this fault. In a real change-management sense the
fix would be `nft delete rule ... handle <handle>` to remove exactly one line, and
the incident's next step would be to find out **why the rule was added**: an ACL
that drops one department's traffic is usually either a stale change or a
justified one that should have been logged.

## Verification

```
$ pc1 HTTP status: 200
T-08 verified: VLAN 10 can load the site again
```

The original failing test repeated — an HTTP request from pc1 to
`10.100.0.12:80` — with the rule gone and the same page that pc2 and `client` were
getting all along.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (rule added) | 09:01:56 |
| Evidence collected (pc1 fails, others work, rule found) | 09:02:02 |
| Fix applied (table deleted) | 09:02:07 |
| Verified | 09:02:11 |
| Total | 15 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — the working cases first (they prove
the server is fine), the filter second.

## Prevention

- **Monitoring alert that should have caught this:** a per-VLAN synthetic HTTP
  check. The Lab 09 NOC pings `srv-web` from the server side, which stays green
  through this entire fault — the box is up, one flow is blocked. A Zabbix "Web
  scenario" item per VLAN would fail immediately, and it is the standard
  NOC answer to "the application is down for some users". This is a named gap.
- **Config standard or baseline change:** the rule lives in a named table
  (`ip acl`) loaded from the configuration, and `baseline.sh` asserts cross-VLAN
  paths and HTTP from the client at deploy time — so a permanent rule fails the
  health check. What neither catches is a rule added at runtime, which is why
  change control matters more than the check itself.
- **What would have made this obvious sooner:** notice what the timeout is *not*.
  A reader who treats "timeout" as "the server is broken" spends the ticket in the
  wrong place; a reader who asks "refused or dropped?" is already at the router.
  And the second habit: test the same service from a *different* source before
  testing anything else. Two HTTP requests — one failing, one succeeding —
  localise the fault to a single flow in five seconds. A rate limit or a firewall
  rule is always source-specific, so the working case is the more informative one.
