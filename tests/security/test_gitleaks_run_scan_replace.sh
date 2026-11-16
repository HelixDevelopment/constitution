#!/usr/bin/env bash
# test_gitleaks_run_scan_replace.sh -- tests for the replace-ref handling of
# scripts/gitleaks/gitleaks_run_scan.sh (CON-435, follow-up of CON-425).
#
# Purpose: a refs/replace/<id> entry makes git show another object in place of
# <id>. gitleaks detect reads the history through `git log -p`, so a secret
# commit or blob replaced by a clean one is invisible to it unless
# GIT_NO_REPLACE_OBJECTS is set in the environment the scanner inherits. The
# script's git-env scrub unsets that variable; before CON-435 it was never set
# again. This test drives the REAL script on throwaway repositories:
#   R0 precondition: the replace refs really hide the secret from `git log -p`
#      (and GIT_NO_REPLACE_OBJECTS=1 shows it), so the cases below can fail;
#   R1 commit-replace repo: the hidden secret is found (exit 1);
#   R2 the same repo: the positive control (a secret on a branch that is not
#      replaced) is found;
#   R3 blob-replace repo: the hidden secret is found;
#   R4 plain repo (same history, no replace ref): both secrets found;
#   R5 negative control (no secret anywhere): exit 0, zero findings;
#   R6 core.useReplaceRefs=true in the repository config does not turn replace
#      refs back on;
#   R7 core.useReplaceRefs=true in GIT_CONFIG_PARAMETERS does not either;
#   R8 a caller-exported GIT_NO_REPLACE_OBJECTS is not needed: the run works
#      with the variable unset by the caller (the scrub clears it anyway) and
#      the scanner process sees the value 1 (fake scanner only).
# Scanner: by default the fake tests/security/fixtures/fake_gitleaks_detect.py
# (gate-logic only, §11.4.289). With GLRS_GITLEAKS=/path/to/gitleaks the REAL
# binary is used (live evidence); R8's env check is then reported as a SKIP
# line, because the real binary does not log its environment.
# Fabricated values are random per run and built with python3 (no
# secret-shaped literal in this file); output never prints them.
#
# Usage: bash tests/security/test_gitleaks_run_scan_replace.sh
#        GLRS_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        GLRS_GITLEAKS=/path/to/real/gitleaks bash ...   (live run)
#        SEC_TEST_FAILFAST=1 stops at the first failing case
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${GLRS_SCRIPT:-$here/scripts/gitleaks/gitleaks_run_scan.sh}"
FIX="$here/tests/security/fixtures"
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
[ -f "$SCRIPT" ] || { echo "env: script not found: $SCRIPT" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"  # absolute: scan() runs from $tmp
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/bin"
if [ -n "${GLRS_GITLEAKS:-}" ]; then
  [ -x "$GLRS_GITLEAKS" ] || { echo "env: GLRS_GITLEAKS is not executable: $GLRS_GITLEAKS" >&2; exit 2; }
  ln -s "$GLRS_GITLEAKS" "$tmp/bin/gitleaks"; MODE=real
else
  printf '#!/usr/bin/env bash\nexec python3 -I %q "$@"\n' "$FIX/fake_gitleaks_detect.py" > "$tmp/bin/gitleaks"
  chmod +x "$tmp/bin/gitleaks"; MODE=fake
fi
echo "scanner: $MODE"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
export GIT_AUTHOR_DATE=2001-01-01T00:00:00Z GIT_COMMITTER_DATE=2001-01-01T00:00:00Z
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
tok(){ python3 -I -c 'import secrets,string;a=string.ascii_letters+string.digits;print("gh"+"p_"+"".join(secrets.choice(a) for _ in range(36)))'; }

SEC=$(tok); CTL=$(tok); SEC2=$(tok)
# Commit replace: root -> secret commit S -> removal; S is replaced by a clean
# stand-in; a control secret sits on branch ctl (not replaced). MODE replaced|plain|neg.
mk_commit_repo(){ # DIR MODE
  local r=$1 m=$2 s cl
  git init -q -b main "$r"; echo base > "$r/base.txt"; git -C "$r" add .; git -C "$r" commit -qm root
  if [ "$m" = neg ]; then echo two > "$r/two.txt"; git -C "$r" add .; git -C "$r" commit -qm two; return 0; fi
  printf 'token=%s\n' "$SEC" > "$r/cfg.env"; git -C "$r" add .; git -C "$r" commit -qm add; s=$(git -C "$r" rev-parse HEAD)
  git -C "$r" rm -q cfg.env; git -C "$r" commit -qm remove
  if [ "$m" = replaced ]; then
    git -C "$r" checkout -q -b cl "$s~1"; echo harmless > "$r/cfg.env"; git -C "$r" add .; git -C "$r" commit -qm stand-in
    cl=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q main; git -C "$r" replace "$s" "$cl"
  fi
  git -C "$r" checkout -q -b ctl main~2; printf 'token=%s\n' "$CTL" > "$r/ctl.env"; git -C "$r" add .; git -C "$r" commit -qm ctl
  git -C "$r" checkout -q main
}
# Blob replace: the secret blob is replaced by a clean blob.
mk_blob_repo(){ # DIR
  local r=$1 sb cb
  git init -q -b main "$r"; printf 'token=%s\n' "$SEC2" > "$r/s.env"; git -C "$r" add .; git -C "$r" commit -qm s
  sb=$(git -C "$r" rev-parse HEAD:s.env); cb=$(printf 'clean\n' | git -C "$r" hash-object -w --stdin)
  git -C "$r" replace "$sb" "$cb"
}
RR="$tmp/r_replaced"; mk_commit_repo "$RR" replaced
RP="$tmp/r_plain"; mk_commit_repo "$RP" plain
RN="$tmp/r_neg"; mk_commit_repo "$RN" neg
RB="$tmp/r_blob"; mk_blob_repo "$RB"
cp -a "$RR" "$tmp/r_cfg"; git -C "$tmp/r_cfg" config core.useReplaceRefs true
cp -a "$RR" "$tmp/r_par"

scan(){ # REPO [env assignments...] -> sets RC and FJ (findings.json path, may be empty)
  local r=$1; shift
  ( cd "$tmp" && env "$@" PATH="$tmp/bin:$PATH" bash "$SCRIPT" "$r" ) > "$tmp/out" 2> "$tmp/err"; RC=$?
  FJ=$(sed -n 's/^ *\[evidence: \(.*\)\]$/\1/p' "$tmp/out" | tail -1); FJ=${FJ:+$FJ/findings.json}
}
has(){ [ -n "$FJ" ] && [ -f "$FJ" ] && jq -e --arg v "$1" 'map(.Secret) | index($v) != null' "$FJ" >/dev/null 2>&1; }
count(){ if [ -n "$FJ" ] && [ -s "$FJ" ]; then jq 'length' "$FJ"; else echo 0; fi; }
show(){ sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -20; }

# R0: precondition (§11.4.199): without the variable the secret is hidden, with it shown.
# The logs go to files first: `git log | grep -q` under pipefail fails at random when grep exits
# early and git gets SIGPIPE (measured: R0 failed in 1 of 3 runs before this was changed).
git -C "$RR" log -p --all > "$tmp/l_rr0"; GIT_NO_REPLACE_OBJECTS=1 git -C "$RR" log -p --all > "$tmp/l_rr1"
git -C "$RB" log -p --all > "$tmp/l_rb0"; GIT_NO_REPLACE_OBJECTS=1 git -C "$RB" log -p --all > "$tmp/l_rb1"
if ! grep -qF "$SEC" "$tmp/l_rr0" && grep -qF "$SEC" "$tmp/l_rr1" && ! grep -qF "$SEC2" "$tmp/l_rb0" && grep -qF "$SEC2" "$tmp/l_rb1"; then
  ok "R0 precondition: replace refs hide both secrets from git log -p; GIT_NO_REPLACE_OBJECTS=1 shows them"
else nok "R0 precondition: replace refs do not hide the secrets (the cases below prove nothing)"; fi

: > "$tmp/envlog"
scan "$RR" FAKE_GL_ENVLOG="$tmp/envlog"
if [ "$RC" = 1 ] && has "$SEC"; then ok "R1 commit-replace repo: hidden secret found (exit 1)"; else nok "R1 commit-replace repo: hidden secret not found (rc=$RC, findings=$(count))"; show; fi
if has "$CTL"; then ok "R2 commit-replace repo: positive control found"; else nok "R2 commit-replace repo: positive control missing (rc=$RC)"; show; fi
scan "$RB"
if [ "$RC" = 1 ] && has "$SEC2"; then ok "R3 blob-replace repo: hidden secret found"; else nok "R3 blob-replace repo: hidden secret not found (rc=$RC, findings=$(count))"; show; fi
scan "$RP"
if [ "$RC" = 1 ] && has "$SEC" && has "$CTL"; then ok "R4 plain repo: both secrets found"; else nok "R4 plain repo: rc=$RC findings=$(count)"; show; fi
scan "$RN"
if [ "$RC" = 0 ] && [ "$(count)" = 0 ]; then ok "R5 negative control: exit 0, zero findings"; else nok "R5 negative control: rc=$RC findings=$(count)"; show; fi
scan "$tmp/r_cfg"
if [ "$RC" = 1 ] && has "$SEC"; then ok "R6 core.useReplaceRefs=true in repo config: hidden secret still found"; else nok "R6 repo config core.useReplaceRefs=true hides the secret (rc=$RC)"; show; fi
scan "$tmp/r_par" "GIT_CONFIG_PARAMETERS='core.usereplacerefs'='true'"
if [ "$RC" = 1 ] && has "$SEC"; then ok "R7 core.useReplaceRefs=true in GIT_CONFIG_PARAMETERS: hidden secret still found"; else nok "R7 GIT_CONFIG_PARAMETERS core.useReplaceRefs=true hides the secret (rc=$RC)"; show; fi
if [ "$MODE" = fake ]; then
  if [ -s "$tmp/envlog" ] && ! grep -qvx 1 "$tmp/envlog"; then ok "R8 scanner process sees GIT_NO_REPLACE_OBJECTS=1"; else nok "R8 scanner process saw: $(tr '\n' ' ' < "$tmp/envlog")"; fi
else
  echo "SKIP R8 scanner-environment check: the real binary does not log its environment (R1/R3 are the live proof)"
fi
echo "RESULT: $((n-bad))/$n passed (scanner: $MODE)"
[ "$bad" -eq 0 ]
