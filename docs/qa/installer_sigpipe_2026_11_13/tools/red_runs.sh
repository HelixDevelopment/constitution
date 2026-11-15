#!/usr/bin/env bash
D="$(cd "$(dirname "$0")/.." && pwd)"; N="${1:-3000}"
for v in old new; do for run in 1 2 3; do
  systemd-run --user --scope -q -p TasksMax=3000 nice -n 10 env -i HOME="$D" PATH=/usr/bin:/bin LC_ALL=C \
    bash "$D/tools/red_harness.sh" "$D/ev/${v}_install_constitution.sh" "$N" > "$D/ev/harness_${v}_run$run.txt" 2>&1
done; done
echo done > "$D/ev/harness.done"
