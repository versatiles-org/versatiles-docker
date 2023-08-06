#!/usr/bin/env sh
set -ex

versatiles serve --auto-shutdown 1000 -p 8088 "https://download.versatiles.org/planet-20230605.versatiles"
