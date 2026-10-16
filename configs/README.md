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
  `configs/lab-NN/<device>.cfg`, or
- Push it over TFTP from the `CLIENT` (`noc-tools:lab`) container — see below.

Export **after** verification, not before. A config exported mid-debugging is a
record of a mistake.

## Backing up configs over TFTP

The `noc-tools:lab` container carries `tftp-hpa`, so a device can hand its own
configuration to it. No console copy-paste, and the procedure is the same for
every device.

On the **CLIENT** console, start the server once:

```sh
mkdir -p /tftp
in.tftpd -l -c -s /tftp -u root &
```

On **each device**:

```
copy running-config tftp://10.100.0.50/<device>.cfg
```

Accept the default destination filename when prompted. The files land in
`/tftp` inside the container; copy them out with:

```sh
docker cp GNS3.CLIENT-1.<project-id>:/tftp/. configs/lab-NN/
```

`-c` allows the upload to create a file, and `-s` confines the server to
`/tftp`, so a device cannot write anywhere else. This is the same job the
Phase 5 `backup-configs.yml` playbook will do.

## Proving that a config was actually saved

`write memory` prints `Building configuration... [OK]`, which is not proof that
the device will boot with that configuration. Check the thing that matters:

```
show startup-config | include ^hostname
show startup-config | include ^ip route
```

Then, once per lab, prove it the hard way: stop the node, start it again, and
confirm the hostname and the management addresses are still there. A node that
comes back as `Router>` costs an hour and teaches nothing new.

Lab 06 is the cautionary tale. Its two routers booted from their saved
configuration, but its two **switches** did not — the switch startup-config was
not on disk when it was inspected later. Everything was recovered from the copies
in `configs/lab-06/`, which is the entire point of this section.

## Restoring a config from a backup

Console paste, in this order:

1. `enable`, then `configure terminal`.
2. Paste the whole file from `configs/lab-NN/<device>.cfg`. The `!` header block
   is a comment to IOS, so the file can be pasted unedited.
3. `end`, then `write memory`.
4. Verify against the design, not against hope: `show ip interface brief`,
   `show ip route`, `show vlan brief`, and the same checks the lab used when it
   was first built.

A device that already holds a partial configuration should be cleared first
(`write erase`, then `reload`, answering **no** to saving) so nothing stale
survives the paste.

The other half of this section is a GNS3 habit, and it is a real one:

| Action | Effect on node disks |
|---|---|
| **Rename** the project | Nothing. Same node IDs, same disks, same saved configs |
| **Save as** / **Duplicate** the project | New node IDs, **brand-new blank disks** — every device boots factory-fresh |

Copying a topology forwards what is in the project file (nodes, links, ports,
images). It does *not* forward what is inside each node's disk, and that is where
the startup-config lives. If a copy is ever needed, copy the project **directory**
from `~/GNS3/projects/<project-id>/` while GNS3 is closed.

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
└── lab-05-network-management/
    ├── R1.cfg
    └── SW1.cfg
└── lab-06-hq/
    ├── R1.cfg
    ├── ISP.cfg
    ├── SW1.cfg
    └── SW2.cfg
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
