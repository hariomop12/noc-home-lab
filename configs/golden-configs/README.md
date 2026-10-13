---
tags: [homelab, golden-configs]
status: active
---

# Golden Configs

Reusable, verified baselines. Every lab starts by copying one of these.

| File | For | What it contains |
|---|---|---|
| `vios-router-baseline.cfg` | `vios` L3 router | Hostname, SSH, secrets, NTP, syslog, SNMP, Loopback0, CDP/LLDP |
| `vios-switch-baseline.cfg` | `vios_l2` switch | VLANs 10/20/30/40/99, management SVI, SSH, rapid-PVST, access and trunk templates |

## Conventions these baselines follow

| Item | Value |
|---|---|
| Router Loopback0 | `10.255.0.<N>` — R1 is `10.255.0.1` |
| Switch management address | `10.10.99.1<N>` — SW1 is `10.10.99.11` |
| Switch default gateway | `10.10.99.1` |
| DNS / NTP / Syslog | `10.100.0.10` / `10.100.0.13` / `10.100.0.11` |
| Enable secret and local user | `Cisco123` (lab only) |

Both files contain placeholders: `<N>` is the device number and `X/0` is the
interface slot, so the baseline can be pasted onto any node of that type.

Interface examples are commented out rather than active. A baseline that
configures interfaces it should not own causes confusion in the next lab; a
commented example does not.

## Adding a new golden config

1. Configure and **verify** in a lab (ping works, `show` output is as expected).
2. Export it to `configs/lab-NN/<device>.cfg`.
3. Merge only the reusable parts into `golden-configs/` — strip anything
   lab-specific such as a particular interface address or a one-off VLAN.
4. Commit: `configs: golden — add OSPF baseline`.

## Planned additions

- [ ] `vios-router-ospf.cfg` — single-area OSPF baseline
- [ ] `vios-router-nat.cfg` — NAT/PAT overload baseline
- [ ] `vios-switch-l2sec.cfg` — port security, BPDU guard, DHCP snooping
- [ ] `ios-acl-examples.cfg` — standard and extended ACL patterns
- [ ] `ios-ipv6-baseline.cfg` — IPv6 addressing with SLAAC

## Related documents

- [../README.md](../README.md)
- [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md)
- [../../docs/05-ios-cheatsheet.md](../../docs/05-ios-cheatsheet.md)
