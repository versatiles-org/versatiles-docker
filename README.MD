
[![Docker Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles)](https://hub.docker.com/r/versatiles/versatiles/latest-debian)

# VersaTiles Docker

This Repo contains .Dockerfiles and GitHub Workflows to build Docker Images.

## Image `versatiles`

- Contains only the `versatiles` binary
- Supported OS: Alpine, Debian and "Scratch"
- Supported Architectures: AMD64, ARM64
- Images are on [GitHub Container registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles) and on [Docker Hub](https://hub.docker.com/repository/docker/versatiles/versatiles/general)

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

## Image `versatiles-frontend`

- Contains the `versatiles` binary and the latest [frontend](https://github.com/versatiles-org/versatiles-frontend)
- Supported OS: Alpine, Debian and "Scratch"
- Supported Architectures: AMD64, ARM64
- Images are on [GitHub Container registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-frontend) and on [Docker Hub](https://hub.docker.com/repository/docker/versatiles/versatiles-frontend/general)

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

## Next steps:

We are planning to add:
- `versatiles-tilemaker` containing tilemaker to generate vector tiles ([Issue #4](https://github.com/versatiles-org/versatiles-docker/issues/4))
- `versatiles-nginx` containing nginx, lets encrypt and [frontend](https://github.com/versatiles-org/versatiles-frontend) to have everything to run a simple server ([Issue #5](https://github.com/versatiles-org/versatiles-docker/issues/5))
