# Zabbix server (Phase 5) with the clab-noc/ wrapper so it can sit in VLAN 40.
# The vendor entrypoint and CMD are inherited: this only prepends the address.
FROM zabbix/zabbix-server-pgsql:alpine-7.0-latest

USER root
RUN apk add --no-cache iproute2

ENV LAB_IFACE=eth1 \
    LAB_IP=10.100.0.21/24 \
    LAB_GW=10.100.0.1 \
    LAB_UPSTREAM=/usr/bin/docker-entrypoint.sh

COPY clab-noc/noc-entrypoint.sh /usr/local/bin/noc-entrypoint.sh
RUN chmod +x /usr/local/bin/noc-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/noc-entrypoint.sh"]
# CMD has to be repeated: setting ENTRYPOINT in a Dockerfile resets the CMD that
# came from the base image, and without --foreground the server refuses to start
# with "LogType console can only be used with -f".
CMD ["/usr/sbin/zabbix_server", "--foreground", "-c", "/etc/zabbix/zabbix_server.conf"]
