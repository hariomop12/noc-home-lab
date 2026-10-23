---
tags: [homelab, ticket, incident, dhcp, relay, vlan]
status: done
---

# T-02 — No DHCP address on the new PC in Sales

**Severity:** P2
**Reported:** "The new PC in Sales has no network. It worked on the bench, and
the other departments are fine."
**Scope:** one VLAN (VLAN 20, Sales). VLAN 10 and VLAN 30 get leases normally,
and the DNS/DHCP server itself is healthy.
**Lab:** containerlab `noclab`, pc2 in VLAN 20 → relay on r1 → `srv-dns` in VLAN 40
**Status:** closed

## Symptom

One host has no address while its neighbours do:

```
---- who has a lease and who does not ----
  pc1  10.10.10.113      (VLAN 10)
  pc2                    (VLAN 20)  <- the report
  pc3  10.10.30.141      (VLAN 30)
```

The client is asking, and the request goes nowhere:

```
$ udhcpc on pc2 (VLAN 20), foreground
udhcpc: started, v1.36.1
udhcpc: broadcasting discover
udhcpc: broadcasting discover
udhcpc: no lease, failing
```

## Impact

One user cannot get on the network at all. Nothing else is affected, which is
what makes the scope statement the most valuable line in the ticket: "VLAN 20,
and only VLAN 20" rules out the server, the trunk, the uplink and the addressing
scheme in one sentence.

## Hypothesis

Written before investigating:

1. The DHCP server is down or its pool is exhausted → *would affect every VLAN,
   and pc1 and pc3 have leases*.
2. The relay is not running → a single `ps` answers it.
3. The relay is running but its configuration is missing this VLAN → the
   relay is per-interface (`--dhcp-relay=<gateway>,<server>`), so one missing
   line is one broken VLAN while everything else keeps working. **Most likely.**

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | lease inventory on pc1/pc2/pc3 | pc1 and pc3 have leases, pc2 does not | the scope is one VLAN |
| 2 | `udhcpc` by hand on pc2 | `broadcasting discover`, then `no lease, failing` | the client is working and getting no answer |
| 3 | `ps \| grep dnsmasq` on r1 | the relay is running | the relay process is not the problem |
| 4 | `grep dhcp-relay /tmp/relay-broken.conf` | `10.10.10.1` and `10.10.30.1` present, **`10.10.20.1` missing** | the relay has no entry for VLAN 20 — this is the cause |
| 5 | `udhcpc` by hand on pc1 | `lease of 10.10.10.113 obtained from 10.100.0.10` | server, relay path and VLAN 10 are all healthy |

Checks 3 and 5 together are the whole diagnosis: the relay is *up* and the server
is *reachable* — the request simply has no route defined for that VLAN.

## Root cause

One sentence: r1's DHCP relay was started from a configuration that had the VLAN
20 entry deleted (`--dhcp-relay=10.10.20.1,10.100.0.10`), so VLAN 20's broadcasts
were never forwarded to the DHCP server, while the relay itself, the server and
the other two VLANs were completely healthy.

The detail that makes this a NOC ticket rather than a lab exercise: a relayed
DHCP request is a broadcast on the client's VLAN and a unicast to the server. The
relay is the only device that bridges those two worlds, so a relay that is
running but wrong is invisible to every "is it up?" check.

## Fix

```bash
docker exec clab-noclab-r1 sh -c 'pkill dnsmasq; dnsmasq --conf-file=/etc/lab/dhcp-relay.conf'
# then let the client ask again (its loop was stopped for the fault)
```

The fix restarts the relay **from the versioned config**, not by editing the
broken one: the working configuration is in `configs/r1/` in this repository, and
copying it back is the only version of this fix that survives a reboot.

## Verification

```
T-02 verified: pc2 has 10.10.20.112

$ udhcpc on pc2 (VLAN 20)
udhcpc: lease of 10.10.20.112 obtained from 10.100.0.10
```

The same client, same interface, same server: it now receives the full DORA
exchange and installs the lease with the gateway and DNS options.

## Timeline

| Event | Clock (from the transcript) |
|---|---|
| Fault injected (relay started without VLAN 20, pc2's lease dropped) | 08:59:05 |
| Evidence collected (leases, live client, relay config, working VLAN) | 08:59:11 |
| Fix applied (relay restarted from the real config) | 08:59:16 |
| Verified (pc2 has `10.10.20.112`) | 08:59:21 |
| Total | 16 s |

These are the runner's clock, not a human's: the script already knows which checks
to run. What the ticket scores is the order — scope first (who has a lease, who does
not), then the working case, then the broken config.

## Prevention

- **Monitoring alert that should have caught this:** a per-VLAN DHCP check —
  "VLAN 20 has no leases" — is the honest alert. The lab's baseline asserts a
  lease per host (`dhcp-pc2`), and a NOC would poll the DHCP server's lease
  count per scope (or run a synthetic client per VLAN). What would *not* have
  caught it is the obvious one: the relay answers SNMP and its process is up.
- **Config standard or baseline change:** one relay configuration per router,
  versioned in `configs/`, and a baseline assertion per VLAN rather than per
  device. The bug was a single missing line, so the check has to be per-VLAN too.
- **What would have made this obvious sooner:** comparing the *working* VLAN with
  the broken one. VLAN 10's client succeeded in four seconds with the same server
  and the same relay host, which eliminates half the diagram before any config is
  read. "Works here, fails there" is a scope question, and one command answered
  it.
