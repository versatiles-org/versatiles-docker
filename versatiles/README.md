# Docker Image: `versatiles/versatiles`

A minimal, lightweight, production-ready Docker image containing only [VersaTiles](https://github.com/versatiles-org/versatiles-rs).

## Quick Start

You can explore the CLI directly:

```bash
docker run -it versatiles/versatiles:latest
```

Every command from **versatiles‑rs** is available inside the container.

## Example: Download and Crop Map Data

The following example downloads a prebuilt VersaTiles dataset and crops it to a bounding box around Paris.

```bash
# Download Map Data
docker run -it --rm -v $(pwd):/data versatiles/versatiles:latest \
  convert --bbox-border 3 --bbox "2.224,48.815,2.47,48.903" \
  "https://download.versatiles.org/osm.versatiles" "paris.versatiles"
```

## Example: Run the Tile Server

> [!TIP]
> For production deployments with **caching**, **TLS**, and **reverse‑proxy features**, see the companion image  
> **versatiles-nginx**: [GHCR](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-nginx), [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-nginx), [Repo](https://github.com/versatiles-org/versatiles-docker?tab=readme-ov-file#image-versatiles-nginx), [Readme](https://github.com/versatiles-org/versatiles-docker/blob/main/versatiles-nginx/README.md)

After generating or downloading a `.versatiles` file, start the server:

```bash
docker run -d --name versatiles -p 80:8080 -v $(pwd):/data \
  versatiles/versatiles:latest \
  serve --static "frontend-dev.br.tar.gz" "paris.versatiles"
```

The container exposes port **8080** internally. Map it however you like (`-p 80:8080`, `-p 8080:8080`, etc.).

The server:
- Serves tiles from your `.versatiles` container
- Optionally provides static frontend assets (`--static <file>`)

## Volumes

A common pattern is to mount the working directory:

```bash
-v $(pwd):/data
```

All relative paths inside the VersaTiles CLI will resolve to `/data`.

## Image Variants

This image is available in three variants:

| Variant   | Version                                                                   | Size                                                                               | Signal Handling                                                               |
|-----------|---------------------------------------------------------------------------|------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| `alpine`  | ![](https://img.shields.io/docker/v/versatiles/versatiles/alpine?label=)  | ![](https://img.shields.io/docker/image-size/versatiles/versatiles/alpine?label=)  | ✅ Includes [tini](https://github.com/krallin/tini) for proper signal handling |
| `debian`  | ![](https://img.shields.io/docker/v/versatiles/versatiles/debian?label=)  | ![](https://img.shields.io/docker/image-size/versatiles/versatiles/debian?label=)  | ✅ Includes [tini](https://github.com/krallin/tini) for proper signal handling |
| `scratch` | ![](https://img.shields.io/docker/v/versatiles/versatiles/scratch?label=) | ![](https://img.shields.io/docker/image-size/versatiles/versatiles/scratch?label=) | ⚠️ No tini included. Use `docker run --init` if you need signal handling      |

**Signal Handling:**
The Alpine and Debian variants include tini as the init system, ensuring containers respond correctly to termination signals (e.g., Ctrl-C in interactive mode) and shut down gracefully in under 1 second.

For the scratch variant, if you need proper signal handling, use Docker's `--init` flag:
```bash
docker run --init -it versatiles/versatiles:scratch
```

## About This Image

This image is built from the  
`versatiles-org/versatiles-docker` repository, specifically the `versatiles/` subdirectory:

https://github.com/versatiles-org/versatiles-docker/tree/main/versatiles

## License

Distributed under the MIT License.