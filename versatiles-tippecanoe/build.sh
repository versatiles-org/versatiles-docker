#!/usr/bin/env bash
set -euo pipefail

cd $(dirname "$0")

# Load shared helpers
source ../scripts/utils.sh
# Parse CLI flags → sets needs_push / needs_testing
parse_arguments "$@"

VER_VT=$(fetch_release_tag)
VER_TC=$(fetch_release_tag "felt/tippecanoe")
ARGS=$(setup_buildx "$@")

echo "👷 Building versatiles-tippecanoe Docker images for version $VER_TC"
docker buildx build --quiet \
    --tag "versatiles/versatiles-tippecanoe:latest" \
    --tag "versatiles/versatiles-tippecanoe:$VER_TC" \
    --build-arg TIPPECANOE_VERSION="$VER_TC" \
    $ARGS \
    .

if $needs_testing; then
    echo "🧪 Running tests"

    result=$(docker run --rm "versatiles/versatiles-tippecanoe" -v 2>&1 || true)
    if [ "$result" != "tippecanoe v$VER_TC" ]; then
        echo "❌ Version mismatch: expected 'tippecanoe v${VER_VT:1}', got '$result'" >&2
        exit 1
    fi

    result=$(docker run --rm --entrypoint "versatiles" "versatiles/versatiles-tippecanoe" -V 2>&1 | head -n 1 || true)
    if [ "$result" != "versatiles ${VER_VT:1}" ]; then
        echo "❌ Version mismatch: expected 'versatiles ${VER_VT:1}', got '$result'" >&2
        exit 1
    fi

    echo "✅ Images started successfully."
fi

if $needs_push; then
    update_docker_description versatiles-tippecanoe
fi
