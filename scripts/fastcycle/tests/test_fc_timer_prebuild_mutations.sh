#!/bin/bash
# Purpose : paired §1.1 mutation runner for test_fc_timer_prebuild_red.sh (T048 restart
#           round-1, R1-B1 instance 1). Each mutant is a COPY of pre_build_verification.sh
#           placed in a shadow tree (every other path a symlink into this checkout, so the
#           mutant's own ANDROID_ROOT resolves exactly like the real file's), run through the
#           UNMODIFIED test with FC_TIMER_RED_PREBUILD=<mutant>; the test must exit non-zero
#           with a FAIL line naming the expected assertion.
#             MD  (reviewer, verbatim): every _fc_section_boundary call deleted -> no rows.
#             MDo (fixer): log_section times every section under ONE constant id -> the TSV no
#                 longer follows the run's own banner order.
#           Part 2 (archived evidence) is disabled for mutants -- an archived run cannot see a
#           source mutation; Part 1's live bounded run is what must catch it.
# Usage   : bash test_fc_timer_prebuild_mutations.sh   (exit 0 = all killed for the right reason)
#           FC_TIMER_RED_BOUND_S (default 60) bounds each live run.
# Runtime : ~3-4 min (control + 2 mutants, one bounded pre_build run each). Background it.
# Safety  : the shadow tree is mktemp; the pre_build copy writes its TSV under the test's own
#           private CAPTURE_TRIPLET_TSV_ROOT. Nothing in the checkout is modified.
# Every anchor below is LITERAL source text -- never expanded here.
# shellcheck disable=SC2016
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
REL="device/rockchip/rk3588/tests"
PBV="$ROOT/$REL/pre_build_verification.sh"
TEST="$HERE/test_fc_timer_prebuild_red.sh"
[ -f "$PBV" ] && [ -f "$TEST" ] || { echo "FATAL: inputs missing"; exit 2; }
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
fail=0
export FC_TIMER_RED_BOUND_S="${FC_TIMER_RED_BOUND_S:-60}"

# shadow <dir> <pbv content file>: <dir>/<every top-level entry> -> symlinks, except the path
# down to $REL, which is real directories whose OTHER entries are symlinks.
shadow() {
  local d="$1" src="$2" cur="$ROOT" out="$1" part e
  mkdir -p "$d"
  for part in device rockchip rk3588 tests; do
    for e in "$cur"/* "$cur"/.[!.]*; do
      [ -e "$e" ] || [ -L "$e" ] || continue
      [ "$(basename -- "$e")" = "$part" ] && continue
      # never expose the real .git to the shadow worktree: a git command run there could
      # refresh/lock the live index (git reads are then honestly "not a repository").
      [ "$(basename -- "$e")" = .git ] && continue
      ln -s "$e" "$out/$(basename -- "$e")"
    done
    cur="$cur/$part"; out="$out/$part"; mkdir -p "$out"
  done
  for e in "$cur"/* "$cur"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    [ "$(basename -- "$e")" = pre_build_verification.sh ] && continue
    ln -s "$e" "$out/$(basename -- "$e")"
  done
  cp -- "$src" "$out/pre_build_verification.sh"
}

run_case() {  # <id> <pbv content> <expected FAIL substring or "">
  local id="$1" src="$2" want="$3" rc out="$TMP/$1.out"
  shadow "$TMP/root_$id" "$src"
  FC_TIMER_RED_PREBUILD="$TMP/root_$id/$REL/pre_build_verification.sh" FC_TIMER_RED_EVIDENCE_DIR="$TMP/no-evidence" \
    bash "$TEST" >"$out" 2>&1; rc=$?
  if [ -z "$want" ]; then
    if [ "$rc" = 0 ]; then echo "ok   control: the unmutated copy passes through the shadow-tree path"
    else echo "NOT ok control: the unmutated copy FAILS through the shadow path (rc=$rc)"; grep '^FAIL' "$out" | head -3; exit 1; fi
  elif [ "$rc" != 0 ] && grep '^FAIL' "$out" | grep -qF -- "$want"; then
    echo "ok   $id killed (rc=$rc): $(grep '^FAIL' "$out" | grep -F -- "$want" | head -n1 | cut -c1-150)"
  else
    echo "NOT ok $id SURVIVED or killed for the wrong reason (rc=$rc, wanted FAIL naming '$want')"; grep '^FAIL' "$out" | head -3; fail=1
  fi
}

run_case control "$PBV" ""
python3 - "$PBV" "$TMP/md.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read().split("\n")
out = [re.sub(r"^(\s*)_fc_section_boundary\b.*$", r"\1:", l) for l in s]
assert out != s
open(sys.argv[2], "w").write("\n".join(out))
PY
run_case MD "$TMP/md.sh" "live: the pinned TSV exists"
python3 - "$PBV" "$TMP/mdo.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = 'log_section() {\n    _fc_section_boundary "$1"'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, 'log_section() {\n    _fc_section_boundary "SECTION ZZZ: constant"', 1))
PY
run_case MDo "$TMP/mdo.sh" "live: the TSV's ordered section codes"

echo
if [ "$fail" = 0 ]; then echo "=== PREBUILD TIMER MUTATIONS: ALL KILLED ==="; else echo "=== PREBUILD TIMER MUTATIONS: SURVIVORS ABOVE ==="; fi
exit "$fail"
