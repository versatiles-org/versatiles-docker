#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
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
    
    output=$(docker run --rm "versatiles-tippecanoe:latest" -v 2>&1 || true)
    if [[ "$output" != "tippecanoe v$VER_TC" ]]; then
        printf "❌ Unexpected output:\n%s\n" "$output" >&2
        exit 1
    fi
    output=$(docker run --rm --entrypoint "versatiles" "versatiles-tippecanoe:latest" -V 2>&1 | head -n 1 || true)
    if [[ "$output" != "versatiles ${VER_VT:1}" ]]; then
        echo "❌ Version mismatch: expected 'versatiles ${VER_VT:1}', got '$output'" >&2
        exit 1
    fi
    
    echo "✅ Image tested successfully."
fi

###############################################################################
# 3. Multi‑arch push (only if requested)
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing multi-arch image …"
    build_push_image versatiles-tippecanoe "$NAME" "latest,$VER_TC" "./versatiles-tippecanoe/Dockerfile"
    update_docker_description versatiles-tippecanoe
fi
