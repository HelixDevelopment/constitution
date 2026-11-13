#!/usr/bin/env bash
# tests/workable_items/test_remint_ids_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/remint_ids.py and its suite tests/workable_items/test_remint_ids.sh.
#
# Documentation (section 11.4.18): docs/guides/remint_ids_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the tool (the replaced text must
#   occur exactly once, otherwise the mutant is stale and the test fails). The suite runs against
#   each copy (REMINT_IDS=<copy>) and must FAIL; the unmutated copy must PASS (the control).
# ENV   WORKABLE_ITEMS  path of the workable-items engine binary (default: the tracked
#                       scripts/workable-items/bin/workable-items; exit 2 when not executable)
# EXIT  0 every mutant killed and the control passes; 1 otherwise; 2 setup error, or the cleanup of
#       the temp dir was refused.
# EVIDENCE CLASS  gate-logic only (section 11.4.289).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
src=$root/scripts/workable-items/remint_ids.py
suite=$here/test_remint_ids.sh
[ -f "$src" ] && [ -f "$suite" ] || { echo "setup: tool or suite missing" >&2; exit 2; }
export WORKABLE_ITEMS=${WORKABLE_ITEMS:-$root/scripts/workable-items/bin/workable-items}
[ -x "$WORKABLE_ITEMS" ] || { echo "setup: engine binary not executable: $WORKABLE_ITEMS (set WORKABLE_ITEMS)" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT

# id | old ||| new
mutants=(
  'R1 partly mapped range not refused|            if len(hit) != len(ids):|||            if False:'
  'R2 tokens chained once|                return m[iid]|||                return m.get(m[iid], m[iid])'
  'R3 non-contiguous range not refused|            if new != list(range(new[0], new[0] + len(new))):|||            if False:'
  'R4 Foreign line rewritten|        if FOREIGN_LINE.match(line):|||        if False:'
  'R5 held-id pre-check off|    if held:|||    if False:'
  'R6 .db file accepted|        if f.endswith(".db") or f.endswith(".bundle"):|||        if f.endswith(".bundle"):'
  'R7 id boundary dropped|    tok = re.compile(r"(?<![\w-])" + p + r"-(\d+)\b(?!-)")|||    tok = re.compile(p + r"-(\d+)")'
  'R8 collision with a staying id not refused|            raise Refusal("new id %s is an item of the vehicle that is not moved" % new)|||            pass'
)

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }

cp "$src" "$tmp/control.py" || exit 2
REMINT_IDS=$tmp/control.py bash "$suite" >"$tmp/control.out" 2>&1; rc=$?
if [ "$rc" = 0 ]; then ok "control: the unmutated copy passes the suite"
else bad "control: the unmutated copy passes the suite" "rc=$rc $(grep -m3 '^FAIL' "$tmp/control.out" | tr '\n' '|')"; fi

for spec in "${mutants[@]}"; do
  id=${spec%% *}; rest=${spec#*|}; old=${rest%%|||*}; new=${rest#*|||}
  copy=$tmp/$id.py
  python3 -I - "$src" "$copy" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
n = s.count(old)
if n != 1:
    print("stale mutant: the replaced text occurs %d times" % n)
    sys.exit(4)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
  st=$?
  if [ "$st" != 0 ]; then bad "$spec" "stale (exit $st)"; continue; fi
  REMINT_IDS=$copy bash "$suite" >"$tmp/$id.out" 2>&1; rc=$?
  if [ "$rc" = 1 ]; then ok "$id killed: $(grep -m1 '^FAIL' "$tmp/$id.out" | cut -c1-120)"
  else bad "$id ${spec#* }" "survived (suite rc=$rc)"; fi
done
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
