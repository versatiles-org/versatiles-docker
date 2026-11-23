# Docker Image: versatiles‑nginx

A production‑ready, **zero‑dependency** image that bundles

* a [VersaTiles](https://github.com/versatiles-org/versatiles-rs) tile server (`versatiles serve`)
* an in‑memory **Nginx** reverse‑proxy & tile cache
* an optional static [front‑end](https://github.com/versatiles-org/versatiles-frontend)
* automatic HTTPS certificates via **Let’s Encrypt**

in **one single container**.

## Quick Start

Point a domain (e.g. `maps.example.com`) at your server, then run:

```bash
docker run -d --name versatiles \
  -p 80:80 -p 443:443 \
  -v "$(pwd)/data:/data" \
  -e DOMAIN=maps.example.com \
  -e EMAIL=admin@example.com \
  -e FRONTEND=standard \
  -e TILE_SOURCES=osm-vector.versatiles \
  -e BBOX="9.5,46.3,17.2,49.1" \
  versatiles/versatiles-nginx:latest
```

> [!IMPORTANT]
> `DOMAIN` must resolve to this server and port 80 must be reachable from the
> internet: the first start obtains a Let’s Encrypt certificate via ACME
> HTTP‑01. Renewal checks then run in the background.

The first start also downloads the frontend and the map data. The optional `BBOX` crops the
download to one region — worth setting, since the full `osm-vector.versatiles` planet
is ~66 GB and nothing is served until it has finished downloading.

To run **without TLS** — behind a CDN, a load balancer, or on a private network
— set `HTTP_ONLY=1` and omit `EMAIL` and `-p 443:443`.

## Environment Variables

| Variable              | Required           | Default          | Purpose                                                                     |
|-----------------------|--------------------|------------------|-----------------------------------------------------------------------------|
| `DOMAIN`              | **Yes**            | –                | Fully qualified domain name served by Nginx and used for ACME issuance.     |
| `EMAIL`               | Unless `HTTP_ONLY` | –                | Contact address for ACME registration.                                      |
| `FRONTEND`            | **Yes**            | –                | UI bundle: `standard`, `dev`, `min`, `tiny`, `blank`, or `none`.            |
| `TILE_SOURCES`        | **Yes**            | –                | Comma‑separated tile archives — see [Tile Data](#tile-data).                |
| `BBOX`                | No                 | –                | `lng_min,lat_min,lng_max,lat_max`. Crops **downloads** only.                |
| `HTTP_ONLY`           | No                 | –                | Serve plain HTTP on port 80, no certificates. For use behind a proxy.       |
| `CACHE_SIZE_KEYS`     | No                 | ≈20 % RAM        | Nginx `keys_zone` size, e.g. `128m`.                                        |
| `CACHE_SIZE_MAX`      | No                 | ≈60 % RAM        | Maximum cached bytes, e.g. `2g`.                                            |
| `CERT_MIN_DAYS`       | No                 | `30`             | Skip ACME on startup if the current certificate is valid for longer.        |
| `CERT_RENEW_INTERVAL` | No                 | `86400` (24 h)   | Seconds between background `certbot renew` attempts.                        |

## Data Directory

The container needs **one** bind‑mount at `/data`:

```
/data
 ├─ certificates/   Let’s Encrypt config & live certificates
 ├─ frontend/       downloaded UI bundle (unless FRONTEND=none)
 ├─ log/            Nginx access & error logs
 ├─ static/         your static files (served before frontend files)
 └─ tiles/          tile archives
```

VersaTiles runs as the unprivileged user `vs`, with uid and gid `10001`. At every
start the container makes `/data` and everything in it owned by them. The ids
are fixed when the image is built; setting `UID` or `GID` when running it
changes nothing.

## Tile Data

Each entry in `TILE_SOURCES` is resolved against `/data/tiles/`:

| State          | Behaviour                                                                                          |
|----------------|----------------------------------------------------------------------------------------------------|
| File present   | Served as‑is. Nothing is downloaded, modified, or deleted.                                          |
| File missing   | Downloaded once from [download.versatiles.org](https://download.versatiles.org/), then kept.        |

Tiles are served at `/tiles/{name}/{z}/{x}/{y}`, where `{name}` is the part of
the filename before its first dot — `osm-vector.versatiles` and a dated
`osm-vector.20261101.versatiles` both become `/tiles/osm-vector/…`, which is
where the frontends load the map from. A file whose name has more than that is
also served under its name without the extension, e.g.
`/tiles/osm-vector.20261101/…`.

> [!NOTE]
> The hosted tilesets were renamed so each name ends with its format:
> `osm` → `osm-vector`, `landcover-vectors` → `landcover-vector`,
> `hillshade-vectors` → `hillshade-vector`, `bathymetry-vectors` →
> `bathymetry-vector`, `elevation` → `elevation-raster`, `satellite` →
> `satellite-raster`. Old names in `TILE_SOURCES` still work: the file is
> downloaded under its new name but saved under the old one, and served under
> both (`/tiles/osm-vector/…` and `/tiles/osm/…`). To switch to the new name
> without downloading again, rename the file in `data/tiles/` along with the
> entry in `TILE_SOURCES`.

### Serving your own tile data

To serve data you built yourself — e.g. with
[versatiles-planetiler](https://github.com/versatiles-org/versatiles-docker/tree/main/versatiles-planetiler)
— put the `.versatiles`, `.mbtiles` or `.pmtiles` file into the volume and name
it in `TILE_SOURCES`:

```bash
cp my-region.mbtiles data/tiles/
docker run … -e TILE_SOURCES=my-region.mbtiles …
```

Mixed lists work: `TILE_SOURCES=osm-vector.versatiles,my-region.mbtiles` downloads the
first and serves the second from disk.

The frontends show the tiles served as `osm-vector`. A versatiles-planetiler
result such as `osm-vector.20261101.versatiles` is served under that name; give
other OSM tiles a name starting with `osm-vector.` to show them in the frontends.

> [!IMPORTANT]
> A name with no matching file is treated as a download request — so a typo in a
> local filename makes startup fail with `Download failed for …`. Check it
> against `ls data/tiles/`.
>
> `BBOX` applies only to downloads. Files you supply are served exactly as they
> are, whatever area they cover.

## Admin Commands

```bash
# Container health
docker inspect --format='{{json .State.Health}}' versatiles

# Clear the in‑memory tile cache
docker exec versatiles /scripts/nginx_clear.sh

# Realtime Nginx stats (stub_status)
docker exec versatiles curl -s http://127.0.0.1:8090/_nginx_status

# Startup & runtime logs (Nginx logs are in /data/log)
docker logs -f versatiles
```

## How It Works

1. `entrypoint.sh`
   * downloads the chosen **front‑end** release,
   * downloads any **tile archives** not already present in `/data/tiles/`,
   * ensures a valid **TLS certificate** (launching a minimal Nginx for the ACME challenge if needed),
   * generates an optimised **Nginx** configuration (cache sizes based on RAM).
2. Nginx starts (or reloads) and a background loop renews the certificate.
3. `versatiles serve` — running as the unprivileged `vs` user — answers all requests proxied by Nginx.
