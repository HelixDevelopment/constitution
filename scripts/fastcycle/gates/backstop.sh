#!/bin/sh
# backstop.sh - full uncached backstop lane, drift monitor, guard-freshness
# queue (SpecKit-004 "fast-dev-cycles", User Story 2; plan.md T-C10;
# tasks.md T077; FR-006, FR-022, SC-003). Guarded by
# constitution/scripts/fastcycle/tests/test_backstop_red.sh (T060).
#
# WHAT THIS TOOL IS (plan.md T-C10 Work line, verbatim): "gates/backstop.sh
# runs the full gate set and full mutation corpus with --no-cache and no
# selection: before every release tag, nightly when the fast lane ran that
# day, and on any change to the gate engine, I/O map or key definition;
# any verdict the full lane produces and the fast lane missed is a
# **drift**: release blocker, the offending gate marked `force-full` until
# re-traced. Also drains the SS11.4.226 guard-freshness queue (registered
# guards never executed on the current artifact) most-reopened-first
# (SS11.4.189), reusing SOL-09."
#
# TRIGGERS (documentation only -- fixtures/backstop/README.md's own "What
# this RED test does NOT cover" section explicitly scopes automated
# scheduling OUT of T060/T077: "The release-tag-time / nightly-on-main /
# gate-engine-change scheduling triggers DEC-17 names for WHEN the full
# lane runs ... this RED test covers only the COMPARISON + BLOCK
# behaviour ... both of which are agnostic to what triggered the run."
# No fixture or contract defines an automated scheduler; inventing an
# unverified one here would itself be a constitution SS11.4.6 guess.
# Wire this tool's `run` subcommand into the ACTUAL trigger points as a
# separate, later wiring task):
#   1. Before every release tag (scripts/testing/release_tag.sh /
#      scripts/lib/critical_blocker_gate.sh's own seam).
#   2. Nightly on `main`, but ONLY when the fast lane ran that day
#      (a cron/scheduled-agent concern, not this file's).
#   3. On any change to the gate engine, the I/O map, or the cache-key
#      definition (constitution/scripts/fastcycle/gates/gate_runner.sh,
#      io_trace.sh's build-map output, verdict_cache.py's DEC-07 key
#      formula).
#
# CLI (per fixtures/backstop/README.md, this RED test's own binding wire
# format -- no specs/004-fast-dev-cycles/contracts/*.md file exists for
# T-C10; confirmed absent by a real directory listing before writing this
# file, constitution SS11.4.6):
#
#   backstop.sh run --config <cfg> --manifest <gates.json> --no-cache
#       --out <full_verdicts.json> [--jobs N] [--host-guard <path>]
#     Runs EVERY gate in <gates.json> uncached, no --affected narrowing --
#     the ground-truth "slow but always-complete" pass. --manifest is an
#     honest addition beyond the README's documented flag set (see
#     lib/backstop_run.py's own "HONEST GAP" docstring section: no
#     existing config key enumerates individual gate scripts). NOT
#     exercised by test_backstop_red.sh (T060) -- see
#     fixtures/backstop/README.md "What this RED test does NOT cover".
#
#   backstop.sh compare --fast <fast_verdicts.json> --full <full_verdicts.json>
#       --out <drift.json> [--apply --map <gate_map.json>]
#       [--determinism-check]
#     DEC-17 drift = a gate_id whose FULL verdict is FAIL and whose FAST
#     verdict is anything other than FAIL (absent -- selection hole -- or
#     PASS/SKIP/BLIND -- stale/wrong verdict). Exit 0 + "NO_DRIFT" when
#     none found; exit 1 (block -- a drift IS a release blocker) + one
#     "DRIFT gate=<id> fast=<verdict|ABSENT> full=FAIL" line per drifting
#     gate + "DRIFT_COUNT=<n>" otherwise. --apply --map marks each
#     drifting gate's map entry `force_full: true` (data-model.md Section
#     3) until it is re-traced.
#
#   backstop.sh freshness-queue --registry <registry.json> --fingerprint <fp>
#       --out <queue.json> [--topology-in-scope <classes|@file>]
#       [--determinism-check]
#     Drains the SS11.4.226 guard-freshness queue (SOL-09 reused, see
#     lib/backstop_freshness.py's own docstring for the exact reuse
#     mapping): a guard is STALE (queued) iff its stored
#     last_verdict_fingerprint != <fp> (never-executed counts as stale); a
#     guard whose stored fingerprint MATCHES <fp> is FRESH and excluded
#     from the queue REGARDLESS of reopens_count. Queue order:
#     reopens_count descending (SS11.4.189 most-reopened-first) PRIMARY,
#     staleness descending SECONDARY. Exit 0 (an ordering emission, not a
#     pass/fail judgement); exit 4 (BLIND) when the registry is empty --
#     "no pressure is computable over nothing" (SOL-09).
#
# Exit codes (C-001, contracts/common-conventions.md): 0 clean/no-drift,
# 1 a finding (drift found, or a `run`/determinism-check FAIL), 2 usage/
# config error, 4 BLIND (a required input could not be read, or an
# empty registry/manifest -- no honest verdict is possible).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat >&2 <<'EOF'
Usage:
  backstop.sh run --config CFG --manifest GATES.json --no-cache --out OUT.json
                   [--jobs N] [--host-guard PATH]
  backstop.sh compare --fast FAST.json --full FULL.json --out DRIFT.json
                       [--apply --map MAP.json] [--determinism-check]
  backstop.sh freshness-queue --registry REG.json --fingerprint FP --out QUEUE.json
                               [--topology-in-scope CLASSES|@FILE] [--determinism-check]
EOF
}

_require_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "backstop.sh: python3 not found on PATH -- cannot run" >&2
        exit 2
    fi
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    run)
        shift
        _require_python3
        python3 "$HERE/lib/backstop_run.py" "$@"
        ;;
    compare)
        shift
        _require_python3
        python3 "$HERE/lib/backstop_compare.py" "$@"
        ;;
    freshness-queue)
        shift
        _require_python3
        python3 "$HERE/lib/backstop_freshness.py" "$@"
        ;;
    "")
        usage
        exit 2
        ;;
    *)
        echo "backstop.sh: unknown subcommand '$1'" >&2
        usage
        exit 2
        ;;
esac
