---
tags: [homelab, noc, gns3, networking]
status: active
---

# NOC Home Lab

> Goal: NOC / Network Engineer job ke liye ek **repeatable, version-controlled lab**.
> Sirf GNS3 me click-click nahi — har lab ka topology, config, capture aur note git me.

## Hardware / Software

| Cheez | Value |
|---|---|
| Machine | Lenovo IdeaPad 3 15ALC6 (Ryzen 5 5500U, 6C/12T) |
| RAM | 9.6 GiB ← **yehi asli limit hai** |
| Disk free | ~86 GB |
| GNS3 | 3.0.6, local server, KVM enabled (GNS3 VM ki zarurat nahi) |
| Docker | 29.1.3 — servers/containers ke liye |
| IOS images | `c7200` (classic IOS), `vios` (L3), `vios_l2` (L2 switch) |

**Resource rule:** max ~6-8 vIOS routers. PC = **VPCS**, Server = **Docker**.
QEMU VM sirf tab jab koi cheez container me na chale.

## Kaise chalayein

1. `gns3` kholo (local server already running).
2. `topology/lab-NN-*/` me jaake `lab-NN.gns3` import karo.
3. Lab note padho → `topology/lab-NN-*/README.md` (objective, tasks, verification).
4. Config `configs/golden-configs/` se start karo.
5. Lab ke baad: config export → `configs/lab-NN/`, capture → `wireshark/`, phir `git commit`.

## Folder map

| Folder | Kya rakhte hain |
|---|---|
| `topology/` | Lab ka GNS3 project (portable export) + lab note |
| `configs/golden-configs/` | Working baseline configs (R1, SW1) — copy-paste start |
| `configs/lab-NN/` | Us lab ki final configs (startup-config export) |
| `docs/` | Roadmap, IP plan, device inventory, tickets |
| `wireshark/` | `.pcapng` + analysis notes |
| `ansible/` | Playbooks se golden config push (Phase 5) |

## Docs

- [docs/00-roadmap.md](docs/00-roadmap.md) — Phase 0 → 5 ka master plan
- [docs/01-ip-plan.md](docs/01-ip-plan.md) — ek fixed addressing scheme (sab labs me same)
- [docs/02-device-inventory.md](docs/02-device-inventory.md) — images, docker, device naming
- [docs/tickets/README.md](docs/tickets/README.md) — ticket-style (real) labs

## Lab status

| # | Lab | Level | Status |
|---|---|---|---|
| 01 | Basic LAN (2 PC + switch) | micro | not-started |
| 02 | Router + 2 LANs | micro | not-started |
| 03 | VLAN + Trunk + Inter-VLAN | micro | not-started |
| 04 | DHCP + DNS + HTTP (docker) | micro | not-started |
| 05 | Network Management (SSH/NTP/Syslog/SNMP) | micro | not-started |
| 06 | Small Enterprise HQ | combo | not-started |
| 07 | Branch + WAN + NAT/PAT | combo | not-started |
| 08 | Redundancy (HSRP + OSPF tuning) | complex | not-started |
| 09 | Full NOC (Zabbix + syslog + failover) | complex | not-started |

Status values: `not-started` · `in-progress` · `done` · `broken` (tod diya, fix karna hai)

## Conventions

- Folder + GNS3 project name: `lab-NN-naam` (kebab-case, dono same).
- Devices: `R1..Rn` router · `SW1..SWn` switch · `PC1..` VPCS · `SRV-*` docker · `ISP` cloud.
- Commit message: `lab-01: <kya kiya>`
- Ek lab ek commit — itna chhota rakho ki `git log` hi progress report ban jaye.
