#!/usr/bin/env bash
set -euo pipefail

REPO=${1:-"versatiles-org/versatiles-rs"}

curl -s https://api.github.com/repos/$REPO/releases/latest | jq -r '.tag_name'
