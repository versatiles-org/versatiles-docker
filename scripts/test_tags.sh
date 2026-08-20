#!/usr/bin/env bash
###############################################################################
# test_tags.sh — verify which tags each build.sh would publish.
#
# Why this exists: issue #47. The `latest-alpine` / `latest-debian` /
# `latest-scratch` aliases silently dropped out of the tag lists and nobody
# noticed for 15 months, because nothing anywhere asserted what gets published.
# The images themselves were fine — only the tag list was wrong.
#
# Runs in milliseconds: no Docker, no network, no image builds. Safe to run on
# every pull request.
#
# It works by stubbing build_push_image and `eval`ing the real call sites out of
# each build.sh, so bash itself does the parsing and the assertions track what
# the scripts actually do rather than a copy of it.
#
#   ./scripts/test_tags.sh
###############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./scripts/utils.sh
source ./scripts/utils.sh
# shellcheck source=./scripts/test_utils.sh
source ./scripts/test_utils.sh

# Fixed stand-ins for the values the build scripts resolve at runtime.
NAME="IMG"
VER="v1.2.3"
VER_TC="2.79.0"
VER_VT="v4.8.0"
export NAME VER VER_TC VER_VT

# Keep a copy of the real helper before shadowing it, so section 3 can exercise
# the genuine registry fan-out rather than a re-statement of it.
eval "real_build_push_image() $(declare -f build_push_image | tail -n +2)"

# Recorded (target -> tag-list) pairs for the script under test.
declare -a REC_TARGETS=()
declare -a REC_TAGS=()

# Stub replacing the real helper; records instead of building.
build_push_image() {
    REC_TARGETS+=("$1")
    REC_TAGS+=("$3")
}

# collect_tags <build.sh path>  — populates REC_TARGETS / REC_TAGS
collect_tags() {
    local script="$1" line
    REC_TARGETS=()
    REC_TAGS=()
    while IFS= read -r line; do
        eval "$line"
    done < <(grep -E '^[[:space:]]*build_push_image ' "$script")
}

# tags_for <target> — echo the recorded tag list for one target
tags_for() {
    local want="$1" i
    for i in "${!REC_TARGETS[@]}"; do
        if [[ "${REC_TARGETS[$i]}" == "$want" ]]; then
            echo "${REC_TAGS[$i]}"
            return 0
        fi
    done
    echo "<no build_push_image call for target '$want'>"
}

###############################################################################
# 1. Golden expectations — the exact tag list per target.
#
#    Deliberately explicit: changing a published tag set should require editing
#    this file, so it is a conscious decision rather than a silent drift.
###############################################################################
echo "🏷  Tag lists"

collect_tags versatiles/build.sh
assert_eq "versatiles: debian tags"  "$(tags_for versatiles-debian)"  "debian,v1.2.3-debian,latest-debian"
assert_eq "versatiles: alpine tags"  "$(tags_for versatiles-alpine)"  "alpine,v1.2.3-alpine,latest,v1.2.3,latest-alpine"
assert_eq "versatiles: scratch tags" "$(tags_for versatiles-scratch)" "scratch,v1.2.3-scratch,latest-scratch"

collect_tags versatiles-frontend/build.sh
assert_eq "versatiles-frontend: debian tags"  "$(tags_for versatiles-debian)"  "debian,v1.2.3-debian,latest-debian"
assert_eq "versatiles-frontend: alpine tags"  "$(tags_for versatiles-alpine)"  "alpine,v1.2.3-alpine,latest,v1.2.3,latest-alpine"
assert_eq "versatiles-frontend: scratch tags" "$(tags_for versatiles-scratch)" "scratch,v1.2.3-scratch,latest-scratch"

collect_tags versatiles-nginx/build.sh
assert_eq "versatiles-nginx: tags" "$(tags_for versatiles-nginx)" "latest,v1.2.3"

collect_tags versatiles-gdal/build.sh
assert_eq "versatiles-gdal: tags" "$(tags_for versatiles-gdal)" "latest,v1.2.3"

collect_tags versatiles-planetiler/build.sh
assert_eq "versatiles-planetiler: tags" "$(tags_for versatiles-planetiler)" "latest,v1.2.3"

collect_tags versatiles-tilemaker/build.sh
assert_eq "versatiles-tilemaker: tags" "$(tags_for versatiles-tilemaker)" "latest,v1.2.3"

collect_tags versatiles-tippecanoe/build.sh
assert_eq "versatiles-tippecanoe: tags" "$(tags_for versatiles-tippecanoe)" "latest,2.79.0"

###############################################################################
# 2. Structural invariants — these hold regardless of the exact version string,
#    and are what would catch a #47-style omission generically.
###############################################################################
echo "🏷  Invariants"

# assert_tags_include <description> <tag-csv> <tag…>
assert_tags_include() {
    local desc="$1" csv="$2" tag
    shift 2
    for tag in "$@"; do
        if [[ ",$csv," != *",$tag,"* ]]; then
            _fail "$desc" "missing tag '$tag'" "tag list: $csv"
        fi
    done
    _pass "$desc"
}

# assert_no_duplicate_tags <description> <tag-csv>
assert_no_duplicate_tags() {
    local desc="$1" csv="$2" total uniq
    total=$(echo "$csv" | tr ',' '\n' | grep -c .)
    uniq=$(echo "$csv" | tr ',' '\n' | grep . | sort -u | wc -l | tr -d ' ')
    if [[ "$total" -eq "$uniq" ]]; then
        _pass "$desc"
    else
        _fail "$desc" "tag list contains duplicates: $csv"
    fi
}

for script in versatiles/build.sh versatiles-frontend/build.sh; do
    image="${script%/build.sh}"
    collect_tags "$script"

    # Each variant must publish its bare name, its versioned name, and — the
    # thing that went missing in #47 — its deprecated latest-* alias.
    for variant in debian alpine scratch; do
        tags=$(tags_for "versatiles-$variant")
        assert_tags_include "$image/$variant: name, version and latest-$variant alias" \
            "$tags" "$variant" "$VER-$variant" "latest-$variant"
        assert_no_duplicate_tags "$image/$variant: no duplicate tags" "$tags"
    done

    # `latest` and the bare version must point at exactly one variant (alpine),
    # otherwise the last push silently wins and `latest` becomes a coin flip.
    all=""
    for variant in debian alpine scratch; do all+="$(tags_for "versatiles-$variant"),"; done
    for tag in latest "$VER"; do
        count=$(echo "$all" | tr ',' '\n' | grep -cx "$tag")
        assert_eq "$image: '$tag' claimed by exactly one variant" "$count" "1"
    done
    assert_tags_include "$image: 'latest' rides on alpine" "$(tags_for versatiles-alpine)" latest
done

###############################################################################
# 3. Registry fan-out — every tag must reach Docker Hub *and* GHCR.
#
#    The one-off repair for #47 only fixed Docker Hub; GHCR stayed stale until
#    the next release. Both registries are part of the contract.
###############################################################################
echo "🏷  Registry fan-out"

# Drive the REAL build_push_image with docker stubbed out, so this asserts the
# registry list the helper actually uses. Passing the registries in by hand here
# would only re-state the expectation instead of testing it.
# NB: build_push_image redirects the docker invocation to /dev/null, so the stub
# records into a file rather than onto stdout.
_docker_log=$(mktemp)
(
    docker() { printf '%s\n' "$*" >>"$_docker_log"; }
    _ensure_builder() { :; }
    buildx_cache_args() { :; }
    real_build_push_image sometarget IMG "alpine,latest" ./Dockerfile
) >/dev/null 2>&1
docker_args=$(cat "$_docker_log")
rm -f "$_docker_log"

for ref in versatiles/IMG:alpine versatiles/IMG:latest \
    ghcr.io/versatiles-org/IMG:alpine ghcr.io/versatiles-org/IMG:latest; do
    assert_contains "build_push_image targets $ref" "$docker_args" "--tag $ref"
done

print_test_summary
