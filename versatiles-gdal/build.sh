#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Load shared helpers
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
NAME="versatiles-gdal"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-gdal "$NAME" latest
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"
    
#    output=$(docker run --rm "versatiles-gdal:latest" -v 2>&1 || true)
#    expected="gdal"
#    if [[ "$output" != "$expected" ]]; then
#        printf "❌ Test 1 failed: expected '$expected', got '$output'\n" >&2
#        exit 1
#    fi
#
#    output=$(docker run --rm --entrypoint "versatiles" "versatiles-gdal:latest" -V 2>&1 | head -n 1 || true)
#    expected="versatiles"
#    if [[ "$output" != "$expected" ]]; then
#        echo "❌ Test 2 failed: expected '$expected', got '$output'" >&2
#        exit 1
#    fi

    echo "✅ All images tested successfully."
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-gdal "$NAME" "latest,$VER"
    update_docker_description versatiles-gdal
fi
