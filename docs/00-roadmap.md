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

- [ ] Write the design document before touching GNS3: `docs/designs/hq-design.md`
      — topology, addressing, VLANs, port assignments, routing, security intent.
- [ ] Build it from your own design, then compare against the design document.
- [ ] Inter-VLAN routing with OSPF, plus a default route out.
- [ ] Extended ACLs: Sales cannot reach HR, IT can reach everything.
- [ ] DHCP relay (`ip helper-address`) with the DHCP server in the SERVERS VLAN.
- [ ] Prove every requirement with a command or a capture, not an opinion.

**Exit criterion:** the site works end to end, every device is visible in
monitoring, and the design document matches what is actually running.

---

## Phase 3 — Branch + WAN

- [ ] Two sites (HQ and BR1) connected through a simulated ISP.
- [ ] Static routing first, then OSPF. Measure and compare convergence.
- [ ] NAT/PAT overload so the LAN can reach the simulated internet.
- [ ] WAN failure: primary path down, backup path takes over. Record the timeline.
- [ ] Decode OSPF hellos and the OSPF database exchange in Wireshark.

**Exit criterion:** a link can be failed and the network recovers without manual
intervention, and the recovery is explained from the packet level up.

---

## Phase 4 — Ticket labs

The rule here is simple: **you are not given a configuration, you are given a
problem.** Format and severity guide: [tickets/README.md](tickets/README.md).

Method to follow every time: symptom → hypothesis → checks → root cause → fix →
prevention. Ten scenarios are listed in [../labs/README.md](../labs/README.md).

- [ ] Break a working multi-VLAN network in ten different ways, one at a time.
- [ ] For each one, write a ticket with the real commands and real output.
- [ ] Write the RCA in a way a non-engineer could follow.
- [ ] For each one, name the monitoring alert that *should* have caught it.

**Exit criterion:** a symptom is given, and root cause is found in under 15
minutes using method rather than memory.

---

## Phase 5 — Full NOC simulation

- [ ] Zabbix stack running in Docker (server, frontend, Postgres, agent).
- [ ] Every router and switch polled over SNMP; interfaces and CPU monitored.
- [ ] Central syslog collecting from every device, with accurate NTP.
- [ ] Triggers and dashboards for: interface down, high CPU, packet loss,
      SNMP unreachable, syslog severity 0-2.
- [ ] Failover drill: fail a link, alert fires, timeline documented end to end.
- [ ] Ansible pushes the golden baseline to every device in one run, and the
      result is diffed against the manual configuration.

**Exit criterion:** something breaks, an alert fires before a user notices, and
the response follows a written runbook.

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
