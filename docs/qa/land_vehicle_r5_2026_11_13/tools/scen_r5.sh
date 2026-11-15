#!/usr/bin/env bash
# scen_r5.sh <lander> <lib-dir> <scratch-root>: the round-5 fixer's own adversarial
# scenarios for scripts/release/land_vehicle.sh.
#
# Class (§11.4.289(C)): gate logic. The git side is real (local bare repositories as
# the nine remotes, real server-side hooks). Test doubles (UNIT-CLASS): fake mint
# scripts, a fake ssh program that never connects (it prints its arguments and exits
# 255), server hooks acting as a concurrent writer. No network: every URL is a local
# path, or an ssh URL served by the fake ssh. HOME is never reassigned; git config is
# isolated per scenario with GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM. Only fake
# credentials (the string FAKETOKEN).
#
# Sink-side evidence: every remote carries a pre-receive logger that records each ref
# update the SERVER receives (old, new, ref) and classifies it as create, delete, ff or
# NONFF. The summary counts NONFF updates, deletions, updates of a ref other than
# refs/heads/main and tags on the servers, over every scenario.
# Output: one PASS/FAIL line per check, then
#   SUMMARY nonff=N deletions=N nonmain=N server_tags=N leaks=N
#   RESULT pass=N fail=N
# Exit 0 when every check passes and every summary count is 0.
set -uo pipefail
LANDER=${1:?lander}; LIB=${2:?lib dir}; ROOT=${3:?scratch root}
# shellcheck source=/dev/null
. "$LIB/safe_rm.sh"
REALGIT=$(command -v git)
REMOTES="gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w origin"
ZERO=0000000000000000000000000000000000000000
T=$(mktemp -d "$ROOT/scen5.XXXXXX"); : "${T:?}"
cleanup() {
  [ -n "${T:-}" ] && [ -d "$T" ] || return 0
  chmod -R u+rwx "$T" 2>/dev/null || true
  safe_rm_rf "$T"
}
trap cleanup EXIT
export GIT_CONFIG_NOSYSTEM=1
export LANDER_TRACKER_PATHS=docs/tracker.fake
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
g() { git -C "$1" "${@:2}"; }
rmain() { git --git-dir="$1/remotes/$2.git" rev-parse -q --verify refs/heads/main 2>/dev/null || echo none; }
run() { local out=$1; shift; "$@" > "$out" 2>&1; RC=$?; }
hg() { env -u GIT_DIR -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
         -u GIT_PUSH_OPTION_COUNT -u GIT_PROTOCOL -u GIT_PREFIX "$REALGIT" "$@"; }
ALL_UPDATES=$T/all_server_updates.log; : > "$ALL_UPDATES"

# setcfg <F>: a private global config for the scenario
setcfg() {
  export GIT_CONFIG_GLOBAL="$1/gc"
  git config --file "$1/gc" user.name "Scen5 Test"
  git config --file "$1/gc" user.email "scen5@test.invalid"
  git config --file "$1/gc" init.defaultBranch main
  git config --file "$1/gc" advice.detachedHead false
}
gcfg() { git config --file "$GIT_CONFIG_GLOBAL" "$@"; }
# ff_logger <F> <dir of the bare repo> <name>: server pre-receive logger
ff_logger() {
  cat > "$2/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
while read -r old new ref; do
  if [ "\$old" = $ZERO ]; then c=create; elif [ "\$new" = $ZERO ]; then c=delete
  elif git merge-base --is-ancestor "\$old" "\$new" 2>/dev/null; then c=ff; else c=NONFF; fi
  printf '%s %s %s %s %s opts=%s\n' "$3" "\$ref" "\$old" "\$new" "\$c" "\${GIT_PUSH_OPTION_COUNT:-0}" >> "$1/server_updates.log"
done
exit 0
EOF
  chmod +x "$2/hooks/pre-receive"
}
# base <name> [remote root]: 9 bare remotes at a base commit (logger on each), seed on branch vehicle
base() {
  local F=$T/$1 RR=${2:-remotes} r
  mkdir -p "$F/$RR" "$F/work"; setcfg "$F"
  git init -q "$F/seed"
  printf 'base\n' > "$F/seed/a.txt"; g "$F/seed" add a.txt
  g "$F/seed" commit -q -m "base" -m "Roadmap-Item: CON-001"
  g "$F/seed" tag -a -m "v0" v0 main
  : > "$F/remotes.txt"
  for r in $REMOTES; do
    git init -q --bare "$F/$RR/$r.git"
    g "$F/seed" push -q "$F/$RR/$r.git" main:refs/heads/main
    ff_logger "$F" "$F/$RR/$r.git" "$r"
    printf '%s %s\n' "$r" "$F/$RR/$r.git" >> "$F/remotes.txt"
  done
  [ "$RR" = remotes ] || ln -s "$RR" "$F/remotes"
  : > "$F/server_updates.log"
  g "$F/seed" checkout -q -b vehicle
  printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake; echo CON-777\n' > "$F/mint.sh"
  chmod +x "$F/mint.sh"
}
vc() { local F=$1; printf '%s\n' "$2" > "$F/seed/$2"; g "$F/seed" add "$2"; printf '%b' "$3" > "$F/msg"; g "$F/seed" commit -q --cleanup=verbatim -F "$F/msg"; }
mkbundle() { local F=$1; g "$F/seed" bundle create -q "$F/vehicle.bundle" vehicle ^main 2>/dev/null; g "$F/seed" rev-parse vehicle > "$F/head"; sha256sum "$F/vehicle.bundle" | awk '{print $1}' > "$F/sha"; }
std() { base "$@"; local F=$T/$1; vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-landing\n'; mkbundle "$F"; }
prep() { local F=$1; shift; "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"; }
pub() { local F=$1; shift; "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"; }
allat() { local F=$1 want=$2 r n=0; for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$want" ] && n=$((n + 1)); done; echo "$n"; }
nupd() { local n; n=$(grep -c . "$1/server_updates.log" 2>/dev/null) || true; echo "${n:-0}"; }
nclass() { local n; n=$(grep -c -E " $2 opts=" "$1/server_updates.log" 2>/dev/null) || true; echo "${n:-0}"; }
collect() { cat "$1/server_updates.log" >> "$ALL_UPDATES"; }
# expect_rc <label> <want> <outfile>
expect_rc() { if [ "$RC" -eq "$2" ]; then ok "$1 (rc=$RC)"; else bad "$1 (rc=$RC, want $2)"; sed 's/^/    | /' "$3"; fi; }

# ------------------------------------------------------------------ S01 fast-forward landing with a mint
std s01; F=$T/s01
run "$F/prep.out" prep "$F" --mint-cmd "$F/mint.sh"; expect_rc "S01 prepare with a mint" 0 "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
run "$F/pub.out" pub "$F"; expect_rc "S01 publish" 0 "$F/pub.out"
if [ "$(allat "$F" "$L")" = 9 ] && [ "$(nupd "$F")" = 9 ] && [ "$(nclass "$F" ff)" = 9 ]; then ok "S01 9/9 at the checked main; the servers saw 9 updates, all fast-forward"
else bad "S01 servers (at main $(allat "$F" "$L"), updates $(nupd "$F"), ff $(nclass "$F" ff))"; fi
collect "$F"; : > "$F/server_updates.log"
# S02 publish again: idempotent, no server update
run "$F/pub2.out" pub "$F"; expect_rc "S02 publish again" 0 "$F/pub2.out"
if [ "$(nupd "$F")" = 0 ] && [ "$(grep -c '| up-to-date |' "$F/ev/publish.md")" = 9 ]; then ok "S02 publish again: 9 up-to-date, the servers saw 0 updates"
else bad "S02 re-run (updates $(nupd "$F"))"; fi
collect "$F"

# ------------------------------------------------------------------ S03 merge landing (main moved after the vehicle forked)
std s03; F=$T/s03
g "$F/seed" checkout -q main; printf 'mover\n' > "$F/seed/m.txt"; g "$F/seed" add m.txt
g "$F/seed" commit -q -m "mover" -m "Roadmap-Item: CON-002"
for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
g "$F/seed" checkout -q vehicle; : > "$F/server_updates.log"
run "$F/prep.out" prep "$F" --item-id CON-903; expect_rc "S03 prepare (merge)" 0 "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
run "$F/pub.out" pub "$F"; expect_rc "S03 publish" 0 "$F/pub.out"
if [ "$(g "$C" rev-list --parents -n 1 main | wc -w)" = 3 ] && [ "$(allat "$F" "$L")" = 9 ] && [ "$(nclass "$F" ff)" = 9 ] && [ "$(nupd "$F")" = 9 ]; then
  ok "S03 the merge commit reached 9/9; the servers saw 9 fast-forward updates"
else bad "S03 merge landing (parents $(g "$C" rev-list --parents -n 1 main | wc -w), ff $(nclass "$F" ff))"; fi
collect "$F"

# ------------------------------------------------------------------ S04 hostile global push config (no remote.<n>.* key)
std s04; F=$T/s04
gcfg push.default matching; gcfg push.followTags true; gcfg push.pushOption FAKEOPT; gcfg remote.pushDefault github
gcfg push.recurseSubmodules on-demand
for r in $REMOTES; do git --git-dir="$F/remotes/$r.git" config receive.advertisePushOptions true; done
run "$F/prep.out" prep "$F" --item-id CON-904; expect_rc "S04 prepare" 0 "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
g "$C" tag -a -m "local tag" vlocal main; g "$C" branch extra main
run "$F/pub.out" pub "$F"; expect_rc "S04 publish" 0 "$F/pub.out"
tags=0; for r in $REMOTES; do n=$(git --git-dir="$F/remotes/$r.git" for-each-ref refs/tags | grep -c . || true); tags=$((tags + n)); done
# control: the same global config, a plain push to a server that (like the 9 remotes)
# advertises push options; its rc is recorded, never swallowed
git init -q --bare "$F/ctl.git"; git --git-dir="$F/ctl.git" config receive.advertisePushOptions true
crc=0; g "$C" push -q "$F/ctl.git" main 2>"$F/ctl.err" || crc=$?
ctl=$(git --git-dir="$F/ctl.git" for-each-ref refs/tags | grep -c . || true)
if [ "$(allat "$F" "$L")" = 9 ] && [ "$(nupd "$F")" = 9 ] && [ "$(grep -c ' refs/heads/main .* ff opts=0$' "$F/server_updates.log")" = 9 ] && [ "$tags" = 0 ] && [ "$crc" = 0 ] && [ "$ctl" -ge 1 ]; then
  ok "S04 matching/followTags/pushOption/pushDefault: only refs/heads/main, ff, 0 push options, 0 tags on the servers (control: a plain push with the same config sends the tag, rc 0)"
else bad "S04 hostile config (updates $(nupd "$F"), tags $tags, control rc $crc, control tags $ctl)"; sed 's/^/    | /' "$F/server_updates.log" "$F/ctl.err"; fi
collect "$F"

# ------------------------------------------------------------------ S05 global remote.<n>.push refspec: refused before any push
std s05; F=$T/s05
run "$F/prep.out" prep "$F" --item-id CON-905; expect_rc "S05 prepare" 0 "$F/prep.out"
gcfg remote.github.push '+refs/heads/*:refs/heads/*'
gcfg --add remote.github.push ':refs/heads/stale'
run "$F/pub.out" pub "$F"; expect_rc "S05 publish with a global remote.github.push" 2 "$F/pub.out"
if grep -q "remote 'github' has remote.github.push set" "$F/pub.out" && [ "$(nupd "$F")" = 0 ]; then ok "S05 refused naming remote.github.push; the servers saw 0 updates"
else bad "S05 (updates $(nupd "$F"))"; fi
collect "$F"

# ------------------------------------------------------------------ S06 a remote diverged after prepare: preflight refuses all
std s06; F=$T/s06
run "$F/prep.out" prep "$F" --item-id CON-906; expect_rc "S06 prepare" 0 "$F/prep.out"
git clone -q "$F/remotes/gitverse.git" "$F/other" 2>/dev/null
printf 'other\n' > "$F/other/o.txt"; g "$F/other" add o.txt; g "$F/other" commit -q -m other -m "Roadmap-Item: CON-007"
g "$F/other" push -q origin main; : > "$F/server_updates.log"
run "$F/pub.out" pub "$F"; expect_rc "S06 publish against a diverged gitverse" 1 "$F/pub.out"
if grep -q 'preflight refused 1 remote' "$F/pub.out" && [ "$(nupd "$F")" = 0 ]; then ok "S06 preflight refused gitverse; the servers saw 0 updates"
else bad "S06 (updates $(nupd "$F"))"; fi
collect "$F"

# ------------------------------------------------------------------ S07 concurrent writer in the clone during the pushes
std s07; F=$T/s07
run "$F/prep.out" prep "$F" --item-id CON-907; expect_rc "S07 prepare" 0 "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
cat > "$F/remotes/gitflic.git/hooks/post-receive" <<EOF
#!/usr/bin/env bash
cat > /dev/null
$(declare -f hg)
REALGIT=$REALGIT
[ -e "$F/race.done" ] && exit 0
: > "$F/race.done"
printf 'unreviewed\n' > "$C/unreviewed.txt"
hg -C "$C" add unreviewed.txt && hg -C "$C" -c core.hooksPath=/dev/null commit -q -m "UNREVIEWED" >/dev/null 2>&1
exit 0
EOF
chmod +x "$F/remotes/gitflic.git/hooks/post-receive"
run "$F/pub.out" pub "$F"; expect_rc "S07 publish while the clone main moves" 1 "$F/pub.out"
U=$(g "$C" rev-parse main)
if [ -e "$F/race.done" ] && [ "$U" != "$L" ] && [ "$(allat "$F" "$L")" = 9 ] && ! grep -q " $U " "$F/server_updates.log" && [ "$(nclass "$F" ff)" = 9 ]; then
  ok "S07 the servers received the checked sha 9 times and the moved main 0 times"
else bad "S07 (at checked $(allat "$F" "$L"))"; fi
run "$F/pub2.out" pub "$F"; expect_rc "S07 publish again refuses the unreviewed commit" 1 "$F/pub2.out"
if ! grep -q " $U " "$F/server_updates.log"; then ok "S07 the unreviewed commit never reached a server"; else bad "S07 unreviewed commit reached a server"; fi
collect "$F"

# ------------------------------------------------------------------ S08 credential surface (FAKETOKEN), with control needles
base s08 x-FAKETOKEN-abc; F=$T/s08
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\nprintf "fake-ssh: cannot reach %%s\\n" "$*" >&2\nexit 255\n' > "$F/fakessh"; chmod +x "$F/fakessh"
sed 's#^\(m3w\) .*#\1 lander@FAKETOKEN-ssh.invalid:m3w.git#' "$F/remotes.txt" > "$F/remotes_ssh.txt"
{ head -n 2 "$F/remotes.txt"; printf 'github_vasic_digital %s extra-FAKETOKEN-field\n' "$F/x-FAKETOKEN-abc/github_vasic_digital.git"; tail -n +4 "$F/remotes.txt"; } > "$F/remotes_bad.txt"
run "$F/o1" env GIT_SSH_COMMAND="$F/fakessh" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" \
  --workdir "$F/work" --remotes-file "$F/remotes_ssh.txt" --evidence-dir "$F/ev" --item-id CON-908
expect_rc "S08 prepare with an ssh remote that cannot be reached" 1 "$F/o1"
C=$F/work/constitution
errlog_hits=$(grep -c FAKETOKEN "$C/.git/land_git_stderr.log" 2>/dev/null || true)
safe_rm_rf "${C:?}"
run "$F/o2" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" \
  --workdir "$F/work" --remotes-file "$F/remotes_bad.txt" --evidence-dir "$F/ev" --item-id CON-908
expect_rc "S08 a remotes file line with three fields" 2 "$F/o2"
run "$F/o3" prep "$F" --item-id CON-908; expect_rc "S08 prepare (FAKETOKEN in every remote path)" 0 "$F/o3"
chmod 000 "$F/x-FAKETOKEN-abc/gitverse.git/objects"
run "$F/o4" pub "$F"; expect_rc "S08 publish with gitverse unreadable" 1 "$F/o4"
chmod 755 "$F/x-FAKETOKEN-abc/gitverse.git/objects"
cat > "$F/x-FAKETOKEN-abc/github.git/hooks/pre-receive" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; echo "rejected by policy" >&2; exit 1
EOF
chmod +x "$F/x-FAKETOKEN-abc/github.git/hooks/pre-receive"
run "$F/o5" pub "$F"; expect_rc "S08 publish with github rejecting" 1 "$F/o5"
run "$F/o6" env GIT_SSH_COMMAND="$F/fakessh" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes_ssh.txt" --evidence-dir "$F/ev"
expect_rc "S08 verify with a mismatching ssh URL" 2 "$F/o6"
run "$F/o7" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
expect_rc "S08 verify (github still behind)" 1 "$F/o7"
leaks=0; scanned=0
for f in "$F"/o1 "$F"/o2 "$F"/o3 "$F"/o4 "$F"/o5 "$F"/o6 "$F"/o7 "$F"/ev/*; do
  [ -f "$f" ] || continue
  scanned=$((scanned + 1))
  if grep -q FAKETOKEN "$f"; then leaks=$((leaks + 1)); printf '    | LEAK in %s\n' "$(basename "$f")"; fi
done
printf 'needle FAKETOKEN\n' > "$F/planted.txt"; planted=$(grep -c FAKETOKEN "$F/planted.txt" || true)
neg=0; for f in "$F"/o1 "$F"/o2 "$F"/o3 "$F"/o4 "$F"/o5 "$F"/o6 "$F"/o7 "$F"/ev/*; do [ -f "$f" ] && grep -q 'ZZNEEDLE-9f3' "$f" && neg=$((neg + 1)); done
named=$(grep -c '^| gitverse |' "$F/ev/publish.md" || true)
line3=$(grep -c 'remotes file line 3' "$F/o2" || true)
if [ "$leaks" = 0 ] && [ "$scanned" -ge 10 ] && [ "${errlog_hits:-0}" -ge 1 ] && [ "$planted" = 1 ] && [ "$neg" = 0 ] && [ "$named" -ge 1 ] && [ "$line3" = 1 ]; then
  ok "S08 0 of $scanned output/evidence files hold FAKETOKEN (controls: the clone's stderr log holds it $errlog_hits time(s); a planted needle is found; a fabricated needle is not; gitverse is named; the bad line is named by number)"
else bad "S08 leak scan (leaks $leaks of $scanned, errlog $errlog_hits, planted $planted, negative $neg, named $named, line3 $line3)"; fi
collect "$F"

# ------------------------------------------------------------------ S09 an annotated tag object as --head
std s09; F=$T/s09
g "$F/seed" tag -a -m "vehicle tag" vt vehicle
g "$F/seed" bundle create -q "$F/vehicle.bundle" refs/tags/vt ^main 2>/dev/null
g "$F/seed" rev-parse vt > "$F/head"; sha256sum "$F/vehicle.bundle" | awk '{print $1}' > "$F/sha"
run "$F/prep.out" prep "$F" --item-id CON-909; expect_rc "S09 prepare with a tag object as --head" 1 "$F/prep.out"
if grep -q 'is a tag object, not a commit' "$F/prep.out" && [ "$(nupd "$F")" = 0 ]; then ok "S09 refused as a tag object; the servers saw 0 updates"
else bad "S09"; fi
collect "$F"

# ------------------------------------------------------------------ summary over every scenario (sink side)
nonff=$(grep -c ' NONFF opts=' "$ALL_UPDATES" || true)
dels=$(grep -c ' delete opts=' "$ALL_UPDATES" || true)
nonmain=$(grep -vc ' refs/heads/main ' "$ALL_UPDATES" || true)
stags=0
for d in "$T"/s0*/remotes/*.git "$T"/s08/x-FAKETOKEN-abc/*.git; do
  [ -d "$d" ] || continue
  n=$(git --git-dir="$d" for-each-ref refs/tags | grep -c . || true); stags=$((stags + n))
done
total=$(grep -c . "$ALL_UPDATES" || true)
if [ "$total" -ge 40 ]; then ok "SUMMARY control: the server loggers recorded $total ref updates"; else bad "SUMMARY control: only $total server updates recorded"; fi
printf 'SUMMARY nonff=%s deletions=%s nonmain=%s server_tags=%s leaks=%s\n' "$nonff" "$dels" "$nonmain" "$stags" "$leaks"
if [ "$nonff" = 0 ] && [ "$dels" = 0 ] && [ "$nonmain" = 0 ] && [ "$stags" = 0 ] && [ "$leaks" = 0 ]; then
  ok "SUMMARY 0 non-fast-forward, 0 deletions, 0 non-main refs, 0 tags on any server, 0 leaks"
else bad "SUMMARY counts not all 0"; fi
printf 'RESULT pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
