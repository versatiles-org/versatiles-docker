#!/usr/bin/env bash
set -euo pipefail
. /scripts/utils.sh # brings in log()

# how often to check (default: 1 day)
INTERVAL=${CERT_RENEW_INTERVAL:-86400}

trap 'log "cert_renew loop terminated." INFO; exit 0' INT TERM

log "Starting background renew loop every $((INTERVAL / 3600)) h." INFO

while sleep "$INTERVAL"; do
    if certbot renew --quiet \
        --config-dir /data/certificates \
        --work-dir /data/certificates/work \
        --logs-dir /data/certificates/logs \
        --deploy-hook "nginx -s reload"; then
        log "certbot renew: nothing to do." INFO
    else
        log "certbot renew failed." ERROR
    fi
done
