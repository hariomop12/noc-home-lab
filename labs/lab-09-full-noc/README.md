---
lab: 09
level: complex
status: done
tags: [homelab, lab, noc, zabbix, snmp, syslog, monitoring, alerting, containerlab]
---

# Lab 09 — Full NOC

## Metadata

| Field | Value |
|---|---|
| Level | complex |
| Estimated time | 2–3 days |
| Prerequisites | Lab 05 (management plane), Lab 06 (HQ), Lab 07 (branch + WAN); the ticket labs for the fault set |
| Skills practised | Monitoring design, SNMP polling, Zabbix host/item/trigger modelling, low-level discovery, ICMP versus SNMP failures, alert triage, measured failover timelines, runbook writing, containerlab as a test bed |
| Related docs | [containerlab/README.md](../../containerlab/README.md), [Roadmap Phase 5](../../docs/00-roadmap.md), [Ticket labs](../../docs/tickets/README.md) |

## Objective

Build a NOC that watches every device in the lab, and then **prove it works by
breaking the lab and measuring how long the alarm took**.

The network is the HQ + Branch-1 topology from Labs 06/07, rebuilt in
containerlab ([`containerlab/topology.clab.yml`](../../containerlab/topology.clab.yml))
so that a fault can be injected, detected, repaired and repeated from a shell —
no GUI, no clicking, and a timestamp on every step.

The deliverable is not "Zabbix is running". It is this line, with real numbers
behind it:

> The NOC lost sight of six devices, raised six High alarms, and the fastest one
> fired 13 seconds after the fault — while the lab itself took 88 seconds to
> recover its state in the monitoring system.

## What is monitored

Twelve hosts, chosen so that every layer of the lab has a witness:

| Host | Address polled | Why this address | Checks |
|---|---|---|---|
| `r1` | `10.255.0.1` (loopback) | must survive any single link failure | SNMP, interfaces, CPU, ICMP |
| `r2` | `10.255.0.2` (loopback) | same, on the branch router | SNMP, interfaces, CPU, ICMP |
| `isp` | `10.0.0.14` | the internet edge is where "no internet" is decided | SNMP, interfaces, CPU, ICMP |
| `sw1` | `10.10.99.11` (VLAN 99 SVI) | the switch's own management address | SNMP, interfaces, CPU, ICMP |
| `sw2` | `10.10.99.12` | " | SNMP, interfaces, CPU, ICMP |
| `sw3` | `10.20.99.13` | " | SNMP, interfaces, CPU, ICMP |
| `srv-dns` | `10.100.0.10` | the service the whole lab depends on | ICMP |
| `srv-syslog` | `10.100.0.11` | the collector itself must be watched | ICMP |
| `srv-web` | `10.100.0.12` | the service the ACL ticket breaks | ICMP |
| `srv-ntp` | `10.100.0.13` | time is what makes logs usable | ICMP |
| `client` | `10.100.0.50` | the NOC toolbox | ICMP |
| `zbx-agent` | `10.100.0.23` | the NOC watches itself too | Zabbix agent |

Per device: `sysName`, `sysDescr`, `sysUpTime` over SNMP; interface operational
status for **every interface, discovered** with low-level discovery (IF-MIB
`ifOperStatus`, `{#SNMPINDEX}` = `ifIndex`); CPU idle and 1-minute load from the
UCD-SNMP MIB; and ICMP reachability, loss and round-trip time.

Triggers: host unreachable by ICMP (High, needs three lost polls), partial packet
loss > 40% over five minutes (Average), SNMP data missing for five minutes (High
— a box can be pingable while its monitoring died), interface down (Average),
CPU idle < 10% for five minutes, load average > 4, and agent not answering.

Measured on the live stack: **12 hosts, 6 discovery rules, 115 items, 92
triggers** — 41 declared by hand and 51 created by discovery, one per interface,
with every item `state=0` (supported) in
[`../../containerlab/artifacts/phase5-zabbix-status.txt`](../../containerlab/artifacts/phase5-zabbix-status.txt).

## Theory

**Poll, don't wait to be told.** SNMP is a pull protocol: the NOC decides the
interval, so detection latency is a number you choose, not a number you hope for.
`delay` on the item is how often the value is collected; the trigger's window
(`#3`, `5m`) is how much bad data is required before it counts. Alert time is
roughly `delay × window` plus one scheduler pass — which is why this lab runs
ICMP at 30 s and SNMP at 60 s, and why the SNMP backstop deliberately takes five
minutes.

**The monitoring address must be the one that cannot move.** The routers are
polled on their loopbacks. In drill B below the branch switch loses its uplink
and goes red while `r2` — the router *behind* that same failure — stays green,
because its loopback is still reachable over a different path. Had `r2` been
polled on a physical interface, the same outage would have looked like two
problems.

**A host needs two interfaces in the monitoring system, not one.** SNMP items are
polled over the SNMP interface, but `icmpping` is a *simple check* executed by the
Zabbix server itself and needs a plain interface to run against. Creating only the
SNMP interface makes `item.create` reject every ICMP item; creating only the agent
interface makes SNMP impossible. This is the first wall every newcomer hits when
adding a switch.

**Two different failures need two different triggers.** "The box is gone" (ICMP
fails) and "the box is there but stopped reporting" (SNMP values stop arriving)
describe different incidents: a crashed poller, an ACL on the management path, a
community string changed by someone. ICMP alone will happily report a healthy
device that has not been polled in a week.

**The monitor has to be reachable when the lab is not.** The NOC lives in VLAN 40
next to the servers it watches, and its four containers also have fixed addresses
on the out-of-band management network (`172.21.21.0/24`, `eth0` on every node).
The Zabbix frontend is therefore reachable at `http://172.21.21.74:8080` even
during an outage in the lab — which is exactly when you need to look at it.

**Recovery is a measurement too.** Zabbix triggers here use an explicit recovery
expression (`max(...,#3)=1`), so "resolved" means three consecutive good polls,
not the first lucky one. The cost is honest: the drill shows ~88 s from repair to
"resolved", because three 30-second polls have to succeed.

**One blind spot, stated up front.** Every device in this lab is polled through
VLAN 40, so drill A breaks the NOC's own view along with the network. From inside
Zabbix, "six devices unreachable" cannot be distinguished from "my path is
broken". The fix is to poll each device twice, over two independent paths — the
lab routers all have an `eth0` on the out-of-band network for exactly this — and
it is written down under *What is next* rather than pretended away.

## Topology

```
                       srv-net 200.1.1.10
                               |
                           +-------+
                           |  isp  | 10.0.0.14 (loopback 100.64.0.1)
                           +-------+
                   10.0.0.12/30 |         | 10.0.0.16/30
                                 |         |
                                 |         |
                          +-------+     +-------+
                          |  r1   |=====|  r2   |   transit 10.0.0.0/30
                          | Lo .1 |     | Lo .2 |   polled on the loopbacks
                          +-------+     +-------+
                        eth2 |              | eth2
                             |              |
                        +---------+     +--------+
                        |   sw1   |=====|   sw2  |   L2 loop, STP blocks one
                        | .99.11  |=====| .99.12 |
                        +---------+     +--------+
                          |   |          | | | | | | |
                       pc1  pc2        pc3 pc4 client srv-dns/syslog/web/ntp
                                                  + zbx-web / zbx-server / zbx-agent
                                                     10.100.0.20 / .21 / .23
                                                     (VLAN 40 - the NOC)
                          zbx-db 172.21.21.72 - out-of-band only, on purpose
```

`zbx-db` has no lab interface at all: it is a backend that the server reaches over
the management network. That is a deliberate design choice explained in
[containerlab/README.md](../../containerlab/README.md) — a restart in containerlab
builds a new network namespace, and a node that only received its lab interface
earlier never gets it back.

## Build it

```bash
cd containerlab
sudo containerlab deploy -t topology.clab.yml      # the whole lab, 22 containers
./scripts/baseline.sh                              # 51 assertions, expect 51/51

python3 scripts/noc-bootstrap.py                   # declare the lab to Zabbix
python3 scripts/nocctl.py status                   # what the NOC can see now
python3 scripts/nocctl.py problems                 # open problems + recent events
python3 scripts/nocctl.py drill                    # the failover drill, end to end
```

`noc-bootstrap.py` is idempotent and self-healing: a host that already exists is
walked through the item and trigger stage again, so a half-finished bootstrap or
a check added later is repaired by re-running it. Nothing is created by clicking
in the web UI — the entire NOC is code in the repository, which means it can be
reviewed, diffed and rebuilt.

The Zabbix API is documented at
https://www.zabbix.com/documentation/7.0/en/manual/api and the scripts use it
directly (`user.login`, `host.create`, `item.create`, `trigger.create`,
`discoveryrule.create`, `problem.get`, `event.get`).

## Verification

`./scripts/baseline.sh` treats the NOC as part of the lab, so the monitoring
stack cannot be broken without the baseline failing:

```
== management plane
  PASS  snmp-r1 ... snmp-isp              SNMP labRO reachable on all six devices
  PASS  syslog-r1, syslog-sw1, syslog-isp collector has each device's messages
  PASS  ntp-r1, ntp-sw1                   devices are synced to srv-ntp

== NOC stack (Phase 5)
  PASS  zbx-db       Postgres accepts connections (5432, out-of-band)
  PASS  zbx-server   Zabbix server listens (10051)
  PASS  zbx-agent    Zabbix agent listens (10050)
  PASS  zbx-web      frontend answers HTTP on 8080
  PASS  zbx-api      API answers apiinfo.version (7.0.31)
```

All of it measured on a live deployment — raw output in
[`../../containerlab/artifacts/baseline-noclab.txt`](../../containerlab/artifacts/baseline-noclab.txt).
The item-by-item state of the NOC is in
[`phase5-zabbix-status.txt`](../../containerlab/artifacts/phase5-zabbix-status.txt):
every item `state=0` (supported), with real last values — sysUpTime climbing,
interface statuses at 1, CPU idle where it should be.

## The failover drill

Full transcript: [`../../containerlab/artifacts/phase5-zabbix-drill.txt`](../../containerlab/artifacts/phase5-zabbix-drill.txt).
Every timestamp below is copied from it.

### Drill A — one change, six alarms (blast radius)

Fault: VLAN 40 is removed from sw2's two uplinks. The lab keeps forwarding, but
the NOC's own path to every device it polls is gone.

| Time | Event |
|---|---|
| 14:14:19 | fault injected (`bridge vlan del dev eth1 vid 40`, `eth2` likewise) |
| 14:14:19 | NOC toolbox cannot ping `10.255.0.1` — verified independently of Zabbix |
| 14:14:32 | **`r1` unreachable by ICMP** — 13 s after injection |
| 14:14:35 | `r2` unreachable |
| 14:14:38 | `isp`, `sw1` unreachable |
| 14:14:41 | `sw2` unreachable |
| 14:14:44 | `sw3` unreachable — all six devices, one changed line |
| 14:14:53 | fault repaired (VLAN 40 added back to both uplinks) |
| 14:15:02 | ping works again — the lab is healthy before Zabbix says so |
| 14:16:02–14:16:12 | the six alarms resolve, ~88 s after the repair (three good 30 s polls) |

Two lessons are visible in those numbers. First, **13 seconds**: the ICMP item
polls every 30 s and the trigger wants three lost polls, yet the alarm fired in
13 s — because Zabbix evaluates the trigger as soon as new data lands and the
poller had already collected failing values. The formula is `delay × window`, but
the clock starts at the first poll *after* the fault, not at the fault. Second,
**the recovery is slower than the detection**: 88 s of good polls are required
before the problem clears, which is the price of a three-sample recovery
expression. If that is too slow for an SLA, lower the window — and accept more
flapping.

### Drill B — one device, and the loopback payload

Fault: sw3's uplink to r2 goes down.

| Time | Event |
|---|---|
| 14:16:18 | fault injected (`ip link set eth1 down` on sw3) |
| 14:16:18 | NOC toolbox cannot ping `10.20.99.13` |
| 14:16:43 | **`sw3` unreachable by ICMP** — 25 s after injection |
| 14:16:52 | fault repaired |
| 14:18:12 | alarm resolves, 89 s later |

Only one host alarmed. `r2` — the router whose access port just died, and whose
users are cut off — stayed green, because it is monitored on its loopback and its
loopback is still reachable over the transit. A physical-interface monitoring
address would have reported two devices down and sent the responder looking for a
cause that does not exist.

Both drills also show the difference between the two findings: after the repair
in drill A the network was verifiably healthy (`0% packet loss` from the toolbox)
a full minute before Zabbix cleared the alarm. When someone asks "is it really
fixed?", the answer is a command, not the dashboard.

## Triage runbook

What to do, in order, when this NOC goes off:

1. **Read the alert, not the dashboard.** One host down = the device. Many hosts
   down at once = a shared path (uplink, VLAN, or the NOC's own route). The blast
   radius *is* the first diagnostic.
2. **Confirm with a command outside the NOC.** `docker exec clab-noclab-client
   ping -c2 <address>`. If the toolbox also fails, the network is down. If the
   toolbox succeeds and Zabbix fails, the problem is the NOC or its path.
3. **Distinguish ICMP from SNMP.** ICMP down + no SNMP = the device is gone. ICMP
   up + SNMP missing = the device is up but something on its management plane
   changed (community, ACL, agent crash, CPU starved).
4. **Check the device itself.** `docker exec -it clab-noclab-r1 vtysh -c "show ip
   ospf neighbor"`, `bridge vlan show` on a switch, `snmpwalk -v2c -c labRO
   <address> 1.3.6.1.2.1.1`.
5. **Correlate with syslog and time.** `ls -lt /var/log/remote/` inside
   `clab-noclab-srv-syslog`, and `chronyc sources` to prove the timestamps can be
   trusted.
6. **Write down what you did, with the timestamps.** The next drill's numbers are
   only interesting next to this one's.

## Traps (each cost real time here)

| Trap | What it looks like | Fix |
|---|---|---|
| A wrapped vendor image exits immediately | `LogType "console" ... can only be used with -f` in the server log, container restarting | Setting `ENTRYPOINT` in a Dockerfile **resets the base image's `CMD`** — repeat the vendor `CMD` |
| A container loops forever with no lab interface | `Error: Nexthop has invalid gateway`, `eth1` missing | containerlab runs nodes with `restart: always`; a restart makes a new netns and the veth is gone. Give backends no lab link, or `containerlab deploy --reconfigure`. Never `docker restart` |
| `problem.get` fails with `unexpected parameter "selectHosts"` | the API refuses the call | `problem.get` returns a *trigger* id, not a host; resolve it with `trigger.get` in a second call |
| `item.create` says `the parameter "key_" is missing` | API rejects an item | The parameter is `key_`, with the underscore — `key` is silently a different field |
| `apiinfo.version` fails once authenticated | `must be called without the "auth" parameter` | Ask it before logging in; it is the one unauthenticated method |
| The ISP's syslog never reaches the collector | SNMP to the ISP works, syslog is missing, `omfwd: no working target server` in its own log | rsyslog *suspends* a UDP forwarding action when the target has no route at boot: `action.resumeRetryCount="-1" action.resumeInterval="5"` |

## What I learned

1. **A monitoring system is a design, not a product.** Choosing what to poll,
   where to poll it and how long to wait is where the engineering is; installing
   Zabbix is the easy hour.
2. **Poll the address that should not move.** Loopbacks for routers, the SVI for
   switches. Drill B is the proof: one outage, one alarm, because the monitoring
   address did not share fate with the failed link.
3. **Detection latency is arithmetic you can predict.** `delay × window`, minus
   the head start of an already-running poll cycle. The drill measured 13 s and
   25 s against a 90-second worst case — knowing *why* is the difference between
   trusting the NOC and guessing at it.
4. **Alert count is information.** Six alarms from one change tells you the blast
   radius before you open a single device.
5. **The NOC must survive what it watches.** Its database lives out-of-band, its
   frontend has a management address, and its own agent is monitored — otherwise
   the monitoring becomes part of the outage.
6. **State the blind spots.** Polling everything through one VLAN means one
   cut can blind the NOC; writing that down next to the green checkmarks is the
   honest version of "the NOC works".

## Self-check questions

1. The ICMP item polls every 30 s and the trigger requires three lost polls —
   why did drill A alarm in 13 seconds?
2. Why does the recovery take ~88 s even though the repair was verified by ping
   in one second?
3. What would `r2` have looked like in drill B if it were polled on
   `10.0.0.17` instead of `10.255.0.2`?
4. Why does every SNMP host also need an interface of type "Zabbix agent" that
   has no agent behind it?
5. What failure does the `nodata(/host/snmp.sysUpTime,5m)` trigger catch that
   `icmpping` cannot?
6. If the NOC reports six devices down at once, what are the first two commands
   you run, and what does each outcome mean?

## What is next

Phase 5's remaining roadmap items, honestly listed:

- **Poll over two independent paths.** Add ICMP/SNMP checks through the
  out-of-band network (`172.21.21.x`, already assigned to every node) so the NOC
  can tell "the lab is broken" from "my path is broken". Drill A is the evidence
  that this matters.
- **Syslog triggers.** The collector stores per-device files; a severity 0–2
  trigger (via a log-file item or the SNMP trap receiver) would catch an incident
  the poller is too slow to see.
- **Dashboards.** Problems, blast radius and the last drill's timeline on one
  screen — the API already returns everything needed.
- **Ansible.** Push the golden configuration to every device in one run and diff
  it against this lab's manual configuration, which is the last open item in
  Phase 5.
- **Lab 08 (Redundancy) is still paused**, and deliberately not rebuilt here: this
  substrate uses the Lab 06/07 addressing with real `.1` gateways, so HSRP virtual
  IPs and the second HQ router can be added on top without changing anything the
  NOC polls — except that the monitoring addresses stay on the loopbacks, which is
  precisely the point.
