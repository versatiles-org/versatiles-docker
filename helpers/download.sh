#!/usr/bin/env sh

set -e

TARGETPLATFORM=$1
URL="https://github.com/versatiles-org/versatiles-rs/releases/latest/download/versatiles"

case $TARGETPLATFORM in
	"linux/amd64-musl")
		curl -sL "${URL}-linux-x86_64-musl.tar.gz" | tar x -z -f - versatiles
		;;
	"linux/arm64-musl")
		curl -sL "${URL}-linux-aarch64-musl.tar.gz" | tar x -z -f - versatiles
		;;
	"linux/amd64-gnu")
		curl -sL "${URL}-linux-x86_64-gnu.tar.gz" | tar x -z -f - versatiles
		;;
	"linux/arm64-gnu")
		curl -sL "${URL}-linux-aarch64-gnu.tar.gz" | tar x -z -f - versatiles
		;;
	"macos-x86_64.tar.gz")
		echo "IMPLEMENT ME!"
		exit 1
		;;
	"macos-aarch64.tar.gz")
		echo "IMPLEMENT ME!"
		exit 1
		;;
	*)
		echo "Unknown target plattform $TARGETPLATFORM"
		exit 1
		;;
esac