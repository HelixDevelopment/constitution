#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh
# tests/pi-constitution/test_stress_perf.sh — stress/perf: run the audit N times against the
# same state and verify consistent results + bounded per-run time.
#
# Oracle strategy: DERIVED (all N runs must produce identical output; per-run time bounded).
#
# Run: bash tests/pi-constitution/test_stress_perf.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
. "$(dirname "$0")/lib.sh"
new_sandbox
T_NAME=stress_perf

P="$SB/proj"; make_project "$P"; add_constitution_dir "$P" submodules/constitution >/dev/null

N=10
first_out=""
all_ok=1
total_t0=$SECONDS
for i in $(seq 1 "$N"); do
  run_audit "$P"
  if [ "$AUDIT_RC" -ne 0 ]; then
    nok "stress run $i exit non-zero"
    all_ok=0
  fi
  if [ -z "$first_out" ]; then
    first_out="$AUDIT_OUT"
  elif [ "$AUDIT_OUT" != "$first_out" ]; then
    nok "stress run $i output differs from run 1"
    all_ok=0
  fi
done
total_t=$((SECONDS - total_t0))

eq "stress all $N runs healthy" 1 "$all_ok"
eq "stress output identical across $N runs" 1 "$all_ok"
echo "  info  stress_perf: $N runs in ${total_t}s (${total_t}s total)"
[ "$total_t" -lt 120 ] && ok "stress perf: $N runs under 120s" || nok "stress perf: $N runs took ${total_t}s (over 120s)"

# Stress against player repo too
for i in $(seq 1 3); do
  run_audit "$PLAYER"
  [ "$AUDIT_RC" -eq 0 ] && ok "stress player run $i exit 0" || nok "stress player run $i exit non-zero"
done

finish
