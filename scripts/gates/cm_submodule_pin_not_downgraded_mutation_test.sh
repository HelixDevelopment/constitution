#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SUBMODULE-PIN-NOT-DOWNGRADED.
# Part 1: fixtures vs the real gate. Part 2: mutants of a scratch gate copy; each MUST change a verdict (be killed).
# Fixtures: throwaway repos (real repo never touched). Exit 0 proof holds · 1 misclassified/survivor · 2 env error.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; gate="$here/cm_submodule_pin_not_downgraded.sh"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT; export HOME="$tmp/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
bad=0
# fixture <name> -> repo at $tmp/<name>/super with submodule dir "sub": commits A (parent), B, side-branch S (diverged from A)
seq=0
mk() { # sets globals R A B S (no subshell)
  local d; d="$(mktemp -d "$tmp/fx.XXXXXX")"; mkdir -p "$d/super/sub"; git -C "$d/super/sub" init -q
  git -C "$d/super/sub" commit -q --allow-empty -m A; A=$(git -C "$d/super/sub" rev-parse HEAD)
  git -C "$d/super/sub" commit -q --allow-empty -m B; B=$(git -C "$d/super/sub" rev-parse HEAD)
  git -C "$d/super/sub" checkout -q -b side "$A"; git -C "$d/super/sub" commit -q --allow-empty -m S; S=$(git -C "$d/super/sub" rev-parse HEAD)
  git -C "$d/super" init -q; git -C "$d/super" update-index --add --cacheinfo 160000,"$B",sub
  git -C "$d/super" commit -q -m base; R="$d/super"
}
stage() { git -C "$1" update-index --cacheinfo 160000,"$2",sub; }
run() { bash "${3:-$gate}" --root "$1" ${2:+--waivers "$2"} >"$tmp/out" 2>&1; echo $?; }
expect() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1 (exit $3)"; else echo "BAD  $1: want $2 got $3"; bad=1; fi
}
classify() { # gate-path -> prints verdicts line for killing comparison
  local g="$1" out=""
  mk;r=$R; stage "$r" "$A"; out+="DOWN=$(run "$r" "" "$g") "
  mk;r=$R; out+="NOCHANGE=$(run "$r" "" "$g") "
  mk;r=$R; stage "$r" "$S"; out+="DIVERGED=$(run "$r" "" "$g") "
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q -m down; stage "$r" "$B"; out+="FORWARD=$(run "$r" "" "$g") "
  mk;r=$R; stage "$r" "$A"; printf 'sub\t%s\tme\t2999-01-01\tCON-046\n' "$A" >"$tmp/w_ok"; out+="WAIVED=$(run "$r" "$tmp/w_ok" "$g") "
  mk;r=$R; stage "$r" "$A"; printf 'sub\t%s\tme\t2000-01-01\tCON-046\n' "$A" >"$tmp/w_old"; out+="EXPIRED=$(run "$r" "$tmp/w_old" "$g") "
  mk;r=$R; stage "$r" "$A"; printf 'sub\t%s\tme\t2999-01-01\t\n' "$A" >"$tmp/w_inc"; out+="NOTRACK=$(run "$r" "$tmp/w_inc" "$g") "
  mk;r=$R; stage "$r" "$A"; rm -rf "$r/sub/.git"; out+="BLIND=$(run "$r" "" "$g") "
  mk;r=$R; echo x >"$r/other"; git -C "$r" add other; out+="UNRELATED=$(run "$r" "" "$g") "
  mk;r=$R; stage "$r" "$A"; printf 'sub\t%s\tme\t2999-01-01\tCON-046\n' "$S" >"$tmp/w_wrong"; out+="WRONGSHA=$(run "$r" "$tmp/w_wrong" "$g") "
  echo "$out"
}
want="DOWN=1 NOCHANGE=0 DIVERGED=0 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1 "
got="$(classify "$gate")"; echo "real gate: $got"
[ "$got" = "$want" ] || { echo "BAD  classification: want [$want] got [$got]"; bad=1; }
n=0
mutant() { # name sed-expr
  local m="$tmp/m$((++n)).sh"; sed "$2" "$gate" >"$m"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1 did not change the gate"; bad=1; return; fi
  local g; g="$(classify "$m")"
  if [ "$g" = "$got" ]; then echo "BAD  mutant $1 SURVIVED"; bad=1; else echo "ok   mutant $1 killed"; fi
}
mutant no-ancestor-check 's/if git -C "\$sub" merge-base --is-ancestor "\$nsha" "\$osha" 2>\/dev\/null; then/if false; then/'
mutant always-ancestor 's/if git -C "\$sub" merge-base --is-ancestor "\$nsha" "\$osha" 2>\/dev\/null; then/if true; then/'
mutant blind-is-pass 's/blind=1; continue/continue/'
mutant waiver-ignores-expiry 's/ \&\& \$4>=t//'
mutant waiver-ignores-tracked-item 's/ \&\& \$5!=""//'
mutant waiver-ignores-sha 's/ \&\& \$2==n//'
mutant fail-is-pass 's/^\[ "\$fail" = 1 \] \&\& exit 1/[ "$fail" = 1 ] \&\& exit 0/'
exit "$bad"
