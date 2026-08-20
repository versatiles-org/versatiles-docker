#!/usr/bin/env sh
#
# download_versatiles_binary.sh - Download VersaTiles binary for target platform
#
# USAGE
#   download_versatiles_binary.sh <TARGETPLATFORM> <VERSION>
#
# ARGUMENTS
#   TARGETPLATFORM  Platform identifier, one of:
#                   - linux/amd64-musl   (Alpine Linux, x86_64)
#                   - linux/arm64-musl   (Alpine Linux, ARM64)
#                   - linux/amd64-gnu    (Debian/Ubuntu, x86_64)
#                   - linux/arm64-gnu    (Debian/Ubuntu, ARM64)
#   VERSION         Release tag to download, e.g. "v4.9.0".
#
# DESCRIPTION
#   Downloads the given VersaTiles release for the specified platform. The
#   binary is extracted to the current directory and made executable.
#
#   VERSION is REQUIRED and deliberately not defaulted to "latest": the
#   download used to come from /releases/latest/download/, a moving URL. That
#   made the RUN layer's cache key independent of the release, so BuildKit
#   happily served a stale binary while build.sh tagged the image with a newer
#   version. Pinning the tag ties the artifact to the label and keeps a release
#   published mid-build from changing what we get.
#
# EXIT CODES
#   0  Success
#   1  Unknown platform, missing version, or download failure
#
set -eu

TARGETPLATFORM=$1
VERSION=${2:-}

if [ -z "$VERSION" ]; then
	echo "Missing VERSION argument (e.g. v4.9.0)" >&2
	exit 1
fi

BASE_URL="https://github.com/versatiles-org/versatiles-rs/releases/download/${VERSION}"

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
