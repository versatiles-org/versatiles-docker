#!/usr/bin/env bash

function run() {
	case $1 in
		"x86")
			platform=linux/amd64
			;;
		"amd")
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
	
	docker buildx build --platform=$platform --progress=plain --file=docker/$name.Dockerfile --tag=test .
	docker run --platform=$platform -it --rm test serve --auto-shutdown 1000 -p 8088 "https://download.versatiles.org/planet-20230605.versatiles"
}

#run x86 basic-alpine
run x86 basic-debian
#run x86 basic-scratch
#run x86 debian-maker
#run x86 debian-nginx
#run x86 frontend-alpine
#run x86 frontend-debian
#run x86 frontend-scratch
