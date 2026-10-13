---
tags: [homelab, troubleshooting, method, noc]
status: active
---

# 04 — Troubleshooting Method

The difference between a technician and an engineer is not knowledge of
protocols. It is having a method that produces the answer when the knowledge runs
out.

This document is the method. Use it for every ticket lab, and for every lab that
breaks unexpectedly — which, in a lab, is most of them.

## The rule that matters most

**Change one thing at a time, and write down what you changed.**

Almost every "unfixable" problem in a lab is the result of three changes made at
once, two of which were wrong. A change log turns an impossible problem into a
bisection.

Before any change:

1. Note the exact symptom, in the words the user would use.
2. Note what you believe is happening, and why.
3. Make one change.
4. Test the same way as before (same command, same source, same target).
5. Record the result.

If step 5 is skipped, the diagnosis is a guess that happened to work.

## Four approaches

Pick one deliberately. Mixing them mid-investigation is how time disappears.

| Approach | Start at | Best for | Risk |
|---|---|---|---|
| **Bottom-up** | Layer 1, walk up | No connectivity at all, physical/link failures | Slow on a large network |
| **Top-down** | Application, walk down | Single application failing, users report a specific service | Can waste time if the problem is physical |
| **Divide and conquer** | Some layer in the middle, then move to whichever side fails | When you already suspect a layer | Need a hypothesis to start |
| **Follow the path** | Source, hop by hop toward the destination | "Works from A, fails from B", asymmetric problems | Requires access to intermediate devices |

The usual default in this lab is **bottom-up**, because virtual labs break at
Layer 1 constantly: a node that never booted, a cable on the wrong port, an
interface left administratively down.

## Layer-by-layer checks

Run down this table when you have no idea where the fault is. Stop at the first
layer that fails — everything above it is a consequence, not a cause.

| Layer | Question | On the device | Expected |
|---|---|---|---|
| 1 | Is the interface up? Is there a link? | `show ip interface brief` | status `up`, protocol `up` |
| 1 | Are there physical errors? | `show interfaces Gi0/0` | CRC, input errors near zero |
| 2 | Is the frame reaching the right port? | `show mac address-table` | Source MAC learned on the expected port |
| 2 | Is the VLAN correct on that port? | `show interfaces switchport` | Correct access VLAN / trunk allowed list |
| 2 | Is the trunk passing the VLAN? | `show interfaces trunk` | VLAN present in the allowed and forwarding list |
| 3 | Is the address inside the subnet? | `show ip interface brief` | Address and mask consistent |
| 3 | Is there a route to the destination? | `show ip route <dest>` | A matching route, correct next hop |
| 3 | Is the gateway the right one? | Clients: `ipconfig` / `show ip` | Gateway inside the local subnet |
| 4 | Are ARP entries resolving? | `show arp` on the router | Gateway MAC for reached hosts |
| 4 | Is a firewall or ACL dropping it? | `show access-lists`, `show ip interface` | No unexpected deny counter incrementing |
| 4 | Is NAT translating? | `show ip nat translations` | Entry present for the flow |
| 7 | Does the service answer? | `telnet <ip> <port>`, container logs | Port open and responding |

Two habits make this table fast:

- **Compare against a working case.** Ping from a working PC to the same target.
  Whatever is different is closer to the cause than anything else you will find.
- **Read outputs fully.** `show ip interface brief` showing `up/down` is not the
  same as `down/down`, and the difference decides the next command.

## Symptom to cause: the fault library

The fastest path in a NOC is pattern recognition. This is the shortlist for
lab-scale networks.

| Symptom | Most likely causes, in order | First command |
|---|---|---|
| No connectivity at all | Interface shut; cable on wrong port; node not booted; wrong VLAN | `show ip interface brief` |
| Local ping works, remote fails | Missing route; wrong gateway; wrong mask | `show ip route`, `ipconfig` |
| Works for some hosts, not others | Wrong mask; duplicate IP; ACL; VLAN mismatch | Compare `ipconfig` of both hosts |
| Intermittent connectivity | Duplex mismatch; STP reconvergence; ARP timeout; flapping link | `show interfaces`, `show spanning-tree` |
| Slow, but working | Duplex mismatch; broadcast storm; overloaded link | `show interfaces`, `show processes cpu sorted` |
| One VLAN cannot reach another | Trunk not allowing the VLAN; missing SVI; missing router-on-a-stick subinterface | `show interfaces trunk` |
| Cannot get a DHCP address | Pool exhausted; relay missing; server unreachable; wrong VLAN | `show ip dhcp binding`, `show run \| section dhcp` |
| Name resolution fails, ping by IP works | Wrong DNS server handed out; DNS container down | Test with `nslookup` against the server directly |
| Internet fails, internal works | Missing default route; NAT misconfigured; ACL on the WAN interface | `show ip route`, `show ip nat statistics` |
| Duplicate address warnings | Static address inside the DHCP pool; two devices with the same address | `show ip dhcp conflict` |
| High CPU on a switch | Broadcast storm, STP loop, port security violation storm | `show processes cpu sorted`, `show spanning-tree` |

## Ticket discipline

Every ticket lab follows the same shape. Format:
[tickets/README.md](tickets/README.md).

1. **Restate the symptom** in one sentence. If you cannot, you do not understand
   the report yet.
2. **Set the scope.** One host, one VLAN, one site, or everything? Scope narrows
   the search space faster than any command.
3. **Form one hypothesis** and write it down. Written hypotheses are testable;
   remembered ones mutate to fit the evidence.
4. **Test the cheapest check first.** `show` output costs nothing. Reloading a
   device costs everything.
5. **Find the root cause**, not the symptom. "The interface was down" is a
   symptom of "someone shut it down while testing two days ago".
6. **Fix it, then verify** with the original failing test.
7. **Write the RCA**: what happened, why, how it was fixed, and what would have
   caught it earlier.

## Severity and urgency

Borrowed from how a real NOC triages. Apply it in ticket labs so the habit forms.

| Severity | Meaning | Response expectation |
|---|---|---|
| P1 | Service down for many users, or a site offline | Drop everything, work it now |
| P2 | Degraded service, or one department affected | Within 30 minutes |
| P3 | Single user, or cosmetic | Best effort, batched |

Rule of thumb: fix the widest impact first, even if it is the least interesting
problem. A P1 with an obvious cause beats a P3 puzzle every time.

## Debugging safely

`debug` output can take a router to its knees, and on a console it can scroll the
device into unresponsiveness.

- Always know the way out before entering: `undebug all`, or `Ctrl+C`.
- Prefer `show` over `debug`. Exhaust every `show` first.
- Use an ACL or a specific condition with debug (`debug ip icmp` with an ACL is
  better than unfiltered).
- On a remote session, `terminal no monitor` before leaving, or the next login
  drowns in output.
- `debug` is a temporary tool. If it stays on, it is a latent outage.

## What to record, always

A diagnosis that is not written down will be repeated. For each ticket, capture:

- Exact symptom and how it was reported
- Scope: what worked, what did not, from where
- Every command run and its output
- The hypothesis, and whether it survived
- Root cause, in one sentence
- Fix applied
- Verification output after the fix
- Time from report to resolution
- The monitoring alert that should have fired first

That last line is what turns a lab exercise into NOC experience.
