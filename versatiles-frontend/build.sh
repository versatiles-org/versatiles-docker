#!/usr/bin/env bash
# Build script for the "versatiles-frontend" image family.
#
#  Flow:
#    1. Always build single‑arch (host) images so we can smoke‑test them locally
#       *unless* the user passed --push without --testing.
#    2. Optionally run the tests (‒-test / ‒-testing).
#    3. Optionally build + push the multi‑arch images (‒-push).
#
#  Flags are parsed by utils.sh → parse_arguments().
#
set -euo pipefail
cd "$(dirname "$0")/.."

# ── Shared helpers ───────────────────────────────────────────────────────────
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
NAME="versatiles-frontend"

echo "👷 Building $NAME Docker images for version $VER"

# Helper function for getting millisecond timestamps
get_timestamp_ms() {
    date +%s%N | cut -b1-13
}

# Test shutdown time - verify containers respond to SIGTERM in <1s
# This validates that tini is properly installed and configured
test_shutdown_time() {
    local image="$1"

    echo "  🧪 Testing shutdown time..."

    # Start a long-running server container
    CONTAINER_ID=$(docker run -d --rm -v "$(pwd)"/testdata:/data "$image" serve chioggia.versatiles)

    # Give the server a moment to initialize
    sleep 0.5

    # Measure how long docker stop takes (sends SIGTERM, waits for graceful shutdown)
    start_time=$(get_timestamp_ms)
    docker stop --time=3 "$CONTAINER_ID" >/dev/null 2>&1 || true
    end_time=$(get_timestamp_ms)
    duration=$(( end_time - start_time ))

    echo "  ⏱️  Shutdown time: ${duration}ms"

    # Fail if shutdown takes longer than 1 second
    if [[ $duration -ge 1000 ]]; then
        echo "  ❌ Shutdown took too long: ${duration}ms (expected < 1000ms)" >&2
        exit 1
    fi
}

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    build_load_image versatiles-debian "$NAME" debian "./versatiles-frontend/Dockerfile"
    build_load_image versatiles-alpine "$NAME" alpine "./versatiles-frontend/Dockerfile"
    build_load_image versatiles-scratch "$NAME" scratch "./versatiles-frontend/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"

    TEST_DIR=$(readlink -f "./testdata/")

    test_image() {
        local image="$1"
        echo "  🧪 Testing: $image"

        TMP_DIR=$(mktemp -d)
        # Start the container in background (serves chioggia.versatiles)
        echo "    ▶️ Starting server..."
        CONTAINER_ID=$(docker run -d --rm -v "$TEST_DIR":/data -p 8080:8080 "$image" chioggia.versatiles)

        # Wait for the server to come up
        sleep 1

        # Try fetching a single tile
        TILE_URL="http://localhost:8080/tiles/chioggia/14/8750/5880"
        TILE_PATH="$TMP_DIR/tile.pbf"
        echo "    ⬇️ Downloading $TILE_URL"
        curl -s "$TILE_URL" -o "$TILE_PATH" || {
            echo "    ❌ Failed to download tile from $TILE_URL"
            docker logs "$CONTAINER_ID" || true
            docker kill "$CONTAINER_ID" >/dev/null 2>&1 || true
            exit 1
        }

        # Stop the container
        docker kill "$CONTAINER_ID" >/dev/null 2>&1 || true

        # Check tile file size
        TILE_SIZE=$(wc -c "$TILE_PATH" | awk '{print $1}')
        echo "    📦 Tile size: $TILE_SIZE"

        # Sanity check: ensure nonzero tile
        if [[ "$TILE_SIZE" != 48679 ]]; then
            echo "    ❌ Tile size check failed (expected 48679 bytes, got $TILE_SIZE)"
            exit 1
        fi
    }

    test_image "$NAME:debian"
    test_shutdown_time "$NAME:debian"

    test_image "$NAME:alpine"
    test_shutdown_time "$NAME:alpine"

    test_image "$NAME:scratch"

    echo "✅ All images tested successfully."
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-debian "$NAME" "debian,$VER-debian" "./versatiles-frontend/Dockerfile"
    build_push_image versatiles-alpine "$NAME" "alpine,$VER-alpine,latest,$VER" "./versatiles-frontend/Dockerfile"
    build_push_image versatiles-scratch "$NAME" "scratch,$VER-scratch" "./versatiles-frontend/Dockerfile"

    update_docker_description versatiles-frontend
fi
