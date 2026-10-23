---
tags: [homelab, roadmap, noc]
status: in-progress
---

# 00 — Roadmap

The plan for this lab, in phases. Each phase has an exit criterion: the next
phase does not start until the previous one is at least 90% done.

Structure: **Micro → Combo → Complex → Tickets → Full NOC.**

---

## Phase 0 — Foundation

Nothing in this phase teaches networking. It exists so that every later lab can
start in five minutes instead of an hour.

- [x] Repository structure (`docs/`, `labs/`, `configs/`, `topology/`, `wireshark/`, `ansible/`)
- [x] `.gitignore` covering images, keys, GNS3 project files and secrets
- [x] Fixed addressing scheme in `docs/01-ip-plan.md`
- [x] Golden baseline configs for `vios` and `vios_l2`
- [x] Lab guide template
- [x] Reference library (setup, troubleshooting method, cheatsheets, monitoring, glossary)
- [x] Git remote configured and first push
- [x] GNS3 project cleanup: one project per lab; empty, duplicate and junk
      projects removed (32 → 2: `Lab Template` + the active lab)
- [x] Build a `Lab Template` GNS3 project (vios + vios_l2 + 2× VPCS + Docker
      host + cloud, pre-cabled)
- [x] Verify one full round trip: template → lab → export → commit
      (`topology/lab-05-network-management.gns3project`)

**Exit criterion:** a new lab can be started from the template, built, verified,
exported and committed without any setup work or improvisation.

**Status: complete** — the GNS3 project list is clean (2 projects), the `Lab
Template` is pre-cabled, and lab 05 was exported through the full round trip.

---

## Phase 1 — Micro labs (01-05)

One concept per lab, 45-90 minutes, always ending with a broken thing to fix.

- [x] **Lab 01 — Basic LAN.** Two PCs and a switch. Watch MAC learning happen,
      capture ARP, explain why the first ping is slower than the second.
- [x] **Lab 02 — Router + 2 LANs.** Two subnets, one router. Understand what a
      gateway actually is, and read a routing table like a sentence.
- [x] **Lab 03 — VLAN + Trunk + Inter-VLAN.** VLAN 10/20/99, an 802.1Q trunk,
      and router-on-a-stick subinterfaces. Break the trunk and diagnose it.
- [x] **Lab 04 — DHCP + DNS + HTTP.** dnsmasq and nginx as containers. Capture a
      full DORA exchange, a DNS query, and an HTTP request over TCP.
- [x] **Lab 05 — Network Management.** SSH hardening, NTP, central syslog, SNMP
      polling. First time the lab produces telemetry instead of just packets.

**Exit criterion:** a micro lab can be designed, built, verified, captured,
broken and fixed without following a guide line by line.

---

## Phase 2 — Combo: Small Enterprise HQ

The first lab where no configuration is given. Only a specification.

> A company of 100-200 users across HR, IT and Sales. Two switches and one
> router. The site needs DHCP, DNS, HTTP, SSH, central syslog and NTP. Departments
> must be separated. Monitoring must be able to see every device.

- [x] Write the design document before touching GNS3: `docs/designs/hq-design.md`
      — topology, addressing, VLANs, port assignments, routing, security intent.
- [x] Build it from your own design, then compare against the design document.
- [x] Inter-VLAN routing with OSPF, plus a default route out.
- [x] Extended ACLs: Sales cannot reach HR, IT can reach everything.
- [x] DHCP relay (`ip helper-address`) with the DHCP server in the SERVERS VLAN.
- [x] Prove every requirement with a command or a capture, not an opinion.

**Exit criterion:** the site works end to end, every device is visible in
monitoring, and the design document matches what is actually running.

**Status: complete** — 15 of 15 verification rows pass, four captures and four
exported configurations are committed, and the exported configs were diffed
against `docs/designs/hq-design.md`. One fault (ACL entry reordered) injected,
diagnosed and fixed.

---

## Phase 3 — Branch + WAN

The second site. HQ from Phase 2 gains a branch office, a shared ISP and a
transit link between them.

- [x] Write the design document first: `docs/designs/branch-wan-design.md`
      — topology, addressing, routing, NAT, failover and the drills that prove it.
- [x] Two sites (HQ and BR1) connected through a simulated ISP.
- [x] Static routing first, then OSPF. Measure and compare convergence.
- [x] NAT/PAT overload so the LAN can reach the simulated internet.
- [x] WAN failure: primary path down, backup path takes over. Record the timeline.
- [x] Decode OSPF hellos and the OSPF database exchange in Wireshark.

**Exit criterion:** a link can be failed and the network recovers without manual
intervention, and the recovery is explained from the packet level up.

**Status: complete** (2026-10-17). The build, the evidence and two corrections are
in `labs/lab-07-branch-wan/README.md`: drill B passed for the wrong reason (private
addresses were reaching the internet link), and the fix is designed into Phase 3.5
below.

---

## Phase 3.5 — Redundancy

Make the HQ survive the failures that Labs 06 and 07 could only demonstrate. Same
site, three layers of redundancy, all measured.

- [ ] Write the design document first: `docs/designs/redundancy-design.md`
      — HSRP split per VLAN, a second HQ router with its own WAN, cost-tuned OSPF,
      a second inter-switch trunk and STP root control.
- [ ] Add the second HQ router and give every VLAN a surviving gateway (HSRP).
- [ ] Give the HQ a second WAN link and prove both egress paths.
- [ ] Put two links between the switches and control which carries which VLAN.
- [ ] Measure each failover, and re-run the Lab 06/07 checks as regressions.

**Exit criterion:** any one of {an HQ router, an HQ uplink, a switch, a cable} can be
failed and the measured outage is explained by a specific protocol timer or topology
event — with no private address leaking to the internet on any path.

---

## Phase 4 — Ticket labs

The rule here is simple: **you are not given a configuration, you are given a
problem.** Format and severity guide: [tickets/README.md](tickets/README.md).

Method to follow every time: symptom → hypothesis → checks → root cause → fix →
prevention. Ten scenarios are listed in [../labs/README.md](../labs/README.md).

- [x] Break a working multi-VLAN network in ten different ways, one at a time.
- [x] For each one, write a ticket with the real commands and real output.
- [x] Write the RCA in a way a non-engineer could follow.
- [x] For each one, name the monitoring alert that *should* have caught it.

**Exit criterion:** a symptom is given, and root cause is found in under 15
minutes using method rather than memory.

**Status: complete** (2026-10-18). All ten tickets are written up in
`docs/tickets/T-01…T-10.md`, each quoting a raw transcript from
`containerlab/artifacts/T-NN-*.txt`. They run as code: one fault per script
(`containerlab/faults/`), injected, diagnosed, fixed and verified by
`./scripts/run-tickets.sh`, which re-generates every transcript. Four of them were
rewritten after their first evidence failed to prove anything: T-01 (the simulated
ISP does not filter RFC1918, so the proof has to be the source address on the wire,
not the ping), T-04 (turning STP off does not un-block the port STP had blocked, so
the loop stayed idle and there was no storm to see), T-05 ("the internet is down"
is really the WAN adjacency dead while the branch quietly carries the traffic), and
T-09 (the duplicate address has to announce itself, or nothing has it cached and the
owner notices nothing).

---

## Phase 5 — Full NOC simulation

- [x] Zabbix stack running in Docker (server, frontend, Postgres, agent).
- [x] Every router and switch polled over SNMP; interfaces and CPU monitored —
      interfaces are found by low-level discovery on the standard IF-MIB
      `ifOperStatus` OID (one rule and one item prototype covers every port that
      comes and goes), CPU and load come from the UCD-SNMP MIB.
- [x] Central syslog collecting from every device, with accurate NTP.
- [x] Triggers for interface down, high CPU, packet loss and SNMP unreachable —
      92 triggers over 12 monitored hosts: 41 declared by name and 51 created by
      the interface-discovery prototype, one per port. Every kind was exercised by
      a real fault, not only created.
- [ ] Dashboards, and a trigger for syslog severity 0-2. The collector already
      receives the logs; what is missing is the alarm on them.
- [x] Failover drill: fail a link, alert fires, timeline documented end to end —
      two faults, one trunk-wide (six alarms, the first 13 s after the fault and
      all by 14 s) and one single-uplink (one alarm, 25 s), each with a
      container-to-container ping as evidence independent of Zabbix.
- [ ] Ansible pushes the golden baseline to every device in one run, and the
      result is diffed against the manual configuration.

**Exit criterion:** something breaks, an alert fires before a user notices, and
the response follows a written runbook.

**Status: 5 of 6 done** (2026-10-18). The stack, the polling, the discovery, the
collector, the triggers and the drill are all in `labs/lab-09-full-noc/README.md`
with measured timelines; dashboards, the syslog-severity trigger and the Ansible
push are the honest gaps. One structural limitation is recorded there as well:
the NOC reaches every device over the lab's own network, so a fault that takes
that path away takes the monitoring with it — which is exactly what the drill
showed, and why the drill used a ping from an independent container as its
non-Zabbix evidence.

---

## Progress log

| Date | Change |
|---|---|
| 2026-10-12 | Phase 0 foundation: repo scaffold, IP plan, golden configs, templates, reference library, first push |
| 2026-10-13 | Lab 03 (VLAN + trunk + inter-VLAN) built, verified, captured, fault injected and fixed |
| 2026-10-13 | Lab 04 (DHCP + DNS + HTTP) built, verified, captured, `ip helper-address` fault injected and fixed |
| 2026-10-14 | Lab 01 (Basic LAN) built, verified, captured, Gi0/1 shutdown fault injected and fixed |
| 2026-10-14 | Lab 02 (Router + 2 LANs) built, verified, captured, Gi0/1 shutdown fault injected and fixed |
| 2026-10-15 | Lab 05 (Network Management) built, verified, captured, four faults injected and fixed |
| 2026-10-15 | Phase 0 closed out: GNS3 project list cleaned (32 → 2), `Lab Template` rebuilt pre-cabled, lab 05 exported to `topology/` |
| 2026-10-15 | Lab 06 design document drafted (`docs/designs/hq-design.md`) — topology, VLANs, addressing, ports, routing, security, verification; DD-1..DD-5 pending review |
| 2026-10-16 | Lab 06 (Small Enterprise HQ) built from the design: inter-VLAN router-on-a-stick, OSPF default route via the ISP, DHCP relay, Sales→HR ACL, management plane on all four devices. 15/15 verification rows pass, 4 captures and 4 configs exported, ACL fault injected and fixed. Phase 2 complete |
| 2026-10-16 | `noc-tools:lab` gained `tftp-hpa`; configs are now exported with `copy running-config tftp://10.100.0.50/<device>.cfg` instead of console copy-paste |
| 2026-10-16 | Phase 3 design agreed (`docs/designs/branch-wan-design.md`): BR1 through a simulated ISP, static-then-OSPF, NAT/PAT, three failover drills. Hidden trap recorded: GNS3 **Duplicate/Save-as** regenerates node IDs and therefore boots every node with a blank disk — a duplicate of the Lab 06 project came up factory-fresh. The original was untouched (both routers **and** both switches still held their saved configuration) and was renamed **in place** to `lab-07-branch-wan`. Trap, restore procedure and "verify on the device, not the disk file" written into `configs/README.md` |
| 2026-10-16 | Lab 06 HQ confirmed intact after the in-place rename: R1 `show ip ospf neighbor` FULL with the ISP and `O*E2 0.0.0.0/0` via `10.0.0.14`, SW1/SW2 hostnames and VLANs 10/20/30/40/99/999 present, PC1 leased `10.10.10.160/24`. Lab 07 builds on this base |
| 2026-10-16 | Lab 07 build, session 1: BR1 added and cabled (R2, SW3, PC5, PC6, SRV-NET). SW3 L2 done; R2 VLAN subinterfaces + relay + WAN + transit + loopback done. Stage 1 static routing verified, then Stage 2 OSPF: two neighbours each on both links, statics removed, transit preferred, `O*E2` default on both sites, PC5 reaches HQ. Paused before NAT. Progress and resume point recorded in the design document section 19 |
| 2026-10-17 | Lab 07 recovery after three host restarts: stale docker `container_id`s nulled in the project file, R2/SW3 restored from scripted configs, every node verified booting with its saved configuration. Root cause of the config loss recorded in `configs/README.md` (QEMU write cache — a hard power-off can lose a recent `write memory`); config export over TFTP is now the standing backup |
| 2026-10-17 | Lab 07 NAT fixed properly, and the fix took three attempts. The textbook source list translates site-to-site traffic (the transit must be `ip nat outside` for drill B), and the "obvious" repair — two `match ip address` lines in one route-map sequence — silently does nothing because they are OR'd and the second list ends in `permit any`. The working shape is **one extended ACL matching source and destination**. Found from evidence, not theory: `show ip nat translations` on R1 showed a lab address (`10.20.10.163`) as *outside local*, and the collector saw BR1's traffic as `10.0.0.17` |
| 2026-10-17 | Lab 07 verified end to end: BR1 leases from the HQ `dnsmasq` over the relay (`10.20.10.163`/`.164`, `giaddr` `10.20.10.1`), site-to-site ICMP both ways, both sites reach `200.1.1.10`, PAT proof (inside locals `10.10.10.165` and `10.10.20.162` → one inside global `10.0.0.13`), cross-site DNS (`web.lab.local`, `sw3.lab.local`), SNMP poll of R2 and SW3 from `CLIENT`. Four captures taken through the API rather than the GUI: hellos, database exchange at packet level, NAT/PAT on the internet edge, and a merged WAN-failover capture |
| 2026-10-17 | Lab 07 failover drills measured, not felt: drill A (transit down) 5.8 s and 18 lost probes on the first run, under 300 ms on the warm second run; drill B (HQ WAN down) the same, and `show ip route 0.0.0.0` during the outage proved the default relearned from the ISP **through the transit** (`O*E2 via 10.0.0.2`). Fault #1 injected (transit MTU mismatch): neighbour stuck in EXCHANGE, HQ→BR1 silently moved to the two-hop ISP path — fixed by removing the mismatch |
| 2026-10-17 | Lab 07 complete: guide written (`labs/lab-07-branch-wan/README.md`), six configurations exported to `configs/lab-07/`, four captures in `wireshark/`, design-vs-config diff done. Phase 3 closed |
| 2026-10-17 | Lab 07 correction, found while designing Lab 08: **drill B passed for the wrong reason.** A capture taken during the drill shows every echo request on the `ISP ↔ SRV-NET` link carrying the private source `10.100.0.50`. With `interface Gi0/1 overload` and `Gi0/1` shut, IOS creates no translation and forwards the packet untranslated; it only worked because the simulated ISP does not filter RFC1918 and has the HQ prefixes in OSPF. Recorded in the Lab 07 guide and design (section 8), and the corrected rule — internal transits are `ip nat inside`, so the router whose WAN is up translates — is designed into Lab 08 |
| 2026-10-17 | Phase 3.5 design written (`docs/designs/redundancy-design.md`, status proposed): a second HQ router with its own WAN, HSRP split per VLAN keeping the existing `.1` VIPs, OSPF adjacency confined to a new VLAN 200 core transit with cost tuning per VLAN for path symmetry, a second inter-switch trunk with STP root control aligned to the HSRP active roles, and five measured drills. Verification against Cisco's IOSvL2 feature list confirmed 16 Gigabit interfaces and HSRP support, and that SPAN is unavailable — so captures stay on links |
| 2026-10-18 | Phase 4 and Phase 5 rebuilt as **code, not clicks**, in `containerlab/`: the whole HQ + BR1 + ISP lab deploys from one `topology.clab.yml` (22 nodes, FRR routers, Linux-bridge switches, the repo's service images plus the Zabbix stack), and `./scripts/baseline.sh` proves 51 checks green. This is what makes the ticket labs repeatable — a fault is a script, not a story |
| 2026-10-18 | Phase 4 closed: ten tickets written up in `docs/tickets/T-01…T-10.md`, each quoting a raw transcript regenerated by `./scripts/run-tickets.sh`. Three tickets were rewritten ater their evidence turned out not to prove the fault: T-01 (the simulated ISP accepts private sources, so the proof is the source address on the wire), T-04 (disabling STP does not un-block the port STP already blocked, so there was no storm to see), T-05 (the branch was quietly carrying the traffic the WAN link was supposed to carry), T-09 (the duplicate address was not announcing itself, so the victim noticed nothing). A fifth bug was in the ticket infrastructure itself: the DHCP stop/start helpers killed their own shell with a pattern that matched the loop *and* the pkill command line, which made T-10's fault heal itself and left T-02's repair without a client |
| 2026-10-18 | Phase 5: Zabbix 7.0 stack (server, frontend, Postgres, agent) in the topology, declared entirely through the JSON-RPC API by `scripts/noc-bootstrap.py` — 12 hosts, 115 items, 92 triggers (41 declared, 51 discovered), interfaces found from `ifOperStatus` via low-level discovery, CPU and load from the UCD-SNMP MIB, every item supported. Drill run twice and measured: a trunk-wide fault fired six alarms with the first at 13 s, a single-uplink fault fired one alarm at 25 s, both repaired and verified, with a container-to-container ping as evidence that does not come from the thing being tested. Gaps left open on purpose: dashboards, the syslog severity 0-2 trigger, and the Ansible baseline push |
