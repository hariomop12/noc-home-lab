FROM nginx:alpine

# Same static-address contract as the other lab images: read LAB_IP / LAB_GW,
# apply them, then hand off to nginx. This is why the stock image is not used
# directly -- its address must be known before the lab starts, every time.
COPY entrypoint-lib.sh /usr/local/lib/lab-entrypoint.sh
COPY web/entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh

# Default lab address for SRV-WEB. Override with LAB_IP / LAB_GW.
ENV LAB_IP=10.100.0.12/24 \
    LAB_GW=10.100.0.1

ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
