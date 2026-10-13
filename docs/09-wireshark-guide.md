---
tags: [homelab, wireshark, packet-analysis, reference]
status: active
---

# 09 — Wireshark Guide

Wireshark is the single most useful tool in this lab. A router's `show` command
tells you what the device *thinks* is happening. A capture tells you what is
actually on the wire.

This document is the deep version: how to capture, how to filter, how to read a
packet layer by layer, and how to answer a question with evidence instead of
memory.

## 1. What Wireshark is, and what it is not

| It is | It is not |
|---|---|
| A protocol decoder and traffic analyser | A network scanner — it cannot find hosts |
| Passive — it decodes what already reached your NIC | An intrusion detection system |
| A tool for proving a hypothesis | A tool for "just looking around" |
| Useful only when you have a specific question | Faster than reading the config |

Two consequences shape everything below:

1. **You only see traffic that reaches the capture point.** A capture on PC1 will
   never show the frame on the SW1-to-R1 link. Choosing where to capture is the
   first real decision, not an afterthought.
2. **A capture without a question produces a wall of packets and no knowledge.**
   Decide what you are trying to prove before pressing start.

## 2. Install and permissions

Wireshark is already installed on this machine. Verify and check capture
permissions:

```bash
wireshark --version          # expect 4.x
tshark --version             # the CLI twin, useful for scripting
groups | grep wireshark      # capture without sudo requires this group
```

On Debian/Ubuntu, non-root capture is granted to the `wireshark` group. If you
are not in it:

```bash
sudo dpkg-reconfigure wireshark-common   # answer Yes to non-superuser capture
sudo usermod -aG wireshark "$USER"
# then log out and back in
```

This user is already in the `wireshark` group, so it should work as-is.

If capture fails with *permission denied*, the group membership is the first
thing to check — not the interface list.

## 3. Where to capture in this lab

### Primary method: capture the GNS3 link

Right-click the link in GNS3 → **Start capture**. Wireshark opens automatically.

This is the method used by every lab here, because it lets you capture on an
exact link — the trunk between two switches, the WAN link, the router's LAN
interface — without caring about which host the traffic came from.

The capture file is written into the GNS3 project directory. Move the interesting
part into `wireshark/` in this repository, named per the rules in
[wireshark/README.md](../wireshark/README.md).

### Alternative: capture inside a container

When the traffic of interest never leaves a container, or when you want the
container's own view:

```bash
docker exec -it noc-tools sh
tcpdump -i eth0 -n -w /tmp/cap.pcapng
# copy out
docker cp <container>:/tmp/cap.pcapng ./
```

This is how you capture on a server's NIC rather than on the wire between it and
the switch.

### Alternative: capture on the host

Only meaningful when the topology is bridged to a host interface. Two cautions:

- The host sees traffic for every container and every process, so use a capture
  filter.
- Bridging a lab to a physical NIC puts lab traffic on the real network. Avoid it
  unless the exercise requires it.

### What the capture point changes

| Capture point | You see | You do not see |
|---|---|---|
| PC1 → SW1 access port | Untagged Ethernet, no VLAN information | The VLAN tag, which is stripped at the access port |
| SW1 → SW2 trunk | The 802.1Q tag, including the VLAN ID | Nothing of interest is missing |
| R1 LAN interface | The frame as the router received it | What happened after NAT |
| R1 WAN interface | Post-NAT addresses | Original private addresses |

Capturing the same flow on two links and comparing is the fastest way to make
NAT, MAC rewriting and TTL decrement click.

## 4. First look: the three panes

| Pane | Contains | What you use it for |
|---|---|---|
| Packet list | One row per packet | Scanning, sorting, finding the suspicious row |
| Packet details | The dissection tree, collapsed by protocol | Reading the actual fields |
| Packet bytes | The raw hexadecimal and ASCII | Proving what the bytes really say, seeing padding |

The default columns matter more than people expect:

| Column | Meaning | Watch for |
|---|---|---|
| No. | Packet number in the capture | Reference number for notes |
| Time | Timestamp, mode is configurable | Switching modes is how latency is measured |
| Source / Destination | Address of the outermost relevant layer | The field changes meaning between L2 and L3 views |
| Protocol | Highest layer dissected | "TCP" here often hides a higher protocol |
| Length | Frame size on the wire | Large frames, tiny ACKs, fragmentation |
| Info | Summary | The first place to spot an anomaly |

**Time display format is the most underrated setting.** Right-click the time
column → *Time Display Format*:

| Mode | Use it for |
|---|---|
| Seconds Since Beginning of Capture | Overall shape of the capture |
| Seconds Since Previous Displayed Packet | Gaps — where did the silence come from |
| Time of Day | Correlating against a device log or a syslog entry |

That last pairing — capture timestamp against syslog timestamp — is only possible
if NTP is working, which is why Lab 05 exists.

## 5. The workflow that produces answers

1. **State the question.** "Why does PC1's ping to 10.10.20.10 fail?" Not "let's
   capture some traffic".
2. **Choose the capture point** that will show the answer. Between the source and
   the suspected fault, closest to the fault.
3. **Apply a capture filter** so the file stays small and readable.
4. **Reproduce the failure** once, cleanly. Long captures hide short problems.
5. **Stop the capture** before analysing. Do not analyse a live capture.
6. **Filter down** to the flow: `ip.addr == 10.10.10.100`.
7. **Read one packet completely**, outermost layer inward.
8. **Follow the stream** if it is a conversation, to see the outcome.
9. **Write the answer down**, with the packet number as evidence.

Step 9 is what turns a capture into knowledge. A capture nobody wrote about is a
file that will be deleted in a week.

## 6. Capture filters (BPF)

Applied *before* the capture starts, and cannot be changed afterwards. They
reduce what is recorded.

| Filter | Meaning |
|---|---|
| `host 10.10.10.100` | Any traffic to or from that host |
| `net 10.10.10.0/24` | Any traffic within that subnet |
| `port 53` | Any traffic to or from port 53 |
| `tcp port 80` | TCP on port 80 only |
| `ether host aa:bb:cc:dd:ee:ff` | Filter by MAC |
| `icmp` | ICMP only |
| `arp` | ARP only |
| `vlan 10` | Tagged VLAN 10 traffic |
| `not arp and not stp` | Silence the constant background chatter |
| `ip proto 89` | OSPF |
| `host 10.10.10.100 and port 67` | Combining conditions with `and` |

Why capture filters still matter even though display filters exist: on a busy or
looping link, an unfiltered capture can drop packets, and dropped packets look
exactly like packets that were never sent. Never let a resource limit create
false evidence.

Sensible default for a lab capture:

```
not arp and not stp and not cdp and not lldp
```

## 7. Display filters

The real power. Applied after capture, changeable at any time, never lose data.

### Syntax essentials

| Construct | Example | Meaning |
|---|---|---|
| Equality | `ip.addr == 10.10.10.1` | Match a value (also accepts `eq`) |
| Inequality | `ip.ttl != 64` | Not equal (`ne`) |
| Compare | `frame.len > 1000` | Numeric comparison |
| Contains | `dns.qry.name contains "lab.local"` | Substring match on a byte sequence |
| Matches | `http.host matches "lab"` | Regular expression |
| And / or / not | `icmp && ip.src == 10.10.10.100` | Logic; `and`, `or`, `!` also work |
| In set | `tcp.port in {80, 443, 8080}` | Membership |
| Slice | `eth.dst[0:3] == 01:00:5e` | Byte range within a field |
| Field existence | `tcp.options` | True if the field is present |

### The filters used most in this lab

| Task | Display filter |
|---|---|
| All traffic for one host | `ip.addr == 10.10.10.100` |
| One direction only | `ip.src == 10.10.10.100 && ip.dst == 10.10.20.10` |
| One MAC address | `eth.addr == aa:bb:cc:dd:ee:ff` |
| ARP requests only | `arp.opcode == 1` |
| ARP replies only | `arp.opcode == 2` |
| Ping requests / replies | `icmp.type == 8` / `icmp.type == 0` |
| DHCP only | `bootp` |
| DHCP Discover / Offer / Request / ACK | `bootp.option.dhcp == 1` / `2` / `3` / `5` |
| DHCP for one client MAC | `bootp.hw.mac_addr == aa:bb:cc:dd:ee:ff` |
| DNS queries | `dns.flags.response == 0` |
| A specific DNS name | `dns.qry.name contains "web.lab.local"` |
| TCP handshake start | `tcp.flags.syn == 1 && tcp.flags.ack == 0` |
| Connections being reset | `tcp.flags.reset == 1` |
| One TCP conversation | `tcp.stream eq 0` |
| Retransmissions and other problems | `tcp.analysis.flags` |
| HTTP requests only | `http.request` |
| A specific HTTP method | `http.request.method == "GET"` |
| Tagged VLAN traffic | `vlan.id == 10` |
| Spanning Tree | `stp` |
| OSPF | `ospf` |
| TTL anomalies | `ip.ttl < 10` |
| Frames larger than expected | `frame.len > 1000` |

### Capture filter versus display filter: do not mix them up

| | Capture filter | Display filter |
|---|---|---|
| When applied | Before capture | Any time |
| Syntax | BPF (`host`, `port`, `and`) | Wireshark fields (`ip.addr ==`, `&&`) |
| Effect of a mistake | Packets never recorded — evidence lost forever | Nothing lost, just fix the filter |
| Use it for | Keeping the file small on busy links | All actual analysis |

A common beginner mistake is typing `ip.addr == 10.10.10.1` into the capture
filter box and getting a syntax error, or typing `port 53` into the display
filter and matching nothing.

## 8. Reading one packet properly

Work outward-in, every time. Reading a packet is a checklist, not an act of
intuition.

| Layer | What to check | Why it matters |
|---|---|---|
| Frame | Number, length, capture timestamp | Reference point for notes |
| Ethernet II | Source and destination MAC | Which physical devices are involved at this hop |
| 802.1Q (if present) | VLAN ID, priority | Which broadcast domain this frame belongs to |
| IPv4 | Source, destination, TTL, protocol, flags, fragmentation | Routing, direction of travel, MTU problems |
| TCP / UDP | Ports, flags, sequence and acknowledgement numbers, window | Which application, and the state of the conversation |
| Payload | The actual protocol fields | The answer to the original question |

Habits that make this fast:

- **Use the "source" column and the dissection together.** The column shows the
  outermost relevant address; the tree shows every layer's addresses, which is
  how you see a NAT translation in a single packet.
- **Expand only what you need.** A raw dump of every field is unreadable.
- **Right-click a field → Apply as Column** when a field matters repeatedly
  (`tcp.stream`, `ip.ttl`, `vlan.id` are the usual candidates).
- **Click a field and read the status bar.** It shows the protocol and field name,
  which is the fastest way to learn filter names.

## 9. Protocol walkthroughs

The protocols that appear in this lab, and specifically what to look at.

### ARP

Filter: `arp`

| Packet | Purpose | Fields to read |
|---|---|---|
| Request | "Who has 10.10.10.100?" | Opcode 1, target IP, sender MAC, destination MAC is `ff:ff:ff:ff:ff:ff` |
| Reply | "10.10.10.100 is at aa:bb:cc:dd:ee:ff" | Opcode 2, sender IP and MAC, sent unicast |

Why it matters: ARP is the bridge between Layer 3 and Layer 2. If a host has no
ARP entry, it cannot send anything, which is why the very first ping is slower
than the second. Lab 01 makes you watch exactly that.

### ICMP

Filter: `icmp`

| Field | Meaning | Classically used for |
|---|---|---|
| Type 8 / 0 | Echo request / reply | `ping` |
| Type 11 | Time exceeded | `traceroute` |
| Type 3 | Destination unreachable, with a code | "Why is it failing" — code 1 is host unreachable, code 3 is port unreachable |
| TTL | Hop limit | Every router decrements it — proof of how many hops were crossed |
| Identifier and sequence | Request/reply pairing | Which reply belongs to which request |

If you see a reply with the same identifier but a different source address, then
you have found a NAT translation.

### DHCP (DORA)

Filter: `bootp`

| Step | Message type | Notes |
|---|---|---|
| Discover | `bootp.option.dhcp == 1` | Client has no address, so source `0.0.0.0`, destination broadcast |
| Offer | `bootp.option.dhcp == 2` | Server proposes an address |
| Request | `bootp.option.dhcp == 3` | Client asks for the offered address |
| ACK | `bootp.option.dhcp == 5` | Server confirms |

Fields worth reading: transaction ID (groups the exchange), `bootp.option.router`
(option 3), `bootp.option.dns` (option 6), lease time, and `bootp.giaddr`.

`bootp.giaddr` is the star of the relay lab. When a router relays the request,
`giaddr` carries the client's own subnet, which is how a server on a different
network knows which pool to use. Seeing a non-zero `giaddr` is proof that the
relay worked.

### DNS

Filter: `dns`

| Field | Meaning |
|---|---|
| Transaction ID | Pairs the query with its response |
| Flags | Query versus response, recursion desired/available, and the reply code |
| Questions | The name and type being asked for |
| Answers | The resolved records |

Note that a single name lookup often produces **two** queries — one for the A
record and one for the AAAA (IPv6) record. That is normal, not a fault.

A useful troubleshooting pattern: if you see the query leave and no response
come back, the problem is upstream of the client. If no query appears at all, the
client is not even trying — usually the wrong DNS server in its configuration.

### TCP

Filter: `tcp`

| Stage | Flags | What proves the connection works |
|---|---|---|
| Open | SYN → SYN, ACK → ACK | All three packets present. A SYN followed by RST means the port is closed; a SYN with no answer means it was filtered |
| Data | PSH, ACK | Sequence numbers advance by exactly the number of payload bytes |
| Close | FIN, ACK | Graceful teardown |
| Abort | RST | Something refused the connection — read the preceding packet |

The display filter `tcp.analysis.flags` highlights the problems Wireshark has
already detected: retransmissions, duplicate acknowledgements, zero windows,
out-of-order segments. Treat it as a starting point and then confirm the cause by
reading the sequence numbers.

### HTTP

Filter: `http`

`http.request` shows requests only. A healthy request/response pair looks like:

```
GET /index.html HTTP/1.1      → 200 OK
```

Reading the headers is often where the answer is: a `301` redirect, a `404` for a
missing file, a `500` from the server. HTTPS will not be readable this way — see
section 16.

### 802.1Q (VLAN tags)

Filter: `vlan`

| Field | Meaning |
|---|---|
| TPID | Usually `0x8100`, marks the frame as tagged |
| Priority (PCP) | 3-bit class of service |
| DEI | Drop eligible indicator |
| VLAN ID | 12 bits, the actual VLAN |

Two facts this makes visible: on an access port the tag does not exist at all,
and on a trunk the **native VLAN** frames pass untagged. Comparing those two
captures simultaneously makes VLAN tagging stop being abstract.

### Spanning Tree

Filter: `stp`

BPDUs arrive roughly every two seconds and are switched, not routed. Read the
root bridge ID and the timer values. A capture full of topology change
notifications suggests a flapping link.

### OSPF

Filter: `ospf`

| Message type | Purpose |
|---|---|
| Hello | Neighbour discovery, sent to `224.0.0.5` |
| Database Description | Summarising the topology database |
| Link State Request / Update | Exchanging topology details |

If neighbours stay in EXSTART, capture both sides and compare — mismatched MTU
or a stuck DD exchange is visible here and invisible in a config diff.

### NAT and PAT

Capture the same flow on the inside and the outside interfaces and compare.

| Inside capture | Outside capture |
|---|---|
| Source `10.10.10.100` | Source `200.1.1.x` (the translated address) |
| Private addresses visible | Private addresses gone |
| Checksums computed over the original header | Checksums recomputed after translation |

This comparison is the clearest possible proof that NAT is working, and the
clearest possible diagnosis when it is not.

## 10. Time analysis

Three questions, three views:

| Question | Method |
|---|---|
| How long did the whole thing take? | Time since beginning of capture, read at the last packet |
| Where was the delay? | Time since previous displayed packet — look for the large gap |
| Does this match the device log? | Absolute time of day, compared against syslog |

A 2-second gap before a DHCP Offer, or a 1.5-second gap before a TCP SYN/ACK, is
a finding. A finding needs a number attached to it.

## 11. Statistics: the underused menu

| Menu item | Answers |
|---|---|
| Conversations | Who is talking to whom, and how much. Sorted by bytes, the top talker is usually obvious |
| Protocol Hierarchy | What percentage of the capture is broadcast noise, and what percentage is real traffic |
| Endpoints | Which single host is generating the most traffic |
| IO Graph | Throughput over time. A flat line during a "slow network" complaint is a finding in itself |
| Service Response Time | Time between a request and its response, per protocol |
| Flow Graph | The whole conversation as a sequence diagram, including the time axis |
| Expert Information | Wireshark's own list of anomalies — a fast first pass, never the conclusion |

Sorting Conversations by bytes and Protocol Hierarchy by percentage answers "what
is actually on this wire" in about ten seconds.

## 12. Expert Information

`Analyze → Expert Information` groups findings into severity levels: errors,
warnings, notes and chats. It is a good first pass and a bad last word — Wireshark
flags symptoms, not causes. A retransmission warning is real; whether it caused
the user's problem is a question only you can answer.

## 13. Following and reconstructing

| Action | Right-click on | Gives you |
|---|---|---|
| Follow → TCP Stream | A TCP packet | The whole conversation, in order, as text |
| Follow → UDP Stream | A UDP packet | Same, for connectionless traffic |
| Follow → HTTP Stream | An HTTP packet | Request and response, headers included |
| Apply as Filter → Selected | Any field | Turns a field into a display filter — the fastest way to isolate a flow |
| Export Objects → HTTP | Any HTTP packet | Files transferred over plain HTTP |

Follow Stream is how you go from "something is wrong" to "here is exactly what the
two sides said to each other".

## 14. Coloring rules

Default colours are meaningful, and the most useful one is the black background
with red text, which marks TCP problems.

To add your own: `View → Coloring Rules`. A rule is a filter plus a colour. Useful
candidates for this lab:

| Rule name | Filter | Colour |
|---|---|---|
| ARP | `arp` | light blue |
| DHCP | `bootp` | light green |
| DNS | `dns` | light yellow |
| ICMP errors | `icmp.type == 3 \|\| icmp.type == 11` | red text |
| My test host | `ip.addr == 10.10.10.100` | bold |

## 15. Profiles and columns

**Profiles** (`Edit → Configuration Profiles`) let you keep a separate column
layout and filter set per task — one for Layer 2 switching, one for routing, one
for DHCP and DNS. Switching profiles is switching mindset.

**Columns worth adding** (right-click a field → Apply as Column):

| Field | Why |
|---|---|
| `tcp.stream` | Groups a conversation without filtering |
| `tcp.flags` | Shows SYN/ACK/RST at a glance while scrolling |
| `ip.ttl` | Shows hop count, and catches routing loops |
| `vlan.id` | Makes VLAN membership visible in the list |
| `arp.opcode` | Request versus reply without expanding |
| `dns.qry.name` | The name being resolved, right in the list |

## 16. Decrypting TLS (honest version)

HTTPS is encrypted. Without keys you see the TCP conversation and nothing inside
it — no URL, no headers, no body. That is the point of the protocol.

You can decrypt in two situations:

| Situation | Method |
|---|---|
| You control the client | Set the `SSLKEYLOGFILE` environment variable, then point Wireshark at that file (`Preferences → Protocols → TLS → (Pre)-Master-Secret log filename`) |
| You hold the server's private RSA key | Configure it in the TLS dissector — only works for key exchange that does not use forward secrecy |

What will not work: decrypting someone else's traffic by "putting Wireshark on the
network". Anyone claiming otherwise is describing a different tool.

For this lab, the useful habit is simpler: use plain HTTP (port 80) when you want
to study application behaviour, and treat HTTPS as a black box whose *timing and
volume* you can still measure.

## 17. Speed and workflow tips

### Keyboard shortcuts worth memorising

| Shortcut | Action |
|---|---|
| `Ctrl+E` | Start or stop capture |
| `Ctrl+K` | Capture options |
| `Ctrl+Shift+R` | Restart current capture |
| `Ctrl+G` | Go to a specific packet number |
| `Ctrl+F` / `Ctrl+B` | Find packet / find next |
| `Ctrl+Shift+F` | Find next in the current filter |
| `Ctrl+Alt+1..9` | Apply a filter bookmark |
| `Ctrl+M` | Mark packet (a manual bookmark) |

### Bookmarks

`Ctrl+Alt+1` through `9` store display filters. Put the five filters you type
most on the first five keys and stop retyping them.

### tshark for scripting

The same engine, on the command line:

```bash
# Read a file with a display filter, one line per packet
tshark -r captures/lab-01-basic-lan-arp.pcapng -Y "arp" -T fields \
       -e frame.number -e eth.src -e arp.opcode -e arp.src.proto_ipv4

# Only DHCP message types, summarised
tshark -r cap.pcapng -Y "bootp" -T fields \
       -e frame.number -e bootp.option.dhcp -e bootp.ip.your

# Follow a TCP stream as text
tshark -r cap.pcapng -q -z follow,tcp,ascii,0
```

`tshark` is how a capture becomes data instead of a picture.

### Long or busy captures

```bash
# Ring buffer: 100 MB files, 10 of them, dropping the oldest
dumpcap -i eth0 -b filesize:102400 -b files:10 -w /tmp/lab.pcapng

# Truncate each frame to 128 bytes when only headers matter
dumpcap -i eth0 -s 128 -w /tmp/headers.pcapng
```

Using `dumpcap` rather than the Wireshark GUI for long captures avoids losing
packets to the interface redrawing.

### Display filter macros and buttons

A filter button (`Edit → Preferences → Filter Buttons`) turns a frequently used
filter into a one-click button. Worth doing for `tcp.analysis.flags`.

## 18. When Wireshark itself looks broken

| Symptom | Cause | Fix |
|---|---|---|
| No interfaces listed | Missing group membership, or running in a container | Check `groups`, re-login |
| "Permission denied" on capture | Not in the `wireshark` group | `dpkg-reconfigure wireshark-common`, re-login |
| Packets missing from a busy capture | Capture dropping under load | Use `dumpcap` with a capture filter and a ring buffer |
| Checksum errors on every packet | Checksum offloading — the NIC computes checksums after the capture point | Normal on a host capture. Ignore unless testing checksum behaviour |
| "Unreassembled" or truncated frames | Snaplen too small, or a genuine fragmentation problem | Check the `-s` value and read the IP flags |
| Timestamps look impossible | Mixed time zones, or clocks not synchronised | Fix NTP first, then re-capture |
| Traffic you expected is absent | Wrong capture point | Re-read section 3 |
| `tcp.port == 53` matches nothing but DNS is clearly present | DNS is UDP here — use `dns`, or `udp.port == 53` | Prefer the protocol name over the port |

## 19. Captures in this repository

Naming: `wireshark/lab-NN-name-<what>.pcapng`, for example
`lab-03-vlan-trunk-8021q-on-trunk.pcapng`.

For each capture kept, the same four lines are recorded in the lab note:

1. Which link it was taken on, and which direction.
2. The display filter used.
3. Which packet numbers are the evidence.
4. What those packets prove, in one sentence.

A capture with no written conclusion is not saved in this repository. It is a
reminder of an afternoon, not knowledge.

## 20. Skill ladder

Work through these in order. Each one is done when the answer can be given with a
packet number.

| # | Task | Done means |
|---|---|---|
| 1 | Capture an ARP request and reply | Can name the sender MAC, target IP and why the request is broadcast |
| 2 | Capture a ping and explain why packet 1 differs from packet 2 | Can point at the ARP exchange in between |
| 3 | Capture across a router | Can show TTL decrementing and the MAC address changing |
| 4 | Capture a trunk and an access port on the same flow | Can show the tag present on one and absent on the other |
| 5 | Capture a full DHCP DORA | Can name all four packets and the option numbers used |
| 6 | Capture a DNS query and its response | Can name the transaction ID pairing them |
| 7 | Capture a TCP handshake and teardown | Can name the flags and prove the sequence numbers advance by the payload size |
| 8 | Capture a plain HTTP request | Can read the method, the host header and the status code |
| 9 | Capture the same flow inside and outside NAT | Can show the address rewrite between the two |
| 10 | Capture OSPF hellos | Can name the multicast address, the interval and the router IDs |
| 11 | Use Expert Information on a capture with a fault | Can name the fault and explain why Wireshark flagged it |
| 12 | Use Statistics → Conversations to find a top talker | Can name the host and the protocol |
| 13 | Use Flow Graph on a failed connection | Can point at the packet where it went wrong |
| 14 | Write a `tshark` one-liner that extracts a field from a capture | Output is text that could be pasted into a report |
| 15 | Diagnose a fault using only a capture | Root cause stated, with evidence, in under 15 minutes |

## 21. Cheat block

The twenty filters that cover most of the work:

```
ip.addr == 10.10.10.100
ip.src == 10.10.10.100 && ip.dst == 10.10.20.10
eth.addr == aa:bb:cc:dd:ee:ff
arp
icmp
icmp.type == 3
bootp
dns
dns.qry.name contains "lab.local"
tcp.flags.syn == 1 && tcp.flags.ack == 0
tcp.flags.reset == 1
tcp.stream eq 0
tcp.analysis.flags
http.request
http.response.code >= 400
vlan.id == 10
stp
ospf
ip.ttl < 10
frame.len > 1000
```

Capture filters that keep files small:

```
not arp and not stp and not cdp and not lldp
host 10.10.10.100
tcp port 80
```

## Related documents

- [../wireshark/README.md](../wireshark/README.md) — capture naming and the per-lab
  analysis checklist
- [05-ios-cheatsheet.md](05-ios-cheatsheet.md) — the device side of the same
  investigations
- [04-troubleshooting-method.md](04-troubleshooting-method.md) — where a capture
  fits into a diagnosis
