#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER_VT=$(fetch_release_tag)
VER_TC=$(fetch_release_tag "felt/tippecanoe")
NAME="versatiles-tippecanoe"
BUILD_ARGS="--build-arg TIPPECANOE_VERSION=$VER_TC"


echo "👷 Building $NAME Docker images for version $VER_TC"

###############################################################################
# 1. Host‑arch build & load (needed for local tests)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building image"
    build_load_image versatiles-tippecanoe "$NAME" "latest" "./versatiles-tippecanoe/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-test …"

    # Contract (see issue #47). This image resolves its entrypoint by NAME, so a
    # PATH change can break it without touching the ENTRYPOINT line.
    echo "  🧪 Contract: $NAME:latest"
    assert_image_config "$NAME:latest" '["/sbin/tini","--","tippecanoe"]' "/data"
    assert_path_appends_app "$NAME:latest"
    assert_binary_resolves "$NAME:latest" tippecanoe /usr/local/bin/tippecanoe
    assert_binary_resolves "$NAME:latest" versatiles /app/versatiles

    output=$(docker run --rm "$NAME:latest" -v 2>&1 || true)
    assert_eq "$NAME: tippecanoe -v" "$output" "tippecanoe v$VER_TC"

    output=$(docker run --rm --entrypoint versatiles "$NAME:latest" -V 2>&1 | head -n 1 || true)
    assert_eq "$NAME: versatiles -V" "$output" "versatiles ${VER_VT:1}"

    print_test_summary
fi

###############################################################################
# 3. Multi‑arch push (only if requested)
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing multi-arch image …"
    build_push_image versatiles-tippecanoe "$NAME" "latest,$VER_TC" "./versatiles-tippecanoe/Dockerfile"
    update_docker_description versatiles-tippecanoe
fi
