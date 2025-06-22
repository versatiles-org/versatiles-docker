#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)/..

./docker-basic/build.sh "$@"
./docker-frontend/build.sh "$@"
./docker-tilemaker/build.sh "$@" 
./docker-tippecanoe/build.sh "$@" 
