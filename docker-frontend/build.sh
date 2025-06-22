#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

# Load shared helpers
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
ARGS=$(setup_buildx "$@")
NAME="versatiles/versatiles-frontend"

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

if $needs_push; then
    update_docker_description versatiles-frontend
fi
