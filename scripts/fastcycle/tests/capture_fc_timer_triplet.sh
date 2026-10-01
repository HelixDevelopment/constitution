#!/bin/bash
# capture_fc_timer_triplet.sh -- PRODUCES the only evidence shape
# test_fc_timer_golden_output.sh accepts for its real FR-002/T-A01 comparison:
# a same-run TRIPLET of pre_build_verification.sh captures with a provenance
# manifest. (spec 004-fast-dev-cycles T015/T048; plan.md T-A01.)
#
# Why this exists (T048 round-5 review, S11.4.250 heuristic-tower finding):
# rounds 1-5 kept adding pairing/classification heuristics to the golden test
# so it could auto-discover HISTORICAL, NON-CONCURRENT captures of a drifting,
# flaky suite and try to compare them. Each heuristic compensated for that one
# primitive defect. Round 6 removes the primitive: the golden test no longer
# pairs anything. It REQUIRES a triplet this harness produced -- FC0a + FC0b
# (two runs WITHOUT timers; their own diff is the noise floor) and FC1 (one run
# WITH timers) -- all launched under ONE run-id against the SAME tree in the
# SAME time window, which is the round-4 reviewer's own manual method made
# mechanical.
#
# CONCURRENT by default (all three members start together), exactly the
# reviewer's method: every member sees the same evolving shared tree at the
# same moments, so ordinary concurrent-checkout drift lands in FC0a, FC0b and
# FC1 alike and is visible in the FC0a-vs-FC0b noise floor. --sequential runs
# them one after another instead (roughly 3x the wall-clock, which with the
# golden test's default 3600 s window will usually be REFUSED there -- honest,
# because a sequential triplet is not same-window). pre_build_verification.sh
# is a read-only source/tree check; the round-4 reviewer ran three of them
# concurrently on this host without contention.
#
# PROVENANCE (fixes T048 round-5 minor m3 at the source, not by filename
# trust): each member gets its OWN fc_timer run-id via FC_TIMER_RUN_ID, so its
# own section TSV lands at an EXACT, member-unique path
# (<tsv-root>/<FC_TIMER_RUN_ID>/prebuild_sections.tsv -- pre_build_verification
# .sh derives FC_TIMER_TSV from fc_timer_run_id, which honours FC_TIMER_RUN_ID).
# After the member finishes, this harness counts that exact file's data rows:
# a genuine timers-ON run (FC1) must have > 0, a genuine timers-OFF run (FC0a,
# FC0b) must have 0. No proximity matching, no filename inference. The golden
# test re-counts the same exact paths and refuses on any contradiction.
#
# OUTPUT (all in --out-dir, default qa-results/fastcycle/us1/red/T015):
#   <PREFIX>_FC0a_<RUN_ID>.log   <PREFIX>_FC0b_<RUN_ID>.log   <PREFIX>_FC1_<RUN_ID>.log
#   <PREFIX>_<RUN_ID>.triplet    -- key=value manifest, written ATOMICALLY and
#                                   LAST, so its presence means all three
#                                   members finished; a killed run leaves no
#                                   manifest and is never consumed.
# Manifest keys: format, run_id, prefix, mode (real|stand-in), concurrency,
#   tmpdir_isolation (per-member), started_epoch, finished_epoch, tree_head_start/_end,
#   tree_status_sha256_start/_end, and per member M in FC0a FC0b FC1:
#   member.M.log, member.M.log_sha256, member.M.fc_timing, member.M.exit,
#   member.M.started_epoch, member.M.finished_epoch, member.M.tsv,
#   member.M.tsv_rows.
#
# Usage: bash capture_fc_timer_triplet.sh [--prefix NAME] [--out-dir DIR] [--sequential]
# Env:
#   CAPTURE_TRIPLET_PREFIX   filename prefix, [A-Za-z0-9-]+ (default "triplet")
#   CAPTURE_TRIPLET_OUT_DIR  output directory
#   CAPTURE_TRIPLET_RUN_ID   pin the run-id (YYYYMMDDTHHMMSSZ); default: minted once, now
#   CAPTURE_TRIPLET_PREBUILD path of the script to run instead of the real
#                            pre_build_verification.sh. ANY override records
#                            mode=stand-in in the manifest, and the golden test's
#                            auto-discovery ignores stand-in manifests -- a
#                            stand-in capture can never pass as real evidence
#                            (S11.4.6). Used by this harness's own tests.
#   CAPTURE_TRIPLET_TSV_ROOT root under which fc_timer writes <run-id>/prebuild_sections.tsv
#                            (default <repo>/qa-results/fastcycle, which is where
#                            the real pre_build_verification.sh writes it)
#
# Host safety (S12 / S12.11): a real (non-stand-in) capture calls
# host_check_safety first and aborts on refusal.
#
# Producer != Verifier (S11.4.240): this harness produces evidence only. The
# golden test, run separately, is the verifier.
#
# PER-MEMBER TMPDIR ISOLATION (T048 round 7, finding R6-B1 root cause): each
# member runs with its OWN private, empty TMPDIR (<work>/tmp.<member>), and the
# manifest records tmpdir_isolation=per-member. Measured, not assumed: at least
# two sub-tests pre_build_verification.sh runs keep their evidence in a FIXED
# ${TMPDIR}/<name> directory (test_stress_chaos_oracles_selfcheck.sh -> $TMPDIR/
# sc_oracles_selfcheck, which it rm -rf's at start; test_subtitle_denylist_
# parity_unit.sh -> $TMPDIR/sub_parity_evidence). Two copies running at the
# same moment with a SHARED TMPDIR failed 6/8 and 7/8 paired trials; with
# separate TMPDIRs 0/8 and 0/8. In a concurrent triplet FC0a and FC0b run the
# same code at the same speed, so they reach those sub-tests together and
# clobber each other (BOTH get CM-ATM352-OCRW-SOURCE / CM-SC-COVERAGE-1215-FIXES
# ERROR), while FC1 -- slower by its timing overhead -- reaches them at a
# different moment and passes. Because the twins fail IDENTICALLY, their
# FC0a-vs-FC0b noise floor was structurally blind to it, and the collision
# surfaced as a false "verdict flip caused by timers". Isolating TMPDIR removes
# that cross-member channel (and any collision with other users of the shared
# TMPDIR on this host). The golden test refuses a CONCURRENT triplet whose
# manifest does not record per-member isolation.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
REAL_PREBUILD="$ROOT/device/rockchip/rk3588/tests/pre_build_verification.sh"
PREBUILD="${CAPTURE_TRIPLET_PREBUILD:-$REAL_PREBUILD}"
OUT_DIR="${CAPTURE_TRIPLET_OUT_DIR:-$ROOT/qa-results/fastcycle/us1/red/T015}"
PREFIX="${CAPTURE_TRIPLET_PREFIX:-triplet}"
TSV_ROOT="${CAPTURE_TRIPLET_TSV_ROOT:-$ROOT/qa-results/fastcycle}"
CONCURRENCY=concurrent

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix requires a value}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:?--out-dir requires a value}"; shift 2 ;;
    --sequential) CONCURRENCY=sequential; shift ;;
    *) echo "FATAL: unrecognised argument: $1" >&2; exit 2 ;;
  esac
done

# The golden test splits filenames on "_FC0a_"/"_FC0b_"/"_FC1_" and on the
# run-id, so the prefix must be a plain token.
if ! printf '%s' "$PREFIX" | grep -qE '^[A-Za-z0-9-]+$'; then
  echo "FATAL: prefix '$PREFIX' must match [A-Za-z0-9-]+" >&2; exit 2
fi
if [ ! -f "$PREBUILD" ]; then
  echo "FATAL: pre-build script not found: $PREBUILD" >&2; exit 2
fi
MODE=real
[ "$PREBUILD" = "$REAL_PREBUILD" ] || MODE=stand-in

if [ "$MODE" = real ]; then
  HOST_SAFETY_LIB="$ROOT/scripts/lib/host_session_safety.sh"
  if [ -f "$HOST_SAFETY_LIB" ]; then
    # shellcheck source=/dev/null
    . "$HOST_SAFETY_LIB"
    if command -v host_check_safety >/dev/null 2>&1 && ! host_check_safety; then
      echo "FATAL: host_check_safety refused -- not starting 3 real pre_build_verification.sh runs" >&2
      exit 3
    fi
  else
    echo "WARN: $HOST_SAFETY_LIB not found -- no host-safety gate available" >&2
  fi
fi

RUN_ID="${CAPTURE_TRIPLET_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
if ! printf '%s' "$RUN_ID" | grep -qE '^[0-9]{8}T[0-9]{6}Z$'; then
  echo "FATAL: run-id '$RUN_ID' must match YYYYMMDDTHHMMSSZ" >&2; exit 2
fi
mkdir -p "$OUT_DIR" || { echo "FATAL: could not create $OUT_DIR" >&2; exit 2; }
MANIFEST="$OUT_DIR/${PREFIX}_${RUN_ID}.triplet"
if [ -e "$MANIFEST" ]; then
  echo "FATAL: $MANIFEST already exists -- refusing to overwrite evidence" >&2; exit 2
fi

_tree_head() { git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo UNKNOWN; }
_tree_status_sha() {
  git -C "$ROOT" status --porcelain=v1 --ignore-submodules=all -uno 2>/dev/null | sha256sum | awk '{print $1}'
}

MEMBERS="FC0a FC0b FC1"
_timing_of() { case "$1" in FC1) echo 1 ;; *) echo 0 ;; esac; }

echo "INFO: run-id $RUN_ID (minted once, shared by all 3 members), mode=$MODE, $CONCURRENCY"
echo "INFO: pre-build script: $PREBUILD"
echo "INFO: output: $OUT_DIR"

TREE_HEAD_START="$(_tree_head)"
TREE_STATUS_START="$(_tree_status_sha)"
STARTED_EPOCH="$(date -u +%s)"

WORK="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# _run_member M -- runs one member, writing its log, and records its own
# start/end/exit into $WORK/M.* (read back after all members finish).
_run_member() {
  local m="$1" timing fc_id log
  timing="$(_timing_of "$m")"
  fc_id="${RUN_ID}_${PREFIX}_${m}"
  log="$OUT_DIR/${PREFIX}_${m}_${RUN_ID}.log"
  mkdir -p "$WORK/tmp.$m" || { echo "FATAL: cannot create private TMPDIR for $m" >&2; echo 2 > "$WORK/$m.exit"; return; }
  date -u +%s > "$WORK/$m.started"
  TMPDIR="$WORK/tmp.$m" FC_TIMING="$timing" FC_TIMER_RUN_ID="$fc_id" CAPTURE_TRIPLET_TSV_ROOT="$TSV_ROOT" \
    bash "$PREBUILD" > "$log" 2>&1
  echo "$?" > "$WORK/$m.exit"
  date -u +%s > "$WORK/$m.finished"
}

PIDS=""
for m in $MEMBERS; do
  if [ "$CONCURRENCY" = concurrent ]; then
    _run_member "$m" &
    PIDS="$PIDS $!"
  else
    _run_member "$m"
  fi
done
for p in $PIDS; do wait "$p"; done

FINISHED_EPOCH="$(date -u +%s)"
TREE_HEAD_END="$(_tree_head)"
TREE_STATUS_END="$(_tree_status_sha)"

# Count data rows (all lines after the header) of a TSV; 0 when absent.
_tsv_rows() {
  if [ -f "$1" ]; then tail -n +2 "$1" | grep -c . || true; else echo 0; fi
}

TMP_MANIFEST="$MANIFEST.tmp.$$"
{
  echo "format=fc_timer_triplet/v1"
  echo "run_id=$RUN_ID"
  echo "prefix=$PREFIX"
  echo "mode=$MODE"
  echo "concurrency=$CONCURRENCY"
  echo "tmpdir_isolation=per-member"
  echo "started_epoch=$STARTED_EPOCH"
  echo "finished_epoch=$FINISHED_EPOCH"
  echo "tree_head_start=$TREE_HEAD_START"
  echo "tree_head_end=$TREE_HEAD_END"
  echo "tree_status_sha256_start=$TREE_STATUS_START"
  echo "tree_status_sha256_end=$TREE_STATUS_END"
  for m in $MEMBERS; do
    log="$OUT_DIR/${PREFIX}_${m}_${RUN_ID}.log"
    tsv="$TSV_ROOT/${RUN_ID}_${PREFIX}_${m}/prebuild_sections.tsv"
    echo "member.$m.log=$(basename -- "$log")"
    echo "member.$m.log_sha256=$(sha256sum "$log" | awk '{print $1}')"
    echo "member.$m.fc_timing=$(_timing_of "$m")"
    echo "member.$m.exit=$(cat "$WORK/$m.exit" 2>/dev/null || echo MISSING)"
    echo "member.$m.started_epoch=$(cat "$WORK/$m.started" 2>/dev/null || echo MISSING)"
    echo "member.$m.finished_epoch=$(cat "$WORK/$m.finished" 2>/dev/null || echo MISSING)"
    echo "member.$m.tsv=$tsv"
    echo "member.$m.tsv_rows=$(_tsv_rows "$tsv")"
  done
} > "$TMP_MANIFEST" && mv -f -- "$TMP_MANIFEST" "$MANIFEST" || {
  rm -f -- "$TMP_MANIFEST"; echo "FATAL: could not write manifest $MANIFEST" >&2; exit 2; }

echo "SUMMARY: triplet $RUN_ID captured in $((FINISHED_EPOCH - STARTED_EPOCH))s; manifest: $MANIFEST"
cat "$MANIFEST"
echo "Next: bash $HERE/test_fc_timer_golden_output.sh"
