---
lab: 00
level: template
status: template
tags: [homelab, lab, template]
---

# Lab NN — <Lab ka naam>

> Copy this file → `topology/lab-NN-naam/README.md`

## Objective

<Ek line me: is lab me kya prove karna hai? "Is lab ke baad main X kar sakta hoon.">

## Prerequisites

- Concept read: <vault note link>
- Configs: `configs/golden-configs/`

## Topology

```
PC1 ── SW1 ── R1 ── ISP
```

| Device | Type | Interface | IP | Note |
|---|---|---|---|---|
| R1 | vios L3 | Gi0/0 | 10.10.10.1/24 | LAN gateway |
| SW1 | vios_l2 | Gi0/0 | — | access to PC1 |
| PC1 | VPCS | eth0 | 10.10.10.100/24 | — |

## Tasks

1. 
2. 
3. 

## Verification (ye prove karo)

| # | Command | Expected |
|---|---|---|
| 1 | `ping` | reply |
| 2 | `show ip route` | connected + static |
| 3 | `show mac address-table` | MAC learned on expected port |

## Wireshark

Capture karo → `wireshark/lab-NN-naam-<kya>.pcapng`

Kya dekhna hai:
- 

## Troubleshooting (jo tuta)

| Problem | Root cause | Fix |
|---|---|---|
| | | |

## Kya seekha (lab ke baad bharo)

- 
- 

## Status

`status: not-started` → `in-progress` → `done`
Time laga: __ min
