#!/usr/bin/env bash
# lock_race_probe.sh REPO ITER DELAY → replays test_lock.sh's reclaim_race (verbatim logic) on the no-re-check mutant,
# preceded each time by an updater race (as in the suite, so $SB/ra holds the previous run's "TEST PAUSE reclaim").
# DELAY>0 constructs a slow child (sleep before the redirection) to show the stale-read mechanism deterministically.
R="${1:?}"; ITER="${2:?}"; DELAY="${3:-0}"
T_NAME=lockprobe; . "$R/tests/install/lib.sh"; new_sandbox
P="$SB/proj"; new_project "$P" || exit 2
LOCK="$P/.git/helix-constitution-install.lock"
LIBI='HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"; hi_lock; echo "rc=$?"'
LIBU='HELIX_UPDATER_LIB_MODE=1; . "$1"; set +e; hi_gx_bin; UP_ROOT="$2"; up_lock; echo "rc=$?"'
clean_lock() { rm -f -- "$LOCK" "$LOCK.reclaim" "$SB/resume" "$P/.git/helix-constitution-install.lock."*; }
reclaim_race() { # script body delay
  local a t dead
  clean_lock
  sleep 0 & dead=$!; wait "$dead" 2>/dev/null; printf '%s\n' "$dead" >"$LOCK"
  sleep 300 & live=$!
  [ "${FIX:-0}" = 1 ] && : >"$SB/ra"   # the test_lock.sh fix: emptied in the parent, before A starts
  if [ "$3" = 0 ]; then
    HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_PAUSE=reclaim HELIX_INSTALLER_TEST_RESUME="$SB/resume" \
      bash -c "$2" a "$1" "$P" >"$SB/ra" 2>&1 &
  else
    ( sleep "$3"; HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_PAUSE=reclaim HELIX_INSTALLER_TEST_RESUME="$SB/resume" \
      exec bash -c "$2" a "$1" "$P" >"$SB/ra" 2>&1 ) &
  fi
  a=$!; T0=$SECONDS
  for ((t=0; t<400; t++)); do grep -q 'TEST PAUSE reclaim' "$SB/ra" && break; sleep 0.05; done
  cp -- "$SB/ra" "$SB/ra.at_break" 2>/dev/null || : >"$SB/ra.at_break"; LOOP_T=$t; LOOP_S=$((SECONDS-T0)); DEAD=$dead
  rm -f -- "$LOCK"; printf '%s\n' "$live" >"$LOCK"
  : >"$SB/resume"; wait "$a"
}
M4="$SB/mut_norecheck.sh"
python3 -I - "$INSTALLER" "$M4" <<'PY2'
import sys
src = open(sys.argv[1]).read(); a = 'if [ "$pid2" != "$pid" ] || [ -L "$lockp" ]; then'
if src.count(a) == 1: open(sys.argv[2], "w").write(src.replace(a, 'if false; then'))
PY2
[ -s "$M4" ] || { echo "mutant not built"; exit 2; }
fail=0; stale=0
for ((i=1; i<=ITER; i++)); do
  reclaim_race "$UPDATER" "$LIBU" 0; kill "$live" 2>/dev/null; wait "$live" 2>/dev/null; clean_lock
  reclaim_race "$M4" "$LIBI" "$DELAY"
  # stale read: at the moment the poll loop stopped, ra still held the updater run's text, not run A's
  grep -q 'update-constitution' "$SB/ra.at_break" && stale=$((stale+1))
  if grep -q '^rc=0$' "$SB/ra" && [ "$(tr -cd 0-9 <"$LOCK")" != "$live" ]; then :; else
    fail=$((fail+1)); echo "iter $i FAIL: loop_iters=$LOOP_T loop_secs=$LOOP_S dead=$DEAD live=$live total_secs=$((SECONDS-T0)) A said: $(tr '\n' '|' <"$SB/ra") ; ra at break: $(tr '\n' '|' <"$SB/ra.at_break")"; fi
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null; clean_lock
done
echo "FIX=${FIX:-0} DELAY=$DELAY ITER=$ITER mutant_case_fail=$fail stale_read_then_refused=$stale"
