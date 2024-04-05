#!/usr/bin/env bash

cd "$(dirname "$0")/.."

set -e

RED="\033[1;31m"
GRE="\033[1;32m"
YEL="\033[1;33m"
END="\033[0m"

run_arch() {
	case $1 in
		"x86")
			platform=linux/amd64
			;;
		"arm")
			platform=linux/arm64
			;;
		*)
			echo "Unknown target plattform $1"
			exit 1
			;;
	esac
	
	name=$2

	if [ -z $name ]; then echo "name not set"; fi
	if [ -z $platform ]; then echo "platform not set"; fi
	
	echo -e "${YEL}Build and Test $name on $platform${END}"

	docker buildx build --platform=$platform --file=docker/$name.Dockerfile --tag=test .
	docker run --platform=$platform -it --rm test versatiles serve --auto-shutdown 1000 -p 8088 "https://download.versatiles.org/osm.versatiles"
}

function run() {
	run_arch x86 $1
	run_arch arm $1
}

run basic-alpine
run basic-debian
run basic-scratch
run frontend-alpine
run frontend-debian
run frontend-scratch
run tilemaker-debian
#run debian-nginx
