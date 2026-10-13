#!/usr/bin/env sh
set -eu
. /usr/local/lib/lab-entrypoint.sh

apply_lab_address || true

exec "$@"
