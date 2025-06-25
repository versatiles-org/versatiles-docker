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
# If a certificate exists and is still valid for more than $CERT_MIN_DAYS,
# skip ACME. openssl -checkend expects seconds.
if [ -f "$CERT_PATH" ]; then
    if openssl x509 -checkend "$((CERT_MIN_DAYS * 86400))" -noout -in "$CERT_PATH"; then
        log "Existing cert valid for more than ${CERT_MIN_DAYS} days - skipping ACME."
        exit 0
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
log "Certificate obtained; stub stopped."
