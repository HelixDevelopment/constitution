#!/usr/bin/env bash
# lognorm14.sh <log>...: prints, per targeted-run log, the raw sha256 and the sha256 after removing exactly the
# host-state lines: `note` lines (the resource-failure retry notes), the `cgroup pids/oom event counter` line, and
# the event-counter numbers `events N->M` (the cgroup's pids/oom event count at that moment). Every verdict line
# is kept, so two logs with the same normalised hash have the same verdicts in the same order.
set -u
for f in "$@"; do
  raw="$(sha256sum <"$f" | cut -d' ' -f1)"
  norm="$(grep -v -e '^note' -e '^cgroup pids/oom event counter' "$f" | sed -E 's/events [0-9]+->[0-9]+/events N->N/g' | sha256sum | cut -d' ' -f1)"
  printf '%s raw=%s norm=%s\n' "$f" "$raw" "$norm"
done
