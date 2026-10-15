---
tags: [homelab, ip-plan, addressing]
status: active
---

# 01 — IP Plan

One addressing scheme, used by every lab in this repository.

This is deliberate. Reusing the same subnets, gateways and loopbacks across labs
builds muscle memory, makes configurations copy-pasteable, and means an address
you see in a capture is instantly recognisable. If a lab genuinely needs a new
subnet, this document is updated first — never the lab on its own.

## Supernets

| Purpose | Subnet | Notes |
|---|---|---|
| HQ site | `10.10.0.0/16` | HQ user and management VLANs |
| Branch 1 | `10.20.0.0/16` | BR1 |
| Branch 2 | `10.30.0.0/16` | BR2 |
| Servers / DC | `10.100.0.0/16` | Container-hosted services |
| WAN transit links | `10.0.0.0/24` | Carved into /30 per link |
| Loopbacks | `10.255.0.0/24` | Router identity and router-id |
| Lab management | `10.254.0.0/24` | GNS3 host side, out-of-band access |
| ISP side (simulated) | `100.64.0.0/16` | ISP loopback and internal addresses |
| Simulated internet | `200.1.1.0/24` | Public-looking block for NAT testing |

Why `10.0.0.0/24` for WAN and not part of the site ranges: keeping transit links
in their own block means a route summarisation mistake is visible immediately,
and `10.0.0.x` in a traceroute can only be a WAN hop.

## Loopbacks

Every router gets a Loopback0. It is the router-id for OSPF, a stable address
for testing, and it never goes down as long as the router is alive.

| Device | Loopback0 |
|---|---|
| R1 | `10.255.0.1/32` |
| R2 | `10.255.0.2/32` |
| R3 | `10.255.0.3/32` |
| R4 | `10.255.0.4/32` |
| ISP | `100.64.0.1/32` |

## WAN transit links

`10.0.0.0/24` carved into `/30` blocks. Convention: the lower address is the
"A" side of the link, the higher address is the "B" side.

| Link | Subnet | A side | B side |
|---|---|---|---|
| R1 ↔ R2 | `10.0.0.0/30` | R1 `.1` | R2 `.2` |
| R1 ↔ R3 | `10.0.0.4/30` | R1 `.5` | R3 `.6` |
| R2 ↔ R3 | `10.0.0.8/30` | R2 `.9` | R3 `.10` |
| R1 ↔ ISP | `10.0.0.12/30` | R1 `.13` | ISP `.14` |
| R2 ↔ ISP | `10.0.0.16/30` | R2 `.17` | ISP `.18` |
| R3 ↔ ISP | `10.0.0.20/30` | R3 `.21` | ISP `.22` |

Continue from `10.0.0.24/30` for additional links. A `/30` gives exactly two
usable addresses — correct for a point-to-point link, and a good reminder of why
`/31` exists on modern equipment.

## HQ VLANs

| VLAN | Name | Subnet | Gateway (R1 SVI) | DHCP pool |
|---|---|---|---|---|
| 10 | HR | `10.10.10.0/24` | `10.10.10.1` | `.100` – `.200` |
| 20 | SALES | `10.10.20.0/24` | `10.10.20.1` | `.100` – `.200` |
| 30 | IT | `10.10.30.0/24` | `10.10.30.1` | `.100` – `.200` |
| 40 | SERVERS | `10.100.0.0/24` | `10.100.0.1` | static only |
| 99 | MGMT | `10.10.99.0/24` | `10.10.99.1` | static only |

VLAN 40 is addressed out of the **Servers / DC** supernet (`10.100.0.0/16`), not
out of `10.10.0.0/16`. Server addresses are deliberately site-independent — the
same `10.100.0.x` services serve HQ today and a branch in Lab 07 — so they live
in their own block rather than inside the HQ range. See
[designs/hq-design.md](designs/hq-design.md), decision DD-1.

**Within each /24, the pattern is always the same:**

| Range | Reserved for |
|---|---|
| `.1` – `.9` | Gateways, HSRP virtual IPs, VIPs |
| `.10` – `.49` | Infrastructure: switches, APs, printers |
| `.50` – `.99` | Servers and appliances |
| `.100` – `.200` | DHCP pool for users |
| `.201` – `.254` | Future growth / testing |

Switch management addresses: `10.10.99.11` (SW1), `10.10.99.12` (SW2), and so on.

VLAN 99 is the management VLAN. It exists so that device access is never mixed
with user traffic, and so that an ACL mistake in a user VLAN cannot lock you out
of a switch.

## Branch sites

| Site | User VLAN | Subnet | Gateway | Management | WAN router |
|---|---|---|---|---|---|
| BR1 | 10 | `10.20.10.0/24` | `10.20.10.1` | `10.20.99.0/24` | R2 |
| BR2 | 10 | `10.30.10.0/24` | `10.30.10.1` | `10.30.99.0/24` | R3 |

Branches use the same VLAN ID numbering as HQ so that the design stays
predictable, but a different second octet so summarisation is still possible
(`10.20.0.0/16` is BR1 in one line).

## Servers and containers

| Host | Address | Runs | Role |
|---|---|---|---|
| SRV-DNS | `10.100.0.10` | `dockurr/dnsmasq` | DHCP and DNS for the lab |
| SRV-SYSLOG | `10.100.0.11` | rsyslog | Central log collector |
| SRV-WEB | `10.100.0.12` | `nginx:alpine` | HTTP/HTTPS target |
| SRV-NTP | `10.100.0.13` | chrony | Time source for every device |
| SRV-ZBX-WEB | `10.100.0.20` | `zabbix-web-nginx-pgsql` | Monitoring frontend |
| SRV-ZBX-SRV | `10.100.0.21` | `zabbix-server-pgsql` | Polling and triggers |
| SRV-DB | `10.100.0.22` | `postgres:16-alpine` | Zabbix database |
| SRV-ZBX-AGT | `10.100.0.23` | `zabbix-agent2` | Linux host metrics |

The lab management address, on the GNS3 host side, is `10.254.0.1`.

## DNS

Forward zone: `lab.local`

| Record | Type | Value |
|---|---|---|
| `r1.lab.local` | A | `10.255.0.1` |
| `r2.lab.local` | A | `10.255.0.2` |
| `web.lab.local` | A | `10.100.0.12` |
| `dns.lab.local` | A | `10.100.0.10` |
| `zabbix.lab.local` | A | `10.100.0.20` |
| `*.lab.local` | A | `10.100.0.12` (wildcard, for quick tests) |

DHCP options handed out by SRV-DNS:

| Option | Value |
|---|---|
| Domain name | `lab.local` |
| DNS server | `10.100.0.10` |
| NTP server | `10.100.0.13` |
| Default gateway | per-VLAN router address |

## IPv6 plan (Phase 3 onwards)

| Purpose | Prefix |
|---|---|
| Global simulation | `2001:db8::/32` |
| HQ | `2001:db8:10::/48` |
| BR1 | `2001:db8:20::/48` |
| BR2 | `2001:db8:30::/48` |
| WAN links | `2001:db8:ff::/64`, one /64 per link |
| Loopbacks | `2001:db8:255::X/128` |

Both SLAAC and DHCPv6 will be tested, and the difference recorded in the lab note.

## Interface naming in GNS3

| Template | Interfaces |
|---|---|
| `vios` (router) | `GigabitEthernet0/0` … `0/3` |
| `vios_l2` (switch) | `GigabitEthernet0/0` … `0/3` (switchports), `Vlan99` (SVI) |
| `c7200` (fallback) | `GigabitEthernet` slots — check what the image provides |

Interface convention used by every lab: **the lowest port faces the LAN, the
highest port faces the WAN or uplink.** When a cable is being followed in a
diagram, the direction is never ambiguous.

## Addressing hygiene

1. Need a new subnet? Update this document first, then use it.
2. Every router gets a Loopback0 — required for OSPF router-id stability.
3. WAN interfaces need `no shutdown`; on serial links the DCE side needs a clock
   rate, on Ethernet both sides need matching speed and duplex.
4. Never assign a static address from the DHCP pool range.
5. Before adding a subnet, check for overlap against every supernet in this file.
