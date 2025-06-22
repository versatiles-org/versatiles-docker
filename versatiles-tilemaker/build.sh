#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

# Load shared helpers
source ../scripts/utils.sh
# Parse CLI flags → sets needs_push / needs_testing
parse_arguments "$@"

VER=$(fetch_release_tag "systemed/tilemaker")
ARGS=$(setup_buildx "$@")

echo "👷 Building versatiles-tilemaker Docker images for version $VER"
docker buildx build \
    -t "versatiles/versatiles-tilemaker:latest" \
    -t "versatiles/versatiles-tilemaker:$VER" \
    $ARGS \
    .

if $needs_testing; then
    echo "🧪 Running test"

    result=$(docker run --rm "versatiles/versatiles-tilemaker" || true)

    if [ "$result" != $'Arguments required: <pbf-url> <name> [bbox]\n       bbox default: -180,-86,180,86' ]; then
        echo ">$result<"
        printf "❌ Result mismatch for versatiles/versatiles-tilemaker, got '%q'\n" "$result" >&2
        exit 1
    fi

    echo "✅ Images started successfully."
fi

if $needs_push; then
    update_docker_description versatiles-tilemaker
fi
