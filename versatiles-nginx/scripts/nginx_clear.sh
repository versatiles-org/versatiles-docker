#!/usr/bin/env bash
set -euo pipefail

. /scripts/utils.sh

log "Clearing nginx proxy cache …"

if [ ! -d /dev/shm/nginx_cache ]; then
    log "Cache directory not found – nothing to clear" WARN
    exit 0
fi

rm -rf /dev/shm/nginx_cache/* || true
# reload nginx config so that any stale cache metadata is dropped
nginx -s reload
