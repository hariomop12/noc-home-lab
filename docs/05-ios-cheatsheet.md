---
tags: [homelab, cheatsheet, ios]
status: active
---

# Cisco IOS Cheat Sheet

Topic-by-topic command reference for the `vios`, `vios_l2` and `c7200` nodes in this lab — one line per command, plus a short example where it helps.

> Examples use the lab IP plan: loopbacks `10.255.0.1` (R1), WAN `/30` chunks from `10.0.0.0/24`, HQ VLANs `10.10.10.0/24` (HR), `10.10.20.0/24` (SALES), `10.10.40.0/24` (SERVERS), `10.10.99.0/24` (MGMT), servers `10.100.0.0/16`. Password convention: enable secret / local user `Cisco123`, domain `lab.local`.

## 1. Navigation & modes

| Command | What it does | When you use it |
|---|---|---|
| `enable` | Move from user exec (`>`) to privileged exec (`#`) | Need `show`/`debug`/config access |
| `disable` | Drop from privileged exec back to user exec | Hand the console to someone with less access |
| `configure terminal` | Enter global config mode (`(config)#`) | Start any configuration |
| `interface GigabitEthernet0/0` | Enter interface config mode (`(config-if)#`) | Change a port |
| `line vty 0 4` | Enter line config mode (`(config-line)#`) | Configure SSH/telnet login |
| `exit` | Step back one level | Move up the mode hierarchy |
| `end` | Jump straight to privileged exec | Leave all config modes at once |
| `do <exec cmd>` | Run a privileged-exec command from config mode | `do show ip interface brief` without leaving config |

```text
R1> enable
R1# configure terminal
R1(config)# interface GigabitEthernet0/0
R1(config-if)# do show ip interface brief
R1(config-if)# exit
R1(config)# end
R1#
```

## 2. Context saving & reload safety

| Command | What it does | When you use it |
|---|---|---|
| `show running-config` | Show the active config in RAM | Confirm your changes before saving |
| `show startup-config` | Show the saved config in NVRAM | Check what will come back after reload |
| `copy running-config startup-config` | Save RAM config to NVRAM (`copy run start` works) | Whenever changes should survive a reload |
| `write memory` | Legacy save (`wr`) — same effect as `copy run start` | Older images / muscle memory |
| `show version` | IOS version, uptime, config register | Verify image and `0x2102` register |
| `show flash:` | List files in flash | Find IOS image / archived configs |
| `reload` | Reboot the device | ⚠️ Reboots immediately — save first |
| `boot system flash:<image>` | Set which image to load at boot | Only if multiple images in flash |

⚠️ `reload` and `write erase` are irreversible. `write erase` deletes the startup config — always `show startup-config` first.

## 3. Interface basics

| Command | What it does | When you use it |
|---|---|---|
| `show ip interface brief` | One-line IP/status per interface | First command for "is the link up?" |
| `show interfaces` | Full counters, errors, MTU, duplex | Deep link inspection |
| `show interfaces GigabitEthernet0/0` | Detail for one port | Focus on a suspect link |
| `description WAN to R2` | Label a port in the config | Document what each link is |
| `no shutdown` | Admin-enable an interface | Interfaces are `shutdown` by default |
| `speed auto` / `speed 1000` | Set port speed | Match a device that won't auto-negotiate |
| `duplex full` / `duplex auto` | Set duplex | Fix half/full duplex mismatch |
| `show controllers GigabitEthernet0/0` | Physical layer / clock info | Suspect cabling or serial clocking |
| `show interfaces GigabitEthernet0/0 \| include errors` | Show only error lines | Spot CRC / input errors fast |

```text
R1# show interfaces GigabitEthernet0/0
GigabitEthernet0/0 is up, line protocol is up
  ...
  0 input errors, 0 CRC, 0 frame, 0 overrun, 0 ignored
```

Increasing `CRC` / `input errors` = physical/cabling problem (ticket R6).

## 4. Layer 2 switching

| Command | What it does | When you use it |
|---|---|---|
| `show mac address-table` | MAC-to-port mapping | See which port learned a host |
| `show vlan brief` | VLANs and their member ports | Confirm VLAN/port assignment |
| `show interfaces switchport` | Access/trunk mode, VLANs, native VLAN | Verify port role before blaming the far end |
| `switchport mode access` | Force a port to access mode | Endpoint/PC ports |
| `switchport mode trunk` | Force a port to trunk mode | Switch-to-switch / uplink ports |
| `switchport access vlan 10` | Put an access port in a VLAN | Connect a PC to HR/SALES/IT |
| `switchport trunk allowed vlan 10,20,99` | Restrict which VLANs cross a trunk | Least-privilege trunk |
| `switchport trunk allowed vlan add 40` | Add one VLAN to an existing list | Grow a trunk without replacing the list |
| `switchport trunk native vlan 99` | Set the untagged VLAN on a trunk | Match native VLAN on both ends |
| `switchport nonegotiate` | Stop DTP on the port | Hardening a fixed trunk |
| `vlan 10` / `name HR` | Create/name a VLAN in the VLAN database | Define VLANs before assigning ports |
| `interface vlan 99` | Create/enter an SVI | Give a switch an IP for management |

```text
SW1(config)# vlan 99
SW1(config-vlan)# name MGMT
SW1(config)# interface GigabitEthernet0/1
SW1(config-if)# switchport mode access
SW1(config-if)# switchport access vlan 10
```

## 5. Spanning Tree

| Command | What it does | When you use it |
|---|---|---|
| `show spanning-tree` | Root bridge, roles, states per VLAN | Confirm the topology you expect |
| `spanning-tree mode rapid-pvst` | Use Rapid-PVST+ | Modern default in this lab |
| `spanning-tree portfast` | Skip listening/learning on an access port | Endpoint ports only |
| `spanning-tree portfast default` | Portfast on all access ports (global) | Global policy, then disable where needed |
| `spanning-tree bpduguard enable` | Err-disable a port that receives BPDUs | Access ports facing hosts |
| `spanning-tree portfast bpduguard default` | BPDU guard on all portfast ports (global) | Scalable access-edge protection |
| `spanning-tree vlan 10 root primary` | Force this switch to be root for VLAN 10 | Deterministic root selection |
| `spanning-tree vlan 10 root secondary` | Backup root for VLAN 10 | Redundancy |

```text
SW1(config)# spanning-tree mode rapid-pvst
SW1(config)# spanning-tree vlan 10 root primary
SW1(config)# interface GigabitEthernet0/1
SW1(config-if)# spanning-tree portfast
SW1(config-if)# spanning-tree bpduguard enable
```

## 6. EtherChannel

| Command | What it does | When you use it |
|---|---|---|
| `channel-protocol lacp` | Force LACP (or `pagp`) on the port | Pick the negotiation protocol |
| `channel-group 1 mode active` | LACP active — creates/joins bundle 1 | Preferred LACP bundle |
| `channel-group 1 mode passive` | LACP passive — waits for the far end | When you can't change the far side |
| `channel-group 1 mode desirable` | PAgP desirable (Cisco-only) | Legacy Cisco-to-Cisco links |
| `channel-group 1 mode on` | Static bundle, no negotiation | Both ends already agree |
| `show etherchannel summary` | Per-bundle member/port state | Verify members are `(P)` bundled |
| `show etherchannel 1 port-channel` | Load-balancing / member detail | Tune or debug a bundle |

```text
SW1(config)# interface range GigabitEthernet0/1 - 2
SW1(config-if-range)# channel-protocol lacp
SW1(config-if-range)# channel-group 1 mode active

SW1# show etherchannel summary
```

## 7. IPv4 addressing & verification

| Command | What it does | When you use it |
|---|---|---|
| `ip address 10.10.10.1 255.255.255.0` | Assign an IPv4 address | Every routed interface / loopback |
| `show ip interface brief` | Address + status per interface | Fast addressing check |
| `show ip interface GigabitEthernet0/0` | Full IP detail incl. applied ACLs | Verify up/down and inbound/outbound filters |
| `ping 10.100.0.10` | ICMP echo test | Basic reachability |
| `ping` (no args) | Extended ping — pick source/repeat/size | Test from a specific loopback |
| `traceroute 200.1.1.1` | Hop-by-hop path | Find where traffic stops |
| `show arp` | IP-to-MAC cache | Same-subnet resolution check |
| `arp 10.10.10.5 0050.7966.6800 arpa` | Static ARP entry | Test/pin a MAC in the lab |

```text
R1(config)# interface Loopback0
R1(config-if)# ip address 10.255.0.1 255.255.255.255

R1# ping 10.255.0.2
```

## 8. Static routing

| Command | What it does | When you use it |
|---|---|---|
| `ip route 10.20.0.0 255.255.0.0 10.0.0.2` | Static route to a prefix via next hop | Small/simple topologies, BR sites |
| `ip route 0.0.0.0 0.0.0.0 10.0.0.14` | Default route toward the ISP | Last-resort gateway |
| `ip route 0.0.0.0 0.0.0.0 10.0.0.18 10` | Floating static (higher AD) | Backup path if the primary fails |
| `show ip route` | Full routing table | Confirm the best path |
| `show ip route static` | Only static routes | Filter the table |

```text
R1(config)# ip route 0.0.0.0 0.0.0.0 10.0.0.14
R1(config)# ip route 0.0.0.0 0.0.0.0 10.0.0.18 10
```

Route code legend (`show ip route`):

| Code | Meaning |
|---|---|
| `C` | Connected |
| `L` | Local (interface address /32) |
| `S` | Static |
| `S*` | Candidate default static |
| `O` | OSPF |
| `O IA` | OSPF inter-area |
| `O E1` / `O E2` | OSPF external |
| `D` | EIGRP |
| `D EX` | EIGRP external |
| `R` | RIP |
| `B` | BGP |
| `*` | Candidate default |

## 9. OSPF

| Command | What it does | When you use it |
|---|---|---|
| `router ospf 1` | Enter OSPF process 1 | Enable OSPF |
| `router-id 10.255.0.1` | Set the router ID | Stable, loopback-based RID |
| `network 10.10.10.0 0.0.0.255 area 0` | Advertise a prefix (wildcard mask) | Add interfaces to OSPF |
| `passive-interface GigabitEthernet0/0` | Stop Hellos on a LAN/edge port | No neighbors expected there |
| `passive-interface default` + `no passive-interface Gi0/1` | Passive unless explicitly enabled | Safer default posture |
| `default-information originate` | Advertise the default route into OSPF | Give OSPF domains an exit |
| `show ip ospf neighbor` | Neighbor states (FULL, 2WAY, EXSTART…) | First OSPF troubleshooting step |
| `show ip ospf interface brief` | Per-interface area, cost, state | Verify area/interface membership |
| `show ip route ospf` | Only OSPF-learned routes | Confirm advertisements arrived |

```text
R1(config)# router ospf 1
R1(config-router)# router-id 10.255.0.1
R1(config-router)# network 10.255.0.1 0.0.0.0 area 0
R1(config-router)# network 10.0.0.0 0.0.0.3 area 0
R1(config-router)# passive-interface GigabitEthernet0/0
R1(config-router)# default-information originate
```

Neighbor stuck not at `FULL` = MTU mismatch (`EXSTART`), subnet/area mismatch, or timers.

## 10. EIGRP basics

| Command | What it does | When you use it |
|---|---|---|
| `router eigrp 10` | Enter EIGRP AS 10 | Enable EIGRP |
| `network 10.0.0.0 0.255.255.255` | Advertise a range (wildcard) | Add interfaces to EIGRP |
| `network 10.0.0.0` | Classful form — advertises that classful net | Quick lab setup |
| `no auto-summary` | Disable classful summarization at boundaries | Always in modern designs |
| `show ip eigrp neighbors` | Neighbor table | Verify adjacencies |
| `show ip protocols` | Active routing protocols and networks | Confirm what is being advertised |
| `show ip route eigrp` | Only EIGRP-learned routes | Check installed EIGRP routes |

```text
R1(config)# router eigrp 10
R1(config-router)# no auto-summary
R1(config-router)# network 10.0.0.0 0.255.255.255
R1(config-router)# network 10.255.0.1 0.0.0.0
```

## 11. RIP basics

| Command | What it does | When you use it |
|---|---|---|
| `router rip` | Enter RIP config | Enable RIP |
| `version 2` | Use RIPv2 (classless, multicast) | Always for v2 |
| `network 10.0.0.0` | Enable RIP on interfaces in that classful net | RIP takes no wildcard mask |
| `no auto-summary` | Disable classful summarization | Required at discontiguous boundaries |
| `show ip rip database` | RIP's own route database | Inspect what RIP knows |
| `show ip protocols` | Confirm RIP is running and its networks | Sanity check |

```text
R1(config)# router rip
R1(config-router)# version 2
R1(config-router)# no auto-summary
R1(config-router)# network 10.0.0.0
```

RIP `network` statements are classful only — no masks, no `area`.

## 12. Access Control Lists (ACLs)

| Command | What it does | When you use it |
|---|---|---|
| `access-list 10 permit 10.10.10.0 0.0.0.255` | Numbered standard ACL (source only) | Permit/deny a whole subnet |
| `access-list 100 permit tcp 10.10.10.0 0.0.0.255 10.10.40.0 0.0.0.255 eq 443` | Numbered extended ACL | Filter by protocol/port |
| `ip access-list standard HR_ACCESS` | Named standard ACL | Readable, editable rules |
| `ip access-list extended BLOCK_SALES_HR` | Named extended ACL | Source + destination + port |
| `ip access-group 100 in` | Apply an ACL to an interface/direction | Enforce the rules |
| `show access-lists` | All ACLs and hit counts | Verify rules match |
| `show ip interface GigabitEthernet0/0` | Shows inbound/outbound applied ACLs | Confirm which ACL is live |

```text
R1(config)# ip access-list extended BLOCK_SALES_HR
R1(config-ext-nacl)# deny ip 10.10.20.0 0.0.0.255 10.10.10.0 0.0.0.255
R1(config-ext-nacl)# permit ip any any

R1(config)# interface GigabitEthernet0/1
R1(config-if)# ip access-group BLOCK_SALES_HR in
```

Every ACL ends with an implicit `deny any`. Add an explicit `permit ip any any` when you mean it.

## 13. NAT

| Command | What it does | When you use it |
|---|---|---|
| `ip nat inside` | Mark an interface as the inside | LAN-facing interface |
| `ip nat outside` | Mark an interface as the outside | ISP-facing interface |
| `ip nat inside source static 10.10.40.12 200.1.1.12` | One-to-one static NAT | Publish an internal server |
| `ip nat inside source static tcp 10.100.0.12 80 200.1.1.12 80` | Static port forwarding | Expose one service only |
| `ip nat inside source list 1 interface GigabitEthernet0/1 overload` | PAT (many-to-one) using ACL 1 | LAN shares one public IP |
| `show ip nat translations` | Active translation table | See live flows |
| `show ip nat statistics` | Counters, interfaces, hit rates | Capacity/debugging |
| `clear ip nat translation *` | Clear all translations | ⚠️ Drops active sessions |

```text
R1(config)# access-list 1 permit 10.10.0.0 0.0.255.255

R1(config)# interface GigabitEthernet0/1
R1(config-if)# ip nat inside
R1(config)# interface GigabitEthernet0/0
R1(config-if)# ip nat outside

R1(config)# ip nat inside source list 1 interface GigabitEthernet0/0 overload
```

## 14. DHCP

| Command | What it does | When you use it |
|---|---|---|
| `ip dhcp excluded-address 10.10.10.1 10.10.10.99` | Reserve addresses the pool must not hand out | Keep gateways/infra static |
| `ip dhcp pool HR_POOL` | Create/enter a DHCP pool | Define a scope |
| `network 10.10.10.0 255.255.255.0` | Pool subnet | Match the VLAN subnet |
| `default-router 10.10.10.1` | Gateway option handed to clients | Relay/routing for clients |
| `dns-server 10.100.0.10` | DNS option handed to clients | Point clients at SRV-DNS |
| `lease 0 8` | Lease time (days hours) | Short leases for lab churn |
| `ip helper-address 10.100.0.10` | Relay DHCP on an interface to a server | Server on another subnet |
| `show ip dhcp binding` | Current leases | Who has which IP |
| `show ip dhcp conflict` | Address conflicts detected | Diagnose duplicate IPs |

```text
R1(config)# ip dhcp excluded-address 10.10.10.1 10.10.10.99
R1(config)# ip dhcp pool HR_POOL
R1(dhcp-config)# network 10.10.10.0 255.255.255.0
R1(dhcp-config)# default-router 10.10.10.1
R1(dhcp-config)# dns-server 10.100.0.10

R1(config)# interface Vlan10
R1(config-if)# ip helper-address 10.100.0.10
```

## 15. DNS & name resolution on IOS

| Command | What it does | When you use it |
|---|---|---|
| `ip name-server 10.100.0.10` | Set DNS server(s) for name lookup | Use SRV-DNS for `lab.local` |
| `ip domain-lookup` | Enable DNS resolution (`no ip domain-lookup` disables) | Disable to stop typo hangs on console |
| `ip host r1 10.255.0.1` | Static hostname-to-IP mapping | Local name for a device |
| `ip domain-name lab.local` | Set the domain / SSH key suffix | Required for RSA keys |
| `show hosts` | Cached and static host entries | Verify resolution config |

```text
R1(config)# ip domain-name lab.local
R1(config)# ip name-server 10.100.0.10
R1(config)# ip host srv-web 10.100.0.12
R1# ping srv-web
```

## 16. Device hardening / management plane

| Command | What it does | When you use it |
|---|---|---|
| `enable secret Cisco123` | Hashed privileged-exec password | Always (never `enable password`) |
| `username admin privilege 15 secret Cisco123` | Local user with full rights | SSH login account |
| `service password-encryption` | Weakly encrypts plaintext passwords in config | Stop casual config reads |
| `line vty 0 4` | Enter the SSH/telnet lines | Configure remote login |
| `transport input ssh` | Allow SSH only on VTY lines | Turn off telnet |
| `login local` | Authenticate VTY logins against local users | Use the `username` above |
| `ip domain-name lab.local` | Domain for the RSA key | Before key generation |
| `crypto key generate rsa modulus 2048` | Generate the SSH RSA keypair | Enables SSH |
| `ip ssh version 2` | Use SSHv2 only | Harden remote access |
| `exec-timeout 10 0` | Idle timeout (minutes seconds) | Auto-logout idle sessions |
| `logging synchronous` | Reprint the prompt after log lines | Stop logs breaking your typing |

```text
R1(config)# enable secret Cisco123
R1(config)# username admin privilege 15 secret Cisco123
R1(config)# service password-encryption
R1(config)# ip domain-name lab.local
R1(config)# crypto key generate rsa modulus 2048
R1(config)# ip ssh version 2
R1(config)# line vty 0 4
R1(config-line)# transport input ssh
R1(config-line)# login local
R1(config-line)# exec-timeout 10 0
R1(config-line)# logging synchronous
```

## 17. Logging, NTP, SNMP

| Command | What it does | When you use it |
|---|---|---|
| `logging host 10.100.0.11` | Send syslog to SRV-SYSLOG | Central logging |
| `logging trap informational` | Set the severity level sent | Control log volume |
| `logging buffered 16384` | Keep logs in a local RAM buffer | Read history with `show logging` |
| `service timestamps log datetime msec localtime` | Precise, local-time log stamps | Readable correlation |
| `show logging` | Show the local log buffer | Recent events on the device |
| `clock timezone IST 5 30` | Set the timezone | Before NTP |
| `ntp server 10.100.0.13` | Point at SRV-NTP | Get accurate time |
| `show ntp status` | Sync state (`synchronized`?) | Confirm NTP works |
| `snmp-server community public RO` | Read-only SNMP v2c community (lab only) | Let Zabbix poll |
| `snmp-server host 10.100.0.21 version 2c public` | Send traps to the Zabbix server | Trap-based alerting |
| `show snmp` | SNMP counters and settings | Verify SNMP config |

```text
R1(config)# clock timezone IST 5 30
R1(config)# ntp server 10.100.0.13
R1(config)# logging host 10.100.0.11
R1(config)# logging trap informational
R1(config)# snmp-server community public RO
R1(config)# snmp-server host 10.100.0.21 version 2c public
```

## 18. Configuration management

| Command | What it does | When you use it |
|---|---|---|
| `copy running-config tftp:` | Back the config up to a TFTP/`SRV` host | Off-device backup |
| `copy tftp: running-config` | Pull a config from a server | Restore |
| `archive` | Enter archive config mode | Set up automatic rollback points |
| `path flash:/archive` | Where archives are stored | Keep history in flash |
| `maximum 5` | how many archives to keep | Cap flash usage |
| `show archive` | List stored archives | Pick a rollback point |
| `configure replace flash:/archive/... force` | Roll the running config back to an archive | ⚠️ Replaces running config |

```text
R1(config)# archive
R1(config-archive)# path flash:/archive
R1(config-archive)# maximum 5
R1(config-archive)# time-period 1440
R1# show archive
```

## 19. Router-on-a-stick & inter-VLAN

| Command | What it does | When you use it |
|---|---|---|
| `interface GigabitEthernet0/0` | Parent (physical) interface | One physical link carrying all VLANs |
| `no shutdown` | Bring the parent up | Subinterfaces won't work if the parent is down |
| `interface GigabitEthernet0/0.10` | Create a subinterface | One subinterface per VLAN |
| `encapsulation dot1q 10` | Tag this subinterface with VLAN 10 | Match the switch trunk VLAN |
| `ip address 10.10.10.1 255.255.255.0` | Gateway address for the VLAN | Default gateway for that VLAN |
| `encapsulation dot1q 99 native` | Native (untagged) VLAN on the subinterface | Match the trunk's native VLAN |

```text
R1(config)# interface GigabitEthernet0/0
R1(config-if)# no shutdown

R1(config)# interface GigabitEthernet0/0.10
R1(config-subif)# encapsulation dot1q 10
R1(config-subif)# ip address 10.10.10.1 255.255.255.0

R1(config)# interface GigabitEthernet0/0.20
R1(config-subif)# encapsulation dot1q 20
R1(config-subif)# ip address 10.10.20.1 255.255.255.0
```

## 20. First-hop redundancy (HSRP)

| Command | What it does | When you use it |
|---|---|---|
| `standby 1 ip 10.10.10.1` | Define the virtual gateway IP (group 1) | Clients point here |
| `standby 1 priority 150` | Set election priority (higher wins) | Make one router active |
| `standby 1 preempt` | Reclaim active role when it returns | Deterministic failback |
| `standby 1 track GigabitEthernet0/1 50` | Lower priority if the tracked link fails | Automatic failover |
| `show standby brief` | One-line HSRP state per group | Fast health check |
| `show standby` | Detailed HSRP state and timers | Deep debugging |

```text
R1(config)# interface Vlan10
R1(config-if)# ip address 10.10.10.2 255.255.255.0
R1(config-if)# standby 1 ip 10.10.10.1
R1(config-if)# standby 1 priority 150
R1(config-if)# standby 1 preempt
R1(config-if)# standby 1 track GigabitEthernet0/1 50

R1# show standby brief
```

## 21. Generic show / debug commands

| Command | What it does | When you use it |
|---|---|---|
| `show version` | IOS, uptime, register, serials | Inventory/health |
| `show ip protocols` | Running routing protocols | Verify what a router runs |
| `show cdp neighbors` | Cisco Discovery Protocol neighbors | Map directly-connected Cisco devices |
| `show lldp neighbors` | LLDP neighbors | Vendor-neutral link mapping |
| `show clock` | Current device time | Time/NTP checks |
| `show users` | Who is logged in on which line | Console/VTY awareness |
| `show processes cpu sorted` | Top CPU consumers | High-CPU troubleshooting (ticket R4) |
| `terminal monitor` | Show log output on a VTY/SSH session | Watch logs remotely |
| `debug ip icmp` | Live-debug ICMP packets | Short, targeted packet tracing |
| `undebug all` | Turn off all debugging (`no debug all`) | Immediately after any debug |

⚠️ **Debug safety:** `debug` runs in the CPU path — on a busy device it can overload the processor and drop traffic. Never leave `debug` on, never run `debug all`, always set a plan to `undebug all`, and prefer ACL-scoped or conditional debugs. On a remote session, `terminal monitor` is required before you will see debug output.

## How this maps to this lab

| Lab | Most useful sections |
|---|---|
| Lab 01 — Basic LAN (2 PC + switch) | 3 Interface basics · 4 Layer 2 switching · 7 IPv4 verification |
| Lab 02 — Router + 2 LANs | 2 Save/reload · 3 Interface basics · 7 IPv4 · 8 Static routing |
| Lab 03 — VLAN + Trunk + Inter-VLAN | 4 Layer 2 switching · 5 Spanning Tree · 6 EtherChannel · 19 Router-on-a-stick |
| Lab 04 — DHCP + DNS + HTTP | 7 IPv4 · 13 NAT · 14 DHCP · 15 DNS |
| Lab 05 — Network Management | 16 Hardening · 17 Logging/NTP/SNMP · 18 Config management · 21 Debug safety |
