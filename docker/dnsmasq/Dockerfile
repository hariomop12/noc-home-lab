FROM alpine:3.20

RUN apk add --no-cache bash dnsmasq iproute2 tini

COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY dnsmasq/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY dnsmasq/dnsmasq.conf /etc/dnsmasq.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

# 53 DNS, 67 DHCP
EXPOSE 53/tcp 53/udp 67/udp

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["dnsmasq", "--keep-in-foreground", "--log-facility=-"]
