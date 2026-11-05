#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SUBMODULE-PIN-NOT-DOWNGRADED.
# Part 1: fixtures vs the gate (GATE_UNDER_TEST overrides the path, used to show RED on an older gate; then Part 2 is
#         skipped because the mutant seds are written against the current gate).
# Part 2: mutants of a scratch gate copy; each MUST change the verdict vector (be killed). Includes the round-2
#         reviewer mutants RM1-RM5 and their killer fixtures.
# Part 3: the hook end to end through `git commit`, with the hook COPIED next to the gate under test (so GATE_UNDER_TEST
#         reaches it too): plain repo, a linked worktree with a REAL submodule (gitdir under .git/worktrees/<wt>/modules),
#         the round-2 waiver-persistence replay, and the layout SKIP.
# Fixtures are throwaway repos under a mktemp dir; the real repo is never touched. HOME is a temp dir.
# Exit 0 proof holds · 1 misclassified/survivor/hook failure · 2 env error.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"; gate="${GATE_UNDER_TEST:-$here/cm_submodule_pin_not_downgraded.sh}"
hook="$here/../hooks/pre-commit-submodule-pin-not-downgraded"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
[ -r "$hook" ] || { echo "META: hook missing" >&2; exit 2; }
tmp="$(mktemp -d)"; [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "META: mktemp failed" >&2; exit 2; }
trap 'rm -rf "${tmp:?}"' EXIT; mkdir -p "$tmp/home"; export HOME="$tmp/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
unset EMAIL
git config --global protocol.file.allow always; git config --global init.defaultBranch main
d10="$(date -d '+10 days' +%F)"; d30="$(date -d '+30 days' +%F)"; d31="$(date -d '+31 days' +%F)"
d45="$(date -d '+45 days' +%F)"; today="$(date +%F)"
bad=0; SUBN=sub
mk() { # sets globals R A B S (no subshell); submodule dir name $SUBN; super pins B
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
conf() { printf '%b' "$2" >"${1:?}/.submodule_pin_gate.conf"; git -C "$1" add .submodule_pin_gate.conf; }
wf() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; } # path old new authoriser expiry item
run() { # repo gate [env assignments / -u X ...] [-- gate args...]; output in $tmp/out
  local r="$1" g="$2"; shift 2; local e=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done; [ "${1:-}" = -- ] && shift
  env "${e[@]}" bash "$g" --root "$r" "$@" >"$tmp/out" 2>&1; echo $?; }
cnt() { grep -c -- "$1" "$tmp/out"; }
classify() { # gate-path -> one-line verdict vector
  local g="$1" out="" r i e w gd o c c2 c3 c4 c5 lnk
  mk;r=$R; stage "$r" "$A"; out+="DOWN=$(run "$r" "$g") "
  mk;r=$R; out+="NOCHANGE=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$S"; out+="DIVERGED=$(run "$r" "$g")/$(cnt '^CM-SUBMODULE-PIN-NOT-DOWNGRADED: WARN') "
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q -m down; stage "$r" "$B"; out+="FORWARD=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; out+="WAIVED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me 2000-01-01 CON-046)\n"; out+="EXPIRED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" '')\n"; out+="NOTRACK=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub/.git"; out+="BLIND=$(run "$r" "$g") "
  mk;r=$R; echo x >"$r/other"; git -C "$r" add other; out+="UNRELATED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$S" me "$d10" CON-046)\n"; out+="WRONGSHA=$(run "$r" "$g") "
  # R2-I1 transition binding: a row for (S -> A) must not cover (B -> A)
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$S" "$A" me "$d10" CON-046)\n"; out+="OLDBIND=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "1111111111111111111111111111111111111111"; out+="NEWOBJ=$(run "$r" "$g")/$(cnt 'new pin 1111111 not in') "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" '' "$d10" CON-046)\n"; out+="NOAUTH=$(run "$r" "$g") "
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; out+="TWOSUB=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$today" CON-046)\n"; out+="TODAY=$(run "$r" "$g") "
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; rm -rf "${r:?}/sub2/.git"; out+="MIXED=$(run "$r" "$g") "
  # expiry form + R2-I1 horizon: far-future dates are refused now
  mk;r=$R; stage "$r" "$A"; e=""
  for i in never 9999 N/A 2026-13-45 2026-2-1 2999-01-01 "$(date +%Y-%m)-32"; do waive "$r" "$(wf sub "$B" "$A" me "$i" CON-046)\n"; e+="$(run "$r" "$g"),"; done; out+="BADEXP=$e "
  # R2-I1 horizon: default max 30 days (inclusive), 31 refused
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d30" CON-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" me "$d31" CON-046)\n"; e+="$(run "$r" "$g")"; out+="HORIZON=$e "
  # consumer DATA read from the BASE commit: committed max 60 honoured; the same config only in the index is not
  mk;r=$R; conf "$r" 'max_waiver_days=60\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d45" CON-046)\n"; e="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'max_waiver_days=60\n'; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d45" CON-046)\n"; e+="$(run "$r" "$g")"; out+="CONF=$e "
  # a bad config disables waivers (fail safe) but never blocks a forward bump (no deadlock)
  mk;r=$R; conf "$r" 'max_waiver_days=9999\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  git -C "$r" rm -q --cached .submodule_pin_waivers; git -C "$r" commit -q -m down; stage "$r" "$B"; e+="$(run "$r" "$g")"; out+="BADCONF=$e "
  # R2-m4 item key is consumer DATA (declared prefix honoured; default stays CON)
  mk;r=$R; conf "$r" 'item_prefix=CAT\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CAT-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CAT-046)\n"; e+="$(run "$r" "$g")"; out+="PREFIX=$e "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" x)\n"; out+="BADITEM=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" t "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" T@T "$d10" CON-046)\n"; e+="$(run "$r" "$g")"; out+="SELFAUTH=$e "
  # R2-m3 authoriser: leading space, <..> form, author identity (name, email), Cyrillic case under LC_ALL=C, NFD vs
  # NFC; last: a distinct authoriser under LC_ALL=C with a Cyrillic committer is accepted (positive control)
  mk;r=$R; stage "$r" "$A"; e=""
  waive "$r" "$(wf sub "$B" "$A" ' me' "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" '<me@x>' "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" zz "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_AUTHOR_NAME=zz GIT_AUTHOR_EMAIL=zz@z),"
  waive "$r" "$(wf sub "$B" "$A" ZZ@Z "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_AUTHOR_NAME=zz GIT_AUTHOR_EMAIL=zz@z),"
  waive "$r" "$(wf sub "$B" "$A" 'МИЛОШ ВАСИЋ' "$d10" CON-046)\n"; e+="$(run "$r" "$g" LC_ALL=C GIT_COMMITTER_NAME='Милош Васић'),"
  waive "$r" "$(wf sub "$B" "$A" $'Milos\xcc\x8c' "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_COMMITTER_NAME=$'Milo\xc5\xa1'),"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g" LC_ALL=C GIT_COMMITTER_NAME='Милош Васић')"; out+="AUTHNORM=$e "
  # RM1 killer: identity unresolvable -> waiver not honoured
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; git -C "$r" config user.useConfigOnly true
  out+="IDENT=$(run "$r" "$g" -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL) "
  mk;r=$R; stage "$r" "$A"; wf sub "$B" "$A" me "$d10" CON-046 >"$r/.submodule_pin_waivers"; out+="UNTRACKED=$(run "$r" "$g") "
  # R2-I1 replay: a waiver committed with an earlier rollback must not cover a later downgrade (row stays in HEAD)
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  git -C "$r" commit -q -m rollback; stage "$r" "$B"; git -C "$r" commit -q -m fwd; stage "$r" "$A"; e+="$(run "$r" "$g")"; out+="PERSIST=$e "
  # --amend view (--base HEAD^): the rollback commit re-checked against its parent is waived; the default base sees no
  # change; a later rollback whose row was already in the parent is refused; an unresolvable --base is BLIND
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; git -C "$r" commit -q -m rollback
  e="$(run "$r" "$g" -- --base HEAD^),$(run "$r" "$g"),"; stage "$r" "$B"; git -C "$r" commit -q -m fwd; stage "$r" "$A"; git -C "$r" commit -q -m again
  e+="$(run "$r" "$g" -- --base HEAD^),"; mk;r=$R; e+="$(run "$r" "$g" -- --base nosuchrev)"; out+="AMEND=$e "
  # RM2 killers: ignore=all from config or .gitmodules must not hide the gitlink change
  mk;r=$R; stage "$r" "$A"; git -C "$r" config diff.ignoreSubmodules all; e="$(run "$r" "$g"),"
  mk;r=$R; stage "$r" "$A"; printf '[submodule "sub"]\n\tpath = sub\n\turl = ./sub\n\tignore = all\n' >"$r/.gitmodules"; git -C "$r" add .gitmodules
  e+="$(run "$r" "$g")"; out+="IGNSUB=$e "
  # RM3 killer: a staged rename to a 4-word name that sorts before the gitlink
  mk;r=$R; printf 'one\ntwo\nthree\nfour\nfive\n' >"$r/file.txt"; git -C "$r" add file.txt; git -C "$r" commit -q -m f
  git -C "$r" mv file.txt "a b c d"; stage "$r" "$A"; out+="RENAME=$(run "$r" "$g") "
  # RM4 killer (7 fields) / RM5 killer (invalid row before a valid row) / CRLF row refused with CR named
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr -d '\n')\t\n"; out+="FIELDS7=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" '' "$d10" CON-046)\n$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; out+="DUPROW=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr -d '\n')\r\n"; out+="CRLF=$(run "$r" "$g")/$(cnt 'CR (CRLF') "
  # R2-m2: unreadable index -> BLIND; --root subdir with diff.relative=true still sees the gitlink
  mk;r=$R; stage "$r" "$A"; printf 'garbage' >"$tmp/badindex"; out+="UNREAD=$(run "$r" "$g" GIT_INDEX_FILE="$tmp/badindex") "
  mk;r=$R; mkdir -p "$r/d"; git -C "$r" config diff.relative true; stage "$r" "$A"; out+="RELATIVE=$(run "$r/d" "$g") "
  # hook-style env (linked worktree, embedded copy): forward ok, downgrade refused
  mk;r=$R; w="$tmp/wt.$RANDOM"; git -C "$r" worktree add -q -b wt "$w" 2>/dev/null
  rm -rf "${w:?}/sub"; cp -a "$r/sub" "$w/sub"; stage "$w" "$A"; git -C "$w" commit -q --no-verify -m down; stage "$w" "$B"
  gd="$(git -C "$w" rev-parse --absolute-git-dir)"
  out+="WT=$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index"),"; git -C "$w" commit -q --no-verify -m up; stage "$w" "$A"
  out+="$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index") "
  # shallow submodule: relation hidden -> BLIND; missing intermediate object -> BLIND
  mk;r=$R; o="$tmp/origin.$RANDOM"; mkdir "$o"; git -C "$o" init -q; for i in 1 2 3; do git -C "$o" commit -q --allow-empty -m "c$i"; done
  c3=$(git -C "$o" rev-parse HEAD); c2=$(git -C "$o" rev-parse HEAD~1)
  rm -rf "${r:?}/sub"; git clone -q --depth 1 "file://$o" "$r/sub"; git -C "$r/sub" fetch -q --depth 1 origin "$c2"
  git -C "$r" update-index --cacheinfo 160000,"$c3",sub; git -C "$r" commit -q -m p3; stage "$r" "$c2"; out+="SHALLOW=$(run "$r" "$g") "
  mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m C; c="$(git -C "$r/sub" rev-parse HEAD)"
  git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pc; rm -f "${r:?}/sub/.git/objects/${B:0:2}/${B:2}"
  stage "$r" "$A"; out+="MISSINGMID=$(run "$r" "$g") "
  # R2-m1: shallow submodule where both directions are provable: forward c4->c5 ok, downgrade c4->c3 FAIL
  mk;r=$R; o="$tmp/origin5.$RANDOM"; mkdir "$o"; git -C "$o" init -q; for i in 1 2 3 4 5; do git -C "$o" commit -q --allow-empty -m "c$i"; done
  c5=$(git -C "$o" rev-parse HEAD); c4=$(git -C "$o" rev-parse HEAD~1); c3=$(git -C "$o" rev-parse HEAD~2)
  rm -rf "${r:?}/sub"; git clone -q --depth 3 "file://$o" "$r/sub"
  git -C "$r" update-index --cacheinfo 160000,"$c4",sub; git -C "$r" commit -q -m p4; stage "$r" "$c5"; e="$(run "$r" "$g"),"
  stage "$r" "$c3"; e+="$(run "$r" "$g")"; out+="SHFWD=$e "
  # replace refs must not change ancestry: graft B to a root commit, then B -> A is still a downgrade (not DIVERGED)
  mk;r=$R; git -C "$r/sub" replace --graft "$B"; stage "$r" "$A"; out+="REPLACE=$(run "$r" "$g") "
  # a submodule checkout path that is a symlink to another clone -> BLIND, named (never read through the link)
  mk;r=$R; o="$tmp/elsewhere.$RANDOM"; git clone -q "$r/sub" "$o" 2>/dev/null; rm -rf "${r:?}/sub"; ln -s "$o" "$r/sub"
  stage "$r" "$A"; out+="SYMSUB=$(run "$r" "$g")/$(cnt 'checkout path is a symlink') "
  # -h prints the whole header (including NOT ENFORCED and Exit)
  out+="HELP=$(bash "$g" -h 2>/dev/null | grep -c -e '^NOT ENFORCED' -e '^Exit: ') "
  SUBN="süb"; mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; out+="NONASCII=$(run "$r" "$g") "; SUBN=sub
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; lnk="$tmp/lnk.$RANDOM"; ln -s "$r" "$lnk"
  out+="SYMROOT=$(run "$lnk" "$g") "
  echo "$out"
}
want="DOWN=1 NOCHANGE=0 DIVERGED=0/1 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1 OLDBIND=1 NEWOBJ=2/1 NOAUTH=1 TWOSUB=1 TODAY=0 MIXED=1 BADEXP=1,1,1,1,1,1,1, HORIZON=0,1 CONF=0,1 BADCONF=1,0 PREFIX=0,1,1 BADITEM=1 SELFAUTH=1,1 AUTHNORM=1,1,1,1,1,1,0 IDENT=1 UNTRACKED=1 PERSIST=0,1 AMEND=0,0,1,2 IGNSUB=1,1 RENAME=1 FIELDS7=1 DUPROW=0 CRLF=1/1 UNREAD=2 RELATIVE=1 WT=0,1 SHALLOW=2 MISSINGMID=2 SHFWD=0,1 REPLACE=1 SYMSUB=2/1 HELP=2 NONASCII=0 SYMROOT=0 "
got="$(classify "$gate")"; echo "gate vector: $got"
[ "$got" = "$want" ] || { echo "BAD  classification:"; echo "  want [$want]"; echo "  got  [$got]"; bad=1; }
# ── Part 2: mutants (skipped under GATE_UNDER_TEST: the seds target the current gate text) ──
n=0
mutant() { # name sed-expr
  local m="$tmp/m$((++n)).sh"; sed "$2" "$gate" >"$m"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1 did not change the gate"; bad=1; return; fi
  local g; g="$(classify "$m")"
  if [ "$g" = "$got" ]; then echo "BAD  mutant $1 SURVIVED"; bad=1; else echo "ok   mutant $1 killed"; fi
}
if [ -z "${GATE_UNDER_TEST:-}" ]; then
  # decision table
  mutant downgrade-never-detected 's/ 2>\/dev\/null; back=\$?/ 2>\/dev\/null; back=1/'
  mutant always-ancestor 's/ 2>\/dev\/null; back=\$?/ 2>\/dev\/null; back=0/'
  mutant forward-not-checked-first 's/ 2>\/dev\/null; fwd=\$?/ 2>\/dev\/null; fwd=1/'
  mutant shallow-unchecked 's/ \&\& \[ "\$shallow" = false \]//'
  mutant undecided-is-ok 's/^    blindmsg "\$path" "ancestry of.*$/    :/'
  mutant diverged-silent 's/WARN \$path/ok $path/'
  mutant blind-is-pass 's/blind=1; }$/blind=0; }/'
  mutant fail-is-pass 's/^\[ "\$fail" = 1 \] \&\& exit 1/[ "$fail" = 1 ] \&\& exit 0/'
  mutant blind-outranks-fail 's/^\[ "\$fail" = 1 \] \&\& exit 1$/[ "$blind" = 1 ] \&\& exit 2/'
  mutant presence-checks-removed '/cat-file -e/{N;d}'
  mutant hook-env-inherited 's/^sg() { env .*git "\$@"; }/sg() { git "$@"; }/'
  mutant replace-refs-honoured 's/ GIT_NO_REPLACE_OBJECTS=1//'
  # reading the index diff (R2-m2, RM2, RM3)
  mutant diff-status-ignored 's/^\[ "\${dstat\[0\]}" = 0 \] || .*$/:/'
  mutant root-not-normalised 's/^root="\$(cd "\$top" \&\& pwd -P)" || .*$/:/'
  mutant RM2-ignore-submodules 's/ --ignore-submodules=none//'
  mutant RM3-renames 's/ --no-renames//'
  mutant no-z-parsing 's/--raw -z/--raw/'
  mutant logical-paths 's/pwd -P/pwd/g'
  mutant base-ignored 's/ --ignore-submodules=none "\$basec"/ --ignore-submodules=none/'
  # waiver row (R2-I1 and the rest of the class)
  mutant novelty-unchecked '/waiver row already in the base commit/d'
  mutant waiver-ignores-old-sha 's/ \&\& \$2==o//'
  mutant waiver-ignores-new-sha 's/ \&\& \$3==n//'
  mutant waiver-ignores-path 's/ \&\& \$1==p//'
  mutant RM4-extra-fields 's/NF==6 \&\&/NF>=6 \&\&/'
  mutant RM5-first-bad-row-aborts 's/3) WHY="\(.*\)" ;;/3) WHY="\1"; return 1 ;;/'
  mutant cr-not-named '/waiver row has a CR/d'
  mutant waiver-from-worktree 's/git -C "\$root" show :.submodule_pin_waivers/cat "$root\/.submodule_pin_waivers"/'
  mutant waiver-ignores-expiry '/\[\[ "\$e" < "\$today" \]\]/d'
  mutant expiry-boundary 's/\[\[ "\$e" < "\$today" \]\]/[[ ! "$e" > "$today" ]]/'
  mutant expiry-format-unchecked '/not a real YYYY-MM-DD date/d'
  mutant horizon-unchecked '/beyond today + max_waiver_days/d'
  mutant horizon-boundary 's/\[\[ "\$e" > "\$lim" \]\]/[[ ! "$e" < "$lim" ]]/'
  mutant item-format-unchecked '/does not match \${prefix}-NNN/d'
  mutant item-prefix-hardcoded 's/\^\${prefix}-/^CON-/'
  mutant config-from-index 's/ctext="\$(blob "\$basec" .submodule_pin_gate.conf)"/ctext="$(git -C "$root" show :.submodule_pin_gate.conf 2>\/dev\/null)"/'
  mutant config-error-ignored 's/^  \[ -z "\$conferr" \] || .*$/  :/'
  # authoriser (R2-m3, RM1)
  mutant RM1-ident-guard '/committer or author identity unresolvable/d'
  mutant self-authoriser-allowed 's/sys.exit(1 if any(.*) else 0)/sys.exit(0)/'
  mutant no-casefold-no-nfc 's/^f=lambda s: .*/f=lambda s: s/'
  mutant casefold-without-nfc 's/unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())/s.casefold()/'
  mutant authoriser-form-unchecked 's/ or a!=a.strip() or "<" in a or ">" in a//'
  mutant empty-authoriser-allowed 's/if not a or /if /'
  mutant author-not-compared 's/"\$(idname "\$aident")" "\$(idmail "\$aident")"/"" ""/'
  mutant help-truncated 's/-h|--help) awk .*$/-h|--help) sed -n 2,40p "$self"; exit 0 ;;/'
fi
# ── Part 3: the hook end to end, hook copied next to the gate under test ─────
lay="$tmp/lay"; mkdir -p "$lay/scripts/gates" "$lay/scripts/hooks"
cp "$gate" "$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
lhook="$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
hk() { git -C "$1" commit -q -m hk >"$tmp/hout" 2>&1; echo $?; }
inst() { ln -s "$lhook" "$1/.git/hooks/pre-commit"; }
mk;r=$R; inst "$r"; stage "$r" "$A"; d1=$(hk "$r")
mk;r=$R; inst "$r"; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; f1=$(hk "$r"); stage "$r" "$A"; d2=$(hk "$r")
# a linked worktree with a REAL submodule (git submodule add + submodule update --init inside the worktree)
up="$tmp/up"; git init -q "$up"; for i in A M B; do git -C "$up" commit -q --allow-empty -m "$i"; done
uA=$(git -C "$up" rev-parse HEAD~2); uB=$(git -C "$up" rev-parse HEAD)
sup="$tmp/sup"; git init -q "$sup"; git -C "$sup" submodule add -q "file://$up" sub >/dev/null 2>&1; git -C "$sup" commit -q -m base; inst "$sup"
git -C "$sup" worktree add -q -b wtr "$tmp/wtr" 2>/dev/null; git -C "$tmp/wtr" submodule update -q --init 2>/dev/null
wgd="$(git -C "$tmp/wtr/sub" rev-parse --absolute-git-dir)"; case "$wgd" in */.git/worktrees/wtr/modules/sub) wlay=real ;; *) wlay="unexpected:$wgd" ;; esac
git -C "$tmp/wtr/sub" checkout -q "$uA"; git -C "$tmp/wtr" commit -q --no-verify -a -m setup
git -C "$tmp/wtr/sub" checkout -q "$uB"; wf1=$(git -C "$tmp/wtr" commit -q -a -m fwd >"$tmp/hout" 2>&1; echo $?)
git -C "$tmp/wtr/sub" checkout -q "$uA"; wd1=$(git -C "$tmp/wtr" commit -q -a -m down >"$tmp/hout" 2>&1; echo $?)
# R2-I1 replay through the hook: reviewed rollback with waiver, re-advance, then a snapshot commit -a over the stale
# checkout that stages only `notes` must be refused (the row is no longer new)
up2="$tmp/up2"; git init -q "$up2"; for i in A B; do git -C "$up2" commit -q --allow-empty -m "$i"; done
pA=$(git -C "$up2" rev-parse HEAD~1); pB=$(git -C "$up2" rev-parse HEAD)
ps="$tmp/ps"; git init -q "$ps"; git -C "$ps" submodule add -q "file://$up2" sub >/dev/null 2>&1; echo 0 >"$ps/notes"; git -C "$ps" add notes
git -C "$ps" commit -q -m base; inst "$ps"
git -C "$ps/sub" checkout -q "$pA"; wf sub "$pB" "$pA" ops "$d10" CON-046 >"$ps/.submodule_pin_waivers"; git -C "$ps" add .submodule_pin_waivers
p1=$(git -C "$ps" commit -q -a -m rollback >"$tmp/hout" 2>&1; echo $?)
git -C "$ps/sub" checkout -q "$pB"; p2=$(git -C "$ps" commit -q -a -m fwd >"$tmp/hout" 2>&1; echo $?)
git -C "$ps/sub" checkout -q "$pA"; echo 1 >"$ps/notes"; p3=$(git -C "$ps" commit -q -a -m snapshot >"$tmp/hout" 2>&1; echo $?)
ppin="$(git -C "$ps" ls-tree HEAD -- sub | awk '{print $3}')"; if [ "$ppin" = "$pB" ]; then pkept=B; else pkept=A; fi
# layout SKIP: hook copied somewhere without ../gates
mkdir -p "$tmp/lonely"; cp "$hook" "$tmp/lonely/pre-commit"; mk;r=$R; echo y >"$r/doc"; git -C "$r" add doc
( cd "$r" && bash "$tmp/lonely/pre-commit" >"$tmp/lout" 2>&1 ); lr=$?
echo "hook: plain downgrade rc=$d1 forward rc=$f1 downgrade-after rc=$d2 ; real-submodule worktree ($wlay) forward rc=$wf1 downgrade rc=$wd1 ; persist rollback rc=$p1 fwd rc=$p2 snapshot rc=$p3 pin=$pkept ; layout-skip rc=$lr [$(head -c 80 "$tmp/lout")]"
if [ "$d1" != 0 ] && [ "$f1" = 0 ] && [ "$d2" != 0 ] && [ "$wlay" = real ] && [ "$wf1" = 0 ] && [ "$wd1" != 0 ] \
  && [ "$p1" = 0 ] && [ "$p2" = 0 ] && [ "$p3" != 0 ] && [ "$pkept" = B ] && [ "$lr" = 0 ] && grep -q SKIP "$tmp/lout"; then :
else echo "BAD  hook end-to-end"; bad=1; fi
exit "$bad"
