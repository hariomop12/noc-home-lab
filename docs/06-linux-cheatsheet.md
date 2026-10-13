---
tags: [homelab, cheatsheet, linux, networking]
status: active
---

# Linux Networking Cheat Sheet

Command reference for the Docker-based servers in this lab (dnsmasq, nginx, rsyslog, chrony, Zabbix, busybox) and for troubleshooting from a Linux host.

> Examples use the lab IP plan: SRV-DNS `10.100.0.10`, SRV-SYSLOG `10.100.0.11`, SRV-WEB `10.100.0.12`, SRV-NTP `10.100.0.13`, Zabbix `10.100.0.20/21/22/23`, HQ gateway `10.10.0.0/16`, domain `lab.local`.

## 1. Interfaces

| Command | What it does | When you use it |
|---|---|---|
| `ip link show` | List interfaces and their state | Check if a link is `UP`/`DOWN` |
| `ip -br link show` | Brief one-line-per-interface list | Fast overview |
| `ip addr show` | Interfaces with IPv4/IPv6 addresses | Full addressing view |
| `ip -br addr` | Brief address list (name, state, address) | Go-to first command |
| `ip link set eth0 up` / `down` | Bring an interface up or down | ⚠️ `down` drops your session if it's your uplink |
| `ip addr add 10.100.0.10/24 dev eth0` | Add an IP address | Static addressing in a container |
| `ip addr del 10.100.0.10/24 dev eth0` | Remove an IP address | Clean up / re-address |
| `ethtool eth0` | Speed, duplex, link detected | Check negotiated link settings |
| `ethtool -i eth0` | Driver and firmware info | Identify the NIC driver |
| `ethtool -g eth0` | Ring buffer sizes | Tuning/drops investigation |
| `ethtool -S eth0` | Per-NIC statistics | Errors, drops, queues |
| `ip -s link show eth0` | RX/TX counters incl. errors and drops | Check for L1/L2 problems |

```bash
ip -br addr
# eth0   UP   10.100.0.10/24
ip addr add 10.100.0.10/24 dev eth0
ip link set eth0 up
ethtool -S eth0 | grep -i -E 'err|drop'
```

## 2. Routes

| Command | What it does | When you use it |
|---|---|---|
| `ip route show` | Show the main routing table | Check where traffic will go |
| `ip -br route` | Compact route list | Quick review |
| `ip route add 10.20.0.0/16 via 10.10.0.1` | Add a static route | Reach a remote subnet |
| `ip route add default via 10.10.0.1` | Add/replace the default route | Set the gateway |
| `ip route del default` | Remove the default route | ⚠️ Cuts off-routed connectivity |
| `ip route show table all` | All tables (main, local, default) | See VRF/rule-based routes |
| `ip rule show` | Policy-routing rules | Understand which table wins |
| `ip route get 8.8.8.8` | Which interface/source a path would use | Confirm the chosen route and source IP |

Route tables live in `/etc/iproute2/rt_tables`: `main` (254), `local` (255), `default` (253).

```bash
ip route add 10.20.0.0/16 via 10.10.0.1
ip route add default via 10.10.0.1
ip route get 8.8.8.8
```

## 3. Neighbours / ARP

| Command | What it does | When you use it |
|---|---|---|
| `ip neigh show` | IPv4/IPv6 neighbour (ARP) cache | Check L2 resolution |
| `ip -s neigh show` | Neighbour cache with use/confirm counters | Spot stale entries |
| `arp -a` | Legacy ARP view (`net-tools`) | Familiar output |
| `ip neigh del 10.10.10.5 dev eth0` | Delete one neighbour entry | Force re-resolution |
| `ip neigh flush dev eth0` | Flush the whole cache on an interface | Clear stale entries |

```bash
ip neigh show
# 10.10.10.1 dev eth0 lladdr 0c:1d:2e:3f:40:51 REACHABLE
ip neigh flush dev eth0
```

## 4. DNS

| Command | What it does | When you use it |
|---|---|---|
| `dig web.lab.local` | Full DNS query for a name | Verify a record |
| `dig +short web.lab.local` | Just the answer | Scripting / quick check |
| `dig @10.100.0.10 web.lab.local` | Query a specific server | Test SRV-DNS directly |
| `dig -x 10.100.0.12` | Reverse (PTR) lookup | Check reverse records |
| `resolvectl status` | System resolver config per link | See effective DNS servers |
| `nslookup web.lab.local 10.100.0.10` | Simple query against a server | Familiar alternative |
| `cat /etc/resolv.conf` | Resolver file the libc uses | Check configured nameservers |
| `cat /etc/hosts` | Local static name mappings | Override DNS locally |
| `getent hosts web.lab.local` | Resolve the way libc does (honours `/etc/hosts`) | Match application behaviour |

Split-DNS concept: internal names (`lab.local`) resolve via SRV-DNS `10.100.0.10`, while public names go to an external resolver — point the right clients at the right server.

```bash
dig +short web.lab.local
dig @10.100.0.10 srv-web.lab.local
resolvectl status
```

## 5. DHCP client / server

| Command | What it does | When you use it |
|---|---|---|
| `dhclient eth0` | Request a DHCP lease | Get an address |
| `dhclient -r eth0` | Release the current lease | ⚠️ Drops the address |
| `ip addr show eth0` | Shows `dynamic` on DHCP-obtained addresses | Confirm the lease is dynamic |
| `journalctl -u dnsmasq -f` | Follow the dnsmasq log live | Watch DHCP/DNS activity |
| `cat /var/lib/misc/dnsmasq.leases` | Current dnsmasq lease file | See who holds which lease |

Basic dnsmasq config (SRV-DNS):

```text
# /etc/dnsmasq.conf
interface=eth0
dhcp-range=10.100.0.100,10.100.0.200,255.255.255.0,12h
dhcp-option=3,10.100.0.1
dhcp-option=6,10.100.0.10
dhcp-option=42,10.100.0.13
domain=lab.local
```

Common options: `3` = router/gateway, `6` = DNS server, `42` = NTP server.

Client lease files: `/var/lib/dhcp/dhclient.leases` (Debian/Ubuntu) or `/var/lib/dhclient/dhclient.leases` (RHEL family).

```bash
dhclient eth0
journalctl -u dnsmasq -f
```

## 6. Reachability testing

| Command | What it does | When you use it |
|---|---|---|
| `ping -c 4 10.100.0.10` | Send 4 ICMP echoes | Basic reachability |
| `ping -I eth0 10.100.0.10` | Ping from a chosen interface | Bind the source interface |
| `ping -I 10.100.0.10 10.100.0.13` | Ping from a chosen source IP | Match a specific source |
| `ping -M do -s 1472 10.100.0.10` | Don't fragment, 1472-byte payload (1472+28 = 1500) | Path-MTU testing |
| `fping -a -g 10.100.0.0/24` | Ping-sweep a whole subnet, print live hosts | Quick host discovery |
| `arping -I eth0 10.10.10.1` | ARP-level reachability on the LAN | Test L2 before L3 |
| `mtr 8.8.8.8` | Live traceroute + packet-loss per hop | Find the lossy hop |
| `traceroute -n 8.8.8.8` | UDP/traceroute path | Classic path trace |
| `tracepath 8.8.8.8` | Path trace without root, reports MTU | Unprivileged path/MTU test |

```bash
ping -c 4 10.100.0.10
ping -M do -s 1472 10.100.0.10   # works only if path MTU >= 1500
tracepath 8.8.8.8
```

## 7. Sockets & ports

| Command | What it does | When you use it |
|---|---|---|
| `ss -tulnp` | TCP/UDP listening sockets with PID (no resolve) | Which process owns a port |
| `ss -tan state established` | Only established TCP sockets | See active connections |
| `ss -tanp \| grep :80` | Filter to port 80 | Web check |
| `lsof -i :80` | Process holding port 80 | Detailed owner info |
| `lsof -i -P -n` | All network files, no name resolution | Broad open-connections view |
| `fuser 80/tcp` | PID bound to TCP 80 | Quick owner lookup |
| `netstat -tulnp` | Legacy equivalent of `ss` (`net-tools`) | Only if `ss` is unavailable |

```bash
ss -tulnp
ss -tan state established
lsof -i :80
```

`netstat` is deprecated — prefer `ss`, which is faster and reads kernel state directly.

## 8. Packet capture

| Command | What it does | When you use it |
|---|---|---|
| `tcpdump -i any -n -v` | Capture all interfaces, no DNS, verbose | Broad live capture |
| `tcpdump -i eth0 -n icmp` | Only ICMP | Diagnose ping/reachability |
| `tcpdump -i any -n port 53` | Only DNS | Trace name resolution |
| `tcpdump -i any -n port 67 or port 68` | Only DHCP DORA | Watch leases |
| `tcpdump -i any -n arp` | Only ARP | L2 resolution issues |
| `tcpdump -i any -n tcp port 80` | Only HTTP | Web traffic |
| `tcpdump -i eth0 -n -w /tmp/cap.pcapng` | Write packets to a file | Capture for Wireshark |
| `tcpdump -r /tmp/cap.pcapng -n` | Read a captured file | Review offline |

```bash
tcpdump -i any -n -v port 53
tcpdump -i eth0 -n -w /tmp/cap.pcapng port 67 or port 68
tcpdump -r /tmp/cap.pcapng -n
```

Load `cap.pcapng` into Wireshark for decode and follow-stream. `tshark` one-liners:

```bash
tshark -i eth0 -n -V -Y icmp
tshark -r /tmp/cap.pcapng -Y dns -T fields -e dns.qry.name
```

## 9. Bandwidth & latency emulation

| Command | What it does | When you use it |
|---|---|---|
| `tc qdisc add dev eth0 root netem delay 100ms` | Add 100 ms one-way delay | Simulate a slow WAN |
| `tc qdisc add dev eth0 root netem loss 5%` | Drop 5% of packets | Simulate a bad link |
| `tc qdisc change dev eth0 root netem delay 100ms 20ms distribution normal` | Add jitter | Realistic latency variation |
| `tc qdisc show dev eth0` | Show current qdisc | Confirm the fault is active |
| `tc qdisc del dev eth0 root` | Remove the qdisc | Clean up after the test |

```bash
tc qdisc add dev eth0 root netem delay 100ms loss 5%
tc qdisc show dev eth0
tc qdisc del dev eth0 root
```

This is how you inject faults for ticket R7 (high latency / packet loss) without touching the real topology.

## 10. Performance / traffic

| Command | What it does | When you use it |
|---|---|---|
| `iperf3 -s` | Run an iperf3 server | Receive a bandwidth test |
| `iperf3 -c 10.100.0.11` | Run a TCP bandwidth test to a host | Measure throughput |
| `iperf3 -c 10.100.0.11 -u -b 10M` | UDP test at 10 Mbit/s | Measure loss/jitter |
| `iftop -i eth0` | Live per-connection bandwidth | See who is generating traffic |
| `nethogs eth0` | Bandwidth per process | Find the noisy process |
| `vnstat -l` | Live interface traffic rate | Long-term + live stats |
| `sar -n DEV 1` | Interface counters every 1s | Historical/periodic sampling |

```bash
# on SRV-SYSLOG
iperf3 -s
# on SRV-WEB
iperf3 -c 10.100.0.11
```

## 11. Bridges, veth and Docker networking

| Command | What it does | When you use it |
|---|---|---|
| `ip link add veth0 type veth peer name veth1` | Create a virtual cable (two endpoints) | Wire namespaces/containers together |
| `ip link add br0 type bridge` | Create a software L2 bridge | Build a virtual switch |
| `ip link set br0 up` | Bring the bridge up | Activate it |
| `ip link set veth1 master br0` | Attach an interface to the bridge | Add a port to the switch |
| `bridge link show` | Bridge port state/flags | Verify bridge membership |
| `docker network create --subnet 10.100.0.0/16 labnet` | Create a user-defined bridge network | Give containers a controlled subnet |
| `docker network ls` | List networks | Inventory |
| `docker network inspect labnet` | Network detail: subnet, gateway, members | Verify addressing |
| `docker run --network labnet --ip 10.100.0.10 nginx` | Attach a container with a fixed IP | Reproduce the lab IP plan |
| `docker run -p 8080:80 nginx` | Publish a container port on the host | Reach a container from outside |
| `docker exec -it srv-dns ip addr` | Run a command inside a container | Inspect container networking |

```bash
ip link add br0 type bridge
ip link set br0 up
ip link set veth1 master br0
docker network create --subnet 10.100.0.0/16 labnet
docker exec -it srv-dns ip -br addr
```

Containers need a bridge (or equivalent) because each container is its own network namespace with only a `veth` pair — the bridge gives them a shared L2 segment and a gateway, exactly like a physical switch.

## 12. Firewall basics

| Command | What it does | When you use it |
|---|---|---|
| `nft list ruleset` | Show all nftables rules | Modern default view |
| `iptables -L -n -v` | Show filter rules with counters | Classic rule inspection |
| `iptables -t nat -L -n -v` | Show NAT rules | Check masquerade/redirect |
| `ufw status verbose` | Simple firewall status | Ubuntu-style front-end |
| `ufw allow 22/tcp` | Permit SSH | Open a port |
| `sysctl net.ipv4.ip_forward` | Check IP forwarding | Needed for routing/NAT |

```bash
# NAT / masquerade: rewrite source for outbound traffic
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# Port redirect: send inbound 80 to a local 8080
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
```

Docker writes its own `DOCKER`/`DOCKER-USER` chains, so published container ports can bypass `ufw` rules — check `iptables -t nat` before trusting `ufw status`.

## 13. Services & logs

| Command | What it does | When you use it |
|---|---|---|
| `systemctl status dnsmasq` | Service state and recent log lines | Check a service is up |
| `systemctl restart nginx` | Restart a service | Apply config changes |
| `systemctl enable --now chronyd` | Enable at boot and start now | Persistent time sync |
| `journalctl -u rsyslog` | Logs for one unit | Per-service debugging |
| `journalctl -f` | Follow the system journal live | Watch events as they happen |
| `journalctl --since "10 min ago"` | Time-windowed logs | Recent incidents |
| `timedatectl` | Time, timezone, NTP sync state | Time sanity check |
| `timedatectl set-timezone Asia/Kolkata` | Set the timezone | Match device `clock timezone` |
| `chronyc sources` | NTP sources and their state | Verify time sync |
| `chronyc tracking` | Offset/drift detail | Fine-grained NTP check |

rsyslog config locations: main file `/etc/rsyslog.conf`, drop-ins in `/etc/rsyslog.d/*.conf` (that's where a lab rule sending `*.* @@10.100.0.11:514` for TCP, or `@` for UDP, would go).

```bash
systemctl status dnsmasq
journalctl -u dnsmasq -f
chronyc sources
```

## 14. Handy one-liners

```bash
# Which interface owns an IP?
ip -br addr | grep 10.100.0.10

# Is a remote port open? (either form)
nc -zv 10.100.0.12 80
timeout 2 bash -c '</dev/tcp/10.100.0.12/80' && echo OPEN || echo CLOSED

# Capture a full DHCP DORA exchange
tcpdump -i any -n -v port 67 or port 68

# Follow one HTTP request
curl -v http://web.lab.local/

# Resolve then ping
ping -c 2 "$(dig +short web.lab.local)"

# Measure path MTU (repeat with smaller -s until it answers)
ping -M do -s 1472 -c 1 8.8.8.8

# Watch live dnsmasq leases
watch -n 2 'cat /var/lib/misc/dnsmasq.leases'

# What is listening right now, with owners?
sudo ss -tulnp
```

## How this maps to this lab

| Lab | Most useful sections |
|---|---|
| Lab 01 — Basic LAN (2 PC + switch) | 1 Interfaces · 3 Neighbours/ARP · 6 Reachability (arping, ping) |
| Lab 02 — Router + 2 LANs | 2 Routes · 3 Neighbours · 6 Reachability (mtr, tracepath) |
| Lab 03 — VLAN + Trunk + Inter-VLAN | 1 Interfaces · 2 Routes · 11 Bridges/veth |
| Lab 04 — DHCP + DNS + HTTP | 4 DNS · 5 DHCP · 8 Packet capture · 13 Services (dnsmasq, nginx) |
| Lab 05 — Network Management | 7 Sockets/ports · 9 tc netem · 10 Traffic · 12 Firewall · 13 Services/logs (rsyslog, chrony) |
