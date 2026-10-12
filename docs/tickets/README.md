---
tags: [homelab, tickets, real-labs]
status: not-started
---

# Ticket-Style Labs (Real Labs)

> Yahan **config nahi milegi — problem milegi.** Yahi actual NOC job hai.
> Symptom padho → hypothesis → check karo → root cause → fix → prevention.

## Kaise banayein

1. Pehle lab me **jaan-boojh ke tod do** (config galat karo ya link down karo).
2. `ticket-template.md` copy karo → `tickets/T-01-internet-down.md`.
3. Symptom sirf likho. Solution **collapse** me ya alag section me (pehle khud solve karo).
4. Timer laga — real NOC me time matter karta hai.

## Ticket template

```markdown
# T-01 — <symptom, user ki bhasha me>

**Severity:** P1 / P2 / P3
**Reported:** <user kya bol raha hai>
**Topology:** topology/lab-NN-*/ 
**Status:** open

## Symptom
- 

## Impact
- Kya kaam nahi kar raha, kitne log affected

## Hypothesis (pehle socho)
1. 

## Checks (command → observation)
| # | Command | Observation |
|---|---|---|
| 1 | | |

## Root cause
- 

## Fix
```

## Changelog / RCA

```markdown
## Prevention
- Monitoring add karo:
- Config standard update:
```

## Severity guide (NOC style)

| Sev | Matlab | Response |
|---|---|---|
| P1 | Network down / multiple users | turant, sabse pehle |
| P2 | Degraded / ek site / ek department | 30 min |
| P3 | Single user / cosmetic | best-effort |
