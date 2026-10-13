#!/bin/bash
# Test for check_deps.sh: scrubbed PATH lacking one tool => exit 4 naming it; full PATH => lists all found (or 4 honestly).
# fastcycle-timeout-s: 600
# (measured serial 210 s at load ~35; the 240 s default leaves no margin. 600 s = ~3x, operator-tunable, not a data-derived bound)
HERE=$(cd "$(dirname "$0")" && pwd)
SUT="$HERE/check_deps.sh"
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }  # FC_TEST_FAILFAST: stop at the first failure (mutation sweeps)
[ -x "$SUT" ] || { echo "FAIL: $SUT missing/not executable"; exit 1; }
TOOLS="git sqlite3 strace pandoc weasyprint shellcheck python3 mmdc"
# Case 1: scrubbed PATH = every present tool + helpers EXCEPT git (timeout included so ONLY git is absent)
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
mkpath() { # dir skip_tool : shim EVERY executable from the real PATH (so tool wrappers keep their
  # interpreters) except skip_tool, so ONLY that tool is genuinely absent.
  OLDIFS=$IFS; IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      b=${f##*/}; [ "$b" = "$2" ] && continue
      # exec-shim (not a symlink): wrappers that resolve their own dirname via $0 keep working
      [ -x "$f" ] && [ ! -e "$1/$b" ] && { printf '#!/bin/sh\nexec "%s" "$@"\n' "$f" >"$1/$b"; chmod +x "$1/$b"; }
    done
  done
  IFS=$OLDIFS
}
mkpath "$S" git
out=$(PATH="$S" "$SUT" 2>&1); rc=$?
[ "$rc" -eq 4 ] || { echo "FAIL case1: rc=$rc want 4"; failx; }
# expected MISSING set = git + any tool genuinely absent on this host
want="git"; for t in $TOOLS; do [ "$t" = git ] || command -v "$t" >/dev/null 2>&1 || want="$want $t"; done
got=$(echo "$out" | sed -n 's/^MISSING \([^:]*\):.*/\1/p' | sort | tr '\n' ' ')
exp=$(echo "$want" | tr ' ' '\n' | sort | tr '\n' ' ')
[ "$got" = "$exp" ] || { echo "FAIL case1: MISSING set '$got' != '$exp'"; failx; }
echo "$out" | grep -q "^BLIND: missing/unusable: git" || [ "$want" != git ] || { echo "FAIL case1: exit-4 message must name exactly git"; failx; }
# F14: broken tool (loader error, exit 127) must be MISSING/unusable, not FOUND
B=$(mktemp -d); trap 'rm -rf "$S" "$B"' EXIT
mkpath "$B" git
printf '#!/bin/sh\necho "error while loading shared libraries: libfoo.so"\nexit 127\n' >"$B/git"; chmod +x "$B/git"
out=$(PATH="$B" "$SUT" 2>&1); rc=$?
[ "$rc" -eq 4 ] || { echo "FAIL F14: broken tool rc=$rc want 4"; failx; }
echo "$out" | grep -q "^MISSING git" || { echo "FAIL F14: broken git not reported MISSING"; failx; }
echo "$out" | grep -q "^FOUND git" && { echo "FAIL F14: broken git reported FOUND"; failx; }
# exit 0 with empty output is also unusable
printf '#!/bin/sh\nexit 0\n' >"$B/git"
out=$(PATH="$B" "$SUT" 2>&1); echo "$out" | grep -q "^MISSING git" || { echo "FAIL F14: silent tool not MISSING"; failx; }
# timeout itself absent => named, not swallowed as a version string
T=$(mktemp -d); mkpath "$T" timeout
out=$(PATH="$T" "$SUT" 2>&1); rc=$?
[ "$rc" -eq 4 ] || { echo "FAIL timeout-absent: rc=$rc"; failx; }
echo "$out" | grep -q "timeout" || { echo "FAIL timeout-absent: timeout not named"; failx; }
echo "$out" | grep -q "^FOUND.*command not found" && { echo "FAIL timeout-absent: garbage FOUND"; failx; }
echo "$out" | grep -q "/jobs" && { echo "FAIL timeout-absent: cleanup wrote to a stray path (/jobs)"; failx; }
rm -rf "$T"
# F15/MR8: a HANGING tool must be reported MISSING with rc=124 (timeout), not hang the probe.
H=$(mktemp -d); mkpath "$H" git
printf '#!/bin/sh\nsleep 60\n' >"$H/git"; chmod +x "$H/git"
t0=$(date +%s); out=$(FC_PROBE_TIMEOUT_S=1 PATH="$H" timeout 45 "$SUT" 2>&1); rc=$?; el=$(( $(date +%s) - t0 ))
[ "$el" -lt 20 ] || { echo "FAIL hang: probe took ${el}s, FC_PROBE_TIMEOUT_S=1 not honoured"; failx; }
[ "$rc" -eq 4 ] || { echo "FAIL hang: rc=$rc want 4 (hang => 124 from outer timeout)"; failx; }
echo "$out" | grep -q "^MISSING git: --version rc=124" || { echo "FAIL hang: git not reported MISSING rc=124"; failx; }
rm -rf "$H"
# R3-F6: probe timeout 0 / non-numeric refused (exit 2); TERM-ignoring tool is KILLed promptly.
for v in 0 abc -1 1x ""; do
  FC_PROBE_TIMEOUT_S=$v timeout 20 "$SUT" >"$S/o6" 2>&1; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL bad probe timeout [$v]: rc=$rc want 2"; failx; }
  case $v in 0) pat="(>= 1)" ;; *) pat="at most 6 digits: '$v'" ;; esac
  grep -qF -- "$pat" "$S/o6" || { echo "FAIL bad probe timeout [$v]: message lacks [$pat]"; failx; }
done
K=$(mktemp -d); mkpath "$K" git
printf '#!/bin/sh\ntrap "" TERM\nexec sleep 60\n' >"$K/git"; chmod +x "$K/git"
t0=$(date +%s); out=$(FC_PROBE_TIMEOUT_S=1 PATH="$K" timeout 45 "$SUT" 2>&1); rc=$?; el=$(( $(date +%s) - t0 ))
[ "$el" -lt 15 ] || { echo "FAIL term-ignorer: probe took ${el}s"; failx; }
echo "$out" | grep -q "^MISSING git" || { echo "FAIL term-ignorer: git not MISSING"; failx; }
rm -rf "$K"
# MXL: a present-but-BROKEN timeout must be named as the cause (probe of timeout itself).
W=$(mktemp -d); mkpath "$W" timeout
printf '#!/bin/sh\nexit 127\n' >"$W/timeout"; chmod +x "$W/timeout"
out=$(PATH="$W" "$SUT" 2>&1); rc=$?
[ "$rc" -eq 4 ] || { echo "FAIL broken-timeout: rc=$rc want 4"; failx; }
echo "$out" | grep -q "^MISSING timeout:" || { echo "FAIL broken-timeout: timeout not named as cause"; failx; }
echo "$out" | grep -q "^BLIND:.* timeout" || { echo "FAIL broken-timeout: BLIND line does not name timeout"; failx; }
rm -rf "$W"
# R4-F3: probe timeout rule 'positive integer, at most 6 characters'.
for v in 1234567 12345678 0000001 12345678901234567890 000000; do
  FC_PROBE_TIMEOUT_S=$v timeout 20 "$SUT" >"$S/o8" 2>&1; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL long probe timeout [$v]: rc=$rc want 2"; failx; }
  case $v in 000000) pat="(>= 1)" ;; *) pat="at most 6 digits: '$v'" ;; esac
  grep -qF -- "$pat" "$S/o8" || { echo "FAIL long probe timeout [$v]: message lacks [$pat]"; failx; }
done
for v in 999999 123456 1 000001; do
  FC_PROBE_TIMEOUT_S=$v timeout 60 "$SUT" >/dev/null 2>&1; rc=$?
  case $rc in 0|4) ;; *) echo "FAIL probe timeout accepted [$v]: rc=$rc want 0|4"; failx ;; esac
done
# R5 sweep additions: exact message formats, first-line-only, stderr captured, stdin closed, default bound, self-probe.
E=$(mktemp -d); mkpath "$E" git
out=$(PATH="$E" "$SUT" 2>&1)
echo "$out" | grep -qx "MISSING git: --version rc=1, output '' (absent or unusable)" || { echo "FAIL exact absent line for git"; failx; }
want=""; for t in $TOOLS; do [ "$t" = git ] || command -v "$t" >/dev/null 2>&1 || want="$want $t"; done
echo "$out" | grep -qx "BLIND: missing/unusable: git$(printf '%s' "$(for t in $TOOLS; do [ "$t" = git ] || command -v "$t" >/dev/null 2>&1 || printf ' %s' "$t"; done)")" || { echo "FAIL exact BLIND line (tool order)"; failx; }
printf '#!/bin/sh\necho "error while loading shared libraries: libfoo.so"\nexit 127\n' >"$E/git"; chmod +x "$E/git"
PATH="$E" "$SUT" 2>&1 | grep -qx "MISSING git: --version rc=127, output 'error while loading shared libraries: libfoo.so' (absent or unusable)" || { echo "FAIL exact broken line for git"; failx; }
# first line only
printf '#!/bin/sh\necho v1.0\necho v2-second\necho v3-third\n' >"$E/git"
o=$(PATH="$E" "$SUT" 2>&1)
echo "$o" | grep -qx "FOUND git: v1.0" || { echo "FAIL FOUND line format/first line"; failx; }
echo "$o" | grep -q "v2-second" && { echo "FAIL extra version lines leaked"; failx; }
# version printed on stderr is still captured
printf '#!/bin/sh\necho v9.9 >&2\n' >"$E/git"
PATH="$E" "$SUT" 2>&1 | grep -qx "FOUND git: v9.9" || { echo "FAIL stderr version not captured"; failx; }
# stdin closed for probes: a tool that reads stdin must not hang the probe (stdin here never closes)
printf '#!/bin/sh\ncat >/dev/null\necho vstdin\n' >"$E/git"
mkfifo "$E/fifo"; exec 3<>"$E/fifo"   # read-write open: stdin that never reaches EOF
o=$(PATH="$E" FC_PROBE_TIMEOUT_S=3 "$SUT" 2>&1 <&3); exec 3<&-
echo "$o" | grep -qx "FOUND git: vstdin" || { echo "FAIL probe stdin not closed (hang => MISSING)"; failx; }
# default probe bound is not tiny (unset var, hanging tool: still probing after 7 s)
printf '#!/bin/sh\nsleep 40\n' >"$E/git"
env -u FC_PROBE_TIMEOUT_S PATH="$E" timeout 7 "$SUT" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 124 ] || { echo "FAIL default probe bound < 7 s (rc=$rc)"; failx; }
# self-probe message names the bound and command exactly
rm -f "$E/timeout"
o=$(PATH="$E" "$SUT" 2>&1)
echo "$o" | grep -qx "MISSING timeout: cannot run 'timeout 5 sh -c :' (absent or unusable)" || { echo "FAIL exact timeout line"; failx; }
echo "$o" | grep -qx "BLIND: missing/unusable: timeout.*" || { echo "FAIL BLIND names timeout first"; failx; }
# full host: every tool that is usable on this host must be reported FOUND, no other line kinds.
out2=$("$SUT" 2>&1)
for t in $TOOLS; do
  if command -v "$t" >/dev/null 2>&1 && timeout 30 "$t" --version </dev/null >/dev/null 2>&1; then
    echo "$out2" | grep -q "^FOUND $t: ." || { echo "FAIL host-usable $t not FOUND"; failx; }
  fi
done
echo "$out2" | grep -qv '^\(FOUND \|MISSING \|BLIND: \)' && { echo "FAIL unexpected output lines"; failx; }
[ "$(echo "$out2" | grep -c '^\(FOUND\|MISSING\) ')" -eq 8 ] || { echo "FAIL expected exactly 8 tool lines"; failx; }
rm -rf "$E"
# usage refusals: exact rc 2 (already tested) with the digit message; boundary FC_PROBE_TIMEOUT_S=1 accepted.
FC_PROBE_TIMEOUT_S=1 timeout 60 "$SUT" >/dev/null 2>&1; rc=$?; case $rc in 0|4) ;; *) echo "FAIL probe timeout 1 accepted rc=$rc"; failx ;; esac
# R5 round-2 additions.
# BLIND goes to stderr (not stdout); exit 0 only when everything is usable (all 8 tools shimmed usable).
F=$(mktemp -d); mkpath "$F" __none__
for t in $TOOLS; do printf '#!/bin/sh\necho "%s 1.0"\n' "$t" >"$F/$t"; chmod +x "$F/$t"; done
out=$(PATH="$F" "$SUT" 2>"$F/err"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL all-usable: rc=$rc want 0"; failx; }
[ -z "$(cat "$F/err")" ] || { echo "FAIL all-usable: unexpected stderr"; failx; }
[ "$(echo "$out" | grep -c '^FOUND ')" -eq 8 ] || { echo "FAIL all-usable: 8 FOUND lines expected"; failx; }
echo "$out" | grep -q "^MISSING\|^BLIND" && { echo "FAIL all-usable: MISSING/BLIND printed"; failx; }
rm -f "$F/git" "$F/sqlite3"
out=$(PATH="$F" "$SUT" 2>"$F/err" ); rc=$?
[ "$rc" -eq 4 ] || { echo "FAIL two-missing: rc=$rc want 4"; failx; }
grep -qx "BLIND: missing/unusable: git sqlite3" "$F/err" || { echo "FAIL BLIND line not on stderr / order (git sqlite3): $(cat "$F/err")"; failx; }
echo "$out" | grep -q "^BLIND" && { echo "FAIL BLIND printed on stdout"; failx; }
m1=$(echo "$out" | grep -n '^MISSING git' | cut -d: -f1); m2=$(echo "$out" | grep -n '^MISSING sqlite3' | cut -d: -f1)
[ -n "$m1" ] && [ -n "$m2" ] && [ "$m1" -lt "$m2" ] || { echo "FAIL MISSING lines out of TOOLS order (git before sqlite3)"; failx; }
# timeout absent: tools are NOT probed (rc=1, empty output, no rc=127 noise); self-probe TERM-ignoring sh is KILLed.
rm -f "$F/timeout"
out=$(PATH="$F" "$SUT" 2>&1)
echo "$out" | grep -qx "MISSING python3: --version rc=1, output '' (absent or unusable)" || { echo "FAIL timeout-absent: tools must not be probed without timeout"; failx; }
X=$(mktemp -d); printf '#!/bin/bash\ntrap "" TERM\nexec sleep 40\n' >"$X/sh"; chmod +x "$X/sh"
mkpath "$X" sh; printf '#!/bin/bash\ntrap "" TERM\nexec sleep 40\n' >"$X/sh"
t0=$(date +%s); out=$(PATH="$X" timeout 30 "$SUT" 2>&1); el=$(( $(date +%s) - t0 ))
[ "$el" -lt 25 ] || { echo "FAIL TERM-ignoring self-probe not killed (${el}s)"; failx; }
echo "$out" | grep -q "^MISSING timeout:" || { echo "FAIL TERM-ignoring self-probe not reported"; failx; }
rm -rf "$F" "$X"
# ROUND 5b id c225: an absent `timeout` must be reported MISSING even if a BASH_ENV command_not_found_handle
# makes every unknown command "succeed" (a bare `if timeout ...` would accept it; `command -v` must gate).
N=$(mktemp -d); for b in bash head sh; do ln -s "$(command -v $b)" "$N/$b"; done
printf 'command_not_found_handle() { return 0; }\n' >"$N/env.sh"
out=$(PATH="$N" BASH_ENV="$N/env.sh" "$(command -v bash)" "$SUT" 2>&1); rc=$?
echo "$out" | grep -q "^MISSING timeout:" && [ "$rc" -eq 4 ] || { echo "FAIL c225: absent timeout accepted under command_not_found_handle (rc=$rc)"; failx; }
rm -rf "$N"
# ROUND 6 (R5-F1): a probe whose descendant keeps stdout open must not delay the verdict past the bound, and nothing may outlive the call.
lo_pids() { grep -la "FC_ORPH=$1" /proc/[0-9]*/environ 2>/dev/null | sed -n 's#^/proc/\([0-9]*\)/environ$#\1#p'; }
lo_kill() { for p in $(lo_pids "$1"); do [ "$p" -gt 1 ] && kill -s KILL "$p" 2>/dev/null; done; return 0; }
r6clean() { for m in r6a r6b r6c r6d r6e; do lo_kill "$m$$"; done; rm -rf "$S" "$B" "$H" "$K" "$W" "$G" "$G2" 2>/dev/null; }
trap r6clean EXIT
env FC_ORPH=r6c$$ sleep 30 & r6c=$!
i=0; while [ -z "$(lo_pids r6c$$)" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
[ -n "$(lo_pids r6c$$)" ] || { echo "FAIL r6 instrument: scan cannot see a live marked process (positive control)"; failx; }
[ -z "$(lo_pids r6neg$$)" ] || { echo "FAIL r6 instrument: scan finds an absent marker (negative control)"; failx; }
kill -s KILL "$r6c" 2>/dev/null; wait "$r6c" 2>/dev/null
G=$(mktemp -d); mkpath "$G" git
printf '#!/bin/sh\nsleep 60 &\necho git-mock 1.0\nexit 0\n' >"$G/git"; chmod +x "$G/git"
t0=$(date +%s); out=$(env FC_ORPH=r6a$$ FC_PROBE_TIMEOUT_S=3 PATH="$G" timeout -k 1 40 "$SUT" 2>&1); rc=$?; el=$(( $(date +%s) - t0 ))
echo "$out" | grep -q "^FOUND git: git-mock 1.0$" || { echo "FAIL r5-f1: stdout-holding grandchild: git not FOUND (rc=$rc, ${el}s)"; failx; }
[ "$el" -lt 30 ] || { echo "FAIL r5-f1: probe waited ${el}s for a stdout-holding grandchild"; failx; }
[ -z "$(lo_pids r6a$$)" ] || { echo "FAIL r5-f1: orphaned descendant survived check_deps"; failx; }
lo_kill "r6a$$"
G2=$(mktemp -d); mkpath "$G2" git
printf '#!/bin/sh\ntrap "" TERM\nsleep 300 &\nsleep 300\n' >"$G2/git"; chmod +x "$G2/git"
t0=$(date +%s); out=$(env FC_ORPH=r6b$$ FC_PROBE_TIMEOUT_S=3 PATH="$G2" timeout -k 1 60 "$SUT" 2>&1); rc=$?; el=$(( $(date +%s) - t0 ))
echo "$out" | grep -q "^MISSING git: --version rc=" || { echo "FAIL r5-f1 hang: git not MISSING (rc=$rc)"; failx; }
[ "$el" -lt 40 ] || { echo "FAIL r5-f1 hang: took ${el}s with a 3 s probe bound"; failx; }
[ -z "$(lo_pids r6b$$)" ] || { echo "FAIL r5-f1 hang: orphan survived"; failx; }
lo_kill "r6b$$"
# ROUND 6b (sweep survivors, killed by tests).
# A TERM-ignoring descendant left behind by a NORMAL probe exit must be KILLed, not TERMed.
G3=$(mktemp -d); mkpath "$G3" git
printf '#!/bin/sh\ntrap "" TERM\nsleep 60 &\necho git-mock 1.0\nexit 0\n' >"$G3/git"; chmod +x "$G3/git"
out=$(env FC_ORPH=r6d$$ FC_PROBE_TIMEOUT_S=3 PATH="$G3" timeout -k 1 60 "$SUT" 2>&1)
echo "$out" | grep -q "^FOUND git: git-mock 1.0$" || { echo "FAIL r6b: TERM-ignoring orphan: git not FOUND"; failx; }
[ -z "$(lo_pids r6d$$)" ] || { echo "FAIL r6b: a TERM-ignoring orphan survived a normal probe exit (group must get KILL)"; failx; }
lo_kill "r6d$$"
# A probe that prints its version on STDERR only is still FOUND (stderr is merged into the probe output).
G4=$(mktemp -d); mkpath "$G4" git
printf '#!/bin/sh\necho "gitv-on-stderr 9" >&2\nexit 0\n' >"$G4/git"; chmod +x "$G4/git"
out=$(PATH="$G4" "$SUT" 2>&1)
echo "$out" | grep -q "^FOUND git: gitv-on-stderr 9$" || { echo "FAIL r6b: version on stderr not FOUND"; failx; }
# The probe's stdin is /dev/null, not the caller's: proven under a real pty with job control (`bash -m`), where a bare '&' keeps the tty as stdin.
G5=$(mktemp -d); mkpath "$G5" git
printf '#!/bin/sh\ncat >/dev/null\necho git-stdin-mock 1.0\n' >"$G5/git"; chmod +x "$G5/git"
pty_run() { # cmd... : run under a pty, print the output then 'exit=<n>'
  python3 - "$@" <<'PYEOF'
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
}
out=$(PTY_SET="FC_PROBE_TIMEOUT_S=3;PATH=$G5"; export PTY_SET; pty_run bash -m "$SUT" 2>&1) || true
echo "$out" | grep -q "FOUND git: git-stdin-mock 1.0" || { echo "FAIL r6b: probe inherited the tty stdin under job control: $(echo "$out" | head -2)"; failx; }
# Each probe's output is separate (a stale/appended scratch file would show the FIRST tool's line for later tools).
G6=$(mktemp -d); mkpath "$G6" git; mkpath "$G6" sqlite3; mkpath "$G6" strace
printf '#!/bin/sh\necho gitmock-1\n' >"$G6/git"; printf '#!/bin/sh\nexit 0\n' >"$G6/sqlite3"; printf '#!/bin/sh\necho stracemock-3\n' >"$G6/strace"; chmod +x "$G6/git" "$G6/sqlite3" "$G6/strace"
out=$(PATH="$G6" "$SUT" 2>&1)
# shellcheck disable=SC2015 # pure boolean chain (three `grep -q` checks culminating in `|| FAIL`); no
# side-effecting step exists between the checks and the FAIL branch, so C never fires for the wrong
# reason -- there is nothing here for shellcheck's usual A-then-B concern to apply to.
echo "$out" | grep -q "^FOUND git: gitmock-1$" && echo "$out" | grep -q "^MISSING sqlite3: --version rc=0, output ''" && echo "$out" | grep -q "^FOUND strace: stracemock-3$" || { echo "FAIL r6b: probe outputs bleed between tools: $(echo "$out" | head -3)"; failx; }
# No scratch dir is left behind (TMPDIR watched), on a normal run.
TD6=$(mktemp -d); TMPDIR="$TD6" "$SUT" >/dev/null 2>&1
[ -z "$(ls -A "$TD6")" ] || { echo "FAIL r6b: scratch dir leaked: $(ls "$TD6")"; failx; }
# A signal while a probe hangs: exit 2, probe group killed, scratch dir removed.
for sg in TERM HUP INT; do
  set -m   # a plain `&` child ignores SIGINT from birth (an ignored-on-entry signal cannot be trapped): job control, R7-F5
  env FC_ORPH=r6e$$ TMPDIR="$TD6" FC_PROBE_TIMEOUT_S=60 PATH="$G2" "$SUT" >/dev/null 2>&1 &
  hp=$!; set +m
  i=0; while [ -z "$(lo_pids r6e$$)" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(lo_pids r6e$$)" ] || { echo "FAIL r6b signal $sg: probe never started"; failx; }
  kill -s "$sg" "$hp"; wait "$hp"; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL r6b signal $sg: expected exit 2 got $rc"; failx; }
  sleep 0.5
  [ -z "$(lo_pids r6e$$)" ] || { echo "FAIL r6b signal $sg: probe group survived"; failx; }
  lo_kill "r6e$$"
  [ -z "$(ls -A "$TD6")" ] || { echo "FAIL r6b signal $sg: scratch dir leaked: $(ls "$TD6")"; failx; }
done
# A broken mktemp (rc 0 but empty output / a path that does not exist / an existing FILE / rc 1 with noise) is named MISSING, never used:
# no probe runs (no shell redirect error), nothing relative is removed (cwd holds a dir named x), mktemp stderr is not leaked.
f6=$(mktemp); XC=$(mktemp -d); mkdir "$XC/x"
i=0
for mk in 'exit 0' 'echo /nonexistent-r6b-dir; exit 0' "echo $f6; exit 0" 'echo MKTEMP-NOISE >&2; exit 1'; do
  i=$((i + 1)); M=$(mktemp -d); mkpath "$M" mktemp; printf '#!/bin/sh\n%s\n' "$mk" >"$M/mktemp"; chmod +x "$M/mktemp"
  out=$(cd "$XC" && PATH="$M" "$SUT" 2>&1); rc=$?
  echo "$out" | grep -q "^MISSING mktemp:" && [ "$rc" -eq 4 ] || { echo "FAIL r6b broken mktemp [$i]: rc=$rc: $(echo "$out" | head -3)"; failx; }
  echo "$out" | grep -q "^BLIND: missing/unusable:.* mktemp" || { echo "FAIL r6b broken mktemp [$i]: BLIND line does not name mktemp"; failx; }
  echo "$out" | grep -q "MKTEMP-NOISE" && { echo "FAIL r6b broken mktemp [$i]: mktemp stderr leaked"; failx; }
  echo "$out" | grep -qi "denied\|/out" && { echo "FAIL r6b broken mktemp [$i]: a probe ran with an unusable scratch dir: $(echo "$out" | grep -i 'denied\|/out' | head -1)"; failx; }
  [ -d "$XC/x" ] || { echo "FAIL r6b broken mktemp [$i]: cleanup removed the relative dir x"; failx; }
  [ -f "$f6" ] || { echo "FAIL r6b broken mktemp [$i]: cleanup removed the existing file mktemp named"; failx; }
  rm -rf "$M"
done
rm -rf "$XC" "$f6"
# Cleanup never removes a relative path: with `timeout` absent (no scratch dir) a dir named x in cwd survives.
XD=$(mktemp -d); mkdir "$XD/x"; XP=$(mktemp -d); mkpath "$XP" timeout
( cd "$XD" && PATH="$XP" "$SUT" >/dev/null 2>&1 )
[ -d "$XD/x" ] || { echo "FAIL r6b: cleanup removed a relative directory 'x' (unset scratch must not be removed)"; failx; }
rm -rf "$XD" "$XP" "$G3" "$G4" "$G5" "$TD6"
# R6b (pid-reuse safety): an inherited or stale target pid must never make cleanup kill an unrelated group.
# (a) env-inherited tpid, no probe runs: the sleeper's group must survive the EXIT cleanup.
if command -v setsid >/dev/null 2>&1; then
  PP=$(mktemp -d); for b in timeout mktemp head rm sh bash; do ln -s "$(command -v $b)" "$PP/$b"; done
  # shellcheck disable=SC2016 # the single-quoted `sh -c` argument is CODE for a NEW sub-shell; $$/$1
  # inside it must stay literal here so they expand in that sub-shell's own environment, not this one.
  setsid sh -c 'echo $$ >"$1/sp.pid"; exec sleep 40' _ "$PP" >/dev/null 2>&1 </dev/null &
  # Disown this background job right away: this test kills the sleeper's whole process group
  # (below, via $sp) itself, and bash still announces a job's signal-death to THIS script's own
  # stderr on some LATER line once that happens ("... Killed  setsid sh -c ...") even when the
  # job is later explicitly `wait`-ed on by the same pid -- disowning removes the job from
  # bash's table so no such announcement is ever queued. Purely output-hygiene: it does not
  # change what gets killed or when.
  disown "$!" 2>/dev/null || true
  i=0; while [ ! -s "$PP/sp.pid" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  sp=$(cat "$PP/sp.pid" 2>/dev/null)
  if [ -n "$sp" ]; then
    tpid=$sp PATH="$PP" timeout 60 /bin/bash "$SUT" >/dev/null 2>&1
    kill -0 "$sp" 2>/dev/null || { echo "FAIL r6b inherited tpid: cleanup killed an unrelated process group"; failx; }
    case $sp in *[!0-9]*) ;; *) [ "$sp" -gt 1 ] && kill -s KILL -- "-$sp" 2>/dev/null ;; esac   # 11.4.263: integer > 1 only
  else echo "FAIL r6b inherited tpid: sleeper never started"; failx; fi
  rm -rf "$PP"
else echo "SKIP r6b inherited tpid: setsid_unavailable"; fi
# (b) pid reuse in a pid namespace: the reused pid's group must survive the EXIT cleanup.
if unshare -Urpf --mount-proc sh -c : >/dev/null 2>&1 && command -v strace >/dev/null 2>&1; then
  ok=0; res=""
  # shellcheck disable=SC2034
  for try in 1 2 3; do
    res=$(timeout -k 2 60 unshare -Urpf --mount-proc sh "$HERE/fixtures/triple_harness/nsdrv_c.sh" "$HERE" 2>/dev/null)
    [ "$res" = NOREUSE ] || { ok=1; break; }
  done
  if [ "$ok" -eq 0 ]; then echo "FAIL r6b pid reuse: reuse window never reached in 3 tries"; failx
  elif [ "$res" != REUSED-ALIVE ]; then echo "FAIL r6b pid reuse: cleanup killed an unrelated group that reused the stale pid ($res)"; failx; fi
else echo "SKIP r6b pid reuse: userns_unavailable (unshare -Urpf --mount-proc or strace cannot run)"; fi
# R6-F1 / R6-F2 / R7 signal windows (plain, inherit, postwait, shim, shimord: see fixtures/triple_harness/sigwin_rig.sh):
# a TERM must exit 2, kill the probe's whole group in every window and spare an inherited stale tpid's group.
res=$(bash "$HERE/fixtures/triple_harness/sigwin_check.sh" deps "$HERE")
[ -z "$res" ] || printf '%s\n' "$res"
printf '%s\n' "$res" | grep -q '^FAIL' && failx
# R7b: reap_jobs pid source shimmed (see fixtures/triple_harness/jobs_shim_check.sh): no pgid <= 1 ever reaches kill,
# dash-like `jobs -r` rejection falls back to `jobs -p`, the pid-namespace canary (stale done job) survives, silent stderr.
res=$(bash "$HERE/fixtures/triple_harness/jobs_shim_check.sh" deps "$HERE")
[ -z "$res" ] || printf '%s\n' "$res"
printf '%s\n' "$res" | grep -q '^FAIL' && failx
# R6-F5 (usable = rc 0 AND any non-whitespace output; first NON-blank line shown; locale independent)
res=$(bash "$HERE/fixtures/triple_harness/f5_check.sh" "$SUT")
[ -z "$res" ] || printf '%s\n' "$res"
printf '%s\n' "$res" | grep -q '^FAIL' && failx
# Case 2: full PATH: rc 0 iff all present, else 4; every tool line printed either way
out2=$("$SUT" 2>&1); rc2=$?
for t in $TOOLS; do echo "$out2" | grep -q "$t" || { echo "FAIL case2: $t not reported"; failx; }; done
case $rc2 in 0|4) ;; *) echo "FAIL case2: rc=$rc2"; failx;; esac
if [ "$rc2" -eq 0 ] && echo "$out2" | grep -q MISSING; then echo "FAIL case2: rc0 with MISSING"; failx; fi
[ $fail -eq 0 ] && echo "PASS test_check_deps" || exit 1
