#!/usr/bin/env bash
set -euo pipefail
. /scripts/utils.sh
require FRONTEND "Allowed: default|dev|min|none"

case "$FRONTEND" in
"default" | "standard") variant="frontend" ;;
"none" | "off" | "disabled")
    log "Frontend disabled."
    return 0
    ;;
"dev") variant="frontend-dev" ;;
"min") variant="frontend-min" ;;
*)
    log "Unknown FRONTEND \"${FRONTEND}\". Allowed: default|dev|min|none" ERROR
    exit 1
    ;;
esac

mkdir -p /data/frontend
filename="${variant}.br.tar"
filepath="/data/frontend/${filename}"

if [ ! -f "$filepath" ]; then
    tmpfile="${filepath}.part"
    url="https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/${filename}.gz"
    log "Downloading $filename …"
    if curl -fL --retry 3 --retry-delay 2 --retry-max-time 30 "$url" | gzip -cd >"$tmpfile"; then
        mv "$tmpfile" "$filepath"
    else
        rm -f "$tmpfile"
        log "Download failed for $filename" ERROR
        exit 1
    fi
fi

declare -g VERSATILES_ARGS="${VERSATILES_ARGS-} --static $filepath"
