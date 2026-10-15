---
lab: 05
level: micro
status: done
tags: [homelab, lab, ssh, ntp, syslog, snmp, monitoring, docker]
---

# Lab 05 — Network Management

## Metadata

| Field | Value |
|---|---|
| Level | micro |
| Estimated time | 90 min |
| Prerequisites | Lab 02 (gateway), Lab 04 (Docker services) |
| Skills practised | SSH hardening, NTP, central syslog, SNMP polling, reading telemetry from a capture |
| Related docs | [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md), [../../docs/07-monitoring-basics.md](../../docs/07-monitoring-basics.md), [../../docker/README.md](../../docker/README.md) |

## Objective

After this lab I can securely manage a router instead of using Telnet, keep its
clock correct, ship its logs to a central collector, and poll it for health over
SNMP — and I can **prove each one from a packet capture**, including the part
where SNMP gives the community string away in clear text.

## Theory

- **SSH** replaces Telnet. Telnet sends the password in clear text; SSH sets up an
  encrypted channel first and then authenticates. The only thing readable on the
  wire is the version banner (e.g. `SSH-2.0-Cisco-1.25`) during key exchange.
- **NTP** keeps every device's clock in agreement — which time-stamped logs and
  monitoring depend on. A client polls a server; the server is one stratum closer
  to a real time source. Here the router (`stratum 11`) syncs to `SRV-NTP`
  (`stratum 10`, chrony serving its own clock).
- **Syslog** is fire-and-forget: the device pushes text events to a collector over
  **UDP 514**, unencrypted. The collector writes one file per source device.
- **SNMP** is how a monitoring system asks a device questions (interface state,
  CPU, counters). SNMPv2c authenticates with a **community string** — which
  travels in clear text. SNMPv3 with `authPriv` fixes that; that is why v3 is the
  production choice.

## Topology

```
PC1 ── SW1 Gi0/1 (access VLAN 10)
SW1 Gi0/2 ── R1 Gi0/0 (access VLAN 10)
R1 Gi0/1 ── SW2 (management segment, 10.100.0.0/24)
              ├── SRV-SYSLOG  10.100.0.11   (syslog:lab, rsyslog)
              ├── SRV-NTP     10.100.0.13   (ntp:lab, chrony)
              └── CLIENT      10.100.0.50   (noc-tools:lab — ssh/nmap/snmpwalk)
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | vios | Gi0/0 | 10.10.10.1/24 | VLAN 10 gateway |
| R1 | vios | Gi0/1 | 10.100.0.1/24 | management segment gateway |
| R1 | vios | Lo0 | 10.255.0.1/32 | stable router identity |
| SW1 | vios_l2 | Gi0/1 | — | access port to PC1, VLAN 10 |
| SW1 | vios_l2 | Gi0/2 | — | uplink to R1 Gi0/0, VLAN 10 |
| SW2 | Ethernet switch | — | — | management segment (no config) |
| PC1 | VPCS | eth0 | 10.10.10.100/24 | management client |
| SRV-SYSLOG | `syslog:lab` | eth0 | 10.100.0.11/24 | rsyslog collector |
| SRV-NTP | `ntp:lab` | eth0 | 10.100.0.13/24 | chrony time source |
| CLIENT | `noc-tools:lab` | eth0 | 10.100.0.50/24 | test tools |

Addressing from [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md).

This is deliberately a **flat, simple** topology — the point of the lab is the
management plane, not the data plane. VLAN 10 is carried as plain access ports
(no trunk), so nothing distracts from the services being studied.

## Build steps

### 0. Build the images (once)

```bash
cd docker
./build.sh          # builds ntp:lab, syslog:lab, noc-tools:lab, ...
```

### 1. Add the container templates in GNS3

`Preferences → Docker containers → New`, for each image. Console type **telnet**:

| Template name | Image | `LAB_IP` | `LAB_GW` |
|---|---|---|---|
| `SRV-NTP` | `ntp:lab` | `10.100.0.13/24` | `10.100.0.1` |
| `SRV-SYSLOG` | `syslog:lab` | `10.100.0.11/24` | `10.100.0.1` |
| `CLIENT` | `noc-tools:lab` | `10.100.0.50/24` | `10.100.0.1` |

**Gotcha that cost the most time — the container console needs a shell.**
These images start a *foreground service* (`chronyd`, `rsyslogd`) as their CMD, so
the GNS3 telnet console shows no prompt. Set a **Start command** in the template
so the service starts and *then* a shell is handed over. GNS3 parses this line
itself, so use **single quotes** — double quotes fail with
`Invalid start command ... No closing quotation`:

| Template | Start command |
|---|---|
| `SRV-NTP` | `sh -c 'chronyd -d -x -u root -f /etc/chrony/chrony.conf & exec sh'` |
| `SRV-SYSLOG` | `sh -c 'rsyslogd -n & exec sh'` |
| `CLIENT` | `/bin/sh` |

**Gotcha #2 — right image, right node.** A `syslog` node accidentally built from
the `ntp:lab` image took the *same* `10.100.0.13` as `SRV-NTP`, producing a
duplicate-IP conflict. If a service "starts" but the router still cannot reach
it, check you are running the image you think you are.

### 2. Build and cable the topology

1. Add: 1× `vios` router, 1× `vios_l2` switch, 1× **Ethernet switch** (built-in),
   1× VPCS, and the three containers from step 1.
2. Name them `R1`, `SW1`, `SW2`, `PC1`, `SRV-NTP`, `SRV-SYSLOG`, `CLIENT`.
3. Cable exactly as drawn. Start everything; `vios_l2` boots slowly.

### 3. Configure

Start from `configs/golden-configs/`, then apply the changes below.

**R1**

```
ip domain name lab.local
ip ssh version 2
username admin privilege 15 secret Cisco123
enable secret Cisco123
!
interface GigabitEthernet0/0
 description LAN-HQ
 ip address 10.10.10.1 255.255.255.0
 no shutdown
!
interface GigabitEthernet0/1
 description SERVERS-LAN
 ip address 10.100.0.1 255.255.255.0
 no shutdown
!
interface Loopback0
 ip address 10.255.0.1 255.255.255.255
!
ntp server 10.100.0.13
logging host 10.100.0.11
logging trap informational
snmp-server community labRO RO
snmp-server community labRW RW
snmp-server location HOME-LAB
snmp-server contact hariom@lab.local
!
line vty 0 4
 login local
 transport input ssh
```

Why each block: `ip domain name` is required before an RSA key can be generated
for SSH; `ip ssh version 2` bans the weak v1; `login local` + a `username` means
the vty has a real account; `transport input ssh` is what actually closes
Telnet; the **loopback** gives NTP/syslog/SNMP a source address that never goes
down.

**SW1**

```
vlan 10
interface GigabitEthernet0/1
 switchport mode access
 switchport access vlan 10
interface GigabitEthernet0/2
 switchport mode access
 switchport access vlan 10
```

**SW2** — nothing to configure.

**PC1** (VPCS console)

```
ip 10.10.10.100/24 10.10.10.1
```

## Verification

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip interface brief` (R1) | Gi0/0, Gi0/1, Lo0 all up/up | ✅ `10.10.10.1`, `10.100.0.1`, `10.255.0.1` all **up/up** (Gi0/2-3 admin down) |
| 2 | `show logging` (R1) | trap level + collector | ✅ `Trap logging: level informational` · `Logging to 10.100.0.11 (udp port 514)` |
| 3 | `show run \| include snmp-server` (R1) | two communities | ✅ `labRO RO`, `labRW RW` |
| 4 | `nmap -p 22,23 10.100.0.1` (CLIENT) | 22 open, **23 closed** | ✅ `22/tcp open ssh`, `23/tcp closed telnet` |
| 5 | `nc 10.100.0.1 22` (CLIENT) | SSH banner, no password prompt over telnet | ✅ banner `SSH-2.0-Cisco-1.25` |
| 6 | `snmpget -v2c -c labRO 10.100.0.1 sysName.0` (CLIENT) | sysName | ✅ `STRING: "R1.lab.local"` |
| 7 | `snmpget -v2c -c WRONG 10.100.0.1 sysName.0` (CLIENT) | no reply | ✅ timeout (no response to a bad community) |
| 8 | `snmpwalk -v2c -c labRO 10.100.0.1 ifDescr` (CLIENT) | interface list | ✅ Gi0/0..Gi0/3, Null0, Loopback0 |
| 9 | `tail /var/log/remote/10.100.0.1.log` (SRV-SYSLOG) | R1's log lines | ✅ one file per source **IP**, messages arriving |
| 10 | `show ntp associations` (R1) | `*` selected peer | ✅ `*~10.100.0.13 st 10`, reach climbing |
| 11 | `show ntp status` (R1) | synchronized, stratum 11 | ✅ `Clock is synchronized, stratum 11, reference is 10.100.0.13` |

Real output (selected):

```
R1# show ip interface brief
Interface                  IP-Address      OK? Method Status                Protocol
GigabitEthernet0/0         10.10.10.1      YES manual up                    up
GigabitEthernet0/1         10.100.0.1      YES manual up                    up
GigabitEthernet0/2         unassigned      YES unset  administratively down down
GigabitEthernet0/3         unassigned      YES unset  administratively down down
Loopback0                  10.255.0.1      YES manual up                    up

R1# show logging
    Trap logging: level informational, 53 message lines logged
        Logging to 10.100.0.11  (udp port 514, audit disabled,

R1# show ntp status
Clock is synchronized, stratum 11, reference is 10.100.0.13
... loopfilter state is 'CTRL' (Normal Controlled Loop), drift is -0.000148524 s/s

R1# show ntp associations
  address         ref clock       st   when   poll reach  delay  offset   disp
*~10.100.0.13     127.127.1.1     10     31     64     3  1.439  -0.099 63.276

SRV-SYSLOG / # tail -3 /var/log/remote/10.100.0.1.log
2026-10-15T06:47:31 10.100.0.1 51: *Oct 15 06:47:30.742: %SYS-5-CONFIG_I: Configured from console by admin on console
2026-10-15T06:51:53 10.100.0.1 52: *Oct 15 06:51:52.890: %GRUB-5-CONFIG_WRITING: GRUB configuration is being updated on disk...
2026-10-15T06:51:53 10.100.0.1 53: *Oct 15 06:51:53.622: %GRUB-5-CONFIG_WRITTEN: GRUB configuration was written to disk successfully.
```

Two things this proves that are easy to miss:

- The collector file is named **after the source IP** (`10.100.0.1.log`), not the
  hostname. At scale you map IP → hostname yourself; do not assume the log file
  is named after the device.
- `snmpget` returning **`R1.lab.local`** rather than `R1` is the effect of
  `ip domain name lab.local` — sysName is the FQDN.

### Diagnosis worth remembering: NTP stuck at "unsynchronized"

Symptom: `show ntp associations` showed the server but the clock would not lock,
and `ping 10.100.0.13` from R1 failed. Root cause was **not** NTP: R1 held a
**stale ARP entry** mapping `10.100.0.13` to the *old* container's MAC address, so
its NTP requests were sent to a dead MAC. `clear ip arp 10.100.0.13` restored
`ping` (5/5) and NTP converged moments later. Lesson: check layer 2 reachability
before blaming the service.

## Capture exercise

| File | Link | Filter | What it proves |
|---|---|---|---|
| `wireshark/lab-05-network-management-mgmt.pcapng` | R1 Gi0/1 ↔ SW2 | `snmp \|\| ntp \|\| syslog \|\| ssh` | all four management services on one wire — and how exposed each one is |

60 seconds, 743 frames. Protocol breakdown:

| Protocol | Frames | What it shows |
|---|---|---|
| SNMP | 684 | community **`labRO` in clear text**, version field `1` (= v2c), CLIENT `.50` → R1 `.1`, whole interface table walked with GETNEXT |
| NTP | 2 | F739 R1 `.1` → SRV-NTP `.13`, **mode 3** (client); F740 reply **mode 4** (server), **stratum 10** |
| Syslog | 2 | R1 `.1` → SRV-SYSLOG `.11`, clear-text UDP 514 messages |
| SSH | 1 | R1 → CLIENT banner `SSH-2.0-Cisco-1.25` — the only clear-text frame; everything after it is encrypted |
| Overhead | — | CDP 3, STP 31, DTP 2, ARP 2 |

Answered from the capture:

- [x] **SNMP community is readable** — `tshark -Y snmp -T fields -e snmp.community`
      returns `labRO`. That is the whole argument for SNMPv3 `authPriv`.
- [x] **Version field value** — `snmp.version == 1` means **v2c** (0 = v1,
      3 = v3).
- [x] **NTP direction and stratum** — the request is mode 3 with R1's own stratum
      (11); the reply is mode 4 with the server's stratum (10). A client is always
      `server_stratum + 1`.
- [x] **Syslog is unencrypted UDP 514** — anyone on the management segment can
      read every device's log line.
- [x] **SSH is not readable** — only the banner appears; the session is encrypted
      after key exchange.
- [x] **Discovery protocols count too** — CDP/STP/DTP frames on the link are part
      of the same exposure, which is why they get disabled at the edge.

## Break it / fix it

Four faults were injected, one at a time, and fixed without looking at the guide.
(All four ran to completion.)

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | `no snmp-server community labRO ro` + `snmp-server community labRX ro` | `snmpwalk -c labRO` times out | community mismatch — the monitor goes blind on the wrong string | re-add `snmp-server community labRO ro` |
| 2 | `no logging host 10.100.0.11` | collector file stops growing | the device is no longer sending logs to any collector | re-add `logging host 10.100.0.11` |
| 3 | `no ntp server 10.100.0.13` | soon `show ntp status` is unsynchronized | the time source was removed | `ntp server 10.100.0.13` and wait for the next polls |
| 4 | `no username admin privilege 15 secret Cisco123` | SSH login fails | `line vty` uses `login local`, but the account is gone | re-create the `username` |

Diagnose with: `show run | include snmp-server` · `show logging` ·
`show ntp associations` · `show run | include username`. Each fault maps to one
monitoring blind spot, which is exactly what a NOC alert would catch.

## Self-check questions

1. Telnet and SSH both log you in — what specifically travels differently on the
   wire, and how does the capture show it?
2. `show ntp status` says `stratum 11` while the server says `10`. Why?
3. Why is `logging trap informational` (or the default) enough for a NOC, and what
   would `logging trap warnings` cost you?
4. SNMPv2c works fine here. Give one concrete reason to move to v3 anyway.

## What I learned

- The container console needs a shell: a service image whose CMD is a foreground
  daemon (`chronyd`, `rsyslogd`) leaves the GNS3 telnet console with no prompt.
  A Start command that launches the daemon *then* `exec sh` fixes it.
- GNS3 parses the Start command itself — **single quotes only**; double quotes
  fail with `No closing quotation`.
- A wrong-image node silently steals the same IP. "Service up but unreachable" is
  usually a layer 1/2 or identity problem, not a service problem.
- **Stale ARP can look exactly like a broken NTP server.** `clear ip arp` proved
  L2 was the real fault; the service was never down.
- SNMPv2c community strings, syslog, and the SSH banner are visible in clear
  text; SSH payload is not. One capture tells you the security posture of all
  four services at once.
- The central collector names logs by **source IP**, and sysName is the **FQDN**
  because `ip domain name` is set — small details that shape how a real NOC
  correlates logs and polls.
- `transport input ssh` is the line that actually disables Telnet — version and
  key setup alone are not enough.

## Cleanup

- [x] Configs exported to `configs/lab-05/` (R1.cfg, SW1.cfg)
- [x] Capture saved in `wireshark/lab-05-network-management-mgmt.pcapng`
- [x] Status flipped in `labs/README.md`, main `README.md`, skill matrix, roadmap
- [ ] GNS3 project closed (not suspended)
- [x] Committed with a specific message
