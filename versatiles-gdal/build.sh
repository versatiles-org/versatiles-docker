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
    
    output=$(docker run --rm "versatiles-gdal" -V 2>&1 || true)
    expected="versatiles ${VER#v}"
    if [[ "$output" != "$expected" ]]; then
        printf "❌ Test 1 failed: expected '$expected', got '$output'\n" >&2
        exit 1
    fi

    mkdir -p ../testdata/temp
    output=$(docker run --rm -v ../testdata:/data versatiles-gdal convert liechtenstein.vpl ./temp/liechtenstein.mbtiles 2>&1 || true)
    expected="finished converting tiles"
    if [[ "$output" != *"$expected" ]]; then
        echo "❌ Test 2 failed: expected output to end with '$expected', got '$output'" >&2
        exit 1
    fi
    file_size=$(ls -lh ../testdata/temp/liechtenstein.mbtiles | awk '{print $5}')
    rm -rf ../testdata/temp
    if [[ $file_size != "16M" ]]; then
        echo "❌ Test 2 failed: expected output file size to be '16MB', got '$file_size'" >&2
        exit 1
    fi

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
