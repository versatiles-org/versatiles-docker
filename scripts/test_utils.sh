#!/usr/bin/env bash
# shellcheck shell=bash
###############################################################################
# test_utils.sh — shared assertions and container helpers for the image tests.
#
# Sourced by each <image>/build.sh *after* scripts/utils.sh:
#
#     source ./scripts/utils.sh
#     source ./scripts/test_utils.sh
#
# Conventions:
#   * Every assert_* takes the human-readable description FIRST.
#   * A failing assertion prints the reason and exits 1 immediately, matching
#     the fail-fast behaviour the build scripts already relied on.
#   * Helpers that need a shell inside the container are marked "needs shell";
#     they cannot be used on the `scratch` variant, which ships no shell.
#     Use the inspect-only helpers (assert_image_config, assert_path_appends_app)
#     for contracts that must hold on every variant.
###############################################################################

TESTS_PASSED=0

_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '    ✅ %s\n' "$1"
}

# _fail <description> [detail…]
_fail() {
    printf '    ❌ %s\n' "$1" >&2
    shift
    local line
    for line in "$@"; do printf '       %s\n' "$line" >&2; done
    exit 1
}

###############################################################################
# Assertions
###############################################################################

# assert_eq <description> <actual> <expected>
assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        _pass "$desc"
    else
        _fail "$desc" "expected: '$expected'" "actual:   '$actual'"
    fi
}

# assert_contains <description> <haystack> <needle>
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        _pass "$desc"
    else
        _fail "$desc" "expected to contain: '$needle'" "actual: '$haystack'"
    fi
}

# assert_ends_with <description> <haystack> <suffix>
#
# Kept distinct from assert_contains because the convert tests deliberately
# require the success line to be the LAST thing emitted — a later error must not
# be masked by an earlier success message.
assert_ends_with() {
    local desc="$1" haystack="$2" suffix="$3"
    if [[ "$haystack" == *"$suffix" ]]; then
        _pass "$desc"
    else
        _fail "$desc" "expected to end with: '$suffix'" "actual tail: '${haystack: -120}'"
    fi
}

# assert_min_size <description> <file> <min_bytes>
assert_min_size() {
    local desc="$1" file="$2" min="$3" size
    if [[ ! -f "$file" ]]; then
        _fail "$desc" "file does not exist: $file"
    fi
    size=$(wc -c <"$file" | tr -d ' ')
    if [[ "$size" -ge "$min" ]]; then
        _pass "$desc ($size bytes)"
    else
        _fail "$desc" "expected at least $min bytes, got $size"
    fi
}

###############################################################################
# Timing
###############################################################################

# Millisecond epoch timestamp. GNU date supports %N; BSD/macOS date does not,
# so fall back to perl (present on both platforms).
get_timestamp_ms() {
    local ns
    ns=$(date +%s%N 2>/dev/null || true)
    if [[ "$ns" =~ ^[0-9]{16,}$ ]]; then
        echo "${ns:0:13}"
    else
        perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'
    fi
}

###############################################################################
# Container helpers
###############################################################################

# start_http_container <image> [docker-run-opts…] -- [container-args…]
#
# Publishes the container's port 8080 on an ephemeral loopback port, so tests
# never collide with whatever already listens on 8080 and can run in parallel.
# Sets the globals CONTAINER_ID and HOST_PORT.
start_http_container() {
    local image="$1"
    shift

    local -a opts=()
    while (($#)) && [[ "$1" != "--" ]]; do
        opts+=("$1")
        shift
    done
    if [[ "${1:-}" == "--" ]]; then shift; fi

    CONTAINER_ID=$(docker run -d --rm -p 127.0.0.1:0:8080 \
        ${opts[@]+"${opts[@]}"} "$image" "$@")

    # `|| true` so a container that already exited reaches the guard below and
    # reports its logs, instead of `set -e` aborting on docker's raw error.
    HOST_PORT=$(docker port "$CONTAINER_ID" 8080 2>/dev/null | head -n1 | sed 's/.*://' || true)
    if [[ -z "$HOST_PORT" ]]; then
        printf '    container did not publish port 8080; logs follow:\n' >&2
        docker logs "$CONTAINER_ID" >&2 2>/dev/null || true
        stop_container
        _fail "could not determine published host port for $image"
    fi
}

# stop_container [container-id]
stop_container() {
    local cid="${1:-${CONTAINER_ID:-}}"
    if [[ -n "$cid" ]]; then
        docker kill "$cid" >/dev/null 2>&1 || true
    fi
    return 0
}

# wait_for_http <url> [timeout_seconds] [container-id]
#
# Replaces fixed `sleep` calls: polls until the endpoint answers or the timeout
# expires. A server that is slow to start (large --static archive, cold cache,
# loaded CI runner) then waits rather than failing spuriously.
#
# Readiness means "the server responded", not "returned 2xx": the base image
# serves no static content, so / legitimately answers 404 while being perfectly
# up. Callers that care about the status code should assert it themselves.
wait_for_http() {
    local url="$1" timeout="${2:-60}" cid="${3:-${CONTAINER_ID:-}}" code
    local deadline=$((SECONDS + timeout))

    while ((SECONDS < deadline)); do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
        if [[ -n "$code" && "$code" != "000" ]]; then
            return 0
        fi
        # Fail fast if the container died instead of waiting out the timeout.
        if [[ -n "$cid" ]] && ! docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null | grep -q true; then
            docker logs "$cid" >&2 || true
            _fail "container exited before serving $url"
        fi
        sleep 0.25
    done

    if [[ -n "$cid" ]]; then
        docker logs "$cid" >&2 2>/dev/null || true
    fi
    _fail "timed out after ${timeout}s waiting for $url"
}

###############################################################################
# Image contract  (see issue #47 — these are the checks that were missing)
###############################################################################

# assert_image_config <image> <expected-entrypoint-json> <expected-workdir>
#
# Inspect-only, so it also covers the `scratch` variant. Guards the entrypoint /
# working-directory contract that changed silently in #21 and broke every
# documented `docker run` invocation.
assert_image_config() {
    local image="$1" want_entrypoint="$2" want_workdir="$3" got

    got=$(docker inspect "$image" --format '{{json .Config.Entrypoint}}')
    assert_eq "$image: entrypoint" "$got" "$want_entrypoint"

    got=$(docker inspect "$image" --format '{{.Config.WorkingDir}}')
    assert_eq "$image: workdir" "$got" "$want_workdir"
}

# assert_path_appends_app <image>
#
# Inspect-only. /app must be present but LAST, so a derived image that installs
# its own binary into /usr/local/bin still wins. Prepending would silently
# shadow such overrides instead of failing loudly.
assert_path_appends_app() {
    local image="$1" path last
    path=$(docker inspect "$image" --format \
        '{{range .Config.Env}}{{if eq (slice . 0 5) "PATH="}}{{slice . 5}}{{end}}{{end}}')

    if [[ -z "$path" ]]; then
        _fail "$image: no PATH set in image config"
    fi
    if [[ ":$path:" != *":/app:"* ]]; then
        _fail "$image: /app missing from PATH" "PATH=$path"
    fi

    last="${path##*:}"
    if [[ "$last" == "/app" ]]; then
        _pass "$image: /app is last on PATH"
    else
        _fail "$image: /app must be appended, not prepended" \
            "PATH=$path" "last element: '$last'"
    fi
}

# assert_binary_resolves <image> <name> <expected-path>   (needs shell)
assert_binary_resolves() {
    local image="$1" name="$2" want="$3" got
    got=$(docker run --rm --entrypoint sh "$image" -c "command -v $name || echo NOT_FOUND")
    assert_eq "$image: '$name' resolves" "$got" "$want"
}

# assert_file_in_image <image> <path> [test-flag]         (needs shell)
# Defaults to -x (exists and is executable).
assert_file_in_image() {
    local image="$1" path="$2" flag="${3:--x}" got
    got=$(docker run --rm --entrypoint sh "$image" -c "[ $flag '$path' ] && echo yes || echo no")
    assert_eq "$image: $path exists ($flag)" "$got" "yes"
}

###############################################################################
# Shutdown behaviour
###############################################################################

# test_shutdown_time <image> [max_ms] [server-args…]
#
# Verifies the container reacts to SIGTERM promptly, which is what tini is there
# for. Waits for the server to actually serve before timing, so a slow start can
# no longer be mistaken for a fast shutdown.
test_shutdown_time() {
    local image="$1" max_ms="${2:-1000}"
    shift 2 || shift $#
    local start end duration

    start_http_container "$image" -v "$(pwd)/testdata:/data" -- \
        ${@+"$@"}
    wait_for_http "http://127.0.0.1:${HOST_PORT}/" 90

    start=$(get_timestamp_ms)
    docker stop --time=3 "$CONTAINER_ID" >/dev/null 2>&1 || true
    end=$(get_timestamp_ms)
    duration=$((end - start))

    if [[ "$duration" -lt "$max_ms" ]]; then
        _pass "$image: shutdown in ${duration}ms (< ${max_ms}ms)"
    else
        _fail "$image: shutdown took ${duration}ms (expected < ${max_ms}ms)"
    fi
}

###############################################################################
# Summary
###############################################################################

print_test_summary() {
    printf '✅ %d assertion(s) passed.\n' "$TESTS_PASSED"
}
