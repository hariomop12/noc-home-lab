---
tags: [homelab, roadmap, noc]
status: in-progress
---

# 00 — Roadmap

Tier structure: **Micro → Combo → Real (ticket) → Complex → Full NOC.**

Rule: har phase ka exit criteria clear hai. Pehle wala 90% na ho, agla shuru nahi.

---

## Phase 0 — Foundation (repo + GNS3 hygiene)

- [x] Repo structure (topology / configs / docs / wireshark / ansible)
- [x] `.gitignore` (images, keys, project-files ignored)
- [x] IP plan fix (ek scheme, sab labs me same)
- [x] Golden configs — vios router + switch baseline
- [x] Lab note template
- [ ] GNS3 projects rename → `lab-NN-naam`
- [ ] Khaali/duplicate projects delete (`Temp`, `flab3`, `5`, `flab1-1`, `flab2-1`, `lab4f-1`)
- [ ] Ek "Lab Template" GNS3 project banao (vios + vios_l2 + VPCS + docker network pre-wired)
- [x] Remote (GitHub) add + first push → `hariomop12/noc-home-lab` (branch `main`)

**Exit:** naya lab 5 min me start ho jaye — template kholo, naam do, kaam shuru.

---

## Phase 1 — Micro Labs (01-05)

Ek lab = ek concept, 30-60 min. Har lab me: objective, topology, tasks, verification, "kya seekha".

- [ ] **Lab 01 — Basic LAN**: 2 PC + 1 switch, same subnet, ARP + MAC table dekho
- [ ] **Lab 02 — Router + 2 LANs**: 2 subnets, router 2 interface, static route, ping/traceroute
- [ ] **Lab 03 — VLAN + Trunk + Inter-VLAN**: VLAN 10/20/99, 802.1Q trunk, router-on-a-stick
- [ ] **Lab 04 — DHCP + DNS + HTTP**: dnsmasq (DHCP+wildcard DNS) + nginx, docker me
- [ ] **Lab 05 — Network Management**: SSH, NTP, syslog (rsyslog), SNMP poll, Zabbix agent scope

**Exit:** Micro lab apne aap bana sake, troubleshoot kar sake, capture samajh sake.

---

## Phase 2 — Combo: Small Enterprise HQ

Config nahi milegi — **spec milegi**. Khud design karo: topology, IP scheme, VLANs, ports, routing.

> Company: 100-200 users · Departments: HR, IT, Sales
> Required: DHCP, DNS, HTTP, SSH, Syslog, NTP · 2 switches + router
> Security: VLAN separation · Monitoring: syslog + SNMP

- [ ] Design doc likho (`docs/designs/hq-design.md`) — phir configure karo
- [ ] Inter-VLAN + OSPF (single area) + default route
- [ ] ACL (extended) — sales ko HR tak mat jaane do
- [ ] DHCP relay (`ip helper-address`) — DHCP server servers VLAN me
- [ ] Verification: har requirement ko prove karo (`show` + ping + capture)

**Exit:** poora HQ end-to-end chale + monitoring me device dikhe.

---

## Phase 3 — Branch + WAN

- [ ] 2 site (HQ + BR1) + ISP cloud
- [ ] Pehle static route, phir **OSPF** — convergence compare karo
- [ ] **NAT/PAT** (overload) — LAN se internet sim
- [ ] WAN failover: primary down → backup route active
- [ ] Wireshark: OSPF hello/packet decode

---

## Phase 4 — Real / Ticket Labs

Rule: **"config karo" nahi — "ye problem hai, fix karo".**
Har ticket: symptom → hypothesis → checks → root cause → fix → prevention.

Scenarios (GNS3 pe pehle tod do, phir fix karo):

| ID | Ticket | Status |
|---|---|---|
| R1 | LAN chalu, internet nahi (NAT/default route) | not-started |
| R2 | DHCP pool exhausted (PC ko IP nahi mila) | not-started |
| R3 | VLAN mismatch / trunk allowed-vlan galat | not-started |
| R4 | STP loop / broadcast storm (CPU 100%) | not-started |
| R5 | OSPF neighbor stuck in EXSTART / flapping | not-started |
| R6 | Interface flap + CRC errors | not-started |
| R7 | High latency / packet loss WAN pe (`tc` se emulate) | not-started |
| R8 | ACL ne silently traffic block kar diya | not-started |
| R9 | Duplicate IP address conflict | not-started |
| R10 | DNS resolve nahi ho raha (par ping IP se chal raha) | not-started |

---

## Phase 5 — Full NOC Simulation

- [ ] Zabbix (docker: server + web + agent2) — SNMP se routers poll karo
- [ ] Syslog central (rsyslog) + NTP
- [ ] Dashboards + triggers: `interface down`, CPU high, packet loss
- [ ] HSRP/VRRP failover drill + alert timeline likho
- [ ] **Ansible** se golden config push (baseline automate) — yahi Phase 14 (Automation) ka entry point

**Exit:** kuch toote to alert aaye → tu detect → diagnose → document kare. Yeh actual NOC job hai.

---

## Progress log

| Date | Kya kiya |
|---|---|
| 2026-10-12 | Phase 0 foundation — repo scaffold, IP plan, golden configs, template, first push |
