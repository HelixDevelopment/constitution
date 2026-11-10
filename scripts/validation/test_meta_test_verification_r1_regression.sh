#!/bin/bash
# Purpose : CON-120 regression guard for scripts/validation/meta_test_verification.sh
#           (the paired-mutation meta-test of scripts/validation/run_verification.sh):
#           the meta-test never changes the tree it checks -- no renamed
#           submodule, no edited tracked gate script -- even when it is stopped
#           with TERM or KILL at any moment; it writes only under $TMPDIR; its
#           mutations are real (a weakened gate that parses, not a syntax
#           error); it fails when the gate is blind to a missing required
#           submodule or always fails; and on its PASS path the summary line
#           is printed last (CON-118 class, review round 2 finding R2-F5-A).
# Forensic: before the fix the meta-test renamed submodules/verification in
#           place and ran `sed -i` on the tracked run_verification.sh, with no
#           trap; measured 2026-11-06 on a scratch tree, a TERM at 0.02 s left
#           the submodule renamed and a TERM at 0.12, 0.25 and 0.30 s left the
#           tracked gate mutated (4 of 15 delays). Its "mutation 2" seds also
#           rewrote every `fi`/`else` on every line, so the mutated gate was a
#           syntax error that fails whatever the gate checks.
# Known gap (stated, not fixed; CON-120 review round 3, FU-7): SIGKILL cannot
#           run a trap, so after a KILL the scratch root stays under $TMPDIR.
#           It holds only SYMLINKS to the real submodules and a copy of the
#           gate (measured: 503 symlinks over 30 runs). `rm -rf` (GNU and
#           uutils) removes the links and leaves their targets alone, so a
#           later cleanup with it is safe; a tool that FOLLOWS links
#           (`find -L`, `cp -rL`, `chmod -R` with -L) would reach the checked
#           tree. The checked tree itself never changes (G-KILL below).
# Usage   : bash scripts/validation/test_meta_test_verification_r1_regression.sh
#           Exit 0 when every check passes, 1 otherwise. The last line is the
#           summary line.
# Inputs  : none. Builds a throwaway fake constitution tree under a temp dir
#           (git repo, the REAL meta-test and gate copied in, one directory per
#           required submodule); never this project's tree.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MTV="$HERE/meta_test_verification.sh"
GATE="$HERE/run_verification.sh"
RUNNER="$ROOT/scripts/full_suite/run_full_suite.py"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }

TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT

for p in "$MTV" "$GATE" "$RUNNER"; do [ -f "$p" ] || notok "control needle: $p not found"; done
[ "$fail" = 0 ] && ok "control needle: meta-test, gate and full-suite runner resolve"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }

# mktree DIR [GATEFILE]: a fake constitution tree whose gate passes.
mktree() {
  local d=$1 gate=${2:-$GATE} mtv=${3:-$MTV} s p
  mkdir -p "$d/scripts/validation" "$d/submodules"
  cp "$mtv" "$d/scripts/validation/meta_test_verification.sh"
  cp "$gate" "$d/scripts/validation/run_verification.sh"
  for s in $(sed -n '/^REQUIRED_SUBMODULES=(/,/^)/p' "$GATE" | grep -o '"[^"]*"' | tr -d '"'); do mkdir -p "$d/submodules/$s"; done
  for p in $(grep -oE '\[ -f [A-Za-z0-9_./-]+ \]' "$GATE" | awk '{print $3}' | sort -u); do
    mkdir -p "$d/submodules/$(dirname "$p")"; printf 'x\n' > "$d/submodules/$p"
  done
  g init --quiet "$d"; g -C "$d" add -A; g -C "$d" commit --quiet -m base
}
# snap DIR: everything the meta-test must never change (tracked state, submodule names, gate bytes).
snap() {
  { g -C "$1" status --porcelain --untracked-files=all; ls -A "$1/submodules"; sha256sum < "$1/scripts/validation/run_verification.sh"; } 2>&1
}

T1="$TMP/t1"; mktree "$T1"
if bash "$T1/scripts/validation/run_verification.sh" >/dev/null 2>&1; then ok "control needle: the fake tree's real gate passes (every required submodule present)"
else notok "control needle: the fake tree's gate fails before any mutation"; fi
BASE=$(snap "$T1")
mkdir -p "$TMP/tt"

# G1: a full run passes, changes nothing, leaves nothing in TMPDIR, and its summary is last.
T0=$(date +%s.%N)
OUT=$(TMPDIR="$TMP/tt" bash "$T1/scripts/validation/meta_test_verification.sh" 2>&1); RC=$?
RUNS=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.3f", b - a }')
printf '%s\n' "$OUT" > "$TMP/g1.out"
[ "$RC" = 0 ] && ok "G1 full run exits 0" || notok "G1 full run exit $RC: $(printf '%s' "$OUT" | tail -3 | tr '\n' '|')"
[ "$(snap "$T1")" = "$BASE" ] && ok "G1 the checked tree is unchanged after a full run" || notok "G1 the checked tree changed: $(snap "$T1" | tr '\n' '|')"
[ -z "$(ls -A "$TMP/tt")" ] && ok "G1 nothing left under TMPDIR" || notok "G1 left under TMPDIR: $(ls -A "$TMP/tt" | tr '\n' ' ')"
J=$(python3 -I - "$RUNNER" "$TMP/g1.out" "$RC" <<'PYEOF'
import importlib.util, sys
s = importlib.util.spec_from_file_location("rfs", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
v = m.judge(int(sys.argv[3]), False, open(sys.argv[2]).read(), "bash")
print("%s %s" % (v[0], v[1]))
PYEOF
)
[ "$J" = "PASS " ] && ok "G1 the full-suite runner judges the PASS output PASS (summary line last)" || notok "G1 the full-suite runner judges '$J'"
case "$OUT" in *"weakened gate parses"*) ok "G1 mutation 2 is a real mutation (the weakened gate parses)" ;;
  *) notok "G1 output does not show that the mutation-2 gate parses" ;; esac

# G2 / G3: stopped with TERM or KILL at any moment, the checked tree never changes.
# The delays are scaled to the MEASURED run time of G1 ($RUNS s): 14 points from
# 2% to 98% of it, so the last mutation and the summary are interrupted too
# (review round 3, FU-6: fixed delays that stopped at 0.60 s left the last third
# of a 1.01 s run untested). A control needle checks the run was measurable.
DELAYS=$(awk -v r="$RUNS" 'BEGIN { split("0.02 0.07 0.12 0.18 0.25 0.32 0.40 0.48 0.56 0.64 0.72 0.80 0.90 0.98", f, " "); for (i = 1; i <= 14; i++) printf "%.3f ", r * f[i] }')
case "$RUNS" in 0.000|"") notok "control needle: the full run took '$RUNS' s; the delays cannot be scaled" ;;
  *) ok "control needle: full run $RUNS s; signal delays $DELAYS" ;; esac
for sig in TERM KILL; do
  bad=""
  for d in $DELAYS; do
    mkdir -p "$TMP/tt_$sig"
    TMPDIR="$TMP/tt_$sig" timeout -s "$sig" "$d" bash "$T1/scripts/validation/meta_test_verification.sh" >/dev/null 2>&1
    [ "$(snap "$T1")" = "$BASE" ] || { bad="$bad $d"; g -C "$T1" checkout -q -- .; [ -d "$T1/submodules/verification.mut.bak" ] && mv "$T1/submodules/verification.mut.bak" "$T1/submodules/verification"; g -C "$T1" clean -qfd; }
    if [ "$sig" = TERM ] && [ -n "$(ls -A "$TMP/tt_$sig")" ]; then bad="$bad $d(tmpdir-left)"; fi
    rm -rf "${TMP:?}/tt_$sig"
  done
  if [ -z "$bad" ]; then ok "G-$sig stopped by $sig at 14 delays (2%..98% of the run): the checked tree never changed${sig:+}"
  else notok "G-$sig stopped by $sig: the checked tree changed (or scratch left) at delay(s)$bad"; fi
done

# B1: a gate blind to a missing 'verification' submodule must make the meta-test fail.
python3 -I - "$GATE" "$TMP/gate_blind.sh" <<'PYEOF'
import sys
c = open(sys.argv[1]).read()
for old in ('    "verification"\n',
            'run_check "verification (agent-skills)" \\\n    "ls -la verification/ && [ -f verification/README.md ]" \\\n    "${SUBMODULES_DIR}"\n'):
    assert c.count(old) == 1, old
    c = c.replace(old, "")
open(sys.argv[2], "w").write(c)
PYEOF
T2="$TMP/t2"; mktree "$T2" "$TMP/gate_blind.sh"
TMPDIR="$TMP/tt" bash "$T2/scripts/validation/meta_test_verification.sh" > "$TMP/b1.out" 2>&1; RC=$?
[ "$RC" != 0 ] && ok "B1 gate blind to a missing required submodule -> meta-test exits $RC" || notok "B1 meta-test passed a gate that ignores a missing required submodule"
# B2: a gate that always fails must make the meta-test fail.
printf '#!/usr/bin/env bash\necho "always FAIL"\nexit 1\n' > "$TMP/gate_false.sh"
T3="$TMP/t3"; mktree "$T3" "$TMP/gate_false.sh"
TMPDIR="$TMP/tt" bash "$T3/scripts/validation/meta_test_verification.sh" > "$TMP/b2.out" 2>&1; RC=$?
[ "$RC" != 0 ] && ok "B2 gate that always fails -> meta-test exits $RC" || notok "B2 meta-test passed a gate that always fails"

# B3 / B4 (review round 3, killing MT1 and MT9): the two ways the meta-test could
# say PASS while mutation 2 proved nothing.
# B3: a gate that fails at EVERY root without a .git (it passes on the fake tree,
#     which is a git repo, and fails on every scratch root for a reason that is
#     NOT the missing submodule): mutation 2's weakened gate fails there too, so
#     the meta-test must FAIL.
# B4: a gate whose text no longer matches the mutation-2 anchors but which still
#     detects the missing submodule: the meta-test must FAIL closed ("update the
#     mutation anchors"), never pass with mutation 2 silently unrun.
python3 -I - "$GATE" "$TMP/gate_needs_git.sh" "$TMP/gate_reformatted.sh" <<'PYEOF'
import sys
c = open(sys.argv[1]).read()
anchor = 'SUBMODULES_DIR="${CONSTITUTION_ROOT}/submodules"\n'
assert c.count(anchor) == 1
open(sys.argv[2], "w").write(c.replace(anchor, anchor + '[ -e "${CONSTITUTION_ROOT}/.git" ] || { echo "not a checkout"; exit 1; }\n'))
old = '    "verification"\n'
assert c.count(old) == 1
open(sys.argv[3], "w").write(c.replace(old, '    "verification"   # agent-skills\n'))
PYEOF
# b34 MTVFILE: prints "needs_git_rc reformatted_rc ctl1 ctl2" (meta-test exit codes
# on the two fixtures; ctl = the fixture gate passes on its fake tree, rc 0).
b34() {
  local fx rcs="" ctl="" T
  for fx in needs_git reformatted; do
    T="$TMP/b34_$fx"; rm -rf "${T:?}"; mktree "$T" "$TMP/gate_$fx.sh" "$1"
    bash "$T/scripts/validation/run_verification.sh" > /dev/null 2>&1; ctl="$ctl $?"
    mkdir -p "$TMP/tt34"
    TMPDIR="$TMP/tt34" bash "$T/scripts/validation/meta_test_verification.sh" > "$TMP/b34_$fx.out" 2>&1; rcs="$rcs $?"
  done
  echo "$rcs |$ctl"
}
R34=$(b34 "$MTV"); set -- ${R34%%|*}; C34=${R34##*|}
[ "$C34" = " 0 0" ] && ok "control needle: both B3/B4 fixture gates pass on their fake trees (rc 0)" || notok "control needle: B3/B4 fixture gates rc '$C34'"
[ "${1:-0}" != 0 ] && ok "B3 a gate that fails at any root without .git -> meta-test exits $1" || notok "B3 meta-test passed a gate that fails at every scratch root"
[ "${2:-0}" != 0 ] && ok "B4 a gate whose text no longer matches the mutation-2 anchors -> meta-test exits $2 (fail closed)" || notok "B4 meta-test passed with mutation 2 silently unrun"

# Paired mutations of the meta-test itself: each must be caught by the named check.
mtv_mutant() {  # NAME OLD NEW -> path of the mutant meta-test, or "" when the anchor is not unique
  local f="$TMP/mtvmut_$1.sh"
  if python3 -I - "$MTV" "$f" "$2" "$3" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
c = open(src, encoding="utf-8").read()
if c.count(old) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
  then echo "$f"; fi
}
mtv_mutation() {  # NAME NEEDED_INDEX(1=B3, 2=B4) OLD NEW
  local m r
  m=$(mtv_mutant "$1" "$3" "$4")
  if [ -z "$m" ]; then notok "mutation $1: anchor not unique in the meta-test (not a catch)"; return; fi
  r=$(b34 "$m"); set -- $2 ${r%%|*}
  # $1 = index, $2 = B3 rc, $3 = B4 rc: the mutant is caught when the named fixture now exits 0.
  [ "$(eval echo "\${$(( $1 + 1 ))}")" = 0 ] && ok "mutation (meta-test) caught by B$(( $1 + 2 )): the mutant exits 0 on its fixture" \
    || notok "mutation (meta-test) SURVIVED B$(( $1 + 2 )): rcs '${r%%|*}'"
}
mtv_mutation MT1_mut2_verdict_ignored 1 'notok "weakened gate still exits non-zero; the real gate'"'"'s mutation-1 result' 'ok "weakened gate still exits non-zero; the real gate'"'"'s mutation-1 result'
mtv_mutation MT9_anchor_failure_ok 2 'notok "could not build the weakened gate (gate text changed; update the mutation anchors)"' 'ok "could not build the weakened gate (gate text changed; update the mutation anchors)"'

echo "=== meta_test_verification regression guard (CON-120): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
