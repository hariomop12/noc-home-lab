---
lab: 01
level: micro
status: done
tags: [homelab, lab, switching, mac-learning, arp, icmp]
---

# Lab 01 — Basic LAN

## Metadata

| Field | Value |
|---|---|
| Level | micro |
| Estimated time | 45 min |
| Prerequisites | none (first lab) |
| Skills practised | Switch ports, MAC learning, ARP, ICMP, first packet capture |
| Related docs | [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md), [../../docs/09-wireshark-guide.md](../../docs/09-wireshark-guide.md) |

## Objective

After this lab I can explain, from a capture and from the switch's MAC table, how
two hosts on the same wire find each other — and why a switch needs no
configuration at all for that to work.

## Theory

- A **switch** forwards frames by looking at the **destination MAC**, and it
  learns which MAC lives on which port from the **source MAC** of frames it
  receives. That is the whole trick.
- Hosts do not know each other's MAC. To find one, a host sends an **ARP
  request** — a *broadcast* (`Who has X?`). The owner answers with a *unicast*
  **ARP reply** (`X is at <mac>`).
- Because both hosts are in the same subnet, traffic goes **directly**, host to
  host. No gateway, no routing, no TTL decrement.
- **ICMP** echo request/reply is what `ping` sends. The TTL starts at 64 and
  stays 64 — proof no router touched the packet.

## Topology

```
PC1 ── SW1 Gi0/1
PC2 ── SW1 Gi0/2
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| PC1 | VPCS | eth0 | 10.10.10.10/24 | no gateway needed |
| PC2 | VPCS | eth0 | 10.10.10.11/24 | no gateway needed |
| SW1 | vios_l2 | Gi0/1 | — | access port to PC1 (default VLAN 1) |
| SW1 | vios_l2 | Gi0/2 | — | access port to PC2 (default VLAN 1) |

Addresses are taken from the infrastructure range of the HR subnet in
[../../docs/01-ip-plan.md](../../docs/01-ip-plan.md). The `.100–.200` range is
reserved for DHCP, so static hosts must not use it.

## Build steps

1. Create the GNS3 project `lab1`.
2. Add 1× `vios_l2` switch (`SW1`) and 2× VPCS (`PC1`, `PC2`).
3. Cable PC1 eth0 → SW1 Gi0/1 and PC2 eth0 → SW1 Gi0/2.
4. Start all nodes. `vios_l2` boots slowly — wait for the `Switch>` prompt.
5. Address the PCs (below). The switch needs nothing.
6. Run the verification table.

## Configuration

Start from `configs/golden-configs/`. Show only what changed for this lab.

**SW1 — nothing.** All ports are in VLAN 1 by default and the switch forwards
immediately. This is deliberate: it isolates *MAC learning* from switch config.

**PC1 / PC2** (VPCS console):
```
PC1> ip 10.10.10.10/24
PC2> ip 10.10.10.11/24
```
No default gateway: the two hosts are in the same subnet, so a gateway would
never be used.

## Verification

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip` on PC1 | IP 10.10.10.10/24 | ✅ |
| 2 | `ping 10.10.10.11` from PC1 | 5/5 replies | ✅ 5/5 |
| 3 | `show interfaces status` on SW1 | Gi0/1 and Gi0/2 `connected` | ✅ Gi0/1, Gi0/2 connected |
| 4 | `show mac address-table` on SW1 | 2 dynamic entries | ✅ 2 entries, Gi0/1 + Gi0/2 |

Raw SW1 output:
```
Switch#show interfaces status
Port      Name               Status       Vlan       Duplex  Speed Type
Gi0/0                        notconnect   1          a-full   auto RJ45
Gi0/1                        connected    1          a-full   auto RJ45
Gi0/2                        connected    1          a-full   auto RJ45
Gi0/3                        notconnect   1          a-full   auto RJ45

Switch#show mac address-table
          Mac Address Table
-------------------------------------------
Vlan    Mac Address       Type        Ports
----    -----------       --------    -----
   1    0050.7966.6800    DYNAMIC     Gi0/1
   1    0050.7966.6801    DYNAMIC     Gi0/2
Total Mac Addresses for this criterion: 2
```

`0050.7966.6800` is PC1 (seen on Gi0/1) and `0050.7966.6801` is PC2 (seen on
Gi0/2). The switch learned these from the **source MAC** of the frames each PC
sent — nobody configured them.

## Capture exercise

Capture on: **SW1 Gi0/1 ↔ PC1** (the client link).
Saved as: `wireshark/lab-01-basic-lan-arp-icmp.pcapng`.
Filter: `arp || icmp`

One ping, four frames — the whole story of a same-subnet conversation:

| Frame | src MAC → dst MAC | Protocol | What it is |
|---|---|---|---|
| 1 | `00:50:79:66:68:00` → `Broadcast` | ARP | `Who has 10.10.10.11? Tell 10.10.10.10` |
| 2 | `00:50:79:66:68:01` → `00:50:79:66:68:00` | ARP | `10.10.10.11 is at 00:50:79:66:68:01` |
| 3 | `10.10.10.10` → `10.10.10.11` | ICMP | Echo (ping) request, `ttl=64` |
| 4 | `10.10.10.11` → `10.10.10.10` | ICMP | Echo (ping) reply, `ttl=64` |

Answered from the capture:

- **Which MAC addresses are involved, and which device owns each one?** PC1 =
  `00:50:79:66:68:00`, PC2 = `00:50:79:66:68:01` (also visible in the SW1 MAC
  table, which is how the two views confirm each other).
- **Which addresses are rewritten at each hop?** None — there is no hop. The MAC
  and IP addresses are identical in request and reply. ✅
- **What is the TTL doing?** Nothing: `64` in, `64` out. A router would have
  decremented it to 63; the absence of that is the proof this was pure Layer 2.
- **Why was ping #1 slower?** The first ping waits for the ARP exchange (frames
  1–2) before it can send the ICMP; after that the ARP entry is cached, so every
  following ping goes out immediately.

The original capture also contained a stream of background chatter (STP, CDP,
DTP) — the switch talks even when nobody asked. It was trimmed out; see the
trim rule in [../../wireshark/README.md](../../wireshark/README.md).

## Break it / fix it

Diagnose without looking at this file. Time each one.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | `shutdown` SW1 Gi0/1 | PC1 → PC2 ping times out | the port is down, so PC1 has no path into the switch | `no shutdown` on Gi0/1 |
| 2 | Give PC2 a `/25` mask | PC1 → PC2 ping fails | `.11/25` puts PC2 in a different subnet than `.10/24`, so PC1 treats it as "not local" | correct mask back to `/24` |

Fault #1 was run to completion: `shutdown` on SW1 Gi0/1 → `ping 10.10.10.11`
from PC1 timed out → `no shutdown` → ping passed again.

## Self-check questions

1. Why do the two PCs not need a default gateway?
2. Why is the ARP request a broadcast but the ARP reply a unicast?
3. What does the switch look at to decide which port to send a frame out of?
4. Why is the TTL still 64 after the ping — and what would 63 have meant?

## What I learned

- A switch works with **zero configuration**; it learns source MACs and forwards
  to destination MACs.
- Same-subnet traffic never touches a gateway — the hosts talk directly.
- The first ping is slower because **ARP has to happen first**.
- `ttl=64` unchanged is positive proof nothing was routed.

## Cleanup

- [x] Configs exported to `configs/lab-01/` (SW1.cfg — default config)
- [x] Capture saved, trimmed and annotated in `wireshark/`
- [x] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [x] Committed with a specific message
