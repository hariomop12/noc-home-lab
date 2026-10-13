---
lab: 00
level: template
status: template
tags: [homelab, lab, template]
---

# Lab NN — <Lab name>

> Copy this folder to `labs/lab-NN-name/` and fill it in.
> Delete the guidance comments as you go, but keep every numbered section —
> a lab without a verification table is not a lab.

## Metadata

| Field | Value |
|---|---|
| Level | micro / combo / complex |
| Estimated time | |
| Prerequisites | |
| Skills practised | |
| Related docs | |

## Objective

One paragraph. Finish this sentence: *after this lab I can ...*

Write it as a capability, not a task list. "I can explain why a PC in VLAN 10
cannot reach VLAN 20 and fix it" beats "configure VLANs".

## Theory

The minimum you need to understand *before* touching a device. Keep it short and
use your own words. If you cannot write this section without copying a textbook,
you are not ready to build the lab — read the concept note first.

## Topology

```
PC1 ── SW1 ── R1 ── ISP
```

Note which physical ports are used, because the port assignment is part of the
design, not an accident.

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | vios | Gi0/0 | 10.10.10.1/24 | LAN gateway |
| SW1 | vios_l2 | Gi0/1 | — | Access port to PC1 |
| PC1 | VPCS | eth0 | 10.10.10.100/24 | |

Addressing is taken from [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md).
If this lab needs something that is not in the IP plan, update the IP plan first.

## Build steps

1. Create the project in GNS3 and name it `lab-NN-name`.
2. Add the nodes from the table above using the templates in `docs/02-device-inventory.md`.
3. Cable them exactly as drawn. Check the port names on both ends.
4. Start all nodes. Wait for the switches to finish booting — `vios_l2` is slow.
5. Configure in order: end devices → switch → router. Outside in.
6. Run the verification table.

## Configuration

Start from `configs/golden-configs/`. Show only what changed for this lab.

```
R1(config)# interface GigabitEthernet0/0
R1(config-if)# ip address 10.10.10.1 255.255.255.0
R1(config-if)# no shutdown
```

For each block, add one line explaining *why* this command and not another.

## Verification

Every row must have real output pasted in. If a row fails, the lab is not done.

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip interface brief` | both interfaces up/up | |
| 2 | `ping 10.10.10.100` | 5/5 replies | |
| 3 | `show ip route` | connected + static entries | |

## Capture exercise

Capture on: `<which link>`
Save as: `wireshark/lab-NN-name-<what>.pcapng`
Filter: `<filter>`

Answer these from the capture, not from memory:

- Which MAC addresses are involved, and which device owns each one?
- Which addresses are rewritten at each hop, and which are not?
- What is the TTL doing, hop by hop?

## Break it / fix it

Inject the fault, then diagnose it without looking at this file.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | `shutdown` the LAN interface | | | |
| 2 | Wrong subnet mask | | | |

Record how long the diagnosis took. That number is the real progress metric.

## Self-check questions

Answer in writing. If you cannot, redo the lab before moving on.

1.
2.
3.

## What I learned

- 

## Cleanup

- [ ] Configs exported to `configs/lab-NN/`
- [ ] Capture saved and annotated
- [ ] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [ ] Committed with a specific message
