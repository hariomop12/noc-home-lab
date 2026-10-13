---
tags: [homelab, wireshark, packet-analysis]
status: active
---

# Captures

Packet captures taken in this lab, and the analysis written about them.

How to capture, filter and read traffic in depth:
[../docs/09-wireshark-guide.md](../docs/09-wireshark-guide.md). This file covers
what gets kept, and how it is named.

## Naming

```
lab-NN-name-<what>.pcapng
```

| Example | Meaning |
|---|---|
| `lab-01-basic-lan-arp.pcapng` | Lab 01, the ARP exchange between the two PCs |
| `lab-02-router-two-lans-ttl.pcapng` | Lab 02, TTL decrement across the router |
| `lab-03-vlan-trunk-8021q.pcapng` | Lab 03, tagged frames on the trunk |
| `lab-04-dhcp-dns-http-dora.pcapng` | Lab 04, the full DHCP exchange |

The lab number and the link name come first so that sorting the folder groups
captures by lab automatically.

## Capturing in GNS3

1. Right-click the **link** → **Start capture**.
2. Reproduce the failure exactly once.
3. Stop the capture.
4. Trim to the interesting range, then save as
   `wireshark/lab-NN-name-<what>.pcapng`.
5. Commit it — these files are small and they are evidence.

For captures larger than roughly 10 MB, keep only the filtered, trimmed range.
A 200 MB capture of background chatter is not evidence, it is storage.

## Every capture needs four written lines

Stored next to the capture (in the lab note), without exception:

1. The link it was taken on, and the direction of capture.
2. The display filter used.
3. The packet numbers that constitute the evidence.
4. What those packets prove, in one sentence.

A capture with no written conclusion is not kept.

## Analysis checklist per lab

| Lab | Capture | Filter | What to observe |
|---|---|---|---|
| 01 | ARP request and reply | `arp` | Broadcast request, unicast reply, MAC resolution, why the first ping is slower |
| 01 | ICMP echo | `icmp` | Identifier and sequence pairing requests with replies |
| 02 | Ping across a router | `icmp` | MAC addresses rewritten per hop, TTL decrementing, IP addresses unchanged |
| 02 | Traceroute | `icmp` | Type 11 time-exceeded replies revealing each hop |
| 03 | Trunk versus access port | `vlan` | 802.1Q tag present on the trunk, absent on the access port |
| 03 | Inter-VLAN traffic | `icmp` | Which MAC the sender resolves, and why it is the router's |
| 04 | DHCP DORA | `bootp` | All four messages, option 53 types, `giaddr` proving the relay worked |
| 04 | DNS query and response | `dns` | Transaction ID pairing, A record in the answer |
| 04 | HTTP request and response | `http` | TCP handshake, `GET`, `200 OK` |
| 05 | SSH session | `tcp.port == 22` | Handshake, then encrypted payload |
| 05 | SNMP poll | `snmp` | Get-Request and Get-Response, OID being polled |
| 07 | OSPF hellos | `ospf` | Multicast destination, hello interval, router IDs |
| 07 | NAT in action | `icmp` | Address rewritten between inside and outside captures |

## Advanced exercises

- [ ] Take one ping and build a per-hop table: `frame.number`, `eth.src`,
      `eth.dst`, `ip.src`, `ip.ttl`.
- [ ] Capture the same flow inside and outside NAT and explain every changed byte.
- [ ] Add delay and loss with `tc` in a container, then find the retransmissions
      with `tcp.analysis.flags`.
- [ ] Reconstruct an HTTP request body with *Follow → HTTP Stream*.
- [ ] Write a `tshark` one-liner that lists every DHCP client and the address it
      received, as plain text.

## Related documents

- [../docs/09-wireshark-guide.md](../docs/09-wireshark-guide.md) — the full guide
- [../docs/04-troubleshooting-method.md](../docs/04-troubleshooting-method.md) —
  where a capture fits into a diagnosis
- [../docs/06-linux-cheatsheet.md](../docs/06-linux-cheatsheet.md) — `tcpdump` and
  `tshark` from the command line
