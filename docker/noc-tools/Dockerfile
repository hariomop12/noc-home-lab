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

# Default lab address for a throwaway tools box (used as a lab CLIENT).
# Override with LAB_IP / LAB_GW.
ENV LAB_IP=10.100.0.50/24 \
    LAB_GW=10.100.0.1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
