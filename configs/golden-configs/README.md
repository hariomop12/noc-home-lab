---
tags: [homelab, golden-configs]
status: active
---

# Golden Configs

Reusable, tested baselines. Yahi se har lab start hota hai.

| File | Kiske liye | Kya include hai |
|---|---|---|
| `vios-router-baseline.cfg` | vios L3 router | hostname, SSH, secrets, NTP, syslog, SNMP, Loopback0, CDP/LLDP |
| `vios-switch-baseline.cfg` | vios_l2 switch | VLANs 10/20/30/40/99, SVI mgmt, SSH, STP rapid-pvst, trunk template |

## Convention (IP plan ke hisaab se)

- Router: Loopback0 = `10.255.0.<n>` (R1 → .1)
- Switch mgmt: `10.10.99.1<n>` (SW1 → 10.10.99.11), gateway `10.10.99.1`
- DNS/NTP/Syslog: `10.100.0.10/13/11`
- Password: `Cisco123` (lab only)

## Naya golden banane ka tarika

1. Lab me config karo, **verify karo** (ping + `show` output OK).
2. `configs/lab-NN/<device>.cfg` me export karo.
3. Sirf generic cheezein `golden-configs/` me merge karo (lab-specific IP/VLAN nahi).
4. Commit: `configs: golden <device> — <kya add hua>`

## TODO (aage add karna hai)

- [ ] `vios-router-ospf.cfg` — single-area OSPF baseline
- [ ] `vios-router-nat.cfg` — NAT/PAT overload baseline
- [ ] `vios-switch-l2sec.cfg` — port-security, BPDU guard, DHCP snooping
- [ ] `ios-acl-standards.cfg` — standard + extended ACL examples
- [ ] `ios-ipv6-baseline.cfg` — IPv6 + SLAAC
