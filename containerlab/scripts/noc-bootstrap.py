#!/usr/bin/env python3
"""Phase 5 - declare the whole lab to Zabbix through its JSON-RPC API.

The NOC stack (Zabbix 7.0 LTS: Postgres + server + frontend + one agent) is part
of topology.clab.yml, so it is already running before this script is called.
This script does the part a human would otherwise click through: create the host
group, the hosts, their items and their triggers.

    cd containerlab && python3 scripts/noc-bootstrap.py

Everything is idempotent and self-healing: an existing host is not skipped, it
is walked through the item/trigger stage again, so a half-finished bootstrap (or
a check added later) is repaired by simply re-running the script.

Teaching notes (things the API makes you think about):
  * A device needs TWO interfaces. SNMP items are polled over the SNMP
    interface (type 2), while `icmpping` is a "simple check" executed by the
    server itself and wants a plain interface (type 1). Give it only the SNMP
    interface and item.create fails; give it only the agent interface and you
    cannot poll SNMP. Every switch/router a NOC adds hits this.
  * The triggers are deliberately about *reachability* (ICMP, and "no SNMP data
    for 5 minutes"), not about counters. A NOC's first job is "did the box
    disappear" - and the two are different failures: a device can be pingable
    while its monitoring data died, which is why the nodata() trigger exists.
  * `icmpping` is one of the few item types that needs nothing on the far side,
    so it is the one check that works on a brand-new device.
"""

import sys

from noc_api import API, DEVICES, GROUP, SNMP_DELAY, Zabbix


def main():
    z = Zabbix()
    version = z.login()
    print(f"API {API}: Zabbix {version}")

    gid = z.group_id()
    if gid is None:
        gid = z.call("hostgroup.create", name=GROUP)["groupids"][0]
        print(f"created host group '{GROUP}'")

    for host, addr, role, snmp, icmp, agent in DEVICES:
        existing = z.call("host.get", filter={"host": host}, output=["hostid"])
        if existing:
            hostid, note = existing[0]["hostid"], "checked"
        else:
            interfaces = []
            if snmp:
                interfaces.append({
                    "type": 2, "main": 1, "useip": 1, "ip": addr, "dns": "", "port": "161",
                    "details": {"version": 2, "bulk": 1, "community": "labRO"},
                })
            if icmp:
                # type 1 is the "Zabbix agent" interface. There is no agent on
                # these boxes; the interface exists only so that the simple
                # checks (icmpping) have an interface to run against.
                interfaces.append({"type": 1, "main": 1, "useip": 1, "ip": addr,
                                   "dns": "", "port": "10050"})
            if agent:
                interfaces.append({"type": 1, "main": 1, "useip": 1, "ip": addr,
                                   "dns": "", "port": "10050"})
            hostid = z.call(
                "host.create", host=host, name=f"{host} - {role}",
                groups=[{"groupid": gid}], interfaces=interfaces,
                inventory_mode=-1, description=role,
            )["hostids"][0]
            note = "created"

        ifaces = z.call("hostinterface.get", hostids=hostid, output=["interfaceid", "type"])
        snmp_if = next((i["interfaceid"] for i in ifaces if i["type"] == "2"), None)
        ping_if = next((i["interfaceid"] for i in ifaces if i["type"] == "1"), None)

        items = 0
        if snmp:
            for name, key, oid, vtype in (
                ("SNMP sysName",   "snmp.sysName",   "1.3.6.1.2.1.1.5.0", 4),
                ("SNMP sysDescr",  "snmp.sysDescr",  "1.3.6.1.2.1.1.1.0", 4),
                ("SNMP sysUpTime", "snmp.sysUpTime", "1.3.6.1.2.1.1.3.0", 3),
            ):
                if item(z, host, hostid, snmp_if, name, key,
                        type=20, value_type=vtype, snmp_oid=oid):
                    items += 1
            # A device that answers no SNMP at all is the classic silent outage:
            # the box is still pingable (its management plane is alive) but the
            # monitoring data has stopped. nodata() is what catches that.
            trigger(z, f"SNMP data missing: {host} (no update for 5m)",
                    f"nodata(/{host}/snmp.sysUpTime,5m)=1", 4)

            # Interfaces are not listed host by host - they are *discovered*.
            # The walk is the standard IF-MIB ifOperStatus OID; the index of each
            # returned OID is the ifIndex, which is what {#SNMPINDEX} expands to
            # in every prototype below. The item count in the log below therefore
            # does not include them: how many appear depends on the device.
            lld(z, host, hostid, snmp_if)

            # CPU on a Linux device comes from the UCD-SNMP MIB that net-snmp
            # serves: ssCpuIdle is a percentage, so the trigger is the inverse.
            for name, key, oid, vtype, units in (
                ("CPU idle",        "cpu.idle",  "1.3.6.1.4.1.2021.11.11.0", 0, "%"),
                ("Load average 1m", "cpu.load1", "1.3.6.1.4.1.2021.10.1.3.1", 0, ""),
            ):
                if item(z, host, hostid, snmp_if, name, key, type=20,
                        value_type=vtype, units=units, snmp_oid=oid):
                    items += 1
            trigger(z, f"CPU busy: {host} (idle below 10% for 5m)",
                    f"max(/{host}/cpu.idle,5m)<10", 3)
            trigger(z, f"High load: {host} (1-minute load above 4)",
                    f"min(/{host}/cpu.load1,5m)>4", 3)
        if icmp:
            for name, key, vtype, units in (
                ("ICMP ping",            "icmpping",     3, ""),
                ("ICMP packet loss",     "icmppingloss", 0, "%"),
                ("ICMP round-trip time", "icmppingsec",  0, "s"),
            ):
                if item(z, host, hostid, ping_if, name, key, type=3,
                        value_type=vtype, units=units, delay="30s"):
                    items += 1
            trigger(z, f"Host unreachable by ICMP: {host}",
                    f"min(/{host}/icmpping,#3)=0", 4,
                    recovery=f"max(/{host}/icmpping,#3)=1")
            trigger(z, f"Partial packet loss: {host} (>40% for 5m)",
                    f"min(/{host}/icmppingloss,5m)>40", 3)
        if agent:
            if item(z, host, hostid, ping_if, "Agent ping", "agent.ping",
                    type=0, value_type=3, delay=SNMP_DELAY):
                items += 1
            trigger(z, f"Agent not answering: {host}",
                    f"nodata(/{host}/agent.ping,3m)=1", 4)

        print(f"  {host:11s} {note:8s} {addr:12s} new items: {items}")

    hosts = z.call("host.get", groupids=[gid], output=["host"], selectInterfaces=["ip"])
    trigs = z.call("trigger.get", groupids=[gid], output=["description"])
    print(f"\ngroup '{GROUP}': {len(hosts)} hosts, {len(trigs)} triggers")
    for h in hosts:
        print(f"  {h['host']:11s} {h['interfaces'][0]['ip']}")


def lld(z, host, hostid, ifaceid):
    """Discover this device's interfaces and watch each one.

    The discovery rule walks the standard IF-MIB `ifOperStatus` OID once an hour.
    Zabbix turns the index of every returned OID into `{#SNMPINDEX}` (= `ifIndex`)
    and the value into `{#SNMPVALUE}`. The filter keeps only 1 (up) and 2 (down),
    so ports that report notPresent / lowerLayerDown never generate items at all.

    Two traps are baked into this function:
      * the filter operator must be 0 ("matches"), not 8 ("like") - LIKE with a
        regular expression `^(1|2)$` matches nothing and the rule silently
        discovers zero interfaces;
      * an existing rule is deleted and rebuilt, so a corrected filter takes
        effect on re-run instead of being ignored because "the rule is there".

    Doing this by hand is what stops a NOC from growing past a handful of
    devices: one rule, one item prototype, one trigger prototype, and every
    switch port in the lab is covered.
    """
    name = "Network interfaces"
    existing = z.call("discoveryrule.get", hostids=hostid, filter={"name": name},
                      output=["itemid"])
    if existing:
        # Zabbix's delete methods take a bare array of ids, not {"itemids": [...]}.
        z.call("discoveryrule.delete", [existing[0]["itemid"]])

    ruleid = z.call(
        "discoveryrule.create", name=name, key_="if.status", hostid=hostid,
        type=20, interfaceid=ifaceid,
        # SNMP low-level discovery does not take a bare OID: it takes
        # `discovery[{#MACRO},<oid>]`, the pair of macro and OID the server
        # complains is missing otherwise. {#SNMPINDEX} (the OID index) is added
        # automatically alongside the macro that is named here.
        snmp_oid="discovery[{#SNMPVALUE},1.3.6.1.2.1.2.2.1.8]",
        delay="3600s", lifetime="7d",
        filter={"evaltype": 0, "conditions": [
            {"macro": "{#SNMPVALUE}", "value": "^[12]$", "operator": "8"}]},
    )["itemids"][0]

    key = "if.status[{#SNMPINDEX}]"
    z.call("itemprototype.create", hostid=hostid, ruleid=ruleid,
           name="Interface {#SNMPINDEX} state", key_=key, type=20, value_type=3,
           delay="60s", interfaceid=ifaceid,
           snmp_oid="1.3.6.1.2.1.2.2.1.8.{#SNMPINDEX}")
    z.call("triggerprototype.create",
           description=f"Interface down: {host} ({{#SNMPINDEX}})",
           expression=f"last(/{host}/{key})=2", priority=3,
           recovery_mode=1, recovery_expression=f"last(/{host}/{key})=1")
    return True


def item(z, host, hostid, ifaceid, name, key, **fields):
    """item.create for one item; skipped when the key already exists."""
    if z.call("item.get", hostids=hostid, filter={"key_": key}, output=["itemid"]):
        return False
    fields.setdefault("delay", SNMP_DELAY)
    z.call("item.create", hostid=hostid, interfaceid=ifaceid, name=name, key_=key,
           **fields)
    return True


def trigger(z, description, expression, priority, recovery=None):
    if z.call("trigger.get", filter={"description": description}, output=["triggerid"]):
        return False
    params = {"description": description, "expression": expression, "priority": priority}
    if recovery:
        params["recovery_mode"] = 1          # recovery expression
        params["recovery_expression"] = recovery
    z.call("trigger.create", **params)
    return True


if __name__ == "__main__":
    sys.exit(main())
