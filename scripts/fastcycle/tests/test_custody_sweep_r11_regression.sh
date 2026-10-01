#!/bin/bash
# Purpose : T140 Round 11 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- findings B1 (data-safety: destructive verdicts on backups
#           that cannot restore the work), B2 (no real test reached the
#           safety checks) and I6 (one non-UTF-8 byte crashed inventory).
#
# Every case below builds REAL, throwaway git repositories under a temp
# dir (never this project's own repo, worktrees or stashes), creates the
# backup INDEPENDENTLY with plain git using the documented canonical
# option set (CANONICAL_PATCH_OPTS in custody_sweep.py's docstring -- the
# contract an operator follows), and runs the REAL tool's
# `verify-proposal` with ABSOLUTE backup paths, so every case genuinely
# reaches the check it names. The REFUSED cases assert the verdict DETAIL
# names the intended check -- the round-10 reviewer found the old
# golden-bad fixture was refused for an unrelated reason (a path that does
# not exist on this host), proving nothing about the hash comparison.
#
# The ALLOWED cases additionally prove RESTORABILITY: the backup is
# applied with `git apply` onto a fresh checkout of HEAD and the result is
# byte-compared against the live files (the property B1 was really about:
# "ALLOWED" must mean "this backup can bring the work back").
#
# Guard viability: each safety check is deleted/weakened in a throwaway
# copy of the tool and the SAME case is re-run -- the mutant must give
# the wrong answer, the real tool the right one.
#
# Producer != Verifier (section 11.4.240): the cases and mutations are
# derived from the round-10 reviewer's findings text and reproductions,
# not from custody_sweep.py's own selftest.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

# Hermetic git: no system/global config, no inherited repo redirection.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c core.autocrlf=false -c init.defaultBranch=main "$@"; }
# protocol.file.allow is needed ONLY for local submodule setup.
gsub() { g -c protocol.file.allow=always "$@"; }

CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)

fail=0
pass=0
failx() { fail=1; }
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { failx; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R11 regression guard: control needle -- tool + libs exist, git usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do
  [ -f "$p" ] || notok "control needle: $p not found"
done
command -v git >/dev/null || notok "control needle: git not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git present"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
sha() { sha256sum "$1" | cut -d' ' -f1; }

# run_case IMPL ROOT KIND ID ACTION HASH PATH -> prints "VERDICT<TAB>DETAIL"
run_case() {
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" hash="$6" path="$7"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json"
  python3 - "$pj" "$kind" "$id" "$action" "$hash" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h or None, "backup_artifact_path": path or None}, open(p, "w"))
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

# expect NAME RESULT VERDICT [DETAIL_SUBSTRING]
expect() {
  local name="$1" res="$2" want="$3" sub="${4:-}"
  local got="${res%%$'\t'*}" det="${res#*$'\t'}"
  if [ "$got" = "$want" ] && { [ -z "$sub" ] || [[ "$det" == *"$sub"* ]]; }; then
    ok "$name -> $got${sub:+ (detail names: $sub)}"
  else
    notok "$name: expected $want${sub:+ naming \"$sub\"}, got $got ($det)"
  fi
}

# mk_repo DIR : commits text.txt, crlf.txt (CRLF bytes), bin.dat (binary)
mk_repo() {
  local d="$1"
  mkdir -p "$d"
  g init --quiet "$d"
  printf 'line one\nline two\n' > "$d/text.txt"
  printf 'crlf one\r\ncrlf two\r\n' > "$d/crlf.txt"
  printf '\x00\x01\x02\xff\xfe binary \x00\x10' > "$d/bin.dat"
  g -C "$d" add -A
  g -C "$d" commit --quiet -m "base"
}

# mk_linked REPO NAME -> linked worktree at $TMP/NAME (entry_id = NAME)
mk_linked() { g -C "$1" worktree add --quiet -b "br_$2" "$TMP/$2" >/dev/null 2>&1; }

canon_backup() { g -C "$1" diff "${CANON[@]}" HEAD > "$2"; }

# restore_matches REPO WORKTREE BACKUP FILE... : apply BACKUP onto a fresh
# checkout of WORKTREE's HEAD and byte-compare each FILE with the live one.
restore_matches() {
  local repo="$1" wt="$2" backup="$3"
  shift 3
  local fresh
  fresh="$TMP/restore.$RANDOM"
  g -C "$repo" worktree add --quiet --detach "$fresh" "$(g -C "$wt" rev-parse HEAD)" >/dev/null 2>&1 || return 1
  g -C "$fresh" apply "$backup" >/dev/null 2>&1 || return 1
  local f
  for f in "$@"; do
    cmp -s "$fresh/$f" "$wt/$f" || return 1
  done
  return 0
}

# ---------------------------------------------------------------------------
# Repo A: plain cases (text, binary, CRLF, wrong-hash, stale, untracked,
# missing entry, MAIN).
# ---------------------------------------------------------------------------
A="$TMP/repoA"
mk_repo "$A"

echo
echo "=== B2/C1: golden-good text change in a LINKED worktree -> ALLOWED and restorable ==="
mk_linked "$A" wt_text
printf 'line one\nline two CHANGED\n' > "$TMP/wt_text/text.txt"
canon_backup "$TMP/wt_text" "$TMP/b_text.patch"
R=$(run_case "$IMPL" "$A" worktree wt_text retire "$(sha "$TMP/b_text.patch")" "$TMP/b_text.patch")
expect "C1 text golden-good" "$R" ALLOWED
if restore_matches "$A" "$TMP/wt_text" "$TMP/b_text.patch" text.txt; then
  ok "C1 restorability: backup re-applied onto fresh HEAD reproduces text.txt byte-for-byte"
else
  notok "C1 restorability: backup did NOT restore text.txt"
fi

echo
echo "=== B1 scenario 1: binary file change ==="
mk_linked "$A" wt_bin
printf '\x00\x09\x08 CHANGED binary \xff\x00\x01' > "$TMP/wt_bin/bin.dat"
canon_backup "$TMP/wt_bin" "$TMP/b_bin_good.patch"
g -C "$TMP/wt_bin" diff HEAD > "$TMP/b_bin_lossy.patch"   # the pre-round-11 convention
if grep -q "Binary files" "$TMP/b_bin_lossy.patch"; then
  ok "B1.1 evidence: a plain 'git diff HEAD' backup holds only 'Binary files ... differ' (no content)"
else
  notok "B1.1 evidence: expected the plain diff to be content-free for a binary file"
fi
R=$(run_case "$IMPL" "$A" worktree wt_bin retire "$(sha "$TMP/b_bin_lossy.patch")" "$TMP/b_bin_lossy.patch")
expect "B1.1 lossy 'Binary files differ' backup" "$R" REFUSED "freshly re-derived LIVE"
R=$(run_case "$IMPL" "$A" worktree wt_bin retire "$(sha "$TMP/b_bin_good.patch")" "$TMP/b_bin_good.patch")
expect "B1.1 faithful --binary backup" "$R" ALLOWED
if restore_matches "$A" "$TMP/wt_bin" "$TMP/b_bin_good.patch" bin.dat; then
  ok "B1.1 restorability: the --binary backup restores bin.dat byte-for-byte"
else
  notok "B1.1 restorability: the --binary backup did NOT restore bin.dat"
fi

echo
echo "=== B1 scenario 2: CRLF file change ==="
mk_linked "$A" wt_crlf
printf 'crlf one\r\ncrlf two CHANGED\r\n' > "$TMP/wt_crlf/crlf.txt"
canon_backup "$TMP/wt_crlf" "$TMP/b_crlf_good.patch"
tr -d '\r' < "$TMP/b_crlf_good.patch" > "$TMP/b_crlf_stripped.patch"
R=$(run_case "$IMPL" "$A" worktree wt_crlf retire "$(sha "$TMP/b_crlf_stripped.patch")" "$TMP/b_crlf_stripped.patch")
expect "B1.2 CR-stripped backup" "$R" REFUSED "freshly re-derived LIVE"
R=$(run_case "$IMPL" "$A" worktree wt_crlf retire "$(sha "$TMP/b_crlf_good.patch")" "$TMP/b_crlf_good.patch")
expect "B1.2 faithful CRLF backup (was REFUSED forever pre-fix)" "$R" ALLOWED
if restore_matches "$A" "$TMP/wt_crlf" "$TMP/b_crlf_good.patch" crlf.txt; then
  ok "B1.2 restorability: the faithful backup restores crlf.txt byte-for-byte (CRs intact)"
else
  notok "B1.2 restorability: faithful CRLF backup did NOT restore crlf.txt"
fi

echo
echo "=== B2: wrong hash on an existing, otherwise-matching backup ==="
R=$(run_case "$IMPL" "$A" worktree wt_text retire "$(printf '0%.0s' $(seq 64))" "$TMP/b_text.patch")
expect "B2 wrong-hash" "$R" REFUSED "does not match the real sha256"

echo
echo "=== B2: stale backup (live content changed after the backup) ==="
mk_linked "$A" wt_stale
printf 'line one\nline two v1\n' > "$TMP/wt_stale/text.txt"
canon_backup "$TMP/wt_stale" "$TMP/b_stale.patch"
printf 'line one\nline two v2 (after backup)\n' > "$TMP/wt_stale/text.txt"
R=$(run_case "$IMPL" "$A" worktree wt_stale retire "$(sha "$TMP/b_stale.patch")" "$TMP/b_stale.patch")
expect "B2 stale backup" "$R" REFUSED "freshly re-derived LIVE"

echo
echo "=== B2: untracked file in the worktree ==="
mk_linked "$A" wt_untr
printf 'line one\nline two U\n' > "$TMP/wt_untr/text.txt"
printf 'not in any patch\n' > "$TMP/wt_untr/new_untracked.txt"
canon_backup "$TMP/wt_untr" "$TMP/b_untr.patch"
R=$(run_case "$IMPL" "$A" worktree wt_untr retire "$(sha "$TMP/b_untr.patch")" "$TMP/b_untr.patch")
expect "B2 untracked worktree" "$R" REFUSED "untracked content"

echo
echo "=== B2: entry no longer exists ==="
R=$(run_case "$IMPL" "$A" worktree wt_never_existed retire "$(sha "$TMP/b_text.patch")" "$TMP/b_text.patch")
expect "B2 missing worktree entry" "$R" REFUSED "no longer resolves"

echo
echo "=== B1 scenario 5: the MAIN checkout ==="
printf 'line one\nline two MAIN EDIT\n' > "$A/text.txt"
canon_backup "$A" "$TMP/b_main.patch"
R=$(run_case "$IMPL" "$A" worktree MAIN retire "$(sha "$TMP/b_main.patch")" "$TMP/b_main.patch")
expect "B1.5 retire MAIN (root = main)" "$R" REFUSED "MAIN worktree"
# --repo-root is a LINKED worktree: the real main worktree is no longer
# called "MAIN" (it gets its basename) -- must still be refused.
R=$(run_case "$IMPL" "$TMP/wt_text" worktree repoA retire "$(sha "$TMP/b_main.patch")" "$TMP/b_main.patch")
expect "B1.5 retire the main worktree addressed by basename (root = linked)" "$R" REFUSED "MAIN worktree"
# (main stays dirty: the M6* mutations below re-use this exact state)

echo
echo "=== B1 sibling: detached worktree whose commit is reachable from no ref ==="
g -C "$A" worktree add --quiet --detach "$TMP/wt_det" >/dev/null 2>&1
printf 'committed only on a detached HEAD\n' > "$TMP/wt_det/det_only.txt"
g -C "$TMP/wt_det" add det_only.txt
g -C "$TMP/wt_det" commit --quiet -m "detached-only commit"
printf 'line one\nline two DET\n' > "$TMP/wt_det/text.txt"
canon_backup "$TMP/wt_det" "$TMP/b_det.patch"
R=$(run_case "$IMPL" "$A" worktree wt_det retire "$(sha "$TMP/b_det.patch")" "$TMP/b_det.patch")
expect "B1 detached unreachable HEAD" "$R" REFUSED "DETACHED HEAD"

# ---------------------------------------------------------------------------
# Stash cases (B1 scenario 3 + B2 stash-resolution).
# ---------------------------------------------------------------------------
S="$TMP/repoS"
mk_repo "$S"
echo
echo "=== B1 scenario 3: 'git stash push -u' (untracked files in the ^3 parent) ==="
printf 'line one\nline two STASH-U\n' > "$S/text.txt"
printf 'untracked, lives only in stash^3\n' > "$S/only_in_stash.txt"
g -C "$S" stash push --quiet -u -m "with untracked" >/dev/null
printf 'line one\nline two PLAIN STASH\n' > "$S/text.txt"
g -C "$S" stash push --quiet -m "plain" >/dev/null
# now stash@{0} = plain, stash@{1} = -u
g -C "$S" stash show -p "${CANON[@]}" 'stash@{1}' > "$TMP/b_stash_u.patch"
if ! grep -q only_in_stash "$TMP/b_stash_u.patch"; then
  ok "B1.3 evidence: 'git stash show -p' omits the -u stash's untracked file"
else
  notok "B1.3 evidence: expected the untracked file to be missing from stash show -p"
fi
R=$(run_case "$IMPL" "$S" stash 'stash@{1}' land "$(sha "$TMP/b_stash_u.patch")" "$TMP/b_stash_u.patch")
expect "B1.3 land a -u stash" "$R" REFUSED "untracked content"

g -C "$S" stash show -p "${CANON[@]}" 'stash@{0}' > "$TMP/b_stash_plain.patch"
R=$(run_case "$IMPL" "$S" stash 'stash@{0}' land "$(sha "$TMP/b_stash_plain.patch")" "$TMP/b_stash_plain.patch")
expect "B2 stash golden-good (plain stash, faithful backup)" "$R" ALLOWED
FRESH_S="$TMP/restore_stash"
g -C "$S" worktree add --quiet --detach "$FRESH_S" "$(g -C "$S" rev-parse 'stash@{0}^1')" >/dev/null 2>&1
if g -C "$FRESH_S" apply "$TMP/b_stash_plain.patch" >/dev/null 2>&1 \
    && g -C "$FRESH_S" diff --quiet 'stash@{0}' -- .; then
  ok "B2 stash restorability: backup re-applied onto stash^1 equals the stash tree"
else
  notok "B2 stash restorability: backup did NOT reproduce the stash tree"
fi
R=$(run_case "$IMPL" "$S" stash 'stash@{99}' land "$(sha "$TMP/b_stash_plain.patch")" "$TMP/b_stash_plain.patch")
expect "B2 stash ref that does not resolve" "$R" REFUSED "no longer resolves"

# ---------------------------------------------------------------------------
# Submodule case (B1 scenario 4).
# ---------------------------------------------------------------------------
echo
echo "=== B1 scenario 4: uncommitted changes INSIDE a submodule ==="
SUBSRC="$TMP/subsrc"
mk_repo "$SUBSRC"
P="$TMP/repoP"
mk_repo "$P"
gsub -C "$P" submodule add --quiet "$SUBSRC" sub >/dev/null 2>&1
g -C "$P" commit --quiet -m "add submodule"
mk_linked "$P" wt_sub
gsub -C "$TMP/wt_sub" submodule update --quiet --init >/dev/null 2>&1
printf 'submodule-internal uncommitted edit\n' >> "$TMP/wt_sub/sub/text.txt"
canon_backup "$TMP/wt_sub" "$TMP/b_sub.patch"
if grep -q -- "-dirty" "$TMP/b_sub.patch" && ! grep -q "submodule-internal" "$TMP/b_sub.patch"; then
  ok "B1.4 evidence: the parent patch records only 'Subproject commit ...-dirty', not the edit"
else
  notok "B1.4 evidence: unexpected parent patch shape for a dirty submodule: $(head -c 300 "$TMP/b_sub.patch")"
fi
R=$(run_case "$IMPL" "$P" worktree wt_sub retire "$(sha "$TMP/b_sub.patch")" "$TMP/b_sub.patch")
expect "B1.4 retire a worktree with a dirty submodule" "$R" REFUSED "submodule"

# ---------------------------------------------------------------------------
# I6: a non-UTF-8 byte anywhere no longer crashes inventory.
# ---------------------------------------------------------------------------
echo
echo "=== I6: non-UTF-8 bytes in a diff, a commit subject and a stash message ==="
U="$TMP/repoU"
mk_repo "$U"
mk_linked "$U" wt_bytes
printf 'line one\nline two \xff\xfe\xc3\x28 latin1 caf\xe9\n' > "$TMP/wt_bytes/text.txt"
printf 'x\xffy\n' > "$U/bin2.txt"
g -C "$U" add bin2.txt
g -C "$U" commit --quiet -m "$(printf 'subject \xff\xfe non-utf8')" >/dev/null 2>&1
printf 'line one\nline two stash \xe9\n' > "$U/text.txt"
g -C "$U" stash push --quiet -m "$(printf 'msg \xff non-utf8')" >/dev/null 2>&1
python3 "$IMPL" inventory --repo-root "$U" --backup-root "$TMP/nobackups" --out "$TMP/inv_u.json" >"$TMP/inv_u.err" 2>&1
RC=$?
if [ "$RC" = 0 ] && python3 - "$TMP/inv_u.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert "internal_error" not in d, d
ents = {e["entry_id"]: e for e in d["entries"]}
assert ents["wt_bytes"]["dirty_file_hash"]["status"] == "dirty", ents["wt_bytes"]
assert ents["stash@{0}"]["dirty_file_hash"]["status"] == "dirty", ents["stash@{0}"]
PYEOF
then
  ok "I6 inventory survives non-UTF-8 diff/subject/stash message (rc=0, entries measured)"
else
  notok "I6 inventory: rc=$RC $(head -c 400 "$TMP/inv_u.err")"
fi

# ---------------------------------------------------------------------------
# End-to-end inventory -> propose with the documented backup layout.
# ---------------------------------------------------------------------------
echo
echo "=== B1/B2: inventory -> propose end-to-end (backup layout) ==="
E="$TMP/repoE"
mk_repo "$E"
mk_linked "$E" wt_e2e
printf '\x00\x07 e2e binary \xff' > "$TMP/wt_e2e/bin.dat"
printf 'crlf one\r\ne2e\r\n' > "$TMP/wt_e2e/crlf.txt"
BR="$TMP/backups_e2e"
mkdir -p "$BR/backup_worktrees/wt_e2e" "$BR/backup_worktrees/MAIN"
canon_backup "$TMP/wt_e2e" "$BR/backup_worktrees/wt_e2e/tracked.patch"
printf 'line one\nmain edit\n' > "$E/text.txt"
canon_backup "$E" "$BR/backup_worktrees/MAIN/tracked.patch"
python3 "$IMPL" inventory --repo-root "$E" --backup-root "$BR" --out "$TMP/inv_e.json" >/dev/null 2>&1
python3 "$IMPL" propose --inventory "$TMP/inv_e.json" --repo-root "$E" --out "$TMP/prop_e.json" >/dev/null 2>&1
if python3 - "$TMP/inv_e.json" "$TMP/prop_e.json" <<'PYEOF'
import json, sys
inv = json.load(open(sys.argv[1]))
prop = json.load(open(sys.argv[2]))
main = [e for e in inv["entries"] if e.get("entry_id") == "MAIN"][0]
assert main["is_main"] is True, main
p = {x["entry_id"]: x for x in prop["proposals"]}
assert p["wt_e2e"]["action"] == "retire" and p["wt_e2e"]["verdict"] == "ALLOWED", p["wt_e2e"]
assert p["MAIN"]["action"] == "keep", p["MAIN"]
PYEOF
then
  ok "e2e: binary+CRLF linked worktree proposed retire/ALLOWED; MAIN (with a matching backup) proposed keep"
else
  notok "e2e: unexpected proposals: $(cat "$TMP/prop_e.json" 2>/dev/null | head -c 600)"
fi

# ---------------------------------------------------------------------------
# A hostile user git config must not change the patch shape (diff.noprefix,
# color.ui=always, mnemonic prefixes would all break `git apply`).
# ---------------------------------------------------------------------------
echo
echo "=== B1: hostile global git config does not change the canonical patch ==="
printf '[diff]\n\tnoprefix = true\n\tmnemonicPrefix = true\n[color]\n\tui = always\n' > "$TMP/hostile.gitconfig"
R=$(GIT_CONFIG_GLOBAL="$TMP/hostile.gitconfig" run_case "$IMPL" "$A" worktree wt_text retire \
      "$(sha "$TMP/b_text.patch")" "$TMP/b_text.patch")
expect "hostile-config golden-good still ALLOWED" "$R" ALLOWED

# ---------------------------------------------------------------------------
# Guard viability: mutate one check at a time in a throwaway copy.
# ---------------------------------------------------------------------------
build_copy() {
  local dir="$1"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/custody_sweep.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"
}

# mutate FILE OLD NEW  (OLD must occur exactly once)
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

# mut NAME OLD NEW ROOT KIND ID ACTION HASH PATH WANT_MUTANT_VERDICT [DETAIL_THE_REAL_TOOL_GIVES]
# Real tool gives REFUSED (with DETAIL); mutant must differ: either its
# verdict is WANT_MUTANT_VERDICT, or (when WANT is "DETAIL") its detail no
# longer names DETAIL.
mut() {
  local name="$1" old="$2" new="$3" root="$4" kind="$5" id="$6" action="$7" hash="$8" path="$9"
  local want="${10}" det="${11:-}"
  local d="$TMP/mut_$name"
  build_copy "$d"
  if ! mutate "$d/orchestration/custody_sweep.py" "$old" "$new" >"$TMP/mut_$name.log" 2>&1; then
    notok "mutation $name: anchor not found ($(cat "$TMP/mut_$name.log"))"
    return
  fi
  local real mutant
  real=$(run_case "$IMPL" "$root" "$kind" "$id" "$action" "$hash" "$path")
  mutant=$(run_case "$d/orchestration/custody_sweep.py" "$root" "$kind" "$id" "$action" "$hash" "$path")
  local rv="${real%%$'\t'*}" rd="${real#*$'\t'}" mv="${mutant%%$'\t'*}" md="${mutant#*$'\t'}"
  if [ "$rv" != "REFUSED" ] || { [ -n "$det" ] && [[ "$rd" != *"$det"* ]]; }; then
    notok "mutation $name: REAL tool did not refuse as expected ($rv: $rd)"
    return
  fi
  if [ "$want" = "DETAIL" ]; then
    if [[ "$md" != *"$det"* ]]; then
      ok "mutation $name: caught -- mutant's refusal no longer comes from this check ($mv: ${md:0:90}...)"
    else
      notok "mutation $name SURVIVED: mutant still names '$det'"
    fi
  elif [ "$mv" = "$want" ]; then
    ok "mutation $name: caught -- mutant says $mv, real tool says REFUSED"
  else
    notok "mutation $name SURVIVED: mutant says $mv ($md)"
  fi
}

echo
echo "=== guard viability (paired mutations) ==="
# T140 Round 13: M2/M3a/M3b/M7/M9/M10 moved from "mutant must say ALLOWED"
# to DETAIL mode. Round 13 added the positive RESTORABILITY ORACLE as the
# final, sufficient check (round-12 finding B-1), so deleting one of these
# earlier, cheaper checks no longer flips the verdict -- the oracle then
# refuses the same case on its own (genuine defense-in-depth, measured
# live: the stale/untracked/submodule/lossy backups are each refused by the
# oracle with the specific differing paths named). The mutation is still
# caught: the refusal no longer comes from the deleted check. The oracle
# itself is proven load-bearing by test_custody_sweep_r13_regression.sh
# (deleting it turns the round-12 bypasses ALLOWED).
ZERO=$(printf '0%.0s' $(seq 64))
mut M1_hash_compare '    if real_hash != backup_hash:' '    if False:' \
    "$A" worktree wt_text retire "$ZERO" "$TMP/b_text.patch" ALLOWED "does not match the real sha256"
mut M2_live_compare '    if live_hash != real_hash:' '    if False:' \
    "$A" worktree wt_stale retire "$(sha "$TMP/b_stale.patch")" "$TMP/b_stale.patch" DETAIL "freshly re-derived LIVE"
mut M3a_untracked_check '    if has_untracked is not False:' '    if False:' \
    "$A" worktree wt_untr retire "$(sha "$TMP/b_untr.patch")" "$TMP/b_untr.patch" DETAIL "untracked content"
mut M3b_untracked_detect '            res["has_untracked"] = True' '            res["has_untracked"] = False' \
    "$A" worktree wt_untr retire "$(sha "$TMP/b_untr.patch")" "$TMP/b_untr.patch" DETAIL "untracked content"
# M4/M5: the existence/resolution checks are defense-in-depth -- with them
# deleted a later check still refuses, so the mutant is detected by the
# refusal no longer naming the real reason (honest: no verdict flip).
mut M4_found_check '    if not live.get("found"):' '    if False:' \
    "$A" worktree wt_never_existed retire "$(sha "$TMP/b_text.patch")" "$TMP/b_text.patch" DETAIL "no longer resolves"
mut M5_stash_resolve 'entry_id],
                               check=False, env=env)
        if rc != 0:
            return res' 'entry_id],
                               check=False, env=env)
        if False:
            return res' \
    "$S" stash 'stash@{99}' land "$(sha "$TMP/b_stash_plain.patch")" "$TMP/b_stash_plain.patch" DETAIL "no longer resolves"
mut M6_is_main_check '    if entry_kind == "worktree" and live.get("is_main"):' '    if False:' \
    "$TMP/wt_text" worktree repoA retire "$(sha "$TMP/b_main.patch")" "$TMP/b_main.patch" ALLOWED "MAIN worktree"
mut M6b_is_main_index0 '        res["is_main"] = (idx == 0) or' '        res["is_main"] = False or' \
    "$TMP/wt_text" worktree repoA retire "$(sha "$TMP/b_main.patch")" "$TMP/b_main.patch" ALLOWED "MAIN worktree"
mut M7_submodule_check '    if dirty_submodules is None or dirty_submodules:' '    if False:' \
    "$P" worktree wt_sub retire "$(sha "$TMP/b_sub.patch")" "$TMP/b_sub.patch" DETAIL "changed submodule"
mut M8_stash_untracked 'has_untracked=stash_has_untracked(root, entry_id, env=env),' 'has_untracked=False,' \
    "$S" stash 'stash@{1}' land "$(sha "$TMP/b_stash_u.patch")" "$TMP/b_stash_u.patch" ALLOWED "untracked content"
mut M9_no_binary '    "--binary", "--no-color",' '    "--no-color",' \
    "$A" worktree wt_bin retire "$(sha "$TMP/b_bin_lossy.patch")" "$TMP/b_bin_lossy.patch" DETAIL "freshly re-derived LIVE"
mut M10_text_mode_crlf '    return proc.returncode, proc.stdout, proc.stderr.decode' \
    '    return proc.returncode, proc.stdout.replace(b"\r\n", b"\n"), proc.stderr.decode' \
    "$A" worktree wt_crlf retire "$(sha "$TMP/b_crlf_stripped.patch")" "$TMP/b_crlf_stripped.patch" DETAIL "freshly re-derived LIVE"

mut M11_detached_head '    if head_unreachable is not False:' '    if False:' \
    "$A" worktree wt_det retire "$(sha "$TMP/b_det.patch")" "$TMP/b_det.patch" ALLOWED "DETACHED HEAD"

# The MAIN check for the root==main case must flip the VERDICT (not only
# the detail): with the is_main gate gone, a matching main backup is ALLOWED.
mut M6c_is_main_verdict '    if entry_kind == "worktree" and live.get("is_main"):' '    if False:' \
    "$A" worktree MAIN retire "$(sha "$TMP/b_main.patch")" "$TMP/b_main.patch" ALLOWED "MAIN worktree"

echo
echo "=== I3: a stale --out never survives a handled propose refusal ==="
i3_case() {  # i3_case IMPL OUTFILE -> rc
  printf '{"schema":"custody-sweep-propose/v1","proposals":[{"verdict":"ALLOWED","action":"retire"}],"STALE":1}' > "$2"
  python3 "$1" propose --inventory "$TMP/no_such_inventory.json" --repo-root "$A" --out "$2" >/dev/null 2>&1
}
i3_case "$IMPL" "$TMP/i3_real.json"; RC=$?
if [ "$RC" = 2 ] && ! grep -q STALE "$TMP/i3_real.json" 2>/dev/null; then
  ok "I3 propose with an unreadable --inventory (rc=2): the previous ALLOWED proposal is gone"
else
  notok "I3 propose refusal: rc=$RC stale_left=$(grep -c STALE "$TMP/i3_real.json" 2>/dev/null)"
fi
D="$TMP/mut_I3"
build_copy "$D"
if mutate "$D/orchestration/custody_sweep.py" '        invalidate_stale_out(getattr(args, "out", None))
' '' >"$D.log" 2>&1; then
  i3_case "$D/orchestration/custody_sweep.py" "$TMP/i3_mut.json"
  if grep -q STALE "$TMP/i3_mut.json" 2>/dev/null; then
    ok "mutation I3_invalidate: caught -- without the post-parse invalidation the stale proposal survives"
  else
    notok "mutation I3_invalidate SURVIVED"
  fi
else
  notok "mutation I3_invalidate: anchor not found ($(cat "$D.log"))"
fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R11 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- every destructive"
  echo "    verdict now requires a byte-faithful, restorable backup; binary/CRLF/-u stash/"
  echo "    dirty submodule/MAIN/unreachable-detached cases are refused; every safety check is reached by a real"
  echo "    case and proven load-bearing by a paired mutation. ==="
  exit 0
else
  echo "=== R11 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
