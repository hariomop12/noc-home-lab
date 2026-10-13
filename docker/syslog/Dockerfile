FROM alpine:3.20

RUN apk add --no-cache bash iproute2 rsyslog tini

COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY syslog/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY syslog/rsyslog.conf /etc/rsyslog.conf
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /var/log/remote

# Default lab address for SRV-SYSLOG. Override with LAB_IP / LAB_GW.
ENV LAB_IP=10.100.0.11/24 \
    LAB_GW=10.100.0.1

# 514/udp is the classic syslog port, 514/tcp is used by some devices
EXPOSE 514/udp 514/tcp

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["rsyslogd", "-n"]
