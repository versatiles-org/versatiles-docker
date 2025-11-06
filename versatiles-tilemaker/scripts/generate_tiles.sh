#!/usr/bin/env bash
#
# generate_tiles.sh  <PBF‑URL>  <NAME>  [BBOX]
#
# Downloads an OpenStreetMap PBF extract, converts it to MBTiles via Tilemaker,
# then re‑encodes it to VersaTiles format. The resulting archive is placed in
# /app/result/<NAME>.versatiles.
#
# Dependencies: aria2c, osmium, tilemaker, versatiles

set -euo pipefail

###########################################################################
# 🛠  Helper functions
###########################################################################
usage() {
    echo "Arguments required: <pbf-url> <name> [bbox]"
    echo "       bbox default: -180,-86,180,86"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command '$1' not found." >&2
        exit 1
    }
}

###########################################################################
# 🔎  Sanity checks & argument parsing
###########################################################################
[[ $# -ge 2 ]] || usage

PBF_URL=$1
TILE_NAME=$2
TILE_BBOX=${3:--180,-86,180,86}

[[ "$PBF_URL" =~ ^https?:// ]] || {
    echo "First argument must be a valid URL"
    exit 1
}
[[ -n "$TILE_NAME" ]] || {
    echo "Second argument must be a name"
    exit 1
}

for cmd in aria2c osmium tilemaker versatiles; do
    require_cmd "$cmd"
done

###########################################################################
# 📁  Directory layout
###########################################################################
DATADIR="/app/data"
TMPDIR="${DATADIR}/tmp"
RAMDISK_MOUNT="${DATADIR}/ramdisk"

mkdir -p "$DATADIR" "$TMPDIR"

###########################################################################
# 🚿  Cleanup on exit
###########################################################################
cleanup() {
    echo "Cleaning up…"
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

###########################################################################
# 🚚  Download PBF
###########################################################################
echo "GENERATE OSM VECTOR TILES:"
echo "   URL:  $PBF_URL"
echo "   NAME: $TILE_NAME"
echo "   BBOX: $TILE_BBOX"

echo "📥  Downloading data…"
aria2c --seed-time=0 --dir="$DATADIR" "$PBF_URL"

PBF_FILE=$(find "$DATADIR" -maxdepth 1 -type f -name '*.pbf' | head -n 1)
[[ -n "$PBF_FILE" ]] || {
    echo "No PBF file found after download"
    exit 1
}

mv "$PBF_FILE" "$DATADIR/input.pbf"

###########################################################################
# 🛠  Prepare PBF for Tilemaker
###########################################################################
echo "🔃  Renumbering PBF…"
time osmium renumber --progress -o "$DATADIR/prepared.pbf" "$DATADIR/input.pbf"
rm "$DATADIR/input.pbf"

###########################################################################
# 🖼  Generate MBTiles with Tilemaker
###########################################################################
echo "🧱  Rendering tiles…"
time tilemaker \
    --input "$DATADIR/prepared.pbf" \
    --config config.json \
    --process process.lua \
    --bbox "$TILE_BBOX" \
    --output "$DATADIR/output.mbtiles" \
    --compact \
    --store "$TMPDIR"

rm -rf "$TMPDIR"
rm -f "$DATADIR/prepared.pbf"

###########################################################################
# 🔄  Convert MBTiles → VersaTiles
###########################################################################
echo "🚀  Converting to VersaTiles…"

# Determine whether we can use an existing tmpfs
# Priority:
# 1) Environment variable RAMDISK_DIR pointing to a mounted tmpfs
# 2) Pre-mounted tmpfs at $RAMDISK_MOUNT (e.g., via Docker tmpfs)
# 3) /dev/shm (typically tmpfs) as fallback
# 4) Otherwise: no ramdisk; convert directly

RAMDISK_DIR="${RAMDISK_DIR:-}"

is_tmpfs() {
    local target
    target="$(readlink -f "$1" 2>/dev/null || echo "$1")"
    awk -v p="$target" '($2==p && $3=="tmpfs"){found=1} END{exit(found?0:1)}' /proc/mounts
}

CHOSEN_TMPFS=""
if [ -n "$RAMDISK_DIR" ] && [ -d "$RAMDISK_DIR" ] && is_tmpfs "$RAMDISK_DIR"; then
    CHOSEN_TMPFS="$RAMDISK_DIR"
elif [ -d "$RAMDISK_MOUNT" ] && is_tmpfs "$RAMDISK_MOUNT"; then
    CHOSEN_TMPFS="$RAMDISK_MOUNT"
elif [ -d /dev/shm ] && is_tmpfs /dev/shm; then
    CHOSEN_TMPFS="/dev/shm/versatiles"
    mkdir -p "$CHOSEN_TMPFS"
fi

if [ -n "$CHOSEN_TMPFS" ]; then
    echo "→ Using tmpfs at $CHOSEN_TMPFS"
    mkdir -p "$CHOSEN_TMPFS"
    mv "$DATADIR/output.mbtiles" "$CHOSEN_TMPFS/"
    SRC_DIR="$CHOSEN_TMPFS"
else
    echo "→ No tmpfs detected; converting directly from disk"
    SRC_DIR="$DATADIR"
fi

time versatiles convert -c brotli \
    "$SRC_DIR/output.mbtiles" \
    "$DATADIR/output.versatiles"

###########################################################################
# 📦  Deliver result
###########################################################################
echo "📤  Moving result to /app/result…"
mkdir -p /app/result
mv "$DATADIR/output.versatiles" "/app/result/${TILE_NAME}.versatiles"

echo "✅  Done: /app/result/${TILE_NAME}.versatiles"
