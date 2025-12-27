#!/usr/bin/env bash
#
# download_versatiles_binary.sh - Download VersaTiles binary for target platform
#
# USAGE
#   download_versatiles_binary.sh <TARGETPLATFORM>
#
# ARGUMENTS
#   TARGETPLATFORM  Platform identifier, one of:
#                   - linux/amd64-musl   (Alpine Linux, x86_64)
#                   - linux/arm64-musl   (Alpine Linux, ARM64)
#                   - linux/amd64-gnu    (Debian/Ubuntu, x86_64)
#                   - linux/arm64-gnu    (Debian/Ubuntu, ARM64)
#
# DESCRIPTION
#   Downloads the latest VersaTiles binary from GitHub releases for the
#   specified platform. The binary is extracted to the current directory
#   and made executable.
#
# EXIT CODES
#   0  Success
#   1  Unknown platform or download failure
#
set -euo pipefail

TARGETPLATFORM=$1
BASE_URL="https://github.com/versatiles-org/versatiles-rs/releases/latest/download"

case $TARGETPLATFORM in
	"linux/amd64-musl")
		URL="${BASE_URL}/versatiles-linux-musl-x86_64.tar.gz"
		;;
	"linux/arm64-musl")
		URL="${BASE_URL}/versatiles-linux-musl-aarch64.tar.gz"
		;;
	"linux/amd64-gnu")
		URL="${BASE_URL}/versatiles-linux-gnu-x86_64.tar.gz"
		;;
	"linux/arm64-gnu")
		URL="${BASE_URL}/versatiles-linux-gnu-aarch64.tar.gz"
		;;
	*)
		echo "Unknown target platform $TARGETPLATFORM"
		exit 1
		;;
esac

echo "Downloading versatiles binary from $URL"
curl --retry 3 --max-time 30 -sL "$URL" | tar x -zf - versatiles
chmod +x versatiles
