#!/usr/bin/env bash
###############################################################################
# utils.sh — shared Bash helpers for the VersaTiles Docker build system
#
# This file is sourced by every `build.sh` script in the repository.
#
# Dependencies:
#   • bash 4+
#   • curl
#   • jq          — JSON parsing (GitHub API + Docker Hub API payloads)
#   • docker + buildx + qemu (for multi‑arch builds)
#
# Conventions:
#   • All public helpers echo a *string* that the caller can embed
#     into its own commands (no global side‑effects unless stated).
#   • Functions exit non‑zero on error so the parent script can `set -e`.
#
# Public API overview
#   fetch_release_tag <owner/repo>?
#   parse_arguments   "$@"
#   build_load_image  <target> <name> <tag…>
#   build_push_image  <target> <name> <tag…>
#   update_docker_description <repo>
#
# Maintainer tips:
#   • Keep helper functions POSIX‑portable except where Bash arrays
#     genuinely simplify tag handling.
#   • Avoid echoing unescaped user input — everything is quoted below.
###############################################################################
# Consolidated helper library for build scripts.
# Source it from another script via:
#
#     source "./utils.sh"
#
# It exposes four functions:
#
#   fetch_release_tag [owner/repo]
#   parse_arguments   "$@"
#   setup_buildx      [--push]
#   update_docker_description <repository>
#
# ---------------------------------------------------------------------------
set -euo pipefail
shopt -s extglob

#############################################################################
# 📦  GitHub releases
#############################################################################
# --------------------------------------------------------------------------- #
#  fetch_release_tag
# --------------------------------------------------------------------------- #
# Arguments:
#   $1 (optional) — GitHub repository in "owner/name" form. Defaults to the
#                   VersaTiles CLI repo.
#
# Output:
#   Prints the latest *GitHub release tag* (not prerelease) on stdout.
#
# Example:
#   TAG=$(fetch_release_tag "felt/tippecanoe")   # → "v2.34.0"
#
# Notes:
#   • Uses the GitHub REST API unauthenticated (60 req/hr IP‑limit).
#     If you hit rate‑limits, export GITHUB_TOKEN and add an
#     "Authorization" header here.
# --------------------------------------------------------------------------- #
# fetch_release_tag [owner/repo]
# Prints the latest Git tag of a GitHub project (defaults to versatiles‑rs).
fetch_release_tag() {
    local repo=${1:-"versatiles-org/versatiles-rs"}
    local tag
    tag=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name')

    if [[ "$tag" == "null" || -z "$tag" ]]; then
        echo "❌ Failed to fetch release tag for repository: $repo" >&2
        return 1
    fi

    echo "$tag"
}

#############################################################################
# 🏷️  CLI flag parsing
#############################################################################
# --------------------------------------------------------------------------- #
#  parse_arguments
# --------------------------------------------------------------------------- #
# Parses common CLI flags used by build scripts and sets two global booleans:
#   needs_push    — true when `--push` is present
#   needs_testing — true when `--test` or `--testing` is present
#
# Call with:
#   parse_arguments "$@"
#
# Safe to call multiple times: the last invocation wins.
# --------------------------------------------------------------------------- #
# parse_arguments "$@"
# Sets two globals the caller can inspect:
#   needs_push    – true/false
#   needs_testing – true/false
#
# It understands:
#   --push
#   --test | --testing
#   -h | --help
#
parse_arguments() {
    # Defaults (exported for caller convenience)
    needs_push=false
    needs_testing=false

    while (("$#")); do
        case "$1" in
        --push) needs_push=true ;;
        --test | --testing) needs_testing=true ;;
        -h | --help)
            cat <<EOF
Available options:
  --push            Enable image push
  --test, --testing Enable smoke tests
  -h, --help        Show this help
EOF
            return 0
            ;;
        *)
            echo "❌ Unknown option: $1" >&2
            return 1
            ;;
        esac
        shift
    done
}

#############################################################################
# 🐳 Buildx helpers
#############################################################################

# --------------------------------------------------------------------------- #
#  _ensure_builder (internal)
# --------------------------------------------------------------------------- #
# Idempotently creates and selects the Buildx builder named "multiarch".
# Required once per CI job before any `docker buildx build` invocation.
# --------------------------------------------------------------------------- #
# Idempotent helper — creates the builder once
_ensure_builder() {
    if ! docker buildx inspect multiarch >/dev/null 2>&1; then
        docker buildx create --name multiarch --driver docker-container --use 1>&2
    else
        docker buildx use multiarch 1>&2
    fi
}

# --------------------------------------------------------------------------- #
#  build_image_args (internal)
# --------------------------------------------------------------------------- #
# Helper that constructs the common `docker buildx` argument list for tags.
#
# Arguments:
#   $1 = Dockerfile target stage
#   $2 = base image name  (e.g. "versatiles/versatiles")
#   $3..$n = tag suffixes (e.g. "latest" "alpine" "v1.2.3-alpine")
#
# Prints the argument string on stdout so callers can embed it.
# --------------------------------------------------------------------------- #
# Build a single image variant.
#   $1 = target stage in the Dockerfile
#   $2 = base image name (e.g. "$NAME")
#   $3..$n = tag suffixes (e.g. "latest" "debian" "$VER-debian")
build_image_args() {
    local target="$1"
    shift
    local imgname="$1"
    shift
    local tags=("$@") # remaining args = tag list

    # Construct repeated --tag arguments
    local tag_args=()
    for tag in "${tags[@]}"; do
        tag_args+=(--tag "${imgname}:${tag}")
    done

    echo "--target $target ${tag_args[@]}"
}

# --------------------------------------------------------------------------- #
#  build_load_image
# --------------------------------------------------------------------------- #
# Builds a *single‑architecture* image (matching the host) and loads it into
# the local Docker Engine, enabling smoke‑tests.
#
# Example:
#   build_load_image versatiles-alpine "$NAME" latest "$VER" alpine
# --------------------------------------------------------------------------- #
build_load_image() {
    echo "  - build, load: $1"
    _ensure_builder

    local host_arch
    host_arch=$(uname -m)
    case "$host_arch" in
    x86_64) host_arch="amd64" ;;
    aarch64 | arm64) host_arch="arm64" ;;
    *)
        echo "Unsupported host arch: $host_arch" >&2
        return 1
        ;;
    esac

    docker buildx build $(build_image_args "$@") --platform "linux/${host_arch}" ${BUILD_ARGS:-} --load . >/dev/null
}

# --------------------------------------------------------------------------- #
#  build_push_image
# --------------------------------------------------------------------------- #
# Builds a *multi‑architecture* image (amd64 + arm64) and pushes it directly
# to the Docker registry in one step.
#
# Example:
#   build_push_image versatiles-alpine "$NAME" latest "$VER" alpine
# --------------------------------------------------------------------------- #
build_push_image() {
    echo "  - build, push: $1"
    _ensure_builder

    docker buildx build $(build_image_args "$@") --platform linux/amd64,linux/arm64 ${BUILD_ARGS:-} --push . >/dev/null
}

#############################################################################
# 📄  Docker Hub description updater
#############################################################################
# --------------------------------------------------------------------------- #
#  update_docker_description
# --------------------------------------------------------------------------- #
# Pushes README updates to Docker Hub (short + full description).
#
# Preconditions:
#   • $DOCKERHUB_TOKEN  — JWT with write access to the repo.
#   • short.md / full.md exist in $PWD.
#
# Arguments:
#   $1 — Repository slug *without* namespace, e.g. "versatiles-tippecanoe".
#
# Returns:
#   0 on success, non‑zero on HTTP failure or validation error.
# --------------------------------------------------------------------------- #
# update_docker_description <repository>
# Reads short.md & full.md from the current directory and updates the Docker
# Hub description of the given repository (under n/s "versatiles/").
#
update_docker_description() {
    local repository=${1:-}
    [[ -n "$repository" ]] || {
        echo "❌ Repository name required"
        return 1
    }
    [[ -n "${DOCKERHUB_TOKEN:-}" ]] || {
        echo "❌ DOCKERHUB_TOKEN not set."
        return 1
    }

    local short_desc full_desc status data
    short_desc=$(<"short.md")
    ((${#short_desc} <= 100)) || {
        echo "❌ Short description > 100 chars"
        return 1
    }

    full_desc=$(<"full.md")
    ((${#full_desc} <= 25000)) || {
        echo "❌ Full description > 25 000 chars"
        return 1
    }

    data=$(jq -n --arg short "$short_desc" --arg full "$full_desc" \
        '{description: $short, full_description: $full}')

    status=$(curl --silent --show-error --fail --output /dev/null \
        --retry 3 --retry-delay 2 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -H "Authorization: JWT ${DOCKERHUB_TOKEN}" \
        -H "Accept: application/json" \
        -d "$data" \
        -w "%{http_code}" \
        "https://hub.docker.com/v2/namespaces/versatiles/repositories/${repository}")

    if [[ "$status" == "200" ]]; then
        echo "✅ Description updated."
    else
        echo "❌ Failed (HTTP $status)."
        return 1
    fi
}

#############################################################################
# ℹ️  Guard against accidental execution
#############################################################################
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cat <<EOF
utils.sh is intended to be *sourced*, not executed.

Example:
    source "\${0%/*}/utils.sh"
    parse_arguments "\$@"
    EXTRA_ARGS=\$(setup_buildx "\$@")
    TAG=\$(fetch_release_tag versatiles-org/versatiles-rs)
    update_docker_description my-repo-name

EOF
    exit 0
fi
