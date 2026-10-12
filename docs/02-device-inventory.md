---
tags: [homelab, inventory, gns3, docker]
status: active
---

# 02 — Device Inventory

## GNS3 templates (jo already buggy/halaki hain)

| Template | Image | Type | RAM (typ) | Kis kaam ke liye |
|---|---|---|---|---|
| Cisco vios L3 | `vios-adventerprisek9-m.SPA.159-3.M6.qcow2` | QEMU | ~512 MB | Router — routing, NAT, ACL, OSPF |
| Cisco vios L2 | `vios_l2-adventerprisek9-m.ssa.high_iron_20200929.qcow2` | QEMU | ~512 MB | Switch — VLAN, trunk, STP |
| Cisco c7200 | `c7200-adventerprisek9-mz.153-3.XB12.image` | IOS (dynamips) | ~256 MB | Legacy — kam use karo, RAM bacha ke |
| VPCS | built-in | VPCS | ~10 MB | PC / endpoints — **default choice** |

> `c7200` sirf tab jab koi feature vios pe na mile. Warna RAM bacha ke vios.

## Docker containers (servers ke liye)

| Image | Kya hai | Role |
|---|---|---|
| `dockurr/dnsmasq` | DHCP + DNS | SRV-DNS (10.100.0.10) |
| `nginx:alpine` | Web | SRV-WEB (10.100.0.12) |
| `busybox` | light tools | ping/iperf/netcat, tcpdump sidecar |
| `zabbix/zabbix-server-pgsql` | Zabbix server | polling + triggers |
| `zabbix/zabbix-web-nginx-pgsql` | Zabbix UI | dashboard |
| `postgres:16-alpine` | DB | Zabbix backend |
| `zabbix/zabbix-agent2` | Agent | Linux host metrics |

Chaahiye (abhi nahi hai): `frrouting/frr` (Linux routing), `alpine` (rsyslog/chrony custom), `iperf3` image.

## Device naming

| Prefix | Matlab | Example |
|---|---|---|
| `R` | Router (vios L3) | R1, R2, ISP |
| `SW` | Switch (vios_l2) | SW1, SW2 |
| `PC` | VPCS endpoint | PC1, PC2 |
| `SRV-` | Docker service | SRV-DNS, SRV-WEB, SRV-ZBX-SRV |
| `FW` | Firewall (aage) | FW1 |
| `CLOUD` | GNS3 host/cloud breakout | CLOUD-HOST |

## Resource budget — kya kitna chalega

| Scenario | Nodes | Approx RAM | Viable? |
|---|---|---|---|
| Micro lab | 1-2 R + 1 SW + 3 PC | ~1.5 GB | ✅ easy |
| HQ (P2) | 2 R + 2 SW + 4 PC + 3 docker | ~3 GB | ✅ |
| 2-site WAN (P3) | 3 R + 2 SW + 6 PC + 4 docker | ~4.5 GB | ✅ (close others first) |
| Full NOC (P5) | + Zabbix stack (4 containers) | ~5.5-6 GB | ⚠️ Zabbix stack ~1 GB lagega, monitor karte raho |
| Anything above 8 vIOS | — | >6 GB | ❌ |

**Discipline:** ek time pe ek hi lab chalayein. Session ke baad `File → Close` (suspend nahi) — warna RAM leak.

## GNS3 setup checklist (ek baar)

- [ ] vios + vios_l2 dono templates ka **QEMU binary** `qemu-system-x86_64`, `-enable-kvm` on
- [ ] Har template ke liye **console type = telnet**, `console port` auto
- [ ] `vios_l2` template: `-machine` type check karo, boot thoda slow hoga — normal
- [ ] Docker template: "Docker container" section, `console type = telnet`
- [ ] Baad ke liye: Zabbix images ka `docker pull` (already pulled)
- [ ] "Use as a template" wale nodes `Lab Template` project me rakh do — naya lab instant
