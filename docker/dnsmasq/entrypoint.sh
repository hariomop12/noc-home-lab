#!/usr/bin/env sh
set -eu
. /usr/local/lib/lab-entrypoint.sh

# Apply the static address before handing off to the dnsmasq entrypoint.
apply_lab_address || true

exec "$@"
