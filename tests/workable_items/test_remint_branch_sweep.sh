#!/usr/bin/env bash
# tests/workable_items/test_remint_branch_sweep.sh -- hermetic test of the branch-mutation sweep
# tests/workable_items/remint_branch_sweep.py (round 5, R4-2): the sweep's own logic, not remint_ids.py.
#
# Documentation (section 11.4.18): docs/guides/remint_ids_guide.md, section "Branch sweep".
#
# WHAT  The sweep finds its inputs next to itself (../../scripts/workable-items/remint_ids.py, the suite
#       test_remint_ids.sh and the register remint_branch_equivalents.tsv beside it), so the test copies
#       it into a scratch tree with a FAKE remint_ids.py and a STAND-IN suite (gate-logic fixtures,
#       section 11.4.289(C)(2); they prove the sweep decides correctly, nothing about remint_ids.py).
#       The fake holds one branch of each kind the sweep must classify: tested both ways (KILLED), never
#       tested (SURVIVED), an equivalent mutant (registered, EQUIVALENT), a `while` that never ends when
#       forced True (TIMEOUT), a mutant that breaks the stand-in suite or makes it exit 1 without a
#       FAIL line (SETUP), a comprehension filter, a condition after a
#       non-ASCII character on its line (the byte-offset conversion), a condition holding a comma (a key
#       is never split), a `while True` (skipped) and a function outside the targets (not listed).
#       Cases: the inventory; a full run (per-key verdicts, the tally, exit 1, --out equal to stdout);
#       --only and --only-file subsets; a stale register entry (counted only without --only); a bad
#       register line; usage errors; the unmutated control (a suite that fails without any mutant is a
#       setup error, never a run of KILLED verdicts); a missing source or suite; and the span control
#       needle (a sweep whose span ignores byte offsets stops as a setup error).
# ENV   REMINT_BRANCH_SWEEP  the sweep to test (default: the repository copy; the round-5 RED used a copy)
# EXIT  0 all cases pass; 1 a case failed; 2 setup error, or the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic (section 11.4.289): fake tool and stand-in suite, no engine, no database.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
sweep_src=${REMINT_BRANCH_SWEEP:-$here/remint_branch_sweep.py}
[ -f "$sweep_src" ] || { echo "setup: sweep not found: $sweep_src" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT
mkdir -p "$tmp/swtmp" || exit 2

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }
check() { # check <name> <want-rc> <pattern-or-empty>  (reads $rc and $tmp/out)
  if [ "$rc" != "$2" ]; then bad "$1" "rc=$rc want=$2: $(tr '\n' '|' <"$tmp/out" | cut -c1-400)"; return; fi
  if [ -n "$3" ] && ! grep -Eq -- "$3" "$tmp/out"; then bad "$1" "/$3/ not in: $(tr '\n' '|' <"$tmp/out" | cut -c1-400)"; return; fi
  ok "$1"
}
lacks() { # lacks <name> <fixed-string>  (reads $tmp/out)
  if grep -Fq -- "$2" "$tmp/out"; then bad "$1" "'$2' found in: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; else ok "$1"; fi
}
verdict() { # verdict <name> <key> <want>  (reads $tmp/out: the row of KEY must carry WANT)
  local got
  got=$(awk -F'\t' -v k="$2" '$1 == k { print $3 }' "$tmp/out")
  if [ "$got" = "$3" ]; then ok "$1"; else bad "$1" "key $2: got '$got' want '$3'"; fi
}
sw() { # sw <tree> <args...>: run the sweep copy of a tree; output in $tmp/out, exit status in $rc
  local t=$1; shift
  (cd "$t" && TMPDIR="$tmp/swtmp" python3 -I "$t/tests/workable_items/remint_branch_sweep.py" "$@") >"$tmp/out" 2>&1
  rc=$?
}

fake_tool() { # the fake remint_ids.py (a fixture, never a tool)
  cat <<'PY'
"""fixture: a fake remint_ids.py for the branch-sweep test (not a tool)"""


def make_plan(n):
    if n > 2:
        return "big"
    return "small"


def block_steps(n):
    if isinstance(n, int) and n == 7:
        return "seven"
    return "other"


def lifecycle_steps(s):
    if not s:
        return ""
    return s.strip()


class Rewriter:
    def text(self, s):
        dash = "–"; got = (1 if len(s) > 0 else 0)
        return got


def cmd_verify(n):
    i = 0
    while i < n:
        i += 1
    return i


def check_history(n):
    if n < 0:
        return "boom"
    return "ok"


def check_od(n):
    if n > 100:
        return "quiet"
    return "fine"


def cmd_replay(xs):
    return [x for x in xs if x > 0]


def v_text_rules():
    while True:
        break
    return "done"


def helper(n):
    if n:
        return 1
    return 0
PY
}
stand_in_suite() { # the stand-in for test_remint_ids.sh (a fixture)
  cat <<'SH'
#!/usr/bin/env bash
# fixture: a stand-in for test_remint_ids.sh in the branch-sweep test (section 11.4.289(C)(2))
set -u
t=${REMINT_IDS:?}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
if [ "${REMINT_IDS_FAILFAST:-}" != 1 ]; then echo "setup: the sweep must set REMINT_IDS_FAILFAST=1"; exit 2; fi
if [ -e "$here/broken" ]; then echo "FAIL control: this suite fails on every input"; exit 1; fi
# r <expression>: load the module under test and print the value of one of the fixed expressions written
# below (eval sees only these literals, never any input)
r() { python3 -I -c 'import importlib.util, sys
s = importlib.util.spec_from_file_location("m", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(eval(sys.argv[2], {"m": m}))' "$t" "$1"; }
fail() { echo "FAIL $1"; exit 1; }
if [ -e "$here/minimal" ]; then
  [ "$(r 'm.make_plan(3)')" = big ] || fail "make_plan 3"
  [ "$(r 'm.make_plan(1)')" = small ] || fail "make_plan 1"
  echo "RESULT: pass"; exit 0
fi
if [ "$(r 'm.check_history(1)')" = boom ]; then echo "setup: the instrument broke"; exit 2; fi
[ "$(r 'm.check_history(1)')" = ok ] || fail "check_history 1"
if [ "$(r 'm.check_od(1)')" = quiet ]; then echo "the suite stopped without a verdict"; exit 1; fi
[ "$(r 'm.cmd_replay([-1, 2])')" = "[2]" ] || fail "cmd_replay"
[ "$(r 'm.make_plan(3)')" = big ] || fail "make_plan 3"
[ "$(r 'm.make_plan(1)')" = small ] || fail "make_plan 1"
[ "$(r 'm.lifecycle_steps(" a ")')" = a ] || fail "lifecycle_steps"
[ "$(r 'm.Rewriter().text("x")')" = 1 ] || fail "text x"
[ "$(r 'm.Rewriter().text("")')" = 0 ] || fail "text empty"
[ "$(r 'm.cmd_verify(3)')" = 3 ] || fail "cmd_verify 3"
echo "RESULT: pass"
SH
}
mktree() { # mktree <dir> [minimal]: a scratch tree holding the sweep copy, the fake tool and the stand-in suite
  local d=$1
  mkdir -p "$d/tests/workable_items" "$d/scripts/workable-items" || exit 2
  cp "$sweep_src" "$d/tests/workable_items/remint_branch_sweep.py" || exit 2
  if [ "${2:-}" = minimal ]; then
    printf 'def make_plan(n):\n    if n > 2:\n        return "big"\n    return "small"\n' >"$d/scripts/workable-items/remint_ids.py"
    : >"$d/tests/workable_items/minimal"
  else
    fake_tool >"$d/scripts/workable-items/remint_ids.py"
  fi
  stand_in_suite >"$d/tests/workable_items/test_remint_ids.sh"
  printf '# register of the test tree\n' >"$d/tests/workable_items/remint_branch_equivalents.tsv"
}
reg() { printf '%s\t%s\n' "$2" "$3" >>"$1/tests/workable_items/remint_branch_equivalents.tsv"; }

K_PT='make_plan|if|n > 2#1=True'
K_PF='make_plan|if|n > 2#1=False'
K_BT='block_steps|if|isinstance(n, int) and n == 7#1=True'
K_BF='block_steps|if|isinstance(n, int) and n == 7#1=False'
K_LT='lifecycle_steps|if|not s#1=True'
K_LF='lifecycle_steps|if|not s#1=False'
K_RT='Rewriter|ifexp|len(s) > 0#1=True'
K_RF='Rewriter|ifexp|len(s) > 0#1=False'
K_VT='cmd_verify|while|i < n#1=True'
K_VF='cmd_verify|while|i < n#1=False'
K_HT='check_history|if|n < 0#1=True'
K_HF='check_history|if|n < 0#1=False'
K_OT='check_od|if|n > 100#1=True'
K_OF='check_od|if|n > 100#1=False'
K_CT='cmd_replay|compif|x > 0#1=True'
K_CF='cmd_replay|compif|x > 0#1=False'

A=$tmp/a
mktree "$A"
reg "$A" "$K_LF" "fixture: the guard returns what the fall-through returns for the empty string"
reg "$A" "$K_HF" "fixture: no input the stand-in suite gives is negative"
reg "$A" "$K_OF" "fixture: no input the stand-in suite gives is above 100"

# 1. the inventory
sw "$A" --list
check "list: the inventory counts every target branch point, two mutants each" 0 '^INVENTORY: mutants=16 branch-points=8 skipped=1$'
check "list: a condition after a non-ASCII character on its line keeps its exact key" 0 '^Rewriter\|ifexp\|len\(s\) > 0#1=True	line '
check "list: a key holding a comma is printed whole" 0 '^block_steps\|if\|isinstance\(n, int\) and n == 7#1=False	line '
check "list: a while True loop is listed as skipped" 0 '^SKIPPED	v_text_rules\|while\|True \(line [0-9]+\)$'
lacks "list: a function outside the targets is not listed" 'helper|'

# 2. a full run: every verdict, the tally, exit 1, and --out
sw "$A" --jobs 2 --timeout 4 --out "$tmp/a.tsv"
check "full run: an unregistered survivor and a SETUP verdict fail the sweep" 1 '^RESULT: mutants=16 EQUIVALENT=3 KILLED=8 SETUP=2 SURVIVED=2 TIMEOUT=1 skipped=1 stale-register=0 FAIL$'
check "full run: the unmutated control is reported" 1 '^CONTROL: the unmutated source passes the suite$'
verdict "full run: a branch tested both ways is killed when forced True" "$K_PT" KILLED
verdict "full run: a branch tested both ways is killed when forced False" "$K_PF" KILLED
verdict "full run: an untested branch survives when forced True" "$K_BT" SURVIVED
verdict "full run: an untested branch survives when forced False" "$K_BF" SURVIVED
verdict "full run: a tested guard is killed" "$K_LT" KILLED
verdict "full run: a registered survivor is EQUIVALENT" "$K_LF" EQUIVALENT
verdict "full run: a conditional expression is killed when forced True" "$K_RT" KILLED
verdict "full run: a conditional expression is killed when forced False" "$K_RF" KILLED
verdict "full run: a loop forced to run forever is a TIMEOUT" "$K_VT" TIMEOUT
verdict "full run: a loop forced never to run is killed" "$K_VF" KILLED
verdict "full run: a mutant that breaks the suite is a SETUP verdict" "$K_HT" SETUP
verdict "full run: a second registered survivor is EQUIVALENT" "$K_HF" EQUIVALENT
verdict "full run: a suite exit 1 without a FAIL line is a SETUP verdict, never KILLED" "$K_OT" SETUP
verdict "full run: a third registered survivor is EQUIVALENT" "$K_OF" EQUIVALENT
verdict "full run: a comprehension filter is killed when forced True" "$K_CT" KILLED
verdict "full run: a comprehension filter is killed when forced False" "$K_CF" KILLED
same_rows=$(grep -P '\t(KILLED|SURVIVED|SETUP|TIMEOUT|EQUIVALENT)\t' "$tmp/out")
if [ -f "$tmp/a.tsv" ] && [ "$(cat "$tmp/a.tsv")" = "$same_rows" ] && [ "$(wc -l <"$tmp/a.tsv")" -eq 16 ]; then
  ok "full run: --out holds the same 16 rows as stdout"
else
  bad "full run: --out holds the same 16 rows as stdout" "$(tr '\n' '|' <"$tmp/a.tsv" 2>/dev/null | cut -c1-300)"
fi

# 3. subsets
sw "$A" --jobs 2 --timeout 4 --only "$K_PT" --only "$K_LF" --only "$K_VT"
check "--only: killed, equivalent and timeout verdicts pass the sweep" 0 '^RESULT: mutants=3 EQUIVALENT=1 KILLED=1 TIMEOUT=1 skipped=1 stale-register=0 PASS$'
sw "$A" --only "$K_BT"
check "--only: a key holding a comma is never split, and its survivor fails the sweep" 1 '^RESULT: mutants=1 SURVIVED=1 .* FAIL$'
sw "$A" --only "$K_HT"
check "--only: a SETUP verdict fails the sweep" 1 '^RESULT: mutants=1 SETUP=1 .* FAIL$'
printf '%s\tline 1\n%s\tKILLED\tnote\n' "$K_PF" "$K_RT" >"$tmp/keys.txt"
sw "$A" --only-file "$tmp/keys.txt"
check "--only-file: the first TAB field of each line names a key" 0 '^RESULT: mutants=2 KILLED=2 .* PASS$'

# 4. usage and setup errors exit 2
sw "$A" --only 'no|if|such#1=True'
check "usage: an unknown --only key is a setup error" 2 'not in the inventory'
sw "$A" --only-file "$tmp/no_such_file"
check "usage: a missing --only-file is a setup error" 2 '^setup: --only-file'
sw "$A" --jobs 0
check "usage: --jobs 0 is a setup error" 2 '^setup: --jobs'

# 5. the register
B=$tmp/b
mktree "$B" minimal
sw "$B" --jobs 2
check "register: a minimal tree with every branch killed passes" 0 '^RESULT: mutants=2 KILLED=2 skipped=0 stale-register=0 PASS$'
reg "$B" 'gone|if|x#1=True' "a branch that no longer exists"
sw "$B" --jobs 2
check "register: a stale entry fails a full run" 1 '^RESULT: mutants=2 KILLED=2 skipped=0 stale-register=1 FAIL$'
check "register: a stale entry is named" 1 '^STALE-REGISTER	gone\|if\|x#1=True$'
sw "$B" --only 'make_plan|if|n > 2#1=True'
check "register: a stale entry is reported but not counted with --only" 0 '^RESULT: mutants=1 KILLED=1 skipped=0 stale-register=1 PASS$'
printf 'make_plan|if|n > 2#1=True no tab here\n' >>"$B/tests/workable_items/remint_branch_equivalents.tsv"
sw "$B" --jobs 2
check "register: a line without a TAB and a reason is a setup error" 2 '^setup: .*want <key>TAB<reason>'

G=$tmp/g
mktree "$G" minimal
reg "$G" 'make_plan|if|n > 2#1=False' "a register entry for a mutant the suite kills"
sw "$G" --jobs 2
check "register: an entry does not turn a killed mutant into an equivalent" 0 '^RESULT: mutants=2 KILLED=2 skipped=0 stale-register=0 PASS$'

# 6. the unmutated control: a suite that fails without any mutant must never yield KILLED verdicts
C=$tmp/c
mktree "$C" minimal
: >"$C/tests/workable_items/broken"
sw "$C" --jobs 2
check "control: a suite that fails on the unmutated source is a setup error" 2 '^setup: the unmutated source does not pass the suite'
lacks "control: no mutant is run when the control fails" 'KILLED'

# 7. missing inputs
D=$tmp/d
mktree "$D" minimal
safe_rm_rf "${D:?}/scripts/workable-items/remint_ids.py" || exit 2
sw "$D" --list
check "setup: a missing remint_ids.py is a setup error" 2 '^setup: cannot read '
E=$tmp/e
mktree "$E" minimal
safe_rm_rf "${E:?}/tests/workable_items/test_remint_ids.sh" || exit 2
sw "$E" --jobs 2
check "setup: a missing suite is a setup error" 2 '^setup: the suite is missing'

# 8. the span control needle: a sweep that takes the parser's byte offsets as character offsets
# must stop as a setup error on the condition after the en dash, never mutate some other text
F=$tmp/f
mktree "$F"
# (a sweep that lacks the conversion line has lost the byte-offset conversion: a FAIL, never a setup error)
if python3 -I - "$F/tests/workable_items/remint_branch_sweep.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'return lo[lineno] + len(lines[lineno - 1].encode("utf-8")[:col].decode("utf-8"))'
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, "return lo[lineno] + col"))
PY
then
  sw "$F" --list
  check "needle: a span taken from byte offsets as characters is a setup error" 2 '^setup: the span of the condition at line [0-9]+ does not parse back to it'
else
  bad "needle: a span taken from byte offsets as characters is a setup error" "the sweep has no byte-offset conversion line"
fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
