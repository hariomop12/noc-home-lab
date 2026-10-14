---
tags: [homelab, configs]
status: active
---

# Configs

Device configurations, in two flavours.

| Folder | Contains | When it is used |
|---|---|---|
| `golden-configs/` | Reusable, tested baselines | Starting point for every new lab |
| `lab-NN/` | The final configuration of a specific lab | After the lab is verified, as evidence |

## The rule

1. **Start from golden.** Copy a baseline, change only what the lab needs. Never
   retype a baseline from memory — that is how typos become "unexplained bugs".
2. **Promote good changes back.** If a lab produced a better baseline (a cleaner
   ACL, a hardening step worth keeping), merge it into `golden-configs/`.
3. **Golden means working.** A configuration that has not been verified does not
   belong in `golden-configs/`.

## Exporting a configuration from GNS3

Either:

- Right-click the node → **Export config**, or
- On the device console: `show running-config`, then copy the output into
  `configs/lab-NN/<device>.cfg`.

Export **after** verification, not before. A config exported mid-debugging is a
record of a mistake.

## Folder layout

```
configs/
├── README.md
├── golden-configs/
│   ├── README.md
│   ├── vios-router-baseline.cfg
│   └── vios-switch-baseline.cfg
└── lab-01-basic-lan/
    └── SW1.cfg
└── lab-02-router-two-lans/
    └── R1.cfg
└── lab-03-vlan-trunk/
    ├── R1.cfg
    ├── SW1.cfg
    └── SW2.cfg
└── lab-04-dhcp-dns-http/
    ├── R1.cfg
    └── SW1.cfg
```

`configs/lab-NN/` appears when the first lab is completed. It does not need to
exist in advance.

## Credentials used in this lab

| Item | Value |
|---|---|
| `enable secret` | `Cisco123` |
| Local user | `admin` / `Cisco123` |
| Domain name | `lab.local` |

⚠️ These values exist only so the lab is reproducible. A real network uses
centralised authentication (TACACS+ or RADIUS), unique per-engineer credentials,
and no shared local passwords. Do not carry this convention anywhere beyond the
lab.

## Related documents

- [golden-configs/README.md](golden-configs/README.md)
- [../docs/01-ip-plan.md](../docs/01-ip-plan.md) — the addresses these configs use
- [../docs/05-ios-cheatsheet.md](../docs/05-ios-cheatsheet.md) — command reference
