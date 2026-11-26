#!/usr/bin/env bash
#
# cert_ensure.sh — Ensure SSL/TLS certificates exist and are valid
#
# DESCRIPTION
#   Obtains or verifies SSL/TLS certificates via Let's Encrypt (ACME protocol)
#   for the specified domains. If a valid certificate for all of them already
#   exists with more than CERT_MIN_DAYS remaining, the script exits early.
#   Otherwise, it starts a temporary nginx stub server and uses certbot to
#   obtain a certificate.
#
# REQUIRED ENVIRONMENT VARIABLES
#   DOMAIN    Domain name(s) for certificate (comma-separated for multiple domains)
#             Examples: "example.com" or "example.com,www.example.com"
#             The first domain names the certificate.
#   EMAIL     Email address for ACME registration and renewal notifications
#
# OPTIONAL ENVIRONMENT VARIABLES
#   CERT_MIN_DAYS    Minimum days of certificate validity before renewal (default: 30)
#
# BEHAVIOR
#   1. Check if the certificate exists, covers every domain, and is valid
#      for > CERT_MIN_DAYS
#   2. If so, exit early (fast path)
#   3. Otherwise, create temporary nginx configuration
#   4. Start nginx stub server for ACME HTTP-01 challenge
#   5. Run certbot to obtain/renew certificate
#   6. Stop nginx stub server
#   7. If ACME failed, leave the stub running and wait 15 minutes before
#      exiting, so a restart policy can't run into Let's Encrypt's limit of
#      5 failed validations per domain and hour
#
# EXIT CODES
#   0    Certificate exists and is valid, or successfully obtained
#   1    Missing required environment variables
#   2    ACME certificate request failed
#
# FILES
#   /data/certificates/live/<first domain>/fullchain.pem    Certificate chain
#   /data/certificates/live/<first domain>/privkey.pem      Private key
#   /data/certificates/work/                                Certbot working directory
#   /data/certificates/logs/                                Certbot logs
#
set -euo pipefail

. /scripts/utils.sh

require DOMAIN "e.g. 'example.com'"
require EMAIL "for ACME registration"
parse_domains

# Allow operators to tune the renewal threshold; default = 30 days
CERT_MIN_DAYS=${CERT_MIN_DAYS:-30}

# Seconds to wait after a failed ACME request before exiting
ACME_FAILURE_DELAY=900

mkdir -p /data/certificates /data/certificates/work /data/certificates/logs

CERT_PATH="/data/certificates/live/${CERT_NAME}/fullchain.pem"

# Whether the certificate names every domain in DOMAIN. A domain added to
# DOMAIN later needs a new certificate.
cert_covers_domains() {
    local sans d
    # "DNS:example.com, DNS:www.example.com" → "DNS:example.com,DNS:www.example.com"
    sans=$(openssl x509 -noout -ext subjectAltName -in "$CERT_PATH" | tail -n +2 | tr -d ' ')
    for d in "${DOMAINS[@]}"; do
        [[ ",$sans," == *",DNS:$d,"* ]] || return 1
    done
}

# ----- FAST PATH ---------------------------------------------------------
# If a certificate for every domain exists and is still valid for more than
# $CERT_MIN_DAYS, skip ACME. openssl -checkend expects seconds.
if [ -f "$CERT_PATH" ]; then
    if ! cert_covers_domains; then
        log "Existing cert doesn't cover all of ${SERVER_NAMES} - requesting a new one."
    elif openssl x509 -checkend "$((CERT_MIN_DAYS * 86400))" -noout -in "$CERT_PATH"; then
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
    server_name ${SERVER_NAMES};

    location / { return 404; }
  }
}
EOF

# In the foreground, so that $! is nginx itself and can be stopped. Run as a
# daemon, nginx would fork, and $! would be a process that has already exited.
log "Starting nginx stub …"
nginx -g 'daemon off;' &
NGINX_STUB_PID=$!

############### ACME ##################
log "Requesting/renewing certificate …"

cert_args=()
for d in "${DOMAINS[@]}"; do
    cert_args+=(-d "$d")
done

# certonly: nginx_start.sh writes the nginx config with the certificate, so
# certbot must not edit it. --cert-name keeps the certificate in the folder of
# the first domain, also when the domains change.
if ! certbot certonly --nginx -n --agree-tos \
    --config-dir /data/certificates \
    --work-dir /data/certificates/work \
    --logs-dir /data/certificates/logs \
    --cert-name "$CERT_NAME" \
    -m "$EMAIL" "${cert_args[@]}"; then
    log "ACME failed - leaving stub running for debugging, and exiting in $((ACME_FAILURE_DELAY / 60)) minutes, so that restarts don't run into Let's Encrypt's rate limits. Logs: /data/certificates/logs/letsencrypt.log" ERROR
    sleep "$ACME_FAILURE_DELAY"
    exit 2
fi

# Stop nginx stub
kill -QUIT "$NGINX_STUB_PID" || true
wait "$NGINX_STUB_PID" || true
log "Certificate obtained; stub stopped."
