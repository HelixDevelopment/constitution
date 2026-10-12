#!/usr/bin/env bash
# test_index_commit_seam.sh -- RED-first behaviour test for scripts/anchors/index_commit_seam.sh, the
# COMMIT-path stage of the constitution index-regeneration seam (T048 round-4 review, R4-01).
#
# Why: anchor_citations.py refuses an index whose generated_from.source_sha256 differs from
# Constitution.md (E_INDEX_SHA_MISMATCH, exit 4). 59 of the last 60 commits that touched
# Constitution.md left the index stale, because nothing on the amendment path regenerated it.
# regenerate_if_stale.sh does the regeneration; this seam is what a commit wrapper (commit_all.sh's
# submodule cascade) runs after staging and before `git commit`, so an amendment can never be
# committed with a stale index.
#
# Every case drives the REAL seam script through its real CLI against a scratch git work tree built
# from the REAL Constitution.md and the REAL generator.
#
# Cases:
#   S1 fresh, nothing amended         -> exit 0, "fresh", nothing staged, index byte-identical
#   S2 amendment STAGED               -> exit 0, index regenerated AND staged, staged index checksum
#                                        == sha256 of the STAGED Constitution.md, changed groups/*.md
#                                        staged, an unrelated modified file is NOT staged
#   S3 amendment NOT staged (the staged Constitution.md is the old one, the working tree is new)
#                                     -> exit 3, names the disagreement, the index is NOT staged
#   S4 --root is not a git work tree  -> exit 4 (BLIND)
#   S5 the staged index is stale but the working tree is fresh (someone regenerated without
#      staging) -> exit 0 and the fresh index is staged
#   S6 usage error (no --root value)  -> exit 2
#   S7  a required tool (sha256sum) is missing from PATH -> exit 4, names the dependency (BLIND, not a pass)
#   S8  regenerate_if_stale.sh absent                     -> exit 4 BLIND naming the missing file
#   S9  --root is a SUBDIRECTORY of a work tree (all files fresh and present in it) -> exit 4 BLIND, not the top
#   S10 Constitution.md is not tracked                    -> exit 4 BLIND
#   S11 the regeneration itself fails (stub regenerator: --check stale, regen rc=7 + a marker line)
#                                     -> exit 3, the message names rc=7 + the regenerator's own output, nothing staged
#   S12 `git add` fails (a held .git/index.lock; the pair is otherwise fresh) -> exit 3 'git add ... failed'
#   S13 the staged index is corrupted DURING staging (a clean filter rewrites source_sha256) -> exit 3 'after staging'
#   S14 a groups/*.md is HAND-EDITED while the checksum is fresh (regenerate_if_stale.sh --check says fresh)
#                                     -> exit 3 naming the drift, nothing staged (F5: the seam runs the generator's own drift check)
#   S15 the generator (constitution_generate.py) is absent while the checker reports fresh
#                                     -> exit 4 BLIND naming the missing generator (V5 N5), never a pass and never rc 3
# Every S7-S15 fixture is otherwise CLEAN, so only the named refusal branch can produce the exit/message.
# Paired mutations (Step M): each one-place edit of a COPY of the seam must make >=1 case FAIL.
# shellcheck disable=SC2016  # file-wide: the Step-M mutation targets and the S11 stub-regenerator body are deliberately literal shell text
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANCHORS="$(cd "$HERE/.." && pwd)"
CROOT="$(cd "$ANCHORS/../.." && pwd)"
SEAM="${INDEX_COMMIT_SEAM_UNDER_TEST:-$ANCHORS/index_commit_seam.sh}"
GEN="$ANCHORS/constitution_generate.py"
REAL_SOURCE="$CROOT/Constitution.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

for dep in git python3 sha256sum cmp flock; do
  command -v "$dep" >/dev/null 2>&1 || { echo "BLIND: required dependency '$dep' not usable" >&2; exit 4; }
done
[ -f "$REAL_SOURCE" ] || { echo "BLIND: real Constitution.md absent at $REAL_SOURCE" >&2; exit 4; }

TMP=$(mktemp -d) || { echo "BLIND: mktemp failed" >&2; exit 4; }
trap 'rm -rf "$TMP"' EXIT

if [ -f "$SEAM" ]; then ok "index_commit_seam.sh exists ($SEAM)"
else bad "index_commit_seam.sh missing at $SEAM"; echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1; fi

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 HOME="$TMP/home"
mkdir -p "$HOME"

# A scratch constitution work tree whose committed outputs are a real fresh generation.
mkroot() { # mkroot <dir>
  mkdir -p "$1"
  cp "$REAL_SOURCE" "$1/Constitution.md"
  python3 "$GEN" generate --source "$1/Constitution.md" --groups-dir "$1/groups" \
    --index-out "$1/constitution_index.yaml" >/dev/null 2>"$1.gen.err" \
    || { echo "BLIND: generator could not build the scratch root: $(cat "$1.gen.err")" >&2; exit 4; }
  printf 'export twin\n' > "$1/groups/testing-and-tdd.html"
  printf 'unrelated\n' > "$1/notes.txt"
  if git -C "$1" init -q && git -C "$1" add -A && git -C "$1" commit -q -m base; then
    :
  else
    echo "BLIND: cannot build the scratch git work tree $1" >&2; exit 4
  fi
}
# A typical amendment: one sentence inside an anchor body, no heading changed.
amend() { # amend <Constitution.md>
  python3 - "$1" <<'PY' || { echo "BLIND: cannot amend $1" >&2; exit 4; }
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
m = re.search(r"(?m)^### §11\.4\.108\b.*$", t)
assert m, "no §11.4.108 heading"
i = t.index("\n", m.end()) + 1
open(p, "w", encoding="utf-8").write(t[:i] + "An amendment sentence added by test_index_commit_seam.\n" + t[i:])
PY
}
staged_index_sha() { # the source_sha256 recorded in the STAGED constitution_index.yaml
  git -C "$1" show :constitution_index.yaml 2>/dev/null \
    | sed -n '/^generated_from:/,/^[^ ]/s/^  source_sha256: *'"'"'\{0,1\}\([0-9a-f]\{64\}\)'"'"'\{0,1\} *$/\1/p' | head -n 1
}
staged_source_sha() { git -C "$1" show :Constitution.md | sha256sum | cut -c1-64; }

run_cases() { # run_cases <seam-script> ; every case on a fresh scratch tree
  local seam=$1 r out rc
  # S1
  r="$TMP/s1"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  cp "$r/constitution_index.yaml" "$TMP/s1.idx"
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^fresh' <<< "$out" && git -C "$r" diff --cached --quiet \
     && cmp -s "$r/constitution_index.yaml" "$TMP/s1.idx"; then
    ok "S1 fresh: exit 0, 'fresh', nothing staged, index byte-identical"
  else bad "S1 fresh: rc=$rc staged=[$(git -C "$r" diff --cached --name-only | tr '\n' ' ')] out=[$out]"; fi
  # S2
  r="$TMP/s2"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  amend "$r/Constitution.md"; printf 'changed\n' >> "$r/notes.txt"; printf 'twin2\n' >> "$r/groups/testing-and-tdd.html"
  git -C "$r" add Constitution.md
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  local staged; staged=$(git -C "$r" diff --cached --name-only | sort | tr '\n' ' ')
  if [ "$rc" -eq 0 ] && [ "$(staged_index_sha "$r")" = "$(staged_source_sha "$r")" ] \
     && grep -q 'constitution_index.yaml' <<< "$staged" \
     && grep -q 'groups/.*\.md' <<< "$staged" \
     && ! grep -q 'notes.txt' <<< "$staged" \
     && ! grep -q 'testing-and-tdd.html' <<< "$staged" \
     && git -C "$r" diff --quiet -- constitution_index.yaml; then
    ok "S2 staged amendment: index regenerated + staged, checksums agree, groups .md staged, unrelated files untouched"
  else bad "S2 staged amendment: rc=$rc staged=[$staged] idx=$(staged_index_sha "$r") src=$(staged_source_sha "$r") out=[$out]"; fi
  # S3
  r="$TMP/s3"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  amend "$r/Constitution.md"
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  # captured first, then grepped via a here-string: a `git ... | grep -q` pipeline under pipefail
  # can return git's SIGPIPE status 141 when grep matches early, which the `!` would invert into
  # a false PASS (CM-SIGPIPE-PIPEFAIL-CLASS).
  s3_staged="$(git -C "$r" diff --cached --name-only)"
  if [ "$rc" -eq 3 ] && grep -qi 'disagree' <<< "$out" \
     && ! grep -q 'constitution_index.yaml' <<< "$s3_staged"; then
    ok "S3 unstaged amendment: exit 3, the disagreement is named, the index is NOT staged"
  else bad "S3 unstaged amendment: rc=$rc staged=[$(git -C "$r" diff --cached --name-only | tr '\n' ' ')] out=[$out]"; fi
  # S4
  mkdir -p "$TMP/s4_notgit"; cp "$REAL_SOURCE" "$TMP/s4_notgit/Constitution.md"
  out=$(GIT_CEILING_DIRECTORIES="$TMP" bash "$seam" --root "$TMP/s4_notgit" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q 'BLIND' <<< "$out"; then ok "S4 not a git work tree: exit 4 BLIND"
  else bad "S4 not a git work tree: rc=$rc out=[$out]"; fi
  # S5
  r="$TMP/s5"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  amend "$r/Constitution.md"; git -C "$r" add Constitution.md
  python3 "$GEN" generate --source "$r/Constitution.md" --groups-dir "$r/groups" --index-out "$r/constitution_index.yaml" >/dev/null 2>&1
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [ "$(staged_index_sha "$r")" = "$(staged_source_sha "$r")" ]; then
    ok "S5 fresh working tree but stale STAGED index: exit 0 and the fresh index is staged"
  else bad "S5 stale staged index: rc=$rc idx=$(staged_index_sha "$r") src=$(staged_source_sha "$r") out=[$out]"; fi
  # S6
  out=$(bash "$seam" --root 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then ok "S6 usage error: exit 2"; else bad "S6 usage error: rc=$rc out=[$out]"; fi
  # S7 -- a missing tool: PATH holds symlinks to everything the seam needs EXCEPT sha256sum
  local bin="$TMP/s7bin"; rm -rf "$bin"; mkdir -p "$bin"
  local tool
  for tool in bash git python3 dirname cut sed cat basename mkdir rm; do
    command -v "$tool" >/dev/null 2>&1 && ln -sf "$(command -v "$tool")" "$bin/$tool"
  done
  r="$TMP/s7"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  out=$(env PATH="$bin" "$bin/bash" "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q "dependency 'sha256sum' not usable" <<< "$out"; then
    ok "S7 missing dependency: exit 4, the missing tool (sha256sum) is named"
  else bad "S7 missing dependency: rc=$rc out=[$out]"; fi
  # S8 -- the regenerator is absent
  r="$TMP/s8"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  out=$(INDEX_COMMIT_SEAM_REGEN="$TMP/no_such_regen.sh" bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q 'BLIND -- .*no_such_regen.sh is missing' <<< "$out"; then
    ok "S8 regenerator absent: exit 4 BLIND naming the missing file"
  else bad "S8 regenerator absent: rc=$rc out=[$out]"; fi
  # S9 -- --root is a subdirectory of the work tree; the subdirectory holds a complete FRESH copy, so only the
  #       top-of-work-tree guard can refuse it
  r="$TMP/s9"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  mkdir -p "$r/sub"; cp "$r/Constitution.md" "$r/constitution_index.yaml" "$r/sub/"; cp -r "$r/groups" "$r/sub/groups"
  out=$(bash "$seam" --root "$r/sub" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q 'not the top of its own work tree' <<< "$out"; then
    ok "S9 root is a subdirectory of its work tree: exit 4 BLIND 'not the top'"
  else bad "S9 subdirectory root: rc=$rc out=[$out]"; fi
  # S10 -- Constitution.md exists on disk (fresh pair) but is not tracked
  r="$TMP/s10"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  git -C "$r" rm -q --cached Constitution.md && git -C "$r" -c user.name=t -c user.email=t@t commit -q -m untrack
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q 'Constitution.md is not tracked' <<< "$out"; then
    ok "S10 Constitution.md not tracked: exit 4 BLIND"
  else bad "S10 untracked Constitution.md: rc=$rc out=[$out]"; fi
  # S11 -- the regeneration fails. Stub regenerator: --check says stale (rc 1), a real run fails rc=7 with a marker.
  local stub="$TMP/s11_regen.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'for a in "$@"; do [ "$a" = --check ] && exit 1; done' 'echo "STUB-REGEN-BOOM"; exit 7' > "$stub"
  r="$TMP/s11"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  out=$(INDEX_COMMIT_SEAM_REGEN="$stub" bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 3 ] && grep -q 'regenerate_if_stale.sh failed (rc=7)' <<< "$out" \
     && grep -q 'STUB-REGEN-BOOM' <<< "$out" && git -C "$r" diff --cached --quiet; then
    ok "S11 regeneration failure: exit 3, cause 'rc=7' + the regenerator's own output named, nothing staged"
  else bad "S11 regeneration failure: rc=$rc staged=[$(git -C "$r" diff --cached --name-only | tr '\n' ' ')] out=[$out]"; fi
  # S12 -- git add fails (index.lock held); the pair itself is fresh and staged-consistent
  r="$TMP/s12"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  : > "$r/.git/index.lock"
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  rm -f "$r/.git/index.lock"
  if [ "$rc" -eq 3 ] && grep -q 'git add of the index/groups failed' <<< "$out"; then
    ok "S12 git add failure: exit 3, 'git add of the index/groups failed'"
  else bad "S12 git add failure: rc=$rc out=[$out]"; fi
  # S13 -- staging corrupts the index: a clean filter on constitution_index.yaml zeroes source_sha256 on `git add`
  r="$TMP/s13"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  printf '%s\n' '#!/usr/bin/env bash' "exec sed -E \"s/(source_sha256: *'?)[0-9a-f]{64}/\\\\10000000000000000000000000000000000000000000000000000000000000000/\"" > "$TMP/s13_filter.sh"
  chmod +x "$TMP/s13_filter.sh"
  git -C "$r" config filter.corrupt.clean "$TMP/s13_filter.sh"
  printf 'constitution_index.yaml filter=corrupt\n' > "$r/.gitattributes"
  touch "$r/constitution_index.yaml"
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 3 ] && grep -q 'after staging, the staged index' <<< "$out"; then
    ok "S13 index corrupted during staging: exit 3, 'after staging ... still disagrees'"
  else bad "S13 post-stage disagreement: rc=$rc out=[$out]"; fi
  # S14 -- a hand-edited generated group with a fresh checksum
  r="$TMP/s14"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  printf 'hand edit\n' >> "$r/groups/testing-and-tdd.md"
  out=$(bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 3 ] && grep -q 'DRIFT from a fresh generation' <<< "$out" && git -C "$r" diff --cached --quiet; then
    ok "S14 hand-edited group with a fresh checksum: exit 3 'DRIFT', nothing staged"
  else bad "S14 drift: rc=$rc staged=[$(git -C "$r" diff --cached --name-only | tr '\n' ' ')] out=[$out]"; fi
  # S15 -- the generator is absent (the checker, the REAL regenerate_if_stale.sh, still reports fresh)
  r="$TMP/s15"; rm -rf "$r" "$r.gen.err"; mkroot "$r"
  out=$(INDEX_COMMIT_SEAM_GEN="$TMP/no_such_generator.py" bash "$seam" --root "$r" 2>&1); rc=$?
  if [ "$rc" -eq 4 ] && grep -q 'BLIND -- generator .*no_such_generator.py is missing' <<< "$out" && git -C "$r" diff --cached --quiet; then
    ok "S15 generator absent: exit 4 BLIND naming the missing generator, nothing staged"
  else bad "S15 generator absent: rc=$rc out=[$out]"; fi
}

echo "== Step B: behaviour of the real seam =="
run_cases "$SEAM"
BASE_FAIL=$FAIL

echo "== Step M: paired mutations (each must make >= 1 case FAIL) =="
mutate() { # mutate <name> <old> <new>
  local name=$1 m="$TMP/mut_$1.sh"
  if ! python3 - "$SEAM" "$m" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if t.count(old) != 1:
    print("target occurs %d times: %r" % (t.count(old), old)); sys.exit(2)
open(dst, "w", encoding="utf-8").write(t.replace(old, new))
PY
  then bad "mutation $name could not be applied"; return; fi
  # The mutant lives in $TMP; it reaches the REAL regenerate_if_stale.sh through the test-only
  # INDEX_COMMIT_SEAM_REGEN override (nothing is written into the repository).
  local before=$FAIL p0=$PASS
  INDEX_COMMIT_SEAM_REGEN="$ANCHORS/regenerate_if_stale.sh" INDEX_COMMIT_SEAM_GEN="$GEN" run_cases "$m" > "$TMP/mut_$name.out" 2>&1
  local mf; mf=$(grep -c '^FAIL' "$TMP/mut_$name.out")
  FAIL=$before; PASS=$p0
  if [ "$name" = SM0_identity ]; then  # runner control: the unchanged copy must pass every case
    if [ "$mf" -eq 0 ]; then ok "mutation runner control: the identity mutant passes every case"
    else bad "mutation runner control: the identity mutant fails ($(grep -m1 '^FAIL' "$TMP/mut_$name.out"))"; fi
    return
  fi
  if [ -n "${4:-}" ]; then  # a named case must be the one that catches it (not collateral damage elsewhere)
    if grep -q "^FAIL: $4 " "$TMP/mut_$name.out"; then ok "mutation $name caught by $4 ($(grep -m1 "^FAIL: $4 " "$TMP/mut_$name.out" | cut -c1-100))"
    else bad "mutation $name was NOT caught by $4 (mutant fails: $(grep -c '^FAIL' "$TMP/mut_$name.out"))"; fi
  elif [ "$mf" -gt 0 ]; then ok "mutation $name caught ($(grep -m1 '^FAIL' "$TMP/mut_$name.out" | cut -c1-110))"
  else bad "mutation $name SURVIVED every case"; fi
}
mutate SM0_identity '#!/usr/bin/env bash' '#!/usr/bin/env bash'
mutate SM1_never_regenerates 'if ! bash "$REGEN" --root "$ROOT" --check >/dev/null 2>&1; then' 'if false; then'
mutate SM2_never_stages 'git -C "$ROOT" add -A -- constitution_index.yaml "${GROUP_PATHSPEC}"' 'true'
mutate SM3_stages_everything 'git -C "$ROOT" add -A -- constitution_index.yaml "${GROUP_PATHSPEC}"' 'git -C "$ROOT" add -A'
mutate SM4_no_staged_pair_check 'if [ "$staged_src" != "$wt_idx" ]; then' 'if false; then'
mutate SM5_not_git_passes 'echo "index_commit_seam: BLIND -- $ROOT is not a git work tree" >&2; exit 4' 'exit 0'
mutate RM-B_dep_check_dropped 'for dep in git sha256sum python3; do' 'for dep in git python3; do' S7
mutate RM-F_regen_missing_guard_off '[ -f "$REGEN" ] ||' 'true ||' S8
mutate RM-C_top_of_tree_guard_off 'if [ -z "$TOP" ] || [ "$(cd "$ROOT" && pwd -P)" != "$(cd "$TOP" && pwd -P)" ]; then' 'if false; then' S9
mutate RM-G_untracked_guard_off 'if ! git -C "$ROOT" cat-file -e :Constitution.md 2>/dev/null; then' 'if false; then' S10
mutate RM-E_regen_failure_not_fatal 'if [ "$rc" -ne 0 ]; then' 'if false; then' S11
mutate RM-H_git_add_failure_ignored 'if ! git -C "$ROOT" add -A -- constitution_index.yaml "${GROUP_PATHSPEC}"; then' 'if false; then' S12
mutate RM-I_drift_check_off 'if [ "$drift_rc" -ne 0 ]; then' 'if false; then' S14
mutate VB_generator_missing_guard_off '[ -f "$GEN" ] ||' 'true ||' S15
mutate RM-D_post_stage_verify_off 'if [ "$staged_idx" != "$staged_src" ]; then' 'if false; then' S13

echo "SUMMARY pass=$PASS fail=$FAIL (behaviour fails=$BASE_FAIL)"
[ "$FAIL" -eq 0 ]
