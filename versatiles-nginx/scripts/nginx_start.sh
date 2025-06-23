#!/usr/bin/env bash
set -euo pipefail

. /scripts/utils.sh

# -----------------------------------------------------------------------------
# Validate input
# -----------------------------------------------------------------------------
require DOMAIN "domain name for this instance"

# -----------------------------------------------------------------------------
# Ensure log directories and certificates
# -----------------------------------------------------------------------------
mkdir -p /data/log
/scripts/cert_ensure.sh

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
# Write full HTTPS nginx config
# -----------------------------------------------------------------------------
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

    # frontend (if any)
    location / {
      proxy_pass http://127.0.0.1:8080;
      proxy_cache tiles;
      proxy_cache_valid any 5m;
      add_header X-Cache \$upstream_cache_status;
    }
  }
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
/scripts/cert_renew.sh &
