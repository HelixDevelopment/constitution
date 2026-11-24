#!/usr/bin/env bash
# scripts/hooks/issue_sync_pre_commit.sh -- git pre-commit hook of the workable-items Issues mirror (anchor §11.4.300(E)).
# Offline (no network, no write): refuses the commit when the workable-items DB holds changes that the mirror map does not yet reflect,
# unless acknowledged with ISSUE_SYNC_ACK=1 in the environment. DEFAULT OFF: no .workable-items-sync.yaml, enabled:false, or no DB => exit 0.
# Usage: installed as .git/hooks/pre-commit chain (or called from one) at the repository root. Exit: 0 allow, 1 refuse.
# Side-effects: none. Dependencies: bash, python3, PyYAML; the constitution scripts dir via ISSUE_SYNC_HOME or ./submodules/constitution/scripts.
# Classification: universal (§11.4.17).
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
CFG="$ROOT/.workable-items-sync.yaml"; DB="$ROOT/docs/workable_items.db"
[ -f "$CFG" ] && [ -f "$DB" ] || exit 0
HOME_S="${ISSUE_SYNC_HOME:-$ROOT/submodules/constitution/scripts}"; [ -d "$HOME_S/issue_sync" ] || HOME_S="$ROOT/scripts"
[ -d "$HOME_S/issue_sync" ] || exit 0
export PYTHONPATH="$HOME_S${PYTHONPATH:+:$PYTHONPATH}"
out=$(cd "$ROOT" && python3 -W ignore -m issue_sync.cli status --config "$CFG" --db "$DB" --owner-repo "${ISSUE_SYNC_OWNER_REPO:-github.com/unknown/unknown}" 2>&1); rc=$?
case "$out" in disabled*) exit 0 ;; esac
[ "$rc" -eq 0 ] && exit 0
if [ "${ISSUE_SYNC_ACK:-0}" = "1" ]; then echo "issue-sync: pending mirror changes acknowledged (ISSUE_SYNC_ACK=1): $out" >&2; exit 0; fi
echo "issue-sync: commit refused -- workable-items changes are not yet reflected in the Issues mirror: $out" >&2
echo "issue-sync: run 'bash $HOME_S/issue_sync.sh plan ...' to review and apply per the project's mode, or commit with ISSUE_SYNC_ACK=1." >&2
exit 1
