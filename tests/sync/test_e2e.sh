#!/usr/bin/env bash
# tests/sync/test_e2e.sh -- END-TO-END tests: the wrapper exactly as a user runs it (no --out, no --root, from a
# subdirectory of the project), with the evidence checked field by field: schema id, run id, per-repository
# before/after SHAs against `git rev-parse`, timestamps, exit code, control needle, TSV column set, and the
# default evidence location under $XDG_CACHE_HOME. Real git, sandbox, no network.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
T_NAME=sync-e2e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
o="$(bash "$SX_ENGINE" --help 2>&1)"; rc=$?
eq "--help: exit 0" 0 "$rc"
has "--help lists --apply" "--apply" "$o"
sx_std_tree
sx_commit "$U_ROOT" "r1"
mkdir -p "$W/sub/dir"; old_root="$(sx_head "$W")"
out="$(cd "$W/sub/dir" && bash "$SX_ENGINE" --apply --run-id e2e-1 2>"$SB/e2e.err")"; rc=$?
eq "user run from a subdirectory: exit 0" 0 "$rc"
J="$(sed -n 's/^REPORT_JSON=//p' <<<"$out")"
eq "default evidence under XDG_CACHE_HOME" "$XDG_CACHE_HOME/helix_sync_upstreams/root-e2e-1/sync_report.json" "$J"
SX_JSON="$J"
eq "schema id" "helix.sync_upstreams/1" "$(sx_q 'r["schema"]')"
eq "run id" "e2e-1" "$(sx_q 'r["run_id"]')"
eq "mode" "apply" "$(sx_q 'r["mode"]')"
eq "exit code recorded" "0" "$(sx_q 'r["exit_code"]')"
eq "verdict recorded" "APPLIED" "$(sx_q 'r["verdict"]')"
eq "control needle recorded and ok" "True" "$(sx_q 'r["control_needle"]["ok"] and int(r["control_needle"]["count"])>=1')"
eq "timestamps are UTC ISO-8601" "True" "$(sx_q 'r["started"].endswith("Z") and r["ended"].endswith("Z") and r["started"]<=r["ended"]')"
eq "root head_before = pre-run HEAD" "$old_root" "$(sx_q 'P["."]["head_before"]')"
eq "root head_after = HEAD now" "$(sx_head "$W")" "$(sx_q 'P["."]["head_after"]')"
eq "root action recorded (fast-forward rc 0)" "fast-forward 0" "$(sx_q 'P["."]["actions"][0]["op"]+" "+str(P["."]["actions"][0]["rc"])')"
eq "every repository has a result" "True" "$(sx_q 'all(x.get("result") for x in r["repos"])')"
eq "canonical hash recorded" "64" "$(sx_q 'len(r["canonical_sha256"])')"
T="$(dirname "$J")/sync_report.tsv"
eq "TSV header" "path kind depth initialised branch head_before head_after target upstream_state local_vs_target pin_state pin_behind_main own_org result reasons remotes" "$(head -n1 "$T" | tr '\t' ' ')"
eq "TSV row per repository" "4" "$(tail -n +2 "$T" | wc -l | tr -d ' ')"
eq "TSV root row result" "updated" "$(awk -F'\t' '$1=="."{print $14}' "$T")"
has "stderr summary lists the root" "updated" "$(cat "$SB/e2e.err")"
# exit-code contract end to end: 3 behind, 4 attention, 2 usage
sx_commit "$U_ROOT" "r2"
(cd "$W" && bash "$SX_ENGINE" --check --quiet >/dev/null 2>&1); eq "contract: behind -> 3" 3 "$?"
echo x >>"$W/README"
(cd "$W" && bash "$SX_ENGINE" --check --quiet >/dev/null 2>&1); eq "contract: dirty -> 4" 4 "$?"
(cd "$W" && bash "$SX_ENGINE" --check --dry-run >/dev/null 2>&1); eq "contract: two modes -> 2" 2 "$?"
(cd "$W" && bash "$SX_ENGINE" --check --run-id '../x' >/dev/null 2>&1); eq "contract: bad run id -> 2" 2 "$?"
finish
