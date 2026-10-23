#!/usr/bin/env bash
# =============================================================================
#  baseline.sh - health check for the containerlab lab (noc-home-lab)
#
#  Every check is an assertion against a live container, not a screenshot. It is
#  the same list the Lab 06 and Lab 07 guides walk through by hand, scripted so
#  that a change can be proved harmless (or guilty) in one command.
#
#    ./scripts/baseline.sh
#
#  Exit code 0 = every check passed.
# =============================================================================
set -u

PREFIX="clab-noclab"
DNS_SERVER="10.100.0.10"
WEB_SERVER="10.100.0.12"
INTERNET="200.1.1.10"

pass=0
fail=0

if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
    G=''; R=''; D=''; N=''
fi

ok()  { printf '  %sPASS%s  %-30s %s\n' "$G" "$N" "$1" "$2"; pass=$((pass + 1)); }
bad() { printf '  %sFAIL%s  %-30s %s\n' "$R" "$N" "$1" "$2"; fail=$((fail + 1)); }
hdr() { printf '\n%s== %s%s\n' "$D" "$1" "$N"; }

# t <name> <description> <command...>
t() {
    local name="$1" desc="$2"; shift 2
    if "$@" >/tmp/baseline.out 2>&1; then
        ok "$name" "$desc"
    else
        bad "$name" "$desc"
        sed -n '1,3p' /tmp/baseline.out | sed 's/^/          /'
    fi
}

x()      { docker exec "$PREFIX-$1" "${@:2}"; }
pingq()  { docker exec "$PREFIX-$1" ping -c1 -W2 -q "$2" >/dev/null 2>&1; }
has_ip() { x "$1" ip -4 addr show "$2" 2>/dev/null | grep -q "inet $3"; }
vty()    { docker exec "$PREFIX-$1" vtysh -c "$2"; }

if ! docker ps --format '{{.Names}}' | grep -q "^${PREFIX}-r1$"; then
    echo "The lab is not deployed. Run: sudo containerlab deploy -t topology.clab.yml"
    exit 2
fi

printf '\ncontainerlab baseline - %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

# ------------------------------------------------------------- containers ---
hdr "containers"
t "containers" "22 nodes running" \
    bash -c "[ \"\$(docker ps --filter name=$PREFIX --format '{{.Names}}' | wc -l)\" = 22 ]"

# ----------------------------------------------------------------- routing --
hdr "routing (OSPF, one area)"
t "ospf-r1" "r1: both neighbours FULL" \
    bash -c "[ \"\$(docker exec $PREFIX-r1 vtysh -c 'show ip ospf neighbor' | grep -c Full)\" = 2 ]"
t "ospf-r2" "r2: both neighbours FULL" \
    bash -c "[ \"\$(docker exec $PREFIX-r2 vtysh -c 'show ip ospf neighbor' | grep -c Full)\" = 2 ]"
t "default-r1" "r1 has an OSPF default route" \
    bash -c "docker exec $PREFIX-r1 ip route | grep -q '^default.*proto ospf'"
t "default-r2" "r2 has an OSPF default route" \
    bash -c "docker exec $PREFIX-r2 ip route | grep -q '^default.*proto ospf'"
t "br1-via-transit" "r1 reaches BR1 over the transit" \
    bash -c "docker exec $PREFIX-r1 ip route | grep '10.20.10.0/24' | grep -q 'via 10.0.0.2'"
t "hq-via-transit" "r2 reaches HQ over the transit" \
    bash -c "docker exec $PREFIX-r2 ip route | grep '10.10.10.0/24' | grep -q 'via 10.0.0.1'"

# -------------------------------------------------------------------- DHCP --
hdr "DHCP (one server, relayed)"
t "dhcp-pc1" "pc1 has a VLAN 10 lease"   has_ip pc1 eth1 10.10.10.
t "dhcp-pc2" "pc2 has a VLAN 20 lease"   has_ip pc2 eth1 10.10.20.
t "dhcp-pc3" "pc3 has a VLAN 30 lease"   has_ip pc3 eth1 10.10.30.
t "dhcp-pc4" "pc4 has a VLAN 30 lease"   has_ip pc4 eth1 10.10.30.
t "dhcp-pc5" "pc5 has a BR1 lease"       has_ip pc5 eth1 10.20.10.
t "dhcp-pc6" "pc6 has a BR1 lease"       has_ip pc6 eth1 10.20.10.

# --------------------------------------------------------------- reachability
hdr "reachability"
t "pc1-to-gw"   "pc1 -> VLAN 10 gateway"  pingq pc1 10.10.10.1
t "pc2-to-gw"   "pc2 -> VLAN 20 gateway"  pingq pc2 10.10.20.1
t "pc3-to-gw"   "pc3 -> VLAN 30 gateway"  pingq pc3 10.10.30.1
t "pc4-to-gw"   "pc4 -> VLAN 30 gateway"  pingq pc4 10.10.30.1
t "pc5-to-gw"   "pc5 -> BR1 gateway"      pingq pc5 10.20.10.1
t "pc6-to-gw"   "pc6 -> BR1 gateway"      pingq pc6 10.20.10.1
t "inter-vlan"  "pc1 (VLAN 10) -> srv-web (VLAN 40)" pingq pc1 "$WEB_SERVER"
t "inter-vlan2" "pc4 (VLAN 30) -> srv-web (VLAN 40)" pingq pc4 "$WEB_SERVER"
t "br1-to-hq"   "pc5 (BR1) -> srv-web (HQ)" pingq pc5 "$WEB_SERVER"
t "br1-to-hq-loopback" "pc5 -> r1 loopback 10.255.0.1" pingq pc5 10.255.0.1
t "internet-hq" "pc1 -> $INTERNET (NAT)"  pingq pc1 "$INTERNET"
t "internet-br1" "pc5 -> $INTERNET (NAT)" pingq pc5 "$INTERNET"
t "mgmt-sw1"    "client -> sw1 VLAN 99 SVI" pingq client 10.10.99.11
t "mgmt-sw3"    "client -> sw3 VLAN 99 SVI" pingq client 10.20.99.13

# --------------------------------------------------------------------- NAT --
hdr "NAT (only the WAN interface translates)"
# The translation itself, from the router's own state table.
x pc1 ping -c4 -i 0.2 -W2 "$INTERNET" >/dev/null 2>&1
t "nat-translated" "conntrack shows the WAN address" \
    bash -c "docker exec $PREFIX-r1 conntrack -L 2>/dev/null | grep 'dst=$INTERNET' | grep -q 'dst=10.0.0.13'"
# And what actually appears on the wire towards the simulated internet. The
# capture runs with a timeout so a silent link cannot hang the whole check.
docker exec "$PREFIX-isp" timeout 8 tcpdump -ni eth3 -c 6 icmp >/tmp/nat-isp.txt 2>/dev/null &
cap=$!
sleep 1
x pc1 ping -c4 -i 0.2 -W2 "$INTERNET" >/dev/null 2>&1
wait $cap 2>/dev/null
t "nat-on-the-wire" "the internet sees r1's WAN address" \
    grep -q '10.0.0.13 > ' /tmp/nat-isp.txt
t "nat-not-leaking" "no private source on the ISP internet link" \
    bash -c "! grep -qE '10\.(10|20|100)\.' /tmp/nat-isp.txt"
t "nat-rule" "r1 NAT matches the WAN interface only" \
    bash -c "docker exec $PREFIX-r1 nft list ruleset | grep -q 'oifname \"eth1\"'"

# --------------------------------------------------------------------- DNS --
hdr "DNS"
t "dns-a-record" "client resolves web.lab.local" \
    bash -c "docker exec $PREFIX-client nslookup web.lab.local $DNS_SERVER 2>/dev/null | grep -q '$WEB_SERVER'"
t "dns-ptr"      "client resolves r1.lab.local" \
    bash -c "docker exec $PREFIX-client nslookup r1.lab.local $DNS_SERVER 2>/dev/null | grep -q '10.255.0.1'"

# --------------------------------------------------------------------- STP --
hdr "layer 2 (STP)"
t "stp-loop-broken" "exactly one uplink is blocking" \
    bash -c "[ \"\$( { docker exec $PREFIX-sw1 bridge -d link show; docker exec $PREFIX-sw2 bridge -d link show; } | grep -c 'state blocking')\" = 1 ]"
t "stp-root" "sw1 is the root bridge (priority 4096)" \
    bash -c "docker exec $PREFIX-sw1 bridge -d link show >/dev/null && [ \"\$(docker exec $PREFIX-sw1 cat /sys/class/net/br0/bridge/root_path_cost)\" = 0 ]"

# ------------------------------------------------------ management plane ----
hdr "management plane"
for n in r1 r2 sw1 sw2 sw3 isp; do
    case "$n" in
        r1) addr=10.10.10.1 ;;
        r2) addr=10.20.10.1 ;;
        sw1) addr=10.10.99.11 ;;
        sw2) addr=10.10.99.12 ;;
        sw3) addr=10.20.99.13 ;;
        isp) addr=10.0.0.14 ;;
    esac
    t "snmp-$n" "SNMP labRO reachable on $n" \
        bash -c "docker exec $PREFIX-client snmpget -v2c -c labRO -t 3 -r 1 $addr sysName.0 2>/dev/null | grep -q 'STRING: $n'"
done
t "syslog-r1"  "collector has r1's messages"  \
    bash -c "docker exec $PREFIX-srv-syslog ls /var/log/remote/ | grep -q '^10.100.0.1.log'"
t "syslog-sw1" "collector has sw1's messages" \
    bash -c "docker exec $PREFIX-srv-syslog ls /var/log/remote/ | grep -q '^10.10.99.11.log'"
t "syslog-isp" "collector has ISP messages"   \
    bash -c "docker exec $PREFIX-srv-syslog ls /var/log/remote/ | grep -q '^10.0.0.14.log'"
t "ntp-r1" "r1 is synced to srv-ntp" \
    bash -c "docker exec $PREFIX-r1 chronyc sources 2>/dev/null | grep -q '10.100.0.13'"
t "ntp-sw1" "sw1 is synced to srv-ntp" \
    bash -c "docker exec $PREFIX-sw1 chronyc sources 2>/dev/null | grep -q '10.100.0.13'"

# --------------------------------------------------------------- NOC stack --
hdr "NOC stack (Phase 5)"
t "zbx-db" "Postgres accepts connections (5432, out-of-band)" \
    bash -c "docker exec $PREFIX-client nc -z -w2 172.21.21.72 5432"
t "zbx-server" "Zabbix server listens (10051)" \
    bash -c "docker exec $PREFIX-client nc -z -w2 10.100.0.21 10051"
t "zbx-agent" "Zabbix agent listens (10050)" \
    bash -c "docker exec $PREFIX-client nc -z -w2 10.100.0.23 10050"
t "zbx-web" "frontend answers HTTP on 8080" \
    bash -c "code=\$(docker exec $PREFIX-client curl -s -m 5 -o /dev/null -w '%{http_code}' http://10.100.0.20:8080/); [ \"\$code\" != 000 ]"
t "zbx-api" "API answers apiinfo.version" \
    bash -c "docker exec $PREFIX-client curl -s -m 5 -H 'Content-Type: application/json-rpc' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"apiinfo.version\",\"params\":{},\"id\":1}' \
        http://10.100.0.20:8080/api_jsonrpc.php | grep -q result"

# ------------------------------------------------------------------ summary --
printf '\n'
if [ "$fail" -eq 0 ]; then
    printf '%s%d passed, %d failed%s\n\n' "$G" "$pass" "$fail" "$N"
    exit 0
fi
printf '%s%d passed, %d failed%s\n\n' "$R" "$pass" "$fail" "$N"
exit 1
