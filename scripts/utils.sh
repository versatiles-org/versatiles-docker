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
#   • Uses the GitHub REST API. Unauthenticated requests are limited to
#     60 req/hr per IP, which is easily exhausted when several build jobs
#     run in parallel on a shared runner IP (HTTP 403). To raise the limit
#     to ~1000 req/hr, export GITHUB_TOKEN (or GH_TOKEN) — when present it
#     is sent as a Bearer "Authorization" header automatically.
# --------------------------------------------------------------------------- #
# fetch_release_tag [owner/repo]
# Prints the latest Git tag of a GitHub project (defaults to versatiles‑rs).
fetch_release_tag() {
    local repo=${1:-"versatiles-org/versatiles-rs"}
    local tag
    local response

    # Authenticate when a token is available to avoid the 60 req/hr
    # unauthenticated rate limit.
    local auth_args=()
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    if [[ -n "$token" ]]; then
        auth_args=(--header "Authorization: Bearer ${token}")
    fi

    response=$(curl --retry 3 --silent --show-error --location --fail \
        --header "Accept: application/vnd.github+json" \
        "${auth_args[@]}" \
        "https://api.github.com/repos/${repo}/releases/latest") || {
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
        --push) export needs_push=true ;;
        --test | --testing) export needs_testing=true ;;
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
#     --cache-from type=gha,scope=…
#     --cache-to   type=gha,scope=…,mode=max
#
# Arguments:
#   $1 (optional) — image name used as scope suffix so each image gets its own
#                   cache partition (e.g. "versatiles-nginx"). Without it, all
#                   parallel jobs would share one scope and evict each other.
#
# It outputs nothing when:
#   • the script is not running inside GitHub Actions ($GITHUB_ACTIONS not set)
#
# Usage:
#   docker buildx build $(buildx_cache_args "$name") …
#
# --------------------------------------------------------------------------- #
buildx_cache_args() {
    local scope="versatiles-docker${1:+-$1}"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "Setting up Buildx cache for GitHub Actions… (scope=$scope)" 1>&2
        echo "--cache-from type=gha,scope=$scope --cache-to type=gha,scope=$scope,mode=max"
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
    IFS=',' read -ra tag_list <<<"$tag_csv"

    # Produce one  --tag  flag for every <image>:<tag> combination
    local tag_args=()
    for image in "${images[@]}"; do
        [[ -z "$image" ]] && continue
        for tag in "${tag_list[@]}"; do
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
# Arguments:
#   $1 = target stage name
#   $2 = image name(s) (comma-separated)
#   $3 = tag(s) (comma-separated)
#   $4 = dockerfile path (optional, defaults to ".")
#
# Example:
#   build_load_image versatiles-alpine "$NAME" "latest,$VER,alpine" "./versatiles/Dockerfile"
# --------------------------------------------------------------------------- #
build_load_image() {
    local target="$1"
    local name="$2"
    local tags="$3"
    local dockerfile="${4:-.}"

    echo "  - build, load: $target"
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

    # shellcheck disable=SC2046,SC2086
    docker buildx build \
        --file "$dockerfile" \
        --target "$target" \
        $(build_image_args "$name" "$tags") \
        --platform "linux/${host_arch}" \
        $(buildx_cache_args "$name") \
        ${BUILD_ARGS:-} \
        --load .
}

# --------------------------------------------------------------------------- #
#  build_push_image
# --------------------------------------------------------------------------- #
# Builds a *multi‑architecture* image (amd64 + arm64) and pushes it directly
# to the Docker registry in one step.
#
# Arguments:
#   $1 = target stage name
#   $2 = image name(s) (comma-separated)
#   $3 = tag(s) (comma-separated)
#   $4 = dockerfile path (optional, defaults to ".")
#
# Example:
#   build_push_image versatiles-alpine "$NAME" "latest,$VER,alpine" "./versatiles/Dockerfile"
# --------------------------------------------------------------------------- #
build_push_image() {
    local target="$1"
    local name="$2"
    local tags="$3"
    local dockerfile="${4:-.}"

    echo "  - build, push: $target"
    _ensure_builder

    # shellcheck disable=SC2046,SC2086
    docker buildx build \
        --file "$dockerfile" \
        --target "$target" \
        $(build_image_args "versatiles/$name,ghcr.io/versatiles-org/$name" "$tags") \
        --platform linux/amd64,linux/arm64 \
        $(buildx_cache_args "$name") \
        ${BUILD_ARGS:-} \
        --push . >/dev/null
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

    # Validate repository name to prevent path traversal
    if [[ ! "$repository" =~ ^[a-z0-9-]+$ ]]; then
        echo "❌ Invalid repository name: $repository (must match ^[a-z0-9-]+$)" >&2
        return 1
    fi
    [[ -n "${DOCKERHUB_TOKEN:-}" ]] || {
        echo "❌ DOCKERHUB_TOKEN not set."
        return 1
    }

    # Determine the directory containing the README and short.md files
    # If repository is "versatiles", use the versatiles/ directory
    # Otherwise use the repository name as-is (e.g., versatiles-nginx/)
    local repo_dir="$repository"

    local full_desc
    full_desc=$(<"$repo_dir/README.md")
    (( ${#full_desc} <= 25000 )) || {
        echo "❌ Full description > 25000 bytes"
        return 1
    }

    local short_desc
    short_desc=$(<"$repo_dir/short.md")
    (( ${#short_desc} <= 100 )) || {
        echo "❌ Short description > 100 bytes"
        return 1
    }

    local data
    data=$(jq -n \
        --arg username "${DOCKERHUB_USERNAME}" \
        --arg password "${DOCKERHUB_TOKEN}" \
        '{identifier: $username, secret: $password}')

    local jwt_token
    jwt_token=$(curl --silent --show-error --retry 3 --retry-delay 3 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "https://hub.docker.com/v2/auth/token" | jq -r '.access_token')

    if [[ -z "$jwt_token" || "$jwt_token" == "null" ]]; then
        echo "❌ Authentication failed - could not obtain JWT." >&2
        return 1
    fi

    data=$(jq -n \
        --arg short "$short_desc" \
        --arg full "$full_desc" \
        '{description: $short, full_description: $full}')

    # Perform the PATCH request, capturing *both* body and status code
    local response
    response=$(curl --silent --show-error --retry 3 --retry-delay 3 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "Accept: application/json" \
        -d "$data" \
        -w "\n%{http_code}" \
        "https://hub.docker.com/v2/namespaces/${DOCKERHUB_USERNAME}/repositories/${repository}")

    # Separate HTTP status code from body (last line)
    local status
    status=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

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
