#!/bin/bash
# runscope.sh <unit> <tasksmax> <log> <cmd...>: run cmd in a user scope, record pids.peak and pids.events after
set -u
u="${1:?}"; tm="${2:?}"; log="${3:?}"; shift 3
systemd-run --user --scope -q --unit="$u" -p TasksMax="$tm" bash -c '
  cg="/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)"
  echo "scope $0 cgroup $cg pids.max $(cat $cg/pids.max) load $(cut -d" " -f1-3 /proc/loadavg) start $(date -Is)"
  nice -n 10 "$@"; rc=$?
  echo "rc=$rc end $(date -Is) pids.peak $(cat $cg/pids.peak 2>/dev/null || echo unreadable) pids.events $(tr "\n" " " <$cg/pids.events 2>/dev/null)"
  exit $rc' "$u" "$@" >"$log" 2>&1
