#!/bin/bash
# Purpose : CON-158 regression guard for scripts/validation/meta_test_verification.sh
#           (the paired-mutation meta-test of scripts/validation/run_verification.sh):
#           the meta-test never changes the tree it checks -- no renamed
#           submodule, no edited tracked gate script -- even when it is stopped
#           with TERM or KILL at any moment; it writes only under $TMPDIR; its
#           mutations are real (a weakened gate that parses, not a syntax
#           error); it fails when the gate is blind to a missing required
#           submodule or always fails; and on its PASS path the summary line
#           is printed last (CON-156 class, review round 2 finding R2-F5-A).
#           Round 5 (CON-158 review round 4, F1: reviewer mutants Ma and Mb
#           survived): every decision point of the meta-test listed below has its own
#           fixture, pinned to one verdict (exit code, fail count, the one
#           failure line it must print, nothing left under TMPDIR), and one
#           paired mutant (list below the fixtures); a TERM that hits the
#           cleanup's rm no longer leaves the scratch root (SCLEAN_TERM).
#           Round 6 (review of fsfix5, N1..N3): every signal is sent on an
#           OBSERVED event (a marker the meta-test's run writes), never at a
#           time derived from one measurement; every wait is bounded and the
#           fixture's whole session is reaped and counted; each signal fixture
#           is pinned to its own exit code; the fixtures cover the mktemp
#           failure, a duplicated mutation-2 anchor, a failing cp and a failing
#           ln in build_root, and INT and HUP during the cleanup's rm. The
#           decision points are also enumerated mechanically, and every
#           single-edit mutant is run against this test, by
#           scripts/validation/enumerate_decision_mutants.py (section 11.4.274).
# Forensic: before the fix the meta-test renamed submodules/verification in
#           place and ran `sed -i` on the tracked run_verification.sh, with no
#           trap; measured 2026-11-06 on a scratch tree, a TERM at 0.02 s left
#           the submodule renamed and a TERM at 0.12, 0.25 and 0.30 s left the
#           tracked gate mutated (4 of 15 delays). Its "mutation 2" seds also
#           rewrote every `fi`/`else` on every line, so the mutated gate was a
#           syntax error that fails whatever the gate checks.
# Known gap (stated, not fixed; CON-158 review round 3, FU-7): SIGKILL cannot
#           run a trap, so after a KILL the scratch root stays under $TMPDIR.
#           It holds only SYMLINKS to the real submodules and a copy of the
#           gate (measured: 503 symlinks over 30 runs). `rm -rf` (GNU and
#           uutils) removes the links and leaves their targets alone, so a
#           later cleanup with it is safe; a tool that FOLLOWS links
#           (`find -L`, `cp -rL`, `chmod -R` with -L) would reach the checked
#           tree. The checked tree itself never changes (G-KILL below).
# Usage   : bash scripts/validation/test_meta_test_verification_r1_regression.sh
#           Exit 0 when every check passes, 1 otherwise. The last line is the
#           summary line. MTV_REG_PINS_ONLY=1 skips the paired-mutant section
#           (used by the decision-point enumerator, which supplies the mutants
#           itself and judges by this test's exit status).
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

# mktree DIR [GATEFILE] [MTVFILE]: a fake constitution tree whose gate passes.
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

# runtime: one bounded full run of the meta-test on $T1; prints its wall time in
# seconds, or "x" when it did not exit 0. Every run of the meta-test in this
# test is bounded (review fsfix5 N2): `timeout -k 5 120`.
runtime() {
  local t0 rc
  t0=$(date +%s.%N)
  TMPDIR="$TMP/tt" timeout -k 5 120 bash "$T1/scripts/validation/meta_test_verification.sh" > "$TMP/rt.out" 2>&1; rc=$?
  [ "$rc" = 0 ] || { echo x; return; }
  awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.3f", b - a }'
}

# G1: a full run passes, changes nothing, leaves nothing in TMPDIR, and its summary is last.
OUT=$(TMPDIR="$TMP/tt" timeout -k 5 120 bash "$T1/scripts/validation/meta_test_verification.sh" 2>&1); RC=$?
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
# line (CON-158 round 5, review F7: a KILL ends the meta-test, and its scratch root
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
# The delays are 14 points from 2% to 98% of the run time, so the last mutation and
# the summary are interrupted too (review round 3, FU-6). Round 6 (review fsfix5
# N1): the run time is the MINIMUM of three measured runs, never one measurement,
# and the sweep counts how many stops really ended the run before its summary; a
# sweep in which fewer than 7 of 14 did is BLIND (the delays missed the run), is
# re-measured and re-run once, and is a failure only if it is BLIND again. The
# sweep's verdict (tree unchanged, nothing left) never depends on the timing.
RUNS=""
for _i in 1 2 3; do
  r=$(runtime)
  case "$r" in x) ;; *) RUNS=$(awk -v a="${RUNS:-$r}" -v b="$r" 'BEGIN { printf "%.3f", (b < a ? b : a) }') ;; esac
done
case "$RUNS" in ""|0.000) notok "control needle: no measurable full run (run time '$RUNS' s); the delays cannot be scaled" ; RUNS=1.000 ;;
  *) ok "control needle: full run (minimum of 3 measured runs) $RUNS s" ;; esac
delays() { awk -v r="$1" 'BEGIN { split("0.02 0.07 0.12 0.18 0.25 0.32 0.40 0.48 0.56 0.64 0.72 0.80 0.90 0.98", f, " "); for (i = 1; i <= 14; i++) printf "%.3f ", r * f[i] }'; }
# sweep SIG RUNTIME: sets SW_BAD (delays at which something was left or changed)
# and SW_STOPPED (how many of the 14 stops ended the run before its summary).
sweep() {
  local sig=${1:?} d
  SW_BAD=""; SW_STOPPED=0
  for d in $(delays "$2"); do
    mkdir -p "$TMP/tt_$sig"
    TMPDIR="$TMP/tt_$sig" timeout -s "$sig" "$d" bash "$T1/scripts/validation/meta_test_verification.sh" > "$TMP/sw.out" 2>&1
    grep -q '^=== meta-test verification:' "$TMP/sw.out" || SW_STOPPED=$((SW_STOPPED + 1))
    # A KILL can leave the meta-test's `$(build_root ...)` subshell running
    # (measured, round 5: its cmdline is the meta-test's own, not the scratch
    # path), so wait for both names before the scratch root is removed.
    { wait_gone "$TMP/tt_$sig" && wait_gone "$T1/scripts/validation/meta_test_verification.sh"; } >/dev/null || SW_BAD="$SW_BAD $d(processes-left)"
    [ "$(snap "$T1")" = "$BASE" ] || { SW_BAD="$SW_BAD $d"; g -C "$T1" checkout -q -- .; [ -d "$T1/submodules/verification.mut.bak" ] && mv "$T1/submodules/verification.mut.bak" "$T1/submodules/verification"; g -C "$T1" clean -qfd; }
    if [ "$sig" = TERM ] && [ -n "$(ls -A "$TMP/tt_$sig")" ]; then SW_BAD="$SW_BAD $d(tmpdir-left)"; fi
    rm -rf "${TMP:?}/tt_${sig:?}"
  done
}
for sig in TERM KILL; do
  sweep "$sig" "$RUNS"
  if [ "$SW_STOPPED" -lt 7 ]; then
    echo "note G-$sig BLIND: only $SW_STOPPED of 14 stops ended the run before its summary (run time $RUNS s); re-measuring and re-running once"
    r=$(runtime); case "$r" in x) ;; *) RUNS=$(awk -v a="$RUNS" -v b="$r" 'BEGIN { printf "%.3f", (b < a ? b : a) }') ;; esac
    sweep "$sig" "$RUNS"
  fi
  if [ "$SW_STOPPED" -lt 7 ]; then notok "G-$sig BLIND twice: only $SW_STOPPED of 14 stops ended the run before its summary"
  elif [ -z "$SW_BAD" ]; then ok "G-$sig stopped by $sig at 14 delays (2%..98% of the run, $SW_STOPPED of 14 before the summary): the checked tree never changed"
  else notok "G-$sig stopped by $sig: the checked tree changed (or scratch left) at delay(s)$SW_BAD"; fi
done

# --- Decision points of the meta-test, each with its own fixture (CON-158 review
# round 4, F1: the class "a reviewer mutant of the meta-test survives" recurred in
# rounds 3, 4 and 5 because the fixtures did not separate the verdict axes). Each
# fixture makes exactly ONE decision point fire on the original meta-test, and the
# paired mutant of that branch (below) must change the fixture's verdict. This
# list was written by hand; it is CROSS-CHECKED mechanically by
# scripts/validation/enumerate_decision_mutants.py, which generates the
# single-edit mutants of the decision points its closed operator list matches
# and runs this test against them (not a completeness proof for decision
# points no operator generates, CON-159).
#   DP0  mktemp of the scratch root fails -> B12 "mktemp failed" (exit 1, no summary)   (R2)
#   DP1  gate script missing            -> B7  "verification script not found"
#   DP2  test submodule missing         -> B8  "test submodule not present"
#   DP3  control: real gate, real tree  -> B6  "real gate does not pass on the real tree"   (reviewer Ma)
#   DP4  mutation-1 root not buildable: mkdir -> B9, cp -> B14 (R4), ln -> B15 (R7)
#        "could not build the mutation-1 scratch root"
#   DP5  mutation 1: gate passes        -> B5  "real gate passed despite the missing"      (reviewer Mb)
#   DP6  mutation-2 anchor not unique: absent -> B4 (MT9), duplicated -> B13 (R3)
#        "could not build the weakened gate"
#   DP7  weakened gate does not parse   -> B11 "the weakened gate does not parse"
#   DP8  mutation-2 root not buildable  -> B10 "could not build the mutation-2 scratch root"
#   DP9  weakened gate still fails      -> B3  "weakened gate still exits non-zero"        (MT1)
#   DP10 finish: exit code from fail    -> B2 (bad) and G (good)
#   DP11 traps: EXIT -> G (tmp left); TERM / INT / HUP while the control gate runs
#        -> STERM / SINT / SHUP, each pinned to its own exit code 143 / 130 / 129
#        (the run ENDS THROUGH its trap, nothing left); TERM / INT / HUP while the
#        cleanup's rm runs -> SCLEAN_TERM / SCLEAN_INT / SCLEAN_HUP (the rm
#        finishes, the run keeps its exit 0)                                        (R1b, R5b)
#   DP12 build_root: skip the test submodule, use the given gate file -> G
#   DP13 mutation 2's two edits, mutation 1 and 2 run on their own roots -> G
#   DP14 each gate run captures BOTH its streams into its file, and the meta-test
#        prints them indented: control -> B2, mutation 1 -> G and B16 (stderr),
#        the weakened gate's parse -> B11, mutation 2 -> B3 (the diag= field)
#        (found by the round-6 census, enumerate_decision_mutants.py)
#   DP15 a scratch root that cannot be built STOPS the run at once: the m1
#        `finish` and build_root's first `|| return 1` -> B9, the m2 `finish`
#        -> B10 (the stop= field; round-6 census)
# Not separable (stated, §11.4.6): `[ -e "$s" ] || continue` in build_root -- the
# DP2 guard means the glob always matches at least the test submodule, and a
# dangling entry linked or skipped gives the gate the same (absent) target, so
# the mutant that drops the line is equivalent; not adopted (the enumerator's
# equivalence ledger carries the same proof).
# Also equivalent (ledger): in cleanup, dropping either of `[ -n "${W:-}" ]` and
# `[ -d "${W}" ]` (W is a mktemp -d path whenever the EXIT trap is set, and
# `rm -rf` of a missing path is a no-op whose status is not read).

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
# The diagnostics below go to STDERR on purpose: the meta-test must capture both
# streams of every gate run (round 6, census: its `2>&1` / `> file` redirects
# were decision points no fixture pinned).
w("false", '#!/usr/bin/env bash\necho "always FAIL" >&2\nexit 1\n')                   # B2
w("needs_git", c.replace(SUB, SUB + '[ -e "${CONSTITUTION_ROOT}/.git" ] || { echo "not a checkout" >&2; exit 1; }\n'))  # B3
w("stderr_missing", c.replace(SUB, SUB + '[ -d "${SUBMODULES_DIR}/verification" ] || echo "verification not cloned (stderr)" >&2\n'))  # B16
w("reformatted", c.replace(REQ, '    "verification"   # agent-skills\n'))             # B4
w("always_pass", c.replace(BANNER, BANNER + 'exit 0\n'))                             # B5
SAB = 'for _d in "${TMPDIR:-/tmp}"/meta_test_verification.*; do [ -d "$_d" ] && %s; done\n'
w("sab_m1", c.replace(SUB, SUB + SAB % ': > "$_d/m1"'))                              # B9
w("sab_m2", c.replace(SUB, SUB + SAB % ': > "$_d/m2"'))                              # B10
w("if_wrapped", c.replace(CHK, "if true; then\n" + CHK + "fi\n"))                    # B11
w("dup_req", c.replace(REQ, REQ + REQ))                                              # B13
# B14: the m1 gate path is a directory holding a directory of the same name, so
# build_root's `cp` fails (it cannot overwrite a directory with a file).
w("sab_cp", c.replace(SUB, SUB + SAB % 'mkdir -p "$_d/m1/scripts/validation/run_verification.sh/run_verification.sh"'))
# B15: a regular FILE where build_root links a (non-test) submodule, so its `ln -s` fails.
w("sab_ln", c.replace(SUB, SUB + SAB % '{ for _s in "${SUBMODULES_DIR}"/*; do [ "${_s##*/}" = verification ] && continue; mkdir -p "$_d/m1/submodules" && : > "$_d/m1/submodules/${_s##*/}"; break; done; }'))
# Signal fixtures: on its FIRST call (the control phase, while the scratch root
# exists) the gate writes the marker named by MTV_SIGMARK and sleeps, so the
# launcher can send the signal on that observed event (review fsfix5 N1).
w("sigwait", c.replace(SUB, SUB + 'if [ -n "${MTV_SIGMARK:-}" ] && [ ! -e "${MTV_SIGMARK}" ]; then : > "${MTV_SIGMARK}"; sleep 20; fi\n'))
PYEOF

# fx NAME MTVFILE: run the meta-test MTVFILE on fixture NAME; prints the verdict
# "rc=<exit> fail=<n> msg=<0|1> tmp=<0|1> diag=<0|1|-> stop=<0|1|->" (msg: the fixture's pinned
# line is in the output; tmp: something was left under TMPDIR; diag: the
# fixture's indented gate diagnostic is in the output, "-" when none is pinned;
# stop: for a fixture whose decision point must STOP the run (fx_stops), its line
# is the last unindented line before the summary and no later step ran (B9: no
# `cp:` error either, build_root stopped at the mkdir), "-" for the others; round 6
# census survivors ed1705be1215 and 54dcb68d8153). Every fixture runs in its own
# mktemp directory (review fsfix5 n1: a counter bumped inside $(...) never moved),
# and every run is bounded (timeout: rc 124 or 137 shows in the verdict).
fx_gate() { case $1 in B1) echo blind ;; B2) echo false ;; B3) echo needs_git ;; B4) echo reformatted ;;
  B5) echo always_pass ;; B9) echo sab_m1 ;; B10) echo sab_m2 ;; B11) echo if_wrapped ;; B13) echo dup_req ;;
  B14) echo sab_cp ;; B15) echo sab_ln ;; B16) echo stderr_missing ;; *) echo real ;; esac; }
fx_msg() { case $1 in
  G) echo "✓ the weakened gate parses" ;; B1|B5) echo "✗ real gate passed despite the missing" ;;
  B2|B6) echo "✗ real gate does not pass on the real tree" ;; B3) echo "✗ weakened gate still exits non-zero" ;;
  B4|B13) echo "✗ could not build the weakened gate" ;; B7) echo "✗ verification script not found" ;;
  B8) echo "✗ test submodule not present" ;; B9|B14|B15) echo "✗ could not build the mutation-1 scratch root" ;;
  B10) echo "✗ could not build the mutation-2 scratch root" ;; B11) echo "✗ the weakened gate does not parse" ;;
  B12) echo "✗ mktemp failed" ;; B16) echo "✓ real gate exits non-zero when" ;;
  *) echo "=== meta-test verification:" ;; esac; }
# fx_diag NAME: the indented diagnostic line the meta-test must print for the
# fixture (the gate's own output, captured from BOTH streams and indented by
# four spaces), or nothing when the fixture pins no diagnostic.
fx_diag() { case $1 in
  G) echo '^    .*REQUIRED submodule MISSING: verification' ;; B2) echo '^    always FAIL' ;;
  B3) echo '^    not a checkout' ;; B11) echo '^    .*syntax error' ;;
  B16) echo '^    verification not cloned \(stderr\)' ;; esac; }
fx_stops() { case $1 in B4|B7|B8|B9|B10|B13|B14|B15) return 0 ;; esac; return 1; }
fx() {
  local name=$1 mtv=$2 T rc fl msg tmp tt dg pat st last
  T=$(mktemp -d "$TMP/fx.XXXXXX") || { echo "fixture-mktemp-failed"; return; }
  mktree "$T/tree" "$TMP/gate_$(fx_gate "$name").sh" "$mtv" >/dev/null 2>&1
  case $name in
    B6) rm -f "$T/tree/submodules/verification/README.md" ;;
    B7) rm -f "$T/tree/scripts/validation/run_verification.sh" ;;
    B8) rm -rf "${T:?}/tree/submodules/verification" ;;
  esac
  mkdir -p "$T/tt"; tt="$T/tt"
  [ "$name" = B12 ] && tt="$T/tt/missing"   # TMPDIR names no directory: the scratch root's mktemp fails
  TMPDIR="$tt" timeout -k 5 120 bash "$T/tree/scripts/validation/meta_test_verification.sh" > "$T/out" 2>&1; rc=$?
  fl=$(sed -n 's/^=== meta-test verification: pass=[0-9]* fail=\([0-9]*\) ===$/\1/p' "$T/out")
  grep -qF -- "$(fx_msg "$name")" "$T/out" && msg=1 || msg=0
  [ -z "$(ls -A "$T/tt")" ] && tmp=0 || tmp=1
  pat=$(fx_diag "$name"); dg=-
  [ -n "$pat" ] && { grep -qE -- "$pat" "$T/out" && dg=1 || dg=0; }
  st=-
  if fx_stops "$name"; then
    last=$(sed '/^=== meta-test verification:/,$d' "$T/out" | grep -v -e '^$' -e '^    ' | tail -n 1)
    st=0
    case $last in *"$(fx_msg "$name")"*) st=1 ;; esac
    [ "$name" = B9 ] && grep -q '^cp: ' "$T/out" && st=0
  fi
  rm -rf "${T:?}"
  echo "rc=$rc fail=${fl:-none} msg=$msg tmp=$tmp diag=$dg stop=$st"
}

# sigfx SIG MTVFILE [clean]: stop the meta-test with SIG on an observed event and
# print its verdict "mark=<0|1> seen=<0|1> sum=<0|1> tmp=<0|1> end=<how> left=<n>".
#   without "clean": the event is the sigwait gate's marker (written on the
#     control run, while the scratch root exists); with "clean": the event is the
#     rm shim's marker (written when the cleanup's rm starts; it then sleeps 2 s
#     before it runs the real rm).
#   mark: the event was observed; seen: the scratch root existed at that moment
#   (positive control); sum: the summary line was printed; tmp: something was left
#   under TMPDIR; end: exit=<code>, sig=<n>, timeout (killed after 30 s) or
#   nomark (no event within 30 s); left: processes of the fixture's session that
#   were still there after the meta-test ended (they are killed and counted).
# The meta-test runs in its own session with HUP, INT and TERM reset to their
# defaults (so a signal ignored by whoever started this test cannot hide a trap,
# and INT works, which `setsid ... &` cannot give), and the signal goes to its
# whole process group, as timeout sends it. Every wait is bounded (review fsfix5
# N2). A verdict whose end is timeout or nomark is BLIND: the run is repeated
# once (noted), and only the repeat counts.
cat > "$TMP/sigrun.py" <<'PYEOF'
import os, signal, subprocess, sys, time
sig, mtv, out, tt, mark = getattr(signal, "SIG" + sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
def pre():
    for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(s, signal.SIG_DFL)
    signal.pthread_sigmask(signal.SIG_SETMASK, [])
p = subprocess.Popen(["bash", mtv], stdout=open(out, "w"), stderr=subprocess.STDOUT,
                     start_new_session=True, preexec_fn=pre)
seen = got = 0
end = None
t_end = time.monotonic() + 30
while time.monotonic() < t_end:
    if os.path.exists(mark):
        got = 1
        seen = 1 if os.listdir(tt) else 0
        try:
            if isinstance(p.pid, int) and p.pid > 1 and p.pid != os.getpgrp():   # section 11.4.263
                os.killpg(p.pid, sig)
        except ProcessLookupError:
            pass
        break
    if p.poll() is not None:
        break
    time.sleep(0.01)
if not got and p.poll() is None:
    end = "nomark"
try:
    rc = p.wait(timeout=30)
except subprocess.TimeoutExpired:
    end = end or "timeout"
    try:
        if isinstance(p.pid, int) and p.pid > 1 and p.pid != os.getpgrp():   # section 11.4.263
            os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    rc = p.wait()
if end is None:
    end = "sig=%d" % -rc if rc < 0 else "exit=%d" % rc
def session():
    found = []
    for q in os.listdir("/proc"):
        if not q.isdigit():
            continue
        try:
            st = open("/proc/%s/stat" % q).read()
        except OSError:
            continue
        f = st[st.rindex(")") + 2:].split()
        if int(f[3]) == p.pid and f[0] != "Z":
            found.append(int(q))
    return found
left = []
for _ in range(100):
    left = session()
    if not left:
        break
    time.sleep(0.05)
for q in left:
    try:
        os.kill(q, signal.SIGKILL)
    except ProcessLookupError:
        pass
print("mark=%d seen=%d tmp=@TMP@ end=%s left=%d" % (got, seen, end, len(left)))
PYEOF
mkdir -p "$TMP/rmshim"
cat > "$TMP/rmshim/rm" <<EOF
#!/bin/bash
case "\$*" in *meta_test_verification.*) : > "\$RMSHIM_MARK"; sleep 2 ;; esac
exec $(command -v rm) "\$@"
EOF
chmod +x "$TMP/rmshim/rm"
sigfx_once() {
  local sig=$1 mtv=$2 clean=${3:-} T v sum tmp
  T=$(mktemp -d "$TMP/sx.XXXXXX") || { echo "fixture-mktemp-failed"; return; }
  mkdir -p "$T/tt"
  if [ -z "$clean" ]; then
    mktree "$T/tree" "$TMP/gate_sigwait.sh" "$mtv" >/dev/null 2>&1
    v=$(TMPDIR="$T/tt" MTV_SIGMARK="$T/mark" python3 -I "$TMP/sigrun.py" "$sig" "$T/tree/scripts/validation/meta_test_verification.sh" "$T/out" "$T/tt" "$T/mark")
  else
    mktree "$T/tree" "$TMP/gate_real.sh" "$mtv" >/dev/null 2>&1
    v=$(TMPDIR="$T/tt" RMSHIM_MARK="$T/mark" PATH="$TMP/rmshim:$PATH" python3 -I "$TMP/sigrun.py" "$sig" "$T/tree/scripts/validation/meta_test_verification.sh" "$T/out" "$T/tt" "$T/mark")
  fi
  wait_gone "$T/tt" >/dev/null
  grep -q '^=== meta-test verification:' "$T/out" && sum=1 || sum=0
  [ -z "$(ls -A "$T/tt")" ] && tmp=0 || tmp=1
  rm -rf "${T:?}"
  v=${v/tmp=@TMP@/sum=$sum tmp=$tmp}
  echo "$v"
}
sigfx() {
  local v
  v=$(sigfx_once "$@")
  case "$v" in *end=timeout*|*end=nomark*)
    echo "note sigfx $1 ${3:-} BLIND ($v): repeated once" >> "$TMP/notes"
    v=$(sigfx_once "$@") ;; esac
  echo "$v"
}

# The original meta-test on every fixture: the verdict each one is pinned to.
declare -A WANT
for x in G B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12 B13 B14 B15 B16; do WANT[$x]=$(fx "$x" "$MTV"); done
for s in TERM INT HUP; do WANT[S$s]=$(sigfx "$s" "$MTV"); WANT[SCLEAN_$s]=$(sigfx "$s" "$MTV" clean); done

[ "${WANT[G]}" = "rc=0 fail=0 msg=1 tmp=0 diag=1 stop=-" ] && ok "G (fixture) good tree -> ${WANT[G]}" || notok "G (fixture) good tree -> ${WANT[G]}"
want_diag() { [ -n "$(fx_diag "$1")" ] && echo 1 || echo -; }
want_stop() { fx_stops "$1" && echo 1 || echo -; }
for x in B1 B2; do
  case ${WANT[$x]} in "rc=1 fail="[12]" msg=1 tmp=0 diag=$(want_diag "$x") stop=-") ok "$x -> ${WANT[$x]} ($(fx_msg "$x"))" ;;
    *) notok "$x -> ${WANT[$x]}, want rc=1, its line '$(fx_msg "$x")', nothing left" ;; esac
done
for x in B3 B4 B5 B6 B7 B8 B9 B10 B11 B13 B14 B15; do
  # one decision point fires, and only that one (fail=1)
  w="rc=1 fail=1 msg=1 tmp=0 diag=$(want_diag "$x") stop=$(want_stop "$x")"
  [ "${WANT[$x]}" = "$w" ] && ok "$x -> ${WANT[$x]} ($(fx_msg "$x"))" \
    || notok "$x -> ${WANT[$x]}, want '$w' with '$(fx_msg "$x")'"
done
# B16: a gate that reports the missing submodule on STDERR; the meta-test passes
# and shows that line indented (both streams of the mutation-1 run captured).
[ "${WANT[B16]}" = "rc=0 fail=0 msg=1 tmp=0 diag=1 stop=-" ] && ok "B16 -> ${WANT[B16]} (stderr diagnostic captured)" \
  || notok "B16 -> ${WANT[B16]}, want 'rc=0 fail=0 msg=1 tmp=0 diag=1 stop=-'"
# B12: the meta-test stops before it counts anything, so no summary line.
[ "${WANT[B12]}" = "rc=1 fail=none msg=1 tmp=0 diag=- stop=-" ] && ok "B12 -> ${WANT[B12]} ($(fx_msg B12), no summary)" \
  || notok "B12 -> ${WANT[B12]}, want 'rc=1 fail=none msg=1 tmp=0 diag=- stop=-' with '$(fx_msg B12)'"
# Each signal pinned to its own exit code (review fsfix5 N3(e)).
want_sig() { case $1 in
  STERM) echo "mark=1 seen=1 sum=0 tmp=0 end=exit=143 left=0" ;;
  SINT) echo "mark=1 seen=1 sum=0 tmp=0 end=exit=130 left=0" ;;
  SHUP) echo "mark=1 seen=1 sum=0 tmp=0 end=exit=129 left=0" ;;
  SCLEAN_*) echo "mark=1 seen=1 sum=1 tmp=0 end=exit=0 left=0" ;; esac; }
for x in STERM SINT SHUP SCLEAN_TERM SCLEAN_INT SCLEAN_HUP; do
  [ "${WANT[$x]}" = "$(want_sig "$x")" ] && ok "$x stopped on its event -> ${WANT[$x]}" \
    || notok "$x -> ${WANT[$x]}, want '$(want_sig "$x")'"
done

if [ "${MTV_REG_PINS_ONLY:-0}" != 1 ]; then
# Paired mutants of the meta-test, one per decision point (DPn above). Each is an
# exact, unique replacement in a copy; it is caught when its fixture's verdict
# differs from the original's. Ma and Mb are the round-4 reviewer mutants, MT1
# and MT9 the round-3 ones, R1b, R2, R3, R4, R5b and R7 the round-5 ones, verbatim.
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
    STERM|SINT|SHUP) got=$(sigfx "${2#S}" "$m") ;;
    SCLEAN_*) got=$(sigfx "${2#SCLEAN_}" "$m" clean) ;;
    *) got=$(fx "$2" "$m") ;;
  esac
  case "$got" in *end=timeout*|*end=nomark*) notok "mutation $1 BLIND on $2 twice ($got): no verdict"; return ;; esac
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
mtv_mutation DP11f_cleanup_signals_not_ignored SCLEAN_TERM "cleanup() { trap '' HUP INT TERM; " 'cleanup() { '
mtv_mutation DP12a_test_submodule_not_skipped G '        [ "$(basename -- "${s}")" = "${TEST_SUBMODULE}" ] && continue
' ''
mtv_mutation DP12b_gate_file_ignored G 'cp -- "${2:-${VERIFICATION_SCRIPT}}"' 'cp -- "${VERIFICATION_SCRIPT}"'
mtv_mutation DP13a_requirement_kept G "edits = ['    \"%s\"\\n' % name," 'edits = ['
mtv_mutation DP13b_check_kept G '         '"'"'run_check "%s (agent-skills)" \\\n    "ls -la %s/ && [ -f %s/README.md ]" \\\n    "${SUBMODULES_DIR}"\n'"'"' % (name, name, name)]' '         ]'
mtv_mutation DP13c_mutation1_on_real_tree G 'if bash "${R1}/scripts/validation/run_verification.sh"' 'if bash "${VERIFICATION_SCRIPT}"'
mtv_mutation DP13d_mutation2_on_m1_root G 'if bash "${R2}/scripts/validation/run_verification.sh"' 'if bash "${R1}/scripts/validation/run_verification.sh"'
# Round-5 reviewer mutants (review of fsfix5, N3), verbatim; RED first on the
# round-5 test (5 of 6 survived, R5b caught only through the self-comparison).
mtv_mutation R1b_int_hup_not_ignored_in_cleanup SCLEAN_INT "cleanup() { trap '' HUP INT TERM; " "cleanup() { trap '' HUP INT TERM; trap - HUP INT; "
mtv_mutation R1b_int_hup_not_ignored_in_cleanup_hup SCLEAN_HUP "cleanup() { trap '' HUP INT TERM; " "cleanup() { trap '' HUP INT TERM; trap - HUP INT; "
mtv_mutation R2_mktemp_failure_exit_0 B12 '|| { echo "✗ mktemp failed"; exit 1; }' '|| { echo "✗ mktemp failed"; exit 0; }'
mtv_mutation R3_duplicate_anchor_accepted B13 '    if c.count(old) != 1:' '    if c.count(old) == 0:'
mtv_mutation R4_cp_failure_ignored B14 'run_verification.sh" || return 1' 'run_verification.sh"'
mtv_mutation R5b_int_exits_143 SINT "trap 'exit 143' TERM" "trap 'exit 143' TERM
trap 'exit 143' INT"
# DP14 (round-6 census survivors, killed by the diag= pins).
mtv_mutation DP14a_control_stderr_dropped B2 '> "${W}/verify_real.txt" 2>&1' '> "${W}/verify_real.txt"'
mtv_mutation DP14b_control_output_not_captured B2 '> "${W}/verify_real.txt" 2>&1' '2>&1'
mtv_mutation DP14c_m1_stderr_dropped B16 '> "${W}/verify_missing.txt" 2>&1' '> "${W}/verify_missing.txt"'
mtv_mutation DP14d_m1_output_not_captured G '> "${W}/verify_missing.txt" 2>&1' '2>&1'
mtv_mutation DP14e_parse_errors_not_captured B11 ' 2> "${W}/weak_syntax.txt"; then' '; then'
mtv_mutation DP14f_m2_stderr_dropped B3 '> "${W}/verify_weak.txt" 2>&1' '> "${W}/verify_weak.txt"'
mtv_mutation DP14g_m2_output_not_captured B3 '> "${W}/verify_weak.txt" 2>&1' '2>&1'
# DP15 (round-6 census survivors, killed by the stop= pin).
mtv_mutation DP15a_m1_root_failure_no_finish B9 'notok "could not build the mutation-1 scratch root"; finish; }' 'notok "could not build the mutation-1 scratch root"; :; }'
mtv_mutation DP15b_mkdir_failure_ignored B9 'mkdir -p "${r}/scripts/validation" "${r}/submodules" || return 1' 'mkdir -p "${r}/scripts/validation" "${r}/submodules"'
mtv_mutation DP15c_m2_root_failure_no_finish B10 'notok "could not build the mutation-2 scratch root"; finish; }' 'notok "could not build the mutation-2 scratch root"; :; }'
mtv_mutation R7_ln_failure_ignored B15 '"${r}/submodules/$(basename -- "${s}")" || return 1' '"${r}/submodules/$(basename -- "${s}")"'
fi

[ -f "$TMP/notes" ] && cat "$TMP/notes"
echo "=== meta_test_verification regression guard (CON-158): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
