---
tags: [homelab, design, lab-08, redundancy, hsrp, stp, ospf-tuning, nat, failover]
status: proposed
---

# Lab 08 — Redundancy: an HQ that survives a failure

This is the design for **Lab 08 (Redundancy)**. It is written before the build, in
the same shape as [Lab 06](hq-design.md) and [Lab 07](branch-wan-design.md), and it
is expected to change once reality disagrees with it.

---

## 1. The brief

Labs 06 and 07 built a working two-site network, and then spent most of their time
showing how it *fails*: one router, one uplink, one switch between the users and
everything else. Lab 08 removes that single point of failure at the three layers
where it actually exists, and measures what the removal buys.

| Layer | What is single-homed today | What Lab 08 does |
|---|---|---|
| Default gateway | `R1` is the only gateway for all five HQ VLANs | A second router (`R3`) shares every VLAN with HSRP, so the VIP never moves |
| Uplink | The HQ's only path off-site is `R1`'s WAN | `R3` gets its own WAN link, cost-tuned as the backup egress |
| Inter-switch link | `SW1 ↔ SW2` is one cable | A second trunk makes an L2 loop, and STP root control decides which one carries each VLAN |

The interesting part is not "configure HSRP". It is that three independent
mechanisms — HSRP, OSPF and STP — have to agree about which router and which link
should carry a given VLAN, and that they fail *independently*. Almost every drill
below is about noticing that one of the three moved and the other two did not.

## 2. What already exists

Everything from Labs 06 and 07, unchanged except where section 6 says so:

- `R1` (`vios`) is the HQ router: trunk `Gi0/0` to `SW1`, WAN `Gi0/1` to the ISP,
  transit `Gi0/2` to `R2`, `Gi0/3` free.
- `SW1`, `SW2` (`vios_l2`) are the HQ access switches: `SW1` is the STP root for
  every VLAN (priority 24576), VLANs 10/20/30/40/99, trunk `Gi0/0` to `R1`,
  `Gi0/1` carrying the inter-switch link. Both switches are **full**: four
  interfaces, four cables.
- `SW3`/`R2`/`PC5`/`PC6` at BR1, the ISP, `SRV-SEG` with the servers, `CLIENT`.
- NAT on `R1` and `R2` with the Lab 07 route-map shape, and the transit marked
  `ip nat outside` (that marking is corrected here — section 10).
- The 19-node project `lab-07-branch-wan`, all devices configured, six
  configurations exported to `configs/lab-07/`.

Free capacity this design uses: `R1 Gi0/3`, `ISP Gi0/3`, `SRV-SEG` ports, and the
fact that **IOSvL2 supports 16 GigabitEthernet interfaces** (confirmed against
Cisco's IOSvL2 feature list, which also confirms HSRP on SVIs and, importantly,
that **SPAN is not supported** — so every capture in this lab is a GNS3 link
capture).

## 3. Requirements

Named, not numbered — each one is a sentence that can be answered yes or no.

| Requirement | Why it is in the lab |
|---|---|
| The default gateway survives a router failure | This is the failure a user actually notices |
| The gateway that is active has a working uplink | A redundant gateway with no path off-site is decoration |
| Traffic enters HQ the same way it leaves | Asymmetric routing breaks ACLs, NAT and any stateful middlebox |
| The internal LAN survives one switch failing | The second trunk should not be a cable that is never used |
| Every mechanism is measured, not asserted | Lab 07's drill B taught this the expensive way |
| Existing behaviour does not regress | Lab 06/07 tests are re-run as part of the verification table |

## 4. Non-goals

- **VRRP and GLBP.** HSRP is the one that appears in job ads; a comparison table is
  a paragraph, not a lab.
- **EtherChannel between the switches.** Deliberate — see decision D5.
- **BFD.** Sub-second detection is already available with HSRP millisecond timers
  and interface tracking; BFD deserves its own lab.
- **Inbound NAT / publishing services.** Same reasoning as Lab 07.
- **IPv6, stacking, VSS/vPC, fabric.** Out of scope for this repository.
- **Replacing router-on-a-stick with L3 switches.** It would throw away Lab 06's
  evidence for nothing this lab needs.

## 5. Topology

One node is added, two cables are added, and two switches get one and two extra
interfaces respectively.

```
                        ISP (vios)  Lo0 100.64.0.1/32
        Gi0/0 10.0.0.14/30 │ Gi0/1 200.1.1.1/24 │ Gi0/2 10.0.0.18/30 │ Gi0/3 10.0.0.22/30
              │                    │                     │                  │
   R1 Gi0/1 10.0.0.13/30            │                     │        R3 Gi0/1 10.0.0.21/30
              │                    │                     │                  │
        ┌─────┴─────┐        SRV-NET 200.1.1.10    (to R2/BR1)      ┌────────┴────────┐
        │    R1     │ Gi0/2 10.0.0.1/30 ───── transit ─────         │       R3        │
        │ Lo0 .1    │                                              │ Lo0 .3          │
        └─────┬─────┘                                              └────────┬────────┘
              │ Gi0/0 trunk        VLAN 200 CORE-TRANSIT (10.10.200.0/30)  │ Gi0/0 trunk
              │                    R1 .1  ──────  .2 R3                    │
        ┌─────┴─────┐  Gi0/4 ═══════ second trunk ═══════ Gi0/4   ┌────────┴────────┐
        │    SW1    │  Gi0/1 ─────── existing trunk ─────── Gi0/1  │       SW2       │
        │  (root    │                                              │  (root          │
        │  VLAN 10, │                                              │  VLAN 20,30,    │
        │  40, 99)  │                                              │  99, 200)       │
        └──┬─────┬──┘                                              └──┬─────┬───┬────┘
      PC1 │     │ PC2                                          PC3 │  PC4│  SRV-SEG
      VLAN 10   VLAN 20                                    VLAN 30  VLAN 30  VLAN 40
```

| Node | Change | Detail |
|---|---|---|
| `R3` | **added** (`vios`, 512 MB, `Lo0 10.255.0.3/32`) | second HQ router, trunk to `SW2` |
| `SW1` | adapters 4 → **5** | second inter-switch trunk |
| `SW2` | adapters 4 → **6** | second inter-switch trunk + trunk to `R3` |
| `ISP` | no new node, one new cable | `Gi0/3` `10.0.0.22/30` ↔ `R3 Gi0/1` |

**Design vs build (found in stage 1).** IOSvL2 puts the extra NICs in slot 1, not
slot 0: with 5 and 6 adapters the new ports are `Gi1/0` (`SW1` and `SW2`) and
`Gi1/1` (`SW2`), not `Gi0/4`/`Gi0/5`. Everything else in the design held. Two
GNS3 traps were recorded in section 20 in the same pass.

### Cabling added

| From | To | Purpose |
|---|---|---|
| `R3 Gi0/0` | `SW2 Gi0/5` | trunk: VLANs 10,20,30,40,99 + VLAN 200, native 999 |
| `SW1 Gi0/4` | `SW2 Gi0/4` | second inter-switch trunk (creates the L2 loop) |
| `R3 Gi0/1` | `ISP Gi0/3` | second HQ WAN link, `10.0.0.20/30` |

The trunk configuration on the new links copies the existing ones exactly —
`dot1q`, native 999, `nonegotiate`, allowed list `10,20,30,40,99` plus `200` on the
switch-to-switch links and on `R3`'s trunk.

## 6. Addressing

The important decision: **the VIPs keep the addresses the network already uses**,
and the two routers take new ones. Nothing else in the lab has to change — DHCP
scopes, DNS records, switch default gateways, ACLs, the branch relay and the
servers all point at `.1` today and still will.

| VLAN | Purpose | Virtual IP (HSRP) | `R1` | `R3` | Group |
|---|---|---|---|---|---|
| 10 | HR | `10.10.10.1/24` | `.2` | `.3` | 10 |
| 20 | Sales | `10.10.20.1/24` | `.2` | `.3` | 20 |
| 30 | IT | `10.10.30.1/24` | `.2` | `.3` | 30 |
| 40 | Servers | `10.100.0.1/24` | `.2` | `.3` | 40 |
| 99 | Management | `10.10.99.1/24` | `.2` | `.3` | 99 |
| 200 | **CORE-TRANSIT (new)** | — | `10.10.200.1/30` | `10.10.200.2/30` | — |

New point-to-point link and router ids:

| Device | Interface | Address | Note |
|---|---|---|---|
| `R3` | `Gi0/1` | `10.0.0.21/30` | WAN to `ISP Gi0/3` `10.0.0.22/30` |
| `R3` | `Lo0` | `10.255.0.3/32` | OSPF router-id, advertised |

Unchanged and deliberately so: `R1 Gi0/0.10-.99` keep their subinterface
*numbers*, `ip helper-address 10.100.0.10`, `ip nat inside`, and the existing OSPF
`network 10.10.0.0 0.0.255.255` swath — which now also covers VLAN 200, so VLAN 200
gets its own more specific statement and the LAN subinterfaces stay passive.

## 7. Gateway redundancy — HSRP

One group per VLAN, group number = VLAN number, so the state line and the VLAN
line can be read together. Active role is **split**, not all-on-one-router:

| VLAN | Active | Standby | Reason |
|---|---|---|---|
| 10 HR, 40 Servers, 99 Mgmt | `R1` (priority 150) | `R3` (100) | `R1` hangs off `SW1`, which is also the STP root for these VLANs |
| 20 Sales, 30 IT | `R3` (priority 150) | `R1` (100) | Same reasoning, the other way round |

On both routers, for every group:

```
! R1, VLAN 10 — the pattern repeats per VLAN
standby 10 ip 10.10.10.1
standby 10 priority 150
standby 10 preempt delay minimum 20
standby 10 authentication md5 key-string noc-lab-hsrp
standby 10 timers msec 250 msec 800
standby 10 track GigabitEthernet0/1 30
```

Four of those lines are judgement calls, and each one is worth being able to
defend:

- **`preempt delay minimum 20`** — without a delay, a router that just booted can
  win the active role back before OSPF has converged, and black-hole traffic for
  the length of that window. The delay is what makes the reclaim safe.
- **`authentication md5`** — plaintext HSRP lets anything on the segment claim a
  higher priority and become the gateway. This is a one-line fix for a real attack.
- **`timers msec 250 msec 800`** — the defaults (hello 3 s / hold 10 s) mean up to
  ten seconds of a dead gateway. The lab *measures* the defaults first and then the
  tuned values, and keeps the tuned ones: five groups × four hellos per second is
  20 packets per second per router, which is a fine price for sub-second failover.
- **`track GigabitEthernet0/1 30`** — a gateway without a working uplink is
  decoration. The decrement is 30, so `150 → 120` loses the election to the
  standby's 100... and that sentence is already a reason to look twice: with the
  VLAN-200 transit in place, `R1` *can* still reach the internet with its WAN down.
  This is a **policy** choice, not a reachability requirement, and the design
  records it as such: fail over because the active router should be the one with
  the direct path, not because it is the only one that works.

The virtual MACs follow the standard scheme (`0000.0c07.ac<group>`), which is what
makes the failover capture readable: the same MAC moves to a different physical
port.

## 8. Path redundancy — dual WAN with cost, not ECMP

`R3 Gi0/1` joins `R1 Gi0/1` on the ISP. Both routers now advertise the HQ prefixes
and both can reach the internet.

| Traffic | Primary | Backup | Mechanism |
|---|---|---|---|
| HQ → internet | `R1` (WAN cost 1) | `R3` (WAN cost 10) | OSPF cost on the WAN interface decides the default's forward metric |
| Internet → HQ | `R1` for VLAN 10/40/99, `R3` for 20/30 | the other router | `ip ospf cost 110` on the *standby's* LAN subinterface for that VLAN |
| HQ VLAN → HQ VLAN | the VLAN's active gateway | — | HSRP decides the first hop; the routers then route directly |

`ip ospf cost 110` on `R3 Gi0/0.10` (and `.40`, `.99`) and on `R1 Gi0/0.20`
(and `.30`) is the whole trick for path symmetry. It works because the cost a
router advertises for a subnet is the cost of **its interface in that subnet** —
so raising it on the standby makes every other router prefer the active one, which
is the same router the users' traffic leaves through. Without it, both routers
advertise each HQ prefix at cost 1, and inbound traffic can arrive at the standby
and then cross the VLAN-200 transit to reach the user's segment: working, but
asymmetric, and the sort of thing that breaks an ACL or a stateful device later.

**Not ECMP.** Equal-cost multipath would give more bandwidth and would guarantee
the asymmetry above, in both directions, on every flow. Primary/backup is the
honest design for a lab that is about *predictable* failover.

## 9. Layer 2 — the second trunk and STP root control

`SW1 Gi0/4 ↔ SW2 Gi0/4` makes a loop, which is the point: RSTP now has an election
to run and a port to block. Placing the root per VLAN is what makes the forwarding
tree agree with HSRP and OSPF:

```
! SW1
spanning-tree vlan 10,40,99 root primary
spanning-tree vlan 20,30,200 root secondary
! SW2 — the mirror image
spanning-tree vlan 20,30,200 root primary
spanning-tree vlan 10,40,99 root secondary
```

`root primary` and `root secondary` write priorities of 24576 and 28672, which is
what the existing config already does crudely for every VLAN on `SW1`.

The evidence for this section is a **table of blocked ports per VLAN**
(`show spanning-tree vlan X`) plus interface counters showing which of the two
inter-switch links carried a VLAN's traffic before and after. Latency is the wrong
measurement here — the two links are the same length — so the lab measures
*placement*, and says so.

## 10. NAT, and the rule Lab 07 got wrong

Lab 07 marked the `R1 ↔ R2` transit `ip nat outside` so that `R1` would translate
internet traffic leaving over it. A capture taken while writing this design shows
what that actually does when `R1`'s WAN is down: with `interface Gi0/1 overload`
and `Gi0/1` down, IOS creates no translation and the packet leaves **untranslated**.
Every echo request on the ISP link carried the private source `10.100.0.50`. It
only worked because the simulated ISP does not filter RFC1918 and has the HQ
prefixes in OSPF. A real ISP edge would have dropped it.

So Lab 08 changes the rule, on the Lab 07 transit as well as the new VLAN 200:| Interface | Marking | Why |
|---|---|---|
| LAN subinterfaces (`.10`–`.99`) on both routers | `ip nat inside` | the users |
| `VLAN 200` core transit, `R1 Gi0/2` transit to BR1 | `ip nat inside` | an internal path to another NAT box is not an exit |
| `Gi0/1` on both routers (the WAN links) | `ip nat outside` | the only exits |

With that marking, a packet that leaves HQ towards `R2` while `R1`'s WAN is down
arrives at `R2` on an *inside* interface and leaves through `R2`'s *outside* WAN —
so **`R2` does the translation**, using `R2`'s WAN address, and the reply comes
back to the router that owns it. The address on the internet link is then
`10.0.0.17`, not a private address. The same logic applies between `R1` and `R3`
inside the HQ.

The destination filter from Lab 07 becomes unnecessary in this shape (site-to-site
traffic is never inside-to-outside), so both routers run the simpler rule — one
standard access list, `NAT-INTERNAL`, permitting `10.10/16`, `10.20/16` and
`10.100/16`, and `ip nat inside source list NAT-INTERNAL interface Gi0/1 overload`.
The extended list and the route-map from Lab 07 are removed rather than left in
the config looking load-bearing.

**Second finding, same place.** Lab 07's `NAT-OVERLOAD-LIST` permitted `10.10/16`
and `10.20/16` but not `10.100/16` — the SERVERS/DC supernet the design document
*created* (decision DD-1 in the Lab 06 design). Every internet-bound packet from
`CLIENT` and the servers was therefore outside the NAT rule as well: another
private address leaving the lab, found the moment the list was read line by line.
Including `10.100/16` is the fix.

## 11. Management plane

`R3` joins the existing management plane, and everything that was true for `R1`
becomes true per-router:

- NTP from `10.100.0.13`, syslog to `10.100.0.11`, SNMP `labRO`/`labRW`, SSH v2,
  RSA 2048, `logging host`, `service timestamps`.
- The `MGMT-ACCESS` ACL on every device gains `10.10.99.3` (and `R3`'s loopback).
  An ACL written before the second router existed is exactly how a new device ends
  up unmanageable — the same trap Lab 06 recorded.
- One visible side effect to expect, not to fix: `R1`'s syslog source changes from
  `10.100.0.1` to `10.100.0.2` (the address it now owns), so the collector grows a
  new file name. The lab records the before/after so the change is explainable
  rather than surprising.

## 12. Convergence and failover

Five drills. Every one of them is measured with a timestamped ping from `CLIENT`
(`ping -D -n -i 0.3`) against a target that should stay reachable, plus a capture
that shows *why* the number is what it is.

| # | Drill | Expected outcome | What makes it interesting |
|---|---|---|---|
| A | Shut `R1 Gi0/0` (the trunk) | HSRP moves VLAN 10/40/99 to `R3`; HQ keeps working | HSRP and STP both react, OSPF does not |
| B | Shut `R1 Gi0/1` (the WAN) | Internet survives, now egressed by `R3` or `R2`; tracking moves the gateway too | Proves the corrected NAT rule and the tracking policy |
| C | Shut `SW1` (root + `R1`'s switch) | RSTP re-roots on `SW2`, HSRP fails over at the same moment | Two mechanisms, one cable, one timeline |
| D | Bring `R1` back | The active role returns after the preempt delay | The delay is only justified if it is visible |
| E | Re-run Lab 06/07 checks | PC1 DHCP, Sales→HR block, BR1 ping, NAT table, syslog files | Regression, not ambition |

Recorded per drill: **outage in seconds**, **packets lost**, and the **first packet
after recovery** identified in the capture. Two runs per HSRP drill where it
matters: default timers, then millisecond timers.

## 13. How we prove each requirement

| Requirement | The proof |
|---|---|
| Gateway survives a router failure | `show standby brief` on both routers before/after drill A; timed ping gap; the virtual MAC moving in the capture |
| The active gateway has a working uplink | Drills B; `show standby` showing the tracked interface and the decremented priority |
| Traffic enters the way it leaves | `show ip route` for each HQ prefix from `R2`/the ISP (one path, the active router's), plus a capture of a return flow |
| LAN survives one switch failing | Drill C; `show spanning-tree vlan X` root and blocked port before/after |
| Mechanisms measured, not asserted | The drill table, with packet counts, and each capture's four-line analysis |
| No regression | The Lab 06/07 rows re-run and recorded: DHCP leases, ACL block, branch reachability, NAT translations, syslog identity, SNMP answers |

## 14. Captures to take

| File | Link | Filter | The question it answers |
|---|---|---|---|
| `lab-08-hsrp-hellos.pcapng` | `SW1 ↔ SW2` trunk | `hsrp` | Who is talking, which group, which priority, and what is the virtual MAC |
| `lab-08-hsrp-failover.pcapng` | `SW1 ↔ SW2` trunk + access port | `arp \|\| icmp` | The gratuitous ARP when the standby takes over, and the gap in the ping |
| `lab-08-stp-bpdu.pcapng` | second inter-switch trunk | `stp` | Which link is blocked for which VLAN, and the TCN when the root disappears |
| `lab-08-egress-translation.pcapng` | `ISP ↔ SRV-NET` | `icmp` | That the failover egress is translated by the router that owns the working WAN — no private address on the wire |

The `SW1 ↔ SW2` trunk is captured rather than a router link on purpose: HSRP
hellos cross it, so both routers appear in one file.

## 15. Faults to inject

| # | Fault | Symptom | Root cause | How it is found |
|---|---|---|---|---|
| 1 | `R3` runs group **2** on VLAN 20 while `R1` runs group 20 | Intermittent loss on PC2 only; both routers insist they are active | Two groups = two actives on one segment; the VIP is claimed twice | `show standby brief` on both, then a capture showing two different MACs answering ARP for `10.10.20.1` |
| 2 | `no standby 10 preempt` on `R1` | After any drill, `R1` stays standby forever; the OSPF cost tuning now points the wrong way | Preempt off means the higher priority never takes the role back | `show standby brief` shows `Pri 150` but `Standby`, and the path is asymmetric |

Fault 3 (root bridge placement) is listed as a **question** in the lab guide
rather than an injected fault, because its symptom is a change of *placement*, not
of reachability — the honest evidence is a counter, not a ping.

## 16. Order of work

Each stage ends in a checkpoint that can be tested on its own, and the rollback
for every stage is the exported configuration from the previous one.

| Stage | Work | Checkpoint |
|---|---|---|
| 0 | Export all six configs (already done, `configs/lab-07/`), note the GNS3 project state | Rollback point exists |
| 1 | Add `R3`, extra adapters on `SW1`/`SW2`, the second inter-switch trunk, `R3`'s WAN link | `SW1`/`SW2` boot with their saved config and their new port; `R3` is a factory `vios` with a trunk up |
| 2 | Address shift on `R1` (`.1` → `.2`) and HSRP on both routers, VLAN 200 adjacency, in one maintenance window | `show standby brief` shows one Active and one Standby per group; `ping` to every VIP works from a PC in that VLAN |
| 3 | OSPF cost tuning + passive defaults + `timers throttle spf` | `show ip route` on `R2` shows one path per HQ prefix, via the VLAN's active router |
| 4 | Second trunk + STP root control | `show spanning-tree vlan X` shows the intended root and exactly one blocked inter-switch port |
| 5 | HSRP behaviour: measure default timers, then apply `msec`, `preempt delay`, MD5, tracking | Drill A measured twice, with two numbers |
| 6 | `R3` management plane + `MGMT-ACCESS` on every device; fix the NAT marking on the Lab 07 transit as well | `R3` appears in syslog/SNMP; the egress capture shows a router address, not `10.100.0.50` |
| 7 | Drills A–E, four captures, fault 1, fault 2 | The verification table is filled with real output |
| 8 | Lab guide, design-vs-build diff, config export, status flips, commit | `labs/lab-08-redundancy/README.md` exists and the repo says done |

## 17. Budget and limits

| Limit | Reality | Mitigation |
|---|---|---|
| Host RAM (9.6 GB, `earlyoom` active) | `R3` is the fourth `vios` | 512 MB like the others; if the host starts reclaiming, drop `R3` to 384 MB and start it last |
| IOSvL2 interfaces | 16 supported, so 5 and 6 are fine | Verified against Cisco's IOSvL2 feature list before writing this |
| Changing adapters = node restart | `vios_l2` takes 4–5 minutes to boot | Do `SW1` and `SW2` in one window, with `configs/` as the rollback |
| No SPAN on IOSvL2 | Every capture is a link capture | Captures are chosen on trunks that carry the traffic of interest |
| Host power-offs have cost configurations before | `write memory` is not durability | Export after each stage; close the project before any planned shutdown |
| One maintenance window | The address shift on `R1` is the risky moment | It is one command batch: change the subinterface address and add the HSRP group in the same pass |

## 18. Decisions

| # | Decision | Alternative considered | Why this one |
|---|---|---|---|
| D1 | Add a second HQ router (`R3`) for HSRP | Make `SW1`/`SW2` the gateway pair with SVIs | Keeps router-on-a-stick and every piece of Lab 06 evidence intact |
| D2 | VIPs keep `.1`; routers become `.2`/`.3` | Move the network to new gateway addresses | Nothing else in the lab has to change — DHCP, DNS, ACLs, switches, the branch relay |
| D3 | Split the active role per VLAN | One router active for everything | Uses both uplinks, and gives STP root control something to agree with |
| D4 | OSPF adjacency only on VLAN 200; LAN subinterfaces passive | Let OSPF form on all five VLANs | Five adjacencies is noise; a distribution pair uses a dedicated transit |
| D5 | Second inter-switch link is a plain trunk | EtherChannel between the switches | An EtherChannel removes the blocked port, and this lab is partly about STP |
| D6 | Dual WAN, primary/backup by cost | ECMP across both WANs | ECMP guarantees the asymmetry section 8 exists to prevent |
| D7 | Transit and VLAN 200 are `ip nat inside` | Lab 07's `outside` marking | Corrects a real leak, proved with a capture (section 10) |
| D8 | Keep HSRP millisecond timers and MD5 auth; preempt with a 20 s delay | Defaults, plaintext auth, instant preempt | Sub-second failover, no spoofing, no black hole during return |
| D9 | Track the WAN with a 30 decrement | No tracking | A policy choice: the active gateway should hold the direct path, and the lab states that it is a choice |
| D10 | Two injected faults, one STP question | Three injected faults | Fault 3 has no reachability symptom, so it is better as a guided question |

## 19. Status

| Item | State |
|---|---|
| Design | agreed (2026-10-17) — this document |
| Build | **stage 1 complete**, stage 2 in progress |
| Prerequisites | Labs 06 and 07 complete; `configs/lab-07/` exported; the Lab 07 drill-B correction recorded |
| Riskiest step | Stage 2, the address shift on `R1` — one window, HSRP configured in the same batch |

## 20. Build notes

Things the build taught that the design did not know. Kept here as they happen,
because the guide is written from them.

**Changing adapters breaks the pre-existing links.** After `SW1` and `SW2` were
given 5 and 6 adapters and restarted, every port that was cabled *before* the
change reported `notconnect` — the new NICs were up, the old ones were not. GNS3
left those NICs in the link-down state and did not re-apply it on start. The QEMU
monitor's `set_link gns3-N on` is what GNS3 itself uses to bring a link up, so
`linkup.py` in the helper directory does exactly that for every NIC of a named
node. **It has to be run after every restart of a switch in this lab**, which
matters for the drill that shuts `SW1` down. The settings survive the run but not
a restart.

**Never send `quit` to the QEMU monitor.** It powers the VM off. It was sent
while probing the link state, and `SW1` came back up in the GRUB shell instead of
IOS: the guest filesystem's boot path had been damaged by the unclean kill, while
the qcow2 itself checked out clean (`qemu-img check`). The fix was to rebuild the
node's overlay disk from the appliance image (`qemu-img create -f qcow2 -F qcow2
-b <base> hda_disk.qcow2`) and re-apply `configs/lab-07/SW1.cfg`. The damaged
overlay is kept next to it as `hda_disk.qcow2.grub-broken-20261017`.

**`exit` in an applied command file leaves configuration mode.** A stray `exit`
after the global settings in `r3-base.txt` sent every following line into enable
mode, where `interface Loopback0` is an invalid command. The whole first R3 pass
was a no-op past the hostname. Worth remembering: the helper sends lines blind,
so a command file is a script, not a transcript.

**A node cloned through the API inherits the source node's MAC base.** `R3` was
created by posting `R1`'s node body with a new name, so it kept
`mac_address = 0c:9d:c6:ef:00:00`. GNS3 derives *every* adapter MAC from that
base (`…:00:00`, `…:00:01`, …), so `R1` and `R3` were on the wire with identical
MACs for all four ports. The visible symptoms, all of which look like routing
faults rather than an L2 fault:

* every HSRP group showed `Active / unknown` on **both** routers — each was
  hearing its own virtual MAC fragments, never a peer hello;
* no OSPF adjacency formed over VLAN 200 (`R1` and `R3` are the only pair that
  shares a broadcast domain on identical MACs);
* `SW2` learned `R1`'s MAC on `R3`'s port `Gi1/1`.

Fix: give the node a unique `mac_address` and restart it. Check a cloned node
with `show interface GigabitEthernet0/0 | include [Hh]ardware` on both routers —
if the two addresses match, nothing else in the lab will work.

**A link can be up at both ends and still carry nothing.** After the adapter
change, `SW1 Gi0/1 ↔ SW2 Gi0/0` (the original inter-switch trunk) read
`connected` + `trunking` on both ends, both ends were *transmitting* (STP
BPDUs), and both ends showed `0 packets input`. `R1 ↔ SW1` was in the same
state. The link existed in the project with correct adapter numbers and
`suspend: false`; its NIO pair was simply not passing frames, and a restart alone
did not repair it. Deleting and recreating the link (which allocates fresh NIO
ports) did. The diagnostic that finds this in one step is `show cdp neighbors`
plus the input counters on both ends of the link, not the interface state.

**An IOSvL2 VLAN database is not in `startup-config`.** `vlan 200` /
`name CORE-TRANSIT` lives in `flash:vlan.dat`, so
`show startup-config | include ^vlan 200` prints nothing even when the VLAN is
saved and does survive a reload. That check gives a false negative — the honest
test is `show vlan brief` after the reload.

**The adapter change silently dropped a link.** `SW1 Gi0/2 ↔ PC1` vanished from
the project during the build: `SW1` still showed the port as `PC1-HR` and
`notconnect`, while uBridge still held a stale bridge for the PC1 node. Diffing
the live link list against `lab-06-hq.gns3.pre-lab08` is how it was caught — that
comparison is now part of the stage-1 check. Recreating it needs the VPCS node
stopped first, otherwise the API answers `409 … bridge 'VPCS-…' already exist`.

**Order that worked.** Stop `R1`, `R3`, `SW1`, `SW2`; recreate the two suspect
links; start the four; run `linkup.py` for every restarted node (plus `ISP`, which
was not restarted — `set_link` works on a running VM); then verify with CDP and
counters. HSRP came up in the designed roles on the first try after that, and
`R1` formed `FULL/DR` with `R3` over `Gi0/0.200`.

