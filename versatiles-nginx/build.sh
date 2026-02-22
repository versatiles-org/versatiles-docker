#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load shared helpers
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
NAME="versatiles-nginx"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-nginx "$NAME" latest "./versatiles-nginx/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"

    output="'FRONTEND' is required (Allowed: standard|dev|min|tiny|none)"
    result=$(docker run --rm "$NAME:latest" 2>&1 || true)
    if [[ "$result" != *"$output"* ]]; then
        echo "❌ Test failed: expected \"$result\" to contain \"$output\"" >&2
        exit 1
    fi

    output="'TILE_SOURCES' is required"
    result=$(docker run --rm -e "FRONTEND=min" "$NAME:latest" 2>&1 || true)
    if [[ "$result" != *"$output"* ]]; then
        echo "❌ Test failed: expected \"$result\" to contain \"$output\"" >&2
        exit 1
    fi

    echo "✅ All images tested successfully."
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-nginx "$NAME" "latest,$VER" "./versatiles-nginx/Dockerfile"
    update_docker_description versatiles-nginx
fi
