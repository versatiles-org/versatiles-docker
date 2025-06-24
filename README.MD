# VersaTiles Docker

This repo contains .Dockerfiles and GitHub workflows for building Docker images with VersaTiles.

## Images `versatiles`

- Contains only the [versatiles](https://github.com/versatiles-org/versatiles-rs) binary
- Supported OS: Alpine, Debian and Scratch
- Supported architectures: AMD64, ARM64
- See the [Dockerfile README](versatiles/README.md) for detailed information and usage instructions.
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles) and [Docker Hub](https://hub.docker.com/r/versatiles/versatiles)


[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles)](https://hub.docker.com/r/versatiles/versatiles)

<table>
<tr>
	<th>OS</th>
	<th>VersaTiles Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/alpine?label=" alt="Docker Image version versatiles/alpine"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/alpine?label=" alt="Docker Image size versatiles/alpine"></td>
</tr>
<tr>
	<td>Scratch</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/scratch?label=" alt="Docker Image version versatiles/scratch"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/scratch?label=" alt="Docker Image size versatiles/scratch"></td>
</tr>
<tr>
	<td>Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles/debian?label=" alt="Docker Image version versatiles/debian"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles/debian?label=" alt="Docker Image size versatiles/debian"></td>
</tr>
</table>

## Images `versatiles-frontend`

- Contains: [versatiles](https://github.com/versatiles-org/versatiles-rs) and the latest [frontend](https://github.com/versatiles-org/versatiles-frontend)
- Supported OS: Alpine, Debian and Scratch
- Supported architectures: AMD64, ARM64
- See the [Dockerfile README](versatiles-frontend/README.md) for detailed information and usage instructions.
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-frontend) and on [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-frontend)


[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-frontend)](https://hub.docker.com/r/versatiles/versatiles-frontend)

<table>
<tr>
	<th>OS</th>
	<th>VersaTiles Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/alpine?label=" alt="Docker Image version versatiles-frontend/alpine"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/alpine?label=" alt="Docker Image size versatiles-frontend/alpine"></td>
</tr>
<tr>
	<td>Scratch</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/scratch?label=" alt="Docker Image version versatiles-frontend/scratch"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/scratch?label=" alt="Docker Image size versatiles-frontend/scratch"></td>
</tr>
<tr>
	<td>Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-frontend/debian?label=" alt="Docker Image version versatiles-frontend/debian"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/debian?label=" alt="Docker Image size versatiles-frontend/debian"></td>
</tr>
</table>

## Images `versatiles-tilemaker`

- Contains: [versatiles](https://github.com/versatiles-org/versatiles-rs), [tilemaker](https://github.com/systemed/tilemaker) and some helpers like: [aria2](https://aria2.github.io), [curl](https://curl.se/), [gdal](https://gdal.org), [osmium tool](https://osmcode.org/osmium-tool/)
- Supported OS: Debian
- Supported architectures: AMD64, ARM64
- See the [Dockerfile README](versatiles-tilemaker/README.md) for detailed information and usage instructions.
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-tilemaker) and on [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-tilemaker)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-tilemaker)](https://hub.docker.com/r/versatiles/versatiles-tilemaker)

<table>
<tr>
	<th>OS</th>
	<th>tilemaker Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-tilemaker/latest?label=" alt="Docker Image version versatiles-tilemaker"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-tilemaker/latest?label=" alt="Docker Image size versatiles-tilemaker"></td>
</tr>
</table>

## Images `versatiles-tippecanoe`

- Contains: [versatiles](https://github.com/versatiles-org/versatiles-rs) and [felt/tippecanoe](https://github.com/felt/tippecanoe)
- Supported OS: Alpine
- Supported architectures: AMD64, ARM64
- See the [Dockerfile README](versatiles-tippecanoe/README.md) for detailed information and usage instructions.
- Images are available on [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-tippecanoe) and on [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-tippecanoe)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-tippecanoe)](https://hub.docker.com/r/versatiles/versatiles-tippecanoe)

<table>
<tr>
	<th>OS</th>
	<th>tippecanoe Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-tippecanoe/latest?label=" alt="Docker Image version versatiles-tippecanoe"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-tippecanoe/latest?label=" alt="Docker Image size versatiles-tippecanoe"></td>
</tr>
</table>
