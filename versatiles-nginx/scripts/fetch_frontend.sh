#!/usr/bin/env bash
#
# fetch_frontend.sh — Download VersaTiles frontend variant
#
# DESCRIPTION
#   Downloads the specified variant of the VersaTiles web frontend from GitHub
#   releases into /data/frontend, and keeps it up to date: the release tag it
#   came from is stored next to it, and it is downloaded again when the wanted
#   release differs. The frontend is a Brotli-compressed tarball.
#
# REQUIRED ENVIRONMENT VARIABLES
#   FRONTEND    Frontend variant to download
#               Allowed values:
#                 - standard, default, 1, true, yes  → Standard frontend
#                 - dev                              → Development frontend
#                 - min                              → Minimal frontend
#                 - tiny                             → Tiny frontend
#                 - blank                            → Blank frontend (fonts + sprites only)
#                 - none, no, 0, false, off, disabled → No frontend
#
# OPTIONAL ENVIRONMENT VARIABLES
#   FRONTEND_VERSION  Release tag to use, such as "v3.20.0" (default: "latest",
#                     the latest release, looked up at every start)
#
# BEHAVIOR
#   1. Parse FRONTEND environment variable to determine variant
#   2. Exit early if frontend is disabled (none/no/0/false/off/disabled)
#   3. Find the wanted release tag: FRONTEND_VERSION, or the latest release
#   4. If /data/frontend/<variant>.br.tar.version names that tag, keep the
#      bundle. Otherwise download it (gzipped, decompressed to a Brotli tar)
#      and store its tag. A bundle without a tag file counts as outdated.
#   5. If GitHub can't be reached or the download fails, keep the bundle that
#      is there with a warning; fail only if there is none
#   6. Output --static argument to stdout for use by caller
#
# OUTPUT
#   Prints "--static /data/frontend/<variant>.br.tar" to stdout for use by entrypoint
#   Returns empty output if frontend is disabled
#
# EXIT CODES
#   0    Frontend fetched successfully, kept, or disabled
#   1    Required environment variable missing, invalid value, or no frontend
#        could be downloaded and none was there
#
# EXAMPLES
#   FRONTEND="standard" ./fetch_frontend.sh
#   FRONTEND="min" FRONTEND_VERSION="v3.20.0" ./fetch_frontend.sh
#   FRONTEND="none" ./fetch_frontend.sh
#
set -euo pipefail
. /scripts/utils.sh
require FRONTEND "Allowed: standard|dev|min|tiny|blank|none"

case "$FRONTEND" in
"default" | "standard" | "" | "1" | "true" | "yes") variant="frontend" ;;
"dev") variant="frontend-dev" ;;
"min") variant="frontend-min" ;;
"tiny") variant="frontend-tiny" ;;
"blank") variant="frontend-blank" ;;
"none" | "no" | "0" | "false" | "off" | "disabled")
    log "Frontend disabled."
    exit 0
    ;;
*)
    log "Unknown FRONTEND \"${FRONTEND}\". Allowed: standard|dev|min|tiny|blank|none" ERROR
    exit 1
    ;;
esac

mkdir -p /data/frontend
filename="${variant}.br.tar"
filepath="/data/frontend/${filename}"
tagpath="${filepath}.version"
releases="https://github.com/versatiles-org/versatiles-frontend/releases"

# The latest release tag, read from where /releases/latest redirects to
# (.../releases/tag/<tag>). Unlike the GitHub API, this has no rate limit.
latest_tag() {
    local url
    url=$(curl -sfI -o /dev/null -w '%{redirect_url}' --max-time 10 --retry 2 "$releases/latest") || return 1
    [[ "$url" == "$releases/tag/"?* ]] || return 1
    echo "${url##*/}"
}

# Keep the bundle that is there, or fail if there is none.
keep_cached() {
    if [ -f "$filepath" ]; then
        log "$1 Keeping the frontend from ${cached_tag:-an unknown release}." WARN
    else
        log "$1 No frontend to fall back to." ERROR
        exit 1
    fi
}

cached_tag=""
if [ -f "$filepath" ] && [ -f "$tagpath" ]; then
    cached_tag=$(cat "$tagpath")
fi

wanted_tag="${FRONTEND_VERSION:-latest}"
if [ "$wanted_tag" = "latest" ]; then
    wanted_tag=$(latest_tag) || wanted_tag=""
fi

if [ -z "$wanted_tag" ]; then
    keep_cached "Can't look up the latest frontend release on GitHub."
elif [ "$wanted_tag" != "$cached_tag" ]; then
    # Download the tag itself, not .../latest/..., so the bundle always matches
    # the tag stored with it, even if a release is published meanwhile.
    tmpfile="${filepath}.part"
    url="$releases/download/${wanted_tag}/${filename}.gz"
    log "Downloading $filename $wanted_tag …"
    if curl -#fL --retry 3 --retry-delay 2 --retry-max-time 30 "$url" | gzip -cd >"$tmpfile"; then
        mv "$tmpfile" "$filepath"
        # Written after the bundle, so a start that is interrupted in between
        # finds no matching tag and downloads again.
        echo "$wanted_tag" >"${tagpath}.part"
        mv "${tagpath}.part" "$tagpath"
    else
        rm -f "$tmpfile"
        keep_cached "Download of $filename $wanted_tag failed."
    fi
fi

# print argument string for entrypoint.sh to capture
echo "--static $filepath"
