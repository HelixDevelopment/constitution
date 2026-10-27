#!/usr/bin/env bash
# CM-JEV-DETECTION (§11.4.279(D), §11.4.282(D), §11.4.286(D))
# Asserts the decision-model detection record is present, fresh, schema-valid,
# reasoned when empty, secret-free, provenanced, and — critically — that
# endpoints claimed reachable actually probe reachable in THIS environment.
#
# Env overrides (consumer DATA, §11.4.35):
#   JEV_DETECTION_FILE         detection record (default: the shared resolver's <evidence>/jev-detection.json)
#   JEV_EVIDENCE_WINDOW_START  epoch; generated_at/probed_at must be >= this (default: 0)
#   JEV_PROBE_CMD              probe command, invoked as "$JEV_PROBE_CMD <id> <url>";
#                              default: fail-closed probe (claims of reachability
#                              require an explicit probe mechanism)
#   JEV_FIXTURE_ROOT           root for resolving relative tools.*.path entries
#                              (default: directory containing the detection file)
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "CM-JEV-DETECTION CANNOT DETERMINE: jq not installed (rc 2, never a pass)" >&2; exit 2; }

# CLI (consistent with the other cm_* gates): --root <dir> judges <dir>/.jev/jev-detection.json.
# JEV_DETECTION_FILE (env) still wins over --root when both are given.
ROOT_ARG=""
# shellcheck source=../jev/lib_decide.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../jev/lib_decide.sh"   # THE path resolver (review r6 I6-2): no independent derivation here
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "CM-JEV-DETECTION: --root needs a directory" >&2; exit 2; }; ROOT_ARG="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "CM-JEV-DETECTION: unknown argument: $1 (usage: cm_jev_detection.sh [--root <dir>])" >&2; exit 2 ;;
  esac
done
DEFAULT_DET="$(jev_detection_file)"; [ -z "$ROOT_ARG" ] || DEFAULT_DET="${ROOT_ARG%/}/.jev/jev-detection.json"   # jev-path-ok: --root is an explicit caller-chosen project layout
DETECTION="${JEV_DETECTION_FILE:-$DEFAULT_DET}"
WINDOW_START="${JEV_EVIDENCE_WINDOW_START:-0}"
ROOT=""   # resolved after clause 1 proved the record exists (a cd into an absent dir only produced noise)
PROBE="${JEV_PROBE_CMD:-}"

fail=0
err() { printf 'CM-JEV-DETECTION FAIL: %s\n' "$*" >&2; fail=1; }
# ok prints only when the clause added no FAIL (no "ok" line after a failure).
clause_start() { _f0=$fail; }
ok()  { [ "$fail" = "$_f0" ] && printf 'CM-JEV-DETECTION ok: %s\n' "$*" >&2; return 0; }
note() { printf 'CM-JEV-DETECTION NOTE: %s\n' "$*" >&2; }
_f0=0

# Contract (producer = scripts/jev/bootstrap.sh):
#   endpoints[].reachable    true | false | null  (null = NOT PROBED; passes the schema, is
#                            NOT verification and is counted in a NOTE). null requires
#                            reachable_basis (toolkit-cache entries carry "resolution-only").
#   reachable == true        requires a non-empty .url AND a JEV_PROBE_CMD replay.
#   probed_at                number, required when reachable is boolean.
#   tools.<t>.source         submodule | clone | explicit | unavailable.
#                            unavailable requires a non-empty .reason (path may be empty);
#                            every other source requires an existing path.
#   capacity.decision_instances  number (computed, not guessed).

# Clause 1 - exists, parses, schema-valid.
clause_start
if [ ! -f "$DETECTION" ]; then
  err "detection record missing: $DETECTION (silent absence is a §7.1 bluff - run detection and persist jev-detection.json)"
  exit 1
fi
if ! jq -e . "$DETECTION" >/dev/null 2>&1; then
  err "detection record does not parse as JSON: $DETECTION"
  exit 1
fi
jq -e '.endpoints | type == "array"' "$DETECTION" >/dev/null \
  || err "schema: .endpoints must be an array"
n=$(jq '.endpoints | length' "$DETECTION" 2>/dev/null || echo 0)
if [ "$n" -eq 0 ]; then
  jq -e '.reason | type == "string" and length > 0' "$DETECTION" >/dev/null \
    || err "schema: empty endpoints require a non-empty top-level .reason (§11.4.279(B))"
else
  bad=$(jq '[.endpoints[] | select(
        (.id|type=="string" and length>0) and
        (.source|type=="string" and length>0) and
        (.model|type=="string" and length>0) and
        ((.reachable == null) or (.reachable|type=="boolean")) and
        ((.reachable == null) or (.probed_at|type=="number")) and
        ((.reachable != null) or (.reachable_basis|type=="string" and length>0))
      )] | length' "$DETECTION")
  [ "$bad" = "$n" ] || err "schema: some endpoints lack id/source/model, have reachable not true|false|null, lack probed_at (probed entries), or are unprobed (null) without reachable_basis"
fi
ok "clause 1: record parses, schema-valid ($n endpoints)"
ROOT="${JEV_FIXTURE_ROOT:-$(cd "$(dirname "$DETECTION")" 2>/dev/null && pwd)}"
unprobed=$(jq '[.endpoints[]? | select(.reachable == null)] | length' "$DETECTION" 2>/dev/null || echo 0)
if [ "${unprobed:-0}" -gt 0 ]; then
  note "$unprobed of $n endpoint(s) have reachable=null (NOT probed): schema-valid, but 'unprobed' is not 'verified'"
fi

# Clause 2 - within the evidence window.
clause_start
gen=$(jq -r '.generated_at // 0' "$DETECTION")
[ "$gen" -ge "$WINDOW_START" ] 2>/dev/null \
  || err "freshness: generated_at=$gen predates evidence window start $WINDOW_START"
stale=$(jq --argjson w "$WINDOW_START" '[.endpoints[]? | select(.probed_at != null and .probed_at < $w)] | length' "$DETECTION")
[ "$stale" = "0" ] || err "freshness: $stale endpoint(s) probed before the evidence window"
ok "clause 2: generated_at=$gen within window (>= $WINDOW_START)"

# Clause 3 - hosted entries carry key_var NAMES only, never materialized secrets.
clause_start
secret_hits=$(jq '[.endpoints[]? | to_entries[] |
    select(.key | test("(?i)(api_?key|token|secret|password)")) |
    select(.key != "key_var") |
    select(.value | type == "string" and length > 0)] | length' "$DETECTION")
[ "$secret_hits" = "0" ] || err "secrets: $secret_hits materialized secret field(s) - key_var NAMES only (§11.4.279(A) hygiene)"
ok "clause 3: no materialized secrets in hosted entries"

# Clause 4 - provenance record for llmctl + claude_toolkit (§11.4.286(D)).
clause_start
for tool in llmctl claude_toolkit; do
  jq -e --arg t "$tool" '.tools[$t] | type == "object"' "$DETECTION" >/dev/null \
    || { err "provenance: tools.$tool record missing"; continue; }
  src=$(jq -r --arg t "$tool" '.tools[$t].source // ""' "$DETECTION")
  jq -e --arg t "$tool" '.tools[$t].ref | type == "string" and length > 0' "$DETECTION" >/dev/null \
    || err "provenance: tools.$tool.ref missing"
  p=$(jq -r --arg t "$tool" '.tools[$t].path // ""' "$DETECTION")
  case "$src" in
    submodule|clone|explicit)
      if [ -z "$p" ]; then
        err "provenance: tools.$tool.source='$src' requires a non-empty path"
      else
        case "$p" in /*) abs="$p";; *) abs="$ROOT/$p";; esac
        [ -d "$abs" ] || err "provenance: tools.$tool.path '$p' does not exist on this host (resolved: $abs) - unprovenanced install is non-compliance (§11.4.286)"
      fi ;;
    unavailable)
      jq -e --arg t "$tool" '.tools[$t].reason | type == "string" and length > 0' "$DETECTION" >/dev/null \
        || err "provenance: tools.$tool.source='unavailable' requires a non-empty .reason (silent unavailability is a bluff)" ;;
    *) err "provenance: tools.$tool.source must be submodule|clone|explicit|unavailable, got '$src'" ;;
  esac
done
ok "clause 4: tools provenance present (paths exist / unavailable reasoned)"

# Clause 5 - computed capacity: decision_instances is a number (§11.4.282(A)).
clause_start
jq -e '.capacity.decision_instances | type == "number" and . >= 0' "$DETECTION" >/dev/null \
  || err "capacity: .capacity.decision_instances must be a non-negative number - capacity is computed, not guessed (§11.4.282(A))"
ok "clause 5: capacity.decision_instances is a number"

# Clause 6 - reachable=true: needs a .url and a probe replay that succeeds HERE.
clause_start
nt=$(jq '[.endpoints[]? | select(.reachable == true)] | length' "$DETECTION")
if [ "${nt:-0}" -gt 0 ]; then
  nourl=$(jq '[.endpoints[] | select(.reachable == true and ((.url // "") | length == 0))] | length' "$DETECTION")
  [ "$nourl" = "0" ] || err "probe: $nourl endpoint(s) claim reachable=true but carry no .url - an unprobeable claim is a bluff (§7.1)"
  if [ -z "$PROBE" ]; then
    err "probe: $nt endpoint(s) claim reachable=true but no JEV_PROBE_CMD mechanism is configured - unverifiable claims are bluffs (§7.1). Supply the replayable probe exactly as bootstrap does: JEV_PROBE_CMD=<constitution>/scripts/jev/jev-probe.sh JEV_DETECTION_FILE=<record> bash scripts/gates/cm_jev_detection.sh"
  else
    while IFS="$(printf '\t')" read -r id url; do
      [ -n "$url" ] || continue
      if ! "$PROBE" "$id" "$url" >/dev/null 2>&1; then
        err "probe: endpoint '$id' claimed reachable=true but probe replay FAILED in this environment"
      fi
    done < <(jq -r '.endpoints[] | select(.reachable == true) | [.id, (.url // "")] | @tsv' "$DETECTION")
  fi
fi
ok "clause 6: probe replay consistent with recorded reachability ($nt claimed reachable)"

# Clause 8 - a hosted endpoint with a key variable whose key is REAL (not a placeholder) must have been
# PROVEN reachable. reachable=null/false next to a usable key means detection skipped or failed the probe:
# GREEN would otherwise vouch for an endpoint nobody called (H1, 2026-10-24).
clause_start
_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../jev/lib_keys.sh"
if [ -f "$_lib" ]; then
  # shellcheck source=../jev/lib_keys.sh
  . "$_lib"
  _fallback_noted=0
  while IFS="$(printf '\t')" read -r _id _kv _rc; do
    [ -n "$_kv" ] || continue
    # The verdict is judged on the key state RECORDED at detection time (key_discovery.vars[]), so it is the same on
    # every host that re-runs the gate. Only a record that carries no such state falls back to the RUNNER's own
    # environment, and then the verdict is declared environment-dependent (a NOTE, once).
    _rec="$(jq -r --arg v "$_kv" '[.key_discovery.vars[]? | select(.key_var == $v) | .state][0] // empty' "$DETECTION" 2>/dev/null)"
    if [ -n "$_rec" ]; then _kst="$_rec"
    else
      _kst="$(key_state "$_kv" | cut -f1)"
      if [ "$_fallback_noted" = 0 ]; then
        note "clause 8: the record carries no key_discovery state for $_kv - the verdict depends on the environment of the host running this gate"
        _fallback_noted=1
      fi
    fi
    if [ "$_kst" = "real" ]; then
      err "key: endpoint '$_id' (key variable $_kv) holds a real key but reachable=$_rc - the endpoint was not proven reachable (re-run detection with hosted probing enabled)"
    fi
  done < <(jq -r '.endpoints[]? | select((.key_var // "") != "" and .reachable != true) | [.id, .key_var, (.reachable | tostring)] | @tsv' "$DETECTION" 2>/dev/null)
else
  note "lib_keys.sh not found next to the gates: the key-present/unproven-endpoint check was not run"
fi
ok "clause 8: no hosted endpoint with a real key is unproven"

# Clause 7 - an EMPTY record must not contradict llmctl's own registry (§11.4.201(6): a
# false-null). With llmctl on PATH, a running gateway, a running profile or a healthy
# decide service means "no endpoints" is wrong. llmctl absent/unparsable = NOTE only.
clause_start
if [ "$n" -eq 0 ]; then
  if command -v llmctl >/dev/null 2>&1; then
    _tmo="${JEV_TOOL_TIMEOUT:-30}"
    if command -v timeout >/dev/null 2>&1; then _run() { timeout --kill-after=2 "$_tmo" "$@"; }; else _run() { "$@"; }; fi
    st="$(_run llmctl decide status --json 2>/dev/null)"; _src=$?
    if [ "$_src" -eq 124 ] || [ "$_src" -eq 137 ]; then
      note "llmctl decide status timed out after ${_tmo}s: the empty record cannot be cross-checked"
      st=""
    else
      st="$(printf '%s' "$st" | jq -c '.' 2>/dev/null)" || st=""
    fi
    if [ -z "$st" ]; then
      case "$_src" in 124|137) : ;; *) note "llmctl decide status gave no parsable JSON: the empty record cannot be cross-checked" ;; esac
    else
      cap="$(_run llmctl decide capacity --json 2>/dev/null | jq -c '.' 2>/dev/null)" || cap=""
      [ -n "$cap" ] || cap='{}'
      # A gateway with nothing behind it, and a profile that speaks the jev-verdict protocol (decide-tiny has no
      # driver and is not a usable decision endpoint), are the two LAWFUL empty states. Everything else running is a
      # contradiction. A running profile whose protocol is unknown is counted live (conservative).
      # shellcheck source=../jev/lib_decide.sh
      . "$(dirname "$0")/../jev/lib_decide.sh"
      live="$(jev_usable_live "$st" "$cap")"
      if [ -n "$live" ]; then
        err "contradiction: the record lists 0 endpoints but llmctl reports live decision infrastructure ($live) - re-run detection (§11.4.279(A), false-null §11.4.201(6))"
      fi
    fi
  else
    note "llmctl not on PATH: the empty record cannot be cross-checked against llmctl's registry"
  fi
fi
ok "clause 7: empty record consistent with llmctl's registry (or n/a: $n endpoints)"

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-DETECTION: RED" >&2
  exit 1
fi
echo "CM-JEV-DETECTION: GREEN"
exit 0
