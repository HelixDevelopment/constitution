#!/usr/bin/env bash
# test_regenerate_if_stale.sh -- RED-first behaviour test for scripts/anchors/regenerate_if_stale.sh
# (R4-01, round-4 review of T048: anchor_citations.py fails closed with E_INDEX_SHA_MISMATCH whenever
# Constitution.md changes after constitution_index.yaml was generated, and NOTHING regenerated the
# index -- 59 of the last 60 Constitution.md commits left it stale).
#
# Every case drives the REAL script through its real CLI against a scratch constitution root built
# from the REAL Constitution.md and the REAL generator (never a re-implementation). The committed
# outputs of the scratch root are produced by `constitution_generate.py generate`, so "fresh" is the
# generator's own definition of fresh.
#
# Cases:
#   R1  fresh index        -> exit 0, "fresh", every output byte-identical (generated_at included)
#   R2  --check fresh      -> exit 0, nothing written
#   R3  --check stale      -> exit 1, names the stale checksum, nothing written
#   R4  stale (amended)    -> exit 0, "regenerated", index sha == new source sha, generator `check`
#                             passes, changed files are listed
#   R5  idempotent         -> a second run after R4 is "fresh" and byte-identical
#   R6  source changed DURING regeneration (test hook) -> exit 3, real outputs byte-identical,
#                             no temp directory left behind (temp dir + atomic replace)
#   R7  malformed source   -> generator failure -> exit 3, real outputs byte-identical
#   R8  lock held by another process + --lock-timeout 1 -> exit 75, real outputs byte-identical
#   R9  4 concurrent runs on a stale root -> all exit 0, exactly ONE regenerates, final state fresh
#   R10 index without source_sha256 -> treated as stale and regenerated
#   R11 a group .md no longer produced is removed and reported
# Paired mutations (Step M): each one-place edit of a COPY of the script must make >=1 case FAIL.
# shellcheck disable=SC2016  # mutation targets and sh -c bodies are deliberately literal shell text
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANCHORS="$(cd "$HERE/.." && pwd)"
CROOT="$(cd "$ANCHORS/../.." && pwd)"
SCRIPT="${REGEN_SCRIPT_UNDER_TEST:-$ANCHORS/regenerate_if_stale.sh}"
GEN="$ANCHORS/constitution_generate.py"
REAL_SOURCE="$CROOT/Constitution.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

for dep in python3 flock cmp sha256sum; do
  command -v "$dep" >/dev/null 2>&1 || { echo "BLIND: required dependency '$dep' not usable" >&2; exit 4; }
done
[ -f "$REAL_SOURCE" ] || { echo "BLIND: real Constitution.md absent at $REAL_SOURCE" >&2; exit 4; }

TMP=$(mktemp -d) || { echo "BLIND: mktemp failed" >&2; exit 4; }
trap 'rm -rf "$TMP"' EXIT

if [ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; then ok "regenerate_if_stale.sh exists and is executable"
else bad "regenerate_if_stale.sh missing or not executable at $SCRIPT"; echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1; fi

# A scratch constitution root whose committed outputs are a real fresh generation.
mkroot() { # mkroot <dir>
  mkdir -p "$1"
  cp "$REAL_SOURCE" "$1/Constitution.md"
  python3 "$GEN" generate --source "$1/Constitution.md" --groups-dir "$1/groups" \
    --index-out "$1/constitution_index.yaml" >/dev/null 2>"$1.gen.err" \
    || { echo "BLIND: generator could not build the scratch root: $(cat "$1.gen.err")" >&2; exit 4; }
  # Sibling exports the generator does not own: they must never be touched by the script.
  printf 'export twin\n' > "$1/groups/testing-and-tdd.html"
}
# A fingerprint of every output file: path, sha256, mtime (so "untouched" means untouched).
fingerprint() { # fingerprint <root>
  (cd "$1" && find groups constitution_index.yaml -type f -print0 | LC_ALL=C sort -z \
     | xargs -0 sh -c 'for f; do printf "%s %s %s\n" "$f" "$(sha256sum < "$f" | cut -c1-64)" "$(stat -c %y "$f")"; done' sh)
}
src_sha() { sha256sum < "$1" | cut -c1-64; }
idx_sha() { sed -n 's/^  source_sha256: *'"'"'\{0,1\}\([0-9a-f]\{64\}\).*/\1/p' "$1" | head -n 1; }
# Amend the body of an existing anchor without touching any heading (the reviewer's simulation).
amend() { # amend <root>
  python3 - "$1/Constitution.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
key = "\n### §11.4.108"
i = t.find(key)
assert i >= 0, "anchor 11.4.108 heading not found"
j = t.find("\n", i + 1)
t = t[:j + 1] + "\nAn amendment sentence inserted by test_regenerate_if_stale.sh.\n" + t[j + 1:]
open(p, "w", encoding="utf-8").write(t)
PY
}
run() { # run <root> [args...] -> sets RC, OUT
  local r=$1; shift
  OUT=$("$SCRIPT" --root "$r" "$@" 2>&1); RC=$?
}

# ---- R1 / R2: a fresh index is left byte-identical (mtime included) -------------------------------
R="$TMP/fresh"; mkroot "$R"
FP0=$(fingerprint "$R"); sleep 1
run "$R"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^fresh:' && [ "$(fingerprint "$R")" = "$FP0" ]; then
  ok "R1 fresh index: exit 0, 'fresh:', every output byte-identical with unchanged mtime"
else bad "R1 fresh index: rc=$RC out=[$OUT] changed=$([ "$(fingerprint "$R")" = "$FP0" ] && echo no || echo yes)"; fi
run "$R" --check
if [ "$RC" -eq 0 ] && [ "$(fingerprint "$R")" = "$FP0" ]; then ok "R2 --check on a fresh index: exit 0, nothing written"
else bad "R2 --check fresh: rc=$RC out=[$OUT]"; fi

# ---- R3: --check on a stale index -------------------------------------------------------------------
R="$TMP/check"; mkroot "$R"; amend "$R"
FP0=$(fingerprint "$R")
run "$R" --check
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'stale' && printf '%s' "$OUT" | grep -q 'source_sha256' \
   && [ "$(fingerprint "$R")" = "$FP0" ]; then
  ok "R3 --check on a stale index: exit 1, names the stale source_sha256, nothing written"
else bad "R3 --check stale: rc=$RC out=[$OUT] changed=$([ "$(fingerprint "$R")" = "$FP0" ] && echo no || echo yes)"; fi

# ---- R4 / R5: an amendment is regenerated, then idempotent ------------------------------------------
R="$TMP/stale"; mkroot "$R"; amend "$R"
HTML0=$(sha256sum < "$R/groups/testing-and-tdd.html")
run "$R"
NEW_SHA=$(src_sha "$R/Constitution.md")
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^regenerated:' \
   && [ "$(idx_sha "$R/constitution_index.yaml")" = "$NEW_SHA" ] \
   && printf '%s' "$OUT" | grep -q 'updated: constitution_index.yaml' \
   && printf '%s' "$OUT" | grep -q 'updated: groups/' \
   && python3 "$GEN" check --source "$R/Constitution.md" --groups-dir "$R/groups" --index-out "$R/constitution_index.yaml" >/dev/null 2>&1 \
   && [ "$(sha256sum < "$R/groups/testing-and-tdd.html")" = "$HTML0" ]; then
  ok "R4 stale index regenerated: exit 0, index sha == source sha, generator check passes, changes listed, exports untouched"
else bad "R4 stale index: rc=$RC out=[$OUT] idx=$(idx_sha "$R/constitution_index.yaml") src=$NEW_SHA"; fi
FP1=$(fingerprint "$R"); sleep 1
run "$R"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^fresh:' && [ "$(fingerprint "$R")" = "$FP1" ]; then
  ok "R5 idempotent: the second run is 'fresh' and byte-identical"
else bad "R5 idempotent: rc=$RC out=[$OUT]"; fi

# ---- R6: the source changes DURING regeneration: nothing is replaced, no temp dir is left ----------
R="$TMP/race"; mkroot "$R"; amend "$R"
FP0=$(fingerprint "$R")
OUT=$(REGEN_TEST_HOOK_AFTER_GENERATE="printf '\nlate edit\n' >> '$R/Constitution.md'" "$SCRIPT" --root "$R" 2>&1); RC=$?
LEFT=$(find "$R" -maxdepth 1 -name '.regen.*' | wc -l)
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'changed during regeneration' && [ "$(fingerprint "$R")" = "$FP0" ] \
   && [ "$LEFT" -eq 0 ]; then
  ok "R6 source changed mid-regeneration: exit 3, real outputs byte-identical, no temp dir left"
else bad "R6 mid-regeneration change: rc=$RC out=[$OUT] left=$LEFT changed=$([ "$(fingerprint "$R")" = "$FP0" ] && echo no || echo yes)"; fi

# ---- R7: generator failure (duplicate anchor heading) -----------------------------------------------
R="$TMP/malformed"; mkroot "$R"
printf '\n### §11.4.108 — duplicate heading\n\nbody\n' >> "$R/Constitution.md"
FP0=$(fingerprint "$R")
run "$R"
if [ "$RC" -eq 3 ] && [ "$(fingerprint "$R")" = "$FP0" ] && [ "$(find "$R" -maxdepth 1 -name '.regen.*' | wc -l)" -eq 0 ]; then
  ok "R7 generator failure: exit 3, real outputs byte-identical"
else bad "R7 generator failure: rc=$RC out=[$OUT]"; fi

# ---- R8: lock held by another process ---------------------------------------------------------------
R="$TMP/locked"; mkroot "$R"; amend "$R"
FP0=$(fingerprint "$R")
LOCK="$TMP/locked.lock"
flock "$LOCK" sleep 6 & HOLDER=$!
sleep 1
run "$R" --lock "$LOCK" --lock-timeout 1
if [ "$RC" -eq 75 ] && printf '%s' "$OUT" | grep -q 'lock' && [ "$(fingerprint "$R")" = "$FP0" ]; then
  ok "R8 lock held elsewhere: exit 75, nothing written"
else bad "R8 lock held: rc=$RC out=[$OUT] changed=$([ "$(fingerprint "$R")" = "$FP0" ] && echo no || echo yes)"; fi
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

# ---- R9: concurrent invocations ---------------------------------------------------------------------
R="$TMP/concurrent"; mkroot "$R"; amend "$R"
for i in 1 2 3 4; do ( "$SCRIPT" --root "$R" > "$TMP/c$i.out" 2>&1; echo $? > "$TMP/c$i.rc" ) & done
wait
RCS=$(cat "$TMP"/c?.rc | LC_ALL=C sort | tr '\n' ' ')
NREG=$(grep -l '^regenerated:' "$TMP"/c?.out | wc -l)
NFRESH=$(grep -l '^fresh:' "$TMP"/c?.out | wc -l)
if [ "$RCS" = "0 0 0 0 " ] && [ "$NREG" -eq 1 ] && [ "$NFRESH" -eq 3 ] \
   && python3 "$GEN" check --source "$R/Constitution.md" --groups-dir "$R/groups" --index-out "$R/constitution_index.yaml" >/dev/null 2>&1; then
  ok "R9 4 concurrent runs: all exit 0, exactly one regenerates, three see 'fresh', final state passes check"
else bad "R9 concurrent: rcs=[$RCS] regenerated=$NREG fresh=$NFRESH $(cat "$TMP"/c?.out | tr '\n' ' ' | cut -c1-400)"; fi

# ---- R10: an index that records no source_sha256 is stale ------------------------------------------
R="$TMP/nosha"; mkroot "$R"
sed -i '/^  source_sha256:/d' "$R/constitution_index.yaml"
run "$R" --check; RC_CHECK=$RC
run "$R"
if [ "$RC_CHECK" -eq 1 ] && [ "$RC" -eq 0 ] && [ "$(idx_sha "$R/constitution_index.yaml")" = "$(src_sha "$R/Constitution.md")" ]; then
  ok "R10 an index without source_sha256 is stale (--check exit 1) and is regenerated"
else bad "R10 no source_sha256: check rc=$RC_CHECK regen rc=$RC out=[$OUT]"; fi

# ---- R11: a stale group file the generator no longer produces is removed and reported ----------------
R="$TMP/orphan"; mkroot "$R"; amend "$R"
printf '# Retired group\n' > "$R/groups/retired-group.md"
run "$R"
if [ "$RC" -eq 0 ] && [ ! -e "$R/groups/retired-group.md" ] && printf '%s' "$OUT" | grep -q 'removed: groups/retired-group.md'; then
  ok "R11 a group .md the generator no longer produces is removed and reported"
else bad "R11 orphan group: rc=$RC out=[$OUT]"; fi

# ---- Step M: paired mutations of the script (each must make >= 1 case FAIL) -------------------------
if [ -z "${REGEN_SCRIPT_UNDER_TEST:-}" ]; then
  # Mutants live in their own directory beside symlinks to the REAL generator + library, exactly as
  # the real script sits beside them (the script resolves the generator relative to itself).
  MUTD="$TMP/mutants"; mkdir -p "$MUTD"
  ln -s "$ANCHORS/constitution_generate.py" "$MUTD/constitution_generate.py"
  ln -s "$ANCHORS/anchor_lib.py" "$MUTD/anchor_lib.py"
  cat > "$TMP/mutate.py" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
n = t.count(old)
if n != 1:
    print("target occurs %d times (must be exactly 1): %r" % (n, old)); sys.exit(2)
open(dst, "w", encoding="utf-8").write(t.replace(old, new))
PY
  runmut() { # runmut <name> <mutant path> -> 0 when every case passes
    chmod +x "$2"
    REGEN_SCRIPT_UNDER_TEST="$2" bash "$HERE/test_regenerate_if_stale.sh" > "$TMP/mut_$1.out" 2>&1
  }
  # Runner control: an identity mutant (a comment changed) must PASS every case, so a caught
  # mutation is the mutation's effect, never an artefact of the mutant environment.
  if python3 "$TMP/mutate.py" "$SCRIPT" "$MUTD/identity.sh" '# under the lock' '# under the lock (identity)' >/dev/null 2>&1 \
     && runmut identity "$MUTD/identity.sh"; then ok "mutation runner control: the identity mutant passes every case"
  else bad "mutation runner control: the identity mutant FAILED ($(grep -m1 '^FAIL' "$TMP/mut_identity.out" 2>/dev/null))"; fi
  mutate() { # mutate <name> <old> <new>
    if ! python3 "$TMP/mutate.py" "$SCRIPT" "$MUTD/mut_$1.sh" "$2" "$3" > "$TMP/mut_apply.out" 2>&1; then
      bad "mutation $1 could not be applied: $(cat "$TMP/mut_apply.out")"; return; fi
    if runmut "$1" "$MUTD/mut_$1.sh"; then bad "mutation $1 SURVIVED: every case still passes"
    else ok "mutation $1 caught ($(grep -m1 '^FAIL' "$TMP/mut_$1.out" | cut -c1-110))"; fi
  }
  mutate RM1_always_regenerate 'if [ "$have" = "$want" ]; then  # fresh under the lock' 'if false; then'
  mutate RM2_never_regenerate 'if [ "$have" = "$want" ]; then  # fresh under the lock' 'if true; then'
  mutate RM3_no_lock 'if ! flock -w "$LOCK_TIMEOUT" 9; then' 'if false; then'
  mutate RM4_no_recheck_after_generate 'if [ "$after" != "$want" ]; then' 'if false; then'
  mutate RM5_check_mode_writes 'if [ "$CHECK" -eq 1 ]; then' 'if false; then'
  mutate RM6_generate_into_real_dirs '--groups-dir "$STAGE/groups" --index-out "$STAGE/constitution_index.yaml"' '--groups-dir "$GROUPS_DIR" --index-out "$INDEX"'
  mutate RM7_orphans_kept '    rm -f -- "$GROUPS_DIR/$name"' '    :'
  mutate RM8_missing_sha_is_fresh 'have=$(index_sha "$INDEX")  # under the lock' 'have=$(index_sha "$INDEX"); [ -n "$have" ] || have=$want'
  mutate RM9_index_replaced_first '# The index LAST: it is the commit point' 'cp "$STAGE/constitution_index.yaml" "$INDEX"; exit 0 # The index LAST'
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
