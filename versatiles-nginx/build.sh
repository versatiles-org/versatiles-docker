#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Load shared helpers
# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(fetch_release_tag)
# Pin the downloaded binary to the tag we publish under, so the layer cache
# cannot serve a stale build and a mid-build release cannot swap it.
BUILD_ARGS="--build-arg VERSATILES_VERSION=$VER"
NAME="versatiles-nginx"

echo "👷 Building $NAME Docker images for version $VER"

###############################################################################
# 1. Host‑arch build (loaded into local Docker for testing)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building images"
    # Resolve build arguments for local / push modes later
    build_load_image versatiles-nginx "$NAME" latest "./versatiles-nginx/Dockerfile"
fi

###############################################################################
# 2. Optional smoke‑tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-tests"

    # Contract (see issue #47). Both the entrypoint and the versatiles binary are
    # resolved by name here — entrypoint.sh from /scripts, versatiles from
    # /usr/local/bin — so PATH is load-bearing for this image.
    echo "  🧪 Contract: $NAME:latest"
    # NB: the runtime stage sets no WORKDIR (the /app one belongs to the
    # builder), so the working directory is the default "/".
    assert_image_config "$NAME:latest" '["/sbin/tini","--","entrypoint.sh"]' "/"
    assert_binary_resolves "$NAME:latest" entrypoint.sh /scripts/entrypoint.sh
    assert_binary_resolves "$NAME:latest" versatiles /usr/local/bin/versatiles

    result=$(docker run --rm "$NAME:latest" 2>&1 || true)
    assert_contains "$NAME: FRONTEND is required" "$result" \
        "'FRONTEND' is required (Allowed: standard|dev|min|tiny|blank|none)"

    result=$(docker run --rm -e "FRONTEND=min" "$NAME:latest" 2>&1 || true)
    assert_contains "$NAME: TILE_SOURCES is required" "$result" "'TILE_SOURCES' is required"

    # Tile names. The frontends load /tiles/osm-vector/, so a dated file and a
    # file under an old dataset name are served under the dataset's name, and
    # under the name derived from the file as before. Port 8080 is versatiles
    # itself, behind nginx.
    echo "  🧪 Tile names: $NAME:latest"
    DATA_DIR=$(mktemp -d)
    mkdir -p "$DATA_DIR/tiles"
    cp ./testdata/chioggia.versatiles "$DATA_DIR/tiles/chioggia.20261123.versatiles"
    cp ./testdata/chioggia.versatiles "$DATA_DIR/tiles/osm.versatiles"
    start_http_container "$NAME:latest" -v "$DATA_DIR:/data" \
        -e DOMAIN=localhost -e HTTP_ONLY=1 -e FRONTEND=none \
        -e TILE_SOURCES=chioggia.20261123.versatiles,osm.versatiles
    wait_for_http "http://127.0.0.1:${HOST_PORT}/tiles/index.json" 60
    index=$(curl -sf "http://127.0.0.1:${HOST_PORT}/tiles/index.json" || true)
    assert_eq "$NAME: tile names" "$index" '["chioggia","osm-vector"]'
    for id in chioggia chioggia.20261123 osm-vector osm; do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOST_PORT}/tiles/$id/14/8750/5880" || true)
        assert_eq "$NAME: tile at /tiles/$id/" "$code" "200"
    done
    stop_container
    # The container owns the files now; on Linux the runner may not delete them.
    rm -rf "$DATA_DIR" 2>/dev/null || true

    print_test_summary
fi

###############################################################################
# 3. Optional multi‑arch push
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing images to Docker Hub"
    build_push_image versatiles-nginx "$NAME" "latest,$VER" "./versatiles-nginx/Dockerfile"
    update_docker_description versatiles-nginx
fi
