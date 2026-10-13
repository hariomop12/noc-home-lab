FROM alpine:3.20

RUN apk add --no-cache bash dnsmasq iproute2 tini

COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY dnsmasq/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY dnsmasq/dnsmasq.conf /etc/dnsmasq.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default lab address for SRV-DNS. Override with the LAB_IP / LAB_GW
# environment variables when a lab needs a different address.
ENV LAB_IP=10.100.0.10/24 \
    LAB_GW=10.100.0.1

# 53 DNS, 67 DHCP
EXPOSE 53/tcp 53/udp 67/udp

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["dnsmasq", "--keep-in-foreground", "--log-facility=-"]
