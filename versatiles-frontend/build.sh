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
cd "$(dirname "$0")"

# ── Shared helpers ───────────────────────────────────────────────────────────
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
NAME="versatiles-frontend"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
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
        local first_line
        first_line=$(docker run --rm "$image" --help | head -n 1)
        if [[ "$first_line" != "Serve tiles via HTTP" ]]; then
            echo "❌ Expected 'Serve tiles via HTTP', got '$first_line'" >&2
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

    update_docker_description versatiles-frontend
fi
