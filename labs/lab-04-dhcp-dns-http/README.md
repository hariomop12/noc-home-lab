---
lab: 04
level: micro
status: done
tags: [homelab, lab, dhcp, dns, http, docker]
---

# Lab 04 — DHCP + DNS + HTTP

## Metadata

| Field | Value |
|---|---|
| Level | micro |
| Estimated time | 90 min |
| Prerequisites | Lab 02 (gateway), Lab 03 (VLAN + trunk) |
| Skills practised | DHCP DORA, DHCP relay, DNS resolution, HTTP over TCP, Docker services |
| Related docs | [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md), [../../docs/03-gns3-setup.md](../../docs/03-gns3-setup.md), [../../docker/README.md](../../docker/README.md) |

## Objective

After this lab I can bring a PC onto the network with **no manual IP**, explain
how it got its address, resolve a name to an IP, and fetch a web page — proving
each step from a packet capture instead of from memory.

## Theory

- **DHCP** hands a host four things: IP, mask, gateway, DNS. It happens in four
  messages — **D**iscover, **O**ffer, **R**equest, **A**ck (DORA). Because the
  server lives on a different subnet here, the router must **relay** the request
  and stamp it with `giaddr` so the server knows which pool to use.
- **DNS** turns `web.lab.local` into `10.100.0.12`. The client asks its configured
  DNS server (from DHCP) and caches the answer.
- **HTTP** runs over **TCP**: three-way handshake, then `GET`, then `200 OK`.
  Names are resolved *before* any of that happens.

## Topology

```
PC1 ── SW1 Gi0/1 (access VLAN 10)
SW1 Gi0/2 ── R1 Gi0/0 (trunk, VLAN 10)
R1 Gi0/1 ── SW2 (server segment, 10.100.0.0/24)
              ├── SRV-DNS   10.100.0.10   (dnsmasq)
              ├── SRV-WEB   10.100.0.12   (nginx)
              └── CLIENT    10.100.0.50   (noc-tools: dig / curl / tcpdump)
```

| Device | Template | Interface | Address | Notes |
|---|---|---|---|---|
| R1 | vios | Gi0/0 | — | trunk to SW1 |
| R1 | vios | Gi0/0.10 | 10.10.10.1/24 | VLAN 10 gateway + DHCP relay |
| R1 | vios | Gi0/1 | 10.100.0.1/24 | server LAN gateway |
| SW1 | vios_l2 | Gi0/1 | — | access port to PC1 |
| SW1 | vios_l2 | Gi0/2 | — | trunk to R1 |
| SW2 | Ethernet switch | — | — | server segment (no config) |
| PC1 | VPCS | eth0 | **DHCP** | the client being served |
| SRV-DNS | `dnsmasq:lab` | eth0 | 10.100.0.10/24 | DHCP + DNS |
| SRV-WEB | `web:lab` | eth0 | 10.100.0.12/24 | nginx |
| CLIENT | `noc-tools:lab` | eth0 | 10.100.0.50/24 | test tools |

Addressing from [../../docs/01-ip-plan.md](../../docs/01-ip-plan.md).

## Build steps

### 0. Build the images (once)

```bash
cd docker
./build.sh          # builds noc-tools:lab, syslog:lab, dnsmasq:lab, web:lab
```

### 1. Add the container templates in GNS3

`Preferences → Docker containers → New`, for each image:

| Template name | Image | `LAB_IP` (default) | `LAB_GW` (default) |
|---|---|---|---|
| `SRV-DNS` | `dnsmasq:lab` | `10.100.0.10/24` | `10.100.0.1` |
| `SRV-WEB` | `web:lab` | `10.100.0.12/24` | `10.100.0.1` |
| `CLIENT` | `noc-tools:lab` | `10.100.0.50/24` | `10.100.0.1` |

Console type **telnet**. The images already default to these addresses, so no
environment variables are needed — set `LAB_IP` / `LAB_GW` only to override.

### 2. Build and cable the topology

1. Add: 1× `vios` router, 1× `vios_l2` switch, 1× **Ethernet switch** (built-in,
   free), 1× VPCS, and the three containers from step 1.
2. Name them `R1`, `SW1`, `SW2`, `PC1`, `SRV-DNS`, `SRV-WEB`, `CLIENT`.
3. Cable exactly as drawn. Lowest port to the LAN, highest to the uplink.
4. Start everything. `vios_l2` boots slowly — wait.

### 3. Configure

Apply the golden baseline first (`configs/golden-configs/`), then:

**R1**
```
interface GigabitEthernet0/0
 no shutdown
!
interface GigabitEthernet0/0.10
 encapsulation dot1Q 10
 ip address 10.10.10.1 255.255.255.0
 ip helper-address 10.100.0.10
!
interface GigabitEthernet0/1
 ip address 10.100.0.1 255.255.255.0
 no shutdown
```
`ip helper-address` is the relay: it converts the client's broadcast into a
unicast to the DHCP server and puts `10.10.10.1` in `giaddr`.

**SW1**
```
vlan 10
!
interface GigabitEthernet0/1
 switchport mode access
 switchport access vlan 10
!
interface GigabitEthernet0/2
 switchport trunk encapsulation dot1q
 switchport mode trunk
```

**SW2** — nothing to configure.

**PC1** (VPCS console)
```
dhcp
show ip
```
VPCS should print an address in `10.10.10.100-200`, gateway `10.10.10.1`, DNS
`10.100.0.10`.

## Verification

| # | Command | Expected result | Actual result |
|---|---|---|---|
| 1 | `show ip` on PC1 | address 10.10.10.100-200, gw .1, dns 10.100.0.10 | ✅ `10.10.10.160/24`, gw `10.10.10.1`, dns `10.100.0.10`, domain `lab.local` |
| 2 | `ping 10.100.0.1` from PC1 | server-LAN gateway reachable | ✅ 3/3, `ttl=255` (reply from R1 itself) |
| 3 | `ping web.lab.local` from PC1 | resolves to 10.100.0.12 and replies | ✅ resolved to `10.100.0.12`, 3/3, `ttl=63` |
| 4 | `dig web.lab.local @10.100.0.10` on CLIENT | A record 10.100.0.12 | ✅ `10.100.0.12` |
| 5 | `curl -s web.lab.local` on CLIENT | nginx page returned | ✅ `HTTP 200`, 896 bytes, nginx welcome page |

If row 1 fails, nothing else can pass — fix DHCP first.

Raw PC1 output:

```
PC1> show ip
NAME        : PC1[1]
IP/MASK     : 10.10.10.160/24
GATEWAY     : 10.10.10.1
DNS         : 10.100.0.10
DHCP SERVER : 10.100.0.10
DHCP LEASE  : 43200, 43200/21600/37800
DOMAIN NAME : lab.local

PC1> ping web.lab.local
web.lab.local resolved to 10.100.0.12
84 bytes from 10.100.0.12 icmp_seq=1 ttl=63 time=7.137 ms
84 bytes from 10.100.0.12 icmp_seq=2 ttl=63 time=3.918 ms
84 bytes from 10.100.0.12 icmp_seq=3 ttl=63 time=4.129 ms
```

`ttl=63` proves PC1's traffic was routed out of VLAN 10 to the server LAN.
`ping web.lab.local` printing `resolved to 10.100.0.12` proves DNS came back
from the server DHCP handed out (10.100.0.10), not from a local hosts file.

## Capture exercise

Two captures were kept:

| File | Link / direction | Filter | What it proves |
|---|---|---|---|
| `wireshark/lab-04-dhcp-dns-http-dora.pcapng` | server side — SRV-DNS `eth0` | `bootp` | the relay worked: full DORA with `giaddr` |
| `wireshark/lab-04-dhcp-dns-http-web.pcapng` | server side — CLIENT `eth0` | `dns \|\| http` | name resolution, then HTTP over TCP |

The DHCP capture is taken on the **server segment** (SRV-DNS `eth0`). From here
every packet is already unicast between the relay and the server, so the
broadcast half of the story has to be read on the client link. The four-frame
exchange:

| Frame | src → dst | UDP | Option 53 | `giaddr` | Message |
|---|---|---|---|---|---|
| 1 | 10.10.10.1 → 10.100.0.10 | 67 → 67 | 1 | 10.10.10.1 | Discover |
| 2 | 10.100.0.10 → 10.10.10.1 | 67 → 67 | 2 | 10.10.10.1 | Offer |
| 3 | 10.10.10.1 → 10.100.0.10 | 67 → 67 | 3 | 10.10.10.1 | Request |
| 4 | 10.100.0.10 → 10.10.10.1 | 67 → 67 | 5 | 10.10.10.1 | ACK |

The relay-carried packet always shows up **sourced from the router**
(`10.10.10.1`) with `giaddr = 10.10.10.1`, which is how dnsmasq knows to hand out
an address from the `10.10.10.0/24` pool even though it lives in `10.100.0.0/24`.
The client source IP is `0.0.0.0` in Discover, then `10.10.10.160` in Request.

The DNS + HTTP capture is 20 frames:

| Frames | What they are |
|---|---|
| 1–2 | DNS query `0x5eb2` `A web.lab.local` → response, `A 10.100.0.12` |
| 3–6 | A + AAAA queries (the resolver also asks for IPv6), same answer / empty |
| 7–9 | TCP three-way handshake `10.100.0.50:46272 → 10.100.0.12:80` |
| 10 | `GET / HTTP/1.1` |
| 12, 14 | `HTTP/1.1 200 OK`, `text/html`, 896-byte body |
| 16–18 | FIN, FIN-ACK, ACK teardown |
| 19–20 | DNS query for `dns.lab.local` → `A 10.100.0.10` |

Answered from the capture:

- [x] The four DORA messages, and which are **broadcast** vs **unicast**: the
      client's DISCOVER/REQUEST are broadcast inside VLAN 10; the relay converts
      them to **unicast** and stamps `giaddr`, so on the server segment all four
      frames are unicast UDP 67 ↔ 67.
- [x] On the server-side capture: `giaddr = 10.10.10.1` — proof the relay worked.
- [x] Option 53 (message type) values for each of the four messages: **1, 2, 3,
      5**.
- [x] The DNS query and response: transaction ID pairing, A record in the answer:
      query `0x5eb2` ↔ response `0x5eb2`, answer `A 10.100.0.12`.
- [x] The TCP handshake before the HTTP `GET`, and the `200 OK` reply: frames
      7–9 are SYN / SYN-ACK / ACK, frame 10 is the `GET`, frames 12/14 are
      `200 OK`.

## Break it / fix it

Diagnose without looking at this file. Time each one.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | Remove `ip helper-address` on R1 | PC1 gets no address | broadcast DISCOVER is not routed; only a relay turns it into unicast to the server | re-add `ip helper-address 10.100.0.10` |
| 2 | Change `dhcp-range` to a different subnet | Offer is for the wrong network | the pool no longer matches the subnet the relay selected via `giaddr` | set `dhcp-range` back to `10.10.10.100,10.10.10.200` |
| 3 | Remove the `dns-server` option | IP works, names fail | DHCP still hands out IP/mask/gw but no option 6, so the host has no resolver | add `dhcp-option=6,10.100.0.10` |
| 4 | Stop SRV-WEB | ping by IP works, HTTP fails | DNS still resolves, but nothing is listening on TCP 80 | start SRV-WEB again |

Fault #1 was run to completion: `no ip helper-address 10.100.0.10` on R1
Gi0/0.10 → PC1 `dhcp -r` then `dhcp` printed **`Can't find dhcp server`** and
could not get a lease (VPCS kept showing the stale `10.10.10.160`) → re-added the
helper-address → `dhcp` immediately returned `DORA` and `10.10.10.160/24` again.
Diagnosed in one move.

## Self-check questions

1. Why are DISCOVER and REQUEST broadcast, but OFFER and ACK often unicast?
2. What does `giaddr` tell the DHCP server, and why is it needed here?
3. Which came first for `curl web.lab.local` — DNS or TCP? Prove it from a capture.

## What I learned

- DORA has four steps, and **only the first broadcast of them needs a relay**;
  the relay rewrites a broadcast into a unicast and stamps `giaddr`.
- `giaddr` is what lets one DHCP server serve many subnets: it is the address of
  the *interface the request arrived on*, so the server picks the matching pool.
- DNS runs **before** TCP: without the A record there is no address for the SYN.
- `ttl=63` after a name lookup shows the name resolved *and* the packet routed.
- A GNS3 Docker node keeps its container across stop/start, so a rebuilt image
  only applies after the container is recreated (or the address set by hand).

## Cleanup

- [x] Configs exported to `configs/lab-04/` (R1.cfg, SW1.cfg)
- [x] Capture saved, trimmed and annotated in `wireshark/`
- [x] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [x] Committed with a specific message
