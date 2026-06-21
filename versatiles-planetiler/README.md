# Docker Image: versatiles/versatiles-planetiler

This Docker image provides a self-contained toolchain to generate OpenStreetMap based vector tiles in the [Shortbread schema](https://shortbread-tiles.org) using [Planetiler](https://github.com/onthegomap/planetiler) (the [VersaTiles fork](https://github.com/versatiles-org/planetiler) with the Shortbread profile), then packs the result into an efficient `.versatiles`, `.pmtiles` or `.mbtiles` container.

It is part of the [versatiles-docker](https://github.com/versatiles-org/versatiles-docker) project.

---

## 🧩 Features

- Fully automated OSM → Shortbread tiles → VersaTiles pipeline
- Based on **Planetiler** and **versatiles-rs**
- **Interactive wizard** *or* fully scriptable via flags / environment variables
- Optional **land cover** injection from [`landcover-vectors.versatiles`](https://download.versatiles.org/landcover-vectors.versatiles) (merged on the fly, no extra download)
- Output as **versatiles** (brotli), **pmtiles** or **mbtiles**
- Renders the whole **planet** or any **Geofabrik** sub-region
- Graceful shutdown on Ctrl-C (`tini` enabled)

---

## 🚀 Quick Start

### Interactive

Run with an attached terminal (`-it`) and no arguments to launch the wizard. It asks whether to render the whole planet or a sub-region, whether to inject land cover, which container format to use, and the output filename:

```bash
docker run -it --rm \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/result:/app/result \
  versatiles/versatiles-planetiler:latest
```

### Non-interactive (flags)

Only `--area` is required; everything else has a default:

```bash
docker run --rm \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/result:/app/result \
  versatiles/versatiles-planetiler:latest \
  --area monaco --landcover
```

### Non-interactive (docker-compose)

```yaml
services:
  planetiler:
    image: versatiles/versatiles-planetiler:latest
    environment:
      AREA: planet
      LANDCOVER: "1"
      FORMAT: versatiles
      JAVA_OPTS: -Xmx20g
    volumes:
      - ./data:/app/data
      - ./result:/app/result
```

The final file is written to `./result/<name>.<format>`.

---

## ⚙️ How interactive vs. non-interactive is decided

The container chooses its mode from two signals:

| Invocation                             | stdin     | Behavior                |
|----------------------------------------|-----------|-------------------------|
| `docker run -it …` (no args)           | terminal  | **Interactive wizard**  |
| `docker run … --area …` (args or `-e`) | any       | **Non-interactive**     |
| `docker run …` (no `-it`, no config)   | not a tty | **Usage hint + exit 1** |

The terminal check (`[ -t 0 ]`) prevents a detached or CI run from hanging on a prompt. Use `-i` / `INTERACTIVE=1` to force the wizard.

---

## 🎛️ Options

| Flag                      | Environment     | Default                   | Description                                                           |
|---------------------------|-----------------|---------------------------|-----------------------------------------------------------------------|
| `--area <planet\|REGION>` | `AREA`          | *(required)*              | `planet`, or a Geofabrik area name (e.g. `monaco`, `berlin`) matched against the [Geofabrik index](https://download.geofabrik.de/). |
| `--landcover`             | `LANDCOVER=1`   | off                       | Merge land cover into the Shortbread layers.                          |
| `--format <FMT>`          | `FORMAT`        | `versatiles`              | `versatiles` (brotli), `pmtiles` or `mbtiles`.                        |
| `--name <BASENAME>`       | `OUTPUT_NAME`   | `osm[-landcover].<date>`  | Output filename; the extension is added automatically.                |
| `--xmx <SIZE>`            | `XMX`           | auto (from available RAM) | JVM heap for Planetiler, e.g. `20g`. See [Memory](#-memory) below.    |
| `--torrent`               | `TORRENT=1`     | off                       | For `--area planet`: fetch the pbf via BitTorrent. See [Planet download](#-planet-download). |
| `-i`, `--interactive`     | `INTERACTIVE=1` | —                         | Force the interactive wizard.                                         |

Flags take precedence over environment variables, which take precedence over the built-in defaults.

> **Naming a region:** `--area` is matched by name against the Geofabrik index, so use the region's own name (e.g. `berlin`, `monaco`, `massachusetts`) — **not** a path like `germany/berlin`. If a name is ambiguous, add a qualifier (e.g. `us georgia` for the US state).

### Tuning variables

| Variable                 | Default                               | Description                                                         |
|--------------------------|---------------------------------------|---------------------------------------------------------------------|
| `LANDCOVER_URL`          | public `landcover-vectors.versatiles` | Land cover container to merge.                                      |
| `LANGUAGES`              | `en,fr,es,de,ar,el,it,nl,pl,pt,uk`    | `--name_languages` passed to Planetiler.                            |
| `EXPERIMENTS`            | `all`                                 | `--shortbread_experiments` value.                                   |
| `PLANETILER_EXTRA_FLAGS` | `--nodemap_type=array --storage=mmap` | Extra Planetiler flags.                                             |
| `JAVA_OPTS`              | *(unset)*                             | Extra JVM options. An explicit `-Xmx` here overrides `--xmx`/`XMX`. |

---

## 🧠 Memory

Planetiler does **not** auto-abort on low memory — it only logs a warning and continues — so plan capacity yourself.

With the default `--storage=mmap --nodemap_type=array`, Planetiler keeps node locations in **memory-mapped files**, so the JVM heap can stay modest and the dominant requirement is **free RAM for the OS page cache**. Rule of thumb: **≥ 0.5× the `.osm.pbf` size as free RAM** (the whole planet is a ~70 GB pbf → **64 GB+ RAM** recommended).

**JVM heap (`-Xmx`):** In a container the JVM otherwise grabs only ~25 % of the cgroup limit. This image instead derives a sensible default (~40 % of the memory available to the container, capped at 32 GB) and prints it on startup. Override it with `--xmx 20g` / `XMX=20g`, or set the full `JAVA_OPTS` (an explicit `-Xmx` there wins).

**Big machines:** to keep everything in RAM for maximum speed, switch storage and raise the heap:

```bash
docker run --rm \
  -e PLANETILER_EXTRA_FLAGS="--storage=ram --nodemap_type=array" \
  -e XMX=110g \
  -v $(pwd)/result:/app/result \
  versatiles/versatiles-planetiler:latest --area planet
```

See Planetiler's [PLANET.md](https://github.com/onthegomap/planetiler/blob/main/PLANET.md) for details.

---

## 🌍 Planet download

For `--area planet`, Planetiler downloads the ~70 GB planet extract over HTTP by default. With `--torrent` (or `TORRENT=1`) the image instead fetches it via **BitTorrent** using `aria2c` and feeds it to Planetiler with `--osm_path` — usually faster and more reliable. The other sources (water polygons, Natural Earth) are still fetched by Planetiler.

```bash
docker run --rm \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/result:/app/result \
  versatiles/versatiles-planetiler:latest --area planet --torrent
```

The pbf is cached under `/app/data/sources/planet-<date>.osm.pbf` (resumable, reused on re-runs). Override the snapshot with `PLANET_DATE=YYMMDD`, or the source with `PLANET_PBF_BASE`. `--torrent` is ignored for sub-regions (those download from Geofabrik via `--area`).

---

## 🧱 Technical Overview

The container runs [`generate_tiles.sh`](https://github.com/versatiles-org/versatiles-docker/blob/main/versatiles-planetiler/scripts/generate_tiles.sh), which performs:

1. **Render** Shortbread tiles with `planetiler shortbread-1.1 --area=<area>` into an intermediate **PMTiles** file (flat layout → fast sequential reads).
2. **Convert** the PMTiles to the chosen container with `versatiles convert`. When land cover is enabled, the VPL `from_merged_vector` operation folds the remote land cover container's features into the Shortbread layers (range-read on demand, nothing downloaded).
3. **Store** the final result in `/app/result/<name>.<format>`.

`.versatiles` output is compressed with **brotli**; `.pmtiles` / `.mbtiles` keep their default compression.

---

## 💾 Disk & host mounts

Rendering the whole planet is heavy: budget **~400 GB+ free disk** and a few hours (see [Memory](#-memory) for RAM). Mount a host directory at `/app/data` so the large intermediate files don't live in the container layer, and at `/app/result` for the output. Test with a small region first, e.g. `--area monaco`.

---

## 🪄 Graceful Shutdown

This image uses [`tini`](https://github.com/krallin/tini) as PID 1 to correctly handle `SIGINT` / `SIGTERM` signals. You can safely interrupt the container with **Ctrl-C**.

---

## 📄 License

Distributed under the MIT License.
Project: [versatiles.org](https://versatiles.org)
