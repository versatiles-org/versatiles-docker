#!/usr/bin/env bash
set -euo pipefail

. /scripts/utils.sh

require DOMAIN "e.g. 'example.com'"
require EMAIL "for ACME registration"

# Allow operators to tune the renewal threshold; default = 30 days
CERT_MIN_DAYS=${CERT_MIN_DAYS:-30}

mkdir -p /data/certificates /data/certificates/work /data/certificates/logs

CERT_PATH="/data/certificates/live/${DOMAIN}/fullchain.pem"

# ----- FAST PATH ---------------------------------------------------------
if [ -f "$CERT_PATH" ]; then
    # days until expiry
    DAYS_LEFT=$(openssl x509 -noout -enddate -in "$CERT_PATH" |
        cut -d= -f2 | xargs -I{} date -d {} +%s)
    DAYS_LEFT=$(((DAYS_LEFT - $(date +%s)) / 86400))

    if [ "$DAYS_LEFT" -gt "$CERT_MIN_DAYS" ]; then
        log "Existing cert valid for ${DAYS_LEFT} days (> ${CERT_MIN_DAYS}) - skipping ACME." INFO
        return 0
    fi
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

  server {
    listen 80 default_server;
    server_name ${DOMAIN};

    location / { return 404; }
  }
}
EOF

log "Starting nginx stub …"
nginx &
NGINX_STUB_PID=$!

############### ACME ##################
log "Requesting/renewing certificate …"

# Build -d arguments for each comma‑separated domain
IFS=',' read -ra _DOMAINS <<<"$DOMAIN"
cert_args=()
for d in "${_DOMAINS[@]}"; do
    cert_args+=(-d "$d")
done

if ! certbot --nginx -n --agree-tos \
    --config-dir /data/certificates \
    --work-dir /data/certificates/work \
    --logs-dir /data/certificates/logs \
    -m "$EMAIL" "${cert_args[@]}"; then
    log "ACME failed - leaving stub running for debugging" ERROR
    exit 2
fi

# Stop nginx stub
kill -TERM "$NGINX_STUB_PID" || true
wait "$NGINX_STUB_PID" || true
log "Certificate obtained; stub stopped." INFO
