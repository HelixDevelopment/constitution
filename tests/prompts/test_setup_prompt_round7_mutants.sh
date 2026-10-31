#!/usr/bin/env bash
# test_setup_prompt_round7_mutants.sh — paired mutation proof (§1.1) for the review round 7 fixes.
# Each mutant is applied to a sandbox copy of ONE file (latest.md, follow-up 01, the allow-list
# analyser or the rotation script) and the suite that guards it is run on the copy; every mutant
# must make that suite FAIL. All mutants are written by the round-7 fixer (the reviewer's P10 is
# killed inside test_setup_prompt_round7.sh, NEEDLE section).
# Env: R7MM_ONLY="<ids>" (a subset). Writes only inside a mktemp -d sandbox.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LATEST="$REPO/docs/prompts/setup/latest.md"
FU01="$REPO/docs/prompts/setup/followups/01_verify_incorporation.md"
AL="$here/git_allowlist.py"
RS="$REPO/scripts/prompts/rotate_setup_prompt.sh"
W="$(mk_sandbox)"

# id | file (L F1 A S) | guard (R7:<sections> or R5:<sections>)
SPECS=(
"M01-STEP1-NO-SYMLINK-GUARD|L|R7:SYMLINK"
"M02-CREDRX-NO-QUERY|L|R5:CRED"
"M03-REDACT-NO-QUERY|L|R5:REDACT"
"M04-NEEDLE-TWO-LINES|L|R7:NEEDLE"
"M05-V6-NEEDLE-TWO-LINES|F1|R7:NEEDLE"
"M06-LSREMOTE-NO-DDASH|L|R7:LSREMOTE"
"M07-AL-PLAIN-WORD-ALWAYS|A|R7:ALLOW"
"M08-AL-SEGMENTS-UNCHECKED|A|R7:ALLOW"
"M09-AL-RM-TRAILING-OK|A|R7:ALLOW"
"M10-AL-NO-DATA-TOKEN-CHECK|A|R7:ALLOW"
"M11-RS-NO-STAGED-CHECK|S|R7:STAGED"
"M12-RS-NO-TAKEOVER|S|R7:TAKEOVER"
"M13-RS-NO-DIRTY-DEFAULT|S|R7:DIRTY"
"M14-RS-ALLOW-DIRTY-IGNORED|S|R7:DIRTY"
"M15-NOTE-GITCONFIG-BACK|L|R7:NOTE"
"M16-S13-RERUN-PROMPT|L|R7:SIZE"
)

mutate() { # <id> <src> <dst> -> 0 when the file changed
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys, re
mid, src, dst = sys.argv[1:]
s = open(src, encoding='utf-8').read(); o = s
def sub(old, new, count=1):
    global s
    assert old in s, (mid, old[:70])
    s = s.replace(old, new, count) if count else s.replace(old, new)
def blk(b, old, new):
    global s
    i = s.index('# %s-BEGIN' % b); j = s.index('# %s-END' % b, i); seg = s[i:j]
    assert old in seg, (mid, b, old[:70])
    s = s[:i] + seg.replace(old, new, 1) + s[j:]
QT = "[Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]"
NEW_PROBE = "printf 'bash ./constitution/x.sh\\nsee constitution/legacy_x.sh\\nrun ./constitution/legacyx\\nold legacy path ./constitution/x\\nlegacy: constitution/a\\nconstitution/b (legacy)\\nLEGACY ./constitution/c\\n'"
OLD_PROBE = "printf 'bash ./constitution/x.sh\\nold legacy path ./constitution/x\\n'"
if mid == 'M01-STEP1-NO-SYMLINK-GUARD':
    blk('STEP1', '[ ! -L .constitution-install-backup ] || { echo "STOP: .constitution-install-backup is a symlink; nothing written"; exit 3; }', ':')
elif mid == 'M02-CREDRX-NO-QUERY':   sub("|[?&;][A-Za-z_]*(" + QT + ")[A-Za-z_]*='", "'", 0)
elif mid == 'M03-REDACT-NO-QUERY':   sub("; s#([?&;][A-Za-z_]*(" + QT + ")[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g", "", 0)
elif mid == 'M04-NEEDLE-TWO-LINES':  blk('S7', NEW_PROBE, OLD_PROBE)
elif mid == 'M05-V6-NEEDLE-TWO-LINES': blk('V6', NEW_PROBE, OLD_PROBE)
elif mid == 'M06-LSREMOTE-NO-DDASH': blk('STEP3', 'git ls-remote --exit-code -- "$u" HEAD', 'git ls-remote --exit-code "$u" HEAD')
elif mid == 'M07-AL-PLAIN-WORD-ALWAYS':
    k = s.index('def plain_word_start('); e = s.index('\n', k) + 1; s = s[:e] + '    return True\n' + s[e:]
elif mid == 'M08-AL-SEGMENTS-UNCHECKED':
    sub('        if base in (CMD_LIKE if k == 0 else DANGER_CMDS):', '        if k == 0 and base in CMD_LIKE:')
elif mid == 'M09-AL-RM-TRAILING-OK':  sub('"rm": r"-rf -- \\$\\{tmpdir:\\?\\}",', '"rm": r"-rf -- \\$\\{tmpdir:\\?\\}.*",')
elif mid == 'M10-AL-NO-DATA-TOKEN-CHECK':
    sub(' or DATA_TOKEN.fullmatch(first)):', ' or True):')
elif mid == 'M11-RS-NO-STAGED-CHECK': sub('  if ! rsp_has_prompt_block "$lk/staged"; then', '  if false; then')
elif mid == 'M12-RS-NO-TAKEOVER':     sub('      rsp_take_over_stale "$lk" "$obs" || return 3', '      :')
elif mid == 'M13-RS-NO-DIRTY-DEFAULT': sub('  elif [ "$allow_dirty" = 0 ] && command -v git', '  elif false && command -v git')
elif mid == 'M14-RS-ALLOW-DIRTY-IGNORED': sub('      --allow-dirty) allow_dirty=1; shift ;;', '      --allow-dirty) shift ;;')
elif mid == 'M15-NOTE-GITCONFIG-BACK':
    sub('(correction, round 7: only `.gitmodules` is read; the local\n  `.git/config` is not checked)', 'or the\n  local `.git/config` carries one')
elif mid == 'M16-S13-RERUN-PROMPT':
    k = s.index('  S13 '); e = s.index('If any line FAILs', k)
    s = s[:k] + '  S13 IDEMPOTENCY: re-running this prompt changes nothing.\n' + s[e:]
else:
    sys.exit(9)
open(dst, 'w', encoding='utf-8').write(s)
sys.exit(0 if s != o else 1)
PY
}

killed=0; survived=0; surv=""
for spec in "${SPECS[@]}"; do
  IFS='|' read -r id file guard <<<"$spec"
  [ -z "${R7MM_ONLY:-}" ] || case " $R7MM_ONLY " in *" $id "*) ;; *) continue ;; esac
  d="$W/$id"; mkdir -p "$d"
  case "$file" in
    L) src="$LATEST"; dst="$d/latest.md" ;;
    F1) src="$FU01"; dst="$d/01_verify_incorporation.md" ;;
    A) src="$AL"; dst="$d/git_allowlist.py" ;;
    S) src="$RS"; mkdir -p "$d/scripts/prompts" "$d/scripts/lib"
       cp -- "$REPO/scripts/lib/setup_prompt_extract.sh" "$d/scripts/lib/"; dst="$d/scripts/prompts/rotate_setup_prompt.sh" ;;
  esac
  if ! mutate "$id" "$src" "$dst" 2>"$d/err"; then no "$id: mutant not placed ($(tail -n1 "$d/err"))"; continue; fi
  case "$guard" in
    R7:*) env_k="R7"; sect="${guard#R7:}" ;;
    R5:*) env_k="R5"; sect="${guard#R5:}" ;;
  esac
  envs=()
  case "$env_k:$file" in
    R7:L) envs=(R7_LATEST="$dst") ;; R7:F1) envs=(R7_FU01="$dst") ;; R7:A) envs=(R7_AL="$dst") ;; R7:S) envs=(R7_ROTATE="$dst") ;;
    R5:L) envs=(R5_LATEST="$dst") ;; R5:A) envs=(R5_AL="$dst") ;;
  esac
  if [ "$env_k" = R7 ]; then
    ( export "${envs[@]}" R7_SECT="$sect"; bash "$here/test_setup_prompt_round7.sh" ) >"$d/out" 2>&1; rc=$?
  else
    ( export "${envs[@]}" R5_SECT="$sect"; bash "$here/test_setup_prompt_round5.sh" ) >"$d/out" 2>&1; rc=$?
  fi
  if [ "$rc" -eq 0 ]; then survived=$((survived + 1)); surv="$surv $id"; no "MUTANT SURVIVED $id (guard $guard)"
  else killed=$((killed + 1)); ok "killed $id by $guard: $(grep -m1 '^FAIL' "$d/out" | cut -c1-110)"; fi
done
echo "MUTANTS killed=$killed survived=$survived${surv:+ (survivors:$surv)}"
summary round7_mutants
