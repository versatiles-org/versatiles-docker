# Docker Image: versatiles/versatiles-tilemaker

This Docker image provides a self-contained toolchain to generate OpenStreetMap based vector tiles in the [Shortbread schema](https://shortbread-tiles.org) using [tilemaker](https://github.com/systemed/tilemaker), then converts the resulting `.mbtiles` database into an efficient `.versatiles` container format.

It is part of the [versatiles-docker](https://github.com/versatiles-org/versatiles-docker) project.

---

## 🧩 Features

- Fully automated OSM → MBTiles → VersaTiles pipeline
- Based on **tilemaker** and **versatiles-rs**
- Supports **pre-mounted tmpfs** (RAM disk) for faster conversion
- No special privileges required (no SYS_ADMIN)
- Graceful shutdown on Ctrl‑C (`tini` enabled)

---

## 🚀 Quick Start

Generate `.versatiles` tiles directly from a `.pbf` extract (e.g. from Geofabrik):

```bash
docker run --rm \
  -v $(pwd)/result:/app/result \
  versatiles/versatiles-tilemaker:latest \
  "https://download.geofabrik.de/europe/germany/bremen-latest.osm.pbf" \
  bremen \
  8.6,53,9,53.2
```

The final file will be written to `./result/bremen.versatiles`.

---

## ⚙️ Optional Performance Boost with tmpfs

For large `.mbtiles` databases, read performance can be greatly improved by using a RAM-backed filesystem.

### Using Docker Compose

```yaml
services:
  tilemaker:
    image: versatiles/versatiles-tilemaker:latest
    volumes:
      - ./result:/app/result
    tmpfs:
      - /app/data/ramdisk:size=8g,mode=1777,noexec,nosuid,nodev
    environment:
      RAMDISK_DIR: /app/data/ramdisk
```

### Using docker run

```bash
docker run --rm \
  -v $(pwd)/result:/app/result \
  --mount type=tmpfs,target=/app/data/ramdisk,tmpfs-mode=1777 \
  -e RAMDISK_DIR=/app/data/ramdisk \
  versatiles/versatiles-tilemaker:latest \
  "https://download.geofabrik.de/europe/germany/bremen-latest.osm.pbf" \
  bremen \
  8.6,53,9,53.2
```

This avoids the need for `SYS_ADMIN` capabilities.

---

## 🔧 Environment Variables

| Variable       | Default   | Description                                                                          |
|----------------|-----------|--------------------------------------------------------------------------------------|
| `RAMDISK_DIR`  | *(unset)* | Path to a pre-mounted tmpfs directory for faster reads of the `.mbtiles` file.       |
| `STRICT_TMPFS` | `0`       | If set to `1`, aborts if no suitable tmpfs is found instead of falling back to disk. |

---

## 🧱 Technical Overview

The container executes [`generate_tiles.sh`](https://github.com/versatiles-org/versatiles-docker/blob/main/versatiles-tilemaker/scripts/generate_tiles.sh), which performs:

1. **Download** an `.osm.pbf` file (via `aria2c`)
2. **Renumber** with `osmium`
3. **Render** MBTiles using `tilemaker`
4. **Convert** MBTiles → VersaTiles using `versatiles convert`
5. **Store** the final result in `./result/<name>.versatiles`

---

## 🪄 Graceful Shutdown

This image uses [`tini`](https://github.com/krallin/tini) as PID 1 to correctly handle `SIGINT` / `SIGTERM` signals. You can safely interrupt the container with **Ctrl‑C**.

---

## 📄 License

Distributed under the MIT License.
Project: [versatiles.org](https://versatiles.org)
