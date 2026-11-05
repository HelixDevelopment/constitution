#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SUBMODULE-PIN-NOT-DOWNGRADED.
# Part 1: fixtures vs the gate (GATE_UNDER_TEST overrides the path, used to show RED on an older gate; then Part 2 is
#         skipped because the mutant seds are written against the current gate).
# Part 2: mutants of a scratch gate copy; each MUST change the verdict vector (be killed). Includes the round-2
#         reviewer mutants RM1-RM5, the round-3 reviewer mutants RV1, RV3-RV7, the round-4 reviewer mutants RM8-RM14
#         and their killer fixtures (K1-K14), and the round-5 mutants for M-1, M-2 and N-4. Mutants run in
#         parallel, MUT_JOBS at a time (default 3), each in its own temp dir.
# The verdict vector includes the waiver LIFECYCLE class (round 4): every way a reviewed row could be reused by a
#         commit it was not reviewed for (snapshot, amend, merge, conflicted merge, squash, --no-commit merge,
#         cherry-pick, rebase, leftover worktree rows, base-field forms), each through `git commit` with the hook.
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
git config --global protocol.file.allow always; git config --global init.defaultBranch main; git config --global advice.graftFileDeprecated false
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
wf() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-$(git -C "${r:?}" rev-parse HEAD)}"; } # path old new authoriser expiry item [base, default HEAD of $r]
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
  # RM4 killer (8 fields) / the old 6-field form (no base) / RM5 killer (invalid row before a valid row) / CRLF row
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr -d '\n')\t\n"; out+="FIELDS8=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | cut -f1-6)\n"; out+="FIELDS6=$(run "$r" "$g") "
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
  # R3-m3 reviewer killers K1, K3-K5 (RV1, RV3-RV5). K1: base config is a tree (unreadable) -> waivers disabled
  mk;r=$R; mkdir "$r/.submodule_pin_gate.conf"; echo x >"$r/.submodule_pin_gate.conf/x"; git -C "$r" add .submodule_pin_gate.conf
  git -C "$r" commit -q -m cfgdir; git -C "$r" rm -rq --cached .submodule_pin_gate.conf; rm -rf "${r:?}/.submodule_pin_gate.conf"
  stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  # K3 duplicate key, K4 item_prefix with a regex metacharacter, K5 max_waiver_days=400 with a 45-day expiry
  mk;r=$R; conf "$r" 'max_waiver_days=30\nmax_waiver_days=30\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'item_prefix=C.N\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'max_waiver_days=400\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d45" CON-046)\n"; e+="$(run "$r" "$g")"
  out+="KCONF=$e "
  # K6 (RV6): the submodule dir has no .git, the parent holds the submodule's commits, B -> S: BLIND, never read via the parent
  mk;r=$R; git -C "$r" fetch -q "$r/sub" "$B:refs/x/b" "side:refs/x/s" 2>/dev/null; stage "$r" "$S"; mv "$r/sub/.git" "$tmp/subgit.$RANDOM"
  out+="NOTOWN=$(run "$r" "$g")/$(cnt 'not its own repository') "
  # RV7: lazy fetch off. The submodule is a partial clone; the new pin exists only on its promisor remote -> BLIND, nothing fetched
  mk;r=$R; o="$tmp/lz.$RANDOM"; git init -q "$o"; git -C "$o" config uploadpack.allowfilter true; git -C "$o" config uploadpack.allowanysha1inwant true
  git -C "$o" commit -q --allow-empty -m l1; c="$(git -C "$o" rev-parse HEAD)"; rm -rf "${r:?}/sub"; git clone -q --filter=blob:none "file://$o" "$r/sub" 2>/dev/null
  git -C "$o" commit -q --allow-empty -m l2; c2="$(git -C "$o" rev-parse HEAD)"; git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pl
  stage "$r" "$c2"; e="$(run "$r" "$g")"
  out+="LAZY=$e/$(git -C "$r/sub" config remote.origin.promisor)/$(GIT_NO_LAZY_FETCH=1 git -C "$r/sub" cat-file -e "$c2^{commit}" 2>/dev/null && echo fetched || echo absent) "
  # R3-m1: legacy info/grafts in the submodule must not hide ancestry (B made parentless: still a downgrade, not DIVERGED)
  mk;r=$R; printf '%s\n' "$B" >"$r/sub/.git/info/grafts"; stage "$r" "$A"; out+="GRAFT=$(run "$r" "$g") "
  # R3-n1: string comparison in awk: a row for path 10 must not waive the gitlink at path 1e1
  SUBN=1e1; mk;r=$R; stage "$r" "$A" 1e1; waive "$r" "$(wf 10 "$B" "$A" ops "$d10" CON-046)\n"; out+="NUMPATH=$(run "$r" "$g") "; SUBN=sub
  # R3-n4: a python3 that fails (exit 1) means "authoriser check failed", never "self-waive"
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; mkdir -p "$tmp/fakepy"
  printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$tmp/fakepy/python3"; chmod +x "$tmp/fakepy/python3"
  e="$(run "$r" "$g" PATH="$tmp/fakepy:$PATH")"; out+="PYFAIL=$e/$(cnt 'authoriser check failed')/$(cnt 'cannot self-waive') "
  # spent check reads sibling commits: one on the same base whose waiver path is a tree cannot be read -> not waived
  mk;r=$R; git -C "$r" checkout -q -b y; mkdir "$r/.submodule_pin_waivers"; echo x >"$r/.submodule_pin_waivers/x"; git -C "$r" add .submodule_pin_waivers
  git -C "$r" commit -q -m y; git -C "$r" checkout -q main; rm -rf "${r:?}/.submodule_pin_waivers"; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  e="$(run "$r" "$g")"; out+="CHILDTREE=$e/$(cnt 'unreadable') "
  # a broken ref makes `rev-list --all` fail: the row cannot be proven unspent -> not waived
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; mkdir -p "$r/.git/refs/heads"
  printf '%s\n' 1111111111111111111111111111111111111111 >"$r/.git/refs/heads/broken"; e="$(run "$r" "$g")"; out+="BADREF=$e/$(cnt 'rev-list --all failed') "
  # a sibling commit on the same parent carrying a row for the same transition but bound to ANOTHER base spends nothing
  mk;r=$R; git -C "$r" checkout -q -b y; wf sub "$B" "$A" ops "$d10" CON-046 2222222222222222222222222222222222222222 >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; git -C "$r" commit -q -m y; git -C "$r" checkout -q main; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  out+="SIBOTHER=$(run "$r" "$g") "
  out+="$(lifecycle "$g")"
  echo "$out"
}
# ── the waiver LIFECYCLE class, through `git commit` with the hook (real submodule, one worktree) ─────────────
# Rule under test: one row = one transition (path, old, new) in one single-parent commit whose parent is the row's base;
# the first such commit on a ref spends it. Each member is a way a row could be reused by a commit it was not reviewed for.
lc_sup() { # sets SR uA uB: superproject with a REAL submodule `sub` at uB (upstream A <- B), file notes, hook $1
  local up; up="$(mktemp -d "$tmp/up.XXXXXX")"; git -C "$up" init -q; for i in A B; do git -C "$up" commit -q --allow-empty -m "$i"; done
  uA=$(git -C "$up" rev-parse HEAD~1); uB=$(git -C "$up" rev-parse HEAD); SR="$(mktemp -d "$tmp/sup.XXXXXX")"; git -C "$SR" init -q
  git -C "$SR" submodule add -q "file://$up" sub >/dev/null 2>&1; echo 0 >"$SR/notes"; git -C "$SR" add -A; git -C "$SR" commit -q --no-verify -m base
  ln -s "$1" "$SR/.git/hooks/pre-commit"; }
lrow() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub "$uB" "$uA" ops "$d10" CON-046 "$1"; } # <base>
lgc() { local r="$1"; shift; git -C "$r" commit -q "$@" >"$tmp/hout" 2>&1; echo $?; }
lpin() { case "$(git -C "$1" ls-tree "${2:-HEAD}" -- sub | awk '{print $3}')" in "$uA") echo A ;; "$uB") echo B ;; *) echo X ;; esac; }
lg() { bash "$LG" --root "$@" >"$tmp/gout" 2>&1; echo $?; }
lrb() { # in ${1:-$SR}: checkout to A (stale against pin B), row bound to HEAD, staged, commit -a = the reviewed rollback
  local r="${1:-$SR}"; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; lgc "$r" -a -m rollback; }
lc_veh() { # vehicle X at main's tip: reviewed rollback Rc, index-only forward; back on main (checkout stays at A)
  lc_sup "$LH"; git -C "$SR" checkout -q -b X; lrb >/dev/null; Rc=$(git -C "$SR" rev-parse HEAD)
  git -C "$SR" update-index --cacheinfo 160000,"$uB",sub; lgc "$SR" -m fwd >/dev/null; git -C "$SR" checkout -q main; }
lc_x() { # <moved|same> <conflict|-> : vehicle X at main's tip: reviewed rollback, [notes edit], index-only forward to B;
  # back on main (the checkout stays at A, as after any branch switch), main then moved or not
  lc_sup "$LH"; git -C "$SR" checkout -q -b X; LX1=$(lrb); if [ "$2" = conflict ]; then echo x >"$SR/notes"; lgc "$SR" -m xn -- notes >/dev/null; fi
  git -C "$SR" update-index --cacheinfo 160000,"$uB",sub; lgc "$SR" -m fwd >/dev/null; git -C "$SR" checkout -q main
  if [ "$1" = moved ]; then echo m >"$SR/notes"; lgc "$SR" -m mn -- notes >/dev/null; fi; }
lifecycle() { # gate path -> vector part
  local g="$1" o="" r a b c x lay; lay="$(mktemp -d "$tmp/lay.XXXXXX")"; mkdir -p "$lay/scripts/gates" "$lay/scripts/hooks"
  cp "$g" "$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
  LH="$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"; LG="$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"
  # legit reviewed rollback; then the R2-I1 snapshot over the stale checkout; then the same snapshot as --amend -a
  lc_sup "$LH"; r=$SR; a=$(lrb); o+="LEGIT=$a/$(lpin "$r") "
  git -C "$r" update-index --cacheinfo 160000,"$uB",sub; b=$(lgc "$r" -m fwd); echo 1 >"$r/notes"; c=$(lgc "$r" -a -m snapshot)
  x=$(lgc "$r" --amend -a -m snapshot2); o+="SNAP=$b,$c/$(lpin "$r") AMENDSNAP=$x/$(lpin "$r") "
  # amend the message of the reviewed rollback, re-judge it against its parent (--base HEAD^), then reset --soft and redo
  lc_sup "$LH"; r=$SR; a=$(lrb); b=$(lgc "$r" --amend -m rollback2); c=$(lg "$r" --base HEAD^); git -C "$r" reset -q --soft HEAD^
  x=$(lgc "$r" -m redo); o+="AMENDMSG=$a,$b,$c REDO=$x/$(lpin "$r") "
  # integrate the vehicle into main: conflicted merge, squash, --no-commit merge; main moved or not
  lc_x moved conflict; r=$SR; git -C "$r" merge -q X >/dev/null 2>&1; echo r >"$r/notes"; a=$(lgc "$r" -a -m merge); o+="MERGECONF=$LX1,$a/$(lpin "$r") "
  lc_x moved -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; a=$(lgc "$r" -a -m sq); o+="SQUASHMOVED=$a/$(lpin "$r") "
  lc_x same -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; a=$(lgc "$r" -a -m sq); o+="SQUASHSAME=$a/$(lpin "$r")/$(grep -c 'already spent' "$tmp/hout") "
  lc_x moved -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; a=$(lgc "$r" -a -m nc); o+="NOCOMMITMOVED=$a/$(lpin "$r") "
  lc_x same -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; a=$(lgc "$r" -a -m nc); o+="NOCOMMITSAME=$a/$(lpin "$r") "
  # the one-parent clause alone: the vehicle (and so its rollback) is deleted while the merge is open
  lc_x same -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; git -C "$r" branch -q -D X; a=$(lgc "$r" -a -m nc)
  o+="NOCOMMITDEL=$a/$(lpin "$r")/$(grep -c 'single-parent' "$tmp/hout") "
  # a superproject graft (written after the squash) must not hide the spent rollback (made parentless by the graft)
  lc_x same -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; b=$(git -C "$r" diff --cached --name-only | grep -c '^\.submodule_pin_waivers$')
  git -C "$r" rev-parse X~1 >"$r/.git/info/grafts"; a=$(lgc "$r" -a -m sq); o+="SQGRAFT=$a/$(lpin "$r")/$b "
  # cherry-pick and rebase run no pre-commit hook when clean (measured); the gate in --base mode judges the result
  lc_x moved -; r=$SR; a=$(git -C "$r" cherry-pick X~1 >/dev/null 2>&1; echo $?); b=$(lg "$r" --base HEAD^); o+="CHERRY=$a,$b "
  # (-x: a clean pick onto the same parent in the same second would otherwise be byte-identical, i.e. the reviewed commit)
  lc_x same -; r=$SR; a=$(git -C "$r" cherry-pick -x X~1 >/dev/null 2>&1; echo $?); b=$(lg "$r" --base HEAD^)
  c=$([ "$(git -C "$r" rev-parse HEAD)" != "$(git -C "$r" rev-parse X~1)" ] && echo distinct || echo same); o+="CHERRYSAME=$a,$b/$c "
  lc_x moved -; r=$SR; git -C "$r" checkout -q X; a=$(git -C "$r" rebase -q main >/dev/null 2>&1; echo $?); git -C "$r" checkout -q --detach X~1
  b=$(lg "$r" --base HEAD^); o+="REBASE=$a,$b "
  # leftover worktree rows: bound to the current HEAD (honoured: the documented residual) and to an older HEAD (refused)
  lc_sup "$LH"; r=$SR; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r/sub" checkout -q "$uA"; git -C "$r" add -A
  a=$(lgc "$r" -m snap); o+="LEFTSAME=$a/$(lpin "$r") "
  lc_sup "$LH"; r=$SR; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; echo 1 >"$r/notes"; lgc "$r" -m n -- notes >/dev/null
  git -C "$r/sub" checkout -q "$uA"; git -C "$r" add -A; a=$(lgc "$r" -m snap); o+="LEFTOLD=$a/$(lpin "$r")/$(grep -c 'bound to base' "$tmp/hout") "
  # base field forms: an abbreviated sha and the literal HEAD are refused
  lc_sup "$LH"; r=$SR; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse --short HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
  a=$(lgc "$r" -a -m rb); lrow HEAD >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; b=$(lgc "$r" -a -m rb); o+="BASEFORM=$a,$b/$(lpin "$r") "
  # ── round-5: the round-4 reviewer's killer fixtures K8-K14 (probes/p7_killers.sh), adopted as written with the
  # lc_* helpers in place of the probe library's (sup=lc_sup, rb=lrb, gc=lgc, pin=lpin, row=lrow, vehicle=lc_veh) ──
  # K8: the spender is reachable only from a tag (vehicle branch deleted) -> refused
  lc_veh; r=$SR; git -C "$r" tag t "$Rc"; x=$(git -C "$r" rev-parse X); git -C "$r" branch -q -D X; git -C "$r" merge -q --squash "$x" >/dev/null 2>&1
  o+="K8TAG=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K14: the spender is only the detached HEAD of another worktree -> refused (rev-list --all covers all worktrees)
  lc_sup "$LH"; r=$SR; w="$tmp/w.$RANDOM"; git -C "$r" worktree add -q --detach "$w" 2>/dev/null; git -C "$w" submodule update -q --init 2>/dev/null
  lrb "$w" >/dev/null; git -C "$w" update-index --cacheinfo 160000,"$uB",sub; lgc "$w" -m fwd >/dev/null
  git -C "$r" merge -q --squash "$(git -C "$w" rev-parse HEAD)" >/dev/null 2>&1; git -C "$r/sub" checkout -q "$uA"; o+="K14WT=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K9: a superproject replace ref makes the spender parentless; replace refs must be ignored -> refused
  lc_veh; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; git -C "$r" replace --graft "$Rc"; o+="K9REPL=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K11 / K12: a sibling on the same parent whose row is for ANOTHER path / ANOTHER old sha is no spender -> waived
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub2 "$uB" "$uA" ops "$d10" CON-046 "$x" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; o+="K11PATH=$(lrb)/$(lpin "$r") "
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub 3333333333333333333333333333333333333333 "$uA" ops "$d10" CON-046 "$x" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; o+="K12OLD=$(lrb)/$(lpin "$r") "
  # K13: a sibling's waiver path is a tree (the spent check cannot tell) -> refused, through the hook
  lc_sup "$LH"; r=$SR; git -C "$r" checkout -q -b Y; mkdir "$r/.submodule_pin_waivers"; echo x >"$r/.submodule_pin_waivers/x"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; rm -rf "${r:?}/.submodule_pin_waivers"; o+="K13TELL=$(lrb)/$(lpin "$r") "
  # K10: blob:none partial superproject, the spender's waiver blob only on the promisor -> refused as unreadable, nothing fetched
  lc_veh; r=$SR; git -C "$r/sub" checkout -q "$uB"; git -C "$r" config uploadpack.allowfilter true; git -C "$r" config uploadpack.allowanysha1inwant true
  b=$(git -C "$r" rev-parse "$Rc:.submodule_pin_waivers"); c="$tmp/bn.$RANDOM"; git clone -q --no-local --filter=blob:none "file://$r" "$c" 2>/dev/null
  git -C "$c" submodule update -q --init 2>/dev/null; ln -s "$LH" "$c/.git/hooks/pre-commit"
  lrow "$(git -C "$c" rev-parse HEAD)" | sed 's/\tops\t/\tops2\t/' >"$c/.submodule_pin_waivers"; git -C "$c" add .submodule_pin_waivers; git -C "$c/sub" checkout -q "$uA"
  x=$(GIT_NO_LAZY_FETCH=1 git -C "$c" cat-file -e "$b" 2>/dev/null && echo present || echo absent)
  a=$(lgc "$c" -a -m snap); y=$(GIT_NO_LAZY_FETCH=1 git -C "$c" cat-file -e "$b" 2>/dev/null && echo present || echo absent)
  o+="K10LAZY=$a/$x/$y/$(grep -c unreadable "$tmp/hout") "
  # ── round-5 M-1: the spender's TREE is missing (incomplete object store) -> unreadable, refused (never "absent") ──
  lc_sup "$LH"; r=$SR; git -C "$r" checkout -q -b X; lrb >/dev/null; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q main; git -C "$r/sub" checkout -q "$uB"
  b=$(git -C "$r" rev-parse "$x^{tree}"); rm -f "${r:?}/.git/objects/${b:0:2}/${b:2}"
  lrow "$(git -C "$r" rev-parse HEAD)" | sed 's/\tops\t/\tops2\t/' >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; git -C "$r/sub" checkout -q "$uA"
  a=$(lgc "$r" -a -m snap); o+="TREEMISS=$a/$(lpin "$r")/$(GIT_NO_LAZY_FETCH=1 git -C "$r" cat-file -e "$b" 2>/dev/null && echo present || echo missing)/$(grep -c unreadable "$tmp/hout") "
  # M-1: a shallow superproject hides the spender's parent (R is a shallow boundary) -> waivers refused
  lc_veh; r=$SR; git -C "$r/sub" checkout -q "$uB"; c="$tmp/sh.$RANDOM"; git clone -q --no-local --depth 1 --branch main "file://$r" "$c" 2>/dev/null
  git -C "$c" fetch -q --depth 2 origin X:refs/remotes/origin/X 2>/dev/null; git -C "$c" submodule update -q --init 2>/dev/null; ln -s "$LH" "$c/.git/hooks/pre-commit"
  git -C "$c" checkout -q origin/X -- .submodule_pin_waivers; git -C "$c/sub" checkout -q "$uA"; a=$(lgc "$c" -a -m snap)
  o+="SHALLOWSUP=$a/$(lpin "$c")/$(git -C "$c" rev-parse --is-shallow-repository)/$(grep -c 'superproject is shallow' "$tmp/hout") "
  # M-2: a stash of the staged reviewed rollback is no spender: stash push, stash apply --index, commit -a -> waived
  lc_sup "$LH"; r=$SR; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r" add -A
  git -C "$r" stash push -q >/dev/null 2>&1; git -C "$r" stash apply -q --index >/dev/null 2>&1; git -C "$r/sub" checkout -q "$uA"
  a=$(lgc "$r" -a -m rollback); o+="STASH=$a/$(lpin "$r")/$(git -C "$r" rev-parse -q --verify refs/stash >/dev/null && echo kept || echo gone) "
  # N-4: --base mode, HEAD = the reviewed rollback R. An index equal to HEAD's tree is HEAD (R not counted: waived); an
  # index that differs from HEAD's tree is another commit, so R counts as a spender (refused)
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; lrb >/dev/null; c=$(git -C "$r" rev-parse HEAD)
  git -C "$r" read-tree "$x"; git -C "$r" checkout "$c" -- .submodule_pin_waivers; git -C "$r" update-index --cacheinfo 160000,"$uA",sub
  a=$(lg "$r" --base "$x"); echo n4 >"$r/notes"; git -C "$r" add notes; b=$(lg "$r" --base "$x"); o+="N4INDEX=$a,$b "
  # M-3 documented residual (pinned): reviewed rollback + index-only forward, then `reset --soft HEAD~2 && commit -a` over
  # the stale checkout: the rollback is reflog-only, so the row waives again and A lands (header: Residual)
  lc_sup "$LH"; r=$SR; a=$(lrb); git -C "$r" update-index --cacheinfo 160000,"$uB",sub; b=$(lgc "$r" -m fwd); git -C "$r" reset -q --soft HEAD~2
  c=$(lgc "$r" -a -m squash); o+="RESETSQ=$a,$b,$c/$(lpin "$r") "
  echo "$o"
}
want="DOWN=1 NOCHANGE=0 DIVERGED=0/1 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1 OLDBIND=1 NEWOBJ=2/1 NOAUTH=1 TWOSUB=1 TODAY=0 MIXED=1 BADEXP=1,1,1,1,1,1,1, HORIZON=0,1 CONF=0,1 BADCONF=1,0 PREFIX=0,1,1 BADITEM=1 SELFAUTH=1,1 AUTHNORM=1,1,1,1,1,1,0 IDENT=1 UNTRACKED=1 PERSIST=0,1 AMEND=0,0,1,2 IGNSUB=1,1 RENAME=1 FIELDS8=1 FIELDS6=1 DUPROW=0 CRLF=1/1 UNREAD=2 RELATIVE=1 WT=0,1 SHALLOW=2 MISSINGMID=2 SHFWD=0,1 REPLACE=1 SYMSUB=2/1 HELP=2 NONASCII=0 SYMROOT=0 KCONF=1,1,1,1 NOTOWN=2/1 LAZY=2/true/absent GRAFT=1 NUMPATH=1 PYFAIL=1/1/0 CHILDTREE=1/1 BADREF=1/1 SIBOTHER=0 LEGIT=0/A SNAP=0,1/B AMENDSNAP=1/B AMENDMSG=0,0,0 REDO=0/A MERGECONF=0,1/B SQUASHMOVED=1/B SQUASHSAME=1/B/1 NOCOMMITMOVED=1/B NOCOMMITSAME=1/B NOCOMMITDEL=1/B/1 SQGRAFT=1/B/1 CHERRY=0,1 CHERRYSAME=0,1/distinct REBASE=0,1 LEFTSAME=0/A LEFTOLD=1/B/1 BASEFORM=1,1/B K8TAG=1/B K14WT=1/B K9REPL=1/B K11PATH=0/A K12OLD=0/A K13TELL=1/B K10LAZY=1/absent/absent/1 TREEMISS=1/B/missing/1 SHALLOWSUP=1/B/true/1 STASH=0/A/kept N4INDEX=0,1 RESETSQ=0,0,0/A "
got="$(classify "$gate")"; echo "gate vector: $got"
[ "$got" = "$want" ] || { echo "BAD  classification:"; echo "  want [$want]"; echo "  got  [$got]"; bad=1; }
# ── Part 2: mutants (skipped under GATE_UNDER_TEST: the seds target the current gate text) ──
# Each mutant is classified in a background job with its own temp dir; MUT_JOBS jobs at a time (bounded, §12.8).
n=0; mj="${MUT_JOBS:-3}"; [[ "$mj" =~ ^[1-9][0-9]?$ ]] || { echo "META: MUT_JOBS must be 1..99" >&2; exit 2; }; mnames=()
mutant() { # name sed-expr
  local m="$tmp/m$((++n)).sh"; sed "$2" "$gate" >"$m"; mnames[n]="$1"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1 did not change the gate"; bad=1; mnames[n]=""; return; fi
  ( tmp="$tmp/j$n"; mkdir -p "$tmp"; classify "$m" >"$tmp.res" 2>/dev/null ) &
  while [ "$(jobs -rp | wc -l)" -ge "$mj" ]; do wait -n; done
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
  mutant replace-refs-honoured '/^sg() /s/ GIT_NO_REPLACE_OBJECTS=1//'
  mutant R3m1-grafts-honoured '/^sg() /s/ GIT_GRAFT_FILE=\/dev\/null//'
  mutant RV7-lazy-fetch '/^sg() /s/ GIT_NO_LAZY_FETCH=1//'
  mutant RV6-own-repo-unchecked 's/^    blindmsg "\$path" "path is not its own repository.*$/    :; fi/'
  # reading the index diff (R2-m2, RM2, RM3)
  mutant diff-status-ignored 's/^\[ "\${dstat\[0\]}" = 0 \] || .*$/:/'
  mutant root-not-normalised 's/^root="\$(cd "\$top" \&\& pwd -P)" || .*$/:/'
  mutant RM2-ignore-submodules 's/ --ignore-submodules=none//'
  mutant RM3-renames 's/ --no-renames//'
  mutant no-z-parsing 's/--raw -z/--raw/'
  mutant logical-paths 's/pwd -P/pwd/g'
  mutant base-ignored 's/ --ignore-submodules=none "\$basec"/ --ignore-submodules=none/'
  # waiver lifetime: ONE row = one transition, one commit, one parent (round 4)
  mutant base-unbound '/waiver row is bound to base/d'
  mutant merge-allowed '/a waiver is valid only in a single-parent commit/d'
  mutant spent-unchecked 's/      0) spent "\$1" "\$2" "\$3"; case \$? in/      0) case 1 in/'
  mutant spent-head-counted 's/        \$1""!=h"" {for/        {for/'
  mutant spent-base-ignored 's/ \&\& \$7""==b"" {f=0}/ {f=0}/'
  mutant spent-unreadable-ignored '/(same parent) is unreadable/d'
  mutant spent-history-error-ignored 's/^  \[ "\$kidsrc" = ok \] || .*$/  :/'
  mutant spent-grafts-honoured '/^pg() /s/ GIT_GRAFT_FILE=\/dev\/null//'
  # round-4 reviewer mutants RM8-RM14 (adopted, §11.4.276(D)). RM9-RM13 are the reviewer's seds unchanged; RM8 and RM14
  # target the round-5 text `--exclude=refs/stash --all` (RM14 keeps --single-worktree BEFORE --all, else it is equivalent)
  mutant RM8-scope-branches-only 's/pg rev-list --exclude=refs\/stash --all --parents/pg rev-list --branches --parents/'
  mutant RM9-super-replace-honoured '/^pg() /s/ GIT_NO_REPLACE_OBJECTS=1//'
  mutant RM10-super-lazy-fetch '/^pg() /s/GIT_NO_LAZY_FETCH=1 //'
  mutant RM11-spent-ignores-path 's/^      NF==7 \&\& \$1""==p"" \&\& \$2""==o""/      NF==7 \&\& $2""==o""/'
  mutant RM12-spent-ignores-old 's/^      NF==7 \&\& \$1""==p"" \&\& \$2""==o"" \&\& /      NF==7 \&\& $1""==p"" \&\& /'
  mutant RM13-spent-cannot-tell-is-unspent 's/^           \*) WHY="\$SPENT; cannot prove the row is unspent" ;;/           *) return 0 ;;/'
  mutant RM14-single-worktree 's/pg rev-list --exclude=refs\/stash --all --parents/pg rev-list --exclude=refs\/stash --single-worktree --all --parents/'
  # round-5: missing tree read as absent (M-1), shallow superproject unchecked (M-1), stash counted (M-2), HEAD always
  # excluded from spenders (N-4)
  mutant M1-tree-missing-is-absent '/^  pg cat-file -e "\$1^{tree}" 2>\/dev\/null || return 2$/d'
  mutant M1-shallow-superproject-unchecked 's/^    if \[ "\$(pg rev-parse --is-shallow-repository 2>\/dev\/null)" != false \]; then kidsrc=shallow$/    if false; then :/'
  mutant M2-stash-counted '/^    elif all=/s/ --exclude=refs\/stash//'
  mutant N4-head-always-excluded 's/ 2>\/dev\/null \&\& hx="\$headc"$/; hx="$headc"/'
  # waiver row form
  mutant waiver-ignores-old-sha 's/ \&\& \$2""==o""//'
  mutant waiver-ignores-new-sha 's/ \&\& \$3""==n""//'
  mutant waiver-ignores-path 's/ \&\& \$1""==p""//'
  mutant R3n1-numeric-compare 's/\$1""==p""/$1==p/'
  mutant RM4-extra-fields 's/    NF==7 \&\& \$1!~/    NF>=7 \&\& $1!~/'
  mutant six-field-rows 's/    NF==7 \&\& \$1!~/    NF>=6 \&\& $1!~/'
  mutant RM5-first-bad-row-aborts 's/3) WHY="\(.*\)" ;;/3) WHY="\1"; return 1 ;;/'
  mutant cr-not-named '/waiver row has a CR/d'
  mutant waiver-from-worktree 's/pg show :.submodule_pin_waivers/cat "$root\/.submodule_pin_waivers"/'
  mutant waiver-ignores-expiry '/\[\[ "\$e" < "\$today" \]\]/d'
  mutant expiry-boundary 's/\[\[ "\$e" < "\$today" \]\]/[[ ! "$e" > "$today" ]]/'
  mutant expiry-format-unchecked '/not a real YYYY-MM-DD date/d'
  mutant horizon-unchecked '/beyond today + max_waiver_days/d'
  mutant horizon-boundary 's/\[\[ "\$e" > "\$lim" \]\]/[[ ! "$e" < "$lim" ]]/'
  mutant item-format-unchecked '/does not match \${prefix}-NNN/d'
  mutant item-prefix-hardcoded 's/\^\${prefix}-/^CON-/'
  # consumer DATA (config from the base commit) and the reviewer killers K1, K3-K5
  mutant config-from-index 's/ctext="\$(blob "\$basec" .submodule_pin_gate.conf)"/ctext="$(git -C "$root" show :.submodule_pin_gate.conf 2>\/dev\/null)"/'
  mutant config-error-ignored 's/^  \[ -z "\$conferr" \] || .*$/  :/'
  mutant RV1-config-unreadable-as-absent 's/^if \[ "\$crc" = 2 \]; then conferr=.*$/if false; then :/'
  mutant RV3-duplicate-key-allowed 's/^    case "\$seen" in .*$/    :/'
  mutant RV4-prefix-unvalidated 's/item_prefix) \[\[ "\$v" =~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\] || /item_prefix) true || /'
  mutant RV5-365-cap-removed 's/ \&\& \[ "\$v" -le 365 \]//'
  # authoriser (R2-m3, RM1, R3-n4)
  mutant RM1-ident-guard '/committer or author identity unresolvable/d'
  mutant self-authoriser-allowed 's/    return 10 if any(.*) else 0/    return 0/'
  mutant R3n4-failure-reported-as-self 's/^      10) WHY=/      1|10) WHY=/'
  mutant no-casefold-no-nfc 's/^    f=lambda s: .*/    f=lambda s: s/'
  mutant casefold-without-nfc 's/unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())/s.casefold()/'
  mutant authoriser-form-unchecked 's/ or a!=a.strip() or "<" in a or ">" in a//'
  mutant empty-authoriser-allowed 's/if not a or /if /'
  mutant author-not-compared 's/"\$(idname "\$aident")" "\$(idmail "\$aident")"/"" ""/'
  mutant help-truncated 's/-h|--help) awk .*$/-h|--help) sed -n 2,40p "$self"; exit 0 ;;/'
  wait
  for ((k=1; k<=n; k++)); do
    [ -n "${mnames[k]:-}" ] || continue
    if [ ! -s "$tmp/j$k.res" ]; then echo "BAD  mutant ${mnames[k]} produced no vector"; bad=1
    elif [ "$(cat "$tmp/j$k.res")" = "$got" ]; then echo "BAD  mutant ${mnames[k]} SURVIVED"; bad=1
    else echo "ok   mutant ${mnames[k]} killed"; fi
  done
  echo "mutants: $n"
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
# checkout that stages only `notes` must be refused (the row is bound to an earlier parent)
up2="$tmp/up2"; git init -q "$up2"; for i in A B; do git -C "$up2" commit -q --allow-empty -m "$i"; done
pA=$(git -C "$up2" rev-parse HEAD~1); pB=$(git -C "$up2" rev-parse HEAD)
ps="$tmp/ps"; git init -q "$ps"; git -C "$ps" submodule add -q "file://$up2" sub >/dev/null 2>&1; echo 0 >"$ps/notes"; git -C "$ps" add notes
git -C "$ps" commit -q -m base; inst "$ps"
git -C "$ps/sub" checkout -q "$pA"; wf sub "$pB" "$pA" ops "$d10" CON-046 "$(git -C "$ps" rev-parse HEAD)" >"$ps/.submodule_pin_waivers"; git -C "$ps" add .submodule_pin_waivers
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
