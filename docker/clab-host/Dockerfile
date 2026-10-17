# Lab host / access-switch node for containerlab.
#
# A plain Alpine box with real iproute2 (busybox `ip` cannot do 802.1Q bridge
# filtering, which is how the switches are built), plus the agents the NOC
# needs: SNMP, syslog forwarding, NTP, and tcpdump/dig for the ticket labs.
FROM alpine:3.20

RUN apk add --no-cache \
        bash \
        bind-tools \
        bridge-utils \
        chrony \
        conntrack-tools \
        curl \
        iproute2 \
        iproute2-tc \
        iputils \
        jq \
        net-snmp \
        net-snmp-tools \
        python3 \
        rsyslog \
        tcpdump \
        tini \
        traceroute

COPY clab-entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/lab-entrypoint.sh"]
CMD ["sleep", "infinity"]
