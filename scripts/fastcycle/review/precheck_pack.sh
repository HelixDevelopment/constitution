#!/bin/sh
# precheck_pack.sh - machine pre-check pack (DEC-33) on a clean checkout
# (spec-004 "fast-dev-cycles", plan.md T-C11; tasks.md T078; FR-023,
# SC-009, SC-002). Guarded by
# constitution/scripts/fastcycle/tests/test_precheck_slicer_red.sh (T061),
# per contract specs/004-fast-dev-cycles/contracts/review-batch-and-
# precheck.md (RB-002) and data-model.md #10.3 PreCheckReport.
#
# CLI (contract "Invocations", verbatim):
#   precheck_pack.sh --config <cfg> --batch <batch.json>
#                     --clean-checkout <dir> --out <precheck.json>
#                     [--determinism-check]
#
# This is a thin sh dispatcher (house pattern: gates/io_trace.sh ->
# gates/lib/io_trace_parse.py) -- argument parsing + preconditions only;
# the real 10-check DEC-33 implementation lives in
# review/lib/precheck_pack_run.py, invoked once preconditions hold.
#
# --config is accepted and passed through but NOT required to be a
# fastcycle.yaml file: T061's own RED test invokes this tool with
# --config pointing at a plain fixture DIRECTORY
# (fixtures/precheck_slicer/case2_lint_in_pack/), not a YAML file --
# UNCONFIRMED by the contract beyond "--config <cfg>" and not narrowed
# here (constitution 11.4.6: never invent a schema the contract does not
# state). The checks this revision implements (see lib/precheck_pack_run.py
# module docstring for the full per-check honest-scope breakdown) read
# their inputs from --batch and --clean-checkout only, so an unusable
# --config value never blocks a real run.
#
# Exit codes (contract "Exit codes"): 0 all pass; 1 any check FAILs;
# 2 usage/configuration error (missing/unreadable --batch, bad args);
# 4 clean checkout unavailable (--clean-checkout missing or not a
# directory -- the ONE clause the contract states explicitly for this
# tool, kept distinct from the generic 2 above).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

CONFIG=""
BATCH=""
CLEAN_CHECKOUT=""
OUT=""
DETERMINISM_CHECK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --config requires a value" >&2; exit 2; }
            CONFIG="$2"; shift 2 ;;
        --batch)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --batch requires a value" >&2; exit 2; }
            BATCH="$2"; shift 2 ;;
        --clean-checkout)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --clean-checkout requires a value" >&2; exit 2; }
            CLEAN_CHECKOUT="$2"; shift 2 ;;
        --out)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --out requires a value" >&2; exit 2; }
            OUT="$2"; shift 2 ;;
        --determinism-check)
            DETERMINISM_CHECK=1; shift ;;
        *)
            echo "precheck_pack.sh: unknown option: $1" >&2
            exit 2 ;;
    esac
done

if [ -z "$BATCH" ] || [ -z "$CLEAN_CHECKOUT" ] || [ -z "$OUT" ]; then
    echo "precheck_pack.sh: --batch, --clean-checkout and --out are all required" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "precheck_pack.sh: python3 not found on PATH -- cannot run the DEC-33 pack" >&2
    exit 2
fi

if [ ! -f "$BATCH" ]; then
    echo "precheck_pack.sh: --batch not found or not a file: $BATCH" >&2
    exit 2
fi

# The ONE clause the contract states explicitly by exit code (4): a
# clean-checkout that does not exist or is not a directory is an
# unavailability, never a plain usage error.
if [ ! -d "$CLEAN_CHECKOUT" ]; then
    echo "precheck_pack.sh: --clean-checkout is unavailable (not a readable directory): $CLEAN_CHECKOUT" >&2
    exit 4
fi

if [ -n "$CONFIG" ]; then
    if [ "$DETERMINISM_CHECK" -eq 1 ]; then
        exec python3 "$HERE/lib/precheck_pack_run.py" --config "$CONFIG" --batch "$BATCH" \
            --clean-checkout "$CLEAN_CHECKOUT" --out "$OUT" --determinism-check
    fi
    exec python3 "$HERE/lib/precheck_pack_run.py" --config "$CONFIG" --batch "$BATCH" \
        --clean-checkout "$CLEAN_CHECKOUT" --out "$OUT"
fi

if [ "$DETERMINISM_CHECK" -eq 1 ]; then
    exec python3 "$HERE/lib/precheck_pack_run.py" --batch "$BATCH" \
        --clean-checkout "$CLEAN_CHECKOUT" --out "$OUT" --determinism-check
fi
exec python3 "$HERE/lib/precheck_pack_run.py" --batch "$BATCH" \
    --clean-checkout "$CLEAN_CHECKOUT" --out "$OUT"
