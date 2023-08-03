
[![Docker Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles)](https://hub.docker.com/r/versatiles/versatiles/latest-debian)

# VersaTiles Docker

This Repo contains .Dockerfiles and GitHub Workflows to build Docker images.

## Image `versatiles``

- Contains only `versatiles` and minimal dependencies.
- Supported OS: Alpine, Debian and Scratch
- Supported Architectures: AMD64, ARM64
- Images are on [GitHub Container registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles) and on [Docker Hub](https://hub.docker.com/repository/docker/versatiles/versatiles/general)

| OS             | Version                                                                                                                 | Image Size                                                                                                                    |
|----------------|-------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Linux: Alpine  | ![Docker Image version versatiles/latest-alpine](https://img.shields.io/docker/v/versatiles/versatiles/latest-alpine)   | ![Docker Image size versatiles/latest-alpine](https://img.shields.io/docker/image-size/versatiles/versatiles/latest-alpine)   |
| Linux: Debian  | ![Docker Image version versatiles/latest-debian](https://img.shields.io/docker/v/versatiles/versatiles/latest-debian)   | ![Docker Image size versatiles/latest-debian](https://img.shields.io/docker/image-size/versatiles/versatiles/latest-debian)   |
| Linux: Scratch | ![Docker Image version versatiles/latest-scratch](https://img.shields.io/docker/v/versatiles/versatiles/latest-scratch) | ![Docker Image size versatiles/latest-scratch](https://img.shields.io/docker/image-size/versatiles/versatiles/latest-scratch) |

## Image `versatiles-frontend`

- Contains `versatiles` and the latest [frontend](https://github.com/versatiles-org/versatiles-frontend)
- Supported OS: Alpine, Debian and Scratch
- Supported Architectures: AMD64, ARM64
- Images are on [GitHub Container registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-frontend) and on [Docker Hub](https://hub.docker.com/repository/docker/versatiles/versatiles-frontend/general)


| OS             | Version                                                                                                                                   | Image Size                                                                                                                             |
|----------------|-------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| Linux: Alpine  | ![Docker Image version versatiles-frontend/latest-alpine](https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-alpine)   | ![Docker Image size versatiles/latest-alpine](https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-alpine)   |
| Linux: Debian  | ![Docker Image version versatiles-frontend/latest-debian](https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-debian)   | ![Docker Image size versatiles/latest-debian](https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-debian)   |
| Linux: Scratch | ![Docker Image version versatiles-frontend/latest-scratch](https://img.shields.io/docker/v/versatiles/versatiles-frontend/latest-scratch) | ![Docker Image size versatiles/latest-scratch](https://img.shields.io/docker/image-size/versatiles/versatiles-frontend/latest-scratch) |

## Next steps:

We are planning to add:
- `versatiles-maker` containing tilemaker to generate vector tiles ([Issue #4](https://github.com/versatiles-org/versatiles-docker/issues/4))
- `versatiles-nginx` containing nginx, lets encrypt and [frontend](https://github.com/versatiles-org/versatiles-frontend) to have everything to run a simple server ([Issue #5](https://github.com/versatiles-org/versatiles-docker/issues/5))
