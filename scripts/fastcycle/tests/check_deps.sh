#!/bin/bash
# check_deps.sh — probe required tools by REAL invocation (§11.4.201(11)), not command -v alone.
# Usable = `--version` exits 0 AND prints output (any non-whitespace character anywhere in the captured
# stdout+stderr; leading blank lines are fine, whitespace-only output counts as empty); `timeout` is probed too.
# Exit: 0 all usable; 4 (BLIND) if any missing/unusable, naming each (common-conventions C-001).
# Probe bounds: operator-tunable defaults, NO measured basis (engineering guesses, not data).
# Each probe's stdout+stderr go to a temp FILE (never a pipe a descendant could hold open) and,
# once the probe returns, KILL is sent to its whole process group (timeout(1) leads its own
# group), so a background descendant can neither delay the verdict nor outlive the call.
# A descendant that escapes the group (its own setsid) is out of scope and not reaped.
# A signal (HUP/INT/TERM) exits 2 and reaps the probe even when it lands between the fork of the
# probe and the shell recording its pid: the still-running background job is found through the
# shell's own job table (`jobs`; bare-pid lines and zsh's whole-line `[N] [+-] PID ...` lines are both
# understood), so no window leaves the probe group alive.
# FC_PROBE_TIMEOUT_S bounds each `<tool> --version`; 5 s bounds the `timeout` self-probe.
PROBE_TIMEOUT_S=${FC_PROBE_TIMEOUT_S-30}
SELF_PROBE_TIMEOUT_S=5
KILL_AFTER_S=2   # SIGKILL grace after TERM so a TERM-ignoring tool cannot overrun
# Positive decimal integer of <=6 digits: GNU `timeout 0` DISABLES the bound (R3-F6) => exit 2.
case $PROBE_TIMEOUT_S in ''|*[!0-9]*|???????*) echo "check_deps: FC_PROBE_TIMEOUT_S must be a positive integer of at most 6 digits: '$PROBE_TIMEOUT_S'" >&2; exit 2 ;; esac
[ "$PROBE_TIMEOUT_S" -ge 1 ] || { echo "check_deps: FC_PROBE_TIMEOUT_S must be a positive integer of at most 6 digits (>= 1)" >&2; exit 2; }
TOOLS="git sqlite3 strace pandoc weasyprint shellcheck python3 mmdc"
missing=""
# `timeout` bounds every probe, so it is itself a probed dependency (its absence must be named, not swallowed).
have_timeout=0
if command -v timeout >/dev/null 2>&1 && timeout -k "$KILL_AFTER_S" "$SELF_PROBE_TIMEOUT_S" sh -c : >/dev/null 2>&1; then have_timeout=1
else
  echo "MISSING timeout: cannot run 'timeout ${SELF_PROBE_TIMEOUT_S} sh -c :' (absent or unusable)"
  missing="$missing timeout"
fi
scratch=""; tpid=""
kill_group() {
  case $tpid in
    ''|*[!0-9]*) ;;
    *) if [ "$tpid" -gt 1 ]; then kill -s KILL -- "-$tpid" 2>/dev/null; fi ;;
  esac
  tpid=""
}
# Kill every still-running background job of this shell (pid, then its process group): covers the
# fork -> `tpid=$!` window where tpid is not recorded yet. `jobs -rp` lists RUNNING jobs only, so a
# reaped child's reusable pid is never signalled. Second form is a fallback for a shell without -r.
# shellcheck disable=SC2329 # invoked from cleanup()'s body below (the bare `reap_jobs` call); cleanup
# itself is wired via `trap cleanup EXIT` (a bareword trap action), which shellcheck's static
# call-graph does not credit as invoking cleanup once the script ends in an unconditional `exit`
# (reproduced in isolation: adding a trailing `exit 0` to a minimal two-function/trap-EXIT script is
# what makes shellcheck 0.11 flag both functions as unused -- a verified false positive, not a bug).
reap_jobs() {
  [ -n "$scratch" ] || return 0
  { jobs -rp || jobs -p; } >"$scratch/jobs" 2>/dev/null
  while read -r j; do
    # zsh (also as `sh`) prints whole job lines `[1]  + 237188 running  cmd`, not bare pids: take the pid
    # of a `[N] [+-] PID ...` line ONLY; any other non-numeric line is skipped (R7-F1).
    case $j in ''|*[!0-9]*) j=$(printf '%s\n' "$j" | sed -n 's/^\[[0-9][0-9]*\][ +-]*\([0-9][0-9]*\) .*$/\1/p') ;; esac
    case $j in ''|*[!0-9]*) continue ;; esac
    if [ "$j" -gt 1 ]; then kill -s KILL "$j" 2>/dev/null; kill -s KILL -- "-$j" 2>/dev/null; fi
  done <"$scratch/jobs"
}
# shellcheck disable=SC2329 # invoked via `trap cleanup EXIT` below; shellcheck's static call-graph
# does not credit a bareword `trap NAME SIGNAL` action as invoking NAME here (verified false positive,
# see the reap_jobs() note above for the reproduction).
cleanup() {
  kill_group
  reap_jobs
  if [ -n "$scratch" ]; then rm -rf "$scratch"; fi
}
trap cleanup EXIT
# A signal exits 2; the EXIT trap (cleanup) then kills the probe group and removes the scratch dir.
trap 'exit 2' HUP INT TERM
if [ "$have_timeout" -eq 1 ]; then
  if scratch=$(mktemp -d 2>/dev/null) && [ -d "$scratch" ]; then :; else
    scratch=""; have_timeout=0
    echo "MISSING mktemp: cannot create a scratch directory for probe output (absent or unusable)"
    missing="$missing mktemp"
  fi
fi
for t in $TOOLS; do
  out=""; rc=1
  if [ "$have_timeout" -eq 1 ] && command -v "$t" >/dev/null 2>&1; then
    timeout -k "$KILL_AFTER_S" "$PROBE_TIMEOUT_S" "$t" --version >"$scratch/out" 2>&1 </dev/null &
    tpid=$!
    wait "$tpid"; rc=$?
    kill_group
    out=$(LC_ALL=C sed -n '/[^[:space:]]/{p;q;}' "$scratch/out")
  fi
  # usable = exit status 0 AND non-empty output (a loader error exiting 127 is NOT usable)
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    echo "FOUND $t: $out"
  else
    echo "MISSING $t: --version rc=$rc, output '${out}' (absent or unusable)"
    missing="$missing $t"
  fi
done
if [ -n "$missing" ]; then
  echo "BLIND: missing/unusable:$missing" >&2
  exit 4
fi
exit 0
