#!/bin/sh
# Test double for the LAST check_deps probe (mmdc): its --version starts an escapee that reuses the dead
# timeout pid. Env: PR_DIR, PR_HERE.
T=$PPID
setsid sh "$PR_HERE/pidreuse_escapee.sh" "$T" "$PR_DIR" >/dev/null 2>&1 </dev/null &
i=0; while [ ! -e "$PR_DIR/ready.$T" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
echo "mmdc 1.0"; exit 0
