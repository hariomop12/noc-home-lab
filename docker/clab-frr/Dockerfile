# Lab router node for containerlab: FRRouting plus the tooling the lab guides
# assume on a router — SNMP for the NOC, syslog for the collector, NTP, DHCP
# relay, tcpdump for captures.
#
# Based on the official FRR image so that vtysh, the daemons and the start-up
# wrapper behave exactly as they do upstream. That build ships without NAT
# support (no libnftnl), so NAT overload is done with nftables instead — the
# same approach the Lab 07 correction documents for the GNS3 lab.
FROM quay.io/frrouting/frr:10.7.1

RUN apk add --no-cache \
        bash \
        bind-tools \
        chrony \
        conntrack-tools \
        curl \
        dnsmasq \
        iproute2 \
        iproute2-tc \
        iputils \
        jq \
        net-snmp \
        net-snmp-tools \
        nftables \
        rsyslog \
        tcpdump \
        traceroute

COPY clab-entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/lab-entrypoint.sh"]
CMD ["/usr/lib/frr/docker-start"]
