#!/usr/bin/env bash
#
# entrypoint.sh — Main entrypoint for versatiles-nginx container
#
# DESCRIPTION
#   Orchestrates the startup sequence for the VersaTiles nginx container.
#   Sets up the data directory, downloads required frontend and tile data,
#   configures and starts nginx as a reverse proxy, then launches the
#   VersaTiles backend server.
#
# REQUIRED ENVIRONMENT VARIABLES
#   DOMAIN          Domain name for nginx configuration
#   FRONTEND        Frontend variant (standard|dev|min|none)
#   TILE_SOURCES    Comma-separated list of tile files to download
#   EMAIL           Email for SSL certificate registration (if not HTTP_ONLY)
#
# OPTIONAL ENVIRONMENT VARIABLES
#   HTTP_ONLY           Skip SSL certificates, run HTTP-only mode
#   BBOX                Bounding box for tile cropping (lng_min,lat_min,lng_max,lat_max)
#   CACHE_SIZE_KEYS     Nginx cache keys zone size (default: 20% of RAM)
#   CACHE_SIZE_MAX      Nginx cache max size (default: 60% of RAM)
#   CERT_MIN_DAYS       Min certificate validity before renewal (default: 30)
#   CERT_RENEW_INTERVAL Renewal check interval in seconds (default: 86400)
#
# BEHAVIOR
#   1. Set up /data directory with proper ownership for vs:vs user
#   2. Create /data/static for user-defined static files
#   3. Fetch frontend variant (calls fetch_frontend.sh)
#   4. Fetch tile data sources (calls fetch_data.sh)
#   5. Configure and start nginx reverse proxy (calls nginx_start.sh)
#   6. Launch VersaTiles backend server on port 8080
#
# ARCHITECTURE
#   - Nginx (port 80/443): Reverse proxy with caching in tmpfs
#   - VersaTiles (port 8080): Backend tile server (runs as vs:vs user)
#   - Certbot: Automatic SSL certificate management (if HTTPS mode)
#
# EXIT CODES
#   Inherits from VersaTiles backend (this script execs into it)
#
set -euo pipefail

. /scripts/utils.sh

# Fix ownership of the unified volume
mkdir -p /data
chown -R vs:vs /data || true

# user defined static files
mkdir -p /data/static
versatiles_args=(--static /data/static)
# shellcheck disable=SC2207
versatiles_args+=($(/scripts/fetch_frontend.sh))
# shellcheck disable=SC2207
versatiles_args+=($(/scripts/fetch_data.sh))

/scripts/nginx_start.sh

############### start VersaTiles ############
log "Launching VersaTiles backend with arguments: ${versatiles_args[*]}"
exec su-exec vs:vs versatiles serve -p 8080 "${versatiles_args[@]}"
