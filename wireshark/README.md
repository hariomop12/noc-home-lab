---
tags: [homelab, wireshark, packet-analysis]
status: active
---

# Wireshark Captures

Har capture ka naam: `<lab-NN-naam>-<kya>.pcapng` → `lab-01-basic-lan-arp.pcapng`

## Kaise capture karein (GNS3)

1. Link pe **right-click → Start capture** (ya link pe right-click → packet capture).
2. `Save as` → `wireshark/lab-NN-naam-<kya>.pcapng`.
3. `.pcapng` **commit karo** — chhoti file hoti hai, aur proof ke kaam aati hai.
4. Bade capture (>10 MB) skip karo — sirf filter kiya hua interesting part save karo.

## Kya dekhna hai — lab-wise checklist

| Lab | Capture | Filters | Kya observe karna hai |
|---|---|---|---|
| 01 | ARP request/reply | `arp` | MAC kaise resolve hota hai, broadcast domain |
| 01 | ICMP ping | `icmp` | TTL, CSMA/CD vs switch forwarding |
| 02 | ICMP across router | `icmp` | Naya L2 header per hop, MAC change, TTL decrement |
| 03 | VLAN trunk | `vlan` | 802.1Q tag, native VLAN untagged |
| 04 | DORA | `bootp` (`udp.port==67`) | Discover → Offer → Request → ACK |
| 04 | DNS query | `dns` | Query + response, A record |
| 04 | HTTP GET | `http` | TCP handshake → GET → 200 OK |
| 05 | SSH session | `tcp.port==22` | TCP handshake, encrypted payload |
| 05 | SNMP poll | `snmp` | Get-Request/Response OID |
| 07 | OSPF hello | `ospf` | Hello, DR/BDR election |
| 07 | NAT/PAT | `ip.addr==200.1.1.x` | Private IP → public translation |

## Level-2 exercises (khud karo)

- [ ] Ek hi ping me: `frame.number`, `eth.src`, `ip.src`, `ip.ttl` — per-hop table banao
- [ ] ARP cache poison jaisa scene dekho — kya badla (educational only)
- [ ] TCP retransmission / duplicate ACK wala capture banao (`tc` se loss add karke)
- [ ] Follow TCP Stream → HTTP request/response padho

## Tips

- Useful filters: `icmp`, `arp`, `dns`, `bootp`, `ospf`, `bgp`, `tcp.flags.syn==1`, `tcp.analysis.flags`
- Name resolution off karo (`View → Name Resolution`) — MAC/IP plain dikhenge
- Time delta column on karo — latency samajhne ke liye
