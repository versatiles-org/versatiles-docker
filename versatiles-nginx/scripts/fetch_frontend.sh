#!/usr/bin/env bash
#
# fetch_frontend.sh — Download VersaTiles frontend variant
#
# DESCRIPTION
#   Downloads the specified variant of the VersaTiles web frontend from GitHub
#   releases. Files are cached in /data/frontend and won't be re-downloaded if
#   they already exist. The frontend is a Brotli-compressed tarball.
#
# REQUIRED ENVIRONMENT VARIABLES
#   FRONTEND    Frontend variant to download
#               Allowed values:
#                 - standard, default, 1, true, yes  → Standard frontend
#                 - dev                              → Development frontend
#                 - min                              → Minimal frontend
#                 - none, no, 0, false, off, disabled → No frontend
#
# BEHAVIOR
#   1. Parse FRONTEND environment variable to determine variant
#   2. Exit early if frontend is disabled (none/no/0/false/off/disabled)
#   3. Check if frontend file already exists in /data/frontend/
#   4. If not, download from GitHub releases (gzipped, decompress to Brotli tar)
#   5. Output --static argument to stdout for use by caller
#
# OUTPUT
#   Prints "--static /data/frontend/<variant>.br.tar" to stdout for use by entrypoint
#   Returns empty output if frontend is disabled
#
# EXIT CODES
#   0    Frontend fetched successfully or disabled
#   1    Required environment variable missing, invalid value, or download failed
#
# EXAMPLES
#   FRONTEND="standard" ./fetch_frontend.sh
#   FRONTEND="min" ./fetch_frontend.sh
#   FRONTEND="none" ./fetch_frontend.sh
#
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
    if curl -#fL --retry 3 --retry-delay 2 --retry-max-time 30 "$url" | gzip -cd >"$tmpfile"; then
        mv "$tmpfile" "$filepath"
    else
        rm -f "$tmpfile"
        log "Download failed for $filename" ERROR
        exit 1
    fi
fi

# print argument string for entrypoint.sh to capture
echo "--static $filepath"
