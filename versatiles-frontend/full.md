# Docker Image: versatiles/versatiles-frontend

A production-ready Docker image running a [VersaTiles server](https://github.com/versatiles-org/versatiles-rs) with the [developer frontend](https://github.com/versatiles-org/versatiles-frontend).

## Quick Start

Pull and run the image:

```sh
docker run -it versatiles/versatiles osm.versatiles
```

You can pass any [`versatiles serve` command-line arguments](https://github.com/versatiles-org/versatiles-rs?tab=readme-ov-file#serve-tiles). For example, to serve on port 80:

```sh
docker run -it versatiles/versatiles --port 80 osm.mbtiles
```

## About

This Docker image is built from the [versatiles-org/versatiles-docker](https://github.com/versatiles-org/versatiles-docker) repository, specifically the [docker-frontend/](https://github.com/versatiles-org/versatiles-docker/tree/main/docker-frontend) subfolder.

## License

Distributed under the MIT License.