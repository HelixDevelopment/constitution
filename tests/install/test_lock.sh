#!/usr/bin/env bash
# test_lock.sh — the installer's run lock (hi_lock) under real concurrency.
#   * N=8 concurrent contenders, 20 rounds, no lock present: exactly ONE takes the lock per round.
#   * N=8 concurrent contenders, 20 rounds, a STALE lock (dead pid) present: exactly ONE reclaims it per round
#     (the old check-then-rm-then-create let two contenders both remove the stale lock and both proceed).
#   * a FIFO, or a symlink to a FIFO, planted at the lock path is never opened (no hang) and is refused.
#   * paired mutants: the same harness against a copy whose lock create is NOT exclusive, and against a copy
#     whose stale reclaim is not serialised, must observe a double acquire (proves the harness can see one).
# Contenders are separate bash processes that source the installer in library mode and call hi_lock; each
# holder keeps the lock for 1 s so every other contender of the round tries while it is held.
# Usage: bash tests/install/test_lock.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=lock
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
N=8; ROUNDS=20
P="$SB/proj"; new_project "$P" || exit 2
LOCK="$P/.git/helix-constitution-install.lock"

# Each contender is its own bash PROCESS (not a subshell: a subshell shares $$ with this test, so every
# contender would read the others' pid as its own and the harness would measure nothing real).
CONTENDER='HELIX_INSTALLER_LIB_MODE=1; . "$1" || exit 9; set +e; hi_init_state; O_ROOT="$2"
while [ ! -e "$3" ]; do sleep 0.01; done
if hi_lock 2>/dev/null; then printf "GOT\n" >>"$4"; sleep 1; hi_unlock; else printf "NO\n" >>"$4"; fi'
contend() { bash -c "$CONTENDER" contender "$1" "$P" "$2" "$3"; }   # installer go-file out-file
# The updater's contender is the same shape, written to a file (sourced in updater library mode; up_lock/up_unlock).
UC="$SB/updater_contender.sh"
cat >"$UC" <<'EOF'
HELIX_UPDATER_LIB_MODE=1; . "$1" || exit 9; set +e; hi_gx_bin || exit 9; UP_ROOT="$2"
while [ ! -e "$3" ]; do sleep 0.01; done
if up_lock 2>/dev/null; then printf "GOT\n" >>"$4"; sleep 1; up_unlock; else printf "NO\n" >>"$4"; fi
EOF
ucontend() { bash "$UC" "$1" "$P" "$2" "$3"; }   # updater go-file out-file
round() { # script stale(0|1) [upd] → prints the number of contenders that took the lock
  local inst="$1" stale="$2" kind="${3:-inst}" go="$SB/go.$RANDOM$RANDOM" out="$SB/out.$RANDOM$RANDOM" dead k
  if [ "$stale" = 1 ]; then
    sleep 0 & dead=$!; wait "$dead" 2>/dev/null
    printf '%s\n' "$dead" >"$LOCK"; fi
  : >"$out"
  for ((k=0; k<N; k++)); do
    if [ "$kind" = upd ]; then ucontend "$inst" "$go" "$out" & else contend "$inst" "$go" "$out" & fi
  done
  sleep 0.5; : >"$go"; wait
  grep -c '^GOT$' "$out"
  rm -f -- "$go" "$out" "$LOCK" "$LOCK.reclaim" "$P/.git/helix-constitution-install.lock."*
}
series() { # script stale [upd] → "rounds-with-exactly-one rounds-with-more-than-one"
  local one=0 many=0 r g
  for ((r=0; r<ROUNDS; r++)); do
    g="$(round "$1" "$2" "${3:-inst}")"
    [ "$g" = 1 ] && one=$((one+1)); [ "$g" -gt 1 ] && many=$((many+1))
  done
  printf '%s %s\n' "$one" "$many"
}

echo "# $N concurrent contenders, $ROUNDS rounds, no lock present"
read -r one many <<<"$(series "$INSTALLER" 0)"
eq "fresh lock: exactly one contender proceeded in every round" "$ROUNDS 0" "$one $many"

echo "# $N concurrent contenders, $ROUNDS rounds, a stale lock (dead pid) present"
read -r one many <<<"$(series "$INSTALLER" 1)"
eq "stale lock: exactly one contender reclaimed it in every round" "$ROUNDS 0" "$one $many"

echo "# a FIFO / symlink planted at the lock path is never opened"
for kind in fifo symlink-to-fifo; do
  rm -f -- "$LOCK" "$SB/victim.fifo"; mkfifo "$SB/victim.fifo"
  if [ "$kind" = fifo ]; then rm -f -- "$SB/victim.fifo"; mkfifo "$LOCK"; else ln -s "$SB/victim.fifo" "$LOCK"; fi
  bash -c 'HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"; hi_lock; echo "rc=$?"' one "$INSTALLER" "$P" >"$SB/fo" 2>&1 &
  pid=$!; for ((t=0; t<100; t++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; o="$(cat "$SB/fo")"
  check "$kind at the lock path: hi_lock returned (no hang on open)" grep -q '^rc=' <<<"$o"
  check "$kind at the lock path: refused (rc=3)" grep -q '^rc=3$' <<<"$o"
  check "$kind at the lock path: left in place (not deleted)" eval '[ -p "$LOCK" ] || [ -L "$LOCK" ]'
  rm -f -- "$LOCK" "$SB/victim.fifo"
done

echo "# the lock cannot be created at all (no ln on PATH): refused with the TRUE reason, never 'not a regular file'"
NOLN="$SB/noln"; mkdir -p "$NOLN"
for t in bash git mktemp printf rm head tr timeout kill cat sed awk grep id dirname date; do
  p="$(command -v "$t" 2>/dev/null)"; case "$p" in /*) ln -s "$p" "$NOLN/$t" ;; esac; done
for w in installer updater; do
  if [ "$w" = installer ]; then
    o="$(PATH="$NOLN" bash -c 'HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"; hi_lock; echo "rc=$?"' one "$INSTALLER" "$P" 2>&1)"
  else
    o="$(PATH="$NOLN" bash -c 'HELIX_UPDATER_LIB_MODE=1; . "$1"; set +e; hi_gx_bin; UP_ROOT="$2"; up_lock; echo "rc=$?"' one "$UPDATER" "$P" 2>&1)"
  fi
  check "$w, no ln: refused (rc=3)" grep -q '^rc=3$' <<<"$o"
  check "$w, no ln: says the lock could not be created" grep -q 'cannot create the lock' <<<"$o"
  check "$w, no ln: does NOT claim a non-regular file is there" eval '! grep -q "not a regular file" <<<"$o"'
  check "$w, no ln: nothing left at the lock path" eval '[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ] && [ -z "$(ls -A "$P/.git" | grep -F helix-constitution-install.lock)" ]'
done

echo "# a normal lock/unlock cycle leaves nothing behind (control needle)"
o="$(bash -c 'HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"
       hi_lock; echo "rc=$?"; [ -f "$3" ] && echo held; hi_unlock' one "$INSTALLER" "$P" "$LOCK" 2>&1)"
check "control: hi_lock succeeds when no lock exists" grep -q '^rc=0$' <<<"$o"
check "control: the lock file exists while held" grep -q '^held$' <<<"$o"
check "control: unlock removed the lock" eval '[ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]'
check "control: no temp/reclaim files left" eval '[ -z "$(ls -A "$P/.git" | grep -F helix-constitution-install.lock)" ]'

echo "# paired mutants: the harness must SEE a double acquire"
M1="$SB/mut_nonexclusive.sh"; M2="$SB/mut_noreclaimlock.sh"
python3 -I - "$INSTALLER" "$M1" "$M2" <<'PY'
import sys
src = open(sys.argv[1]).read()
a = 'ln -- "$tmp" "$lockp" 2>/dev/null'
b = 'ln -- "$tmp" "$lockp.reclaim" 2>/dev/null'
if src.count(a) >= 1 and src.count(b) == 1:
    open(sys.argv[2], "w").write(src.replace(a, 'cp -- "$tmp" "$lockp" 2>/dev/null'))
    open(sys.argv[3], "w").write(src.replace(b, 'true'))
PY
check "the two mutants could be built (the lock uses ln for the lock and for the reclaim marker)" eval '[ -s "$M1" ] && [ -s "$M2" ]'
one=0; many=0; [ -s "$M1" ] && read -r one many <<<"$(series "$M1" 0)"
check "mutant (non-exclusive create): a double acquire is observed ($many of $ROUNDS rounds)" eval '[ "$many" -ge 1 ]'
one=0; many=0; [ -s "$M2" ] && read -r one many <<<"$(series "$M2" 1)"
check "mutant (unserialised stale reclaim): a double acquire is observed ($many of $ROUNDS rounds)" eval '[ "$many" -ge 1 ]'

echo "# the updater's lock (up_lock): same primitive, same lock file as the installer"
read -r one many <<<"$(series "$UPDATER" 0 upd)"
eq "updater, fresh lock: exactly one contender proceeded in every round" "$ROUNDS 0" "$one $many"
read -r one many <<<"$(series "$UPDATER" 1 upd)"
eq "updater, stale lock: exactly one contender reclaimed it in every round" "$ROUNDS 0" "$one $many"

echo "# installer and updater exclude each other (4 installer + 4 updater contenders per round)"
mixed_round() {
  local go="$SB/go.$RANDOM$RANDOM" out="$SB/out.$RANDOM$RANDOM" k
  : >"$out"
  for ((k=0; k<4; k++)); do contend "$INSTALLER" "$go" "$out" & ucontend "$UPDATER" "$go" "$out" & done
  sleep 0.5; : >"$go"; wait; grep -c '^GOT$' "$out"
  rm -f -- "$go" "$out" "$LOCK" "$LOCK.reclaim" "$P/.git/helix-constitution-install.lock."*
}
one=0; many=0
for ((r=0; r<ROUNDS; r++)); do g="$(mixed_round)"; [ "$g" = 1 ] && one=$((one+1)); [ "$g" -gt 1 ] && many=$((many+1)); done
eq "mixed installer+updater: exactly one proceeded in every round" "$ROUNDS 0" "$one $many"

echo "# updater: a FIFO / symlink planted at the lock path is never opened"
UF="$SB/updater_fifo.sh"
cat >"$UF" <<'EOF'
HELIX_UPDATER_LIB_MODE=1; . "$1"; set +e; hi_gx_bin; UP_ROOT="$2"; up_lock; echo "rc=$?"
EOF
for kind in fifo symlink-to-fifo; do
  rm -f -- "$LOCK" "$SB/victim.fifo"; mkfifo "$SB/victim.fifo"
  if [ "$kind" = fifo ]; then rm -f -- "$SB/victim.fifo"; mkfifo "$LOCK"; else ln -s "$SB/victim.fifo" "$LOCK"; fi
  bash "$UF" "$UPDATER" "$P" >"$SB/fo" 2>&1 &
  pid=$!; for ((t=0; t<100; t++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; o="$(cat "$SB/fo")"
  check "updater, $kind at the lock path: refused without hanging (rc=3)" grep -q '^rc=3$' <<<"$o"
  check "updater, $kind at the lock path: left in place" eval '[ -p "$LOCK" ] || [ -L "$LOCK" ]'
  rm -f -- "$LOCK" "$SB/victim.fifo"
done

echo "# updater paired mutant: non-exclusive create must show a double acquire"
M3="$SB/mut_upd_nonexclusive.sh"
python3 -I - "$UPDATER" "$M3" <<'PY'
import sys
src = open(sys.argv[1]).read(); a = 'ln -- "$tmp" "$lockp" 2>/dev/null'
if src.count(a) >= 1: open(sys.argv[2], "w").write(src.replace(a, 'cp -- "$tmp" "$lockp" 2>/dev/null'))
PY
check "updater mutant could be built (up_lock uses ln)" eval '[ -s "$M3" ]'
one=0; many=0; [ -s "$M3" ] && read -r one many <<<"$(series "$M3" 0 upd)"
check "updater mutant (non-exclusive create): a double acquire is observed ($many of $ROUNDS rounds)" eval '[ "$many" -ge 1 ]'

LIBI='HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"; hi_lock; echo "rc=$?"'
LIBU='HELIX_UPDATER_LIB_MODE=1; . "$1"; set +e; hi_gx_bin; UP_ROOT="$2"; up_lock; echo "rc=$?"'
clean_lock() { rm -f -- "$LOCK" "$LOCK.reclaim" "$SB/resume" "$P/.git/helix-constitution-install.lock."*; }
# run A judges the lock stale and pauses (TEST seam) BEFORE it takes the reclaim marker; meanwhile another run
# reclaims and now holds the lock (a live pid); A resumes. → $SB/ra (A's output), $live (the live holder)
reclaim_race() { # script body
  local a t dead
  clean_lock
  sleep 0 & dead=$!; wait "$dead" 2>/dev/null; printf '%s\n' "$dead" >"$LOCK"
  sleep 300 & live=$!
  HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_PAUSE=reclaim HELIX_INSTALLER_TEST_RESUME="$SB/resume" \
    bash -c "$2" a "$1" "$P" >"$SB/ra" 2>&1 &
  a=$!
  for ((t=0; t<400; t++)); do grep -q 'TEST PAUSE reclaim' "$SB/ra" && break; sleep 0.05; done
  rm -f -- "$LOCK"; printf '%s\n' "$live" >"$LOCK"
  : >"$SB/resume"; wait "$a"
}
echo "# reclaim race (I-4): the stale lock was replaced by a live run while A was between its check and the marker"
for kind in inst upd; do
  if [ "$kind" = inst ]; then S="$INSTALLER"; B="$LIBI"; else S="$UPDATER"; B="$LIBU"; fi
  reclaim_race "$S" "$B"
  check "$kind: control: run A paused after it judged the lock stale" grep -q 'TEST PAUSE reclaim' "$SB/ra"
  check "$kind: run A refused (rc=3)" grep -q '^rc=3$' "$SB/ra"
  check "$kind: run A reports that another run took the lock" grep -q 'took' "$SB/ra"
  eq "$kind: the live run's lock is untouched" "$live" "$(tr -cd 0-9 <"$LOCK")"
  check "$kind: no reclaim marker left" eval '[ ! -e "$LOCK.reclaim" ]'
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null; clean_lock
done
echo "# paired mutant: without the re-check under the marker, A takes the live run's lock (the harness sees it)"
M4="$SB/mut_norecheck.sh"
python3 -I - "$INSTALLER" "$M4" <<'PY2'
import sys
src = open(sys.argv[1]).read(); a = 'if [ "$pid2" != "$pid" ] || [ -L "$lockp" ]; then'
if src.count(a) == 1: open(sys.argv[2], "w").write(src.replace(a, 'if false; then'))
PY2
check "re-check mutant could be built" eval '[ -s "$M4" ]'
if [ -s "$M4" ]; then
  reclaim_race "$M4" "$LIBI"
  check "mutant (no re-check): A took the lock (rc=0)" grep -q '^rc=0$' "$SB/ra"
  check "mutant (no re-check): the live run's lock was replaced" eval '[ "$(tr -cd 0-9 <"$LOCK")" != "$live" ]'
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null; clean_lock
fi
echo "# a test switch outside test mode does nothing: no pause without HELIX_INSTALLER_TEST=1"
clean_lock; sleep 0 & dead=$!; wait "$dead" 2>/dev/null; printf '%s\n' "$dead" >"$LOCK"
o="$(HELIX_INSTALLER_TEST_PAUSE=reclaim HELIX_INSTALLER_TEST_RESUME="$SB/never" timeout 20 bash -c "$LIBI" a "$INSTALLER" "$P" 2>&1)"
check "no TEST PAUSE without HELIX_INSTALLER_TEST=1" eval '! grep -q "TEST PAUSE" <<<"$o"'
check "the stale lock was reclaimed at once (rc=0)" grep -q '^rc=0$' <<<"$o"
clean_lock

echo "# liveness (M-6): 'Operation not permitted' is alive; a pid that started after the lock was written is gone"
for kind in inst upd; do
  if [ "$kind" = inst ]; then S="$INSTALLER"; B="$LIBI"; else S="$UPDATER"; B="$LIBU"; fi
  clean_lock; printf '1\n' >"$LOCK"
  o="$(bash -c "$B" a "$S" "$P" 2>&1)"
  check "$kind: a lock naming pid 1 is not reclaimed (rc=3)" grep -q '^rc=3$' <<<"$o"
  eq "$kind: the pid-1 lock is left as it was" "1" "$(tr -cd 0-9 <"$LOCK")"
  clean_lock; sleep 300 & young=$!; printf '%s\n' "$young" >"$LOCK"
  o="$(bash -c "$B" a "$S" "$P" 2>&1)"
  check "$kind: control: a live pid that predates the lock holds it (rc=3)" grep -q '^rc=3$' <<<"$o"
  touch -d '-1 hour' "$LOCK"
  o="$(bash -c "$B" a "$S" "$P" 2>&1)"
  check "$kind: the same live pid, lock written an hour before it started: reclaimed (rc=0)" grep -q '^rc=0$' <<<"$o"
  check "$kind: the reclaim says the old lock was stale" grep -q 'stale' <<<"$o"
  kill "$young" 2>/dev/null; wait "$young" 2>/dev/null; clean_lock
done


echo "# F2: a signal during hi_lock / up_lock never deletes a LIVE holder's lock and leaves no temp or marker file"
SIGI='HELIX_INSTALLER_LIB_MODE=1; . "$1"; set +e; hi_init_state; O_ROOT="$2"; trap "hi_on_signal TERM" TERM; hi_lock; echo "rc=$?"'
SIGU='HELIX_UPDATER_LIB_MODE=1; . "$1"; set +e; hi_gx_bin; UP_ROOT="$2"; trap up_unlock EXIT; trap "exit 143" TERM; up_lock; echo "rc=$?"'
leftovers() { ls -A "$P/.git" | grep -F 'helix-constitution-install.lock.' | wc -l; }
sig_case() { # script body pausepoint live|stale → $SB/rs, $holder, $sig_rc; TERM is sent while the contender is paused
  local b t
  clean_lock
  if [ "$4" = live ]; then sleep 300 & holder=$!; else sleep 0 & holder=$!; wait "$holder" 2>/dev/null; fi
  printf '%s\n' "$holder" >"$LOCK"
  HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_PAUSE="$3" HELIX_INSTALLER_TEST_RESUME="$SB/resume" \
    bash -c "$2" b "$1" "$P" >"$SB/rs" 2>&1 &
  b=$!
  for ((t=0; t<400; t++)); do grep -q "TEST PAUSE $3" "$SB/rs" && break; sleep 0.05; done
  kill -TERM "$b" 2>/dev/null; wait "$b" 2>/dev/null; sig_rc=$?
  : >"$SB/resume"
}
for kind in inst upd; do
  if [ "$kind" = inst ]; then S="$INSTALLER"; B="$SIGI"; pp=lock_read; else S="$UPDATER"; B="$SIGU"; pp=up_lock_read; fi
  sig_case "$S" "$B" "$pp" live
  check "$kind: control: the contender paused after reading the live holder's lock" grep -q 'TEST PAUSE' "$SB/rs"
  eq "$kind: TERM while another run holds the lock: exit 143" 143 "$sig_rc"
  eq "$kind: the live holder's lock is untouched" "$holder" "$(tr -cd 0-9 <"$LOCK" 2>/dev/null)"
  eq "$kind: no temp or marker file left" 0 "$(leftovers)"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; clean_lock
  sig_case "$S" "$B" reclaim stale
  check "$kind: control: the contender paused at the reclaim point" grep -q 'TEST PAUSE reclaim' "$SB/rs"
  eq "$kind: TERM at the reclaim point: exit 143" 143 "$sig_rc"
  eq "$kind: the stale lock is not removed by a run that never took it" "$holder" "$(tr -cd 0-9 <"$LOCK" 2>/dev/null)"
  eq "$kind: no temp or marker file left (stale case)" 0 "$(leftovers)"
  check "$kind: no reclaim marker left" eval '[ ! -e "$LOCK.reclaim" ]'
  clean_lock
done
echo "# F2 paired mutants: with the old shape (lock path set before ownership, unconditional unlock) the live lock IS deleted"
M5="$SB/mut_sig_inst.sh"; M6="$SB/mut_sig_upd.sh"
python3 -I - "$INSTALLER" "$UPDATER" "$M5" "$M6" <<'PY3'
import sys
i = open(sys.argv[1]).read(); u = open(sys.argv[2]).read()
ia = '  lockp="$gd/helix-constitution-install.lock"\n'
ib = '[ -n "$S_LOCK" ] && [ "$(hi_lock_pid "$S_LOCK")" = "$$" ] && rm -f -- "$S_LOCK"'
ua = '  lockp="$gd/helix-constitution-install.lock"; UP_LOCK_FILE="$lockp"\n'
ub = '[ -n "$UP_LOCK" ] && [ "$(up_lock_pid "$UP_LOCK")" = "$$" ] && rm -f -- "$UP_LOCK"'
if i.count(ia) == 1 and i.count(ib) == 1:
    open(sys.argv[3], "w").write(i.replace(ia, ia + '  S_LOCK="$lockp"\n').replace(ib, '[ -n "$S_LOCK" ] && rm -f -- "$S_LOCK"'))
if u.count(ua) == 1 and u.count(ub) == 1:
    open(sys.argv[4], "w").write(u.replace(ua, ua + '  UP_LOCK="$lockp"\n').replace(ub, '[ -n "$UP_LOCK" ] && rm -f -- "$UP_LOCK"'))
PY3
check "signal mutants could be built" eval '[ -s "$M5" ] && [ -s "$M6" ]'
if [ -s "$M5" ]; then sig_case "$M5" "$SIGI" lock_read live
  check "mutant (installer, old shape): the live holder's lock was deleted" eval '[ ! -e "$LOCK" ]'
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; clean_lock; fi
if [ -s "$M6" ]; then sig_case "$M6" "$SIGU" up_lock_read live
  check "mutant (updater, old shape): the live holder's lock was deleted" eval '[ ! -e "$LOCK" ]'
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; clean_lock; fi

echo "# B18: after a successful stale reclaim the .reclaim marker and the temp file are gone"
for kind in inst upd; do
  if [ "$kind" = inst ]; then S="$INSTALLER"; B="$LIBI"; else S="$UPDATER"; B="$LIBU"; fi
  clean_lock; sleep 0 & dead=$!; wait "$dead" 2>/dev/null; printf '%s\n' "$dead" >"$LOCK"
  o="$(bash -c "$B; ls -A \"\$2/.git\" | grep -F helix-constitution-install.lock | sort | tr '\n' ' '" a "$S" "$P" 2>&1)"
  check "$kind: stale reclaim succeeded (rc=0)" grep -q '^rc=0$' <<<"$o"
  check "$kind: only the lock itself exists afterwards (no .reclaim, no temp)" grep -qx 'helix-constitution-install.lock ' <<<"$(tail -n 1 <<<"$o")"
  clean_lock
done
M7="$SB/mut_keep_reclaim.sh"
python3 -I - "$INSTALLER" "$M7" <<'PY4'
import sys
i = open(sys.argv[1]).read()
a = '[ -n "$S_LOCK_RECLAIM" ] && [ "$(hi_lock_pid "$S_LOCK_RECLAIM")" = "$$" ] && rm -f -- "$S_LOCK_RECLAIM"'
if i.count(a) == 1: open(sys.argv[2], "w").write(i.replace(a, 'true'))
PY4
check "keep-reclaim mutant could be built" eval '[ -s "$M7" ]'
if [ -s "$M7" ]; then
  clean_lock; sleep 0 & dead=$!; wait "$dead" 2>/dev/null; printf '%s\n' "$dead" >"$LOCK"
  o="$(bash -c "$LIBI; ls -A \"\$2/.git\" | grep -F helix-constitution-install.lock | sort | tr '\n' ' '" a "$M7" "$P" 2>&1)"
  check "mutant (marker kept): a .reclaim file is observed" grep -q 'reclaim' <<<"$(tail -n 1 <<<"$o")"
  clean_lock
fi

finish
