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
  local d=$1 gate=${2:-$GATE} s p
  mkdir -p "$d/scripts/validation" "$d/submodules"
  cp "$MTV" "$d/scripts/validation/meta_test_verification.sh"
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
OUT=$(TMPDIR="$TMP/tt" bash "$T1/scripts/validation/meta_test_verification.sh" 2>&1); RC=$?
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
for sig in TERM KILL; do
  bad=""
  for d in 0.02 0.05 0.08 0.11 0.14 0.17 0.20 0.25 0.30 0.35 0.45 0.60; do
    mkdir -p "$TMP/tt_$sig"
    TMPDIR="$TMP/tt_$sig" timeout -s "$sig" "$d" bash "$T1/scripts/validation/meta_test_verification.sh" >/dev/null 2>&1
    [ "$(snap "$T1")" = "$BASE" ] || { bad="$bad $d"; g -C "$T1" checkout -q -- .; [ -d "$T1/submodules/verification.mut.bak" ] && mv "$T1/submodules/verification.mut.bak" "$T1/submodules/verification"; g -C "$T1" clean -qfd; }
    if [ "$sig" = TERM ] && [ -n "$(ls -A "$TMP/tt_$sig")" ]; then bad="$bad $d(tmpdir-left)"; fi
    rm -rf "${TMP:?}/tt_$sig"
  done
  if [ -z "$bad" ]; then ok "G-$sig stopped by $sig at 12 delays: the checked tree never changed${sig:+}"
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

echo "=== meta_test_verification regression guard (CON-120): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
