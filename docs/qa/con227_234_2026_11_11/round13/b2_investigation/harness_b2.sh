#!/bin/bash
# harness_b2.sh TREE TMPROOT TAG: run the standing harness of TREE with --only B2, as run_full_harness13.sh runs it
tree="${1:?}"; tr="${2:?}"; tag="${3:?}"
t="$(mktemp -d "$tr/t_$tag.XXXXXX")"; : "${t:?}"
echo "env: nofile_soft=$(ulimit -n) nofile_hard=$(ulimit -Hn) tasksmax=$(cat "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/pids.max")"
cd "$tree" || exit 2
TMPDIR="$t" bash tests/release/test_release_tooling_mutations.sh --only B2; echo "harness_rc=$?"
