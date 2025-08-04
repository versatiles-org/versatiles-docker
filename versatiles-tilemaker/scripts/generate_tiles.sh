#!/usr/bin/env bash
#
# generate_tiles.sh  <PBF‑URL>  <NAME>  [BBOX]
#
# Downloads an OpenStreetMap PBF extract, converts it to MBTiles via Tilemaker,
# then re‑encodes it to Versatiles format. The resulting archive is placed in
# /app/result/<NAME>.versatiles.
#
# Dependencies: aria2c, osmium, tilemaker, versatiles, mount, stat, perl
#
# Environment variables:
#   DATADIR        Working directory for intermediate artefacts (default: /app/data)
#   TMPFS_SIZE_GB  Override automatic tmpfs sizing in GB
#

set -euxo pipefail

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
DATADIR="${DATADIR:-/app/data}"
TMPDIR="${DATADIR}/tmp"
RAMDISK_MOUNT="${DATADIR}/ramdisk"

mkdir -p "$DATADIR" "$TMPDIR"

###########################################################################
# 🚿  Cleanup on exit
###########################################################################
cleanup() {
    echo "Cleaning up…"
    umount -q "$RAMDISK_MOUNT" 2>/dev/null || true
    rm -rf "$TMPDIR" "$RAMDISK_MOUNT"
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
# 🔄  Convert MBTiles → Versatiles
###########################################################################
echo "🚀  Converting to Versatiles…"
FILE_SIZE_BYTES=$(stat -c %s "$DATADIR/output.mbtiles")

if [[ -n "${TMPFS_SIZE_GB:-}" ]]; then
    RAM_GB="$TMPFS_SIZE_GB"
else
    RAM_GB=$(perl -E "use POSIX;say ceil($FILE_SIZE_BYTES/1073741824 + 0.3)")
fi

mkdir -p "$RAMDISK_MOUNT"
mount -t tmpfs -o size=${RAM_GB}G tmpfs "$RAMDISK_MOUNT"

mv "$DATADIR/output.mbtiles" "$RAMDISK_MOUNT"

time versatiles convert -c brotli \
    "$RAMDISK_MOUNT/output.mbtiles" \
    "$DATADIR/output.versatiles"

###########################################################################
# 📦  Deliver result
###########################################################################
echo "📤  Moving result to /app/result…"
mkdir -p /app/result
mv "$DATADIR/output.versatiles" "/app/result/${TILE_NAME}.versatiles"

echo "✅  Done: /app/result/${TILE_NAME}.versatiles"
