#!/usr/bin/env bash
# Round-5 mutant runner (adapted from the reviewer's tools/mutrun.sh): one git
# worktree per mutant at commit $REV, python exact-string replacement (fails
# when the target string is not present exactly once), full go test of the
# package. Usage: mutrun.sh <work-dir> <rev> <name> <file> <old> <new>
set -u
W="${1:?work dir}"; REV="${2:?rev}"; NAME="${3:?mutant name}"; FILE="${4:?file}"; OLD="${5?old}"; NEW="${6?new}"
REPO="$W/repo"; WT="$W/mut/$NAME"
[ -e "$WT" ] && { echo "exists $WT"; exit 64; }
git -C "$REPO" worktree add -q --detach "$WT" "$REV" || exit 1
if [ "$NAME" != CONTROL ]; then
  python3 -I -c '
import sys; f,o,n=sys.argv[1:4]; s=open(f).read(); c=s.count(o)
if c!=1: print("APPLY-FAIL count",c); sys.exit(3)
open(f,"w").write(s.replace(o,n))' "$WT/$FILE" "$OLD" "$NEW" || { echo "$NAME APPLY-FAIL"; exit 3; }
fi
cd "$WT/scripts/workable-items" || exit 1
export TMPDIR=/mnt/DATA1TB/claude-work/tmp GOCACHE=/mnt/DATA1TB/claude-work/gocache
systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 go test -count=1 -json ./cmd/workable-items/ > "$W/mut/$NAME.json" 2>"$W/mut/$NAME.err"
rc=$?
echo "$NAME go-test rc=$rc fails=$(grep -c '"Action":"fail","Package":"[^"]*","Test"' "$W/mut/$NAME.json")"
