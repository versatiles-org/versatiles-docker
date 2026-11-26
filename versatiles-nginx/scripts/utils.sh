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
    if [ -t 1 ]; then
        case "$level" in
        ERROR) color="$color_red" ;;
        WARN) color="$color_yellow" ;;
        *)
            level="INFO"
            color="$color_green"
            ;;
        esac
    fi
    printf '%b[%s] [%s] %s%b\n' "$color" "$(/bin/date -u '+%F %T')" "$level" "$1" "$color_reset" >&2
}

require() {
    local var=$1 msg=${2:-}
    [ -n "${!var:-}" ] && return
    log "Environment variable '$var' is required${msg:+ ($msg)}" ERROR
    exit 1
}

parse_domains() {
    # DOMAIN is one domain or several, separated by commas. Sets DOMAINS (an
    # array), CERT_NAME (the first domain, which names the certificate's
    # folder) and SERVER_NAMES (the domains separated by spaces, for nginx).
    local d
    local -a parts
    DOMAINS=()
    IFS=',' read -ra parts <<<"${DOMAIN//[[:space:]]/}"
    for d in "${parts[@]}"; do
        if [ -n "$d" ]; then DOMAINS+=("$d"); fi
    done
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        log "DOMAIN '$DOMAIN' names no domain" ERROR
        exit 1
    fi
    CERT_NAME=${DOMAINS[0]}
    SERVER_NAMES="${DOMAINS[*]}"
}
