---
tags: [homelab, glossary]
status: active
---

# Glossary

One-line, plain-English definitions of the networking and NOC terms used across this repo.

---

## Fundamentals

- **Host** — Any device with an IP address that sends or receives traffic (PC, server, router interface).
- **Node** — A single point/device in a network or topology diagram.
- **Segment** — A portion of a network that shares a common physical or logical boundary.
- **Broadcast domain** — The set of devices that receive a broadcast frame; bounded by a router (or a VLAN).
- **Collision domain** — The set of devices that can collide when transmitting; a switch port is its own, a hub is one shared.
- **Encapsulation** — Wrapping data with the headers (and trailers) of each layer as it moves down the stack.
- **PDU (Protocol Data Unit)** — The data unit named per OSI layer: frame (L2), packet (L3), segment (L4), bits (L1).
- **Simplex** — One-way communication only.
- **Half-duplex** — Both directions possible, but not at the same time (shared medium).
- **Full-duplex** — Both directions at the same time; standard on modern switched links.
- **Bandwidth** — The maximum theoretical capacity of a link, e.g. 1 Gbps.
- **Throughput** — The actual data rate achieved, always ≤ bandwidth.
- **Latency** — The delay for a packet to travel from source to destination, usually measured in milliseconds.
- **Jitter** — Variation in latency between packets; high jitter hurts voice and video.
- **MTU (Maximum Transmission Unit)** — The largest payload a link can carry in one frame (Ethernet: 1500 bytes by default).
- **MSS (Maximum Segment Size)** — The largest TCP payload in one segment; negotiated from MTU minus IP/TCP headers.
- **Attenuation** — Weakening of a signal over distance or through media.
- **Crosstalk** — Signal from one wire pair leaking into another, causing interference (near-end/far-end forms).

---

## Layer 1 / media

- **UTP (Unshielded Twisted Pair)** — Ordinary copper cabling with twisted pairs and no shielding; common Ethernet media.
- **STP (Shielded Twisted Pair)** — Copper cabling with shielding to reduce interference (not to be confused with Spanning Tree Protocol).
- **Coax (coaxial cable)** — Single-conductor copper cable used by older Ethernet and cable systems.
- **SMF (Single-Mode Fibre)** — Fibre with a small core for long-distance, laser-driven links.
- **MMF (Multimode Fibre)** — Fibre with a larger core for shorter distances, often LED/VCSEL-driven.
- **SFP (Small Form-factor Pluggable)** — A hot-swappable transceiver module that fits a switch/router port to provide a specific media type.
- **RJ45** — The 8-pin connector used for twisted-pair Ethernet.
- **RJ11** — The smaller connector commonly used for telephone lines.
- **Straight-through cable** — Cable wired pin-to-pin, used to connect unlike devices (PC↔switch, router↔switch).
- **Crossover cable** — Cable with transmit/receive pairs swapped, used to connect like devices (switch↔switch, PC↔PC).
- **Rollover cable** — Cisco console cable with pin order reversed end-to-end, used for console access.
- **T568A / T568B** — The two standard RJ45 pin/pair colour-order wirings; either is valid if consistent.
- **PoE (Power over Ethernet)** — Delivering electrical power to a device over the same Ethernet cable as data (e.g. APs, phones, cameras).

---

## Layer 2

- **MAC address** — A 48-bit hardware address burned into a NIC, used for delivery within a LAN.
- **OUI (Organizationally Unique Identifier)** — The first 3 bytes of a MAC address, identifying the manufacturer.
- **Frame** — The Layer 2 PDU, containing source/dest MAC, payload, and FCS.
- **FCS (Frame Check Sequence)** — A 32-bit CRC in the Ethernet trailer used to detect corrupted frames.
- **ARP (Address Resolution Protocol)** — Resolves an IPv4 address to a MAC address on the local segment.
- **VLAN (Virtual LAN)** — A logically separate broadcast domain on a switch, independent of physical ports.
- **802.1Q** — The standard that tags frames with a VLAN ID on a trunk.
- **Native VLAN** — The one VLAN whose frames cross a trunk untagged; both ends must agree.
- **Trunk** — A link that carries traffic for multiple VLANs (tagged).
- **Access port** — A switch port belonging to a single VLAN, usually to an end device.
- **STP (Spanning Tree Protocol)** — Prevents Layer 2 loops by blocking redundant paths.
- **RSTP (Rapid STP)** — The faster modern STP (802.1w) with quicker convergence.
- **BPDU (Bridge Protocol Data Unit)** — The STP control frame that elects the topology and maintains it.
- **Root bridge** — The switch with the lowest bridge ID; the reference point of the STP topology.
- **Port states** — STP states: Blocking, Listening, Learning, Forwarding, Disabled (RSTP: Discarding, Learning, Forwarding).
- **PortFast** — A port setting that skips STP learning states for end-device ports to speed up access.
- **Port security** — Restricts which/all how many MAC addresses may appear on a port.
- **MAC flooding** — An attack that overfills the switch MAC table, forcing it to flood frames.
- **LACP (Link Aggregation Control Protocol)** — The standards-based protocol that bundles links into an EtherChannel.
- **EtherChannel** — Multiple physical links bundled into one logical link for bandwidth and redundancy.
- **VTP (VLAN Trunking Protocol)** — Cisco-proprietary protocol for propagating VLAN databases across switches (use with caution).
- **Broadcast storm** — A feedback loop of broadcasts, typically from a Layer 2 loop, that saturates the network.

---

## Layer 3

- **IPv4** — The 32-bit addressing scheme used for most internet and LAN traffic.
- **Subnet mask** — The mask that separates the network portion of an address from the host portion.
- **CIDR (Classless Inter-Domain Routing)** — Notation that expresses a mask as a prefix length, e.g. `/24`.
- **VLSM (Variable Length Subnet Mask)** — Using different mask lengths for different subnets to save address space.
- **Classful vs classless** — Classful uses fixed A/B/C sizes; classless (CIDR) can use any prefix length.
- **Private IP** — Address ranges (10/8, 172.16/12, 192.168/16) not routable on the public internet.
- **Public IP** — Globally routable addressing assigned/allocated for internet reachability.
- **NAT (Network Address Translation)** — Rewriting IP addresses in transit, typically private to public.
- **PAT (Port Address Translation)** — NAT overload that maps many private addresses to one public address using ports.
- **DHCP (Dynamic Host Configuration Protocol)** — Automatically assigns IP configuration to hosts.
- **DNS (Domain Name System)** — Resolves names to IP addresses and back.
- **ICMP (Internet Control Message Protocol)** — IP's control/error protocol; powers `ping` and `traceroute`.
- **TTL (Time To Live)** — A hop counter that limits a packet's lifetime and prevents loops; decremented at each router.
- **Fragmentation** — Splitting a packet that exceeds the path MTU into smaller pieces.
- **Gateway** — A device that forwards traffic between networks.
- **Default gateway** — The router a host uses for destinations outside its own subnet.
- **Routing table** — The list of known networks and how to reach them.
- **Next hop** — The immediate neighbour address a router forwards a packet to.
- **Administrative distance (AD)** — A trust ranking used to choose between routes learned from different sources.
- **Metric** — The cost used to choose the best route among routes from the same routing protocol.
- **Static route** — A manually configured route that does not change on its own.
- **Dynamic routing** — Protocols that learn and adapt routes automatically.
- **Floating static route** — A backup static route with a higher AD that activates only if the primary fails.
- **IGP (Interior Gateway Protocol)** — A routing protocol used within one organisation (OSPF, EIGRP, RIP).
- **EGP (Exterior Gateway Protocol)** — A routing protocol used between organisations (BGP).
- **OSPF (Open Shortest Path First)** — A link-state IGP that computes shortest paths with Dijkstra's algorithm.
- **Area** — An OSPF grouping of routers/links that limits the scope of link-state flooding.
- **LSA (Link State Advertisement)** — An OSPF message describing a router, network, or route.
- **DR/BDR (Designated/Backup Router)** — Routers elected on a multi-access OSPF segment to reduce adjacencies.
- **EIGRP (Enhanced Interior Gateway Routing Protocol)** — Cisco's advanced distance-vector IGP.
- **RIP (Routing Information Protocol)** — A simple distance-vector IGP using hop count as its metric.
- **BGP (Border Gateway Protocol)** — The path-vector protocol that routes between autonomous systems on the internet.
- **AS number (Autonomous System)** — An identifier for a network/administrative domain in BGP.
- **Peering** — A BGP relationship between two autonomous systems exchanging routes.
- **Redistribution** — Importing routes from one routing protocol into another.
- **Policy routing (PBR)** — Forwarding decisions based on policy (source, port, etc.), not just destination.

---

## Layer 4-7

- **TCP (Transmission Control Protocol)** — Connection-oriented, reliable, ordered transport.
- **UDP (User Datagram Protocol)** — Connectionless, best-effort transport with low overhead.
- **Port numbers** — 16-bit identifiers (0–65535) that select the application/service on a host.
- **3-way handshake** — TCP connection setup: SYN, SYN-ACK, ACK.
- **Windowing** — The amount of unacknowledged data TCP may have in flight.
- **Flow control** — Preventing the receiver from being overrun.
- **Congestion control** — TCP's adaptation to network congestion (slow start, congestion avoidance).
- **Retransmission** — Resending lost/unacknowledged TCP data.
- **Session** — A logical, ongoing exchange between two endpoints.
- **TLS (Transport Layer Security)** — Encrypts and authenticates application traffic (the `S` in HTTPS).
- **HTTP / HTTPS** — Web protocols; HTTPS is HTTP over TLS.
- **FTP (File Transfer Protocol)** — File transfer over TCP (ports 20/21).
- **TFTP (Trivial FTP)** — Lightweight UDP file transfer (port 69), used for images and configs.
- **SSH (Secure Shell)** — Encrypted remote CLI access (port 22).
- **Telnet** — Unencrypted remote CLI access (port 23); avoid.
- **SMTP (Simple Mail Transfer Protocol)** — Sends email between servers (port 25, or 587 for submission).
- **DHCP DORA** — The DHCP exchange: Discover, Offer, Request, Acknowledge.
- **Proxy** — An intermediary that forwards requests on behalf of clients.
- **ACL (Access Control List)** — An ordered list of permit/deny rules that filters traffic.
- **Firewall** — A device/software that enforces traffic policy between zones.
- **Stateful vs stateless** — Stateful tracks connections; stateless evaluates each packet independently.
- **DoS (Denial of Service)** — An attack that exhausts a resource so legitimate users cannot be served.

---

## Network design & operations

- **LAN (Local Area Network)** — A network covering a small area, typically one site.
- **WAN (Wide Area Network)** — A network spanning distant sites, usually over a provider.
- **MAN (Metropolitan Area Network)** — A network covering a city-scale area.
- **CAN (Campus Area Network)** — A network connecting buildings across one campus.
- **PAN (Personal Area Network)** — A very small network around one person (e.g. Bluetooth).
- **DMZ (Demilitarised Zone)** — A buffer subnet hosting externally reachable services, isolated from the internal LAN.
- **Redundancy** — Duplicate components/paths so a single failure does not cause an outage.
- **Failover** — Automatic switch to a standby component or path.
- **HSRP (Hot Standby Router Protocol)** — Cisco first-hop redundancy providing a virtual gateway IP/MAC.
- **VRRP (Virtual Router Redundancy Protocol)** — The standards-based equivalent of HSRP.
- **Load balancing** — Spreading traffic across multiple servers or links.
- **SLA (Service Level Agreement)** — A defined commitment for availability, latency, or response time.
- **MTTR (Mean Time To Repair/Resolve)** — Average time to restore service after a failure.
- **MTTD (Mean Time To Detect)** — Average time from failure to detection.
- **RTO (Recovery Time Objective)** — The target time to restore service after a disruption.
- **Incident vs problem vs change** — An incident is a disruption; a problem is its underlying cause; a change is a planned modification.
- **Escalation** — Moving an issue to a higher tier, another team, or management.
- **Ticket priority (P1–P4)** — Severity ranking of an issue; P1 is the most severe/urgent.
- **RCA (Root Cause Analysis)** — Investigating *why* an incident happened, not just what was fixed.
- **Runbook** — Step-by-step documented procedure for a task or incident.
- **SOP (Standard Operating Procedure)** — A formal, repeatable way of doing a routine task.
- **Change window** — A scheduled period in which changes may be made.
- **Maintenance window** — A planned period during which service (or alerting) is expected to be affected.

---

## Security basics

- **AAA (Authentication, Authorization, Accounting)** — The framework for verifying identity, granting rights, and logging activity.
- **TACACS+** — Cisco-favoured AAA protocol for controlling device administration.
- **RADIUS** — Widely used AAA protocol, common for network and VPN access.
- **Authentication** — Proving who you are.
- **Authorization** — Deciding what you are allowed to do.
- **Accounting** — Recording what you did.
- **Least privilege** — Granting the minimum access needed to do the job.
- **Port security** — Restricting which devices/MACs may connect to a switch port, limiting MAC spoofing and loops.
- **DHCP snooping** — Trusts DHCP only on designated ports, blocking rogue servers.
- **DAI (Dynamic ARP Inspection)** — Validates ARP packets against the DHCP snooping binding, blocking ARP spoofing.
- **BPDU guard** — Shuts a port that receives BPDUs, protecting against rogue switches and loops.
- **ACL direction (in/out)** — Whether an ACL filters traffic entering or leaving an interface, from the device's perspective.
- **VPN (Virtual Private Network)** — An encrypted tunnel over an untrusted network.
- **IPsec** — The standard suite that secures IP traffic (authentication, integrity, encryption).
- **Tunnel mode vs transport mode** — Tunnel mode encrypts the whole original packet (site-to-site); transport mode protects only the payload (host-to-host).
- **PKI (Public Key Infrastructure)** — The system of certificates and authorities that issues and validates keys.
- **RSA** — A widely used public-key algorithm for encryption and signatures.

---

## Monitoring & tooling

- **SNMP (Simple Network Management Protocol)** — Standard protocol for reading device data and receiving events.
- **MIB (Management Information Base)** — The structured database of objects a device exposes over SNMP.
- **OID (Object Identifier)** — The numeric address of one object in the MIB tree.
- **Trap** — An unacknowledged SNMP event sent by a device to a manager.
- **Syslog severity** — The 0–7 scale (emergency … debug) marking a log message's importance.
- **NetFlow** — Flow telemetry describing who talked to whom, used for top-talkers and capacity analysis.
- **Wireshark** — GUI packet analyser for deep protocol inspection.
- **tcpdump** — Command-line packet capture tool.
- **ping** — ICMP echo utility for reachability and basic latency/loss testing.
- **traceroute** — Tool that maps the path to a destination by varying TTL.
- **mtr** — Combines ping and traceroute into a continuous, per-hop view.
- **iperf** — Tool for measuring achievable bandwidth between two hosts.
- **Zabbix** — Open-source monitoring platform (server, agents, proxies, frontend, database).
- **Grafana** — Visualisation and dashboarding tool that graphs data from many sources.
- **NetBox** — Source-of-truth system for documenting IP addresses (IPAM) and devices (DCIM).
