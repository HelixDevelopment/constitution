#!/usr/bin/env bash
# test_security_scripts_mutations.sh -- paired §1.1 mutations for the three
# scripts/security tools: each mutant re-introduces one defect the independent
# review found (or one this fix guards) into a COPY of the script, and the
# matching hermetic test must then FAIL. A surviving mutant fails this test.
#
# Ids FM1-FM11, AM1-AM5, HM1-HM4 re-state the reviewer's 21 mutants (2026-11-12)
# against the fixed scripts (AM3 "single-org check" becomes "the pinned-scope
# check", since apply is now pinned to a repo list); the other ids are the
# fixer's own. Round 2 (review r2, 2026-11-12): RM*/AR*/HR* re-state the
# reviewer's surviving mutants (RM6/RM9/RM12/RM13, AR2-AR6, HR1/HR3/HR6/HR8/HR10
# were already killed and are not repeated); FM25-FM35, AM14, AM16, AM17 and HM13
# are the round-2 fixer's own for F1-F3/F5. FM10 now matches `|| return 2` (the
# read-back moved into branch_rules_ok, same check). Recorded as equivalent, not
# in the table: RM6-style removal of the per-request bound_ok check in req()
# (start-up refuses every unbound target first), the self-referential token
# mutant (token from the input file: equal to the allowlist token whenever the
# allowlist check passes). The round-2 claim that removing LC_ALL=C is an
# equivalent, environment-dependent mutant was WRONG (review r3 F4): the test
# now pins LC_ALL=en_US.UTF-8 for one plan and one apply case, and the mutant
# is row Y4 (killed). Round 3 (review r3, 2026-11-12): X3, X6-X15, X17, X18,
# Y7, Z3, Z4, Z8 are the reviewer's 17 mutants VERBATIM (its table has no X1,
# X2, X4, X5 or X16), Y4 is its locale mutant in table form, and R3* are the
# round-3 fixer's own on the token-binding, apply-tuple, exit-order, proxy,
# gh-host, curl and keys-file classes.
# Each mutation must match its script EXACTLY ONCE (else the
# mutant is reported BROKEN and the run fails), and the unmutated copies must
# pass first (control).
#
# Usage: bash tests/security/test_security_scripts_mutations.sh [ID ...]
# Exit: 0 every selected mutant killed and the controls pass; 1 otherwise;
#       2 environment error. Heavy tier (about 60 minutes for all mutants).
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/scripts/security"; ln -s "$here/scripts/lib" "$tmp/scripts/lib"
command -v python3 >/dev/null 2>&1 || { echo "env: python3 missing" >&2; exit 2; }

# id <TAB> script <TAB> python repr of the old text <TAB> python repr of the new text
cat > "$tmp/mutants.tsv" <<'EOF'
FM1	forge_branch_protect.sh	'[ "${FORGE_PROTECT_APPLY:-}" = yes ] || refuse'	'true || refuse'
FM2	forge_branch_protect.sh	'[ ${#SEL[@]} -eq 1 ] && [ "$CONFIRM" = "${SEL[0]}" ] || refuse'	'true || refuse'
FM3	forge_branch_protect.sh	'"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}\' "$rsname"'	'"rules":[{"type":"non_fast_forward"}]}\' "$rsname"'
FM4	forge_branch_protect.sh	'"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}\' "$rsname"'	'"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request"}]}\' "$rsname"'
FM5	forge_branch_protect.sh	'"enforcement":"active","bypass_actors":[],"conditions"'	'"enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}],"conditions"'
FM6	forge_branch_protect.sh	'-H "$acc" ${extra[@]+'	'-H "$acc" -H "$hdr" ${extra[@]+'
FM7	forge_branch_protect.sh	'if [ -n "$compliant" ]; then'	'if false; then'
FM8	forge_branch_protect.sh	'ff=\'"enable_force_push":false,\''	'ff=\'"enable_force_push":true,\''
FM9	forge_branch_protect.sh	'{"rule_name":"%s","enable_push":true,'	'{"rule_name":"%s","enable_push":false,'
FM10	forge_branch_protect.sh	'check_response "readback GET rules/branches/$BRANCH" "$rb" 200 || return 2'	'true'
FM11	forge_branch_protect.sh	'"target":"branch","enforcement":"active","bypass_actors":[]'	'"target":"branch","enforcement":"evaluate","bypass_actors":[]'
FM12	forge_branch_protect.sh	'  [ "$c" = 429 ] && return 0'	'  return 1'
FM13	forge_branch_protect.sh	'in_list "${SEL[0]}" "${APPLY_ALLOW[@]}" || refuse'	'true || refuse'
FM14	forge_branch_protect.sh	'known_target "$s" || die "unknown target'	'true || die "unknown target'
FM15	forge_branch_protect.sh	'(if .enable_force_push == false then "COMPLIANT"'	'(if true then "COMPLIANT"'
FM16	forge_branch_protect.sh	'check_response "POST ruleset" "$ar" 201 || return 0'	'check_response "POST ruleset" "$ar" 201,422 || return 0'
FM17	forge_branch_protect.sh	'local _xt=0; case $- in *x*) _xt=1; set +x ;; esac'	'local _xt=0'
FM18	forge_branch_protect.sh	'nothing to read back)"; flag 6 ;;'	'nothing to read back)" ;;'
FM19	forge_branch_protect.sh	'[.[]? | select(.ruleset_id==$id) | .type]'	'[.[]? | .type]'
FM20	forge_branch_protect.sh	'for tool in curl jq python3; do'	'for tool in curl python3; do'
FM21	forge_branch_protect.sh	'[[ "$BRANCH" != *..* ]]'	'true'
FM22	forge_branch_protect.sh	'refuse "targets come from FORGE_PROTECT_TARGETS_FILE'	'true "targets come from FORGE_PROTECT_TARGETS_FILE'
FM23	forge_branch_protect.sh	'echo "  FAILED: $label -> HTTP $c | $(summ "$(body_of "$res")")"; flag 1; return 1'	'return 0'
FM24	forge_branch_protect.sh	'[ "${t%%|*}" = "$1" ] && return 0; done; return 1; }'	'printf "%s\\n" "${t%%|*}"; done | grep -qxF -- "$1"; }'
AM1	github_actions_inventory_disable.sh	'if [ "$en" = true ] && [ "$arch" = false ]; then'	'if [ "$en" = true ]; then'
AM2	github_actions_inventory_disable.sh	'if [ "$sel" = yes ] && [ "$PAGES" = no ] && {'	'if false && {'
AM3	github_actions_inventory_disable.sh	'[ "$scope_ok" = yes ] || { echo "REFUSED: the live selection'	'true || { echo "REFUSED: the live selection'
AM4	github_actions_inventory_disable.sh	'-F enabled=false >/dev/null'	'-F enabled=true >/dev/null'
AM5	github_actions_inventory_disable.sh	'[ "${GH_ACTIONS_APPLY:-}" = yes ] ||'	'true ||'
AM6	github_actions_inventory_disable.sh	'if [ "$files" = ERR ] || [ "$en" = ERR ] || [ "$pg" = ERR ]; then'	'if [ "$files" = ERR ] || [ "$pg" = ERR ]; then'
AM7	github_actions_inventory_disable.sh	'[[ "$dyn" == *pages* ]] || [ "$pg" != - ]'	'[[ "$dyn" == *pages* ]]'
AM8	github_actions_inventory_disable.sh	'if [ "$now" = false ]; then'	'if true; then'
AM9	github_actions_inventory_disable.sh	'echo "# apply FAILED $r" >&2; rc=1; continue'	'echo "# apply FAILED $r" >&2; continue'
AM10	github_actions_inventory_disable.sh	'[ "$rc" -eq 0 ] || { echo "REFUSED: ERR rows present'	'true || { echo "REFUSED: ERR rows present'
AM11	github_actions_inventory_disable.sh	'[ -n "$CONFIRM" ] && [ "$CONFIRM" = "$TOKEN" ] ||'	'true ||'
AM12	github_actions_inventory_disable.sh	'row "$org/*" ERR ERR ERR ERR ERR ERR ERR ERR ERR ERR; rc=1; continue'	'continue'
AM13	github_actions_inventory_disable.sh	'[ -n "$REPOS_FILE" ] || { echo "REFUSED: apply needs --repos-file'	'true || { echo "REFUSED: apply needs --repos-file'
HM1	history_secret_scan.sh	'[ "$npos" -ge 1 ] || fail 3'	'true || fail 3'
HM2	history_secret_scan.sh	'[ "$nneg" -eq 0 ] || fail 3'	'true || fail 3'
HM3	history_secret_scan.sh	'"$GL" git --redact --no-banner'	'"$GL" git --no-banner'
HM4	history_secret_scan.sh	'--no-banner --log-opts="--all -m"'	'--no-banner --log-opts="--all"'
HM5	history_secret_scan.sh	'case "$grc" in 0|1) ;;'	'case "$grc" in *) ;;'
HM6	history_secret_scan.sh	'[ "$nmrg" -ge 1 ] || fail 3'	'true || fail 3'
HM7	history_secret_scan.sh	'[ -f "$SAFE_RM" ] && [ -r "$SAFE_RM" ] || fail 5'	'[ -f "$SAFE_RM" ] && [ -r "$SAFE_RM" ] || fail 1'
HM8	history_secret_scan.sh	'if [ -n "$KEYS" ]; then\n  KOUT='	'if false; then\n  KOUT='
HM9	history_secret_scan.sh	'if [[ "$u" =~ ^[Hh][Tt][Tt][Pp][Ss]?://[^/]*@ ]] ||'	'if false ||'
HM10	history_secret_scan.sh	'fail 6 "SCANNER-ERROR: exit $grc inconsistent'	'true "SCANNER-ERROR: exit $grc inconsistent'
HM11	history_secret_scan.sh	'[ -s "$REP" ] || fail 6 "SCANNER-ERROR: no report written"'	'[ -s "$REP" ] || exit 0'
HM12	history_secret_scan.sh	'git -C "$M" update-ref refs/fetched/needle/pos "$p2"'	'git -C "$M" update-ref refs/fetched/needle/pos "$p1"'
RM1	forge_branch_protect.sh	'    and ((.conditions.ref_name.include // []) | index($ref) != null)\n'	''
RM2	forge_branch_protect.sh	'if (type=="object") and (.target=="branch") and'	'if (type=="object") and'
RM3	forge_branch_protect.sh	'[ -z "$CONFIRM" ] || known_target "$CONFIRM" || die "unknown --apply-confirm target: $CONFIRM"'	'true'
RM4	forge_branch_protect.sh	'[ "${perm: -2}" = 00 ] || { echo "ERROR: $KEYS_FILE'	'[ "${perm: -1}" = 0 ] || { echo "ERROR: $KEYS_FILE'
RM5	forge_branch_protect.sh	"case \"$v\" in *'\"'*|*'\\'*|*$'\\n'*|*$'\\r'*) return 3 ;; esac"	"case \"$v\" in *'\"'*|*'\\'*) return 3 ;; esac"
RM7	forge_branch_protect.sh	'6) [ "$rc" = 0 ] && rc=6 ;;'	'6) [ "$rc" = 4 ] || rc=6 ;;'
RM8	forge_branch_protect.sh	'if [ "$(body_of "$rb" | jq -r \'.rule_name // .branch_name // empty\' 2>/dev/null)" != "$BRANCH" ]; then'	'if false; then'
RM10	forge_branch_protect.sh	'BRANCH=main\nMODE=plan\n'	'BRANCH=main\nMODE=apply\n'
RM11	forge_branch_protect.sh	'is_plan_blocked "$pr" || check_response "GET branch protection" "$pr" 200,404 || true'	'true'
FM25	forge_branch_protect.sh	'    and ((.conditions.ref_name.exclude // []) == [])\n'	''
FM26	forge_branch_protect.sh	'(if (has("bypass_actors") | not) then "NOBYPASS" elif .bypass_actors == [] then'	'(if (.bypass_actors // []) == [] then'
FM27	forge_branch_protect.sh	'brc=0; branch_rules_ok "$base" "$o" "$r" "$tv" "$c" || brc=$?'	'brc=0'
FM28	forge_branch_protect.sh	'[ "$s" = https ] && [ "$h" = "$want" ]'	'true'
FM29	forge_branch_protect.sh	'[ "$s" = https ] && [ "$h" = "$want" ]'	'[ "$h" = "$want" ]'
FM30	forge_branch_protect.sh	'if [ "$have" != "$want" ]; then'	'if false; then'
FM31	forge_branch_protect.sh	'    flag 7; return 0\n'	'    return 0\n'
FM32	forge_branch_protect.sh	'-ge 100 ]; then'	'-ge 100000 ]; then'
FM33	forge_branch_protect.sh	'done <<<"$globs"\n    flag 6\n'	'done <<<"$globs"\n'
FM34	forge_branch_protect.sh	'  [ -n "$want" ] || return 1\n'	''
FM35	forge_branch_protect.sh	'if is_loopback "$h"; then [ "${FORGE_PROTECT_TEST_LOOPBACK:-}" = yes ]; return; fi'	'if is_loopback "$h"; then return 0; fi'
AR1	github_actions_inventory_disable.sh	'MODE=list; SELECT=files'	'MODE=apply; SELECT=files'
AR7	github_actions_inventory_disable.sh	'[ "$scope_ok" = yes ] && echo "# SCOPE MATCH" >&2 || rc=1'	'echo "# SCOPE MATCH" >&2'
AM14	github_actions_inventory_disable.sh	'[ "$PIN_IS_ALLOWLIST" = yes ] || { echo "REFUSED: $REPOS_FILE is not'	'true || { echo "REFUSED: $REPOS_FILE is not'
AM16	github_actions_inventory_disable.sh	'jq -e \'(.workflows|type=="array") and ((.total_count // (.workflows|length)) <= (.workflows|length))\''	'jq -e \'(.workflows|type=="array")\''
AM17	github_actions_inventory_disable.sh	'  echo "# pinned=${#PIN[@]} apply-confirm token: $TOKEN" >&2\nelse'	'  :\nelse'
HR2	history_secret_scan.sh	'keys.tsv")" -ge 1 ]'	'keys.tsv")" -ge 0 ]'
HR4	history_secret_scan.sh	' || [[ "$u" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/@]*:[^/@]*@ ]]; then'	'; then'
HR5	history_secret_scan.sh	'"+refs/heads/*:refs/fetched/r$i/heads/*" "+refs/tags/*:refs/fetched/r$i/tags/*"'	'"+refs/heads/*:refs/fetched/r$i/heads/*"'
HR9	history_secret_scan.sh	'-f json -r "$REP" "$M" >"$WORK/gl.out" 2>&1 || grc=$?'	'-f json -r "$REP" "$M" || grc=$?'
HM13	history_secret_scan.sh	'  echo "exact-match note: not searched: $ss, $sp"\n'	''
X3	forge_branch_protect.sh	'[ "$s" = https ] && [ "$h" = "$want" ]'	'[ "$s" = https ] && [[ "$h" == "$want"* ]]'
X6	forge_branch_protect.sh	'"$hp|$ho|$hr|$ht" = "$wp|$wo|$wr|$wt"'	'"$hp|$ho|$hr" = "$wp|$wo|$wr"'
X7	forge_branch_protect.sh	'"$hp|$ho|$hr|$ht" = "$wp|$wo|$wr|$wt"'	'"$hp|$hr|$ht" = "$wp|$wr|$wt"'
X8	forge_branch_protect.sh	'and (.enforcement=="active")'	''
X9	forge_branch_protect.sh	'((.conditions.ref_name.exclude // []) == [])'	'((.conditions.ref_name.exclude // []) | index($ref) == null)'
X10	forge_branch_protect.sh	'for them; nothing will be sent)"; flag 1; return 0'	'for them; nothing will be sent)"; return 0'
X11	forge_branch_protect.sh	'cannot read the bypass list; nothing will be sent)"; flag 1; return 0'	'cannot read the bypass list; nothing will be sent)"; return 0'
X12	forge_branch_protect.sh	'paginated by this script; nothing will be sent)"; flag 1; return 0'	'paginated by this script; nothing will be sent)"; return 0'
X13	forge_branch_protect.sh	'7) case "$rc" in 0|6) rc=7 ;; esac ;;'	'7) rc=7 ;;'
X14	forge_branch_protect.sh	'6) [ "$rc" = 0 ] && rc=6 ;;'	'6) case "$rc" in 0|7) rc=6 ;; esac ;;'
X15	forge_branch_protect.sh	'test("[*?\\\\[]")'	'test("[*]")'
X17	forge_branch_protect.sh	'curl -q -sS -K -'	'curl -sS -K -'
X18	forge_branch_protect.sh	'-X "$m" --max-time 30'	'-X "$m" -L --location-trusted --max-time 30'
Y7	github_actions_inventory_disable.sh	'printf \'%s\\n%s\\n\' "$sel_sorted" "$done_pin"'	'printf \'%s\\n\' "$sel_sorted"'
Z3	history_secret_scan.sh	'__HSS_CONTROL_ABSENT__"{print $2}\' "$WORK/keys.tsv")" -eq 0 ]'	'__HSS_CONTROL_ABSENT__"{print $2}\' "$WORK/keys.tsv")" -ge 0 ]'
Z4	history_secret_scan.sh	'perm=$(stat -c \'%a\' "$KEYS"); [ "${perm: -2}" = 00 ]'	'perm=$(stat -c \'%a\' "$KEYS"); [ "${perm: -1}" = 0 ]'
Z8	history_secret_scan.sh	'if [ "$nf" -gt 0 ] || [ "$kh" -gt 0 ] || [ "$rh" -gt 0 ]; then exit 1; fi'	'if [ "$nf" -gt 0 ] || [ "$rh" -gt 0 ]; then exit 1; fi'
Y4	github_actions_inventory_disable.sh	'export LC_ALL=C   # one collation'	': LC_ALL=C   # one collation'
R3B1	forge_branch_protect.sh	'[ "$s" = https ] && [ "$h" = "$want" ]'	'[ "$s" = https ] && [[ "$h" == *"$want" ]]'
R3B2	forge_branch_protect.sh	'  case "$port" in -|:443) ;; *) return 1 ;; esac\n'	''
R3B3	forge_branch_protect.sh	'case "$port" in -|:443) ;;'	'case "$port" in -|:*443) ;;'
R3B4	forge_branch_protect.sh	'"${BASH_REMATCH[2],,}"'	'"${BASH_REMATCH[2]}"'
R3B5	forge_branch_protect.sh	'"${BASH_REMATCH[3]:--}"'	'"-"'
R3A1	forge_branch_protect.sh	'"$hp|$ho|$hr|$ht" = "$wp|$wo|$wr|$wt"'	'"$ho|$hr|$ht" = "$wo|$wr|$wt"'
R3A2	forge_branch_protect.sh	'"$hp|$ho|$hr|$ht" = "$wp|$wo|$wr|$wt"'	'"$hp|$ho|$ht" = "$wp|$wo|$wt"'
R3A3	forge_branch_protect.sh	'read -r _ hhost _ <<<"$hh"'	'read -r hhost _ _ <<<"$hh"'
R3E1	forge_branch_protect.sh	'1) [ "$rc" = 4 ] || rc=1 ;;'	'1) rc=1 ;;'
R3E2	forge_branch_protect.sh	'4) rc=4 ;;'	'4) [ "$rc" = 1 ] || rc=4 ;;'
R3E3	forge_branch_protect.sh	'7) case "$rc" in 0|6) rc=7 ;; esac ;;'	'7) case "$rc" in 0) rc=7 ;; esac ;;'
R3E4	forge_branch_protect.sh	'6) [ "$rc" = 0 ] && rc=6 ;;'	'6) rc=6 ;;'
R3P1	forge_branch_protect.sh	'[ -z "${!_pv:-}" ] || die'	'true || die'
R3P2	forge_branch_protect.sh	'for _pv in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY; do'	'for _pv in http_proxy https_proxy all_proxy; do'
R3P3	forge_branch_protect.sh	'if [ "${FORGE_PROTECT_TEST_LOOPBACK:-}" = yes ]; then\n  for _pv'	'if true; then\n  for _pv'
R3H1	forge_branch_protect.sh	'gh auth token --hostname github.com 2>/dev/null'	'gh auth token 2>/dev/null'
R3H2	forge_branch_protect.sh	'-u GH_TOKEN -u GH_HOST -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN gh auth'	'-u GH_TOKEN gh auth'
R3C1	forge_branch_protect.sh	'sw=$(curl -q -sS --max-time 30'	'sw=$(curl -sS --max-time 30'
R3C2	forge_branch_protect.sh	'-X "$m" --max-time 30'	'-X "$m" -L --max-time 30'
R3G1	github_actions_inventory_disable.sh	'gh api --hostname github.com "$@"'	'gh api "$@"'
R3G2	github_actions_inventory_disable.sh	'-u GH_TOKEN -u GH_HOST -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN gh api'	'-u GH_TOKEN gh api'
R3K1	history_secret_scan.sh	'perm=$(stat -c \'%a\' "$KEYS"); [ "${perm: -2}" = 00 ]'	'perm=$(stat -c \'%a\' "$KEYS"); [ "${perm: -2:1}" = 0 ]'
EOF

declare -A TESTOF=([forge_branch_protect.sh]=test_forge_branch_protect.sh [github_actions_inventory_disable.sh]=test_github_actions_inventory_disable.sh [history_secret_scan.sh]=test_history_secret_scan.sh)
declare -A VAROF=([forge_branch_protect.sh]=FBP_SCRIPT [github_actions_inventory_disable.sh]=GHA_SCRIPT [history_secret_scan.sh]=HSS_SCRIPT)
runtest(){ # script-name copy-path -> rc of its test
  env "${VAROF[$1]}=$2" SEC_TEST_FAILFAST="${3:-}" timeout 900 bash "$here/tests/security/${TESTOF[$1]}" > "$tmp/t.out" 2>&1
}
bad=0; killed=0; total=0
for s in forge_branch_protect.sh github_actions_inventory_disable.sh history_secret_scan.sh; do
  cp "$here/scripts/security/$s" "$tmp/scripts/security/$s"
  if runtest "$s" "$tmp/scripts/security/$s"; then echo "control ok   $s"; else echo "CONTROL FAIL $s"; tail -5 "$tmp/t.out"; bad=$((bad+1)); fi
done
while IFS=$'\t' read -r id s old new; do
  [ -n "$id" ] || continue
  if [ $# -gt 0 ]; then printf '%s\n' "$@" | grep -qxF "$id" || continue; fi
  total=$((total+1))
  if ! python3 -I - "$here/scripts/security/$s" "$tmp/scripts/security/$s" "$old" "$new" <<'PY'
import ast, sys
src, dst, old, new = sys.argv[1], sys.argv[2], ast.literal_eval(sys.argv[3]), ast.literal_eval(sys.argv[4])
t = open(src).read()
if t.count(old) != 1:
    sys.exit(1)
open(dst, "w").write(t.replace(old, new))
PY
  then echo "BROKEN   $id (pattern not found exactly once in $s)"; bad=$((bad+1)); continue; fi
  if runtest "$s" "$tmp/scripts/security/$s" 1; then
    echo "SURVIVED $id"; bad=$((bad+1))
  else
    echo "killed   $id ($(grep -m1 '^FAIL' "$tmp/t.out" | cut -c1-90))"; killed=$((killed+1))
  fi
  cp "$here/scripts/security/$s" "$tmp/scripts/security/$s"
done < "$tmp/mutants.tsv"
echo "RESULT: killed $killed/$total mutants; problems: $bad"
[ "$bad" -eq 0 ] && [ "$killed" -eq "$total" ]
