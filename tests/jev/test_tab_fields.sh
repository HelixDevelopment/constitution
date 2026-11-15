#!/usr/bin/env bash
# test_tab_fields.sh (round 4, review R3-4): an EMPTY field in a TAB-separated row must stay empty.
# TAB is IFS whitespace, so `IFS=$'\t' read -r a b c` swallows an empty field and shifts the later fields left. Every Jev
# read site now reads with the unit separator (\x1f, not whitespace). Each case below is an empty field that used to shift:
#   F1 jev_usable_live: a healthy decide service with NO url and protocol jev-verdict is NOT usable (the protocol used to
#      land in the url variable, so the service counted as live). CONTROL: the same service with a url, and an
#      empty-url service with a usable protocol (counted).
#   F2 bootstrap: the same registry service is excluded from the detection record (the url used to become "jev-verdict").
#   F3 CM-JEV-DETECTION clause 6: an endpoint with an EMPTY id that claims reachable=true is still probe-replayed.
#   F4 CM-JEV-DETECTION clause 8: an endpoint with an EMPTY id, a key variable and reachable=null is still checked.
#   F5 jev-calibrate: a decision whose answer is "" keeps its endpoint|model attribution.
#   F6 (round 5, N1) STATIC: no Jev read site (scripts/jev, the skill, the cm_jev gates) reads with IFS=TAB.
# Keys are DUMMY values. Evidence class: gate-logic / unit (§11.4.289(C)(2)): stub tools, fixture records, no network.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -uo pipefail
export HELIX_TEST_MODE=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
RUT="${JEV_TAB_TREE_UNDER_TEST:-$REPO}"   # tree under test (a RED run points this at an export of the pre-fix tree)
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq git; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done

# ---- F1 ----
ul() { ( set +u; . "$RUT/scripts/jev/lib_decide.sh"; jev_usable_live "$1" "$2" ); }
CAP='{"decision_instances":{"decide-tiny":{"protocol":"jev-verdict"},"decide-a":{"protocol":"openai"}}}'
svc() { jq -nc --arg u "$2" --arg p "$1" '{profiles:[],registry:{services:[{name:"svc", healthy:true, labels:{kind:"decide", profile:$p}} + (if $u == "" then {} else {url:$u} end)]}}'; }
assert_eq "" "$(ul "$(svc decide-tiny "")" "$CAP")" "F1 an empty-url jev-verdict service is NOT usable"
assert_eq "" "$(ul "$(svc decide-tiny https://127.0.0.1:9001)" "$CAP")" "F1 CONTROL: the same service with a url is NOT usable"
assert_eq "service:svc" "$(ul "$(svc decide-a "")" "$CAP")" "F1 CONTROL: an empty-url service with a usable protocol IS counted"

# ---- F2 ----
make_fixture_env tabf2; make_fixture_constitution_root
mkdir -p "$T/constitution/scripts"; ln -s "$RUT/scripts/gates" "$T/constitution/scripts/gates"
jq -n '{gateway:{running:false},profiles:[],registry:{services:[{name:"svc",healthy:true,labels:{kind:"decide",profile:"decide-tiny"}}]}}' > "$T/status.json"
printf '%s' "$CAP" > "$T/cap.json"
LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json" bash "$RUT/scripts/jev/bootstrap.sh" --non-interactive >"$T/f2.out" 2>"$T/f2.err"
DET="$JEV_EVIDENCE_DIR/jev-detection.json"
assert_eq "0" "$(jq '[.endpoints[]? | select(.id == "llmctl-decide-tiny")] | length' "$DET" 2>/dev/null || echo missing)" "F2 the empty-url jev-verdict service is not recorded as an endpoint"
assert_eq "0" "$(jq '[.endpoints[]? | select((.url // "") == "jev-verdict")] | length' "$DET" 2>/dev/null || echo missing)" "F2 no endpoint carries the protocol as its url"
assert_contains "$DET" "decide-tiny excluded: protocol jev-verdict has no driver" "F2 the exclusion is recorded with its reason"

# ---- F3 / F4 ----
GATE="$RUT/scripts/gates/cm_jev_detection.sh"
printf '#!/bin/sh\necho "$*" >> "%s/probe.calls"\nexit 1\n' "$T" > "$T/probe-fail.sh"; chmod +x "$T/probe-fail.sh"
mkrec() { jq -n --argjson e "$1" '{schema_version:1, generated_at:1760000000, endpoints:[$e],
  key_discovery:{vars:[{key_var:"TYPESAFE_API_KEY", state:"real"}]}, capacity:{decision_instances:1}, tools:{}}' > "$2"; }
mkrec '{"id":"","source":"hosted","model":"jev-latest","reachable":true,"url":"https://api.typesafe.test/v1","probed_at":1760000000,"parallel":1}' "$T/f3.json"
JEV_DETECTION_FILE="$T/f3.json" JEV_PROBE_CMD="$T/probe-fail.sh" bash "$GATE" >"$T/f3.out" 2>&1
assert_contains "$T/f3.out" "probe: endpoint '' claimed reachable=true but probe replay FAILED" "F3 an empty-id endpoint claiming reachable=true is probe-replayed"
assert_contains "$T/probe.calls" "https://api.typesafe.test/v1" "F3 the probe received the url (not a shifted field)"
mkrec '{"id":"","source":"toolkit-cache","model":"jev-latest","reachable":null,"reachable_basis":"resolution-only","url":"https://api.typesafe.test/v1","key_var":"TYPESAFE_API_KEY","parallel":1}' "$T/f4.json"
JEV_DETECTION_FILE="$T/f4.json" JEV_PROBE_CMD="$T/probe-fail.sh" bash "$GATE" >"$T/f4.out" 2>&1
assert_contains "$T/f4.out" "(key variable TYPESAFE_API_KEY) holds a real key but reachable=null" "F4 an empty-id endpoint with a real key and reachable=null is still checked"

# ---- F5 ----
make_fixture_env tabf5
export JEV_TEST=1 JEV_CALIBRATE_ALIAS_CMD="jev-label-stub" JEV_CALIBRATE_MIN_SAMPLE=10
DEC="$JEV_STATE_DIR/decisions.jsonl"; : > "$DEC"
for i in $(seq 0 11); do
  jq -nc --argjson ts $((5000+i)) --arg q "q$i" '{ts:$ts, question_type:"gate", question:$q, criteria:{yes:"y",no:"n"}, answer:"",
    confidence:0.95, label_hint:"yes", mode:"shadow", endpoint:"typesafe", model:"jev-latest"}' >> "$DEC"
done
bash "$RUT/scripts/jev/jev-calibrate.sh" --now --sample 100 >"$T/f5.out" 2>"$T/f5.err"
THR="$JEV_CONFIG_DIR/jev-thresholds.json"
assert_eq "12" "$(jq -r '.per_endpoint["typesafe|jev-latest"].gate.n // "absent"' "$THR" 2>/dev/null || echo missing)" "F5 empty answers keep their endpoint|model (typesafe|jev-latest n=12)"
assert_eq "absent" "$(jq -r '.per_endpoint["unknown|unknown"].gate.n // "absent"' "$THR" 2>/dev/null || echo missing)" "F5 nothing is mis-attributed to unknown|unknown"

# ---- F6 (round 5, review N1): no Jev read site splits on TAB any more ----
# The two register.sh sites (the effective mode, the MCP mode rows) read two fields whose first one is never empty, so no
# shift is reachable with today's producers; the check keeps the convention for every read site so a third field cannot
# reintroduce the collapse. Comment lines do not count. CONTROLS: a planted TAB read is found, a \x1f read is not.
tabreads() { grep -HnF "IFS=\$'\\t' read" "$@" 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true; }
mapfile -t _srcs < <(find "$RUT/scripts/jev" "$RUT/skills/jev-decision-layer" -type f -name '*.sh' 2>/dev/null; ls "$RUT"/scripts/gates/cm_jev*.sh 2>/dev/null)
assert_ne "0" "${#_srcs[@]}" "F6 the scan sees the Jev sources (${#_srcs[@]})"
_tr="$(tabreads "${_srcs[@]}")"
if [ -z "$_tr" ]; then ok "F6 no Jev read site uses IFS=TAB"; else fail "F6 TAB read sites remain: $(printf '%s' "$_tr" | sed "s|$RUT/||" | tr '\n' ' ' | cut -c1-300)"; fi
_pd="$(mktemp -d)"; _JEV_FIXTURE_DIRS+=("$_pd")
printf '%s\n' '#!/bin/sh' "IFS=\$'\\t' read -r a b <x" > "$_pd/planted.sh"; printf '%s\n' '#!/bin/sh' "IFS=\$'\\x1f' read -r a b <x" > "$_pd/clean.sh"
assert_eq "1" "$(tabreads "$_pd/planted.sh" | grep -c .)" "F6 CONTROL: a planted TAB read is found"
assert_eq "0" "$(tabreads "$_pd/clean.sh" | grep -c .)" "F6 CONTROL: a unit-separator read is not"
finish
