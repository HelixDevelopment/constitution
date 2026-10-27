#!/usr/bin/env bash
# CM-JEV-TOKEN-REDUCTION (§11.4.283(D))
# Asserts the measured BEFORE/AFTER decision-layer harness proves reduction:
#   1. before/after artifacts exist, parse, carry provider `usage` fields (§11.4.141 schema)
#   2. the two runs' configs differ only in the decision-layer arm allowlist (JEV_GATE, JEV_MODE)
#   3. AFTER_total <= floor * BEFORE_total (floor = JEV_REDUCTION_FLOOR, default 1.0)
#   4. decisions.jsonl shows >=1 decision per gated tool-call class
#   5. savings figures in any stats report are labeled ESTIMATES
#
# Env overrides:
#   JEV_BEFORE / JEV_AFTER     jsonl artifacts (default: <evidence>/{before,after}.jsonl from the shared resolver)
#   JEV_BEFORE_CONFIG / JEV_AFTER_CONFIG   run configs for clause 2
#   JEV_DECISIONS              decisions.jsonl. Row schema: ts, question, answer, confidence, state_hash, mode ...
#                              A row's class is `.class` when present, else `.question` - the claude_toolkit
#                              jev-gate.sh writes the decision type as `.question` ("gate") and no `.class`.
#   JEV_STATS_REPORT           optional stats report checked for ESTIMATE labeling
#   JEV_GATED_CLASSES          comma list (default: gate,routing,score)
#   JEV_REDUCTION_FLOOR        default 1.0 (AFTER <= BEFORE; §11.4.35 DATA)
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "CM-JEV-TOKEN-REDUCTION CANNOT DETERMINE: jq not installed (rc 2, never a pass)" >&2; exit 2; }

# No synthetic default (2026-10-24): a GREEN from bundled fixtures is a verdict about the fixtures, not
# about this project. The pair comes from JEV_BEFORE/JEV_AFTER, else from <JEV_EVIDENCE_DIR>/{before,after}.jsonl
# when both exist; otherwise the gate is BLIND (rc 2), never GREEN and never a false RED.
# shellcheck source=../jev/lib_decide.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../jev/lib_decide.sh"   # THE path resolver (review r6 I6-2): no independent derivation here
EVD="$(jev_evidence_dir)"
BEFORE="${JEV_BEFORE:-}"; AFTER="${JEV_AFTER:-}"
[ -n "$BEFORE" ] || { [ -f "$EVD/before.jsonl" ] && BEFORE="$EVD/before.jsonl"; }
[ -n "$AFTER" ]  || { [ -f "$EVD/after.jsonl" ]  && AFTER="$EVD/after.jsonl"; }
if [ -z "$BEFORE" ] || [ -z "$AFTER" ]; then
  echo "CM-JEV-TOKEN-REDUCTION BLIND: no real BEFORE/AFTER harness pair configured (set JEV_BEFORE and JEV_AFTER, or place before.jsonl/after.jsonl in $EVD); no verdict is possible (rc 2, never a pass)" >&2
  exit 2
fi
BCONF="${JEV_BEFORE_CONFIG:-${BEFORE%.jsonl}.config}"
ACONF="${JEV_AFTER_CONFIG:-${AFTER%.jsonl}.config}"
DECISIONS="${JEV_DECISIONS:-$(dirname "$BEFORE")/decisions.jsonl}"
REPORT="${JEV_STATS_REPORT:-}"
FLOOR="${JEV_REDUCTION_FLOOR:-1.0}"
CLASSES="${JEV_GATED_CLASSES:-gate,routing,score}"

fail=0
err() { printf 'CM-JEV-TOKEN-REDUCTION FAIL: %s\n' "$*" >&2; fail=1; }
# ok prints only when the clause added no FAIL (no "ok" line after a failure of the same clause).
clause_start() { _f0=$fail; }
ok()  { [ "$fail" = "$_f0" ] && printf 'CM-JEV-TOKEN-REDUCTION ok: %s\n' "$*" >&2; return 0; }
_f0=0

clause_start
# Clause 1 — artifacts exist, parse, usage schema.
for f in "$BEFORE" "$AFTER"; do
  [ -f "$f" ] || { err "artifact missing: $f"; continue; }
  bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s' "$line" | jq -e '.usage.input_tokens | type == "number"' >/dev/null 2>&1 \
      && printf '%s' "$line" | jq -e '.usage.output_tokens | type == "number"' >/dev/null 2>&1 \
      || bad=1
  done < "$f"
  [ "$bad" -eq 0 ] || err "artifact $f has lines without numeric provider usage fields (§11.4.141 schema)"
done
ok "clause 1: BEFORE/AFTER artifacts parse with usage schema"

total() { jq -s '[.[].usage | .input_tokens + .output_tokens] | add // 0' "$1"; }

clause_start
# Clause 2 — config digests differ only in the decision-layer arm allowlist.
if [ -f "$BCONF" ] && [ -f "$ACONF" ]; then
  diff_lines=$(diff <(sort "$BCONF") <(sort "$ACONF") | grep -E '^[<>]' | sed -E 's/^[<>] //' | cut -d= -f1 | sort -u)
  disallowed=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$k" in JEV_GATE|JEV_MODE) ;; *) disallowed=1; err "clause2: config key '$k' differs between runs — only the decision-layer arm (JEV_GATE/JEV_MODE) may differ";; esac
  done <<< "$diff_lines"
  [ "$disallowed" -eq 0 ] && ok "clause 2: configs differ only in the allowlisted decision-layer arm"
else
  err "clause2: run config(s) missing ($BCONF / $ACONF) — arm isolation unverifiable"
fi

clause_start
# Clause 3 — AFTER <= floor * BEFORE (measured).
if [ -f "$BEFORE" ] && [ -f "$AFTER" ]; then
  b=$(total "$BEFORE"); a=$(total "$AFTER")
  # A zero BEFORE total is an empty harness (0 <= 0 would pass vacuously): refuse it.
  [ "${b:-0}" -gt 0 ] 2>/dev/null || err "clause3: BEFORE total is ${b:-unset} (empty/zero harness) — a reduction cannot be measured against nothing"
  pass=$(awk -v a="$a" -v b="$b" -v f="$FLOOR" 'BEGIN{print (a <= f*b) ? 1 : 0}')
  [ "$pass" = "1" ] || err "clause3: AFTER total ($a) exceeds floor($FLOOR) x BEFORE total ($b) — no measured reduction"
  ok "clause 3: AFTER=$a <= $FLOOR x BEFORE=$b"
fi

clause_start
# Clause 4 — >=1 decision per gated tool-call class.
if [ -f "$DECISIONS" ]; then
  IFS=',' read -ra cls <<< "$CLASSES"
  for c in "${cls[@]}"; do
    n=$(jq -s --arg c "$c" '[.[] | select((.class // .question) == $c)] | length' "$DECISIONS" 2>/dev/null || echo 0)
    [ "${n:-0}" -ge 1 ] || err "clause4: decisions.jsonl shows 0 decisions for gated class '$c'"
  done
  ok "clause 4: decisions recorded for every gated class ($CLASSES)"
else
  err "clause4: decisions.jsonl missing: $DECISIONS"
fi

clause_start
# Clause 5 — stats reports label savings as ESTIMATES.
if [ -n "$REPORT" ] && [ -f "$REPORT" ]; then
  grep -qi 'ESTIMATE' "$REPORT" \
    || err "clause5: $REPORT presents savings without an ESTIMATE label — jev-stats estimates never substitute for the measured harness (§11.4.283(C))"
  ok "clause 5: stats report savings labeled ESTIMATE"
fi

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-TOKEN-REDUCTION: RED" >&2
  exit 1
fi
echo "CM-JEV-TOKEN-REDUCTION: GREEN"
exit 0
