#!/usr/bin/env bash
# jev-status.sh — decision-layer status reporter (§11.4.281(D)).
#
# Human-readable sections by default; --json emits exactly this schema:
#   {"version": <int>,
#    "detection": <jev-detection.json inline | null>,
#    "thresholds": <jev-thresholds.json inline | null>,
#    "bootstrap": {"stamp": <bootstrap.stamp inline | null>, "pending": <bool>},
#    "mode": "<shadow|enforce|unknown>"}
# A state file that exists but is not valid JSON is reported as null on stdout
# and named on stderr; it is never silently treated as healthy.
#
# Read-only: this script writes nothing and contacts no endpoint. Reachability
# shown is what the LAST bootstrap recorded, not a live probe.
#
# Exit codes: 0 report produced; 2 usage error or no JSON engine for --json.
# JSON assembly uses jq; python3 is the documented fallback ONLY when jq is
# absent (re-implementing a JSON parser in bash would fork a wire format).
#
# Usage: jev-status.sh [--json]
# Env (names only): JEV_STATE_DIR (default ~/.local/state/jev),
#      JEV_EVIDENCE_DIR (default .jev), JEV_CONFIG_DIR (default ~/.config/jev).

set -euo pipefail

SCHEMA_VERSION=1
JEV_STATE_DIR="${JEV_STATE_DIR:-$HOME/.local/state/jev}"
JEV_EVIDENCE_DIR="${JEV_EVIDENCE_DIR:-.jev}"
JEV_CONFIG_DIR="${JEV_CONFIG_DIR:-$HOME/.config/jev}"

JSON_OUT=0
case "${1:-}" in
  "") ;;
  --json) JSON_OUT=1 ;;
  --help|-h) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 0 ;;
  *) echo "jev-status: unknown argument: $1" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "jev-status: unexpected extra argument: $2" >&2; exit 2; }

DETECTION_FILE="$JEV_EVIDENCE_DIR/jev-detection.json"
THRESHOLDS_FILE="$JEV_CONFIG_DIR/jev-thresholds.json"
[ -f "$THRESHOLDS_FILE" ] || THRESHOLDS_FILE="$JEV_EVIDENCE_DIR/jev-thresholds.json"
STAMP_FILE="$JEV_STATE_DIR/bootstrap.stamp"
PENDING_FILE="$JEV_STATE_DIR/bootstrap.pending"
ENV_FILE="$JEV_CONFIG_DIR/env"

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
HAVE_PY=0; command -v python3 >/dev/null 2>&1 && HAVE_PY=1

MODE="unknown"
if [ -f "$ENV_FILE" ]; then
  MODE="$(grep -s '^JEV_MODE=' "$ENV_FILE" | head -1 | cut -d= -f2 || true)"
  MODE="${MODE:-unknown}"
fi

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
      --arg mode "$MODE" \
      '{version:$version, detection:$detection, thresholds:$thresholds,
        bootstrap:{stamp:$stamp, pending:$pending}, mode:$mode}'
  elif [ "$HAVE_PY" = "1" ]; then
    JEV_DET="$det_json" JEV_THR="$thr_json" JEV_STAMP="$stamp_json" \
    JEV_PENDING="$PENDING" JEV_MODE="$MODE" JEV_VER="$SCHEMA_VERSION" \
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
