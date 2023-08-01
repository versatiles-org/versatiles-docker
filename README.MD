# VersaTiles Docker

This Repo contains .Dockerfiles and GitHub Workflows to build Docker images

## Level 1

The folder `docker/level1` contains .Dockerfiles for creating minimal images. These images containing only the `versatiles` binary, curl and sqlite. Currently we support:
- `debian`
- `alpine`
- `scratch`

## Level 2

The folder `docker/level2` contains .Dockerfiles for more complex images based on the previous level1 images. Currently they are all based on `debian`:
- `debian-frontend` adds the [frontend](https://github.com/versatiles-org/versatiles-frontend)
- *TODO:* ~~`debian-nginx` adds nginx and the [frontend](https://github.com/versatiles-org/versatiles-frontend)~~
- *TODO:* ~~`debian-maker` adds tilemaker~~
