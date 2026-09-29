#!/bin/bash
# heartbeat.sh - T132 (SpecKit-004 "fast-dev-cycles", User Story 5 / Phase B,
# plan task T-B03; FR-015, FR-016; constitution §11.4.232(C)).
#
# Contract: NONE -- $FC/orchestration/heartbeat.sh is on
# contracts/common-conventions.md's own "no contract in this directory
# (open gap)" list, so every wire-format decision below is DEFINED here,
# binding-if-adopted, per the house convention already used by
# fixtures/evidence_ref/README.md, fixtures/handoff/README.md and T135's
# limit_class.py header -- never re-decided without an explicit note.
#
# Purpose (plan.md T-B03, task text): "long-running agents and long ops emit
# a heartbeat with a monotonically advancing progress offset
# (section 11.4.232(C)); stale-lock reaping reads holder liveness and
# heartbeat, and logs wait duration". This file is the emit+classify half;
# scripts/hooks/agent_registry_writer.sh's --reap mode (T132, this same
# task) is the stale-lock-reaping half that CONSUMES this file's
# classify-key verb rather than re-implementing the liveness rule.
#
# Protecting test: constitution/scripts/fastcycle/tests/test_heartbeat_liveness_red.sh
# (T124). Its Section 3 "real after check" invokes EXACTLY:
#   heartbeat.sh classify --samples <fixture.json> --budget-seconds <N>
# and requires the bare string ALIVE or STALE on stdout, nothing else --
# that shape is therefore NORMATIVE for the `classify` verb regardless of
# this file's own header commentary (a test binding directly to plan task
# text, per common-conventions.md's own instruction for contract-less
# tools).
#
# IMPORTANT (Producer != Verifier, constitution section 11.4.240): the
# classify algorithm below is authored independently from T124's own
# `oracle_liveness()` bash function -- it applies the SAME plain-English
# T-B03 rule (never imported, sourced, or copy-pasted from the test file)
# so that a bug shared between the test's oracle and this tool's real
# implementation cannot silently cancel out. The two were compared for
# BEHAVIOURAL agreement only, via the RED test's real invocation of this
# file (Section 3), never via a shared code path.
#
# ============================================================================
# Verbs
# ============================================================================
#
#   heartbeat.sh beat --key <16-hex agent-key> [--heartbeat-dir <dir>]
#     Appends ONE heartbeat sample {"ts": <int, UTC epoch seconds>,
#     "offset": <int>} to <heartbeat-dir>/<key>.jsonl (append-only, O_APPEND,
#     one JSON object per line -- mirrors agent_registry_writer.sh's own
#     registry-file convention, section 11.4.116). `offset` is a MECHANICAL,
#     MONOTONICALLY STRICTLY-INCREASING sequence number -- 1 + the number of
#     prior lines already in that key's log -- NEVER a clock reading (a
#     clock can tie or go backward under NTP skew; a line count cannot).
#     This is the "strictly-increasing sequence number" form the T132
#     dispatch instructions name explicitly (the alternative named there,
#     a byte-offset, is numerically equivalent for liveness purposes: both
#     are monotonic counters that only move forward on a genuine call).
#     Prints `OK key=<key> offset=<n>` to stdout. Exit 0 on success, 2 on a
#     usage/config error (bad/missing --key, heartbeat-dir not creatable).
#
#   heartbeat.sh classify --samples <path to JSON array of {ts,offset}>
#                          --budget-seconds <N>
#     PURE function of the supplied sample array (never reads wall-clock
#     "now" -- this is what keeps it C-003-deterministic and directly
#     testable against T124's fixed fixtures). Applies the T-B03 rule:
#     STALE iff, walking the samples in ts order, there exists a point
#     whose elapsed time since the offset's LAST real advance exceeds the
#     budget; otherwise ALIVE. Fewer than 2 samples => ALIVE (no gap is yet
#     observable). Prints EXACTLY the bare word `ALIVE` or `STALE` to
#     stdout, nothing else (T124's own test captures this via `$(...)` and
#     asserts byte equality against that exact word). Exit 0 for ALIVE,
#     1 for STALE (this file's own C-001-style convention, chosen for
#     consistency with every sibling contract's "1 = a finding" rule; T124
#     itself does not assert on the exit code, only on stdout). Exit 2 on
#     a usage/config error (missing/unreadable/unparseable --samples file,
#     missing --budget-seconds).
#
#   heartbeat.sh classify-key --key <16-hex agent-key>
#                              [--heartbeat-dir <dir>] --budget-seconds <N>
#     Wall-clock-AWARE convenience layered on top of `classify` (calls the
#     SAME bash function directly -- no duplicated algorithm): reads
#     <heartbeat-dir>/<key>.jsonl, and -- because a real dead agent simply
#     STOPS appending (there is no "final" sample marking its own death) --
#     appends ONE synthetic checkpoint {"ts": now, "offset": <last known
#     offset>} before classifying, so a key whose last real beat was long
#     ago is correctly detected once enough wall-clock time has elapsed
#     with nothing further recorded. If the key has no heartbeat log at
#     all, prints `NO-EVIDENCE` and exits 4 (this file's own C-001-style
#     "BLIND: no honest verdict possible" class -- never silently read as
#     ALIVE, which would be exactly the section 11.4.201(6) false-null this
#     project forbids). Otherwise prints the same bare ALIVE/STALE word and
#     exit code as `classify`.
#
# Env vars:
#   HELIX_AGENT_HEARTBEAT_DIR (optional) -- overrides the default heartbeat
#     log directory (mirrors agent_registry_writer.sh's own
#     HELIX_AGENT_REGISTRY_FILE convention so tests never touch the real
#     directory). Default: <repo-root>/docs/requests/agent_heartbeats.
#
# Dependencies: bash, python3 (json parsing + the classify algorithm; if
#   absent, every verb exits 2 with an honest message -- no silent
#   degradation to a fabricated verdict, section 11.4.6).
# Cross-references: section 11.4.232(C) (heartbeat liveness truth-source),
#   section 11.4.201(6) (false-null), section 11.4.240 (Producer != Verifier),
#   data-model.md section 9.1 (`suspected-dead` state, `in-flight
#   --progress*--> in-flight` transition), tasks.md T124/T132,
#   plan.md T-B03, scripts/hooks/agent_registry_writer.sh (the consumer of
#   `classify-key` via its --reap sweep).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FC="$(cd "$SCRIPT_DIR/.." && pwd)"                 # constitution/scripts/fastcycle
CONST_ROOT="$(cd "$FC/../.." && pwd)"              # constitution/
REPO_ROOT="$(cd "$CONST_ROOT/.." && pwd)"          # project root
DEFAULT_HEARTBEAT_DIR="${HELIX_AGENT_HEARTBEAT_DIR:-$REPO_ROOT/docs/requests/agent_heartbeats}"

die_usage() { echo "heartbeat.sh: $1" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "heartbeat.sh: python3 unavailable -- cannot classify or beat honestly (section 11.4.6)" >&2
  exit 2
fi

# =============================================================================
# beat -- append one monotonic {ts, offset} sample for --key.
# =============================================================================
cmd_beat() {
  local key="" hb_dir="$DEFAULT_HEARTBEAT_DIR"
  while [ $# -gt 0 ]; do
    case "$1" in
      --key) key="$2"; shift 2 ;;
      --heartbeat-dir) hb_dir="$2"; shift 2 ;;
      *) die_usage "beat: unknown arg '$1'" ;;
    esac
  done
  [ -n "$key" ] || die_usage "beat: --key is required"
  mkdir -p "$hb_dir" 2>/dev/null || die_usage "beat: cannot create heartbeat dir '$hb_dir'"
  local log="$hb_dir/$key.jsonl"
  local prior=0
  if [ -e "$log" ]; then
    prior="$(wc -l < "$log" 2>/dev/null || echo 0)"
    prior="${prior//[[:space:]]/}"
    case "$prior" in ''|*[!0-9]*) prior=0 ;; esac
  fi
  local offset=$((prior + 1))
  local now_epoch
  now_epoch="$(date -u +%s)"
  printf '{"ts":%s,"offset":%s}\n' "$now_epoch" "$offset" >> "$log"
  echo "OK key=$key offset=$offset"
  return 0
}

# =============================================================================
# classify -- pure function of a supplied {ts,offset} sample array
# (independently authored from T124's oracle_liveness(); see header note).
# =============================================================================
cmd_classify() {
  local samples="" budget=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --samples) samples="$2"; shift 2 ;;
      --budget-seconds) budget="$2"; shift 2 ;;
      *) die_usage "classify: unknown arg '$1'" ;;
    esac
  done
  [ -n "$samples" ] || die_usage "classify: --samples is required"
  [ -r "$samples" ] || die_usage "classify: --samples path not readable: '$samples'"
  [ -n "$budget" ] || die_usage "classify: --budget-seconds is required"

  local verdict
  verdict="$(SAMPLES_PATH="$samples" BUDGET_SECONDS="$budget" python3 -c '
import json, os, sys

try:
    with open(os.environ["SAMPLES_PATH"], encoding="utf-8") as fh:
        samples = json.load(fh)
except Exception as exc:
    print(f"USAGE-ERROR: unreadable/unparseable --samples file: {exc}", file=sys.stderr)
    sys.exit(2)

try:
    budget = float(os.environ["BUDGET_SECONDS"])
except Exception:
    print("USAGE-ERROR: --budget-seconds is not a number", file=sys.stderr)
    sys.exit(2)

if not isinstance(samples, list) or len(samples) < 2:
    # Fewer than two samples: no gap between two points is yet observable,
    # so there is nothing to disprove liveness with (T124 golden semantics).
    print("ALIVE")
    sys.exit(0)

ordered = sorted(samples, key=lambda entry: entry["ts"])
anchor_ts = ordered[0]["ts"]
anchor_offset = ordered[0]["offset"]
past_budget = False
for entry in ordered[1:]:
    if entry["offset"] > anchor_offset:
        anchor_ts = entry["ts"]
        anchor_offset = entry["offset"]
    if (entry["ts"] - anchor_ts) > budget:
        past_budget = True

if past_budget:
    print("STALE")
    sys.exit(1)
print("ALIVE")
sys.exit(0)
')"
  local rc=$?
  if [ "$rc" = "2" ]; then
    die_usage "classify: bad input (see stderr above)"
  fi
  echo "$verdict"
  return "$rc"
}

# =============================================================================
# classify-key -- wall-clock-aware wrapper over cmd_classify (same function,
# no duplicated algorithm): resolves a key's real heartbeat log, appends a
# synthetic "as of now" checkpoint, and classifies that.
# =============================================================================
cmd_classify_key() {
  local key="" hb_dir="$DEFAULT_HEARTBEAT_DIR" budget=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --key) key="$2"; shift 2 ;;
      --heartbeat-dir) hb_dir="$2"; shift 2 ;;
      --budget-seconds) budget="$2"; shift 2 ;;
      *) die_usage "classify-key: unknown arg '$1'" ;;
    esac
  done
  [ -n "$key" ] || die_usage "classify-key: --key is required"
  [ -n "$budget" ] || die_usage "classify-key: --budget-seconds is required"

  local log="$hb_dir/$key.jsonl"
  if [ ! -r "$log" ]; then
    echo "NO-EVIDENCE"
    return 4
  fi

  local tmp_samples
  tmp_samples="$(mktemp)" || die_usage "classify-key: cannot create temp file"
  local now_epoch
  now_epoch="$(date -u +%s)"
  local rc_build
  LOG_PATH="$log" NOW_EPOCH="$now_epoch" OUT_PATH="$tmp_samples" python3 -c '
import json, os

log = os.environ["LOG_PATH"]
now = int(os.environ["NOW_EPOCH"])
out = os.environ["OUT_PATH"]

samples = []
with open(log, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            samples.append(json.loads(line))
        except Exception:
            continue

if samples:
    last_offset = max(entry["offset"] for entry in samples)
    samples.append({"ts": now, "offset": last_offset})

with open(out, "w", encoding="utf-8") as fh:
    json.dump(samples, fh)
'
  rc_build=$?
  if [ "$rc_build" != "0" ]; then
    rm -f "$tmp_samples"
    echo "NO-EVIDENCE"
    return 4
  fi

  local verdict rc
  verdict="$(cmd_classify --samples "$tmp_samples" --budget-seconds "$budget")"
  rc=$?
  rm -f "$tmp_samples"
  echo "$verdict"
  return "$rc"
}

# =============================================================================
# main
# =============================================================================
[ $# -ge 1 ] || die_usage "usage: heartbeat.sh {beat|classify|classify-key} ..."
sub="$1"; shift
case "$sub" in
  beat) cmd_beat "$@" ;;
  classify) cmd_classify "$@" ;;
  classify-key) cmd_classify_key "$@" ;;
  *) die_usage "unknown verb '$sub' (expected beat|classify|classify-key)" ;;
esac
