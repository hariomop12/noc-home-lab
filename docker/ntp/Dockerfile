FROM alpine:3.20

RUN apk add --no-cache bash iproute2 chrony tini

COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY ntp/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ntp/chrony.conf /etc/chrony/chrony.conf
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /var/lib/chrony /var/log/chrony

# Default lab address for SRV-NTP. Override with LAB_IP / LAB_GW.
ENV LAB_IP=10.100.0.13/24 \
    LAB_GW=10.100.0.1

# NTP server socket
EXPOSE 123/udp

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["chronyd", "-d", "-x", "-u", "root", "-f", "/etc/chrony/chrony.conf"]
