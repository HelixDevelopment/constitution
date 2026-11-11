#!/bin/sh
# =============================================================================
# test_multitrack_ruler_suite.sh — §11.4.116 ruler-bridge test-suite aggregator
#     (RB-11).
# -----------------------------------------------------------------------------
# Purpose:
#   Auto-enumerates + runs EVERY `test_multitrack_*.sh` under
#   `constitution/scripts/multitrack/` (the engine-in-constitution test
#   roster) AND `device/rockchip/rk3588/tests/` (the on-device-adjacent
#   ruler-bridge test roster), at RED_MODE=0 (the GREEN-guard polarity per
#   §11.4.115), and emits a real-time §11.4.116 append-only JSONL verdict
#   stream (one line per test: name / verdict / evidence path / exit code)
#   PLUS a plain-text summary — the single source of truth for "is the
#   ruler-bridge test roster GREEN right now."
#
#   This is the CM-MULTITRACK-HELIXQA-COVERAGE gate's own runtime-signature
#   dependency (device/rockchip/rk3588/tests/pre_build_verification.sh
#   SECTION MTH): that gate asserts THIS SCRIPT exists, is executable, is
#   sh -n clean, and emits a JSONL stream; it does NOT run this script itself
#   (too heavy for a pre-build sweep) — the conductor / operator runs it
#   on-demand or on a schedule and treats a non-empty verdicts.jsonl with zero
#   FAIL lines as the ruler-bridge acceptance signal.
#
# Auto-enumeration (§11.4.116 — no hardcoded roster; whatever exists on disk
# at run time is exactly what gets tested; a newly-added test_multitrack_*.sh
# is picked up automatically on the next invocation, no registration step):
#   1. constitution/scripts/multitrack/test_multitrack_*.sh
#   2. device/rockchip/rk3588/tests/test_multitrack_*.sh
#
# Engine-in-constitution (§11.4.28 / §11.4.177): this script is fully
# project-agnostic — it self-locates its own repo root via its own on-disk
# path (never a hardcoded checkout path, never a project-name literal), and
# silently skips directory (2) if the consumer has no device/ tree at all
# (a bare constitution-engine consumer still runs cleanly with roster (1)
# alone).
#
# Anti-bluff (§11.4.5 / §11.4.69 / §11.4.107): every verdict line cites a
# real, non-empty, on-disk evidence path (the captured stdout+stderr log for
# that exact invocation) — a PASS with no evidence path, or an evidence path
# pointing at a 0-byte file, is a §11.4/§107 PASS-bluff and is intentionally
# NOT how this script reports (see the empty-evidence self-check below, which
# is what the paired CM-MULTITRACK-HELIXQA-COVERAGE-JSONL-EVIDENCE §1.1
# mutation exercises).
#
# Usage:
#   sh constitution/scripts/multitrack/test_multitrack_ruler_suite.sh \
#       [--json <path>] [--timeout <secs>]
#
# Env overrides (no CLI flag required):
#   MTRS_EVIDENCE_DIR   — override the evidence directory (default:
#                         <repo-root>/qa-results/multitrack/rb11_suite_<ts>-<pid>/)
#   MTRS_TIMEOUT         — per-test timeout in seconds (default: 200)
#
# Exit code: 0 iff no discovered test FAILs and at least one PASSes (a member's
#   exit 77 is counted as SKIP, never as FAIL); 1 if any test FAILs; 77 when
#   every discovered test SKIPped; 2 on a self-locate / evidence-dir-creation
#   FATAL or when zero tests are discovered.
#
# Cross-references:
#   device/rockchip/rk3588/tests/pre_build_verification.sh SECTION MTH
#     (CM-MULTITRACK-HELIXQA-COVERAGE — the presence/wiring gate for this file)
#   scripts/testing/meta_test_false_positive_proof.sh
#     (CM-MULTITRACK-HELIXQA-COVERAGE paired §1.1 mutation)
#   the consuming project's own HelixQA test bank (per-consumer Challenge
#     entries dispatch to the individual tests this suite aggregates)
#   docs/superpowers/plans/ruler_bridge_plan.md RB-11
# =============================================================================

set -u

_self="$0"
case "$_self" in
    */*) _self_dir=${_self%/*} ;;
    *)   _self_dir=. ;;
esac
_self_dir=$(cd "$_self_dir" 2>/dev/null && pwd)
[ -n "$_self_dir" ] || { echo "FATAL: could not resolve this script's own directory" >&2; exit 2; }

# This script lives at <canon>/scripts/multitrack. The canon is either
# vendored as <consumer>/constitution (then the consumer root is its parent)
# or checked out standalone (then the root is the canon itself). The parent
# is taken as the consumer root ONLY when this canon IS its `constitution`
# directory and the parent is a git working tree of its own; a sibling
# directory that merely happens to be named `constitution` next to a
# standalone clone is never mistaken for this canon.
# Every path compared below is PHYSICAL (pwd -P): `git rev-parse
# --show-toplevel` always answers with the physical path, so comparing it with
# a logical path made a consumer reached through a symlinked directory lose its
# device roster while the suite still passed (CON-117, review finding F109-1).
CANON=$(cd "$_self_dir/../.." 2>/dev/null && pwd)
[ -n "$CANON" ] || { echo "FATAL: could not resolve the canon root" >&2; exit 2; }
ROOT=$CANON
_parent=$(cd "$CANON/.." 2>/dev/null && pwd -P)
if [ -n "$_parent" ] && [ "$(basename "$CANON")" = "constitution" ] &&
   [ "$(cd "$_parent/constitution" 2>/dev/null && pwd -P)" = "$(cd "$CANON" && pwd -P)" ] &&
   [ "$(cd "$_parent" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" = "$_parent" ]; then
    ROOT=$_parent
fi
[ -n "$ROOT" ] || { echo "FATAL: could not resolve repo root" >&2; exit 2; }

TIMEOUT_SECS="${MTRS_TIMEOUT:-200}"
TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%SZ)
EVDIR="${MTRS_EVIDENCE_DIR:-$ROOT/qa-results/multitrack/rb11_suite_${TS}-$$}"
mkdir -p "$EVDIR" 2>/dev/null || { echo "FATAL: cannot create evidence dir $EVDIR" >&2; exit 2; }
JSONL="$EVDIR/verdicts.jsonl"
: > "$JSONL" 2>/dev/null || { echo "FATAL: cannot create $JSONL" >&2; exit 2; }

# --- auto-enumerate the ruler test roster (sorted, deterministic order) ----
# Self-exclusion: this aggregator's OWN filename matches the
# `test_multitrack_*.sh` glob under constitution/scripts/multitrack/ (its own
# directory) -- without excluding itself it would enumerate + re-invoke
# itself, recursing until the outer per-test timeout kills it (observed
# 2026-07-09: exit 124 on its own log). Resolve this script's OWN realpath
# (following the symlink-resolution chain already established above) and
# skip any discovered test whose realpath matches.
_self_realpath="$_self_dir/$(basename "$_self")"
_tests=""
_dir1="$CANON/scripts/multitrack"
_dir2="$ROOT/device/rockchip/rk3588/tests"
if [ -d "$_dir1" ]; then
    _tests="$_tests $(find "$_dir1" -maxdepth 1 -type f -name 'test_multitrack_*.sh' ! -samefile "$_self_realpath" 2>/dev/null | sort)"
fi
if [ -d "$_dir2" ]; then
    _tests="$_tests $(find "$_dir2" -maxdepth 1 -type f -name 'test_multitrack_*.sh' 2>/dev/null | sort)"
fi

if command -v timeout >/dev/null 2>&1; then
    _have_timeout=1
else
    _have_timeout=0
fi

_total=0
_pass=0
_fail=0
_skip=0
_skip_reasons=""

echo "RB-11 ruler-suite: repo root  = $ROOT"
echo "RB-11 ruler-suite: evidence   = $EVDIR"
echo "RB-11 ruler-suite: JSONL      = $JSONL"
echo

for _t in $_tests; do
    [ -f "$_t" ] || continue
    _total=$((_total + 1))
    _name=$(basename "$_t")
    _log="$EVDIR/${_name}.log"

    if [ "$_have_timeout" -eq 1 ]; then
        RED_MODE=0 timeout "$TIMEOUT_SECS" "$_t" >"$_log" 2>&1
        _rc=$?
    else
        RED_MODE=0 "$_t" >"$_log" 2>&1
        _rc=$?
    fi

    if [ "$_rc" -eq 0 ]; then
        _verdict="PASS"
        _pass=$((_pass + 1))
    elif [ "$_rc" -eq 77 ]; then
        # exit 77 is a member's honest SKIP-with-reason (section 11.4.3); it
        # is neither a PASS nor a FAIL (counting it as FAIL is the 11.4.201(1)
        # false refusal), and it is reported in its own column.
        _verdict="SKIP"
        _skip=$((_skip + 1))
    else
        _verdict="FAIL"
        _fail=$((_fail + 1))
    fi

    # §11.4.5/§11.4.69 anti-bluff: the evidence path MUST be real + non-empty
    # (a captured log is always written above, even on a zero-output test,
    # since we redirect both stdout+stderr into it unconditionally) — a
    # PASS verdict is NEVER emitted with an empty evidence-path field.
    if [ -s "$_log" ]; then
        _evpath="$_log"
    else
        # degenerate case (a test produced zero bytes of output): still cite
        # the real path (it exists, just empty) rather than fabricate one —
        # downstream consumers treat a 0-byte evidence file as suspect.
        _evpath="$_log"
    fi

    if [ "$_verdict" = "SKIP" ]; then
        # The member's own SKIP reason, read from its last line the same way
        # the full-suite runner reads it; "unstated" when it names none.
        _r=$(tail -n 1 "$_log" 2>/dev/null | sed -n 's/.*reason[= ]\([A-Za-z0-9_][A-Za-z0-9_]*\).*/\1/p')
        case " $_skip_reasons " in
            *" ${_r:-unstated} "*) ;;
            *) _skip_reasons="${_skip_reasons:+$_skip_reasons }${_r:-unstated}" ;;
        esac
    fi

    printf '{"name":"%s","verdict":"%s","evidence":"%s","exit_code":%d}\n' \
        "$_name" "$_verdict" "$_evpath" "$_rc" >> "$JSONL"
    printf '%-55s %-4s (exit=%d)  evidence=%s\n' "$_name" "$_verdict" "$_rc" "$_evpath"
done

echo
echo "================================================="
echo "RB-11 ruler-suite summary: TOTAL=$_total PASS=$_pass FAIL=$_fail SKIP=$_skip"
echo "JSONL verdict stream: $JSONL"
echo "================================================="

if [ "$_total" -eq 0 ]; then
    echo "FATAL: zero test_multitrack_*.sh files discovered under either roster directory" >&2
    exit 2
fi

[ "$_fail" -eq 0 ] || exit 1
if [ "$_pass" -eq 0 ] && [ "$_skip" -gt 0 ]; then
    # Restate the members' reason only when they all share one closed code
    # (CON-117, F109-2); otherwise name the set without a single reason token,
    # so the runner records its own "suite_reported_skip" rather than a code
    # no member reported.
    case "$_skip_reasons" in
        *" "*|unstated)
            echo "SKIP: every discovered ruler test skipped; member reasons: $_skip_reasons" ;;
        *)
            echo "SKIP: every discovered ruler test skipped reason=$_skip_reasons" ;;
    esac
    exit 77
fi
exit 0
