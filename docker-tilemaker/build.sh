#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(../scripts/fetch_release_tag.sh "systemed/tilemaker")

ARGS=$(../scripts/setup_buildx.sh "${1:-}")

docker buildx build \
    -t "versatiles/versatiles-tilemaker:latest" \
    -t "versatiles/versatiles-tilemaker:$VER" \
    $ARGS \
    .
