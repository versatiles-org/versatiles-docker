#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(../scripts/fetch_release_tag.sh)

ARGS=$(../scripts/setup_buildx.sh "${1:-}")

NAME="versatiles/versatiles"

docker buildx build --target versatiles-debian \
    -t $NAME:debian \
    -t $NAME:$VER-debian \
    $ARGS .

docker buildx build --target versatiles-alpine \
    -t $NAME:alpine \
    -t $NAME:$VER-alpine \
    -t $NAME:latest \
    -t $NAME:$VER \
    $ARGS .

docker buildx build --target versatiles-scratch \
    -t $NAME:scratch \
    -t $NAME:$VER-scratch \
    $ARGS .

../scripts/update_docker_description.sh versatiles
