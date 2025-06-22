#!/usr/bin/env bash
# scripts/parse_arguments.sh
#
# Usage (inside another script):
#   source "$(dirname "$0")/parse_arguments.sh" "$@"
#
# After that call, you have:
#   $needs_push    → true/false
#   $needs_testing → true/false
#
# If you run this file directly instead of sourcing it, it just prints the
# resulting values, making it easy to inspect in CI logs.

set -euo pipefail
shopt -s extglob

###############################################################################
# Default values
###############################################################################
needs_push=false
needs_testing=false

###############################################################################
# Parse CLI
###############################################################################
while (("$#")); do
    case "$1" in
    --push) needs_push=true ;;
    --test | --testing) needs_testing=true ;;
    -h | --help)
        cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options
  --push            Set needs_push=true
  --test, --testing Set needs_testing=true
  -h, --help        Show this help
EOF
        return 0 2>/dev/null || exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        return 1 2>/dev/null || exit 1
        ;;
    esac
    shift
done

###############################################################################
# When sourced we’re done; when executed, print the result for debugging.
###############################################################################
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'needs_push=%s\nneeds_testing=%s\n' \
        "$needs_push" "$needs_testing"
fi
