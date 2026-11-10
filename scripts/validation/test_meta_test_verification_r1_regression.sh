#!/bin/bash
# Purpose : CON-128 regression guard for scripts/validation/meta_test_verification.sh
#           (the paired-mutation meta-test of scripts/validation/run_verification.sh):
#           the meta-test never changes the tree it checks -- no renamed
#           submodule, no edited tracked gate script -- even when it is stopped
#           with TERM or KILL at any moment; it writes only under $TMPDIR; its
#           mutations are real (a weakened gate that parses, not a syntax
#           error); it fails when the gate is blind to a missing required
#           submodule or always fails; and on its PASS path the summary line
#           is printed last (CON-126 class, review round 2 finding R2-F5-A).
#           Round 5 (CON-128 review round 4, F1: reviewer mutants Ma and Mb
#           survived): every decision point of the meta-test has its own
#           fixture, pinned to one verdict (exit code, fail count, the one
#           failure line it must print, nothing left under TMPDIR), and one
#           paired mutant (list below the fixtures); a TERM that hits the
#           cleanup's rm no longer leaves the scratch root (SCLEAN).
# Forensic: before the fix the meta-test renamed submodules/verification in
#           place and ran `sed -i` on the tracked run_verification.sh, with no
#           trap; measured 2026-11-06 on a scratch tree, a TERM at 0.02 s left
#           the submodule renamed and a TERM at 0.12, 0.25 and 0.30 s left the
#           tracked gate mutated (4 of 15 delays). Its "mutation 2" seds also
#           rewrote every `fi`/`else` on every line, so the mutated gate was a
#           syntax error that fails whatever the gate checks.
# Known gap (stated, not fixed; CON-128 review round 3, FU-7): SIGKILL cannot
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

# wait_gone STRING: wait (at most 20 s) until no process has STRING in its command
# line (CON-128 round 5, review F7: a KILL ends the meta-test, and its scratch root
# is removed only after every process that still names it has gone). STRING is
# passed in the environment, so the scanner never matches itself.
wait_gone() {
  WG="$1" python3 -I -c '
import os, sys, time
s, me = os.environ["WG"].encode(), os.getpid()
for _ in range(400):
    left = []
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) == me:
            continue
        try:
            if s in open("/proc/%s/cmdline" % p, "rb").read():
                left.append(p)
        except OSError:
            pass
    if not left:
        sys.exit(0)
    time.sleep(0.05)
print("still running: %s" % " ".join(left))
sys.exit(1)'
}

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
    # A KILL can leave the meta-test's `$(build_root ...)` subshell running
    # (measured, round 5: its cmdline is the meta-test's own, not the scratch
    # path), so wait for both names before the scratch root is removed.
    { wait_gone "$TMP/tt_$sig" && wait_gone "$T1/scripts/validation/meta_test_verification.sh"; } >/dev/null || bad="$bad $d(processes-left)"
    [ "$(snap "$T1")" = "$BASE" ] || { bad="$bad $d"; g -C "$T1" checkout -q -- .; [ -d "$T1/submodules/verification.mut.bak" ] && mv "$T1/submodules/verification.mut.bak" "$T1/submodules/verification"; g -C "$T1" clean -qfd; }
    if [ "$sig" = TERM ] && [ -n "$(ls -A "$TMP/tt_$sig")" ]; then bad="$bad $d(tmpdir-left)"; fi
    rm -rf "${TMP:?}/tt_$sig"
  done
  if [ -z "$bad" ]; then ok "G-$sig stopped by $sig at 14 delays (2%..98% of the run): the checked tree never changed${sig:+}"
  else notok "G-$sig stopped by $sig: the checked tree changed (or scratch left) at delay(s)$bad"; fi
done

# --- Decision points of the meta-test, each with its own fixture (CON-128 review
# round 4, F1: the class "a reviewer mutant of the meta-test survives" recurred in
# rounds 3 and 4 because the fixtures did not separate the verdict axes). Every
# branch that sets the meta-test's verdict is listed here; each fixture makes
# exactly ONE of them fire on the original meta-test, and the paired mutant of
# that branch (below) must change the fixture's verdict.
#   DP1  gate script missing            -> B7  "verification script not found"
#   DP2  test submodule missing         -> B8  "test submodule not present"
#   DP3  control: real gate, real tree  -> B6  "real gate does not pass on the real tree"   (reviewer Ma)
#   DP4  mutation-1 root not buildable  -> B9  "could not build the mutation-1 scratch root"
#   DP5  mutation 1: gate passes        -> B5  "real gate passed despite the missing"      (reviewer Mb)
#   DP6  mutation-2 anchors not unique  -> B4  "could not build the weakened gate"         (MT9)
#   DP7  weakened gate does not parse   -> B11 "the weakened gate does not parse"
#   DP8  mutation-2 root not buildable  -> B10 "could not build the mutation-2 scratch root"
#   DP9  weakened gate still fails      -> B3  "weakened gate still exits non-zero"        (MT1)
#   DP10 finish: exit code from fail    -> B2 (bad) and G (good)
#   DP11 traps: EXIT, TERM, INT, HUP    -> G (tmp left), STERM / SINT / SHUP (stopped at
#        half the run: the scratch root must be gone and the run must END THROUGH
#        its trap, exit 143 / 130 / 129), SCLEAN (a TERM while the cleanup's rm
#        runs: the rm must finish)
#   DP12 build_root: skip the test submodule, use the given gate file -> G
#   DP13 mutation 2's two edits, mutation 1 and 2 run on their own roots -> G
# Not separable (stated, §11.4.6): `[ -e "$s" ] || continue` in build_root -- the
# DP2 guard means the glob always matches at least the test submodule, and a
# dangling entry linked or skipped gives the gate the same (absent) target, so
# the mutant that drops the line is equivalent; not adopted.

# Fixture gates (each passes on its own fake tree except where the fixture is
# about the checked tree itself).
python3 -I - "$GATE" "$TMP" <<'PYEOF'
import sys
src, d = sys.argv[1:3]
c = open(src).read()
REQ = '    "verification"\n'
CHK = 'run_check "verification (agent-skills)" \\\n    "ls -la verification/ && [ -f verification/README.md ]" \\\n    "${SUBMODULES_DIR}"\n'
SUB = 'SUBMODULES_DIR="${CONSTITUTION_ROOT}/submodules"\n'
BANNER = 'echo "Submodules dir: ${SUBMODULES_DIR}"\necho\n'
for a in (REQ, CHK, SUB, BANNER):
    assert c.count(a) == 1, a
def w(name, text): open("%s/gate_%s.sh" % (d, name), "w").write(text)
w("real", c)
w("blind", c.replace(REQ, "").replace(CHK, ""))                                     # B1
w("false", '#!/usr/bin/env bash\necho "always FAIL"\nexit 1\n')                       # B2
w("needs_git", c.replace(SUB, SUB + '[ -e "${CONSTITUTION_ROOT}/.git" ] || { echo "not a checkout"; exit 1; }\n'))  # B3
w("reformatted", c.replace(REQ, '    "verification"   # agent-skills\n'))             # B4
w("always_pass", c.replace(BANNER, BANNER + 'exit 0\n'))                             # B5
SAB = 'for _d in "${TMPDIR:-/tmp}"/meta_test_verification.*; do [ -d "$_d" ] && : > "$_d/%s"; done\n'
w("sab_m1", c.replace(SUB, SUB + SAB % "m1"))                                        # B9
w("sab_m2", c.replace(SUB, SUB + SAB % "m2"))                                        # B10
w("if_wrapped", c.replace(CHK, "if true; then\n" + CHK + "fi\n"))                    # B11
PYEOF

# fx NAME MTVFILE: run the meta-test MTVFILE on fixture NAME; prints the verdict
# "rc=<exit> fail=<n> msg=<0|1> tmp=<0|1>" (msg: the fixture's pinned line is in
# the output; tmp: something was left under TMPDIR). The fixture trees are
# rebuilt per run, so no run sees another run's state.
fx_gate() { case $1 in B1) echo blind ;; B2) echo false ;; B3) echo needs_git ;; B4) echo reformatted ;;
  B5) echo always_pass ;; B9) echo sab_m1 ;; B10) echo sab_m2 ;; B11) echo if_wrapped ;; *) echo real ;; esac; }
fx_msg() { case $1 in
  G) echo "✓ the weakened gate parses" ;; B1|B5) echo "✗ real gate passed despite the missing" ;;
  B2|B6) echo "✗ real gate does not pass on the real tree" ;; B3) echo "✗ weakened gate still exits non-zero" ;;
  B4) echo "✗ could not build the weakened gate" ;; B7) echo "✗ verification script not found" ;;
  B8) echo "✗ test submodule not present" ;; B9) echo "✗ could not build the mutation-1 scratch root" ;;
  B10) echo "✗ could not build the mutation-2 scratch root" ;; B11) echo "✗ the weakened gate does not parse" ;;
  *) echo "=== meta-test verification:" ;; esac; }
FXN=0
fx() {
  local name=$1 mtv=$2 T rc fl msg tmp
  FXN=$((FXN + 1)); T="$TMP/fx$FXN"; rm -rf "${T:?}"
  mktree "$T" "$TMP/gate_$(fx_gate "$name").sh" "$mtv" >/dev/null 2>&1
  case $name in
    B6) rm -f "$T/submodules/verification/README.md" ;;
    B7) rm -f "$T/scripts/validation/run_verification.sh" ;;
    B8) rm -rf "${T:?}/submodules/verification" ;;
  esac
  mkdir -p "$T.tt"
  TMPDIR="$T.tt" bash "$T/scripts/validation/meta_test_verification.sh" > "$T.out" 2>&1; rc=$?
  fl=$(sed -n 's/^=== meta-test verification: pass=[0-9]* fail=\([0-9]*\) ===$/\1/p' "$T.out")
  grep -qF -- "$(fx_msg "$name")" "$T.out" && msg=1 || msg=0
  [ -z "$(ls -A "$T.tt")" ] && tmp=0 || tmp=1
  rm -rf "${T:?}" "${T:?}.tt"
  echo "rc=$rc fail=${fl:-none} msg=$msg tmp=$tmp"
}
# sigfx SIG MTVFILE [rm-shim]: stop the meta-test with SIG at half the measured run
# (or, with rm-shim, while its cleanup's rm runs); prints "stopped=<0|1> tmp=<0|1>"
# (stopped: no summary line, so the signal really ended the run).
sigfx() {
  local sig=$1 mtv=$2 shim=${3:-} T pid i ec=""
  FXN=$((FXN + 1)); T="$TMP/fx$FXN"; rm -rf "${T:?}"
  mktree "$T" "$TMP/gate_real.sh" "$mtv" >/dev/null 2>&1; mkdir -p "$T.tt"
  if [ -z "$shim" ]; then
    # The meta-test runs in its own session; the signal goes to its whole
    # process group (as timeout sends it) at half the measured run. ec is how
    # it ended: exit=<code> (its trap ran `exit 1xx`) or sig=<n> (killed).
    # Measured (round 5): bash runs the EXIT trap on a fatal TERM, INT or HUP
    # even without a trap for it, so the cleanup alone cannot tell whether the
    # TERM/INT/HUP traps are there; the exit status can.
    ec=$(TMPDIR="$T.tt" python3 -I -c '
import os, signal, subprocess, sys, time
sig, half, mtv, out = getattr(signal, "SIG" + sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4]
p = subprocess.Popen(["bash", mtv], stdout=open(out, "w"), stderr=subprocess.STDOUT, start_new_session=True)
time.sleep(half)
try:
    os.killpg(p.pid, sig)
except ProcessLookupError:
    pass
rc = p.wait()
print("sig=%d" % -rc if rc < 0 else "exit=%d" % rc)' "$sig" "$HALF" "$T/scripts/validation/meta_test_verification.sh" "$T.out")
    wait_gone "$T.tt" >/dev/null
  else
    # A PATH shim for rm: on the cleanup's call it writes a marker and sleeps 2 s
    # before it runs the real rm; the signal is sent to the whole process group
    # (as timeout does) while it sleeps.
    TMPDIR="$T.tt" RMSHIM_MARK="$T.mark" PATH="$TMP/rmshim:$PATH" setsid bash "$T/scripts/validation/meta_test_verification.sh" > "$T.out" 2>&1 &
    pid=$!
    for i in $(seq 1 300); do [ -e "$T.mark" ] && break; sleep 0.05; done
    [ -e "$T.mark" ] && kill -s "$sig" -- "-$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    wait_gone "$T.tt"
  fi
  local st tmp
  grep -q '^=== meta-test verification:' "$T.out" && st=0 || st=1
  [ -n "$shim" ] && { [ -e "$T.mark" ] && st=1 || st=0; }
  [ -z "$(ls -A "$T.tt")" ] && tmp=0 || tmp=1
  rm -rf "${T:?}" "${T:?}.tt" "${T:?}.mark"
  echo "stopped=$st tmp=$tmp${ec:+ $ec}"
}
mkdir -p "$TMP/rmshim"
cat > "$TMP/rmshim/rm" <<EOF
#!/bin/bash
case "\$*" in *meta_test_verification.*) : > "\$RMSHIM_MARK"; sleep 2 ;; esac
exec $(command -v rm) "\$@"
EOF
chmod +x "$TMP/rmshim/rm"
HALF=$(awk -v r="$RUNS" 'BEGIN { printf "%.3f", r * 0.5 }')

# The original meta-test on every fixture: the verdict each one is pinned to.
declare -A WANT
for x in G B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11; do WANT[$x]=$(fx "$x" "$MTV"); done
ign() { local v; v=$(awk '/^SigIgn:/ { print $2 }' /proc/self/status); echo $(( (16#$v >> ($1 - 1)) & 1 )); }
for s in TERM:15 INT:2 HUP:1; do
  if [ "$(ign "${s#*:}")" = 1 ]; then WANT[S${s%%:*}]="ignored"; else WANT[S${s%%:*}]=$(sigfx "${s%%:*}" "$MTV"); fi
done
WANT[SCLEAN]=$(sigfx TERM "$MTV" shim)

[ "${WANT[G]}" = "rc=0 fail=0 msg=1 tmp=0" ] && ok "G (fixture) good tree -> ${WANT[G]}" || notok "G (fixture) good tree -> ${WANT[G]}"
for x in B1 B2; do
  case ${WANT[$x]} in "rc=1 fail="[12]" msg=1 tmp=0") ok "$x -> ${WANT[$x]} ($(fx_msg "$x"))" ;;
    *) notok "$x -> ${WANT[$x]}, want rc=1, its line '$(fx_msg "$x")', nothing left" ;; esac
done
for x in B3 B4 B5 B6 B7 B8 B9 B10 B11; do
  # one decision point fires, and only that one (fail=1)
  [ "${WANT[$x]}" = "rc=1 fail=1 msg=1 tmp=0" ] && ok "$x -> ${WANT[$x]} ($(fx_msg "$x"))" \
    || notok "$x -> ${WANT[$x]}, want 'rc=1 fail=1 msg=1 tmp=0' with '$(fx_msg "$x")'"
done
for x in STERM SINT SHUP SCLEAN; do
  case ${WANT[$x]} in
    "stopped=1 tmp=0"|"stopped=1 tmp=0 exit=143"|"stopped=1 tmp=0 exit=130"|"stopped=1 tmp=0 exit=129") ok "$x stopped by the signal${x#S} -> nothing left under TMPDIR (${WANT[$x]})" ;;
    ignored) ok "$x SKIP: SIG${x#S} is ignored in this shell (inherited), so the meta-test cannot be stopped with it here" ;;
    *) notok "$x -> ${WANT[$x]}, want stopped=1 tmp=0 (and, for STERM/SINT/SHUP, exit=143/130/129 from the trap)" ;; esac
done

# Paired mutants of the meta-test, one per decision point (DPn above). Each is an
# exact, unique replacement in a copy; it is caught when its fixture's verdict
# differs from the original's. Ma and Mb are the round-4 reviewer mutants, MT1
# and MT9 the round-3 ones, verbatim.
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
mtv_mutation() {  # NAME FIXTURE OLD NEW
  local m got
  m=$(mtv_mutant "$1" "$3" "$4")
  if [ -z "$m" ]; then notok "mutation $1: anchor not unique in the meta-test (not a catch)"; return; fi
  case $2 in
    STERM|SINT|SHUP) [ "${WANT[$2]}" = ignored ] && { ok "mutation $1 SKIP: SIG${2#S} is ignored in this shell"; return; }
       got=$(sigfx "${2#S}" "$m") ;;
    SCLEAN) got=$(sigfx TERM "$m" shim) ;;
    *) got=$(fx "$2" "$m") ;;
  esac
  [ "$got" != "${WANT[$2]}" ] && ok "mutation $1 caught by $2 ($got, original ${WANT[$2]})" \
    || notok "mutation $1 SURVIVED $2 ($got)"
}
Q="'"
mtv_mutation DP1_script_missing_ok B7 'notok "verification script not found' 'ok "verification script not found'
mtv_mutation DP2_submodule_missing_ok B8 'notok "test submodule not present' 'ok "test submodule not present'
mtv_mutation Ma_control_verdict_ignored B6 'notok "real gate does not pass on the real tree; output:"' 'ok "real gate does not pass on the real tree; output:"'
mtv_mutation DP4_m1_root_failure_ok B9 'notok "could not build the mutation-1 scratch root"' 'ok "could not build the mutation-1 scratch root"'
mtv_mutation Mb_mutation1_verdict_ignored B5 'notok "real gate passed despite the missing' 'ok "real gate passed despite the missing'
mtv_mutation MT9_anchor_failure_ok B4 'notok "could not build the weakened gate (gate text changed; update the mutation anchors)"' 'ok "could not build the weakened gate (gate text changed; update the mutation anchors)"'
mtv_mutation DP7_unparsable_ok B11 'notok "the weakened gate does not parse:"' 'ok "the weakened gate does not parse:"'
mtv_mutation DP7b_no_syntax_check B11 'if bash -n "${W}/run_verification_weak.sh" 2> "${W}/weak_syntax.txt"; then' 'if true; then'
mtv_mutation DP8_m2_root_failure_ok B10 'notok "could not build the mutation-2 scratch root"' 'ok "could not build the mutation-2 scratch root"'
mtv_mutation MT1_mut2_verdict_ignored B3 'notok "weakened gate still exits non-zero; the real gate'"$Q"'s mutation-1 result' 'ok "weakened gate still exits non-zero; the real gate'"$Q"'s mutation-1 result'
mtv_mutation DP10a_always_exit_0 B2 '    [ "${fail}" = 0 ] && exit 0
    exit 1' '    exit 0'
mtv_mutation DP10b_always_exit_1 G '    [ "${fail}" = 0 ] && exit 0
    exit 1' '    exit 1'
mtv_mutation DP10c_notok_not_counted B2 'notok() { fail=$((fail + 1));' 'notok() {'
mtv_mutation DP11a_no_exit_trap G 'trap cleanup EXIT' ':'
mtv_mutation DP11b_cleanup_noop G '&& rm -rf -- "${W:?}"; }' '&& :; }'
mtv_mutation DP11c_no_term_trap STERM "trap 'exit 143' TERM" ':'
mtv_mutation DP11d_no_int_trap SINT "trap 'exit 130' INT" ':'
mtv_mutation DP11e_no_hup_trap SHUP "trap 'exit 129' HUP" ':'
mtv_mutation DP11f_cleanup_signals_not_ignored SCLEAN "cleanup() { trap '' HUP INT TERM; " 'cleanup() { '
mtv_mutation DP12a_test_submodule_not_skipped G '        [ "$(basename -- "${s}")" = "${TEST_SUBMODULE}" ] && continue
' ''
mtv_mutation DP12b_gate_file_ignored G 'cp -- "${2:-${VERIFICATION_SCRIPT}}"' 'cp -- "${VERIFICATION_SCRIPT}"'
mtv_mutation DP13a_requirement_kept G "edits = ['    \"%s\"\\n' % name," 'edits = ['
mtv_mutation DP13b_check_kept G '         '"'"'run_check "%s (agent-skills)" \\\n    "ls -la %s/ && [ -f %s/README.md ]" \\\n    "${SUBMODULES_DIR}"\n'"'"' % (name, name, name)]' '         ]'
mtv_mutation DP13c_mutation1_on_real_tree G 'if bash "${R1}/scripts/validation/run_verification.sh"' 'if bash "${VERIFICATION_SCRIPT}"'
mtv_mutation DP13d_mutation2_on_m1_root G 'if bash "${R2}/scripts/validation/run_verification.sh"' 'if bash "${R1}/scripts/validation/run_verification.sh"'

echo "=== meta_test_verification regression guard (CON-128): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
