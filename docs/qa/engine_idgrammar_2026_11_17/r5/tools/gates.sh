#!/usr/bin/env bash
# Round-5 gate runner: runs each gate from the repo root, one at a time,
# writes <out>/<name>.out and a gates.tsv row "name rc seconds last-line".
# Usage: gates.sh <repo-root> <out-dir>   (<out-dir> must not exist)
set -u
ROOT="${1:?repo root}"; OUT="${2:?out dir}"
[ -e "$OUT" ] && { echo "exists $OUT" >&2; exit 64; }
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
cd "$ROOT" || exit 1
export TMPDIR=/mnt/DATA1TB/claude-work/tmp GOCACHE=/mnt/DATA1TB/claude-work/gocache GOPROXY=off
run() {
  local name="$1"; shift
  until awk '{exit !($1<50)}' /proc/loadavg; do sleep 20; done
  local t0=$SECONDS
  systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 "$@" >"$OUT/$name.out" 2>&1
  local rc=$?
  printf '%s\t%s\t%ss\t%s\n' "$name" "$rc" "$((SECONDS - t0))" "$(grep -v '^\s*$' "$OUT/$name.out" | tail -1)" >>"$OUT/gates.tsv"
}
run verify_manifest bash scripts/run_full_suite.sh --verify-manifest
run cm_full_suite_manifest_complete bash scripts/gates/cm_full_suite_manifest_complete.sh
run cm_gate_ledger_ratchet bash scripts/gates/cm_gate_ledger_ratchet.sh
run cm_constitution_index_fresh bash scripts/gates/cm_constitution_index_fresh.sh
run gitenv_census python3 -I scripts/validation/git_env_class_census.py
run cm_helix_deps_manifest_present bash scripts/gates/cm_helix_deps_manifest_present.sh
run cm_state_fields_anchor_wired bash scripts/gates/cm_state_fields_anchor_wired.sh
run cm_repro_first_anchor_wired bash scripts/gates/cm_repro_first_anchor_wired.sh
run cm_reporting_directives bash scripts/gates/cm_reporting_directives.sh
run cm_feature_directive bash scripts/gates/cm_feature_directive.sh
run test_report_item_bug_states bash tests/reporting/test_report_item_bug_states.sh
run us3_shipped_engine bash scripts/fastcycle/tests/test_shipped_workable_items_us3_red.sh
run test_constitution_cmd bash tests/constitution_cmd/test_constitution_cmd.sh
run cm_state_fields_anchor_wired_mutation_test bash scripts/gates/cm_state_fields_anchor_wired_mutation_test.sh
run cm_repro_first_anchor_wired_mutation_test bash scripts/gates/cm_repro_first_anchor_wired_mutation_test.sh
# Note requested by the brief: sh -n on the anchor-wired gates (recorded, pre-existing).
for g in cm_state_fields_anchor_wired cm_repro_first_anchor_wired; do
  sh -n "scripts/gates/$g.sh" >"$OUT/sh_n_$g.out" 2>&1; echo "sh -n $g rc=$?" >>"$OUT/sh_n.txt"
  bash -n "scripts/gates/$g.sh" >>"$OUT/sh_n_$g.out" 2>&1; echo "bash -n $g rc=$?" >>"$OUT/sh_n.txt"
done
echo GATES-DONE >>"$OUT/gates.tsv"
