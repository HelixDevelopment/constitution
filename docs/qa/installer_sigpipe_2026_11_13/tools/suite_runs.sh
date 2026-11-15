#!/usr/bin/env bash
# suite_runs.sh LABEL REPO_DIR N → N quick install-suite runs, one log each, then a summary line per run
D="$(cd "$(dirname "$0")/.." && pwd)"; L="${1:?}"; R="${2:?}"; N="${3:?}"
mkdir -p "$D/ev/suites_final"
for ((k=1; k<=N; k++)); do
  log="$D/ev/suites_final/${L}_run$k.log"; t0=$SECONDS
  systemd-run --user --scope -q -p TasksMax=3000 nice -n 10 env -i HOME=/nonexistent-home TMPDIR="$D/tmp" \
    PATH=/usr/bin:/bin LC_ALL=C.UTF-8 TERM=dumb bash "$R/tests/install/run_all.sh" --quick >"$log" 2>&1
  rc=$?
  echo "$L run$k rc=$rc secs=$((SECONDS-t0)) $(grep -E '^RUN_ALL:' "$log")" >>"$D/ev/suites_final/summary.txt"
done
