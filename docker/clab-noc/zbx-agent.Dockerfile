# Zabbix agent 2 (Phase 5): one agent watching the NOC server itself, so the
# monitoring box is monitored too. Same clab-noc/ wrapper as the rest of the
# stack.
FROM zabbix/zabbix-agent2:alpine-7.0-latest

USER root
RUN apk add --no-cache iproute2

ENV LAB_IFACE=eth1 \
    LAB_IP=10.100.0.23/24 \
    LAB_GW=10.100.0.1 \
    LAB_UPSTREAM=/usr/bin/docker-entrypoint.sh

COPY clab-noc/noc-entrypoint.sh /usr/local/bin/noc-entrypoint.sh
RUN chmod +x /usr/local/bin/noc-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/noc-entrypoint.sh"]
# Repeated on purpose: an ENTRYPOINT in this Dockerfile resets the base CMD.
CMD ["/usr/sbin/zabbix_agent2", "--foreground", "-c", "/etc/zabbix/zabbix_agent2.conf"]
