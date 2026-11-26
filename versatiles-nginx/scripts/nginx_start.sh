#!/usr/bin/env bash
#
# nginx_start.sh — Configure and start nginx reverse proxy with caching
#
# DESCRIPTION
#   Configures and starts nginx as a reverse proxy with intelligent caching for
#   VersaTiles. Supports both HTTP-only and HTTPS modes. Automatically manages
#   SSL certificates via Let's Encrypt and starts a background renewal loop.
#
# REQUIRED ENVIRONMENT VARIABLES
#   DOMAIN    Domain name for the server
#             Example: "tiles.example.com"
#
# OPTIONAL ENVIRONMENT VARIABLES
#   HTTP_ONLY           Set to any non-empty value to disable HTTPS and certificates
#   CACHE_SIZE_KEYS     Size of cache keys zone (default: 1% of the max size, at least 1m)
#   CACHE_SIZE_MAX      Maximum cache data size (default: 60% of the container's
#                       memory limit, at most half the free disk space)
#
# BEHAVIOR
#   1. Validate required DOMAIN environment variable
#   2. Set up signal handlers for graceful shutdown
#   3. Create log directories
#   4. If HTTPS mode: ensure SSL certificates via cert_ensure.sh
#   5. Empty the cache, and calculate its sizes from the memory limit and
#      the free disk space
#   6. Generate nginx.conf with appropriate server blocks:
#      - HTTP-only mode: Single HTTP server on port 80
#      - HTTPS mode: HTTP→HTTPS redirect + HTTPS server on port 443
#   7. Configure proxy cache on disk (/var/cache/nginx/tiles)
#   8. Start or reload nginx
#   9. If HTTPS mode: launch background certificate renewal loop
#
# CACHE CONFIGURATION
#   - Cache location: /var/cache/nginx/tiles, emptied at every start
#   - Default keys zone: 1% of the max size, at least 1 MB
#   - Default max size: 60% of the container's memory limit (or of the host's
#     RAM without one), at most half the free disk space
#   - Inactive timeout: 24 hours
#   - Cache valid time: as the Cache-Control of versatiles says (tiles four
#     weeks, static files not at all), 404 one minute, other errors never
#   - Browsers get the Cache-Control of versatiles; 404 five minutes, other
#     errors "no-store"
#
# SIGNAL HANDLING
#   SIGINT, SIGTERM    Gracefully shutdown nginx and exit
#
# NGINX ENDPOINTS
#   /                  Proxied to VersaTiles backend (127.0.0.1:8080) with caching
#   /_nginx_status     Nginx status (localhost only, 127.0.0.1:8090)
#
# EXIT CODES
#   0    Graceful shutdown via signal
#   1    Missing required environment variable or nginx start failed
#
set -euo pipefail

. /scripts/utils.sh

# -----------------------------------------------------------------------------
# Validate input
# -----------------------------------------------------------------------------
require DOMAIN "domain name for this instance"

# Set to any non‑empty value to skip certificates and run HTTP‑only
HTTP_ONLY=${HTTP_ONLY:-}

# Graceful shutdown: forward SIGTERM/SIGINT to nginx, then exit
trap 'log "Shutdown signal received — quitting nginx …" INFO; nginx -s quit; exit 0' TERM INT

# -----------------------------------------------------------------------------
# Ensure log directories and certificates
# -----------------------------------------------------------------------------
mkdir -p /data/log
if [ -z "$HTTP_ONLY" ]; then
    /scripts/cert_ensure.sh
fi

# -----------------------------------------------------------------------------
# Prepare the cache and calculate its sizes unless overridden
# -----------------------------------------------------------------------------
# The cache is on disk, not in /dev/shm: Docker gives /dev/shm 64 MB unless
# --shm-size is set, and memory in a tmpfs can't be reclaimed. Tiles requested
# often still come from RAM, from the kernel's page cache. It is emptied at
# every start, as tiles may have changed meanwhile.
CACHE_DIR=/var/cache/nginx/tiles
mkdir -p "$CACHE_DIR"
find "$CACHE_DIR" -mindepth 1 -delete

# The container's memory limit in KiB, from cgroups, or the host's RAM if
# there is none. /proc/meminfo always shows the host's RAM.
mem_limit_kb() {
    local limit=""
    if [ -r /sys/fs/cgroup/memory.max ]; then
        limit=$(cat /sys/fs/cgroup/memory.max) # cgroup v2
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes) # cgroup v1
    fi
    # "max" (v2) or a sentinel near 2^63 (v1) means "no limit".
    if [[ "$limit" =~ ^[0-9]+$ ]] && ((limit < 9000000000000000000)); then
        echo $((limit / 1024))
    else
        awk '/^MemTotal:/ {print $2}' /proc/meminfo
    fi
}

# max_size: 60 % of the memory limit, as the cache is only fast while the page
# cache can hold it, but at most half the free disk space. keys_zone: 1 MB
# holds about 8,000 keys, so 1 % of max_size is enough for entries of 12 KB on
# average, and at least 1 MB.
calc_cache() {
    local mem_kb free_kb max_kb keys_kb
    mem_kb=$(mem_limit_kb)
    free_kb=$(df -Pk "$CACHE_DIR" | awk 'NR == 2 {print $4}')
    max_kb=$((mem_kb * 3 / 5))
    if ((max_kb > free_kb / 2)); then max_kb=$((free_kb / 2)); fi
    keys_kb=$((max_kb / 100))
    if ((keys_kb < 1024)); then keys_kb=1024; fi
    KEY_AUTO=${keys_kb}k
    MAX_AUTO=${max_kb}k
}
calc_cache
CACHE_KEYS=${CACHE_SIZE_KEYS:-$KEY_AUTO}
CACHE_MAX=${CACHE_SIZE_MAX:-$MAX_AUTO}

log "Cache keys=${CACHE_KEYS}, max=${CACHE_MAX}"

# -----------------------------------------------------------------------------
# Generate nginx.conf (HTTP‑only or HTTPS) in a single pass
# -----------------------------------------------------------------------------

NGINX_LOCATION_CACHE=$(
    cat <<EOF
      location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_cache tiles;
        # nginx keeps a response as long as the Cache-Control of versatiles
        # allows: tiles for four weeks, static files with "no-cache" not at all,
        # so edits in /data/static show at once. Errors come without
        # Cache-Control and are cached only if listed here: a 404 briefly, to
        # spare versatiles repeated misses, a 5xx never, as it describes a moment.
        proxy_cache_valid 404 1m;
        # Browsers get the header of versatiles, and one for errors
        # (see \$browser_cache_control).
        proxy_hide_header Cache-Control;
        add_header Cache-Control \$browser_cache_control always;
        add_header X-Cache \$upstream_cache_status always;
      }
EOF
)

if [ -n "$HTTP_ONLY" ]; then
    SERVER_BLOCK=$(
        cat <<EOF
    # HTTP server only (no TLS)
    server {
      listen 80 default_server;
      server_name ${DOMAIN};

        ${NGINX_LOCATION_CACHE}
    }
EOF
    )
else
    SERVER_BLOCK=$(
        cat <<EOF
    # redirect HTTP → HTTPS
    server {
      listen 80 default_server;
      server_name ${DOMAIN};
      return 301 https://\$host\$request_uri;
    }

    # HTTPS server
    server {
      listen 443 ssl;
      http2 on;
      server_name ${DOMAIN};

      ssl_certificate     /data/certificates/live/${DOMAIN}/fullchain.pem;
      ssl_certificate_key /data/certificates/live/${DOMAIN}/privkey.pem;

        ${NGINX_LOCATION_CACHE}
    }
EOF
    )
fi

cat >/etc/nginx/nginx.conf <<EOF
worker_processes auto;
error_log /data/log/error.log info;
pid /run/nginx.pid;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  access_log    /data/log/access.log;
  sendfile      on;
  server_tokens off;

  # use_temp_path=off: responses are written in the cache directory itself,
  # not copied there from proxy_temp_path.
  proxy_cache_path ${CACHE_DIR} levels=1:2 use_temp_path=off keys_zone=tiles:${CACHE_KEYS} max_size=${CACHE_MAX} inactive=24h;

  # Cache-Control for browsers. Successful answers and redirects keep the one
  # of versatiles (filled in on cache hits too), "no-cache" if it sent none.
  # Errors carry none from versatiles: a 404 may be kept for five minutes, any
  # other error describes a moment and must not be kept.
  map \$upstream_http_cache_control \$backend_cache_control {
    ""      "no-cache";
    default \$upstream_http_cache_control;
  }
  map \$status \$browser_cache_control {
    "~^[23]" \$backend_cache_control;
    404      "public, max-age=300";
    default  "no-store";
  }

  # status endpoint on 127.0.0.1:8090
  server {
    listen 127.0.0.1:8090;
    location /_nginx_status { stub_status; allow 127.0.0.1; deny all; }
  }

  ${SERVER_BLOCK}
}
EOF

# -----------------------------------------------------------------------------
# Start or reload nginx
# -----------------------------------------------------------------------------
if [ ! -s /run/nginx.pid ] || ! kill -0 "$(cat /run/nginx.pid 2>/dev/null)" 2>/dev/null; then
    log "Starting nginx …"
    nginx
else
    log "Reloading nginx …"
    nginx -s reload
fi

# -----------------------------------------------------------------------------
# Background certificate renewal loop
# -----------------------------------------------------------------------------
if [ -z "$HTTP_ONLY" ]; then
    /scripts/cert_renew.sh &
fi
