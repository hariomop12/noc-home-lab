---
tags: [homelab, configs]
status: active
---

# Configs

| Folder | Kya hai | Kab use karein |
|---|---|---|
| `golden-configs/` | Reusable baselines (tested, working) | Har naye lab ki starting point |
| `lab-NN/` | Us lab ki final configs | Lab ke baad, proof ke liye |

## Rule

1. Lab start karte waqt `golden-configs/` se copy karo — zero se nahi likhna.
2. Lab me jo better hua (naya ACL, hardening, tuning) → wapas `golden-configs/` me promote karo.
3. Golden config **hamesha working** ho. Tuta hua config golden me nahi jaata.

## Kaise export karein

GNS3 → node pe right-click → **Export config** → `configs/lab-NN/<device>.cfg`

Ya terminal se:
```
R1# show running-config
```
Copy → `configs/lab-NN/R1.cfg` me paste.

## Password convention (lab only)

| Cheez | Value |
|---|---|
| enable secret | `Cisco123` |
| local user | `admin` / `Cisco123` |
| domain | `lab.local` |

⚠️ Ye sirf lab ke liye hai. Asli network me `secret` + AAA use hota hai.
