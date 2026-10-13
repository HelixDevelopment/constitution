#!/bin/sh
# Purpose: run every test_*.sh in a directory; fail if none match (empty-glob false-null guard, §11.4.201(6)).
# Usage: run_all.sh [tests_dir]   (default: directory of this script)
# Exit: 0 all pass; 1 any failure or zero tests found; 2 usage, or a HUP/INT/TERM received while running.
# Signals (R7-F2): `timeout` leads its own process group, so a signal to the runner (or Ctrl-C to its group)
# never reached the running test. A HUP/INT/TERM now sends TERM to the running test's `timeout` (which forwards
# it to the test's whole group and sends KILL 2 s later), waits up to 3 s, then KILLs the group and exits 2.
# It works even when the signal lands between the fork of the test and the shell recording its pid (the running
# background job is found through `jobs`). No group id <= 1 is ever signalled (constitution 11.4.263).
# Each test runs under the interpreter named by its shebang (bash / sh; default sh) with a
# per-test timeout (FASTCYCLE_TEST_TIMEOUT seconds, default 240, must be integer >=1 else exit 2;
# hang => TERM then KILL after 2 s => TIMEOUT + failure).
# Per-test override: a test file may carry ONE header line `# fastcycle-timeout-s: N` in its first
# 10 lines (exactly that text: '# ', no other spacing, N a positive integer of at most 6 digits,
# no trailing characters). It replaces the default bound for THAT test only. A line in the first
# 10 lines that starts '#', optional spaces, then fastcycle-timeout-s but does not match exactly,
# or a second such line, is malformed: run_all names the file and exits 2 BEFORE running any test
# (a bound that silently fails to apply would read as a load-dependent false failure). A header
# after line 10 is ignored. The header is the place to record a MEASURED need (see the file).
# Recursion guard: FASTCYCLE_RUN_ALL_DEPTH caps nesting (test_run_all.sh invokes this with temp dirs).
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-$here}
[ -d "$dir" ] || { echo "run_all: not a directory: $dir" >&2; exit 2; }
depth=${FASTCYCLE_RUN_ALL_DEPTH:-0}
[ "$depth" -ge 2 ] && { echo "run_all: recursion depth exceeded" >&2; exit 2; }
FASTCYCLE_RUN_ALL_DEPTH=$((depth + 1)); export FASTCYCLE_RUN_ALL_DEPTH
# Default per-test bound: operator-tunable, no measured basis (engineering guess, not data).
TEST_TIMEOUT_S=${FASTCYCLE_TEST_TIMEOUT-240}
# Must be a positive decimal integer of <=6 digits: GNU `timeout 0` DISABLES the bound (R3-F6).
case $TEST_TIMEOUT_S in ''|*[!0-9]*|???????*) echo "run_all: FASTCYCLE_TEST_TIMEOUT must be a positive integer of at most 6 digits: '$TEST_TIMEOUT_S'" >&2; exit 2 ;; esac
[ "$TEST_TIMEOUT_S" -ge 1 ] || { echo "run_all: FASTCYCLE_TEST_TIMEOUT must be a positive integer of at most 6 digits (>= 1)" >&2; exit 2; }
# SIGKILL grace after the TERM at the bound, so a TERM-ignoring test cannot overrun (engineering constant).
KILL_AFTER_S=2
# test_bound <file>: prints "" (no header), or the header value; returns 1 if malformed.
test_bound() {
  awk 'NR > 10 { exit }
    /^#[[:space:]]*fastcycle-timeout-s/ { c++
      if ($0 ~ /^# fastcycle-timeout-s: [0-9]+$/) { v = $0; sub(/^# fastcycle-timeout-s: /, "", v); if (length(v) > 6 || v + 0 < 1) bad = 1; else val = v } else bad = 1 }
    END { if (c > 1) bad = 1; if (bad) exit 3; if (c == 1) print val }' "$1"
  case $? in 0) return 0 ;; *) return 1 ;; esac
}
for t in "$dir"/test_*.sh; do
  [ -f "$t" ] || continue
  test_bound "$t" >/dev/null || { echo "run_all: malformed fastcycle-timeout-s header in $(basename "$t") (want exactly '# fastcycle-timeout-s: N', N positive, at most 6 digits, once, in the first 10 lines)" >&2; exit 2; }
done
work=$(mktemp -d) || { echo "run_all: cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
# job_pids: pids of the still-RUNNING background jobs, one per line, into $work/jobs (`jobs -rp`, falling back to
# `jobs -p` for a shell without -r). zsh prints whole job lines `[1]  + 237188 running cmd`: the pid of a
# `[N] [+-] PID ...` line is taken; any other non-numeric line is skipped.
job_pids() {
  # shellcheck disable=SC3045 # -r is not POSIX; the fallback form covers shells without it
  { jobs -rp || jobs -p; } >"$work/jobs.raw" 2>/dev/null
  : >"$work/jobs"
  while read -r j; do
    case $j in ''|*[!0-9]*) j=$(printf '%s\n' "$j" | sed -n 's/^\[[0-9][0-9]*\][ +-]*\([0-9][0-9]*\) .*$/\1/p') ;; esac
    case $j in ''|*[!0-9]*) continue ;; esac
    [ "$j" -gt 1 ] && printf '%s\n' "$j" >>"$work/jobs"
  done <"$work/jobs.raw"
}
on_signal() {
  job_pids
  while read -r j; do kill -s TERM "$j" 2>/dev/null; done <"$work/jobs"
  # bounded grace (3 s: `timeout -k` already sends KILL 2 s after the forwarded TERM): a `timeout` that ignores
  # TERM must not make the runner wait for the whole test bound.
  i=0
  while [ "$i" -lt 30 ]; do
    alive=0
    while read -r j; do kill -0 "$j" 2>/dev/null && alive=1; done <"$work/jobs"
    [ "$alive" -eq 1 ] || break
    sleep 0.1; i=$((i + 1))
  done
  while read -r j; do kill -s KILL -- "-$j" 2>/dev/null; kill -s KILL "$j" 2>/dev/null; done <"$work/jobs"
  wait
  exit 2
}
trap on_signal HUP INT TERM
count=0; failed=0
for t in "$dir"/test_*.sh; do
  [ -f "$t" ] || continue
  count=$((count + 1))
  case $(head -n 1 "$t") in *bash*) interp="bash" ;; *) interp="sh" ;; esac
  bound=$(test_bound "$t"); bound=${bound:-$TEST_TIMEOUT_S}
  # background + wait: a shell only runs a trap after its FOREGROUND child ends, so a foreground test would
  # defer every signal for its whole bound; stdin is /dev/null explicitly (a job under `sh -m` would stop on tty reads).
  timeout -k "$KILL_AFTER_S" "$bound" "$interp" "$t" </dev/null &
  wait "$!"; trc=$?
  if [ "$trc" -eq 124 ] || [ "$trc" -eq 137 ]; then echo "TIMEOUT $(basename "$t")"; fi
  if [ "$trc" -eq 0 ]; then echo "PASS $(basename "$t")"; else echo "FAIL $(basename "$t")"; failed=$((failed + 1)); fi
done
if [ "$count" -eq 0 ]; then echo "run_all: zero tests matched in $dir (refusing to pass vacuously)" >&2; exit 1; fi
echo "run_all: $count run, $failed failed"
[ "$failed" -eq 0 ]
