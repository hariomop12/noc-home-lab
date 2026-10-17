---
tags: [homelab, design, wan, nat, ospf, branch, lab-07]
status: agreed
---

# Lab 07 — Branch + WAN + NAT (Phase 3 design)

> This is the design for the next lab, written before anything is built. It is the
> plan: what we build, why, and how each claim gets proved. The open questions in
> section 18 have been answered; the build starts from there.

---

## 1. The brief

The company opened a second site. **HQ** is the site built in Lab 06. **BR1** is a
small branch office: 20–30 users, one switch, one router, and no servers of its
own — the branch uses HQ's DNS, DHCP, syslog and NTP over the WAN.

Both sites buy their internet from the same ISP, and there is also a direct
inter-site link between the two routers. Site-to-site traffic prefers that direct
link (one hop, not billed); the ISP path is its backup. For internet traffic each
site uses its own ISP link first.

---

## 2. What already exists

Lab 06 is built, verified and exported to `topology/lab-06-hq.gns3project`. The HQ
side already has:

| Piece | State |
|---|---|
| R1 | router-on-a-stick, five subinterfaces, OSPF with the ISP, learns the default route |
| SW1, SW2 | VLANs 10/20/30/40/99, trunks, STP root, management SVIs |
| PC1–PC4 | DHCP clients in the HR, Sales and IT VLANs |
| SRV-DNS, SRV-WEB, SRV-SYSLOG, SRV-NTP, CLIENT | services on VLAN 40, `10.100.0.0/24` |
| Management plane | SSH, NTP, syslog, SNMP on R1, ISP, SW1, SW2 |
| NAT | **none** — Lab 06 never left the simulated network |

Lab 07 reuses it directly: the live `lab-06-hq` project is **renamed**
`lab-07-branch-wan` and the branch is added to it, so the branch lands on a
working HQ instead of a rebuilt one. The Lab 06 export in `topology/` stays as it
is — that archive is the permanent record of the lab, so renaming the working
copy loses nothing. (Re-importing the archive is not part of this lab. It gets
tested for free when Lab 08 imports the Lab 07 export.)

---

## 3. Requirements

Written as capability statements, not as commands.

| Requirement | What "done" looks like |
|---|---|
| Branch LAN works | A PC in BR1 gets an address, a gateway and DNS, and reaches HQ |
| One source of DHCP and DNS | BR1 has no server of its own; DHCP and DNS come from HQ over the WAN |
| Static routing first, then OSPF | The same reachability is achieved twice — once with static routes, once with OSPF — and the difference is measured, not asserted |
| Shared default route | Both sites reach the simulated internet, and each keeps a default route |
| NAT/PAT overload | Traffic leaving a site for the internet is translated to that site's WAN address, and two inside hosts share one outside address |
| Primary path and backup path | HQ↔BR1 has two paths; the primary is preferred, and the backup is used only when the primary is gone |
| Convergence is measured | The outage caused by losing a path is timed in seconds and packets, before and after OSPF timer tuning |
| Branch is monitored | BR1's devices are in the same management plane as HQ's, and the collector sees them |
| OSPF is understood at packet level | Hello, database description and update packets are identified in a capture, not just described |

## 4. Non-goals

Explicitly **not** in this lab, so the scope stays two days:

- IPv6. The IP plan reserves `2001:db8::/32`, but this lab stays IPv4 only. IPv6
  belongs in its own lab.
- HSRP / first-hop redundancy. That is Lab 08.
- Zabbix. Monitoring is still "a poll answers and a log line arrives". Lab 09.
- Publishing internal servers with static NAT (port forwarding), and an inbound
  ACL on the ISP-facing interface. NAT overload is the only edge treatment here;
  hardening the edge is a later conversation.
- NAT64, GRE, IPsec, QoS, redistribution, policy routing.

---

## 5. Topology

```
              ┌──────────── SRV-NET 200.1.1.10/24 ─────────────┐
              │              (simulated internet)              │
              │                                                │
              │ Gi0/1  200.1.1.1/24                            │
         ┌────┴─────┐                                          │
         │   ISP    │  Lo0 100.64.0.1/32                      │
         └─┬──────┬─┘                                          │
   Gi0/0   │      │  Gi0/2                                     │
 10.0.0.14 │      │ 10.0.0.18      ═══ site-to-site primary (transit)
           │      │                ┈┈┈ site-to-site backup (via ISP)
   Gi0/1   │      │ Gi0/1
 10.0.0.13 │      │ 10.0.0.17
      ┌────┴───┐  │  ┌────────┐
      │   R1   ├══╪══┤   R2   │   Gi0/2 ─ Gi0/2 = 10.0.0.1/30 ─ 10.0.0.2/30
      │  HQ    │     │  BR1   │   (transit, preferred for site-to-site)
      └───┬────┘     └───┬────┘
          │ Gi0/0        │ Gi0/0
          │ trunk        │ trunk
      ┌───┴────┐     ┌───┴────┐
      │  SW1   │     │  SW3   │
      └─┬────┬─┘     └─┬────┬─┘
     PC1   PC2       PC5   PC6
   (HR)  (Sales)    BR1 users  VLAN 10, 10.20.10.0/24
        │
     SW2 ── PC3, PC4 (IT), SRV-SEG (VLAN 40: DNS, WEB, SYSLOG, NTP, CLIENT)
```

### Nodes added for this lab

| Node | Template | Role | RAM |
|---|---|---|---|
| `R2` | `vios` | BR1 edge router: branch LAN gateway, WAN, NAT | ~512 MB |
| `SW3` | `vios_l2` | BR1 access switch: VLAN 10 + 99, trunk to R2 | ~512 MB |
| `PC5`, `PC6` | VPCS | BR1 users (two, so PAT has two inside hosts) | ~10 MB each |
| `SRV-NET` | `web:lab` | the "public internet" web server | ~50 MB |

### Cabling

| Link | A side | B side | Carries |
|---|---|---|---|
| Primary WAN, HQ | R1 `Gi0/1` `10.0.0.13/30` | ISP `Gi0/0` `10.0.0.14/30` | default route, NAT outside |
| Primary WAN, BR1 | R2 `Gi0/1` `10.0.0.17/30` | ISP `Gi0/2` `10.0.0.18/30` | default route, NAT outside |
| Transit (backup) | R1 `Gi0/2` `10.0.0.1/30` | R2 `Gi0/2` `10.0.0.2/30` | site-to-site OSPF, primary for HQ↔BR1 |
| Simulated internet | ISP `Gi0/1` `200.1.1.1/24` | SRV-NET `eth0` `200.1.1.10/24` | NAT proof, HTTP test |
| BR1 LAN | R2 `Gi0/0` — trunk | SW3 `Gi0/0` — trunk | VLAN 10, 99 |
| BR1 access | SW3 `Gi0/1`, `Gi0/2` | PC5, PC6 | VLAN 10 |

Port convention is unchanged: lowest port faces the LAN, highest faces the WAN or
uplink. `R2 Gi0/0` is the LAN, `Gi0/1` is the ISP, `Gi0/2` is the transit.

---

## 6. Addressing

All of it is already in `docs/01-ip-plan.md` — this lab uses `10.20.0.0/16`
(BR1), the carved `10.0.0.0/24` WAN block and the `200.1.1.0/24` simulated
internet block. **No change to the IP plan is needed.** Restated here so the
design reads on its own:

| Device | Interface | Address | Notes |
|---|---|---|---|
| R1 | `Gi0/2` | `10.0.0.1/30` | transit to R2, "A" side |
| R2 | `Gi0/2` | `10.0.0.2/30` | transit, "B" side |
| R2 | `Gi0/0.10` | `10.20.10.1/24` | BR1 user gateway, DHCP relay |
| R2 | `Gi0/0.99` | `10.20.99.1/24` | BR1 management gateway |
| R2 | `Gi0/1` | `10.0.0.17/30` | WAN to ISP |
| R2 | `Lo0` | `10.255.0.2/32` | router-id, stable identity |
| SW3 | `Vlan99` | `10.20.99.13/24` | management SVI |
| PC5, PC6 | `eth0` | DHCP | `10.20.10.100`–`.200` |
| SRV-NET | `eth0` | `200.1.1.10/24` | gw `200.1.1.1` |

BR1 follows the same within-`/24` pattern as HQ: `.1`–`.9` gateways, `.10`–`.49`
infrastructure, `.100`–`.200` DHCP.

Branches reuse VLAN **IDs** from HQ (10 = users, 99 = management) so the design
stays predictable, and use a different second octet so `10.20.0.0/16` is BR1 in
one line.

---

## 7. Routing design

### Stage 1 — static routing (on purpose, briefly)

The first build uses only static routes: a default on R1 and R2 pointing at the
ISP, and routes on the ISP for both sites. It works, and it is uncomfortable:
every new subnet needs a route typed on a device that does not own it, and
failing a link means a human edits a route.

Stage 1 exists to make Stage 2 feel earned. It is also the comparison baseline: we
time the same failure under static routing and under OSPF.

**This stage applies to the branch.** Lab 06 already left R1 and the ISP running
OSPF — that is the HQ design and it is not undone. What Stage 1 changes is how the
**branch** learns its routes: R2 gets static routes only, and R1 and the ISP get a
static route for `10.20.0.0/16`. Stage 2 then replaces exactly those branch routes
with OSPF, which makes the comparison like-for-like without disturbing HQ.

### Stage 2 — OSPF

| Router | Area | Networks |
|---|---|---|
| R1 | 0 | `10.0.0.0/30` (transit), `10.0.0.12/30` (WAN), `10.10.0.0/16`, `10.100.0.0/24`, `10.255.0.1/32` |
| R2 | 0 | `10.0.0.0/30` (transit), `10.0.0.16/30` (WAN), `10.20.0.0/16`, `10.255.0.2/32` |
| ISP | 0 | `10.0.0.12/30`, `10.0.0.16/30`, `100.64.0.1/32` |

Decisions worth stating:

- **One area, area 0.** A two-site network with one path choice does not need
  areas. Areas are a Lab 08 conversation about tuning, not a starting point.
- **The ISP stays in OSPF and keeps `default-information originate`.** Lab 06
  already works this way, and it is what makes the failure drill interesting: if
  R1's own WAN link dies, the default route can still arrive from R2 over the
  transit link, so the internet keeps working without a human.
- **LAN subinterfaces are passive.** No neighbour is expected on a LAN.
- **The transit link is the preferred HQ↔BR1 path**, not the ISP path. It is one
  hop instead of two, and it is not billed. This needs no tuning: every link has
  the same default OSPF cost, so the transit wins on hop count (cost 1 against
  cost 2) purely because of the topology. A protocol preference would not be
  needed either — both paths are OSPF, which is the point.

### Why not static for everything

A static `ip route` cannot fail over by itself. A *floating* static route can, but
it only reacts to a route leaving the table, not to a neighbour becoming slow or a
path losing half its packets. OSPF reacts to the neighbour, and it repairs routes
for subnets it was never told about. That argument is the point of the lab, which
is why Stage 1 is short and Stage 2 is the real build.

---

## 8. NAT design

### The evidence, captured before it is solved

The "internet" here is one container behind the ISP, and the ISP sits in the same
OSPF domain as both sites. So a request from a private address **does** come back:
the simulated internet is permissive on purpose. Worth naming the simplification —
a real ISP edge filters RFC 1918 source and destination addresses (BCP 38 and
bogon lists) and would drop this traffic.

The "before" step is therefore not a broken ping. It is the evidence of what a real
ISP would drop: the capture on the ISP↔SRV-NET link shows the request arriving with
`10.10.10.160` as its **source**, and the reply addressed to `10.10.10.160`. The
internet was asked to carry private addresses end to end.

Two reasons the demo is built this way:

- A private-address filter at the ISP edge would also break drills B and C: the
  surviving path has no public address to translate to, so the failover story
  could not be measured. The permissive internet is what keeps the drills honest.
- It makes the comparison exact: same request, same link, same capture, before and
  after. Only the source address changes.

One capture covers both phases: start it, make the request, configure NAT, make the
request again. The file then contains the private source and the translated source
side by side, on one clock.

### Configuration shape

```
! R1 (and the same idea on R2, for BR1)
ip nat inside source route-map NAT-OVERLOAD interface GigabitEthernet0/1 overload
!
! One extended ACL, read as a sentence:
! "translate a site prefix only when the destination is outside the lab".
ip access-list extended NAT-OVERLOAD-LIST
 deny   ip 10.10.0.0 0.0.255.255 10.0.0.0 0.255.255.255
 deny   ip 10.20.0.0 0.0.255.255 10.0.0.0 0.255.255.255
 permit ip 10.10.0.0 0.0.255.255 any
 permit ip 10.20.0.0 0.0.255.255 any
!
route-map NAT-OVERLOAD permit 10
 match ip address NAT-OVERLOAD-LIST
!
interface GigabitEthernet0/0.10
 ip nat inside
! ... every LAN subinterface is "inside"
interface GigabitEthernet0/1
 ip nat outside
!
interface GigabitEthernet0/2
 ip nat outside
```

Points that matter:

- **`overload` is PAT.** Many inside hosts, one outside address, told apart by
  port. The proof is `show ip nat translations` showing two inside locals
  sharing one inside global with different ports.
- **The destination filter is what keeps site-to-site traffic routed, and it has to
  live in one ACL.** A source list alone does not deliver that promise: the transit
  must be `ip nat outside` (next point), so a packet leaving a BR1 user VLAN for a
  HQ subnet is an inside-to-outside packet and *is* translated. It was built that
  way first and the failure was clean and worth recording: `PC5 → PC1` timed out,
  and `show ip nat translations` on R1 showed the giveaway — entries whose
  *outside local* was `10.20.10.163`, a lab address. Each site translated the flow
  on the way out and the reply was translated a second time, so it came back
  addressed to the other router's WAN interface instead of the original host. The
  same mechanism rewrote BR1's management traffic to R2's WAN address, which broke
  the management story in section 10 before it could be tested — the collector saw
  `10.0.0.17` where the design promised `10.20.99.13`.
  The second attempt looked right and failed the same way: a route-map with
  `match ip address NAT-INTERNAL` and `match ip address NAT-EXTERNAL` on two lines.
  **Multiple `match ip address` lines in the same sequence are OR'd**, and the
  external list ends in `permit any`, so every packet matched. One extended ACL,
  matching source *and* destination, is what actually expresses "translate it only
  if it is leaving the lab". Three objects, one sentence of intent — and the fix
  restored site-to-site routing and management identity in the same change.
- **The NAT ACL scope is deliberate.** The source list names the two site
  supernets and nothing else; the transit `/30` and the server VLAN are outside
  it, so R1's own traffic and the NOC toolbox keep their addresses — `CLIENT` is
  untranslated on purpose, which is what makes the before/after capture a
  comparison rather than a coincidence.
- **`ip nat inside` goes on LAN subinterfaces, `ip nat outside` on the
  ISP-facing interface and on the transit interface.** Site-to-site traffic never
  enters NAT (the destination filter excludes it), but the transit must be
  `outside` so that drill B can translate in the other direction. If it is not,
  the failover works for internal traffic and silently breaks the internet — the
  subtlety the drill is designed to expose.

### Not in scope

Publishing HQ's web server to the outside with a static PAT entry is the same
translation table read in the other direction, and it is a good conversation — but
it needs an inbound ACL to be safe, and that edges into a hardening lab. Skipped
here (see section 4).

---

## 9. Convergence and failover

### Paths

| Traffic | Primary | Backup |
|---|---|---|
| HQ ↔ BR1 | transit `R1 Gi0/2 ↔ R2 Gi0/2` (one hop) | via ISP: R1 → ISP → R2 (two hops) |
| Either site → internet | own WAN link to the ISP | transit, then the other site's WAN link |

### Drills

| # | Drill | What should happen |
|---|---|---|
| A | Shut the transit link (`R1 Gi0/2`) | HQ↔BR1 moves to the ISP path; internet is unaffected |
| B | Shut R1's WAN link (`R1 Gi0/1`) | HQ's default route is relearned from R2 over the transit; internet survives — **only if R1 can translate on the transit path** |
| C | Shut R2's WAN link (`R2 Gi0/1`) | BR1's internet moves to the transit; HQ is unaffected |

### How convergence is measured

Not by feel. Three numbers per drill:

1. **Outage in seconds** — a continuous ping from `CLIENT` to a remote address,
   with timestamps; the gap between the last reply and the first reply after the
   change is the convergence time.
2. **Packets lost** — the count of unanswered pings in that gap.
3. **The cause, from the capture** — the last OSPF hello on the failed path and
   the first data packet on the new path, on one clock.

Then the same three numbers again after tuning:

```
interface GigabitEthernet0/2
 ip ospf hello-interval 1
 ip ospf dead-interval 4
!
router ospf 1
 timers throttle spf 50 200 5000
```

The result is a table: drill × (default timers, tuned timers) → seconds, packets.
That table is the deliverable; it is also the honest answer to "how fast does
OSPF converge?" — *it depends on the timers, and here is the measurement.*

---

## 10. Management plane for the branch

BR1's devices join the same management plane as HQ's. This is not optional: the
second site is exactly where an unnoticed blind spot appears.

| Item | R2 | SW3 |
|---|---|---|
| SSH | v2 only, `login local`, account `admin` privilege 15 | same |
| NTP | `ntp server 10.100.0.13` (HQ) | same |
| Syslog | `logging host 10.100.0.11` (HQ) | same |
| SNMP | `labRO` ro, `labRW` rw, location, contact | same |
| VTY access | `MGMT-ACCESS` vty ACL | same |
| Default route | from OSPF | static `ip route 0.0.0.0 0.0.0.0 10.20.99.1` — `vios_l2` runs with `ip routing` on, so `ip default-gateway` is ignored |

**Operational consequence:** `MGMT-ACCESS` must gain `permit 10.20.99.0
0.0.0.255`, and it must be updated on **every** device — R1, ISP, SW1, SW2 as well
as R2 and SW3. Forgetting this is how a new site becomes invisible to the
collector: the branch can reach the poller, but the poller's reply is filtered by
an ACL written before the branch existed. This is a deliberate part of the lab.

The syslog collector names files by **source IP**, and on this topology the two new
files arrived differently from the first guess:

| Device | File | Why |
|---|---|---|
| R2 | `10.0.0.2.log` | R2 reaches `10.100.0.11` over the transit, so it sources from the transit interface |
| SW3 | `10.20.99.13.log` | SW3's own management address, untranslated once the NAT destination filter exists |

`10.0.0.17.log` — R2's WAN address — appeared during the first build, and that was
the tell: SW3's syslog was being translated on its way through R2, so the collector
saw the router's WAN address where the design promised the branch switch. It is the
same NAT fault that broke site-to-site traffic in section 8, seen from the
management plane.

---

## 11. DHCP and DNS for the branch

BR1 has no server. This is the realistic branch design and it also tests whether
the WAN path really works for services, not just for pings.

1. `dnsmasq.conf` on `SRV-DNS` gains a BR1 scope:

   ```
   dhcp-range=set:br1,10.20.10.100,10.20.10.200,255.255.255.0,12h
   ```

   The image is rebuilt (`dnsmasq:lab`) because the config is baked in, and the
   `SRV-DNS` node is restarted so it picks up the new image. Same trap as Lab 06:
   a rebuilt image does not reach a running container.

2. `R2 Gi0/0.10` gets `ip helper-address 10.100.0.10`. A BR1 client broadcast
   becomes a unicast across two hops (R2 → transit/ISP → HQ), and the server
   answers into the subnet named by `giaddr` (`10.20.10.1`).

3. DNS is unchanged: the server is `10.100.0.10` for BR1 too. `r2.lab.local`
   (`10.255.0.2`) and `sw3.lab.local` (`10.20.99.13`) are added as explicit records
   in `dnsmasq.conf`. The first is already in the IP plan's DNS table, the second is
   not, and the wildcard `address=/.lab.local/` would otherwise answer both with the
   web server's address. `sw3.lab.local` is added to the IP plan at the same time.

**Failure mode to watch:** DHCP relay through an OSPF path is a good test. If the
relay works but DNS is slow, the problem is usually the return path, not the
server. Check `giaddr` in a capture before touching `dnsmasq`.

---

## 12. Security and hygiene

| Item | Setting | Why |
|---|---|---|
| NAT | one extended ACL: site prefixes as source, every lab destination denied | site-to-site traffic must not be translated, in either direction |
| VTY | SSH v2, `MGMT-ACCESS`, `deny any log` | a blocked login should be a log line |
| Trunks | explicit allowed list, native 999, `nonegotiate` | same as Lab 06 |
| Unused ports | shutdown, VLAN 999 | same as Lab 06 |
| SNMP | v2c, acknowledged as lab-only | the capture shows `labRO` in clear text; v3 is the Lab 09 conversation |
| Routing | `passive-interface` on LAN subinterfaces | never form a neighbour on a user VLAN |

---

## 13. How we prove each requirement

| Requirement | Proof | Command or capture |
|---|---|---|
| Branch LAN works | PC5/PC6 get a lease and reach HQ | `ip dhcp` on PC5; `ping 10.10.10.160` |
| One DHCP/DNS source | the branch has no server, yet resolves | `giaddr 10.20.10.1` in the DORA capture; `dig web.lab.local` from PC5 |
| Static routing stage | reachability before OSPF exists | `show ip route` on R1/R2 with only static routes |
| OSPF | neighbours and learned routes | `show ip ospf neighbor` = FULL on both links; `show ip route ospf` on R1 and R2 |
| Shared default route | both sites can leave | `show ip route` shows `O*E2 0.0.0.0/0` on R1 and R2 |
| NAT/PAT overload | two inside hosts share one address | `show ip nat translations` + capture on ISP↔SRV-NET with a translated source |
| Primary path preferred | transit is used for HQ↔BR1 | `traceroute` from HQ to BR1 shows `10.0.0.1 → 10.0.0.2` |
| Backup path | the other path is used when the primary is gone | drill A/B/C with `traceroute` before and after |
| Convergence measured | seconds and packets | the timed-ping table, default vs tuned timers |
| Branch monitored | collector sees the new devices | `snmpget` from `CLIENT` on `10.0.0.17` and `10.20.99.13`; new `.log` files on SRV-SYSLOG |
| OSPF at packet level | hellos and database exchange identified | capture with OSPF type 1 (Hello), 2 (DBD), 3/4/5 |

Rule unchanged from Lab 06: **a requirement is only done when the command or
capture above says so.**

---

## 14. Captures to take

| File | Link | Filter | Question it answers |
|---|---|---|---|
| `lab-07-branch-wan-nat.pcapng` | ISP `Gi0/1` ↔ SRV-NET | `http \|\| icmp` | What source address does the internet actually see, and is it translated? |
| `lab-07-branch-wan-ospf-hello.pcapng` | R1 ↔ R2 transit | `ospf` | Which routers are in area 0, what are the hello/dead timers, who is DR? |
| `lab-07-branch-wan-ospf-dbd.pcapng` | R1 ↔ R2 transit, after a clear | `ospf` | The database exchange: DBD, LSR, LSU, LSAck — and the MTU field that breaks it |
| `lab-07-branch-wan-failover.pcapng` | R1 ↔ R2 transit + a second capture on the ISP path | `ospf \|\| icmp` | The reconvergence timeline: last hello, route change, first data packet |

Captures are named `lab-07-branch-wan-<what>.pcapng`, per `wireshark/README.md`.

---

## 15. Faults to inject

One is done for the lab; the rest are the ticket scenarios that feed Phase 4.

| # | What to break | Symptom | Root cause | Ties to |
|---|---|---|---|---|
| 1 | Change `ip ospf mtu-ignore` off by giving the transit interfaces different MTUs | neighbours stuck in **EXSTART**, no routes exchanged, links UP | DBD packets must agree on MTU; OSPF refuses to exchange a database it cannot size | T-05 |
| 2 | Remove a subnet from `NAT-INTERNAL` | that site loses internet, HQ keeps working | traffic matches no NAT rule, so it leaves with a private source and is never answered | T-01 |
| 3 | Different OSPF area on one transit end | neighbour never reaches FULL | hellos are discarded: area mismatch | — |
| 4 | Wrong `ip nat inside` interface | everything internal breaks while the WAN looks fine | traffic is translated in the wrong direction | — |

Recommended for this lab: **#1**, because it looks exactly like a broken link while
every interface is up — the lesson is "check the control plane, not just the
lights".

---

## 16. Order of work

1. **Rename the existing project, in place.** In GNS3, rename `lab-06-hq` to
   `lab-07-branch-wan`, open it, and confirm HQ still works before adding
   anything. Nothing in the topology changes yet.

   Use **Rename**. Not **Save as**, not **Duplicate**: those build a new project
   with new node IDs and therefore **blank node disks**, so every device boots
   factory-fresh and the Lab 06 configuration is gone from that copy. The
   startup-config lives inside each node's disk, and a project copy does not
   carry it. (If Lab 06 is ever restored by hand, the procedure is in
   `configs/README.md`.)

2. Confirm the renamed project kept its configuration: R1 and ISP boot with their
   hostnames, SW1 and SW2 answer `show running-config` with the Lab 06 VLANs. If
   a switch is blank, restore it from `configs/lab-06/SW1.cfg` / `SW2.cfg` before
   touching anything else — the branch depends on an HQ that matches the design.
3. Add `R2`, `SW3`, `PC5`, `PC6` and `SRV-NET`; cable per section 5.
4. Configure BR1's L2: VLANs 10 and 99, access ports, trunk to R2, management SVI.
5. Configure R2: subinterfaces, WAN, transit, loopback, DHCP relay.
6. **Stage 1 — static routing.** Defaults on R1/R2, routes on the ISP. Verify both
   sites can reach each other and the internet. Record `show ip route`.
7. **Stage 2 — OSPF.** Replace the static routes with OSPF, keep the ISP as the
   default originator. Confirm the same reachability, then confirm that the
   transit is chosen for HQ↔BR1 and that the default still arrives from the ISP.
8. NAT: demonstrate the failure first (section 8), then configure PAT on R1 and
   R2, then prove two inside hosts share one outside address.
9. Management plane for R2 and SW3, **including the `MGMT-ACCESS` update on every
   device**, then confirm syslog and SNMP from the collector.
10. DHCP/DNS: rebuild `dnsmasq:lab` with the BR1 scope, restart `SRV-DNS`, lease a
    PC in BR1.
11. Run the section 13 table. Capture as in section 14.
12. Drills A, B, C with the timed ping. Tune the timers, re-run, build the table.
13. Inject fault #1, diagnose it, fix it.
14. Export configs to `configs/lab-07/`, captures to `wireshark/`, export the
    topology, write `labs/lab-07-branch-wan/README.md`, diff running config
    against this document.

---

## 17. Budget and limits

| Item | Value |
|---|---|
| Nodes | 3 routers + 3 switches + 6 PCs + 6 containers (+ 1 internet container) |
| RAM estimate | ~3.5–4.5 GB — the heaviest lab so far |
| Machine total | 9.6 GiB shared with the desktop |
| Rule | close every other GNS3 project and every other heavy application before starting |
| If it swaps | drop PC6 and PC4, and shut down `SRV-NET` between captures |

`vios_l2` takes noticeably longer to boot than `vios`. Configure `SW3` after it
finishes, not during.

---

## 18. Decisions

The questions this design left open, and the answers they got. These are settled;
the build follows them.

| # | Question | Decision |
|---|---|---|
| O1 | Reuse the Lab 06 topology, or rebuild HQ? | **Rename the existing project** to `lab-07-branch-wan` and add the branch to it. No import, no rebuild. The Lab 06 archive in `topology/` is the permanent record of that lab, so renaming the working copy loses nothing. |
| O2 | IPv6 in this lab or its own? | **No IPv6 here.** IPv4 only; `2001:db8::/32` stays reserved for its own lab. |
| O3 | How is the internet simulated? | **A container** behind the ISP — a real TCP stack and a real return-path problem to demonstrate NAT against. |
| O4 | Primary HQ↔BR1 path? | **The transit link** (one hop, not billed). The ISP path is the backup. |
| O5 | Branch DHCP? | **HQ's server over the WAN**, with a relay on R2. The branch has no server of its own. |
| O6 | Inbound ACL on the ISP-facing interface? | **Out of scope.** NAT overload is the only edge treatment in this lab. |
| O7 | Keep the ISP in OSPF? | **Yes.** It is what Lab 06 already does, and it is what makes drill B work. |

**Guiding rule for this lab: keep it simple.** One OSPF area, no redistribution, no
policy routing, no IPv6, no static NAT. Every extra knob is something that has to
be explained rather than something learned from.

---

## 19. Status

| Item | State |
|---|---|
| Design | agreed (this document) |
| Build | **complete** — the record of the build, the evidence and the faults is `labs/lab-07-branch-wan/README.md` |
| Done | Everything in the stage list: BR1 built and cabled; SW3 L2; R2 subinterfaces, relay, WAN, transit, `Lo0`; static stage then OSPF (transit preferred, `O*E2 0.0.0.0/0` at both sites); NAT/PAT on both routers; branch DHCP/DNS from the HQ servers; management plane for R2 and SW3; 13/13 verification rows; four captures; drills A and B measured; MTU fault injected, diagnosed and fixed; six configurations exported to `configs/lab-07/` |
| Not done | Nothing required. Out of scope by design: static NAT/port forwarding inbound (O6), IPv6, redistribution, policy routing, per-ticket follow-ups |
| Next step | Lab 08 (redundancy) builds on this topology: HSRP on the HQ distribution pair, STP root control, and a timed failover drill against the numbers measured here |

Build notes worth keeping for the guide:

- The far-end OSPF side is easy to forget: R2 had the process configured and still
  saw no neighbour, because R1 was missing `no passive-interface GigabitEthernet0/2`
  and the ISP was missing `network 10.0.0.16 0.0.0.3 area 0`. R2's own
  `show ip ospf interface brief` was correct the whole time.
- R2 learns the default from the transit first (it is the only path until the WAN
  adjacency forms) and then moves to its own WAN once the ISP is a neighbour.
- The NAT shape took three attempts; the working one is a **single extended ACL**
  matching source and destination. A route-map with two `match ip address` lines
  looks right and is a no-op (they are OR'd). See section 8.
- PC5's address is a manual VPCS setting, so it does not survive a restart. The
  DHCP scope in section 11 replaces it — and the scope works over the relay.
- SRV-NET shipped with the `web:lab` image default (`LAB_IP=10.100.0.12/24`,
  `LAB_GW=10.100.0.1`) because the node's Environment was never set, so the
  simulated internet did not exist until it was overridden to `200.1.1.10/24` with
  gateway `200.1.1.1`.
- A first failure is not a second failure: drill A cost 5.8 s cold and under
  300 ms warm. Quote which one you measured, and why (SPF + route install + ARP,
  not the hello/dead timers).
- **A hard host power-off can lose a recent `write memory`** — the emulator's
  write cache. Two devices came back factory-fresh, four did not. Closing the
  project before shutting the host down flushes it, and the TFTP export to
  `configs/lab-07/` is the backup that survives everything.

### Bringing the lab back up

| Step | Time |
|---|---|
| Open GNS3, open `lab-07-branch-wan` | 1 min |
| Start all nodes — start the routers and switches first; `vios_l2` is the slowest to boot (~4–5 min) | 5 min |
| Check: R1 and R2 `show ip ospf neighbor` = 2 FULL each, PC1 and PC5 `ip dhcp` both get a lease | 1 min |
| If a docker node refuses to start with `No such container`, null `container_id` in the `.gns3` file with the project closed, then reopen | 2 min |
| Restore any device that answers with a factory prompt from `configs/lab-07/` per `configs/README.md` | 2 min |

If a device answers with a factory prompt instead of its hostname, it did not
write its configuration before shutdown — restore it from `configs/` following
`configs/README.md`.
