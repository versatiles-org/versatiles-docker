# Docker Image: versatiles/versatiles-tilemaker

Docker image running a script to generate OpenStreetMap vector tiles in [Shortbread schema](https://shortbread-tiles.org) with [tilemaker](https://github.com/systemed/tilemaker) and converting them into a `*.versatiles` container.

## Quick Start

Pull and run the image:

```sh
docker run -it -v ".:/app/result" versatiles/versatiles-tilemaker
```

## About

This Docker image is built from the [versatiles-org/versatiles-docker](https://github.com/versatiles-org/versatiles-docker) repository, specifically the [versatiles-tilemaker/](https://github.com/versatiles-org/versatiles-docker/tree/main/versatiles-tilemaker) subfolder.

## License

Distributed under the MIT License.