---
tags: [homelab, monitoring, snmp, syslog, zabbix]
status: active
---

# Monitoring Basics

Purpose: the monitoring knowledge a NOC engineer must have before touching the
Zabbix/syslog/NTP stack in this lab — what to collect, why, and how to read it.

Monitoring is not the same thing as troubleshooting. Troubleshooting fixes a
problem that already exists. Monitoring makes sure you *know* a problem exists
before a user tells you.

---

## 1. Why a NOC engineer cares

| Activity | Question it answers | When it happens |
|---|---|---|
| Monitoring | "Is everything healthy right now?" | Continuously, 24x7 |
| Alerting | "Should a human look at this?" | When a threshold breaks |
| Triage | "How bad is it, and who does it affect?" | After an alert fires |
| Troubleshooting | "Why is this broken?" | During an incident |
| Escalation | "Who owns this now?" | When it is beyond your scope |

The detection loop is: **detect → alert → triage → escalate → resolve →
verify → document.**

- **Detect** — the tool notices a state change (interface down, CPU spike,
  packet loss).
- **Alert** — a rule turns that state into a notification.
- **Triage** — you decide severity and impact (one user, one site, or everyone).
- **Escalate** — hand off to the right team with the evidence you gathered.
- **Resolve + verify** — fix and confirm the alert clears.
- **Document** — write the timeline; this is how MTTR improves next time.

**MTTR (Mean Time To Repair/Resolve)** is the average time from incident start
(or detection) to service restored. A NOC improves MTTR mostly by *detecting
faster* and *diagnosing faster* — not only by fixing faster. Related terms:

- **MTTD (Mean Time To Detect)** — how long until the problem is noticed.
- **MTBF (Mean Time Between Failures)** — reliability of a component.

**Proactive** means you act on a trend before it becomes an outage: disk filling
up, CPU climbing each day, errors creeping up on a link, a DHCP pool shrinking.
**Reactive** means you act only after the user complains. A NOC job is judged
on how much is proactive — which is exactly what polling, logging, and
thresholds buy you.

⚠️ Monitoring is only as good as the data feeding it. Wrong time (no NTP),
missing devices, or noisy thresholds make the whole stack untrustworthy.

---

## 2. SNMP

**SNMP (Simple Network Management Protocol)** is the standard way to read
operational data and state from network devices. It runs over **UDP**: port
**161** for polling (manager → agent) and port **162** for notifications
(agent → manager).

### Architecture

| Component | Role |
|---|---|
| Manager (NMS) | The poller — Zabbix server asks the questions. |
| Agent | Runs on the device (the IOS SNMP engine) and answers. |
| MIB | Management Information Base — the database/schema of what the agent exposes. |
| OID | Object Identifier — the numeric address of one object inside the MIB tree. |
| SMI | Structure of Management Information — the rules (ASN.1 based) that define data types and how the MIB is organised. |

The MIB is a tree. The root is `iso(1)`, and the common managed objects live
under `mib-2` (`1.3.6.1.2.1`). An **OID** is a path down that tree, e.g.
`1.3.6.1.2.1.1.5` (`sysName`). You usually reference objects by their
descriptive name and let the tool resolve the number.

### Versions

| Version | Auth | Encryption | Counters | Notes |
|---|---|---|---|---|
| v1 | Community string (cleartext) | None | 32-bit | Oldest; limited, avoid. |
| v2c | Community string (cleartext) | None | 32-bit + 64-bit | Most common in labs; adds `GetBulk`. |
| v3 | User-based (USM) with username + auth | Yes (privacy) | 64-bit | Real security: authentication and encryption. |

**Why v3 matters:** v1/v2c community strings are sent in cleartext on every
request — anyone who can capture the traffic or guess the string has access.
v3 adds **USM (User-based Security Model)** with three security levels:

- `noAuthNoPriv` — username only.
- `authNoPriv` — authenticated (MD5/SHA).
- `authPriv` — authenticated and encrypted (DES/AES).

In a production NOC, read access is usually v3 `authPriv`. In this lab, v2c is
used for simplicity and because all traffic stays inside the GNS3 topology.

### Communities: read-only vs read-write

- `snmp-server community labRO ro` — **read-only**: allows `GET`/`GETNEXT`
  (read data). This is what monitoring should use.
- `snmp-server community labRW rw` — **read-write**: also allows `SET`
  (change device configuration/state). Powerful and dangerous.

⚠️ Rule of thumb: **monitoring uses RO.** RW communities should be rare,
restricted by ACL, and never used by an automated poller.

### Polling model

The manager **polls** devices on an interval (`SNMP` items in Zabbix typically
every 1–5 minutes) and stores the returned values. Polling gives you regular,
predictable samples and control over load. The trade-off is that a state change
between two polls can be missed — poll interval decides your detection
granularity.

### Traps vs informs

| | Trap | Inform |
|---|---|---|
| Direction | Agent → manager | Agent → manager |
| Reliability | Fire-and-forget | Acknowledged; retransmitted until a response |
| Port | UDP 162 | UDP 162 |
| Use | Event push (link down, config change) | When delivery must be confirmed |

Traps/informs are **push**: the device tells the manager something just
happened, instead of waiting to be asked. On IOS, the destination is set with
`snmp-server host`, and relevant trap types must be enabled for the device to
actually emit them:

```
snmp-server host 10.100.0.21 version 2c labRO
snmp-server enable traps
```

### Walk / get / bulk

| Operation | What it does |
|---|---|
| `GET` | Read one specific OID's value. |
| `GETNEXT` | Read the *next* OID in the MIB tree (used to walk a subtree). |
| `GETBULK` | v2c/v3 bulk retrieval — fetch many rows per request instead of one-by-one. |
| walk | Repeatedly `GETNEXT` from a starting OID to enumerate a whole table/subtree (e.g. every interface). |
| bulkwalk | Walk implemented with `GETBULK`; far more efficient. |

Walking an OID tree conceptually: you pick a starting OID (say the interface
table) and repeatedly ask "give me the next object". This enumerates every
interface and every counter under it. In practice you let a tool do the loop:

```
snmpwalk  -v2c -c labRO 10.255.0.1 1.3.6.1.2.1.2.2.1
snmpbulkwalk -v2c -c labRO 10.255.0.1 1.3.6.1.2.1.2.2.1
snmpget   -v2c -c labRO 10.255.0.1 1.3.6.1.2.1.1.5.0
```

### Security notes

- Prefer v3 `authPriv`; treat v2c community strings as passwords (they are).
- Bind SNMP to management addresses and restrict with ACLs.
- Use a **dedicated RO** community or v3 user for monitoring; never reuse the RW
  one.
- SNMP is not encrypted by default — do not expose it to untrusted networks.

---

## 3. Syslog

**Syslog** is the standard event-logging protocol. Devices push log messages to
a central collector, usually over **UDP 514** (TCP/TLS variants exist).

### Severity levels (lower number = more severe)

| Value | Name | Meaning | Typical use |
|---|---|---|---|
| 0 | Emergency (emerg) | System is unusable | total outage, panic |
| 1 | Alert | Immediate action required | power/hardware critical |
| 2 | Critical | Critical condition | link/process critically failed |
| 3 | Error | Error condition | interface errors, failed auth |
| 4 | Warning | Warning condition | high CPU, config warnings |
| 5 | Notice | Normal but significant | interface up/down, reload, login |
| 6 | Informational | Informational | routine operational events |
| 7 | Debug | Debugging | verbose diagnostics (noisy) |

### Facilities

A **facility** is a code identifying the *source or subsystem* of a message
(e.g. kernel, mail, auth, cron, and the **local0–local7** set). It lets the
collector route and file messages by origin. Cisco IOS maps its messages into a
configurable facility (`logging facility local6`, etc.) so network logs can be
segregated from Linux system logs on the same collector.

### Message flow: router → collector

1. The device generates a message (an event, a debug, a state change).
2. `logging host 10.100.0.11` defines the destination collector.
3. `logging trap informational` sets the **maximum severity number sent** —
   values 0 through 6 are forwarded, 7 (debug) is not.
4. The collector (rsyslog) receives it, timestamps it, appends it to a file.

```
logging host 10.100.0.11
logging trap informational
logging buffered 16384
service timestamps log datetime msec localtime
```

- `logging trap <level>` — which severities leave the device.
- `logging buffered <bytes>` — size of the local in-memory log buffer (read it
  with `show logging`; survives until reload).
- `service timestamps` — makes every message carry a timestamp; without it you
  cannot correlate events across devices.

### Why central logging matters

- One place to correlate events from routers, switches, and servers.
- Logs survive a device reload (local buffers do not).
- Enables search and timeline reconstruction during an incident.
- Supports compliance and audit requirements.

### What to log vs not to log

- **Log:** interface up/down, routing adjacency changes, authentication
  successes/failures, reloads, config changes, hardware errors, DHCP exhaustion.
- **Do not log at high volume:** routine per-packet `debug` output. Debugging
  is CPU-expensive and floods the collector; enable it narrowly and turn it off.

### Retention and rotation

Collectors must be told how long to keep data and when to rotate. On Linux,
`logrotate` handles rotation; systemd's journal is bounded with settings like
`SystemMaxUse`. A common mistake is an unbounded syslog file quietly filling the
disk and taking down the server — the monitoring server itself is a monitored
host.

### Useful Linux side

```bash
# rsyslog receives remote logs; check its config
sudo cat /etc/rsyslog.conf
ls /etc/rsyslog.d/
# A minimal receive rule (imudp) listens on UDP 514:
#   module(load="imudp")
#   input(type="imudp" port="514")

# Look for this lab's router messages (match on hostname)
grep -i 'r1' /var/log/messages

# systemd journal (local logs)
journalctl -xe
journalctl -u rsyslog --since "1 hour ago"
```

⚠️ If the **collector clock is wrong**, all the timestamps it stamps onto
received messages are wrong too. NTP (next section) is not optional.

---

## 4. NTP

**NTP (Network Time Protocol)** synchronises clocks across devices, over
**UDP 123**. Accurate time is mandatory the moment you try to correlate logs
from more than one device — a log timeline is meaningless if each box runs a
different clock.

### Stratum

Stratum describes *distance from a reference clock*:

| Stratum | What it is |
|---|---|
| 0 | The reference clock itself (atomic clock, GPS receiver). |
| 1 | A server directly attached to a stratum-0 source. |
| 2 | A server synchronised to a stratum-1 server. |
| 3, 4, … | Each level further from the reference. |
| 16 | Unsynchronised / not usable. |

Lower stratum is *closer* to the reference, not necessarily "better" for you.
Max usable is 15.

### Configure

```
ntp server 10.100.0.13
```

Point every device at the lab's NTP server. Optionally set a local timezone for
display (NTP itself works in UTC internally):

```
clock timezone IST 5 30
```

### Avoid stratum loops

A loop happens when device A syncs to B and B (directly or indirectly) syncs
back to A. NTP is designed to detect and refuse a source that would create a
loop, but the *design* is on you: keep a clear hierarchy. Routers and switches
should be **clients of the NTP servers**, never servers that point back at each
other. Do not point the NTP server at a device that points at the NTP server.

### Reading the status

```
show ntp status
show ntp associations
show clock detail
```

- `show ntp status` — is the clock synchronised, at what stratum, and to which
  reference. If it says "Clock is not synchronized", nothing on this device is a
  trustworthy time source yet. Also shows clock offset and drift (nominal vs
  actual frequency).
- `show ntp associations` — the candidate servers. A leading `*` marks the
  current **system peer** (the one in use), `+` a usable candidate, `-` unusable.
  Key columns:
  - `st` — the peer's stratum.
  - `reach` — an 8-bit shift register of the last 8 polls; `377` (octal) means
    all 8 polls answered.
  - `offset` — how far this device's clock is from the peer.
  - `delay` / `jitter` — round-trip delay and variance; lower and stable is good.
- `show clock detail` — local time and its source.

### Drift

**Drift** is the difference between a clock's *actual* rate and the ideal rate.
Hardware oscillators are never perfect, so a device slowly gains or loses time
until NTP corrects it. NTP learns the drift rate and corrects continuously, so
short NTP outages cause small offsets rather than a runaway clock.

---

## 5. NetFlow / IPFIX / sFlow

Flow telemetry records **who talked to whom** — the detail SNMP cannot give you.

| | Provides |
|---|---|
| SNMP | Counters and state: bytes on an interface, up/down, CPU. |
| Flow telemetry | Per-conversation detail: source/dest IP, ports, protocol, ToS, byte/packet counts, timestamps, next hop. |

| Technology | Notes |
|---|---|
| NetFlow v5 | Fixed-format IPv4 flows; older. |
| NetFlow v9 | Template-based; extensible (IPv6, MPLS, etc.). |
| IPFIX | The IETF standard derived from NetFlow v9. |
| sFlow | Sampling-based, layer-2 capable, vendor-neutral. |

**Exporter / collector model:** the router or switch is the **exporter** — it
builds flow records and exports them to a **collector** (a flow analyser).
The collector aggregates and displays them.

**Top-talkers use case:** during a congestion incident you ask "what is filling
this link?" Flow data answers it: one host saturating the uplink, a backup job
running at the wrong hour, a broadcast/multicast source, or a possible attack.

Where it fits in a NOC: SNMP tells you *the link is full*; flow tells you *what
filled it*. That shortens triage from "investigate everything" to "look at this
one host."

---

## 6. Zabbix architecture

| Component | Role |
|---|---|
| Zabbix server | Core engine: pollers, trappers, preprocessing, trigger evaluation, alerting. |
| Zabbix agent / agent2 | Lightweight daemon on a host; reports local metrics (CPU, memory, disk, services). agent2 is the newer Go-based agent with plugin support. |
| Agentless checks | Server-side collection with no agent: SNMP, ICMP/simple checks, HTTP agent, IPMI, JMX, SSH/Telnet. |
| Frontend | The PHP web UI (dashboards, configuration, problems view). |
| Database | Stores configuration, history, and trends (PostgreSQL in this lab). |
| Proxies | Collect and buffer data for remote segments, then forward to the server. |
| Items | A single metric definition: a key + a polling interval. |
| Triggers | A logical expression over item values that raises (or clears) a problem. |
| Actions | What happens when a trigger fires: notifications, escalations, remote commands. |
| Templates | Reusable bundles of items, triggers, graphs, and discovery rules. |
| Host groups | Logical grouping of hosts for permissions and mass operations. |
| LLD (Low-Level Discovery) | Automatically discovers entities (interfaces, disks, SNMP OIDs) and auto-creates items/triggers from a prototype. |
| Dashboards | Widget-based visual summaries (graphs, maps, problems, top-talkers). |
| Maintenance windows | Suppress alerting during planned work so real alarms are not drowned out. |

The mental model: **items** collect data, **triggers** turn data into problems,
**actions** turn problems into notifications, and **templates** make all of it
reusable across many hosts.

---

## 7. How this lab wires it up

| Device / service | Monitored by | What is collected |
|---|---|---|
| Routers (vios L3, R1–Rn) | SNMP v2c (`labRO ro`) | Interface state/counters, CPU, uptime, reachability |
| Switches (vios_l2, SW1–SWn) | SNMP | Interface state/counters, MAC/port state |
| Linux servers | `zabbix-agent2` | CPU, memory, disk, processes, service state |
| Web service (SRV-WEB) | Zabbix HTTP agent | Availability and response code of the web check |
| Any reachable address | Simple check / ICMP | Reachability and latency (`icmpping`) |
| All IOS devices | Syslog → SRV-SYSLOG (10.100.0.11) | Events: link up/down, auth, reloads |
| All devices | NTP → SRV-NTP (10.100.0.13) | Correct time so the above can be correlated |

### Planned alerts

| Alert | Idea | Roughly |
|---|---|---|
| Interface down | `ifOperStatus` not `up`, or SNMP link-down trap | immediate |
| CPU high | 5-minute CPU above a sustained threshold | few minutes |
| Packet loss | ICMP loss ratio above threshold | few polls |
| SNMP unreachable | Poll fails / no response for N | few minutes |
| DHCP pool exhausted | DHCP server reports no free leases | on transition |

Each alert needs a *reason to believe it is real* — otherwise it becomes noise
and everyone starts ignoring the dashboard. See section 9.

---

## 8. Planned SNMP checks on IOS

Read these by **name** and let the tool resolve the numeric OID. ⚠️ **Verify
the numeric OID per platform** on the live device with `snmpwalk` before wiring
it into a trigger — the number can differ between IOS families and MIB revisions.

| Object (name) | MIB | What it tells you |
|---|---|---|
| `sysDescr` | SNMPv2-MIB | Device description / software version |
| `sysObjectID` | SNMPv2-MIB | Vendor/device identity |
| `sysUpTime` | SNMPv2-MIB | How long since last initialisation (reload detection) |
| `sysContact` | SNMPv2-MIB | Configured contact |
| `sysName` | SNMPv2-MIB | Configured hostname |
| `sysLocation` | SNMPv2-MIB | Configured location |
| `ifNumber` | IF-MIB | Number of interfaces |
| `ifIndex` | IF-MIB | Interface table index (key for all `if*` tables) |
| `ifDescr` | IF-MIB | Interface name/description |
| `ifType` | IF-MIB | Interface media type |
| `ifAdminStatus` | IF-MIB | Desired state (up/down/testing) |
| `ifOperStatus` | IF-MIB | Actual state — the key one for "interface down" |
| `ifLastChange` | IF-MIB | When the interface last changed state |
| `ifSpeed` / `ifHighSpeed` | IF-MIB | Link speed (32-bit / higher-range) |
| `ifInOctets` / `ifOutOctets` | IF-MIB | 32-bit octet counters (wrap on high-speed links) |
| `ifHCInOctets` / `ifHCOutOctets` | IF-MIB | 64-bit version — use these on fast links |
| `ifInErrors` / `ifOutErrors` | IF-MIB | Receive/transmit errors (physical/cabling problems) |
| `ifInDiscards` / `ifOutDiscards` | IF-MIB | Packets dropped due to resource/queue limits |
| `cpmCPUTotal5minRev` | CISCO-PROCESS-MIB | 5-minute CPU average (sustained utilization) |
| `cpmCPUTotal1minRev` | CISCO-PROCESS-MIB | 1-minute CPU average (burst view) |

⚠️ `ifInOctets`/`ifOutOctets` are 32-bit counters and wrap quickly on fast
interfaces — always prefer the `ifHC*` 64-bit counters for rate math. On
IOS-XE/`vios`, CPU objects may be exposed with the `Rev` suffix; confirm with a
walk.

---

## 9. Troubleshooting the monitoring stack itself

| Symptom | Likely causes | Where to look |
|---|---|---|
| SNMP not responding | Wrong community, wrong version, ACL/mgmt binding, SNMP disabled, UDP 161 filtered | `show run | include snmp`, `snmpwalk` from the collector |
| Syslog not arriving | `logging host` missing/wrong, `logging trap` level too high, collector not listening on UDP 514, routing/firewall | `show logging`, `show run | include logging`, collector config |
| Clock skew | Device not synced to NTP, wrong timezone, NTP server unreachable | `show ntp status`, `show clock detail` |
| False-positive flapping alerts | Poll interval too short, no hysteresis, transient dips counted as outages | Trigger expression, item interval |
| Alert fatigue | Too many low-value/duplicate alerts, no severity or dedup | Trigger thresholds, actions, maintenance windows |
| Thresholds wrong | Threshold set by guess, not by baseline | Graph historical data first |

Tuning thresholds: **baseline first.** Watch a healthy graph for a day, then set
the threshold above normal peak with enough margin that only real problems fire.
For flapping, require the condition to hold for N polls (or for a duration)
before raising a problem, and require a clear condition before resolving it
(hysteresis). Suppress planned work with maintenance windows rather than
muting the whole system.

⚠️ A noisy monitoring stack is worse than no monitoring — people stop trusting
it. Every alert you add should have a defined owner and a defined action.

---

## 10. Exercises

1. **Walk the interface table.** From the collector, `snmpwalk` the interface
   table on R1 and map `ifDescr`, `ifAdminStatus`, and `ifOperStatus` to the
   physical ports. Record the numeric OIDs you actually got.
2. **Interface-down drill.** `shutdown` one interface, then confirm the alert
   fires within N minutes. Record the timeline: shut time, poll time, alert
   time. Then `no shutdown` and confirm it clears.
3. **CPU baseline + threshold.** Graph `cpmCPUTotal5minRev` for 30 minutes of
   idle, then generate load and record the peak. Choose a threshold and justify
   it from the data.
4. **Counter rate math.** Collect `ifHCInOctets`/`ifHCOutOctets` twice, one
   minute apart, and compute the interface throughput in Mbps. Compare against
   `show interface` on the device.
5. **Syslog end-to-end.** Trigger a logged event (interface flap, bad login),
   find it in the collector, and confirm the timestamp matches device time.
6. **NTP verification.** Break NTP on one device (remove the server), watch the
   offset grow, restore it, and confirm `show ntp status` returns to
   synchronised. Note how drift and offset behave.
7. **DHCP exhaustion alert.** Shrink a DHCP pool, lease it out, and confirm the
   "pool exhausted" alert fires. Record the trigger and the recovery.
8. **Alert-fatigue review.** List every alert in the stack, and for each write
   owner, severity, expected action, and whether it is actionable. Remove or
   tune anything that fails the test.
