#!/usr/bin/env sh

set -e

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
		echo "Unknown target plattform $TARGETPLATFORM"
		exit 1
		;;
esac

echo "Downloading versatiles binary from $URL"
curl --retry 3 -sL "$URL" | tar x -zf - versatiles
chmod +x versatiles
