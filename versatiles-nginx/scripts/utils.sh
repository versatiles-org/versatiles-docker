#!/usr/bin/env bash
set -euo pipefail

color_red=""
color_green=""
color_yellow=""
color_reset=""

# Detect if stdout is a TTY and tput is available
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    color_red=$(tput setaf 1)
    color_green=$(tput setaf 2)
    color_yellow=$(tput setaf 3)
    color_reset=$(tput sgr0)
fi

log() {
    # usage: log "message" [LEVEL]
    local level=${2:-INFO}
    local color=""
    local symbol=""
    if [ -t 1 ]; then
        case "$level" in
        ERROR)
            color="$color_red"
            symbol="🌶️"
            ;;
        WARN)
            color="$color_yellow"
            symbol="🍋"
            ;;
        INFO)
            color="$color_green"
            symbol="🥦"
            ;;
        esac
    fi
    printf '%b[%s] [%s] %s %s%b\n' "$color" "$(/bin/date +%FT%T%z)" "$level" "$symbol" "$1" "$color_reset" >&2
}

require() {
    local var=$1 msg=${2:-}
    [ -n "${!var:-}" ] && return
    log "Environment variable '$var' is required${msg:+ ($msg)}" ERROR
    exit 1
}
