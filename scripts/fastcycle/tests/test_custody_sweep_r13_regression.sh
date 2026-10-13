#!/bin/bash
# Purpose : T140 Round 13 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- round-12 independent review findings B-1 (the positive
#           RESTORABILITY ORACLE: assume-unchanged, skip-worktree, staged-vs-
#           worktree divergence in a worktree AND in a stash, lossy clean
#           filter), I-1 (gitignored files), I-2 (unmerged state, submodule
#           ignore=all config override, staged rename -- each with a paired
#           mutation), M-1 (symlinked --repo-root), M-2/M-3 (exit-code
#           contract documented consistently with the live code).
#
# Every case builds REAL throwaway git repositories under a temp dir (never
# this project's own repo, worktrees or stashes), creates the backup
# INDEPENDENTLY with plain git using the documented canonical option set,
# and runs the REAL tool's `verify-proposal`. Every REFUSED case asserts the
# verdict DETAIL names the intended check; every round-12 bypass case also
# proves, with a plain `git apply` round-trip, that the backup really DOES
# lose data (so a REFUSED here is a correct refusal, not an over-refusal).
# The golden-good controls prove the oracle does not over-refuse genuinely
# restorable work (exec bit, symlink, rename, fully-staged change, eol
# attribute, core.autocrlf, plain stash, fully-staged stash).
#
# Guard viability: each check is deleted/weakened in a throwaway copy of the
# tool and the SAME case is re-run -- the mutant must give the wrong answer.
# The oracle's own internals are also exercised directly (unit level) with
# backups that APPLY but do not restore, since the earlier byte-match check
# would otherwise shadow them end-to-end.
#
# Producer != Verifier (section 11.4.240): the bypass cases reproduce the
# round-12 reviewer's own scripts (scratchpad/adv/{adv.sh,st.sh,x.sh}), not
# the tool's selftest.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
gsub() { g -c protocol.file.allow=always "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)

fail=0
pass=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=1; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R13 regression guard: control needle -- tool + libs exist, git usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
command -v git >/dev/null || notok "control needle: git not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git present"

sha() { sha256sum "$1" | cut -d' ' -f1; }

run_case() {  # IMPL ROOT KIND ID ACTION BACKUP -> "VERDICT<TAB>DETAIL"
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

mk_repo() {
  local d="$1"
  mkdir -p "$d"
  g init --quiet "$d"
  printf 'a\nb\n' > "$d/t.txt"
  printf 'cfg=1\n' > "$d/local.properties"
  printf 'p\nq\n' > "$d/e.txt"
  g -C "$d" add -A
  g -C "$d" commit --quiet -m base
}
mk_linked() { g -C "$1" worktree add --quiet -b "br_$2" "$TMP/$2" >/dev/null 2>&1; }
canon_backup() { g -C "$1" diff "${CANON[@]}" HEAD > "$2"; }

# lossy REPO WT BACKUP FILE : 0 when a plain restore of BACKUP onto a fresh
# checkout of WT's HEAD does NOT reproduce FILE (i.e. the data really is lost)
lossy() {
  local fresh="$TMP/fresh.$RANDOM"
  g -C "$1" worktree add --quiet --detach "$fresh" "$(g -C "$2" rev-parse HEAD)" >/dev/null 2>&1 || return 1
  g -C "$fresh" apply "$3" >/dev/null 2>&1 || return 0
  ! cmp -s "$fresh/$4" "$2/$4"
}

R="$TMP/repo"
mk_repo "$R"

echo
echo "=== B-1.1 assume-unchanged edit (invisible to git diff) ==="
mk_linked "$R" a1
g -C "$TMP/a1" update-index --assume-unchanged local.properties
echo 'secret=XYZ' >> "$TMP/a1/local.properties"; echo c >> "$TMP/a1/t.txt"
canon_backup "$TMP/a1" "$TMP/a1.patch"
if ! grep -q secret "$TMP/a1.patch" && lossy "$R" "$TMP/a1" "$TMP/a1.patch" local.properties; then
  ok "B-1.1 evidence: the canonical backup omits the assume-unchanged edit; a plain restore LOSES it"
else
  notok "B-1.1 evidence: expected the backup to omit + lose the assume-unchanged edit"
fi
expect "B-1.1 assume-unchanged" "$(run_case "$IMPL" "$R" worktree a1 retire "$TMP/a1.patch")" REFUSED \
  "RESTORABILITY ORACLE" "local.properties: content differs"

echo
echo "=== B-1.1b skip-worktree edit ==="
mk_linked "$R" a2
g -C "$TMP/a2" update-index --skip-worktree local.properties
echo 'secret=XYZ' >> "$TMP/a2/local.properties"; echo c >> "$TMP/a2/t.txt"
canon_backup "$TMP/a2" "$TMP/a2.patch"
expect "B-1.1b skip-worktree" "$(run_case "$IMPL" "$R" worktree a2 retire "$TMP/a2.patch")" REFUSED \
  "RESTORABILITY ORACLE" "local.properties: content differs"

echo
echo "=== B-1.2 worktree: staged content differs from the worktree file ==="
mk_linked "$R" a3
echo STAGED_ONLY >> "$TMP/a3/t.txt"; g -C "$TMP/a3" add t.txt
g -C "$TMP/a3" restore --worktree --source=HEAD t.txt; echo other >> "$TMP/a3/e.txt"
canon_backup "$TMP/a3" "$TMP/a3.patch"
if ! grep -q STAGED_ONLY "$TMP/a3.patch" && g -C "$TMP/a3" show :t.txt | grep -q STAGED_ONLY; then
  ok "B-1.2 evidence: STAGED_ONLY lives only in the index; 'git diff HEAD' never carries it"
else
  notok "B-1.2 evidence: unexpected staged/backup shape"
fi
expect "B-1.2 worktree staged divergence" "$(run_case "$IMPL" "$R" worktree a3 retire "$TMP/a3.patch")" \
  REFUSED "RESTORABILITY ORACLE" "t.txt: STAGED content differs"

echo
echo "=== B-1.3 stash: the ^2 index parent holds staged-only content ==="
S="$TMP/repoS"
mk_repo "$S"
echo STAGED_ONLY >> "$S/t.txt"; g -C "$S" add t.txt
g -C "$S" restore --worktree --source=HEAD t.txt; echo w >> "$S/e.txt"
g -C "$S" stash push --quiet -m idx
g -C "$S" stash show -p "${CANON[@]}" 'stash@{0}' > "$TMP/st.patch"
if ! grep -q STAGED_ONLY "$TMP/st.patch" && g -C "$S" show 'stash@{0}^2:t.txt' | grep -q STAGED_ONLY; then
  ok "B-1.3 evidence: the stash's ^2 holds STAGED_ONLY; 'git stash show -p' omits it"
else
  notok "B-1.3 evidence: unexpected stash shape"
fi
expect "B-1.3 stash staged divergence" "$(run_case "$IMPL" "$S" stash 'stash@{0}' land "$TMP/st.patch")" \
  REFUSED "RESTORABILITY ORACLE" "t.txt: staged-only content"

echo
echo "=== B-1.4 lossy clean filter ==="
F="$TMP/repoF"
mk_repo "$F"
g -C "$F" config filter.strip.clean "sed 's/SECRET.*//'"
g -C "$F" config filter.strip.smudge cat
echo 'e.txt filter=strip' > "$F/.gitattributes"; g -C "$F" add .gitattributes; g -C "$F" commit --quiet -m attr
mk_linked "$F" a4
echo 'line SECRET=keepme' >> "$TMP/a4/e.txt"
canon_backup "$TMP/a4" "$TMP/a4.patch"
if ! grep -q keepme "$TMP/a4.patch" && lossy "$F" "$TMP/a4" "$TMP/a4.patch" e.txt; then
  ok "B-1.4 evidence: the backup holds the FILTERED content; a plain restore loses SECRET=keepme"
else
  notok "B-1.4 evidence: expected the clean filter to make the backup lossy"
fi
expect "B-1.4 lossy clean filter" "$(run_case "$IMPL" "$F" worktree a4 retire "$TMP/a4.patch")" REFUSED \
  "RESTORABILITY ORACLE" "e.txt: content differs"

echo
echo "=== I-1 gitignored file in a linked worktree ==="
I="$TMP/repoI"
mk_repo "$I"
echo '.env' > "$I/.gitignore"; g -C "$I" add .gitignore; g -C "$I" commit --quiet -m ign
mk_linked "$I" a5
echo 'API_KEY=zzz' > "$TMP/a5/.env"; echo c >> "$TMP/a5/t.txt"
canon_backup "$TMP/a5" "$TMP/a5.patch"
expect "I-1 ignored .env + tracked edit" "$(run_case "$IMPL" "$I" worktree a5 retire "$TMP/a5.patch")" REFUSED \
  "RESTORABILITY ORACLE" ".env: present LIVE but absent after restore"

echo
echo "=== golden-good controls: the oracle must NOT over-refuse restorable work ==="
G="$TMP/repoG"
mk_repo "$G"
mk_linked "$G" g1
echo c >> "$TMP/g1/t.txt"
canon_backup "$TMP/g1" "$TMP/g1.patch"
expect "G1 plain text change" "$(run_case "$IMPL" "$G" worktree g1 retire "$TMP/g1.patch")" ALLOWED \
  "RESTORABILITY ORACLE passed"
mk_linked "$G" g2
chmod +x "$TMP/g2/t.txt"; ln -s t.txt "$TMP/g2/lnk"; g -C "$TMP/g2" add -N lnk
canon_backup "$TMP/g2" "$TMP/g2.patch"
expect "G2 exec bit + intent-to-add symlink" "$(run_case "$IMPL" "$G" worktree g2 retire "$TMP/g2.patch")" ALLOWED
mk_linked "$G" g3
g -C "$TMP/g3" mv t.txt renamed.txt; echo c >> "$TMP/g3/renamed.txt"
canon_backup "$TMP/g3" "$TMP/g3.patch"
expect "G3 staged rename + further edit" "$(run_case "$IMPL" "$G" worktree g3 retire "$TMP/g3.patch")" ALLOWED
mk_linked "$G" g4
echo staged-and-live >> "$TMP/g4/e.txt"; g -C "$TMP/g4" add e.txt
canon_backup "$TMP/g4" "$TMP/g4.patch"
expect "G4 fully-staged change (index == worktree)" "$(run_case "$IMPL" "$G" worktree g4 retire "$TMP/g4.patch")" \
  ALLOWED
printf 'k.txt text eol=crlf\n' > "$G/.gitattributes"; printf 'k1\nk2\n' > "$G/k.txt"
g -C "$G" add -A; g -C "$G" commit --quiet -m crlfattr
mk_linked "$G" g5
printf 'k1\r\nK2\r\n' > "$TMP/g5/k.txt"
canon_backup "$TMP/g5" "$TMP/g5.patch"
expect "G5 eol=crlf attribute" "$(run_case "$IMPL" "$G" worktree g5 retire "$TMP/g5.patch")" ALLOWED
A="$TMP/repoA"
mk_repo "$A"
g -C "$A" config core.autocrlf true
mk_linked "$A" g6
if head -c 200 "$TMP/g6/t.txt" | grep -q $'\r'; then
  ok "G6 evidence: core.autocrlf=true checked the linked worktree out with CRLF"
else
  notok "G6 evidence: expected CRLF in the autocrlf checkout"
fi
printf 'a\r\nb CHANGED\r\n' > "$TMP/g6/t.txt"
canon_backup "$TMP/g6" "$TMP/g6.patch"
expect "G6 core.autocrlf=true repo (conversion config transferred)" \
  "$(run_case "$IMPL" "$A" worktree g6 retire "$TMP/g6.patch")" ALLOWED
S2="$TMP/repoS2"
mk_repo "$S2"
echo fully >> "$S2/t.txt"; g -C "$S2" add t.txt; echo w >> "$S2/e.txt"
g -C "$S2" stash push --quiet -m staged-and-unstaged
g -C "$S2" stash show -p "${CANON[@]}" 'stash@{0}' > "$TMP/s2.patch"
expect "G7 stash with a fully-staged + an unstaged change" \
  "$(run_case "$IMPL" "$S2" stash 'stash@{0}' land "$TMP/s2.patch")" ALLOWED "reproduces the stash tree"

echo
echo "=== I-2.1 unmerged (UU) merge-conflict worktree ==="
U="$TMP/repoU"
mk_repo "$U"
mk_linked "$U" x1
g -C "$U" checkout --quiet -b other; echo OTHER > "$U/t.txt"; g -C "$U" commit --quiet -am o
g -C "$U" checkout --quiet main
echo MINE > "$TMP/x1/t.txt"; g -C "$TMP/x1" commit --quiet -am mine
g -C "$TMP/x1" merge --quiet other >/dev/null 2>&1
if g -C "$TMP/x1" status --porcelain=v2 | grep -q '^u UU'; then
  ok "I-2.1 evidence: the worktree holds a real 'u UU' unmerged entry"
else
  notok "I-2.1 evidence: no unmerged entry was produced"
fi
canon_backup "$TMP/x1" "$TMP/x1.patch"
expect "I-2.1 unmerged worktree" "$(run_case "$IMPL" "$U" worktree x1 retire "$TMP/x1.patch")" REFUSED \
  "unresolved merge conflicts"

echo
echo "=== I-2.2 dirty submodule hidden by submodule.<name>.ignore=all in repo config ==="
SUBSRC="$TMP/subsrc"
mk_repo "$SUBSRC"
P="$TMP/repoP"
mk_repo "$P"
gsub -C "$P" submodule add --quiet "$SUBSRC" sm >/dev/null 2>&1
g -C "$P" commit --quiet -m addsub
g -C "$P" config submodule.sm.ignore all
mk_linked "$P" x2
gsub -C "$TMP/x2" submodule update --quiet --init >/dev/null 2>&1
echo dirty >> "$TMP/x2/sm/t.txt"; echo z >> "$TMP/x2/t.txt"
canon_backup "$TMP/x2" "$TMP/x2.patch"
if ! g -C "$TMP/x2" status --porcelain=v2 | grep -q ' sm$' \
   && g -C "$TMP/x2" status --porcelain=v2 --ignore-submodules=none | grep -q ' sm$'; then
  ok "I-2.2 evidence: a plain 'git status' hides the dirty submodule; --ignore-submodules=none shows it"
else
  notok "I-2.2 evidence: submodule.sm.ignore=all did not hide the submodule as expected"
fi
expect "I-2.2 dirty submodule under ignore=all" "$(run_case "$IMPL" "$P" worktree x2 retire "$TMP/x2.patch")" \
  REFUSED "changed submodule"

echo
echo "=== M-1 --repo-root given as a SYMLINK to a linked worktree ==="
mk_linked "$G" m1
echo c >> "$TMP/m1/t.txt"
canon_backup "$TMP/m1" "$TMP/m1.patch"
ln -s "$TMP/m1" "$TMP/link_m1"
expect "M-1 symlinked --repo-root, entry addressed by name" \
  "$(run_case "$IMPL" "$TMP/link_m1" worktree m1 retire "$TMP/m1.patch")" REFUSED "no longer resolves"
expect "M-1 symlinked --repo-root, entry addressed as MAIN" \
  "$(run_case "$IMPL" "$TMP/link_m1" worktree MAIN retire "$TMP/m1.patch")" REFUSED "MAIN worktree"

echo
echo "=== M-2/M-3 exit-code contract (live code == docstring == --help) ==="
mkdir -p "$TMP/notgit"
( cd "$TMP/notgit" && GIT_CEILING_DIRECTORIES="$TMP" python3 "$IMPL" propose --inventory /nonexistent/inv.json \
    --out "$TMP/m3a.json" >/dev/null 2>&1 ); RC1=$?
python3 "$IMPL" propose --inventory /nonexistent/inv.json --repo-root "$G" --out "$TMP/m3b.json" >/dev/null 2>&1; RC2=$?
if [ "$RC1" = 2 ] && [ "$RC2" = 2 ]; then
  ok "M-3 missing --inventory is rc=2 both outside a checkout (repo root resolved first) and inside one"
else
  notok "M-3 rc outside=$RC1 inside=$RC2 (both expected 2)"
fi
if python3 - "$IMPL" <<'PYEOF'
import ast, sys
doc = ast.get_docstring(ast.parse(open(sys.argv[1]).read()))
assert "BLIND: a required input file" not in doc, "stale exit-4 claim still present"
assert "--determinism-check` only" in doc, "exit-4 scope not documented"
assert "MUST GATE ON THE EXIT CODE" in doc, "M-2 consumer contract missing from docstring"
PYEOF
then
  ok "M-2/M-3 docstring: stale 'missing --inventory is BLIND exit 4' removed; exit-code gating documented"
else
  notok "M-2/M-3 docstring check failed"
fi
HELP=$(python3 "$IMPL" --help 2>&1)
if [[ "$HELP" == *"MUST gate on the exit"* && "$HELP" == *"usage"* ]]; then
  ok "M-2 --help itself states consumers must gate on the exit code"
else
  notok "M-2 --help does not carry the exit-code gating contract"
fi

# ---------------------------------------------------------------------------
# Oracle internals, exercised directly: backups that APPLY but do NOT restore
# (the end-to-end byte-match check would otherwise shadow these branches).
# ---------------------------------------------------------------------------
oracle_unit() {  # IMPL -> prints one line per case: NAME=True|False
  python3 - "$1" "$G" "$TMP" "$S2" <<'PYEOF'
import importlib.util, sys
impl, G, T, S2 = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", impl)
cs = importlib.util.module_from_spec(spec); spec.loader.exec_module(cs)
head = lambda p: cs._run(["git", "-C", p, "rev-parse", "HEAD"])[1].strip()
# U1: worktree g1 (one appended line) vs a backup appending a DIFFERENT line
open(T + "/u1.patch", "wb").write(open(T + "/g1.patch", "rb").read().replace(b"+c\n", b"+X\n"))
print("U1_worktree_wrong_content=%s" % cs.restore_oracle_worktree(T + "/g1", head(T + "/g1"), T + "/u1.patch")[0])
# U2: empty backup on a dirty worktree (applies trivially, restores nothing)
open(T + "/u2.patch", "wb").write(b"")
print("U2_worktree_empty_backup=%s" % cs.restore_oracle_worktree(T + "/g1", head(T + "/g1"), T + "/u2.patch")[0])
# U3: garbage backup (does not apply)
open(T + "/u3.patch", "wb").write(b"diff --git a/nope b/nope\ngarbage\n")
print("U3_worktree_garbage=%s" % cs.restore_oracle_worktree(T + "/g1", head(T + "/g1"), T + "/u3.patch")[0])
# U4: the correct backup (control: must be True)
print("U4_worktree_correct=%s" % cs.restore_oracle_worktree(T + "/g1", head(T + "/g1"), T + "/g1.patch")[0])
# U5: stash -- a backup that applies to the base but yields another tree
open(T + "/u5.patch", "wb").write(open(T + "/s2.patch", "rb").read().replace(b"+fully\n", b"+FULLY\n"))
print("U5_stash_wrong_tree=%s" % cs.restore_oracle_stash(S2, "stash@{0}", T + "/u5.patch")[0])
print("U6_stash_correct=%s" % cs.restore_oracle_stash(S2, "stash@{0}", T + "/s2.patch")[0])
# U7: garbage backup against a CLEAN worktree -- only the apply-exit-code
# check can refuse it (live == a fresh HEAD checkout either way)
print("U7_clean_worktree_garbage=%s" % cs.restore_oracle_worktree(T + "/g0", head(T + "/g0"), T + "/u3.patch")[0])
# U8: no room for a full scratch checkout -> cannot prove -> refuse
import collections, os, tempfile
real_statvfs = os.statvfs
os.statvfs = lambda _p: collections.namedtuple("SV", "f_bavail f_frsize")(1, 1)
print("U8_no_scratch_space=%s" % cs.restore_oracle_worktree(T + "/g1", head(T + "/g1"), T + "/g1.patch")[0])
os.statvfs = real_statvfs
# U9: the scratch dir would land INSIDE the worktree under test -> refuse
tempfile.tempdir = T + "/g0"
u9 = cs.restore_oracle_worktree(T + "/g0", head(T + "/g0"), T + "/u2.patch")
print("U9_scratch_inside_worktree=%s" % u9[0])
# without the location check the snapshot comparison still refuses (the
# scratch files show up as live-only) -- the reason is what discriminates
print("U9_reason_named=%s" % ("would sit inside the worktree" in u9[1]))
tempfile.tempdir = None
PYEOF
}
echo
echo "=== oracle internals (unit level, real tool) ==="
mk_linked "$G" g0   # a CLEAN linked worktree (HEAD checkout, nothing changed)
UNIT=$(oracle_unit "$IMPL" 2>&1)
for want in U1_worktree_wrong_content=False U2_worktree_empty_backup=False U3_worktree_garbage=False \
            U4_worktree_correct=True U5_stash_wrong_tree=False U6_stash_correct=True \
            U7_clean_worktree_garbage=False U8_no_scratch_space=False U9_scratch_inside_worktree=False \
            U9_reason_named=True; do
  if grep -qx "$want" <<<"$UNIT"; then ok "oracle unit $want"; else notok "oracle unit expected $want; got: $UNIT"; fi
done

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

# mut_e2e NAME OLD NEW ROOT KIND ID ACTION BACKUP WANT [DETAIL]
#   WANT=ALLOWED  : mutant must ALLOW what the real tool refuses (naming DETAIL)
#   WANT=REFUSED  : mutant must REFUSE what the real tool allows
#   WANT=DETAIL   : mutant still refuses, but no longer for reason DETAIL
mut_e2e() {
  local name="$1" old="$2" new="$3" root="$4" kind="$5" id="$6" action="$7" path="$8" want="$9" det="${10:-}"
  local m real mutant
  m=$(mk_mutant "$name" "$old" "$new")
  if [ -z "$m" ]; then notok "mutation $name: anchor not found ($(cat "$TMP/mut_$name.log"))"; return; fi
  real=$(run_case "$IMPL" "$root" "$kind" "$id" "$action" "$path")
  mutant=$(run_case "$m" "$root" "$kind" "$id" "$action" "$path")
  local rv="${real%%$'\t'*}" rd="${real#*$'\t'}" mv="${mutant%%$'\t'*}" md="${mutant#*$'\t'}"
  case "$want" in
    ALLOWED|DETAIL)
      if [ "$rv" != REFUSED ] || { [ -n "$det" ] && [[ "$rd" != *"$det"* ]]; }; then
        notok "mutation $name: REAL tool did not refuse naming '$det' ($rv: ${rd:0:200})"; return
      fi ;;
    REFUSED)
      if [ "$rv" != ALLOWED ]; then notok "mutation $name: REAL tool did not allow ($rv: ${rd:0:200})"; return; fi ;;
  esac
  if [ "$want" = DETAIL ]; then
    if [ "$mv" = REFUSED ] && [[ "$md" != *"$det"* ]]; then
      ok "mutation $name: caught -- mutant's refusal no longer comes from this check ($mv: ${md:0:80}...)"
    else
      notok "mutation $name SURVIVED: mutant $mv ($md)"
    fi
  elif [ "$mv" = "$want" ]; then
    ok "mutation $name: caught -- mutant says $mv, real tool says $rv"
  else
    notok "mutation $name SURVIVED: mutant says $mv (${md:0:200})"
  fi
}

echo
echo "=== guard viability (paired mutations) ==="
GATE_OLD='    if not restorable:'
GATE_NEW='    if False:'
mut_e2e MO1a_oracle_gate_assume "$GATE_OLD" "$GATE_NEW" "$R" worktree a1 retire "$TMP/a1.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO1b_oracle_gate_skipwt "$GATE_OLD" "$GATE_NEW" "$R" worktree a2 retire "$TMP/a2.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO1c_oracle_gate_filter "$GATE_OLD" "$GATE_NEW" "$F" worktree a4 retire "$TMP/a4.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO1d_oracle_gate_ignored "$GATE_OLD" "$GATE_NEW" "$I" worktree a5 retire "$TMP/a5.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO1e_oracle_gate_wt_staged "$GATE_OLD" "$GATE_NEW" "$R" worktree a3 retire "$TMP/a3.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO1f_oracle_gate_stash_staged "$GATE_OLD" "$GATE_NEW" "$S" stash 'stash@{0}' land "$TMP/st.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO2_tree_compare_blind '        if lv == rv:
            continue' '        if True:
            continue' "$R" worktree a1 retire "$TMP/a1.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO3_snapshot_skips_hidden '                if not rel and ent.name == ".git":' \
    '                if ent.name.startswith("."):' "$I" worktree a5 retire "$TMP/a5.patch" ALLOWED "RESTORABILITY ORACLE"
mut_e2e MO4_wt_index_check '        if idx_problems:' '        if False:' \
    "$R" worktree a3 retire "$TMP/a3.patch" ALLOWED "STAGED content differs"
mut_e2e MO5_wt_index_hash_compare '            if h_live != h_index:' '            if False:' \
    "$R" worktree a3 retire "$TMP/a3.patch" ALLOWED "STAGED content differs"
mut_e2e MO6_stash_index_only '        if index_only:' '        if False:' \
    "$S" stash 'stash@{0}' land "$TMP/st.patch" ALLOWED "staged-only content"
mut_e2e MO7_no_config_transfer '    pairs = list(conv_pairs) + list(_SCRATCH_PINNED_CONFIG)' \
    '    pairs = list(_SCRATCH_PINNED_CONFIG)' "$A" worktree g6 retire "$TMP/g6.patch" REFUSED
mut_e2e MO8_rename_blob_exempt ' or h_index in head_side:' ':' \
    "$G" worktree g3 retire "$TMP/g3.patch" REFUSED
mut_e2e MO9_ita_visible '"--ita-invisible-in-index", ' '' \
    "$G" worktree g2 retire "$TMP/g2.patch" REFUSED
mut_e2e MI1_has_unmerged_check '    if live.get("has_unmerged"):' '    if False:' \
    "$U" worktree x1 retire "$TMP/x1.patch" DETAIL "unresolved merge conflicts"
mut_e2e MI2_ignore_submodules_none '"--untracked-files=all", "--ignore-submodules=none"]' '"--untracked-files=all"]' \
    "$P" worktree x2 retire "$TMP/x2.patch" DETAIL "changed submodule"
mut_e2e MI3_rename_counter '            i += 1  # a rename' '            pass  # a rename' \
    "$G" worktree g3 retire "$TMP/g3.patch" REFUSED
mut_e2e MM1_symlink_realpath '    return os.path.realpath(a) == os.path.realpath(b)' \
    '    return os.path.abspath(a) == os.path.abspath(b)' "$TMP/link_m1" worktree m1 retire "$TMP/m1.patch" ALLOWED \
    "no longer resolves"

echo
echo "=== guard viability: oracle internals (unit level) ==="
unit_mut() {  # NAME OLD NEW CASE=WANTED_MUTANT_VALUE
  local m
  m=$(mk_mutant "$1" "$2" "$3")
  if [ -z "$m" ]; then notok "mutation $1: anchor not found ($(cat "$TMP/mut_$1.log"))"; return; fi
  if grep -qx "$4" <<<"$(oracle_unit "$m" 2>&1)"; then
    ok "mutation $1: caught -- mutant gives $4"
  else
    notok "mutation $1 SURVIVED: mutant did not give $4"
  fi
}
unit_mut MU1_stash_tree_compare '        if got != tree:' '        if False:' U5_stash_wrong_tree=True
unit_mut MU2_apply_rc_ignored '            if rc != 0:
                return False, ("the backup does NOT apply onto a fresh checkout' \
    '            if False:
                return False, ("the backup does NOT apply onto a fresh checkout' U7_clean_worktree_garbage=True
unit_mut MU4_space_check '        if not space:' '        if False:' U8_no_scratch_space=True
unit_mut MU5_scratch_inside_check '            if os.path.realpath(tmp).startswith(real_top + os.sep):' \
    '            if False:' U9_reason_named=False
unit_mut MU3_problems_ignored '        if problems:
            return False, ("%d path(s) differ' '        if False:
            return False, ("%d path(s) differ' U1_worktree_wrong_content=True

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R13 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- a land/retire verdict now"
  echo "    requires a POSITIVE restorability proof; assume-unchanged/skip-worktree/staged-divergence"
  echo "    (worktree + stash)/lossy-filter/ignored-file cases are refused, restorable work is not,"
  echo "    and every check is proven load-bearing by a paired mutation. ==="
  exit 0
else
  echo "=== R13 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
