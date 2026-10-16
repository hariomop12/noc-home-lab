---
tags: [homelab, labs, index]
status: active
---

# Labs

A master index of every lab in this repository. Each lab has its own folder with
a self-contained guide: objective, theory, build steps, config, verification,
capture exercise, a fault to inject, and self-check questions.

The full descriptions live in `README.md` next to each lab, not here. This file
is for navigation, progression and expectations.

## Progression

```
Micro labs 01-05        one concept each, 45-90 minutes
        │
        ▼
Lab 06  Small Enterprise HQ      first design task, no config given
        │
        ▼
Lab 07  Branch + WAN + NAT       multi-site, dynamic routing, internet edge
        │
        ▼
Lab 08  Redundancy               make it survive failures
        │
        ▼
Lab 09  Full NOC                 monitoring, alerting, failover drills
        │
        ▼
Tickets  incident-style labs     symptom given, cause hidden
```

The reasoning behind the ordering is in [../docs/00-roadmap.md](../docs/00-roadmap.md).

## Micro labs

| # | Lab | Level | Time | Skills | Status |
|---|---|---|---|---|---|
| 01 | [Basic LAN](lab-01-basic-lan/README.md) | micro | 45 min | Switch ports, MAC learning, ARP, ICMP, first capture | done |
| 02 | [Router + 2 LANs](lab-02-router-two-lans/README.md) | micro | 60 min | Addressing, gateway role, static route, routing table, traceroute | done |
| 03 | [VLAN + Trunk + Inter-VLAN](lab-03-vlan-trunk/README.md) | micro | 90 min | VLANs, 802.1Q, trunking, router-on-a-stick | done |
| 04 | [DHCP + DNS + HTTP](lab-04-dhcp-dns-http/README.md) | micro | 90 min | DORA, relay, DNS resolution, HTTP over TCP, Docker services | done |
| 05 | [Network Management](lab-05-network-management/README.md) | micro | 90 min | SSH hardening, NTP, syslog, SNMP | done |

## Combo and complex labs

| # | Lab | Level | Time | Skills | Status |
|---|---|---|---|---|---|
| 06 | [Small Enterprise HQ](lab-06-hq/README.md) | combo | 2-3 days | Requirements → design → build → verify, inter-VLAN, OSPF, ACLs, DHCP relay | done |
| 07 | [Branch + WAN + NAT](../docs/designs/branch-wan-design.md) *(design)* | combo | 2 days | WAN technologies, OSPF convergence, NAT/PAT, default route, link failure | in-progress |
| 08 | Redundancy | complex | 1 day | HSRP, OSPF tuning, STP root control, convergence measurement | not-started |
| 09 | Full NOC | complex | 2-3 days | Zabbix, SNMP polling, central syslog, alert triage, failover drill | not-started |

## Ticket labs

Rules and format: [../docs/tickets/README.md](../docs/tickets/README.md).

A ticket gives you a symptom and nothing else. The answer is deliberately not in
the file until you collapse it.

| ID | Ticket | Severity | Status |
|---|---|---|---|
| T-01 | LAN works, no internet | P1 | not-started |
| T-02 | No DHCP address on new PC | P2 | not-started |
| T-03 | Two PCs in different VLANs cannot reach each other | P2 | not-started |
| T-04 | Switch CPU at 100%, network crawling | P1 | not-started |
| T-05 | OSPF neighbour stuck in EXSTART | P2 | not-started |
| T-06 | Interface flapping with CRC errors | P2 | not-started |
| T-07 | High latency and loss on the WAN link | P2 | not-started |
| T-08 | ACL silently blocking traffic | P3 | not-started |
| T-09 | Duplicate IP address conflict | P2 | not-started |
| T-10 | Name resolution fails but IP connectivity works | P3 | not-started |

## How to add a lab

1. `cp -r lab-00-template lab-NN-name` and rename the GNS3 project to match.
2. Fill in the frontmatter: lab number, level, status.
3. Write the guide in this order: objective, theory, topology, build steps,
   addressing, configuration, verification, capture, break it/fix it, questions.
4. Register it in the tables above, in the main [README](../README.md) lab index,
   and in the skill coverage matrix.
5. When finished: export configs to `configs/lab-NN/`, save captures to
   `wireshark/`, flip the status, and write the "What I learned" section.
