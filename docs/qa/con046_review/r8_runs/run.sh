#!/bin/bash
# usage: run.sh <n> ; full mutation suite on the committed snapshot snap/c (5834ce3d), persistent TMPDIR
B="$(cd "$(dirname "$0")/.." && pwd)"; n="${1:?}"; log="$B/runs/run$n.log"
cd "$B/snap/c" || exit 9
{ echo "start $(date -Is) commit 5834ce3d host $(hostname) load $(cut -d' ' -f1-3 /proc/loadavg)"
  TMPDIR="$B/tmp" MUT_JOBS=6 nice -n 10 bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh; echo "rc=$?"
  echo "end $(date -Is)"; } >"$log" 2>&1
sha256sum "$log" > "$log.sha256"
