# Docker Image: versatiles/versatiles-planetiler

This Docker image provides a self-contained toolchain to generate OpenStreetMap based vector tiles in the [Shortbread schema](https://shortbread-tiles.org) using [Planetiler](https://github.com/onthegomap/planetiler) (the [VersaTiles fork](https://github.com/versatiles-org/planetiler) of Planetiler together with the [Shortbread profile](https://github.com/versatiles-org/planetiler-shortbread)), then packs the result into an efficient `.versatiles`, `.pmtiles` or `.mbtiles` container.

It is part of the [versatiles-docker](https://github.com/versatiles-org/versatiles-docker) project.

---

## 🧩 Features

- Fully automated OSM → Shortbread tiles → VersaTiles pipeline
- Based on **Planetiler** and **versatiles-rs**
- **Interactive wizard** *or* fully scriptable via flags / environment variables
- Optional **land cover** injection from [`landcover-vectors.versatiles`](https://download.versatiles.org/landcover-vectors.versatiles) (merged on the fly, no extra download, and [filtered so each kind comes from one source per zoom](https://github.com/versatiles-org/landcover-vectors#merging-with-osm)), written as a second output next to the plain OSM one
- Feature IDs in the tiles are **OSM IDs** (see [Feature IDs](#-feature-ids)); optional renumbering for 2–4% smaller tiles
- Optional **checksums** (`.md5` + `.sha256`) written next to each output
- Output as **versatiles** (brotli), **pmtiles** or **mbtiles**
- Renders the whole **planet** or any **Geofabrik** sub-region
- A clean console: one line per step with a progress bar and ETA; the complete output goes to a log file
- Graceful shutdown on Ctrl-C (`tini` enabled)

---

## 🚀 Quick Start

### Interactive

Run with an attached terminal (`-it`) and no arguments to launch the wizard. It asks whether to render the whole planet (the default) or a sub-region, whether to inject land cover from download.versatiles.org, which container format to use, the output filename, and whether Planetiler works in disk or memory mode (see [Memory](#-memory)). Mount **one** host directory at `/app/data` — it holds the source cache, temp files and the results:

```bash
docker run -it --rm \
  -v $(pwd)/planetiler:/app/data \
  versatiles/versatiles-planetiler:latest
```

### Non-interactive (flags)

Only `--area` is required; everything else has a default:

```bash
docker run --rm \
  -v $(pwd)/planetiler:/app/data \
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
      MODE: disk
    volumes:
      - ./planetiler:/app/data
```

The final file is written to `./planetiler/result/<name>.<format>`. With land cover, two files are written from the same render: `osm[.<region>].<date>.<format>` (OSM only) and `osm-landcover[.<region>].<date>.<format>` (OSM with land cover).

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
| `--landcover`             | `LANDCOVER=1`   | off                       | Also write a second output with land cover merged into the Shortbread layers. |
| `--format <FMT>`          | `FORMAT`        | `versatiles`              | `versatiles` (brotli), `pmtiles` or `mbtiles`.                        |
| `--name <BASENAME>`       | `OUTPUT_NAME`   | `osm[.<region>].<date>`   | Output filename; the extension is added automatically. Sub-regions include the region name. The land cover output is `osm-landcover[.<region>].<date>` by default, or `<BASENAME>-landcover` for a custom name. |
| `--mode <disk\|memory>`   | `MODE`          | `disk`                    | Where Planetiler keeps its temporary data: memory-mapped files, or the Java heap (faster, more RAM). See [Memory](#-memory) below. |
| `--xmx <SIZE>`            | `XMX`           | from `--mode`             | Override the Java heap that `--mode` derives, e.g. `20g`.             |
| `--torrent`               | `TORRENT=1`     | off                       | For `--area planet`: fetch the pbf via BitTorrent. See [Planet download](#-planet-download). |
| `--renumber`              | `RENUMBER=1`    | off                       | Renumber the OSM IDs with `osmium` first: renders a bit faster and makes the tiles 2–4% smaller, but the feature IDs are no longer OSM IDs. See [Feature IDs](#-feature-ids). |
| `--checksum`              | `CHECKSUM=1`    | off                       | Write `<output>.md5` and `<output>.sha256` next to each output.       |
| `-i`, `--interactive`     | `INTERACTIVE=1` | —                         | Force the interactive wizard.                                         |

Flags take precedence over environment variables, which take precedence over the built-in defaults.

> **Naming a region:** `--area` is matched by name against the Geofabrik index, so use the region's own name (e.g. `berlin`, `monaco`, `massachusetts`) — **not** a path like `germany/berlin`. If a name is ambiguous, add a qualifier (e.g. `us georgia` for the US state).

### Tuning variables

| Variable                 | Default                               | Description                                                         |
|--------------------------|---------------------------------------|---------------------------------------------------------------------|
| `LANDCOVER_URL`          | public `landcover-vectors.versatiles` | Land cover container to merge.                                      |
| `OCEAN_URL`              | osmdata.openstreetmap.de              | Water polygons zip. See [Water polygons](#-water-polygons).         |
| `OCEAN_MIRROR`           | [FAU mirror](https://ftp.fau.de/mirrors/openstreetmapdata.com-archive/) | Fallback when `OCEAN_URL` fails: the newest dated folder is used. |
| `LANGUAGES`              | `extended`                            | `--name_languages` passed to Planetiler: `extended` for the [81 languages](https://github.com/versatiles-org/planetiler-shortbread#names), a comma-separated list of codes (e.g. `en,de,fr`), or both (`extended,tok`). |
| `EXPERIMENTS`            | `all`                                 | `--shortbread_experiments` value.                                   |
| `PLANETILER_EXTRA_FLAGS` | *(unset)*                             | Extra Planetiler flags. They come after the flags of `--mode`, so they override them. |
| `JAVA_OPTS`              | *(unset)*                             | Extra JVM options. An explicit `-Xmx` here overrides `--xmx`/`XMX`. |

---

## 🧠 Memory

Planetiler itself only logs a warning when memory is short and then carries on, very slowly. This image checks instead: it estimates the RAM a run needs from the size of the `.osm.pbf` and stops with an error if the container has less. For the planet it checks before the download, using the size of the latest planet file on the server; for a region, as soon as the `.osm.pbf` is downloaded.

Choose a mode with `--mode` / `MODE`, or in the wizard:

| Mode             | Planetiler flags                       | Java heap            | RAM needed           | Planet (89 GB pbf, Oct 2026) |
|------------------|----------------------------------------|----------------------|----------------------|------------------------------|
| `disk` (default) | `--storage=mmap`                       | 0.3× pbf size + 2 GB | 0.5× pbf size + 3 GB | ~48 GB                       |
| `memory`         | `--storage=ram`                        | 1.7× pbf size + 2 GB | 1.7× pbf size + 3 GB | ~154 GB                      |

Sizes are binary (1 GB = 1024³ bytes), as Docker and the JVM count them.

In **disk** mode, Planetiler keeps node locations and multipolygon geometries in memory-mapped files, and the RAM beyond the Java heap serves as page cache for them. In **memory** mode they stay on the Java heap, which is faster but needs about three times as much RAM. The wizard shows both figures for the planet and suggests memory mode when it fits.

**Renumbering** (`--renumber`, off by default) keeps all old node IDs in a list that doubles in size when full, so it needs 8 bytes × the next power of two above the node count, plus 2 GB — for the planet (~10.7 billion nodes) ~130 GB, more than disk mode itself. If it doesn't fit but Planetiler does, renumbering is skipped with a notice; the tiles are the same, only slightly larger. The node map is a plain array indexed by node ID (`--nodemap_type=array`) for renumbered input and for the planet in disk mode; its size follows the highest node ID, ~110 GB for real OSM IDs. Everything else uses `--nodemap_type=sparsearray`, whose size follows the node count.

**Overrides:** `--xmx 40g` / `XMX=40g`, or `-Xmx` in `JAVA_OPTS`, replaces the derived heap; the check then uses that heap. Storage flags in `PLANETILER_EXTRA_FLAGS` override the mode's, but the check still assumes the mode's.

**Docker Desktop** (Mac, Windows) runs containers in a virtual machine, so the container only sees that machine's memory. If the check fails there, raise the limit under *Settings → Resources*.

See Planetiler's [PLANET.md](https://github.com/onthegomap/planetiler/blob/main/PLANET.md) for details.

---

## 🌍 Planet download

For `--area planet`, Planetiler downloads the ~89 GB planet extract over HTTP by default. With `--torrent` (or `TORRENT=1`) the image instead fetches it via **BitTorrent** using `aria2c` and feeds it to Planetiler with `--osm_path` — usually faster and more reliable. The water polygons are fetched separately (see [below](#-water-polygons)), the Natural Earth country polygons by Planetiler.

```bash
docker run --rm \
  -v $(pwd)/planetiler:/app/data \
  versatiles/versatiles-planetiler:latest --area planet --torrent
```

The pbf is cached under `/app/data/sources/planet-<date>.osm.pbf` (resumable, reused on re-runs). Override the snapshot with `PLANET_DATE=YYMMDD`, or the source with `PLANET_PBF_BASE`. `--torrent` is ignored for sub-regions (those download from Geofabrik via `--area`).

---

## 🌊 Water polygons

The `ocean` layer is built from the OSM water polygons (`water-polygons-split-3857.zip`, ~930 MB), which osmdata.openstreetmap.de rebuilds daily. The script fetches them itself before Planetiler runs and caches them at `/app/data/sources/water-polygons-split-3857.zip`:

1. A cached copy less than a week old is reused.
2. Otherwise the file is downloaded from `OCEAN_URL` (skipped if the server has nothing newer than the cache).
3. If that fails, the newest dated folder of `OCEAN_MIRROR` is tried.
4. If both fail, the cached copy is used with a warning; without one, the run stops.

To force a fresh download, delete the cached file.

---

## 🧱 Technical Overview

The container runs [`generate_tiles.sh`](https://github.com/versatiles-org/versatiles-docker/blob/main/versatiles-planetiler/scripts/generate_tiles.sh), which performs:

0. *(optional, `--renumber`)* **Renumber** the OSM input with `osmium renumber` so node/way IDs are dense. This shrinks Planetiler's node map (faster, less I/O) and shortens the feature IDs encoded in each tile (2–4% smaller output), but the IDs are then no longer OSM IDs. For the whole planet it needs ~130 GB of RAM (see [Memory](#-memory)); with less, it is skipped.
1. **Render** Shortbread tiles with `planetiler shortbread-1.1 --area=<area>` into an intermediate **PMTiles** file (flat layout → fast sequential reads).
2. **Convert** the PMTiles to the chosen container with `versatiles convert`. When land cover is enabled, a second container is converted from the same PMTiles: the VPL `from_merged_vector` operation folds the remote land cover container's features into the Shortbread layers (range-read on demand, nothing downloaded). Both sources are filtered first: up to z10 the land cover supplies forest, farmland, glacier and the other land cover kinds, while OSM supplies `water` from z4 and `residential` from z10 (see [Merging with OSM](https://github.com/versatiles-org/landcover-vectors#merging-with-osm)).
3. **Store** the final result(s) in `/app/data/result/<name>.<format>`.
4. *(optional, `--checksum`)* **Checksum** — write `<name>.<format>.md5` and `<name>.<format>.sha256` next to each result.

`.versatiles` output is compressed with **brotli**; `.pmtiles` / `.mbtiles` keep their default compression.

---

## 🔖 Feature IDs

Every feature in the tiles carries its OSM ID, encoded as `OSM ID × 10 + type`, where the type is 1 for a node, 2 for a way and 3 for a relation. For example, `15670183441` is node 1567018344, and `13691913` is relation 1369191.

With `--renumber`, `osmium renumber` replaces the OSM IDs with sequential numbers first. The tiles become 2–4% smaller (Monaco 3.7%, Liechtenstein 1.7%), but their IDs no longer point to the OSM objects — a renumbered ID is usually a valid OSM ID of an unrelated object — and they change from build to build. Use it only when nothing needs the IDs.

---

## 💾 Disk & host mounts

Mount **one** host directory at `/app/data`; it holds everything — the source cache (`sources/`), Planetiler's temp files (`tmp/`), the intermediate tiles, the results (`result/`) and the logs (`logs/`). Keeping the cache on the host means re-runs reuse already-downloaded sources. A cached `.osm.pbf` is never refreshed (the log says when one is used), so delete `sources/<area>.osm.pbf` to render current OSM data.

Rendering the whole planet is heavy: budget **~400 GB+ free disk** and a few hours (see [Memory](#-memory) for RAM). Test with a small region first, e.g. `--area monaco`. To put results elsewhere, set `RESULT_DIR`.

---

## 📟 Console and log

The console shows one line per step. On a terminal (`docker run -t` or `-it`), a progress bar with the elapsed time and an estimate of the time left redraws that line:

```
[1/4] Downloading sources       ✓ 3m12s · planet-261019.osm.pbf, 88.9 GB
      💾 disk mode: Java heap 28.7 GB, needs ~47.5 GB of 122.8 GB RAM
[2/4] Rendering tiles           ▕██████████▊         ▏  54% · processing OSM · 1h41m · ~1h26m left
```

Without a terminal (`docker logs`, CI), each step prints a start line, a status line at most once a minute, and an end line.

The complete output of all tools, including Planetiler's debug messages, goes to `/app/data/logs/<name>.log`. Planetiler's warnings and errors also appear on the console. If a step fails, the console shows the last lines of the log.

The time estimate for *Rendering tiles* gives each of Planetiler's stages a fixed share, taken from a planet run. For small regions, where the ocean stage takes most of the time, the estimate is rough.

---

## 🪄 Graceful Shutdown

This image uses [`tini`](https://github.com/krallin/tini) as PID 1 to correctly handle `SIGINT` / `SIGTERM` signals. You can safely interrupt the container with **Ctrl-C**.

---

## 📄 License

Distributed under the MIT License.
Project: [versatiles.org](https://versatiles.org)
