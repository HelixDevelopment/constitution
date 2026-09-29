#!/bin/sh
# Runs INSIDE `unshare -Urpf --mount-proc`: $1 = tests dir. Runs check_deps.sh under a strace write delay so
# the reuse escapee wins the window before its EXIT cleanup. Prints REUSED-ALIVE | REUSED-DEAD | NOREUSE.
TD=$1; PF=$TD/fixtures/triple_harness; D=$(mktemp -d); W=$D/W; mkdir "$W"
export PR_DIR=$D PR_HERE=$PF
for b in timeout mktemp head rm sh bash strace setsid sleep cat awk; do ln -s "$(command -v $b)" "$W/$b"; done
cp "$PF/pidreuse_mmdc.sh" "$W/mmdc"; chmod +x "$W/mmdc"
PATH=$W strace -e trace=write -e inject=write:delay_enter=700000 -o /dev/null sh "$TD/check_deps.sh" >/dev/null 2>&1
sleep 1
[ -s "$D/reuse.pid" ] || { echo NOREUSE; exit 0; }
if kill -0 "$(cat "$D/reuse.pid")" 2>/dev/null; then echo REUSED-ALIVE; else echo REUSED-DEAD; fi
