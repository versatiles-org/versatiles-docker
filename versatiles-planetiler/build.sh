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
# Versioning: the Planetiler fork branch (feature/shortbread-java-profile) has
# no GitHub release tag, so images are tagged with the build date.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
parse_arguments "$@"
# Variables from utils.sh: needs_push, needs_testing
VER=$(date +%Y-%m-%d)
NAME="versatiles-planetiler"

echo "👷 Building $NAME Docker images for version $VER"

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

    # With no arguments and no TTY the container must print a usage hint and exit 1.
    output=$(docker run --rm "${NAME}:latest" 2>&1 || true)

    if [[ "$output" != *"No configuration provided"* ]]; then
        printf "❌  Unexpected output:\n%s\n" "$output" >&2
        exit 1
    fi

    echo "✅ Images tested successfully."
fi

###############################################################################
# 3. Multi-arch push (only if requested)
###############################################################################
if $needs_push; then
    echo "🚀 Building and pushing multi-arch image …"
    build_push_image versatiles-planetiler "$NAME" "latest,$VER" "./versatiles-planetiler/Dockerfile"
    update_docker_description versatiles-planetiler
fi
