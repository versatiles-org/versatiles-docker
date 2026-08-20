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
NAME="versatiles"

echo "👷 Building $NAME Docker images for version $VER"

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

    TEST_DIR=$(readlink -f "./testdata/")

    # Contract checks (see issue #47): these guard the entrypoint / workdir /
    # PATH surface that every documented `docker run` invocation depends on.
    # Inspect-only, so they also cover `scratch`, which ships no shell.
    test_contract() {
        local image="$1" entrypoint="$2"
        echo "  🧪 Contract: $image"
        assert_image_config "$image" "$entrypoint" "/data"
        assert_path_appends_app "$image"
    }

    test_image() {
        local image="$1" output
        echo "  🧪 Testing: $image"

        output=$(docker run --rm "$image" --version)
        assert_eq "$image: --version" "$output" "versatiles ${VER:1}"

        mkdir -p "$TEST_DIR/temp"
        output=$(docker run --rm -v "$TEST_DIR:/data" "$image" \
            convert chioggia.versatiles ./temp/chioggia.pmtiles 2>&1 || true)
        assert_ends_with "$image: convert completes" "$output" "finished converting tiles"
        assert_min_size "$image: converted output" "$TEST_DIR/temp/chioggia.pmtiles" 12500000
        rm -rf "$TEST_DIR/temp"
    }

    test_contract "$NAME:debian"  '["/usr/bin/tini","--","/app/versatiles"]'
    test_contract "$NAME:alpine"  '["/sbin/tini","--","/app/versatiles"]'
    test_contract "$NAME:scratch" '["/app/versatiles"]'

    # `versatiles` must resolve by name for images that override the entrypoint
    # (e.g. a Cloud Run wrapper). scratch has no shell, so it is exempt.
    assert_binary_resolves "$NAME:debian" versatiles /app/versatiles
    assert_binary_resolves "$NAME:alpine" versatiles /app/versatiles

    test_image "$NAME:debian"
    test_shutdown_time "$NAME:debian" 1000 serve chioggia.versatiles

    test_image "$NAME:alpine"
    test_shutdown_time "$NAME:alpine" 1000 serve chioggia.versatiles

    test_image "$NAME:scratch"

    print_test_summary
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    # The `latest-*` tags are deprecated aliases kept only so old pulls do not
    # silently serve a stale image; see issue #47. Prefer alpine/debian/scratch.
    build_push_image versatiles-debian "$NAME" "debian,$VER-debian,latest-debian" "./versatiles/Dockerfile"
    build_push_image versatiles-alpine "$NAME" "alpine,$VER-alpine,latest,$VER,latest-alpine" "./versatiles/Dockerfile"
    build_push_image versatiles-scratch "$NAME" "scratch,$VER-scratch,latest-scratch" "./versatiles/Dockerfile"
    update_docker_description versatiles
fi
