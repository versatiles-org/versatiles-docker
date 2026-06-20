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
#   --area <planet|REGION>   What to render: "planet" or a Geofabrik region id
#                            such as "monaco" or "germany/berlin". Planetiler
#                            downloads the extract from download.geofabrik.de.
#                            REQUIRED in non-interactive mode.
#   --landcover              Merge land cover data (default: off).
#   --format <FMT>           Output container: versatiles (default), mbtiles or
#                            pmtiles. "versatiles" uses brotli compression.
#   --name <BASENAME>        Output filename (the extension is added
#                            automatically). Default: osm[-landcover].<date>
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
# 📁 DIRECTORY LAYOUT (inside the container)
#   /app/data      Working directory for downloads and the intermediate PMTiles
#   /app/result    Final output location (<name>.<format>)
#
# 🔄 PIPELINE
#   1) planetiler shortbread-1.1 → intermediate PMTiles
#   2) versatiles convert (optionally merging land cover via VPL) → final container
#
set -euo pipefail

###########################################################################
# ⚙️  Defaults (overridable via environment)
###########################################################################
PLANETILER_JAR="${PLANETILER_JAR:-/opt/planetiler/planetiler.jar}"
DATA_DIR="${DATA_DIR:-/app/data}"
RESULT_DIR="${RESULT_DIR:-/app/result}"
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
  --area <planet|REGION>   What to render: "planet" or a Geofabrik region id
                           such as "monaco" or "germany/berlin". REQUIRED in
                           non-interactive mode.
  --landcover              Merge land cover data (default: off).
  --format <FMT>           Output container: versatiles (default), mbtiles or
                           pmtiles. "versatiles" uses brotli compression.
  --name <BASENAME>        Output filename without extension. Default:
                           osm[-landcover].<date>
  -i, --interactive        Force the interactive wizard.
  -h, --help               Show this help.

ENVIRONMENT (flags take precedence)
  AREA, LANDCOVER=1, FORMAT, OUTPUT_NAME, INTERACTIVE=1   configuration
  LANDCOVER_URL, LANGUAGES, EXPERIMENTS,
  PLANETILER_EXTRA_FLAGS, JAVA_OPTS                       tuning
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

# ask <prompt> <default> → echoes the user's answer, or the default on empty/EOF.
ask() {
    local prompt="$1" default="$2" answer
    printf '%s' "$prompt" >&2
    read -r answer || answer=""
    [[ -z "$answer" ]] && answer="$default"
    printf '%s' "$answer"
}

# Base filename (without extension) used as the default output name.
default_output_name() {
    local base="osm"
    [[ "$LANDCOVER" == "1" ]] && base="osm-landcover"
    printf '%s.%s' "$base" "$DATE"
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
    else
        echo "  Enter a Geofabrik region id (e.g. monaco, germany/berlin)." >&2
        echo "  Browse available regions at https://download.geofabrik.de/" >&2
        AREA=""
        while [[ -z "$AREA" ]]; do
            AREA="$(ask "  Region: " "")"
            [[ -z "$AREA" ]] && echo "  A region is required." >&2
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

    echo >&2
}

###########################################################################
# ✅  Validate the resolved configuration
###########################################################################
finalize_config() {
    if [[ -z "$AREA" ]]; then
        echo "Error: --area is required (planet or a Geofabrik region id)." >&2
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

    # Remove the intermediate PMTiles on exit (success or failure).
    trap 'rm -f "${intermediate:-}"' EXIT

    echo "GENERATE SHORTBREAD VECTOR TILES:"
    echo "   AREA:      $AREA"
    if [[ "$LANDCOVER" == "1" ]]; then
        echo "   LANDCOVER: yes ($LANDCOVER_URL)"
    else
        echo "   LANDCOVER: no"
    fi
    echo "   FORMAT:    $FORMAT"
    echo "   OUTPUT:    $out_file"

    ###########################################################################
    # 1) Render with Planetiler → intermediate PMTiles
    #
    # PMTiles is a flat, sequentially-laid-out file, so the `versatiles convert`
    # read below avoids the random-access SQLite overhead of MBTiles.
    ###########################################################################
    echo "🧱  Rendering tiles with Planetiler…"
    # shellcheck disable=SC2086
    time java $JAVA_OPTS -jar "$PLANETILER_JAR" shortbread-1.1 \
        --area="$AREA" \
        --download \
        --force \
        --name_languages="$LANGUAGES" \
        --shortbread_experiments="$EXPERIMENTS" \
        --output="$intermediate" \
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
