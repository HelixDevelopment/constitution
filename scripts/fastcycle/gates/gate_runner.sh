#!/bin/sh
# gate_runner.sh -- fail-fast history-cost gate ordering (T070, plan.md
# T-C04) + bounded parallel gate sharding (T071, plan.md T-C05) for
# SpecKit-004 "fast-dev-cycles", User Story 2 (SC-002, FR-018, FR-021).
#
# Guarded by:
#   constitution/scripts/fastcycle/tests/test_gate_order_red.sh (T054, the
#     ordering half, contract AS-013)
#   constitution/scripts/fastcycle/tests/test_gate_shard_red.sh (T055, the
#     sharding half, plan.md T-C05 -- no standalone contracts/*.md file
#     names this half; plan.md's own T-C05 section is authoritative)
#
# Contract: specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
#   AS-013 (ordering) / AS-014 (parallel sharding).
#
# =============================================================================
# MODE 1 (default, "verdicts" mode) -- T070, AS-013
# =============================================================================
#
#   gate_runner.sh --config <cfg> --affected <affected.json>
#                   [--order history-cost] [--no-cache] --out <verdicts.json>
#
# Orders (or not) the declared members of --affected by historical
# fail_rate/mean_cost read from --config's history_log (AS-013, DEC-10),
# runs EVERY member to completion regardless (AS-013: "ordering never
# removes a member and the final verdict set is identical with and
# without ordering"), and writes the verdicts/v1 document to --out.
# Delegates the real work to lib/gate_runner_order.py -- see that file's
# own header comment for the full design (config schema, the "fast lane
# stops at the first FAIL and reports" reading, output schema, the
# --no-cache scope gap). Exit 0 all PASS, 1 any FAIL, 4 any BLIND, 2 usage.
#
# =============================================================================
# MODE 2 ("--mode shard") -- T071, plan.md T-C05
# =============================================================================
#
#   gate_runner.sh --mode shard --manifest <manifest.json> --n-shards <N>
#
# Partitions --manifest's declared gates into shards such that "no shard
# writes what another reads" (plan.md line 812) -- two gates whose
# declared `writes` paths intersect are ALWAYS co-scheduled into the same
# shard (write-set-intersection union-find, lib/gate_runner_shard.py's own
# header comment has the full algorithm), and the tracker DB
# (docs/workable_items.db) / agent registry
# (docs/requests/agent_registry.jsonl) are additionally NEVER written by
# gates running in parallel (tasks.md T071's own text) -- any gate
# touching either path is forced into a dedicated shard that runs strictly
# AFTER the parallel batch, one at a time, never overlapping anything
# else.
#
# The REQUESTED --n-shards value is the PARTITION count (how many write-
# disjoint groups to carve the gate set into); the ACTUAL concurrency
# handed to `xargs -P` is a SEPARATE, HOST-CLAMPED value read from
# lib/host_guard.sh (nproc, §12.12 thread headroom, §12.6 memory ceiling --
# NEVER hardcoded, §12.11) -- a constrained host degrades to fewer
# concurrent shard-workers (down to strictly serial, `xargs -P 1`) without
# ever changing which gates land in which shard, and without ever raising
# a limit (C-007).
#
# stdout (on success): one JSON line per shard-run summary (shard index
# order), then a final line
#   VERDICT-SET <canonical_evidence_sha256> <sorted gate:VERDICT pairs,
#   space-joined>
# (lib/gate_runner_shard.py's `finalize` subcommand; canonical evidence
# hash formula = sha256(sorted "gate:VERDICT" lines, newline-joined), per
# tests/fixtures/gate_shard/README.md).
#
# Exit 0 iff EVERY declared gate produced a verdict and the VERDICT-SET
# line was emitted (regardless of any individual gate's own PASS/FAIL --
# a FAILing gate inside a successfully-completed run is NOT a
# gate_runner.sh failure); nonzero exit means the RUN ITSELF could not
# complete (a gate script genuinely absent/unresolvable, a manifest parse
# failure, or a crash) -- lib/gate_runner_shard.py's `finalize` names every
# gate that never produced a verdict on stderr in that case.
#
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)   # .../fastcycle/gates
FC=$(cd "$HERE/.." && pwd)            # .../fastcycle
ORDER_LIB="$HERE/lib/gate_runner_order.py"
SHARD_LIB="$HERE/lib/gate_runner_shard.py"
HOST_GUARD="$FC/lib/host_guard.sh"

usage() {
    cat >&2 <<'EOF'
Usage:
  gate_runner.sh --config <cfg> --affected <affected.json>
                  [--order history-cost] [--no-cache] --out <verdicts.json>
  gate_runner.sh --mode shard --manifest <manifest.json> --n-shards <N>
EOF
}

# ---- MODE 1: verdicts/ordering (T070) --------------------------------------
run_verdicts_mode() {
    if [ -z "${config:-}" ] || [ -z "${affected:-}" ] || [ -z "${out:-}" ]; then
        echo "gate_runner.sh: --config, --affected and --out are all required (default mode)" >&2
        usage
        exit 2
    fi
    if [ ! -f "$ORDER_LIB" ]; then
        echo "gate_runner.sh: internal error -- $ORDER_LIB not found" >&2
        exit 2
    fi

    set -- --config "$config" --affected "$affected" --out "$out"
    if [ -n "${order:-}" ]; then
        set -- "$@" --order "$order"
    fi
    if [ "${no_cache:-0}" = 1 ]; then
        set -- "$@" --no-cache
    fi
    python3 "$ORDER_LIB" "$@"
    exit $?
}

# ---- MODE 2: bounded parallel sharding (T071) ------------------------------
run_shard_mode() {
    if [ -z "${manifest:-}" ] || [ -z "${n_shards:-}" ]; then
        echo "gate_runner.sh: --manifest and --n-shards are both required (--mode shard)" >&2
        usage
        exit 2
    fi
    if [ ! -f "$manifest" ]; then
        echo "gate_runner.sh: --manifest file not found: $manifest" >&2
        exit 2
    fi
    case "$n_shards" in
        ''|*[!0-9]*)
            echo "gate_runner.sh: --n-shards must be a positive integer: $n_shards" >&2
            exit 2
            ;;
    esac
    if [ "$n_shards" -lt 1 ]; then
        echo "gate_runner.sh: --n-shards must be >= 1: $n_shards" >&2
        exit 2
    fi
    if [ ! -f "$SHARD_LIB" ]; then
        echo "gate_runner.sh: internal error -- $SHARD_LIB not found" >&2
        exit 2
    fi
    if ! command -v xargs >/dev/null 2>&1; then
        echo "gate_runner.sh: xargs not found on PATH -- required for --mode shard (plan.md T-C05)" >&2
        exit 2
    fi

    workdir=$(mktemp -d 2>/dev/null || mktemp -d -t gate_runner_shard)
    trap 'rm -rf "$workdir"' EXIT INT TERM

    if ! plan_err=$(python3 "$SHARD_LIB" plan --manifest "$manifest" --n-shards "$n_shards" --out-dir "$workdir" 2>&1 1>/dev/null); then
        echo "gate_runner.sh: shard planning failed: $plan_err" >&2
        exit 2
    fi

    parallel_idx=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(' '.join(str(i) for i in d['parallel_shards']))
" "$workdir/plan.json")
    serial_idx=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(' '.join(str(i) for i in d['serial_shards']))
" "$workdir/plan.json")

    # AS-014 / FR-018 / FR-021 / §12.11: the xargs -P concurrency level is
    # HOST-CLAMPED at run time, never hardcoded. The partition count
    # (--n-shards, above) is the requested granularity; host_guard.sh
    # clamps how many of those shard-jobs may genuinely run concurrently
    # (nproc, §12.12 thread headroom, §12.6 memory ceiling) and degrades by
    # serialising (down to N=1) with a named reason, never by raising a
    # limit (C-007).
    guard_out=$(sh "$HOST_GUARD" "$n_shards" --kind jobs 2>&1)
    guard_rc=$?
    if [ "$guard_rc" -ne 0 ]; then
        echo "gate_runner.sh: host_guard.sh failed (rc=$guard_rc): $guard_out" >&2
        exit 2
    fi
    xargs_p=$(printf '%s\n' "$guard_out" | sed -n 's/^N=//p')
    case "$xargs_p" in
        ''|*[!0-9]*) xargs_p=1 ;;
    esac
    if [ "$xargs_p" -lt 1 ]; then
        xargs_p=1
    fi

    if [ -n "$parallel_idx" ]; then
        # shellcheck disable=SC2086 -- deliberate word-splitting: one
        # shard index per xargs -I{} invocation.
        printf '%s\n' $parallel_idx | xargs -P "$xargs_p" -I{} python3 "$SHARD_LIB" run-shard \
            --manifest "$manifest" --shard-file "$workdir/shard_{}.json" --out "$workdir/result_{}.json"
    fi

    # Tracker-DB/registry-protected shards: run strictly AFTER the
    # parallel batch, one at a time, never overlapping with anything else
    # (tasks.md T071: "tracker DB and registry never written by gates
    # running in parallel").
    for i in $serial_idx; do
        python3 "$SHARD_LIB" run-shard \
            --manifest "$manifest" --shard-file "$workdir/shard_$i.json" --out "$workdir/result_$i.json"
    done

    python3 "$SHARD_LIB" finalize --result-dir "$workdir"
    exit $?
}

# ---- argument parsing + dispatch -------------------------------------------
mode="verdicts"
config=""
affected=""
order=""
no_cache=0
out=""
manifest=""
n_shards=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --mode requires a value" >&2; exit 2; }
            mode="$2"; shift 2 ;;
        --config)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --config requires a value" >&2; exit 2; }
            config="$2"; shift 2 ;;
        --affected)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --affected requires a value" >&2; exit 2; }
            affected="$2"; shift 2 ;;
        --order)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --order requires a value" >&2; exit 2; }
            order="$2"; shift 2 ;;
        --no-cache)
            no_cache=1; shift ;;
        --out)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --out requires a value" >&2; exit 2; }
            out="$2"; shift 2 ;;
        --manifest)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --manifest requires a value" >&2; exit 2; }
            manifest="$2"; shift 2 ;;
        --n-shards)
            [ $# -ge 2 ] || { echo "gate_runner.sh: --n-shards requires a value" >&2; exit 2; }
            n_shards="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "gate_runner.sh: unknown argument: $1" >&2
            usage
            exit 2 ;;
    esac
done

case "$mode" in
    shard)
        run_shard_mode
        ;;
    verdicts)
        run_verdicts_mode
        ;;
    *)
        echo "gate_runner.sh: --mode must be 'shard' (omit --mode for the default verdicts/ordering mode): $mode" >&2
        exit 2
        ;;
esac
