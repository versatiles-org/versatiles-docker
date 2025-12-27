#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load shared helpers
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
NAME="versatiles"

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
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-debian "$NAME" debian "./versatiles/Dockerfile"
    build_load_image versatiles-alpine "$NAME" alpine "./versatiles/Dockerfile"
    build_load_image versatiles-scratch "$NAME" scratch "./versatiles/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"

    test_image() {
        local image="$1"
        echo "  🧪 Testing: $image"
        result=$(docker run --rm "$image" --version)
        if [ "$result" != "versatiles ${VER:1}" ]; then
            echo "  ❌ Version mismatch for $image: expected 'versatiles ${VER:1}', got '$result'" >&2
            exit 1
        fi
        
        TEST_DIR=$(readlink -f "./testdata/")
        mkdir -p "$TEST_DIR/temp"
        output=$(docker run --rm -v "$TEST_DIR:/data" "$image" convert chioggia.versatiles ./temp/chioggia.pmtiles 2>&1 || true)
        expected="finished converting tiles"
        if [[ "$output" != *"$expected" ]]; then
            echo "  ❌ Test 2 failed: expected output to end with '$expected', got '$output'" >&2
            exit 1
        fi
        file_size=$(wc -c "$TEST_DIR/temp/chioggia.pmtiles" | awk '{print $1}')
        rm -rf "$TEST_DIR/temp"
        if [[ $file_size -lt 12500000 ]]; then
            echo "  ❌ Test 2 failed: expected output file size to be greater than 12.5 MB, got '$file_size'" >&2
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
    build_push_image versatiles-debian "$NAME" "debian,$VER-debian" "./versatiles/Dockerfile"
    build_push_image versatiles-alpine "$NAME" "alpine,$VER-alpine,latest,$VER" "./versatiles/Dockerfile"
    build_push_image versatiles-scratch "$NAME" "scratch,$VER-scratch" "./versatiles/Dockerfile"
    update_docker_description versatiles
fi
