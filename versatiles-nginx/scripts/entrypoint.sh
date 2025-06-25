#!/usr/bin/env bash
set -euo pipefail

. /scripts/utils.sh

# Global argument accumulator for VersaTiles

# fix ownership of the unified volume
mkdir -p /data
chown -R vs:vs /data || true

# user defined static files
mkdir -p /data/static
versatiles_args="--static /data/static"
versatiles_args+=" $(/scripts/fetch_frontend.sh)"
versatiles_args+=" $(/scripts/fetch_data.sh)"

/scripts/nginx_start.sh

############### start VersaTiles ############
log "Launching VersaTiles backend with arguments: ${versatiles_args}"
exec su-exec vs:vs versatiles serve -p 8080 $versatiles_args
