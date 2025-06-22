# Docker Image: versatiles/versatiles

A minimal, lightweight, production-ready Docker image for [VersaTiles](https://github.com/versatiles-org/versatiles-rs).

## Quick Start

Pull and run the image:

```sh
docker run -it versatiles/versatiles
```

You can pass any [versatiles-rs command-line arguments](https://github.com/versatiles-org/versatiles-rs?tab=readme-ov-file#usage). For example, to convert an MBTiles file to the VersaTiles format:

```sh
docker run -it versatiles/versatiles convert osm.mbtiles osm.versatiles
```

## About

This Docker image is built from the [versatiles-org/versatiles-docker](https://github.com/versatiles-org/versatiles-docker) repository, specifically the [docker-basic/](https://github.com/versatiles-org/versatiles-docker/tree/main/docker-basic) subfolder.

## License

Distributed under the MIT License.