#!/usr/bin/env bash
# scripts/label-sync/adapters/codex/codex-notify.sh
#
# Purpose : OpenAI Codex CLI `notify` program -> label bus. Codex invokes the
#           configured program after each completed agent turn and passes ONE
#           argument: a JSON document (documented event: `agent-turn-complete`
#           with `thread-id`, `turn-id`, `cwd`, ...). Mapped to a heartbeat on
#           the thread's entity.
# Usage   : ~/.codex/config.toml   notify = ["bash", "<this script>"]
#           Manual: codex-notify.sh '{"type":"agent-turn-complete","thread-id":"t1","cwd":"/x"}'
# Inputs  : argv[1] JSON (only type, thread-id, cwd are read — `input-messages`
#           and `last-assistant-message` are NEVER parsed); env LABEL_SYNC_ENTITY_ID
#           (set by generic/label-agent-run.sh) overrides the entity id.
# Outputs : nothing.
# Exit    : ALWAYS 0.
# STATUS  : UNCONFIRMED — Codex is NOT installed on the host this was written on.
#           The payload shape is the documented one from memory of the upstream
#           project, never exercised against a real Codex (§11.4.6). The
#           guaranteed path for Codex is generic/label-agent-run.sh.
# Side-effects: labelctl calls. Deps: bash, jq (absent => no-op).
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
al_init || exit 0
command -v jq >/dev/null 2>&1 || exit 0
payload="${1:-}"
[ -n "$payload" ] || exit 0
parsed="$(printf '%s' "$payload" | jq -r 'select(type=="object") |
  [(.type // ""), (."thread-id" // .thread_id // ""), (.cwd // "")] | map(gsub("[[:cntrl:]]";"")) | join("\u001f")' 2>/dev/null)" || exit 0
IFS=$'\037' read -r typ thread cwd <<<"${parsed:-}"
[ "$typ" = "agent-turn-complete" ] || exit 0
[ -n "$thread" ] || [ -n "${LABEL_SYNC_ENTITY_ID:-}" ] || exit 0
sess="${thread:-env}"; [ -n "${LABEL_SYNC_ENTITY_ID:-}" ] && sess="env"
al_upsert codex "$sess" "$cwd" "" "" idle
exit 0
