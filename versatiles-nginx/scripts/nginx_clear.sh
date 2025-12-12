#!/usr/bin/env bash
#
# nginx_clear.sh — Clear nginx proxy cache
#
# DESCRIPTION
#   Clears the nginx proxy cache stored in tmpfs and reloads nginx to drop
#   any stale cache metadata. This is useful for forcing fresh tile data
#   or troubleshooting caching issues.
#
# BEHAVIOR
#   1. Check if cache directory exists (/dev/shm/nginx_cache)
#   2. If not found, exit with warning
#   3. Remove all files from cache directory
#   4. Reload nginx to clear cache metadata
#
# EXIT CODES
#   0    Cache cleared successfully or cache directory not found
#
# NOTES
#   - Safe to run while nginx is serving requests
#   - Cache will be repopulated on subsequent requests
#   - Uses tmpfs location configured by nginx_start.sh
#
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
