#!/usr/bin/env bash
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
# mutrun.sh <repo> <outdir> <pattern|ALL> ids...   one mutant at a time in a copy of scripts/workable-items.
set -u
REPO="$1"; OUT="$2"; PAT="$3"; shift 3
MUT=/mnt/DATA1TB/claude-work/scratch/fix456r6_5Dgr6t/mut
export TMPDIR=/mnt/DATA1TB/claude-work/tmp GOCACHE=/mnt/DATA1TB/claude-work/gocache GOPROXY=off
mkdir -p "$OUT"
for id in "$@"; do
  until awk '{exit !($1<50)}' /proc/loadavg; do sleep 20; done
  W=$(mktemp -d "$OUT/w.$id.XXXXXX")
  cp -r "$REPO/scripts/workable-items/." "$W/" && rm -rf "$W/bin"
  case "$id" in
    NOOP) echo "APPLIED NOOP identity" >"$OUT/$id.apply" ;;
    RV*) python3 -I "$MUT/rev_mutants.py" "$W/cmd/workable-items" "$id" >"$OUT/$id.apply" 2>&1 ;;
    *) python3 -I "$MUT/own_mutants.py.txt" "$W/cmd/workable-items" "$id" >"$OUT/$id.apply" 2>&1 ;;
  esac
  if grep -q NOT-APPLIED "$OUT/$id.apply"; then echo "$id NOT-APPLIED" >>"$OUT/table.tsv"; ${SAFE_RM:-true}; continue; fi
  if [ "$PAT" = ALL ]; then RUN=(); else RUN=(-run "$PAT"); fi
  (cd "$W" && systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 go test -count=1 -json "${RUN[@]}" ./cmd/workable-items >"$OUT/$id.json" 2>"$OUT/$id.err")
  rc=$?
  python3 -I - "$OUT/$id.json" "$id" "$rc" >>"$OUT/table.tsv" <<'PY'
import json,sys
p,i,rc=sys.argv[1:4]
fails=set(); build=False
for l in open(p):
    try:e=json.loads(l)
    except: 
        if 'build failed' in l or 'FAIL' in l: build=True
        continue
    if e.get('Action')=='fail' and e.get('Test'): fails.add(e['Test'])
    if e.get('Action')=='fail' and not e.get('Test') and e.get('Package'): pass
print(f"{i}\trc={rc}\tfails={len(fails)}\t{'BUILD?' if build and not fails else ''}\t{sorted(fails)[:3]}")
PY
done
echo MUT-DONE >>"$OUT/table.tsv"
