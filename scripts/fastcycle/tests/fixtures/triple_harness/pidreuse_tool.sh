#!/bin/sh
# Test tool for the harness pid-reuse test: on the golden-bad fixture it starts an escapee (own session)
# that reuses the dead timeout pid, then TERMs the harness; it prints a large "REC" line so the harness
# stays busy after its kill_group. Env: PR_DIR (state dir), PR_HERE (fixtures dir holding the escapee).
case $(cat "$1") in
  bad)
    T=$PPID; H=$(awk '{print $4}' "/proc/$T/stat")
    setsid sh "$PR_HERE/pidreuse_escapee.sh" "$T" "$PR_DIR" "$H" >/dev/null 2>&1 </dev/null &
i=0; while [ ! -e "$PR_DIR/ready.$T" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
    awk 'BEGIN { for (i = 0; i < 100000; i++) printf "RECx "; print "REC" }'
    exit 1 ;;
  good|neg) [ "$(cat "$1")" = good ] && exit 0; exit 0 ;;
esac
