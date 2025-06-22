#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(./fetch_release_tag.sh "felt/tippecanoe")

ARGS=$(./setup_buildx.sh "${1:-}")

docker buildx build \
    -t "versatiles/versatiles-tippecanoe:latest" \
    -t "versatiles/versatiles-tippecanoe:$VER" \
    --args TIPPECANOE_VERSION=$VER \
    $ARGS \
    .
