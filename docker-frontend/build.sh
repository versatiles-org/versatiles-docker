#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

# Load shared helpers
source ../scripts/utils.sh
parse_arguments "$@"
VER=$(fetch_release_tag)
ARGS=$(setup_buildx "$@")
NAME="versatiles/versatiles-frontend"

echo "👷 Building versatiles-frontend Docker images for version $VER"
docker buildx build --quiet \
    --target versatiles-debian \
    --tag $NAME:debian \
    --tag $NAME:$VER-debian \
    $ARGS .

docker buildx build --quiet \
    --target versatiles-alpine \
    --tag $NAME:alpine \
    --tag $NAME:$VER-alpine \
    --tag $NAME:latest \
    --tag $NAME:$VER \
    $ARGS .

docker buildx build --quiet \
    --target versatiles-scratch \
    --tag $NAME:scratch \
    --tag $NAME:$VER-scratch \
    $ARGS .

if $needs_testing; then
    echo "🧪 Running tests"

    test_image() {
        local image="$1"
        echo "  - $image"
        result=$(docker run --rm "$image" --help | head -n 1)
        if [ "$result" != "Serve tiles via HTTP" ]; then
            echo "❌ Result mismatch for $image: expected 'Serve tiles via HTTP', got '$result'" >&2
            exit 1
        fi
    }

    test_image "$NAME:debian"
    test_image "$NAME:alpine"
    test_image "$NAME:scratch"

    echo "✅ All images start successfully and report a version."
fi

if $needs_push; then
    update_docker_description versatiles-frontend
fi
