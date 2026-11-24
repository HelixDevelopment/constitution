#!/usr/bin/env bash
# scripts/hooks/issue_sync_post_merge.sh -- git post-merge hook of the workable-items Issues mirror (anchor §11.4.300(E), §11.4.88 style).
# After a merge: if the project's config is enabled AND mode: apply (with apply_decision) it starts `issue_sync.sh apply --apply` DETACHED in the
# background under a lock (the git command returns at once); otherwise it does nothing. Default OFF. Never runs in CI. Honours ISSUE_SYNC_TARGETS
# (space separated HOST/OWNER/REPO list), ISSUE_SYNC_OWNER_REPO, ISSUE_SYNC_DB_REPO (parent-prefix owner) and ISSUE_SYNC_PRIVATE_CORPUS; without them it logs that targets are undeclared and exits 0.
# Side-effects: background network writes to the declared trackers; log at .git/issue-sync.log. Classification: universal (§11.4.17).
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
CFG="$ROOT/.workable-items-sync.yaml"; DB="$ROOT/docs/workable_items.db"
[ -f "$CFG" ] && [ -f "$DB" ] || exit 0
HOME_S="${ISSUE_SYNC_HOME:-$ROOT/submodules/constitution/scripts}"; [ -d "$HOME_S/issue_sync" ] || HOME_S="$ROOT/scripts"
[ -x "$HOME_S/issue_sync.sh" ] || exit 0
LOG="$(git rev-parse --git-dir)/issue-sync.log"
# the effective mode comes from the engine's own validator (never a grep of the YAML): an invalid or disabled declaration is never ON
MODE=$(PYTHONPATH="$HOME_S${PYTHONPATH:+:$PYTHONPATH}" python3 -W ignore -m issue_sync.mode "$CFG" 2>/dev/null) || { echo "$(date -u +%FT%TZ) skipped: config invalid" >>"$LOG"; exit 0; }
[ "$MODE" = "apply" ] || exit 0
if [ -z "${ISSUE_SYNC_TARGETS:-}" ] || [ -z "${ISSUE_SYNC_OWNER_REPO:-}" ]; then echo "$(date -u +%FT%TZ) skipped: ISSUE_SYNC_TARGETS / ISSUE_SYNC_OWNER_REPO undeclared" >>"$LOG"; exit 0; fi
args=(); for t in $ISSUE_SYNC_TARGETS; do args+=(--target "$t"); done
args+=(--db-repo "${ISSUE_SYNC_DB_REPO:-$ISSUE_SYNC_OWNER_REPO}")
( cd "$ROOT" && exec flock -n "$(git rev-parse --git-dir)/issue-sync.lock" "$HOME_S/issue_sync.sh" apply --apply --config "$CFG" --db "$DB" --owner-repo "$ISSUE_SYNC_OWNER_REPO" "${args[@]}" ) >>"$LOG" 2>&1 </dev/null &
disown 2>/dev/null; exit 0
