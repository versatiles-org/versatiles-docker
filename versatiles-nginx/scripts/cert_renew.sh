#!/usr/bin/env bash
#
# cert_renew.sh — Background certificate renewal loop
#
# DESCRIPTION
#   Runs an infinite loop that periodically checks for expiring SSL/TLS
#   certificates and renews them automatically using certbot. This script
#   is typically run in the background by nginx_start.sh.
#
# OPTIONAL ENVIRONMENT VARIABLES
#   CERT_RENEW_INTERVAL    Seconds between renewal checks (default: 86400 = 1 day)
#
# BEHAVIOR
#   1. Start infinite loop with configurable sleep interval
#   2. Attempt certificate renewal via certbot
#   3. If certificates are renewed, nginx is automatically reloaded via deploy-hook
#   4. Log success or failure
#   5. Sleep for INTERVAL seconds and repeat
#
# SIGNAL HANDLING
#   SIGINT, SIGTERM    Gracefully exit the renewal loop
#
# EXIT CODES
#   0    Graceful shutdown via signal
#
# NOTES
#   - Certbot only renews certificates that are close to expiration
#   - The deploy-hook ensures nginx picks up renewed certificates
#   - Renewal failures are logged but don't stop the loop
#
set -euo pipefail
. /scripts/utils.sh

# How often to check for renewal (default: 1 day)
INTERVAL=${CERT_RENEW_INTERVAL:-86400}

trap 'log "cert_renew loop terminated." INFO; exit 0' INT TERM

log "Starting background renew loop every $((INTERVAL / 3600)) h."

while sleep "$INTERVAL"; do
    if certbot renew --quiet \
        --config-dir /data/certificates \
        --work-dir /data/certificates/work \
        --logs-dir /data/certificates/logs \
        --deploy-hook "nginx -s reload"; then
        log "certbot renew: nothing to do."
    else
        log "certbot renew failed." ERROR
    fi
done
