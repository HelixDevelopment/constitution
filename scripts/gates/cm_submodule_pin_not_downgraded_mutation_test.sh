#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SUBMODULE-PIN-NOT-DOWNGRADED.
# Part 1: fixtures vs the gate (GATE_UNDER_TEST overrides the path, used to show RED on an older gate).
# Part 2: mutants of a scratch gate copy; each MUST change a verdict vector (be killed). Part 3: the REAL hook end to end
# (plain repo + linked worktree + layout SKIP). Fixtures are throwaway repos under a mktemp dir; the real repo is never touched.
# Exit 0 proof holds · 1 misclassified/survivor · 2 env error.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"; gate="${GATE_UNDER_TEST:-$here/cm_submodule_pin_not_downgraded.sh}"
hook="$here/../hooks/pre-commit-submodule-pin-not-downgraded"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d)"; [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "META: mktemp failed" >&2; exit 2; }
trap 'rm -rf "${tmp:?}"' EXIT; mkdir -p "$tmp/home"; export HOME="$tmp/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
bad=0; SUBN=sub
mk() { # sets globals R A B S (no subshell); submodule dir name $SUBN
  local d; d="$(mktemp -d "$tmp/fx.XXXXXX")"; mkdir -p "$d/super/$SUBN"; git -C "$d/super/$SUBN" init -q
  git -C "$d/super/$SUBN" commit -q --allow-empty -m A; A=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super/$SUBN" commit -q --allow-empty -m B; B=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super/$SUBN" checkout -q -b side "$A"; git -C "$d/super/$SUBN" commit -q --allow-empty -m S; S=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super" init -q; git -C "$d/super" update-index --add --cacheinfo 160000,"$B","$SUBN"
  git -C "$d/super" commit -q -m base; R="$d/super"
}
mk2() { mk; cp -a "${R:?}/sub" "$R/sub2"; git -C "$R" update-index --add --cacheinfo 160000,"$B",sub2; git -C "$R" commit -q -m base2; }
stage() { git -C "$1" update-index --cacheinfo 160000,"$2","${3:-$SUBN}"; }
waive() { printf '%b' "$2" >"${1:?}/.submodule_pin_waivers"; git -C "$1" add .submodule_pin_waivers; }
run() { # repo gate [extra env assignments...] ; output in $tmp/out
  local r="$1" g="$2"; shift 2; env "$@" bash "$g" --root "$r" >"$tmp/out" 2>&1; echo $?; }
wf() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
classify() { # gate-path -> one-line verdict vector
  local g="$1" out="" r i e
  mk;r=$R; stage "$r" "$A"; out+="DOWN=$(run "$r" "$g") "
  mk;r=$R; out+="NOCHANGE=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$S"; out+="DIVERGED=$(run "$r" "$g")/$(grep -c '^CM-SUBMODULE-PIN-NOT-DOWNGRADED: WARN' "$tmp/out") "
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q -m down; stage "$r" "$B"; out+="FORWARD=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" me 2999-01-01 CON-046)\n"; out+="WAIVED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" me 2000-01-01 CON-046)\n"; out+="EXPIRED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" me 2999-01-01 '')\n"; out+="NOTRACK=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub/.git"; out+="BLIND=$(run "$r" "$g") "
  mk;r=$R; echo x >"$r/other"; git -C "$r" add other; out+="UNRELATED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$S" me 2999-01-01 CON-046)\n"; out+="WRONGSHA=$(run "$r" "$g") "
  # R1: new pin object absent -> BLIND with the new-pin cause named
  mk;r=$R; stage "$r" "1111111111111111111111111111111111111111"; out+="NEWOBJ=$(run "$r" "$g")/$(grep -c 'new pin 1111111 not in' "$tmp/out") "
  # R2: empty authoriser
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" '' 2999-01-01 CON-046)\n"; out+="NOAUTH=$(run "$r" "$g") "
  # R3: waiver for sub must not cover sub2 (same sha)
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; waive "$r" "$(wf sub "$A" me 2999-01-01 CON-046)\n"; out+="TWOSUB=$(run "$r" "$g") "
  # R4: expiry == today is still valid
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" me "$(date +%F)" CON-046)\n"; out+="TODAY=$(run "$r" "$g") "
  # R5: FAIL (sub) + BLIND (sub2) -> FAIL outranks
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; rm -rf "${r:?}/sub2/.git"; out+="MIXED=$(run "$r" "$g") "
  # I-3: garbage / unpadded / impossible expiries all refused
  mk;r=$R; stage "$r" "$A"; e=""
  for i in never 9999 N/A 2026-13-45 2026-2-1; do waive "$r" "$(wf sub "$A" me "$i" CON-046)\n"; e+="$(run "$r" "$g"),"; done; out+="BADEXP=$e "
  # I-4: item format, self-authorisation (name and email), untracked waiver file, staged waiver by another identity
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" me 2999-01-01 x)\n"; out+="BADITEM=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$A" t 2999-01-01 CON-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$A" T@T 2999-01-01 CON-046)\n"; e+="$(run "$r" "$g")"; out+="SELFAUTH=$e "
  mk;r=$R; stage "$r" "$A"; wf sub "$A" me 2999-01-01 CON-046 >"$r/.submodule_pin_waivers"; out+="UNTRACKED=$(run "$r" "$g") "
  # I-1: hook-style env (linked worktree): forward ok, downgrade refused
  mk;r=$R; git -C "$r" worktree add -q -b wt "$tmp/wt.$RANDOM" 2>/dev/null; local w; w="$(git -C "$r" worktree list --porcelain | awk '/^worktree /{p=$2} END{print p}')"
  rm -rf "${w:?}/sub"; cp -a "$r/sub" "$w/sub"; stage "$w" "$A"; git -C "$w" commit -q --no-verify -m down; stage "$w" "$B"
  local gd; gd="$(git -C "$w" rev-parse --absolute-git-dir)"
  out+="WT=$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index"),"; git -C "$w" commit -q --no-verify -m up; stage "$w" "$A"
  out+="$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index") "
  # I-2: shallow submodule (relation hidden) and a missing intermediate object -> BLIND, never ok
  mk;r=$R; local o="$tmp/origin.$RANDOM"; mkdir "$o"; git -C "$o" init -q; for i in 1 2 3; do git -C "$o" commit -q --allow-empty -m "c$i"; done
  local c3 c2; c3=$(git -C "$o" rev-parse HEAD); c2=$(git -C "$o" rev-parse HEAD~1)
  rm -rf "${r:?}/sub"; git clone -q --depth 1 "file://$o" "$r/sub"; git -C "$r/sub" fetch -q --depth 1 origin "$c2"
  git -C "$r" update-index --cacheinfo 160000,"$c3",sub; git -C "$r" commit -q -m p3; stage "$r" "$c2"; out+="SHALLOW=$(run "$r" "$g") "
  mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m C; local c; c="$(git -C "$r/sub" rev-parse HEAD)"
  git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pc; rm -f "$r/sub/.git/objects/${B:0:2}/${B:2}"
  stage "$r" "$A"; out+="MISSINGMID=$(run "$r" "$g") "
  # M-1 / M-2
  SUBN="süb"; mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; out+="NONASCII=$(run "$r" "$g") "; SUBN=sub
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; ln -s "$r" "$tmp/lnk.$RANDOM"
  out+="SYMROOT=$(run "$tmp/lnk.$(ls "$tmp" | grep -o '^lnk\.[0-9]*$' | tail -1 | cut -d. -f2)" "$g") "
  echo "$out"
}
want="DOWN=1 NOCHANGE=0 DIVERGED=0/1 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1 NEWOBJ=2/1 NOAUTH=1 TWOSUB=1 TODAY=0 MIXED=1 BADEXP=1,1,1,1,1, BADITEM=1 SELFAUTH=1,1 UNTRACKED=1 WT=0,1 SHALLOW=2 MISSINGMID=2 NONASCII=0 SYMROOT=0 "
got="$(classify "$gate")"; echo "gate vector: $got"
[ "$got" = "$want" ] || { echo "BAD  classification:"; echo "  want [$want]"; echo "  got  [$got]"; bad=1; }
n=0
mutant() { # name sed-expr
  local m="$tmp/m$((++n)).sh"; sed "$2" "$gate" >"$m"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1 did not change the gate"; bad=1; return; fi
  local g; g="$(classify "$m")"
  if [ "$g" = "$got" ]; then echo "BAD  mutant $1 SURVIVED"; bad=1; else echo "ok   mutant $1 killed"; fi
}
mutant no-ancestor-check 's/ 2>\/dev\/null; rc=\$?/ 2>\/dev\/null; rc=1/'
mutant always-ancestor 's/ 2>\/dev\/null; rc=\$?/ 2>\/dev\/null; rc=0/'
mutant blind-is-pass 's/blind=1; }$/blind=0; }/'
mutant waiver-ignores-expiry '/\[\[ "\$e" < "\$today" \]\]/d'
mutant expiry-boundary 's/\[\[ "\$e" < "\$today" \]\]/[[ "$e" <= "$today" ]]/'
mutant expiry-format-unchecked '/not a real YYYY-MM-DD date/d'
mutant waiver-ignores-item-format '/does not match CON-NNN/d'
mutant waiver-ignores-sha 's/ \&\& \$2==n//'
mutant waiver-ignores-path 's/ \&\& \$1==p//'
mutant waiver-ignores-authoriser '/authoriser empty/d'
mutant waiver-allows-self-authoriser '/producer cannot self-waive/d'
mutant waiver-from-worktree 's/git -C "\$root" show :.submodule_pin_waivers/cat "$root\/.submodule_pin_waivers"/'
mutant fail-is-pass 's/^\[ "\$fail" = 1 \] \&\& exit 1/[ "$fail" = 1 ] \&\& exit 0/'
mutant blind-outranks-fail 's/^\[ "\$fail" = 1 \] \&\& exit 1$/[ "$blind" = 1 ] \&\& exit 2/'
mutant presence-checks-removed '/cat-file -e/{N;d}'
mutant hook-env-inherited 's/^sg() { env [^g]*git "\$@"; }/sg() { git "$@"; }/'
mutant rc-other-is-ok 's/^    \*) blindmsg .*$/    *) : ;;/'
mutant shallow-unchecked 's/ \&\& \[ "\$(sg -C "\$sub" rev-parse --is-shallow-repository 2>\/dev\/null)" != false \]//'
mutant no-z-parsing 's/--raw -z/--raw/'
mutant logical-paths 's/pwd -P/pwd/g'
mutant diverged-silent 's/WARN \$path/ok $path/'
# Part 3: the real hook end to end (plain repo, linked worktree, layout SKIP)
hk() { # repo -> commit rc via installed hook symlink
  git -C "$1" commit -q -m hk >"$tmp/hout" 2>&1; echo $?; }
mk;r=$R; ln -s "$(readlink -f "$hook")" "$r/.git/hooks/pre-commit"; stage "$r" "$A"; d1=$(hk "$r")
mk;r=$R; ln -s "$(readlink -f "$hook")" "$r/.git/hooks/pre-commit"
stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; f1=$(hk "$r")
stage "$r" "$A"; d2=$(hk "$r")
# worktree through the real hook
mk;r=$R; ln -s "$(readlink -f "$hook")" "$r/.git/hooks/pre-commit"; git -C "$r" worktree add -q -b wth "$tmp/wth" 2>/dev/null
rm -rf "${tmp:?}/wth/sub"; cp -a "$r/sub" "$tmp/wth/sub"; stage "$tmp/wth" "$A"; git -C "$tmp/wth" commit -q --no-verify -m down; stage "$tmp/wth" "$B"; wf1=$(hk "$tmp/wth")
stage "$tmp/wth" "$A"; wd1=$(hk "$tmp/wth")
# layout SKIP: hook copied somewhere without ../gates
mkdir -p "$tmp/lonely"; cp "$hook" "$tmp/lonely/pre-commit"; mk;r=$R; echo y >"$r/doc"; git -C "$r" add doc
( cd "$r" && bash "$tmp/lonely/pre-commit" >"$tmp/lout" 2>&1 ); lr=$?
echo "hook: plain downgrade rc=$d1 forward rc=$f1 downgrade-after rc=$d2 ; worktree forward rc=$wf1 downgrade rc=$wd1 ; layout-skip rc=$lr [$(head -c 80 "$tmp/lout")]"
[ "$d1" != 0 ] && [ "$f1" = 0 ] && [ "$d2" != 0 ] && [ "$wf1" = 0 ] && [ "$wd1" != 0 ] && [ "$lr" = 0 ] && grep -q SKIP "$tmp/lout" || { echo "BAD  hook end-to-end"; bad=1; }
exit "$bad"
