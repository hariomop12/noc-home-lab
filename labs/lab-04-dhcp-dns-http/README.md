---
lab: 04
level: micro
status: not-started
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

| Template name | Image | `LAB_IP` | `LAB_GW` |
|---|---|---|---|
| `SRV-DNS` | `dnsmasq:lab` | `10.100.0.10/24` | `10.100.0.1` |
| `SRV-WEB` | `web:lab` | `10.100.0.12/24` | `10.100.0.1` |
| `CLIENT` | `noc-tools:lab` | `10.100.0.50/24` | `10.100.0.1` |

Console type **telnet**. The `LAB_IP` / `LAB_GW` environment variables are what
make each server come up already addressed.

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
| 1 | `show ip` on PC1 | address 10.10.10.100-200, gw .1, dns 10.100.0.10 | |
| 2 | `ping 10.100.0.1` from PC1 | server-LAN gateway reachable | |
| 3 | `ping web.lab.local` from PC1 | resolves to 10.100.0.12 and replies | |
| 4 | `dig web.lab.local @10.100.0.10` on CLIENT | A record 10.100.0.12 | |
| 5 | `curl -s web.lab.local` on CLIENT | nginx page returned | |

If row 1 fails, nothing else can pass — fix DHCP first.

## Capture exercise

Capture on: **SW1 Gi0/1 ↔ PC1** (the client link) and **R1 Gi0/1** (the server link).
Save as: `wireshark/lab-04-dhcp-dns-http-dora.pcapng`.
Filter: `bootp` (DHCP), then `dns`, then `http`.

Answer from the capture:

- [ ] The four DORA messages, and which are **broadcast** vs **unicast**.
- [ ] On the server-side capture: `giaddr = 10.10.10.1` — proof the relay worked.
- [ ] Option 53 (message type) values for each of the four messages.
- [ ] The DNS query and response: transaction ID pairing, A record in the answer.
- [ ] The TCP handshake before the HTTP `GET`, and the `200 OK` reply.

## Break it / fix it

Diagnose without looking at this file. Time each one.

| # | What to break | Symptom you should see | Root cause | Fix |
|---|---|---|---|---|
| 1 | Remove `ip helper-address` on R1 | PC1 gets no address | | |
| 2 | Change `dhcp-range` to a different subnet | Offer is for the wrong network | | |
| 3 | Remove the `dns-server` option | IP works, names fail | | |
| 4 | Stop SRV-WEB | ping by IP works, HTTP fails | | |

## Self-check questions

1. Why are DISCOVER and REQUEST broadcast, but OFFER and ACK often unicast?
2. What does `giaddr` tell the DHCP server, and why is it needed here?
3. Which came first for `curl web.lab.local` — DNS or TCP? Prove it from a capture.

## What I learned

-

## Cleanup

- [ ] Configs exported to `configs/lab-04/`
- [ ] Capture saved, trimmed and annotated in `wireshark/`
- [ ] Status flipped in `labs/README.md`, main `README.md`, skill matrix
- [ ] GNS3 project closed (not suspended)
- [ ] Committed with a specific message
