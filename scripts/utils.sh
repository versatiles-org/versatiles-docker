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
    local response
    response=$(curl --retry 3 --silent --show-error --location --fail "https://api.github.com/repos/${repo}/releases/latest") || {
        echo "❌ curl failed while fetching release info for repository: $repo" >&2
        return 1
    }
    tag=$(echo "$response" | jq -r '.tag_name')

    if [[ "$tag" == "null" || -z "$tag" ]]; then
        echo "❌ Failed to fetch release tag for repository: $repo" >&2
        echo "Full API response was:" >&2
        echo "$response" >&2
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
    export needs_push=false
    export needs_testing=false

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
#  buildx_cache_args (internal)
# --------------------------------------------------------------------------- #
# Returns the two Buildx flags that hook the GitHub‑Actions cache backend
#     --cache-from type=gha
#     --cache-to   type=gha,mode=max
#
# It outputs nothing when:
#   • the script is not running inside GitHub Actions ($GITHUB_ACTIONS not set)
#
# Usage:
#   docker buildx build $(buildx_cache_args) …
#
# --------------------------------------------------------------------------- #
buildx_cache_args() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "Setting up Buildx cache for GitHub Actions…" 1>&2
        echo "--cache-from type=gha,scope=versatiles-docker --cache-to type=gha,scope=versatiles-docker,mode=max"
    fi
}

# --------------------------------------------------------------------------- #
#  build_image_args (internal)
# --------------------------------------------------------------------------- #
# Helper that constructs the common `docker buildx` argument list for tags.
#
# Arguments:
#   $1 = comma‑separated list of **image names** (e.g. "versatiles/versatiles-frontend,ghcr.io/versatiles-org/versatiles-frontend")
#   $2 = comma‑separated list of **tags** (e.g. "latest-alpine-v1.2.3-alpine")
build_image_args() {
    local img_csv="$1"
    local tag_csv="$2"

    # Split the two CSV arguments into arrays
    IFS=',' read -ra images <<<"$img_csv"
    IFS=',' read -ra tags <<<"$tag_csv"

    # Produce one  --tag  flag for every <image>:<tag> combination
    local tag_args=()
    for image in "${images[@]}"; do
        [[ -z "$image" ]] && continue
        for tag in "${tags[@]}"; do
            [[ -z "$tag" ]] && continue
            tag_args+=(--tag "${image}:${tag}")
        done
    done

    # Echo the argument string so the caller can embed it
    echo "${tag_args[*]}"
}

# --------------------------------------------------------------------------- #
#  build_load_image
# --------------------------------------------------------------------------- #
# Builds a *single‑architecture* image (matching the host) and loads it into
# the local Docker Engine, enabling smoke‑tests.
#
# Example:
#   build_load_image versatiles-alpine "$NAME" "latest,$VER,alpine"
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

    docker buildx build --target "$1" $(build_image_args "$2" "$3") --platform "linux/${host_arch}" $(buildx_cache_args) ${BUILD_ARGS:-} --load .
}

# --------------------------------------------------------------------------- #
#  build_push_image
# --------------------------------------------------------------------------- #
# Builds a *multi‑architecture* image (amd64 + arm64) and pushes it directly
# to the Docker registry in one step.
#
# Example:
#   build_push_image versatiles-alpine "$NAME" "latest,$VER,alpine"
# --------------------------------------------------------------------------- #
build_push_image() {
    echo "  - build, push: $1"
    _ensure_builder

    docker buildx build --target "$1" $(build_image_args "versatiles/$2,ghcr.io/versatiles-org/$2" "$3") --platform linux/amd64,linux/arm64 $(buildx_cache_args) ${BUILD_ARGS:-} --push . >/dev/null
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
    local DOCKERHUB_USERNAME="versatiles"

    local repository=${1:-}
    [[ -n "$repository" ]] || {
        echo "❌ Repository name required"
        return 1
    }
    [[ -n "${DOCKERHUB_TOKEN:-}" ]] || {
        echo "❌ DOCKERHUB_TOKEN not set."
        return 1
    }

    local full_desc=$(<"README.md")
    (($(echo "$full_desc" | wc -c) <= 25000)) || {
        echo "❌ Full description > 25000 bytes"
        return 1
    }

    local short_desc=$(<"short.md")
    (($(echo "$short_desc" | wc -c) <= 100)) || {
        echo "❌ Short description > 100 bytes"
        return 1
    }

    local data=$(jq -n \
        --arg username "${DOCKERHUB_USERNAME}" \
        --arg password "${DOCKERHUB_TOKEN}" \
        '{identifier: $username, secret: $password}')

    local jwt_token=$(curl --silent --show-error --retry 3 --retry-delay 3 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "https://hub.docker.com/v2/auth/token" | jq -r '.access_token')

    if [[ -z "$jwt_token" || "$jwt_token" == "null" ]]; then
        echo "❌ Authentication failed - could not obtain JWT." >&2
        return 1
    fi

    local data=$(jq -n \
        --arg short "$short_desc" \
        --arg full "$full_desc" \
        '{description: $short, full_description: $full}')

    # Perform the PATCH request, capturing *both* body and status code
    local response=$(curl --silent --show-error --retry 3 --retry-delay 3 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "Accept: application/json" \
        -d "$data" \
        -w "\n%{http_code}" \
        "https://hub.docker.com/v2/namespaces/${DOCKERHUB_USERNAME}/repositories/${repository}")

    # Separate HTTP status code from body (last line)
    local status=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [[ "$status" == "200" ]]; then
        echo "✅ Description updated."
    else
        echo "❌ Failed (HTTP $status). Server response:" >&2
        [[ -n "$body" ]] && echo "$body" >&2
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
