#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load shared helpers
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh
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

    # Contract (see issue #47). gdal shipped /app/versatiles unreachable by name
    # until the PATH fix; only the entrypoint invocation was ever exercised.
    echo "  🧪 Contract: $NAME:latest"
    assert_image_config "$NAME:latest" '["/usr/bin/tini","--","/app/versatiles"]' "/data"
    assert_path_appends_app "$NAME:latest"
    assert_binary_resolves "$NAME:latest" versatiles /app/versatiles

    output=$(docker run --rm "$NAME:latest" -V 2>&1 || true)
    assert_eq "$NAME: -V" "$output" "versatiles ${VER#v}"

    TEST_DIR=$(readlink -f "./testdata/")
    mkdir -p "$TEST_DIR/temp"
    output=$(docker run --rm -v "$TEST_DIR:/data" "$NAME:latest" \
        convert liechtenstein.vpl ./temp/liechtenstein.mbtiles 2>&1 || true)
    assert_ends_with "$NAME: convert completes" "$output" "finished converting tiles"
    assert_min_size "$NAME: converted output" "$TEST_DIR/temp/liechtenstein.mbtiles" 16000000
    rm -rf "$TEST_DIR/temp"

    print_test_summary
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-gdal "$NAME" "latest,$VER" "./versatiles-gdal/Dockerfile"
    update_docker_description versatiles-gdal
fi
