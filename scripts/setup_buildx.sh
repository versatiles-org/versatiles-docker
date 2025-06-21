#!/usr/bin/env bash
# scripts/buildx_setup.sh
# Usage: buildx_setup.sh [--push]
set -euo pipefail

# ── 1. Make sure we have a multi-arch builder ────────────────────────────────
if ! docker buildx inspect multiarch >/dev/null 2>&1; then
    docker buildx create --name multiarch --driver docker-container --use
else
    docker buildx use multiarch
fi

# ── 2. Decide which buildx flags we need ─────────────────────────────────────
if [[ "${1:-}" == "--push" ]]; then
    # Push a real multi-arch image to the registry
    echo "--platform linux/amd64,linux/arm64 --push"
else
    # Only build & load the host’s architecture locally
    HOST_ARCH=$(uname -m)
    case "$HOST_ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported host arch: $HOST_ARCH" >&2
        exit 1
        ;;
    esac
    echo "--platform linux/${ARCH} --load"
fi
