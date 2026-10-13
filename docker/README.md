# Lab images

Three small container images used as the *servers* in this lab. They replace the
default images for a simple reason: a lab server must come up with a **known IP
address** every time, without manual steps inside the container.

Each image reads two environment variables at startup:

| Variable | Meaning | Example |
|---|---|---|
| `LAB_IP` | Address and prefix to assign to the container's interface | `10.100.0.10/24` |
| `LAB_GW` | Default gateway (optional) | `10.100.0.1` |

The entrypoint clears whatever address GNS3 or Docker assigned, applies `LAB_IP`,
sets the default route, then hands off to the service. Console access stays
available through GNS3 because each service runs in the foreground.

## Images

| Image | Tag | Address in the IP plan | Purpose |
|---|---|---|---|
| noc-tools | `noc-tools:lab` | on demand | Aladdin's cave: tcpdump, nmap, net-snmp, mtr, dig, iperf3 |
| syslog | `syslog:lab` | `10.100.0.10` → see note | Central syslog collector on UDP/TCP 514 |
| dnsmasq | `dnsmasq:lab` | `10.100.0.10` | DHCP + DNS for the lab |
| web | `web:lab` | `10.100.0.12` | nginx HTTP/HTTPS target for client tests |

> The IP plan gives SRV-DNS `10.100.0.10` and SRV-SYSLOG `10.100.0.11`. Only one
> service runs at a time in the micro labs, so each image defaults to the address
> its lab needs. Override with `LAB_IP` when running both at once.

## Build

```bash
cd docker
./build.sh
```

Build once. Rebuild only when a Dockerfile changes.

## Add to GNS3

For each image, `Preferences → Docker containers → New`:

1. Select the image (`noc-tools:lab`, `syslog:lab`, `dnsmasq:lab`).
2. Console type: **telnet**.
3. Name the template to match the service, e.g. `SRV-DNS`.
4. In **Environment**, add `LAB_IP` and `LAB_GW` as key/value pairs.
5. Save.

Now every time the node is dropped into a topology it boots already addressed.

## Why not just use the stock images

The stock `nginx:alpine` builds its config from templates and needs no address
of its own, but the lab still needs the web server at a known address
(`10.100.0.12`), so `web:lab` wraps it with the same `LAB_IP` contract. For
anything where the address matters, a small purpose-built image is less work
than fighting an entrypoint written for a different use case.

## Note on persistence

These containers are stateless by design. Anything important — a config, a
capture, a log worth keeping — is copied into the repository, not left inside a
container. Nothing here survives a rebuild, and that is deliberate: the
repository is the source of truth.
