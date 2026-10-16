---
lab: 06
level: combo
status: done
tags: [homelab, lab, design, vlan, trunk, ospf, acl, dhcp-relay, monitoring, docker]
---

# Lab 06 — Small Enterprise HQ

## Metadata

| Field | Value |
|---|---|
| Level | combo |
| Estimated time | 2–3 days (design, build, verify, capture, fault) |
| Prerequisites | Labs 01–05 — VLANs, trunking, DHCP relay, DNS/HTTP, management plane |
| Skills practised | Turning a written requirement into a design, then a working site; router-on-a-stick; 802.1Q trunking; OSPF default route; extended ACLs; DHCP relay; proving requirements with captures |
| Related docs | [Design document](../../docs/designs/hq-design.md), [IP plan](../../docs/01-ip-plan.md), [Wireshark guide](../../docs/09-wireshark-guide.md), [Docker images](../../docker/README.md) |

## Objective

After this lab I can take a **one-paragraph business requirement** — no
configuration, no port table, no addressing — and produce a design document, build
the site from that document, and prove every requirement with a command or a
capture. I can also say out loud which parts of my design are decisions and which
are just the only option that works.

This is the first lab where the config is **not given**. The specification lives in
[../../docs/designs/hq-design.md](../../docs/designs/hq-design.md); the whole point
is to build from it and then diff reality against it.

## Theory

- **Router-on-a-stick.** One physical link becomes many logical gateways: the
  router's subinterface `Gi0/0.20` is the default gateway for VLAN 20, and every
  frame for VLAN 20 crosses the same cable with an 802.1Q tag. Inter-VLAN routing
  then needs no routing protocol — every VLAN is *directly connected*.
- **An 802.1Q tag is only added on a trunk.** On an access port the tag does not
  exist; the switch knows the VLAN from the port. This is why a capture on a PC
  link shows untagged frames and a capture on the trunk shows `vlan` on every
  frame.
- **DHCP relay.** The DHCP server sits in the SERVERS VLAN, not in the user
  VLANs, so a client's broadcast (which a router would normally drop) is turned
  into a unicast to the server. The router stamps the client's subnet into the
  **relay agent address (`giaddr`)** field, and that is how one server serves
  three subnets: it answers into the subnet `giaddr` names. Proof is visible in a
  capture as `giaddr = 10.10.10.1`.
- **OSPF, only where a neighbour exists.** LAN subinterfaces are passive — there
  is no router on the other side of them. The WAN link runs OSPF with the ISP,
  and the ISP originates the default route with `default-information originate`.
  R1 shows it as `O*E2 0.0.0.0/0`: *O* = learned by OSPF, `*` = the candidate
  default. Typing a static default would also "work" and would prove nothing.
- **ACL placement decides what the counters mean.** An extended ACL applied
  **inbound on the source's gateway** drops the packet before it crosses the core.
  The counter is then a per-source hit count, which is exactly the evidence you
  want when someone says "Sales can reach HR again".
- **Management plane is a separate design.** SSH, NTP, syslog and SNMP each need
  a stable source address (a loopback, or an SVI) and a reachable server. If the
  management path is missing, monitoring is blind — which is why this lab checks
  reachability *from a collector*, not from the router.

## Topology

```
                    ISP (vios)
                  Lo0 100.64.0.1/32
                     │ Gi0/0 10.0.0.14/30
                     │
                  Gi0/1 10.0.0.13/30        WAN, OSPF area 0
                     │
   ┌─────────────  R1 (vios)  ─────────────┐   Lo0 10.255.0.1/32
   │            Gi0/0 = router-on-a-stick  │
   │              │  trunk 10,20,30,40,99  │
   │           SW1 (vios_l2)  ← STP root   │
   │            │            │             │
   │         PC1 (HR)      PC2 (Sales)     │
   │        VLAN 10        VLAN 20         │
   │                                       │
   │        SW1 Gi0/1 ──── trunk ──── Gi0/0 SW2 (vios_l2)
   │                                       │
   │                            ┌──────────┴─────┬────────────┬────────────┐
   │                          PC3 (IT)       PC4 (IT)     SRV-SEG      VLAN 99
   │                          VLAN 30        VLAN 30    (unmanaged)   mgmt SVI
   │                                                        │
   │                        ┌───────┬──────────┬────────────┬────────┐
   │                     SRV-DNS  SRV-WEB  SRV-SYSLOG  SRV-NTP    CLIENT
   │                     .10      .12      .11         .13        .50
   │                              VLAN 40 10.100.0.0/24
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | `vios` | Gi0/0.10 | `10.10.10.1/24` | HR gateway, DHCP relay, ACL |
| R1 | `vios` | Gi0/0.20 | `10.10.20.1/24` | Sales gateway, DHCP relay, ACL in |
| R1 | `vios` | Gi0/0.30 | `10.10.30.1/24` | IT gateway, DHCP relay |
| R1 | `vios` | Gi0/0.40 | `10.100.0.1/24` | SERVERS gateway |
| R1 | `vios` | Gi0/0.99 | `10.10.99.1/24` | management gateway |
| R1 | `vios` | Gi0/1 | `10.0.0.13/30` | WAN to ISP |
| R1 | `vios` | Lo0 | `10.255.0.1/32` | OSPF router-id, stable identity |
| ISP | `vios` | Gi0/0 | `10.0.0.14/30` | WAN, OSPF area 0 |
| ISP | `vios` | Lo0 | `100.64.0.1/32` | simulated upstream |
| SW1 | `vios_l2` | Gi0/0 | — | trunk to R1, native 999 |
| SW1 | `vios_l2` | Gi0/1 | — | trunk to SW2 |
| SW1 | `vios_l2` | Gi0/2, Gi0/3 | — | access: PC1 (VLAN 10), PC2 (VLAN 20) |
| SW2 | `vios_l2` | Gi0/0 | — | trunk to SW1 |
| SW2 | `vios_l2` | Gi0/1, Gi0/2 | — | access: PC3, PC4 (VLAN 30) |
| SW2 | `vios_l2` | Gi0/3 | — | access: SRV-SEG (VLAN 40) |
| SW1/SW2 | `vios_l2` | Vlan99 | `10.10.99.11` / `.12` | management SVI |
| PC1–PC4 | VPCS | eth0 | DHCP | HR / Sales / IT / IT |
| SRV-DNS | `dnsmasq:lab` | eth0 | `10.100.0.10/24` | DHCP + DNS |
| SRV-SYSLOG | `syslog:lab` | eth0 | `10.100.0.11/24` | central collector |
| SRV-WEB | `web:lab` | eth0 | `10.100.0.12/24` | HTTP |
| SRV-NTP | `ntp:lab` | eth0 | `10.100.0.13/24` | chrony, stratum 10 |
| CLIENT | `noc-tools:lab` | eth0 | `10.100.0.50/24` | NOC toolbox: ssh, dig, curl, snmpget, tftp |
| SRV-SEG | Ethernet switch | — | — | carries VLAN 40 only |

Addressing is in [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md); the design
rationale (including why VLAN 40 is `10.100.0.0/24` and why the servers hang off
an unmanaged switch) is in the design document, sections 5–8.

## Build steps

1. Read [../../docs/designs/hq-design.md](../../docs/designs/hq-design.md) end to
   end. Do not open GNS3 until the design makes sense — that is the exercise.
2. Create the project `lab-06-hq` from the `Lab Template`.
3. Add the nodes and cable them exactly as designed. Record the port every link
   uses; the port assignment is part of the design.
4. Start everything. `vios_l2` boots slowly, and the containers need a moment to
   configure their own address and default route.
5. Configure outside-in: containers → access ports and VLANs → trunks → R1
   subinterfaces and WAN → OSPF → DHCP relay → ACLs → management plane.
6. Work the verification table in section 12 of the design document. Every row
   needs real output.
7. Capture, then inject the fault and fix it.

### Getting the configs out (worth doing now)

Console copy-paste works, but it does not scale and it is easy to corrupt. The
`CLIENT` container carries `tftp-hpa`, so each device can hand over its own
configuration:

```sh
# on the CLIENT console, once
mkdir -p /tftp
in.tftpd -l -c -s /tftp -u root &
```

```
R1# copy running-config tftp://10.100.0.50/R1.cfg
```

Then `docker cp GNS3.CLIENT.<project-id>:/tftp/. configs/lab-06/`. The device
needs a working default route for this to leave the site — on the switches that
means the static default described below.

## Configuration

Start from `configs/golden-configs/`. Only what this lab adds is shown; the full
exported configurations are in [`configs/lab-06/`](../../configs/lab-06/).

### Layer 2 — VLANs, access ports, trunk (SW1; SW2 is the same idea)

```
vlan 10,20,30,40,99
!
interface GigabitEthernet0/0
 description TRUNK-TO-R1
 switchport trunk encapsulation dot1q
 switchport trunk native vlan 999
 switchport trunk allowed vlan 10,20,30,40,99
 switchport mode trunk
 switchport nonegotiate
!
interface GigabitEthernet0/2
 description PC1-HR
 switchport mode access
 switchport access vlan 10
 spanning-tree portfast edge
 spanning-tree bpduguard enable
!
spanning-tree vlan 10,20,30,40,99 priority 24576
```

`switchport trunk encapsulation dot1q` must come **before** `switchport mode
trunk` on `vios_l2`; without it the trunk command is rejected. `nonegotiate` turns
DTP off — a trunk that a switch can negotiate is a trunk an attacker can
negotiate. Native 999 is an unused VLAN: untagged frames then land nowhere.

### Layer 3 — router-on-a-stick (R1)

```
interface GigabitEthernet0/0
 no shutdown
!
interface GigabitEthernet0/0.10
 encapsulation dot1Q 10
 ip address 10.10.10.1 255.255.255.0
 ip helper-address 10.100.0.10
!
interface GigabitEthernet0/0.20
 encapsulation dot1Q 20
 ip address 10.10.20.1 255.255.255.0
 ip helper-address 10.100.0.10
 ip access-group SALES-TO-HR in
!
interface GigabitEthernet0/0.30
 encapsulation dot1Q 30
 ip address 10.10.30.1 255.255.255.0
 ip helper-address 10.100.0.10
!
interface GigabitEthernet0/0.40
 encapsulation dot1Q 40
 ip address 10.100.0.1 255.255.255.0
!
interface GigabitEthernet0/0.99
 encapsulation dot1Q 99
 ip address 10.10.99.1 255.255.255.0
```

No `ip helper-address` on `.40` — the DHCP server is already local there.

### Routing — OSPF on the WAN only

```
router ospf 1
 router-id 10.255.0.1
 passive-interface default
 network 10.0.0.12 0.0.0.3 area 0
 network 10.10.0.0 0.0.255.255 area 0
 network 10.100.0.0 0.0.0.255 area 0
 network 10.255.0.1 0.0.0.0 area 0
!
! ISP
router ospf 1
 router-id 100.64.0.1
 network 10.0.0.12 0.0.0.3 area 0
 network 100.64.0.1 0.0.0.0 area 0
 default-information originate always
```

`always` matters: the ISP has a static `ip route 0.0.0.0 0.0.0.0 Null0` so it is
allowed to advertise a default it did not itself learn by OSPF.

### Security — the two ACLs

```
ip access-list extended SALES-TO-HR
 deny   ip 10.10.20.0 0.0.0.255 10.10.10.0 0.0.0.255
 permit ip any any
!
ip access-list standard MGMT-ACCESS
 permit 10.10.30.0 0.0.0.255
 permit 10.10.99.0 0.0.0.255
 deny   any log
!
line vty 0 4
 access-class MGMT-ACCESS in
 transport input ssh
```

Order inside an ACL **is** the logic. `permit ip any any` at the end is what keeps
Sales online for DNS, HTTP and the internet; `deny any log` on the VTY is what
turns a blocked login into a log line instead of silence.

### The switch default route (vios_l2 gotcha)

`vios_l2` boots with `ip routing` enabled, so `ip default-gateway` is stored but
**ignored** — `Gateway of last resort` stays unset and the switch cannot reach
NTP, syslog or a poller. The working config is an explicit static default:

```
ip route 0.0.0.0 0.0.0.0 10.10.99.1
```

Symptom if it is missing: `ping 10.10.99.1` works, `ping 10.100.0.13` fails, and
an inbound SSH attempt is *logged* as denied while the switch's own reply never
leaves.

## Verification

Every row is a real result from this build. Commands run on the device named, or
from `CLIENT` (`noc-tools:lab`).

| # | Requirement | Command | Expected | Actual |
|---|---|---|---|---|
| 1 | Inter-VLAN routing | `show ip interface brief` (R1) | every subinterface + Lo0 up/up | ✅ `.10 .20 .30 .40 .99`, `Gi0/1`, `Lo0` all **up/up** |
| 2 | OSPF neighbour | `show ip ospf neighbor` (R1) | ISP `100.64.0.1` in FULL | ✅ `100.64.0.1 ... FULL/-` |
| 3 | OSPF default route | `show ip route ospf` (R1) | `O*E2 0.0.0.0/0` | ✅ via `10.0.0.14`, external type 2 |
| 4 | DHCP (all user VLANs) | `ip dhcp` (PC1–PC4) | address, mask, gateway, DNS | ✅ PC1 `10.10.10.160/24`, gw `10.10.10.1`, DNS `10.100.0.10`, domain `lab.local`, lease 43200 s |
| 5 | DHCP relay | capture, filter `bootp` | `giaddr = 10.10.10.1` | ✅ Discover/Offer/Request/ACK, relay agent IP `10.10.10.1` |
| 6 | DNS | `dig web.lab.local @10.100.0.10` (CLIENT) | answer `10.100.0.12` | ✅ query → `web.lab.local. 0 IN A 10.100.0.12` |
| 7 | HTTP | `wget -qO- http://10.100.0.12/` + `curl -I` (CLIENT) | page served | ✅ `GET /` → `200 OK`, `HEAD /` → `200 OK` (in the capture) |
| 8 | SSH allowed | `ssh -l admin 10.10.99.11` (R1, mgmt VLAN) | login prompt | ✅ banner + login; also `SW1 → SW2 (10.10.99.12)` |
| 9 | SSH blocked + logged | `ssh -l admin 10.10.99.11` (CLIENT, VLAN 40) | denied, log line | ✅ denied; `%SEC-6-IPACCESSLOGNP: list MGMT-ACCESS denied 0 10.100.0.50` on SW1 |
| 10 | SNMP | `snmpget -v2c -c labRO … sysName.0` (CLIENT) | device identity | ✅ `SW1.lab.local`, `SW2.lab.local`, `R1.lab.local`, `ISP.lab.local` |
| 11 | Central syslog | `ls /var/log/remote/` (SRV-SYSLOG) | one file per device | ✅ `10.0.0.14.log`, `10.10.99.11.log`, `10.10.99.12.log`, `10.100.0.1.log` |
| 12 | NTP | `show ntp status` (SW1) | synchronised | ✅ `Clock is synchronized, stratum 11, reference is 10.100.0.13` |
| 13 | Sales→HR blocked | `ping 10.10.10.160` (PC2) | denied | ✅ `ICMP type:3, code:13, Communication administratively prohibited`; `show ip access-lists SALES-TO-HR` deny counter rising |
| 14 | IT→everything | `ping` (PC3/PC4) | reaches HR, Sales, servers, default route | ✅ reaches `10.100.0.1`, `10.10.99.11/.12`, `10.0.0.14` |
| 15 | 802.1Q trunking | capture on SW1↔SW2 | every frame tagged | ✅ 312 frames, **all** carry a `vlan` header |

Real output (selected):

```
SW1# show ntp status
Clock is synchronized, stratum 11, reference is 10.100.0.13
nominal freq is 1000.0003 Hz, actual freq is 1000.1468 Hz, precision is 2**17
reference time is EE7C3AB1.4534BB36 (05:54:57.270 UTC Fri Oct 16 2026)
clock offset is 18.4317 msec, root delay is 4.69 msec
loopfilter state is 'CTRL' (Normal Controlled Loop), drift is -0.000146525 s/s

SW1# show ntp associations
  address         ref clock       st   when   poll reach  delay  offset   disp
*~10.100.0.13     127.127.1.1     10     56     64   377  4.690  18.431  3.759

CLIENT:~# snmpget -v2c -c labRO 10.10.99.11 sysName.0
SNMPv2-MIB::sysName.0 = STRING: SW1.lab.local
CLIENT:~# snmpget -v2c -c labRO 10.10.99.12 sysName.0
SNMPv2-MIB::sysName.0 = STRING: SW2.lab.local
CLIENT:~# snmpget -v2c -c labRO 10.100.0.1 sysName.0
SNMPv2-MIB::sysName.0 = STRING: R1.lab.local
CLIENT:~# snmpget -v2c -c labRO 10.0.0.14 sysName.0
SNMPv2-MIB::sysName.0 = STRING: ISP.lab.local
```

`ref clock 127.127.1.1` is the giveaway that the time source is chrony's **own
clock** (`local stratum 10`), not a real atomic source. It is honest for a home
lab and would be a finding in a real audit.

## Capture exercise

Four captures, one per question the design document asks. All in
[`wireshark/`](../../wireshark/).

| File | Link | Filter | What it proves |
|---|---|---|---|
| `lab-06-hq-dhcp-dora-relay.pcapng` | SW1 ↔ PC1 | `bootp` | the whole relayed DORA exchange, with `giaddr` |
| `lab-06-hq-dns-http.pcapng` | CLIENT ↔ SRV-SEG | `dns \|\| http` | DNS resolution, then HTTP over TCP to the same server |
| `lab-06-hq-trunk-8021q.pcapng` | SW1 ↔ SW2 | `vlan` | every frame on a trunk is tagged |
| `lab-06-hq-management-ntp.pcapng` | SW2 ↔ SRV-SEG | `ntp \|\| bootp` | NTP client/server exchange, plus relayed DHCP crossing the same link |

Answered from the captures, not from memory:

- [x] **The relay field** — `tshark -r … -Y bootp -T fields -e bootp.ip.relay`
      returns `10.10.10.1`. The DHCP server never saw the broadcast; the router
      rewrote it into a unicast and named the subnet in `giaddr`.
- [x] **The lease is 12 hours** — option 51 = 43200 s, matching the pool.
- [x] **DNS and HTTP are two different conversations** — a UDP query/response on
      port 53, then a TCP handshake on port 80 with `GET /` and `200 OK`.
- [x] **A trunk tag is per-frame, not per-flow** — the SW1↔SW2 capture has **312
      frames and 312 `vlan` headers**, including STP and CDP.
- [x] **NTP mode tells direction** — `ntp.flags.mode == 3` is the client, `== 4`
      is the server. Only `10.100.0.13` sends mode 4.
- [x] **NTP stratum adds up** — the server replies `stratum 10`, and the client
      reports `stratum 11`. A client is always `server + 1`.

## Break it / fix it

The fault injected was the classic "someone reordered the ACL" — the same incident
as ticket **T-08**.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | Reorder `SALES-TO-HR`: `permit ip any any` becomes sequence 10, `deny` sequence 20 | PC2 can suddenly reach HR again; the ACL looks *present* on the interface | ACLs are first-match: the broad `permit` shadows the `deny` below it | delete both entries, re-add `deny` first, then `permit` |

```
R1(config)# ip access-list extended SALES-TO-HR
R1(config-ext-nacl)# no 10
R1(config-ext-nacl)# no 20
R1(config-ext-nacl)# permit ip any any            ! becomes sequence 10  <-- fault
R1(config-ext-nacl)# deny ip 10.10.20.0 0.0.0.255 10.10.10.0 0.0.0.255
```

Two traps worth remembering:

- Adding an entry with a **sequence number that already exists** replaces that
  entry in place; it does **not** move the ACE. Sequence numbers decide position,
  and position decides behaviour.
- The counters are the evidence. With the fault live, the `deny` line stops
  incrementing while `permit` climbs; after the fix the `deny` counter rises
  again on every ping. `show ip access-lists SALES-TO-HR` is the whole ticket.

## Self-check questions

1. R1 has five subinterfaces and no routing protocol between them. Why does
   inter-VLAN routing still work?
2. The trunk capture shows a VLAN tag on every frame, but a capture on PC1's link
   shows none. Where exactly is the tag added and removed?
3. `ip helper-address` is on `.10`, `.20` and `.30` but not `.40`. Explain both
   the presence and the absence.
4. R1 learns `O*E2 0.0.0.0/0`; a static default would have the same forwarding
   effect. What does the OSPF version give you that the static one does not?
5. Sales is denied to HR, yet Sales can still resolve DNS and browse the web.
   Which line makes that possible, and what happens if you delete it?
6. `ip default-gateway 10.10.99.1` is in the switch config and does nothing. Why,
   and what is the consequence for monitoring if nobody notices?
7. The ACL blocks SSH from VLAN 40. Why is a log line produced rather than
   nothing at all, and which single keyword causes it?

## What I learned

- **A design document is a checklist, not paperwork.** Working from section 12 of
  the design gave a definition of done; without it, "the lab works" is a feeling.
- **`vios_l2` runs with `ip routing` on.** `ip default-gateway` is accepted,
  stored, and ignored — the switches needed an explicit `ip route 0.0.0.0 0.0.0.0
  10.10.99.1` before NTP, syslog and SNMP could leave them. The symptom is
  misleading: the management request *arrives* (and is logged) while the reply
  never leaves.
- **VPCS is a ping-and-DHCP device.** It has no `dig`, no `wget`/`curl` and no
  `ssh` client, so the DNS, HTTP and SSH checks belong on the `CLIENT`
  (`noc-tools:lab`) container. Knowing your tools' limits is part of the design.
- **Sequence numbers are position, and position is policy.** Inserting the
  `permit` at sequence 10 silently neutered the ACL while leaving it present on
  the interface — a very realistic incident.
- **Export configs over the network, not by copy-paste.** `copy running-config
  tftp://10.100.0.50/<device>.cfg` from a `tftp-hpa` server in the lab produced
  clean, diffable files in seconds. It is exactly what the Phase 5 Ansible
  `backup-configs` playbook will do.
- **A rebuilt Docker image does not reach a running container.** After adding
  `tftp-hpa` to `noc-tools:lab`, the existing `CLIENT` node still had the old
  filesystem (`in.tftpd: not found`). The container is a snapshot of the image at
  creation time; a node restart (or a fresh container) is what adopts the change.
- **A GNS3 console is a shared, single-stream thing.** Attaching a second client -
  or leaving a half-open connection behind - can leave a console window that opens
  but shows nothing. Reset the console from the node menu instead of restarting
  the device, which would cost the running config.

## Cleanup

- [x] Configs exported to `configs/lab-06/` (R1.cfg, ISP.cfg, SW1.cfg, SW2.cfg)
- [x] Captures saved in `wireshark/lab-06-hq-*.pcapng` (4 files)
- [x] Fault injected, diagnosed, fixed, re-verified
- [x] Status flipped in `labs/README.md`, main `README.md`, `docs/00-roadmap.md`
- [ ] GNS3 project closed (not suspended)
- [x] Committed with a specific message
