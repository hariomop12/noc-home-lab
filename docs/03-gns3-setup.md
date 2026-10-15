---
tags: [homelab, gns3, setup, environment]
status: active
---

# 03 — GNS3 Setup

How the lab environment is built, how to add a node, and how to fix GNS3 itself
when it misbehaves.

This document is about the **tooling**. Networking concepts live in `labs/`.

## Environment

| Component | Value |
|---|---|
| GNS3 | 3.0.6, local server (no separate GNS3 VM) |
| Hypervisor | QEMU with KVM (`/dev/kvm` present, user in the `kvm` group) |
| Console | telnet |
| Endpoints | VPCS |
| Servers | Docker containers |
| Host OS | Ubuntu 24.04 |

Using the **local server** rather than the GNS3 VM is deliberate: it halves the
memory footprint and removes an entire class of "the VM is not reachable"
problems. The trade-off is that this machine must have KVM working.

Verify the basics:

```bash
ls -l /dev/kvm            # must exist
groups | grep kvm          # your user must be in this group
gns3 --version             # 3.0.6
docker ps                  # docker must answer without sudo
```

If `/dev/kvm` is missing, virtualisation is disabled in BIOS and every node will
run at emulation speed. Fix that first — nothing else in this lab is worth doing
on an unaccelerated host.

## Directory layout on disk

GNS3 keeps its own data outside this repository. That is intentional: images and
project files are large and machine-specific, so they are never committed.

| Path | Contains |
|---|---|
| `~/GNS3/images/IOS/` | Classic IOS images (`c7200`) |
| `~/GNS3/images/QEMU/` | QEMU images (`vios`, `vios_l2`) |
| `~/GNS3/projects/` | Live GNS3 projects (working copies) |
| `~/.config/GNS3/3.0/` | Server and GUI configuration |

The repository is the **archive**, not the working directory. A lab is built in
GNS3, exported, and the export lands in `topology/` here.

## Adding a QEMU router template (`vios`)

1. `Edit → Preferences → QEMU VMs → New`.
2. Name it exactly `Cisco vios L3` and point the image at
   `~/GNS3/images/QEMU/vios-adventerprisek9-m.SPA.159-3.M6.qcow2`. GNS3 should
   detect the platform automatically; if not, set it manually to `x86_64`.
3. RAM: **512 MB**. More is wasted, less can cause boot failures.
4. Console type: **telnet**.
5. Adapters: **4** (this matches the `GigabitEthernet0/0` … `0/3` numbering used
   throughout the IP plan).
6. Under the advanced/optimisation tab, ensure KVM acceleration is enabled.
7. Save, then start a single instance and wait for the console banner. If the
   console is blank, see *Troubleshooting* below.

## Adding a QEMU switch template (`vios_l2`)

Same procedure, with `vios_l2-adventerprisek9-m.ssa.high_iron_20200929.qcow2`.

Two differences matter:

- `vios_l2` boots noticeably slower. Give it 60-90 seconds before concluding it
  is broken.
- Its ports start as switchports. An IP address can only be configured on an SVI
  (`interface Vlan99`), never directly on `GigabitEthernet0/0`.

## Adding a Docker container template

1. Docker images are managed under `Preferences → Docker containers → New`.
2. Pick the image from the local list (images must be pulled with `docker pull`
   first — GNS3 will not fetch them for you).
3. Console type: **telnet**.
4. Give the template a name that matches the inventory, e.g. `dnsmasq`.
5. Optional: set the container's startup command and environment variables at the
   template level so every new instance starts identically.

The containers used here are listed in
[02-device-inventory.md](02-device-inventory.md).

## The reusable `Lab Template` project

The single highest-value piece of setup work. Built once, it means a new lab
never starts from a blank canvas again.

The template kept in `~/GNS3/projects/` is:

| Node | Template | Role | Cabled to |
|---|---|---|---|
| `PC1` | VPCS | client | `SW1` Ethernet1 |
| `PC2` | VPCS | client | `SW1` Ethernet2 |
| `HOST` | Docker (`alpine:3.20`) | server placeholder | `SW1` Ethernet0 |
| `SW1` | vios_l2 | access switch | `R1` GigabitEthernet0/0 |
| `R1` | vios | router / gateway | `SW1` and `CLOUD` |
| `CLOUD` | Cloud (host) | uplink / NAT to the host | `R1` GigabitEthernet0/1 |

Cabling follows the standing convention — **VPCS → switch → router → cloud** —
with the Docker host on the lowest free switch port.

How to build or rebuild it:

1. New project, name it exactly `Lab Template`.
2. Add the six nodes above from the existing templates.
3. Cable them exactly as the table says, and give every node the name shown.
   The switch is a 4-port GNS3 switch, so all four ports are used.
4. Do **not** leave the nodes running. This project is a source of pre-wired
   nodes, not a running lab. Baselines are applied per lab from
   `configs/golden-configs/` (the template is wiring only, not configuration).
5. Save, then close the project.

To start a new lab: duplicate the template project, rename it to `lab-NN-name`,
and extend it. The IP plan convention still applies — lowest port to the LAN,
highest port to the WAN.

## Connecting the lab to the host

The containers run on the Docker host, which is this machine. Two ways to reach
them from inside a GNS3 topology:

| Method | When to use |
|---|---|
| **Docker container node** directly in the topology | Default. Cleanest. The container becomes a node with a MAC address like any other device. |
| **Cloud node → host interface** | When you need the topology to reach something on the host, such as a local service or the internet through NAT |

For the cloud method, create a cloud node, then `Configure → Show special
Ethernet interfaces` and bind it to a Docker bridge interface rather than a
physical NIC. Bridging a lab to a physical interface puts lab traffic on the real
network, which is rarely what is wanted.

## Snapshots and exports

| Action | What it does | When |
|---|---|---|
| Snapshot | Saves node state in the GNS3 project | Before breaking something in a ticket lab |
| Export portable project | Bundles the topology into a single `.gns3project` file | Every time a lab is finished |
| Export config | Dumps a device's startup configuration | When the lab is verified |

Workflow at the end of every lab:

```bash
# 1. In GNS3: File → Export portable project
# 2. Move the export into the repository
mv ~/Downloads/lab-03-vlan-trunk.gns3project ~/noc-home-lab/topology/

# 3. Export device configs into the lab's config folder
mkdir -p ~/noc-home-lab/configs/lab-03-vlan-trunk

# 4. Commit
cd ~/noc-home-lab
git add topology configs
git commit -m "lab-03: vlan trunk and inter-vlan routing verified"
```

`project-files/` is ignored by `.gitignore` on purpose: it contains large,
machine-specific fragments that break when moved between machines. The portable
export is the thing worth keeping.

## Troubleshooting GNS3 itself

| Symptom | Likely cause | Check | Fix |
|---|---|---|---|
| Node will not start | KVM unavailable or image missing | `ls -l /dev/kvm`, `ls ~/GNS3/images/QEMU/` | Enable virtualisation, re-add the image |
| Node starts but console is blank | Boot still in progress, or wrong console type | Wait 60s, check console type | Set console to telnet, re-read the console |
| Everything is extremely slow | Running without KVM | Check for `-enable-kvm` in the node's QEMU command | Fix KVM; do not tune anything else first |
| Switch ports show no link | Cables attached to wrong port or node not booted | `show ip interface brief` on the switch | Re-cable, wait for boot |
| Container has no console | Console type mismatch | Compare with another working container template | Set console type to telnet |
| `Address already in use` | Console port conflict | Preferences → console ports | Restart the GNS3 server, let it reallocate |
| Project will not open | Moved project files | Check the project folder for `project-files/` | Re-import the portable export instead |
| Host is swapping | Too many nodes | `free -h` | Close unused projects, shut down unused nodes |
| Nodes unresponsive after host sleep | Stale server state | `gns3server` process | Restart the GNS3 server |

## Housekeeping rules

1. **One project per lab.** Names match the repository folder exactly.
2. **Close projects when finished.** Suspended nodes still hold memory.
3. **Export before deleting.** A topology that exists only in `~/GNS3/projects/`
   is one accidental deletion away from gone.
4. **Configs live in the repository**, not only inside the project. The project
   is the topology; the config is the knowledge.
5. **Never commit images, keys or `project-files/`.** `.gitignore` already
   covers this, but check `git status` before every commit.

### Keeping the project list clean

Practice projects pile up fast. This lab's list once held **32 projects** —
unnamed drafts, `*-1` duplicates GNS3 creates on a name clash, empty projects and
one corrupt project that could not even be deleted through the GUI. The list
should hold two things and little else:

| Keep | Delete |
|---|---|
| The active lab project, named `lab-NN-name` | Empty projects (0 nodes) — there is no topology to lose |
| `Lab Template` | Exact duplicates (`*-1`) |
| A finished lab until it is exported and committed | Broken or unwired projects (no links) |
| | Finished labs after their export + configs are committed |

**Export before deleting.** A project is disposable only once its exported
topology, configs and captures are committed. If a project refuses to delete
(corrupt internal data), delete its folder under `~/GNS3/projects/` directly —
the local controller re-scans that directory on the next start, and the entry
then clears.
