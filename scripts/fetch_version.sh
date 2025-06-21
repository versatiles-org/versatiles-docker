#!/usr/bin/env bash
set -euo pipefail

curl -s https://api.github.com/repos/versatiles-org/versatiles-rs/releases/latest | jq -r '.tag_name' | sed 's/^v//'
