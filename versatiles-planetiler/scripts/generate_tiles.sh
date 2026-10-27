#!/usr/bin/env bash
#
# generate_tiles.sh — generate Shortbread vector tiles with Planetiler.
#
# Two modes:
#   • Interactive wizard — when run with no configuration and an attached
#     terminal (e.g. `docker run -it …`). Asks a few questions and runs.
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
#   --landcover              Also write a second output with land cover merged
#                            in (default: off).
#   --format <FMT>           Output container: versatiles (default), mbtiles or
#                            pmtiles. "versatiles" uses brotli compression.
#   --name <BASENAME>        Output filename (the extension is added
#                            automatically). Default: osm.<date> for the planet,
#                            osm.<region>.<date> for a sub-region. The land cover
#                            output is osm-landcover.… by default, or
#                            <BASENAME>-landcover for a custom name.
#   --mode <disk|memory>     Planetiler's temporary data in memory-mapped files
#                            (default) or on the Java heap (faster, more RAM).
#   -i, --interactive        Force the interactive wizard.
#   -h, --help               Show this help.
#
# 🌱 ENVIRONMENT VARIABLES (flags take precedence)
#   AREA, LANDCOVER=1, FORMAT, OUTPUT_NAME, INTERACTIVE=1   configuration
#   LANDCOVER_URL          land cover container (default: the public VersaTiles one)
#   OCEAN_URL              water polygons zip (default: osmdata.openstreetmap.de)
#   OCEAN_MIRROR           fallback with dated folders (default: the FAU mirror)
#   LANGUAGES              name languages: "extended" (default, 81 languages) or comma-separated codes
#   EXPERIMENTS            planetiler shortbread_experiments value (default: all)
#   PLANETILER_EXTRA_FLAGS extra flags passed to planetiler
#   MODE                   disk (default) or memory, see --mode
#   XMX, JAVA_OPTS         Java heap override / extra JVM options
#
# 📁 DIRECTORY LAYOUT (inside the container) — mount ONE volume at /app/data
#   /app/data           Single working volume (mount a host directory here)
#   /app/data/sources   Downloaded source cache (reused across runs)
#   /app/data/tmp       Planetiler temporary storage
#   /app/data/logs      Complete output of each run (<name>.log)
#   /app/data/result    Final output location (<name>.<format>; with land
#                       cover, a second file with the land cover merged in)
#
#   Override the output location with RESULT_DIR if you want it elsewhere.
#
# 🔄 PIPELINE
#   0) (optional, --renumber) osmium renumber the OSM input so its IDs are dense
#   1) planetiler shortbread-1.1 → intermediate PMTiles
#   2) versatiles convert → final container; with land cover, a second
#      container with the land cover merged in via VPL
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
LANGUAGES="${LANGUAGES:-extended}"
EXPERIMENTS="${EXPERIMENTS:-all}"
PLANETILER_EXTRA_FLAGS="${PLANETILER_EXTRA_FLAGS:-}"
JAVA_OPTS="${JAVA_OPTS:-}"
DATE="$(date +%Y-%m-%d)"

# Configuration (seeded from the environment, overridden by flags / wizard)
AREA="${AREA:-}"
LANDCOVER="${LANDCOVER:-0}"
FORMAT="${FORMAT:-versatiles}"
OUTPUT_NAME="${OUTPUT_NAME:-}"
INTERACTIVE="${INTERACTIVE:-0}"
# Processing mode: "disk" keeps Planetiler's temporary data in memory-mapped
# files, "memory" keeps it on the Java heap (see "Memory planning" below).
MODE="${MODE:-disk}"
# JVM heap (-Xmx) value, e.g. "20g". Empty → derived from MODE and the .osm.pbf.
XMX="${XMX:-}"
# Set once check_memory has run with the planet's size, before any download.
MEMORY_CHECKED=0

# Renumber OSM IDs with `osmium renumber` before rendering. Dense IDs shrink the
# node map (faster, less I/O) and shorten feature IDs (2-4% smaller tiles), but
# the tiles' feature IDs are then no longer OSM IDs, and they change from build
# to build. Off by default; set RENUMBER=1 or pass --renumber to enable.
RENUMBER="${RENUMBER:-0}"
RENUMBER_SKIPPED="" # why check_memory turned renumbering off, if it did
renumbered=""

# Write .md5 and .sha256 checksum files next to the output. Off by default;
# set CHECKSUM=1 or pass --checksum to enable.
CHECKSUM="${CHECKSUM:-0}"

# Planet download: when TORRENT=1, fetch the planet .osm.pbf via BitTorrent
# (aria2) and feed it to Planetiler with --osm_path, instead of Planetiler's
# HTTP download. Only applies to AREA=planet.
TORRENT="${TORRENT:-0}"
PLANET_DATE="${PLANET_DATE:-}"
PLANET_PBF_BASE="${PLANET_PBF_BASE:-https://planet.osm.org/pbf}"
PLANET_PBF=""

# OSM water polygons (Planetiler's `ocean` source), fetched by the script before
# Planetiler runs, with a weekly refresh and a mirror fallback (see
# fetch_water_polygons). OCEAN_MIRROR holds dated folders of the same file.
OCEAN_URL="${OCEAN_URL:-https://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip}"
OCEAN_MIRROR="${OCEAN_MIRROR:-https://ftp.fau.de/mirrors/openstreetmapdata.com-archive}"
OCEAN_PATH="$DATA_DIR/sources/water-polygons-split-3857.zip"
# Natural Earth country polygons, for the locale_names experiment.
COUNTRIES_PATH="$DATA_DIR/sources/ne_10m_admin_0_countries.zip"

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
  --landcover              Also write a second output with land cover merged
                           in (default: off).
  --format <FMT>           Output container: versatiles (default), mbtiles or
                           pmtiles. "versatiles" uses brotli compression.
  --name <BASENAME>        Output filename without extension. Default:
                           osm.<date>, or osm.<region>.<date> for a sub-region.
                           The land cover output is osm-landcover.… by default,
                           or <BASENAME>-landcover for a custom name.
  --mode <disk|memory>     How Planetiler keeps its temporary data: "disk"
                           (default) in memory-mapped files, ~0.5× the .osm.pbf
                           size + 3 GB of RAM; "memory" on the Java heap, faster,
                           ~1.7× + 3 GB. The run stops if the RAM is too small.
  --xmx <SIZE>             Override the Java heap that --mode derives, e.g. 20g.
  --torrent                For --area planet: download the planet .osm.pbf via
                           BitTorrent (aria2) and feed it to Planetiler. Faster
                           and more reliable than the default HTTP download.
  --renumber               Renumber the OSM IDs with osmium first: renders a
                           bit faster and makes the tiles 2-4% smaller, but their
                           feature IDs are no longer OSM IDs. Off by default.
  --checksum               Write <output>.md5 and <output>.sha256 next to each output.
  -i, --interactive        Force the interactive wizard.
  -h, --help               Show this help.

ENVIRONMENT (flags take precedence)
  AREA, LANDCOVER=1, FORMAT, OUTPUT_NAME, CHECKSUM=1, INTERACTIVE=1   configuration
  MODE, XMX, JAVA_OPTS                                    memory mode / JVM heap / JVM options
  RENUMBER=1                                              renumber the OSM IDs (off by default)
  TORRENT=1, PLANET_DATE=YYMMDD, PLANET_PBF_BASE          planet download
  OCEAN_URL, OCEAN_MIRROR                                 water polygons download
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

# Write <file>.md5 and <file>.sha256 next to the output. The checksum files use
# the bare filename (run from the file's directory) so they verify in place.
write_checksums() {
    local file="$1" dir base
    dir="$(dirname "$file")"
    base="$(basename "$file")"
    require_cmd md5sum
    require_cmd sha256sum
    (
        cd "$dir"
        md5sum "$base" >"$base.md5"
        sha256sum "$base" >"$base.sha256"
    )
    log "Wrote $base.md5 and $base.sha256"
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

###########################################################################
# 📊  Console output: numbered steps, progress bars and a log file
###########################################################################
# The console shows one line per step, "[n/N] label", which a progress bar
# keeps redrawing on a terminal and which ends with "✓ <duration>". All the
# tools print goes to LOG_FILE instead: progress_filter copies it there and
# turns their progress output into the bar on the way. Without a terminal
# (docker logs, CI), a status line is printed at most once a minute instead.
LOG_FILE=/dev/null
STEP_N=0
STEP_TOTAL=0
STEP_LABEL=""
STEP_START=0
STEP_OPEN=0 # 1 while a step's line is on the console without a line break
IS_TTY=0
[[ -t 1 ]] && IS_TTY=1
# Estimated node count of the .osm.pbf, for the progress of Planetiler's first
# pass, which reports no percentage.
NODES_EST=1

# duration <seconds> → "45s", "12m03s" or "2h05m".
duration() {
    local s="$1"
    if ((s < 60)); then
        printf '%ds' "$s"
    elif ((s < 3600)); then
        printf '%dm%02ds' $((s / 60)) $((s % 60))
    else
        printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
    fi
}

# log <message> → appends a line to the log file.
log() {
    printf '%s\n' "$*" >>"$LOG_FILE"
}

# The current step's "[n/N] label", padded so that the bars line up.
step_prefix() {
    printf '[%d/%d] %-25s' "$STEP_N" "$STEP_TOTAL" "$STEP_LABEL"
}

# step_begin <label> → starts the next step.
step_begin() {
    STEP_N=$((STEP_N + 1))
    STEP_LABEL="$1"
    STEP_START=$EPOCHSECONDS
    log ""
    log "=== [$STEP_N/$STEP_TOTAL] $STEP_LABEL ($(date '+%F %T'))"
    if ((IS_TTY)); then
        printf '%s' "$(step_prefix)"
        STEP_OPEN=1
    else
        printf '[%d/%d] %s …\n' "$STEP_N" "$STEP_TOTAL" "$STEP_LABEL"
    fi
}

# step_end [detail] → finishes the current step with its duration.
step_end() {
    local took
    took="$(duration $((EPOCHSECONDS - STEP_START)))"
    log "--- done in $took"
    if ((IS_TTY)); then
        printf '\r\033[K%s ✓ %s%s\n' "$(step_prefix)" "$took" "${1:+ · $1}"
    else
        printf '[%d/%d] %s ✓ %s%s\n' "$STEP_N" "$STEP_TOTAL" "$STEP_LABEL" "$took" "${1:+ · $1}"
    fi
    STEP_OPEN=0
}

# step_skip <label> <reason> → counts a step that does not run.
step_skip() {
    STEP_N=$((STEP_N + 1))
    STEP_LABEL="$1"
    log ""
    log "=== [$STEP_N/$STEP_TOTAL] $STEP_LABEL: skipped, $2"
    printf '%s – skipped: %s\n' "$(step_prefix)" "$2"
}

# step_failed → reports the failed step with the end of the log, and exits.
step_failed() {
    local took
    took="$(duration $((EPOCHSECONDS - STEP_START)))"
    ((STEP_OPEN)) && printf '\r\033[K'
    printf '[%d/%d] %s ✗ failed after %s\n' "$STEP_N" "$STEP_TOTAL" "$STEP_LABEL" "$took" >&2
    STEP_OPEN=0
    echo "Last lines of the log $LOG_FILE:" >&2
    tail -n 20 "$LOG_FILE" | sed 's/^/  /' >&2
    exit 1
}

# note <message> → prints a message on its own line (above the current step's
# line, which is then redrawn) and logs it.
note() {
    log "$*"
    if ((STEP_OPEN)); then
        printf '\r\033[K      %s\n%s' "$*" "$(step_prefix)"
    else
        printf '      %s\n' "$*"
    fi
}

# fail <line>… → ends the current step's line, prints the error and exits.
fail() {
    ((STEP_OPEN)) && printf '\n'
    STEP_OPEN=0
    local line
    for line in "$@"; do
        printf '%s\n' "$line" >&2
        log "$line"
    done
    exit 1
}

# run_logged <mode[:detail]> <command>… → runs the command with its output
# going through progress_filter into the log; returns the command's status.
run_logged() {
    local mode="$1"
    shift
    log "\$ $*"
    "$@" 2>&1 | progress_filter "$mode" 3>>"$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# progress_filter <mode[:detail]> → copies a tool's output to fd 3 (the log)
# and draws the current step's progress bar from it. Carriage returns become
# line breaks and terminal escape codes are dropped. Modes:
#   generic     the last "NN%" in a line: curl -#, aria2c, osmium, versatiles.
#               Their progress lines reach the log at most every 30 seconds.
#   planetiler  Planetiler's progress lines. A render runs through several
#               stages, so each one gets a share of the bar, measured from
#               Planetiler's own planet run (PLANET.md): reading OSM 8%,
#               processing OSM 45%, sorting 4%, writing tiles 42%, ocean 1%.
#               The first pass reports no percentage, so its progress is the
#               node count against NODES_EST. Warnings and errors are shown
#               on the console, except Planetiler's memory-mapped files
#               warning: it assumes 9.5 billion node IDs for every file, and
#               check_memory checks the RAM instead.
progress_filter() {
    local mode="${1%%:*}" detail=""
    [[ "$1" == *:* ]] && detail="${1#*:}"
    local t0=$EPOCHSECONDS line pct=-1 shown=-1 drawn_at=0 printed_at=$EPOCHSECONDS logged_at=0
    local stage="" base=0 share=100 spct=0 n warn=0
    local -A shares=([ne_10m_admin_0_countries]=0 [osm_pass1]=8 [osm_pass2]=45 [ocean]=1 [sort]=4 [archive]=42)
    local -A starts=([ne_10m_admin_0_countries]=0 [osm_pass1]=0 [osm_pass2]=8 [ocean]=53 [sort]=54 [archive]=58)
    local -A names=([ne_10m_admin_0_countries]="country polygons" [osm_pass1]="reading OSM"
        [osm_pass2]="processing OSM" [ocean]="ocean" [sort]="sorting" [archive]="writing tiles"
        [download]="downloading")
    local re_line='^[0-9:]+ (INF|DEB|WAR|ERR)( \[([a-z0-9_]+)(:[^]]*)?\])? - (.*)$'
    local re_count='([0-9.]+)([kMBT]?)'
    stdbuf -oL tr '\r' '\n' |
        sed -u -E 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)?//g' |
        while IFS= read -r line; do
            if [[ "$mode" == planetiler || "$line" != *%* ]] || ((EPOCHSECONDS - logged_at >= 30)); then
                printf '%s\n' "$line" >&3
                [[ "$line" == *%* ]] && logged_at=$EPOCHSECONDS
            fi

            if [[ "$mode" == generic ]]; then
                [[ "$line" =~ ([0-9]+)(\.[0-9]+)?%[^%]*$ ]] && pct=$((10#${BASH_REMATCH[1]}))
            elif [[ "$line" =~ $re_line ]]; then
                local level="${BASH_REMATCH[1]}" st="${BASH_REMATCH[3]}" msg="${BASH_REMATCH[5]}"
                warn=0
                if [[ "$level" == WAR || "$level" == ERR ]]; then
                    if [[ "$msg" == *"memory-mapped files for node locations"* ]]; then
                        warn=2
                    else
                        warn=1
                        printf '\r\033[K      ⚠️  %s\n' "$msg"
                        shown=-2
                    fi
                fi
                if [[ -n "$st" && "$st" != "$stage" ]]; then
                    stage="$st"
                    base="${starts[$st]:-0}"
                    share="${shares[$st]:-100}"
                    detail="${names[$st]:-$st}"
                    spct=0
                fi
                if [[ -n "$st" ]]; then
                    if [[ "$msg" == "Finished in"* ]]; then
                        spct=100
                    elif [[ "$st" == osm_pass1 && "$msg" =~ nodes:\ \[\ *$re_count ]]; then
                        n="$(awk -v v="${BASH_REMATCH[1]}" -v u="${BASH_REMATCH[2]}" -v e="$NODES_EST" 'BEGIN {
                            m = (u == "k") ? 1e3 : (u == "M") ? 1e6 : (u == "B") ? 1e9 : (u == "T") ? 1e12 : 1
                            p = int(v * m / e * 100); print (p > 99) ? 99 : p }')"
                        spct="$n"
                    elif [[ "$st" == osm_pass2 && "$msg" =~ blocks:\ \[\ *[0-9.]+[kMBT]?\ +([0-9]+)% ]] ||
                        [[ "$st" == archive && "$msg" =~ features:\ \[\ *[0-9.]+[kMBT]?\ +([0-9]+)% ]] ||
                        [[ "$st" == sort && "$msg" =~ chunks:\ \[\ *[0-9]+\ /\ *[0-9]+\ +([0-9]+)% ]] ||
                        [[ "$st" != osm_pass2 && "$st" != archive && "$st" != sort &&
                        "$msg" =~ [a-z_]+:\ \[\ *[0-9.]+[kMBT]?\ +([0-9]+)% ]]; then
                        spct=$((10#${BASH_REMATCH[1]}))
                    fi
                    pct=$((base + share * spct / 100))
                fi
            elif ((warn == 1)) && [[ -n "$line" && "$line" != WARNING:* ]]; then
                printf '\r\033[K      %s\n' "$line"
                shown=-2
            fi

            ((pct < 0)) && continue
            if ((IS_TTY)); then
                ((pct == shown && EPOCHSECONDS == drawn_at)) && continue
                draw_progress "$pct" "$detail" $((EPOCHSECONDS - t0))
                shown=$pct
                drawn_at=$EPOCHSECONDS
            elif ((EPOCHSECONDS - printed_at >= 60)); then
                printf '[%d/%d] %s: %d%%%s\n' "$STEP_N" "$STEP_TOTAL" "$STEP_LABEL" "$pct" "${detail:+ · $detail}"
                printed_at=$EPOCHSECONDS
            fi
        done
}

# draw_progress <percent> <detail> <elapsed seconds> → redraws the current
# step's line as "[n/N] label ▕████▌    ▏ 43% · detail · 1m12s · ~1m35s left".
draw_progress() {
    local pct="$1" detail="$2" elapsed="$3" width=20 bar="" i eighths full part
    local -a partial=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
    ((pct > 100)) && pct=100
    eighths=$((pct * width * 8 / 100))
    full=$((eighths / 8))
    part=$((eighths % 8))
    for ((i = 0; i < full; i++)); do bar+="█"; done
    if ((part > 0)); then
        bar+="${partial[part]}"
        i=$((i + 1))
    fi
    for (( ; i < width; i++)); do bar+=" "; done
    local line
    line="$(step_prefix)▕${bar}▏ $(printf '%3d' "$pct")%${detail:+ · $detail} · $(duration "$elapsed")"
    if ((pct >= 1 && pct < 100 && elapsed >= 10)); then
        line+=" · ~$(duration $((elapsed * (100 - pct) / pct))) left"
    fi
    printf '\r\033[K%s' "$line"
}

###########################################################################
# 🧮  Memory planning
###########################################################################
# Two modes, chosen with --mode / MODE or in the wizard:
#   disk    Planetiler keeps node locations and multipolygon geometries in
#           memory-mapped files (--storage=mmap); free RAM caches them.
#   memory  Planetiler keeps them on the Java heap (--storage=ram): faster,
#           but needs about three times as much RAM.
# The estimates scale with the size of the .osm.pbf, like Planetiler's own
# checks (PLANET.md, Planetiler.checkMemory):
#   disk    heap 0.3× pbf + 2 GB (the Shortbread profile's estimate), plus
#           0.2× pbf as page cache and 1 GB for the JVM     → 0.5× pbf + 3 GB
#   memory  heap 1.7× pbf + 2 GB (node locations, multipolygon geometries and
#           the profile come to ~1.5× pbf; PLANET.md gives a 67 GB planet a
#           110 GB heap), plus 1 GB for the JVM             → 1.7× pbf + 3 GB
#   osmium renumber: keeps the old node IDs (8 bytes each) in a std::vector
#           that doubles its capacity when full, so its last doubling asks
#           for 8 bytes × the next power of two above the node count, while
#           the old half is still in use. The node count is estimated with
#           Planetiler's ratio (7.5 billion nodes in a 66.7 GB planet).
#                                                           → 8 × 2^⌈log2 nodes⌉ + 2 GB
# For the 89 GB planet of October 2026 (binary GB, ~10.7 billion nodes): disk
# ~48 GB, memory ~154 GB, renumber ~130 GB.
GIB=1073741824

# to_bytes <size> → bytes, for a JVM-style size such as "20g", "512m" or "1t".
to_bytes() {
    awk -v s="$1" 'BEGIN {
        n = s + 0; u = tolower(substr(s, length(s)))
        if (u == "k") n *= 1024; else if (u == "m") n *= 1024 ^ 2
        else if (u == "g") n *= 1024 ^ 3; else if (u == "t") n *= 1024 ^ 4
        printf "%.0f", n }'
}

# mib <bytes> → whole MiB, rounded up (for -Xmx).
mib() {
    awk -v b="$1" 'BEGIN { m = b / 1048576; printf "%d", (m == int(m)) ? m : int(m) + 1 }'
}

# human_size <bytes> → "652 MB" below 1 GB, else "88.9 GB" (binary units).
human_size() {
    awk -v b="$1" 'BEGIN { if (b < 1073741824) printf "%.1f MB", b / 1048576; else printf "%.1f GB", b / 1073741824 }'
}

# The heap the user set, in bytes: -Xmx in JAVA_OPTS, else --xmx/XMX, else empty.
heap_override_bytes() {
    local xmx
    xmx="$(grep -oE -- '-Xmx[0-9]+[kKmMgGtT]?' <<<"$JAVA_OPTS" | tail -n1 || true)"
    xmx="${xmx#-Xmx}"
    [[ -z "$xmx" ]] && xmx="$XMX"
    [[ -n "$xmx" ]] && to_bytes "$xmx"
    return 0
}

# plan_memory <pbf bytes> <mode> → sets HEAP_BYTES (the Java heap) and
# NEED_BYTES (the RAM the run needs). A heap set by the user replaces the
# estimate.
plan_memory() {
    local pbf="$1" mode="$2" override
    override="$(heap_override_bytes)"
    if [[ "$mode" == "memory" ]]; then
        HEAP_BYTES="${override:-$(awk -v p="$pbf" 'BEGIN { printf "%.0f", 1.7 * p + 2 * 1073741824 }')}"
        NEED_BYTES=$((HEAP_BYTES + GIB))
    else
        HEAP_BYTES="${override:-$(awk -v p="$pbf" 'BEGIN { printf "%.0f", 0.3 * p + 2 * 1073741824 }')}"
        NEED_BYTES="$(awk -v h="$HEAP_BYTES" -v p="$pbf" 'BEGIN { printf "%.0f", h + 0.2 * p + 1073741824 }')"
    fi
}

# check_memory <pbf bytes> → plans MODE's memory for this input, stops with an
# error when the container has too little RAM, and turns renumbering off (with
# a notice) when only renumbering does not fit.
check_memory() {
    local pbf="$1"
    plan_memory "$pbf" "$MODE"
    if ((NEED_BYTES > MEM_BYTES)); then
        local lines=("Error: $MODE mode needs ~$(human_size "$NEED_BYTES") of RAM for a $(human_size "$pbf") .osm.pbf,"
            "       but the container has only ${MEM_HUMAN} GB.")
        if [[ "$MODE" == "memory" ]]; then
            plan_memory "$pbf" disk
            lines+=("       Disk mode (--mode disk) would need ~$(human_size "$NEED_BYTES").")
        fi
        fail "${lines[@]}" "       On Docker Desktop, raise the memory limit under Settings → Resources."
    fi
    if [[ "$RENUMBER" != "0" ]]; then
        local need
        need="$(awk -v p="$pbf" 'BEGIN {
            n = 7.5e9 * p / 66691979646; c = 1; while (c < n) c *= 2
            printf "%.0f", 8 * c + 2 * 1073741824 }')"
        if ((need > MEM_BYTES)); then
            note "⚠️  Renumbering the OSM IDs needs ~$(human_size "$need") of RAM, but the container has ${MEM_HUMAN} GB;"
            note "    skipping it. The tiles are the same, only slightly larger."
            RENUMBER=0
            RENUMBER_SKIPPED="needs ~$(human_size "$need") of RAM"
        fi
    fi
}

# Planetiler flags for MODE. The node map is a plain array indexed by node ID
# where the IDs are dense, i.e. renumbered; its size follows the highest node
# ID (~110 GB for real OSM IDs, which reach 13.7 billion). In disk mode, that
# array also suits the planet, which uses nearly every ID, and a memory-mapped
# file only takes disk space where it is written. Everything else gets a
# sparse array, whose size follows the node count. (On Docker Desktop, a host
# folder does not keep the array's file sparse, so even Monaco would write
# tens of GB.)
mode_flags() {
    local storage=mmap nodemap=sparsearray
    [[ "$MODE" == "memory" ]] && storage=ram
    if [[ "$RENUMBER" != "0" ]] || [[ "$MODE" != "memory" && "$AREA" == "planet" ]]; then
        nodemap=array
    fi
    printf '%s' "--storage=$storage --nodemap_type=$nodemap"
}

# Size of the newest planet .osm.pbf in bytes, from a HEAD request; empty (and
# non-zero) when the server cannot be reached.
planet_pbf_size() {
    curl -fsSIL --max-time 30 "$PLANET_PBF_BASE/planet-latest.osm.pbf" | tr -d '\r' |
        awk 'tolower($1) == "content-length:" { n = $2 } END { if (n) print n; else exit 1 }'
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
        log "Resolving the latest planet snapshot from ${PLANET_PBF_BASE}/"
        date="$(curl -fsSL "${PLANET_PBF_BASE}/" |
            grep -oE 'planet-[0-9]{6}\.osm\.pbf' |
            grep -oE '[0-9]{6}' | sort | tail -n1 || true)"
    fi
    [[ -n "$date" ]] || fail "Error: could not determine the latest planet date; set PLANET_DATE=YYMMDD."

    PLANET_PBF="$sources_dir/planet-${date}.osm.pbf"
    if [[ -f "$PLANET_PBF" && ! -f "${PLANET_PBF}.aria2" ]]; then
        note "♻️  Using the cached $(basename "$PLANET_PBF"); delete it to download a fresh copy."
        return
    fi

    local torrent="$sources_dir/planet-${date}.osm.pbf.torrent"
    curl -fsSL "${PLANET_PBF_BASE}/planet-${date}.osm.pbf.torrent" -o "$torrent" ||
        fail "Error: could not download ${PLANET_PBF_BASE}/planet-${date}.osm.pbf.torrent"
    # --seed-time=0 stops seeding once complete; --continue + the .aria2 control
    # file make the multi-hour download resumable; falloc preallocates quickly.
    run_logged "generic:planet via BitTorrent" aria2c --dir="$sources_dir" --seed-time=0 \
        --continue=true --file-allocation=falloc --summary-interval=10 "$torrent" || step_failed
}

# Fetch the water polygons into $OCEAN_PATH. Planetiler's --download only fetches
# a missing file, so a cached copy would never be refreshed (osmdata rebuilds it
# daily), and it has no fallback when osmdata is down.
#   • A cached copy less than a week old is kept.
#   • Otherwise try OCEAN_URL, then the newest dated folder of OCEAN_MIRROR. curl
#     -R keeps the server's timestamp, so the age check measures the data, and -z
#     skips the download when the server has nothing newer than the cache.
#   • If both fail, keep the cached copy with a warning; without one, stop.
fetch_water_polygons() {
    require_cmd curl
    local file="$OCEAN_PATH"
    mkdir -p "$(dirname "$file")"

    if [[ -f "$file" && -z "$(find "$file" -mmin +$((7 * 24 * 60)))" ]]; then
        log "Reusing $file (less than a week old)."
        return
    fi

    download_water_polygons "$OCEAN_URL" && return

    local newest
    newest="$(curl -fsS --max-time 30 "$OCEAN_MIRROR/" |
        grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}/' | sort | tail -n1 || true)"
    if [[ -n "$newest" ]]; then
        download_water_polygons "$OCEAN_MIRROR/${newest}water-polygons-split-3857.zip" && return
    else
        note "⚠️  Could not list the dated folders of $OCEAN_MIRROR"
    fi

    [[ -f "$file" ]] || fail "Error: could not download the water polygons, and there is no cached copy."
    note "⚠️  Could not refresh the water polygons; using the cached copy."
}

# download_water_polygons <url> → downloads into $OCEAN_PATH via a .part file,
# so an interrupted download never replaces the cached copy. Returns non-zero
# on failure.
download_water_polygons() {
    local url="$1" file="$OCEAN_PATH" part="$OCEAN_PATH.part" headers="$OCEAN_PATH.headers" newer_than=()
    [[ -f "$file" ]] && newer_than=(-z "$file")
    if run_logged "generic:water polygons" curl -fL -R -# --connect-timeout 30 --retry 2 \
        "${newer_than[@]}" -D "$headers" -o "$part" "$url"; then
        if [[ "$(awk '/^HTTP/ { s = $2 } END { print s }' "$headers")" == "304" ]]; then
            log "The cached copy is up to date."
            rm -f "$part"
        else
            mv "$part" "$file"
        fi
        rm -f "$headers"
        return 0
    fi
    rm -f "$part" "$headers"
    note "⚠️  Download failed: $url"
    return 1
}

###########################################################################
# 🏷️  Output metadata (meta_update arguments)
###########################################################################
# HTML attributes use single quotes so the values need no escaping inside the
# double-quoted VPL strings.
OSM_ATTRIBUTION="<a href='https://www.openstreetmap.org/copyright' target='_blank'>&copy; OpenStreetMap contributors</a>"
LANDCOVER_ATTRIBUTION="<a href='https://esa-worldcover.org/en/data-access' target='_blank'>ESA WorldCover 2021</a> (<a href='https://creativecommons.org/licenses/by/4.0/' target='_blank'>CC BY 4.0</a>)"

base_meta_args() {
    printf '%s' "name=\"VersaTiles OSM\"" \
        " description=\"Vector tiles based on OSM in Shortbread scheme\"" \
        " attribution=\"$OSM_ATTRIBUTION\"" \
        " schema=\"shortbread@1.1\""
}

landcover_meta_args() {
    printf '%s' "name=\"VersaTiles OSM\"" \
        " description=\"Vector tiles based on OSM in Shortbread scheme, with land cover from ESA WorldCover 2021\"" \
        " attribution=\"$OSM_ATTRIBUTION · $LANDCOVER_ATTRIBUTION\"" \
        " schema=\"shortbread@1.1\""
}

###########################################################################
# 🌍  Land cover handover (VPL filters for the merge)
###########################################################################
# The land cover container carries every kind up to z10, so the merge filters
# both sources to take each kind from exactly one of them per zoom
# (https://github.com/versatiles-org/landcover-vectors#merging-with-osm):
#   • OSM's own copies of the land cover kinds are dropped up to z10, because
#     they are sparse where ESA's are complete;
#   • the land cover's residential is dropped from z10 and its water from z4,
#     because OSM maps those better.
# `zoom` in filter expressions needs versatiles 4.15.0 or later; older releases
# silently drop every feature of the filtered layers.
OSM_HANDOVER_FILTER="vector_filter_features layer=[\"land\"] expr=\"!(zoom <= 10 && kind in ['forest', 'farmland', 'bare_rock', 'heath', 'scrub', 'grassland', 'marsh', 'swamp'])\""
OSM_HANDOVER_FILTER+=" | vector_filter_features layer=[\"water_polygons\"] expr=\"!(zoom <= 10 && kind in ['glacier'])\""
LANDCOVER_HANDOVER_FILTER="vector_filter_features layer=[\"land\"] expr=\"!(zoom >= 10 && kind in ['residential'])\""
LANDCOVER_HANDOVER_FILTER+=" | vector_filter_features layer=[\"water_polygons\"] expr=\"!(zoom >= 4 && kind in ['water'])\""

# Echo a container's bounds as "[west,south,east,north]". `versatiles probe` has
# no machine-readable output: it prints its report to stderr, with the metadata
# as an indented JSON block after "  meta: {".
read_bounds() {
    versatiles probe "$1" 2>&1 >/dev/null |
        awk '/^  meta: \{/ { f = 1; print "{"; next } f && /^  \}/ { print "}"; exit } f' |
        jq -ce '.bounds | select(type == "array" and length == 4 and all(type == "number"))'
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

# default_output_name <prefix> → the default base filename (without extension):
#   planet → <prefix>.<date>
#   region → <prefix>.<region>.<date>
default_output_name() {
    local base="$1"
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

# Base names of the outputs: OSM_NAME is OUTPUT_NAME or the default
# osm[.<region>].<date>. With land cover, LANDCOVER_NAME is the default
# osm-landcover[.<region>].<date>, or a custom name with "-landcover" added
# (before its extension, if it has one).
resolve_output_names() {
    OSM_NAME="${OUTPUT_NAME:-$(default_output_name osm)}"
    LANDCOVER_NAME=""
    [[ "$LANDCOVER" == "1" ]] || return 0
    case "$OUTPUT_NAME" in
    "") LANDCOVER_NAME="$(default_output_name osm-landcover)" ;;
    *.versatiles | *.mbtiles | *.pmtiles) LANDCOVER_NAME="${OUTPUT_NAME%.*}-landcover.${OUTPUT_NAME##*.}" ;;
    *) LANDCOVER_NAME="$OUTPUT_NAME-landcover" ;;
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
        --mode) MODE="${2:-}"; shift 2 ;;
        --mode=*) MODE="${1#*=}"; shift ;;
        --xmx) XMX="${2:-}"; shift 2 ;;
        --xmx=*) XMX="${1#*=}"; shift ;;
        --torrent) TORRENT=1; shift ;;
        --renumber) RENUMBER=1; shift ;;
        --no-renumber) RENUMBER=0; shift ;;
        --checksum) CHECKSUM=1; shift ;;
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
    scope="$(ask "Render the whole [p]lanet or a [s]ub-region? [p/s] (default: p): " "p")"
    if [[ "$scope" != [sS]* ]]; then
        AREA="planet"
        echo "  ⚠  The whole planet needs a large machine: ~48 GB+ RAM and ~400 GB+ free disk." >&2
        echo "     The RAM is checked after the processing mode is chosen." >&2
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
    lc="$(ask "Inject land cover data from download.versatiles.org (landcover-vectors.versatiles)? [y/N]: " "n")"
    if [[ "$lc" == [yY]* ]]; then LANDCOVER=1; else LANDCOVER=0; fi

    # 3) Container format?
    local fmt
    fmt="$(ask "Container format — [v]ersatiles, [m]btiles, [p]mtiles? (default: v): " "v")"
    case "$fmt" in
    [mM]*) FORMAT="mbtiles" ;;
    [pP]*) FORMAT="pmtiles" ;;
    *) FORMAT="versatiles" ;;
    esac

    # 4) Output name, without extension. With land cover it names both files
    #    (see resolve_output_names). Empty keeps the default names.
    if [[ "$LANDCOVER" == "1" ]]; then
        OUTPUT_NAME="$(ask "Output name, one for both files (default: $(default_output_name osm) / $(default_output_name osm-landcover)): " "")"
    else
        OUTPUT_NAME="$(ask "Output name (default: $(default_output_name osm)): " "")"
    fi

    # 5) Checksums?
    local cs
    cs="$(ask "Write .md5 and .sha256 checksum files for each output? [y/N]: " "n")"
    if [[ "$cs" == [yY]* ]]; then CHECKSUM=1; else CHECKSUM=0; fi

    # 6) Processing mode. For the planet, the size of the .osm.pbf is known
    #    now, so the RAM is checked right away; for a region, after download.
    local pbf="" default_mode="d" mode
    if [[ "$AREA" == "planet" ]]; then
        pbf="$(planet_pbf_size || true)"
    fi
    if [[ -n "$pbf" ]]; then
        local disk_need memory_need
        plan_memory "$pbf" disk
        disk_need="$NEED_BYTES"
        plan_memory "$pbf" memory
        memory_need="$NEED_BYTES"
        ((memory_need <= MEM_BYTES)) && default_mode="m"
        echo "  The planet .osm.pbf is $(human_size "$pbf"); this container has ${MEM_HUMAN} GB of RAM." >&2
        echo "    [d]isk   — temporary data in memory-mapped files:  needs ~$(human_size "$disk_need")" >&2
        echo "    [m]emory — temporary data on the Java heap, faster: needs ~$(human_size "$memory_need")" >&2
    else
        echo "  This container has ${MEM_HUMAN} GB of RAM. Each mode needs, relative to the .osm.pbf:" >&2
        echo "    [d]isk   — temporary data in memory-mapped files:  ~0.5× its size + 3 GB" >&2
        echo "    [m]emory — temporary data on the Java heap, faster: ~1.7× its size + 3 GB" >&2
        echo "  The RAM is checked once the .osm.pbf is downloaded." >&2
    fi
    mode="$(ask "Processing mode — [d]isk or [m]emory? (default: ${default_mode}): " "$default_mode")"
    if [[ "$mode" == [mM]* ]]; then MODE=memory; else MODE=disk; fi
    if [[ -n "$pbf" ]]; then
        check_memory "$pbf"
        MEMORY_CHECKED=1
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
    case "$MODE" in
    disk | memory) ;;
    *)
        echo "Error: invalid --mode '$MODE' (expected disk or memory)." >&2
        exit 1
        ;;
    esac
    # The JVM reads a bare number as bytes, so "96" would be a 96-byte heap.
    if [[ -n "$XMX" && ! "$XMX" =~ ^[0-9]+[kKmMgGtT]$ ]]; then
        echo "Error: invalid --xmx '$XMX' (expected a size with a unit, such as 20g)." >&2
        exit 1
    fi
    resolve_output_names
}

###########################################################################
# 🚀  Pipeline
###########################################################################
run_pipeline() {
    require_cmd java
    require_cmd versatiles

    mkdir -p "$DATA_DIR" "$RESULT_DIR" "$DATA_DIR/logs"

    intermediate="$DATA_DIR/planetiler.pmtiles"
    local osm_file landcover_file=""
    osm_file="$RESULT_DIR/$(output_filename "$OSM_NAME")"
    [[ "$LANDCOVER" == "1" ]] && landcover_file="$RESULT_DIR/$(output_filename "$LANDCOVER_NAME")"
    LOG_FILE="$DATA_DIR/logs/$OSM_NAME.log"
    : >"$LOG_FILE"
    local t0=$EPOCHSECONDS

    # Remove the intermediate PMTiles, any renumbered pbf and an interrupted
    # water polygons download on exit, and end an open step line.
    trap '((STEP_OPEN)) && printf "\n"; rm -f "${intermediate:-}" "${renumbered:-}" "$OCEAN_PATH.part" "$OCEAN_PATH.headers"' EXIT

    echo "VersaTiles Planetiler: $AREA$([[ -n "$landcover_file" ]] && echo ", with land cover"), $FORMAT, $MODE mode"
    echo "   Results: $osm_file"
    [[ -n "$landcover_file" ]] && echo "            $landcover_file"
    echo "   Log:     $LOG_FILE"
    echo
    {
        echo "VersaTiles Planetiler, $(date '+%F %T')"
        echo "   AREA=$AREA LANDCOVER=$LANDCOVER FORMAT=$FORMAT MODE=$MODE RENUMBER=$RENUMBER"
        echo "   CHECKSUM=$CHECKSUM TORRENT=$TORRENT LANGUAGES=$LANGUAGES EXPERIMENTS=$EXPERIMENTS"
        echo "   JAVA_OPTS=$JAVA_OPTS PLANETILER_EXTRA_FLAGS=$PLANETILER_EXTRA_FLAGS"
        echo "   RAM available: ${MEM_HUMAN} GB"
    } >>"$LOG_FILE"

    # Planetiler only *warns* about insufficient resources and we pass --force
    # (so it never blocks on a prompt), so check_memory checks the RAM instead:
    # for the planet before the download, from the server's file size, and for
    # every area once the .osm.pbf is on disk.
    if [[ "$AREA" == "planet" && "$MEMORY_CHECKED" != "1" ]]; then
        local planet_size
        if planet_size="$(planet_pbf_size)"; then
            check_memory "$planet_size"
        else
            note "⚠️  Could not look up the planet's size; the RAM is checked after the download."
        fi
    fi

    # Renumbering is a step of its own only when it is requested; check_memory
    # may still skip it.
    STEP_TOTAL=$((3 + (RENUMBER != 0) + LANDCOVER))

    ###########################################################################
    # 1) Download: all inputs are fetched first, so that their sizes are known
    #    before the long steps. Planetiler's --download only fetches missing
    #    sources, so it runs only when the .osm.pbf or the country polygons are
    #    missing; the water polygons come from fetch_water_polygons.
    ###########################################################################
    step_begin "Downloading sources"
    fetch_water_polygons

    local src_pbf="$DATA_DIR/sources/$AREA.osm.pbf"
    if [[ "$TORRENT" == "1" && "$AREA" == "planet" ]]; then
        download_planet_torrent
        src_pbf="$PLANET_PBF"
    elif [[ "$TORRENT" == "1" ]]; then
        note "⚠️  --torrent only applies to the planet; ignoring it for '$AREA'."
    fi
    # Planetiler never refreshes a cached .osm.pbf, so say that it is used.
    if [[ "$src_pbf" != "${PLANET_PBF:-}" && -f "$src_pbf" ]]; then
        note "♻️  Using the cached $(basename "$src_pbf") from $(date -r "$src_pbf" +%Y-%m-%d); delete it to download a fresh copy."
    fi
    if [[ ! -f "$src_pbf" || ! -f "$COUNTRIES_PATH" ]]; then
        # shellcheck disable=SC2086
        run_logged planetiler java $JAVA_OPTS -jar "$PLANETILER_JAR" shortbread-1.1 \
            --area="$AREA" --download --only_download \
            --osm_path="$src_pbf" --ocean_path="$OCEAN_PATH" \
            --ne_10m_admin_0_countries_path="$COUNTRIES_PATH" \
            $PLANETILER_EXTRA_FLAGS || step_failed
    fi
    [[ -f "$src_pbf" ]] || fail "Error: the OSM input $src_pbf is missing after the download."

    local pbf_size
    pbf_size="$(stat -c %s "$src_pbf")"
    NODES_EST="$(awk -v p="$pbf_size" 'BEGIN { n = int(7.5e9 * p / 66691979646); print (n < 1) ? 1 : n }')"
    check_memory "$pbf_size"
    local render_java_opts="$JAVA_OPTS"
    [[ "$JAVA_OPTS" == *-Xmx* ]] || render_java_opts="-Xmx$(mib "$HEAP_BYTES")m${JAVA_OPTS:+ $JAVA_OPTS}"
    step_end "$(basename "$src_pbf"), $(human_size "$pbf_size")"
    note "💾 $MODE mode: Java heap $(human_size "$HEAP_BYTES"), needs ~$(human_size "$NEED_BYTES") of ${MEM_HUMAN} GB RAM"

    ###########################################################################
    # 2) Renumber OSM IDs so they are dense (faster, slightly smaller tiles),
    #    if requested with --renumber.
    ###########################################################################
    local osm_pbf="$src_pbf"
    if [[ "$RENUMBER" != "0" ]]; then
        require_cmd osmium
        step_begin "Renumbering OSM IDs"
        renumbered="$DATA_DIR/sources/renumbered.osm.pbf"
        run_logged generic osmium renumber --progress --overwrite -o "$renumbered" "$src_pbf" || step_failed
        osm_pbf="$renumbered"
        step_end
    elif [[ -n "$RENUMBER_SKIPPED" ]]; then
        step_skip "Renumbering OSM IDs" "$RENUMBER_SKIPPED"
    fi

    ###########################################################################
    # 3) Render with Planetiler → intermediate PMTiles
    #
    # PMTiles is a flat, sequentially-laid-out file, so the `versatiles convert`
    # read below avoids the random-access SQLite overhead of MBTiles.
    ###########################################################################
    step_begin "Rendering tiles"
    # mode_flags and PLANETILER_EXTRA_FLAGS are split into words on purpose; the
    # extra flags come last, so they override the mode's.
    # shellcheck disable=SC2086,SC2046
    run_logged planetiler java $render_java_opts -jar "$PLANETILER_JAR" shortbread-1.1 \
        --area="$AREA" \
        --download \
        --force \
        $(mode_flags) \
        --name_languages="$LANGUAGES" \
        --shortbread_experiments="$EXPERIMENTS" \
        --output="$intermediate" \
        --osm_path="$osm_pbf" \
        --ocean_path="$OCEAN_PATH" \
        --ne_10m_admin_0_countries_path="$COUNTRIES_PATH" \
        $PLANETILER_EXTRA_FLAGS || step_failed
    step_end "$(human_size "$(stat -c %s "$intermediate")")"

    ###########################################################################
    # 4) Convert → final container(s)
    #
    # The OSM output is always written. With land cover, a second output is
    # converted from the same intermediate: the VPL `from_merged_vector`
    # operation folds the remote land cover container's features into the
    # Shortbread layers, with both sources filtered so each kind comes from one
    # of them per zoom (see "Land cover handover" above). The land cover
    # container is range-read from its URL — nothing is downloaded.
    # The merge covers the union of both sources, so for a sub-region `filter`
    # crops it back to the Planetiler output's bounds; otherwise the result would
    # hold the whole world's land cover.
    #
    # Either way, `meta_update` replaces Planetiler's generic Shortbread metadata
    # with VersaTiles branding (see issue #53).
    ###########################################################################
    local source="from_container filename=\"$intermediate\""
    step_begin "Converting to $FORMAT"
    convert_output "$source | meta_update $(base_meta_args)" "$osm_file"
    step_end "$(human_size "$(stat -c %s "$osm_file")")"

    if [[ -n "$landcover_file" ]]; then
        step_begin "Merging land cover"
        source="from_merged_vector [ $source | $OSM_HANDOVER_FILTER, from_container filename=\"$LANDCOVER_URL\" | $LANDCOVER_HANDOVER_FILTER ]"
        if [[ "$AREA" != "planet" ]]; then
            local bounds
            bounds="$(read_bounds "$intermediate")" ||
                fail "Error: could not read the bounds of $intermediate to crop the land cover."
            source="$source | filter bbox=$bounds"
        fi
        convert_output "$source | meta_update $(landcover_meta_args)" "$landcover_file"
        step_end "$(human_size "$(stat -c %s "$landcover_file")")"
    fi

    echo
    echo "✅ Done in $(duration $((EPOCHSECONDS - t0))):"
    echo "   $osm_file"
    [[ -n "$landcover_file" ]] && echo "   $landcover_file"
    log "=== done in $(duration $((EPOCHSECONDS - t0)))"
    return 0
}

# convert_output <vpl> <file> → converts the VPL pipeline into <file> (brotli
# for .versatiles) and writes its checksums if requested.
convert_output() {
    local compression_args=()
    [[ "$FORMAT" == "versatiles" ]] && compression_args=(-c brotli)
    run_logged generic versatiles convert "${compression_args[@]}" "[,vpl]($1)" "$2" || step_failed
    if [[ "$CHECKSUM" == "1" ]]; then
        write_checksums "$2"
    fi
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
run_pipeline
