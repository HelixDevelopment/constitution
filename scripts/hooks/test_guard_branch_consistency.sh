#!/usr/bin/env bash
# test_guard_branch_consistency.sh — hermetic test suite for the §11.4.181
# create-time PreToolUse guard hook (guard-branch-consistency.sh).
#
# Anti-bluff (§11.4.107(10) analogue): the suite proves the hook BLOCKS a manual
# feature-branch create with an UNREGISTERED name (exit 2), ALLOWS a REGISTERED
# name / the mint helper / a documented exception / a delete / a non-feature
# branch / non-git / non-Bash (exit 0), and FAILS-CLOSED (exit 2) when the
# registry cannot be read — so the enforcement itself provably cannot bluff.
#
# The create-detection is argv-INTENT-aware, not a raw whole-text scan (Finding
# 1.1, 2026-07-10): it covers checkout -b/-B/--branch/--orphan, switch
# -c/-C/--create/--orphan, branch [-f], `worktree add -b`, and fetch/push refspec
# `SRC:[refs/heads/]feature/…` creates — each in SPACED (`-b NAME`), GLUED
# (`-bNAME`), and =-joined (`--branch=NAME`) forms (Finding 2, 2026-07-10). It
# fail-closes (exit 2) on a same-segment `$(…)`/variable create name or a create
# embedded in a will-execute substitution; and it does NOT over-block a `git …`
# create merely MENTIONED inside echo/grep/a `#`comment (those exit 0). Compound
# `A && <create>` is segment-split so segment-2 is judged on its own.
#
# KNOWN LIMIT (documented, exit 0 by-hook — the L1/L2 DETECTIVE pre-build gate is
# the enforcement boundary): a create whose name is a CROSS-SEGMENT shell variable
# (`b=feature/x; git checkout -b $b`) is NOT resolvable by a text-matching hook —
# the branch name is not literally present in the git segment. This suite asserts
# the current honest behaviour (allow-by-hook) rather than pretending it blocks.
#
# The registry SoT is a throwaway sqlite DB built here (only the logic_groups
# table the hook SELECTs), pointed at via $WI_DB — no project DB, no binary
# dependency; fully self-contained.
#
# Usage: bash constitution/scripts/hooks/test_guard_branch_consistency.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-branch-consistency.sh"

PASS=0
FAIL=0

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "SKIP: sqlite3 unavailable — the registry-backed cases cannot run hermetically."
  echo "  RESULT: SKIP (0 cases run)"
  exit 0
fi

# --- throwaway registry: only 'feature:mistiq-vader' is registered -----------
TMPDIR_T="$(mktemp -d)"
EMPTYDIR="$(mktemp -d)"   # outside any git tree -> fail-closed probe
trap 'rm -rf "$TMPDIR_T" "$EMPTYDIR"' EXIT
TESTDB="$TMPDIR_T/registry.db"
sqlite3 "$TESTDB" "CREATE TABLE logic_groups (group_id TEXT PRIMARY KEY, title TEXT, destination TEXT NOT NULL, priority INTEGER NOT NULL, state TEXT, scope_note TEXT, roadmap_ref TEXT); INSERT INTO logic_groups (group_id,title,destination,priority,state) VALUES ('mistiq-vader','t','feature:mistiq-vader',10,'open'), ('urgent-main','t','main',0,'open');"

# run_case <name> <expected-exit> <json-payload> [mode]
#   mode default  -> registry mode: WI_DB=$TESTDB (verifiable)
#   mode failclosed -> run from a non-git tmp dir with WI_DB unset (unverifiable)
run_case() {
  local name="$1" want="$2" payload="$3" mode="${4:-registry}" got
  if [ "$mode" = "failclosed" ]; then
    got=$(cd "$EMPTYDIR" && env -u WI_DB bash "$HOOK" <<<"$payload" >/dev/null 2>&1; echo $?)
  else
    got=$(WI_DB="$TESTDB" bash "$HOOK" <<<"$payload" >/dev/null 2>&1; echo $?)
  fi
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-56s (exit %s)\n' "$name" "$got"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %-56s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL+1))
  fi
}

echo "§11.4.181 guard-branch-consistency.sh hermetic test suite"
echo "hook: $HOOK"
echo "registry: $TESTDB (registered: feature/mistiq-vader)"
echo

# --- ALLOW cases (exit 0) --------------------------------------------------
run_case "non-Bash tool (Agent) passes through"        0 '{"tool_name":"Agent","tool_input":{"description":"(T1/main) x"}}'
run_case "non-git Bash (ls) passes through"            0 '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
run_case "git status (not a branch create)"            0 '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
run_case "git checkout existing (no -b)"               0 '{"tool_name":"Bash","tool_input":{"command":"git checkout main"}}'
run_case "checkout -b REGISTERED name"                 0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/mistiq-vader"}}'
run_case "switch -c REGISTERED name"                   0 '{"tool_name":"Bash","tool_input":{"command":"git switch -c feature/mistiq-vader"}}'
run_case "git branch REGISTERED name"                  0 '{"tool_name":"Bash","tool_input":{"command":"git branch feature/mistiq-vader"}}'
run_case "sanctioned mint-helper invocation"           0 '{"tool_name":"Bash","tool_input":{"command":"bin/workable-items group branch mistiq-vader --db docs/workable_items.db"}}'
run_case "documented-exception escape marker"          0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/adhoc # guardrails:allow operator-approved reconciliation"}}'
run_case "branch DELETE (-d) not a create"             0 '{"tool_name":"Bash","tool_input":{"command":"git branch -d feature/old-divergent"}}'
run_case "branch DELETE (-D) not a create"             0 '{"tool_name":"Bash","tool_input":{"command":"git branch -D feature/gone"}}'
run_case "non-feature branch create untouched"         0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b hotfix/urgent"}}'
# --- ALLOW: newly-handled forms (Finding 1.1 — argv-vs-text) ----------------
run_case "worktree add -b REGISTERED allowed"          0 '{"tool_name":"Bash","tool_input":{"command":"git worktree add -b feature/mistiq-vader ../wt"}}'
run_case "fetch refspec REGISTERED dst allowed"        0 '{"tool_name":"Bash","tool_input":{"command":"git fetch origin main:feature/mistiq-vader"}}'
run_case "push DELETE refspec (bare src) not a create" 0 '{"tool_name":"Bash","tool_input":{"command":"git push origin :refs/heads/feature/old-divergent"}}'
run_case "echo MENTION of create (not executed)"       0 '{"tool_name":"Bash","tool_input":{"command":"echo git checkout -b feature/mentioned"}}'
run_case "grep MENTION of create (not executed)"       0 '{"tool_name":"Bash","tool_input":{"command":"grep -rn git checkout -b feature/mentioned ."}}'
run_case "comment-line MENTION (not executed)"         0 '{"tool_name":"Bash","tool_input":{"command":"# git checkout -b feature/mentioned"}}'
run_case "compound: status then REGISTERED create"     0 '{"tool_name":"Bash","tool_input":{"command":"git status && git checkout -b feature/mistiq-vader"}}'
# --- ALLOW: glued/=-joined REGISTERED forms (Finding 2 — glued short/long opts) --
run_case "glued -b REGISTERED allowed"                 0 '{"tool_name":"Bash","tool_input":{"command":"git checkout -bfeature/mistiq-vader"}}'
run_case "--branch= REGISTERED allowed"                0 '{"tool_name":"Bash","tool_input":{"command":"git checkout --branch=feature/mistiq-vader"}}'
run_case "glued switch -c REGISTERED allowed"          0 '{"tool_name":"Bash","tool_input":{"command":"git switch -cfeature/mistiq-vader"}}'
# --- ALLOW: KNOWN LIMIT — cross-segment $VAR create (detective-gate enforced) ----
# A text-matching hook cannot resolve a name that is not literally in the git
# segment; this asserts the honest current behaviour, NOT a pretend-block.
run_case "KNOWN-LIMIT cross-segment \$VAR create (allow-by-hook)" 0 '{"tool_name":"Bash","tool_input":{"command":"b=feature/evil; git checkout -b $b"}}'
run_case "worktree add: -b inside a PATH token (not a create)"    0 '{"tool_name":"Bash","tool_input":{"command":"git worktree add ../my-branch main"}}'

# --- BLOCK cases (exit 2) --------------------------------------------------
run_case "checkout -b UNREGISTERED name blocked"       2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/unregistered-name"}}'
run_case "checkout -B UNREGISTERED name blocked"       2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -B feature/force-divergent"}}'
run_case "switch -c UNREGISTERED name blocked"         2 '{"tool_name":"Bash","tool_input":{"command":"git switch -c feature/another-divergent"}}'
run_case "git branch UNREGISTERED name blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git branch feature/typo-vadder"}}'
run_case "git branch -f UNREGISTERED blocked"          2 '{"tool_name":"Bash","tool_input":{"command":"git branch -f feature/forced-divergent"}}'
run_case "quoted UNREGISTERED name blocked"            2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b '"'"'feature/quoted-divergent'"'"'"}}'
run_case "fail-closed: registry unreadable blocks"     2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b feature/whatever"}}' failclosed
# --- BLOCK: newly-closed bypass forms (Finding 1.1 — argv-vs-text) ----------
run_case "worktree add -b UNREGISTERED blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git worktree add -b feature/wt-divergent ../wt"}}'
run_case "fetch refspec UNREGISTERED dst blocked"      2 '{"tool_name":"Bash","tool_input":{"command":"git fetch origin main:feature/fetch-divergent"}}'
run_case "push refspec UNREGISTERED dst blocked"       2 '{"tool_name":"Bash","tool_input":{"command":"git push . HEAD:refs/heads/feature/push-divergent"}}'
run_case "checkout -b DYNAMIC name (unverifiable)"     2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -b $(printf feature/dyn-divergent)"}}'
run_case "create inside will-execute substitution"     2 '{"tool_name":"Bash","tool_input":{"command":"echo $(git checkout -b feature/sub-divergent)"}}'
run_case "compound: status then UNREGISTERED create"   2 '{"tool_name":"Bash","tool_input":{"command":"git status && git checkout -b feature/compound-divergent"}}'
# --- BLOCK: glued short-opt + =-joined long-opt + --orphan (Finding 2, 2026-07-10) --
run_case "glued -b<name> UNREGISTERED blocked"         2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -bfeature/glued-divergent"}}'
run_case "glued -B<name> UNREGISTERED blocked"         2 '{"tool_name":"Bash","tool_input":{"command":"git checkout -Bfeature/glued-force-divergent"}}'
run_case "glued switch -c<name> UNREGISTERED blocked"  2 '{"tool_name":"Bash","tool_input":{"command":"git switch -cfeature/glued-switch-divergent"}}'
run_case "glued switch -C<name> UNREGISTERED blocked"  2 '{"tool_name":"Bash","tool_input":{"command":"git switch -Cfeature/glued-switch-force-divergent"}}'
run_case "glued worktree -b<name> UNREGISTERED blocked" 2 '{"tool_name":"Bash","tool_input":{"command":"git worktree add -bfeature/glued-wt-divergent ../wt"}}'
run_case "--branch=<name> UNREGISTERED blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git checkout --branch=feature/eq-branch-divergent"}}'
run_case "--create=<name> UNREGISTERED blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git switch --create=feature/eq-create-divergent"}}'
run_case "--orphan <name> UNREGISTERED blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git checkout --orphan feature/orphan-divergent"}}'
run_case "--orphan=<name> UNREGISTERED blocked"        2 '{"tool_name":"Bash","tool_input":{"command":"git switch --orphan=feature/orphan-eq-divergent"}}'

echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS cases)"
exit 0
