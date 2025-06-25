#!/usr/bin/env bash
set -euo pipefail
. /scripts/utils.sh
require FRONTEND "Allowed: standard|dev|min|none"

case "$FRONTEND" in
"default" | "standard" | "" | "1" | "true" | "yes") variant="frontend" ;;
"dev") variant="frontend-dev" ;;
"min") variant="frontend-min" ;;
"none" | "no" | "0" | "false" | "off" | "disabled")
    log "Frontend disabled."
    exit 0
    ;;
*)
    log "Unknown FRONTEND \"${FRONTEND}\". Allowed: standard|dev|min|none" ERROR
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

# print argument string for entrypoint.sh to capture
echo "--static $filepath"
