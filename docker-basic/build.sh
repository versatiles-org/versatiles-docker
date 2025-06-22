#!/usr/bin/env bash
set -euo pipefail

cd $(dirname $0)

source ../scripts/parse_arguments.sh "$@"
VER=$(../scripts/fetch_release_tag.sh)
ARGS=$(../scripts/setup_buildx.sh "$@")
NAME="versatiles/versatiles"

echo "👷 Building versatiles Docker images for version $VER"
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
        result=$(docker run --rm "$image" --version)
        if [ "$result" != "versatiles ${VER:1}" ]; then
            echo "❌  Version mismatch for $image: expected 'versatiles ${VER:1}', got '$result'" >&2
            exit 1
        fi
    }

    test_image "$NAME:debian"
    test_image "$NAME:alpine"
    test_image "$NAME:scratch"

    echo "✅  All images start successfully and report a version."
fi

if $needs_push; then
    ../scripts/update_docker_description.sh versatiles
fi
