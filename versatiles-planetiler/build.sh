#!/usr/bin/env bash
# Build script for the "versatiles-planetiler" image.
#
# Flow
# ────
#  1. Build a host-architecture image (`--load`) so we can smoke-test it locally
#     unless the user asked for `--push` *without* tests.
#  2. Optionally run a quick container-starts smoke-test (`--testing` flag).
#  3. Optionally build & push the real multi-arch image (`--push` flag).
#
# Flags are parsed by utils.sh → parse_arguments.
#
# Versioning: neither the Planetiler fork (versatiles-org/planetiler) nor the
# Shortbread profile it consumes as a submodule
# (versatiles-org/planetiler-shortbread) publishes a GitHub release tag yet, so
# images are tagged with the build date. Revisit once either repo tags releases.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(date +%Y-%m-%d)
# NB: VER above is a build date; the bundled versatiles binary has its own version.
VER_VT=$(fetch_release_tag)
# The fork has no releases, so the image is built from the commit main points
# at now. As a build argument it keys the layer cache, so the fork is built
# again exactly when main moves, and never served from an older build (#64).
# The Shortbread profile comes with it, at the commit its submodule names.
PLANETILER_COMMIT=$(git ls-remote https://github.com/versatiles-org/planetiler.git refs/heads/main | cut -f1)
if [[ ! "$PLANETILER_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "❌ Can't find the commit of versatiles-org/planetiler main: '$PLANETILER_COMMIT'" >&2
    exit 1
fi
BUILD_ARGS="--build-arg VERSATILES_VERSION=$VER_VT --build-arg PLANETILER_COMMIT=$PLANETILER_COMMIT"
NAME="versatiles-planetiler"

echo "👷 Building $NAME Docker images for version $VER, planetiler ${PLANETILER_COMMIT:0:12}"

###############################################################################
# 1. Host-arch build & load (needed for local tests)
###############################################################################
if ! $needs_push || $needs_testing; then
    echo "👷 Building image"
    build_load_image versatiles-planetiler "$NAME" "latest" "./versatiles-planetiler/Dockerfile"
fi

###############################################################################
# 2. Optional smoke-tests
###############################################################################
if $needs_testing; then
    echo "🧪 Running smoke-test …"

    # Contract (see issue #47). Both `tini` and `generate_tiles` are resolved by
    # name, so this entrypoint depends entirely on PATH.
    echo "  🧪 Contract: $NAME:latest"
    assert_image_config "$NAME:latest" '["tini","-g","--","generate_tiles"]' "/app"
    assert_binary_resolves "$NAME:latest" generate_tiles /usr/local/bin/generate_tiles
    assert_binary_resolves "$NAME:latest" versatiles /usr/local/bin/versatiles

    # The image names the commit of the fork it was built from (#64).
    label=$(docker inspect --format '{{ index .Config.Labels "org.versatiles.planetiler.revision" }}' "$NAME:latest")
    assert_eq "$NAME: planetiler commit label" "$label" "$PLANETILER_COMMIT"

    # With no arguments and no TTY the container must print a usage hint and exit 1.
    output=$(docker run --rm "$NAME:latest" 2>&1 || true)
    assert_contains "$NAME: usage hint" "$output" "No configuration provided"

    print_test_summary
fi

###############################################################################
# 3. Multi-arch push (only if requested)
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing multi-arch image …"
    build_push_image versatiles-planetiler "$NAME" "latest,$VER" "./versatiles-planetiler/Dockerfile"
    update_docker_description versatiles-planetiler
fi
