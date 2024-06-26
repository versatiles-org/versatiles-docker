
[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles)](https://hub.docker.com/r/versatiles/versatiles/latest-debian)

# VersaTiles Docker

This repo contains .Dockerfiles and GitHub workflows for building Docker images with VersaTiles.

## Images `versatiles`

- Contains only the [versatiles](https://github.com/versatiles-org/versatiles-rs) binary
- Supported OS: Alpine, Debian and Scratch
- Supported architectures: AMD64, ARM64
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles) and [Docker Hub](https://hub.docker.com/r/versatiles/versatiles)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Linux: Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/latest-alpine" alt="Docker Image version versatiles/alpine"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/latest-alpine" alt="Docker Image size versatiles/alpine"></td>
</tr>
<tr>
	<td>Linux: Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/latest-debian" alt="Docker Image version versatiles/debian"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/latest-debian" alt="Docker Image size versatiles/debian"></td>
</tr>
<tr>
	<td>Linux: Scratch</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/latest-scratch" alt="Docker Image version versatiles/scratch"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/latest-scratch" alt="Docker Image size versatiles/scratch"></td>
</tr>
</table>

## Images `versatiles-frontend`

- Contains: [versatiles](https://github.com/versatiles-org/versatiles-rs) and the latest [frontend](https://github.com/versatiles-org/versatiles-frontend)
- Supported OS: Alpine, Debian and Scratch
- Supported architectures: AMD64, ARM64
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-frontend) and on [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-frontend)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Linux: Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-alpine" alt="Docker Image version versatiles-frontend/alpine"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-alpine" alt="Docker Image size versatiles-frontend/alpine"></td>
</tr>
<tr>
	<td>Linux: Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-debian" alt="Docker Image version versatiles-frontend/debian"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-debian" alt="Docker Image size versatiles-frontend/debian"></td>
</tr>
<tr>
	<td>Linux: Scratch</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-scratch" alt="Docker Image version versatiles-frontend/scratch"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-scratch" alt="Docker Image size versatiles-frontend/scratch"></td>
</tr>
</table>

## Images `versatiles-tilemaker`

- Contains: [versatiles](https://github.com/versatiles-org/versatiles-rs), [tilemaker](https://github.com/systemed/tilemaker) and some helpers like: [aria2](https://aria2.github.io), curl, [gdal](https://gdal.org), [osmium tool](https://osmcode.org/osmium-tool/)
- Supported OS: Debian
- Supported architectures: AMD64
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-tilemaker) and on [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-tilemaker)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Linux: Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-tilemaker/latest-debian" alt="Docker Image version versatiles-tilemaker/debian"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-tilemaker/latest-debian" alt="Docker Image size versatiles-tilemaker/debian"></td>
</tr>
</table>

## Next steps:

We are planning to add:
- `versatiles-nginx` containing nginx, lets encrypt and [frontend](https://github.com/versatiles-org/versatiles-frontend) to have everything to run a simple server ([Issue #5](https://github.com/versatiles-org/versatiles-docker/issues/5))

## Notes:

Build and generate tiles locally:
```bash
docker build --file=docker/tilemaker-debian.Dockerfile --tag=test .
mkdir -p result
docker run -it --rm --privileged --mount="type=bind,source=$(pwd)/result,target=/app/result" test generate_tiles.sh https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf osm.berlin "13.0,52.3,13.8,52.7"
```

<!--
Document `tippecanoe`:
```bash
docker run --rm -v $(pwd):/data tippecanoe:latest --force --output=test.mbtiles admin.geojson
```
-->
