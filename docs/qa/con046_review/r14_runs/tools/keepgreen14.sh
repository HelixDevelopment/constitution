#!/usr/bin/env bash
# keepgreen14.sh <repo> <out>: the round-14 keep-green checks (git-env census, index freshness, ledger ratchet,
# --sync-guide idempotence, --verify-manifest, workable-items engine validate and diff); one section per check,
# each with its own exit status. Read-only on the repo except --sync-guide, which must leave the guide unchanged.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
set -u; repo="${1:?repo}"; out="${2:?out}"; cd "$repo" || exit 2
E=scripts/workable-items/bin/workable-items
sec() { name="$1"; shift; echo "## $name"; "$@" >"$out.tmp" 2>&1; rc=$?; tail -n 3 "$out.tmp"; echo "rc $rc"; }
{
  echo "head $(git rev-parse HEAD) index-tree $(git write-tree)"
  sec git_env_class_census python3 -I scripts/validation/git_env_class_census.py
  sec index_fresh bash scripts/gates/cm_constitution_index_fresh.sh
  sec ledger_ratchet bash scripts/gates/cm_gate_ledger_ratchet.sh
  g0="$(sha256sum docs/guides/full_suite_runner_guide.md)"
  sec sync_guide bash scripts/run_full_suite.sh --sync-guide
  [ "$g0" = "$(sha256sum docs/guides/full_suite_runner_guide.md)" ] && echo "guide unchanged by --sync-guide" || echo "GUIDE CHANGED by --sync-guide"
  sec verify_manifest bash scripts/run_full_suite.sh --verify-manifest
  sec engine_validate "$E" validate --db docs/workable_items.db
  sec engine_diff "$E" diff --db docs/workable_items.db --issues docs/Issues.md --fixed docs/Fixed.md
} >"$out"
rm -f "${out:?}.tmp"
