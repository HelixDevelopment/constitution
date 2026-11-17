#!/usr/bin/env bash
# test_calibrate_per_endpoint.sh — S3/S4 calibration producer (2026-11-12): thresholds per (endpoint, model) and the
# main-LLM alias discovery of scripts/jev/jev-calibrate.sh. GATE-LOGIC test (§11.4.289(C)(2)): the labeler is the
# label_hint stub, so this proves the arithmetic and the bookkeeping, never that a real model labels well.
#   C1 per_endpoint["<endpoint>|<model>"][<type>] exists for every (endpoint, model) seen in the labelled sample
#   C2 a group that meets the min sample and the floor enforces; a group below the min sample stays shadow
#   C3 rows with no endpoint/model are grouped as "unknown|unknown" (counted, never dropped silently)
#   C4 the per_type aggregate is unchanged by the grouping (backward compatible)
#   C5 main-LLM alias: --alias wins; else MAIN_LLM_ALIAS (env); else MAIN_LLM_ALIAS in $JEV_CONFIG_DIR/env; else $JEV_CONFIG_DIR/main_llm_alias; else "claude" (default);
#      the record names the alias AND where it came from; an unsafe alias in the file is refused (rc 2)
#   C6 (round 2, review RM11) the precedence is pinned PAIRWISE with both sources present: env beats envfile, envfile beats file
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export FIXTURES="$HERE/fixtures"; REPO="$(cd "$HERE/../.." && pwd)"
source "$HERE/lib_assert.sh"
command -v jq >/dev/null 2>&1 || { assert_skip "jq absent"; finish; exit $?; }

make_fixture_env calep
export JEV_TEST=1 JEV_CALIBRATE_ALIAS_CMD="jev-label-stub" JEV_CALIBRATE_MIN_SAMPLE=10
DEC="$JEV_STATE_DIR/decisions.jsonl"; : > "$DEC"
emit() { # emit <endpoint|-> <model|-> <count> <hint> <ts>
  local i ep="$1" m="$2"
  for ((i=0; i<$3; i++)); do
    jq -nc --argjson ts $(($5+i)) --arg ep "$ep" --arg m "$m" --arg h "$4" --arg q "q$5-$i" \
      '{ts:$ts, question_type:"gate", question:$q, criteria:{yes:"y",no:"n"}, answer:"yes", confidence:0.95, label_hint:$h, mode:"shadow"}
       + (if $ep=="-" then {} else {endpoint:$ep} end) + (if $m=="-" then {} else {model:$m} end)' >> "$DEC"
  done
}
emit typesafe jev-latest 12 yes 1000
emit openrouter typesafe/jev-1.13 4 yes 2000
emit - - 3 no 3000
THR="$JEV_CONFIG_DIR/jev-thresholds.json"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >"$T/c.out" 2>"$T/c.err"; rc=$?
assert_rc 0 "$rc" "calibrate rc 0"
assert_eq 12 "$(jq -r '.per_endpoint["typesafe|jev-latest"].gate.n' "$THR")" "C1 typesafe|jev-latest gate n=12"
assert_eq 4 "$(jq -r '.per_endpoint["openrouter|typesafe/jev-1.13"].gate.n' "$THR")" "C1 openrouter|typesafe/jev-1.13 gate n=4"
assert_eq enforce "$(jq -r '.per_endpoint["typesafe|jev-latest"].gate.mode' "$THR")" "C2 group meeting min sample + floor enforces"
assert_eq shadow "$(jq -r '.per_endpoint["openrouter|typesafe/jev-1.13"].gate.mode' "$THR")" "C2 group below min sample stays shadow"
assert_eq 3 "$(jq -r '.per_endpoint["unknown|unknown"].gate.n' "$THR")" "C3 rows without endpoint/model grouped as unknown|unknown"
assert_eq 19 "$(jq -r '.per_type.gate.n' "$THR")" "C4 per_type aggregate still covers every labelled row"
assert_eq "claude default" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C5 default alias recorded with its source"

MAIN_LLM_ALIAS=claude7 bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>&1
assert_eq "claude7 env:MAIN_LLM_ALIAS" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C5 MAIN_LLM_ALIAS env discovered"
printf 'JEV_MODE=shadow\nMAIN_LLM_ALIAS=claude5\n' > "$JEV_CONFIG_DIR/env"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>&1
assert_eq "claude5 envfile:MAIN_LLM_ALIAS" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C5 MAIN_LLM_ALIAS in the jev env file discovered (user manual §7)"
rm -f "$JEV_CONFIG_DIR/env"
printf 'claude3\n' > "$JEV_CONFIG_DIR/main_llm_alias"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>&1
assert_eq "claude3 file:main_llm_alias" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR" | sed 's#file:.*/main_llm_alias#file:main_llm_alias#')" "C5 alias file discovered"
MAIN_LLM_ALIAS=claude7 bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 --alias claude9 >/dev/null 2>&1
assert_eq "claude9 arg" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C5 --alias wins over env and file"
# ---- C6 pairwise precedence with BOTH sources present (review RM11) -------------------------------------------------
printf 'claude3\n' > "$JEV_CONFIG_DIR/main_llm_alias"
printf 'JEV_MODE=shadow\nMAIN_LLM_ALIAS=claude5\n' > "$JEV_CONFIG_DIR/env"
MAIN_LLM_ALIAS=claude7 bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>&1
assert_eq "claude7 env:MAIN_LLM_ALIAS" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C6 env MAIN_LLM_ALIAS beats the env FILE when both are set"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>&1
assert_eq "claude5 envfile:MAIN_LLM_ALIAS" "$(jq -r '.main_llm_alias | "\(.name) \(.source)"' "$THR")" "C6 the env FILE beats the alias file when both exist"
rm -f "$JEV_CONFIG_DIR/env" "$JEV_CONFIG_DIR/main_llm_alias"
printf 'bad alias;rm\n' > "$JEV_CONFIG_DIR/main_llm_alias"
bash "$REPO/scripts/jev/jev-calibrate.sh" --now --sample 100 >/dev/null 2>"$T/bad.err"; rc=$?
assert_rc 2 "$rc" "C5 unsafe alias in the alias file refused (rc 2)"
finish
