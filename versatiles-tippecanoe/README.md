# Docker Image: versatiles/versatiles-tippecanoe

A compact, multi‑architecture image that bundles

* **[Tippecanoe](https://github.com/felt/tippecanoe)** – lightning‑fast vector tile generation  
* **[VersaTiles CLI](https://github.com/versatiles-org/versatiles-rs)** – convert, inspect and serve Versatiles archives

Built automatically from the GitHub repository  
[`versatiles-org/versatiles-docker`](https://github.com/versatiles-org/versatiles-docker).

---

## Quick start

```bash
# Pull the image
docker pull versatiles/versatiles-tippecanoe:latest

# Show Tippecanoe version
docker run --rm versatiles/versatiles-tippecanoe -v

# Show VersaTiles version
docker run --rm --entrypoint versatiles versatiles/versatiles-tippecanoe -V
```

---

## Signal Handling

This image includes [tini](https://github.com/krallin/tini) as the init system, ensuring containers respond correctly to termination signals (e.g., Ctrl-C in interactive mode) and shut down gracefully in under 1 second.

---

## License

* Tippecanoe – MIT  
* VersaTiles – MIT  
* Dockerfile and build scripts – MIT
