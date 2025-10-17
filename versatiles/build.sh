#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Load shared helpers
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
NAME="versatiles"

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
        
        TEST_DIR=$(readlink -f "../testdata/")
        mkdir -p $TEST_DIR/temp
        output=$(docker run --rm -v $TEST_DIR:/data "$image" convert chioggia.versatiles ./temp/chioggia.pmtiles 2>&1 || true)
        expected="finished converting tiles"
        if [[ "$output" != *"$expected" ]]; then
            echo "❌ Test 2 failed: expected output to end with '$expected', got '$output'" >&2
            exit 1
        fi
        file_size=$(ls -lh $TEST_DIR/temp/chioggia.pmtiles | awk '{print $5}')
        rm -rf $TEST_DIR/temp
        if [[ $file_size != "12M" ]]; then
            echo "❌ Test 2 failed: expected output file size to be '12MB', got '$file_size'" >&2
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
    build_push_image versatiles-debian "$NAME" "debian,$VER-debian"
    build_push_image versatiles-alpine "$NAME" "alpine,$VER-alpine,latest,$VER"
    build_push_image versatiles-scratch "$NAME" "scratch,$VER-scratch"
    update_docker_description versatiles
fi
