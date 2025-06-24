#!/usr/bin/env bash
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
# Calculate cache sizes (20 % keys_zone, 60 % data) unless overridden
# -----------------------------------------------------------------------------
calc_cache() {
    local mem_kb
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    KEY_AUTO=$((mem_kb / 5))k     # 20 %
    MAX_AUTO=$((mem_kb * 3 / 5))k # 60 %
}
calc_cache
CACHE_KEYS=${CACHE_SIZE_KEYS:-$KEY_AUTO}
CACHE_MAX=${CACHE_SIZE_MAX:-$MAX_AUTO}

log "Cache keys=${CACHE_KEYS}, max=${CACHE_MAX}" INFO

# -----------------------------------------------------------------------------
# Generate nginx.conf (HTTP‑only or HTTPS) in a single pass
# -----------------------------------------------------------------------------

NGINX_LOCATION_CACHE=$(
    cat <<EOF
      location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_cache tiles;
        proxy_cache_valid any 5m;
        add_header X-Cache \$upstream_cache_status;
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

  proxy_cache_path /dev/shm/nginx_cache levels=1:2 keys_zone=tiles:${CACHE_KEYS} max_size=${CACHE_MAX} inactive=24h;

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
    log "Starting nginx …" INFO
    nginx
else
    log "Reloading nginx …" INFO
    nginx -s reload
fi

# -----------------------------------------------------------------------------
# Background certificate renewal loop
# -----------------------------------------------------------------------------
if [ -z "$HTTP_ONLY" ]; then
    /scripts/cert_renew.sh &
fi
