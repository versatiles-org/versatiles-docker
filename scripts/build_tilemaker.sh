#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

VER=$(./fetch_version.sh)

ARGS=$(./setup_buildx.sh "${1:-}")

NAME="versatiles/versatiles-tilemaker"

docker buildx build --target versatiles-tilemaker \
    -t $NAME:latest \
    -t $NAME:$VER \
    --file ../docker/tilemaker.Dockerfile \
    ../docker
