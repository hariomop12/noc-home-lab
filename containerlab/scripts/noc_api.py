#!/usr/bin/env python3
"""Shared Zabbix API client for the Phase 5 scripts.

noc-bootstrap.py uses it to declare the lab; nocctl.py uses it to read the
current state while a fault is being drilled. Keeping the client in one file
means there is exactly one place that knows the API address, the credentials and
the device inventory.

The NOC is reachable from the host on its out-of-band address
(http://172.21.21.74:8080) and from inside the lab on http://10.100.0.20:8080.
"""

import json
import os
import sys
import urllib.error
import urllib.request

API = os.environ.get("ZBX_API", "http://172.21.21.74:8080/api_jsonrpc.php")
USER = os.environ.get("ZBX_USER", "Admin")
PASSWORD = os.environ.get("ZBX_PASSWORD", "zabbix")

GROUP = "noc-home-lab"
PING_DELAY = "30s"    # ICMP: fast enough to alarm inside a drill
SNMP_DELAY = "60s"

# (host, managed address, role, snmp?, icmp?, agent?)
#
# The routers are polled on their loopback: that is the address that has to
# survive any single link failure, which is exactly why a monitoring address is
# never one of the physical interfaces.
DEVICES = [
    ("r1",         "10.255.0.1",  "HQ edge router (VLANs 10/20/30/40/99)", True,  True,  False),
    ("r2",         "10.255.0.2",  "Branch-1 edge router (VLANs 10/99)",    True,  True,  False),
    ("isp",        "10.0.0.14",   "Simulated ISP / internet edge",         True,  True,  False),
    ("sw1",        "10.10.99.11", "HQ access switch",                      True,  True,  False),
    ("sw2",        "10.10.99.12", "HQ server switch",                      True,  True,  False),
    ("sw3",        "10.20.99.13", "Branch-1 access switch",                True,  True,  False),
    ("srv-dns",    "10.100.0.10", "VLAN 40 - DNS + DHCP server",           False, True,  False),
    ("srv-syslog", "10.100.0.11", "VLAN 40 - syslog collector",            False, True,  False),
    ("srv-web",    "10.100.0.12", "VLAN 40 - internal web server",         False, True,  False),
    ("srv-ntp",    "10.100.0.13", "VLAN 40 - NTP server",                  False, True,  False),
    ("client",     "10.100.0.50", "VLAN 40 - NOC toolbox",                 False, True,  False),
    ("zbx-agent",  "10.100.0.23", "Zabbix agent on the NOC host",          False, False, True),
]

SEVERITY = {0: "not classified", 1: "information", 2: "warning", 3: "average",
            4: "high", 5: "disaster"}


class Zabbix:
    """Minimal JSON-RPC client: call(method, **params) -> result.

    `params` may also be passed positionally when the method wants a bare JSON
    array instead of a named object - Zabbix's delete methods do exactly that,
    which is why `discoveryrule.delete` returns
    `Invalid parameter "/1": a number is expected` when it is handed
    `{"itemids": [...]}` instead of `[...]`.
    """

    def __init__(self):
        self.auth = None
        self.seq = 0

    def call(self, method, params=None, **kwargs):
        self.seq += 1
        body = {"jsonrpc": "2.0", "method": method,
                "params": kwargs if params is None else params, "id": self.seq}
        if self.auth:
            body["auth"] = self.auth
        req = urllib.request.Request(
            API, json.dumps(body).encode(), {"Content-Type": "application/json-rpc"}
        )
        try:
            with urllib.request.urlopen(req, timeout=25) as resp:
                out = json.load(resp)
        except urllib.error.URLError as exc:
            sys.exit(f"cannot reach the Zabbix API at {API}: {exc}")
        if "error" in out:
            err = out["error"]
            raise RuntimeError(f"{method}: {err.get('message')} - {err.get('data')}")
        return out["result"]

    def login(self):
        # apiinfo.version must be called without the auth parameter.
        version = self.call("apiinfo.version")
        self.auth = self.call("user.login", username=USER, password=PASSWORD)
        return version

    # ------------------------------------------------------------ reads -----
    def group_id(self, name=GROUP):
        found = self.call("hostgroup.get", filter={"name": name}, output=["groupid"])
        return found[0]["groupid"] if found else None

    def items(self, name=GROUP):
        gid = self.group_id(name)
        return self.call("item.get", groupids=[gid], output=[
            "hostid", "name", "key_", "lastvalue", "lastclock", "state", "error"],
            selectHosts=["host"])

    def problems(self, name=GROUP):
        """Currently open problems, each tagged with the host that owns it.

        problem.get itself cannot tell you the host (it only returns the trigger
        id), so the trigger ids are resolved in one extra call.
        """
        gid = self.group_id(name)
        found = self.call("problem.get", groupids=[gid], output=[
            "eventid", "objectid", "name", "clock", "severity", "r_clock"],
            recent=False)
        if not found:
            return []
        triggers = self.call("trigger.get",
                             triggerids=[p["objectid"] for p in found],
                             output=["triggerid"], selectHosts=["host"])
        owners = {t["triggerid"]: t["hosts"][0]["host"] for t in triggers}
        for p in found:
            p["host"] = owners.get(p["objectid"], "?")
        return found

    def events(self, since, name=GROUP, limit=200):
        gid = self.group_id(name)
        return self.call("event.get", groupids=[gid], time_from=since, value=1,
                         output=["eventid", "clock", "name", "severity", "value"],
                         selectHosts=["host"],
                         sortfield="clock", sortorder="DESC", limit=limit)

    def recovery_events(self, since, name=GROUP, limit=200):
        gid = self.group_id(name)
        return self.call("event.get", groupids=[gid], time_from=since, value=0,
                         output=["eventid", "clock", "name", "severity", "value"],
                         selectHosts=["host"], sortfield="clock", sortorder="DESC",
                         limit=limit)


def clock(value):
    """Zabbix epoch seconds -> local HH:MM:SS."""
    import datetime
    return datetime.datetime.fromtimestamp(int(value)).strftime("%H:%M:%S")
