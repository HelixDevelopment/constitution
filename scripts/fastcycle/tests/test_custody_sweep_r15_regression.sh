#!/bin/bash
# Purpose : T140 Round 15 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- round-14 independent review findings:
#             BLOCKING-1  a deinit'd submodule's git dir (with an unpushed
#                         commit) inside the per-worktree admin dir
#             BLOCKING-2  a commit reachable only via the worktree's own
#                         reflog / a per-worktree ref
#             MINOR-3     in-progress operation state in the admin dir
#                         (one check class with BLOCKING-1/2: "what does
#                         `worktree remove --force` delete OUTSIDE the files")
#             IMPORTANT-1 a stash whose base history only the stash keeps alive
#             IMPORTANT-2 ambient GIT_INDEX_FILE / GIT_DIR redirecting checks
#             gap 5       the stash-oracle apply-exit-code check (no coverage)
#             MINOR-1     `hash-object --stdin-paths` C-unquoting a '"q"' path
#             MINOR-2     backup hashed once, re-read from disk by `git apply`
#             MINOR-4     no subprocess timeout (a hanging filter hung the tool)
#
# Every case builds REAL throwaway git repositories under a temp dir (never
# this project's own repo, worktrees or stashes), creates the backup
# INDEPENDENTLY with plain git using the documented canonical option set, and
# runs the REAL tool's `verify-proposal`. Each bypass case is first shown to be
# ALLOWED by the round-13 code path (via a paired mutation that removes only the
# new check) and the LAST section proves -- by actually running
# `worktree remove --force` / `stash drop` + reflog expire + gc on the fixtures
# -- that the refused state really is lost data, so a REFUSED here is a correct
# refusal, not an over-refusal. Golden-good controls prove the new checks do
# not refuse ordinary restorable work.
#
# Producer != Verifier (section 11.4.240): the bypass cases re-derive the
# round-14 reviewer's own repros (scratchpad/w/{n1,n2,n3,n5,env,q2}) from the
# finding text, not the tool's selftest.
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

echo "=== R15 regression guard: control needle -- tool + libs exist, git usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
command -v git >/dev/null || notok "control needle: git not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git present"

sha() { sha256sum "$1" | cut -d' ' -f1; }

run_case() {  # IMPL ROOT KIND ID ACTION BACKUP -> "VERDICT<TAB>DETAIL"   (env passes through)
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json"
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
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
st_backup() { g -C "$1/main" stash show -p "${CANON[@]}" "$2" > "$1/st.patch"; }
admin() { echo "$1/main/.git/worktrees/wt"; }

echo
echo "=== BLOCKING-1 deinit'd submodule with an unpushed commit (admin modules/) ==="
B1="$TMP/b1"
mkdir -p "$B1"
g init --quiet "$B1/sub"; echo s > "$B1/sub/s"; g -C "$B1/sub" add s; g -C "$B1/sub" commit --quiet -m s
g init --quiet "$B1/main"; printf 'a\n' > "$B1/main/f"; printf 'b\n' > "$B1/main/keep"
g -C "$B1/main" add -A; g -C "$B1/main" commit --quiet -m init
g -C "$B1/main" submodule add --quiet "$B1/sub" sub >/dev/null 2>&1; g -C "$B1/main" commit --quiet -m addsub
g -C "$B1/main" worktree add --quiet -b feat "$B1/wt" >/dev/null 2>&1
g -C "$B1/wt" submodule update --quiet --init >/dev/null 2>&1
g -C "$B1/wt/sub" checkout --quiet -b work; echo P > "$B1/wt/sub/p"; g -C "$B1/wt/sub" add p
g -C "$B1/wt/sub" commit --quiet -m PRECIOUS
PRECIOUS=$(g -C "$B1/wt/sub" rev-parse HEAD)
g -C "$B1/wt/sub" checkout --quiet --detach HEAD~1
g -C "$B1/wt" submodule deinit --quiet -f sub >/dev/null 2>&1
echo z >> "$B1/wt/keep"
wt_backup "$B1"
if [ -d "$(admin "$B1")/modules/sub" ] && [ -z "$(g -C "$B1/wt" status --porcelain=v2 --ignore-submodules=none -- sub)" ] \
   && g -C "$(admin "$B1")/modules/sub" cat-file -e "$PRECIOUS" 2>/dev/null; then
  ok "B1 evidence: PRECIOUS lives only in the admin dir's modules/sub; submodule status reads clean"
else
  notok "B1 evidence: unexpected fixture shape"
fi
expect "B1 deinit'd submodule" "$(run_case "$IMPL" "$B1/main" worktree wt retire "$B1/wt.patch")" REFUSED \
  "modules/sub" "submodule git dir inside the per-worktree admin dir"

echo
echo "=== BLOCKING-2a abandoned detached-HEAD commit (only in the worktree's own reflog) ==="
B2="$TMP/b2"; mkrepo "$B2"
g -C "$B2/wt" checkout --quiet --detach; echo o > "$B2/wt/o"; g -C "$B2/wt" add o; g -C "$B2/wt" commit --quiet -m orphan
ORPHAN=$(g -C "$B2/wt" rev-parse HEAD)
g -C "$B2/wt" checkout --quiet feat; echo z >> "$B2/wt/keep"; wt_backup "$B2"
if [ -z "$(g -C "$B2/main" for-each-ref --contains "$ORPHAN")" ] && grep -q "$ORPHAN" "$(admin "$B2")/logs/HEAD"; then
  ok "B2a evidence: the orphan commit is held by no ref, only by the per-worktree logs/HEAD"
else
  notok "B2a evidence: unexpected fixture shape"
fi
expect "B2a reflog-only commit" "$(run_case "$IMPL" "$B2/main" worktree wt retire "$B2/wt.patch")" REFUSED \
  "reachable only through this worktree's own" "$ORPHAN"

echo
echo "=== BLOCKING-2b commit held ONLY by a per-worktree ref (refs/worktree/saved, no reflog) ==="
B3="$TMP/b3"; mkrepo "$B3"
SAVED=$(echo only | g -C "$B3/wt" commit-tree "HEAD^{tree}" -p HEAD -m only)
g -C "$B3/wt" update-ref refs/worktree/saved "$SAVED"; echo z >> "$B3/wt/keep"; wt_backup "$B3"
if [ -f "$(admin "$B3")/refs/worktree/saved" ] && ! grep -q "$SAVED" "$(admin "$B3")/logs/HEAD"; then
  ok "B2b evidence: SAVED is held only by the per-worktree ref file (not in any reflog)"
else
  notok "B2b evidence: unexpected fixture shape"
fi
expect "B2b per-worktree-ref-only commit" "$(run_case "$IMPL" "$B3/main" worktree wt retire "$B3/wt.patch")" \
  REFUSED "refs/worktree/saved: a per-worktree ref" "$SAVED"
B3m="$TMP/b3m"; mkrepo "$B3m"
g -C "$B3m/wt" update-ref refs/bisect/bad HEAD; echo z >> "$B3m/wt/keep"; wt_backup "$B3m"
expect "B2c per-worktree ref to an ANCHORED commit (ref itself is per-worktree state)" \
  "$(run_case "$IMPL" "$B3m/main" worktree wt retire "$B3m/wt.patch")" REFUSED "refs/bisect/bad: a per-worktree ref"

echo
echo "=== MINOR-3 in-progress operation state (merge --no-commit, rebase stopped at 'edit') ==="
M3="$TMP/m3"; mkrepo "$M3"
g -C "$M3/main" checkout --quiet -b other; echo O >> "$M3/main/keep"; g -C "$M3/main" commit --quiet -am o
g -C "$M3/main" checkout --quiet main
g -C "$M3/wt" merge --quiet --no-commit --no-ff other >/dev/null 2>&1; wt_backup "$M3"
[ -f "$(admin "$M3")/MERGE_HEAD" ] && ok "M3a evidence: MERGE_HEAD present, no conflict" || notok "M3a evidence: no MERGE_HEAD"
expect "M3a merge in progress" "$(run_case "$IMPL" "$M3/main" worktree wt retire "$M3/wt.patch")" REFUSED \
  "MERGE_HEAD: in-progress operation state"
R3="$TMP/r3"; mkrepo "$R3"
echo c1 >> "$R3/wt/f"; g -C "$R3/wt" commit --quiet -am c1
GIT_SEQUENCE_EDITOR="sed -i 1s/^pick/edit/" g -C "$R3/wt" rebase --quiet -i HEAD~1 >/dev/null 2>&1
echo z >> "$R3/wt/keep"; wt_backup "$R3"
[ -d "$(admin "$R3")/rebase-merge" ] && ok "M3b evidence: rebase-merge/ present (stopped at edit)" \
  || notok "M3b evidence: no rebase-merge dir"
expect "M3b rebase stopped at edit" "$(run_case "$IMPL" "$R3/main" worktree wt retire "$R3/wt.patch")" REFUSED \
  "rebase-merge: in-progress operation state"
U3="$TMP/u3"; mkrepo "$U3"
echo z >> "$U3/wt/keep"; wt_backup "$U3"; printf '[core]\n\tsparseCheckout = false\n' > "$(admin "$U3")/config.worktree"
expect "M3c unrecognised admin entry (config.worktree)" \
  "$(run_case "$IMPL" "$U3/main" worktree wt retire "$U3/wt.patch")" REFUSED "config.worktree: unrecognised"

echo
echo "=== IMPORTANT-1 stash whose base commit only the stash keeps alive ==="
I1="$TMP/i1"; mkrepo "$I1"
g -C "$I1/main" checkout --quiet -b tmp; echo O > "$I1/main/other.txt"; echo e >> "$I1/main/f"
g -C "$I1/main" add -A; g -C "$I1/main" commit --quiet -m tmpc
TMPC=$(g -C "$I1/main" rev-parse HEAD)
echo w >> "$I1/main/keep"; g -C "$I1/main" stash push --quiet
g -C "$I1/main" checkout --quiet main; g -C "$I1/main" branch --quiet -D tmp
st_backup "$I1" 'stash@{0}'
if ! grep -q other.txt "$I1/st.patch" && [ -z "$(g -C "$I1/main" for-each-ref --format='%(refname)' --contains "$TMPC" | grep -vx refs/stash)" ]; then
  ok "I1 evidence: other.txt is in the base commit only; no ref but refs/stash holds it; the patch omits it"
else
  notok "I1 evidence: unexpected fixture shape"
fi
expect "I1 stash base history unanchored" "$(run_case "$IMPL" "$I1/main" stash 'stash@{0}' land "$I1/st.patch")" \
  REFUSED "only the stash keeps them alive" "$TMPC"

echo
echo "=== IMPORTANT-2 ambient git-redirection variables (git exports these to every hook) ==="
E2="$TMP/e2"; mkrepo "$E2"
echo STAGED >> "$E2/wt/keep"; g -C "$E2/wt" add keep; g -C "$E2/wt" restore --worktree --source=HEAD keep
echo y >> "$E2/wt/f"; wt_backup "$E2"
if [ -n "$(g -C "$E2/wt" diff-index --cached HEAD)" ] && \
   [ -z "$(GIT_INDEX_FILE="$E2/main/.git/index" git -C "$E2/wt" diff-index --cached HEAD)" ]; then
  ok "I2 evidence: with GIT_INDEX_FILE=<main index> the worktree's staged-only change is invisible to git"
else
  notok "I2 evidence: GIT_INDEX_FILE did not redirect as expected"
fi
expect "I2 baseline (no ambient var)" "$(run_case "$IMPL" "$E2/main" worktree wt retire "$E2/wt.patch")" REFUSED \
  "keep: STAGED content differs"
expect "I2 ambient GIT_INDEX_FILE" \
  "$(GIT_INDEX_FILE="$E2/main/.git/index" run_case "$IMPL" "$E2/main" worktree wt retire "$E2/wt.patch")" REFUSED \
  "keep: STAGED content differs"
expect "I2 ambient GIT_DIR" \
  "$(GIT_DIR="$E2/main/.git" run_case "$IMPL" "$E2/main" worktree wt retire "$E2/wt.patch")" REFUSED \
  "keep: STAGED content differs"

echo
echo "=== MINOR-1 a tracked path literally named '\"q\"' (C-quote-shaped) ==="
Q1="$TMP/q1"; mkrepo "$Q1"
printf 'A\n' > "$Q1/main/\"q\""; printf 'q0\n' > "$Q1/main/q"
g -C "$Q1/main" add -A; g -C "$Q1/main" commit --quiet -m quoted; g -C "$Q1/wt" merge --quiet --ff-only main
printf 'S\n' > "$Q1/wt/\"q\""; g -C "$Q1/wt" add -- '"q"'; g -C "$Q1/wt" restore --worktree --source=HEAD -- '"q"'
printf 'S\n' > "$Q1/wt/q"; wt_backup "$Q1"
expect "MINOR-1 staged-only content of '\"q\"' (decoy 'q' holds the same bytes)" \
  "$(run_case "$IMPL" "$Q1/main" worktree wt retire "$Q1/wt.patch")" REFUSED '"q": STAGED content differs'

echo
echo "=== golden-good controls: the new checks must NOT refuse restorable work ==="
G1="$TMP/g1"; mkrepo "$G1"
echo c >> "$G1/wt/f"; g -C "$G1/wt" commit --quiet -am c; echo z >> "$G1/wt/keep"; wt_backup "$G1"
expect "G1 branch commit + tracked edit" "$(run_case "$IMPL" "$G1/main" worktree wt retire "$G1/wt.patch")" ALLOWED \
  "RESTORABILITY ORACLE passed"
G2="$TMP/g2"; mkrepo "$G2"
g -C "$G2/wt" checkout --quiet --detach; g -C "$G2/wt" checkout --quiet feat; echo z >> "$G2/wt/keep"; wt_backup "$G2"
expect "G2 detach + back (every reflog commit anchored)" \
  "$(run_case "$IMPL" "$G2/main" worktree wt retire "$G2/wt.patch")" ALLOWED
G3="$TMP/g3"; mkrepo "$G3"
echo w >> "$G3/main/keep"; g -C "$G3/main" stash push --quiet; st_backup "$G3" 'stash@{0}'
expect "G3 plain stash on a live branch" "$(run_case "$IMPL" "$G3/main" stash 'stash@{0}' land "$G3/st.patch")" ALLOWED
expect "G4 restorable worktree under ambient GIT_INDEX_FILE/GIT_DIR (no over-refusal)" \
  "$(GIT_INDEX_FILE="$G3/main/.git/index" GIT_DIR="$G3/main/.git" run_case "$IMPL" "$G1/main" worktree wt retire \
     "$G1/wt.patch")" ALLOWED

# ---------------------------------------------------------------------------
# Unit level (real tool): gap 5 + MINOR-2 + MINOR-4.
# ---------------------------------------------------------------------------
U5="$TMP/u5"; mkrepo "$U5"
echo untracked > "$U5/main/new.txt"; g -C "$U5/main" stash push --quiet -u
printf 'diff --git a/nope b/nope\ngarbage\n' > "$TMP/garbage.patch"
T2="$TMP/t2"; mkrepo "$T2"; echo z >> "$T2/wt/keep"; wt_backup "$T2"
unit() {  # IMPL -> prints NAME=VALUE lines
  python3 - "$1" "$U5" "$TMP" "$T2" <<'PYEOF'
import importlib.util, sys
impl, U5, T, T2 = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", impl)
cs = importlib.util.module_from_spec(spec); spec.loader.exec_module(cs)
# gap 5: a `stash -u` with only untracked content has tree == base tree, so a
# backup that does NOT apply leaves the scratch tree == the stash tree: only the
# apply-exit-code check can refuse it.
r = cs.restore_oracle_stash(U5 + "/main", "stash@{0}", T + "/garbage.patch")
print("G5_stash_garbage_backup=%s" % r[0])
print("G5_reason_names_apply=%s" % ("does NOT apply" in r[1]))
# MINOR-2: the backup file is swapped for garbage AFTER its hash was verified;
# the oracle must still apply the verified bytes.
orig = cs.restore_oracle_worktree
backup = T2 + "/wt.patch"
def swapped(path, head, backup_full, env=None):
    open(backup, "wb").write(b"diff --git a/nope b/nope\ngarbage\n")
    return orig(path, head, backup_full, env=env)
cs.restore_oracle_worktree = swapped
saved = open(backup, "rb").read()
h = cs.sha256_of_bytes(saved)
v, d = cs.derive_verdict("retire", h, backup, T2 + "/main", entry_kind="worktree", entry_id="wt")
open(backup, "wb").write(saved)
print("M2_tamper_after_hash=%s" % v)
PYEOF
}
echo
echo "=== unit level: gap 5 (stash apply rc) + MINOR-2 (TOCTOU) ==="
UNIT=$(unit "$IMPL" 2>&1)
for want in G5_stash_garbage_backup=False G5_reason_names_apply=True M2_tamper_after_hash=ALLOWED; do
  if grep -qx "$want" <<<"$UNIT"; then ok "unit $want"; else notok "unit expected $want; got: $UNIT"; fi
done

echo
echo "=== MINOR-4 a hanging clean filter is bounded by the git timeout (process group killed) ==="
T4="$TMP/t4"; mkrepo "$T4"
g -C "$T4/main" config filter.slow.clean 'sleep 25; cat'
g -C "$T4/main" config filter.slow.smudge cat
mkdir -p "$T4/main/.git/info"; echo 'f filter=slow' > "$T4/main/.git/info/attributes"
echo changed >> "$T4/wt/f"; cp /dev/null "$T4/wt.patch"
timeout_case() {  # IMPL -> "VERDICT<TAB>DETAIL<TAB>ELAPSED"
  local s e res
  s=$(date +%s)
  res=$(CUSTODY_SWEEP_GIT_TIMEOUT_S=3 run_case "$1" "$T4/main" worktree wt retire "$T4/wt.patch")
  e=$(date +%s)
  printf '%s\t%s\n' "$res" "$((e - s))"
}
TC=$(timeout_case "$IMPL")
TC_EL=${TC##*$'\t'}; TC_V=${TC%%$'\t'*}
if [ "$TC_V" = REFUSED ] && [ "$TC_EL" -lt 20 ]; then
  ok "MINOR-4 hanging filter -> REFUSED in ${TC_EL}s (< the filter's 25s sleep)"
else
  notok "MINOR-4 expected REFUSED in <20s, got $TC_V in ${TC_EL}s"
fi

# ---------------------------------------------------------------------------
# Guard viability: paired mutations.
# ---------------------------------------------------------------------------
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
# mut_allows NAME OLD NEW ROOT KIND ID ACTION BACKUP [ENVASSIGN]
#   the REAL tool refuses; the mutant must ALLOW (the check is load-bearing)
mut_allows() {
  local name="$1" old="$2" new="$3" root="$4" kind="$5" id="$6" action="$7" path="$8" envs="${9:-}"
  local m real mutant
  m=$(mk_mutant "$name" "$old" "$new")
  if [ -z "$m" ]; then notok "mutation $name: anchor not found ($(cat "$TMP/mut_$name.log"))"; return; fi
  real=$( [ -n "$envs" ] && export "${envs?}"; run_case "$IMPL" "$root" "$kind" "$id" "$action" "$path")
  mutant=$( [ -n "$envs" ] && export "${envs?}"; run_case "$m" "$root" "$kind" "$id" "$action" "$path")
  if [ "${real%%$'\t'*}" != REFUSED ]; then notok "mutation $name: REAL tool did not refuse (${real:0:200})"; return; fi
  if [ "${mutant%%$'\t'*}" = ALLOWED ]; then
    ok "mutation $name: caught -- mutant ALLOWS what the real tool refuses"
  else
    notok "mutation $name SURVIVED: mutant ${mutant:0:200}"
  fi
}

echo
echo "=== guard viability (paired mutations) ==="
mut_allows MB1_modules_check '                if subs:' '                if False:' \
  "$B1/main" worktree wt retire "$B1/wt.patch"
mut_allows MB2_reflog_unanchored '    if lost:
        problems.append' '    if False:
        problems.append' "$B2/main" worktree wt retire "$B2/wt.patch"
mut_allows MB3_per_worktree_ref_existence \
  '                            problems.append("%s: a per-worktree ref (deleted with the worktree)" % rel)' \
  '                            pass' "$B3m/main" worktree wt retire "$B3m/wt.patch"
mut_allows MB4_in_progress_whitelisted '            if name in _ADMIN_HARMLESS:' \
  '            if name in _ADMIN_HARMLESS or name in _ADMIN_IN_PROGRESS:' "$M3/main" worktree wt retire "$M3/wt.patch"
mut_allows MB5_unknown_entry_allowed '            if name not in _ADMIN_CHECKED:' '            if False:' \
  "$U3/main" worktree wt retire "$U3/wt.patch"
mut_allows MB6_history_gate '    if history_problems:' '    if False:' \
  "$B1/main" worktree wt retire "$B1/wt.patch"
mut_allows MI1_stash_history_check '    if lost:
        return ["%d commit(s)' '    if False:
        return ["%d commit(s)' "$I1/main" stash 'stash@{0}' land "$I1/st.patch"
mut_allows MI2_stash_counts_as_anchor '        if ref == "refs/stash" or ref.startswith(_PER_WORKTREE_REF_PREFIXES):' \
  '        if ref.startswith(_PER_WORKTREE_REF_PREFIXES):' "$I1/main" stash 'stash@{0}' land "$I1/st.patch"
mut_allows ME1_inherit_ambient_env '    child_env = _targeted_git_env() if env is None else env' \
  '    child_env = env' "$E2/main" worktree wt retire "$E2/wt.patch" "GIT_INDEX_FILE=$E2/main/.git/index"
mut_allows MM1_stdin_paths_unquoting \
  '        rc3, out3, err3 = _run_bytes(["git", "-C", path, "hash-object", "--"] + [p for p, _h in chunk], env=env)' \
  '        rc3, out3, err3 = _run_bytes(["git", "-C", path, "hash-object", "--stdin-paths"], env=env, input_bytes="".join(p + "\n" for p, _h in chunk).encode("utf-8", "surrogateescape"))' \
  "$Q1/main" worktree wt retire "$Q1/wt.patch"

echo
echo "=== guard viability: unit level ==="
unit_mut() {  # NAME OLD NEW CASE=WANTED_MUTANT_VALUE
  local m
  m=$(mk_mutant "$1" "$2" "$3")
  if [ -z "$m" ]; then notok "mutation $1: anchor not found ($(cat "$TMP/mut_$1.log"))"; return; fi
  if grep -qx "$4" <<<"$(unit "$m" 2>&1)"; then
    ok "mutation $1: caught -- mutant gives $4"
  else
    notok "mutation $1 SURVIVED: mutant did not give $4"
  fi
}
unit_mut MG5_stash_apply_rc_ignored '            if rc != 0:
                return False, ("the backup does NOT apply onto the stash' '            if False:
                return False, ("the backup does NOT apply onto the stash' G5_stash_garbage_backup=True
unit_mut MM2_oracle_rereads_path '                restorable, why = restore_oracle_worktree(live.get("path"), live.get("head"), backup_full, env=env)' \
  '                restorable, why = restore_oracle_worktree(live.get("path"), live.get("head"), os.path.abspath(full), env=env)' \
  M2_tamper_after_hash=REFUSED
for spec in 'MT1_kill_only_git|                os.killpg(pgid, _signal.SIGKILL)|                proc.kill()' \
            'MT2_no_timeout|        out, err = proc.communicate(input=input_bytes, timeout=_git_timeout_s())|        out, err = proc.communicate(input=input_bytes)'; do
  IFS='|' read -r name old new <<<"$spec"
  m=$(mk_mutant "$name" "$old" "$new")
  if [ -z "$m" ]; then notok "mutation $name: anchor not found"; continue; fi
  MC=$(timeout_case "$m"); MEL=${MC##*$'\t'}
  if [ "$MEL" -ge 20 ]; then
    ok "mutation $name: caught -- mutant took ${MEL}s (blocked on the hanging filter), real tool ${TC_EL}s"
  else
    notok "mutation $name SURVIVED: mutant took only ${MEL}s"
  fi
done

# ---------------------------------------------------------------------------
# Proof the refused states are REAL data loss (destroys the fixtures -- last).
# ---------------------------------------------------------------------------
echo
echo "=== evidence: performing the destructive action really loses the data ==="
gone() { ! g -C "$1" cat-file -e "$2" 2>/dev/null; }
expire_gc() { g -C "$1" reflog expire --expire=now --all; g -C "$1" gc --quiet --prune=now >/dev/null 2>&1; }
g -C "$B1/main" worktree remove --force --force "$B1/wt" >/dev/null 2>&1
if gone "$B1/sub" "$PRECIOUS" && gone "$B1/main" "$PRECIOUS" && [ ! -d "$(admin "$B1")" ]; then
  ok "B1 loss proven: after 'worktree remove --force' the PRECIOUS submodule commit exists nowhere"
else
  notok "B1 loss NOT reproduced"
fi
# T140 round-17 MINOR-3 (round-16 finding, fixed here): B2's proof used to
# share the loop below with B3, both proven via `expire_gc` (an explicit
# `reflog expire --expire=now --all` + `gc --prune=now`). For B2 specifically
# ORPHAN is anchored ONLY by a reflog entry (per the B2a evidence block
# above), so the EXPLICIT `--expire=now --all` step is, on its own, ALREADY
# sufficient to destroy it -- confirmed live: running it with "$B2/wt" still
# attached destroys ORPHAN even though `worktree remove` never ran. That
# confound meant the before/after comparison never isolated "removal caused
# the loss" for B2 (B1/B3/I1 do not share it: B1's loss needs no expire_gc
# at all, B3/I1's anchors are REFS not reflog entries, so an explicit reflog
# expire plays no role in destroying SAVED/TMPC). Fixed with a plain
# `gc --prune=now` (git's OWN default internal reflog-expire window is
# 30-90 days, so it does not expire a reflog entry created moments ago) for
# BOTH an explicit CONTROL step (worktree still present: ORPHAN must
# survive) and the actual proof step (worktree removed -- which deletes the
# admin dir's `logs/HEAD` file outright -- ORPHAN must now be gone): this
# isolates worktree removal itself as the cause, never the explicit expire.
gc_only() { g -C "$1" gc --quiet --prune=now >/dev/null 2>&1; }
gc_only "$B2/main"
if gone "$B2/main" "$ORPHAN"; then
  notok "B2 control FAILED: plain 'gc --prune=now' (no explicit reflog expire) already destroyed $ORPHAN with the" \
        "worktree still present -- the scenario's reflog-only anchoring assumption is wrong"
else
  ok "B2 control: with the worktree STILL present, plain 'gc --prune=now' (no explicit reflog expire) leaves" \
     "$ORPHAN intact"
fi
g -C "$B2/main" worktree remove --force --force "$B2/wt" >/dev/null 2>&1
gc_only "$B2/main"
if gone "$B2/main" "$ORPHAN"; then
  ok "B2 loss proven: commit $ORPHAN gone after 'worktree remove --force' + plain 'gc --prune=now' (removal alone," \
     "isolated from any explicit reflog expire, caused it)"
else
  notok "B2 loss NOT reproduced ($ORPHAN survives)"
fi
g -C "$B3/main" worktree remove --force --force "$B3/wt" >/dev/null 2>&1; expire_gc "$B3/main"
if gone "$B3/main" "$SAVED"; then ok "B3 loss proven: commit $SAVED gone after remove --force + reflog expire + gc"
else notok "B3 loss NOT reproduced ($SAVED survives)"; fi
g -C "$I1/main" stash drop --quiet; expire_gc "$I1/main"
if gone "$I1/main" "$TMPC"; then ok "I1 loss proven: the stash base commit $TMPC (other.txt) gone after drop + gc"
else notok "I1 loss NOT reproduced"; fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R15 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- retire/land now also refuse git"
  echo "    state deleted OUTSIDE the files (admin-dir submodule git dirs, own reflog, per-worktree refs,"
  echo "    in-progress operations, unanchored stash base history), ignore ambient git-redirection"
  echo "    variables, bound every git call, and every check is proven load-bearing by a mutation. ==="
  exit 0
else
  echo "=== R15 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
