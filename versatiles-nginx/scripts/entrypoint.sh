#!/usr/bin/env bash
set -euo pipefail

. /scripts/utils.sh

# Global argument accumulator for VersaTiles
VERSATILES_ARGS=""

# fix ownership of the unified volume
mkdir -p /data
chown -R vs:vs /data || true

# user defined static files
mkdir -p /data/static
VERSATILES_ARGS+=" --static /data/static"

/scripts/fetch_frontend.sh
/scripts/fetch_data.sh
/scripts/nginx_start.sh

############### start VersaTiles ############
log "Launching VersaTiles backend with arguments: ${VERSATILES_ARGS}"
exec su-exec vs:vs versatiles serve -p 8080 $VERSATILES_ARGS
