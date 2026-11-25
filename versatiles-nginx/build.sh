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
    # Frontend updates (#62), with fetch_frontend.sh on its own. Each case has
    # its own folder in DATA_DIR as /data, and keeps the script's log there.
    echo "  🧪 Frontend updates: $NAME:latest"
    DATA_DIR=$(mktemp -d)
    fetch_frontend() { # fetch_frontend <dir> [docker run options…]
        local dir="$1"
        shift
        docker run --rm "$@" -v "$dir:/data" -e FRONTEND=tiny \
            --entrypoint /scripts/fetch_frontend.sh "$NAME:latest" 2>"$dir/log"
    }
    bundle=frontend/frontend-tiny.br.tar
    latest=$(curl -sfI -o /dev/null -w '%{redirect_url}' https://github.com/versatiles-org/versatiles-frontend/releases/latest)
    latest=${latest##*/}

    dir="$DATA_DIR/offline"
    mkdir -p "$dir/frontend"
    echo "fake" >"$dir/$bundle"
    echo "v0.0.0-old" >"$dir/$bundle.version"
    output=$(fetch_frontend "$dir" --network none) || output="failed"
    assert_eq "$NAME: offline, outdated frontend served" "$output" "--static /data/$bundle"
    assert_eq "$NAME: offline, outdated frontend kept" "$(cat "$dir/$bundle")" "fake"
    assert_contains "$NAME: offline, warning" "$(cat "$dir/log")" "Keeping the frontend from v0.0.0-old."

    dir="$DATA_DIR/offline-empty"
    mkdir -p "$dir"
    output=$(fetch_frontend "$dir" --network none) || output="failed"
    assert_eq "$NAME: offline, no frontend fails" "$output" "failed"
    assert_contains "$NAME: offline, no frontend error" "$(cat "$dir/log")" "No frontend to fall back to."

    # A frontend without a tag file, as downloaded before #62, counts as outdated.
    dir="$DATA_DIR/update"
    mkdir -p "$dir/frontend"
    echo "fake" >"$dir/$bundle"
    fetch_frontend "$dir" >/dev/null
    assert_eq "$NAME: outdated frontend, tag of latest stored" "$(cat "$dir/$bundle.version")" "$latest"
    assert_min_size "$NAME: outdated frontend replaced" "$dir/$bundle" 1000000
    fetch_frontend "$dir" >/dev/null
    if [[ "$(cat "$dir/log")" == *Downloading* ]]; then
        _fail "$NAME: current frontend not downloaded again" "$(cat "$dir/log")"
    fi
    _pass "$NAME: current frontend not downloaded again"

    echo "  🧪 Tile names: $NAME:latest"
    mkdir -p "$DATA_DIR/tiles"
    cp ./testdata/chioggia.versatiles "$DATA_DIR/tiles/chioggia.20261123.versatiles"
    cp ./testdata/chioggia.versatiles "$DATA_DIR/tiles/osm.versatiles"
    mkdir -p "$DATA_DIR/static"
    echo "hello" >"$DATA_DIR/static/hello.txt"
    # A stand-in for the tiny frontend, with a library in a versioned folder
    # and the same one unversioned. Its tag file names the pinned
    # FRONTEND_VERSION, so it is served instead of being downloaded. A plain
    # tar works under the .br.tar name, as each entry's compression is read
    # from its own extension.
    mkdir -p "$DATA_DIR/fake/assets/lib/lib@1.0.0" "$DATA_DIR/fake/assets/lib/lib" "$DATA_DIR/frontend"
    echo "versioned" >"$DATA_DIR/fake/assets/lib/lib@1.0.0/lib.js"
    echo "unversioned" >"$DATA_DIR/fake/assets/lib/lib/lib.js"
    COPYFILE_DISABLE=1 tar -cf "$DATA_DIR/fake.tar" -C "$DATA_DIR/fake" assets
    cp "$DATA_DIR/fake.tar" "$DATA_DIR/frontend/frontend-tiny.br.tar"
    echo "v0.0.0-test" >"$DATA_DIR/frontend/frontend-tiny.br.tar.version"
    start_http_container "$NAME:latest" -v "$DATA_DIR:/data" -p 127.0.0.1:0:80 \
        -e DOMAIN=localhost -e HTTP_ONLY=1 -e FRONTEND=tiny -e FRONTEND_VERSION=v0.0.0-test \
        -e TILE_SOURCES=chioggia.20261123.versatiles,osm.versatiles
    wait_for_http "http://127.0.0.1:${HOST_PORT}/tiles/index.json" 60
    index=$(curl -sf "http://127.0.0.1:${HOST_PORT}/tiles/index.json" || true)
    assert_eq "$NAME: tile names" "$index" '["chioggia","osm-vector"]'
    for id in chioggia chioggia.20261123 osm-vector osm; do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOST_PORT}/tiles/$id/14/8750/5880" || true)
        assert_eq "$NAME: tile at /tiles/$id/" "$code" "200"
    done

    # Caching through nginx (port 80): nginx keeps tiles as long as versatiles
    # allows, never static files, and only a 404 among the errors. Browsers get
    # the header of versatiles, and one for errors.
    echo "  🧪 Caching through nginx: $NAME:latest"
    NGINX_PORT=$(docker port "$CONTAINER_ID" 80 | head -n1 | sed 's/.*://')
    wait_for_http "http://127.0.0.1:${NGINX_PORT}/tiles/index.json" 60
    header() { # header <name> <path>: the value of a response header, via nginx
        curl -s -o /dev/null -D - "http://127.0.0.1:${NGINX_PORT}$2" |
            tr -d '\r' | awk -v name="$1" 'tolower($0) ~ "^" tolower(name) ": " { sub(/^[^:]*: /, ""); print }'
    }
    tile=/tiles/osm-vector/14/8750/5880
    assert_eq "$NAME: tile Cache-Control" "$(header Cache-Control $tile)" "public, max-age=2419200, no-transform"
    assert_eq "$NAME: tile cached in nginx" "$(header X-Cache $tile)" "HIT"
    assert_eq "$NAME: tile Cache-Control on a cache hit" "$(header Cache-Control $tile)" "public, max-age=2419200, no-transform"
    assert_eq "$NAME: static Cache-Control" "$(header Cache-Control /hello.txt)" "no-cache"
    header X-Cache /hello.txt >/dev/null
    assert_eq "$NAME: static not cached in nginx" "$(header X-Cache /hello.txt)" "MISS"
    assert_eq "$NAME: 404 Cache-Control" "$(header Cache-Control /missing.txt)" "public, max-age=300"
    assert_eq "$NAME: 404 cached in nginx" "$(header X-Cache /missing.txt)" "HIT"

    # Versioned libraries get a year once the image's versatiles has
    # --immutable, and "no-cache" before; unversioned ones always "no-cache".
    serve_help=$(docker run --rm --entrypoint versatiles "$NAME:latest" serve --help 2>&1 || true)
    if [[ "$serve_help" == *"--immutable"* ]]; then
        versioned="public, max-age=31536000, immutable"
    else
        versioned="no-cache"
    fi
    assert_eq "$NAME: versioned library Cache-Control" "$(header Cache-Control /assets/lib/lib@1.0.0/lib.js)" "$versioned"
    assert_eq "$NAME: unversioned library Cache-Control" "$(header Cache-Control /assets/lib/lib/lib.js)" "no-cache"
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
