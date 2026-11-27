#!/usr/bin/env bash
set -euo pipefail

# Tells whether a published image lacks package updates that its distribution
# has released: on Alpine any update (a stable branch gets fixes only), on
# Debian and Ubuntu updates from the security archive. Pulls the image and asks
# its own package manager, as root, with the image's network access.
#
# Usage: scripts/check_updates.sh [--list] <image>
#
# Exits 0 when there are updates, 1 when there are none, 2 when the image can't
# be checked (no package manager, or it doesn't run). Prints nothing unless
# --list is given: which packages a published image lacks is a security finding,
# and .github/workflows/rebuild-on-updates.yml runs this where the log is
# public. --list prints them, for a look by hand.

list=false
if [ "${1:-}" = "--list" ]; then
    list=true
    shift
fi
image=${1:?Usage: scripts/check_updates.sh [--list] <image>}

# Alpine: every line of `apk -u list` is an update. Debian and Ubuntu: a line of
# `apt list --upgradable` names the archives the new version is in, such as
# "trixie-security" or "noble-updates,noble-security".
code=0
updates=$(docker run --rm --pull always --quiet --user root --entrypoint sh "$image" -c '
    if command -v apk >/dev/null; then
        apk update -q >/dev/null && apk -u list 2>/dev/null
    elif command -v apt-get >/dev/null; then
        apt-get update -qq >/dev/null && { apt list --upgradable 2>/dev/null | grep -e "-security" || true; }
    else
        exit 3
    fi' 2>/dev/null) || code=$?

if [ "$code" -ne 0 ]; then
    echo "Error: $image can't be checked (exit code $code)." >&2
    exit 2
fi
if $list && [ -n "$updates" ]; then
    echo "$updates"
fi
[ -n "$updates" ]
