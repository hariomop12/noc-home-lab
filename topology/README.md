---
tags: [homelab, topology, gns3]
status: active
---

# Topology

Archive of the GNS3 topologies built in this lab. One file per lab, exported as
a **portable project** so it can be reopened on any machine.

```
topology/
├── README.md
├── lab-05-network-management.gns3project
└── ...
```

Lab guides live in [../labs/](../labs/). This folder holds only the GNS3 exports —
the topology is the artefact, the guide is the knowledge.

## Exported so far

| File | Lab | Nodes | Notes |
|---|---|---|---|
| `lab-05-network-management.gns3project` | 05 | 7 — R1, SW1, SW2, PC1, CLIENT, SRV-SYSLOG, SRV-NTP | ~205 KB; exported with `include_images=false`, so no IOS/QCow2 images are bundled |

The export is produced by GNS3 itself, which guarantees it re-imports cleanly:

```bash
# via the GUI:  File → Export portable project
# or via the local server API (no GUI needed):
curl -s -X POST http://localhost:3080/v3/projects/<project-id>/close         # export needs a stopped project
curl -s    http://localhost:3080/v3/projects/<project-id>/export?include_images=false -o out.gns3project
```

## Exporting from GNS3

`File → Export portable project`

Then move the file in:

```bash
mv ~/Downloads/lab-03-vlan-trunk.gns3project ~/noc-home-lab/topology/
```

The export bundles the topology and the node definitions into one file.
`project-files/` is **not** committed — it is listed in `.gitignore` because it
contains large, machine-specific fragments that break when moved between
machines.

## Importing

`File → Import portable project` → select the `.gns3project` file.

If GNS3 complains about missing images, the required image is missing locally.
The list of required images is in
[../docs/02-device-inventory.md](../docs/02-device-inventory.md).

## Why the export and not the live project

| Live project (`~/GNS3/projects/`) | Export (`topology/`) |
|---|---|
| Working copy, changes constantly | Frozen snapshot of a finished lab |
| Contains `project-files/`, machine paths | Self-contained bundle |
| Not safe to move between machines | Moves cleanly |
| Not committed | Committed |

The live project is where the lab is built. The export is what survives.

## Naming rules

| Thing | Format | Example |
|---|---|---|
| Repository folder | `labs/lab-NN-name/` | `labs/lab-03-vlan-trunk/` |
| GNS3 project | `lab-NN-name` (identical) | `lab-03-vlan-trunk` |
| Export file | `lab-NN-name.gns3project` | `lab-03-vlan-trunk.gns3project` |
| Capture | `lab-NN-name-<what>.pcapng` | `lab-01-basic-lan-arp.pcapng` |
| Config | `<device>.cfg` | `R1.cfg`, `SW1.cfg` |

Keeping the GNS3 project name identical to the folder name means the file, the
project and the note are never a guessing game.

## Related documents

- [../docs/03-gns3-setup.md](../docs/03-gns3-setup.md) — building the environment
- [../labs/README.md](../labs/README.md) — lab index
- [../docs/01-ip-plan.md](../docs/01-ip-plan.md) — the addressing every topology uses
