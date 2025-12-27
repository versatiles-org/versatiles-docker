#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load shared helpers
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
NAME="versatiles-gdal"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-gdal "$NAME" latest "./versatiles-gdal/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"
    
    output=$(docker run --rm "versatiles-gdal" -V 2>&1 || true)
    expected="versatiles ${VER#v}"
    if [[ "$output" != "$expected" ]]; then
        printf "  ❌ Test 1 failed: expected '%s', got '%s'\n" "$expected" "$output" >&2
        exit 1
    fi

    TEST_DIR=$(readlink -f "./testdata/")
    mkdir -p "$TEST_DIR/temp"
    output=$(docker run --rm -v "$TEST_DIR:/data" versatiles-gdal convert liechtenstein.vpl ./temp/liechtenstein.mbtiles 2>&1 || true)
    expected="finished converting tiles"
    if [[ "$output" != *"$expected" ]]; then
        echo "  ❌ Test 2 failed: expected output to end with '$expected', got '$output'" >&2
        exit 1
    fi
    file_size=$(wc -c "$TEST_DIR/temp/liechtenstein.mbtiles" | awk '{print $1}')
    rm -rf "$TEST_DIR/temp"
    if [[ $file_size -lt 16000000 ]]; then
        echo "  ❌ Test 2 failed: expected output file size to be greater than 16MB, got '$file_size'" >&2
        exit 1
    fi

    echo "✅ Image tested successfully."
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-gdal "$NAME" "latest,$VER" "./versatiles-gdal/Dockerfile"
    update_docker_description versatiles-gdal
fi
