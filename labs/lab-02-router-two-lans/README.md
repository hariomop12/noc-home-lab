---
lab: 02
level: micro
status: done
tags: [homelab, lab, routing, gateway, icmp, traceroute]
---

# Lab 02 — Router + 2 LANs

## Metadata

| Field | Value |
|---|---|
| Level | micro |
| Estimated time | 60 min |
| Prerequisites | Lab 01 (Basic LAN) |
| Skills practised | IPv4 addressing, gateway role, routing table, static addressing, traceroute |
| Related docs | [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md), [../../docs/09-wireshark-guide.md](../../docs/09-wireshark-guide.md) |

## Objective

After this lab I can explain why a host needs a **default gateway**, read a
router's routing table as a list of subnets it can reach, and prove from a
capture that a packet was **routed** (TTL decremented) rather than switched.

## Theory

- Two hosts in the **same** subnet talk directly (Lab 01). Two hosts in
  **different** subnets cannot — nobody would forward the frame.
- The **default gateway** is a router's interface in *my* subnet. When a host
  wants an address outside its own subnet, it sends the frame to the gateway's
  MAC and lets the router decide what to do.
- The router has a **routing table**: one entry per network it knows. Both LANs
  here are **directly connected**, so no static route is needed — the router
  knows them the moment they are configured.
- A router **decrements the TTL** by one for every packet it forwards. That
  single changed number is the proof that routing (not switching) happened.

## Topology

```
PC1 ── SW1 Gi0/1        SW1 Gi0/2 ── R1 Gi0/0   10.10.10.1/24
PC2 ── SW2 Gi0/1        SW2 Gi0/2 ── R1 Gi0/1   10.10.20.1/24
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | vios | Gi0/0 | 10.10.10.1/24 | LAN 1 gateway |
| R1 | vios | Gi0/1 | 10.10.20.1/24 | LAN 2 gateway |
| R1 | vios | Loopback0 | 10.255.0.1/32 | stable router identity |
| SW1 | vios_l2 | Gi0/1, Gi0/2 | — | default config, VLAN 1 |
| SW2 | vios_l2 | Gi0/1, Gi0/2 | — | default config, VLAN 1 |
| PC1 | VPCS | eth0 | 10.10.10.10/24, gw 10.10.10.1 | LAN 1 host |
| PC2 | VPCS | eth0 | 10.10.20.10/24, gw 10.10.20.1 | LAN 2 host |

Addresses are taken from the HR and SALES subnets in
[../../docs/01-ip-plan.md](../../docs/01-ip-plan.md). The routers use the `.1`
of each subnet, hosts sit in the infrastructure range (not the DHCP pool).

## Build steps

1. Create the GNS3 project `lab2`.
2. Add 1× `vios` (`R1`), 2× `vios_l2` (`SW1`, `SW2`) and 2× VPCS (`PC1`, `PC2`).
3. Cable as drawn: PC → switch Gi0/1, switch Gi0/2 → router.
4. Start all nodes. Wait for the switches to boot.
5. Configure end devices → router, outside in.
6. Run the verification table.

## Configuration

Start from `configs/golden-configs/vios-router-baseline.cfg`. Show only what
changed for this lab.

**R1**
```
hostname R1
interface Loopback0
 ip address 10.255.0.1 255.255.255.255
interface GigabitEthernet0/0
 ip address 10.10.10.1 255.255.255.0
 no shutdown
interface GigabitEthernet0/1
 ip address 10.10.20.1 255.255.255.0
 no shutdown
```

**SW1 / SW2** — nothing. Default VLAN 1 is enough.

**PC1 / PC2**
```
PC1> ip 10.10.10.10/24 10.10.10.1
PC2> ip 10.10.20.10/24 10.10.20.1
```

## Verification

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip interface brief` on R1 | Gi0/0, Gi0/1, Lo0 up/up | ✅ all three up/up |
| 2 | `ping 10.10.10.1` from PC1 | gateway reachable | ✅ 5/5, `ttl=255` |
| 3 | `ping 10.10.20.10` from PC1 | replies with `ttl=63` | ✅ 5/5, `ttl=63` |
| 4 | `show ip route` on R1 | two connected subnets + loopback | ✅ 10.10.10.0/24, 10.10.20.0/24, 10.255.0.1/32 |
| 5 | `trace 10.10.20.10` from PC1 | hop 1 = 10.10.10.1 (R1) | ✅ hop1 R1, hop2 PC2 |

Raw PC1 output:
```
PC1> ping 10.10.20.10
84 bytes from 10.10.20.10 icmp_seq=1 ttl=63 time=7.911 ms
84 bytes from 10.10.20.10 icmp_seq=2 ttl=63 time=4.418 ms
...

PC1> trace 10.10.20.10
trace to 10.10.20.10, 8 hops max, press Ctrl+C to stop
 1   10.10.10.1   2.507 ms  2.356 ms  2.686 ms
 2   *10.10.20.10   4.100 ms (ICMP type:3, code:3, Destination port unreachable)
```

`ttl=63` is the proof: the packet left PC1 with TTL 64 and R1 decremented it to
63. (The `ttl=255` for the gateway ping is R1 answering as *itself*, so nothing
was forwarded.) The `type:3, code:3` on the last traceroute hop is normal — the
PC's probe reached its target and the target said "that UDP port is closed".

## Capture exercise

Capture on: **PC1 ↔ SW1** (the host link of LAN 1).
Saved as: `wireshark/lab-02-router-two-lans-ttl.pcapng`.
Filter: `arp || icmp`

One ping across the router (frames 5–6 are a second ping with the same shape):

| Frame | src → dst | Protocol | TTL | What it is |
|---|---|---|---|---|
| 1 | `00:50:79:66:68:00` → Broadcast | ARP | — | `Who has 10.10.10.1? Tell 10.10.10.10` |
| 2 | `0c:e9:ea:9a:00:00` → `00:50:79:66:68:00` | ARP | — | `10.10.10.1 is at 0c:e9:ea:9a:00:00` |
| 3 | 10.10.10.10 → 10.10.20.10 | ICMP | 64 | echo request, leaving PC1 |
| 4 | 10.10.20.10 → 10.10.10.10 | ICMP | 63 | echo reply, *after* R1 routed it |
| 5–6 | same, seq=2 | ICMP | 64 / 63 | second ping, ARP now cached |

Answered from the capture:

- **Which MAC addresses are involved?** PC1 is `00:50:79:66:68:00`; the frame is
  sent to `0c:e9:ea:9a:00:00` — that is **R1's Gi0/0**, not PC2. PC1 does not
  know PC2's MAC, because PC2 is in another subnet.
- **Which addresses are rewritten, and which are not?** The IPs never change
  (10.10.10.10 ↔ 10.10.20.10 top to bottom). The **MACs do**: on each LAN the
  frame is addressed to the local router interface. That is what routing is —
  rewrite the MAC, keep the IP.
- **What is the TTL doing?** 64 on the way out, 63 on the way back — R1
  decremented it once. Switching (Lab 01) would have left it at 64.

## Break it / fix it

Diagnose without looking at this file. Time each one.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | `shutdown` R1 Gi0/1 | PC1 → PC2 ping fails | no interface in 10.10.20.0/24, so the route disappears | `no shutdown` on Gi0/1 |
| 2 | Remove PC1's gateway | ping to PC2 fails, ping to 10.10.10.1 still works | without a gateway the host cannot send to a remote subnet | set gateway back to 10.10.10.1 |
| 3 | Give PC2 the wrong mask | PC1 → PC2 fails | PC2 answers as if PC1 is remote, and has no route back | correct mask to `/24` |

Fault #1 was run to completion: `shutdown` on R1 Gi0/1 → `ping 10.10.20.10` from
PC1 failed → `no shutdown` → ping passed again.

## Self-check questions

1. Why can PC1 reach 10.10.10.1 without a gateway, but not 10.10.20.10?
2. Which MAC address does PC1 put in the frame when pinging 10.10.20.10, and why?
3. Why is `show ip route` empty of any `S` (static) entries in this lab?
4. What does `ttl=63` prove that `ttl=255` does not?

## What I learned

- A gateway is just a router interface in my own subnet; without it, remote
  subnets are unreachable no matter how good the addressing is.
- Directly connected networks appear in the routing table automatically — no
  static route needed while both networks hang off the same router.
- The MAC is rewritten per hop; the IP is not. That is the essence of routing.
- TTL decrement is the fingerprint of a routed packet.

## Cleanup

- [x] Configs exported to `configs/lab-02/` (R1.cfg)
- [x] Capture saved, trimmed and annotated in `wireshark/`
- [x] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [x] Committed with a specific message
