#!/usr/bin/env bash
# run_mut.sh <snapdir> <mutdir> <outdir> <name>...: run each mutant through the whole suite,
# fail-fast. The round-5 cases come first in the suite, so one fail-fast run reaches the
# first failing case at the same point a separate round-5-only stage would, without
# running the round-5 cases twice for the mutants that survive them.
# A mutant is KILLED when the run exits non-zero AND its log has a FAIL line (the first
# FAIL is recorded, so the kill can be checked against the test meant to catch it); a
# non-zero exit with no FAIL line is recorded as ERROR, never as a kill; exit 0 with a
# RESULT line is SURVIVED.
# Each run is in its own user scope (TasksMax=2000) under nice -n 10, in an empty
# working directory, with a one-hour timeout.
set -euo pipefail
SNAP=${1:?}; MUT=${2:?}; OUT=${3:?}; shift 3
TEST=$SNAP/tests/release/test_land_vehicle.sh
mkdir -p "$OUT"
CWD=$OUT/cwd
mkdir -p "$CWD"
RES=$OUT/results.tsv
[ -s "$RES" ] || printf 'name\tstage\trc\tresult\tfirst_fail\n' > "$RES"
for name in "$@"; do
  [ -x "$MUT/$name/land_vehicle.sh" ] || { printf '%s\t-\t-\tMISSING\t-\n' "$name" >> "$RES"; printf '%s MISSING\n' "$name"; continue; }
  log=$OUT/$name.full.log; rc=0
  ( cd "$CWD" && env -u LANDER_TEST_R5_ONLY LANDER_TEST_FAILFAST=1 timeout 3600 systemd-run --user --scope -q -p TasksMax=2000 \
      nice -n 10 bash "$TEST" "$MUT/$name/land_vehicle.sh" ) > "$log" 2>&1 || rc=$?
  res=$(grep -E '^RESULT ' "$log" | tail -n 1 || true)
  ff=$(grep -m 1 -E '^FAIL ' "$log" || true)
  if [ "$rc" != 0 ]; then
    if [ -n "$ff" ]; then verdict=KILLED; else verdict=ERROR; fi
  elif [ -n "$res" ]; then verdict=SURVIVED; ff=SURVIVED
  else verdict=ERROR
  fi
  printf '%s\tfull\t%s\t%s\t%s\n' "$name" "$rc" "${res:-none}" "${ff:-none}" >> "$RES"
  printf '%s %s\n' "$name" "$verdict"
done
