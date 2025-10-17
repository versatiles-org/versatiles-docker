# Docker Image: versatiles/versatiles-frontend

A production‑ready Docker image that runs a [VersaTiles server](https://github.com/versatiles-org/versatiles-rs) bundled with the [developer front‑end](https://github.com/versatiles-org/versatiles-frontend).

## Quick Start

Pull the image and display its built‑in help:

```sh
docker run -it --rm versatiles/versatiles-frontend --help
```

## Usage

To serve a VersaTiles container together with the web front‑end using the latest image:

1. Navigate to the directory that contains an `osm.versatiles` (or any other `*.versatiles`) file.  
2. Start the server with:

```bash
docker run \
  -p 8080:8080 \
  -v "$(pwd)":/data:ro \
  versatiles/versatiles-frontend:latest-alpine \
  osm.versatiles
```

Open <http://localhost:8080/> in your browser. You should see something like this: [screenshot](../assets/screenshots/frontend_index.png).

## Command Breakdown

- **`docker run`** — Launches the container.  
- **`-p 8080:8080`** — Maps port **8080** inside the container to **8080** on the host.  
- **`-v "$(pwd)":/data:ro`** — Binds the current directory to **/data** inside the container (read‑only).  
- **`versatiles/versatiles-frontend:latest-alpine`** — Specifies the Docker image (see [other tags](https://github.com/versatiles-org/versatiles-docker#images-versatiles-frontend)).

Everything after the image name is passed to `versatiles server`:

- **`'osm.versatiles'`** — Serves the mounted `osm.versatiles` file (adjust the path if your file is named differently).

## Resources

- **Server** — [versatiles‑rs](https://github.com/versatiles-org/versatiles-rs) (Rust)  
- **Dockerfiles** — [versatiles‑docker](https://github.com/versatiles-org/versatiles-docker)  
- **Front‑end** — [versatiles‑frontend](https://github.com/versatiles-org/versatiles-frontend) · [latest release](https://github.com/versatiles-org/versatiles-frontend/releases/latest/)  
- **Tile data** — <https://download.versatiles.org>

## About This Image

This image is built from the [`versatiles-frontend`](https://github.com/versatiles-org/versatiles-docker/tree/main/versatiles-frontend) directory in the [versatiles‑docker](https://github.com/versatiles-org/versatiles-docker) repository.

## License

MIT