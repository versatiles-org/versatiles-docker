#!/usr/bin/env bash
#
# generate_tiles.sh — generate Shortbread vector tiles with Planetiler.
#
# Two modes:
#   • Interactive wizard — when run with no configuration and an attached
#     terminal (e.g. `docker run -it …`). Asks five questions and runs.
#   • Non-interactive    — when configuration is supplied via flags or
#     environment variables. Suitable for scripts, CI and docker-compose.
#
# ──────────────────────────────────────────────────────────────────────────────
# 📘 USAGE
#   generate_tiles [OPTIONS]
#
#   --area <planet|REGION>   What to render: "planet" or a Geofabrik area name
#                            such as "monaco" or "berlin". Planetiler matches the
#                            name against the Geofabrik index and downloads it.
#                            REQUIRED in non-interactive mode.
#   --landcover              Merge land cover data (default: off).
#   --format <FMT>           Output container: versatiles (default), mbtiles or
#                            pmtiles. "versatiles" uses brotli compression.
#   --name <BASENAME>        Output filename (the extension is added
#                            automatically). Default: osm[-landcover].<date>
#                            for the planet, osm[-landcover].<region>.<date>
#                            for a sub-region.
#   -i, --interactive        Force the interactive wizard.
#   -h, --help               Show this help.
#
# 🌱 ENVIRONMENT VARIABLES (flags take precedence)
#   AREA, LANDCOVER=1, FORMAT, OUTPUT_NAME, INTERACTIVE=1   configuration
#   LANDCOVER_URL          land cover container (default: the public VersaTiles one)
#   LANGUAGES              comma-separated name languages
#   EXPERIMENTS            planetiler shortbread_experiments value (default: all)
#   PLANETILER_EXTRA_FLAGS extra flags passed to planetiler
#   JAVA_OPTS              extra JVM options, e.g. -Xmx20g
#
# 📁 DIRECTORY LAYOUT (inside the container) — mount ONE volume at /app/data
#   /app/data           Single working volume (mount a host directory here)
#   /app/data/sources   Downloaded source cache (reused across runs)
#   /app/data/tmp       Planetiler temporary storage
#   /app/data/result    Final output location (<name>.<format>)
#
#   Override the output location with RESULT_DIR if you want it elsewhere.
#
# 🔄 PIPELINE
#   0) (optional) osmium renumber the OSM input so its IDs are dense
#   1) planetiler shortbread-1.1 → intermediate PMTiles
#   2) versatiles convert (optionally merging land cover via VPL) → final container
#
set -euo pipefail

###########################################################################
# ⚙️  Defaults (overridable via environment)
###########################################################################
PLANETILER_JAR="${PLANETILER_JAR:-/opt/planetiler/planetiler.jar}"
# Single working volume holding the source cache, temp files, the intermediate
# tiles and (by default) the results — mount one host directory at $DATA_DIR.
DATA_DIR="${DATA_DIR:-/app/data}"
RESULT_DIR="${RESULT_DIR:-$DATA_DIR/result}"
LANDCOVER_URL="${LANDCOVER_URL:-https://download.versatiles.org/landcover-vectors.versatiles}"
LANGUAGES="${LANGUAGES:-en,fr,es,de,ar,el,it,nl,pl,pt,uk}"
EXPERIMENTS="${EXPERIMENTS:-all}"
PLANETILER_EXTRA_FLAGS="${PLANETILER_EXTRA_FLAGS:---nodemap_type=array --storage=mmap}"
JAVA_OPTS="${JAVA_OPTS:-}"
DATE="$(date +%Y-%m-%d)"

# Configuration (seeded from the environment, overridden by flags / wizard)
AREA="${AREA:-}"
LANDCOVER="${LANDCOVER:-0}"
FORMAT="${FORMAT:-versatiles}"
OUTPUT_NAME="${OUTPUT_NAME:-}"
INTERACTIVE="${INTERACTIVE:-0}"
# JVM heap (-Xmx) value, e.g. "20g". Empty → auto-derived from available memory.
XMX="${XMX:-}"
XMX_AUTO=0

# Renumber OSM IDs with `osmium renumber` before rendering. Dense IDs shrink the
# node map (faster, less I/O) and shorten feature IDs (slightly smaller tiles).
# On by default; set RENUMBER=0 or pass --no-renumber to disable.
RENUMBER="${RENUMBER:-1}"
renumbered=""

# Planet download: when TORRENT=1, fetch the planet .osm.pbf via BitTorrent
# (aria2) and feed it to Planetiler with --osm_path, instead of Planetiler's
# HTTP download. Only applies to AREA=planet.
TORRENT="${TORRENT:-0}"
PLANET_DATE="${PLANET_DATE:-}"
PLANET_PBF_BASE="${PLANET_PBF_BASE:-https://planet.osm.org/pbf}"
PLANET_PBF=""

# Path to the intermediate PMTiles; global so the EXIT trap can clean it up.
intermediate=""

###########################################################################
# 🛠  Helpers
###########################################################################
usage() {
    cat <<'EOF'
generate_tiles — generate Shortbread vector tiles with Planetiler

USAGE
  generate_tiles [OPTIONS]

  Run with no options and an attached terminal (docker run -it) to use the
  interactive wizard. Provide options or environment variables for
  non-interactive use.

OPTIONS
  --area <planet|REGION>   What to render: "planet" or a Geofabrik area name
                           such as "monaco" or "berlin" (matched against the
                           Geofabrik index). REQUIRED in non-interactive mode.
  --landcover              Merge land cover data (default: off).
  --format <FMT>           Output container: versatiles (default), mbtiles or
                           pmtiles. "versatiles" uses brotli compression.
  --name <BASENAME>        Output filename without extension. Default:
                           osm[-landcover].<date>, or
                           osm[-landcover].<region>.<date> for a sub-region.
  --xmx <SIZE>             JVM heap for Planetiler, e.g. 20g. Default: derived
                           from the memory available to the container.
  --torrent                For --area planet: download the planet .osm.pbf via
                           BitTorrent (aria2) and feed it to Planetiler. Faster
                           and more reliable than the default HTTP download.
  --no-renumber            Skip the osmium renumber step (it is on by default;
                           dense IDs render faster and yield slightly smaller tiles).
  -i, --interactive        Force the interactive wizard.
  -h, --help               Show this help.

ENVIRONMENT (flags take precedence)
  AREA, LANDCOVER=1, FORMAT, OUTPUT_NAME, INTERACTIVE=1   configuration
  XMX, JAVA_OPTS                                          JVM heap / JVM options
  RENUMBER=0                                              disable osmium renumber (on by default)
  TORRENT=1, PLANET_DATE=YYMMDD, PLANET_PBF_BASE          planet download
  LANDCOVER_URL, LANGUAGES, EXPERIMENTS,
  PLANETILER_EXTRA_FLAGS                                  tuning
EOF
}

print_usage_hint() {
    echo "No configuration provided and no interactive terminal detected." >&2
    echo "Provide --area <planet|REGION> (see --help), or use 'docker run -it' for the interactive wizard." >&2
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command '$1' not found." >&2
        exit 1
    }
}

# Memory (in bytes) available to this container: the cgroup limit if one is set,
# otherwise total system memory.
detect_mem_bytes() {
    local limit=""
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        limit="$(cat /sys/fs/cgroup/memory.max)" # cgroup v2
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        limit="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)" # cgroup v1
    fi
    # "max" (v2) or a sentinel near 2^63 (v1) means "no limit" → use host total.
    if [[ "$limit" == "max" ]] || [[ ! "$limit" =~ ^[0-9]+$ ]] || ((limit > 9000000000000000000)); then
        local kb
        kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        limit=$((kb * 1024))
    fi
    printf '%s' "$limit"
}

# Bytes → "12.3" (GiB, one decimal).
human_gb() {
    awk -v b="$1" 'BEGIN { printf "%.1f", b / 1073741824 }'
}

# Default -Xmx when the user didn't specify one. Planetiler keeps node locations
# off-heap in memory-mapped files (the default --storage=mmap), so a modest heap
# is enough and the rest of RAM should stay free for the OS page cache. Use ~40%
# of available memory, clamped to [2g, 32g]. For --storage=ram on a big machine,
# raise it explicitly via --xmx / JAVA_OPTS.
default_xmx() {
    local gb
    gb=$(awk -v b="$1" 'BEGIN { g = int(b / 1073741824 * 0.4); if (g < 2) g = 2; if (g > 32) g = 32; printf "%d", g }')
    printf '%dg' "$gb"
}

# Resolve the JVM heap into JAVA_OPTS. An explicit -Xmx in JAVA_OPTS wins; then
# XMX (flag/env); otherwise an auto value derived from available memory.
resolve_java_opts() {
    if [[ "$JAVA_OPTS" == *-Xmx* ]]; then
        if [[ -n "$XMX" ]]; then
            echo "⚠️  Both JAVA_OPTS (-Xmx) and --xmx/XMX are set; JAVA_OPTS takes precedence." >&2
        fi
        return
    fi
    local xmx="$XMX"
    if [[ -z "$xmx" ]]; then
        xmx="$(default_xmx "$MEM_BYTES")"
        XMX_AUTO=1
    fi
    JAVA_OPTS="-Xmx${xmx}${JAVA_OPTS:+ $JAVA_OPTS}"
}

# Download the planet .osm.pbf via BitTorrent into $DATA_DIR/sources and set the
# global PLANET_PBF to its path. Mirrors shortbread-compare-demo's 02-generate.sh.
download_planet_torrent() {
    require_cmd aria2c
    require_cmd curl

    local sources_dir="$DATA_DIR/sources"
    mkdir -p "$sources_dir"

    local date="$PLANET_DATE"
    if [[ -z "$date" ]]; then
        echo "🔎  Resolving latest planet snapshot from ${PLANET_PBF_BASE}/ …"
        date="$(curl -fsSL "${PLANET_PBF_BASE}/" |
            grep -oE 'planet-[0-9]{6}\.osm\.pbf' |
            grep -oE '[0-9]{6}' | sort | tail -n1 || true)"
    fi
    [[ -n "$date" ]] || {
        echo "Error: could not determine the latest planet date; set PLANET_DATE=YYMMDD." >&2
        exit 1
    }

    PLANET_PBF="$sources_dir/planet-${date}.osm.pbf"
    if [[ -f "$PLANET_PBF" && ! -f "${PLANET_PBF}.aria2" ]]; then
        echo "♻️  Reusing existing $PLANET_PBF (delete it to force a fresh download)."
        return
    fi

    echo "📥  Downloading planet-${date}.osm.pbf via BitTorrent (aria2c) …"
    local torrent="$sources_dir/planet-${date}.osm.pbf.torrent"
    curl -fsSL "${PLANET_PBF_BASE}/planet-${date}.osm.pbf.torrent" -o "$torrent"
    # --seed-time=0 stops seeding once complete; --continue + the .aria2 control
    # file make the multi-hour download resumable; falloc preallocates quickly.
    aria2c --dir="$sources_dir" --seed-time=0 --continue=true \
        --file-allocation=falloc --summary-interval=30 "$torrent"
}

# ask <prompt> <default> → echoes the user's answer, or the default on empty/EOF.
ask() {
    local prompt="$1" default="$2" answer
    printf '%s' "$prompt" >&2
    read -r answer || answer=""
    [[ -z "$answer" ]] && answer="$default"
    printf '%s' "$answer"
}

# Turn an area name into a filesystem-safe slug, e.g. "us georgia" → "us-georgia".
region_slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' |
        sed -E 's/-+/-/g; s/^-//; s/-$//'
}

# Base filename (without extension) used as the default output name:
#   planet → osm[-landcover].<date>
#   region → osm[-landcover].<region>.<date>
default_output_name() {
    local base="osm"
    [[ "$LANDCOVER" == "1" ]] && base="osm-landcover"
    if [[ "$AREA" == "planet" || -z "$AREA" ]]; then
        printf '%s.%s' "$base" "$DATE"
    else
        printf '%s.%s.%s' "$base" "$(region_slug "$AREA")" "$DATE"
    fi
}

# Append the format extension unless the name already carries one.
output_filename() {
    local name="$1"
    case "$name" in
    *.versatiles | *.mbtiles | *.pmtiles) printf '%s' "$name" ;;
    *) printf '%s.%s' "$name" "$FORMAT" ;;
    esac
}

###########################################################################
# 🏷️  Argument parsing
###########################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --area) AREA="${2:-}"; shift 2 ;;
        --area=*) AREA="${1#*=}"; shift ;;
        --landcover) LANDCOVER=1; shift ;;
        --format) FORMAT="${2:-}"; shift 2 ;;
        --format=*) FORMAT="${1#*=}"; shift ;;
        --name) OUTPUT_NAME="${2:-}"; shift 2 ;;
        --name=*) OUTPUT_NAME="${1#*=}"; shift ;;
        --xmx) XMX="${2:-}"; shift 2 ;;
        --xmx=*) XMX="${1#*=}"; shift ;;
        --torrent) TORRENT=1; shift ;;
        --no-renumber) RENUMBER=0; shift ;;
        -i | --interactive) INTERACTIVE=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        esac
    done
}

###########################################################################
# 🧙  Interactive wizard
###########################################################################
run_wizard() {
    echo "VersaTiles Planetiler — interactive setup" >&2
    echo >&2

    # 1) Whole planet or a sub-region?
    local scope
    scope="$(ask "Render the whole [p]lanet or a [s]ub-region? [p/s] (default: s): " "s")"
    if [[ "$scope" == [pP]* ]]; then
        AREA="planet"
        echo "  ⚠  The whole planet needs a large machine: ~64 GB+ RAM and ~400 GB+ free disk." >&2
        echo "     This container currently sees ${MEM_HUMAN} GB of RAM." >&2
        local cont
        cont="$(ask "  Continue with the planet? [y/N]: " "n")"
        [[ "$cont" == [yY]* ]] || { echo "  Aborted." >&2; exit 1; }
        local tor
        tor="$(ask "  Download the planet via BitTorrent (faster, needs aria2)? [Y/n]: " "y")"
        if [[ "$tor" == [nN]* ]]; then TORRENT=0; else TORRENT=1; fi
    else
        echo "  Enter a Geofabrik area name (e.g. monaco, berlin, massachusetts)." >&2
        echo "  Use the region's own name — not a path like 'germany/berlin'." >&2
        echo "  For an ambiguous name add a qualifier (e.g. 'us georgia')." >&2
        echo "  Browse available regions at https://download.geofabrik.de/" >&2
        AREA=""
        local tries=0
        while [[ -z "$AREA" ]]; do
            AREA="$(ask "  Region: " "")"
            [[ -n "$AREA" ]] && break
            tries=$((tries + 1))
            if ((tries >= 3)); then
                echo "  No region given. Aborting." >&2
                exit 1
            fi
            echo "  A region is required." >&2
        done
    fi

    # 2) Inject land cover?
    local lc
    lc="$(ask "Inject land cover data? [y/N]: " "n")"
    if [[ "$lc" == [yY]* ]]; then LANDCOVER=1; else LANDCOVER=0; fi

    # 3) Container format?
    local fmt
    fmt="$(ask "Container format — [v]ersatiles, [m]btiles, [p]mtiles? (default: v): " "v")"
    case "$fmt" in
    [mM]*) FORMAT="mbtiles" ;;
    [pP]*) FORMAT="pmtiles" ;;
    *) FORMAT="versatiles" ;;
    esac

    # 4) Output filename
    local default_name
    default_name="$(default_output_name)"
    OUTPUT_NAME="$(ask "Output filename (default: ${default_name}.${FORMAT}): " "$default_name")"

    # 5) JVM heap (-Xmx). Empty keeps the auto value derived from available memory.
    if [[ -z "$XMX" ]]; then
        local heap_in
        heap_in="$(ask "JVM heap -Xmx (default: auto $(default_xmx "$MEM_BYTES")): " "")"
        [[ -n "$heap_in" ]] && XMX="$heap_in"
    fi

    echo >&2
}

###########################################################################
# ✅  Validate the resolved configuration
###########################################################################
finalize_config() {
    if [[ -z "$AREA" ]]; then
        echo "Error: --area is required (planet or a Geofabrik area name, e.g. monaco)." >&2
        usage >&2
        exit 1
    fi
    case "$FORMAT" in
    versatiles | mbtiles | pmtiles) ;;
    *)
        echo "Error: invalid --format '$FORMAT' (expected versatiles, mbtiles or pmtiles)." >&2
        exit 1
        ;;
    esac
    if [[ -z "$OUTPUT_NAME" ]]; then
        OUTPUT_NAME="$(default_output_name)"
    fi
}

###########################################################################
# 🚀  Pipeline
###########################################################################
run_pipeline() {
    require_cmd java
    require_cmd versatiles

    mkdir -p "$DATA_DIR" "$RESULT_DIR"

    intermediate="$DATA_DIR/planetiler.pmtiles"
    local out_file
    out_file="$RESULT_DIR/$(output_filename "$OUTPUT_NAME")"

    # Remove the intermediate PMTiles and any renumbered pbf on exit.
    trap 'rm -f "${intermediate:-}" "${renumbered:-}"' EXIT

    echo "GENERATE SHORTBREAD VECTOR TILES:"
    echo "   AREA:      $AREA"
    if [[ "$LANDCOVER" == "1" ]]; then
        echo "   LANDCOVER: yes ($LANDCOVER_URL)"
    else
        echo "   LANDCOVER: no"
    fi
    echo "   FORMAT:    $FORMAT"
    echo "   OUTPUT:    $out_file"
    echo "   RENUMBER:  $([[ "$RENUMBER" != "0" ]] && echo "yes (osmium renumber)" || echo "no")"
    if [[ "$AREA" == "planet" ]]; then
        echo "   DOWNLOAD:  $([[ "$TORRENT" == "1" ]] && echo "BitTorrent (aria2)" || echo "HTTP (planetiler --download)")"
    fi
    if [[ "$XMX_AUTO" == "1" ]]; then
        echo "   MEMORY:    ${MEM_HUMAN} GB available, JVM heap ${JAVA_OPTS%% *} (auto)"
    else
        echo "   MEMORY:    ${MEM_HUMAN} GB available, JVM opts: ${JAVA_OPTS}"
    fi

    # Planetiler only *warns* about insufficient resources and we pass --force
    # (so it never blocks on a prompt). Surface the rule of thumb here instead.
    echo "ℹ️  Planetiler keeps most data in memory-mapped files; keep RAM free for the OS"
    echo "    page cache. Rule of thumb: ≥ 0.5× the .osm.pbf size as free RAM (the whole"
    echo "    planet ≈ 70 GB pbf → 64 GB+ RAM). Tune with --xmx / JAVA_OPTS, or switch to"
    echo "    in-memory storage via PLANETILER_EXTRA_FLAGS=\"--storage=ram --nodemap_type=array\"."

    ###########################################################################
    # 1) Render with Planetiler → intermediate PMTiles
    #
    # PMTiles is a flat, sequentially-laid-out file, so the `versatiles convert`
    # read below avoids the random-access SQLite overhead of MBTiles.
    ###########################################################################
    # Source pbf handling. osm_path_args feeds Planetiler a specific .osm.pbf via
    # --osm_path (instead of letting it download OSM); empty → Planetiler downloads.
    local osm_path_args=()
    local src_pbf=""

    # For a torrent planet build, pre-fetch the pbf via BitTorrent.
    if [[ "$TORRENT" == "1" ]]; then
        if [[ "$AREA" == "planet" ]]; then
            download_planet_torrent
            src_pbf="$PLANET_PBF"
        else
            echo "⚠️  --torrent only applies to the planet; ignoring for area '$AREA'." >&2
        fi
    fi

    # Renumber OSM IDs so they are dense (faster, slightly smaller tiles).
    if [[ "$RENUMBER" != "0" ]]; then
        require_cmd osmium

        # Renumber needs the pbf on disk. If we don't already have one (non-torrent),
        # let Planetiler download all sources first, then locate the OSM file.
        if [[ -z "$src_pbf" ]]; then
            echo "📥  Downloading sources…"
            # shellcheck disable=SC2086
            time java $JAVA_OPTS -jar "$PLANETILER_JAR" shortbread-1.1 \
                --area="$AREA" --download --only_download $PLANETILER_EXTRA_FLAGS
            # `|| true` guards against a SIGPIPE non-zero status (head closes the
            # pipe early) tripping `set -o pipefail` / `set -e`.
            src_pbf="$(find "$DATA_DIR/sources" -maxdepth 3 -name '*.osm.pbf' \
                ! -name 'renumbered.osm.pbf' | head -n1 || true)"
        fi
        [[ -n "$src_pbf" ]] || {
            echo "Error: could not locate the downloaded .osm.pbf to renumber." >&2
            exit 1
        }

        echo "🔢  Renumbering OSM IDs (osmium renumber)…"
        renumbered="$DATA_DIR/sources/renumbered.osm.pbf"
        time osmium renumber --progress --overwrite -o "$renumbered" "$src_pbf"
        osm_path_args=(--osm_path="$renumbered")
    elif [[ -n "$src_pbf" ]]; then
        osm_path_args=(--osm_path="$src_pbf")
    fi

    echo "🧱  Rendering tiles with Planetiler…"
    # shellcheck disable=SC2086
    time java $JAVA_OPTS -jar "$PLANETILER_JAR" shortbread-1.1 \
        --area="$AREA" \
        --download \
        --force \
        --name_languages="$LANGUAGES" \
        --shortbread_experiments="$EXPERIMENTS" \
        --output="$intermediate" \
        "${osm_path_args[@]}" \
        $PLANETILER_EXTRA_FLAGS

    ###########################################################################
    # 2) Convert / merge → final container
    #
    # When land cover is requested, the VPL `from_merged_vector` operation folds
    # the remote land cover container's features into the Shortbread layers. The
    # land cover container is range-read from its URL — nothing is downloaded.
    ###########################################################################
    local compression_args=()
    [[ "$FORMAT" == "versatiles" ]] && compression_args=(-c brotli)

    if [[ "$LANDCOVER" == "1" ]]; then
        echo "🌍  Merging land cover and converting to ${FORMAT}…"
        time versatiles convert "${compression_args[@]}" \
            "[,vpl](from_merged_vector [ from_container filename=\"$intermediate\", from_container filename=\"$LANDCOVER_URL\" ])" \
            "$out_file"
    else
        echo "🚀  Converting to ${FORMAT}…"
        time versatiles convert "${compression_args[@]}" \
            "$intermediate" \
            "$out_file"
    fi

    echo "✅  Done: $out_file"
}

###########################################################################
# 🎬  Main
###########################################################################
MEM_BYTES="$(detect_mem_bytes)"
MEM_HUMAN="$(human_gb "$MEM_BYTES")"

ARGC=$#
parse_args "$@"

if [[ "$INTERACTIVE" == "1" ]]; then
    run_wizard
elif [[ $ARGC -eq 0 && -z "$AREA" ]]; then
    if [[ -t 0 ]]; then
        run_wizard
    else
        print_usage_hint
        exit 1
    fi
fi

finalize_config
resolve_java_opts
run_pipeline
