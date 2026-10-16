---
tags: [homelab, design, lab-06, hq]
status: draft
---

# Lab 06 — Small Enterprise HQ: Design

This is the plan, written **before** opening GNS3. We build from this plan, then
check the running config against it at the end. If the build has to change
something, we write that change down here instead of hiding it.

- Phase 2 of [../00-roadmap.md](../00-roadmap.md)
- Addresses come from [../01-ip-plan.md](../01-ip-plan.md)

---

## 1. What we are building

> A company with 100–200 users, split into HR, IT and Sales. Two switches and one
> router. The site needs DHCP, DNS, HTTP, SSH, central syslog and NTP. The
> departments must be kept apart. Monitoring must be able to see every device.

Nothing is given this time — only the requirement. The result is a working site
plus proof that it works.

### What "done" means

| # | Requirement | Done when |
|---|---|---|
| R1 | 100–200 users, three departments | Three user VLANs exist, each with a DHCP pool of 100 addresses |
| R2 | Two switches, one router | SW1 and SW2 are the only managed switches; R1 is the only router |
| R3 | DHCP | A blank PC gets IP, mask, gateway and DNS on its own |
| R4 | DNS | `web.lab.local` resolves to the web server |
| R5 | HTTP | Every user VLAN can open a page on SRV-WEB |
| R6 | SSH | Every device answers SSH v2 from the IT VLAN |
| R7 | Central syslog | All four devices send logs to one collector |
| R8 | NTP | Every device shows synchronised time from one source |
| R9 | Departments apart | Sales cannot reach HR; IT can reach everything |
| R10 | Monitoring visibility | The collector can reach every device (ping + SNMP) |
| R11 | OSPF default route | The default route is learned from OSPF, not typed by hand |

---

## 2. Limits and assumptions

| # | Limit | What it means for us |
|---|---|---|
| C1 | `vios_l2` has only four ports: `Gi0/0`–`Gi0/3` | Ports are limited, so extra servers go behind a small unmanaged switch |
| C2 | ~9.6 GiB RAM total; Lab 06 budget ~3 GB | Keep it to 2 routers + 2 switches + 4 PCs + a few small containers |
| C3 | `SRV-DNS` has no console (`console_type: none`) | We never log into it; we prove it works from the lease file and a capture |
| C4 | The server images already exist and are already GNS3 templates | `dnsmasq:lab` → `SRV-DNS`, `web:lab` → `SRV-WEB`, `syslog:lab` → `SRV-SYSLOG`, `ntp:lab` → `SRV-NTP` ([../../docker/README.md](../../docker/README.md)) |
| C5 | Server addresses must stay the same in every lab | Servers keep the `10.100.0.x` block (see DD-1) |

---

## 3. Design decisions

### DD-1 — Where the servers live

The IP plan says two different things. The VLAN table puts the SERVERS VLAN at
`10.10.40.0/24`. The server table puts the same hosts at `10.100.0.x`. One host
cannot be in both.

**Decision:** servers keep their `10.100.0.x` addresses, and the SERVERS VLAN
uses `10.100.0.0/24`.

Why:
- **Server addresses should not depend on the site.** The same server serves HQ
  today and a branch in Lab 07. That is what a separate server block is for.
- The golden baseline (`configs/golden-configs/vios-router-baseline.cfg`) points
  at `10.100.0.11` (syslog) and `10.100.0.13` (NTP). Keeping these addresses
  keeps the baseline valid for every lab.
- Changing the addresses would quietly break the finished labs 04 and 05.

Cost: **one line** changes in `docs/01-ip-plan.md` — VLAN 40's subnet. Done
before the build, not after.

VLAN 99 (management) does **not** move. It stays `10.10.99.0/24`.

### DD-2 — Who does the routing

Both switches are `vios_l2`, which is a layer-2 switch and cannot do routing. So
the gateways cannot live on the switches.

The gateways live on **R1, using router-on-a-stick**: one trunk to SW1, and one
subinterface per VLAN (`10`, `20`, `30`, `40`, `99`).

### DD-3 — Why OSPF in a site with one router

OSPF between the HQ VLANs makes no sense — they are directly connected. OSPF is
for the way **out**.

R1 peers with the simulated ISP. The ISP announces a default route into OSPF. R1
ends up with `O*E2 0.0.0.0/0` — learned, not typed in.

### DD-4 — Fitting seven endpoints on four-port switches

SW1 and SW2 have four ports each. Users go on SW1, IT hosts on SW2, and the
servers hang off a small 8-port `Ethernet switch` (`SRV-SEG`). That switch is
unmanaged, needs no config, and is not counted as one of the "two switches".

### DD-5 — Where the Sales→HR block goes

The block is an **extended ACL applied on the Sales subinterface
(`Gi0/0.20 in`)**. Dropping the packet at the source's gateway means it never
crosses the core, and the ACL counters give us clean proof for R9.

---

## 4. Topology

```
                         simulated ISP
                        ┌─────────────┐
                        │     ISP     │  Lo0 100.64.0.1/32
                        └──────┬──────┘
                               │  10.0.0.12/30   R1 .13  ISP .14
                        ┌──────┴──────┐
                        │     R1      │  Lo0 10.255.0.1/32
                        │  (vios L3)  │  router-on-a-stick + OSPF
                        └──────┬──────┘
                               │ Gi0/0  802.1Q trunk (10,20,30,40,99)
                        ┌──────┴──────┐
                        │     SW1     │  Vlan99 10.10.99.11   (STP root)
                        │  (vios_l2)  │
                        └───┬─────┬───┘
              Gi0/2 VLAN10  │     │  Gi0/3 VLAN20
                     ┌──────┘     └──────┐
                   ┌─┴──┐              ┌─┴──┐
                   │PC1 │ HR           │PC2 │ Sales
                   └────┘              └────┘
                        │ Gi0/1  802.1Q trunk
                        │
                        ┌──────┴──────┐
                        │     SW2     │  Vlan99 10.10.99.12
                        │  (vios_l2)  │
                        └──┬────┬─────┘
             Gi0/1 VLAN30  │    │  Gi0/2 VLAN30 / Gi0/3 VLAN40
                    ┌──────┘    └──────┬─────────────────┐
                  ┌─┴──┐            ┌─┴──┐         ┌────┴───┐
                  │PC3 │ IT          │PC4 │ IT       │SRV-SEG │ (unmanaged)
                  └────┘             └────┘          └─┬─┬─┬─┬┘
                                                       │ │ │ └── SRV-NTP    10.100.0.13
                                                       │ │ └──── SRV-SYSLOG 10.100.0.11
                                                       │ └────── SRV-WEB    10.100.0.12
                                                       └──────── SRV-DNS    10.100.0.10
                                                                 (DHCP + DNS)
```

---

## 5. Devices

| Node | Template | Job | Address |
|---|---|---|---|
| R1 | Cisco IOSv | Edge router, inter-VLAN routing, OSPF | Lo0 `10.255.0.1` |
| ISP | Cisco IOSv | Stands in for the internet, announces the default route | Lo0 `100.64.0.1` |
| SW1 | Cisco-Switch-GOAT (`vios_l2`) | Access switch for users | Vlan99 `10.10.99.11` |
| SW2 | Cisco-Switch-GOAT (`vios_l2`) | Access switch for IT + servers | Vlan99 `10.10.99.12` |
| PC1 | VPCS | HR user | DHCP |
| PC2 | VPCS | Sales user | DHCP |
| PC3 | VPCS | IT user | DHCP |
| PC4 | VPCS | IT user (second host) | DHCP |
| SRV-SEG | Ethernet switch | Unmanaged patch panel for servers | — |
| SRV-DNS | Docker `dnsmasq:lab` | DHCP + DNS | `10.100.0.10` |
| SRV-SYSLOG | Docker `syslog:lab` | Log collector | `10.100.0.11` |
| SRV-WEB | Docker `web:lab` | Web page | `10.100.0.12` |
| SRV-NTP | Docker `ntp:lab` | Time source | `10.100.0.13` |

Devices that monitoring must see: **R1, ISP, SW1, SW2** — all four (R10). A
`CLIENT` (`noc-tools:lab`) container can be added on `SRV-SEG` to run the polls
from, or we can run them from `SRV-SYSLOG`.

---

## 6. VLANs and addresses

### VLANs

| VLAN | Name | Subnet | Gateway (R1 subif) | For |
|---|---|---|---|---|
| 10 | HR | `10.10.10.0/24` | `10.10.10.1` | HR users |
| 20 | SALES | `10.10.20.0/24` | `10.10.20.1` | Sales users |
| 30 | IT | `10.10.30.0/24` | `10.10.30.1` | IT users |
| 40 | SERVERS | `10.100.0.0/24` | `10.100.0.1` | Servers (DD-1) |
| 99 | MGMT | `10.10.99.0/24` | `10.10.99.1` | Device management |
| 999 | native, unused | — | — | Trunk native VLAN, no hosts |

### Fixed addresses

| Host | Address | VLAN | Note |
|---|---|---|---|
| R1 Lo0 | `10.255.0.1/32` | — | OSPF router-id |
| ISP Lo0 | `100.64.0.1/32` | — | Announced by ISP |
| R1 Gi0/1 | `10.0.0.13/30` | — | WAN end A |
| ISP Gi0/0 | `10.0.0.14/30` | — | WAN end B |
| SW1 | `10.10.99.11` | 99 | Management |
| SW2 | `10.10.99.12` | 99 | Management |
| SRV-DNS | `10.100.0.10` | 40 | DHCP + DNS |
| SRV-SYSLOG | `10.100.0.11` | 40 | Logs |
| SRV-WEB | `10.100.0.12` | 40 | HTTP |
| SRV-NTP | `10.100.0.13` | 40 | Time |

### DHCP pools (on SRV-DNS)

| Pool | Range | Lease |
|---|---|---|
| VLAN10-HR | `10.10.10.100` – `10.10.10.200` | 12 h |
| VLAN20-SALES | `10.10.20.100` – `10.10.20.200` | 12 h |
| VLAN30-IT | `10.10.30.100` – `10.10.30.200` | 12 h |

Each pool hands out: gateway = that VLAN's `.1`, DNS = `10.100.0.10`,
domain `lab.local`, NTP = `10.100.0.13`.

### DNS records (`lab.local`)

| Name | Type | Value |
|---|---|---|
| `r1.lab.local` | A | `10.255.0.1` |
| `sw1.lab.local` | A | `10.10.99.11` |
| `sw2.lab.local` | A | `10.10.99.12` |
| `dns.lab.local` | A | `10.100.0.10` |
| `web.lab.local` | A | `10.100.0.12` |
| `*.lab.local` | A | `10.100.0.12` |

---

## 7. Cabling

Rule: the **lowest** port faces the LAN, the **highest** port faces the uplink.

### R1 (4 ports)

| Port | Goes to | Role | Config |
|---|---|---|---|
| Gi0/0 | SW1 Gi0/0 | 802.1Q trunk | subinterfaces `.10 .20 .30 .40 .99` |
| Gi0/1 | ISP Gi0/0 | WAN | `10.0.0.13/30` |
| Gi0/2 | — | spare | shut |
| Gi0/3 | — | spare | shut |

### SW1 (4 ports)

| Port | Goes to | Mode | VLAN |
|---|---|---|---|
| Gi0/0 | R1 Gi0/0 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/1 | SW2 Gi0/0 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/2 | PC1 | access | 10 (HR) |
| Gi0/3 | PC2 | access | 20 (Sales) |

### SW2 (4 ports)

| Port | Goes to | Mode | VLAN |
|---|---|---|---|
| Gi0/0 | SW1 Gi0/1 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/1 | PC3 | access | 30 (IT) |
| Gi0/2 | PC4 | access | 30 (IT) |
| Gi0/3 | SRV-SEG | access | 40 (SERVERS) |

### SRV-SEG (unmanaged)

| Port | Goes to |
|---|---|
| 1 | SW2 Gi0/3 (uplink) |
| 2 | SRV-DNS `10.100.0.10` |
| 3 | SRV-WEB `10.100.0.12` |
| 4 | SRV-SYSLOG `10.100.0.11` |
| 5 | SRV-NTP `10.100.0.13` |
| 6 | `CLIENT` `10.100.0.50` (optional, for the R10 poll test) |

### ISP (4 ports)

| Port | Goes to | Role |
|---|---|---|
| Gi0/0 | R1 Gi0/1 | WAN `10.0.0.14/30` |
| Gi0/1–0/3 | — | spare, shut |

---

## 8. Layer 2 plan

- **VLANs 10, 20, 30, 40, 99** exist on both switches. Ports are assigned as in
  section 7. VLAN 99 keeps management traffic away from user traffic.
- **Trunks** carry only those five VLANs, and the native VLAN is moved to
  **999**, which nothing uses. This blocks VLAN-hopping tricks.
- **STP**: make SW1 the root for every VLAN
  (`spanning-tree vlan 10,20,30,40,99 root primary`). Put `portfast` +
  `bpduguard` on access ports. There is no second link yet, so nothing gets
  blocked — seeing a blocked port is Lab 08's job. We can still see who the root
  is with `show spanning-tree`.
- **Unused ports**: `shutdown`, parked in VLAN 999.
- **Port security**: skipped on purpose. It is a later skill and would only add
  noise here.

---

## 9. Layer 3 and routing plan

### R1

| Interface | Address | Role |
|---|---|---|
| `Gi0/0.10` | `10.10.10.1/24` | HR gateway, DHCP relay, ACL |
| `Gi0/0.20` | `10.10.20.1/24` | Sales gateway, DHCP relay, ACL |
| `Gi0/0.30` | `10.10.30.1/24` | IT gateway, DHCP relay |
| `Gi0/0.40` | `10.100.0.1/24` | Servers gateway |
| `Gi0/0.99` | `10.10.99.1/24` | Management gateway |
| `Gi0/1` | `10.0.0.13/30` | WAN to ISP |
| `Lo0` | `10.255.0.1/32` | Router-id |

- All VLANs are directly connected, so inter-VLAN routing needs no protocol.
- `ip helper-address 10.100.0.10` on `Gi0/0.10`, `.20`, `.30`. **Not** on `.40`,
  because the server is already local there.
- OSPF process 1, router-id `10.255.0.1`: `network 10.0.0.12 0.0.0.3 area 0`
  and `network 10.10.0.0 0.0.255.255 area 0`. LAN subinterfaces are
  `passive-interface` — no neighbour is expected on the LAN.

### ISP

- `Gi0/0` = `10.0.0.14/30`, `Lo0` = `100.64.0.1/32`.
- OSPF process 1 with `Gi0/0` and `Lo0` in area 0.
- **`default-information originate`** — this creates the site's default route.
  R1 shows it as `O*E2 0.0.0.0/0`.

### Why not just type a static default on R1

A typed `ip route 0.0.0.0 0.0.0.0 10.0.0.14` would also pass R11, but it proves
nothing about OSPF. Learning it keeps R3–R11 honest and gives Phase 3 something
to compare convergence against.

---

## 10. Security plan

### R9a — Sales cannot reach HR

```
ip access-list extended SALES-TO-HR
 deny   ip 10.10.20.0 0.0.0.255 10.10.10.0 0.0.0.255
 permit ip any any
!
interface GigabitEthernet0/0.20
 ip access-group SALES-TO-HR in
```

The `permit ip any any` matters. Sales must still reach DNS, the web server and
the internet. The rule is "no entry into HR", not "Sales is offline".

### R9b — IT can reach everything

There is no ACL on VLAN 30. That is the point. We prove it by reaching HR, Sales,
the servers and the internet from PC3 and PC4.

### Who can manage devices

```
ip access-list standard MGMT-ACCESS
 permit 10.10.30.0 0.0.0.255     ! IT
 permit 10.10.99.0 0.0.0.255     ! management VLAN
 deny   any log
!
line vty 0 4
 access-class MGMT-ACCESS in
 transport input ssh
```

HR and Sales users cannot SSH to devices even with the right password. `transport
input ssh` (never telnet) comes from the golden baseline.

### Extra L2 hardening

| Item | Setting |
|---|---|
| Native VLAN | 999, unused |
| Allowed VLANs | an explicit list, not `1-4094` |
| Unused ports | shutdown, VLAN 999 |
| Access ports | `spanning-tree portfast` + `bpduguard enable` |
| DTP | `switchport nonegotiate` on trunks |

---

## 11. Monitoring must see everything (R10)

For **R1, ISP, SW1, SW2**:

| Item | Value |
|---|---|
| Reachability | Loopback or SVI reachable from VLAN 40 / VLAN 99 |
| SNMP | `snmp-server community labRO ro`, `labRW rw`, location + contact |
| Syslog | `logging host 10.100.0.11`, trap level informational |
| NTP | `ntp server 10.100.0.13` |
| SSH | v2 only, `login local`, MGMT-ACCESS |

Zabbix itself is Phase 5. In Lab 06 the proof is simple: a poll that answers and
a log line that arrives.

---

## 12. How we prove each requirement

| Req | Proof | Command or capture |
|---|---|---|
| R1 | 3 VLANs, 3 pools of 100 | `show vlan brief`; pool file on SRV-DNS |
| R2 | 2 managed switches + 1 router | `show cdp neighbors` on R1 shows SW1; diagram has 2 switches |
| R3 | DHCP works | `ip dhcp` in VPCS; capture DORA with relay (`giaddr 10.10.10.1`) |
| R4 | DNS | `nslookup web.lab.local` from a PC; capture the query and reply |
| R5 | HTTP | `wget` from PC1, PC2, PC3 to `10.100.0.12`; capture the TCP handshake |
| R6 | SSH | `ssh admin@10.10.99.11` works from PC3, fails from PC2 |
| R7 | Syslog | bounce a spare port; show the line on SRV-SYSLOG |
| R8 | NTP | `show ntp status` = synchronised, on all four devices |
| R9a | Sales→HR blocked | PC2 ping PC1 fails; `show ip access-lists SALES-TO-HR` counters rise |
| R9b | IT→all | PC3/PC4 reach HR, Sales, servers, and the default route |
| R10 | Monitoring | from the collector: `ping` + `snmpget` on all four devices |
| R11 | OSPF default | `show ip ospf neighbor` = FULL; `show ip route ospf` = `O*E2 0.0.0.0/0` |

Rule: **a requirement is only done when the command or capture above says so.**

---

## 13. Fault to inject (pick one)

1. Remove `ip helper-address` from `Gi0/0.10` — HR clients fall back to
   169.254.0.0/16. Symptom: "HR can't reach anything, its IP looks weird."
2. Put `permit ip any any` first in the ACL — R9a silently stops working.
   Symptom: "Sales can reach HR again." (Same as ticket T-08.)
3. Wrong native VLAN on one trunk end — CDP errors, and a VLAN that works one
   way only.
4. Wrong OSPF area on the WAN link — neighbours stay down, no default route.
   Symptom: "everything internal works, nothing gets out."

---

## 14. Order of work

1. **Edit the IP plan first** (DD-1): VLAN 40's subnet in
   `docs/01-ip-plan.md` becomes `10.100.0.0/24`. VLAN 99 does not change.
2. Make a new GNS3 project from `Lab Template`, rename it `lab-06-hq`.
3. Cable everything as in section 7.
4. L2: VLANs, access ports, trunks, native VLAN, management SVIs, STP root.
5. L3: R1 subinterfaces, ISP WAN, loopbacks.
6. OSPF between R1 and ISP; ISP announces the default.
7. DHCP relay on R1 + pools on SRV-DNS; check a PC gets a lease.
8. DNS + HTTP on the containers; check them.
9. ACLs (Sales block + VTY access-class).
10. Management on all four devices: SSH, NTP, syslog, SNMP.
11. Run the section 12 table; capture; inject a fault; fix it.
12. Export configs to `configs/lab-06/`, captures to `wireshark/`, write the lab
    guide, then compare the running config with this document.

---

## 15. Still open

| # | Item | Who |
|---|---|---|
| O1 | ~~Confirm DD-1~~ — confirmed 2026-10-15; `docs/01-ip-plan.md` updated | done |
| O2 | ~~Check how `dnsmasq:lab` gets its config~~ — resolved: `dnsmasq.conf` is baked into the image, the address comes from `LAB_IP`/`LAB_GW`, VLAN 20 + 30 ranges are now live | done |
| O3 | Decide: add the `CLIENT` container for the R10 poll test, or run polls from `SRV-SYSLOG` | build |
| O4 | Decide: is PC4 a second IT host, or a spare we re-patch per test | design |

---

## 16. Risks

| Risk | Effect | Fix |
|---|---|---|
| One trunk between SW1 and SW2 | Servers + IT disappear if it drops | Accept for Lab 06; Lab 08 adds redundancy |
| RAM: 2 routers + 2 switches + 4 small containers ≈ 3 GB | Laptop starts swapping | Close `Lab Template` and every other project first |
| `SRV-DNS` has no console (C3) | Cannot debug it by logging in | Prove it with the lease file and a capture |
| DD-1 edits a source document | Easy to forget | IP plan edited in step 1; baseline re-checked in step 10 |
