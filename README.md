# VersaTiles Docker

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Docker images for [VersaTiles](https://github.com/versatiles-org/versatiles-rs) - a fast map tile server. This repository contains Dockerfiles and GitHub workflows for building and publishing production-ready Docker images.

## Quick Start

Get up and running in seconds:

```bash
# Pull and run a map server with web frontend
docker run -p 8080:8080 -v $(pwd):/data \
  versatiles/versatiles-frontend:latest osm.versatiles
```

Open http://localhost:8080/ in your browser to view your map.

## Prerequisites

- Docker installed ([Get Docker](https://docs.docker.com/get-docker/))

## Which Image Should I Use?

| Image                     | Use Case                      | When to Choose                                                            |
|---------------------------|-------------------------------|---------------------------------------------------------------------------|
| **versatiles-frontend**   | Map server with web interface | Best for most users - includes everything you need to serve and view maps |
| **versatiles**            | Just the binary               | You only need the CLI tool or want the smallest possible image            |
| **versatiles-nginx**      | Production deployment         | You need TLS/SSL, caching, reverse proxy, or Let's Encrypt certificates   |
| **versatiles-gdal**       | Convert geodata formats       | You're working with geospatial data formats (GeoTIFF, Shapefile, etc.)    |
| **versatiles-tilemaker**  | Generate tiles from OSM       | You want to create custom map tiles from OpenStreetMap data               |
| **versatiles-tippecanoe** | Generate vector tiles         | You need to convert GeoJSON to vector tiles                               |

## Images

### Getting Started

#### `versatiles`

Minimal image containing only the [versatiles](https://github.com/versatiles-org/versatiles-rs) binary.

- **Supported OS:** Alpine, Debian, Scratch
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles)
- **Documentation:** [Detailed README](versatiles/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles)](https://hub.docker.com/r/versatiles/versatiles)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
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

**Example usage:**
```bash
# Download and crop map data to Paris
docker run -it --rm -v $(pwd):/data versatiles/versatiles:latest \
  convert --bbox-border 3 --bbox "2.224,48.815,2.47,48.903" \
  "https://download.versatiles.org/osm.versatiles" "paris.versatiles"
```

#### `versatiles-frontend`

Map server bundled with the [versatiles-frontend](https://github.com/versatiles-org/versatiles-frontend) web interface.

- **Contains:** versatiles + web frontend
- **Supported OS:** Alpine, Debian, Scratch
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-frontend) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-frontend)
- **Documentation:** [Detailed README](versatiles-frontend/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-frontend)](https://hub.docker.com/r/versatiles/versatiles-frontend)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
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

**Example usage:**
```bash
# Serve tiles with web interface
docker run -d -p 8080:8080 -v $(pwd):/data:ro \
  versatiles/versatiles-frontend:latest osm.versatiles
```

### Production

#### `versatiles-nginx`

Production-ready setup with nginx reverse proxy and automatic Let's Encrypt SSL certificates via certbot.

- **Contains:** versatiles + nginx + certbot
- **Supported OS:** Alpine
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-nginx) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-nginx)
- **Documentation:** [Detailed README](versatiles-nginx/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-nginx)](https://hub.docker.com/r/versatiles/versatiles-nginx)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-nginx/latest?label=" alt="Docker Image version versatiles-nginx"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-nginx/latest?label=" alt="Docker Image size versatiles-nginx"></td>
</tr>
</table>

### Tile Generation

#### `versatiles-gdal`

VersaTiles combined with [GDAL](https://gdal.org) for working with geospatial data formats.

- **Contains:** versatiles + GDAL
- **Supported OS:** Debian
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-gdal) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-gdal)
- **Documentation:** [Detailed README](versatiles-gdal/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-gdal)](https://hub.docker.com/r/versatiles/versatiles-gdal)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-gdal/latest?label=" alt="Docker Image version versatiles-gdal"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-gdal/latest?label=" alt="Docker Image size versatiles-gdal"></td>
</tr>
</table>

#### `versatiles-tilemaker`

Generate vector tiles from OpenStreetMap data using [tilemaker](https://github.com/systemed/tilemaker).

- **Contains:** versatiles + tilemaker + helper tools (aria2, curl, GDAL, osmium)
- **Supported OS:** Debian
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-tilemaker) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-tilemaker)
- **Documentation:** [Detailed README](versatiles-tilemaker/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-tilemaker)](https://hub.docker.com/r/versatiles/versatiles-tilemaker)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Debian</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-tilemaker/latest?label=" alt="Docker Image version versatiles-tilemaker"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-tilemaker/latest?label=" alt="Docker Image size versatiles-tilemaker"></td>
</tr>
</table>

#### `versatiles-tippecanoe`

Create vector tiles from GeoJSON using [Felt's tippecanoe](https://github.com/felt/tippecanoe).

- **Contains:** versatiles + tippecanoe
- **Supported OS:** Alpine
- **Architectures:** AMD64, ARM64
- **Registries:** [GitHub Container Registry](https://github.com/versatiles-org/versatiles-docker/pkgs/container/versatiles-tippecanoe) | [Docker Hub](https://hub.docker.com/r/versatiles/versatiles-tippecanoe)
- **Documentation:** [Detailed README](versatiles-tippecanoe/README.md)

[![Docker Hub Pulls](https://img.shields.io/docker/pulls/versatiles/versatiles-tippecanoe)](https://hub.docker.com/r/versatiles/versatiles-tippecanoe)

<table>
<tr>
	<th>OS</th>
	<th>Version</th>
	<th>Image Size</th>
</tr>
<tr>
	<td>Alpine</td>
	<td><img src="https://img.shields.io/docker/v/versatiles/versatiles-tippecanoe/latest?label=" alt="Docker Image version versatiles-tippecanoe"></td>
	<td><img src="https://img.shields.io/docker/image-size/versatiles/versatiles-tippecanoe/latest?label=" alt="Docker Image size versatiles-tippecanoe"></td>
</tr>
</table>

## Documentation

- **VersaTiles Server:** [versatiles-rs](https://github.com/versatiles-org/versatiles-rs) - The core tile server implementation
- **Web Frontend:** [versatiles-frontend](https://github.com/versatiles-org/versatiles-frontend) - Interactive map viewer
- **Tile Data:** [download.versatiles.org](https://download.versatiles.org) - Pre-built tile datasets

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Support

- **Issues:** [GitHub Issues](https://github.com/versatiles-org/versatiles-docker/issues)
- **Main Project:** [VersaTiles Organization](https://github.com/versatiles-org)

## License

Distributed under the MIT License. See individual image directories for more details.
