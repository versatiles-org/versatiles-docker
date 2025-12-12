#!/usr/bin/env bash
#
# cert_ensure.sh — Ensure SSL/TLS certificates exist and are valid
#
# DESCRIPTION
#   Obtains or verifies SSL/TLS certificates via Let's Encrypt (ACME protocol)
#   for the specified domain. If a valid certificate already exists with more
#   than CERT_MIN_DAYS remaining, the script exits early. Otherwise, it starts
#   a temporary nginx stub server and uses certbot to obtain certificates.
#
# REQUIRED ENVIRONMENT VARIABLES
#   DOMAIN    Domain name(s) for certificate (comma-separated for multiple domains)
#             Examples: "example.com" or "example.com,www.example.com"
#   EMAIL     Email address for ACME registration and renewal notifications
#
# OPTIONAL ENVIRONMENT VARIABLES
#   CERT_MIN_DAYS    Minimum days of certificate validity before renewal (default: 30)
#
# BEHAVIOR
#   1. Check if certificate exists and is valid for > CERT_MIN_DAYS
#   2. If valid, exit early (fast path)
#   3. Otherwise, create temporary nginx configuration
#   4. Start nginx stub server for ACME HTTP-01 challenge
#   5. Run certbot to obtain/renew certificate
#   6. Stop nginx stub server
#
# EXIT CODES
#   0    Certificate exists and is valid, or successfully obtained
#   1    Missing required environment variables
#   2    ACME certificate request failed
#
# FILES
#   /data/certificates/live/${DOMAIN}/fullchain.pem    Certificate chain
#   /data/certificates/live/${DOMAIN}/privkey.pem      Private key
#   /data/certificates/work/                           Certbot working directory
#   /data/certificates/logs/                           Certbot logs
#
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
