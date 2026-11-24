#!/usr/bin/env bash
# cm_upstream_parity_mutation_test.sh -- §1.1 paired mutation test for CM-UPSTREAM-PARITY-AFTER-MERGE (§11.4.299):
# scripts/sync/verify_upstream_parity.sh and push_all_upstreams.sh. Builds throwaway local bare repositories as the
# "upstreams" of a throwaway work repository (the tool's own logic is under test here; the live proof of a real merge is
# the per-upstream `git ls-remote` read-back the anchor demands, not this test). Every case states its expected exit code;
# a verifier that returned 0 on a behind/diverged/unreachable/empty state would be the PASS-bluff the anchor forbids.
# Cases M1..M15. Exit 0 all as expected · 1 a case differed · 2 environment fault.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); V="$HERE/../sync/verify_upstream_parity.sh"; P="$HERE/../sync/push_all_upstreams.sh"
[ -x "$V" ] && [ -x "$P" ] || { echo "tools missing" >&2; exit 2; }
T=$(mktemp -d) || exit 2; trap 'rm -rf "${T:?}"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
FAIL=0; PASS=0
expect() { local name="$1" want="$2" got="$3"; if [ "$want" = "$got" ]; then PASS=$((PASS+1)); echo "PASS $name (rc=$got)"; else FAIL=$((FAIL+1)); echo "FAIL $name want=$want got=$got"; fi; }
mk() { # mk <dir>: work repo with 2 commits on main, 3 bare upstreams at c2 as remotes a,b,c
  local d="${1:?}"; rm -rf "${d:?}" "${d:?}.a.git" "${d:?}.b.git" "${d:?}.c.git"; mkdir -p "$d"; git -C "$d" init -q -b main; echo 1 > "$d/f"; git -C "$d" add f; git -C "$d" commit -qm c1; C1=$(git -C "$d" rev-parse HEAD)
  echo 2 >> "$d/f"; git -C "$d" commit -qam c2; C2=$(git -C "$d" rev-parse HEAD)
  for r in a b c; do git init -q --bare -b main "$d.$r.git"; git -C "$d" remote add $r "$d.$r.git"; git -C "$d" push -q $r main; done; }
W="$T/w"
mk "$W"; bash "$V" --repo "$W" --quiet >/dev/null; expect "M1 all upstreams current -> 0" 0 $?
git -C "$W" push -q b "$C1:refs/heads/main" -f 2>/dev/null; bash "$V" --repo "$W" --quiet >/dev/null; expect "M2 one upstream behind -> 1" 1 $?
git -C "$W" push -q b main -f 2>/dev/null; git -C "$W" remote set-url c "$T/nonexistent.git"; bash "$V" --repo "$W" --quiet >/dev/null; expect "M3 one unreachable, rest current -> 2" 2 $?
git -C "$W" push -q b "$C1:refs/heads/main" -f 2>/dev/null; bash "$V" --repo "$W" --quiet >/dev/null; expect "M4 behind + unreachable -> 1 (1 outranks 2)" 1 $?
mk "$W"; git -C "$W" checkout -q -b side "$C1"; echo x > "$W/g"; git -C "$W" add g; git -C "$W" commit -qm side; git -C "$W" push -q a side:main -f 2>/dev/null; git -C "$W" checkout -q main
bash "$V" --repo "$W" --quiet >/dev/null; expect "M5 diverged upstream -> 1" 1 $?
mk "$W"; git -C "$W" remote remove c; mkdir -p "$W/upstreams"; printf '#!/bin/bash\nexport UPSTREAMABLE_REPOSITORY="%s"\n' "$W.c.git" > "$W/upstreams/c.sh"
git -C "$W" push -q "$W.c.git" "$C1:refs/heads/main" -f 2>/dev/null; bash "$V" --repo "$W" --quiet >/dev/null; expect "M6 recipe-only upstream behind -> 1" 1 $?
mv "$W/upstreams/c.sh" "$W/upstreams/c.sh.disabled"; bash "$V" --repo "$W" --quiet >/dev/null; expect "M7 disabled recipe not enumerated -> 0" 0 $?
mk "$W"; git init -q --bare -b main "$T/extra.git"; git -C "$W" remote set-url --add --push a "$W.a.git"; git -C "$W" remote set-url --add --push a "$T/extra.git"
bash "$V" --repo "$W" --quiet >/dev/null; expect "M8 second push URL of one remote (empty) -> 1 (get-url --all trap)" 1 $?
mkdir "$T/e"; git -C "$T/e" init -q -b main; echo 1 > "$T/e/f"; git -C "$T/e" add f; git -C "$T/e" commit -qm c; bash "$V" --repo "$T/e" --quiet >/dev/null; expect "M9 no upstream declared -> 2" 2 $?
mk "$W"; git -C "$W" push -q b "$C1:refs/heads/main" -f 2>/dev/null
printf 'w\t%s\tmirror fed by snapshot, recorded decision\n' "$W.b.git" > "$T/ex.tsv"; bash "$V" --repo "$W" --exempt "$T/ex.tsv" --quiet >/dev/null; expect "M10 exempt with reason -> 0" 0 $?
printf 'w\t%s\t\n' "$W.b.git" > "$T/ex.tsv"; bash "$V" --repo "$W" --exempt "$T/ex.tsv" --quiet >/dev/null; expect "M11 exemption without reason -> 2" 2 $?
mk "$W"; echo 3 >> "$W/f"; git -C "$W" commit -qam c3; C3=$(git -C "$W" rev-parse HEAD); bash "$V" --repo "$W" --sha "$C3" --quiet >/dev/null; expect "M12 merged sha newer than every upstream -> 1" 1 $?
mk "$W"; git -C "$W" push -q b "$C1:refs/heads/main" -f 2>/dev/null
bash "$P" --repo "$W" --sha "$C2" >/dev/null; expect "M13a dry-run reports the owed push -> 1" 1 $?
[ "$(git -C "$W.b.git" rev-parse main)" = "$C1" ] && expect "M13b dry-run changed nothing" 0 0 || expect "M13b dry-run changed nothing" 0 1
bash "$P" --repo "$W" --sha "$C2" --apply >/dev/null; expect "M13c --apply fast-forwards, read-back -> 0" 0 $?
[ "$(git -C "$W.b.git" rev-parse main)" = "$C2" ] && expect "M13d upstream b now at merged sha" 0 0 || expect "M13d upstream b now at merged sha" 0 1
git -C "$W" checkout -q -b side "$C1"; echo y > "$W/h"; git -C "$W" add h; git -C "$W" commit -qm side2; SIDE=$(git -C "$W" rev-parse HEAD); git -C "$W" push -q a "$SIDE:refs/heads/main" -f 2>/dev/null; git -C "$W" checkout -q main
bash "$P" --repo "$W" --sha "$C2" --apply >/dev/null 2>&1; rc=$?; expect "M14a diverged upstream -> not 0 (no force)" 1 $(( rc == 0 ? 0 : 1 ))
[ "$(git -C "$W.a.git" rev-parse main)" = "$SIDE" ] && expect "M14b diverged upstream untouched" 0 0 || expect "M14b diverged upstream untouched" 0 1
if grep -nE -- 'push .*(--force|force-with-lease|--no-verify|\+refs|:\+)' "$P" | grep -vE '^[0-9]+:#' >/dev/null; then expect "M15 no force construct in push command" 0 1; else expect "M15 no force construct in push command" 0 0; fi
# ---- verify_constitution_latest.sh (the "constitution is latest + nested submodules current" check) ----
L="$HERE/../sync/verify_constitution_latest.sh"; export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
nb() { git init -q -b main "$1"; echo "$2" > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm i; }
nb "$T/nest" n; git init -q --bare -b main "$T/nest.git"; git -C "$T/nest" push -q "$T/nest.git" main
nb "$T/cu" c; git -C "$T/cu" submodule add -q "$T/nest.git" submodules/nest; git -C "$T/cu" commit -qm sub; git init -q --bare -b main "$T/cu.git"; git -C "$T/cu" push -q "$T/cu.git" main
nb "$T/proj" p; git -C "$T/proj" submodule add -q "$T/cu.git" submodules/constitution; git -C "$T/proj" submodule update -q --init --recursive; git -C "$T/proj" commit -qm pin
bash "$L" --root "$T/proj" --quiet >/dev/null; expect "L1 constitution latest + nested current -> 0" 0 $?
echo more >> "$T/cu/f"; git -C "$T/cu" commit -qam up; git -C "$T/cu" push -q "$T/cu.git" main; git -C "$T/proj/submodules/constitution" fetch -q origin
bash "$L" --root "$T/proj" --quiet >/dev/null; expect "L2 constitution behind its upstream -> 1" 1 $?
git -C "$T/proj/submodules/constitution" merge -q --ff-only origin/main; git -C "$T/proj" add submodules/constitution; git -C "$T/proj" commit -qm bump
bash "$L" --root "$T/proj" --quiet >/dev/null; expect "L3 after fast-forward + pin -> 0" 0 $?
git -C "$T/proj/submodules/constitution" submodule deinit -q -f submodules/nest; bash "$L" --root "$T/proj" --quiet >/dev/null; expect "L4 nested submodule uninitialised -> 1" 1 $?
git -C "$T/proj/submodules/constitution" submodule update -q --init; git -C "$T/proj/submodules/constitution" remote set-url origin "$T/gone.git"; bash "$L" --root "$T/proj" --quiet >/dev/null; expect "L5 constitution upstream unreachable -> 2" 2 $?
echo "RESULT: $PASS pass, $FAIL fail"; [ "$FAIL" = 0 ] && exit 0 || exit 1
