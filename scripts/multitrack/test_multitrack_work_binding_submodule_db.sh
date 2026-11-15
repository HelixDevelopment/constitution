#!/usr/bin/env bash
# test_multitrack_work_binding_submodule_db.sh — permanent §11.4.135 regression
# guard for multitrack_work_binding.sh's OWN submodule-cwd superproject-walk DB
# auto-discovery fix (this cycle).
#
# ── Forensic anchor (this fix, in-flight this cycle) ────────────────────────
#   multitrack_work_binding.sh's DB auto-discovery previously bound ONLY to
#   `git rev-parse --show-toplevel` (the innermost repo). A caller invoking the
#   resolver directly from INSIDE a submodule WITHOUT an explicit `--db` (e.g.
#   the detective gate CM-WORK-TRACK-BINDING-ENFORCED, or any other direct
#   caller that does not replicate the sibling guard hook's own submodule-aware
#   walk) unconditionally fail-closed BLOCKed, regardless of file-scope
#   classification, because `<submodule-root>/docs/workable_items.db` never
#   exists there — the real §11.4.93/§11.4.95 registry lives at the OUTERMOST
#   (super)project root. The fix teaches the resolver's OWN auto-discovery
#   (multitrack_work_binding.sh:129-197) to walk UP through every nested
#   `git rev-parse --show-superproject-working-tree` hop (depth-bounded to 10)
#   and probe each discovered outer root, OUTERMOST-first, mirroring the
#   sibling guard hook's `resolve_workable_items_db()`
#   (guard-work-track-binding.sh:179-205) — but landed INSIDE the shared
#   resolver itself, so every direct caller (not only the guard hook) benefits.
#
# ── What this suite proves (§11.4.115 RED->GREEN polarity + §11.4.6 anti-bluff) ──
#   (1) GREEN / direct regression case — an unclassified file, invoked from
#       cwd INSIDE a real `git submodule add`-created submodule, with $WI_DB
#       UNSET and NO --db, resolves the PARENT superproject's registry and
#       returns the correct verdict (exit 0), NOT a fail-closed "DB not found"
#       (exit 2).
#   (2) The parent DB is GENUINELY CONSULTED, not merely found-and-ignored — a
#       classified file (owned by a group whose canonical branch != the
#       change's declared branch) is still BLOCKED (exit 2) from submodule cwd,
#       and the SAME file with the CORRECT branch is ALLOWED (exit 0).
#   (3) Fail-closed is UNWEAKENED — the identical submodule-cwd invocation
#       against a fixture with NO workable-items DB anywhere in the git chain
#       still fail-closes (exit 2); the fix WIDENS discovery, it never
#       degrades the "unverifiable => BLOCK" guarantee (§11.4.6).
#   (4) RED-polarity self-check (§11.4.115) — a SCRATCHPAD-ONLY mutated copy of
#       the resolver with the superproject-walk block neutralised (the
#       pre-fix behaviour, byte-identical candidate list to before this cycle)
#       re-runs case (1) and MUST fail-closed (exit 2) — proving this guard
#       would catch a revert of the fix. The real, working-tree resolver is
#       NEVER modified; only a `mktemp`-created copy is mutated.
#
# This test is DISTINCT from the existing sibling suite
# constitution/scripts/hooks/test_guard_work_track_binding.sh §D: that suite
# exercises guard-work-track-binding.sh, which has its OWN
# `resolve_workable_items_db()` copy and ALWAYS supplies an explicit `--db` to
# the resolver once it finds one — so it never exercises the RESOLVER's own
# internal auto-discovery fallback path. This suite invokes
# multitrack_work_binding.sh DIRECTLY (no guard hook in the loop, no JSON
# payload), with $WI_DB unset and no --db, so the resolver's OWN walk is the
# only thing under test — the exact code path the detective gate
# CM-WORK-TRACK-BINDING-ENFORCED (and any other direct caller) depends on.
#
# Anti-bluff (§11.4.107(10) analogue): every fixture uses a REAL git submodule
# (`git submodule add`, own `.git` file + gitlink in the outer index — never a
# bare nested `git init`), a REAL schema-v4 sqlite registry (logic_groups +
# group_paths, mirroring the shape used by
# constitution/scripts/hooks/test_guard_work_track_binding.sh §D), and the
# mutation is verified to have actually landed (grep check) before being
# trusted as the RED baseline — a silently-no-op mutation would make the
# RED-polarity assertion vacuously true, which is itself the bluff §11.4.115
# forbids.
#
# Hermetic + self-cleaning: everything lives under one `mktemp -d`, removed via
# `trap ... EXIT` on every exit path. No project DB, no project git tree, no
# binary dependency.
#
# Usage: bash constitution/scripts/multitrack/test_multitrack_work_binding_submodule_db.sh
# Exit 0 = all cases pass (or hermetic SKIP); exit 1 = one or more cases failed.
#
# Cross-references: §11.4.191 (work-to-track/branch binding) · §11.4.135
# (standing regression-guard suite — every fixed defect gets a permanent
# regression test) · §11.4.115 (RED-baseline-on-the-broken-artifact +
# polarity-switch) · §11.4.6 (no-guessing / fail-closed) · §11.4.28(C) /
# §11.4.177 (project-agnostic, inherited by reference). Sibling:
# constitution/scripts/hooks/test_guard_work_track_binding.sh §D (guard-hook-
# level submodule DB resolution — the guard's OWN walk, a separate code path).
#
# Classification: universal.

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$HERE/multitrack_work_binding.sh"

PASS=0
FAIL=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 unavailable — the registry-backed cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git unavailable — the submodule-fixture cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi
if [ ! -f "$RES" ]; then
  echo "FAIL: resolver not found at $RES"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

assert() { # <name> <want-exit> <got-exit>
  local name="$1" want="$2" got="$3"
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-70s (exit %s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-70s (got %s, want %s)\n' "$name" "$got" "$want"; FAIL=$((FAIL+1))
  fi
}

echo "§11.4.191/§11.4.135 multitrack_work_binding.sh submodule-DB-discovery regression guard"
echo "resolver: $RES"
echo

# ===========================================================================
# Fixture A — outer superproject WITH docs/workable_items.db + a real
# `git submodule add` submodule that has NO DB of its own. Mirrors the shape
# used by constitution/scripts/hooks/test_guard_work_track_binding.sh §D, but
# built independently here so this suite has zero dependency on the sibling.
# ===========================================================================
OUTER="$TMP/outer"
SUBSRC="$TMP/subsrc"

git init -q -b main "$OUTER"
git -C "$OUTER" config user.email t@t
git -C "$OUTER" config user.name  t
mkdir -p "$OUTER/docs"
sqlite3 "$OUTER/docs/workable_items.db" "
CREATE TABLE logic_groups (group_id TEXT PRIMARY KEY, title TEXT, destination TEXT NOT NULL, priority INTEGER NOT NULL, state TEXT, scope_note TEXT, roadmap_ref TEXT, canonical_track TEXT);
INSERT INTO logic_groups (group_id,title,destination,priority,state,canonical_track) VALUES
 ('sub-work','t','feature:sub-work',9,'open',NULL);
CREATE TABLE group_paths (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, path_glob TEXT NOT NULL, note TEXT, UNIQUE(group_id,path_glob));
INSERT INTO group_paths (group_id,path_glob) VALUES
 ('sub-work','tracked.kt');
CREATE TABLE items (atm_id TEXT, type TEXT, status TEXT, title TEXT, description TEXT, logic_group TEXT, current_location TEXT, PRIMARY KEY(atm_id,current_location));
"
echo seed > "$OUTER/seed.txt"
git -C "$OUTER" add seed.txt docs/workable_items.db
git -C "$OUTER" commit -qm seed

git init -q -b main "$SUBSRC"
git -C "$SUBSRC" config user.email t@t
git -C "$SUBSRC" config user.name  t
echo x > "$SUBSRC/seed.txt"
git -C "$SUBSRC" add seed.txt
git -C "$SUBSRC" commit -qm seed
git -C "$SUBSRC" branch feature/sub-work

git -C "$OUTER" -c protocol.file.allow=always submodule add -q "$SUBSRC" sub >/dev/null 2>&1
git -C "$OUTER" commit -qm "add submodule" -q

SUB="$OUTER/sub"
echo new > "$SUB/bar.txt"      # unclassified — no group_paths glob owns it
echo new > "$SUB/tracked.kt"   # owned by 'sub-work' -> canonical branch feature/sub-work

# submodule_direct_check <branch> <file> — invoke the RESOLVER DIRECTLY (no
# guard hook) from cwd=$SUB with $WI_DB explicitly UNSET and NO --db, so ONLY
# the resolver's own submodule-aware walk can find the registry — the exact
# scenario this fix addresses.
submodule_direct_check() {
  local branch="$1" file="$2"
  ( cd "$SUB" && unset WI_DB && bash "$RES" check --branch "$branch" --file "$file" >/dev/null 2>&1 ); echo $?
}

echo "-- 1. GREEN: direct regression case (unclassified file, submodule cwd, no --db) --"
RC1="$(submodule_direct_check main bar.txt)"
assert "resolver-direct: unclassified file, submodule cwd, WI_DB unset, no --db -> allowed (parent DB found)" 0 "$RC1"

echo "-- 2. parent DB genuinely CONSULTED (not merely found) --"
RC2="$(submodule_direct_check main tracked.kt)"
assert "resolver-direct: sub-work file on main (wrong branch) -> BLOCKED (parent DB enforced)" 2 "$RC2"
RC3="$(submodule_direct_check feature/sub-work tracked.kt)"
assert "resolver-direct: sub-work file on feature/sub-work (correct branch) -> allowed" 0 "$RC3"

echo "-- 3. fail-closed unweakened: no DB anywhere in the chain --"
OUTER2="$TMP/outer2"
SUBSRC2="$TMP/subsrc2"
git init -q -b main "$OUTER2"
git -C "$OUTER2" config user.email t@t
git -C "$OUTER2" config user.name  t
echo seed > "$OUTER2/seed.txt"
git -C "$OUTER2" add seed.txt
git -C "$OUTER2" commit -qm seed

git init -q -b main "$SUBSRC2"
git -C "$SUBSRC2" config user.email t@t
git -C "$SUBSRC2" config user.name  t
echo x > "$SUBSRC2/seed.txt"
git -C "$SUBSRC2" add seed.txt
git -C "$SUBSRC2" commit -qm seed

git -C "$OUTER2" -c protocol.file.allow=always submodule add -q "$SUBSRC2" sub2 >/dev/null 2>&1
git -C "$OUTER2" commit -qm "add submodule" -q

SUB2="$OUTER2/sub2"
echo new > "$SUB2/whatever.kt"
RC4="$(cd "$SUB2" && unset WI_DB && bash "$RES" check --branch main --file whatever.kt >/dev/null 2>&1; echo $?)"
assert "resolver-direct: no workable-items DB anywhere in the chain -> fail-closed BLOCK" 2 "$RC4"

# ===========================================================================
# 4. RED-polarity self-check (§11.4.115): a SCRATCHPAD-ONLY mutated copy of
# the resolver with the superproject-walk neutralised must reproduce the
# PRE-FIX fail-closed BLOCK on the exact case that is GREEN (exit 0) on the
# real, unmodified resolver above (case 1). The real working-tree resolver
# ($RES) is NEVER edited — only this mktemp-created copy is mutated, and the
# mutation's presence is verified before being trusted as the RED baseline
# (a silently-no-op sed would make this assertion vacuously true — the exact
# bluff §11.4.115/§11.4.6 forbid).
# ===========================================================================
echo "-- 4. RED-polarity: mutated copy (superproject-walk removed) reproduces pre-fix BLOCK --"
MUT="$TMP/multitrack_work_binding.MUTATED.sh"
cp "$RES" "$MUT"
# Neutralise ONLY the outer-root discovery block by disabling its guarding
# `if`, so `_wtb_outer_cands` stays permanently empty — byte-identical to the
# pre-fix candidate list (WI_DB, then only the cwd/$GIT_TOP-relative
# candidates). This targets the exact line the fix introduced
# (multitrack_work_binding.sh:170), leaving every other line untouched.
sed -i 's/if \[ -n "\$GIT_TOP" \]; then/if false; then/' "$MUT"
chmod +x "$MUT"

if ! grep -q 'if false; then' "$MUT"; then
  echo "  FAIL  mutation sanity-check: sed did not neutralise the superproject-walk block (test is broken, not the fix)"
  FAIL=$((FAIL+1))
else
  printf '  PASS  %-70s\n' "mutation sanity-check: superproject-walk block neutralised in scratch copy"
  PASS=$((PASS+1))
  RC_RED="$(cd "$SUB" && unset WI_DB && bash "$MUT" check --branch main --file bar.txt >/dev/null 2>&1; echo $?)"
  assert "RED-polarity: mutated resolver (walk removed) -> fail-closed BLOCK (pre-fix behaviour reproduced)" 2 "$RC_RED"
fi

# Confirm the REAL, working-tree resolver was never touched by this suite
# (byte-for-byte identity) — the RED-polarity mutation lived ONLY in $TMP.
if diff -q "$RES" "$HERE/multitrack_work_binding.sh" >/dev/null 2>&1; then
  printf '  PASS  %-70s\n' "real resolver untouched by this suite (byte-identical post-run)"
  PASS=$((PASS+1))
else
  echo "  FAIL  real resolver was modified by this test run — critical test-hygiene defect"
  FAIL=$((FAIL+1))
fi

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
