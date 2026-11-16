#!/usr/bin/env bash
# tests/sync/test_perf.sh -- PERFORMANCE / BENCHMARK of scripts/sync/sync_all_upstreams.sh on a synthetic tree:
# a root with 30 own-org submodules (real git, sandbox). Measures wall time of --check at --jobs 1 and
# --jobs 4, counts fetch calls (must be exactly one per remote: 31) and git calls per repository, and
# writes a TSV benchmark row to $SB/bench.tsv (printed). Bounds are generous and host-load tolerant: the
# point is a regression guard on call COUNTS (exact) and a sanity bound on time (loose).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
T_NAME=sync-perf
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
N=30
U_R="$(sx_bare HelixDevelopment perfroot)"
w="$(sx_seed "$U_R")"
for i in $(seq 1 $N); do
  u="$(sx_bare HelixDevelopment "p$i")"
  git -C "$w" -c protocol.file.allow=always submodule add -q "$u" "mods/p$i" >/dev/null 2>&1
done
git -C "$w" commit -q -m "add $N submodules" && git -C "$w" push -q origin main
W="$SB/work/perf"; sx_clone "$U_R" "$W"
ms() { date +%s%3N; }
printf 'jobs\twall_ms\tfetch_calls\tgit_calls\trepos\n' >"$SB/bench.tsv"
for j in 1 4; do
  : >"$SB/git_calls.log"; t0=$(ms); sx_run --check --jobs "$j" --root "$W"; t1=$(ms)
  f="$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"; g="$(wc -l <"$SB/git_calls.log" | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$j" "$((t1-t0))" "$f" "$g" "$(sx_q 'r["counts"]["repos"]')" >>"$SB/bench.tsv"
  eq "jobs $j: exit 0" 0 "$SX_RC"
  eq "jobs $j: $((N+1)) repositories" "$((N+1))" "$(sx_q 'r["counts"]["repos"]')"
  eq "jobs $j: exactly one fetch per remote" "$((N+1))" "$f"
  eq "jobs $j: report records the job count" "$j" "$(sx_q 'r["jobs"]')"
  [ "$g" -le $(( (N+1) * 16 )) ] && ok "jobs $j: git calls $g <= 16 per repository" || nok "jobs $j: git calls $g > 16 per repository"
  [ "$((t1-t0))" -lt 180000 ] && ok "jobs $j: wall $((t1-t0)) ms < 180 s" || nok "jobs $j: wall $((t1-t0)) ms"
done
eq "jobs ceiling: 1000 is clamped to at most 8" "True" "$(sx_run --check --no-fetch --jobs 1000 --root "$W"; sx_q 'r["jobs"] <= 8')"
echo "-- benchmark (host load at start: $(cut -d' ' -f1-3 /proc/loadavg))"; cat "$SB/bench.tsv"
finish
