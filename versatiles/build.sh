#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Load shared helpers
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
NAME="versatiles/versatiles"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-debian "$NAME" debian
    build_load_image versatiles-alpine "$NAME" alpine
    build_load_image versatiles-scratch "$NAME" scratch
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"

    test_image() {
        local image="$1"
        echo "  - $image"
        result=$(docker run --rm "$image" --version)
        if [ "$result" != "versatiles ${VER:1}" ]; then
            echo "❌ Version mismatch for $image: expected 'versatiles ${VER:1}', got '$result'" >&2
            exit 1
        fi
    }

    test_image "$NAME:debian"
    test_image "$NAME:alpine"
    test_image "$NAME:scratch"

    echo "✅ All images tested successfully."
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-debian "$NAME" debian "$VER-debian"
    build_push_image versatiles-alpine "$NAME" alpine "$VER-alpine" latest "$VER"
    build_push_image versatiles-scratch "$NAME" scratch "$VER-scratch"
    update_docker_description versatiles
fi
