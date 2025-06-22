#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(../scripts/fetch_release_tag.sh "felt/tippecanoe")
ARGS=$(../scripts/setup_buildx.sh "$@")

docker buildx build \
    -t "versatiles/versatiles-tippecanoe:latest" \
    -t "versatiles/versatiles-tippecanoe:$VER" \
    --args TIPPECANOE_VERSION=$VER \
    $ARGS \
    .

if [[ " $* " == *" --push "* ]]; then
    ../scripts/update_docker_description.sh versatiles-tippecanoe
fi
