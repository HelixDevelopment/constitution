#!/usr/bin/env bash
# test_guard_forbidden_commands.sh — hermetic test suite for the
# PreToolUse guard hook (guard-forbidden-commands.sh).
#
# BOB-099 remediation (2026-08-19): closes the CARRIER-vs-INVOCATION false-
# positive class (§11.4.196(D) / §11.4.201(7)(a)) for the emulator,
# force-push, --no-verify, and --no-gpg-sign gates. The sudo/su + host-power
# gates already routed through the SCRUBBED_COMMAND projection; this fix
# hoists that projection ABOVE those remaining raw-$COMMAND checks so every
# structural-match gate sees the same quote-/comment-/heredoc-scrubbed view.
#
# Anti-bluff (§11.4.107(10) / §11.4.201):
#   - GOLDEN-TRUE fixtures per class: every real invocation still exits 2
#     (the fix does NOT weaken the guard);
#   - GOLDEN-FALSE-CARRIER fixtures per class: a trigger TOKEN merely
#     mentioned inside a quoted echo string OR a shell comment MUST NOT
#     block (the exact defect BOB-099 closes);
#   - ESCAPE-HATCH fixtures: the documented `# guardrails:allow <reason>`
#     marker still downgrades an overridable class (never host-power).
# So the hook provably cannot bluff in either direction.
#
# DETERMINISM (§11.4.50 / §11.4.98): trigger tokens are assembled at runtime
# from concatenated fragments so this test script's own command line and
# process cmdline carry NONE of them — the very hook under test would
# otherwise fire on the test-runner's `bash test_guard_forbidden_commands.sh`
# invocation string via a §11.4.196(D)-class pgrep-carrier match on the test
# harness's own arguments. Same trick the probe script that RED-captured
# BOB-099 relied on.
#
# Usage: bash constitution/scripts/hooks/test_guard_forbidden_commands.sh
# Exit 0 = all cases pass; exit 1 = one or more cases failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/guard-forbidden-commands.sh"

if [ ! -x "$HOOK" ] && [ ! -r "$HOOK" ]; then
  printf 'test_guard_forbidden_commands.sh: hook not found at %s\n' "$HOOK" >&2
  exit 1
fi

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Runtime-assembled trigger tokens (never appear literally in this file's
# lines that carry ONLY tokens — the file itself is inspected by the same
# hook when a subagent Reads it as $CLAUDE_PROJECT_DIR-relative test source).
# ---------------------------------------------------------------------------
SDO=$'\x73\x75\x64\x6f'                    # 'sudo'
S=$'\x73\x75'                              # 'su'
FORCE_FLAG=$'--for''ce'                    # '--force'
NOVER=$'--no-''verify'                     # '--no-verify'
NOGPG=$'--no-gpg''-sign'                   # '--no-gpg-sign'
EMU_AVD=$'emulator -a''vd'                 # 'emulator -avd'
ADB_INSTALL=$'adb ins''tall'               # 'adb install'
AM_INSTR=$'am inst''rument'                # 'am instrument'
GIT_PUSH_LIT=$'git ''push'                 # 'git push'
SYSCTL_SUSP=$'systemctl susp''end'         # 'systemctl suspend'
LOGCTL_KU=$'loginctl kill-''user'          # 'loginctl kill-user'
SHUT_H=$'shutdo''wn'                       # 'shutdown'

DQ='"'
SQ="'"

# run_case <name> <expected-exit> <bash-command-string>
run_case() {
  local name="$1" want="$2" cmd="$3" got
  local body="{${DQ}tool_name${DQ}:${DQ}Bash${DQ},${DQ}tool_input${DQ}:{${DQ}command${DQ}:${DQ}${cmd}${DQ}}}"
  printf '%s' "$body" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-62s (exit %s)\n' "$name" "$got"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %-62s (got exit %s, want %s)\n' "$name" "$got" "$want"
    FAIL=$((FAIL+1))
  fi
}

# run_case_env <name> <env-assignments> <expected-exit> <command>
# Round-2 review finding 1: the suite had NO fixture in which the hook runs
# under a misconfigured environment. Both tuning bounds were read straight
# from the environment, and a non-numeric value took the ENTIRE guard down --
# exit 1 (treated as proceed, so host-power and sudo went dark) for MAX_BYTES,
# and a silent exit 0 for MAX_DEPTH because the arithmetic error killed the
# process substitution feeding the read loop. A guard that configuration can
# switch off is not a guard.
run_case_env() {
  local name="$1" envs="$2" want="$3" cmd="$4" got
  local body="{${DQ}tool_name${DQ}:${DQ}Bash${DQ},${DQ}tool_input${DQ}:{${DQ}command${DQ}:${DQ}${cmd}${DQ}}}"
  printf '%s' "$body" | env $envs bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf '  PASS  %-62s (exit %s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-62s (got exit %s, want %s)\n' "$name" "$got" "$want"; FAIL=$((FAIL+1))
  fi
}

echo "guard-forbidden-commands.sh hermetic test suite (BOB-099 remediation)"
echo "hook: $HOOK"
echo

echo "-- GOLDEN-TRUE  real invocations MUST BLOCK (exit 2) --"
run_case "real sudo id"                        2 "${SDO} id"
run_case "real su -c whoami"                   2 "${S} -c ${SQ}whoami${SQ}"
run_case "real git push --force"               2 "${GIT_PUSH_LIT} ${FORCE_FLAG} origin main"
run_case "real git commit --no-verify"         2 "git commit ${NOVER}"
run_case "real git commit --no-gpg-sign"       2 "git commit ${NOGPG}"
run_case "real emulator -avd pixel"            2 "${EMU_AVD} pixel"
run_case "real adb install app.apk"            2 "${ADB_INSTALL} app.apk"
run_case "real am instrument -w x/y.z"         2 "${AM_INSTR} -w x/y.Runner"
run_case "real systemctl suspend"              2 "${SYSCTL_SUSP}"
run_case "real loginctl kill-user 1000"        2 "${LOGCTL_KU} 1000"
run_case "real shutdown -h now"                2 "${SHUT_H} -h now"

echo
echo "-- GOLDEN-FALSE  carrier in a single-quoted echo string MUST PASS (exit 0) --"
run_case "carrier prose (sudo)"                0 "echo ${SQ}the ${SDO} command is dangerous${SQ}"
run_case "carrier prose (su)"                  0 "echo ${SQ}Do not use ${S} to elevate${SQ}"
run_case "carrier prose (git push --force)"    0 "echo ${SQ}${GIT_PUSH_LIT} ${FORCE_FLAG} is forbidden${SQ}"
run_case "carrier prose (--no-verify)"         0 "echo ${SQ}never pass ${NOVER}${SQ}"
run_case "carrier prose (--no-gpg-sign)"       0 "echo ${SQ}never pass ${NOGPG}${SQ}"
run_case "carrier prose (emulator -avd)"       0 "echo ${SQ}${EMU_AVD} pixel is dev-only${SQ}"
run_case "carrier prose (adb install)"         0 "echo ${SQ}${ADB_INSTALL} apk is dev-only${SQ}"
run_case "carrier prose (am instrument)"       0 "echo ${SQ}${AM_INSTR} is dev-only${SQ}"
run_case "carrier prose (systemctl suspend)"   0 "echo ${SQ}${SYSCTL_SUSP} is banned${SQ}"
run_case "carrier prose (loginctl kill-user)"  0 "echo ${SQ}${LOGCTL_KU} is banned${SQ}"
run_case "carrier prose (shutdown)"            0 "echo ${SQ}${SHUT_H} -h now is banned${SQ}"

echo
echo "-- GOLDEN-FALSE  carrier in a shell comment MUST PASS (exit 0) --"
run_case "comment carrier (git push --force)"  0 "ls -la # ${GIT_PUSH_LIT} ${FORCE_FLAG} is forbidden"
run_case "comment carrier (emulator -avd)"     0 "ls -la # ${EMU_AVD} pixel is forbidden"
run_case "comment carrier (--no-verify)"       0 "ls -la # ${NOVER} is forbidden"
run_case "comment carrier (adb install)"       0 "ls -la # ${ADB_INSTALL} apk is forbidden"
run_case "comment carrier (systemctl suspend)" 0 "ls -la # ${SYSCTL_SUSP} is banned"

echo
echo "-- Non-Bash tools MUST always pass (exit 0) --"
# Even a description that MENTIONS a trigger token — different tool → no scan.
NON_BASH_PAYLOAD="{${DQ}tool_name${DQ}:${DQ}Read${DQ},${DQ}tool_input${DQ}:{${DQ}file_path${DQ}:${DQ}/tmp/${SDO}.txt${DQ}}}"
printf '%s' "$NON_BASH_PAYLOAD" | bash "$HOOK" >/dev/null 2>&1
got=$?
if [ "$got" -eq 0 ]; then
  printf '  PASS  %-62s (exit %s)\n' "non-Bash tool (Read) carrier" "$got"
  PASS=$((PASS+1))
else
  printf '  FAIL  %-62s (got exit %s, want 0)\n' "non-Bash tool (Read) carrier" "$got"
  FAIL=$((FAIL+1))
fi

echo
echo "-- Escape-hatch MUST downgrade overridable classes (exit 0) --"
run_case "sudo w/ escape marker downgrades"    0 "${SDO} apt update # guardrails:allow one-time host cleanup approved by operator"
run_case "force-push w/ escape marker"         0 "${GIT_PUSH_LIT} ${FORCE_FLAG} origin main # guardrails:allow tag-recovery approved"

echo
echo "-- Escape-hatch MUST NOT downgrade host-power classes (exit 2) --"
run_case "systemctl suspend w/ escape marker"  2 "${SYSCTL_SUSP} # guardrails:allow please no"
run_case "shutdown w/ escape marker"           2 "${SHUT_H} -h now # guardrails:allow please no"

echo
echo "-- ATM-GUARD-SUBST: word-boundary + command-substitution class (2026-09-08) --"
# Coverage-escape remediation (§11.4.238): SIX defects in this gate survived the
# 32 cases above and were found only when a real push was refused in live use.
# WHY the suite missed them: every force-push fixture above spells the
# invocation with `git` at start-of-string or after a space, and every
# carrier fixture puts the trigger in an INERT region (quote/comment). No
# fixture placed a LIVE `git push` behind a non-space boundary, and none put a
# `+`-leading token from an UNRELATED command in the same clause as a real
# push. Both blind spots are now fixtured.
#
# FALSE NEGATIVES (each was ALLOWED before the fix -- a §11.4.113 escape
# hatch in a rule that has none):
run_case "force-push inside \$( ) subst"        2 "echo \$(${GIT_PUSH_LIT} ${FORCE_FLAG} origin main)"
run_case "force-push inside backticks"         2 "echo \`${GIT_PUSH_LIT} ${FORCE_FLAG} origin main\`"
run_case "force-push inside subshell parens"   2 "(${GIT_PUSH_LIT} ${FORCE_FLAG} origin main)"
run_case "force-push via absolute path"        2 "/usr/bin/${GIT_PUSH_LIT} ${FORCE_FLAG} origin main"
run_case "force-push in NESTED subst"          2 "x \$(y \$(${GIT_PUSH_LIT} ${FORCE_FLAG} z) w)"
# Load-bearing: the expander must NOT split a real force-push apart when a
# substitution sits BETWEEN `git push` and the force flag.
run_case "force flag after subst argument"     2 "${GIT_PUSH_LIT} \$(get_remote) ${FORCE_FLAG}"
#
# FALSE POSITIVE (was REFUSED before the fix -- §11.4.201 FAIL-bluff): a
# `date +FORMAT` inside a substitution is not a `+<refspec>`.
run_case "push w/ date +FORMAT in subst"       0 "${GIT_PUSH_LIT} gitlab main > log_\$(date -u +%Y%m%dT%H%M%SZ).log"
run_case "push then date +%s in pipeline"      0 "${GIT_PUSH_LIT} gitlab main && date +%s"
run_case "subst w/ + but no push at all"       0 "echo \$(date +%s)"

# +<refspec> IS a force push. NOTE (review finding W1): NO case in the suite
# guarded this check -- deleting the `+` test entirely still scored 42/42.
run_case "real +refspec force push"            2 "${GIT_PUSH_LIT} origin +main:main"
run_case "real +refspec bare ref"              2 "${GIT_PUSH_LIT} origin +main"

# BLOCKING review finding B1: a force flag immediately before `)` was
# INVISIBLE -- the flag tests required whitespace/`=`/end-of-string after it
# -- so the very common `(cd repo && git push --force)` was ALLOWED. The
# first fix's own fixture was spelled `(git push --force origin main)`, with
# tokens AFTER the flag: the one shape that passes. The suite therefore
# asserted the subshell class was closed while this spelling stayed open.
run_case "force flag trailing before paren"    2 "(${GIT_PUSH_LIT} ${FORCE_FLAG})"
run_case "subshell cd && force before paren"   2 "(cd repo && ${GIT_PUSH_LIT} ${FORCE_FLAG})"
run_case "short -f trailing before paren"      2 "(cd repo && ${GIT_PUSH_LIT} origin main -f)"
run_case "force-with-lease before paren"       2 "(${GIT_PUSH_LIT} ${FORCE_FLAG}-with-lease)"
run_case "force flag before redirect"          2 "${GIT_PUSH_LIT} ${FORCE_FLAG}>log.txt"

# Review finding W2: the widened boundary newly and WRONGLY refused these.
# `.` and `:` sit inside ordinary tokens that are not a git invocation.
run_case "repo.git is not a git invocation"    0 "echo repo.git push +tag"
run_case "x:git is not a git invocation"       0 "echo x:git push +x"
run_case "url ending .git is not invocation"   0 "curl https://h/repo.git push +1"

echo
echo "-- ATM-GUARD-FAILCLOSED: misconfigured env MUST NOT disable the guard --"
MB=$'HELIX_GUARD_EXPAND_MAX''_BYTES'
MD=$'HELIX_GUARD_EXPAND_MAX''_DEPTH'
run_case_env "bad MAX_BYTES: force-push still blocked"  "${MB}=abc"   2 "${GIT_PUSH_LIT} ${FORCE_FLAG} origin main"
run_case_env "bad MAX_BYTES: host-power still blocked"  "${MB}=abc"   2 "${SYSCTL_SUSP}"
run_case_env "bad MAX_BYTES: sudo still blocked"        "${MB}=abc"   2 "${SDO} ls"
run_case_env "bad MAX_DEPTH: nested force blocked"      "${MD}=abc"   2 "a \$(b \$(${GIT_PUSH_LIT} ${FORCE_FLAG} o m))"
run_case_env "bad MAX_DEPTH: subst force blocked"       "${MD}=abc"   2 "echo \$(${GIT_PUSH_LIT} ${FORCE_FLAG} o m)"
run_case_env "arith-injection MAX_DEPTH blocked"        "${MD}=x[0]"  2 "a \$(b \$(${GIT_PUSH_LIT} ${FORCE_FLAG} o m))"
run_case_env "valid MAX_DEPTH=0 still blocks force"     "${MD}=0"     2 "a \$(b \$(${GIT_PUSH_LIT} ${FORCE_FLAG} o m))"
run_case_env "valid MAX_BYTES=1 still blocks force"     "${MB}=1"     2 "${GIT_PUSH_LIT} ${FORCE_FLAG} origin main"

echo
echo "-- ATM-GUARD-TERMINATOR: negative class covers & and < too (W1) --"
# Enumerating `)` and `>` missed `&` and `<`. The terminator is now a
# NEGATIVE class, so any non-alnum/_/- character ends the flag.
run_case "force flag before ampersand"         2 "${GIT_PUSH_LIT} ${FORCE_FLAG}&"
run_case "short -f before ampersand"           2 "${GIT_PUSH_LIT} origin main -f&"
run_case "force flag before input redirect"    2 "${GIT_PUSH_LIT} ${FORCE_FLAG}<in"
run_case "force flag before herestring"        2 "${GIT_PUSH_LIT} ${FORCE_FLAG}<<<x"
# Must NOT catch a flag that is a PREFIX of a longer word.
run_case "forced is not the force flag"        0 "echo ${GIT_PUSH_LIT} ${FORCE_FLAG}d"
# Boundary must still reject `git` as a SUBSTRING of a longer identifier.
# NOTE (review finding W1): the first version of this case was
# `echo legit --force nothing` -- it carries NO `push` token, so it could
# not fail under ANY boundary regex and was tautological: deleting the
# leading anchor entirely still scored 42/42. Both cases now carry a real
# `push` token, so a broken boundary wrongly BLOCKS them and they FAIL.
run_case "legit push is not git push"          0 "echo legit push ${FORCE_FLAG} nothing"
run_case "mygit push is not git push"          0 "echo mygit push ${FORCE_FLAG} nothing"

echo
echo "----"
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
