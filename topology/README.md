---
tags: [homelab, topology, gns3]
status: active
---

# Topology — kaise organize karein

Har lab ka **apna folder**: `topology/lab-NN-naam/`

```
topology/lab-01-basic-lan/
├── README.md            # lab note (template se banao)
├── lab-01.gns3project   # GNS3 portable export
└── diagram.png          # optional screenshot (GNS3 "Export as image")
```

## GNS3 se export (portable)

`File → Export portable project` → `.gns3project` file `topology/lab-NN-naam/` me save karo.

**`.gns3project` commit karo, `project-files/` nahi** — wo `.gitignore` me hai (bade + lokal paths).

## Import (dusri machine / fresh start)

`File → Import portable project` → `.gns3project` select → bas.

## Lab note kaise likhein

1. `lab-00-template/README.md` copy karo → `topology/lab-NN-naam/README.md`
2. Frontmatter: `lab`, `level`, `status`, `date`
3. Objective, Topology, IP plan (link karo), Tasks, Verification, "Kya seekha" bharo
4. `README.md` ki status table update karo (`not-started` → `in-progress` → `done`)

## Configs export (lab ke baad)

GNS3 me node pe right-click → **Export config**, ya terminal me `show running-config` →
`configs/lab-NN/<device>.cfg` me paste karo.

Wahi config `configs/golden-configs/` me promote karo jab wo reusable ho.

## Naming rule

| Cheez | Format | Example |
|---|---|---|
| Folder | `lab-NN-naam` | `lab-03-vlan-trunk` |
| Project | `lab-NN-naam` (same!) | `lab-03-vlan-trunk` |
| Capture | `lab-NN-naam-<kya>.pcapng` | `lab-01-basic-lan-arp.pcapng` |
| Config | `<device>.cfg` | `R1.cfg`, `SW1.cfg` |
