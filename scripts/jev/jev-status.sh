#!/usr/bin/env bash
# jev-status.sh — decision-layer status reporter (§11.4.281(D)).
#
# Human-readable sections by default; --json emits exactly this schema:
#   {"version": <int>,
#    "detection": <jev-detection.json inline | null>,
#    "thresholds": <jev-thresholds.json inline | null>,
#    "bootstrap": {"stamp": <bootstrap.stamp inline | null>, "pending": <bool>},
#    "mode": "<shadow|enforce|unknown>",          # the EFFECTIVE mode (shared jev_effective_mode), never just the stored text
#    "mode_stored": "<value of JEV_MODE in the env file | unknown>",
#    "mode_reason": "<why the effective mode is what it is>",
#    "mcp_mode_mismatch": <bool>}   # true when any MCP jev entry's JEV_MODE differs from the env file's stored JEV_MODE
# A state file that exists but is not valid JSON is reported as null on stdout
# and named on stderr; it is never silently treated as healthy.
#
# Read-only: this script writes nothing. It makes no network probe of any endpoint; without --no-validate a stored `enforce`
# IS re-checked by running the local `llmctl require-validated` CLI (STRICT, exactly as bootstrap and register do, and that
# CLI may itself start/contact a local model server), and a failing check reports shadow. Reachability shown is what the
# LAST bootstrap recorded, not a live probe. `mcp_mode_mismatch` (--json) / an "MCP" line (human view) says a toolkit
# MCP `jev` entry carries a JEV_MODE that differs from the env file's (review r5 m5-5).
#
# Exit codes: 0 report produced; 2 usage error or no JSON engine for --json.
# JSON assembly uses jq; python3 is the documented fallback ONLY when jq is
# absent (re-implementing a JSON parser in bash would fork a wire format).
#
# A stored `enforce` is re-derived by running the REAL `llmctl require-validated` (STRICT) for every decision profile, up
# to 60 s EACH, so a status call can be slow and has that side effect (it runs a local CLI; it writes nothing). Pass
# --no-validate (or set JEV_STATUS_NO_VALIDATE=1) to skip it: the mode is then reported `unknown` with reason
# `validation-skipped` when the other conditions would allow enforce, never `enforce`. Off by default.
# "test_override" (--json) / a line in the human view says a JEV_TEST=1 override (JEV_DECISION_PROFILES /
# JEV_REQUIRE_VALIDATED_CMD) is in force, i.e. the mode was NOT derived from the real validator.
#
# Usage: jev-status.sh [--json] [--no-validate]
# Env (names only): JEV_HOME (default $HOME), JEV_STATE_DIR (default <home>/.local/state/jev),
#      JEV_EVIDENCE_DIR (default <state>/evidence), JEV_CONFIG_DIR (default <home>/.config/jev),
#      JEV_DETECTION_FILE (selects the detection record). All defaults come from lib_decide.sh's one resolver.

set -euo pipefail

SCHEMA_VERSION=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_decide.sh
. "$SCRIPT_DIR/lib_decide.sh"
JEV_STATE_DIR="$(jev_state_dir)"; JEV_EVIDENCE_DIR="$(jev_evidence_dir)"; JEV_CONFIG_DIR="$(jev_config_dir)"   # the ONE shared resolver (r6 I6-2)

JSON_OUT=0; NO_VALIDATE="${JEV_STATUS_NO_VALIDATE:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=1 ;;
    --no-validate) NO_VALIDATE=1 ;;
    --help|-h) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 0 ;;
    *) echo "jev-status: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

DETECTION_FILE="$(jev_detection_file)"
THRESHOLDS_FILE="$JEV_CONFIG_DIR/jev-thresholds.json"
[ -f "$THRESHOLDS_FILE" ] || THRESHOLDS_FILE="$JEV_EVIDENCE_DIR/jev-thresholds.json"
STAMP_FILE="$JEV_STATE_DIR/bootstrap.stamp"
PENDING_FILE="$JEV_STATE_DIR/bootstrap.pending"
ENV_FILE="$JEV_CONFIG_DIR/env"

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
HAVE_PY=0; command -v python3 >/dev/null 2>&1 && HAVE_PY=1

MODE="unknown"
if [ -f "$ENV_FILE" ]; then
  MODE="$(jev_env_get "$ENV_FILE" JEV_MODE || true)"   # last assignment wins, `export ` accepted (like a shell sourcing the file)
  MODE="${MODE:-unknown}"
fi

# The mode shown is the EFFECTIVE one: a stored `enforce` is re-derived through the SAME shared function bootstrap stage 5
# and register.sh use, so status can never claim enforce for a host that would not enforce (review r3 I3-2).
MODE_STORED="$MODE"; MODE_REASON="as-stored"
if [ "$MODE_STORED" = "enforce" ]; then
  MODE="shadow"; MODE_REASON="unknown"
  # no base URL is passed: the shared function resolves it (env, MCP entry, cache) like bootstrap and register do
  IFS=$'\t' read -r MODE MODE_REASON < <(JEV_SKIP_VALIDATION="$([ "$NO_VALIDATE" = 1 ] && echo 1 || echo 0)" jev_effective_mode enforce "" "$DETECTION_FILE") || true
  case "$MODE_REASON" in validation-skipped*) MODE="unknown" ;; *) [ "$MODE" = "enforce" ] || MODE="shadow" ;; esac
fi
MCP_MISMATCH=false
# r6 m6-1: compare every MCP entry with the EFFECTIVE mode (what is really in force), also when the env file is absent
# (stored `unknown`): an MCP entry saying enforce while the effective mode is not enforce is a mismatch.
while IFS=$'\t' read -r _f _m; do
  [ -z "${_m:-}" ] || [ "$_m" = "$MODE" ] || MCP_MISMATCH=true
done < <(jev_mcp_modes)
TEST_OVERRIDE=false
{ [ "${JEV_TEST:-}" = "1" ] && { [ -n "${JEV_DECISION_PROFILES:-}" ] || [ -n "${JEV_REQUIRE_VALIDATED_CMD:-}" ]; }; } && TEST_OVERRIDE=true

PENDING=false
[ -f "$PENDING_FILE" ] && PENDING=true

valid_json() { # valid_json <file>
  if [ "$HAVE_JQ" = "1" ]; then jq -e . "$1" >/dev/null 2>&1
  elif [ "$HAVE_PY" = "1" ]; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
  else return 1; fi
}

inline_or_null() { # inline_or_null <file> -> compact JSON body, or null
  local f="$1"
  [ -f "$f" ] || { printf 'null'; return; }
  if valid_json "$f"; then
    if [ "$HAVE_JQ" = "1" ]; then jq -c . "$f"; else cat "$f"; fi
  else
    echo "jev-status: $f is not valid JSON; reported as null" >&2
    printf 'null'
  fi
}

if [ "$JSON_OUT" = "1" ]; then
  det_json="$(inline_or_null "$DETECTION_FILE")"
  thr_json="$(inline_or_null "$THRESHOLDS_FILE")"
  stamp_json="$(inline_or_null "$STAMP_FILE")"
  if [ "$HAVE_JQ" = "1" ]; then
    jq -n \
      --argjson version "$SCHEMA_VERSION" \
      --argjson detection "$det_json" \
      --argjson thresholds "$thr_json" \
      --argjson stamp "$stamp_json" \
      --argjson pending "$PENDING" \
      --argjson test_override "$TEST_OVERRIDE" \
      --arg mode "$MODE" --arg mode_stored "$MODE_STORED" --arg mode_reason "$MODE_REASON" --argjson mcp_mismatch "$MCP_MISMATCH" \
      '{version:$version, detection:$detection, thresholds:$thresholds,
        bootstrap:{stamp:$stamp, pending:$pending}, mode:$mode, mode_stored:$mode_stored, mode_reason:$mode_reason, test_override:$test_override, mcp_mode_mismatch:$mcp_mismatch}'
  elif [ "$HAVE_PY" = "1" ]; then
    JEV_DET="$det_json" JEV_THR="$thr_json" JEV_STAMP="$stamp_json" \
    JEV_PENDING="$PENDING" JEV_MODE="$MODE" JEV_VER="$SCHEMA_VERSION" JEV_MODE_STORED="$MODE_STORED" JEV_MODE_REASON="$MODE_REASON" JEV_TEST_OVERRIDE="$TEST_OVERRIDE" JEV_MCP_MISMATCH="$MCP_MISMATCH" \
    python3 - <<'PY'
import json, os
def load(s):
    try: return json.loads(s)
    except Exception: return None
print(json.dumps({
    "version": int(os.environ["JEV_VER"]),
    "detection": load(os.environ["JEV_DET"]),
    "thresholds": load(os.environ["JEV_THR"]),
    "bootstrap": {"stamp": load(os.environ["JEV_STAMP"]),
                  "pending": os.environ["JEV_PENDING"] == "true"},
    "mode": os.environ["JEV_MODE"],
    "mode_stored": os.environ["JEV_MODE_STORED"],
    "mode_reason": os.environ["JEV_MODE_REASON"],
    "test_override": os.environ.get("JEV_TEST_OVERRIDE") == "true",
    "mcp_mode_mismatch": os.environ.get("JEV_MCP_MISMATCH") == "true",
}, indent=2))
PY
  else
    echo "jev-status: --json requires jq or python3; cannot determine (rc 2)" >&2
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------- human view ----
echo "Jev decision-layer status"
echo "========================="
echo ""
echo "Mode: $MODE"
[ "$MODE_STORED" = "$MODE" ] || echo "  (stored JEV_MODE=$MODE_STORED is NOT in force: $MODE_REASON)"
[ "$MCP_MISMATCH" != "true" ] || echo "  WARNING: an MCP 'jev' entry carries a JEV_MODE that differs from the mode in force ($MODE); re-run bootstrap to re-derive both"
[ "$TEST_OVERRIDE" != "true" ] || echo "  WARNING: JEV_TEST=1 override in force (JEV_DECISION_PROFILES / JEV_REQUIRE_VALIDATED_CMD): not the real validator"
echo ""

echo "Endpoints:"
echo "  (as recorded by the last bootstrap; not a live probe)"
if [ -f "$DETECTION_FILE" ]; then
  if [ "$HAVE_JQ" = "1" ] && valid_json "$DETECTION_FILE"; then
    n="$(jq -r '(.endpoints | length)' "$DETECTION_FILE" 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
      jq -r '.endpoints[] | "  - \(.id) source=\(.source) model=\(.model) reachable=\(.reachable)"' "$DETECTION_FILE"
    else
      echo "  (none detected)"
      jq -r 'if .reason then "  reason: \(.reason)" else empty end' "$DETECTION_FILE"
    fi
  else
    echo "  (jq needed for per-endpoint detail, or the file is not valid JSON; raw file: $DETECTION_FILE)"
  fi
else
  echo "  (no detection record at $DETECTION_FILE — run scripts/jev/bootstrap.sh)"
fi
echo ""

echo "Tools:"
if [ -f "$DETECTION_FILE" ] && [ "$HAVE_JQ" = "1" ] && valid_json "$DETECTION_FILE"; then
  jq -r '(.tools // {}) | to_entries[] | "  - \(.key): \(.value.path) ref=\(.value.ref) source=\(.value.source)"' "$DETECTION_FILE" 2>/dev/null || echo "  (none recorded)"
else
  echo "  (unknown — no readable detection record)"
fi
echo ""

echo "Thresholds:"
if [ -f "$THRESHOLDS_FILE" ]; then
  if [ "$HAVE_JQ" = "1" ] && valid_json "$THRESHOLDS_FILE"; then
    jq -r '(.per_type // {}) | to_entries[] | "  - \(.key): threshold=\(.value.threshold) n=\(.value.n) agreement=\(.value.agreement) promoted=\(.value.promoted) mode=\(.value.mode)"' "$THRESHOLDS_FILE"
  else
    echo "  present: $THRESHOLDS_FILE (jq needed for detail, or the file is not valid JSON)"
  fi
else
  echo "  (none — shadow mode; enforcement requires calibration via scripts/jev/jev-calibrate.sh)"
fi
echo ""

echo "Evidence log:"
if [ -f "$JEV_STATE_DIR/decisions.jsonl" ]; then
  echo "  decisions logged: $(grep -c . "$JEV_STATE_DIR/decisions.jsonl" || true) ($JEV_STATE_DIR/decisions.jsonl)"
else
  echo "  decisions logged: (no log at $JEV_STATE_DIR/decisions.jsonl)"
fi
if [ -s "$JEV_STATE_DIR/gate-off.log" ]; then
  echo "  gate kill-switch uses (JEV_GATE=off): $(grep -c . "$JEV_STATE_DIR/gate-off.log" || true)"
fi
if [ -f "$JEV_STATE_DIR/enforce-deferred" ]; then
  echo "  $(cat "$JEV_STATE_DIR/enforce-deferred")"
fi
echo ""

echo "Bootstrap:"
if [ -f "$STAMP_FILE" ]; then
  echo "  stamp: $STAMP_FILE"
  if [ "$HAVE_JQ" = "1" ] && valid_json "$STAMP_FILE"; then
    jq -r '"  created_at=\(.created_at) version=\(.version)"' "$STAMP_FILE" 2>/dev/null || true
  fi
else
  echo "  stamp: (absent — bootstrap has not completed)"
fi
if [ "$PENDING" = "true" ]; then
  echo "  PENDING: bootstrap deferred or incomplete — pending stamp at $PENDING_FILE"
  if [ "$HAVE_JQ" = "1" ] && valid_json "$PENDING_FILE"; then
    jq -r '"  reason: \(.reason // "unspecified")"' "$PENDING_FILE" 2>/dev/null || true
  fi
else
  echo "  pending: no"
fi
