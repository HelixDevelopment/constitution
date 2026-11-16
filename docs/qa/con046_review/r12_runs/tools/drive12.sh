#!/bin/bash
# drive12.sh: three full screens of the round-12 suite on the clean worktree wt, one at a time, all on ONE local day.
# Same guard as r11 tools/drive.sh, with NO hand-passed input: longest = max(finished screens of THIS drive); screen n>1
# starts only if the day is unchanged and the time left until 23:55 is >= 1.5 x longest; else it is REFUSED (exit 3).
# Each screen runs in its own user scope, TasksMax=2000, MUT_JOBS=6, nice 10; pids.peak / pids.events are recorded.
set -u
d=/mnt/DATA1TB/claude-work/scratch/fx046r12.KQXD; ld="$d/screens"; co="$d/wt"
day="$(date +%F)"; export SUITE_NOW="${day}T12:00:00Z"; longest=0
echo "$(date -Is) drive start day $day SUITE_NOW $SUITE_NOW head $(git -C "$co" rev-parse HEAD)" >>"$ld/drive.log"
for n in 1 2 3; do
  now="$(date +%s)"; left=$(( $(date -d "$day 23:55" +%s) - now ))
  refuse=0; [ "$(date +%F)" = "$day" ] || refuse=1; [ "$n" -gt 1 ] && [ $((left * 2)) -lt $((longest * 3)) ] && refuse=1
  if [ "$refuse" = 1 ]; then echo "$(date -Is) screen $n REFUSED: ${left}s left today, longest screen ${longest}s (needs 1.5x)" >>"$ld/drive.log"; exit 3; fi
  cl="$(git -C "$co" status --porcelain --untracked-files=all | wc -l)"; [ "$cl" = 0 ] || { echo "$(date -Is) screen $n refused: tree not clean ($cl)" >>"$ld/drive.log"; exit 9; }
  echo "$(date -Is) screen $n start (time left ${left}s, longest ${longest}s)" >>"$ld/drive.log"
  t="$d/tmpS$n"; mkdir -p "$t"; t0="$(date +%s)"
  { echo "start $(date -Is) head $(git -C "$co" rev-parse HEAD) clean-tree-lines $cl host $(hostname) SUITE_NOW $SUITE_NOW load $(cut -d' ' -f1-3 /proc/loadavg)"; } >"$ld/screen$n.log"
  ( cd "$co" && TMPDIR="$t" MUT_JOBS=6 "$d/runscope.sh" "con046r12-s$n" 2000 "$ld/screen$n.body" bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh ); rc=$?
  cat "$ld/screen$n.body" >>"$ld/screen$n.log"; rm -f "$ld/screen$n.body"
  echo "end $(date -Is) head $(git -C "$co" rev-parse HEAD) clean-tree-lines $(git -C "$co" status --porcelain --untracked-files=all | wc -l)" >>"$ld/screen$n.log"
  dt=$(( $(date +%s) - t0 )); [ "$dt" -gt "$longest" ] && longest=$dt
  echo "$(date -Is) screen $n rc=$rc duration ${dt}s" >>"$ld/drive.log"
  [ -n "$t" ] && [ -d "$t" ] && rm -rf -- "${t:?}"
done
echo "$(date -Is) all done" >>"$ld/drive.log"
