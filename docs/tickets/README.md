---
tags: [homelab, tickets, incident, noc]
status: not-started
---

# Ticket Labs

An incident-style lab gives you a **symptom** and nothing else. No configuration
steps, no topology hints, no list of commands. You find the cause.

This is the format that most closely resembles the NOC job, and it is the reason
the lab exists at all: configuring a network is a skill, but diagnosing one is the
job.

## Method

Follow [../04-troubleshooting-method.md](../04-troubleshooting-method.md) every
time. In short:

```
symptom → scope → hypothesis → cheapest check → root cause → fix → verify → prevention
```

## Creating a ticket

1. Build a **working** lab first (Lab 03 or Lab 06 are good bases).
2. Break exactly one thing, on purpose.
3. Confirm the symptom appears.
4. Create `tickets/T-NN-short-name.md` from the template below.
5. Only the symptom and the topology are written down. The cause stays hidden
   until you have found it.
6. Start a timer. How long the diagnosis takes is the actual score.

One fault at a time. Two faults at once teaches nothing except panic.

## Ticket template

```markdown
# T-NN — <symptom, in the words a user would use>

**Severity:** P1 / P2 / P3
**Reported:** <what the user says>
**Scope:** who is affected, and who is not
**Topology:** topology/lab-NN-name.gns3project
**Status:** open

## Symptom

- What is observed, with the exact command and its exact output.

## Impact

- What is broken, how many users, since when.

## Hypothesis

Written down **before** investigating. A hypothesis remembered rather than
written mutates to fit whatever the evidence turns out to be.

1.

## Checks

| # | Command | Output observed | Conclusion |
|---|---|---|---|
| 1 | | | |

## Root cause

One sentence.

## Fix

What was changed, and why that addresses the root cause rather than the symptom.

## Verification

The original failing test, repeated, with real output.

## Timeline

| Event | Time |
|---|---|
| Reported | |
| First check | |
| Cause identified | |
| Fixed | |
| Total time | |

## Prevention

- Monitoring alert that should have caught this:
- Config standard or baseline change:
- What would have made this obvious sooner:
```

## Severity guide

| Severity | Meaning | Response expectation |
|---|---|---|
| P1 | Service down for many users, or a whole site offline | Drop everything, work it immediately |
| P2 | Degraded service, or one department affected | Within 30 minutes |
| P3 | Single user, or cosmetic | Best effort, batched with similar work |

Work the widest impact first. A P1 with an obvious cause outranks a P3 puzzle,
every time.

## The questions that matter after every ticket

1. What was the actual root cause, as opposed to the symptom I first saw?
2. Which single command narrowed it down the most?
3. Which assumption was wrong, and how did I get it wrong?
4. What would have caught this before a user noticed?
5. If this happened at 02:00 on a shift with no senior engineer available, would
   I have fixed it in time?

Question 5 is the one that measures readiness.

## Related documents

- [../04-troubleshooting-method.md](../04-troubleshooting-method.md) — the method
  and the fault library
- [../09-wireshark-guide.md](../09-wireshark-guide.md) — evidence collection
- [../../labs/README.md](../../labs/README.md) — the ticket list
