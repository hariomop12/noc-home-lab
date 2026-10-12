---
tags: [homelab, ip-plan, addressing]
status: active
---

# 01 — IP Plan

> **Ek hi scheme, har lab me.** Same subnet, same gateway, same loopback —
> isse muscle memory banegi aur lab-note-lapar config copy-paste chalega.
> Kabhi badalna ho to pehle yahi file update karo, phir labs.

## Supernets

| Kya | Subnet | Note |
|---|---|---|
| HQ site | `10.10.0.0/16` | HQ ke saare VLANs |
| Branch-1 | `10.20.0.0/16` | BR1 |
| Branch-2 | `10.30.0.0/16` | BR2 |
| Servers / DC | `10.100.0.0/16` | Docker servers |
| WAN transit links | `10.0.0.0/24` | /30 chunks (table neeche) |
| Loopbacks | `10.255.0.0/24` | Router IDs |
| Lab mgmt / NOC jump | `10.254.0.0/24` | GNS3 host + cloud |
| ISP side (sim) | `100.64.0.0/16` | ISP loopbacks |
| "Internet" (sim) | `200.1.1.0/24` | Public-looking block |

## Loopbacks (Router ID / stable identity)

| Device | Loopback0 |
|---|---|
| R1 | 10.255.0.1/32 |
| R2 | 10.255.0.2/32 |
| R3 | 10.255.0.3/32 |
| R4 | 10.255.0.4/32 |
| ISP | 100.64.0.1/32 |

## WAN transit links (`10.0.0.0/24` → /30)

| Link | Subnet | End A | End B |
|---|---|---|---|
| R1–R2 | 10.0.0.0/30 | R1 .1 | R2 .2 |
| R1–R3 | 10.0.0.4/30 | R1 .5 | R3 .6 |
| R2–R3 | 10.0.0.8/30 | R2 .9 | R3 .10 |
| R1–ISP | 10.0.0.12/30 | R1 .13 | ISP .14 |
| R2–ISP | 10.0.0.16/30 | R2 .17 | ISP .18 |
| R3–ISP | 10.0.0.20/30 | R3 .21 | ISP .22 |

Bada lab chahiye to `10.0.0.24/30` se aage badho. `/30` ka `.1` = A side, `.2` = B side.

## HQ VLANs (`10.10.0.0/16`)

| VLAN | Naam | Subnet | Gateway (R1 SVI) | DHCP pool |
|---|---|---|---|---|
| 10 | HR | 10.10.10.0/24 | 10.10.10.1 | 10.10.10.100-.200 |
| 20 | SALES | 10.10.20.0/24 | 10.10.20.1 | 10.10.20.100-.200 |
| 30 | IT | 10.10.30.0/24 | 10.10.30.1 | 10.10.30.100-.200 |
| 40 | SERVERS | 10.10.40.0/24 | 10.10.40.1 | static |
| 99 | MGMT | 10.10.99.0/24 | 10.10.99.1 | static |

- Switch mgmt IP: `10.10.99.11` (SW1), `.12` (SW2) ...
- Reserves: `.1-.9` gateways/HSRP VIPs, `.10-.49` infra, `.50-.99` servers/printers, `.100-.200` DHCP.

## Branch sites

| Site | User VLAN | Users | Mgmt | WAN router |
|---|---|---|---|---|
| BR1 | VLAN 10 → 10.20.10.0/24 | 10.20.10.1 | 10.20.99.0/24 | R2 (10.20.99.1) |
| BR2 | VLAN 10 → 10.30.10.0/24 | 10.30.10.1 | 10.30.99.0/24 | R3 (10.30.99.1) |

## Servers / Docker (`10.100.0.0/16`)

| Host | IP | Container | Kaam |
|---|---|---|---|
| SRV-DNS | 10.100.0.10 | `dockurr/dnsmasq` | DHCP + DNS |
| SRV-SYSLOG | 10.100.0.11 | rsyslog (ubuntu) | Central logs |
| SRV-WEB | 10.100.0.12 | `nginx:alpine` | HTTP/HTTPS |
| SRV-NTP | 10.100.0.13 | `chrony` | Time |
| SRV-ZBX-WEB | 10.100.0.20 | `zabbix-web-nginx-pgsql` | Zabbix UI |
| SRV-ZBX-SRV | 10.100.0.21 | `zabbix-server-pgsql` | Poller/trapper |
| SRV-DB | 10.100.0.22 | `postgres:16-alpine` | Zabbix DB |
| SRV-ZBX-AGT | 10.100.0.23 | `zabbix-agent2` | Linux host monitor |

NOC jump / lab mgmt: `10.254.0.1` (GNS3 host side).

## DNS (lab.local)

| Record | Type | Value |
|---|---|---|
| r1.lab.local | A | 10.255.0.1 |
| web.lab.local | A | 10.100.0.12 |
| dns.lab.local | A | 10.100.0.10 |
| zabbix.lab.local | A | 10.100.0.20 |
| \*.lab.local | wildcard | 10.100.0.12 |

DHCP option: domain-name `lab.local`, DNS server `10.100.0.10`, NTP `10.100.0.13`.

## IPv6 (Phase 3+)

| Kya | Prefix |
|---|---|
| Global sim | `2001:db8::/32` |
| HQ | `2001:db8:10::/48` |
| BR1 / BR2 | `2001:db8:20::/48`, `2001:db8:30::/48` |
| WAN /64 (per link) | `2001:db8:ff::/64` se badhao |
| Loopbacks | `2001:db8:255::X/128` |

SLAAC + DHCPv6 dono test karna.

## Interface naming (vios)

- Routers (`vios`): `GigabitEthernet0/0`, `0/1`, `0/2`, `0/3`
- Switches (`vios_l2`): `GigabitEthernet0/0` … `0/3` (switchport), `Vlan99` (SVI — baad me)
- Convention: **lowest port → LAN side**, **highest port → WAN/uplink side**. Har lab me same rakho.

## Addressing hygiene

1. Naya subnet chahiye? Yahi file update karo, phir use karo.
2. Loopback har router pe — OSPF/Router-ID ke liye non-negotiable.
3. WAN pe `no shutdown` + clock rate DCE side pe (serial) ya `speed/duplex` (Ethernet).
4. Reserved dhcp range kabhi static IP ko mat do.
