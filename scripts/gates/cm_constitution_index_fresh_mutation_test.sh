#!/usr/bin/env bash
# cm_constitution_index_fresh_mutation_test.sh -- golden + paired §1.1 mutations for
# cm_constitution_index_fresh.sh (CM-CONSTITUTION-INDEX-FRESH, T048 round-4 review R4-01).
#
# The gate is the BUILD-path stage of the index-regeneration seam: a pre-build run FAILs while
# constitution_index.yaml / groups/*.md do not match a fresh generation from Constitution.md
# (anchor_citations.py would otherwise go BLIND on E_INDEX_SHA_MISMATCH at the first use).
#
# Every case runs the REAL gate (or a one-place mutant copy of it) through its CLI against a scratch
# constitution root built from the REAL Constitution.md and the REAL generator; the tracked files
# are never touched (§11.4.84).
#   G1 golden-true : a fresh generation                      -> exit 0 (no false refusal)
#   G2 golden-false: one sentence added inside an anchor body -> exit 1, names "regenerate"
#   G3 golden-false: a group .md edited, checksum still fresh -> exit 1 (content drift) + the generate command
#   G4 BLIND       : Constitution.md absent                  -> exit 2
# Mutations: GM1 the drift-check branch disabled; GM2 the BLIND branch returning 0; GM3 the repair hint
# reverted to regenerate_if_stale.sh (which cannot repair a hand-edited group). Each must
# make >= 1 case fail; the identity copy must pass every case.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROOT="$(cd "$HERE/../.." && pwd)"
GATE="${CM_INDEX_FRESH_UNDER_TEST:-$HERE/cm_constitution_index_fresh.sh}"
ANCHORS="$CROOT/scripts/anchors"
REAL_SOURCE="$CROOT/Constitution.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
for dep in python3 sha256sum; do
  command -v "$dep" >/dev/null 2>&1 || { echo "BLIND: required dependency '$dep' not usable" >&2; exit 2; }
done
[ -f "$GATE" ] || { bad "gate missing at $GATE"; echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1; }
TMP=$(mktemp -d) || { echo "BLIND: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

mkroot() { # mkroot <dir>: scratch root with the REAL anchors scripts and a fresh generation
  mkdir -p "$1/scripts/anchors"
  cp "$ANCHORS"/constitution_generate.py "$ANCHORS"/anchor_lib.py "$ANCHORS"/regenerate_if_stale.sh "$1/scripts/anchors/"
  [ -f "$ANCHORS/__init__.py" ] && cp "$ANCHORS/__init__.py" "$1/scripts/anchors/"
  cp "$REAL_SOURCE" "$1/Constitution.md"
  python3 "$1/scripts/anchors/constitution_generate.py" generate --source "$1/Constitution.md" \
    --groups-dir "$1/groups" --index-out "$1/constitution_index.yaml" >/dev/null 2>&1 \
    || { echo "BLIND: generator failed for $1" >&2; exit 2; }
}
run_cases() { # run_cases <gate>
  local g=$1 r out rc
  r="$TMP/g1"; rm -rf "$r"; mkroot "$r"
  out=$(bash "$g" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then ok "G1 golden-true: a fresh generation passes"; else bad "G1 fresh: rc=$rc out=[$out]"; fi
  r="$TMP/g2"; rm -rf "$r"; mkroot "$r"
  python3 - "$r/Constitution.md" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
m = re.search(r"(?m)^### §11\.4\.108\b.*$", t); assert m
i = t.index("\n", m.end()) + 1
open(p, "w", encoding="utf-8").write(t[:i] + "An amendment that did not regenerate the index.\n" + t[i:])
PY
  out=$(bash "$g" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 1 ] && grep -q 'regenerate' <<<"$out"; then ok "G2 golden-false: an amendment without regeneration FAILs and says how to regenerate"
  else bad "G2 amendment: rc=$rc out=[$out]"; fi
  r="$TMP/g3"; rm -rf "$r"; mkroot "$r"
  f=""; for _m in "$r"/groups/*.md; do f="$_m"; break; done; printf '\nhand edit\n' >> "$f"
  out=$(bash "$g" --root "$r" 2>&1); rc=$?
  # V5 N3: the drift FAIL must print a command that actually repairs drift. regenerate_if_stale.sh answers
  # "fresh ... nothing to do" when only a group was hand-edited (the checksum still matches), so the
  # message must name the generator's own `generate` invocation for THIS root.
  if [ "$rc" -eq 1 ] && grep -qF "constitution_generate.py generate --source $r/Constitution.md --groups-dir $r/groups --index-out $r/constitution_index.yaml" <<<"$out" \
     && ! grep -q 'regenerate_if_stale.sh' <<<"$out"; then
    ok "G3 golden-false: a hand-edited group .md (checksum fresh) FAILs and prints the generator's generate command"
  else bad "G3 group drift: rc=$rc out=[$out]"; fi
  r="$TMP/g4"; rm -rf "$r"; mkroot "$r"; rm -f "$r/Constitution.md"
  out=$(bash "$g" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then ok "G4 BLIND: Constitution.md absent -> exit 2"; else bad "G4 BLIND: rc=$rc out=[$out]"; fi
}
echo "== the real gate =="
run_cases "$GATE"
echo "== paired mutations =="
mutate() { # mutate <name> <old> <new>
  local m="$TMP/mut_$1.sh"
  python3 - "$GATE" "$m" "$2" "$3" <<'PY' || { bad "mutation $1 could not be applied"; return; }
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if old != new and t.count(old) != 1:
    print("target occurs %d times" % t.count(old)); sys.exit(2)
open(dst, "w", encoding="utf-8").write(t.replace(old, new))
PY
  local p0=$PASS f0=$FAIL
  run_cases "$m" > "$TMP/mut_$1.out" 2>&1
  PASS=$p0; FAIL=$f0
  local mf; mf=$(grep -c '^FAIL' "$TMP/mut_$1.out")
  if [ "$1" = GM0_identity ]; then
    if [ "$mf" -eq 0 ]; then ok "mutation runner control: the identity copy passes every case"
    else bad "mutation runner control: the identity copy fails ($(grep -m1 '^FAIL' "$TMP/mut_$1.out"))"; fi
  elif [ "$mf" -gt 0 ]; then ok "MUTATION $1 caught -- $mf case(s) FAIL on the mutant, first: $(grep -m1 '^FAIL' "$TMP/mut_$1.out" | cut -c1-110)"
  else bad "mutation $1 SURVIVED"; fi
}
mutate GM0_identity 'set -uo pipefail' 'set -uo pipefail'
# shellcheck disable=SC2016 # single-quoted literal mutation patterns are intentional
mutate GM1_drift_check_disabled 'if [ "$rc" -ne 0 ]; then' 'if false; then'
# shellcheck disable=SC2016 # single-quoted literal mutation patterns are intentional
mutate GM2_blind_passes 'echo "$GATE: BLIND -- $SOURCE is missing" >&2; exit 2' 'exit 0'
# shellcheck disable=SC2016 # single-quoted literal mutation patterns are intentional
mutate GM3_hint_is_regenerate_if_stale 'python3 $GEN generate --source $SOURCE --groups-dir $ROOT/groups --index-out $ROOT/constitution_index.yaml' 'bash $ROOT/scripts/anchors/regenerate_if_stale.sh --root $ROOT'
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] && echo "MUTATION PAIR VALID"
[ "$FAIL" -eq 0 ]
