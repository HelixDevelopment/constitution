#!/usr/bin/env bash
# tests/forge/test_forge_mutations.sh -- paired mutation tests (section 1.1) of scripts/forge/.
# CLASS (section 11.4.289(C)(2)): gate-logic. Each mutant copies scripts/forge/ into a private sandbox,
# applies ONE exact text replacement (the mutant must apply: a pattern that is not found is an ERROR,
# never "killed"), and runs the named test file against the copy (FORGE_UNDER_TEST). A mutant is KILLED
# when that test file fails. First the unmutated copy must PASS every named test file (the baseline: a
# baseline failure would make every kill meaningless). Exit 0 only when the baseline passes and every
# mutant is killed. Heavy: about one full provider suite per mutant (run it in the background).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SBX="$(mktemp -d "${TMPDIR:-/tmp}/forge_mut.XXXXXX")" || exit 3
: "${SBX:?}"
cleanup() { case "$SBX" in */forge_mut.??????) rm -rf -- "${SBX:?}" ;; esac; }
trap cleanup EXIT

# M01-M18: own mutants; N01-N18: the independent review of 2026-11-12 (verbatim; N07 and N17 adapted to the
# current text and the "~" separator). N02 and N03 are EQUIVALENT and not run (measured: both survived the whole
# set on 2026-11-12): N02 removes the first of two checks in github.sh prov_repo, and the second (the URL minus the
# origin prefix must be /repositories/N) implies it; N03 removes the symlink test of _fg_file_safe, and the mode
# that stat -c %a reports for a Linux symlink is always 777, which the mode check refuses.
# R01-R11: the round-2 fixes (R03 is retired: the OK exit it mutated was replaced in round 3, and T01 mutates its
# successor; N07 is adapted to the round-3 text of the target check). X01-X16: the independent review of round 2 (scratch rev_mf_tools/mut2.py, adapted to
# the round-3 text: X02, X03 and X10 target the round-3 code that replaced the lines they changed; X12, X13 and X15
# are written without the "=~" operator, since "~" separates the fields here). X07 is EQUIVALENT and not run
# (accepted by the reviewer). T01-T08, S01-S10: the round-3 fixes (the commit verdict per forge, the sanitiser, the
# early traps, the token-set completeness, the hosts-map directory, the notes file type, live_probe.sh). Not run,
# EQUIVALENT by construction: removing [ "$FG_WROTE" -eq 0 ] (no forge with FG_TARGET_DERIVED=1 writes before the
# present branch) and the grep-status branch of fg_secret_hit (grep -F with a valid pattern list cannot return 2).
# W01-W05, W11, W12, W14, W15: the independent review of round 3 (scratch rev_mf_tools/mut3.py, verbatim); W19: the
# round-4 fix of fg_scrub (multi-line text). Not run: W06, W10, W16 and W17 are EQUIVALENT (accepted by the reviewer:
# W06 is implied by _fg_dotenv_names, W10 is unreachable because key names cannot hold "=", W16 re-adds the token in use
# through its source loop, W17 changes only speed); W18 (an 11-character token prefix in the AUTH line) is the stated
# 12-character window boundary, not a defect (docs/guides: "contiguous pieces of 12 or more characters").
# id ~ file (under scripts/forge) ~ test file
MUTANTS=(
"M01~forge.sh~test_forge_gitea.sh~'fg_line \"ACTION: created\"; fg_readback; fg_end_ensure'~'fg_line \"ACTION: created\"; fg_end_ensure'"
"M02~lib/http.sh~test_forge_credentials.sh~'  : >\"\$FG_TMP/resp\"; : >\"\$FG_TMP/code\"; : >\"\$FG_TMP/hdrs\"\\n'~'  [ -n \"\${FG_TOKEN:-}\" ] && args+=(-H \"X-Leak: \$FG_TOKEN\")\\n  : >\"\$FG_TMP/resp\"; : >\"\$FG_TMP/code\"; : >\"\$FG_TMP/hdrs\"\\n'"
"M03~forge.sh~test_forge_detect.sh~'      case \"\$auth\" in *@*) fg_usage_err \"https remote URL carries userinfo: refused (not shown)\" ;; esac\\n'~''"
"M04~providers/gitea.sh~test_forge_gitea.sh~'else FG_REL_STATE=absent; fi'~'else FG_REL_STATE=present; fi'"
"M05~providers/gitea.sh~test_forge_gitea.sh~'if [ \"\${FG_HAS_RELEASES:-unknown}\" = false ]; then'~'if false; then'"
"M06~lib/credentials.sh~test_forge_credentials.sh~'[ \$(( 8#\$mode & 8#077 )) -eq 0 ] || return 1'~'true'"
"M07~lib/credentials.sh~test_forge_credentials.sh~'  local v=\"\$1\" l first\\n'~'  return 1\\n  local v=\"\$1\" l first\\n'"
"M08~lib/http.sh~test_forge_gitea.sh~'--max-redirs 0'~'-L --max-redirs 5'"
"M09~providers/gitflic.sh~test_forge_gitflic.sh~'if [ \"\$p\" -ge \"\$tp\" ]; then _GF_FOUND=0'~'if true; then _GF_FOUND=0'"
"M10~providers/gitverse.sh~test_forge_gitverse.sh~'404) FG_REL_STATE=gap; FG_REL_GAP=releases_unsupported_or_empty ;;'~'404) FG_REL_STATE=absent ;;'"
"M11~lib/common.sh~test_forge_credentials.sh~'fg_env_clean() {\\n  _fg_env_state\\n'~'fg_env_clean() {\\n  return 0\\n  _fg_env_state\\n'"
"M12~providers/gitea.sh~test_forge_gitea.sh~'[ \"\$FG_CODE\" = 200 ] && [ \"\$FG_HAS_RELEASES\" = true ] && FG_ENABLE=enabled'~'FG_ENABLE=enabled'"
"M13~forge.sh~test_forge_gitea.sh~'[ \"\$FG_TAG_SHA\" = \"\$SHA\" ] || fg_fail tag_sha_mismatch'~'true || fg_fail tag_sha_mismatch'"
"M14~forge.sh~test_forge_github_gitlab.sh~'    true) ok=1 ;;\\n    false) ;;'~'    true) ;;\\n    false) ;;'"
"M15~lib/credentials.sh~test_forge_credentials.sh~'    return 2        # stop'~'    return 1        # stop'"
"M16~forge.sh~test_forge_github_gitlab.sh~'fg_ok_rel_id() { fg_ok_id \"\$1\" || { [ \"\$FG_PROVIDER\" = gitlab ] && fg_ok_tag \"\$1\"; }; }'~'fg_ok_rel_id() { fg_ok_id \"\$1\"; }'"
"M17~providers/gitverse.sh~test_forge_gitverse.sh~'{ FG_TAG_STATE=present; FG_TAG_SHA=\"\"; return 0; }'~'{ FG_TAG_STATE=present; FG_TAG_SHA=\"\$s\"; return 0; }'"
"M18~lib/http.sh~test_forge_credentials.sh~'printf -v cfg \"header = \\\\\"\$FG_AUTH_FMT\\\\\"\\\\n\" \"\$FG_TOKEN\"'~'printf -v cfg \"header = \\\\\"\$FG_AUTH_FMT\\\\\"\\\\n\" \"\$FG_TOKEN\"; printf \"%s\\\\n\" \"\$FG_TOKEN\" >&2'"
"N01~lib/http.sh~test_forge_credentials.sh~'  [ \"\$o\" = \"\$FG_API_ORIGIN\" ] || { FG_NET=pin; return 1; }\\n'~''"
"N04~lib/credentials.sh~test_forge_credentials.sh~'  [ \"\$owner\" = \"\$(id -u)\" ] || return 1\\n'~''"
"N05~lib/credentials.sh~test_forge_credentials.sh~'      v=\"\$(_fg_keys_value \"\$kf\" \"\$n\")\"\\n      _fg_try_value keys_file \"\$n\" \"\$v\"; case \$? in 0) return 0 ;; 2) return 1 ;; esac'~'      v=\"\$(_fg_keys_value \"\$kf\" \"\$n\")\"\\n      _fg_try_value keys_file \"\$n\" \"\$v\"; case \$? in 0) return 0 ;; esac'"
"N06~lib/common.sh~test_forge_credentials.sh~'XDG_RUNTIME_DIR \"'~'XDG_RUNTIME_DIR https_proxy HTTPS_PROXY ALL_PROXY all_proxy \"'"
"N07~forge.sh~test_forge_gitea.sh~'    if [ \"\$FG_REL_TARGET\" != \"\$SHA\" ]; then ok=1\\n'~'    if false; then ok=1\\n'"
"N08~providers/gitflic.sh~test_forge_gitflic.sh~'  _GF_FOUND=cap\\n'~'  _GF_FOUND=0\\n'"
"N09~lib/http.sh~test_forge_credentials.sh~'      rmdir -- \"\$FG_TMP\" 2>/dev/null ;;'~'      : ;;'"
"N10~forge.sh~test_forge_credentials.sh~'       fg_gap \"credentials_absent:\$FG_TOKEN_VARS\"'~'       : \"credentials_absent:\$FG_TOKEN_VARS\"'"
"N11~providers/gitlab.sh~test_forge_github_gitlab.sh~'409) FG_CREATE=exists'~'409) FG_CREATE=created'"
"N12~lib/credentials.sh~test_forge_credentials.sh~'  [ \"\${#v}\" -lt 8 ] && return 0\\n'~''"
"N13~forge.sh~test_forge_detect.sh~'  case \"\$o\" in https://*) return 0 ;; esac'~'  return 0'"
"N14~lib/common.sh~test_forge_credentials.sh~'s) _fg_carry_shell \"\$n\" && printf -v \"\$n\" \\'%s\\' \"\$val\" 2>/dev/null ;;'~'s) _fg_carry_shell \"\$n\" && printf -v \"\$n\" \\'%s\\' \"\$val\" 2>/dev/null && export \"\${n?}\" ;;'"
"N15~providers/gitverse.sh~test_forge_gitverse.sh~'403|404) FG_CREATE=refused'~'403|404) FG_CREATE=created'"
"N16~forge.sh~test_forge_gitea.sh~'  [ \"\$FG_REL_TAG\" = \"\$TAG\" ] || ok=1\\n'~''"
"N17~lib/credentials.sh~test_forge_credentials.sh~'  [ \$(( 8#\$mode & 8#077 )) -eq 0 ] || return 1'~'  [ \$(( 8#\$mode & 8#007 )) -eq 0 ] || return 1'"
"N18~providers/github.sh~test_forge_github_gitlab.sh~'[ \"\$(fg_json \\'.ref // empty\\')\" = \"refs/tags/\$1\" ] || { FG_TAG_STATE=absent; return 0; }\\n'~''"
"R01~forge.sh~test_forge_credentials.sh~'  fg_is_credential_file \"\$NOTES\" && fg_usage_err'~'  false && fg_usage_err'"
"R02~forge.sh~test_forge_credentials.sh~'  if fg_text_has_secret \"\$NOTES_TEXT\"; then'~'  if false; then'"
"R04~forge.sh~test_forge_credentials.sh~'& 8#002 )) -eq 0 ] || fg_usage_err'~'& 8#000 )) -eq 0 ] || fg_usage_err'"
"R05~lib/credentials.sh~test_forge_credentials.sh~'  case \"\${FG_DIR_PHYS:-/nonexistent}/\" in \"\$FG_REPO_ROOT\"/*) printf \\'%s\\' \"\$FG_REPO_ROOT/.env\" ;; esac\\n'~'  printf \\'%s\\' \"\$FG_REPO_ROOT/.env\"\\n'"
"R06~lib/common.sh~test_forge_credentials.sh~'-le 65535 ]; }'~'-le 999999 ]; }'"
"R07~providers/github.sh~test_forge_github_gitlab.sh~'    422) [ \"\$(fg_json \\'[.errors[]? | select(.code == \"already_exists\")] | length\\')\" -ge 1 ] 2>/dev/null && FG_CREATE=exists ;;'~'    422) FG_CREATE=exists ;;'"
"R08~lib/http.sh~test_forge_credentials.sh~\"trap 'fg_interrupted 143' TERM\"~'trap - TERM'"
"R09~providers/github.sh~test_forge_github_gitlab.sh~'    404) _github_draft_lookup \"\$1\" || return 1 ;;'~'    404) FG_REL_STATE=absent ;;'"
"R10~lib/http.sh~test_forge_gitea.sh~'|| v=unsafe'~'|| true'"
"R11~forge.sh~test_forge_github_gitlab.sh~'  if fg_ok_sha \"\$FG_REL_TARGET\"; then\\n'~'  if true; then\\n'"
"X01~lib/credentials.sh~test_forge_credentials.sh~'\"\$(fg_env_file_path)\" \"\${FG_REPO_ROOT:+\$FG_REPO_ROOT/.env}\"; do'~'\"\$(fg_env_file_path)\"; do'"
"X02~lib/credentials.sh~test_forge_credentials.sh~'    mapfile -d \\'\\' kv < <(_fg_keys_all \"\$kf\")\\n'~'    kv=()\\n'"
"X03~lib/credentials.sh~test_forge_credentials.sh~'    _fg_sec_add \"\$n\" \"\${!n-}\"\\n  done\\n'~'    :\\n  done\\n'"
"X04~forge.sh~test_forge_credentials.sh~'  NOTES=\"\$FG_TMP/notes.txt\"; NOTES_TEXT=\"\"'~'  NOTES_TEXT=\"\"'"
"X05~lib/http.sh~test_forge_credentials.sh~'  if [ -n \"\${FG_CHILD:-}\" ]; then kill -TERM \"\$FG_CHILD\" 2>/dev/null; wait \"\$FG_CHILD\" 2>/dev/null; FG_CHILD=\"\"; fi\\n'~'  FG_CHILD=\"\"\\n'"
"X06~lib/http.sh~test_forge_gitea.sh~'done < <(tail -n +6 -- \"\$FG_TMP/code\" 2>/dev/null)'~'done < <(tail -n +7 -- \"\$FG_TMP/code\" 2>/dev/null)'"
"X08~forge.sh~test_forge_credentials.sh~'  { [ \"\$owner\" = \"\$(id -u)\" ] || [ \"\$owner\" = 0 ]; } || fg_usage_err'~'  true || fg_usage_err'"
"X09~forge.sh~test_forge_gitverse.sh~'  if [ \"\$DRY\" -eq 1 ]; then fg_line \"ACTION: would-update\"; fg_end_ensure; fi\\n'~''"
"X10~forge.sh~test_forge_credentials.sh~'  FG_NOTES_MAX=1000000\\n'~'  FG_NOTES_MAX=1000000000\\n'"
"X11~lib/http.sh~test_forge_credentials.sh~'  printf \\'REASON: interrupted\\\\nRESULT: INTERRUPTED\\\\n\\'\\n'~'  printf \\'RESULT: INTERRUPTED\\\\n\\'\\n'"
"X12~lib/http.sh~test_forge_gitea.sh~'|| FG_PEER_SUBJECT=unsafe\\n'~'|| true\\n'"
"X13~lib/http.sh~test_forge_gitea.sh~'|| FG_PEER_IP=unsafe\\n'~'|| true\\n'"
"X14~forge.sh~test_forge_credentials.sh~'  fg_text_has_secret \"\$TITLE\" && fg_usage_err'~'  false && fg_usage_err'"
"X15~lib/common.sh~test_forge_credentials.sh~'[ \"\$((10#\$1))\" -ge 1 ] && [ \"\$((10#\$1))\" -le 65535 ]'~'[ \"\$((10#\$1))\" -ge 0 ] && [ \"\$((10#\$1))\" -le 65535 ]'"
"X16~providers/gitflic.sh~test_forge_gitflic.sh~'FG_REL_TARGET=\"\$(jq -r \\'.commitId // empty\\' <\"\$FG_TMP/page.json\" 2>/dev/null)\"'~'FG_REL_TARGET=\"\"'"
"T01~forge.sh~test_forge_gitverse.sh~'  if [ \"\$FG_COMMIT_OK\" = 1 ]; then fg_end OK 0; fi\\n'~'  fg_end OK 0\\n'"
"T02~forge.sh~test_forge_github_gitlab.sh~'    elif [ \"\$FG_TARGET_DERIVED\" = 1 ]; then FG_TARGET_OK=1'~'    elif false; then FG_TARGET_OK=1'"
"T03~forge.sh~test_forge_github_gitlab.sh~'    [ \"\$FG_TARGET_OK\" = 1 ] && [ \"\$FG_WROTE\" -eq 0 ] && FG_COMMIT_OK=1\\n'~''"
"T04~providers/gitlab.sh~test_forge_github_gitlab.sh~'  FG_TARGET_DERIVED=1'~'  FG_TARGET_DERIVED=0'"
"T05~providers/github.sh~test_forge_github_gitlab.sh~'  FG_TARGET_DERIVED=0'~'  FG_TARGET_DERIVED=1'"
"T06~providers/gitverse.sh~test_forge_gitverse.sh~'  FG_TARGET_DERIVED=0'~'  FG_TARGET_DERIVED=1'"
"T07~providers/gitflic.sh~test_forge_gitflic.sh~'  FG_TARGET_DERIVED=0'~'  FG_TARGET_DERIVED=1'"
"T08~providers/gitea.sh~test_forge_gitea.sh~'  FG_TARGET_DERIVED=0'~'  FG_TARGET_DERIVED=1'"
"S01~lib/common.sh~test_forge_gitverse.sh~'fg_line() { printf \\'%s\\\\n\\' \"\$(fg_scrub \"\$*\")\"; }'~'fg_line() { printf \\'%s\\\\n\\' \"\$*\"; }'"
"S02~lib/common.sh~test_forge_credentials.sh~'FG_SEC_WIN=12\\n'~'FG_SEC_WIN=40\\n'"
"S03~lib/http.sh~test_forge_gitea.sh~'    fg_secret_hit \"\$v\" && v=unsafe'~'    :'"
"S04~lib/http.sh~test_forge_gitea.sh~'    fg_secret_hit \"\${!n}\" && printf -v \"\$n\" \\'%s\\' unsafe\\n'~'    :\\n'"
"S05~forge.sh~test_forge_credentials.sh~'trap \\'_fg_early_int 129\\' HUP; trap \\'_fg_early_int 130\\' INT; trap \\'_fg_early_int 143\\' TERM\\n'~''"
"S06~lib/credentials.sh~test_forge_credentials.sh~'    [ \"\$st\" -eq 0 ] || rc=1\\n'~'    true\\n'"
"S07~forge.sh~test_forge_credentials.sh~'  [ \$(( 8#\$dmode & 8#002 )) -eq 0 ] || [ \$(( 8#\$dmode & 8#1000 )) -ne 0 ] || fg_usage_err'~'  true || fg_usage_err'"
"S08~forge.sh~test_forge_credentials.sh~'  [ -f \"\$NOTES\" ] || [ \"\$NOTES\" = /dev/null ] || fg_usage_err'~'  true || fg_usage_err'"
"S09~live_probe.sh~test_forge_credentials.sh~'  hasin \"\$needle\" \"\$f\" || {'~'  true || {'"
"S10~live_probe.sh~test_forge_credentials.sh~'  if hasany \"\${FG_SEC_VALS[\$i]}\"; then leak=1;'~'  if false; then leak=1;'"
"W01~lib/common.sh~test_forge_credentials.sh~'fg_msg() { printf \\'forge: %s\\\\n\\' \"\$(fg_scrub \"\$*\")\" >&2; }'~'fg_msg() { printf \\'forge: %s\\\\n\\' \"\$*\" >&2; }'"
"W02~lib/common.sh~test_forge_credentials.sh~'printf \\'REASON: %s\\\\n\\' \"\$(fg_scrub \"\$3\")\"'~'printf \\'REASON: %s\\\\n\\' \"\$3\"'"
"W03~lib/credentials.sh~test_forge_credentials.sh~'  [ \"\${#v}\" -ge 8 ] || return 0\\n'~'  [ \"\${#v}\" -ge 20 ] || return 0\\n'"
"W04~lib/common.sh~test_forge_credentials.sh~'    [ \"\$?\" -eq 1 ] && return 1\\n'~'    return 1\\n'"
"W05~lib/common.sh~test_forge_credentials.sh~'    for ((w = 0; w + FG_SEC_WIN <= n; w++)); do'~'    for ((w = 0; w + FG_SEC_WIN < n; w++)); do'"
"W11~lib/common.sh~test_forge_credentials.sh~'  if [ \"\$n\" -lt \"\$FG_SEC_WIN\" ]; then printf \\'%s\\\\n\\' \"\$v\"; return 0; fi'~'  if [ \"\$n\" -lt \"\$FG_SEC_WIN\" ]; then return 0; fi'"
"W12~live_probe.sh~test_forge_credentials.sh~'  ! hasin \\'NO_SUCH_STRING_9f3c1e\\' \"\$f\" || {'~'  true || {'"
"W14~forge.sh~test_forge_github_gitlab.sh~'      if fg_matches; then fg_line \"ACTION: kept\"; fg_end_ensure; fi'~'      if fg_matches; then fg_line \"ACTION: kept\"; [ \"\$FG_TARGET_OK\" = 1 ] && FG_COMMIT_OK=1; fg_end_ensure; fi'"
"W15~lib/common.sh~test_forge_credentials.sh~'      [[ \$t == *\"\$v\"* ]] && { FG_SECRET_NAME=\"\${FG_SEC_NAMES[\$i]}\"; return 0; }\\n      continue'~'      continue'"
"W19~lib/common.sh~test_forge_credentials.sh~'  if [[ \$t == *\$\\'\\\\n\\'* ]]; then\\n'~'  if false; then\\n'"
)

copy_tree() { # DEST: a fresh copy of scripts/forge
  mkdir -p "$1/scripts" && cp -R -- "$ROOT/scripts/forge" "$1/scripts/forge"
}
run_test() { # COPY_ROOT TESTFILE -> status of the test file against the copy
  FORGE_UNDER_TEST="$1/scripts/forge/forge.sh" nice -n 10 bash "$HERE/$2" >"$SBX/last.log" 2>&1
}

# baseline: every named test file passes on an unmutated copy
copy_tree "$SBX/base"
base_ok=1
for t in $(printf '%s\n' "${MUTANTS[@]}" | cut -d'~' -f3 | sort -u); do
  if run_test "$SBX/base" "$t"; then echo "BASELINE PASS $t"; else echo "BASELINE FAIL $t"; tail -5 "$SBX/last.log"; base_ok=0; fi
done
[ "$base_ok" -eq 1 ] || { echo "SUMMARY: baseline failed; mutants not run"; exit 1; }

killed=0 survived=0 errors=0
for m in "${MUTANTS[@]}"; do
  IFS='~' read -r id file tfile old new <<<"$m"
  d="$SBX/$id"; copy_tree "$d"
  if ! python3 -I -c '
import sys, ast
p, old, new = sys.argv[1], ast.literal_eval(sys.argv[2]), ast.literal_eval(sys.argv[3])
s = open(p, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))' "$d/scripts/forge/$file" "$old" "$new"; then
    echo "ERROR $id: the mutation does not apply exactly once to $file"; errors=$((errors + 1)); continue
  fi
  if run_test "$d" "$tfile"; then
    echo "SURVIVED $id ($file, $tfile)"; survived=$((survived + 1))
  else
    echo "KILLED $id ($file by $tfile: $(grep -m1 '^FAIL' "$SBX/last.log" | cut -c1-110))"; killed=$((killed + 1))
  fi
done
echo "SUMMARY: ${#MUTANTS[@]} mutants, $killed killed, $survived survived, $errors errors"
[ "$survived" -eq 0 ] && [ "$errors" -eq 0 ] && [ "$killed" -eq "${#MUTANTS[@]}" ]
