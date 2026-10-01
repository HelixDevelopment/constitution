#!/bin/bash
# Purpose : T140 Round 21 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- round-20 independent review finding MINOR-1 (reviewer's own
#           overall verdict after seven review rounds: "I found no
#           remaining path where the tool returns ALLOWED and uncommitted
#           work is then actually lost ... I am highly confident in the
#           data-safety behaviour of this code" -- and predicted a GO once
#           this item lands with a paired fixture + mutation):
#             MINOR-1   round-19's own `os.lstat` + `S_ISLNK`/`S_ISREG`
#                       refusal only covers leaves found while WALKING
#                       `refs/`/`logs/` under the per-worktree admin dir.
#                       The TOP-LEVEL per-worktree pseudo-ref files -- HEAD,
#                       ORIG_HEAD, FETCH_HEAD, AUTO_MERGE -- are read via a
#                       SEPARATE code path
#                       (`candidates.extend(_oids_in_file(fp, reflog=False))`)
#                       with NO such check at all, so a FIFO named e.g.
#                       ORIG_HEAD made `_oids_in_file`'s `open()` block
#                       forever, outside any git timeout. Reproduced live
#                       (reviewer): `mkfifo main/.git/worktrees/wt/ORIG_HEAD`
#                       then `verify-proposal ... retire` hung indefinitely
#                       (killed at 15s, rc=124); a faulthandler dump
#                       confirmed it was blocked in `_oids_in_file`'s
#                       `open()` call, with git's own subprocess timeout set
#                       low to rule git itself out as the cause. The
#                       round-19 commit message's claim ("any non-regular
#                       leaf entry ... is refused too") was only true inside
#                       refs/logs/, not here. Not a data-safety hole
#                       (availability-only -- it hangs rather than falsely
#                       ALLOWing), but a real defect matching round 19's own
#                       stated intent. Fixed with the SAME os.lstat +
#                       S_ISLNK/S_ISREG refusal already used for the
#                       refs/logs walk, applied here too.
#
# Every case builds a REAL throwaway git repository under a temp dir (never
# this project's own repo, worktrees or stashes) and runs the REAL tool's
# `verify-proposal`, bounded by a hard WALL-CLOCK `timeout` (never the
# tool's own internal `CUSTODY_SWEEP_GIT_TIMEOUT_S`, which only bounds git
# subprocess calls -- never this local file `open()`) so a genuine
# regression cannot wedge this test suite itself. The fix is first shown to
# matter via a paired mutation that reverts it -- same pattern round 19
# already used successfully for its own F1 (FIFO-under-refs/) fixture.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
      GIT_COMMON_DIR CUSTODY_SWEEP_GIT_TIMEOUT_S
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main -c protocol.file.allow=always "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)

fail=0
pass=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=1; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R21 regression guard: control needle -- tool + libs exist, git/python/mkfifo usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
command -v git >/dev/null || notok "control needle: git not on PATH"
command -v mkfifo >/dev/null || notok "control needle: mkfifo not on PATH"
command -v timeout >/dev/null || notok "control needle: timeout not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git + mkfifo + timeout present"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# run_case_walltimeout: the python invocation itself is wrapped in a hard
# WALL-CLOCK `timeout` (never the tool's own internal
# CUSTODY_SWEEP_GIT_TIMEOUT_S, which only bounds git subprocess calls --
# never this local admin-file `open()`). Prints "RC<TAB>VERDICT<TAB>DETAIL";
# RC=124 means the wall timeout fired (the process was killed while still
# blocked).
run_case_walltimeout() {  # IMPL ROOT KIND ID ACTION BACKUP WALL_S
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6" wall="$7"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json" rc res
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  timeout -k 2 "$wall" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  rc=$?
  res=$(python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
)
  printf '%s\t%s\n' "$rc" "$res"
}

# mkrepo DIR : main repo DIR/main (one commit: f, keep) + linked worktree DIR/wt on branch feat
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  g init --quiet "$d/main"
  printf 'a\n' > "$d/main/f"; printf 'b\n' > "$d/main/keep"
  g -C "$d/main" add -A; g -C "$d/main" commit --quiet -m init
  g -C "$d/main" worktree add --quiet -b feat "$d/wt" >/dev/null 2>&1
}
wt_backup() { g -C "$1/wt" diff "${CANON[@]}" HEAD > "$1/wt.patch"; }
admin() { echo "$1/main/.git/worktrees/wt"; }

build_copy() {
  mkdir -p "$1/orchestration" "$1/lib"
  cp "$IMPL" "$1/orchestration/custody_sweep.py"
  cp "$LIB" "$1/lib/fc_common.py"
  cp "$EXLIB" "$1/lib/fc_entry.py"
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    print("anchor count=%d for %r" % (c.count(old), old))
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
}
mk_mutant() {  # NAME OLD NEW -> prints mutant impl path, or "" on anchor failure
  local d="$TMP/mut_$1"
  build_copy "$d"
  if mutate "$d/orchestration/custody_sweep.py" "$2" "$3" >"$d.log" 2>&1; then
    echo "$d/orchestration/custody_sweep.py"
  fi
}

# ---------------------------------------------------------------------------
# MINOR-1: a FIFO at a TOP-LEVEL per-worktree pseudo-ref file (ORIG_HEAD)
# is refused instantly, never blocks on open().
# ---------------------------------------------------------------------------
echo
echo "=== MINOR-1: a FIFO named ORIG_HEAD (top-level per-worktree pseudo-ref) is refused instantly, never blocks ==="
P1="$TMP/p1"; mkrepo "$P1"
P1_ADMIN="$(admin "$P1")"
echo z >> "$P1/wt/keep"; wt_backup "$P1"
# `worktree add` itself already writes a real ORIG_HEAD file into the
# admin dir (a non-fixture artifact of checkout) -- it must be replaced
# with the FIFO, not merely created alongside a pre-existing regular file.
rm -f "$P1_ADMIN/ORIG_HEAD"
mkfifo "$P1_ADMIN/ORIG_HEAD"
if [ -p "$P1_ADMIN/ORIG_HEAD" ]; then
  ok "P1 evidence: ORIG_HEAD under the per-worktree admin dir is a real FIFO"
else
  notok "P1 evidence: unexpected fixture shape (ORIG_HEAD is not a FIFO)"
fi
RES=$(run_case_walltimeout "$IMPL" "$P1/main" worktree wt retire "$P1/wt.patch" 10)
IFS=$'\t' read -r P1_RC P1_V P1_DET <<<"$RES"
if [ "$P1_RC" != 124 ] && [ "$P1_V" = REFUSED ] && [[ "$P1_DET" == *"ORIG_HEAD: unexpected non-regular admin entry"* ]]; then
  ok "P1 FIFO as ORIG_HEAD -> REFUSED without hanging (detail names: ORIG_HEAD: unexpected non-regular admin entry)"
else
  notok "P1 expected a non-hang (rc!=124) REFUSED naming ORIG_HEAD as non-regular, got rc=$P1_RC verdict=$P1_V" \
        "(${P1_DET:0:300})"
fi
# Paired mutation: remove ONLY the new top-level lstat/non-regular check
# added this round. Without it, `open()` on the FIFO (inside
# `_oids_in_file`, called unconditionally for HEAD/ORIG_HEAD/FETCH_HEAD/
# AUTO_MERGE) blocks FOREVER (no writer ever connects to the FIFO) --
# bounded here by a hard WALL-CLOCK timeout (never the tool's own internal
# git-subprocess timeout, which this local file read never goes through)
# so a true hang cannot wedge this test suite itself.
m=$(mk_mutant MR21_1_toplevel_pseudoref_check_removed \
'            try:
                lst = os.lstat(fp)
            except OSError as exc:
                return None, "could not stat %r (%s: %s)" % (fp, type(exc).__name__, exc)
            if stat.S_ISLNK(lst.st_mode):
                problems.append("%s: unexpected symlinked admin entry (refused; cannot prove "
                                "the symlink target is anchored elsewhere)" % name)
                continue
            if not stat.S_ISREG(lst.st_mode):
                problems.append("%s: unexpected non-regular admin entry (refused; e.g. a FIFO "
                                "could block indefinitely outside any git timeout)" % name)
                continue
            candidates.extend(_oids_in_file(fp, reflog=False))  # HEAD / ORIG_HEAD / FETCH_HEAD / AUTO_MERGE' \
'            candidates.extend(_oids_in_file(fp, reflog=False))  # HEAD / ORIG_HEAD / FETCH_HEAD / AUTO_MERGE')
if [ -z "$m" ]; then
  notok "mutation MR21_1_toplevel_pseudoref_check_removed: anchor not found ($(cat "$TMP/mut_MR21_1_toplevel_pseudoref_check_removed.log"))"
else
  MRES=$(run_case_walltimeout "$m" "$P1/main" worktree wt retire "$P1/wt.patch" 6)
  IFS=$'\t' read -r M_RC M_V M_DET <<<"$MRES"
  if [ "$M_RC" = 124 ]; then
    ok "mutation MR21_1_toplevel_pseudoref_check_removed: caught -- mutant HANGS on open() (wall-timeout rc=124)," \
       "real tool REFUSES instantly without ever opening the FIFO"
  else
    notok "mutation MR21_1_toplevel_pseudoref_check_removed SURVIVED: mutant did not hang (rc=$M_RC verdict=$M_V," \
          "detail: ${M_DET:0:200})"
  fi
fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R21 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- a FIFO at a top-level per-worktree"
  echo "    pseudo-ref file (HEAD/ORIG_HEAD/FETCH_HEAD/AUTO_MERGE) is refused fail-closed instead of"
  echo "    hanging the tool forever on open(). ==="
  exit 0
else
  echo "=== R21 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
