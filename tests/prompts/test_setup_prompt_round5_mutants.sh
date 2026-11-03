#!/usr/bin/env bash
# test_setup_prompt_round5_mutants.sh — paired mutation proof (§1.1) for the review round 5 fixes.
# Each mutant is applied to a sandbox copy of one file (latest.md, follow-up 01/02, or the
# allow-list analyser) and the suite that guards it is run on the copy; every mutant must make
# that suite FAIL. Groups:
#   REVIEWER  the nine survivors named by the round-5 review (S1-EXCL-CLOBBER, S4-NODIRTY,
#             S4-NOUNPUSHED, S3-NOEXIST, S3-RRUN-RC0, S5-FETCHOK, S6B-RC, S1-NOCHMOD, R-NOG)
#   OWN       adversarial mutants written for this round against the prompt text and the analyser
# (Every STOP site is additionally mutated one by one by test_setup_prompt_round5_stops_mutants.sh.)
# Env: R5MM_ONLY="<ids>" (a subset). Writes only inside a mktemp -d sandbox.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LATEST="$REPO/docs/prompts/setup/latest.md"
FU01="$REPO/docs/prompts/setup/followups/01_verify_incorporation.md"
FU02="$REPO/docs/prompts/setup/followups/02_wire_decision_layer_optional.md"
AL="$here/git_allowlist.py"
W="$(mk_sandbox)"

# id | file (L F1 F2 A) | guard (R5:<sections> or STOPS:<row id>) — the transformation is in mutate()
SPECS=(
"S1-EXCL-CLOBBER|L|R5:STEP1"        "S1-NOCHMOD|L|R5:STEP1"          "S4-NODIRTY|L|STOPS:S4-NODIRTY"
"S4-NOUNPUSHED|L|STOPS:S4-NOUNPUSHED" "S3-NOEXIST|L|STOPS:S3-EXISTS"    "S3-RRUN-RC0|L|R5:RRUN"
"S5-FETCHOK|L|STOPS:S5-FETCHOK"     "S6B-RC|L|STOPS:S6B-RC"          "R-NOG|L|R5:REDACT"
"O01-CREDRX-HTTP|L|R5:CRED"         "O02-CREDRX-SCP|L|R5:CRED"       "O03-STEP3-NOSKIP|L|R5:CRED"
"O04-GMCRED-NEVER|L|R5:CRED"        "O05-STEP7A-NOSCP|L|R5:CRED"     "O06-REDACT-NOSCP|L|R5:REDACT"
"O07-REDACT-SCP-NOG|L|R5:REDACT"    "O08-HDR-LSREMOTE-RAW|L|R5:REDACT" "O09-STEP4G-GREP-RAW|L|R5:REDACT"
"O10-BOOT-NOSHADOW|L|R5:BOOT"       "O11-FU02-AGENTS-KEPT|F2|R5:BOOT" "O12-STEP1-TOKEN-COPIED|L|R5:SECRETS"
"O13-STEP4G-SECRET-CASE|L|R5:SECRETS" "O14-UNPUSHED-LOCALTAGS|L|R5:UNPUSHED" "O15-UNPUSHED-DEAD-OK|L|R5:UNPUSHED"
"O16-REGEX-LEADZERO|L|R5:REGEX"     "O17-FU01-REGEX-OLD|F1|R5:REGEX"   "O18-WORDING-FIVE|L|R5:WORDING"
"O19-STEP1-CHMOD-TOO-LATE|L|R5:STEP1" "O20-AL-UNKNOWN-WORD-OK|A|R5:ALLOW"     "O21-AL-C-ANYWHERE|A|R5:ALLOW"
"O22-AL-NEG-WINDOW|A|R5:ALLOW"      "O23-AL-PUSH-PLUS|A|EQ:R5:ALLOW"    "O24-FU01-V3-STDERR-RAW|F1|R5:REDACT"
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
R2 = "s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g"
if mid == 'S1-EXCL-CLOBBER': blk('STEP1', """|| echo '.constitution-install-backup/' >> "$excl\"""", """|| echo '.constitution-install-backup/' > "$excl\"""")
elif mid == 'S1-NOCHMOD':    blk('STEP1', 'mkdir -p .constitution-install-backup && chmod 700 .constitution-install-backup || exit 3', 'mkdir -p .constitution-install-backup || exit 3')
elif mid == 'S4-NODIRTY':    blk('STEP4', '[ -z "$(git -C constitution status --porcelain)" ] || { echo "STOP: the legacy constitution has local changes"; exit 3; }', ':')
elif mid == 'S4-NOUNPUSHED': blk('STEP4', '[ -z "$np" ] ||', 'true ||')
elif mid == 'S3-NOEXIST':    blk('STEP3', '[ ! -e submodules/constitution ] || { echo "STOP: submodules/constitution exists but is not a registered submodule"; exit 3; }', ':')
elif mid == 'S3-RRUN-RC0':   blk('STEP3', 'redact; return "$rc"; }', 'redact; return 0; }')
elif mid == 'S5-FETCHOK':    blk('STEP5', 'rrun git -C "$c" fetch --tags origin || { echo "STOP: fetch failed"; exit 3; }', 'rrun git -C "$c" fetch --tags origin; true || { echo "STOP: fetch failed"; exit 3; }')
elif mid == 'S6B-RC':        blk('STEP6B', 'if [ "$rc" -ne 0 ] || grep', 'if grep')
elif mid == 'R-NOG':         blk('STEP5', "s#://[^[:space:]]*@#://***@#g;", "s#://[^[:space:]]*@#://***@#;")
elif mid == 'O01-CREDRX-HTTP': sub("credrx='^([Hh][Tt][Tt][Pp][Ss]?://.*@|", "credrx='^(", 0)
elif mid == 'O02-CREDRX-SCP':  sub("|[^/@:]+:[^/@][^@]*@)|", ")|", 0)
elif mid == 'O03-STEP3-NOSKIP': blk('STEP3', 'redact)"; continue; fi', 'redact)"; fi')
elif mid == 'O04-GMCRED-NEVER': sub('[[ "$v" =~ $credrx ]] && { echo "$k"; return 0; }', ':', 0)
elif mid == 'O05-STEP7A-NOSCP': blk('STEP7A', "|(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@|", "|")
elif mid == 'O06-REDACT-NOSCP': sub('; ' + R2, '', 0)
elif mid == 'O07-REDACT-SCP-NOG': sub(R2, R2[:-1], 0)
elif mid == 'O08-HDR-LSREMOTE-RAW':
    i = s.index('## PROMPT'); j = s.index('# STEP0-BEGIN')
    seg = s[i:j]; old = " 2> >(sed -E '"
    k = seg.index(old); e = seg.index(">&2)", k) + 4
    s = s[:i] + seg[:k] + seg[e:] + s[j:]
elif mid == 'O09-STEP4G-GREP-RAW':
    k = s.index('-- "<that file>" | sed -E'); e = s.index("'", s.index("sed -E '", k) + 8) + 1
    s = s[:k] + '-- "<that file>"' + s[e:]
elif mid == 'O10-BOOT-NOSHADOW': sub(' JEV_BOOTSTRAP_MODE=shadow JEV_HOSTED_PROBE=0', ' JEV_HOSTED_PROBE=0')
elif mid == 'O11-FU02-AGENTS-KEPT': sub(' -u JEV_BOOTSTRAP_AGENTS ', ' ')
elif mid == 'O12-STEP1-TOKEN-COPIED': blk('STEP1', " ! -iname '*token*'", '')
elif mid == 'O13-STEP4G-SECRET-CASE': blk('STEP4G', "':(exclude,glob,icase)**/*secret*'", "':(exclude,glob)**/*secret*'")
elif mid == 'O14-UNPUSHED-LOCALTAGS': sub('--not --remotes ${x[@]+"${x[@]}"} --', '--not --remotes --tags --', 0)
elif mid == 'O15-UNPUSHED-DEAD-OK': sub('[ "$ok" = 1 ] || return 1', '[ "$ok" = 1 ] || return 0', 0)
elif mid == 'O16-REGEX-LEADZERO': blk('STEP5', "'^helixconstitution-v(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$'", "'^helixconstitution-v[0-9]+(\\.[0-9]+)*$'")
elif mid == 'O17-FU01-REGEX-OLD': sub("'^helixconstitution-v(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$'", "'^helixconstitution-v[0-9]+(\\.[0-9]+)*$'")
elif mid == 'O18-WORDING-FIVE': sub('four hosts', 'five hosts')
elif mid == 'O19-STEP1-CHMOD-TOO-LATE': blk('STEP1', 'mkdir -p .constitution-install-backup && chmod 700 .constitution-install-backup || exit 3', '[ -d .constitution-install-backup ] || { mkdir -p .constitution-install-backup && chmod 700 .constitution-install-backup; } || exit 3')
elif mid == 'O20-AL-UNKNOWN-WORD-OK':   # round 7: the closed allow-list; an unknown word must stay refused
    sub('        found.append(("WORD " + w + (" " + joined if joined else ""), False))', '        found.append(("WORD " + w + (" " + joined if joined else ""), True))')
elif mid == 'O21-AL-C-ANYWHERE':   # round 7: git -C must name a project directory
    sub('            if a[1] not in GIT_C_DIRS:', '            if False:')
elif mid == 'O22-AL-NEG-WINDOW':
    sub('        if PROSE_DANGER.search(sent) and not NEG.search(sent):', '        if PROSE_DANGER.search(sent) and not NEG.search(" ".join(x for _, x in prose)):')
elif mid == 'O23-AL-PUSH-PLUS': sub('x.startswith("+") or ', '')
elif mid == 'O24-FU01-V3-STDERR-RAW':
    k = s.index(" 2> >(sed -E '"); e = s.index(">&2)", k) + 4; s = s[:k] + s[e:]
else:
    sys.exit(9)
open(dst, 'w', encoding='utf-8').write(s)
sys.exit(0 if s != o else 1)
PY
}

killed=0; survived=0; equiv=0; surv=""
for spec in "${SPECS[@]}"; do
  IFS='|' read -r id file guard <<<"$spec"
  [ -z "${R5MM_ONLY:-}" ] || case " $R5MM_ONLY " in *" $id "*) ;; *) continue ;; esac
  case "$file" in L) src="$LATEST" ;; F1) src="$FU01" ;; F2) src="$FU02" ;; A) src="$AL" ;; esac
  d="$W/$id"; mkdir -p "$d"; dst="$d/${src##*/}"
  if ! mutate "$id" "$src" "$dst" 2>"$d/err"; then no "$id: mutant not placed ($(tail -n1 "$d/err"))"; continue; fi
  envs=(R5_LATEST="$LATEST" R5_FU01="$FU01" R5_FU02="$FU02")
  case "$file" in L) envs[0]="R5_LATEST=$dst" ;; F1) envs[1]="R5_FU01=$dst" ;; F2) envs[2]="R5_FU02=$dst" ;; esac
  [ "$file" = A ] && envs+=("R5_AL=$dst")
  eq=0; case "$guard" in EQ:*) eq=1; guard="${guard#EQ:}" ;; esac
  case "$guard" in
    R5:*) ( export "${envs[@]}" R5_SECT="${guard#R5:}"; bash "$here/test_setup_prompt_round5.sh" ) >"$d/out" 2>&1; rc=$? ;;
    STOPS:*) ( export R5_LATEST="$dst" R5_ONLY="${guard#STOPS:}"; bash "$here/test_setup_prompt_round5_stops.sh" ) >"$d/out" 2>&1; rc=$? ;;
  esac
  if [ "$eq" = 1 ]; then
    # declared EQUIVALENT: the mutated check is redundant with the allow-list as long as the only push
    # pattern is a fully literal refspec (no "+", no variable). The precondition is asserted, so the
    # moment someone adds a looser push pattern this turns into a FAIL that asks for a killing test.
    np="$(grep -cE '^ +r"push ' "$AL")"; lit="$(grep -E '^ +r"push ' "$AL")"
    if [ "$rc" -eq 0 ] && [ "$np" -eq 1 ] && [[ "$lit" == *'HEAD:refs/heads/main",'* ]] && [[ "$lit" != *'+'* ]]; then
      equiv=$((equiv + 1)); ok "equivalent $id (precondition holds: the single push pattern is literal: $(echo $lit))"
    else no "EQUIVALENCE BROKEN $id rc=$rc push-patterns=$np: write a killing test"; fi
    continue
  fi
  if [ "$rc" -eq 0 ]; then survived=$((survived + 1)); surv="$surv $id"; no "MUTANT SURVIVED $id (guard $guard)"
  else killed=$((killed + 1)); ok "killed $id by $guard: $(grep -m1 '^FAIL' "$d/out" | cut -c1-110)"; fi
done
echo "MUTANTS killed=$killed survived=$survived equivalent=$equiv${surv:+ (survivors:$surv)}"
summary round5_mutants
