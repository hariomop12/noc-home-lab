---
tags: [homelab, inventory, gns3, docker]
status: active
---

# 02 — Device Inventory

What this lab is made of, what each piece is for, and what it costs in RAM.

RAM is the binding constraint on this machine (9.6 GiB total, shared with the
desktop). Every decision below exists to keep a full lab under about 4 GB.

## GNS3 node templates

| Template | Image | Type | Typical RAM | Used for |
|---|---|---|---|---|
| Cisco vios L3 | `vios-adventerprisek9-m.SPA.159-3.M6.qcow2` | QEMU | ~512 MB | Routers: routing, NAT, ACLs, OSPF, management plane |
| Cisco vios L2 | `vios_l2-adventerprisek9-m.ssa.high_iron_20200929.qcow2` | QEMU | ~512 MB | Switches: VLANs, trunking, STP, port security |
| Cisco c7200 | `c7200-adventerprisek9-mz.153-3.XB12.image` | IOS (dynamips) | ~256 MB | Fallback only, when a feature is missing on vios |
| VPCS | built in | VPCS | ~10 MB | Endpoints. The default choice for every "PC" |

Rules:

1. **VPCS for every endpoint.** A PC in this lab never needs a full OS.
2. **Docker for every server.** A container is one to two orders of magnitude
   cheaper than a QEMU VM.
3. **`c7200` only as a fallback.** It is RAM-hungry, slow to boot and teaches
   nothing that `vios` does not teach. Reach for it only when an image feature
   is genuinely missing.
4. **Boot switches last, or wait for them.** `vios_l2` takes noticeably longer to
   come up than `vios`. Configuring an SVI before boot completes looks like a bug
   and is not one.

## Docker containers

| Image | Purpose | Address |
|---|---|---|
| `dockurr/dnsmasq` | DHCP and DNS for the whole lab | `10.100.0.10` |
| `nginx:alpine` | HTTP/HTTPS target for client tests | `10.100.0.12` |
| `busybox` | Quick throwaway tools: `ping`, `wget`, `nc`, `tcpdump` | on demand |
| `zabbix/zabbix-server-pgsql` | Monitoring server: polling, triggers, actions | `10.100.0.21` |
| `zabbix/zabbix-web-nginx-pgsql` | Monitoring frontend | `10.100.0.20` |
| `postgres:16-alpine` | Zabbix database backend | `10.100.0.22` |
| `zabbix/zabbix-agent2` | Linux metrics agent | `10.100.0.23` |

Wanted later, not pulled yet:

| Image | Why |
|---|---|
| `frrouting/frr` | Linux-based routing daemon, useful for automation later |
| an alpine-based rsyslog image | Central syslog collector as a container |
| an alpine-based chrony image | NTP server as a container |
| `iperf3` / `networkstatic/iperf3` | Throughput and jitter testing |

## Device naming

| Prefix | Device | Template | Example |
|---|---|---|---|
| `R` | Router | vios L3 | `R1`, `R2`, `ISP` |
| `SW` | Switch | vios_l2 | `SW1`, `SW2` |
| `PC` | Endpoint | VPCS | `PC1`, `PC2` |
| `SRV-` | Container service | Docker | `SRV-DNS`, `SRV-WEB` |
| `FW` | Firewall (later) | — | `FW1` |
| `CLOUD` | GNS3 host/cloud breakout | built in | `CLOUD-HOST` |

Names are stable across all labs. `R1` is always the HQ edge router, `SW1` is
always the first access switch. This means a screenshot from a lab three months
ago is still readable.

## Resource budget

| Scenario | Nodes | Approx RAM | Verdict |
|---|---|---|---|
| Micro lab | 1-2 routers + 1 switch + 3 PCs | ~1.5 GB | Comfortable |
| Lab 06 HQ | 2 routers + 2 switches + 4 PCs + 3 containers | ~3 GB | Fine |
| Lab 07 two sites | 3 routers + 2 switches + 6 PCs + 4 containers | ~4.5 GB | Close all other projects first |
| Lab 09 full NOC | Above + 4-container Zabbix stack | ~5.5-6 GB | Watch `free -h`, expect swapping |
| Anything above 8 routers | — | > 6 GB | Not viable on this machine |

Discipline that keeps this working:

- One lab open at a time. Close the project when finished, do not suspend it.
- Check `free -h` before starting a heavy lab, not after it starts swapping.
- Idle routers still cost RAM. Shut down nodes that the lab is not using.
- If a lab needs a big topology, split it across two labs rather than one huge one.

## GNS3 template setup checklist

One-time work, per machine.

- [ ] `vios` and `vios_l2` templates use `qemu-system-x86_64` with `-enable-kvm`
- [ ] Console type `telnet`, console port allocation automatic
- [ ] Adapters per template: 4 for `vios`, matching GNS3's default slot layout
- [ ] Memory per node: 512 MB for `vios`, 512 MB for `vios_l2`
- [ ] `vios_l2` boot tested once in isolation before being used in a real lab
- [ ] Docker template present with console type `telnet`
- [ ] VPCS template present
- [ ] All Zabbix images already pulled locally
- [ ] One `Lab Template` project built containing these nodes as templates only

Details and screenshots-level instructions: [03-gns3-setup.md](03-gns3-setup.md).
