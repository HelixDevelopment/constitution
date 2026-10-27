#!/usr/bin/env bash
# scripts/label-sync/adapters/aider/aider-notify.sh
#
# Purpose : Aider `--notifications-command` target -> label bus. Aider runs this
#           command each time it finishes a response and is waiting for the user
#           (the same moment it would ring the terminal bell). That is the only
#           lifecycle signal Aider exposes, so it maps to "idle" (heartbeat).
# Usage   : aider --notifications --notifications-command "bash <this script>"
#           (install_adapters.sh writes exactly this into ~/.aider.conf.yml;
#           aider-labelled.sh does it per launch AND registers/unregisters).
# Inputs  : env LABEL_SYNC_ENTITY_ID (set by aider-labelled.sh, inherited by the
#           command); else the id is `aider-pid<pid of the nearest ancestor named
#           aider>`. Aider passes no payload and none is read.
# Outputs : nothing.
# Exit    : ALWAYS 0.
# Limits  : Aider has no start/end hook: without aider-labelled.sh the entity is
#           created on the first notification (so a never-notifying session is
#           invisible) and ends by TTL staleness. Model/effort unknown => `?`
#           unless aider-labelled.sh saw `--model` on the command line.
# Side-effects: labelctl calls. Deps: bash.
# Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md (capability: SCHEMA-ONLY).
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../lib/adapter_lib.sh"
al_init || exit 0
apid="$(al_find_pid aider)"
sess="env"; [ -n "${LABEL_SYNC_ENTITY_ID:-}" ] || sess="pid${apid:-unknown}"
LABEL_SYNC_AGENT_PID="${LABEL_SYNC_AGENT_PID:-$apid}" al_upsert aider "$sess" "$PWD" "${LABEL_SYNC_AGENT_MODEL:-}" "" idle
exit 0
