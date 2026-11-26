#!/usr/bin/env bash
#
# nginx_clear.sh — Clear nginx proxy cache
#
# DESCRIPTION
#   Clears the nginx proxy cache on disk and reloads nginx to drop any stale
#   cache metadata. This is useful for forcing fresh tile data or
#   troubleshooting caching issues.
#
# BEHAVIOR
#   1. Check if cache directory exists (/var/cache/nginx/tiles)
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
#   - Uses the cache location configured by nginx_start.sh
#
set -euo pipefail

. /scripts/utils.sh

CACHE_DIR=/var/cache/nginx/tiles

log "Clearing nginx proxy cache …"

if [ ! -d "$CACHE_DIR" ]; then
    log "Cache directory not found – nothing to clear" WARN
    exit 0
fi

find "$CACHE_DIR" -mindepth 1 -delete || true
# reload nginx config so that any stale cache metadata is dropped
nginx -s reload
