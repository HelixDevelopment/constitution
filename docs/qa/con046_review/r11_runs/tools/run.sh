#!/bin/bash
# usage: run.sh <checkout> <logdir> <n> ; one full mutation screen of the CON-046 pin gate on the committed head of
# <checkout> (round 11). The start line names the head, the number of `git status --porcelain` lines (must be 0) and the
# load; the log gets a .sha256 file. Refuses (exit 9) when the tree is not clean, so a screen never runs on uncommitted code.
set -u
co="${1:?checkout}"; ld="${2:?logdir}"; n="${3:?n}"; log="$ld/screen$n.log"
cd "$co" || exit 9
head="$(git rev-parse HEAD)"; cl="$(git status --porcelain --untracked-files=all | wc -l)"
[ "$cl" = 0 ] || { echo "refused: $cl uncommitted lines in $co" >&2; exit 9; }
mkdir -p "$ld/tmp$n"
{ echo "start $(date -Is) head $head clean-tree-lines $cl host $(hostname) SUITE_NOW ${SUITE_NOW:-unset} load $(cut -d' ' -f1-3 /proc/loadavg)"
  TMPDIR="$ld/tmp$n" MUT_JOBS=6 nice -n 10 bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh; echo "rc=$?"
  echo "end $(date -Is) head $(git rev-parse HEAD) clean-tree-lines $(git status --porcelain --untracked-files=all | wc -l)"; } >"$log" 2>&1
(cd "$ld" && sha256sum "screen$n.log" > "screen$n.log.sha256")
