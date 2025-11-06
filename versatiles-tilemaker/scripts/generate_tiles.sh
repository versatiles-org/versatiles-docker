#!/usr/bin/env bash
#
# generate_tiles.sh  <PBF‑URL>  <NAME>  [BBOX]
#
# Downloads an OpenStreetMap PBF extract, converts it to MBTiles via Tilemaker,
# then re‑encodes it to VersaTiles format. The resulting archive is placed in
# /app/result/<NAME>.versatiles.
#
# ──────────────────────────────────────────────────────────────────────────────
# 📘 Documentation
#
# USAGE
#   ./generate_tiles.sh <PBF-URL> <NAME> [BBOX]
#
#   <PBF-URL>  HTTP(S) URL to an .pbf extract (e.g. from Geofabrik)
#   <NAME>     Base name for the resulting archive written to /app/result/<NAME>.versatiles
#   [BBOX]     Optional lon/lat bounding box: minLon,minLat,maxLon,maxLat
#              Defaults to -180,-86,180,86
#
# PIPELINE OVERVIEW
#   1) Download .pbf → /app/data/input.pbf
#   2) osmium renumber  → /app/data/prepared.pbf
#   3) tilemaker render → /app/data/output.mbtiles
#   4) versatiles convert (.mbtiles → .versatiles)
#   5) Move result to /app/result/<NAME>.versatiles
#
# ENVIRONMENT VARIABLES
#   RAMDISK_DIR
#       Optional absolute path that points to a *pre-mounted* tmpfs to speed up
#       reads of output.mbtiles during conversion. If provided and suitable,
#       the script copies /app/data/output.mbtiles into this tmpfs and reads
#       from there. If the tmpfs is not large enough or not a tmpfs, the script
#       falls back to using the on-disk file in /app/data.
#       Example (docker-compose):
#         tmpfs:
#           - /app/data/ramdisk:size=8g,mode=1777
#         environment:
#           RAMDISK_DIR: /app/data/ramdisk
#
#   STRICT_TMPFS (default: 0)
#       If set to 1, the script will *abort* when no suitable tmpfs is available
#       (or if copy into tmpfs fails) instead of falling back to disk. Useful for
#       CI or environments that must guarantee RAM-backed reads.
#
# DIRECTORY LAYOUT (inside the container)
#   /app/data         Working directory for downloads and intermediate files
#   /app/data/tmp     Tilemaker temporary store (deleted after use)
#   /app/data/ramdisk Optional pre-mounted tmpfs (if provided by docker as tmpfs)
#   /app/result       Final output location (<NAME>.versatiles)
#
# HELPER FUNCTIONS
#   usage()
#       Prints a short usage hint and exits with code 1 when required args are missing.
#
#   require_cmd(<binary>)
#       Verifies a required executable exists in PATH; exits with code 1 if missing.
#
#   choose_tmpfs(<candidate-path>, <required-bytes>) → echoes <resolved-path> | returns 1
#       Accepts a candidate directory and the required capacity (in bytes). Resolves
#       the path, checks that it is a tmpfs and that available capacity is ≥ required.
#       On success, echoes the resolved path to stdout; on failure, returns non-zero.
#
#   cleanup()
#       Removes /app/data/tmp on exit. Registered via `trap cleanup EXIT`.
#
# EXIT BEHAVIOR
#   • Any failing step exits the script (set -euo pipefail).
#   • When STRICT_TMPFS=1 and no suitable tmpfs is available, the script exits with code 1.
#   • Otherwise, the script gracefully falls back to disk-backed reads.

set -euo pipefail

###########################################################################
# 🛠  Helper functions
###########################################################################
# Print a short usage hint and exit
usage() {
    echo "Arguments required: <pbf-url> <name> [bbox]"
    echo "       bbox default: -180,-86,180,86"
    exit 1
}

# Ensure a required binary is available
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command '$1' not found." >&2
        exit 1
    }
}

# Validate candidate tmpfs and ensure capacity ≥ required_bytes
choose_tmpfs() {
    local candidate="$1"
    local required_bytes="$2"
    local target
    target="$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")"

    # Check if candidate is a tmpfs
    awk -v p="$target" '($2==p && $3=="tmpfs"){found=1} END{exit(found?0:1)}' /proc/mounts || return 1

    # Check available space vs required bytes
    local avail_bytes=$(df -B1 "$target" | awk 'NR==2 {print $4}')
    if [ "$avail_bytes" -lt "$required_bytes" ]; then
        echo "⚠️  tmpfs $target may be too small (need ~$((required_bytes/1073741824)) GB, available ~$((avail_bytes/1073741824)) GB). Reverting to disk."
        return 1
    fi

    echo "$target"
}

###########################################################################
# 🔎  Sanity checks & argument parsing
###########################################################################
[[ $# -ge 2 ]] || usage

PBF_URL=$1
TILE_NAME=$2
TILE_BBOX=${3:--180,-86,180,86}

: "${STRICT_TMPFS:=0}"

[[ "$PBF_URL" =~ ^https?:// ]] || {
    echo "First argument must be a valid URL"
    exit 1
}
[[ -n "$TILE_NAME" ]] || {
    echo "Second argument must be a name"
    exit 1
}

for cmd in aria2c osmium tilemaker versatiles df stat; do
    require_cmd "$cmd"
done

###########################################################################
# 📁  Directory layout
###########################################################################
DATA_DIR="/app/data"
TMP_DIR="${DATA_DIR}/tmp"
RAMDISK_DEFAULT_DIR="${DATA_DIR}/ramdisk"

mkdir -p "$DATA_DIR" "$TMP_DIR"

###########################################################################
# 🚿  Cleanup on exit
###########################################################################
# Remove temporary working directory on exit
cleanup() {
    echo "Cleaning up…"
    rm -rf "$TMP_DIR"
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
aria2c --seed-time=0 --dir="$DATA_DIR" "$PBF_URL"

PBF_FILE=$(find "$DATA_DIR" -maxdepth 1 -type f -name '*.pbf' | head -n 1)
[[ -n "$PBF_FILE" ]] || {
    echo "No PBF file found after download"
    exit 1
}

mv "$PBF_FILE" "$DATA_DIR/input.pbf"

###########################################################################
# 🛠  Prepare PBF for Tilemaker
###########################################################################
echo "🔃  Renumbering PBF…"
time osmium renumber --progress -o "$DATA_DIR/prepared.pbf" "$DATA_DIR/input.pbf"
rm "$DATA_DIR/input.pbf"

###########################################################################
# 🖼  Generate MBTiles with Tilemaker
###########################################################################
echo "🧱  Rendering tiles…"
time tilemaker \
    --input "$DATA_DIR/prepared.pbf" \
    --config config.json \
    --process process.lua \
    --bbox "$TILE_BBOX" \
    --output "$DATA_DIR/output.mbtiles" \
    --compact \
    --store "$TMP_DIR"

rm -rf "$TMP_DIR"
rm -f "$DATA_DIR/prepared.pbf"

###########################################################################
# 🔄  Convert MBTiles → VersaTiles
###########################################################################
echo "🚀  Converting to VersaTiles…"

# Determine whether we can use an existing tmpfs
# Priority:
# 1) Environment variable RAMDISK_DIR pointing to a mounted tmpfs
# 2) Pre-mounted tmpfs at $RAMDISK_DEFAULT_DIR (e.g., via Docker tmpfs)
# 3) /dev/shm (typically tmpfs) as fallback
# 4) Otherwise: no ramdisk; convert directly
#
# If no suitable tmpfs is found (or too small), we revert to disk unless
# STRICT_TMPFS=1 is set, in which case the script aborts.

RAMDISK_DIR="${RAMDISK_DIR:-}"

FILE_SIZE_BYTES=$(stat -c %s "$DATA_DIR/output.mbtiles")
REQUIRED_BYTES=$((FILE_SIZE_BYTES + FILE_SIZE_BYTES / 10)) # +10% safety margin
CHOSEN_TMPFS=""
if [ -n "$RAMDISK_DIR" ] && [ -d "$RAMDISK_DIR" ]; then
    CHOSEN_TMPFS=$(choose_tmpfs "$RAMDISK_DIR" "$REQUIRED_BYTES") || CHOSEN_TMPFS=""
elif [ -d "$RAMDISK_DEFAULT_DIR" ]; then
    CHOSEN_TMPFS=$(choose_tmpfs "$RAMDISK_DEFAULT_DIR" "$REQUIRED_BYTES") || CHOSEN_TMPFS=""
elif [ -d /dev/shm ]; then
    mkdir -p /dev/shm/versatiles
    CHOSEN_TMPFS=$(choose_tmpfs /dev/shm "$REQUIRED_BYTES") && CHOSEN_TMPFS="/dev/shm/versatiles" || CHOSEN_TMPFS=""
fi

if [ -z "$CHOSEN_TMPFS" ] && [ "$STRICT_TMPFS" = "1" ]; then
    echo "❌ STRICT_TMPFS=1 but no suitable tmpfs available. Aborting."
    exit 1
fi

if [ -n "$CHOSEN_TMPFS" ]; then
    echo "→ Using tmpfs at $CHOSEN_TMPFS"
    mkdir -p "$CHOSEN_TMPFS"
    SRC_MB_DISK="$DATA_DIR/output.mbtiles"
    TARGET_MB="$CHOSEN_TMPFS/output.mbtiles"

    if cp -f --reflink=auto "$SRC_MB_DISK" "$TARGET_MB"; then
        # quick size verification to catch truncated copies
        if [ "$(stat -c %s "$TARGET_MB")" -eq "$(stat -c %s "$SRC_MB_DISK")" ]; then
            rm -f "$SRC_MB_DISK"
            SRC_DIR="$CHOSEN_TMPFS"
        else
            echo "⚠️  Copy verification failed (size mismatch). Using disk source instead."
            rm -f "$TARGET_MB" || true
            if [ "$STRICT_TMPFS" = "1" ]; then
                echo "❌ STRICT_TMPFS=1 and tmpfs copy failed. Aborting."
                exit 1
            fi
            SRC_DIR="$DATA_DIR"
        fi
    else
        echo "⚠️  Copy to tmpfs failed. Using disk source instead."
        if [ "$STRICT_TMPFS" = "1" ]; then
            echo "❌ STRICT_TMPFS=1 and tmpfs copy failed. Aborting."
            exit 1
        fi
        SRC_DIR="$DATA_DIR"
    fi
else
    echo "→ No tmpfs detected; converting directly from disk"
    SRC_DIR="$DATA_DIR"
fi

time versatiles convert -c brotli \
    "$SRC_DIR/output.mbtiles" \
    "$DATA_DIR/output.versatiles"

###########################################################################
# 📦  Deliver result
###########################################################################
echo "📤  Moving result to ./result…"
mkdir -p /app/result
mv "$DATA_DIR/output.versatiles" "/app/result/${TILE_NAME}.versatiles"

echo "✅  Done: ./result/${TILE_NAME}.versatiles"
