#!/bin/bash
# Purpose : T140 Round 17 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- round-16 independent review findings (a NO-GO review that
#           found NO live bypass after explicit hunting for a 6th-generation
#           defect -- every one of the 24 then-existing regression suites
#           re-verified REFUSED on the reviewer's own fixtures, 3/3 runs,
#           zero regressions from round 15):
#             IMPORTANT-1 the reflog "old oid" branch of `_oids_in_file` has
#                         ZERO test coverage -- a mutant collecting only the
#                         "new" oid of each reflog line passes every r6-r15
#                         custody regression suite untouched, even though the
#                         real code (`oids.extend(parts[:2])`) is ALREADY
#                         correct. This round closes exactly that coverage
#                         gap with the reviewer's own named repro (scenario
#                         R1): a linked worktree, `checkout --detach`,
#                         commit L, `checkout feat` (abandoning L), then
#                         `git reflog delete HEAD@{1}` -- L now survives
#                         ONLY as the OLD id of the surviving reflog entry.
#                         (git's own default 30-day reflog expiry produces
#                         this shape naturally -- no manual reflog surgery
#                         required in practice.)
#             MINOR-1     round-15's own timeout fix was not fully bounded:
#                         after the process-group SIGKILL, `_exec` called
#                         `proc.communicate()` a SECOND time with NO timeout
#                         -- a smudge/clean filter that escaped the group
#                         (e.g. via `setsid`) keeps its OWN dup of the
#                         stdout/stderr PIPE write-end open, so the tool
#                         could still hang well past the configured timeout
#                         (measured by the reviewer: ~25s instead of ~3s
#                         with a `setsid sleep 25 & cat`-style filter; hangs
#                         FOREVER with `sleep infinity`). Fixed with a
#                         short, bounded drain attempt whose own timeout is
#                         resolved via `_group_has_survivor` (signal 0 --
#                         the REAL kernel state, never a guess): something
#                         STILL alive in OUR OWN process group means the
#                         kill itself did not do its job (a genuine defect
#                         that MUST stay observable as a hang -- this is
#                         EXACTLY what the pre-existing MT1 mutation in the
#                         r15 suite exercises, and this round's fix is
#                         proven NOT to weaken it); a genuinely EMPTY group
#                         means whatever still holds a write end open has
#                         ESCAPED it entirely, so the drain is ABANDONED
#                         instead of re-blocking indefinitely.
#             MINOR-2     fail-open directory walk in the admin-dir check:
#                         the `logs/`/`refs/` scan used `os.walk(fp)` with
#                         NO `onerror` handler, which by DEFAULT silently
#                         SKIPS a directory it cannot read (permission
#                         denied) instead of raising -- `chmod 000` on an
#                         admin `refs/worktree`/`logs` directory flipped the
#                         verdict from REFUSED to ALLOWED, contradicting
#                         this module's own fail-closed design (the sibling
#                         `os.scandir` call in `_snapshot_files` already
#                         lets a permission error propagate so the caller
#                         refuses). Fixed with `onerror=_walk_raise`.
#
# MINOR-3 (round-16 finding) is fixed directly in
# test_custody_sweep_r15_regression.sh (the B2 proof-of-loss methodology
# flaw this round found IN THAT suite's own evidence section, not in
# custody_sweep.py itself) -- not duplicated here. MINOR-4 (3 shellcheck
# info/style notes in r15, at warning-level-clean) is cosmetic and left
# untouched.
#
# Every case builds REAL throwaway git repositories under a temp dir (never
# this project's own repo, worktrees or stashes) and runs the REAL tool's
# `verify-proposal`. Each fix is first shown to matter via a paired mutation
# that reverts it (the mutant must regress to the pre-round-17 behaviour the
# finding describes); the real tool's elapsed time / verdict is asserted
# against the finding's own measured numbers (~3-7s fixed vs ~20s+ pre-fix
# for the two timing-based checks).
#
# Producer != Verifier (section 11.4.240): the fixtures re-derive the
# round-16 reviewer's own finding text (reflog old-oid scenario R1, the
# `setsid sleep 25 & cat` smudge filter, the `chmod 000` admin-dir attack),
# not the tool's own selftest.
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

echo "=== R17 regression guard: control needle -- tool + libs exist, git usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
command -v git >/dev/null || notok "control needle: git not on PATH"
command -v setsid >/dev/null || notok "control needle: setsid not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git + setsid present"

sha() { sha256sum "$1" | cut -d' ' -f1; }

run_case() {  # IMPL ROOT KIND ID ACTION BACKUP [TIMEOUT_S] -> "VERDICT<TAB>DETAIL<TAB>ELAPSED"
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6" tmo="${7:-}"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json" s e
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  s=$(date +%s)
  if [ -n "$tmo" ]; then
    CUSTODY_SWEEP_GIT_TIMEOUT_S="$tmo" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  else
    python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  fi
  e=$(date +%s)
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
}

# run_case_timed: same as run_case but ALSO returns elapsed seconds as a third tab field.
run_case_timed() {
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6" tmo="${7:-}"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json" s e res
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  s=$(date +%s)
  if [ -n "$tmo" ]; then
    CUSTODY_SWEEP_GIT_TIMEOUT_S="$tmo" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  else
    python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  fi
  e=$(date +%s)
  res=$(python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
)
  printf '%s\t%s\n' "$res" "$((e - s))"
}

expect() {  # NAME RESULT VERDICT [DETAIL_SUBSTRING...]
  local name="$1" res="$2" want="$3"
  shift 3
  local got="${res%%$'\t'*}" det="${res#*$'\t'}" s
  if [ "$got" != "$want" ]; then
    notok "$name: expected $want, got $got (${det:0:400})"
    return
  fi
  for s in "$@"; do
    if [[ "$det" != *"$s"* ]]; then
      notok "$name: $got but detail does not name \"$s\" (${det:0:400})"
      return
    fi
  done
  ok "$name -> $got${1:+ (detail names: $*)}"
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
mut_allows() {  # NAME OLD NEW ROOT KIND ID ACTION BACKUP
  local name="$1" old="$2" new="$3" root="$4" kind="$5" id="$6" action="$7" path="$8"
  local m real mutant
  m=$(mk_mutant "$name" "$old" "$new")
  if [ -z "$m" ]; then notok "mutation $name: anchor not found ($(cat "$TMP/mut_$name.log"))"; return; fi
  real=$(run_case_timed "$IMPL" "$root" "$kind" "$id" "$action" "$path")
  mutant=$(run_case_timed "$m" "$root" "$kind" "$id" "$action" "$path")
  if [ "${real%%$'\t'*}" != REFUSED ]; then notok "mutation $name: REAL tool did not refuse (${real:0:200})"; return; fi
  if [ "${mutant%%$'\t'*}" = ALLOWED ]; then
    ok "mutation $name: caught -- mutant ALLOWS what the real tool refuses"
  else
    notok "mutation $name SURVIVED: mutant ${mutant:0:200}"
  fi
}

# ---------------------------------------------------------------------------
# IMPORTANT-1: reflog "old oid" branch -- scenario R1.
# ---------------------------------------------------------------------------
echo
echo "=== IMPORTANT-1 a commit reachable only as the OLD oid of a surviving reflog line ==="
R1="$TMP/r1"; mkrepo "$R1"
g -C "$R1/wt" checkout --quiet --detach
echo L > "$R1/wt/lfile"; g -C "$R1/wt" add lfile; g -C "$R1/wt" commit --quiet -m L
LCOMMIT=$(g -C "$R1/wt" rev-parse HEAD)
g -C "$R1/wt" checkout --quiet feat
g -C "$R1/wt" reflog delete 'HEAD@{1}'
echo z >> "$R1/wt/keep"; wt_backup "$R1"
R1_ADMIN_LOG="$(admin "$R1")/logs/HEAD"
if [ -z "$(g -C "$R1/main" for-each-ref --contains "$LCOMMIT")" ] \
   && ! awk -v l="$LCOMMIT" '$2==l{f=1} END{exit !f}' "$R1_ADMIN_LOG" \
   && awk -v l="$LCOMMIT" '$1==l{f=1} END{exit !f}' "$R1_ADMIN_LOG"; then
  ok "R1 evidence: L is reachable from no ref, and appears in logs/HEAD ONLY as an old-oid (never a new-oid)"
else
  notok "R1 evidence: unexpected fixture shape (git reflog delete did not leave L old-oid-only)"
fi
expect "R1 reflog old-oid-only commit" "$(run_case "$IMPL" "$R1/main" worktree wt retire "$R1/wt.patch")" REFUSED \
  "reachable only through this worktree's own" "$LCOMMIT"
mut_allows MR1_reflog_old_oid_collected \
  '            oids.extend(parts[:2])' \
  '            oids.append(parts[1])' \
  "$R1/main" worktree wt retire "$R1/wt.patch"

# ---------------------------------------------------------------------------
# MINOR-1: post-kill drain is bounded against a process that escaped the
# killed group entirely (e.g. via setsid), without weakening detection of a
# kill that never reached the whole group in the first place.
# ---------------------------------------------------------------------------
echo
echo "=== MINOR-1 a filter that escapes the killed process group (setsid) is bounded, not re-blocked forever ==="
T1="$TMP/t1"; mkrepo "$T1"
g -C "$T1/main" config filter.slow.clean 'setsid sh -c "sleep 25" & cat'
g -C "$T1/main" config filter.slow.smudge cat
mkdir -p "$T1/main/.git/info"; echo 'f filter=slow' > "$T1/main/.git/info/attributes"
echo changed >> "$T1/wt/f"; cp /dev/null "$T1/wt.patch"
R1T=$(run_case_timed "$IMPL" "$T1/main" worktree wt retire "$T1/wt.patch" 3)
R1T_V=${R1T%%$'\t'*}; R1T_EL=${R1T##*$'\t'}
if [ "$R1T_V" = REFUSED ] && [ "$R1T_EL" -lt 15 ]; then
  ok "MINOR-1 setsid-escaped filter -> REFUSED in ${R1T_EL}s (bounded; < the escaped filter's 25s sleep)"
else
  notok "MINOR-1 expected REFUSED in <15s, got $R1T_V in ${R1T_EL}s"
fi
# A SECOND, independent same-fixture run: the fix must be DETERMINISTIC, not
# a one-off, so the elapsed-time assertion is run twice against fresh
# processes (the setsid orphan from run 1 is unrelated and long-exited or
# irrelevant by run 2's own bounded window).
R1T2=$(run_case_timed "$IMPL" "$T1/main" worktree wt retire "$T1/wt.patch" 3)
R1T2_V=${R1T2%%$'\t'*}; R1T2_EL=${R1T2##*$'\t'}
if [ "$R1T2_V" = REFUSED ] && [ "$R1T2_EL" -lt 15 ]; then
  ok "MINOR-1 setsid-escaped filter (2nd run, determinism check) -> REFUSED in ${R1T2_EL}s"
else
  notok "MINOR-1 (2nd run) expected REFUSED in <15s, got $R1T2_V in ${R1T2_EL}s"
fi
# Paired mutation: disable ONLY the "group genuinely empty -> abandon" path
# (force it to always fall through to the unbounded wait). The mutant must
# regress to the pre-round-17 ~25s hang; the real tool must stay bounded.
m=$(mk_mutant MR17_1_abandon_path_disabled \
    '            if _group_has_survivor(pgid) is False:' '            if False:')
if [ -z "$m" ]; then
  notok "mutation MR17_1_abandon_path_disabled: anchor not found ($(cat "$TMP/mut_MR17_1_abandon_path_disabled.log"))"
else
  MUT=$(run_case_timed "$m" "$T1/main" worktree wt retire "$T1/wt.patch" 3)
  MUT_EL=${MUT##*$'\t'}
  if [ "$MUT_EL" -ge 15 ]; then
    ok "mutation MR17_1_abandon_path_disabled: caught -- mutant took ${MUT_EL}s (re-blocked on the escaped filter)," \
       "real tool ${R1T_EL}s"
  else
    notok "mutation MR17_1_abandon_path_disabled SURVIVED: mutant took only ${MUT_EL}s"
  fi
fi
# Round-15's pre-existing MT1 (kill only the direct child, never the group)
# must STILL be caught by elapsed time -- the whole point of using
# `_group_has_survivor` instead of a flat bound is to NOT weaken that
# detection. Re-derived here (not merely "trust r15's own file stays
# green") because this IS the specific interaction this round's own fix
# could have broken (and, mid-development, genuinely DID break once before
# the `_group_has_survivor` reap-before-probe fix landed).
T1b="$TMP/t1b"; mkrepo "$T1b"
g -C "$T1b/main" config filter.slow.clean 'sleep 25; cat'
g -C "$T1b/main" config filter.slow.smudge cat
mkdir -p "$T1b/main/.git/info"; echo 'f filter=slow' > "$T1b/main/.git/info/attributes"
echo changed >> "$T1b/wt/f"; cp /dev/null "$T1b/wt.patch"
mT1=$(mk_mutant MR17_2_kill_only_direct_child \
      '                os.killpg(pgid, _signal.SIGKILL)' '                proc.kill()')
if [ -z "$mT1" ]; then
  notok "mutation MR17_2_kill_only_direct_child: anchor not found ($(cat "$TMP/mut_MR17_2_kill_only_direct_child.log"))"
else
  REAL_T1B=$(run_case_timed "$IMPL" "$T1b/main" worktree wt retire "$T1b/wt.patch" 3)
  MUT_T1B=$(run_case_timed "$mT1" "$T1b/main" worktree wt retire "$T1b/wt.patch" 3)
  REAL_T1B_EL=${REAL_T1B##*$'\t'}; MUT_T1B_EL=${MUT_T1B##*$'\t'}
  if [ "$MUT_T1B_EL" -ge 15 ] && [ "$REAL_T1B_EL" -lt 15 ]; then
    ok "mutation MR17_2_kill_only_direct_child: caught -- mutant took ${MUT_T1B_EL}s (a NON-escaped filter sibling" \
       "survives a kill() that targets only git itself), real tool ${REAL_T1B_EL}s -- confirms this round's" \
       "MINOR-1 fix did NOT weaken detection of a kill-logic defect that never reaches the whole process group"
  else
    notok "mutation MR17_2_kill_only_direct_child: expected mutant >=15s and real <15s, got mutant=${MUT_T1B_EL}s" \
          "real=${REAL_T1B_EL}s"
  fi
fi

# ---------------------------------------------------------------------------
# MINOR-2: fail-open os.walk on an unreadable admin-dir subtree.
# ---------------------------------------------------------------------------
echo
echo "=== MINOR-2 chmod 000 on an admin refs/ subdirectory must REFUSE (fail-closed), never silently ALLOW ==="
M2="$TMP/m2"; mkrepo "$M2"
SAVED=$(echo only | g -C "$M2/wt" commit-tree "HEAD^{tree}" -p HEAD -m only)
g -C "$M2/wt" update-ref refs/worktree/saved "$SAVED"
echo z >> "$M2/wt/keep"; wt_backup "$M2"
M2_ADMIN="$(admin "$M2")"
if [ -d "$M2_ADMIN/refs/worktree" ] && [ -f "$M2_ADMIN/refs/worktree/saved" ]; then
  ok "M2 evidence: refs/worktree/saved exists before the permission attack"
else
  notok "M2 evidence: unexpected fixture shape (no refs/worktree/saved to hide)"
fi
chmod 000 "$M2_ADMIN/refs/worktree"
expect "M2 chmod 000 on admin refs/worktree/ -> fail-closed REFUSED (never a silent ALLOW)" \
  "$(run_case "$IMPL" "$M2/main" worktree wt retire "$M2/wt.patch")" REFUSED \
  "could not read the per-worktree admin dir" "PermissionError"
chmod 755 "$M2_ADMIN/refs/worktree"
# Paired mutation: revert the onerror handler to os.walk's silent-skip
# default. The mutant must ALLOW this exact permission-denied scenario
# (reproducing the round-16 finding); the real tool must REFUSE.
M2b="$TMP/m2b"; mkrepo "$M2b"
SAVED2=$(echo only | g -C "$M2b/wt" commit-tree "HEAD^{tree}" -p HEAD -m only2)
g -C "$M2b/wt" update-ref refs/worktree/saved "$SAVED2"
echo z >> "$M2b/wt/keep"; wt_backup "$M2b"
chmod 000 "$(admin "$M2b")/refs/worktree"
# T140 round-19: the anchor's variable name changed from `_dirs` to `dirs`
# when round 19 added the symlinked-subdirectory check (the walk now reads
# the `dirs` list the round-19 fix inspects) -- the mutation itself (revert
# `onerror=_walk_raise` to os.walk's silent-skip default) is unchanged.
m=$(mk_mutant MR17_3_walk_onerror_removed \
    '                for dirpath, dirs, files in os.walk(fp, onerror=_walk_raise):' \
    '                for dirpath, dirs, files in os.walk(fp):')
if [ -z "$m" ]; then
  notok "mutation MR17_3_walk_onerror_removed: anchor not found ($(cat "$TMP/mut_MR17_3_walk_onerror_removed.log"))"
else
  REAL_M2B=$(run_case "$IMPL" "$M2b/main" worktree wt retire "$M2b/wt.patch")
  MUT_M2B=$(run_case "$m" "$M2b/main" worktree wt retire "$M2b/wt.patch")
  if [ "${REAL_M2B%%$'\t'*}" != REFUSED ]; then
    notok "mutation MR17_3_walk_onerror_removed: REAL tool did not refuse (${REAL_M2B:0:200})"
  elif [ "${MUT_M2B%%$'\t'*}" = ALLOWED ]; then
    ok "mutation MR17_3_walk_onerror_removed: caught -- mutant silently ALLOWS the chmod-000 admin dir (the exact" \
       "round-16 REFUSED-to-ALLOWED flip), real tool still REFUSES"
  else
    notok "mutation MR17_3_walk_onerror_removed SURVIVED: mutant ${MUT_M2B:0:200}"
  fi
fi
chmod 755 "$(admin "$M2b")/refs/worktree"

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R17 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- the reflog old-oid branch is now"
  echo "    test-covered, a filter that escapes the killed process group (setsid) no longer re-blocks the"
  echo "    tool indefinitely (while a kill that never reaches the group at all still stays observable as a"
  echo "    hang, per the pre-existing MT1 guard), and a permission-denied admin-dir subtree fails CLOSED. ==="
  exit 0
else
  echo "=== R17 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
