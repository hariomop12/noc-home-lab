---
tags: [containerlab, topology, noc, frr]
status: active
---

# containerlab lab

The same network the GNS3 labs build by hand (Lab 06 HQ, Lab 07 branch + WAN)
— rebuilt as **one YAML file of containers**. Real FRRouting routers, real
Linux bridges as switches, real dnsmasq/rsyslog/nginx/chrony containers as the
servers, and a real NAT table.

Why it exists: Labs 01-07 prove the configuration. This lab is the substrate for
the two phases that need a network that can be broken and repaired on demand,
many times, without a GUI:

- **Phase 4 — ticket labs.** Break one thing, hand over the symptom, diagnose it
  with real commands, fix it, write the ticket (`docs/tickets/`).
- **Phase 5 — Full NOC.** Poll every device over SNMP, collect syslog centrally,
  alert on failure, and write the failover timeline (`labs/lab-09-full-noc/`).

Addressing is the repository plan from [../docs/01-ip-plan.md](../docs/01-ip-plan.md)
— the only deliberate difference is that Lab 08's redundancy (R3, HSRP virtual
IPs) is not rebuilt here, so the gateways are the real router addresses (`.1`),
not virtual ones.

---

## Topology

```
                    srv-net 200.1.1.10
                            |
                            | 200.1.1.0/24
                        +-------+
                        |  isp  | 100.64.0.1
                        +-------+
                10.0.0.12/30 |         | 10.0.0.16/30
                            |         |
                10.0.0.13/30|         |10.0.0.17/30
                      +-------+     +-------+
                      |  r1   |-----|  r2   |           transit 10.0.0.0/30
                      | HQ    |     | BR1   |           10.0.0.1  /  10.0.0.2
                      +-------+     +-------+
                    eth2  |             |  eth2
                  trunk   |             |  trunk
                     +---------+    +--------+
                     |   sw1   |====|   sw2  |          two links: the L2 loop
                     |  4096   |====|  8192  |          STP blocks one of them
                     +---------+    +--------+
                       |     |       | | | | |
                     pc1   pc2     pc3 pc4 ...       VLAN 10 HR, 20 SALES, 30 IT
                      V10   V20     V30 V30
                                              client + srv-dns/syslog/web/ntp
                                                    (VLAN 40 SERVERS)

                     +--------+
                     |   r2   |--+-- sw3 -- pc5, pc6           BR1 VLAN 10
                     +--------+  |   10.20.99.13
```

## Nodes

| Node | Kind | Image | Role |
|---|---|---|---|
| `isp` | frr | `clab-frr:lab` | Simulated ISP, originates the OSPF default route |
| `r1` | frr | `clab-frr:lab` | HQ edge: router-on-a-stick, NAT, DHCP relay, OSPF |
| `r2` | frr | `clab-frr:lab` | BR1 edge: WAN, NAT, DHCP relay, transit to HQ |
| `sw1` | linux | `clab-host:lab` | HQ access switch, STP root (priority 4096) |
| `sw2` | linux | `clab-host:lab` | HQ server switch, STP secondary (priority 8192) |
| `sw3` | linux | `clab-host:lab` | BR1 access switch |
| `pc1`-`pc4` | linux | `clab-host:lab` | HQ users, DHCP clients (VLAN 10/20/30) |
| `pc5`, `pc6` | linux | `clab-host:lab` | BR1 users, DHCP clients (VLAN 10) |
| `client` | linux | `noc-tools:lab` | NOC toolbox: ssh, snmpget/snmpwalk, dig, tcpdump |
| `srv-dns` | linux | `dnsmasq:lab` | DHCP + DNS for the whole lab |
| `srv-syslog` | linux | `syslog:lab` | Central syslog collector |
| `srv-web` | linux | `web:lab` | Internal web server |
| `srv-ntp` | linux | `ntp:lab` | NTP server for every device |
| `srv-net` | linux | `web:lab` | The "internet" behind the ISP |

Routers and switches all run the same management agents
(`configs/common/agents.sh`): `snmpd` (community `labRO`), `rsyslogd`
forwarding to `10.100.0.11`, and `chronyd` pointed at `10.100.0.13`.

## Addressing

| Where | Subnet | Gateway / address |
|---|---|---|
| HQ VLAN 10 HR | `10.10.10.0/24` | `10.10.10.1` (r1 `eth2.10`) |
| HQ VLAN 20 SALES | `10.10.20.0/24` | `10.10.20.1` (r1 `eth2.20`) |
| HQ VLAN 30 IT | `10.10.30.0/24` | `10.10.30.1` (r1 `eth2.30`) |
| HQ VLAN 40 SERVERS | `10.100.0.0/24` | `10.100.0.1` (r1 `eth2.40`) |
| HQ VLAN 99 MGMT | `10.10.99.0/24` | `10.10.99.1` (r1 `eth2.99`) |
| BR1 VLAN 10 USERS | `10.20.10.0/24` | `10.20.10.1` (r2 `eth2.10`) |
| BR1 VLAN 99 MGMT | `10.20.99.0/24` | `10.20.99.1` (r2 `eth2.99`) |
| HQ WAN | `10.0.0.12/30` | r1 `.13`, isp `.14` |
| BR1 WAN | `10.0.0.16/30` | r2 `.17`, isp `.18` |
| HQ-BR1 transit | `10.0.0.0/30` | r1 `.1`, r2 `.2` |
| Simulated internet | `200.1.1.0/24` | isp `.1`, srv-net `.10` |
| Loopbacks | — | r1 `10.255.0.1`, r2 `10.255.0.2`, isp `100.64.0.1` |
| Servers (VLAN 40) | — | dns `.10`, syslog `.11`, web `.12`, ntp `.13`, client `.50` |
| Switch management | — | sw1 `10.10.99.11`, sw2 `10.10.99.12`, sw3 `10.20.99.13` |
| Out-of-band mgmt | `172.21.21.0/24` | containerlab network, `eth0` on every node |

Per-node interface numbering follows the order the node appears in `links`:
r1 `eth1` WAN, `eth2` trunk to sw1 (`.10/.20/.30/.40/.99`), `eth3` transit to r2.
`eth0` is always the out-of-band network.

## Use it

```bash
cd containerlab

sudo containerlab deploy  -t topology.clab.yml     # up
containerlab inspect      -t topology.clab.yml     # what is running
./scripts/baseline.sh                              # ~35 assertions, live
sudo containerlab destroy -t topology.clab.yml --cleanup
```

Log in to a device:

```bash
docker exec -it clab-noclab-r1 vtysh              # router
docker exec -it clab-noclab-sw1 sh                # switch (Linux bridge)
docker exec -it clab-noclab-client sh             # NOC toolbox
```

The images come from this repository's `docker/` directory:

```bash
cd ../docker && ./build.sh      # noc-tools, syslog, dnsmasq, web, ntp, clab-frr, clab-host
```

## Design notes

**The routers are FRR, the switches are bridges.** `clab-frr:lab` is the official
FRR image plus `iproute2`, `nftables`, `dnsmasq`, `net-snmp`, `rsyslog` and
`chrony` — everything the lab's guides assume exists on a router.
`clab-host:lab` is Alpine with real `iproute2` (busybox `ip` cannot do 802.1Q
bridge filtering) and the same agents. A switch is therefore a Linux bridge with
`vlan_filtering 1` and `stp_state 1`: access ports are `pvid untagged`, trunks
carry the tagged VLAN list, and the two links between sw1 and sw2 form a real
loop that STP has to break.

**Each switch has a management address on VLAN 99.** The bridge's own port is
put into VLAN 99 (`bridge vlan add dev br0 vid 99 self pvid untagged`) and the
address goes on `br0` — the closest a Linux bridge gets to an SVI. That is why
the NOC can SNMP-poll a switch at `10.10.99.11` exactly like it polls a router.

**NAT is nftables, not IOS.** The FRR build ships without NAT support, so PAT is
one `nft` table on the WAN interface. The rule kept the lesson from the Lab 07
correction: only the WAN interface translates, and only traffic sourced from the
lab prefixes — the internal transit to the other router is deliberately *not*
translated, so a site whose own WAN is down still reaches the internet through
the other site with a correct source address.

**DHCP is relayed, not served locally.** `ip helper-address 10.100.0.10` does not
exist in FRR; `dnsmasq --dhcp-relay=<gateway>,<server>` does the same job —
the request keeps its broadcast on the user VLAN, the relay stamps giaddr with
the gateway address, and the single server in VLAN 40 picks the scope from that
field. BR1 users are served two hops away over the transit, which is the Lab 07
design.

**The WAN links start in OSPF `Waiting`.** On a broadcast segment a router waits
`dead-interval` (40 s) before the DR election. The first verification run a few
seconds after deploy showed r1 and r2 in `2-Way/DROther` on their WAN links — not
a fault, just the wait timer; the transit link (point-to-point) was `Full`
immediately. `scripts/baseline.sh` therefore asserts on adjacencies after
convergence, and the guides quote the state at the moment they were taken.

### Traps worth knowing (each one cost real time here)

| Trap | Why | What to do |
|---|---|---|
| `docker restart clab-noclab-x` breaks the node | The veth interfaces live in the container's network namespace; a restart creates a new one and the lab interfaces are gone (`Cannot find device "eth2"`) | Use `containerlab deploy` / `destroy`, or `containerlab tools` — never `docker restart` |
| A service container has no lab address | The image entrypoint can run before containerlab has moved `eth1` in | The shared entrypoint waits for `LAB_IFACE` to appear (fixed in `docker/entrypoint-lib.sh`) |
| `snmpd` exits with "Error opening specified endpoint udp:161" | The packaged default config also sets `agentaddress`, so two of them conflict | Start it with `-C -c /etc/snmp/snmpd.conf` |
| A switch has no IP despite `ip addr add` | With `vlan_filtering 1` the bridge wants to know which VLAN its own port is in | `bridge vlan add dev br0 vid 99 self pvid untagged` before the address |

## Evidence

`./scripts/baseline.sh` on a freshly deployed lab — full output in
[`artifacts/baseline-noclab.txt`](artifacts/baseline-noclab.txt):

<details>
<summary><b>46 passed, 0 failed</b> — click for the run</summary>

```
containerlab baseline - 2026-10-17 13:52:07 IST

== containers
  PASS  containers                     18 nodes running

== routing (OSPF, one area)
  PASS  ospf-r1                        r1: both neighbours FULL
  PASS  ospf-r2                        r2: both neighbours FULL
  PASS  default-r1                     r1 has an OSPF default route
  PASS  default-r2                     r2 has an OSPF default route
  PASS  br1-via-transit                r1 reaches BR1 over the transit
  PASS  hq-via-transit                 r2 reaches HQ over the transit

== DHCP (one server, relayed)
  PASS  dhcp-pc1                       pc1 has a VLAN 10 lease
  PASS  dhcp-pc2                       pc2 has a VLAN 20 lease
  PASS  dhcp-pc3                       pc3 has a VLAN 30 lease
  PASS  dhcp-pc4                       pc4 has a VLAN 30 lease
  PASS  dhcp-pc5                       pc5 has a BR1 lease
  PASS  dhcp-pc6                       pc6 has a BR1 lease

== reachability
  PASS  pc1-to-gw                      pc1 -> VLAN 10 gateway
  ...  (6 gateways, 4 cross-VLAN paths, 2 internet paths, 2 management SVIs)
  PASS  mgmt-sw3                       client -> sw3 VLAN 99 SVI

== NAT (only the WAN interface translates)
  PASS  nat-translated                 conntrack shows the WAN address
  PASS  nat-on-the-wire                the internet sees r1's WAN address
  PASS  nat-not-leaking                no private source on the ISP internet link
  PASS  nat-rule                       r1 NAT matches the WAN interface only

== DNS
  PASS  dns-a-record                   client resolves web.lab.local
  PASS  dns-ptr                        client resolves r1.lab.local

== layer 2 (STP)
  PASS  stp-loop-broken                exactly one uplink is blocking
  PASS  stp-root                       sw1 is the root bridge (priority 4096)

== management plane
  PASS  snmp-r1  PASS  snmp-r2  PASS  snmp-sw1  PASS  snmp-sw2  PASS  snmp-sw3  PASS  snmp-isp
  PASS  syslog-r1  PASS  syslog-sw1  PASS  syslog-isp
  PASS  ntp-r1  PASS  ntp-sw1
```

</details>

Measured, not assumed: this is the whole network as one command, after a clean
`deploy`, with the raw output committed alongside it.

Raw evidence for the individual skills (captures, SNMP walks, syslog excerpts)
lives with the lab that produced it:

- `labs/lab-09-full-noc/README.md` — Phase 5: SNMP polling, syslog, Zabbix, alert
  triage, failover timeline.
- `docs/tickets/` — Phase 4: the ten break-and-diagnose tickets, each against
  this lab.
