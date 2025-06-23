#!/usr/bin/env bash
set -euo pipefail
. /scripts/utils.sh

require TILE_SOURCES "comma-separated list of *.versatiles, *.mbtiles or *.pmtiles"

[ -z "$TILE_SOURCES" ] && {
    log "No tile sources requested." INFO
    return 0
}

mkdir -p /data/tiles
IFS=',' read -ra TS <<<"$TILE_SOURCES"

for src in "${TS[@]}"; do
    [ -z "$src" ] && continue
    target="/data/tiles/$src"

    if [ ! -f "$target" ]; then
        tmp="${target}.part"
        url="https://download.versatiles.org/$src"
        log "Fetching $src …" INFO

        if curl -fL --retry 3 --retry-delay 2 --retry-max-time 30 "$url" -o "$tmp"; then
            mv "$tmp" "$target"
        else
            rm -f "$tmp"
            log "Download failed for $src" ERROR
            exit 1
        fi
    fi

    # export so parent script sees the update even when sourced
    declare -g VERSATILES_ARGS="${VERSATILES_ARGS-} $target"
done
