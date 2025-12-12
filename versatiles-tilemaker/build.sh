#!/usr/bin/env bash
# Build script for the "versatiles‑tilemaker" image.
#
# Flow
# ────
#  1. Build a host‑architecture image (`--load`) so we can smoke–test it locally
#     unless the user asked for `--push` *without* tests.
#  2. Optionally run a quick container‑starts smoke‑test (`--testing` flag).
#  3. Optionally build & push the real multi‑arch image (`--push` flag).
#
# Flags are parsed by utils.sh → parse_arguments.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag "systemed/tilemaker")
NAME="versatiles-tilemaker"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build & load (needed for local tests)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building image"
    build_load_image versatiles-tilemaker "$NAME" "latest" "./versatiles-tilemaker/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-test …"
    expected=$'Arguments required: <pbf-url> <name> [bbox]\n       bbox default: -180,-86,180,86'

    output=$(docker run --rm "${NAME}:latest" || true)

    if [[ "$output" != "$expected" ]]; then
        printf "❌  Unexpected output:\n%s\n" "$output" >&2
        exit 1
    fi
    
    echo "✅ Images tested successfully."
fi

###############################################################################
# 3. Multi‑arch push (only if requested)
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing multi-arch image …"
    build_push_image versatiles-tilemaker "$NAME" "latest,$VER" "./versatiles-tilemaker/Dockerfile"
    update_docker_description versatiles-tilemaker
fi
