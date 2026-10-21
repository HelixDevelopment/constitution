#!/usr/bin/env bash
# scripts/label-sync/adapters/aider/aider-labelled.sh
#
# Purpose : Launch Aider so its session is registered, kept fresh and finished on
#           the label bus. Aider has no start/end hook, so the START/END half is
#           the generic supervising wrapper (generic/label-agent-run.sh) and the
#           "idle after each response" half is Aider's own notifications command
#           (aider-notify.sh), both bound to ONE entity via LABEL_SYNC_ENTITY_ID.
# Usage   : aider-labelled.sh [aider args...]      (replaces `aider`)
# Inputs  : the aider arguments (only `--model X` / `--model=X` is read, to show
#           the model; nothing else is inspected or recorded); env LABEL_SYNC_AIDER_BIN
#           overrides the aider executable (default `aider`).
# Outputs : aider's own output.
# Exit    : aider's exit status verbatim.
# Side-effects: appends `--notifications --notifications-command "bash <notify>"`
#           to THIS launch only (no config file is touched). If you pass your own
#           `--notifications-command` yours is kept and no idle updates occur.
# Deps    : bash, aider, label-agent-run.sh.
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
bin="${LABEL_SYNC_AIDER_BIN:-aider}"
mdl="" have_cmd=0 prev=""
for a in "$@"; do
  case "$a" in
    --model=*) mdl="${a#--model=}" ;;
    --notifications-command|--notifications-command=*) have_cmd=1 ;;
  esac
  [ "$prev" = "--model" ] && mdl="$a"
  prev="$a"
done
extra=()
if [ "$have_cmd" = 0 ]; then
  extra=(--notifications --notifications-command "bash $HERE/aider-notify.sh")
fi
exec bash "$HERE/../generic/label-agent-run.sh" --agent aider ${mdl:+--model "$mdl"} -- "$bin" "${extra[@]}" "$@"
