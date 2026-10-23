---
tags: [homelab, ticket, incident, dns, dhcp, client-config]
status: done
---

# T-10 — Name resolution fails but IP connectivity works

**Severity:** P3
**Reported:** "I can ping the server by address, but the browser says the site
cannot be found."
**Scope:** one PC (VLAN 10). Every other host resolves names normally, and the
DNS server answers everyone else.
**Lab:** containerlab `noclab`, PC1 (VLAN 10) → srv-dns in VLAN 40
**Status:** closed

## Symptom

```
$ nslookup web.lab.local            (pc1, using its configured resolver)
;; communications error to 10.100.0.99#53: timed out
;; communications error to 10.100.0.99#53: timed out
;; no servers could be reached
```

Layer 3 is fine, and the same name resolves when the server is asked directly:

```
$ ping -c2 10.100.0.12              (ok)
$ nslookup web.lab.local 10.100.0.10
Name:	web.lab.local
Address: 10.100.0.12
```

```
$ cat /etc/resolv.conf              (pc1)
nameserver 10.100.0.99
```

## Impact

One user cannot reach any internal service by name (they can by address). Nothing
else in the lab is affected: the same query against the DNS server works from the
other VLANs, and every DHCP client in the lab has the correct resolver.

## Hypothesis

Written before investigating:

1. The DNS server is down → *contradicted by the direct query succeeding*.
2. A firewall/ACL blocks UDP 53 from VLAN 10 → also contradicted by the direct
   query, which travels the same path.
3. The client is asking the wrong server — i.e. its configured resolver is not the
   lab's DNS server. **Most likely**, because the failure names a specific address
   (`10.100.0.99`) that must have come from somewhere on the client.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | `nslookup web.lab.local` (pc1) | timeouts against `10.100.0.99` | the client's resolver is the suspect, not the name |
| 2 | `ping 10.100.0.12` (pc1) | replies | transport to VLAN 40 works |
| 3 | `nslookup web.lab.local 10.100.0.10` (pc1) | correct answer | the DNS server is healthy *and reachable from this PC* |
| 4 | `cat /etc/resolv.conf` (pc1) | `nameserver 10.100.0.99` | the wrong server is configured; nothing in the lab owns `.99` |
| 5 | `tail -1 /var/log/dhcp.log` (pc1) | lease line carries `dns 10.100.0.10` | DHCP handed out the correct resolver — the file was overwritten afterwards |

Checks 3 and 4 together are the whole diagnosis: "the server works, and the client
is not talking to it".

## Root cause

One sentence: PC1's `/etc/resolv.conf` pointed at `10.100.0.99`, an address no
device in the lab uses, so every lookup timed out while all IP traffic worked — a
client configuration fault, not a DNS server fault.

The detail worth keeping: the DHCP lease in check 5 shows the *correct* resolver
being delivered all along, which rules out the DHCP server in one line. The
injected fault also has to stop the DHCP client loop, because the next renewal
would rewrite `resolv.conf` from the correct DHCP option and heal the fault by
itself — a fact that explains a whole class of "it fixed itself" tickets.

## Fix

```bash
docker exec clab-noclab-pc1 sh -c 'printf "nameserver 10.100.0.10\n" > /etc/resolv.conf'
# and restart the DHCP client loop, so the file is owned by DHCP again
```

Fixing the *file* alone would be wrong in production: the file is generated, and
the next renewal would overwrite it. The correct fix is to restore what generates
it (the DHCP client, or a fixed resolver in `/etc/resolv.conf.head`, depending on
who is expected to own DNS settings on that host).

## Verification

```
T-10 verified: pc1 resolves names again
```

`nslookup web.lab.local` on pc1 now answers `10.100.0.12` without naming a server.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (resolver pointed at a dead address) | 09:02:53 |
| Evidence collected (client fails, ping works, server answers directly) | 09:03:01 |
| Fix applied (real resolver restored, client restarted) | 09:03:02 |
| Verified (pc1 resolves names again) | 09:03:06 |
| Total | 13 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — ask the *known-good server* directly
before blaming DNS at all.

## Prevention

- **Monitoring alert that should have caught this:** a *resolver-aware* check, not
  a DNS-server check. The lab's `baseline.sh` already resolves `web.lab.local`
  from the NOC toolbox (`dns-a-record`), which proves the server, but a host with
  a broken `resolv.conf` is invisible to that check. The useful alert is "resolve
  a known name *through the resolver each host is configured with*".
- **Config standard or baseline change:** document which component owns
  `/etc/resolv.conf` on each host class (DHCP-provided, or static for servers) and
  check it in the baseline for the servers; for user PCs, it is DHCP's job and the
  DHCP scope is what gets reviewed.
- **What would have made this obvious sooner:** saying the failing address out
  loud — `10.100.0.99`. An engineer who knows the IP plan hears "that address is
  not mine" instantly; the mistake is skipping past it as "some DNS error".
