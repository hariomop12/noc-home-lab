---
tags: [homelab, design, lab-06, hq]
status: draft
---

# Lab 06 — Small Enterprise HQ: Design Document

Written **before** touching GNS3. This is the specification; the build follows
it, and afterwards the running configs are diffed against it. Where the build has
to deviate, the deviation is recorded at the bottom, not silently.

Phase 2 of [../00-roadmap.md](../00-roadmap.md). Addressing follows
[../01-ip-plan.md](../01-ip-plan.md).

---

## 1. The brief

> A company of 100–200 users across HR, IT and Sales. Two switches and one
> router. The site needs DHCP, DNS, HTTP, SSH, central syslog and NTP.
> Departments must be separated. Monitoring must be able to see every device.

This is the first lab where nothing is given. The deliverable is a working site
plus the proof that it works.

### Acceptance criteria

| # | Requirement | Passes when |
|---|---|---|
| R1 | 100–200 users, three departments | Three user VLANs exist; each has a DHCP pool of 100 addresses |
| R2 | Two switches, one router | SW1 + SW2 are the only managed L2 devices; R1 is the only L3 device on the site |
| R3 | DHCP | A blank PC gets IP, mask, gateway and DNS with no manual config |
| R4 | DNS | `web.lab.local` resolves to the web server's address |
| R5 | HTTP | A page is fetched from SRV-WEB from every user VLAN |
| R6 | SSH | Every managed device is reachable over SSH v2 from the IT VLAN |
| R7 | Central syslog | All four devices send logs to one collector |
| R8 | NTP | Every device shows synchronised time from one source |
| R9 | Departments separated | Sales cannot reach HR; IT can reach everything |
| R10 | Monitoring visibility | The collector can reach every device (SNMP + ICMP) |
| R11 | Inter-VLAN routing with OSPF | A dynamic default route is learned over OSPF, not typed statically |

---

## 2. Constraints and assumptions

| # | Constraint | Consequence |
|---|---|---|
| C1 | `vios_l2` in this template exposes **four** ports, `Gi0/0`–`Gi0/3` ([../01-ip-plan.md](../01-ip-plan.md)) | Port assignments must be budgeted; extra endpoints go behind an unmanaged patch switch |
| C2 | RAM ceiling ~9.6 GiB. Inventory budget for Lab 06 is 2 routers + 2 switches + 4 PCs + 3 containers ≈ 3 GB ([../02-device-inventory.md](../02-device-inventory.md)) | The design uses 4 containers; container RAM is tens of MB, so the estimate is superseded, not broken |
| C3 | `SRV-DNS` template has `console_type: none` — no interactive shell ([../02-device-inventory.md](../02-device-inventory.md)) | It is driven from GNS3's environment variables and observed from outside, never logged into |
| C4 | The lab servers are purpose-built images, already built and templated: `dnsmasq:lab` → `SRV-DNS`, `web:lab` → `SRV-WEB`, `syslog:lab` → `SRV-SYSLOG`, `ntp:lab` → `SRV-NTP`, `noc-tools:lab` → `CLIENT` ([../../docker/README.md](../../docker/README.md)) | No image work is needed for this lab; each node self-addresses from `LAB_IP` / `LAB_GW` |
| C5 | Server addresses must stay stable across labs | Site services keep the `10.100.0.x` block (see DD-1) |

---

## 3. Design decisions

### DD-1 — Where the services live

`docs/01-ip-plan.md` has two overlapping statements: the HQ VLAN table puts the
SERVERS VLAN at `10.10.40.0/24`, while the server table puts the same hosts at
`10.100.0.x`. They cannot both be true for one host.

**Decision:** the services keep the **`10.100.0.x`** addresses, and the SERVERS
VLAN is addressed out of the `10.100.0.0/16` block as `10.100.0.0/24`.

Why this way and not the other:
- **Server addressing is global, not site-local.** A server has the same address
  whether it serves HQ today or a branch in Lab 07. Keeping servers in their own
  supernet is what makes that true.
- `configs/golden-configs/vios-router-baseline.cfg` points at `10.100.0.11`
  (syslog) and `10.100.0.13` (NTP). Keeping the addresses keeps the golden
  baseline valid for every lab, which is the whole point of a baseline.
- Re-addressing would silently invalidate the finished labs 04 and 05 configs.

Cost: **one line** in `docs/01-ip-plan.md` changes — VLAN 40's subnet becomes
`10.100.0.0/24`. This edit happens *before* the build (IP plan first, lab second).

VLAN 99 (management) is **not** moved — it stays `10.10.99.0/24` per the IP plan.

### DD-2 — Where inter-VLAN routing happens

Both switches are `vios_l2`, which is L2-only, so the gateways cannot be SVIs on
the switches. Inter-VLAN routing is **router-on-a-stick on R1**: one 802.1Q
trunk to SW1, with subinterfaces for `10/20/30/40/99`.

### DD-3 — Why OSPF is even in a single-router site

"Inter-VLAN routing with OSPF" cannot mean OSPF between the HQ VLANs — those are
directly connected and need no protocol. It means the *outside* path is dynamic:
R1 peers with the simulated ISP, and the ISP **originates the default route**
into OSPF. R1 ends up with `O*E2 0.0.0.0/0` — learned, not typed. This is also
the seed for Phase 3, where a real second site appears.

### DD-4 — How four ports cover seven endpoints

SW1 and SW2 have four ports each. The users sit on SW1, the IT hosts on SW2, and
the server containers hang off a **built-in 8-port `Ethernet switch` (`SRV-SEG`)**.
That switch is unmanaged, takes no configuration, and is not a managed device —
the brief's "two switches" (SW1, SW2) still holds.

### DD-5 — ACL placement

The Sales→HR block is an **extended ACL applied inbound on the Sales
subinterface** (`Gi0/0.20 in`). Dropping inbound at the source's gateway means
the packet never crosses the core, and the ACL counters give a clean proof for
R9.

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

## 5. Node inventory

| Node | Template | Role | Address |
|---|---|---|---|
| R1 | Cisco IOSv | HQ edge, inter-VLAN routing, OSPF | Lo0 `10.255.0.1` |
| ISP | Cisco IOSv | Simulated internet, originates the default | Lo0 `100.64.0.1` |
| SW1 | Cisco-Switch-GOAT (`vios_l2`) | Access switch — users | Vlan99 `10.10.99.11` |
| SW2 | Cisco-Switch-GOAT (`vios_l2`) | Access switch — IT + servers | Vlan99 `10.10.99.12` |
| PC1 | VPCS | HR endpoint | DHCP |
| PC2 | VPCS | Sales endpoint | DHCP |
| PC3 | VPCS | IT endpoint | DHCP |
| PC4 | VPCS | IT endpoint (second host) | DHCP |
| SRV-SEG | Ethernet switch (built-in) | Unmanaged server patch panel | — |
| SRV-DNS | Docker `dnsmasq:lab` | DHCP + DNS | `10.100.0.10` |
| SRV-SYSLOG | Docker `syslog:lab` | Central log collector | `10.100.0.11` |
| SRV-WEB | Docker `web:lab` | HTTP target | `10.100.0.12` |
| SRV-NTP | Docker `ntp:lab` | Time source (stratum 10) | `10.100.0.13` |

Managed devices that must appear in monitoring: **R1, ISP, SW1, SW2** — all four,
no exceptions (R10). A `CLIENT` (`noc-tools:lab`) container may be added on
`SRV-SEG` to run the polling test from, or the test can run from `SRV-SYSLOG`.

---

## 6. VLAN and addressing plan

### VLANs

| VLAN | Name | Subnet | Gateway (R1 subif) | Purpose |
|---|---|---|---|---|
| 10 | HR | `10.10.10.0/24` | `10.10.10.1` | HR users |
| 20 | SALES | `10.10.20.0/24` | `10.10.20.1` | Sales users |
| 30 | IT | `10.10.30.0/24` | `10.10.30.1` | IT users |
| 40 | SERVERS | `10.100.0.0/24` | `10.100.0.1` | Site services (DD-1) |
| 99 | MGMT | `10.10.99.0/24` | `10.10.99.1` | Device management |
| 999 | (native, unused) | — | — | Trunk native VLAN, no hosts |

### Fixed addresses

| Host | Address | VLAN | Notes |
|---|---|---|---|
| R1 Lo0 | `10.255.0.1/32` | — | OSPF router-id |
| ISP Lo0 | `100.64.0.1/32` | — | Advertised by ISP |
| R1 Gi0/1 | `10.0.0.13/30` | — | WAN, "A" end |
| ISP Gi0/0 | `10.0.0.14/30` | — | WAN, "B" end |
| SW1 | `10.10.99.11` | 99 | SVI, management |
| SW2 | `10.10.99.12` | 99 | SVI, management |
| SRV-DNS | `10.100.0.10` | 40 | DHCP + DNS |
| SRV-SYSLOG | `10.100.0.11` | 40 | syslog collector |
| SRV-WEB | `10.100.0.12` | 40 | HTTP |
| SRV-NTP | `10.100.0.13` | 40 | NTP source |

### DHCP pools (allocated on SRV-DNS)

| Pool | Range | Lease |
|---|---|---|
| VLAN10-HR | `10.10.10.100` – `10.10.10.200` | 8 h |
| VLAN20-SALES | `10.10.20.100` – `10.10.20.200` | 8 h |
| VLAN30-IT | `10.10.30.100` – `10.10.30.200` | 8 h |

Every pool hands out: gateway = the VLAN's `.1`, DNS = `10.100.0.10`, domain
`lab.local`, NTP = `10.100.0.13`.

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

## 7. Port assignments

Convention: the **lowest** port faces the LAN, the **highest** faces the uplink.

### R1 (vios, 4 ports)

| Port | Connects to | Role | Config |
|---|---|---|---|
| Gi0/0 | SW1 Gi0/0 | 802.1Q trunk | subinterfaces `.10 .20 .30 .40 .99` |
| Gi0/1 | ISP Gi0/0 | WAN | `10.0.0.13/30` |
| Gi0/2 | — | spare | shut |
| Gi0/3 | — | spare | shut |

### SW1 (vios_l2, 4 ports)

| Port | Connects to | Mode | VLAN |
|---|---|---|---|
| Gi0/0 | R1 Gi0/0 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/1 | SW2 Gi0/0 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/2 | PC1 | access | 10 (HR) |
| Gi0/3 | PC2 | access | 20 (Sales) |

### SW2 (vios_l2, 4 ports)

| Port | Connects to | Mode | VLAN |
|---|---|---|---|
| Gi0/0 | SW1 Gi0/1 | trunk | allow 10,20,30,40,99; native 999 |
| Gi0/1 | PC3 | access | 30 (IT) |
| Gi0/2 | PC4 | access | 30 (IT) |
| Gi0/3 | SRV-SEG | access | 40 (SERVERS) |

### SRV-SEG (Ethernet switch, unmanaged)

| Port | Host |
|---|---|
| 1 | SRV-DNS `10.100.0.10` |
| 2 | SRV-WEB `10.100.0.12` |
| 3 | SRV-SYSLOG `10.100.0.11` |
| 4 | SRV-NTP `10.100.0.13` |
| 5 | `CLIENT` `10.100.0.50` (optional, for the R10 poll test) |

### ISP (vios, 4 ports)

| Port | Connects to | Role |
|---|---|---|
| Gi0/0 | R1 Gi0/1 | WAN `10.0.0.14/30` |
| Gi0/1–0/3 | — | spare, shut |

---

## 8. Layer 2 design

- **VLANs 10, 20, 30, 40, 99** defined on both switches; access ports assigned
  per section 7. VLAN 99 exists so management is never mixed with user traffic.
- **Trunks** carry only those five VLANs. The native VLAN is changed to **999**
  and is unused — this kills VLAN-hopping via native-VLAN tag games.
- **STP**: SW1 is root for every VLAN
  (`spanning-tree vlan 10,20,30,40,99 root primary`). Access ports get
  `portfast` + `bpduguard`. There is no redundant link yet, so nothing is
  blocked — *seeing a blocked port is Lab 08's job*, but root election and port
  roles are visible now with `show spanning-tree`.
- **Unused ports** on both switches are `shutdown` and parked in VLAN 999.
- **Port security** is deliberately **not** enabled here — it is a later skill
  and would add noise to this lab's verification.

---

## 9. Layer 3 and routing design

### R1

| Interface | Address | Role |
|---|---|---|
| `Gi0/0.10` | `10.10.10.1/24` | HR gateway, DHCP relay, ACL in |
| `Gi0/0.20` | `10.10.20.1/24` | Sales gateway, DHCP relay, ACL in |
| `Gi0/0.30` | `10.10.30.1/24` | IT gateway, DHCP relay |
| `Gi0/0.40` | `10.100.0.1/24` | Servers gateway |
| `Gi0/0.99` | `10.10.99.1/24` | Management gateway |
| `Gi0/1` | `10.0.0.13/30` | WAN to ISP |
| `Lo0` | `10.255.0.1/32` | Router-id |

- All VLANs are directly connected — inter-VLAN routing needs no protocol.
- `ip helper-address 10.100.0.10` on `Gi0/0.10`, `.20`, `.30`. **Not** on `.40`,
  where the server is already local.
- OSPF process 1, router-id `10.255.0.1`: `network 10.0.0.12 0.0.0.3 area 0`
  and `network 10.10.0.0 0.0.255.255 area 0`. The LAN subinterfaces are
  `passive-interface` — no neighbour is expected there.

### ISP

- `Gi0/0` = `10.0.0.14/30`, `Lo0` = `100.64.0.1/32`.
- OSPF process 1 with `Gi0/0` and `Lo0` in area 0.
- **`default-information originate`** — this is where the site's default route is
  born. R1 installs it as `O*E2 0.0.0.0/0`.

### Why not a static default on R1

A typed `ip route 0.0.0.0 0.0.0.0 10.0.0.14` would pass R11 but prove nothing
about OSPF. Learning the default keeps R2–R11 honest and gives Phase 3 a
baseline to compare convergence against.

---

## 10. Security intent

### R9a — Sales cannot reach HR

```
ip access-list extended SALES-TO-HR
 deny   ip 10.10.20.0 0.0.0.255 10.10.10.0 0.0.0.255
 permit ip any any
!
interface GigabitEthernet0/0.20
 ip access-group SALES-TO-HR in
```

The trailing `permit ip any any` matters: Sales must still reach DNS, the web
server and the internet. The intent is "no lateral movement into HR", not "Sales
is offline".

### R9b — IT can reach everything

No ACL on VLAN 30, by design. The absence is the feature, and it is asserted in
verification by reaching HR, Sales, the servers and the internet from PC3/PC4.

### Management plane access

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

HR and Sales users cannot SSH to infrastructure even if they know the password.
`transport input ssh` (never telnet) is inherited from the golden baseline.

### Trunk / L2 hardening

| Control | Setting |
|---|---|
| Native VLAN | 999, unused |
| Allowed VLANs | explicit list, not `1-4094` |
| Unused ports | shutdown, parked in VLAN 999 |
| Access ports | `spanning-tree portfast` + `bpduguard enable` |
| DTP | `switchport nonegotiate` on trunks |

---

## 11. Management and monitoring visibility (R10)

Every device must be visible to the collector. For **R1, ISP, SW1, SW2** that
means:

| Item | Value |
|---|---|
| Management reachability | Loopback or SVI reachable from VLAN 40 / VLAN 99 |
| SNMP | `snmp-server community labRO ro`, `labRW rw`, location + contact |
| Syslog | `logging host 10.100.0.11`, trap level informational |
| NTP | `ntp server 10.100.0.13` |
| SSH | v2 only, `login local`, MGMT-ACCESS |

The monitoring *server* itself (Zabbix) is Phase 5. In Lab 06 the proof is a poll
that answers and a log line that arrives, not a dashboard.

---

## 12. Verification plan — requirement to proof

| Req | Proof | Command / capture |
|---|---|---|
| R1 | 3 VLANs, 3 pools of 100 | `show vlan brief`; pool file on SRV-DNS |
| R2 | 2 managed L2 + 1 L3 | `show cdp neighbors` on R1 shows SW1; full diagram has 2 switches |
| R3 | DHCP end to end | `ip dhcp` in VPCS; capture DORA showing relay (`giaddr 10.10.10.1`) |
| R4 | DNS | `nslookup web.lab.local` from a PC; capture the query/reply |
| R5 | HTTP | `wget` from PC1, PC2, PC3 to `10.100.0.12`; capture the TCP handshake |
| R6 | SSH | `ssh admin@10.10.99.11` from PC3 succeeds; from PC2 fails |
| R7 | Syslog | bounce a spare port; show the line on SRV-SYSLOG |
| R8 | NTP | `show ntp status` = synchronised, on all four devices |
| R9a | Sales→HR blocked | PC2 ping PC1 fails; `show ip access-lists SALES-TO-HR` counters climb |
| R9b | IT→all | PC3/PC4 reach HR, Sales, servers, and the default route |
| R10 | Monitoring visibility | from the collector: `ping` + `snmpget` on all four devices |
| R11 | OSPF default | `show ip ospf neighbor` = FULL; `show ip route ospf` = `O*E2 0.0.0.0/0` |

Rule for this lab: **no requirement is "done" until a command or capture in this
table says so.**

---

## 13. Planned fault injection

Pick one, inject it, diagnose from symptoms only, then fix and record:

1. Remove `ip helper-address` from `Gi0/0.10` — HR clients fall back to
   169.254.0.0/16 (APIPA). Symptom: "HR can't reach anything, its IP looks weird."
2. Put `permit ip any any` first in the ACL — R9a silently stops working.
   Symptom: "Sales can reach HR again." (Pre-writes ticket T-08.)
3. Wrong native VLAN on one trunk end — CDP errors, and a VLAN that works one way.
4. Wrong OSPF area on the WAN link — neighbours stay down, no default route.
   Symptom: "everything internal works, nothing gets out."

---

## 14. Build order

1. **IP plan edit first** (DD-1): change VLAN 40's subnet in
   `docs/01-ip-plan.md` to `10.100.0.0/24` (VLAN 99 is unchanged).
2. Create the GNS3 project from `Lab Template`; rename it `lab-06-hq`.
3. Cable per section 7.
4. L2: VLANs, access ports, trunks, native VLAN, mgmt SVIs, STP root.
5. L3: R1 subinterfaces, ISP WAN, loopbacks.
6. OSPF between R1 and ISP; ISP originates the default.
7. DHCP relay on R1 + pools on SRV-DNS; verify a PC gets a lease.
8. DNS + HTTP on the containers; verify.
9. ACLs (Sales block + VTY access-class).
10. Management plane on all four devices: SSH, NTP, syslog, SNMP.
11. Run the section 12 table; capture; inject a fault; fix.
12. Export configs to `configs/lab-06/`, captures to `wireshark/`, write the lab
    guide, then diff the running config against this document.

---

## 15. Open items

| # | Item | Owner |
|---|---|---|
| O1 | ~~Confirm DD-1~~ — confirmed 2026-10-15; `docs/01-ip-plan.md` updated | done |
| O2 | Confirm the `SRV-DNS` `dnsmasq:lab` config is driven by `LAB_IP`/`LAB_GW` + a `dnsmasq.conf`, and where the lease file lives | build |
| O3 | Decide whether to add the `CLIENT` (`noc-tools:lab`) container for the R10 poll test or run it from `SRV-SYSLOG` | build |
| O4 | Decide whether PC4 is IT or a spare host re-patchable per test | design review |

---

## 16. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Single trunk SW1↔SW2 is a single point of failure | Servers + IT vanish if it drops | Accepted for Lab 06; Lab 08 adds redundancy and measures it |
| RAM: 2 vios + 2 vios_l2 + 4 small containers ≈ 3 GB | Host swapping | Close `Lab Template` and every other project before starting |
| `SRV-DNS` has no console (C3) | Cannot debug it interactively | Prove it with the lease file and a packet capture instead |
| DD-1 edits a source document | Drift if the edit is missed | IP plan edited in step 1; golden baseline re-checked in step 10 |
