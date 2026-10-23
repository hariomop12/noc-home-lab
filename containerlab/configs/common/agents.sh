#!/bin/sh
# Management-plane agents that every lab device runs: SNMP, syslog forwarding
# and NTP. Sourced from each node's /etc/lab/setup.sh so that a router and a
# switch are configured exactly the same way.
#
#   . /etc/lab/agents.sh
#
# This is Lab 05 (Network Management) and Lab 09 (Full NOC) in one file: the
# collectors are SRV-SYSLOG (10.100.0.11) and SRV-NTP (10.100.0.13) in VLAN 40,
# and the NOC polls everything with the read-only community `labRO`.
set -u

SYSLOG_SERVER="10.100.0.11"
NTP_SERVER="10.100.0.13"

# --------------------------------------------------------------- SNMP -------
# Read-only for the lab subnets plus the out-of-band management network, so the
# NOC can poll a device over either path.
mkdir -p /etc/snmp /var/lib/net-snmp
cat > /etc/snmp/snmpd.conf <<EOF
sysLocation Home Lab
sysContact noc@lab.local
sysName $(hostname)
sysServices 72

agentaddress udp:161

rocommunity labRO 10.100.0.0/24
rocommunity labRO 10.10.0.0/16
rocommunity labRO 10.20.0.0/16
# 10.0.0.0/24 is the WAN and transit space. The NOC reaches the simulated ISP
# through r1's NAT, so the ISP sees the site's WAN address (10.0.0.13) as the
# source even though the operator is sitting in VLAN 40.
rocommunity labRO 10.0.0.0/24
rocommunity labRO 172.21.21.0/24
EOF

# -C skips the packaged default configuration file. Without it two agentaddress
# lines exist and snmpd exits with "Error opening specified endpoint udp:161" -
# a one-line trap worth knowing when a monitoring agent "just does not start".
/usr/sbin/snmpd -C -c /etc/snmp/snmpd.conf 2>/var/log/snmpd.err \
    || echo "agents: snmpd failed"

# -------------------------------------------------------------- syslog ------
# Everything to the central collector over UDP/514, and keep the local copy so
# `cat /var/log/messages` still works inside the node.
# The second rule is the remote copy over UDP/514. It is written as an explicit
# action() instead of the short "@host:514" selector because of a trap that cost
# one baseline run: a node that boots before its route to the collector exists
# (the simulated ISP is the usual victim) fails to send, and rsyslog *suspends*
# the action with a growing retry interval - minutes of silence even though the
# network is fine a second later. resumeRetryCount="-1" retries every 5 s
# forever instead of backing off.
cat > /etc/rsyslog.conf <<EOF
module(load="imuxsock")
module(load="imklog")

*.*                                                     /var/log/messages
*.* action(type="omfwd" target="${SYSLOG_SERVER}" port="514" protocol="udp" action.resumeRetryCount="-1" action.resumeInterval="5")
EOF

/usr/sbin/rsyslogd 2>/dev/null || echo "agents: rsyslogd failed"

# ----------------------------------------------------------------- NTP ------
cat > /etc/chrony/chrony.conf <<EOF
server ${NTP_SERVER} iburst
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
allow 10.0.0.0/8
EOF

/usr/sbin/chronyd -f /etc/chrony/chrony.conf 2>/dev/null || echo "agents: chronyd failed"

echo "agents: snmpd, rsyslog and chrony started (collectors: ${SYSLOG_SERVER}, ${NTP_SERVER})"
