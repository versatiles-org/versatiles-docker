#!/usr/bin/env bash
set -euo pipefail

cd $(dirname "$0")/..

./versatiles/build.sh "$@"
./versatiles-frontend/build.sh "$@"
./versatiles-nginx/build.sh "$@"
./versatiles-tilemaker/build.sh "$@" 
./versatiles-tippecanoe/build.sh "$@" 
