#!/usr/bin/env bash
#
# build_all.sh — Build all VersaTiles Docker images
#
# USAGE
#   ./build_all.sh [OPTIONS]
#
# OPTIONS
#   --push            Build and push multi-arch images to Docker Hub
#   --test, --testing Run smoke tests on built images
#   -h, --help        Show help message
#
# DESCRIPTION
#   This script orchestrates the building of all VersaTiles Docker images
#   by calling each individual build script in sequence. All command-line
#   arguments are forwarded to each build script.
#
# EXAMPLES
#   ./build_all.sh                    # Build local images only
#   ./build_all.sh --test             # Build and test local images
#   ./build_all.sh --push             # Build and push multi-arch images
#   ./build_all.sh --test --push      # Build, test, and push images
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Run all build scripts with the provided arguments
./versatiles/build.sh "$@"
./versatiles-frontend/build.sh "$@"
./versatiles-nginx/build.sh "$@"
./versatiles-gdal/build.sh "$@"
./versatiles-tilemaker/build.sh "$@"
./versatiles-tippecanoe/build.sh "$@" 
