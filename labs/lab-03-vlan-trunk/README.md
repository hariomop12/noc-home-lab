---
lab: 03
level: micro
status: done
tags: [homelab, lab, vlan, trunk, router-on-a-stick, inter-vlan]
---

# Lab 03 — VLAN + Trunk + Inter-VLAN (router-on-a-stick)

> Status: **done.** Verified ping, capture analysed, fault injected and fixed.

## Metadata

| Field | Value |
|---|---|
| Level | micro |
| Estimated time | 90 min |
| Prerequisites | Lab 01 (switching), Lab 02 (addressing + gateway) |
| Skills practised | VLANs, 802.1Q trunk, router-on-a-stick, inter-VLAN routing |
| Related docs | [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md), [../../docs/05-ios-cheatsheet.md](../../docs/05-ios-cheatsheet.md) |

## Objective

After this lab I can put two hosts in separate VLANs, trunk them to one router,
and explain why a PC in VLAN 10 can reach a PC in VLAN 20 even though they share
no subnet — and fix it from the CLI when it breaks.

## Theory

Two hosts in different subnets are not reachable by switching alone: the sender
ARPs for its **default gateway**, not for the destination host. So the destination
MAC on the frame is the router's, and the router moves the packet between
subnets. One physical router interface can serve many VLANs using **subinterfaces**
(`Gi0/0.10`, `Gi0/0.20`), each tagged with a different 802.1Q VLAN ID — this is
**router-on-a-stick**. The switch uplink to the router must be a **trunk** so the
VLAN tag survives the link.

## Topology

```
PC1 ── SW1 Gi0/1   (access, VLAN 10)
PC2 ── SW1 Gi0/2   (access, VLAN 20)
SW1 Gi0/3 ──────── R1 Gi0/0   (802.1Q trunk)   ← capture point
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | vios | Gi0/0 | — | physical, `no shutdown` |
| R1 | vios | Gi0/0.10 | 10.10.10.1/24 | VLAN 10 gateway |
| R1 | vios | Gi0/0.20 | 10.10.20.1/24 | VLAN 20 gateway |
| SW1 | vios_l2 | Gi0/1 | — | access port VLAN 10 |
| SW1 | vios_l2 | Gi0/2 | — | access port VLAN 20 |
| SW1 | vios_l2 | Gi0/3 | — | trunk to R1 |
| PC1 | VPCS | eth0 | 10.10.10.100/24 gw 10.10.10.1 | |
| PC2 | VPCS | eth0 | 10.10.20.100/24 gw 10.10.20.1 | |

Addressing taken from [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md).

> GNS3 node names were `CiscoIOSv-1`, `Cisco-Switch-GOAT-1`. Repo convention wants
> `R1` / `SW1` — rename in the project next time so console names, captures and
> notes all match.

## Build steps

1. Project in GNS3: nodes PC1, PC2, `vios_l2` switch, `vios` router.
2. Cable as drawn above. Interface convention: lowest port = LAN, highest = uplink.
3. Start all nodes; `vios_l2` boots slowly.
4. Configure outside-in: PC → switch → router.
5. Verify (table below).

## Configuration

**R1 — router-on-a-stick**
```
interface GigabitEthernet0/0
 no shutdown
!
interface GigabitEthernet0/0.10
 encapsulation dot1Q 10
 ip address 10.10.10.1 255.255.255.0
!
interface GigabitEthernet0/0.20
 encapsulation dot1Q 20
 ip address 10.10.20.1 255.255.255.0
```

**SW1 — VLANs, access ports, trunk**
```
vlan 10
vlan 20
!
interface GigabitEthernet0/1
 switchport mode access
 switchport access vlan 10
!
interface GigabitEthernet0/2
 switchport mode access
 switchport access vlan 20
!
interface GigabitEthernet0/3
 switchport trunk encapsulation dot1q
 switchport mode trunk
```

**PC1 / PC2 (VPCS console)**
```
ip 10.10.10.100/24 10.10.10.1     ! PC1
ip 10.10.20.100/24 10.10.20.1     ! PC2
save
```
> VPCS does not persist IPs across a restart — always `save`.

## Verification

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip interface brief` (R1) | Gi0/0.10 and Gi0/0.20 up/up | ✅ both up/up |
| 2 | `show interfaces trunk` (SW1) | Gi0/3 trunking, VLANs 10,20 active | ✅ Gi0/3 trunking, 10 & 20 active |
| 3 | `ping 10.10.20.100` from PC1 | 5/5 replies | ✅ 5/5, `ttl=63`, ~3-7 ms |
| 4 | `ping 10.10.10.1` from PC2 | gateway reachable | ✅ |

Raw PC1 output:
```
PC1> ping 10.10.20.100
84 bytes from 10.10.20.100 icmp_seq=1 ttl=63 time=7.002 ms
84 bytes from 10.10.20.100 icmp_seq=2 ttl=63 time=4.114 ms
84 bytes from 10.10.20.100 icmp_seq=3 ttl=63 time=4.011 ms
84 bytes from 10.10.20.100 icmp_seq=4 ttl=63 time=4.243 ms
84 bytes from 10.10.20.100 icmp_seq=5 ttl=63 time=3.550 ms
```

**`ttl=63` is the proof routing happened**: 64 at PC1, decremented once by R1.
If the hosts were in the same VLAN the reply would show `ttl=64`.

## Capture exercise

Capture on: **SW1 Gi0/3 ↔ R1 Gi0/0** (the trunk).
Saved as: `wireshark/lab-03-vlan-trunk-8021q.pcapng`.
Filter: `vlan` (tags), then `icmp` (the ping).

The capture is the proof. One ping, four frames (ttl and VLAN tag at each step):

| Frame | Direction | VLAN tag | TTL | What it is |
|---|---|---|---|---|
| 59 | 10.10.10.100 → 10.10.20.100 | 10 | 64 | request, before R1 |
| 62 | 10.10.10.100 → 10.10.20.100 | 20 | 63 | same request, after R1 |
| 63 | 10.10.20.100 → 10.10.10.100 | 20 | 64 | reply, before R1 |
| 64 | 10.10.20.100 → 10.10.10.100 | 10 | 63 | same reply, after R1 |

Answered from the capture:

- **VLAN tag present on the trunk**, and it *changes*: request on VLAN 10, routed,
  then the same packet on VLAN 20. Access ports carry no tag. ✅
- **Sender resolves the router's MAC**, not the other PC's: frame 57 ARP
  `Who has 10.10.10.1? Tell 10.10.10.100` → reply `10.10.10.1 is at
  0c:f3:52:ce:00:00` (R1). Then frame 60: R1 itself ARPs for `10.10.20.100`
  inside VLAN 20. ✅
- **TTL 64 → 63** across R1, proving the packet was *routed*, not switched. ✅
- Bonus: 35 frames tagged VLAN 10 and 35 tagged VLAN 20 — the switch is also
  sending PVST+ STP BPDUs per VLAN (frames 2, 3, ...).

## Break it / fix it

Diagnose without looking at this file. Time each one.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | `shutdown` SW1 Gi0/3 (trunk) | both VLANs lose the router | trunk down → no path to R1 | `no shutdown` on Gi0/3 |
| 2 | PC1 access port → `switchport access vlan 20` | PC1 can't reach its gateway | | |
| 3 | R1 Gi0/0.20 → `encapsulation dot1Q 30` | VLAN 20 dead, VLAN 10 fine | | |
| 4 | Forget `no shutdown` on R1 Gi0/0 | subinterfaces stay down | | |

Fault #1 was run to completion: `shutdown` on SW1 Gi0/3 → PC1 `ping 10.10.20.100`
**failed** → `no shutdown` → ping passed again. Diagnosed correctly in one move.

## Self-check questions

1. Why does PC1 need a gateway at all, when PC2 is on the same switch?
2. Which MAC address does PC1 ARP for when pinging 10.10.20.100?
3. Why is the trunk a trunk and the PC ports access ports?

## What I learned

- Inter-VLAN routing needs a **Layer 3** device; a switch alone cannot cross subnets.
- One router interface can serve many VLANs with `dot1Q` subinterfaces.
- `ttl=63` is visible proof the packet was routed, not switched.
- A GNS3 capture must be started **before** the traffic you want to prove.

## Cleanup

- [x] Configs exported to `configs/lab-03/` (R1.cfg, SW1.cfg)
- [x] Capture saved, trimmed and annotated in `wireshark/`
- [x] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [ ] Committed with a specific message
