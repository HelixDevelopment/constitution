#!/bin/bash
# docs/qa/tracker_intake_2026_11_12_v5/engine_repro_check.sh -- tests of engine_repro.sh (round-4 review
# R4-8: the recorded red commands must carry every precondition the script needs, and the script must
# refuse a run that lacks one, so that a re-run either reproduces the evidence or says why it cannot).
#
# Usage: bash docs/qa/tracker_intake_2026_11_12_v5/engine_repro_check.sh <workable-items binary> \
#             <open Task id> <obsolete id> <probe Task id> <open Bug id>
# Every case runs engine_repro.sh on a fresh COPY of docs/workable_items.db in a mktemp directory;
# the tracked database is only read (its sha256 is checked before and after). Run from the repository
# root. The ids are arguments, so the test names no tracker id.
# Cases: the prefix unset and wrong (exit 3), <open> and <probe> of Type Bug (exit 3), an <obsolete> id
# without an obsolete_details row (exit 3), the full run (exit 0, and its output equal to the committed
# engine_repro.txt once the one time-dependent value, the created_at after the close, is masked), the
# comparison's own control needle (the round-4 evidence, which names the v4 script, must differ), and
# the tracked database unchanged.
# ENV   ENGINE_REPRO  the script under test (default engine_repro.sh beside this file; the RED run points
#       it at the round-4 script).
# Exit: 0 every case passed; 1 a case failed; 2 usage.
# Evidence class: gate-logic only (section 11.4.289).
set -u
[ $# -eq 5 ] || { echo "usage: engine_repro_check.sh <wi> <open Task id> <obsolete id> <probe Task id> <open Bug id>" >&2; exit 2; }
WI=${1:?}; OPEN=${2:?}; OBS=${3:?}; PROBE=${4:?}; BUG=${5:?}
D=docs/qa/tracker_intake_2026_11_12_v5
S=${ENGINE_REPRO:-$D/engine_repro.sh}
[ -f "$S" ] || { echo "usage: run from the repository root" >&2; exit 2; }
REAL=docs/workable_items.db
tmp=$(mktemp -d)
cleanup(){ rm -rf "${tmp:?}"; }
trap cleanup EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $1"; }
bad(){ fail=$((fail+1)); echo "FAIL $1: $2"; }
sum0=$(sha256sum "$REAL" | cut -d' ' -f1)
n=0
fresh(){ n=$((n+1)); cp "$REAL" "$tmp/c$n.db"; echo "$tmp/c$n.db"; }
# one case: <name> <want rc> <stderr pattern or -> <env prefix value or -> <ids...>
refuse(){
  local name=$1 want=$2 pat=$3 pfx=$4 db rc; shift 4
  db=$(fresh)
  if [ "$pfx" = - ]; then
    env -u HELIX_RELEASE_PREFIX bash "$S" "$WI" "$db" "$@" >"$tmp/out" 2>"$tmp/err"; rc=$?
  else
    HELIX_RELEASE_PREFIX=$pfx bash "$S" "$WI" "$db" "$@" >"$tmp/out" 2>"$tmp/err"; rc=$?
  fi
  if [ "$rc" = "$want" ] && grep -q -- "$pat" "$tmp/err" && [ ! -s "$tmp/out" ]; then ok "$name"
  else bad "$name" "rc=$rc want=$want stderr=$(head -c 200 "$tmp/err") stdout-bytes=$(wc -c <"$tmp/out")"; fi
}
P=${OPEN%-*}
refuse "the prefix unset is refused" 3 "HELIX_RELEASE_PREFIX must be set to $P" - "$OPEN" "$OBS" "$PROBE"
refuse "a wrong prefix is refused" 3 "HELIX_RELEASE_PREFIX must be set to $P" "X$P" "$OPEN" "$OBS" "$PROBE"
refuse "an <open> of Type Bug is refused" 3 "<open item id> must be of Type Task (got Bug)" "$P" "$BUG" "$OBS" "$PROBE"
refuse "a <probe> of Type Bug is refused" 3 "<probe item id> must be of Type Task (got Bug)" "$P" "$OPEN" "$OBS" "$BUG"
refuse "an <obsolete> without obsolete_details is refused" 3 "has no obsolete_details row" "$P" "$OPEN" "$PROBE" "$BUG"

# the full run reproduces the committed evidence
mask(){ sed -E 's/^(  created_at after:  ).*/\1<close time>/' "$1"; }
db=$(fresh)
HELIX_RELEASE_PREFIX=$P bash "$S" "$WI" "$db" "$OPEN" "$OBS" "$PROBE" >"$tmp/run" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "the full run exits 0" || bad "the full run exits 0" "rc=$rc $(tail -n 2 "$tmp/run")"
if cmp -s <(mask "$tmp/run") <(mask "$D/engine_repro.txt"); then ok "the run equals the committed engine_repro.txt (created_at after masked)"
else bad "the run equals the committed engine_repro.txt" "$(diff <(mask "$tmp/run") <(mask "$D/engine_repro.txt") | head -n 6 | tr '\n' ' ')"; fi
# the mask hides exactly one line and the verdict line is not masked
[ "$(grep -c '^  created_at after:  ' "$tmp/run")" = 1 ] && grep -q '^  created_at changed by close: yes$' "$tmp/run" \
  && ok "one masked line; the G1 verdict reads 'changed by close: yes'" || bad "one masked line; the G1 verdict" "$(grep 'created_at' "$tmp/run" | tr '\n' ' ')"
# control needle: the comparison sees a real difference (the round-4 evidence names the v4 script)
if cmp -s <(mask "$tmp/run") <(mask docs/qa/tracker_intake_2026_11_12_v4/engine_repro.txt); then bad "control needle: the v4 evidence differs" "the comparison found no difference"
else ok "control needle: the v4 evidence differs"; fi
sum1=$(sha256sum "$REAL" | cut -d' ' -f1)
[ "$sum0" = "$sum1" ] && ok "the tracked database is unchanged" || bad "the tracked database is unchanged" "$sum0 -> $sum1"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
