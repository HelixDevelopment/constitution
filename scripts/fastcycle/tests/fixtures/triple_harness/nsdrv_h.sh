#!/bin/sh
# Runs INSIDE `unshare -Urpf --mount-proc`: $1 = tests dir. Prints REUSED-ALIVE | REUSED-DEAD | NOREUSE.
TD=$1; PF=$TD/fixtures/triple_harness; D=$(mktemp -d)
export PR_DIR=$D PR_HERE=$PF
FASTCYCLE_TOOL_TIMEOUT=20 sh "$TD/lib/triple_harness.sh" --tool "$PF/pidreuse_tool.sh" --fixtures "$PF/pidreuse" >/dev/null 2>&1
sleep 1
[ -s "$D/reuse.pid" ] || { echo NOREUSE; exit 0; }
if kill -0 "$(cat "$D/reuse.pid")" 2>/dev/null; then echo REUSED-ALIVE; else echo REUSED-DEAD; fi
