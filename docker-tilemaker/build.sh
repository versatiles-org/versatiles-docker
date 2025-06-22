#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

# Load shared helpers
source ../scripts/utils.sh
# Parse CLI flags → sets needs_push / needs_testing
parse_arguments "$@"

VER=$(fetch_release_tag "systemed/tilemaker")
ARGS=$(setup_buildx "$@")

docker buildx build \
    -t "versatiles/versatiles-tilemaker:latest" \
    -t "versatiles/versatiles-tilemaker:$VER" \
    $ARGS \
    .

if $needs_push; then
    update_docker_description versatiles-tilemaker
fi
