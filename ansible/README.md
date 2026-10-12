---
tags: [homelab, ansible, automation]
status: not-started
---

# Ansible (Phase 5)

Abhi khaali. **Jaan-boojh ke** — Ansible tabhi sense banata hai jab 5-6 lab manually
kar chuke ho aur pata ho ki "baseline" kya hota hai.

## Aage kya aayega

```
ansible/
├── inventory.ini          # lab devices (SSH)
├── group_vars/
│   ├── all.yml            # common (ntp, syslog, snmp, domain)
│   ├── routers.yml
│   └── switches.yml
├── playbooks/
│   ├── baseline.yml       # golden config push
│   ├── collect-facts.yml  # show version / interfaces -> docs/
│   └── backup-configs.yml # running-config -> configs/lab-NN/
└── templates/
    └── router-baseline.j2
```

## Prerequisites (jab shuru karein)

- `ansible` + `ansible.netcommon` + `cisco.ios` collection
- GNS3 nodes ka SSH reachable (mgmt network `10.254.0.0/24` ya `10.10.99.0/24`)
- `network_cli` connection plugin, `ansible_user: admin`
- Vault se password (`ansible-vault`) — `.gitignore` me already ignored

> Goal: ek command se 6 routers pe baseline. **Manual + Ansible ka output same aana chahiye** —
> warna Ansible pe bharosa mat karo.
