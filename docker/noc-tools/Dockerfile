FROM alpine:3.20

# Everything a NOC engineer reaches for when something is broken.
RUN apk add --no-cache \
      bash \
      bind-tools \
      busybox-extras \
      curl \
      iperf3 \
      iproute2 \
      iputils \
      mtr \
      net-snmp-tools \
      nmap \
      nmap-scripts \
      tcpdump \
      traceroute \
      vim

COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY noc-tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
