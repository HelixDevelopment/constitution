#!/usr/bin/env bash
# CM-JEV-DETECTION (§11.4.279(D), §11.4.282(D), §11.4.286(D))
# Asserts the decision-model detection record is present, fresh, schema-valid,
# reasoned when empty, secret-free, provenanced, and — critically — that
# endpoints claimed reachable actually probe reachable in THIS environment.
#
# Env overrides (consumer DATA, §11.4.35):
#   JEV_DETECTION_FILE         detection record (default: .jev/jev-detection.json)
#   JEV_EVIDENCE_WINDOW_START  epoch; generated_at/probed_at must be >= this (default: 0)
#   JEV_PROBE_CMD              probe command, invoked as "$JEV_PROBE_CMD <id> <url>";
#                              default: fail-closed probe (claims of reachability
#                              require an explicit probe mechanism)
#   JEV_FIXTURE_ROOT           root for resolving relative tools.*.path entries
#                              (default: directory containing the detection file)
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "CM-JEV-DETECTION CANNOT DETERMINE: jq not installed (rc 2, never a pass)" >&2; exit 2; }

DETECTION="${JEV_DETECTION_FILE:-.jev/jev-detection.json}"
WINDOW_START="${JEV_EVIDENCE_WINDOW_START:-0}"
ROOT="${JEV_FIXTURE_ROOT:-$(cd "$(dirname "$DETECTION")" && pwd)}"
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
    err "probe: $nt endpoint(s) claim reachable=true but no JEV_PROBE_CMD mechanism is configured - unverifiable claims are bluffs (§7.1)"
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

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-DETECTION: RED" >&2
  exit 1
fi
echo "CM-JEV-DETECTION: GREEN"
exit 0
