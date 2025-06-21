#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(./fetch_version.sh)

ARGS=$(./setup_buildx.sh "${1:-}")

ARGS+=" --file ../docker/basic.Dockerfile ../docker"
NAME="versatiles/versatiles"

docker buildx build --target versatiles-debian \
    -t $NAME:debian \
    -t $NAME:$VER-debian \
    $ARGS

docker buildx build --target versatiles-alpine \
    -t $NAME:alpine \
    -t $NAME:$VER-alpine \
    -t $NAME:latest \
    -t $NAME:$VER \
    $ARGS

docker buildx build --target versatiles-scratch \
    -t $NAME:scratch \
    -t $NAME:$VER-scratch \
    $ARGS
