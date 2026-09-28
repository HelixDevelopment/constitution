#!/bin/sh
# io_trace.sh - observed-I/O capture + gate->inputs map build (spec-004
# "fast-dev-cycles", plan.md T-C02; tasks.md T066; FR-005, FR-007).
# Guarded by constitution/scripts/fastcycle/tests/test_io_trace_red.sh
# (T052).
#
# CLI contract (per fixtures/io_trace/README.md, the RED test's own binding
# definition -- no contracts/ file names this tool, so this file is the
# source of truth alongside the README):
#
#   io_trace.sh <gate-script> [gate-args...]        # bare form == trace
#   io_trace.sh trace <gate-script> [gate-args...]   # explicit trace
#   io_trace.sh build-map [--sections-dir DIR] [--db PATH]
#
# trace: runs <gate-script> [gate-args...] under
#   `strace -f -e trace=openat,stat,newfstatat,lstat,execve` in this
#   process's own (already-clean, per the RED test fixtures) checkout,
#   parses the raw strace log for every observed openat/stat-family syscall
#   PATH ARGUMENT (never source-scanned -- the syscall layer only ever sees
#   the path AFTER shell expansion, which is the whole point per the golden-
#   bad fixture: a dynamically-built path must resolve, never a literal
#   template string), classifies each as a read or write from the openat
#   flags argument (O_WRONLY/O_RDWR/O_CREAT -> write; else read; a stat-
#   family call is always a read -- deciding on file existence IS an input,
#   per plan.md's own paired-mutation note "a gate that decides on file
#   existence loses an input"), filters out dynamic-linker/libc/proc/dev/
#   etc-config noise the traced `sh` interpreter's own startup also emits
#   (own_dir_only_gate.sh's exact-set fixture requires this -- a tracer
#   that leaks library noise into its reported set is a §11.4.201(1)
#   false-positive on the tracer itself), and emits exactly ONE JSON object
#   on stdout: {"reads": [...], "writes": [...]}. Exit 0 on a successful
#   TRACE regardless of the traced gate's own exit code (the tracer's job
#   is to observe, not to judge the gate); nonzero only on a tracer-level
#   failure (gate script missing/unreadable, strace unavailable, python3
#   unavailable).
#
# build-map: iterates every *.sh gate script under --sections-dir (default:
#   device/rockchip/rk3588/tests, this project's pre-build-section home),
#   computes each script's content sha256, and re-traces ONLY a script
#   whose hash differs from (or is absent from) the persisted map at --db
#   (default: .cache/fastcycle/io_map.sqlite) -- "re-traces a gate whenever
#   its script hash changes and fully on the backstop" per plan.md T-C02's
#   Work line. Prints a declared-vs-traced report: this project does not
#   yet ship a separate "declared inputs" source for gate scripts (no
#   T-C02-adjacent task has landed one as of this writing), so the report
#   HONESTLY states that (§11.4.6 -- no fabricated comparison) rather than
#   inventing a declared set to diff against; it is a traced-only summary
#   until such a source exists. build-map is NOT gated by T052's RED test
#   (fixtures/io_trace/README.md's own "What this RED test does NOT cover"
#   section explicitly defers the caching/scheduling behaviour) -- this is
#   a genuine, functional implementation of the task's stated design,
#   scoped honestly where a dependency is missing.
#
# Noise-filter list (§11.4.6 -- a documented, reviewable heuristic, not an
# unstated guess): dynamic linker / shared-library / kernel-pseudo-fs /
# device paths a traced `sh`+gate-script pair opens as normal interpreter
# startup, never a gate's own declared input:
#   /lib/  /lib64/  /usr/lib/  /etc/ld.so.cache  /etc/ld.so.preload
#   /proc/  /dev/  /sys/  /etc/nsswitch.conf  /etc/localtime
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat >&2 <<'EOF'
Usage:
  io_trace.sh <gate-script> [gate-args...]
  io_trace.sh trace <gate-script> [gate-args...]
  io_trace.sh build-map [--sections-dir DIR] [--db PATH]
EOF
}

# _require_strace_and_python3: tracer-level precondition, exit 2 (never 0/1
# -- this is a tool-cannot-run failure, distinct from a trace producing an
# empty/partial result) when either dependency is absent.
_require_strace_and_python3() {
    if ! command -v strace >/dev/null 2>&1; then
        echo "io_trace.sh: strace not found on PATH -- cannot trace (tracer-level failure)" >&2
        exit 2
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "io_trace.sh: python3 not found on PATH -- cannot parse the strace log (tracer-level failure)" >&2
        exit 2
    fi
}

# do_trace <gate-script> [gate-args...]
do_trace() {
    gate_script="${1:-}"
    if [ -z "$gate_script" ]; then
        echo "io_trace.sh trace: a <gate-script> path is required (tracer-level failure)" >&2
        exit 2
    fi
    if [ ! -f "$gate_script" ]; then
        echo "io_trace.sh trace: gate script not found: $gate_script (tracer-level failure)" >&2
        exit 2
    fi
    shift
    _require_strace_and_python3

    _log=$(mktemp)
    trap 'rm -f "$_log"' EXIT
    # The gate's own stdout/stderr are discarded -- the tracer only
    # observes I/O, it never judges or surfaces the gate's own output/exit
    # code (README: "regardless of the traced gate's own exit code").
    strace -f -e trace=openat,stat,newfstatat,lstat,execve \
        -o "$_log" sh "$gate_script" "$@" >/dev/null 2>&1 || true

    if [ ! -s "$_log" ]; then
        echo "io_trace.sh trace: strace produced no output for $gate_script (tracer-level failure)" >&2
        exit 2
    fi

    python3 "$HERE/lib/io_trace_parse.py" "$_log"
}

# do_build_map [--sections-dir DIR] [--db PATH]
do_build_map() {
    sections_dir="device/rockchip/rk3588/tests"
    db_path=".cache/fastcycle/io_map.sqlite"
    while [ $# -gt 0 ]; do
        case "$1" in
            --sections-dir) sections_dir="$2"; shift 2 ;;
            --db)           db_path="$2"; shift 2 ;;
            *) echo "io_trace.sh build-map: unknown option $1" >&2; exit 2 ;;
        esac
    done
    _require_strace_and_python3
    python3 "$HERE/lib/io_trace_build_map.py" \
        --sections-dir "$sections_dir" \
        --db "$db_path" \
        --tool "$0"
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    build-map) shift; do_build_map "$@" ;;
    trace)     shift; do_trace "$@" ;;
    "")        usage; exit 2 ;;
    *)         do_trace "$@" ;;
esac
