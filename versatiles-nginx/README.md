# Docker Image: versatiles‑nginx

A production‑ready, **zero‑dependency** Docker image that bundles

* a [VersaTiles](https://github.com/versatiles-org/versatiles-rs) tile server (`versatiles serve`)
* an in‑memory **Nginx** reverse‑proxy & tile cache
* an optional static [front‑end](https://github.com/versatiles-org/versatiles-frontend)
* automatic HTTPS certificates via **Let’s Encrypt**

in **one single container**.

---

## Production Example (with HTTPS)

Setup a domain (e.g. `maps.example.com`) and point it to the server. Then run:

**ENSURE YOU SET `DOMAIN` AND `EMAIL` CORRECTLY BEFORE RUNNING THE CONTAINER**
```bash
docker run -d --name versatiles \
  -p 80:80 -p 443:443 \
  -v "$(pwd)/data:/data" \
  -e DOMAIN=maps.example.com \
  -e EMAIL=admin@example.com \
  -e FRONTEND=standard \
  -e TILE_SOURCES=osm.versatiles \
  -e BBOX="9.5,46.3,17.2,49.1" \
  versatiles/versatiles-nginx:latest
```

- The first start obtains a **Let’s Encrypt** certificate for `maps.example.com` via ACME HTTP‑01 (port 80 must be reachable). Renewal checks run automatically in the background.
- It also fetches the latest frontend ("standard") and map data (osm.versatiles, but with BBOX).
- Setting `BBOX` limits the map data download to that geographic window, which speeds up startup and saves disk space.

---

## Environment Variables

| Variable              | Required | Default          | Purpose                                                                                            |
|-----------------------|----------|------------------|----------------------------------------------------------------------------------------------------|
| `DOMAIN`              | **Yes**  | –                | A fully qualified domain name served by Nginx and used for ACME certificate issuance.              |
| `EMAIL`               | **Yes**  | –                | Contact e‑mail passed to Certbot during ACME registration.                                         |
| `FRONTEND`            | **Yes**  | -                | UI bundle to serve: `standard`, `dev`, `min`, or `none`.                                            |
| `TILE_SOURCES`        | **Yes**  | -                | Comma‑separated list of `.versatiles`, `.mbtiles`, or `.pmtiles` that are fetched once at startup. |
| `BBOX`                | No       | –                | Restrict the map download to the bounding box `lng_min,lat_min,lng_max,lat_max`.                   |
| `HTTP_ONLY`           | No       | –                | When set, disables certificate issuance/renewal and serves plain HTTP on port 80 only.             |
| `CACHE_SIZE_KEYS`     | No       | auto (≈20 % RAM) | Nginx `keys_zone` size, e.g. `128m`.                                                               |
| `CACHE_SIZE_MAX`      | No       | auto (≈60 % RAM) | Maximum cached bytes, e.g. `2g`.                                                                   |
| `CERT_MIN_DAYS`       | No       | `30`             | Skip ACME on startup if the current cert is valid for more than this many days.                    |
| `CERT_RENEW_INTERVAL` | No       | `43200` (12 h)   | Interval between background `certbot renew` attempts.                                              |
| `UID` / `GID`         | No       | `10001`          | Numeric uid / gid used for the unprivileged `vs` user.                                             |

---

## Volumes & File‑System Layout

The container needs **one** bind‑mount at */data*:

```
/data
 ├─ certificates/   # Let’s Encrypt config & live certs
 ├─ frontend/       # downloaded UI bundle  (if FRONTEND ≠ "none")
 ├─ log/            # Nginx access & error logs
 ├─ static/         # extra static files (served before standard frontend files)
 └─ tiles/          # *.versatiles / *.mbtiles / *.pmtiles archives
```

Bind it like so:

```bash
-v "$(pwd)/data:/data"
```

---

## Useful Admin Commands

```bash
# Inspect container health
docker inspect --format='{{json .State.Health}}' versatiles

# Clear the in‑memory tile cache
docker exec versatiles /scripts/nginx_clear.sh

# View realtime Nginx stats (stub_status)
docker exec versatiles curl -s http://127.0.0.1:8090/_nginx_status

# Watch startup & runtime logs (nginx logs are under /data/log)
docker logs -f versatiles
```

---

## How It Works (under the hood)

1. `entrypoint.sh`  
   * downloads the chosen **front‑end** release,  
   * downloads / verifies **tile archives**,  
   * generates an optimised **Nginx** configuration (cache sizes based on RAM),  
   * ensures a valid **TLS certificate** (launching a minimal Nginx for the ACME challenge if needed).  
2. The main Nginx process starts (or reloads) and a loop renews the certificate.  
3. `versatiles serve` – running as the unprivileged `vs` user – answers all `/tile/{z}/{x}/{y}` requests.
