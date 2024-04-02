#!/usr/bin/env bash
mkdir -p data

set -ex

# reading arguments
TILE_URL=$1 # url of pbf file
TILE_NAME=$2 # name of the result
TILE_BBOX=$3 # bbox

if [[ $TILE_URL != http* ]]
then
	echo "First argument must be a valid URL"
	exit 1
fi

if [ -z "$TILE_NAME" ]
then
	echo "Second argument must be a name"
	exit 1
fi

if [ -z "$TILE_BBOX" ]
then
	TILE_BBOX="-180,-86,180,86"
fi

echo "GENERATE OSM VECTOR TILES:"
echo "   URL:  $TILE_URL"
echo "   NAME: $TILE_NAME"
echo "   BBOX: $TILE_BBOX"

echo "DOWNLOAD DATA"
aria2c --seed-time=0 --dir=data "$TILE_URL"
pbf_file=$(ls data/*.pbf)
if [ $(echo $pbf_file | wc -l) -ne 1 ]
then
	echo "There should be only one PBF file"
	exit 1
fi
mv "${pbf_file}" data/input.pbf

echo "PREPARE DATA"
time osmium renumber --progress -o data/prepared.pbf data/input.pbf
rm data/input.pbf

echo "RENDER TILES"
cd shortbread-tilemaker
time tilemaker --input ../data/prepared.pbf --config config.json --process process.lua --bbox $TILE_BBOX --output ../data/output.mbtiles --compact --shard-stores
cd ..
rm data/prepared.pbf

echo "CONVERT TILES"
file_size=$(stat -c %s data/output.mbtiles)
ram_disk_size=$(perl -E "use POSIX;say ceil($file_size/1073741824 + 0.3)")
mkdir -p ramdisk
mount -t tmpfs -o size=${ram_disk_size}G ramdisk ramdisk
mv data/output.mbtiles ramdisk
time versatiles convert -c brotli ramdisk/output.mbtiles data/output.versatiles

echo "RETURN RESULT"
mv data/output.versatiles "/app/result/${TILE_NAME}.versatiles"
