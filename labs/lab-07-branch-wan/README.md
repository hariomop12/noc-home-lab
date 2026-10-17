---
lab: 07
level: combo
status: done
tags: [homelab, lab, design, wan, ospf, nat, pat, dhcp-relay, multi-site, failover]
---

# Lab 07 — Branch + WAN + NAT

## Metadata

| Field | Value |
|---|---|
| Level | combo |
| Estimated time | 2 days (design, build, verify, capture, fault) |
| Prerequisites | Labs 01–06 — VLANs, trunking, router-on-a-stick, OSPF, ACLs, DHCP relay, management plane |
| Skills practised | Multi-site design, WAN edge, static-then-OSPF migration, OSPF convergence, NAT/PAT overload, DHCP relay across sites, failover timing, packet-level OSPF |
| Related docs | [Design document](../../docs/designs/branch-wan-design.md), [IP plan](../../docs/01-ip-plan.md), [Wireshark guide](../../docs/09-wireshark-guide.md), [Docker images](../../docker/README.md) |

## Objective

After this lab I can connect a **second site** to the HQ from Lab 06 through a
simulated ISP, give it real routing (static first, then OSPF), let both sites reach
the internet through **one translated address each**, and prove that a failed WAN
link recovers — with the recovery measured in seconds and explained from the packet
level up.

The design is given as a specification in
[../../docs/designs/branch-wan-design.md](../../docs/designs/branch-wan-design.md).
The lab is to build it, then diff reality against it.

## Theory

- **Two sites, two paths.** HQ and BR1 each have a WAN link to the ISP and a
  *transit* link between them. The transit is the preferred path for HQ↔BR1 traffic
  because it is **one hop**; the WAN path costs two. No cost tuning is involved —
  hop count decides, which is exactly what you want to be able to say when someone
  asks why the traffic took the internal link.
- **One default route for everyone.** The ISP originates `0.0.0.0/0` with
  `default-information originate`, so both sites learn it as `O*E2 0.0.0.0/0`.
  A static default would forward just as well and would prove nothing about the
  routing protocol.
- **NAT is a source *and* a destination decision.** `overload` (PAT) lets many
  inside hosts share one outside address, told apart by port. A source list alone
  does not keep site-to-site traffic routed *in this topology*, because the transit
  was marked `ip nat outside` on both routers, which makes BR1→HQ an
  inside-to-outside flow. The destination filter (deny everything in `10/8`,
  permit the rest) is what says "translate only what is leaving the lab". Without
  it, both sites translate the same flow and it dies — and BR1's management
  traffic arrives at the collector wearing the router's WAN address. **The cleaner
  answer, applied in Lab 08, is to mark that transit `inside`: then it is not an
  inside-to-outside flow at all and no destination filter is needed.** See the
  correction in the convergence section.
- **A relayed DHCP request is a unicast with a return path.** The branch has no
  server, so `R2 Gi0/0.10` stamps the client's subnet into `giaddr`
  (`10.20.10.1`) and unicasts to HQ. The server answers into the subnet `giaddr`
  names, which is why one `dnsmasq` can serve three HQ VLANs and a branch.
- **Convergence is a number, not a feeling.** "The link came back" is not evidence.
  A timed ping across the failure, plus the last hello and the first data packet in
  a capture, is evidence.

## Topology

```
                        ISP (vios)   Lo0 100.64.0.1/32
                     Gi0/0 10.0.0.14/30 │ Gi0/2 10.0.0.18/30
                                        │
        Gi0/1 10.0.0.13/30              │            Gi0/1 10.0.0.17/30
              │                         │                  │
        ┌─────┴─────┐                   │            ┌─────┴─────┐
        │    R1     │  Gi0/2 10.0.0.1/30 │ Gi0/2 10.0.0.2/30 │    R2     │
        │  (vios)   ├─────────── transit ┴───────────────────┤  (vios)   │
        │ Lo0 .1    │                                       │ Lo0 .2    │
        └─────┬─────┘                                       └─────┬─────┘
              │ Gi0/0 trunk 10,20,30,40,99                        │ Gi0/0 trunk 10,99
        ┌─────┴─────┐                                        ┌────┴────┐
        │    SW1    │──── trunk ──── SW2 (HQ, VLANs)          │   SW3   │
        └─────┬─────┘                                        └──┬───┬──┘
              │                                                 │   │
        PC1 (HR) PC2 (Sales)  PC3 PC4 (IT)                    PC5   PC6
        VLAN 10  VLAN 20      VLAN 30                       VLAN 10 VLAN 10
              │
        VLAN 40 10.100.0.0/24 : SRV-DNS .10  SRV-SYSLOG .11  SRV-WEB .12  SRV-NTP .13  CLIENT .50

        ISP Gi0/1 200.1.1.1/24 ──── SRV-NET 200.1.1.10/24   (the "public internet")
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | `vios` | Gi0/1 | `10.0.0.13/30` | WAN to ISP, `ip nat outside` |
| R1 | `vios` | Gi0/2 | `10.0.0.1/30` | transit to R2, `ip nat outside` |
| R1 | `vios` | Gi0/0.x | `10.10.x.1`, `10.100.0.1` | HQ gateways (Lab 06), `ip nat inside` |
| ISP | `vios` | Gi0/0 / Gi0/2 | `10.0.0.14/30` / `10.0.0.18/30` | both WAN links, OSPF, default originator |
| ISP | `vios` | Gi0/1 | `200.1.1.1/24` | the simulated internet edge |
| R2 | `vios` | Gi0/0.10 | `10.20.10.1/24` | BR1 users gateway, DHCP relay, `ip nat inside` |
| R2 | `vios` | Gi0/0.99 | `10.20.99.1/24` | BR1 management |
| R2 | `vios` | Gi0/1 | `10.0.0.17/30` | WAN to ISP, `ip nat outside` |
| R2 | `vios` | Gi0/2 | `10.0.0.2/30` | transit to R1, `ip nat outside` |
| R2 | `vios` | Lo0 | `10.255.0.2/32` | OSPF router-id |
| SW3 | `vios_l2` | Gi0/0 / Gi0/1,2 | — | trunk to R2, access: PC5, PC6 |
| SW3 | `vios_l2` | Vlan99 | `10.20.99.13/24` | management SVI |
| PC5, PC6 | VPCS | eth0 | DHCP `10.20.10.100+` | BR1 users, relic of the manual stage below |
| SRV-NET | `web:lab` | eth0 | `200.1.1.10/24` | the "public internet" web server |

## Build steps

1. Read the [design document](../../docs/designs/branch-wan-design.md) end to end.
2. **Rename** the Lab 06 project to `lab-07-branch-wan` — in place. Do not Save-as
   and do not Duplicate: those produce new node IDs and therefore blank disks.
3. Confirm HQ survived the rename before adding anything.
4. Add R2, SW3, PC5, PC6 and SRV-NET; cable per the design. Note that `SRV-NET`
   needs `LAB_IP=200.1.1.10/24` and `LAB_GW=200.1.1.1` in the node's Environment —
   the image default is the HQ web server address.
5. Configure BR1's L2 (VLANs, access ports, trunk, management SVI), then R2
   (subinterfaces, WAN, transit, loopback, DHCP relay).
6. **Stage 1 — static routing**, briefly, and record `show ip route`.
7. **Stage 2 — OSPF**: same reachability, then prove the transit is preferred.
8. NAT: show the failure first, then configure PAT on both routers, then prove two
   inside hosts share one outside address.
9. Management plane for R2 and SW3, **including the `MGMT-ACCESS` update on every
   device** (a branch that can reach the poller is useless if the poller's reply is
   filtered by an ACL written before the branch existed).
10. DHCP/DNS: rebuild `dnsmasq:lab` with the BR1 scope, restart SRV-DNS, lease a
    PC in BR1.
11. Work the verification table in section 13 of the design. Then capture, then
    inject the MTU fault and fix it.

## Configuration

Only what this lab adds is shown; the full exported configurations are in
[`configs/lab-07/`](../../configs/lab-07/).

### R2 — the branch edge

```
interface GigabitEthernet0/0.10
 description BR1-USERS
 encapsulation dot1Q 10
 ip address 10.20.10.1 255.255.255.0
 ip helper-address 10.100.0.10
 ip nat inside
!
interface GigabitEthernet0/0.99
 description MGMT
 encapsulation dot1Q 99
 ip address 10.20.99.1 255.255.255.0
 ip nat inside
!
interface GigabitEthernet0/1
 description WAN-TO-ISP
 ip address 10.0.0.17 255.255.255.252
 ip nat outside
!
interface GigabitEthernet0/2
 description TRANSIT-TO-R1
 ip address 10.0.0.2 255.255.255.252
 ip nat outside
!
router ospf 1
 router-id 10.255.0.2
 passive-interface default
 no passive-interface GigabitEthernet0/1
 no passive-interface GigabitEthernet0/2
 network 10.0.0.0 0.0.0.3 area 0
 network 10.0.0.16 0.0.0.3 area 0
 network 10.20.0.0 0.0.255.255 area 0
 network 10.255.0.2 0.0.0.0 area 0
```

### NAT/PAT — the part that is easy to get wrong

```
ip nat inside source route-map NAT-OVERLOAD interface GigabitEthernet0/1 overload
!
ip access-list extended NAT-OVERLOAD-LIST
 deny   ip 10.10.0.0 0.0.255.255 10.0.0.0 0.255.255.255
 deny   ip 10.20.0.0 0.0.255.255 10.0.0.0 0.255.255.255
 permit ip 10.10.0.0 0.0.255.255 any
 permit ip 10.20.0.0 0.0.255.255 any
!
route-map NAT-OVERLOAD permit 10
 match ip address NAT-OVERLOAD-LIST
```

Two builds failed before this one, and both failures are in the lab note because
the second one is a genuine trap:

- **Attempt 1 — the textbook one-liner.**
  `ip nat inside source list NAT-INTERNAL interface Gi0/1 overload` translates
  HQ↔BR1 traffic, because the transit is `ip nat outside` (it has to be, for the
  failover drill). The proof is in `show ip nat translations` on R1: entries whose
  *outside local* is `10.20.10.163` — a lab address. `PC5 → PC1` timed out, and
  SW3's syslog arrived at the collector as `10.0.0.17`, R2's WAN address.
- **Attempt 2 — a route-map that looked right.** `route-map NAT-OVERLOAD` with
  `match ip address NAT-INTERNAL` and `match ip address NAT-EXTERNAL` on separate
  lines. **Multiple `match ip address` lines in the same sequence are OR'd**, and
  the external list ends in `permit any`, so everything matched — identical
  behaviour to attempt 1.
- **Attempt 3 — one extended ACL, matching source *and* destination.** The two
  `deny` lines are what refuse to translate traffic whose destination is another
  lab prefix; the `permit` lines are the rest. Site-to-site came back in both
  directions in the same change, and the translation table stopped showing lab
  addresses.

### SW3 — the branch switch

```
vlan 10
 name USERS
vlan 99
 name MGMT
vlan 999
 name PARKING
!
interface GigabitEthernet0/0
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,99
 switchport mode trunk
 switchport nonegotiate
!
interface Vlan99
 ip address 10.20.99.13 255.255.255.0
!
ip routing
ip route 0.0.0.0 0.0.0.0 10.20.99.1
```

`vios_l2` boots with `ip routing` on, so `ip default-gateway` is stored and
**ignored** — the static default is what lets the switch reach NTP, syslog and the
poller. Same gotcha as Lab 06, same symptom.

### ISP — the default originator

```
router ospf 1
 router-id 100.64.0.1
 network 10.0.0.12 0.0.0.3 area 0
 network 10.0.0.16 0.0.0.3 area 0
 network 100.64.0.1 0.0.0.0 area 0
 default-information originate always
!
ip route 0.0.0.0 0.0.0.0 Null0
```

## Verification

Rows follow section 13 of the design. Commands were run on the device named, or
from `CLIENT` (`noc-tools:lab`).

| # | Requirement | Command | Expected | Actual |
|---|---|---|---|---|
| 1 | Branch LAN up | `show ip interface brief` (R2) | Gi0/0.10, .99, Gi0/1, Gi0/2, Lo0 up/up | ✅ `.10 10.20.10.1`, `.99 10.20.99.1`, `Gi0/1 10.0.0.17`, `Gi0/2 10.0.0.2`, `Lo0 10.255.0.2` — all up/up |
| 2 | OSPF neighbours | `show ip ospf neighbor` (R2) | ISP and R1 FULL | ✅ `100.64.0.1` FULL/DR (Gi0/1), `10.255.0.1` FULL/DR (Gi0/2) |
| 3 | Same on the other side | `show ip ospf neighbor` (R1, ISP) | R2 FULL | ✅ R1: `10.255.0.2` FULL/BDR; ISP: `10.255.0.2` and `10.255.0.1` FULL/BDR |
| 4 | Shared default route | `show ip route` (R1, R2) | `O*E2 0.0.0.0/0` | ✅ on both, learned from the ISP |
| 5 | Transit preferred | `show ip route 10.20.10.0` (R1) | via `10.0.0.2` on Gi0/2 | ✅ `ospf 1, metric 2, via GigabitEthernet0/2` |
| 6 | Branch DHCP relayed | `ip dhcp` (PC5, PC6) | lease from `10.20.10.100+` handed out by the **HQ** server | ✅ PC5 `10.20.10.163/24`, PC6 `10.20.10.164/24`, gateway `10.20.10.1`, DNS `10.100.0.10` — served by `dnsmasq` at HQ, two hops away |
| 7 | DNS across sites | `dig +short web.lab.local @10.100.0.10` (CLIENT) | `10.100.0.12` | ✅ `web.lab.local → 10.100.0.12`, `sw3.lab.local → 10.20.99.13` |
| 8 | Site-to-site both ways | `ping` PC5↔PC1 | replies both directions | ✅ PC1→PC5 5/5, PC5→PC1 5/5 (`ttl 62`, ~3-4 ms) — after the NAT fix, not before |
| 9 | Internet reachable | `ping 200.1.1.10` (PC1, PC2, PC5) | replies | ✅ 5/5 from each, `ttl 62` |
| 10 | PAT overload | `show ip nat translations` (R1) | two inside locals → one inside global | ✅ `10.0.0.13:47098 ← 10.10.10.165:47098` and `10.0.0.13:44282 ← 10.10.20.162:44282`, 10 active translations, identifier per flow |
| 11 | Internet sees one address | capture ISP↔SRV-NET | source is a router address, not a private host address | ✅ ten echo requests from `10.0.0.13` and five from `10.0.0.17`; **no private address on the wire** |
| 12 | Branch monitored | `ls -l /var/log/remote/` (SRV-SYSLOG), `snmpget` (CLIENT) | branch files, SNMP answers | ✅ `10.0.0.2.log` (R2) and `10.20.99.13.log` (SW3); `sysName.0 = R2.lab.local` and `SW3.lab.local` |
| 13 | OSPF at packet level | `ospf` capture on the transit | Hello, then DBD/LSR/LSU/LSAck | ✅ after `clear ip ospf process`: 15 Hello, 10 DBD, 2 LSR, 22 LSU, 14 LSAck |

### Where the build differs from the design

| Design said | Built | Why |
|---|---|---|
| Transit is preferred, no cost tuning | ✅ verified `metric 2 via Gi0/2` vs `metric 3` via the ISP | One hop beats two; hop count decided it, so nothing was engineered to make it look true |
| NAT filters on source **and** destination | ✅ but only after two failed shapes (source list, then a two-`match` route-map) | See the NAT section — the second failure is a route-map OR trap worth knowing |
| SRV-NET is the public internet, `200.1.1.10/24` | ✅ set through the node's Environment (`LAB_IP`, `LAB_GW`) | The image default is the HQ web server's address; the node needs the override |
| Static NAT / port forwarding from the internet in | ❌ deliberately out of scope | Design decision O6 — this lab proves outbound translation and failover only |
| IPv6, redistribution, policy routing | ❌ not built | Design decision O2 and the "keep Phase 3 simple" rule |
| One OSPF area, ISP originates the default | ✅ area 0 everywhere, `O*E2 0.0.0.0/0` on both sites | Design decision O7; a static default would forward traffic and prove nothing |

## Capture exercise

Four captures, one per question the design asks. All in
[`wireshark/`](../../wireshark/).

| File | Link | Filter | What it proves |
|---|---|---|---|
| `lab-07-branch-wan-nat.pcapng` | ISP ↔ SRV-NET | `icmp` | the same request before and after NAT, on the internet side |
| `lab-07-branch-wan-ospf-hello.pcapng` | R1 ↔ R2 transit | `ospf` | who is in area 0, hello/dead timers, DR/BDR election |
| `lab-07-branch-wan-ospf-dbd.pcapng` | R1 ↔ R2 transit, after a clear | `ospf` | the database exchange: DBD, LSR, LSU, LSAck |
| `lab-07-branch-wan-failover.pcapng` | transit + ISP path | `ospf \|\| icmp` | the reconvergence timeline: last hello, route change, first data packet |

Answered from the captures, not from memory:

- [x] **The internet sees one address per site, not one per host.** On the
      `ISP ↔ SRV-NET` link the ten HQ echo requests all carry source `10.0.0.13`
      and the five BR1 ones carry `10.0.0.17`; no packet carries `10.10.x` or
      `10.20.x`. The inside hosts are `10.10.10.165`, `10.10.20.162` and
      `10.20.10.163`, and the router tells them apart by the ICMP identifier —
      which is exactly the entry `show ip nat translations` prints.
- [x] **OSPF hellos are multicast and carry the failure timers.** Every hello goes
      to `224.0.0.5` from `10.0.0.2`, `Area 0.0.0.0`, hello 10 s, dead 40 s,
      DR `10.0.0.2`, BDR `10.0.0.1`. Those two numbers are the worst-case
      detection time for a failure the link itself does not report.
- [x] **The database exchange is a conversation.** After `clear ip ospf process`
      one capture holds 15 Hello, 10 DBD, 2 LSR, 22 LSU and 14 LSAck — the whole
      adjacency coming back up. The DBD carries an MTU field, which is why fault
      #1 stops the neighbour while every interface light stays green.
- [x] **Failover is the same flow on a different link.** The file merges two
      captures. The `CLIENT → 10.20.10.163` echo flow (`seq` 71 onward) appears on
      the **ISP** link — traffic that the router's table had pointed at the transit
      a second earlier. The transit side of the file carries the OSPF reaction to
      the change (18 hello, 15 LSU, 9 LSAck).

## Convergence and failover

Measured with `ping -D -n -i 0.3` from `CLIENT`, one run per drill, loss counted
from the gaps in the sequence numbers — not from a stopwatch.

| Drill | Probe | First run: outage / probes lost | Second run (warm) | What the device shows |
|---|---|---|---|---|
| A — transit down (`R1 Gi0/2` shut) | `CLIENT → 10.20.10.163` (BR1) | **5.8 s / 18** | **< 0.3 s / 0** | on recovery `show ip route 10.20.10.0` is `metric 3 via 10.0.0.14 Gi0/1` — the ISP path |
| B — HQ WAN down (`R1 Gi0/1` shut) | `CLIENT → 200.1.1.10` (internet) | **5.8 s / 18** | — | during the outage `show ip route 0.0.0.0` is `O*E2 via 10.0.0.2 Gi0/2`: the default was relearned **from the ISP through the transit** — but see the correction below |
| — with `ip ospf hello-interval 1` / `dead-interval 4` and `timers throttle spf` on the transit | `CLIENT → 10.20.10.163` | **< 0.3 s / 0** | — | `show ip ospf interface Gi0/2` → `Hello 1, Dead 4, Wait 4, Retransmit 5` |

The honest reading of the two numbers, because the first one is not the timers:

**Correction, found while designing Lab 08 (2026-10-17).** Drill B passes, but not
for the reason this lab first claimed. With `ip nat inside source ... interface
Gi0/1 overload` and `Gi0/1` down, IOS never creates the translation — the address
left with the interface — and the packet is forwarded **untranslated**. The
capture during the drill proves it: all 25 echo requests on the `ISP ↔ SRV-NET`
link carry source `10.100.0.50`, a private address, and the replies come back
because the simulated ISP is not filtering RFC1918 and has the HQ prefixes in its
OSPF table.

A real ISP edge filters private source addresses, so this drill would have failed
there. The rule this lab teaches is narrower than it looked: marking the transit
`ip nat outside` makes *this* router translate on it, which is right while its WAN
is up and useless when it is down. The cleaner placement — used in Lab 08 — is to
leave the internal path to a NAT partner **inside**, so the router whose WAN is
actually up does the translation.

Also true, and the reason the two runs differ:

- **The trigger is a link-down event, so the timer change did not cause the
  difference.** A shut interface is reported immediately; OSPF then runs SPF and
  installs the backup path. The first run paid for a cold path — SPF computation,
  route install and ARP for the ISP next hop — and the second run found all of it
  warm. Sub-300 ms is the steady-state answer; 5.8 s is what the very first
  failure after a boot costs.
- **Hello and dead timers matter for the failure the link cannot report** — a
  middlebox that swallows packets while the interface stays up. There, 40 s is
  how long the router keeps pointing at a dead path; at hello 1 / dead 4 it is
  4 s. Tuning them is a trade, not a free win: 1 s hellos are 10× the control
  traffic on every path, which is why the lab keeps the defaults in the saved
  configuration and only measures the tuned case.

## Break it / fix it

Fault #1 from the design: **make the transit MTUs disagree**.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | Give `R2 Gi0/2` MTU 1400 and leave `R1 Gi0/2` at 1500, then `clear ip ospf process` | neighbour stuck in **EXCHANGE/EXSTART** while the interface is up/up, and HQ→BR1 silently moves to the two-hop ISP path | OSPF DBD packets must agree on MTU; the neighbour refuses to exchange a database it cannot size | remove the mismatch (`no ip mtu 1400`); the adjacency goes to FULL on its own |

Observed on the real devices, which is why the fault stays in the lab:

```
R1# show ip ospf neighbor
100.64.0.1   1  FULL/DR        00:00:32  10.0.0.14   GigabitEthernet0/1
10.255.0.2   1  EXCHANGE/BDR   00:00:39  10.0.0.2    GigabitEthernet0/2     <-- stuck
R1# show ip route 10.20.10.0
  Known via "ospf 1", metric 3, ... via 10.0.0.14, GigabitEthernet0/1         <-- backup path
```

Then `no ip mtu 1400` on R2 → the route is back to `metric 2 via 10.0.0.2
GigabitEthernet0/2` within seconds. Note the shape of the symptom: users still had
connectivity, it just took the expensive path, and the only visible clue on the
router was one neighbour that never finished loading. "Check the control plane, not
just the lights" — same shape as ticket **T-05**.

## Self-check questions

1. HQ↔BR1 traffic uses the transit, and no OSPF cost was tuned. Why?
2. Both sites learn a default route from the ISP. What breaks if you replace
   `default-information originate` with a static default on each router?
3. The transit interface is `ip nat outside` even though it is not the internet.
   Give the drill that requires it.
4. Explain, packet by packet, why `PC5 → PC1` fails when NAT matches on the source
   list only.
5. A branch DHCP client broadcasts in VLAN 10 and is answered by a server two hops
   away. Which field told the server which range to use?
6. SW3's syslog is collected as `10.20.99.13`, but during the first build it
   appeared as `10.0.0.17`. What was happening, and what single object fixed it?

## What I learned

- **NAT needs a destination rule, and it has to be in one ACL.** The textbook
  one-liner works until the same router also has a non-internet path marked
  `outside`. The "obvious" repair — two `match ip address` lines in one route-map
  sequence — silently does nothing, because those lines are OR'd and the second
  list ends in `permit any`. One extended ACL matching source *and* destination is
  the shape that actually works, and it fixed the management plane in the same
  change.
- **A drill can pass for the wrong reason, and only a packet shows it.** Drill B
  reported zero loss and looked like proof that the backup path translated
  correctly. A capture taken while designing Lab 08 shows every request leaving
  with the private source `10.100.0.50`. The lesson is not "the drill was wrong" —
  the drill found something real — it is that a green ping is not evidence about
  *how* the packet got there.
- **A management-plane symptom is a data-plane symptom.** The syslog file named
  after R2's WAN address was the same bug as the dead ping, seen from the other end.
  Monitoring found the fault before the users did — which is the whole point.
- **`write memory` is not durability.** A node's disk write can still be lost if
  the *host* is powered off abruptly, because the emulator holds it in cache. Two
  devices came back factory-fresh after a host restart while four (written days
  earlier) were fine. Closing the project before powering off flushes it; exporting
  the configs is the backup that survives everything.
- **GNS3 keeps a docker container id in the project file.** After a reboot the
  containers are gone but the id is not, and the node then refuses to start with
  `No such container`. Setting `properties.container_id` to null in the `.gns3`
  file while the project is closed is the fix — and a rebuilt image still needs a
  fresh container, not a restart, to be adopted.
- **A DHCP scope is chosen by `giaddr`, not by which server is nearest.** One
  `dnsmasq` serves three HQ VLANs and a branch because the relay tells it which
  subnet to answer into.
- **A first failure is not the same failure as the second one.** The same drill
  cost 5.8 s cold and under 300 ms warm. The difference was SPF, route install and
  ARP for the backup next hop — not the hello/dead timers, which only decide how
  fast a *silent* path is declared dead. Measure twice, and say which number you
  are quoting.
- **The expensive failure is the one that still works.** The MTU mismatch never
  dropped a packet — it moved every HQ↔BR1 flow onto the two-hop path and left one
  neighbour stuck in EXCHANGE. No alarm, no down interface, just a bill nobody
  looks at. That is the argument for the management plane existing at all.

## Cleanup

- [x] Configs exported to `configs/lab-07/` (R1, ISP, SW1, SW2, R2, SW3)
- [x] Captures saved in `wireshark/lab-07-branch-wan-*.pcapng` (4 files)
- [x] Fault injected, diagnosed, fixed, re-verified
- [x] Status flipped in `labs/README.md`, main `README.md`, `docs/00-roadmap.md`
- [ ] GNS3 project closed (not suspended) — leave open for the Lab 08 build
- [x] Committed with a specific message
