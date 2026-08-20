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
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
NAME="versatiles-frontend"

echo "👷 Building $NAME Docker images for version $VER"

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

    # scratch has no shell, so skip the shell-dependent checks there.
    assert_file_in_image_if_shell() {
        case "$1" in
        *:scratch) return 0 ;;
        esac
        assert_file_in_image "$1" /app/frontend-dev.br.tar -f
        assert_binary_resolves "$1" versatiles /app/versatiles
    }

    # Contract checks (see issue #47). The frontend entrypoint bakes in
    # `serve --static`, so everything after the image name is a tile source —
    # that is exactly what broke the documented quick-start command.
    test_contract() {
        local image="$1" entrypoint="$2"
        echo "  🧪 Contract: $image"
        assert_image_config "$image" "$entrypoint" "/data"
        assert_path_appends_app "$image"
        assert_file_in_image_if_shell "$image"
    }

    test_image() {
        local image="$1" tile_path tile_size
        echo "  🧪 Testing: $image"

        start_http_container "$image" -v "$TEST_DIR":/data:ro -- chioggia.versatiles
        wait_for_http "http://127.0.0.1:${HOST_PORT}/" 90

        tile_path="$(mktemp -d)/tile.pbf"
        curl -sf "http://127.0.0.1:${HOST_PORT}/tiles/chioggia/14/8750/5880" -o "$tile_path" || {
            docker logs "$CONTAINER_ID" >&2 || true
            stop_container
            echo "    ❌ $image: failed to download tile" >&2
            exit 1
        }
        stop_container

        tile_size=$(wc -c <"$tile_path" | tr -d ' ')
        assert_eq "$image: tile size" "$tile_size" "48679"
    }

    test_contract "$NAME:debian"  '["/usr/bin/tini","--","/app/versatiles","serve","--static","/app/frontend-dev.br.tar"]'
    test_contract "$NAME:alpine"  '["/sbin/tini","--","/app/versatiles","serve","--static","/app/frontend-dev.br.tar"]'
    test_contract "$NAME:scratch" '["/app/versatiles","serve","--static","/app/frontend-dev.br.tar"]'

    test_image "$NAME:debian"
    # NB: no `serve` argument — the entrypoint already supplies it. Passing one
    # made the container exit instantly, so this test used to pass vacuously.
    test_shutdown_time "$NAME:debian" 1000 chioggia.versatiles

    test_image "$NAME:alpine"
    test_shutdown_time "$NAME:alpine" 1000 chioggia.versatiles

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
    build_push_image versatiles-debian "$NAME" "debian,$VER-debian,latest-debian" "./versatiles-frontend/Dockerfile"
    build_push_image versatiles-alpine "$NAME" "alpine,$VER-alpine,latest,$VER,latest-alpine" "./versatiles-frontend/Dockerfile"
    build_push_image versatiles-scratch "$NAME" "scratch,$VER-scratch,latest-scratch" "./versatiles-frontend/Dockerfile"

    update_docker_description versatiles-frontend
fi
