#!/usr/bin/env bash
# run_all.sh — runs every decisions-wizard suite sequentially (one heavy loop at a time) and the two gates
# with their paired mutation tests. Exit 0 only when every suite passes AND the repo-change guard passes.
# Set DEC_SKIP_OWN_MUTANTS=1 to skip the slow builder-mutant run.
#
# Repo-change guard (tests/decisions/repo_guard.sh): no test may write outside its mktemp sandbox. The DEFAULT
# scoped mode fails only on changes a decisions-test run can have caused (a new root entry, any change under the
# wizard's own paths, a new wizard artefact anywhere outside .git/.remember, a changed managed block in the root
# CLAUDE/AGENTS/GEMINI/QWEN docs), so it can pass in a shared tree. DEC_REPO_GUARD_STRICT=1 adds the whole-tree
# comparison (git status --ignored -uall + every path newer than the run start, .git included); it is meant for
# a quiet tree and is expected to fail while other streams work in the same checkout. The guard's control
# needles run first; if they fail the guard is BLIND and nothing runs (exit 2).
set -u
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(cd "$here/../.." && pwd)"
. "$repo/scripts/lib/safe_rm.sh"
. "$here/repo_guard.sh"
export PYTHONDONTWRITEBYTECODE=1
guard_dir="$(mktemp -d "${TMPDIR:-/tmp}/dec_runall.XXXXXX")" || exit 1
trap 'safe_rm_rf "${guard_dir:?}"' EXIT

if ! guard_selftest >"$guard_dir/selftest.out" 2>&1; then
  cat "$guard_dir/selftest.out"; echo "repo-change guard: BLIND (its control needles failed); refusing to run"; exit 2
fi
echo "repo-change guard: control needles ok ($(grep -c 'needle ok' "$guard_dir/selftest.out") of $(grep -c 'needle ' "$guard_dir/selftest.out"))"
guard_snapshot "$repo" >"$guard_dir/before"
if ! grep -q '^TOP \.git$' "$guard_dir/before" || ! grep -q '^OWN scripts/decisions/decisions_engine.py ' "$guard_dir/before"; then
  echo "repo-change guard: BLIND (the snapshot of the real repository lacks known records)"; exit 2
fi
strict="${DEC_REPO_GUARD_STRICT:-0}"
if [ "$strict" = 1 ]; then guard_strict_status "$repo" >"$guard_dir/strict.before"; touch "$guard_dir/stamp"; sleep 1; fi

# every suite runs from a scratch cwd, never the repo, so a cwd-relative write cannot land in the tree
mkdir -p "$guard_dir/cwd"; cd "$guard_dir/cwd" || exit 1
rcs=0
run() { echo "### $*"; "$@"; local rc=$?; echo "### rc=$rc"; [ "$rc" -eq 0 ] || rcs=1; }
run bash "$here/test_core.sh"
run bash "$here/test_round2.sh"
run bash "$here/test_round3.sh"
run bash "$here/test_round4.sh"
run bash "$here/test_round5.sh"
run bash "$here/test_round6.sh"
run bash "$here/test_round7.sh"
run bash "$here/test_round8.sh"
run bash "$here/test_round9.sh"
run bash "$here/test_round10.sh"
run bash "$here/test_round11.sh"
run bash "$here/test_tty_e2e.sh"
run bash "$here/test_chaos_stress.sh"
run bash "$repo/scripts/gates/cm_decisions_wizard_safety.sh"
run bash "$repo/scripts/gates/cm_decisions_override_valid_mutation_test.sh"
run bash "$repo/scripts/gates/cm_decisions_wizard_safety_mutation_test.sh"
run bash "$here/test_repo_guard_mutants.sh"
[ "${DEC_SKIP_OWN_MUTANTS:-0}" = 1 ] || run bash "$here/test_own_mutants.sh"

guard_snapshot "$repo" >"$guard_dir/after"
if guard_compare "$guard_dir/before" "$guard_dir/after" >"$guard_dir/diff"; then
  echo "repo-change guard (scoped): PASS ($(wc -l <"$guard_dir/before") records compared)"
else
  echo "repo-change guard (scoped): FAIL (this run can have caused these changes)"; cat "$guard_dir/diff"; rcs=1
fi
if [ "$strict" = 1 ]; then
  guard_strict_status "$repo" >"$guard_dir/strict.after"
  guard_strict_newer "$repo" "$guard_dir/stamp" >"$guard_dir/strict.newer"
  if cmp -s "$guard_dir/strict.before" "$guard_dir/strict.after" && [ ! -s "$guard_dir/strict.newer" ]; then
    echo "repo-change guard (strict): PASS (whole tree unchanged)"
  else
    echo "repo-change guard (strict): FAIL (the tree changed; expected in a busy shared tree)"
    diff "$guard_dir/strict.before" "$guard_dir/strict.after" | head -30
    echo "--- paths newer than the run start ($(wc -l <"$guard_dir/strict.newer")), by top-level entry"
    sed "s|^$repo/\{0,1\}||" "$guard_dir/strict.newer" | awk -F/ '{print ($1 == "" ? "." : $1)}' | sort | uniq -c
    echo "--- outside .git and .remember"
    sed "s|^$repo/||" "$guard_dir/strict.newer" | grep -Ev '^(\.git|\.remember)(/|$)' | head -100
    rcs=1
  fi
fi
echo "decisions run_all: $([ $rcs -eq 0 ] && echo ALL-PASS || echo FAILURES)"
exit $rcs
