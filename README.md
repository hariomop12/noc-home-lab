---
tags: [homelab, noc, gns3, networking]
status: active
---

# NOC Home Lab

A Cisco networking lab built on GNS3 — plus the configs, packet captures, notes
and incident write-ups that come out of it.

The first eight labs and every device configuration are IOS on GNS3, because that
is what a CCNA/CCNP job runs. Phases 4 and 5 (the ten incident tickets and the
whole monitoring stack) run on a second build of the same network in
[`containerlab/`](containerlab/README.md): FRR routers and Linux-bridge switches,
declarable in one file, deployable in ninety seconds, and scriptable — which is
what makes a fault reproducible and a ticket's evidence regenerable instead of
remembered.

The purpose of this repository is not to collect topologies. It is to build one
place where every lab leaves behind something reusable: a working configuration,
a capture that was actually analysed, a fault that was actually diagnosed, and a
written note of what was learned. Everything here is self-contained.

## The goal

Go from *"I know the theory"* to *"I can run a shift"*.

Concretely, by the time this repo is finished I should be able to:

- Build and address a multi-VLAN site on a blank GNS3 canvas without a guide.
- Explain any packet on the wire, layer by layer, from a capture.
- Take a ticket like *"the internet is down for the sales floor"* and get from
  symptom to root cause with a repeatable method instead of guesswork.
- Prove a fix worked, and prove it will not break again.
- Operate the tooling a NOC actually uses: syslog, SNMP polling, NTP, a
  monitoring dashboard, and alert triage.

## Hardware reality

This machine is the limit, so the lab is designed around it.

| Item | Value | Why it matters |
|---|---|---|
| CPU | AMD Ryzen 5 5500U, 6C/12T | Enough for 6-8 virtual routers |
| RAM | 9.6 GiB | **The real constraint** |
| Disk free | ~86 GB | Fine for IOS images, not for many VM images |
| GNS3 | 3.0.6, local server, KVM available | No separate GNS3 VM needed |
| Docker | 29.1.3 | Servers run as containers, not VMs |
| Platform | Linux (Ubuntu 24.04) | Native `/dev/kvm` access |

**Design rules that follow from this:**

1. Maximum ~6-8 `vios` routers running at once. One vIOS is roughly 300-500 MB.
2. PCs are **VPCS** (~10 MB each), never a QEMU VM.
3. Servers are **Docker containers** (~10-100 MB), never a QEMU VM.
4. One lab runs at a time. Close the project when finished — do not leave it
   suspended in the background.
5. `c7200` is a fallback only. It costs RAM and adds nothing that `vios` lacks.

## Repository layout

```
noc-home-lab/
├── README.md                  # this file — goals, rules, index
├── docs/                      # the reference library (read these)
│   ├── 00-roadmap.md          # phased plan, Phase 0 → 5
│   ├── 01-ip-plan.md          # the addressing scheme used by every lab
│   ├── 02-device-inventory.md # templates, images, containers, RAM budget
│   ├── 03-gns3-setup.md       # building and running the lab environment
│   ├── 04-troubleshooting-method.md
│   ├── 05-ios-cheatsheet.md
│   ├── 06-linux-cheatsheet.md
│   ├── 07-monitoring-basics.md
│   ├── 08-glossary.md
│   ├── 09-wireshark-guide.md
│   └── tickets/               # how incident-style labs work
├── labs/                      # one folder per lab, fully self-contained
│   ├── README.md              # lab index and progression
│   ├── lab-00-template/       # copy this to start a new lab
│   └── lab-NN-name/README.md  # the lab guide
├── configs/
│   ├── golden-configs/        # tested baselines, start every lab here
│   └── lab-NN/                # exported configs, proof the lab was done
├── containerlab/              # the same network as one deployable file
│   ├── topology.clab.yml      #   22 nodes: FRR routers, bridges, NOC stack
│   ├── faults/T-NN-*.sh       #   the ten tickets, as injectable faults
│   ├── scripts/               #   baseline, ticket runner, Zabbix bootstrap
│   └── artifacts/             #   the raw evidence the write-ups quote
├── docker/                    # the lab's container images (servers, NOC)
├── topology/                  # GNS3 portable project exports
├── wireshark/                 # captures and analysis notes
└── ansible/                   # Phase 5: push baselines at scale
```

## How a lab works

This loop is the whole method. Skipping steps is how a lab turns into an
afternoon of clicking with nothing to show for it.

1. **Read the objective.** Open `labs/lab-NN-name/README.md` and know what you
   are proving before you start clicking.
2. **Build the topology.** First attempt: follow the guide. Second attempt:
   rebuild it from memory. The rebuild is the real test.
3. **Configure.** Copy from `configs/golden-configs/` and change only what the
   lab needs. Never retype a baseline from memory.
4. **Verify.** Run every command in the verification table and paste the *real*
   output into the note. If the output is wrong, the lab is not finished.
5. **Capture.** Take the capture listed in the lab, save it to `wireshark/`, and
   write down what each interesting packet is doing.
6. **Break it, then fix it.** Run the *Break it / fix it* section. This is the
   step that separates a lab from a portfolio.
7. **Export the configs** to `configs/lab-NN/`, then look at them and ask what
   you would change next time.
8. **Commit.** One lab, one commit. `git log` then doubles as a progress report.

Step 6 is the step most people skip. Step 6 is the one that gets you hired.

## Lab index

| # | Lab | Level | Time | Core skills |
|---|---|---|---|---|
| 01 | [Basic LAN](labs/lab-01-basic-lan/README.md) | micro | 45 min | Switching, MAC learning, ARP, ICMP |
| 02 | [Router + 2 LANs](labs/lab-02-router-two-lans/README.md) | micro | 60 min | IPv4 addressing, static routing, routing table |
| 03 | [VLAN + Trunk + Inter-VLAN](labs/lab-03-vlan-trunk/README.md) | micro | 90 min | VLANs, 802.1Q, router-on-a-stick |
| 04 | [DHCP + DNS + HTTP](labs/lab-04-dhcp-dns-http/README.md) | micro | 90 min | DHCP DORA, DNS, HTTP, Docker services |
| 05 | [Network Management](labs/lab-05-network-management/README.md) | micro | 90 min | SSH, NTP, syslog, SNMP |
| 06 | [Small Enterprise HQ](labs/lab-06-hq/README.md) | combo | 2-3 days | Design, inter-VLAN, OSPF, ACLs, DHCP relay |
| 07 | [Branch + WAN + NAT](labs/lab-07-branch-wan/README.md) | combo | 2 days | WAN links, OSPF, NAT/PAT, failover |
| 08 | [Redundancy](docs/designs/redundancy-design.md) *(design)* | complex | 1 day | HSRP, OSPF tuning, STP root control, convergence measurement |
| 09 | [Full NOC](labs/lab-09-full-noc/README.md) | complex | 2-3 days | Zabbix, SNMP polling, low-level discovery, alert design, measured failover drill |

Status values used in lab notes: `not-started` · `in-progress` · `done` ·
`needs-rework` (it worked but I could not explain why).

## Skill coverage

Where each skill is actually practised. A skill only counts once it appears in
at least one *done* lab.

| Skill | Introduced | Reinforced | Mastered |
|---|---|---|---|
| Switching / MAC learning | 01 | 03, 06 | 08 |
| ARP / neighbour resolution | 01 | 02, 06 | 07 |
| IPv4 addressing / VLSM | 02 | 03, 06 | 07 |
| Static routing | 02 | 06 | 07 |
| VLANs / 802.1Q / trunks | 03 | 06 | — |
| Spanning Tree | — | 06 | 08 |
| OSPF | — | 06 | 07, 08 |
| DHCP (server + relay) | 04 | 06 | 07 |
| DNS | 04 | 06 | 09 |
| HTTP / application layer | 04 | 06 | 09 |
| SSH / device hardening | 05 | 06 | 09 |
| NTP | 05 | 06 | 09 |
| Syslog | 05 | 06 | 09 |
| SNMP | 05 | 06 | 09 |
| ACLs | — | 06 | 07 |
| NAT / PAT | — | 07 | 07 |
| HSRP / first-hop redundancy | — | — | 08 |
| Fault diagnosis | 03 (break it) | 04, 05 | tickets |
| Wireshark / packet analysis | 01 | 04, 07 | tickets |
| Monitoring / alerting | 05 | 06 | 09 |
| Automation (Ansible) | — | — | — |

## Reference library

| Document | Use it when |
|---|---|
| [docs/00-roadmap.md](docs/00-roadmap.md) | You want to know what is next and why |
| [docs/01-ip-plan.md](docs/01-ip-plan.md) | You need an address, a VLAN ID, or a WAN subnet |
| [docs/02-device-inventory.md](docs/02-device-inventory.md) | You need to know what a device is and what it costs in RAM |
| [docs/03-gns3-setup.md](docs/03-gns3-setup.md) | GNS3 itself is misbehaving, or you are building a new lab |
| [docs/04-troubleshooting-method.md](docs/04-troubleshooting-method.md) | Something is broken and you are about to guess |
| [docs/05-ios-cheatsheet.md](docs/05-ios-cheatsheet.md) | You forgot the command, not the concept |
| [docs/06-linux-cheatsheet.md](docs/06-linux-cheatsheet.md) | You are working on the container/server side |
| [docs/07-monitoring-basics.md](docs/07-monitoring-basics.md) | You are wiring syslog, SNMP or Zabbix |
| [docs/08-glossary.md](docs/08-glossary.md) | A term came up and you want one clean line |
| [docs/09-wireshark-guide.md](docs/09-wireshark-guide.md) | You are about to capture traffic, or stuck reading a capture |
| [docs/tickets/README.md](docs/tickets/README.md) | You are doing an incident-style lab |
| [containerlab/README.md](containerlab/README.md) | You want the whole lab deployable from one file, or you are running the NOC |

## Conventions

- **Lab folder and GNS3 project share the same name**: `lab-03-vlan-trunk`.
- **Device names**: `R1..Rn` routers · `SW1..SWn` switches · `PC1..` VPCS ·
  `SRV-*` containers · `ISP` the simulated internet.
- **Interface convention**: lowest port faces the LAN, highest port faces the
  WAN or the uplink. Same in every lab, so cables are never a guess.
- **Addressing** always comes from `docs/01-ip-plan.md`. If a lab needs a new
  subnet, that document is updated first.
- **Commit messages**: `lab-03: inter-vlan routing working, ACL next` — specific
  enough that `git log` reads as a history of work, not a list of file changes.
- **Lab notes are written in English.** So are configs, comments and captures.
