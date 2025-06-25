#!/usr/bin/env bash
set -euo pipefail
. /scripts/utils.sh

require TILE_SOURCES "comma-separated list of *.versatiles, *.mbtiles or *.pmtiles"

# Validate BBOX format (expected: "lng_min,lat_min,lng_max,lat_max")
if [ -n "${BBOX:-}" ]; then
    if ! echo "$BBOX" | grep -Eq '^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$'; then
        log "Malformed BBOX: '$BBOX'. Expected 'lng_min,lat_min,lng_max,lat_max'." ERROR
        exit 1
    fi
fi

if [ -z "$TILE_SOURCES" ]; then
    log "No tile sources requested." INFO
    exit 0
fi

mkdir -p /data/tiles
IFS=',' read -ra TS <<<"$TILE_SOURCES"
args=""

for src in "${TS[@]}"; do
    [ -z "$src" ] && continue
    target="/data/tiles/$src"
    args+=" $target"

    if [ ! -f "$target" ]; then
        tmp="${target%.*}.part.${target##*.}"
        url="https://download.versatiles.org/$src"

        if [ -n "${BBOX:-}" ]; then
            log "Fetching $src inside bounding box $BBOX …" INFO
            if versatiles convert --bbox "$BBOX" --bbox-border 3 "$url" "$tmp"; then
                mv "$tmp" "$target"
            else
                rm -f "$tmp"
                log "versatiles convert failed for $src" ERROR
                exit 1
            fi
        else
            log "Fetching $src …" INFO
            if curl -fL --retry 3 --retry-delay 2 --retry-max-time 30 "$url" -o "$tmp"; then
                mv "$tmp" "$target"
            else
                rm -f "$tmp"
                log "Download failed for $src" ERROR
                exit 1
            fi
        fi
    fi
done

printf '%s' "${args}"
