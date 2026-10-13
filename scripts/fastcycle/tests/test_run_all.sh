#!/bin/sh
# Purpose: test run_all.sh (empty-glob needle, pass, fail propagation).
# Usage: sh test_run_all.sh   Exit 0 = all assertions hold.
# shellcheck disable=SC2015 # audited every occurrence in this file (T014 round-10 MINOR-9 sweep):
# always the `<cond> && echo "ok ..." || { echo "NOT ok ..."; failx; }` TAP-style assertion idiom, or a
# chain of pure `[ ]` / `grep -q` boundary conditions with no side-effecting middle command -- so the
# "else" branch never fires for the wrong reason, since nothing between the test and the echo can fail
# independently of the tested condition.
# shellcheck disable=SC2016 # every flagged instance writes a GENERATED fixture-script's CONTENT via a
# single-quoted printf format string (e.g. `printf '...\necho $PPID...' >"$d8/tests/$f.sh"`); the
# embedded $VAR MUST stay literal here so the generated script's OWN shell expands it later, not this
# script writing it out.
here=$(cd "$(dirname "$0")" && pwd)
runner="$here/run_all.sh"
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }  # FC_TEST_FAILFAST: stop at the first failure (mutation sweeps)
chk() { # name expected_nonzero(1/0) actual_rc
  if { [ "$2" = 1 ] && [ "$3" -ne 0 ]; } || { [ "$2" = 0 ] && [ "$3" -eq 0 ]; }; then echo "ok $1 (rc=$3)"; else echo "NOT ok $1 (rc=$3)"; failx; fi
}
[ -f "$runner" ] || { echo "NOT ok run_all.sh missing"; exit 1; }
mkdir "$tmp/empty"
sh "$runner" "$tmp/empty" >"$tmp/o1" 2>&1; chk empty-dir-fails 1 $?
grep -q "zero test" "$tmp/o1" && echo "ok needle-message" || { echo "NOT ok needle-message"; failx; }
mkdir "$tmp/pass"; printf '#!/bin/sh\nexit 0\n' >"$tmp/pass/test_a.sh"
sh "$runner" "$tmp/pass" >"$tmp/o2" 2>&1; chk one-pass 0 $?
mkdir "$tmp/bad"; printf '#!/bin/sh\nexit 0\n' >"$tmp/bad/test_a.sh"; printf '#!/bin/sh\nexit 3\n' >"$tmp/bad/test_b.sh"
sh "$runner" "$tmp/bad" >"$tmp/o3" 2>&1; chk one-fail-propagates 1 $?
# per-test timeout: a hanging test must fail the suite, not stall it
mkdir "$tmp/hang"; printf '#!/bin/sh\nsleep 30\n' >"$tmp/hang/test_h.sh"
FASTCYCLE_TEST_TIMEOUT=1 timeout 20 sh "$runner" "$tmp/hang" >"$tmp/o4" 2>&1; chk hang-times-out-and-fails 1 $?
grep -qx "TIMEOUT test_h.sh" "$tmp/o4" && echo "ok timeout-reported" || { echo "NOT ok timeout-reported"; failx; }
# shebang honoured: bash-only syntax under a bash shebang must run under bash
mkdir "$tmp/sb"; printf '#!/usr/bin/env bash\n[[ a == a ]] || exit 1\n' >"$tmp/sb/test_b.sh"
sh "$runner" "$tmp/sb" >"$tmp/o5" 2>&1; chk shebang-honoured 0 $?
# R3-F6: timeout value 0 / non-numeric must be refused (exit 2), never silently disable the bound.
mkdir "$tmp/one"; printf '#!/bin/sh\nexit 0\n' >"$tmp/one/test_a.sh"
for v in 0 abc -1 "" 1x; do
  FASTCYCLE_TEST_TIMEOUT=$v timeout 20 sh "$runner" "$tmp/one" >"$tmp/o6" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && echo "ok bad-timeout-refused [$v]" || { echo "NOT ok bad-timeout-refused [$v] rc=$rc"; failx; }
  case $v in 0) pat="(>= 1)" ;; *) pat="at most 6 digits: '$v'" ;; esac
  grep -qF -- "$pat" "$tmp/o6" || { echo "NOT ok bad-timeout message [$v] lacks [$pat]"; failx; }
done
# R3-F6: a test that IGNORES TERM must still be killed (kill-after), not outlive the bound.
mkdir "$tmp/ign"; printf '#!/bin/sh\ntrap "" TERM\nexec sleep 25\n' >"$tmp/ign/test_i.sh"
t0=$(date +%s); FASTCYCLE_TEST_TIMEOUT=1 timeout 40 sh "$runner" "$tmp/ign" >"$tmp/o7" 2>&1; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 1 ] && [ "$el" -lt 12 ] && echo "ok term-ignorer-killed (${el}s)" || { echo "NOT ok term-ignorer-killed rc=$rc ${el}s"; failx; }
grep -qx "TIMEOUT test_i.sh" "$tmp/o7" && echo "ok term-ignorer-reported" || { echo "NOT ok term-ignorer-reported"; failx; }
# R4-F3: rule is 'positive integer, at most 6 characters': 7+ characters (leading zeros too) refused, <=6 accepted.
for v in 1234567 12345678 0000001 12345678901234567890 000000; do
  FASTCYCLE_TEST_TIMEOUT=$v timeout 20 sh "$runner" "$tmp/one" >"$tmp/o8" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && echo "ok long-timeout-refused [$v]" || { echo "NOT ok long-timeout-refused [$v] rc=$rc"; failx; }
  case $v in 000000) pat="(>= 1)" ;; *) pat="at most 6 digits: '$v'" ;; esac
  grep -qF -- "$pat" "$tmp/o8" || { echo "NOT ok long-timeout message [$v] lacks [$pat]"; failx; }
done
for v in 999999 123456 1 000001; do
  FASTCYCLE_TEST_TIMEOUT=$v timeout 20 sh "$runner" "$tmp/one" >"$tmp/o8" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && echo "ok timeout-accepted [$v]" || { echo "NOT ok timeout-accepted [$v] rc=$rc"; failx; }
done
# R4-F5 MYH: a #!/bin/sh test must run under `sh`, not bash. When sh is bash it runs in POSIX mode
# (`set -o posix` on); a plain `bash` run has posix off. Under dash BASH_VERSION is empty => pass.
mkdir "$tmp/shb"
cat >"$tmp/shb/test_s.sh" <<'EOS'
#!/bin/sh
[ -z "$BASH_VERSION" ] && exit 0
set -o | grep -q '^posix[[:space:]]*on$' && exit 0
exit 1
EOS
sh "$runner" "$tmp/shb" >"$tmp/o9" 2>&1; chk sh-shebang-runs-under-sh 0 $?
# the bash direction: a bash-shebang test must run under bash (already covered by shebang-honoured); label is exact.
grep -qx "PASS test_s.sh" "$tmp/o9" && echo "ok pass-label-exact" || { echo "NOT ok pass-label-exact"; failx; }
# R5 sweep additions: exact exit codes / summary / usage / default dir / depth guard / default bound.
mkdir "$tmp/e2"; sh "$runner" "$tmp/e2" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 1 ] && echo "ok empty-dir-rc-exactly-1" || { echo "NOT ok empty-dir-rc-exactly-1 rc=$rc"; failx; }
grep -q "^run_all: zero tests matched in $tmp/e2 (refusing" "$tmp/oa" && echo "ok zero-message-exact" || { echo "NOT ok zero-message-exact"; failx; }
sh "$runner" "$tmp/nodir" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "not a directory" "$tmp/oa" && echo "ok missing-dir-2" || { echo "NOT ok missing-dir-2 rc=$rc"; failx; }
sh "$runner" "$tmp/bad" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 1 ] && echo "ok fail-rc-exactly-1" || { echo "NOT ok fail-rc-exactly-1 rc=$rc"; failx; }
grep -qx "run_all: 2 run, 1 failed" "$tmp/oa" && grep -qx "PASS test_a.sh" "$tmp/oa" && grep -qx "FAIL test_b.sh" "$tmp/oa" && echo "ok summary-exact" || { echo "NOT ok summary-exact"; failx; }
sh "$runner" "$tmp/pass" >"$tmp/oa" 2>&1
grep -qx "run_all: 1 run, 0 failed" "$tmp/oa" && echo "ok summary-pass-exact" || { echo "NOT ok summary-pass-exact"; failx; }
timeout 20 sh "$runner" "$tmp/hang" >"$tmp/oa" 2>&1; rc=$?   # default bound 240 > 20: outer kills first
[ "$rc" -eq 124 ] && echo "ok default-bound-above-20s" || { echo "NOT ok default-bound-above-20s rc=$rc"; failx; }
FASTCYCLE_TEST_TIMEOUT=1 timeout 20 sh "$runner" "$tmp/hang" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 1 ] && echo "ok timeout-rc-exactly-1" || { echo "NOT ok timeout-rc-exactly-1 rc=$rc"; failx; }
# recursion guard: depth >= 2 refused; depth 1 accepted; depth exported to the tests (== incoming + 1).
FASTCYCLE_RUN_ALL_DEPTH=2 sh "$runner" "$tmp/pass" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "recursion depth exceeded" "$tmp/oa" && echo "ok depth2-refused" || { echo "NOT ok depth2-refused rc=$rc"; failx; }
FASTCYCLE_RUN_ALL_DEPTH=5 sh "$runner" "$tmp/pass" >"$tmp/oa" 2>&1; rc=$?; [ "$rc" -eq 2 ] && echo "ok depth5-refused" || { echo "NOT ok depth5-refused rc=$rc"; failx; }
FASTCYCLE_RUN_ALL_DEPTH=1 sh "$runner" "$tmp/pass" >"$tmp/oa" 2>&1; rc=$?; [ "$rc" -eq 0 ] && echo "ok depth1-accepted" || { echo "NOT ok depth1-accepted rc=$rc"; failx; }
mkdir "$tmp/dep"; printf '#!/bin/sh\n[ "$FASTCYCLE_RUN_ALL_DEPTH" = 1 ] || { echo "depth=$FASTCYCLE_RUN_ALL_DEPTH"; exit 1; }\n' >"$tmp/dep/test_d.sh"
env -u FASTCYCLE_RUN_ALL_DEPTH sh "$runner" "$tmp/dep" >"$tmp/oa" 2>&1; rc=$?; [ "$rc" -eq 0 ] && echo "ok depth-exported-1" || { echo "NOT ok depth-exported-1 rc=$rc"; cat "$tmp/oa"; failx; }
# default directory = the script's own directory.
mkdir "$tmp/own"; cp "$runner" "$tmp/own/run_all.sh"; printf '#!/bin/sh\nexit 0\n' >"$tmp/own/test_own.sh"
( cd "$tmp" && sh "$tmp/own/run_all.sh" >"$tmp/oa" 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && grep -qx "PASS test_own.sh" "$tmp/oa" && echo "ok default-dir-is-script-dir" || { echo "NOT ok default-dir-is-script-dir rc=$rc"; failx; }
# default bound is not tiny: a 3 s test passes with the timeout variable UNSET.
mkdir "$tmp/slow"; printf '#!/bin/sh\nsleep 3\n' >"$tmp/slow/test_slow.sh"
env -u FASTCYCLE_TEST_TIMEOUT timeout 30 sh "$runner" "$tmp/slow" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 0 ] && echo "ok default-bound-allows-3s" || { echo "NOT ok default-bound-allows-3s rc=$rc"; failx; }
# a test exiting 124 by itself is labelled TIMEOUT-free? (documented: 124/137 labelled TIMEOUT) - exact label lines only.
mkdir "$tmp/t137"; printf '#!/bin/sh\nexit 137\n' >"$tmp/t137/test_k.sh"
sh "$runner" "$tmp/t137" >"$tmp/oa" 2>&1; grep -qx "TIMEOUT test_k.sh" "$tmp/oa" && echo "ok exit137-labelled" || { echo "NOT ok exit137-labelled"; failx; }
mkdir "$tmp/t124"; printf '#!/bin/sh\nexit 124\n' >"$tmp/t124/test_k.sh"
sh "$runner" "$tmp/t124" >"$tmp/oa" 2>&1; grep -qx "TIMEOUT test_k.sh" "$tmp/oa" && echo "ok exit124-labelled" || { echo "NOT ok exit124-labelled"; failx; }
mkdir "$tmp/t2"; printf '#!/bin/sh\nexit 2\n' >"$tmp/t2/test_k.sh"
sh "$runner" "$tmp/t2" >"$tmp/oa" 2>&1; grep -q "^TIMEOUT" "$tmp/oa" && { echo "NOT ok exit2-not-timeout"; failx; } || echo "ok exit2-not-timeout"
# non-test files ignored; only test_*.sh.
mkdir "$tmp/ign2"; printf '#!/bin/sh\nexit 1\n' >"$tmp/ign2/helper.sh"; printf '#!/bin/sh\nexit 0\n' >"$tmp/ign2/test_x.sh"
sh "$runner" "$tmp/ign2" >"$tmp/oa" 2>&1; rc=$?; [ "$rc" -eq 0 ] && grep -qx "run_all: 1 run, 0 failed" "$tmp/oa" && echo "ok only-test-glob" || { echo "NOT ok only-test-glob rc=$rc"; failx; }
# R5 round-2 additions.
# empty depth variable is treated as unset (no shell error noise).
FASTCYCLE_RUN_ALL_DEPTH="" sh "$runner" "$tmp/pass" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ! grep -qi "expected" "$tmp/oa" && echo "ok empty-depth-is-unset" || { echo "NOT ok empty-depth-is-unset rc=$rc: $(head -c 200 "$tmp/oa")"; failx; }
# shebang line 1 only: a bash-shebang test runs under real bash (posix off); a sh test whose 2nd line mentions bash stays under sh.
mkdir "$tmp/bsh"
cat >"$tmp/bsh/test_b.sh" <<'EOS'
#!/usr/bin/env bash
[ -n "$BASH_VERSION" ] || exit 1
set -o | grep -q '^posix[[:space:]]*off$' && exit 0
exit 1
EOS
sh "$runner" "$tmp/bsh" >"$tmp/oa" 2>&1; chk bash-shebang-runs-under-bash 0 $?
mkdir "$tmp/sh2"
cat >"$tmp/sh2/test_s.sh" <<'EOS'
#!/bin/sh
# this comment mentions bash on line 2
[ -z "$BASH_VERSION" ] && exit 0
set -o | grep -q '^posix[[:space:]]*on$' && exit 0
exit 1
EOS
sh "$runner" "$tmp/sh2" >"$tmp/oa" 2>&1; chk shebang-only-first-line-counts 0 $?
mkdir "$tmp/env"; printf '#!/usr/bin/env sh\n[ -z "$BASH_VERSION" ] && exit 0\nset -o | grep -q "^posix[[:space:]]*on$" && exit 0\nexit 1\n' >"$tmp/env/test_e.sh"
sh "$runner" "$tmp/env" >"$tmp/oa" 2>&1; chk env-sh-shebang-runs-under-sh 0 $?
# labels: exit 1 and 2 FAIL (not PASS, not TIMEOUT); exit 125 / 130 FAIL and not TIMEOUT; only 124 / 137 are TIMEOUT.
for code in 1 2 125 130; do
  mkdir "$tmp/c$code"; printf '#!/bin/sh\nexit %s\n' "$code" >"$tmp/c$code/test_k.sh"
  sh "$runner" "$tmp/c$code" >"$tmp/oa" 2>&1; rc=$?
  grep -qx "FAIL test_k.sh" "$tmp/oa" && ! grep -q "^TIMEOUT" "$tmp/oa" && ! grep -q "^PASS" "$tmp/oa" && [ "$rc" -eq 1 ] && echo "ok exit$code-fail-label" || { echo "NOT ok exit$code-fail-label rc=$rc"; failx; }
done
# ROUND 6 (R5-F2): per-test bound override `# fastcycle-timeout-s: N` in the first 10 lines of a test file.
# A header value larger than the default lets a slow test finish (default 1 s here would TIMEOUT it).
mkdir "$tmp/ho"; printf '#!/bin/sh\n# fastcycle-timeout-s: 30\nsleep 3\n' >"$tmp/ho/test_slow.sh"
FASTCYCLE_TEST_TIMEOUT=1 timeout 40 sh "$runner" "$tmp/ho" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -qx "PASS test_slow.sh" "$tmp/oa" && echo "ok header-raises-bound" || { echo "NOT ok header-raises-bound rc=$rc: $(head -c 200 "$tmp/oa")"; failx; }
# A header smaller than the default bounds that test tighter (default 240 s; hang must be cut at 1 s).
mkdir "$tmp/hl"; printf '#!/bin/sh\n# fastcycle-timeout-s: 1\nsleep 30\n' >"$tmp/hl/test_h.sh"
t0=$(date +%s); env -u FASTCYCLE_TEST_TIMEOUT timeout 40 sh "$runner" "$tmp/hl" >"$tmp/oa" 2>&1; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 1 ] && [ "$el" -lt 12 ] && grep -qx "TIMEOUT test_h.sh" "$tmp/oa" && echo "ok header-lowers-bound (${el}s)" || { echo "NOT ok header-lowers-bound rc=$rc ${el}s"; failx; }
# Header applies per test: the neighbour without a header keeps the default (env) bound.
mkdir "$tmp/hn"; printf '#!/bin/sh\n# fastcycle-timeout-s: 30\nexit 0\n' >"$tmp/hn/test_a.sh"; printf '#!/bin/sh\nsleep 30\n' >"$tmp/hn/test_b.sh"
FASTCYCLE_TEST_TIMEOUT=1 timeout 40 sh "$runner" "$tmp/hn" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -qx "PASS test_a.sh" "$tmp/oa" && grep -qx "TIMEOUT test_b.sh" "$tmp/oa" && echo "ok header-is-per-test" || { echo "NOT ok header-is-per-test rc=$rc"; failx; }
# Accepted forms: <=6 digits, leading zeros allowed, shebang bash file, header on line 10.
for v in 1 000005 999999 123456; do
  mkdir "$tmp/hv$v"; printf '#!/bin/sh\n# fastcycle-timeout-s: %s\nexit 0\n' "$v" >"$tmp/hv$v/test_v.sh"
  timeout 20 sh "$runner" "$tmp/hv$v" >"$tmp/oa" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && echo "ok header-accepted [$v]" || { echo "NOT ok header-accepted [$v] rc=$rc"; failx; }
done
mkdir "$tmp/h10"; printf '#!/bin/sh\n#\n#\n#\n#\n#\n#\n#\n#\n# fastcycle-timeout-s: 1\nsleep 30\n' >"$tmp/h10/test_t.sh"
t0=$(date +%s); env -u FASTCYCLE_TEST_TIMEOUT timeout 40 sh "$runner" "$tmp/h10" >"$tmp/oa" 2>&1; el=$(( $(date +%s) - t0 ))
grep -qx "TIMEOUT test_t.sh" "$tmp/oa" && [ "$el" -lt 12 ] && echo "ok header-on-line-10-honoured" || { echo "NOT ok header-on-line-10-honoured ${el}s"; failx; }
# Line 11 is out of the documented window: ignored (the default bound applies, 20 s outer kill => 124).
mkdir "$tmp/h11"; printf '#!/bin/sh\n#\n#\n#\n#\n#\n#\n#\n#\n#\n# fastcycle-timeout-s: 1\nsleep 30\n' >"$tmp/h11/test_t.sh"
env -u FASTCYCLE_TEST_TIMEOUT timeout 8 sh "$runner" "$tmp/h11" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 124 ] && echo "ok header-line-11-ignored" || { echo "NOT ok header-line-11-ignored rc=$rc"; failx; }
# Malformed header => exit 2 naming the file, BEFORE any test runs (no marker created by the earlier good test).
i=0
for bad in '# fastcycle-timeout-s: abc' '# fastcycle-timeout-s: 0' '# fastcycle-timeout-s: 000000' '# fastcycle-timeout-s: 1234567' '# fastcycle-timeout-s: -5' '# fastcycle-timeout-s: 5 6' '# fastcycle-timeout-s: 12x' '# fastcycle-timeout-s:' '# fastcycle-timeout-s: ' '#fastcycle-timeout-s: 5' '#  fastcycle-timeout-s: 5' '# fastcycle-timeout-s:5' '# fastcycle-timeout-s: 5 '; do
  i=$((i + 1)); d="$tmp/hb$i"; mkdir "$d"
  printf '#!/bin/sh\n: >"%s/ran"\nexit 0\n' "$d" >"$d/test_a.sh"
  printf '#!/bin/sh\n%s\nexit 0\n' "$bad" >"$d/test_b.sh"
  timeout 20 sh "$runner" "$d" >"$tmp/oa" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && grep -q "test_b.sh" "$tmp/oa" && grep -q "fastcycle-timeout-s" "$tmp/oa" && [ ! -e "$d/ran" ] && echo "ok header-malformed-refused [$bad]" || { echo "NOT ok header-malformed-refused [$bad] rc=$rc ran=$([ -e "$d/ran" ] && echo yes || echo no): $(head -c 160 "$tmp/oa")"; failx; }
done
mkdir "$tmp/hd"; printf '#!/bin/sh\n# fastcycle-timeout-s: 5\n# fastcycle-timeout-s: 6\nexit 0\n' >"$tmp/hd/test_d.sh"
timeout 20 sh "$runner" "$tmp/hd" >"$tmp/oa" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "test_d.sh" "$tmp/oa" && echo "ok header-duplicate-refused" || { echo "NOT ok header-duplicate-refused rc=$rc"; failx; }
# The mutation meta-test carries a header and it is valid (the real tree's slowest test must not read FAIL under load).
mt="$here/test_foundational_mutations.sh"
hv=$(sed -n '1,10s/^# fastcycle-timeout-s: \([0-9][0-9]*\)$/\1/p' "$mt")
case $hv in ''|*[!0-9]*|???????*) echo "NOT ok mutation meta-test lacks a valid fastcycle-timeout-s header [$hv]"; failx ;; *) [ "$hv" -ge 900 ] && echo "ok mutation-test-header ($hv s)" || { echo "NOT ok mutation-test header $hv below the measured need"; failx; } ;; esac
# R7-F2: a HUP/INT/TERM to the runner (or Ctrl-C to its group) must reach the running test: `timeout` leads its own
# process group, so before round 8 a TERM orphaned the whole test tree for its bound and INT was swallowed until the test
# ended. Each variant: the runner gets the signal while a test sleeps; rc must be 2, nothing marked FC_ORPH may survive,
# the runner's temp dir must be gone. Every child is reaped by exact pid / by marker on every exit path.
lo_pids() { grep -la "FC_ORPH=$1" /proc/[0-9]*/environ 2>/dev/null | sed -n 's#^/proc/\([0-9]*\)/environ$#\1#p'; }
lo_kill() { for p in $(lo_pids "$1"); do [ "$p" -gt 1 ] && kill -s KILL "$p" 2>/dev/null; done; return 0; }
# shellcheck disable=SC2329 # invoked via `trap sigclean EXIT` below; the static call-graph does not
# credit a bareword `trap NAME SIGNAL` action as invoking NAME (verified false positive: reproduced by
# minimal repro -- adding a trailing unconditional `exit` after `trap NAME EXIT` is what makes the
# linter flag NAME as unused, even though `trap` genuinely dispatches to it at shell exit).
sigclean() { lo_kill "r8ra$$"; lo_kill "r8rb$$"; rm -rf "$tmp"; }
trap sigclean EXIT
mkdir "$tmp/sig" "$tmp/sigtmp"; printf '#!/bin/sh\nexec sleep 47\n' >"$tmp/sig/test_slow.sh"
# R8b-A8: the runner's final `wait` (after the KILLs) is what makes its exit mean "the killed job is reaped". A stand-in
# `timeout` that ignores TERM and holds 3 GiB of resident memory dies SLOWLY after the KILL (the kernel frees the pages
# during exit); the runner must not have exited while that process still exists. Without the `wait` the runner exits at
# once and /proc/<pid> is still there (measured in a scratch copy with the wait deleted, see round8b table).
mkdir "$tmp/slbin"
cat >"$tmp/slbin/timeout" <<'PYEOF'
#!/usr/bin/env python3
import os, signal, time
os.setpgid(0, 0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
b = bytearray(b'\1') * (3 << 30)
with open(os.environ["FC_SLPID"] + ".t", "w") as f: f.write(str(os.getpid()))
os.rename(os.environ["FC_SLPID"] + ".t", os.environ["FC_SLPID"])
time.sleep(60)
PYEOF
chmod +x "$tmp/slbin/timeout"
rm -rf "$tmp/sigtmp"; mkdir "$tmp/sigtmp"
set -m
FC_ORPH=r8ra$$ FC_SLPID="$tmp/slpid" TMPDIR="$tmp/sigtmp" PATH="$tmp/slbin:$PATH" sh "$runner" "$tmp/sig" >"$tmp/osl" 2>&1 </dev/null & rp=$!
set +m
i=0; while [ ! -s "$tmp/slpid" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
sp=$(cat "$tmp/slpid" 2>/dev/null)
case $sp in ''|*[!0-9]*) echo "NOT ok r8b A8: the slow-dying timeout stand-in never became ready"; kill -s KILL "$rp" 2>/dev/null; wait "$rp" 2>/dev/null; lo_kill "r8ra$$"; failx; sp= ;; esac
if [ -n "$sp" ]; then
  kill -s TERM "$rp" 2>/dev/null
  wait "$rp"; rc=$?
  if [ -e "/proc/$sp" ]; then echo "NOT ok r8b A8: the runner exited (rc=$rc) while the KILLed job $sp was not yet reaped"; lo_kill "r8ra$$"; failx
  else [ "$rc" -eq 2 ] && echo "ok r8b A8: the runner exit 2 came after the KILLed slow job was reaped" || { echo "NOT ok r8b A8: rc=$rc"; failx; }; fi
  lo_kill "r8ra$$"
fi
# R8b-D6: the mutation driver's cleanup must never signal a pid <= 1 even when its `ps` output names one as a descendant
# (a shimmed ps injecting `1 <job root>`, `0 <job root>`, `-1`, `abc`, `1x` lines; pid 0 = its own group, pid 1 = init).
# The driver runs with (a) a `ps` stand-in that prints the real listing plus those fake descendant lines of the running job
# root, and (b) an exported LOG-ONLY `kill` function: it records every call and forwards to the builtin only when the
# last argument is an integer > 1, so nothing at or below 1 is ever really signalled whatever the driver does. After a
# TERM the log must hold real signals to the stub tree (proof the path ran) and NO signal (-s TERM/KILL) to 0, 1, -1, abc, 1x.
# One job at a time (the host_guard stand-in answers N=1) so exactly one job root exists when the TERM lands.
d8="$tmp/d8tree"; cp -R "$here/.." "$d8"
printf '#!/bin/sh\nprintf "N=1\\n"\n' >"$d8/lib/host_guard.sh"
for f in test_host_guard_red test_fc_common_red test_triple_harness_red; do
  printf '#!/bin/sh\necho $PPID >>"$FC_ROOTFILE"\nexec sleep 43\n' >"$d8/tests/$f.sh"
done
mkdir "$tmp/psbin"
cat >"$tmp/psbin/ps" <<'PSEOF'
#!/bin/sh
"$FC_REALPS" "$@"
r=$(tail -n 1 "$FC_ROOTFILE" 2>/dev/null)
case $r in ''|*[!0-9]*) exit 0 ;; esac
for v in 1 0 -1 abc 1x; do echo "$v $r"; done
echo shim >>"$FC_SHIMLOG"
PSEOF
chmod +x "$tmp/psbin/ps"
cat >"$tmp/drvwrap.sh" <<'WEOF'
#!/bin/bash
# Defense-in-depth (independent of the driver's own descendants()/kill_tree() closure filtering,
# 11.4.263): even if the driver computed a broader-than-expected target set, this wrapper's `kill`
# forwards a real signal ONLY to a pid that is (a) a plain positive integer > 1 AND (b) actually
# marked FC_ORPH=$FC_ORPH -- i.e. a real descendant of THIS run, never any bystander integer > 1.
# The marker-lookup MUST be INLINE, not a separate helper function: this script's last line is
# `exec bash "$1"`, which REPLACES the process image; exported ENV VARS (including bash's env-var
# encoding of an `export -f`'d function) survive exec, but a plain, non-exported function's
# definition does NOT -- it lives only in the current process's internal function table, which
# `exec` discards. A prior version defined a separate `lo_pids()` helper and exported only `kill`,
# so after the exec below every call to `kill()` hit "lo_pids: command not found" (bash names the
# pseudo-script "environment" when reporting an error from an env-var-encoded function body),
# `$(lo_pids ...)` silently expanded to empty under no `set -e`, `marked` never got set, and EVERY
# kill call -- TERM, the `-0` liveness poll, and the final KILL -- was refused: kill_tree() never
# signalled anything at all, so the r8b-D6 stub outlived its 25 s test bound every time (measured:
# 3/3 deterministic reproductions, always exactly at the bound -- not a flake; root-caused with a
# debug-instrumented isolated repro before this fix was written, per 11.4.102/11.4.199). Inlining
# removes the whole "a helper needs its OWN export too" fragility class rather than only patching
# this one instance of it. A `case " $(...) " in *" $l "*)` form was tried first and rejected --
# the marker-lookup emits ONE pid per line and $(...) only strips TRAILING newlines, so a
# multi-line result collapses to a single space-joined string in which an embedded newline (not a
# space) still separates entries, silently failing the match for all but possibly the last pid; a
# `for` loop comparing one candidate at a time has no such failure mode.
# T014 round-10 IMPORTANT-4: the log used to record EVERY call's raw `$*` unconditionally, BEFORE the
# forward/refuse decision below -- so a call this function REFUSED (marked never set) left the exact
# same log line ("-s TERM <pid>") as a call it genuinely forwarded to `builtin kill`. The r8b-D6
# control-needle assertion below matched that log by content alone, so it could not tell "the real
# tree was signalled" apart from "a signal to the real tree was merely ATTEMPTED and then refused" --
# reproduced in a scratch copy by reintroducing the pre-fix unexported-helper bug: with that bug EVERY
# call is refused (marked never set), yet the old bare-content assertion still matched the logged
# line and reported "ok". Each log line now carries a leading FWD (genuinely passed to `builtin kill`)
# or REF (refused) tag, decided ONCE per call and logged exactly once, so a caller can tell forwarded
# from merely-attempted without changing which calls get forwarded (same decision logic as before).
kill() {
  local a l='' q marked= tag
  for a in "$@"; do l=$a; done
  case $l in
    ''|*[!0-9]*) tag=REF ;;
    *)
      if [ "$l" -gt 1 ]; then
        for q in $(grep -la "FC_ORPH=$FC_ORPH" /proc/[0-9]*/environ 2>/dev/null | sed -n 's#^/proc/\([0-9]*\)/environ$#\1#p'); do [ "$q" = "$l" ] && marked=1; done
      fi
      if [ -n "$marked" ]; then tag=FWD; else tag=REF; fi
      ;;
  esac
  printf '%s %s\n' "$tag" "$*" >>"$FC_KILLLOG"
  [ "$tag" = FWD ] && builtin kill "$@"
}
export -f kill
exec bash "$1"
WEOF
rm -rf "$tmp/dtmp"; mkdir "$tmp/dtmp"; : >"$tmp/d8.roots"; : >"$tmp/d8.shim"; : >"$tmp/d8.kills"
set -m
FC_ROOTFILE="$tmp/d8.roots" FC_SHIMLOG="$tmp/d8.shim" FC_KILLLOG="$tmp/d8.kills" FC_REALPS="$(command -v ps)" FC_ORPH=r8rb$$ TMPDIR="$tmp/dtmp" PATH="$tmp/psbin:$PATH" bash "$tmp/drvwrap.sh" "$d8/tests/test_foundational_mutations.sh" >"$tmp/d8.out" 2>&1 </dev/null & dp=$!
set +m
i=0; while [ ! -s "$tmp/d8.roots" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
if [ ! -s "$tmp/d8.roots" ]; then echo "NOT ok r8b D6: no job started under the driver"; kill -s KILL "$dp" 2>/dev/null; wait "$dp" 2>/dev/null; lo_kill "r8rb$$"; failx
else
  sleep 1; kill -s TERM "$dp" 2>/dev/null
  i=0; while kill -0 "$dp" 2>/dev/null && [ "$i" -lt 250 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$dp" 2>/dev/null; then echo "NOT ok r8b D6: driver still alive after 25 s"; kill -s KILL "$dp" 2>/dev/null; wait "$dp" 2>/dev/null; failx
  else wait "$dp"; rc=$?; [ "$rc" -eq 2 ] && echo "ok r8b D6 exit 2" || { echo "NOT ok r8b D6: expected exit 2 got $rc"; failx; }; fi
  [ -s "$tmp/d8.shim" ] && grep -Eq '^FWD -s TERM [0-9]+$' "$tmp/d8.kills" && echo "ok r8b D6: the fake-descendant ps ran and the driver genuinely FORWARDED a signal to the real tree" || { echo "NOT ok r8b D6: control needle failed (ps shim runs: $(wc -l <"$tmp/d8.shim"), kill log: $(tr '\n' '|' <"$tmp/d8.kills"))"; failx; }
  bad=$(grep -E '^(FWD|REF) -s [A-Z]+ (-- )?(0|1|-1|abc|1x)$' "$tmp/d8.kills" | tr '\n' '|')
  [ -z "$bad" ] && echo "ok r8b D6: no signal to a pid <= 1 or non-numeric" || { echo "NOT ok r8b D6: the driver signalled a bad value: $bad"; failx; }
  ! grep -q 'integer expression' "$tmp/d8.out" && echo "ok r8b D6: no test(1) integer error on the fake values" || { echo "NOT ok r8b D6: test(1) error: $(grep 'integer expression' "$tmp/d8.out" | head -1)"; failx; }
  # T014 round-10 IMPORTANT-4: a passing control-needle line above proves a FWD-tagged call was logged;
  # it does not by itself prove the marked descendant actually died. Poll for it directly (same pattern
  # as drv_case's own r7f3 survivor check below), so a kill() that logs FWD without a real effect (or a
  # driver whose kill_tree() stops short of the actual job) is caught here, not silently accepted.
  j=0; while [ -n "$(lo_pids r8rb$$)" ] && [ "$j" -lt 80 ]; do sleep 0.1; j=$((j + 1)); done
  if [ -n "$(lo_pids r8rb$$)" ]; then echo "NOT ok r8b D6: $(lo_pids r8rb$$ | wc -l) marked process(es) survived the driver"; failx
  else echo "ok r8b D6: no marked process survived the driver"; fi
  lo_kill "r8rb$$"
fi
# sig_case <label> <signal> <pid|group> [<PATH-dir prefix> [<tests dir>]]: 'group' signals the runner's whole process group
# (a terminal Ctrl-C: the runner is its own group leader under job control), 'pid' only the runner.
sig_case() {
  lbl=$1; sg=$2; tgt=$3; pd=${4-}; sdir=${5:-$tmp/sig}; rm -rf "$tmp/sigtmp"; mkdir "$tmp/sigtmp"
  # `set -m` (job control) for the launch: a plain `&` in a non-interactive shell starts the child with SIGINT IGNORED,
  # and an ignored-on-entry signal cannot be trapped, so no INT would ever reach the runner's trap (test artefact).
  # Under job control the runner leads its own process group (pgid == pid), like a foreground terminal job.
  set -m
  FC_ORPH=r8ra$$ TMPDIR="$tmp/sigtmp" PATH="${pd:+$pd:}$PATH" sh "$runner" "$sdir" >"$tmp/os" 2>&1 </dev/null & rp=$!
  set +m
  i=0; while [ -z "$(lo_pids r8ra$$)" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(lo_pids r8ra$$)" ] || { echo "NOT ok r7f2 $lbl: test never started"; kill -s KILL "$rp" 2>/dev/null; wait "$rp" 2>/dev/null; failx; return 0; }
  if [ "$tgt" = group ]; then
    pg=$(ps -o pgid= -p "$rp" 2>/dev/null | tr -d ' ')
    if [ "$pg" != "$rp" ]; then echo "SKIP r7f2 $lbl: job control gave no own process group (pgid=$pg)"; kill -s KILL "$rp" 2>/dev/null; wait "$rp" 2>/dev/null; lo_kill "r8ra$$"; return 0; fi
    [ "$rp" -gt 1 ] && kill -s "$sg" -- "-$rp" 2>/dev/null
  else
    kill -s "$sg" "$rp" 2>/dev/null
  fi
  i=0; while kill -0 "$rp" 2>/dev/null && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$rp" 2>/dev/null; then echo "NOT ok r7f2 $lbl: the runner ignored $sg (still alive after 15 s)"; kill -s KILL "$rp" 2>/dev/null; failx
  else
    wait "$rp"; rc=$?
    [ "$rc" -eq 2 ] && echo "ok r7f2 $lbl exit 2" || { echo "NOT ok r7f2 $lbl: expected exit 2 got $rc"; failx; }
  fi
  j=0; while [ -n "$(lo_pids r8ra$$)" ] && [ "$j" -lt 60 ]; do sleep 0.1; j=$((j + 1)); done
  if [ -n "$(lo_pids r8ra$$)" ]; then echo "NOT ok r7f2 $lbl: the test tree survived $sg to the runner"; lo_kill "r8ra$$"; failx
  else echo "ok r7f2 $lbl: test tree gone"; fi
  [ -z "$(ls -A "$tmp/sigtmp")" ] && echo "ok r7f2 $lbl: temp dir removed" || { echo "NOT ok r7f2 $lbl: temp dir leaked: $(ls "$tmp/sigtmp")"; failx; }
}
for sg in TERM HUP INT; do sig_case "pid-$sg" "$sg" pid; done
# A TERM must be GRACEFUL first: the test gets its own TERM (a chance to clean up its temp files) before any KILL.
mkdir "$tmp/sigg"; printf '#!/bin/sh\ntrap '"'"'echo term >"%s/g.mark"; exit 0'"'"' TERM\nsleep 47 &\nwait\n' "$tmp" >"$tmp/sigg/test_g.sh"
sig_case "graceful-TERM" TERM pid "" "$tmp/sigg"
[ -s "$tmp/g.mark" ] && echo "ok r7f2 graceful-TERM: the test ran its own TERM handler" || { echo "NOT ok r7f2 graceful-TERM: the test never got a TERM before the KILL"; failx; }
for sg in INT TERM; do sig_case "group-$sg" "$sg" group; done
# A `timeout` that IGNORES TERM (a python stand-in that leads its own group, ignores TERM and lets its child inherit the
# ignore, i.e. what a wedged timeout looks like) must not make the runner wait for the test bound: the bounded grace
# then KILLs the group (the real timeout installs a TERM handler, so only a stand-in can reach this branch).
mkdir "$tmp/tibin"
cat >"$tmp/tibin/timeout" <<'PYEOF'
#!/usr/bin/env python3
import os, signal, subprocess, sys
os.setpgid(0, 0)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
sys.exit(subprocess.call(sys.argv[4:]))
PYEOF
chmod +x "$tmp/tibin/timeout"
t0=$(date +%s); sig_case "term-ignoring-timeout" TERM pid "$tmp/tibin"; el=$(( $(date +%s) - t0 ))
[ "$el" -lt 30 ] && echo "ok r7f2 term-ignoring-timeout bounded (${el}s)" || { echo "NOT ok r7f2 term-ignoring-timeout took ${el}s"; failx; }
# The same under zsh (also as `sh`): `jobs -rp` prints whole job lines there (R7-F1); SKIP when zsh is absent.
if command -v zsh >/dev/null 2>&1; then
  mkdir "$tmp/zbin"; ln -s "$(command -v zsh)" "$tmp/zbin/sh"
  # the runner itself must run under zsh-as-sh: PATH-first `sh` would only affect its children, so invoke it directly
  FC_ORPH=r8ra$$ TMPDIR="$tmp/sigtmp" "$tmp/zbin/sh" "$runner" "$tmp/sig" >"$tmp/os" 2>&1 </dev/null & rp=$!
  i=0; while [ -z "$(lo_pids r8ra$$)" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  kill -s TERM "$rp" 2>/dev/null
  i=0; while kill -0 "$rp" 2>/dev/null && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  wait "$rp"; rc=$?; j=0; while [ -n "$(lo_pids r8ra$$)" ] && [ "$j" -lt 60 ]; do sleep 0.1; j=$((j + 1)); done
  [ "$rc" -eq 2 ] && [ -z "$(lo_pids r8ra$$)" ] && echo "ok r7f2 zsh runner: TERM -> exit 2, tree gone" || { echo "NOT ok r7f2 zsh runner: rc=$rc survivors=$(lo_pids r8ra$$ | tr '\n' ' ')"; lo_kill "r8ra$$"; failx; }
else echo "SKIP r7f2 zsh runner: zsh_unavailable"; fi
# R7-F3: a HUP/INT/TERM to the mutation driver (test_foundational_mutations.sh) must take every running control/mutant test
# tree down with it (they used to keep running on the deleted scratch copies), leak no temp dir, and exit 2. The driver is run
# from a COPY of the tree whose three owning tests are stubs that just sleep, so no real suite is started.
dt="$tmp/dtree"; cp -R "$here/.." "$dt"
printf '#!/bin/sh\nexec sleep 43\n' >"$dt/tests/test_host_guard_red.sh"
# this one has a TERM handler that leaves a mark: the driver must give TERM a chance BEFORE it KILLs (a graceful stop)
printf '#!/bin/sh\ntrap '"'"'echo term >"$FC_MARK"; exit 0'"'"' TERM\nsleep 43 &\nwait\n' >"$dt/tests/test_fc_common_red.sh"
# this one IGNORES TERM (its sleep inherits the ignore): only the driver's KILL stage can remove it
printf '#!/bin/sh\ntrap "" TERM\nexec sleep 43\n' >"$dt/tests/test_triple_harness_red.sh"
drv_case() { # <signal>
  sg=$1; rm -rf "$tmp/dtmp"; mkdir "$tmp/dtmp"
  set -m   # see sig_case: a plain `&` child ignores SIGINT
  rm -f "$tmp/d.mark"
  FC_MARK="$tmp/d.mark" FC_ORPH=r8rb$$ TMPDIR="$tmp/dtmp" bash "$dt/tests/test_foundational_mutations.sh" >"$tmp/od" 2>&1 </dev/null & dp=$!
  set +m
  i=0; while [ -z "$(lo_pids r8rb$$)" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(lo_pids r8rb$$)" ] || { echo "NOT ok r7f3 $sg: no test started under the driver"; kill -s KILL "$dp" 2>/dev/null; wait "$dp" 2>/dev/null; lo_kill "r8rb$$"; failx; return 0; }
  sleep 1; kill -s "$sg" "$dp" 2>/dev/null
  i=0; while kill -0 "$dp" 2>/dev/null && [ "$i" -lt 250 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$dp" 2>/dev/null; then echo "NOT ok r7f3 $sg: driver still alive after 25 s"; kill -s KILL "$dp" 2>/dev/null; wait "$dp" 2>/dev/null; failx
  else wait "$dp"; rc=$?; [ "$rc" -eq 2 ] && echo "ok r7f3 $sg exit 2" || { echo "NOT ok r7f3 $sg: expected exit 2 got $rc"; failx; }; fi
  j=0; while [ -n "$(lo_pids r8rb$$)" ] && [ "$j" -lt 80 ]; do sleep 0.1; j=$((j + 1)); done
  if [ -n "$(lo_pids r8rb$$)" ]; then echo "NOT ok r7f3 $sg: $(lo_pids r8rb$$ | wc -l) test process(es) survived the driver"; lo_kill "r8rb$$"; failx
  else echo "ok r7f3 $sg: no test survived"; fi
  [ -s "$tmp/d.mark" ] && echo "ok r7f3 $sg: the driver let TERM reach a test before any KILL" || { echo "NOT ok r7f3 $sg: the test never got its TERM (driver KILLed at once)"; failx; }
  [ -z "$(ls -A "$tmp/dtmp")" ] && echo "ok r7f3 $sg: no temp dir leaked" || { echo "NOT ok r7f3 $sg: leaked: $(ls "$tmp/dtmp")"; failx; }
}
drv_case TERM; drv_case INT
# The test's stdin must be /dev/null, not the runner's: under a real pty with job control (`sh -m`) a bare '&' job that reads
# the tty is stopped (SIGTTIN) and would sit until its bound. The test below reads stdin and must finish (exit 0) quickly.
mkdir "$tmp/stdin"; printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' >"$tmp/stdin/test_r.sh"
pty_out=$(PTY_SET="FASTCYCLE_TEST_TIMEOUT=4" python3 - sh -m "$runner" "$tmp/stdin" <<'PYEOF'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    for kv in os.environ.get("PTY_SET", "").split(";"):
        if "=" in kv: k, v = kv.split("=", 1); os.environ[k] = v
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""; t0 = time.time()
while True:
    r, _, _ = select.select([fd], [], [], 1)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    if time.time() - t0 > 60:
        os.kill(pid, 9); break
_, st = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace")); sys.stdout.write("exit=%d\n" % (os.waitstatus_to_exitcode(st)))
PYEOF
)
printf '%s\n' "$pty_out" | grep -q '^exit=0' && printf '%s\n' "$pty_out" | grep -q '^PASS test_r.sh' && echo "ok r7f2 stdin of a test is /dev/null under job control" || { echo "NOT ok r7f2 stdin inherited from the runner under job control: $(printf '%s\n' "$pty_out" | tail -3 | tr '\n' ' ')"; failx; }
# R7b for the runner (jobs shimmed, kill log-only): no pgid <= 1 for any jobs output (0, 1, -1, empty, non-numeric,
# multi-word, backslash line, zsh whole-line format), dash-like `jobs -r` rejection falls back to `jobs -p`.
res=$(bash "$here/fixtures/triple_harness/jobs_shim_check.sh" runall "$here")
[ -z "$res" ] && echo "ok r7b runner jobs shim" || { printf '%s\n' "$res"; printf '%s\n' "$res" | grep -q '^FAIL' && failx; }
exit $fail
