#!/usr/bin/env bash
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
# fetch_release_tag [owner/repo]
# Prints the latest Git tag of a GitHub project (defaults to versatiles‑rs).
fetch_release_tag() {
    local repo=${1:-"versatiles-org/versatiles-rs"}
    curl -s "https://api.github.com/repos/${repo}/releases/latest" |
        jq -r '.tag_name'
}

#############################################################################
# 🏷️  CLI flag parsing
#############################################################################
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
# 🐳  Docker Buildx helper
#############################################################################
# setup_buildx [--push]
# Ensures a multi‑arch builder exists and prints the flags the caller should
# append to `docker buildx build`. If --push is present, it emits flags for a
# real multi‑arch push; otherwise it limits to the host arch and adds --load.
#
# Usage example:
#   EXTRA_ARGS=$(setup_buildx "$@")
#   docker buildx build $EXTRA_ARGS -t my/image .
#
setup_buildx() {
    # 1. Ensure a suitable builder is selected
    if ! docker buildx inspect multiarch >/dev/null 2>&1; then
        docker buildx create --name multiarch --driver docker-container --use
    else
        docker buildx use multiarch
    fi

    # 2. Decide on flags
    if [[ " $* " == *" --push "* ]]; then
        echo "--platform linux/amd64,linux/arm64 --push"
    else
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
        echo "--platform linux/${host_arch} --load"
    fi
}

#############################################################################
# 📄  Docker Hub description updater
#############################################################################
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
