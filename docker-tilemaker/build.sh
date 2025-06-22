#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(../scripts/fetch_release_tag.sh "systemed/tilemaker")
ARGS=$(../scripts/setup_buildx.sh "$@")

docker buildx build \
    -t "versatiles/versatiles-tilemaker:latest" \
    -t "versatiles/versatiles-tilemaker:$VER" \
    $ARGS \
    .

if [[ " $* " == *" --push "* ]]; then
    ../scripts/update_docker_description.sh versatiles-tilemaker
fi
