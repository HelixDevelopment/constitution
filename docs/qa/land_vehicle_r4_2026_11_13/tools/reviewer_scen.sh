#!/usr/bin/env bash
# scen.sh <R> [scenario...]: reviewer round-3 adversarial scenarios for land_vehicle.sh.
# LIVE class: real git 2.53, real local bare repos as remotes, real server-side hooks.
# Fixture class (stated per scenario): git PATH shims, fake mint/engine scripts, fake gpg.
# No network: every URL is a local path, except S_A19 which uses 127.0.0.1:9 (refused at once).
# HOME is never reassigned; git config isolation via GIT_CONFIG_GLOBAL/GIT_CONFIG_NOSYSTEM.
set -uo pipefail
R=${1:?}; shift
LANDER=$R/repo/scripts/release/land_vehicle.sh
. "$R/repo/scripts/lib/safe_rm.sh"
WI=$R/../wi
REALGIT=$(command -v git)
REMOTES="gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w origin"
T=$(mktemp -d "$R/tmp/scen.XXXXXX"); : "${T:?}"
cleanup() { [ -n "${T:-}" ] && [ -d "$T" ] && safe_rm_rf "$T"; }
trap cleanup EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Rev Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "rev@test.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
say() { printf '%s\n' "$*"; }
g() { git -C "$1" "${@:2}"; }
rmain() { git --git-dir="$1/remotes/$2.git" rev-parse main 2>/dev/null || echo none; }
run() { local out=$1; shift; "$@" > "$out" 2>&1; RC=$?; }

# shim recording push argv (fixture class), optional per-scenario pre-push action file
mkdir -p "$T/shim"; PUSHLOG=$T/push.log; : > "$PUSHLOG"
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
i=1; n=\$#; args=("\$@")
while [ \$i -le \$n ]; do
  a=\${args[\$((i - 1))]}
  case "\$a" in -c|-C|--git-dir|--work-tree|--namespace|--exec-path) i=\$((i + 2)) ;; -*) i=\$((i + 1)) ;; *) break ;; esac
done
if [ \$i -le \$n ] && [ "\${args[\$((i - 1))]}" = push ]; then
  ( IFS=\$'\x1f'; printf '%s\n' "\${args[*]:\$i}" ) >> "$PUSHLOG"
  if [ -x "$T/prepush_action" ]; then "$T/prepush_action" "\${args[@]:\$i}"; fi
fi
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/shim/git"
lv() { PATH="$T/shim:$PATH" "$LANDER" "$@"; }

base_fixture() { # base_fixture <name> [extra-file-in-main src dst]
  local F=$T/$1 r
  mkdir -p "$F/remotes" "$F/work"
  git init -q "$F/seed"
  printf 'base\n' > "$F/seed/a.txt"; g "$F/seed" add a.txt
  if [ -n "${2:-}" ]; then mkdir -p "$F/seed/$(dirname "$3")"; cp "$2" "$F/seed/$3"; g "$F/seed" add "$3"; fi
  g "$F/seed" commit -q -m "base" -m "Roadmap-Item: CON-001"
  : > "$F/remotes.txt"
  for r in $REMOTES; do
    git init -q --bare "$F/remotes/$r.git"
    g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main
    printf '%s %s\n' "$r" "$F/remotes/$r.git" >> "$F/remotes.txt"
  done
  g "$F/seed" checkout -q -b vehicle
}
vc() { local F=$1; printf '%s\n' "$2" > "$F/seed/$2"; g "$F/seed" add "$2"; printf '%b' "$3" > "$F/msg"; g "$F/seed" commit -q --cleanup=verbatim -F "$F/msg"; }
mkbundle() { local F=$1; shift; g "$F/seed" bundle create -q "$F/vehicle.bundle" vehicle "$@" ^main 2>/dev/null; g "$F/seed" rev-parse vehicle > "$F/head"; sha256sum "$F/vehicle.bundle" | awk '{print $1}' > "$F/sha"; }
prep() { local F=$1; shift; lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"; }
pub() { local F=$1; shift; lv publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"; }
std() { base_fixture "$1"; local F=$T/$1; vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-landing\n'; mkbundle "$F"; }
allat() { local F=$1 want=$2 r n=0; for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$want" ] && n=$((n+1)); done; echo "$n"; }

# ------------------------------------------------------------------ scenarios
S_A1() { # remote moves between preflight and push (shim advances gitverse just before its push)
  say "== S_A1 remote moved between preflight and push (LIVE git; shim = fixture trigger)"
  std a1; local F=$T/a1 C
  run "$F/prep.out" prep "$F" --item-id CON-901; say "prepare rc=$RC"
  C=$F/work/constitution
  git clone -q "$F/remotes/gitverse.git" "$F/mover"; printf 'mv\n' > "$F/mover/mv.txt"; g "$F/mover" add mv.txt
  g "$F/mover" commit -q -m "concurrent push elsewhere" -m "Roadmap-Item: CON-002"
  local moved; moved=$(g "$F/mover" rev-parse HEAD)
  cat > "$T/prepush_action" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = gitverse ] && [ ! -e "$T/a1.done" ] && { : > "$T/a1.done"; "$REALGIT" -C "$F/mover" push -q "$F/remotes/gitverse.git" HEAD:refs/heads/main; }; done
exit 0
EOF
  chmod +x "$T/prepush_action"; : > "$PUSHLOG"
  run "$F/pub.out" pub "$F"; local rc1=$RC
  rm -f -- "$T/prepush_action"
  local lm; lm=$(g "$C" rev-parse main)
  say "publish rc=$rc1; remotes at local main: $(allat "$F" "$lm")/9; gitverse main is the concurrent commit: $([ "$(rmain "$F" gitverse)" = "$moved" ] && echo yes || echo no)"
  grep '^| gitverse' "$F/ev/publish.md"; grep -c '| pushed |' "$F/ev/publish.md" | sed 's/^/pushed rows: /'
  tail -2 "$F/pub.out"
  say "push argv lines: $(wc -l < "$PUSHLOG"); non-plain: $(grep -vcE $'^-q\x1f--no-verify\x1f[a-z_0-9]+\x1fmain:refs/heads/main$' "$PUSHLOG")"
  # re-run without integrating: must refuse at preflight, push nothing
  run "$F/pub2.out" pub "$F"; say "re-publish without integrating: rc=$RC; $(grep -c 'not-pushed-preflight\|refused-non-ff' "$F/ev/publish.md") preflight rows; $(tail -1 "$F/pub2.out")"
  # resume: integrate the moved remote by merge (with trailer), publish again
  g "$C" fetch -q gitverse main 2>/dev/null; g "$C" merge -q --no-ff -m "merge concurrent gitverse main" -m "Roadmap-Item: CON-901" FETCH_HEAD
  run "$F/pub3.out" pub "$F"; lm=$(g "$C" rev-parse main)
  say "resume publish rc=$RC; remotes at main: $(allat "$F" "$lm")/9; concurrent commit kept: $(g "$C" merge-base --is-ancestor "$moved" "$lm" && echo yes || echo no)"
}

S_A3() { # mint changes the tracker but prints a PRE-EXISTING id
  say "== S_A3 mint prints a pre-existing id while changing the tracker (fixture mint)"
  printf 'CON-100 old item\n' > "$T/oldtracker"
  base_fixture a3 "$T/oldtracker" docs/tracker.fake; local F=$T/a3
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
  cat > "$F/mint.sh" <<'EOF'
#!/usr/bin/env bash
printf 'CON-777 minted\n' >> docs/tracker.fake
echo CON-100
EOF
  chmod +x "$F/mint.sh"
  run "$F/prep.out" prep "$F" --mint-cmd "$F/mint.sh"; say "prepare rc=$RC"; grep 'step 3' "$F/prep.out"
  [ "$RC" = 0 ] && say "trailer on vehicle commit: $(g "$F/work/constitution" log -1 --format='%(trailers:key=Roadmap-Item,valueonly)' "$(g "$F/work/constitution" log --format='%H %s' main | awk '$2=="feat:" {print $1; exit}')")"
}

S_A3b() { # REAL engine binary (scratchpad build of 2026-11-10) on a copy of a real DB
  say "== S_A3b real workable-items engine on a DB copy (LIVE engine binary; DB copy of 2026-11-11)"
  [ -x "$WI" ] || { say "SKIP engine absent"; return; }
  base_fixture a3b "$R/../wi.db" docs/wi.db; local F=$T/a3b
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
  local addargs="add Task low --db docs/wi.db --title 'lander review probe item' --description 'probe of the lander mint path against the real engine binary and database'"
  # (i) documented usage: the engine command itself
  run "$F/p1.out" prep "$F" --mint-cmd "$WI $addargs --prefix CON"; say "(i) raw engine add as --mint-cmd: rc=$RC :: $(grep ERROR "$F/p1.out")"
  safe_rm_rf "${F:?}/work/constitution"
  # (ii) wrapper that extracts the created id
  run "$F/p2.out" prep "$F" --mint-cmd "$WI $addargs --prefix CON | grep -oE 'CON-[0-9]+' | tail -n 1"; say "(ii) wrapper extracting the created id: rc=$RC :: $(grep 'step 3:' "$F/p2.out")"
  safe_rm_rf "${F:?}/work/constitution"
  # (iii) wrapper that runs a real add but prints an OLD id (a parsing slip)
  run "$F/p3.out" prep "$F" --mint-cmd "$WI $addargs --prefix CON >/dev/null; echo CON-001"; say "(iii) real add, prints old id CON-001: rc=$RC :: $(grep 'step 3:' "$F/p3.out")$(grep ERROR "$F/p3.out")"
}

S_A5() { # dangling symlink at the clone path
  say "== S_A5 dangling symlink at <workdir>/constitution (LIVE git)"
  std a5; local F=$T/a5
  ln -s "$T/a5_elsewhere/constitution" "$F/work/constitution"
  run "$F/prep.out" prep "$F" --item-id CON-905; say "prepare rc=$RC :: $(tail -1 "$F/prep.out")"
  say "clone created outside the workdir (symlink target): $([ -d "$T/a5_elsewhere/constitution/.git" ] && echo YES || echo no); target parent created: $([ -d "$T/a5_elsewhere" ] && echo yes || echo no)"
  ls -la "$F/work" | sed 's/^/    /'
}

S_A6() { # credential in a malformed remotes-file line
  say "== S_A6 malformed remotes line carrying a credential URL (no network: dies in load_remotes)"
  std a6; local F=$T/a6
  printf 'https://user:SECRETTOKEN123@example.invalid/x.git\n' > "$F/bad_remotes.txt"
  run "$F/out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/bad_remotes.txt" --item-id CON-906
  say "rc=$RC leak_in_output=$(grep -c SECRETTOKEN123 "$F/out")"; sed 's/^/    | /' "$F/out"
}

S_A7() { # a daemon spawned below a git child (fake gpg agent) inherits the lock fd
  say "== S_A7 commit signing whose gpg spawns a long-lived child (fake gpg = fixture)"
  std a7; local F=$T/a7
  cat > "$T/fakegpg" <<EOF
#!/usr/bin/env bash
cat > /dev/null
( exec sleep 20 ) </dev/null >/dev/null 2>&1 &
echo \$! >> "$T/a7_bg.pids"
printf '\n[GNUPG:] SIG_CREATED D 1 8 00 1 X\n' >&2
printf -- '-----BEGIN PGP SIGNATURE-----\n\nZmFrZQ==\n-----END PGP SIGNATURE-----\n'
EOF
  chmod +x "$T/fakegpg"
  git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign true
  git config --file "$GIT_CONFIG_GLOBAL" gpg.program "$T/fakegpg"
  git config --file "$GIT_CONFIG_GLOBAL" user.signingkey X
  printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake; echo CON-777\n' > "$F/mint7.sh"; chmod +x "$F/mint7.sh"
  run "$F/prep.out" prep "$F" --mint-cmd "$F/mint7.sh"; say "prepare rc=$RC :: $(grep -E 'step 5|ERROR' "$F/prep.out" | head -2)"
  git config --file "$GIT_CONFIG_GLOBAL" --unset commit.gpgsign
  local held=0 p alive=0 recorded=0
  [ -f "$T/a7_bg.pids" ] && recorded=$(wc -l < "$T/a7_bg.pids")
  say "fake gpg invocations recorded: $recorded; signed commits on landed main: $(g "$F/work/constitution" log --format=%G? main | grep -vc N)"
  for p in $(cat "$T/a7_bg.pids" 2>/dev/null); do
    [ -d /proc/"$p" ] && alive=$((alive+1))
    ls -l /proc/"$p"/fd > "$T/a7_fd_$p.txt" 2>/dev/null; grep -c 'land_vehicle.lock' "$T/a7_fd_$p.txt" > "$T/a7_c" ; [ "$(cat "$T/a7_c")" -ge 1 ] && held=$((held+1))
    say "  pid $p fds: $(awk 'NR>1 {print $9 $10 $11}' "$T/a7_fd_$p.txt" | tr '\n' ' ')"
  done
  say "alive children: $alive"
  say "background children of gpg holding .land_vehicle.lock after prepare exited: $held"
  run "$F/pub.out" pub "$F"; say "publish right after prepare: rc=$RC :: $(grep -E 'ERROR' "$F/pub.out")"
  for p in $(cat "$T/a7_bg.pids" 2>/dev/null); do [ "$(tr '\0' ' ' < /proc/"$p"/cmdline 2>/dev/null)" = "sleep 20 " ] && kill "$p" 2>/dev/null; done
  sleep 0.5; run "$F/pub2.out" pub "$F"; say "publish after the children ended: rc=$RC"
}

S_A8() { # ambient push.followTags publishes an extra ref
  say "== S_A8 ambient push.followTags=true + an annotated tag in the clone (LIVE git)"
  std a8; local F=$T/a8 C
  run "$F/prep.out" prep "$F" --item-id CON-908; C=$F/work/constitution
  g "$C" tag -a -m "derived step tag" v-derived main
  git config --file "$GIT_CONFIG_GLOBAL" push.followTags true; : > "$PUSHLOG"
  run "$F/pub.out" pub "$F"; git config --file "$GIT_CONFIG_GLOBAL" --unset push.followTags
  local n=0 r; for r in $REMOTES; do git --git-dir="$F/remotes/$r.git" rev-parse -q --verify refs/tags/v-derived >/dev/null && n=$((n+1)); done
  say "publish rc=$RC; remotes that received tag v-derived: $n/9; shim argv non-plain lines: $(grep -vcE $'^-q\x1f--no-verify\x1f[a-z_0-9]+\x1fmain:refs/heads/main$' "$PUSHLOG")"
}

S_A9() { # ambient status.showUntrackedFiles=no hides an uncommitted derived file
  say "== S_A9 ambient status.showUntrackedFiles=no + an untracked derived file (LIVE git)"
  std a9; local F=$T/a9 C
  run "$F/prep.out" prep "$F" --item-id CON-909; C=$F/work/constitution
  printf 'derived\n' > "$C/derived_new.md"
  git config --file "$GIT_CONFIG_GLOBAL" status.showUntrackedFiles no
  run "$F/pub.out" pub "$F"; git config --file "$GIT_CONFIG_GLOBAL" --unset status.showUntrackedFiles
  say "publish with an untracked file in the clone: rc=$RC (rc 0 = published without it)"
}

S_A10() { # option-like --workdir values reaching cd
  say "== S_A10 option-like --workdir (cd semantics)"
  say "isolated: WORKDIR=-P resolves to: $(bash -c 'W=-P; W=$(cd "$W" && pwd); [ "$W" = "$HOME" ] && echo "\$HOME (same as the caller HOME)" || echo "$W"')"
  run "$T/a10.out" lv verify --workdir -P --remotes-file "$T/nonexistent"; say "lander accepts -P as a value (dies later at remotes file): rc=$RC :: $(cat "$T/a10.out")"
  mkdir -p "$T/a10old"; std a10; local F=$T/a10
  run "$T/a10b.out" env OLDPWD="$T/a10old" CDPATH= "$LANDER" verify --workdir - --remotes-file "$F/remotes.txt"; say "--workdir - with OLDPWD set: rc=$RC :: $(head -2 "$T/a10b.out" | tr '\n' ' ')"
  say "lock file created in OLDPWD dir: $(ls -A "$T/a10old")"
}

S_A11() { # part of the vehicle is already on one remote main
  say "== S_A11a first vehicle commit (real id) already on github main (LIVE git)"
  base_fixture a11; local F=$T/a11 C
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-111\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-x\n'; mkbundle "$F"
  g "$F/seed" push -q "$F/remotes/github.git" vehicle~1:refs/heads/main
  run "$F/prep.out" prep "$F" --item-id CON-911; C=$F/work/constitution; say "prepare rc=$RC :: $(grep -E 'step 2' "$F/prep.out")"
  say "tree_equality rows: $(($(wc -l < "$F/ev/tree_equality.tsv") - 1)) (only the unpushed commit is re-committed)"
  run "$F/pub.out" pub "$F"; say "publish rc=$RC; at main $(allat "$F" "$(g "$C" rev-parse main)")/9"
  say "== S_A11b first vehicle commit with a PLACEHOLDER trailer already on github main"
  base_fixture a11b; F=$T/a11b
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-PENDING-early\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-x\n'; mkbundle "$F"
  g "$F/seed" push -q "$F/remotes/github.git" vehicle~1:refs/heads/main
  run "$F/prep.out" prep "$F" --item-id CON-911; C=$F/work/constitution; say "prepare rc=$RC :: $(grep -oE 'ERROR.*' "$F/prep.out")"
  run "$F/pub.out" pub "$F"; say "publish rc=$RC; at main $(allat "$F" "$(g "$C" rev-parse main)")/9 :: $(grep -oE 'ERROR.*' "$F/pub.out")"
  local r n=0 k; for r in $REMOTES; do git --git-dir="$F/remotes/$r.git" log --format=%B main > "$F/log_$r.txt"; k=$(grep -c 'CON-PENDING-early' "$F/log_$r.txt"); [ "$k" -ge 1 ] && n=$((n+1)); done; say "control needle: grep -c of the string 'feat: one' over the same files: $(cat "$F"/log_*.txt | grep -c 'feat: one') (expect 9)"
  say "remotes whose main now carries the placeholder trailer CON-PENDING-early: $n/9 (1 before publish)"
}

S_A23() { # ambient trailer.<token>.cmd rewrites the appended value
  say "== S_A23 ambient trailer.ri.cmd in global config, vehicle commit without any trailer (LIVE git)"
  base_fixture a23; local F=$T/a23 C h
  vc "$F" v1.txt 'feat: none\n\nno trailer here\n'; mkbundle "$F"
  git config --file "$GIT_CONFIG_GLOBAL" trailer.ri.key Roadmap-Item
  git config --file "$GIT_CONFIG_GLOBAL" trailer.ri.cmd 'echo CON-999'
  run "$F/prep.out" prep "$F" --item-id CON-923
  git config --file "$GIT_CONFIG_GLOBAL" --remove-section trailer.ri
  C=$F/work/constitution
  if [ "$RC" = 0 ]; then h=$(g "$C" log --format='%H %s' main | awk '$2=="feat:" {print $1; exit}'); say "prepare rc=0; landed trailer values: [$(g "$C" log -1 --format='%(trailers:key=Roadmap-Item,valueonly)' "$h" | tr '\n' ',')] (asked for CON-923)"; else say "prepare rc=$RC :: $(grep -oE 'ERROR.*' "$F/prep.out")"; fi
}

S_A12() { # trailer variants, one commit each, --item-id path
  say "== S_A12 trailer variants (LIVE git interpret-trailers)"
  local k=0 m F C h v
  while IFS= read -r m; do
    k=$((k+1)); base_fixture "a12_$k"; F=$T/a12_$k
    vc "$F" "v$k" "$m"; mkbundle "$F"
    run "$F/out" prep "$F" --item-id CON-912; C=$F/work/constitution
    if [ "$RC" = 0 ]; then
      h=$(g "$C" log --format='%H %s' main | awk -v s="t$k" '$2==s {print $1; exit}')
      v=$(g "$C" log -1 --format='%(trailers:key=Roadmap-Item,valueonly)' "$h" | tr '\n' ',')
      say "  [$k] $(printf '%q' "$m") -> rc=0 trailers=[$v]"
    else say "  [$k] $(printf '%q' "$m") -> rc=$RC $(grep -o 'ERROR.*' "$F/out" | cut -c1-110)"; fi
  done <<'EOF'
t1\n\nRoadmap-Item:CON-050\n
t2\n\nRoadmap-Item:\tCON-050\n
t3\n\nRoadmap-Item: CON-050   \n
t4\n\nROADMAP-ITEM: CON-PENDING-x\n
t5\n\nRoadmap-Item: <TO-BE-MINTED>\n
t6\n\nRoadmap-Item: con-050\n
t7\n\nSigned-off-by: A <a@b.c>\nRoadmap-Item: CON-050\nReviewed-by: B <b@c.d>\n
t8\n\nRoadmap-Item: CON-050\nRoadmap-Item: <TO-BE-MINTED>\nRoadmap-Item: CON-123\n
t9\n\nRoadmap-Item: CON-PENDING-\n
t10\n\nRoadmap-Item:
t11\n\nRoadmap-Item: CON-050 # placeholder\n
t12\n\nCloses: #12\nRoadmap-Item: CON-050\n
EOF
}

S_A13() { # verify exit-code matrix
  say "== S_A13 verify exit codes (LIVE git)"
  std a13; local F=$T/a13 C
  run "$F/v0.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt"; say "no clone: rc=$RC :: $(grep -o 'ERROR.*' "$F/v0.out")"
  run "$F/prep.out" prep "$F" --item-id CON-913; C=$F/work/constitution
  run "$F/v1.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; say "after prepare, before publish (all remotes behind): rc=$RC"
  run "$F/pub.out" pub "$F"; run "$F/v2.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; say "after publish: rc=$RC :: $(tail -1 "$F/v2.out")"
  mv "$C/.git/land_vehicle.state" "$C/.git/st.bak"; run "$F/v3.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt"; say "state removed: rc=$RC :: $(grep -o 'ERROR.*' "$F/v3.out")"; mv "$C/.git/st.bak" "$C/.git/land_vehicle.state"
  sed "s|^m3w .*|m3w $F/remotes/origin.git|" "$F/remotes.txt" > "$F/r_wrong.txt"
  run "$F/v4.out" lv verify --workdir "$F/work" --remotes-file "$F/r_wrong.txt"; say "wrong URL for m3w: rc=$RC :: $(grep -o 'ERROR.*' "$F/v4.out")"
}

S_A14() { # server accepts the push, then a post-receive hook moves the ref back
  say "== S_A14 server post-receive rewinds main after accepting (LIVE server-side hook)"
  std a14; local F=$T/a14
  run "$F/prep.out" prep "$F" --item-id CON-914
  local base; base=$(g "$F/seed" rev-parse main)
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base" > "$F/remotes/m3w.git/hooks/post-receive"; chmod +x "$F/remotes/m3w.git/hooks/post-receive"
  run "$F/pub.out" pub "$F"; say "publish rc=$RC :: $(grep '^| m3w' "$F/ev/publish.md") :: $(tail -1 "$F/pub.out")"
}

S_A15() { # odd remote names
  say "== S_A15 odd remote names (LIVE git)"
  local nm F
  for nm in 'a/b' 'a.b-1' '-x'; do
    base_fixture "a15_$(printf '%s' "$nm" | tr -c 'a-z0-9' _)"; F=$T/a15_$(printf '%s' "$nm" | tr -c 'a-z0-9' _)
    vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
    printf '%s %s\n' "$nm" "$F/remotes/origin.git" > "$F/r1.txt"
    run "$F/out" env LANDER_REMOTES="$nm" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/r1.txt" --evidence-dir "$F/ev" --item-id CON-915
    say "  name '$nm': prepare rc=$RC :: $(tail -1 "$F/out" | cut -c1-120)"
    if [ "$RC" = 0 ]; then run "$F/pout" env LANDER_REMOTES="$nm" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/r1.txt" --evidence-dir "$F/ev"; say "    publish rc=$RC"; fi
  done
}

S_A19() { # https URL with a credential, refused at 127.0.0.1:9
  say "== S_A19 credential URL on a failing fetch (local port 9, connection refused)"
  std a19; local F=$T/a19
  sed -i "s|^origin .*|origin https://user:SECRETTOKEN456@127.0.0.1:9/x.git|" "$F/remotes.txt"
  run "$F/out" prep "$F" --item-id CON-919
  say "rc=$RC leak_in_output=$(grep -c SECRETTOKEN456 "$F/out") leak_in_errlog=$(grep -c SECRETTOKEN456 "$F/work/constitution/.git/land_git_stderr.log" 2>/dev/null)"; tail -1 "$F/out"
}

S_A21() { # mint deletes tracked files and writes the id
  say "== S_A21 mint deletes tracked files besides writing the id (fixture mint)"
  std a21; local F=$T/a21
  cat > "$F/mint_del.sh" <<'EOF'
#!/usr/bin/env bash
rm -f a.txt; mkdir -p docs; printf 'CON-777 minted\n' >> docs/tracker.fake; echo CON-777
EOF
  chmod +x "$F/mint_del.sh"
  run "$F/prep.out" prep "$F" --mint-cmd "$F/mint_del.sh"; say "prepare rc=$RC; a.txt on landed main: $(g "$F/work/constitution" cat-file -e main:a.txt 2>/dev/null && echo present || echo DELETED); output mentions the deletion: $(grep -c 'a.txt' "$F/prep.out")"
}

S_A24() { # vehicle containing merge commits (side branch with placeholders, and an internal merge of an older main)
  say "== S_A24 vehicle with merge commits (LIVE git)"
  base_fixture a24; local F=$T/a24 C bad=0 c n
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-PENDING-a\n'
  g "$F/seed" checkout -q -b side vehicle~0; vc "$F" s1.txt 'feat: side\n\nRoadmap-Item: CON-PENDING-b\n'
  g "$F/seed" checkout -q vehicle; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-133\n'
  g "$F/seed" merge -q --no-ff -m "Merge branch side" side
  mkbundle "$F"
  run "$F/prep.out" prep "$F" --item-id CON-924; C=$F/work/constitution; say "prepare rc=$RC :: $(grep -E 'step 4|step 5' "$F/prep.out" | tr '\n' ' ' | cut -c1-200)"
  [ "$RC" = 0 ] || { grep -oE 'ERROR.*' "$F/prep.out"; return; }
  say "tree_equality rows: $(($(wc -l < "$F/ev/tree_equality.tsv") - 1)), FAIL rows: $(grep -c $'\tFAIL\t' "$F/ev/tree_equality.tsv")"
  for c in $(g "$C" rev-list main --not "$(g "$F/seed" rev-parse main)"); do n=$(g "$C" log -1 --format='%(trailers:key=Roadmap-Item,valueonly)' "$c" | sed '/^$/d' | wc -l); [ "$n" = 1 ] || bad=$((bad+1)); done
  say "landed commits: $(g "$C" rev-list --count main --not "$(g "$F/seed" rev-parse main)"), with != 1 trailer: $bad; merge commits on landed range: $(g "$C" rev-list --merges --count main --not "$(g "$F/seed" rev-parse main)")"
  say "landed head tree == vehicle head tree: $([ "$(g "$C" rev-parse "refs/land/landed^{tree}")" = "$(g "$F/seed" rev-parse 'vehicle^{tree}')" ] && echo yes || echo no); CON-133 kept: $(g "$C" log --format=%B main | grep -c 'Roadmap-Item: CON-133')"
  run "$F/pub.out" pub "$F"; say "publish rc=$RC; at main $(allat "$F" "$(g "$C" rev-parse main)")/9"
}

S_A25() { # diverged remote mains
  say "== S_A25 diverged remote mains (LIVE git)"
  std a25; local F=$T/a25
  git clone -q "$F/remotes/gitflic.git" "$F/div"; printf 'x\n' > "$F/div/x"; g "$F/div" add x; g "$F/div" commit -q -m d -m "Roadmap-Item: CON-003"; g "$F/div" push -q origin HEAD:refs/heads/main
  git clone -q "$F/remotes/origin.git" "$F/div2"; printf 'y\n' > "$F/div2/y"; g "$F/div2" add y; g "$F/div2" commit -q -m e -m "Roadmap-Item: CON-004"; g "$F/div2" push -q origin HEAD:refs/heads/main
  local b1 b2; b1=$(rmain "$F" gitflic); b2=$(rmain "$F" origin)
  : > "$PUSHLOG"; run "$F/prep.out" prep "$F" --item-id CON-925; say "prepare rc=$RC :: $(grep -oE 'ERROR.*' "$F/prep.out" | cut -c1-150); pushes: $(wc -l < "$PUSHLOG"); gitflic/origin unchanged: $([ "$(rmain "$F" gitflic)" = "$b1" ] && [ "$(rmain "$F" origin)" = "$b2" ] && echo yes || echo no)"
}

S_A26() { # concurrent runs in one workdir
  say "== S_A26 concurrent prepare x2 and publish x2 in one workdir (LIVE git, real flock)"
  std a26; local F=$T/a26 p1 p2 r1 r2
  ( prep "$F" --item-id CON-926 > "$F/c1.out" 2>&1; echo $? > "$F/c1.rc" ) & p1=$!
  ( prep "$F" --item-id CON-926 > "$F/c2.out" 2>&1; echo $? > "$F/c2.rc" ) & p2=$!
  wait "$p1" "$p2"; r1=$(cat "$F/c1.rc"); r2=$(cat "$F/c2.rc")
  say "prepare rcs: $r1 $r2 :: $(grep -hoE 'ERROR.*' "$F/c1.out" "$F/c2.out" | cut -c1-110 | tr '\n' '|')"
  ( pub "$F" > "$F/d1.out" 2>&1; echo $? > "$F/d1.rc" ) & p1=$!
  ( pub "$F" > "$F/d2.out" 2>&1; echo $? > "$F/d2.rc" ) & p2=$!
  wait "$p1" "$p2"; say "publish rcs: $(cat "$F/d1.rc") $(cat "$F/d2.rc") :: $(grep -hoE 'ERROR.*' "$F/d1.out" "$F/d2.out" | cut -c1-110 | tr '\n' '|'); at main $(allat "$F" "$(g "$F/work/constitution" rev-parse main)")/9"
}

S_A27() { # vehicle head already on main
  say "== S_A27 vehicle head already on every main (LIVE git)"
  std a27; local F=$T/a27 r
  for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" vehicle:refs/heads/main; done
  run "$F/prep.out" prep "$F" --item-id CON-927; say "prepare rc=$RC :: $(grep -oE 'ERROR.*' "$F/prep.out")"
}

S_A28() { # caller environment exports GIT_DIR (e.g. the lander started from inside a git hook or a tool that exports it)
  say "== S_A28 exported GIT_DIR pointing at a scratch 'victim' repo (LIVE git; victim is a scratch repo, never the live checkout)"
  std a28; local F=$T/a28 V=$T/a28_victim
  git init -q "$V"; printf 'mine\n' > "$V/precious.txt"; g "$V" add precious.txt; g "$V" commit -q -m "local only work" -m "Roadmap-Item: CON-005"
  local vmain vcfg vrem; vmain=$(g "$V" rev-parse main); vcfg=$(sha256sum "$V/.git/config" | cut -c1-16); vrem=$(g "$V" remote | wc -l)
  say "victim before: main=$vmain remotes=$vrem config_sha=$vcfg"
  run "$F/prep.out" env GIT_DIR="$V/.git" PATH="$T/shim:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --item-id CON-928
  say "prepare rc=$RC :: $(grep -E 'step 5|ERROR' "$F/prep.out" | head -2 | cut -c1-160)"
  say "full prepare output (last 12 lines, paths shortened):"; tail -n 12 "$F/prep.out" | sed "s#$T#\$T#g; s/^/    | /"
  say "victim objects/refs: branches=$(g "$V" branch -a | tr -d ' ' | tr '\n' ',') objects=$(g "$V" count-objects -v | grep -E '^(count|in-pack)' | tr '\n' ' ') FETCH_HEAD=$([ -e "$V/.git/FETCH_HEAD" ] && echo present || echo absent) land_stderr=$([ -e "$V/.git/land_git_stderr.log" ] && echo present || echo absent) worktree_files=$(ls -A "$V" | tr '\n' ',')"
  say "victim after: main=$(g "$V" rev-parse main) (moved: $([ "$(g "$V" rev-parse main)" = "$vmain" ] && echo no || echo YES)) remotes=$(g "$V" remote | wc -l) config_sha=$(sha256sum "$V/.git/config" | cut -c1-16) core.worktree=$(g "$V" config --get core.worktree || echo unset)"
  say "victim local-only commit still reachable from a branch: $(g "$V" branch --contains "$vmain" 2>/dev/null | wc -l) branch(es); refs/land/* in victim: $(g "$V" for-each-ref refs/land | wc -l); clone dir has .git: $([ -d "$F/work/constitution/.git" ] && echo yes || echo no)"
  say "victim reflog of main (most recent 3): $(g "$V" reflog -3 --format='%gs' main | tr '\n' '|')"
}

S_A29() { # caller environment exports GIT_WORK_TREE (githooks(5): exported to hooks with GIT_DIR)
  say "== S_A29 exported GIT_WORK_TREE pointing at a scratch 'victim' directory (LIVE git; scratch victim)"
  std a29; local F=$T/a29 VW=$T/a29_victim_wt
  mkdir -p "$VW"; printf 'precious-a\n' > "$VW/a.txt"; printf 'keep\n' > "$VW/keep.txt"
  local before; before=$(cd "$VW" && sha256sum a.txt keep.txt | tr '\n' ' ')
  say "victim dir before: files=$(ls -A "$VW" | tr '\n' ',') sums=$before"
  run "$F/prep.out" env GIT_WORK_TREE="$VW" PATH="$T/shim:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --item-id CON-929
  say "prepare rc=$RC; output tail:"; tail -n 8 "$F/prep.out" | sed "s#$T#\$T#g; s/^/    | /"
  say "victim dir after: files=$(ls -A "$VW" | tr '\n' ',') a.txt=[$(head -c 40 "$VW/a.txt" | tr '\n' ' ')] keep.txt=[$(head -c 40 "$VW/keep.txt" 2>/dev/null | tr '\n' ' ')]"
  say "clone core.worktree=$(git --git-dir="$F/work/constitution/.git" config --get core.worktree 2>/dev/null || echo unset); clone dir files=$(ls -A "$F/work/constitution" 2>/dev/null | tr '\n' ',')"
}

S_A30() { # caller environment exports GIT_INDEX_FILE (git commit exports it to pre-commit/commit-msg hooks)
  say "== S_A30 exported GIT_INDEX_FILE pointing at a scratch 'victim' repo index (LIVE git; scratch victim)"
  std a30; local F=$T/a30 V=$T/a30_victim
  git init -q "$V"; printf 'c\n' > "$V/committed.txt"; g "$V" add committed.txt; g "$V" commit -q -m "victim base" -m "Roadmap-Item: CON-006"
  printf 'staged-only\n' > "$V/staged.txt"; g "$V" add staged.txt
  local isum st lf; isum=$(sha256sum "$V/.git/index" | cut -c1-16); st=$(g "$V" status --porcelain | tr '\n' '|'); lf=$(g "$V" ls-files | tr '\n' ',')
  say "victim before: index_sha=$isum status=[$st] ls-files=[$lf]"
  run "$F/prep.out" env GIT_INDEX_FILE="$V/.git/index" PATH="$T/shim:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --item-id CON-930
  say "prepare rc=$RC; output tail:"; tail -n 8 "$F/prep.out" | sed "s#$T#\$T#g; s/^/    | /"
  say "victim after: index_sha=$(sha256sum "$V/.git/index" | cut -c1-16) status=[$(g "$V" status --porcelain 2>&1 | head -6 | tr '\n' '|')] ls-files=[$(g "$V" ls-files 2>&1 | tr '\n' ',')]"
  say "clone own index present: $([ -e "$F/work/constitution/.git/index" ] && echo yes || echo no)"
  local miss=0 e; while read -r _ e _; do g "$V" cat-file -e "$e" 2>/dev/null || miss=$((miss+1)); done < <(g "$V" ls-files -s)
  say "victim index entries whose blob is absent from the victim object store: $miss"
  say "victim write-tree after: $(g "$V" write-tree >/dev/null 2>"$F/wt.err" && echo OK || { echo "FAILS: $(head -1 "$F/wt.err")"; })"
  say "clone landed main tree: [$(git --git-dir="$F/work/constitution/.git" ls-tree -r --name-only main | tr '\n' ',')]"
  say "publish with GIT_INDEX_FILE still exported:"
  run "$F/pub.out" env GIT_INDEX_FILE="$V/.git/index" PATH="$T/shim:$PATH" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
  say "  publish rc=$RC :: $(grep -E 'ERROR|PASS|FAIL' "$F/pub.out" | head -3 | sed "s#$T#\$T#g" | tr '\n' '|' | cut -c1-300)"
  say "  remote main == clone main: $(allat "$F" "$(git --git-dir="$F/work/constitution/.git" rev-parse main)")/9"
}

for s in "${@:-S_A1 S_A3 S_A3b S_A5 S_A6 S_A7 S_A8 S_A9 S_A10 S_A11 S_A12 S_A13 S_A14 S_A15 S_A19 S_A21 S_A23 S_A24 S_A25 S_A26 S_A27 S_A28}"; do
  for x in $s; do "$x"; done
done
say "== scenarios done"
