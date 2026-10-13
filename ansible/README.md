---
tags: [homelab, ansible, automation]
status: not-started
---

# Ansible

Empty on purpose.

Ansible makes sense once the manual configuration is understood, not before. Its
value here is scale and repeatability: pushing one baseline to every device in one
run, and collecting what the devices actually have.

## Why this phase comes last

| Manual first | Then automate | Mistake it prevents |
|---|---|---|
| Write the baseline by hand | Template it with Jinja2 | Automating a configuration nobody has verified |
| Collect outputs with `show` | Collect with `cisco.ios` facts modules | Trusting data you have not compared against reality |
| Fix a device by hand | Fix a hundred with a playbook | Not knowing what the playbook changed |

The rule: **automation output must match manual output before automation is
trusted.** If the playbook and the hand-built config differ, the playbook is wrong
until proven otherwise.

## Planned structure

```
ansible/
├── README.md
├── inventory.ini          # lab devices over SSH
├── group_vars/
│   ├── all.yml            # NTP, syslog, SNMP, domain, AAA intent
│   ├── routers.yml
│   └── switches.yml
├── playbooks/
│   ├── baseline.yml       # push the golden baseline
│   ├── collect-facts.yml  # gather version and interface data into docs/
│   └── backup-configs.yml # running-config into configs/lab-NN/
└── templates/
    └── router-baseline.j2
```

## Prerequisites

- `ansible-core`, plus the `cisco.ios` and `ansible.netcommon` collections
- Devices reachable over SSH on the management network (`10.10.99.0/24`)
- `network_cli` connection with `ansible_user: admin`
- The password stored with `ansible-vault` — `.gitignore` already excludes
  `vault_pass*`
- Device configuration done first: SSH enabled, RSA key generated, `transport
  input ssh` on the VTY lines

## First three playbooks to write

1. **`collect-facts.yml`** — read-only, zero risk. Pull `show version`,
   `show ip interface brief` and interface counters. This is always the first
   playbook, because it cannot break anything and it validates connectivity.

2. **`backup-configs.yml`** — also read-only. Save every device's running
   configuration into `configs/`. This turns the repository into a real record.

3. **`baseline.yml`** — the first playbook that writes. Run it against one device
   first, then diff the result against the same configuration applied by hand.

## Related documents

- [../docs/00-roadmap.md](../docs/00-roadmap.md) — Phase 5
- [../docs/05-ios-cheatsheet.md](../docs/05-ios-cheatsheet.md) — the commands these
  playbooks will replace
