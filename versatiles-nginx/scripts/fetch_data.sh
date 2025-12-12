#!/usr/bin/env bash
#
# fetch_data.sh — Download and prepare tile data sources
#
# DESCRIPTION
#   Downloads tile data files from download.versatiles.org and optionally
#   crops them to a specified bounding box. Files are cached in /data/tiles
#   and won't be re-downloaded if they already exist.
#
# REQUIRED ENVIRONMENT VARIABLES
#   TILE_SOURCES    Comma-separated list of tile files to download
#                   Supported formats: *.versatiles, *.mbtiles, *.pmtiles
#                   Example: "osm.versatiles,hillshade.versatiles"
#
# OPTIONAL ENVIRONMENT VARIABLES
#   BBOX    Geographic bounding box for cropping tiles (lng_min,lat_min,lng_max,lat_max)
#           Example: "13.0,52.3,13.8,52.7" (Berlin area)
#           When set, tiles are cropped using versatiles convert with 3-tile border
#
# BEHAVIOR
#   1. Validate TILE_SOURCES and optional BBOX format
#   2. For each tile source:
#      - Check if file already exists in /data/tiles/
#      - If not, download from https://download.versatiles.org/
#      - If BBOX is set, crop tiles using versatiles convert
#      - Otherwise, download full file with curl
#      - Use .part extension during download, rename when complete
#   3. Output space-separated list of tile paths to stdout
#
# OUTPUT
#   Prints space-separated list of tile file paths to stdout for use by caller
#
# EXIT CODES
#   0    All tiles fetched successfully
#   1    Required environment variable missing, invalid BBOX, or download failed
#
# EXAMPLES
#   TILE_SOURCES="osm.versatiles" ./fetch_data.sh
#   TILE_SOURCES="osm.versatiles,hillshade.versatiles" BBOX="13.0,52.3,13.8,52.7" ./fetch_data.sh
#
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
    log "No tile sources requested." WARN
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
            log "Fetching $src inside bounding box $BBOX …"
            if versatiles convert --bbox "$BBOX" --bbox-border 3 "$url" "$tmp"; then
                mv "$tmp" "$target"
            else
                rm -f "$tmp"
                log "versatiles convert failed for $src" ERROR
                exit 1
            fi
        else
            log "Fetching $src …"
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
