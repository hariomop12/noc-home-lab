# Zabbix web frontend (Phase 5) with the clab-noc/ wrapper so it can sit in
# VLAN 40. nginx listens on 8080 inside the container, which is why the URL is
# http://<mgmt-ip>:8080 from the host.
FROM zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest

USER root
RUN apk add --no-cache iproute2

ENV LAB_IFACE=eth1 \
    LAB_IP=10.100.0.20/24 \
    LAB_GW=10.100.0.1 \
    LAB_UPSTREAM=/usr/bin/docker-entrypoint.sh

COPY clab-noc/noc-entrypoint.sh /usr/local/bin/noc-entrypoint.sh
RUN chmod +x /usr/local/bin/noc-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/noc-entrypoint.sh"]
