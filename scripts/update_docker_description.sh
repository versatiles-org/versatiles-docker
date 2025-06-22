#!/usr/bin/env bash
set -euo pipefail

repository="${1:-}"
[[ -n "$repository" ]] || {
    echo "Usage: $0 <repository-name>"
    exit 1
}

[[ -n "${DOCKERHUB_TOKEN:-}" ]] || {
    echo "DOCKERHUB_TOKEN not set."
    exit 1
}

SHORT_DESC=$(<"short.md")
((${#SHORT_DESC} <= 100)) || {
    echo "Short description > 100 chars"
    exit 1
}

FULL_DESC=$(<"full.md")
((${#FULL_DESC} <= 25000)) || {
    echo "Full description > 25 000 chars"
    exit 1
}

data=$(
    jq -n \
        --arg short "$SHORT_DESC" \
        --arg full "$FULL_DESC" \
        '{description: $short, full_description: $full}'
)

# send a PATCH request to update the Docker Hub repository description
status=$(curl \
    --silent \
    --show-error \
    --fail \
    --output /dev/null \
    --retry 3 \
    --retry-delay 2 \
    -X PATCH \
    -H "Content-Type: application/json" \
    -H "Authorization: JWT ${DOCKERHUB_TOKEN}" \
    -H "Accept: application/json" \
    -d "$data" \
    -w "%{http_code}" \
    "https://hub.docker.com/v2/namespaces/versatiles/repositories/${repository}")

if [[ "$status" == "200" ]]; then
    echo "✅  Description updated."
else
    echo "❌  Failed (HTTP $status)."
    exit 1
fi
