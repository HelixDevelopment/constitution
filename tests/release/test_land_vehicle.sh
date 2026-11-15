#!/usr/bin/env bash
# tests/release/test_land_vehicle.sh - hermetic test of scripts/release/land_vehicle.sh.
#
# Class (§11.4.289(C)): the git side is REAL (real git, nine real bare repositories
# on the local file system as remotes with the real remote names, real client and
# server-side hooks, real flock). Test doubles (UNIT-CLASS): the workable-items engine
# (shell scripts that write a tracker file and print an id), a fake gpg program, and a
# git PATH shim that records the argv of every remote-ref-writing git command the
# lander starts (push, send-pack, http-push, and any alias), and shims that fail one git call
# on purpose (V13, X8b) or change the index inside git write-tree (V15). The run proves the
# lander's logic; it is NOT live proof against any hosting platform. No network, no forge writes, no force leg anywhere, HOME is
# never reassigned: git config isolation is done with GIT_CONFIG_GLOBAL /
# GIT_CONFIG_NOSYSTEM. Scratch comes from mktemp -d and is removed with safe_rm_rf
# (§11.4.287(B)).
#
# Every refusal case asserts its exact exit code AND its die message, so a
# case can only pass for its own reason. Output of git is captured into a
# variable before it is grepped; nothing is piped into `grep -q` under pipefail.
#
# Round 5: the R5-* cases (right after the shared helpers) cover the round-5 findings F1-F13
# and N1-N3 and the round-4 reviewer mutants; see docs/qa/land_vehicle_r5_2026_11_13/.
# Round 6: the R6-* cases (before the R5-* cases) cover the round-5 review findings
# R5-A1, R5-A2, R5-B, R5-C, R5-D, R5-F, R5-G and R5-I; see docs/qa/land_vehicle_r6_2026_11_14/.
#
# Usage: bash tests/release/test_land_vehicle.sh [path/to/land_vehicle.sh]
#        (LANDER_SCRIPT=<path> also selects another copy; LANDER_TEST_FAILFAST=1
#        stops at the first FAIL, used by the mutant runner; LANDER_TEST_R5_ONLY=1 runs
#        the setup and the round-5 cases only, then prints RESULT and exits;
#        LANDER_TEST_R6_ONLY=1 the setup and the round-6 cases only)
# Exit:  0 all cases pass, 1 any case fails. Last line: "RESULT pass=N fail=M".
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LANDER=${1:-${LANDER_SCRIPT:-$ROOT/scripts/release/land_vehicle.sh}}
[ -r "$LANDER" ] || { echo "test: lander not found: $LANDER" >&2; exit 1; }
# shellcheck source=/dev/null # sourced from the repository layout at run time
. "$ROOT/scripts/lib/safe_rm.sh" || { echo "test: cannot source $ROOT/scripts/lib/safe_rm.sh" >&2; exit 1; }
REMOTES="gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w origin"
REALGIT=$(command -v git)
FAILFAST=${LANDER_TEST_FAILFAST:-0}

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() {
  FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"
  if [ "$FAILFAST" = 1 ]; then printf '\nRESULT pass=%d fail=%d (failfast)\n' "$PASS" "$FAIL"; exit 1; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/lvtest.XXXXXX")
: "${T:?}"
cleanup() { [ -n "${T:-}" ] && [ -d "$T" ] && safe_rm_rf "$T"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# the fake mints of this test write docs/tracker.fake (the real default is docs/workable_items.db)
export LANDER_TRACKER_PATHS=docs/tracker.fake

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Lander Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "lander@test.invalid"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

g() { git -C "$1" "${@:2}"; }
rmain() { git --git-dir="$1/remotes/$2.git" rev-parse main; }

# ---- git PATH shim (UNIT-CLASS recorder): every lander invocation goes through lv(),
# which puts this shim first on PATH. The shim records the argv after the `push`
# subcommand (fields separated by \x1f, one push per line). A send-pack or http-push
# call is recorded as a line starting with that name, and a subcommand that is not a
# git command but resolves to an alias as a line starting with ALIAS: (so either one
# fails push_log_clean). Then it runs real git.
mkdir -p "$T/shim"
PUSHLOG=$T/push.log
: > "$PUSHLOG"
KNOWN_CMDS=$("$REALGIT" --list-cmds=main,others | tr '\n' '|')
KNOWN_CMDS=${KNOWN_CMDS%|}
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
i=1; n=\$#; args=("\$@")
while [ \$i -le \$n ]; do
  a=\${args[\$((i - 1))]}
  case "\$a" in
    -c|-C|--git-dir|--work-tree|--namespace|--exec-path) i=\$((i + 2)) ;;
    -*) i=\$((i + 1)) ;;
    *) break ;;
  esac
done
if [ \$i -le \$n ]; then
  sub=\${args[\$((i - 1))]}
  case "\$sub" in
    push) ( IFS=\$'\x1f'; printf '%s\n' "\${args[*]:\$i}" ) >> "$PUSHLOG" ;;
    send-pack|http-push) ( IFS=\$'\x1f'; printf '%s\x1f%s\n' "\$sub" "\${args[*]:\$i}" ) >> "$PUSHLOG" ;;
    $KNOWN_CMDS) : ;;
    *) if "$REALGIT" "\${args[@]:0:\$((i - 1))}" config --get "alias.\$sub" >/dev/null 2>&1; then
         ( IFS=\$'\x1f'; printf 'ALIAS:%s\x1f%s\n' "\$sub" "\${args[*]:\$i}" ) >> "$PUSHLOG"
       fi ;;
  esac
fi
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/shim/git"
lv() { PATH="$T/shim:$PATH" "$LANDER" "$@"; }
# push_log_clean: every recorded push is exactly `-q --no-verify --no-follow-tags
# --recurse-submodules=no <declared remote> <full sha>:refs/heads/main` (no +refspec, -f,
# --force*, --mirror, --delete, tags, a branch name as the source, send-pack or alias ...).
push_log_clean() {
  local line r okr re US=$'\x1f'
  [ -s "$PUSHLOG" ] || return 1
  while IFS= read -r line; do
    okr=0
    for r in $REMOTES; do
      re="^-q${US}--no-verify${US}--no-follow-tags${US}--recurse-submodules=no${US}${r}${US}[0-9a-f]{40}([0-9a-f]{24})?:refs/heads/main\$"
      [[ "$line" =~ $re ]] && okr=1
    done
    [ "$okr" = 1 ] || { printf '    | bad push argv: %s\n' "${line//$'\x1f'/ }"; return 1; }
  done < "$PUSHLOG"
}

# run <outfile> cmd... : runs cmd, stdout+stderr to outfile, exit status in RC
RC=0
run() { local out=$1; shift; set +e; "$@" > "$out" 2>&1; RC=$?; set -e; }
# refused <label> <want_rc> <ERE> <outfile>: asserts the exit code and the message
refused() {
  if [ "$RC" -eq "$2" ] && grep -Eq -- "$3" "$4"; then ok "$1 (rc=$RC)"
  else bad "$1 (rc=$RC, want rc=$2 and /$3/)"; sed 's/^/    | /' "$4"; fi
}
succeeded() { # succeeded <label> <outfile>
  if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1 (rc=$RC)"; sed 's/^/    | /' "$2"; fi
}
# no_remote_moved <F> <sha>: every remote main still equals sha
no_remote_moved() {
  local r
  for r in $REMOTES; do [ "$(rmain "$1" "$r")" = "$2" ] || return 1; done
}

# base_fixture <name>: $T/<name>/ with 9 bare remotes at a base commit, a seed
# repo on branch vehicle (no vehicle commits yet), a remotes file and two fake mints.
base_fixture() {
  local F=$T/$1 r
  mkdir -p "$F/remotes" "$F/work"
  git init -q "$F/seed"
  printf 'base\n' > "$F/seed/a.txt"
  g "$F/seed" add a.txt
  g "$F/seed" commit -q -m "base" -m "Roadmap-Item: CON-001"
  : > "$F/remotes.txt"
  for r in $REMOTES; do
    git init -q --bare "$F/remotes/$r.git"
    g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main
    printf '%s %s\n' "$r" "$F/remotes/$r.git" >> "$F/remotes.txt"
  done
  g "$F/seed" checkout -q -b vehicle
  # fake engine mint: asserts the clone dir name, writes a tracker file, prints the id
  cat > "$F/mint.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$(basename "$PWD")" = constitution ] || { echo "not in constitution dir" >&2; exit 9; }
mkdir -p docs
printf 'CON-777 minted\n' >> docs/tracker.fake
echo "engine: minted"
echo "CON-777"
EOF
  # a mint whose last line is not an id
  cat > "$F/mint_bad.sh" <<'EOF'
#!/usr/bin/env bash
echo "CON-777"
echo "engine: done"
EOF
  chmod +x "$F/mint.sh" "$F/mint_bad.sh"
}
# vc <F> <file> <message as printf %b>: one vehicle commit on the current seed branch
vc() {
  local F=$1
  printf '%s\n' "$2" > "$F/seed/$2"
  g "$F/seed" add "$2"
  printf '%b' "$3" > "$F/msg"
  g "$F/seed" commit -q --cleanup=verbatim -F "$F/msg"
}
# mkbundle <F> [extra refs...]: bundle of vehicle (+refs) ^main; head = vehicle tip
mkbundle() {
  local F=$1; shift
  g "$F/seed" bundle create -q "$F/vehicle.bundle" vehicle "$@" ^main 2>/dev/null
  g "$F/seed" rev-parse vehicle > "$F/head"
  sha256sum "$F/vehicle.bundle" | awk '{print $1}' > "$F/sha"
}
# fixture <name>: base + 2 vehicle commits with placeholder trailers + bundle
fixture() {
  base_fixture "$1"
  local F=$T/$1
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'
  vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-landing\n'
  mkbundle "$F"
}

prepare_raw() { # prepare_raw <F> [args]: no mint/id argument added
  local F=$1; shift
  lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
    --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" \
    --evidence-dir "$F/ev" "$@"
}
prepare() { local F=$1; shift; prepare_raw "$F" --mint-cmd "$F/mint.sh" "$@"; }
publish() {
  local F=$1; shift
  lv publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"
}
# hash_by_subject <repo> <subject>: newest commit on main with that exact subject
hash_by_subject() {
  local out
  out=$(g "$1" log --format='%H %s' main 2>/dev/null || true)
  awk -v s="$2" '{h=$1; $1=""; sub(/^ /,""); if ($0==s) {print h; exit}}' <<<"$out"
}
# rimtrailers <repo> <commit>: Roadmap-Item values as git parses them
rimtrailers() { g "$1" log -1 --format='%(trailers:key=Roadmap-Item,valueonly)' "$2" 2>/dev/null || true; }
BASE_OF() { g "$1/seed" rev-parse main; }
landed_all() { # landed_all <F>: all 9 remote mains equal the clone main
  local lm r; lm=$(g "$1/work/constitution" rev-parse main 2>/dev/null || echo none)
  for r in $REMOTES; do [ "$(rmain "$1" "$r")" = "$lm" ] || return 1; done
}
lvenv() { # lvenv <VAR=value>... -- <lander args>: run the lander with extra env through the shim
  local -a e=()
  while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  env "${e[@]}" PATH="$T/shim:$PATH" "$LANDER" "$@"
}
PREP_ARGS() { printf '%s\n' --bundle "$1/vehicle.bundle" --sha256 "$(cat "$1/sha")" --head "$(cat "$1/head")" \
  --workdir "$1/work" --remotes-file "$1/remotes.txt" --evidence-dir "$1/ev"; }
seed_main_file() { # seed_main_file <F> <path> <content as printf %b>: commit on main, push to all 9, vehicle restarts at main
  local F=$1 r
  g "$F/seed" checkout -q main
  mkdir -p "$F/seed/$(dirname "$2")"; printf '%b' "$3" > "$F/seed/$2"
  g "$F/seed" add "$2"; g "$F/seed" commit -q -m "tracker seed" -m "Roadmap-Item: CON-002"
  for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
  g "$F/seed" checkout -q -B vehicle main
}
mkmint() { # mkmint <file> <line to append to docs/tracker.fake> <printed id>
  printf '#!/usr/bin/env bash\nmkdir -p docs; printf %q >> docs/tracker.fake\necho %q\n' "$2"$'\n' "$3" > "$1"; chmod +x "$1"
}
# nlines <file>: the number of lines of the file, 0 when it does not exist
nlines() { if [ -f "$1" ]; then wc -l < "$1"; else echo 0; fi; }
# atcount <F> <sha>: how many of the 9 remote mains equal sha
atcount() { local F=$1 want=$2 r n=0; for r in $REMOTES; do [ "$(rmain "$F" "$r" 2>/dev/null)" = "$want" ] && n=$((n + 1)); done; echo "$n"; }
# rawmsg <repo> <commit>: the commit message byte for byte (from the object, no git log)
rawmsg() { local raw; raw=$(g "$1" cat-file commit "$2" 2>/dev/null; printf x); raw=${raw%x}; printf '%s' "${raw#*$'\n\n'}"; }
# hook-safe git for server hooks (a hook runs with GIT_DIR and quarantine variables set)
hg() { env -u GIT_DIR -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
       -u GIT_PUSH_OPTION_COUNT -u GIT_PROTOCOL -u GIT_PREFIX "$REALGIT" "$@"; }
# gccopy <F>: a private copy of the test's global config in $F/gc (a case edits only its copy)
gccopy() { cp "$GIT_CONFIG_GLOBAL" "$1/gc"; }
gcset() { git config --file "$1/gc" "${@:2}"; }
# prep_gc / pub_gc <F> [args]: prepare / publish with GIT_CONFIG_GLOBAL=$F/gc, through the shim
prep_gc() { local F=$1; shift; local -a gpa=(); mapfile -t gpa < <(PREP_ARGS "$F")
  env GIT_CONFIG_GLOBAL="$F/gc" PATH="$T/shim:$PATH" "$LANDER" prepare "${gpa[@]}" "$@"; }
pub_gc() { local F=$1; shift
  env GIT_CONFIG_GLOBAL="$F/gc" PATH="$T/shim:$PATH" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" "$@"; }

# ##################################################################### round 6
# The R6-* cases cover the round-5 review findings R5-A1, R5-A2, R5-B, R5-C, R5-D, R5-F
# and R5-G; see docs/qa/land_vehicle_r6_2026_11_14/. LANDER_TEST_R6_ONLY=1 runs the setup
# and these cases only.

# tok_fixture <name>: fixture whose remotes file names every remote through a path that
# holds the stand-in credential $TOK (the workdir and the evidence dir do not hold it)
TOK=Zq7tokLANDSECRET
tok_fixture() {
  local F=$T/$1 r
  fixture "$1"
  ln -s "$F/remotes" "$T/$1.$TOK"
  : > "$F/remotes.txt"
  for r in $REMOTES; do printf '%s %s\n' "$r" "$T/$1.$TOK/$r.git" >> "$F/remotes.txt"; done
}
# tokcount <file>...: lines holding the stand-in credential
tokcount() { cat -- "$@" 2>/dev/null | grep -c -- "$TOK" || true; }
# evtok <dir>: evidence files holding the stand-in credential
evtok() { local l; l=$(grep -rl -- "$TOK" "$1" 2>/dev/null || true); [ -n "$l" ] && wc -l <<<"$l" || echo 0; }

# ============================================ R6-C0 control needle: the instrument sees the credential
tok_fixture r6c0; F=$T/r6c0
nfile=$(tokcount "$F/remotes.txt")
ctl=$(env SHELLOPTS=xtrace bash -c 'u=$(cat "$1"); : "$u"' _ "$F/remotes.txt" 2>&1 || true)
nctl=$(grep -c -- "$TOK" <<<"$ctl" || true)
if [ "$nfile" -eq 9 ] && [ "$nctl" -gt 0 ]; then ok "R6-C0 control needle: the remotes file holds the token 9 times and a traced shell that reads it prints it ($nctl lines)"
else bad "R6-C0 control needle (file $nfile, traced $nctl)"; fi

# ============================================ R6-C1..C3 tracing from the caller never prints a remote URL
for mode in shellopts bashenv bashx; do
  tok_fixture "r6c$mode"; F=$T/r6c$mode
  mapfile -t pargs < <(PREP_ARGS "$F")
  printf 'set -x\n' > "$F/benv.sh"
  case "$mode" in
    shellopts) run "$F/prep.out" env SHELLOPTS=xtrace PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-921
               run "$F/pub.out" env SHELLOPTS=xtrace PATH="$T/shim:$PATH" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" ;;
    bashenv)   run "$F/prep.out" env BASH_ENV="$F/benv.sh" PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-921
               run "$F/pub.out" env BASH_ENV="$F/benv.sh" PATH="$T/shim:$PATH" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" ;;
    bashx)     run "$F/prep.out" env PATH="$T/shim:$PATH" bash -x "$LANDER" prepare "${pargs[@]}" --item-id CON-921
               run "$F/pub.out" env PATH="$T/shim:$PATH" bash -x "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" ;;
  esac
  n=$(tokcount "$F/prep.out" "$F/pub.out"); ne=$(evtok "$F/ev")
  if [ "$RC" -eq 0 ] && landed_all "$F" && [ "$n" -eq 0 ] && [ "$ne" -eq 0 ]; then
    ok "R6-C-$mode tracing from the caller: prepare and publish exit 0, all 9 landed, 0 output lines and 0 evidence files hold the credential"
  else bad "R6-C-$mode (rc=$RC token lines=$n evidence files=$ne)"; grep -m3 -- "$TOK" "$F/prep.out" "$F/pub.out" | sed "s/$TOK/<TOK>/g; s/^/    | /" || true; fi
done

# ============================================ R6-C4 an exported function or a BASH_ENV function named git never runs
fixture r6c4; F=$T/r6c4
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/prep.out" env "BASH_FUNC_git%%=() { : > '$F/expfn.ran'; command git \"\$@\"; }" PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-922
if [ "$RC" -eq 0 ] && [ ! -e "$F/expfn.ran" ]; then ok "R6-C4 an exported function git from the environment never runs (prepare exits 0)"
else bad "R6-C4 exported function (rc=$RC, ran: $([ -e "$F/expfn.ran" ] && echo yes || echo no))"; sed 's/^/    | /' "$F/prep.out"; fi
fixture r6c4b; F=$T/r6c4b
mapfile -t pargs < <(PREP_ARGS "$F")
printf 'git() { : > %q; command git "$@"; }\n' "$F/benvfn.ran" > "$F/benv.sh"
run "$F/prep.out" env BASH_ENV="$F/benv.sh" PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-922
if [ "$RC" -eq 0 ] && [ ! -e "$F/benvfn.ran" ]; then ok "R6-C4b a function git defined by a BASH_ENV file never runs (prepare exits 0)"
else bad "R6-C4b BASH_ENV function (rc=$RC, ran: $([ -e "$F/benvfn.ran" ] && echo yes || echo no))"; sed 's/^/    | /' "$F/prep.out"; fi
# control: the same function DOES run in a plain bash with that environment (the fixture works)
env "BASH_FUNC_git%%=() { : > '$F/ctlfn.ran'; command git \"\$@\"; }" bash -c 'git --version >/dev/null' || true
if [ -e "$F/ctlfn.ran" ]; then ok "R6-C4 control: the exported function runs in a plain bash"; else bad "R6-C4 control: the exported function did not run in a plain bash"; fi

# ============================================ R6-C5 shell options from the caller (bash -O, BASHOPTS) do not change a check
for mode in dashO bashopts; do
  base_fixture "r6c5$mode"; F=$T/r6c5$mode
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
  printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-923 minted\\n" > docs/TRACKER.FAKE; echo CON-923\n' > "$F/m.sh"; chmod +x "$F/m.sh"
  mapfile -t pargs < <(PREP_ARGS "$F")
  if [ "$mode" = dashO ]; then run "$F/out" env PATH="$T/shim:$PATH" bash -O nocasematch "$LANDER" prepare "${pargs[@]}" --mint-cmd "$F/m.sh"
  else run "$F/out" env BASHOPTS=nocasematch PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --mint-cmd "$F/m.sh"; fi
  refused "R6-C5-$mode nocasematch from the caller: a mint writing docs/TRACKER.FAKE is still refused (tracker path docs/tracker.fake)" 1 \
    'the mint command changed a path it may not change \(A docs/TRACKER\.FAKE\)' "$F/out"
done

# ============================================ R6-A1 a folded Roadmap-Item value is refused (prepare and publish)
for shape in emptykey continued; do
  base_fixture "r6a1$shape"; F=$T/r6a1$shape
  if [ "$shape" = emptykey ]; then vc "$F" v1.txt 'feat: one\n\nRoadmap-Item:\n CON-931\n'
  else vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-931\n\tcontinued\n'; fi
  mkbundle "$F"
  run "$F/out" prepare_raw "$F" --item-id CON-931
  refused "R6-A1-$shape a vehicle commit with a folded Roadmap-Item value is refused at prepare" 1 \
    "lacks a single real Roadmap-Item trailer \(found: 'a folded \(continued\) Roadmap-Item value" "$F/out"
done
# control: git itself parses the folded form as ONE trailer CON-931 (so the case is the one git would accept)
F=$T/r6a1emptykey
if [ "$(rimtrailers "$F/seed" vehicle)" = CON-931 ]; then ok "R6-A1 control: git parses the folded form as the single trailer CON-931"
else bad "R6-A1 control: git parses '$(rimtrailers "$F/seed" vehicle)'"; fi
fixture r6a1p; F=$T/r6a1p
run "$F/prep.out" prepare_raw "$F" --item-id CON-932; succeeded "R6-A1p prepare exits 0" "$F/prep.out"
C=$F/work/constitution
printf 'late\n' > "$C/late.txt"; g "$C" add late.txt
printf 'late change\n\nRoadmap-Item:\n CON-932\n' > "$F/msg"; g "$C" -c core.hooksPath=/dev/null commit -q --cleanup=verbatim -F "$F/msg"
run "$F/pub.out" publish "$F"
refused "R6-A1p a folded trailer committed after prepare is refused at publish" 1 \
  "lacks a single real Roadmap-Item trailer \(found: 'a folded \(continued\) Roadmap-Item value" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "R6-A1p nothing was pushed"; else bad "R6-A1p a remote moved"; fi

# ============================================ R6-A2 newness over commit messages: folded, any key spelling, any case, any mention
r6a2() { # r6a2 <name> <vehicle message (printf %b)> <minted id>
  base_fixture "$1"; F=$T/$1
  vc "$F" v0.txt "$2"; vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
  mkmint "$F/m.sh" "$3 minted" "$3"
  run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
}
r6a2 r6a2fold 'feat: zero\n\nRoadmap-Item:\n CON-777\n' CON-777
refused "R6-A2 folded: CON-777 on a continuation line of a vehicle trailer makes CON-777 not new" 1 'CON-777 already appears in a commit message reachable from main or the vehicle' "$F/out"
r6a2 r6a2case 'feat: zero\n\nroadmap-item: con-777\n' CON-777
refused "R6-A2 case: a lower-case 'roadmap-item: con-777' makes CON-777 not new" 1 'CON-777 already appears in a commit message reachable' "$F/out"
r6a2 r6a2ws 'feat: zero\n\nRoadmap-Item  :   CON-0777  \n' CON-777
refused "R6-A2 spacing: 'Roadmap-Item  :   CON-0777' makes CON-777 not new" 1 'CON-777 already appears in a commit message reachable' "$F/out"
r6a2 r6a2body 'feat: zero, see CON-777 for the follow-up\n\nRoadmap-Item: CON-050\n' CON-777
refused "R6-A2 mention: 'see CON-777' in a subject makes CON-777 not new" 1 'CON-777 already appears in a commit message reachable' "$F/out"
r6a2 r6a2ctl 'feat: zero, see CON-777 for the follow-up\n\nRoadmap-Item: CON-050\n' CON-778
succeeded "R6-A2 control: with the same vehicle, CON-778 is new and accepted" "$F/out"

# ============================================ R6-B newness over the vehicle tree (every unpushed vehicle commit)
vt() { # vt <F> <path> <content (printf %b)> <message (printf %b)>: one vehicle commit writing <path>
  local F=$1
  mkdir -p "$F/seed/$(dirname "$2")"; printf '%b' "$3" > "$F/seed/$2"; g "$F/seed" add -- "$2"
  printf '%b' "$4" > "$F/msg"; g "$F/seed" commit -q --cleanup=verbatim -F "$F/msg"
}
r6b() { # r6b <name> <minted id> <mode tip|removed|lower|ctl>
  base_fixture "$1"; F=$T/$1
  case "$3" in
    tip)     vt "$F" docs/items/a.md 'CON-777 row\n' 'feat: items\n\nRoadmap-Item: CON-050\n' ;;
    removed) vt "$F" docs/items/a.md 'CON-777 row\n' 'feat: items\n\nRoadmap-Item: CON-050\n'
             vt "$F" docs/items/a.md 'other row\n' 'feat: items again\n\nRoadmap-Item: CON-050\n' ;;
    lower)   vt "$F" docs/items/a.md 'con-0777 row\n' 'feat: items\n\nRoadmap-Item: CON-050\n' ;;
    ctl)     vt "$F" docs/items/a.md 'CON-776 row\n' 'feat: items\n\nRoadmap-Item: CON-050\n' ;;
  esac
  mkbundle "$F"
  printf '#!/usr/bin/env bash\nmkdir -p docs; printf "%s minted\\n" >> docs/tracker.fake; echo %s\n' "$2" "$2" > "$F/m.sh"; chmod +x "$F/m.sh"
  local -a bpa=(); mapfile -t bpa < <(PREP_ARGS "$F")
  run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/tracker.fake docs/items/*" -- prepare "${bpa[@]}" --mint-cmd "$F/m.sh"
}
r6b r6btip CON-777 tip
refused "R6-B tip: the vehicle tip's tracker file holds CON-777: not new" 1 'CON-777 already appears in docs/items/a\.md in vehicle commit [0-9a-f]+' "$F/out"
r6b r6brem CON-777 removed
refused "R6-B removed: a vehicle commit added CON-777 and a later one removed it: not new" 1 'CON-777 already appears in docs/items/a\.md in vehicle commit [0-9a-f]+' "$F/out"
r6b r6blow CON-777 lower
refused "R6-B case: the vehicle tracker holds con-0777: not new" 1 'CON-777 already appears in docs/items/a\.md in vehicle commit' "$F/out"
r6b r6bctl CON-777 ctl
if [ "$RC" -eq 0 ] && [ "$(nlines "$F/work/constitution/docs/items/a.md")" = 1 ]; then ok "R6-B control: the vehicle tracker holds CON-776 only, CON-777 is new and accepted, the vehicle file landed"
else bad "R6-B control (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi
base_fixture r6bmain; F=$T/r6bmain
seed_main_file "$F" docs/tracker.fake 'con-777 old\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R6-B case at main: the tracker at main holds con-777: not new" 1 'CON-777 already appears in docs/tracker\.fake before the mint' "$F/out"

# ============================================ R6-D verify re-checks the state and the landed head
fixture r6d1; F=$T/r6d1
run "$F/prep.out" prepare_raw "$F" --item-id CON-941; succeeded "R6-D1 prepare exits 0" "$F/prep.out"
C=$F/work/constitution; mb=$(g "$C" rev-parse refs/land/main_before); lh=$(g "$C" rev-parse refs/land/landed)
g "$C" update-ref refs/heads/main "$mb"
run "$F/ver.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
refused "R6-D1 local main reset to the prepared base, never published: verify exits 1" 1 "local main does not contain the landed vehicle head $lh" "$F/ver.out"
fixture r6d2; F=$T/r6d2
run "$F/prep.out" prepare_raw "$F" --item-id CON-942; succeeded "R6-D2 prepare exits 0" "$F/prep.out"
C=$F/work/constitution; lh=$(g "$C" rev-parse refs/land/landed)
run "$F/ver.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
if [ "$RC" -eq 1 ] && grep -q "landed vehicle head: \`$lh\`" "$F/ev/verify.md" && [ "$(grep -c '| FAIL | no |' "$F/ev/verify.md")" -eq 9 ]; then
  ok "R6-D2 prepared but not published: verify exits 1, verify.md names the landed head and 9 rows 'FAIL | no'"
else bad "R6-D2 (rc=$RC)"; sed 's/^/    | /' "$F/ev/verify.md" 2>/dev/null || true; fi
run "$F/pub.out" publish "$F"; succeeded "R6-D2 publish exits 0" "$F/pub.out"
run "$F/ver2.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
if [ "$RC" -eq 0 ] && [ "$(grep -c '| PASS | yes |' "$F/ev/verify.md")" -eq 9 ] && [ "$(grep -c $'\tPASS\tyes$' "$F/ev/verify.tsv")" -eq 9 ]; then
  ok "R6-D2 control: after publish, verify exits 0 with 9 rows 'PASS | yes'"
else bad "R6-D2 control (rc=$RC)"; sed 's/^/    | /' "$F/ver2.out"; fi
g "$C" update-ref refs/land/landed "$(g "$C" rev-parse refs/land/main_before)"
run "$F/ver3.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
refused "R6-D3 verify refuses a prepare state that no longer matches the refs" 2 'prepare state does not match git: landed_vehicle_head differs from refs/land/landed' "$F/ver3.out"

# ============================================ R6-F the clone path is swapped for a symlink while git init runs
fixture r6f; F=$T/r6f
C=$F/work/constitution
mkdir -p "$F/rshim" "$F/outside"
cat > "$F/rshim/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = init ] && [ ! -e "$F/swap.done" ]; then
    : > "$F/swap.done"; mv -- "$C" "$C.moved"; ln -s "$F/outside" "$C"; break
  fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$F/rshim/git"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" env PATH="$F/rshim:$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-961
refused "R6-F the clone path swapped for a symlink during git init: prepare exits 1" 1 'the clone path changed while the clone was created' "$F/out"
if [ -e "$F/swap.done" ] && [ -z "$(ls -A "$F/outside")" ] && no_remote_moved "$F" "$(BASE_OF "$F")"; then
  ok "R6-F nothing was written outside the workdir and no remote moved (control: the shim did swap the path)"
else bad "R6-F outside dir holds: $(ls -A "$F/outside" | tr '\n' ' ') swap: $([ -e "$F/swap.done" ] && echo yes || echo no)"; fi

# ============================================ R6-G1 a url.<x>.pushInsteadOf rewrite at publish
fixture r6g1; F=$T/r6g1
run "$F/prep.out" prepare_raw "$F" --item-id CON-971; succeeded "R6-G1 prepare exits 0" "$F/prep.out"
git init -q --bare "$F/decoy.git"; g "$F/seed" push -q "$F/decoy.git" main:refs/heads/main
gccopy "$F"; gcset "$F" "url.$F/decoy.git.pushInsteadOf" "$F/remotes/origin.git"
if [ "$(GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/work/constitution" remote get-url --push origin)" = "$F/decoy.git" ]; then
  ok "R6-G1 control: with that config git rewrites the push URL of origin to the decoy"
else bad "R6-G1 control: the rewrite is not active"; fi
run "$F/pub.out" pub_gc "$F"
refused "R6-G1 pushInsteadOf rewrites origin's push URL: publish refuses before any push" 2 "remote 'origin' push URL\(s\) in the clone differ from --remotes-file; nothing was pushed" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")" && [ "$(git --git-dir="$F/decoy.git" rev-parse main)" = "$(BASE_OF "$F")" ]; then
  ok "R6-G1 no remote and not the decoy received anything"; else bad "R6-G1 something moved"; fi

# ============================================ R6-G3 a commit encoding header and a non-UTF-8 message are kept
base_fixture r6g3; F=$T/r6g3
printf 'enc\n' > "$F/seed/enc.txt"; g "$F/seed" add enc.txt
printf 'feat: caf\351 au lait\n\nCorps en ISO-8859-1: \351t\351.\n\nRoadmap-Item: CON-050\n' > "$F/msg"
g "$F/seed" -c i18n.commitEncoding=ISO-8859-1 commit -q --cleanup=verbatim -F "$F/msg"
mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-981
C=$F/work/constitution
if [ "$RC" -eq 0 ]; then
  lh=$(g "$C" rev-parse refs/land/landed)
  orig=$(rawmsg "$F/seed" vehicle); new=$(rawmsg "$C" "$lh")
  hdr=$(g "$C" cat-file commit "$lh" | sed -n '1,/^$/p')
  ohdr=$(g "$F/seed" cat-file commit vehicle | sed -n '1,/^$/p')
  if [ "${orig//CON-050/CON-981}" = "$new" ] && grep -qx 'encoding ISO-8859-1' <<<"$hdr" \
     && [ "$(grep -v '^parent ' <<<"$hdr")" = "$(grep -v '^parent ' <<<"$ohdr")" ] && [[ "$orig" == *$'\351'* ]]; then
    ok "R6-G3 encoding ISO-8859-1 kept, message bytes equal except the id, header lines equal except parent"
  else bad "R6-G3 encoding / message bytes differ"; fi
else bad "R6-G3 prepare (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi

if [ "${LANDER_TEST_R6_ONLY:-0}" = 1 ]; then
  if push_log_clean || [ ! -s "$PUSHLOG" ]; then ok "SH2-R6 every push of the round-6 cases is plain"; else bad "SH2-R6 pushes of the round-6 cases"; fi
  printf '\nRESULT pass=%d fail=%d (round-6 cases only)\n' "$PASS" "$FAIL"
  if [ "$FAIL" -eq 0 ]; then exit 0; else exit 1; fi
fi

# ##################################################################### round 5
# The class inventory is docs/qa/land_vehicle_r5_2026_11_13/class_inventory.md. Every
# case asserts the exit code and the message; where a fixture could pass for the wrong
# reason, a control shows the fixture really does what it claims.

# ============================================ R5-K01 / R5-R04 (F1) clone main moves during the pushes
# a gitflic pre-receive hook (the first remote pushed) commits an UNTRAILERED change into the clone
fixture r5k; F=$T/r5k
run "$F/prep.out" prepare_raw "$F" --item-id CON-904; succeeded "R5-K01 prepare exits 0" "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
cat > "$F/remotes/gitflic.git/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
cat > /dev/null
$(declare -f hg)
REALGIT=$REALGIT
[ -e "$F/race.done" ] && exit 0
: > "$F/race.done"
printf 'unreviewed\n' > "$C/unreviewed.txt"
hg -C "$C" add unreviewed.txt && hg -C "$C" -c core.hooksPath=/dev/null commit -q -m "UNREVIEWED change, no trailer" >/dev/null 2>&1
exit 0
EOF
chmod +x "$F/remotes/gitflic.git/hooks/pre-receive"
run "$F/pub.out" publish "$F"
U=$(g "$C" rev-parse main)
refused "R5-K01 a commit made in the clone during the pushes: publish exits 1" 1 'clone main moved during publish' "$F/pub.out"
if [ -e "$F/race.done" ] && [ "$U" != "$L" ] && [ "$(atcount "$F" "$L")" = 9 ] && [ "$(atcount "$F" "$U")" = 0 ]; then
  ok "R5-K01 all 9 remotes got the checked sha, 0 got the moved main (control: the hook did move clone main)"
else bad "R5-K01 pushed sha (at checked: $(atcount "$F" "$L"), at moved: $(atcount "$F" "$U"), moved: $([ "$U" != "$L" ] && echo yes || echo no))"; fi
run "$F/pub2.out" publish "$F"
refused "R5-K01 publish again refuses the unreviewed commit, with the prepare-again hint" 1 'lacks a single real Roadmap-Item trailer.*run prepare again in a new workdir' "$F/pub2.out"
if [ "$(atcount "$F" "$U")" = 0 ]; then ok "R5-K01 the unreviewed commit reached no remote"; else bad "R5-K01 the unreviewed commit reached a remote"; fi

# ============================================ R5-R04b (F1) a remote URL re-pointed in the clone during the pushes
fixture r5b; F=$T/r5b
run "$F/prep.out" prepare_raw "$F" --item-id CON-905; succeeded "R5-R04b prepare exits 0" "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
git init -q --bare "$F/decoy.git"; g "$F/seed" push -q "$F/decoy.git" main:refs/heads/main
cat > "$F/remotes/gitflic.git/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
cat > /dev/null
$(declare -f hg)
REALGIT=$REALGIT
[ -e "$F/race.done" ] && exit 0
: > "$F/race.done"
hg -C "$C" config remote.origin.url "$F/decoy.git"
exit 0
EOF
chmod +x "$F/remotes/gitflic.git/hooks/pre-receive"
run "$F/pub.out" publish "$F"
refused "R5-R04b origin re-pointed after the first push: refused, and the message names the remotes already pushed" 2 \
  "remote 'origin' fetch URL in the clone differs from --remotes-file; this run already pushed the checked main to: gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w; no further remote is pushed" "$F/pub.out"
if [ -e "$F/race.done" ] && [ "$(git --git-dir="$F/decoy.git" rev-parse main)" = "$(BASE_OF "$F")" ] \
   && [ "$(rmain "$F" origin)" = "$(BASE_OF "$F")" ] && [ "$(atcount "$F" "$L")" = 8 ]; then
  ok "R5-R04b the decoy and origin got nothing, the other 8 got the checked sha (control: the hook re-pointed origin)"
else bad "R5-R04b decoy/origin (decoy main $(git --git-dir="$F/decoy.git" rev-parse main), at checked $(atcount "$F" "$L"))"; fi
g "$C" config remote.origin.url "$F/remotes/origin.git"
run "$F/pub2.out" publish "$F"
if [ "$RC" -eq 0 ] && [ "$(atcount "$F" "$L")" = 9 ] && [ "$(grep -c '| up-to-date |' "$F/ev/publish.md")" -eq 8 ] && grep -q '| origin | pushed |' "$F/ev/publish.md"; then
  ok "R5-R04b after the URL is fixed, publish again pushes origin only (8 up-to-date)"
else bad "R5-R04b re-run (rc=$RC)"; sed 's/^/    | /' "$F/pub2.out"; fi

# ============================================ R5-F2 the minted id must be new (every tracker file, every trailer)
# F2a: the id is in a tracker file that the mint did not touch (the mint adds another file)
base_fixture r5f2a; F=$T/r5f2a
seed_main_file "$F" docs/tracker.fake 'CON-100 old item\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\nmkdir -p docs/items; printf "CON-100 item\\n" > docs/items/CON-100.md; echo CON-100\n' > "$F/mint_add.sh"; chmod +x "$F/mint_add.sh"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/tracker.fake docs/items/*" -- prepare "${pargs[@]}" --mint-cmd "$F/mint_add.sh"
refused "R5-F2a an id already in an untouched tracker file is refused" 1 'CON-100 already appears in docs/tracker\.fake before the mint' "$F/out"
base_fixture r5f2ac; F=$T/r5f2ac
seed_main_file "$F" docs/tracker.fake 'CON-100 old item\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\nmkdir -p docs/items; printf "CON-101 item\\n" > docs/items/CON-101.md; echo CON-101\n' > "$F/mint_add.sh"; chmod +x "$F/mint_add.sh"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/tracker.fake docs/items/*" -- prepare "${pargs[@]}" --mint-cmd "$F/mint_add.sh"
if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$F/work/constitution" "$(hash_by_subject "$F/work/constitution" 'feat: one')")" = CON-101 ]; then
  ok "R5-F2a control: a new id CON-101 in a new file matching the glob docs/items/* is accepted"
else bad "R5-F2a control (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi
# F2b: the id is a Roadmap-Item value of a commit on main, or of a vehicle commit
fixture r5f2b; F=$T/r5f2b
mkmint "$F/m.sh" 'CON-001 minted' CON-001
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F2b an id that is a trailer of a commit on main is refused" 1 'CON-001 already appears in a commit message reachable from main or the vehicle' "$F/out"
base_fixture r5f2bv; F=$T/r5f2bv
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-123\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-123 minted' CON-123
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F2b an id that is a trailer of a vehicle commit is refused" 1 'CON-123 already appears in a commit message reachable from main or the vehicle' "$F/out"
fixture r5f2bc; F=$T/r5f2bc
mkmint "$F/m.sh" 'CON-003 minted' CON-003
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
succeeded "R5-F2b control: a new id CON-003 is accepted" "$F/out"
# F2c: a tracker file other than the one the mint wrote (glob docs/*.db)
base_fixture r5f2c; F=$T/r5f2c
seed_main_file "$F" docs/workable_items.db 'CON-123 old item\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-123 minted\\n" > docs/workable_item.db; echo CON-123\n' > "$F/m.sh"; chmod +x "$F/m.sh"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/*.db" -- prepare "${pargs[@]}" --mint-cmd "$F/m.sh"
refused "R5-F2c the id in another tracker file matching the glob is refused, naming that file" 1 'CON-123 already appears in docs/workable_items\.db before the mint' "$F/out"
# F2z: leading zeros are ignored by the newness check
for z in 'CON-77' 'CON-0077'; do
  base_fixture "r5f2z$z"; F=$T/r5f2z$z
  seed_main_file "$F" docs/tracker.fake "$z legacy\\n"
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
  mkmint "$F/m.sh" 'CON-077 minted' CON-077
  run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
  refused "R5-F2z the tracker holds $z: CON-077 is not new" 1 'CON-077 already appears in docs/tracker\.fake before the mint' "$F/out"
done

# ============================================ R5-F3 a tag object as --head; a placeholder after prepare
base_fixture r5f3a; F=$T/r5f3a
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'
g "$F/seed" tag -a -m "vehicle tag" vt vehicle
mkbundle "$F" refs/tags/vt
g "$F/seed" rev-parse vt > "$F/head"
run "$F/out" prepare_raw "$F" --item-id CON-906
refused "R5-F3a an annotated tag object as --head is refused" 1 'is a tag object, not a commit' "$F/out"
if [ "$(g "$F/seed" cat-file -t "$(cat "$F/head")")" = tag ]; then ok "R5-F3a control: the --head given is a tag object"; else bad "R5-F3a control: the --head given is a tag object"; fi
fixture r5f3b; F=$T/r5f3b
run "$F/prep.out" prepare_raw "$F" --item-id CON-907
C=$F/work/constitution
{ printf 'd\n' > "$C/derived.txt" && g "$C" add derived.txt && g "$C" commit -q -m "derived" -m "Roadmap-Item: CON-050"; } 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "R5-F3b a commit after prepare whose trailer is the placeholder CON-050 is refused" 1 "lacks a single real Roadmap-Item trailer \\(found: 'CON-050'" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "R5-F3b no remote moved"; else bad "R5-F3b no remote moved"; fi

# ============================================ R5-F4 ambient log.showSignature: author and committer lines kept
base_fixture r5f4; F=$T/r5f4
GIT_AUTHOR_NAME="Ann Author" GIT_AUTHOR_EMAIL=ann@author.invalid GIT_AUTHOR_DATE="2001-02-03T04:05:06+05:30" \
  vc "$F" f4.txt 'feat f4\n\nRoadmap-Item: CON-050\n'
raw=$(g "$F/seed" cat-file commit HEAD)
signed=$(awk 'h==0 && /^$/ {h=1} h==0 && /^committer / {print; print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " "; print " ZmFrZQ=="; print " -----END PGP SIGNATURE-----"; next} {print}' <<<"$raw" \
  | g "$F/seed" hash-object -t commit -w --stdin)
g "$F/seed" update-ref refs/heads/vehicle "$signed"
mkbundle "$F"
printf '#!/usr/bin/env bash\necho call >> %q\ncat > /dev/null\nexit 1\n' "$F/gpg.calls" > "$F/fakegpg"; chmod +x "$F/fakegpg"
gccopy "$F"; gcset "$F" log.showSignature true; gcset "$F" gpg.program "$F/fakegpg"
run "$F/prep.out" prep_gc "$F" --item-id CON-908
C=$F/work/constitution; n=$(hash_by_subject "$C" 'feat f4')
oh=$(g "$F/seed" cat-file commit "$signed" | grep -E '^(author|committer) ' || true)
nh=$( [ -n "$n" ] && g "$C" cat-file commit "$n" | grep -E '^(author|committer) ' || true)
c0=$(nlines "$F/gpg.calls")
GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/seed" log -1 vehicle > /dev/null 2>&1 || true
c1=$(nlines "$F/gpg.calls")
if [ "$RC" -eq 0 ] && [ -n "$n" ] && [ "$n" != "$signed" ] && [ -n "$oh" ] && [ "$oh" = "$nh" ] && [ "$c0" -eq 0 ] && [ "$c1" -ge 1 ]; then
  ok "R5-F4 with log.showSignature=true the author and committer lines are kept byte for byte (control: git log calls gpg)"
else bad "R5-F4 showSignature (rc=$RC gpg calls by the lander=$c0, by the control=$c1)"; printf '%s\n--\n%s\n' "$oh" "$nh" | sed 's/^/    | /'; fi

# ============================================ R5-F5 ambient push.pushOption reaches no server
fixture r5f5; F=$T/r5f5
run "$F/prep.out" prepare_raw "$F" --item-id CON-909
git --git-dir="$F/remotes/m3w.git" config receive.advertisePushOptions true
# shellcheck disable=SC2016 # the generated script expands these at its own run time
printf '#!/usr/bin/env bash\ncat > /dev/null\nprintf "%%s\\n" "${GIT_PUSH_OPTION_COUNT:-0}" >> %q\n' "$F/opts.log" > "$F/remotes/m3w.git/hooks/pre-receive"
chmod +x "$F/remotes/m3w.git/hooks/pre-receive"
gccopy "$F"; gcset "$F" push.pushOption SECRETOPT
run "$F/pub.out" pub_gc "$F"
git init -q --bare "$F/ctl.git"; git --git-dir="$F/ctl.git" config receive.advertisePushOptions true
# shellcheck disable=SC2016 # the generated script expands these at its own run time
printf '#!/usr/bin/env bash\ncat > /dev/null\nprintf "%%s\\n" "${GIT_PUSH_OPTION_COUNT:-0}" >> %q\n' "$F/ctl.log" > "$F/ctl.git/hooks/pre-receive"
chmod +x "$F/ctl.git/hooks/pre-receive"
GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/seed" push -q "$F/ctl.git" main:refs/heads/main 2>/dev/null || true
if [ "$RC" -eq 0 ] && landed_all "$F" && [ "$(cat "$F/opts.log" 2>/dev/null)" = 0 ] && [ "$(cat "$F/ctl.log" 2>/dev/null)" = 1 ]; then
  ok "R5-F5 push.pushOption in the caller config: 9/9 landed, m3w saw 0 push options (control: a plain push sends 1)"
else bad "R5-F5 push options (rc=$RC m3w=$(cat "$F/opts.log" 2>/dev/null) control=$(cat "$F/ctl.log" 2>/dev/null))"; fi

# ============================================ R5-F6 init templates (global init.templateDir, GIT_TEMPLATE_DIR)
fixture r5f6; F=$T/r5f6
mkdir -p "$F/tpl/info" "$F/outside"; printf 'marker\n' > "$F/outside/marker.txt"
printf '[core]\n\tworktree = %s\n' "$F/outside" > "$F/tpl/config"
printf 'docs/\n' > "$F/tpl/info/exclude"
gccopy "$F"; gcset "$F" init.templateDir "$F/tpl"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/prep.out" env GIT_TEMPLATE_DIR="$F/tpl" GIT_CONFIG_GLOBAL="$F/gc" PATH="$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --mint-cmd "$F/mint.sh"
C=$F/work/constitution
wt=$(git config --file "$C/.git/config" --get core.worktree 2>/dev/null || echo unset)
outl=$(cd "$F/outside" && ls -A)
GIT_CONFIG_GLOBAL="$F/gc" git init -q "$F/ctlrepo" 2>/dev/null || true
cwt=$(git config --file "$F/ctlrepo/.git/config" --get core.worktree 2>/dev/null || echo unset)
if [ "$RC" -eq 0 ] && [ "$wt" = unset ] && [ ! -e "$C/.git/info/exclude" ] && [ "$outl" = marker.txt ] && [ -s "$C/v2.txt" ] && [ "$cwt" = "$F/outside" ]; then
  ok "R5-F6 the clone gets no template (no core.worktree, no info/exclude, outside dir untouched; control: git init copies it)"
else bad "R5-F6 template (rc=$RC worktree=$wt outside=[$outl] control=$cwt)"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi

# ============================================ R5-F7 an option value that looks like an option
run "$T/r5f7a.out" lv prepare --bundle x --evidence-dir -h
refused "R5-F7 '--evidence-dir -h' is a missing value, not help" 2 'option --evidence-dir needs a value' "$T/r5f7a.out"
run "$T/r5f7b.out" lv prepare --key-prefix --help
refused "R5-F7 '--key-prefix --help' is a missing value, not help" 2 'option --key-prefix needs a value' "$T/r5f7b.out"
run "$T/r5f7c.out" lv publish --workdir "$T" -h
if [ "$RC" -eq 0 ] && grep -q 'REMOTES ARE CHECKED AT EVERY USE' "$T/r5f7c.out"; then ok "R5-F7 control: -h in option position prints the help"; else bad "R5-F7 control: help (rc=$RC)"; fi

# ============================================ R5-F9 tracker patterns need a literal first directory
base_fixture r5f9; F=$T/r5f9
for p in '*' 'docs' '*/x' './x'; do
  run "$F/out" env LANDER_TRACKER_PATHS="$p" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt"
  refused "R5-F9 tracker pattern '$p' refused" 2 'each pattern needs a literal first directory' "$F/out"
done
run "$F/out" env LANDER_TRACKER_PATHS="../docs/x" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt"
refused "R5-F9 tracker pattern '../docs/x' refused" 2 "hold no '\\.\\.'" "$F/out"
run "$F/out" env LANDER_TRACKER_PATHS="/abs/x" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt"
refused "R5-F9 tracker pattern '/abs/x' refused" 2 'patterns are relative to the clone root' "$F/out"
run "$F/out" env LANDER_TRACKER_PATHS="docs/*" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt"
refused "R5-F9 control: 'docs/*' passes the pattern check (fails later: no clone)" 2 'no clone at' "$F/out"

# ============================================ R5-F10 ids with a leading zero beyond three digits
fixture r5f10; F=$T/r5f10
run "$F/out" prepare_raw "$F" --item-id CON-0100
refused "R5-F10 --item-id CON-0100 refused" 2 'item-id must match' "$F/out"
mkmint "$F/m.sh" 'CON-0100 minted' CON-0100
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F10 a mint printing CON-0100 is refused" 1 'mint did not print an id matching' "$F/out"

# ============================================ R5-F11 a CRLF remotes file
base_fixture r5f11; F=$T/r5f11
sed 's/$/\r/' "$F/remotes.txt" > "$F/crlf.txt"
run "$F/out" lv verify --workdir "$F/work" --remotes-file "$F/crlf.txt"
if [ "$RC" -eq 2 ] && grep -q 'remotes file line 1: holds a control character other than TAB' "$F/out" && ! grep -qF "$F/remotes" "$F/out"; then
  ok "R5-F11 a CRLF remotes file: exit 2, line 1 named, no URL shown"
else bad "R5-F11 CRLF remotes file (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi

# ============================================ R5-F13 a control character inside a trailer value
base_fixture r5f13; F=$T/r5f13
vc "$F" v1.txt 'feat f13\n\nRoadmap-Item: CON-9\r05\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-913
refused "R5-F13 a vehicle trailer CON-9<CR>05 is refused at prepare" 1 "lacks a single real Roadmap-Item trailer \\(found: 'CON-9\\?05'" "$F/out"
fixture r5f13b; F=$T/r5f13b
run "$F/prep.out" prepare_raw "$F" --item-id CON-914
C=$F/work/constitution
printf 'derived\n\nRoadmap-Item: CON-9\r05\n' > "$F/msg13"
{ printf 'd\n' > "$C/derived.txt" && g "$C" add derived.txt && g "$C" commit -q --cleanup=verbatim -F "$F/msg13"; } 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "R5-F13 a derived commit with the trailer CON-9<CR>05 is refused at publish" 1 "lacks a single real Roadmap-Item trailer \\(found: 'CON-9\\?05'" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "R5-F13 no remote moved"; else bad "R5-F13 no remote moved"; fi

# ============================================ R5-TC ambient trailer config (core.commentChar, trailer.separators)
for tc in commentchar separators; do
  fixture "r5tc$tc"; F=$T/r5tc$tc
  gccopy "$F"
  if [ "$tc" = commentchar ]; then gcset "$F" core.commentChar R; else gcset "$F" trailer.separators '='; fi
  run "$F/prep.out" prep_gc "$F" --mint-cmd "$F/mint.sh"
  C=$F/work/constitution
  msgs=$(g "$C" log --format=%B main -3 2>/dev/null || true)
  ctl=$(printf 'feat\n\nRoadmap-Item: CON-050\n' | GIT_DIR=/nonexistent GIT_CONFIG_GLOBAL="$F/gc" git interpret-trailers --parse 2>/dev/null || true)
  if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$C" "$(hash_by_subject "$C" 'feat: one')")" = CON-777 ] \
     && [ "$(rimtrailers "$C" "$(hash_by_subject "$C" 'feat: two')")" = CON-777 ] && ! grep -Eq 'CON-050|CON-PENDING' <<<"$msgs" && [ -z "$ctl" ]; then
    ok "R5-TC $tc in the caller config does not change the trailer parse (control: interpret-trailers with it finds none)"
  else bad "R5-TC $tc (rc=$RC control=[$ctl])"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
done

# ============================================ R5-N1 merge config: strategy, merge options, merge driver
for n1 in twohead mergeoptions; do
  fixture "r5n1$n1"; F=$T/r5n1$n1
  gccopy "$F"
  if [ "$n1" = twohead ]; then gcset "$F" pull.twohead ours; else gcset "$F" branch.main.mergeOptions '-s ours'; fi
  run "$F/prep.out" prep_gc "$F" --mint-cmd "$F/mint.sh"
  C=$F/work/constitution
  git init -q "$F/ctl"; printf 'b\n' > "$F/ctl/b.txt"; g "$F/ctl" add b.txt; g "$F/ctl" commit -q -m b
  g "$F/ctl" checkout -q -b side; printf 's\n' > "$F/ctl/s.txt"; g "$F/ctl" add s.txt; g "$F/ctl" commit -q -m s
  g "$F/ctl" checkout -q main; printf 'm\n' > "$F/ctl/m.txt"; g "$F/ctl" add m.txt; g "$F/ctl" commit -q -m m
  GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/ctl" merge -q --no-edit side >/dev/null 2>&1 || true
  if [ "$RC" -eq 0 ] && g "$C" cat-file -e main:v1.txt 2>/dev/null && g "$C" cat-file -e main:v2.txt 2>/dev/null && [ ! -e "$F/ctl/s.txt" ]; then
    ok "R5-N1 $n1 ours in the caller config: the vehicle content is merged (control: a plain git merge drops it)"
  else bad "R5-N1 $n1 (rc=$RC ctl s.txt $([ -e "$F/ctl/s.txt" ] && echo present || echo absent))"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
done
# N1c: a merge driver named by an in-tree .gitattributes and defined in the caller config
for n1c in driver plain; do
  base_fixture "r5n1c$n1c"; F=$T/r5n1c$n1c
  g "$F/seed" checkout -q main
  printf 'l1\nl2\nl3\nl4\nl5\n' > "$F/seed/c.txt"; printf 'c.txt merge=lvdrv\n' > "$F/seed/.gitattributes"
  g "$F/seed" add c.txt .gitattributes; g "$F/seed" commit -q -m "c.txt" -m "Roadmap-Item: CON-002"
  for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
  g "$F/seed" checkout -q -B vehicle main
  printf 'l1\nl2\nl3\nl4\nL5-vehicle\n' > "$F/seed/c.txt"; g "$F/seed" add c.txt
  g "$F/seed" commit -q -m "feat n1c" -m "Roadmap-Item: CON-050"; mkbundle "$F"
  git clone -q "$F/remotes/origin.git" "$F/mover"
  printf 'L1-mover\nl2\nl3\nl4\nl5\n' > "$F/mover/c.txt"; g "$F/mover" add c.txt; g "$F/mover" commit -q -m "mover" -m "Roadmap-Item: CON-003"
  for r in $REMOTES; do g "$F/mover" push -q "$F/remotes/$r.git" main:refs/heads/main; done
  gccopy "$F"
  # shellcheck disable=SC2016 # the generated script expands these at its own run time
  printf '#!/usr/bin/env bash\necho call >> %q\nprintf "DRIVER\\n" > "$2"\nexit 0\n' "$F/drv.log" > "$F/drv.sh"; chmod +x "$F/drv.sh"
  [ "$n1c" = driver ] && gcset "$F" merge.lvdrv.driver "$F/drv.sh %O %A %B"
  run "$F/prep.out" prep_gc "$F" --item-id CON-850
  C=$F/work/constitution
  if [ "$n1c" = driver ]; then
    refused "R5-N1c a merge driver from the caller config is refused by the merge oracle" 1 'the merge result differs from the same merge computed without your global and system git config' "$F/prep.out"
    if [ -s "$F/drv.log" ] && [ ! -e "$C/.git/land_vehicle.state" ]; then ok "R5-N1c control: the driver really ran; no prepare state"; else bad "R5-N1c control: the driver really ran"; fi
  else
    got=$(g "$C" show main:c.txt 2>/dev/null || true)
    if [ "$RC" -eq 0 ] && [ "$got" = "$(printf 'L1-mover\nl2\nl3\nl4\nL5-vehicle')" ]; then
      ok "R5-N1c control: without the driver the same merge is clean and holds both edits"
    else bad "R5-N1c control merge (rc=$RC got=[$got])"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
  fi
done

# ============================================ R5-N2 a gitlink change hidden by submodule.<name>.ignore=all
base_fixture r5n2; F=$T/r5n2
g "$F/seed" checkout -q main
printf '[submodule "sub"]\n\tpath = sub\n\turl = ./sub\n\tignore = all\n' > "$F/seed/.gitmodules"
g "$F/seed" add .gitmodules
s1=$(g "$F/seed" rev-parse main)
g "$F/seed" update-index --add --cacheinfo "160000,$s1,sub"
g "$F/seed" commit -q -m "submodule sub" -m "Roadmap-Item: CON-002"
for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
g "$F/seed" checkout -q -B vehicle main
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
s2=$(g "$F/seed" rev-parse vehicle)
printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake\ngit update-index --cacheinfo 160000,%s,sub\necho CON-777\n' "$s2" > "$F/m.sh"; chmod +x "$F/m.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-N2 a mint that restages a gitlink hidden by ignore=all is refused" 1 'mint command changed a path it may not change \(M sub\)' "$F/out"
git -C "$F/seed" update-index --cacheinfo "160000,$s2,sub"
ctl=$(git -C "$F/seed" diff-index --cached --raw HEAD 2>/dev/null || true)
git -C "$F/seed" update-index --cacheinfo "160000,$s1,sub"
if [ -z "$ctl" ]; then ok "R5-N2 control: without --ignore-submodules=none git hides the gitlink change"; else bad "R5-N2 control: [$ctl]"; fi

# ============================================ R5-N3 ambient core.sharedRepository
fixture r5n3; F=$T/r5n3
gccopy "$F"; gcset "$F" core.sharedRepository world
# the caller's umask is pinned to 022 here, so the case does not depend on the umask of the shell running the test
old_umask=$(umask); umask 022
run "$F/prep.out" prep_gc "$F" --item-id CON-911
C=$F/work/constitution
m1=$(stat -c %a "$C/.git" 2>/dev/null || echo none); m2=$(stat -c %a "$C/.git/config" 2>/dev/null || echo none)
GIT_CONFIG_GLOBAL="$F/gc" git init -q "$F/ctlrepo" 2>/dev/null || true
c1=$(stat -c %a "$F/ctlrepo/.git" 2>/dev/null || echo none); c2=$(stat -c %a "$F/ctlrepo/.git/config" 2>/dev/null || echo none)
umask "$old_umask"
if [ "$RC" -eq 0 ] && [ "$m1" = 700 ] && [ "$m2" = 600 ] && [ "$c1" = 2775 ] && [ "$c2" = 664 ]; then
  ok "R5-N3 core.sharedRepository=world in the caller config: clone .git 700, config 600 (control: git init gives 2775/664)"
else bad "R5-N3 modes (rc=$RC clone $m1/$m2 control $c1/$c2)"; fi
# R5-N3b (mutant N3c): the files git writes AFTER init (objects, index, logs, refs) must not get
# group or other permission bits either; that needs the pin on every git call, not only on init.
# Control: the same global config, umask 077, init pinned but a commit WITHOUT the pin gives such bits.
nbad=$(find "$C/.git" -perm /077 2>/dev/null | wc -l); nall=$(find "$C/.git" 2>/dev/null | wc -l)
( umask 077; GIT_CONFIG_GLOBAL="$F/gc" git -c core.sharedRepository=false init -q -b main "$F/ctl2" >/dev/null 2>&1
  printf 'x\n' > "$F/ctl2/f"
  GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/ctl2" add f >/dev/null 2>&1
  GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/ctl2" -c user.name=ctl -c user.email=ctl@invalid commit -q -m ctl >/dev/null 2>&1 ) || true
cbad=$(find "$F/ctl2/.git" -perm /077 2>/dev/null | wc -l)
if [ "$RC" -eq 0 ] && [ "$nbad" -eq 0 ] && [ "$nall" -gt 20 ] && [ "$cbad" -gt 0 ]; then
  ok "R5-N3b no entry of the $nall under the clone .git has a group or other bit (control: an unpinned commit under the same config gives $cbad such entries)"
else bad "R5-N3b modes after init (rc=$RC bad=$nbad of $nall control=$cbad)"
  # R5-I (round 6): no `find | head` under pipefail (find gets SIGPIPE and set -e ends the suite)
  badlist=$(find "$C/.git" -perm /077 2>/dev/null || true); sed -n '1,5s/^/    | /p' <<<"$badlist"; fi

# ============================================ R5-RM reviewer mutants of round 4, re-expressed for round 5
# RM02 ambient core.fsmonitor program never runs
fixture r5rm02; F=$T/r5rm02
printf '#!/usr/bin/env bash\necho call >> %q\nexit 1\n' "$F/fsm.log" > "$F/fsm.sh"; chmod +x "$F/fsm.sh"
gccopy "$F"; gcset "$F" core.fsmonitor "$F/fsm.sh"
run "$F/prep.out" prep_gc "$F" --mint-cmd "$F/mint.sh"; r1=$RC
run "$F/pub.out" pub_gc "$F"; r2=$RC
n0=$(nlines "$F/fsm.log")
GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/seed" status --porcelain > /dev/null 2>&1 || true
n1=$(nlines "$F/fsm.log")
if [ "$r1$r2" = 00 ] && [ "$n0" -eq 0 ] && [ "$n1" -ge 1 ]; then ok "R5-RM02 core.fsmonitor program ran 0 times in prepare+publish (control: git status runs it)"
else bad "R5-RM02 fsmonitor (rc=$r1/$r2 lander runs=$n0 control runs=$n1)"; fi
# RM04 a remotes file without a final newline keeps its last line
fixture r5rm04; F=$T/r5rm04
printf '%s' "$(cat "$F/remotes.txt")" > "$F/r.tmp"; cp "$F/r.tmp" "$F/remotes.txt"
run "$F/prep.out" prepare_raw "$F" --item-id CON-916; r1=$RC
run "$F/pub.out" publish "$F"; r2=$RC
if [ "$r1$r2" = 00 ] && landed_all "$F" && [ "$(tail -c 1 "$F/remotes.txt" | od -An -c | tr -d ' ')" != '\n' ]; then
  ok "R5-RM04 a remotes file without a final newline: origin (the last line) is read, 9/9 landed"
else bad "R5-RM04 no final newline (rc=$r1/$r2)"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
# RM06 a TAB in a mint path is refused
fixture r5rm06; F=$T/r5rm06
printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-777 minted\\n" > %q; echo CON-777\n' "docs/a"$'\t'"b" > "$F/m.sh"; chmod +x "$F/m.sh"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/*" -- prepare "${pargs[@]}" --mint-cmd "$F/m.sh"
refused "R5-RM06 a mint path holding a TAB is refused" 1 'mint command changed a path it may not change \(A docs/a\?b\)' "$F/out"
# RM08 a prose line above a one-space separator line is not part of the trailer block
base_fixture r5rm08; F=$T/r5rm08
vc "$F" k8 'feat k8\n\nroadmap-item:   CON-050 is mentioned here\n \nRoadmap-Item: CON-050\n'; mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-918
C=$F/work/constitution; h=$(hash_by_subject "$C" 'feat k8'); m=$(rawmsg "$C" "${h:-HEAD}")
if [ "$RC" -eq 0 ] && grep -qx 'roadmap-item:   CON-050 is mentioned here' <<<"$m" && [ "$(rimtrailers "$C" "$h")" = CON-918 ]; then
  ok "R5-RM08 the prose line above a whitespace-only separator is kept as written"
else bad "R5-RM08 prose line (rc=$RC)"; printf '%s\n' "$m" | sed 's/^/    | /'; fi
# RM10 a child the id-verify command leaves running does not hold the workdir lock
fixture r5rm10; F=$T/r5rm10
# shellcheck disable=SC2016 # the generated script expands these at its own run time
printf '#!/usr/bin/env bash\n( exec sleep 20 ) </dev/null >/dev/null 2>&1 &\necho $! > %q\necho "## $1"\n' "$F/vbg.pid" > "$F/show_bg.sh"; chmod +x "$F/show_bg.sh"
run "$F/prep.out" prepare "$F" --id-verify-cmd "\"$F/show_bg.sh\" \"\$1\""; r1=$RC
if flock -n "$F/work/.land_vehicle.lock" true; then free=1; else free=0; fi
vbg=$(cat "$F/vbg.pid" 2>/dev/null || true)
live=0; if [[ "$vbg" =~ ^[0-9]+$ ]] && [ "$vbg" -gt 1 ] && [ "$(tr '\0' ' ' < "/proc/$vbg/cmdline" 2>/dev/null)" = "sleep 20 " ]; then live=1; kill "$vbg" 2>/dev/null || true; fi
if [ "$r1" = 0 ] && [ "$free" = 1 ] && [ "$live" = 1 ]; then ok "R5-RM10 the id-verify child is still running and the lock is free (control: the child was alive)"
else bad "R5-RM10 verify child (rc=$r1 lock_free=$free child_alive=$live)"; fi
# RM13 the presence check needs a boundary on the left of the id
fixture r5rm13; F=$T/r5rm13
mkmint "$F/m.sh" 'XCON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-RM13 a tracker holding only XCON-777 does not contain CON-777" 1 'printed CON-777 but no changed file in the clone contains it' "$F/out"
# RM15 the newness check has no left boundary (fail closed)
base_fixture r5rm15; F=$T/r5rm15
seed_main_file "$F" docs/tracker.fake 'XCON-100 old\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-100 minted' CON-100
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-RM15 main holding XCON-100 makes CON-100 not new (fail closed)" 1 'CON-100 already appears in docs/tracker\.fake before the mint' "$F/out"
# RM23 a symlink matching a glob tracker pattern is refused by its mode
fixture r5rm23; F=$T/r5rm23
printf '#!/usr/bin/env bash\nmkdir -p docs; ln -s CON-777 docs/tx; echo CON-777\n' > "$F/m.sh"; chmod +x "$F/m.sh"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" lvenv LANDER_TRACKER_PATHS="docs/t?" -- prepare "${pargs[@]}" --mint-cmd "$F/m.sh"
refused "R5-RM23 a symlink docs/tx matching docs/t? is refused" 1 'docs/tx as a non-regular file \(mode 120000\)' "$F/out"
# RM28 a CR before the newline of the printed id is stripped
fixture r5rm28; F=$T/r5rm28
printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-559 minted\\n" >> docs/tracker.fake; printf "CON-559\\r\\n"\n' > "$F/m.sh"; chmod +x "$F/m.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$F/work/constitution" "$(hash_by_subject "$F/work/constitution" 'feat: two')")" = CON-559 ]; then
  ok "R5-RM28 a mint printing CON-559<CR><LF> mints CON-559"; else bad "R5-RM28 CR in the printed id (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi
# RM31 receivepack or mirror from the caller's GLOBAL config is refused
fixture r5rm31; F=$T/r5rm31
run "$F/prep.out" prepare_raw "$F" --item-id CON-931
for kv in 'remote.m3w.receivepack git-receive-pack' 'remote.github.mirror true'; do
  gccopy "$F"; read -r k v <<<"$kv"; gcset "$F" "$k" "$v"
  run "$F/pub.out" pub_gc "$F"
  nm=${k#remote.}; nm=${nm%%.*}
  refused "R5-RM31 global $k is refused" 2 "remote '$nm' has $k set" "$F/pub.out"
done
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "R5-RM31 no remote moved"; else bad "R5-RM31 no remote moved"; fi

# ============================================ R5-RB (F1) the read-back checks a remote before it reads it
# origin is pushed last. Its pre-receive re-points origin in the clone to a decoy that already
# holds the checked sha, then REJECTS the push: a read-back of the decoy would report origin PASS
fixture r5rb; F=$T/r5rb
run "$F/prep.out" prepare_raw "$F" --item-id CON-910; succeeded "R5-RB prepare exits 0" "$F/prep.out"
C=$F/work/constitution; L=$(g "$C" rev-parse main)
git init -q --bare "$F/decoy.git"; g "$C" push -q "$F/decoy.git" "$L:refs/heads/main"
cat > "$F/remotes/origin.git/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
cat > /dev/null
$(declare -f hg)
REALGIT=$REALGIT
: > "$F/race.done"
hg -C "$C" config remote.origin.url "$F/decoy.git"
exit 1
EOF
chmod +x "$F/remotes/origin.git/hooks/pre-receive"
run "$F/pub.out" publish "$F"
refused "R5-RB origin re-pointed to a decoy at the checked sha during its rejected push: the read-back refuses, naming the remotes pushed" 2 \
  "remote 'origin' fetch URL in the clone differs from --remotes-file; this run already pushed the checked main to: gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w; no further remote is pushed" "$F/pub.out"
if [ -e "$F/race.done" ] && [ "$(git --git-dir="$F/decoy.git" rev-parse main)" = "$L" ] && [ "$(rmain "$F" origin)" = "$(BASE_OF "$F")" ] \
   && [ "$(atcount "$F" "$L")" = 8 ] && ! grep -q 'published to all' "$F/pub.out"; then
  ok "R5-RB origin kept the base, 8 got the checked sha, no success is claimed (control: the decoy holds the checked sha)"
else bad "R5-RB decoy read-back (origin $(rmain "$F" origin), at checked $(atcount "$F" "$L"))"; fi

# ============================================ R5-BUNDLE-COPY (A1) the bundle changes while it is copied into the clone
fixture r5bc; F=$T/r5bc
mkdir -p "$F/cpshim"
cat > "$F/cpshim/cp" <<EOF
#!/usr/bin/env bash
$(command -v cp) "\$@" || exit \$?
dst=\${*: -1}
case "\$dst" in */.git/land_vehicle.bundle) printf 'x' >> "\$dst"; : > "$F/cp.done" ;; esac
EOF
chmod +x "$F/cpshim/cp"
mapfile -t pargs < <(PREP_ARGS "$F")
run "$F/out" env PATH="$F/cpshim:$T/shim:$PATH" "$LANDER" prepare "${pargs[@]}" --item-id CON-911
refused "R5-BUNDLE-COPY a bundle that changes while it is copied into the clone is refused" 1 'bundle sha256 mismatch on the copy in the clone' "$F/out"
if [ -e "$F/cp.done" ] && [ "$(sha256sum "$F/vehicle.bundle" | awk '{print $1}')" = "$(cat "$F/sha")" ] && [ ! -e "$F/work/constitution/.git/land_vehicle.state" ]; then
  ok "R5-BUNDLE-COPY control: the copy really changed, the original still matches its sha256; no prepare state"
else bad "R5-BUNDLE-COPY control"; fi

# ============================================ R5-KEEP (E2) a commit that already carries one real trailer is kept byte for byte
base_fixture r5keep; F=$T/r5keep
vc "$F" k1.txt 'feat keep\n\nRoadmap-Item: CON-912\n'
raw=$(g "$F/seed" cat-file commit HEAD)
signed=$(awk 'h==0 && /^$/ {h=1} h==0 && /^committer / {print; print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " "; print " ZmFrZQ=="; print " -----END PGP SIGNATURE-----"; next} {print}' <<<"$raw" \
  | g "$F/seed" hash-object -t commit -w --stdin)
g "$F/seed" update-ref refs/heads/vehicle "$signed"
vc "$F" k2.txt 'feat keep two\n\nRoadmap-Item: CON-050\n'
mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-912
C=$F/work/constitution
if [ "$RC" -eq 0 ] && g "$C" merge-base --is-ancestor "$signed" main 2>/dev/null \
   && [ "$(g "$C" cat-file commit "$signed" | grep -c '^gpgsig ')" = 1 ] && ! grep -q "^$signed"$'\t' "$F/ev/tree_equality.tsv" \
   && [ "$(rimtrailers "$C" "$(hash_by_subject "$C" 'feat keep two')")" = CON-912 ]; then
  ok "R5-KEEP a signed commit with one real trailer is kept with its signature (same sha); the next commit gets the id"
else bad "R5-KEEP (rc=$RC)"; sed 's/^/    | /' "$F/prep.out"; fi

# ============================================ R5-F1g (A2) a global url.<x>.insteadOf at prepare
# origin is fetched last. The caller's global config rewrites its URL to a decoy that holds a
# commit the real origin does not have. assert_remote runs before each fetch, so prepare refuses
# before anything is fetched from the decoy.
fixture r5f1g; F=$T/r5f1g
git clone -q --bare "$F/remotes/origin.git" "$F/decoy.git"
git clone -q "$F/decoy.git" "$F/dwork"
printf 'decoy\n' > "$F/dwork/decoy.txt"; g "$F/dwork" add decoy.txt
g "$F/dwork" commit -q -m "decoy only" -m "Roadmap-Item: CON-914"; g "$F/dwork" push -q origin main
DS=$(git --git-dir="$F/decoy.git" rev-parse main)
gccopy "$F"; gcset "$F" "url.$F/decoy.git.insteadOf" "$F/remotes/origin.git"
ctl=$(GIT_CONFIG_GLOBAL="$F/gc" git ls-remote "$F/remotes/origin.git" refs/heads/main | awk '{print $1}')
run "$F/prep.out" prep_gc "$F" --item-id CON-913
refused "R5-F1g a global insteadOf that rewrites origin is refused before origin is fetched" 2 \
  "remote 'origin' fetch URL in the clone differs from --remotes-file" "$F/prep.out"
C=$F/work/constitution
if [ "$ctl" = "$DS" ] && ! g "$C" cat-file -e "$DS" 2>/dev/null && [ ! -e "$C/.git/land_vehicle.state" ]; then
  ok "R5-F1g nothing was fetched from the decoy; no prepare state (control: with that config git ls-remote reaches the decoy)"
else bad "R5-F1g decoy (control $ctl, decoy $DS)"; fi

# ============================================ R5-F2zh / R5-F2n (B5, B6) newness: leading zeros in the history, a NUL byte in a tracker
zh_fixture() { # zh_fixture <name>: a commit on main whose trailer is CON-0777 (published), then the vehicle
  local F=$T/$1 r
  base_fixture "$1"
  g "$F/seed" checkout -q main
  printf 'legacy\n' > "$F/seed/legacy.txt"; g "$F/seed" add legacy.txt
  g "$F/seed" commit -q -m "legacy" -m "Roadmap-Item: CON-0777"
  for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
  g "$F/seed" checkout -q -B vehicle main
  vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
}
zh_fixture r5f2zh; F=$T/r5f2zh
mkmint "$F/m.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F2zh a commit on main with the trailer CON-0777 makes CON-777 not new" 1 \
  'CON-777 already appears in a commit message reachable from main or the vehicle' "$F/out"
zh_fixture r5f2zhc; F=$T/r5f2zhc
mkmint "$F/m.sh" 'CON-778 minted' CON-778
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
succeeded "R5-F2zh control: with the same history, CON-778 is new and accepted" "$F/out"
base_fixture r5f2n; F=$T/r5f2n
seed_main_file "$F" docs/tracker.fake 'CON-7775\0row\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F2n a tracker with a NUL byte holding CON-7775 makes CON-777 not new (fail closed)" 1 \
  'CON-777 already appears in docs/tracker\.fake before the mint' "$F/out"
base_fixture r5f2nc; F=$T/r5f2nc
seed_main_file "$F" docs/tracker.fake 'CON-7775 row\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
succeeded "R5-F2n control: the same text without a NUL byte does not block CON-777" "$F/out"

# ============================================ R5-F3c / R5-F3d (B2) a placeholder as the id is refused at once
fixture r5f3c; F=$T/r5f3c
run "$F/out" prepare_raw "$F" --item-id CON-050
refused "R5-F3c --item-id CON-050 (the placeholder) is refused before a clone is made" 2 '--item-id CON-050 matches --placeholder-re' "$F/out"
if [ ! -e "$F/work/constitution" ]; then ok "R5-F3c no clone was made"; else bad "R5-F3c no clone was made"; fi
base_fixture r5f3d; F=$T/r5f3d
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-PENDING-x\n'; mkbundle "$F"
mkmint "$F/m.sh" 'CON-050 minted' CON-050
run "$F/out" prepare_raw "$F" --mint-cmd "$F/m.sh"
refused "R5-F3d a mint printing the placeholder CON-050 is refused before the mint commit" 1 'mint printed CON-050, which matches --placeholder-re' "$F/out"
C=$F/work/constitution
if [ "$(g "$C" rev-parse main 2>/dev/null || echo none)" = "$(BASE_OF "$F")" ] && [ ! -e "$C/.git/land_vehicle.state" ]; then
  ok "R5-F3d no mint commit was made in the clone (main is the base); no prepare state"
else bad "R5-F3d clone main $(g "$C" rev-parse main 2>/dev/null || echo none)"; fi

# SH2-R5 every push the round-5 cases made was plain; the log is then set aside, so the
# round-4 cases below (T1 SH1 counts exactly 9 pushes) start from an empty push log
if push_log_clean; then ok "SH2-R5 all $(wc -l < "$PUSHLOG") pushes of the round-5 cases are plain <sha>:refs/heads/main pushes"
else bad "SH2-R5 pushes of the round-5 cases"; fi
if [ "${LANDER_TEST_R5_ONLY:-0}" = 1 ]; then
  printf '\nRESULT pass=%d fail=%d (round-5 cases only)\n' "$PASS" "$FAIL"
  if [ "$FAIL" -eq 0 ]; then exit 0; else exit 1; fi
fi
cp "$PUSHLOG" "$T/push_r5.log"; : > "$PUSHLOG"


# ================================================================ T1/T2 happy path
fixture t1
F=$T/t1
run "$F/prep.out" prepare "$F"; succeeded "T1 prepare exits 0" "$F/prep.out"
C=$F/work/constitution
msgs=$(g "$C" log --format=%B main -3 2>/dev/null || true)
if grep -q '^Roadmap-Item: CON-777$' <<<"$msgs" && ! grep -Eq 'CON-050|CON-PENDING' <<<"$msgs"; then
  ok "T1 placeholder trailers replaced with minted id"; else bad "T1 placeholder trailers replaced with minted id"; fi
subjects=$(g "$C" log --format=%s main 2>/dev/null || true)
if grep -q 'mint CON-777' <<<"$subjects"; then ok "T1 engine mint output committed"; else bad "T1 engine mint output committed"; fi
mintc=$(hash_by_subject "$C" 'chore(tracker): mint CON-777 via the workable-items engine')
mintns=$(g "$C" diff-tree --no-commit-id --no-renames --name-status -r "${mintc:-HEAD}" 2>/dev/null || true)
if [ "$(cat "$F/ev/mint_changes.tsv" 2>/dev/null)" = "$(printf 'status\tpath\nA\tdocs/tracker.fake')" ] && [ "$mintns" = "$(printf 'A\tdocs/tracker.fake')" ]; then
  ok "V8c T1 mint changes recorded in evidence (name-status equals the mint commit)"; else bad "V8c T1 mint changes recorded in evidence"; cat "$F/ev/mint_changes.tsv" 2>/dev/null || true; fi
if [ -s "$F/ev/tree_equality.tsv" ] && ! grep -q 'FAIL' "$F/ev/tree_equality.tsv" \
   && [ "$(grep -c 'PASS' "$F/ev/tree_equality.tsv")" -eq 2 ]; then
  ok "T2 tree-equality evidence: 2 rows PASS"; else bad "T2 tree-equality evidence: 2 rows PASS"; fi
# independent re-check of tree equality (oracle independent of the script's own table)
orig1=$(g "$F/seed" rev-parse vehicle~1); orig2=$(g "$F/seed" rev-parse vehicle)
new1=$(hash_by_subject "$C" 'feat: one'); new2=$(hash_by_subject "$C" 'feat: two')
if [ -n "$new1" ] && [ -n "$new2" ] && [ "$new1" != "$orig1" ] \
   && [ "$(g "$C" rev-parse "$new1^{tree}")" = "$(g "$F/seed" rev-parse "$orig1^{tree}")" ] \
   && [ "$(g "$C" rev-parse "$new2^{tree}")" = "$(g "$F/seed" rev-parse "$orig2^{tree}")" ]; then
  ok "T2 independent tree re-check"; else bad "T2 independent tree re-check"; fi
if grep -q 'run_full_suite.sh --sync-guide' "$F/prep.out" && grep -q -- '--verify-manifest' "$F/prep.out" \
   && grep -q 'export --no-formats --out-dir docs' "$F/prep.out"; then
  ok "T1 derived-file steps printed"; else bad "T1 derived-file steps printed"; fi
# L2: on the mint path the mint commit lands on main first, so integration is a merge
if grep -q 'step 5: vehicle merged onto main' "$F/prep.out"; then
  ok "T1 mint path integrates by merge (documented)"; else bad "T1 mint path integrates by merge (documented)"; fi
run "$F/pub.out" publish "$F"; succeeded "T1 publish exits 0" "$F/pub.out"
local_main=$(g "$C" rev-parse main 2>/dev/null || echo none)
allok=1
for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$local_main" ] || allok=0; done
if [ $allok = 1 ] && [ "$(grep -c '| PASS |' "$F/ev/publish.md" 2>/dev/null)" -eq 9 ]; then
  ok "T1 all 9 remotes at landed main, 9 PASS rows"; else bad "T1 all 9 remotes at landed main, 9 PASS rows"; fi
if [ "$(wc -l < "$PUSHLOG")" -eq 9 ] && push_log_clean; then
  ok "SH1 T1 publish made 9 plain pushes (argv recorded by the shim)"; else bad "SH1 T1 publish made 9 plain pushes"; sed 's/^/    | /' "$PUSHLOG"; fi
srcs=$(awk -F $'\x1f' '{print $6}' "$PUSHLOG" | sort -u)
if [ "$srcs" = "$local_main:refs/heads/main" ]; then
  ok "SH1b T1 every push names the checked sha as its source, never the branch name"; else bad "SH1b push sources: $srcs"; fi

# ======================================== T3 lagging remote is FAIL (+S8 recovery)
fixture t3
F=$T/t3
run "$F/prep.out" prepare "$F"
printf '#!/bin/sh\necho "denied by test hook" >&2\nexit 1\n' > "$F/remotes/m3w.git/hooks/pre-receive"
chmod +x "$F/remotes/m3w.git/hooks/pre-receive"
run "$F/pub.out" publish "$F"
if [ "$RC" -eq 1 ] && grep -q 'one or more remotes FAIL' "$F/pub.out" \
   && grep -q '| m3w | push-rejected |.*| FAIL |' "$F/ev/publish.md" 2>/dev/null \
   && [ "$(grep -c '| PASS |' "$F/ev/publish.md")" -eq 8 ]; then
  ok "T3 rejecting remote reported FAIL, 8 PASS (rc=$RC)"; else bad "T3 rejecting remote reported FAIL (rc=$RC)"; sed 's/^/    | /' "$F/pub.out"; fi
run "$F/ver.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
refused "T3 verify read-back flags the lagging remote" 1 'read-back FAIL' "$F/ver.out"
p=$F/remotes/m3w.git/hooks/pre-receive; [[ "$p" == "$T"/t3/* ]] && rm -f -- "${p:?}"
run "$F/pub2.out" publish "$F"
tsv=$(cat "$F/ev/publish.tsv" 2>/dev/null || true)
if [ "$RC" -eq 0 ] && [ "$(grep -c $'\tup-to-date\t' <<<"$tsv")" -eq 8 ] && [ "$(grep -c $'\tpushed\t' <<<"$tsv")" -eq 1 ]; then
  ok "S8 re-run of publish recovers (8 up-to-date + 1 pushed)"; else bad "S8 re-run of publish recovers (rc=$RC)"; fi

# ==================== T4/S9 non-ff remote: preflight refuses, NOTHING is pushed
fixture t4
F=$T/t4
run "$F/prep.out" prepare "$F"
base=$(BASE_OF "$F")
git clone -q "$F/remotes/gitverse.git" "$F/other"
printf 'x\n' > "$F/other/x.txt"; g "$F/other" add x.txt; g "$F/other" commit -q -m "diverge"
g "$F/other" push -q origin main
div=$(rmain "$F" gitverse)
run "$F/pub.out" publish "$F"
refused "T4 non-ff remote refused at preflight" 1 'preflight refused.*nothing was pushed' "$F/pub.out"
others=1
for r in $REMOTES; do [ "$r" = gitverse ] && continue; [ "$(rmain "$F" "$r")" = "$base" ] || others=0; done
if [ "$(rmain "$F" gitverse)" = "$div" ] && [ $others = 1 ] \
   && grep -q '| gitverse | refused-non-ff |.*| FAIL |' "$F/ev/publish.md" \
   && [ "$(grep -c '| not-pushed-preflight |' "$F/ev/publish.md")" -eq 8 ]; then
  ok "T4 no remote moved (8 not-pushed-preflight, 1 refused-non-ff)"; else bad "T4 no remote moved"; cat "$F/ev/publish.md" 2>/dev/null || true; fi

# --------------------------------- T5 force flag anywhere in the script fails
force_guard() { # prints offending lines; returns 0 only when the file is clean
  ! grep -nE -- '--force|--force-with-lease|--force-if-includes|push[^#]*[[:space:]]-[a-zA-Z]*f([[:space:]]|$)|[[:space:]:"]\+(refs/|main|HEAD)|--mirror|receive\.denyNonFastForwards' "$1"
}
if force_guard "$LANDER" > "$T/fg.out"; then ok "T5 no force flag in lander"; else bad "T5 no force flag in lander"; cat "$T/fg.out"; fi
# shellcheck disable=SC2016 # literal injected text
for inj in 'git push --force "$r" main' 'git push -f "$r" main' 'git push "$r" +main:refs/heads/main' 'git push --force-with-lease "$r" main'; do
  cp "$LANDER" "$T/mut.sh"; printf '%s\n' "$inj" >> "$T/mut.sh"
  if force_guard "$T/mut.sh" > /dev/null; then bad "T5 guard catches: $inj"; else ok "T5 guard catches: $inj"; fi
done

# -------------------------------------------------- T6/T7 bundle checks
fixture t6
F=$T/t6
run "$F/out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(printf '0%.0s' {1..64})" --head "$(cat "$F/head")" \
   --workdir "$F/work" --remotes-file "$F/remotes.txt" --mint-cmd "$F/mint.sh" --evidence-dir "$F/ev"
refused "T6 wrong bundle sha256 refused" 1 'bundle sha256 mismatch' "$F/out"
fixture t7
F=$T/t7
run "$F/out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(g "$F/seed" rev-parse main)" \
   --workdir "$F/work" --remotes-file "$F/remotes.txt" --mint-cmd "$F/mint.sh" --evidence-dir "$F/ev"
refused "T7 head not a ref tip in the bundle refused" 1 'is not a ref tip in the bundle' "$F/out"

# ------------------------------- T8 main moved: merge, main never rewritten
fixture t8
F=$T/t8
git clone -q "$F/remotes/origin.git" "$F/mover"
printf 'm\n' > "$F/mover/m.txt"; g "$F/mover" add m.txt; g "$F/mover" commit -q -m "main moved" -m "Roadmap-Item: CON-002"
for r in $REMOTES; do g "$F/mover" push -q "$F/remotes/$r.git" main:refs/heads/main; done
moved=$(g "$F/mover" rev-parse main)
run "$F/prep.out" prepare "$F"; rc1=$RC
run "$F/pub.out" publish "$F"; rc2=$RC
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  new=$(rmain "$F" origin)
  merges=$(git --git-dir="$F/remotes/origin.git" rev-list --merges -1 main)
  if git --git-dir="$F/remotes/origin.git" merge-base --is-ancestor "$moved" "$new" && [ -n "$merges" ]; then
    ok "T8 moved main integrated by merge, old main is ancestor"; else bad "T8 moved main integrated by merge"; fi
else bad "T8 prepare+publish on moved main (rc=$rc1/$rc2)"; cat "$F/prep.out" "$F/pub.out" 2>/dev/null || true; fi

# ---------------------------- T9 diverged remote mains refused at prepare
fixture t9
F=$T/t9
git clone -q "$F/remotes/github.git" "$F/div"
printf 'd\n' > "$F/div/d.txt"; g "$F/div" add d.txt; g "$F/div" commit -q -m "d1"
g "$F/div" push -q origin main
git clone -q "$F/remotes/gitflic.git" "$F/div2"
printf 'e\n' > "$F/div2/e.txt"; g "$F/div2" add e.txt; g "$F/div2" commit -q -m "e1"
g "$F/div2" push -q origin main
run "$F/prep.out" prepare "$F"
refused "T9 diverged remote mains refused" 3 'remote mains have diverged' "$F/prep.out"

# ------------------------------ T10 clone dir name enforced for the mint
fixture t10
F=$T/t10
run "$F/prep.out" prepare "$F" --clone-name notconstitution
refused "T10 mint outside a 'constitution' dir refused" 2 "named 'constitution'" "$F/prep.out"
if [ ! -e "$F/work/notconstitution" ]; then ok "T10 refused before any clone was created"; else bad "T10 refused before any clone was created"; fi

# ------------------------------------- T11 publish refuses a dirty tree
fixture t11
F=$T/t11
run "$F/prep.out" prepare "$F"
printf 'dirt\n' > "$F/work/constitution/dirt.txt" 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "T11 dirty tree refused" 2 'uncommitted changes' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "T11 no remote moved"; else bad "T11 no remote moved"; fi

# ================================================= S1 vehicle with a merge commit
base_fixture s1; F=$T/s1
g "$F/seed" checkout -q -b side main
vc "$F" s.txt 'side\n\nRoadmap-Item: CON-050\n'
g "$F/seed" checkout -q vehicle
vc "$F" v.txt 'vfeat\n\nRoadmap-Item: CON-PENDING-x\n'
g "$F/seed" merge -q --no-ff -m "merge side" -m "Roadmap-Item: CON-050" side
vc "$F" w.txt 'after merge\n\nRoadmap-Item: CON-050\n'
mkbundle "$F"
run "$F/prep.out" prepare "$F"; succeeded "S1 merge-commit vehicle: prepare exits 0" "$F/prep.out"
C=$F/work/constitution
parents=$(g "$C" rev-list --parents --merges main 2>/dev/null | awk '{print NF-1}' || true)
allmsg=$(g "$C" log --format=%B main 2>/dev/null || true)
reach=0
oldlist=$(g "$F/seed" rev-list vehicle ^main)
for o in $oldlist; do if g "$C" merge-base --is-ancestor "$o" main 2>/dev/null; then reach=1; fi; done
treeok=1
for o in $oldlist; do
  s=$(g "$F/seed" log -1 --format=%s "$o"); n=$(hash_by_subject "$C" "$s")
  [ -n "$n" ] && [ "$(g "$C" rev-parse "$n^{tree}")" = "$(g "$F/seed" rev-parse "$o^{tree}")" ] || treeok=0
  [ "$(rimtrailers "$C" "$n")" = CON-777 ] || treeok=0
done
if [ "$(tr '\n' ' ' <<<"$parents")" = "2 2 " ] && ! grep -Eq 'CON-050|CON-PENDING' <<<"$allmsg" && [ $reach = 0 ] && [ $treeok = 1 ] \
   && [ "$(grep -c $'\tPASS\t' "$F/ev/tree_equality.tsv")" -eq 4 ]; then
  ok "S1 merges keep 2 parents, no placeholder, no old sha, 4 trees equal, one real trailer each"
else bad "S1 merge-commit vehicle shape"; fi
run "$F/pub.out" publish "$F"; succeeded "S1 publish exits 0" "$F/pub.out"

# ================================================= S2..S5 trailer handling
base_fixture tr; F=$T/tr
vc "$F" s2 'feat s2\n\nRoadmap-Item: <TO-BE-MINTED-by-engine>\n'
vc "$F" s3 'feat s3\r\n\r\nRoadmap-Item: CON-050\r\n'
vc "$F" s4 'feat s4\n\nRoadmap-Item: CON-050 was the old placeholder; see notes.\nMore prose here.\n'
vc "$F" s4b 'feat s4b\n\nRoadmap-Item: CON-050\n\nA middle paragraph.\n\nRoadmap-Item: CON-PENDING-x\n'
vc "$F" s5a 'feat s5a\n\nCo-Authored-By: X <x@y.z>\n'
vc "$F" s5b 'feat s5b\n\nRoadmap-Item: CON-050\nRoadmap-Item: CON-PENDING-q\nCo-Authored-By: X <x@y.z>\n'
vc "$F" s5c 'feat s5c\n\nroadmap-item: CON-050\n'
vc "$F" s5e 'feat s5e\n\nRoadmap-Item: CON-123\n'
vc "$F" s5f 'feat s5f\n\nRoadmap-Item : CON-050\n'
vc "$F" s5g 'feat s5g\n\nRoadmap-Item: CON-1050\n'
vc "$F" s5h 'feat s5h\n\nsome text\n---\nnot a diff\n\nRoadmap-Item: CON-050\n'
mkbundle "$F"
run "$F/prep.out" prepare "$F"; succeeded "S2-S5 prepare exits 0" "$F/prep.out"
C=$F/work/constitution
for s in s2 s3 s4 s4b s5a s5b s5c s5e s5f s5g s5h; do eval "H_$s=\$(hash_by_subject \"\$C\" \"feat $s\")"; done
# shellcheck disable=SC2154 # H_* are set by the eval above
{
m2=$(g "$C" log -1 --format=%B "$H_s2" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s2")" = CON-777 ] && ! grep -q 'TO-BE-MINTED' <<<"$m2"; then
  ok "S2 <TO-BE-MINTED...> placeholder replaced"; else bad "S2 <TO-BE-MINTED...> placeholder replaced"; fi
H_s3=$(g "$C" log --format=%H -1 main -- s3 2>/dev/null || true)
m3=$(rawmsg "$C" "${H_s3:-HEAD}"; printf x); m3=${m3%x}
if [ -n "$H_s3" ] && [ "$(rimtrailers "$C" "$H_s3")" = CON-777 ] && [ "$m3" = $'feat s3\r\n\r\nRoadmap-Item: CON-777\n' ]; then
  ok "S3 CRLF trailer replaced; the subject and the blank line keep their CR, byte for byte"; else bad "S3 CRLF trailer (message: $(printf '%q' "$m3"))"; fi
m4=$(g "$C" log -1 --format=%B "$H_s4" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s4")" = CON-777 ] && grep -qx 'Roadmap-Item: CON-050 was the old placeholder; see notes.' <<<"$m4"; then
  ok "S4 body prose line kept verbatim, real trailer appended"; else bad "S4 body prose line kept verbatim, real trailer appended"; fi
m4b=$(g "$C" log -1 --format=%B "$H_s4b" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s4b")" = CON-777 ] && grep -qx 'Roadmap-Item: CON-050' <<<"$m4b" && ! grep -q 'CON-PENDING' <<<"$m4b"; then
  ok "S4b only the git-parsed trailer block is rewritten"; else bad "S4b only the git-parsed trailer block is rewritten"; fi
m5a=$(g "$C" log -1 --format='%(trailers:key=Co-Authored-By,valueonly)' "$H_s5a" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s5a")" = CON-777 ] && [ "$m5a" = 'X <x@y.z>' ]; then
  ok "S5a missing trailer appended, Co-Authored-By kept"; else bad "S5a missing trailer appended, Co-Authored-By kept"; fi
m5b=$(g "$C" log -1 --format=%B "$H_s5b" 2>/dev/null || true)
c5b=$(g "$C" log -1 --format='%(trailers:key=Co-Authored-By,valueonly)' "$H_s5b" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s5b")" = CON-777 ] && [ "$(grep -ci '^roadmap-item:' <<<"$m5b")" -eq 1 ] && [ "$c5b" = 'X <x@y.z>' ]; then
  ok "S5b two placeholders become one trailer, Co-Authored-By kept"; else bad "S5b two placeholders become one trailer"; fi
m5c=$(g "$C" log -1 --format=%B "$H_s5c" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s5c")" = CON-777 ] && [ "$(grep -ci '^roadmap-item:' <<<"$m5c")" -eq 1 ]; then
  ok "S5c lowercase key replaced, no second trailer"; else bad "S5c lowercase key replaced, no second trailer"; fi
if [ "$(rimtrailers "$C" "$H_s5e")" = CON-123 ]; then
  ok "S5e an existing real id is kept"; else bad "S5e an existing real id is kept"; fi
m5f=$(g "$C" log -1 --format=%B "$H_s5f" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s5f")" = CON-777 ] && [ "$(grep -ci '^roadmap-item' <<<"$m5f")" -eq 1 ]; then
  ok "S5f 'Roadmap-Item : X' (space before the colon) replaced, one trailer"; else bad "S5f space before the colon"; fi
if [ "$(rimtrailers "$C" "$H_s5g")" = CON-1050 ]; then
  ok "S5g a real id containing 050 (CON-1050) is kept"; else bad "S5g real id CON-1050 kept"; fi
m5h=$(g "$C" log -1 --format=%B "$H_s5h" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s5h")" = CON-777 ] && grep -qx -- '---' <<<"$m5h" && grep -qx 'not a diff' <<<"$m5h"; then
  ok "S5h a --- line in the body is not a divider; trailer replaced"; else bad "S5h --- line in body"; fi
}
run "$F/pub.out" publish "$F"; succeeded "S2-S5 publish exits 0" "$F/pub.out"
# S5g-b a value with a leading zero beyond three digits (CON-0501) is not an id: refused
base_fixture s5gb; F=$T/s5gb
vc "$F" s5gb 'feat s5gb\n\nRoadmap-Item: CON-0501\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-788
refused "S5g-b a trailer CON-0501 (not canonical) is refused at prepare" 1 "lacks a single real Roadmap-Item trailer \\(found: 'CON-0501'" "$F/out"

# ------------- S5d author name, email, date (with timezone) preserved; signature noted
base_fixture au; F=$T/au
GIT_AUTHOR_NAME="Ann Author" GIT_AUTHOR_EMAIL=ann@author.invalid GIT_AUTHOR_DATE="2001-02-03T04:05:06+05:30" \
  vc "$F" au1 'feat au1\n\nRoadmap-Item: CON-050\n'
# fake-signed commit object (gpgsig header), to check the dropped-signature evidence
raw=$(g "$F/seed" cat-file commit HEAD)
signed=$(awk 'h==0 && /^$/ {h=1} h==0 && /^committer / {print; print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " "; print " ZmFrZQ=="; print " -----END PGP SIGNATURE-----"; next} {print}' <<<"$raw" \
  | g "$F/seed" hash-object -t commit -w --stdin)
g "$F/seed" update-ref refs/heads/vehicle "$signed"
mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-901; succeeded "S5d prepare exits 0" "$F/prep.out"
C=$F/work/constitution
n=$(hash_by_subject "$C" 'feat au1')
if [ -n "$n" ] && [ "$n" != "$signed" ] \
   && [ "$(g "$C" log -1 --format='%an|%ae|%aI' "$n")" = "$(g "$F/seed" log -1 --format='%an|%ae|%aI' "$signed")" ] \
   && [ "$(g "$C" log -1 --format='%aI' "$n")" = '2001-02-03T04:05:06+05:30' ]; then
  ok "S5d author name, email and date preserved"; else bad "S5d author name, email and date preserved"; fi
newraw=$(g "$C" cat-file commit "$n" 2>/dev/null || true)
if grep -q "^$signed"$'\t'".*"$'\t'"PASS"$'\t'"yes$" "$F/ev/tree_equality.tsv" && ! grep -q '^gpgsig' <<<"$newraw"; then
  ok "S5d dropped signature recorded in evidence"; else bad "S5d dropped signature recorded in evidence"; cat "$F/ev/tree_equality.tsv" 2>/dev/null || true; fi

# ====================================== S6 publish after reset: vehicle not on main
base_fixture s6; F=$T/s6
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-778
C=$F/work/constitution
mb=$(sed -n 's/^main_before=//p' "$C/.git/land_vehicle.state" 2>/dev/null || true)
g "$C" reset -q --hard "${mb:-HEAD}" 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "S6 publish refuses when the landed vehicle is not on main" 1 'does not contain the landed vehicle head' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "S6 no remote moved"; else bad "S6 no remote moved"; fi

# ========================== S7 --item-id path fast-forwards; idempotent publish; re-run prepare
base_fixture s7; F=$T/s7
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-779
if [ "$RC" -eq 0 ] && grep -q 'step 5: main fast-forwarded' "$F/prep.out"; then
  ok "S7 --item-id path fast-forwards"; else bad "S7 --item-id path fast-forwards (rc=$RC)"; fi
run "$F/pub1.out" publish "$F"; succeeded "S7 first publish exits 0" "$F/pub1.out"
run "$F/pub2.out" publish "$F"
if [ "$RC" -eq 0 ] && [ "$(grep -c ': up-to-date -> PASS' "$F/pub2.out")" -eq 9 ]; then
  ok "S7 second publish: 9 up-to-date, exit 0"; else bad "S7 second publish idempotent (rc=$RC)"; fi
run "$F/prep2.out" prepare_raw "$F" --item-id CON-779
if [ "$RC" -eq 2 ] && grep -q 'clone path already exists' "$F/prep2.out" && grep -q 'guarded delete' "$F/prep2.out"; then
  ok "S7 re-run of prepare refused with a recovery hint (rc=2)"; else bad "S7 re-run of prepare message (rc=$RC)"; sed 's/^/    | /' "$F/prep2.out"; fi

# ================================= S10 ambient hooks do not alter the lander's commits
base_fixture s10; F=$T/s10
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkdir -p "$T/hk"
# shellcheck disable=SC2016 # literal hook text
printf '#!/bin/sh\necho "Injected-By: hook" >> "$1"\n' > "$T/hk/commit-msg"
chmod +x "$T/hk/commit-msg"
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$T/hk"
run "$F/prep.out" prepare "$F"
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath
C=$F/work/constitution
bodies=$(g "$C" log --format=%B main 2>/dev/null || true)
if [ "$RC" -eq 0 ] && grep -q 'mint CON-777' <<<"$bodies" && grep -q '^Merge vehicle' <<<"$bodies" && ! grep -q 'Injected-By' <<<"$bodies"; then
  ok "S10 mint and merge commits run without ambient hooks"; else bad "S10 ambient hooks (rc=$RC)"; fi

# ======================================================== S11 empty mirror
base_fixture s11; F=$T/s11
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
safe_rm_rf "${F:?}/remotes/m3w.git"
git init -q --bare "$F/remotes/m3w.git"
run "$F/prep.out" prepare_raw "$F" --item-id CON-782
refused "S11 empty mirror refused at prepare" 1 'fetch of main failed on remote m3w.*no main branch' "$F/prep.out"

# ================================ S12 publish refuses an untrailered commit after prepare
base_fixture s12; F=$T/s12
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --item-id CON-783
C=$F/work/constitution
{ printf 'q\n' > "$C/q" && g "$C" add q && g "$C" commit -q -m "no trailer"; } 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "S12 untrailered commit refused at publish" 1 'lacks a single real Roadmap-Item trailer' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "S12 no remote moved"; else bad "S12 no remote moved"; fi

# ============================ S13 head is an earlier tip of a multi-ref bundle
base_fixture s13; F=$T/s13
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n'; h1=$(g "$F/seed" rev-parse HEAD)
vc "$F" y 'feat y\n\nRoadmap-Item: CON-050\n'
g "$F/seed" branch early "$h1"; mkbundle "$F" early; echo "$h1" > "$F/head"
run "$F/prep.out" prepare_raw "$F" --item-id CON-784
C=$F/work/constitution
subj=$(g "$C" log --format=%s main 2>/dev/null || true)
if [ "$RC" -eq 0 ] && grep -qx 'feat x' <<<"$subj" && ! grep -qx 'feat y' <<<"$subj"; then
  ok "S13 lands only up to the given tip"; else bad "S13 lands only up to the given tip (rc=$RC)"; fi

# ============================================ M11 ids: mint output and --item-id
fixture m11; F=$T/m11
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_bad.sh"
refused "M11 mint whose last line is not an id refused" 1 'did not print an id' "$F/out"
fixture m11b; F=$T/m11b
run "$F/out" prepare_raw "$F" --item-id CON-12x
refused "M11 bogus --item-id refused" 2 'item-id must match' "$F/out"

# ============================================ M12 vehicle already on main
fixture m12; F=$T/m12
for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" vehicle:refs/heads/main; done
run "$F/out" prepare "$F"
refused "M12 vehicle already on main refused" 3 'already on main' "$F/out"

# ============================================ M13 remotes file must match the set
fixture m13; F=$T/m13
cp "$F/remotes.txt" "$F/r_extra.txt"; printf 'extra %s\n' "$F/remotes/origin.git" >> "$F/r_extra.txt"
run "$F/o1" lv verify --workdir "$F/work" --remotes-file "$F/r_extra.txt"
refused "M13 extra remote name refused" 2 'outside LANDER_REMOTES' "$F/o1"
cp "$F/remotes.txt" "$F/r_dup.txt"; printf 'origin %s\n' "$F/remotes/origin.git" >> "$F/r_dup.txt"
run "$F/o2" lv verify --workdir "$F/work" --remotes-file "$F/r_dup.txt"
refused "M13 duplicate remote name refused" 2 "declare 'origin' exactly once \(found 2\)" "$F/o2"
grep -v '^m3w ' "$F/remotes.txt" > "$F/r_miss.txt"
run "$F/o3" lv verify --workdir "$F/work" --remotes-file "$F/r_miss.txt"
refused "M13 missing remote name refused" 2 "declare 'm3w' exactly once \(found 0\)" "$F/o3"

# ============================================ M15 local main lost the prepared base
fixture m15; F=$T/m15
run "$F/prep.out" prepare "$F"
C=$F/work/constitution
{ g "$C" checkout -q --orphan stray && g "$C" commit -q -m "stray root" -m "Roadmap-Item: CON-9" \
  && g "$C" branch -q -f main stray && g "$C" checkout -q main; } 2>/dev/null || true
run "$F/pub.out" publish "$F"
refused "M15 publish refuses a main without the prepared base" 1 'no longer contains the prepared base' "$F/pub.out"

# ============================================ X14 two distinct ids / unknown value
base_fixture x14; F=$T/x14
vc "$F" x 'feat x\n\nRoadmap-Item: CON-123\nRoadmap-Item: CON-050\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-785
refused "X14 two distinct ids in one commit refused at prepare" 1 'lacks a single real Roadmap-Item trailer' "$F/out"
base_fixture x14b; F=$T/x14b
vc "$F" x 'feat x\n\nRoadmap-Item: FOO-1\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-785
refused "X14b unrecognised Roadmap-Item value refused at prepare" 1 'lacks a single real Roadmap-Item trailer' "$F/out"

# ============================================ X8 interpret-trailers failure aborts
base_fixture x8; F=$T/x8
vc "$F" x 'feat x\n\nCo-Authored-By: X <x@y.z>\n'; mkbundle "$F"
mkdir -p "$T/fakegit"
cat > "$T/fakegit/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = interpret-trailers ] && { echo "fake interpret-trailers failure" >&2; exit 7; }; done
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/fakegit/git"
run "$F/out" env PATH="$T/fakegit:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
  --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --item-id CON-786
refused "X8 interpret-trailers failure aborts prepare" 1 'interpret-trailers failed' "$F/out"
if [ "$(g "$F/work/constitution" rev-parse main 2>/dev/null || true)" = "$(BASE_OF "$F")" ]; then
  ok "X8 nothing integrated after the abort"; else bad "X8 nothing integrated after the abort"; fi

# ============================================ X8b a failing write of the re-commit aborts (round 5:
# the trailer is rewritten in bash, so the write of the new commit object is the git step to fail)
base_fixture x8b; F=$T/x8b
vc "$F" x 'feat x\n\nCo-Authored-By: X <x@y.z>\n'; mkbundle "$F"
mkdir -p "$T/fakegit2"
cat > "$T/fakegit2/git" <<EOF
#!/usr/bin/env bash
prev=
for a in "\$@"; do
  if [ "\$prev" = -t ] && [ "\$a" = commit ]; then echo "fake hash-object failure" >&2; exit 7; fi
  prev=\$a
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/fakegit2/git"
run "$F/out" env PATH="$T/fakegit2:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
  --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --item-id CON-787
refused "X8b a failing write of the re-commit aborts prepare" 1 'git hash-object failed for the re-commit' "$F/out"
if grep -q 'fake hash-object failure' "$F/out"; then ok "X8b control: the fault was really injected"; else bad "X8b control: the fault was really injected"; fi
if [ "$(g "$F/work/constitution" rev-parse main 2>/dev/null || true)" = "$(BASE_OF "$F")" ]; then
  ok "X8b nothing integrated after the abort"; else bad "X8b nothing integrated after the abort"; fi

# ============================================ P1 a remote without main at publish time
fixture p1; F=$T/p1
run "$F/prep.out" prepare "$F"
git --git-dir="$F/remotes/m3w.git" update-ref -d refs/heads/main
run "$F/pub.out" publish "$F"
refused "P1 remote without main refused at preflight" 1 'preflight refused.*nothing was pushed' "$F/pub.out"
others=1
for r in $REMOTES; do [ "$r" = m3w ] && continue; [ "$(rmain "$F" "$r")" = "$(BASE_OF "$F")" ] || others=0; done
if [ $others = 1 ] && grep -q '| m3w | refused-no-main-or-unreadable |' "$F/ev/publish.md"; then
  ok "P1 no remote was pushed"; else bad "P1 no remote was pushed"; fi

# ============================================ L4 missing option value: usage exit 2
run "$T/l4.out" lv prepare --bundle
refused "L4 missing option value is a usage error" 2 'option --bundle needs a value' "$T/l4.out"
run "$T/l4b.out" lv prepare --bundle --sha256 abc
refused "L4 option followed by another option is a usage error" 2 'option --bundle needs a value' "$T/l4b.out"

# ============================================ L5 git stderr (URLs) is not printed
fixture l5; F=$T/l5
sed -i "s|^origin .*|origin $F/remotes/SECRETMARK-nope.git|" "$F/remotes.txt"
run "$F/out" prepare "$F"
if [ "$RC" -eq 1 ] && grep -q 'fetch of main failed on remote origin' "$F/out" && ! grep -q 'SECRETMARK' "$F/out"; then
  ok "L5 failing fetch names the remote, not its URL"; else bad "L5 failing fetch names the remote, not its URL (rc=$RC)"; sed 's/^/    | /' "$F/out"; fi

# ============================================ L6 key prefix is an option
base_fixture l6; F=$T/l6
vc "$F" x 'feat x\n\nRoadmap-Item: ABC-PENDING-x\n'; mkbundle "$F"
run "$F/prep.out" prepare_raw "$F" --key-prefix ABC --item-id ABC-012
C=$F/work/constitution
n=$(hash_by_subject "$C" 'feat x')
if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$C" "$n")" = ABC-012 ]; then
  ok "L6 --key-prefix ABC: placeholder replaced with ABC-012"; else bad "L6 --key-prefix ABC (rc=$RC)"; sed 's/^/    | /' "$F/prep.out"; fi
run "$F/pubx.out" publish "$F" --key-prefix CON
refused "L6 publish with a key prefix other than the prepared one refused" 2 'key prefix' "$F/pubx.out"
run "$F/pub.out" publish "$F"; succeeded "L6 publish reads the key prefix from the state" "$F/pub.out"
fixture l6b; F=$T/l6b
run "$F/out" prepare_raw "$F" --key-prefix 'a b' --item-id CON-1
refused "L6 malformed key prefix refused" 2 'key-prefix must match' "$F/out"
fixture l6c; F=$T/l6c
run "$F/out" prepare_raw "$F" --key-prefix ABC --item-id CON-1
refused "L6 --item-id with another key refused" 2 'item-id must match' "$F/out"

# ##################################################################### round 3
# ============================================ U1-U3 R2-F1 remote URLs must match the file
# U1 (A4c): prepare ran with an older remotes file; publish/verify get the declared one
fixture u1; F=$T/u1
git clone -q --bare "$F/remotes/origin.git" "$F/old_origin.git"
sed "s|^origin .*|origin $F/old_origin.git|" "$F/remotes.txt" > "$F/remotes_old.txt"
run "$F/prep.out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" \
  --workdir "$F/work" --remotes-file "$F/remotes_old.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint.sh"
succeeded "U1 prepare with the older remotes file exits 0" "$F/prep.out"
run "$F/pub.out" publish "$F"
refused "U1 publish refuses a clone whose origin URL differs from --remotes-file" 2 "remote 'origin' fetch URL in the clone differs" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")" && [ "$(git --git-dir="$F/old_origin.git" rev-parse main)" = "$(BASE_OF "$F")" ] \
   && [ ! -e "$F/ev/publish.md" ]; then ok "U1 nothing pushed, not even to the old URL; no read-back written"; else bad "U1 nothing pushed"; fi
run "$F/ver.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
refused "U1 verify refuses the URL mismatch too" 2 "fetch URL in the clone differs" "$F/ver.out"
# U2 (A4): origin re-pointed at an unlisted repo after prepare
fixture u2; F=$T/u2
run "$F/prep.out" prepare "$F"
git init -q --bare "$F/unlisted.git"; g "$F/seed" push -q "$F/unlisted.git" main:refs/heads/main
g "$F/work/constitution" remote set-url origin "$F/unlisted.git"
run "$F/pub.out" publish "$F"
refused "U2 publish refuses an origin re-pointed after prepare" 2 "remote 'origin' fetch URL in the clone differs" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")" && [ "$(git --git-dir="$F/unlisted.git" rev-parse main)" = "$(BASE_OF "$F")" ]; then
  ok "U2 nothing pushed"; else bad "U2 nothing pushed"; fi
# U3 (A4b): an extra push URL; U3b remote.<name>.mirror set
fixture u3; F=$T/u3
run "$F/prep.out" prepare "$F"
git init -q --bare "$F/sink.git"
g "$F/work/constitution" config remote.origin.pushurl "$F/sink.git"
run "$F/pub.out" publish "$F"
refused "U3 publish refuses a push URL other than the declared one" 2 "remote 'origin' push URL\(s\) in the clone differ" "$F/pub.out"
g "$F/work/constitution" config --unset remote.origin.pushurl
g "$F/work/constitution" config remote.gitverse.mirror true
run "$F/pub2.out" publish "$F"
refused "U3b publish refuses remote.<name>.mirror" 2 "remote.gitverse.mirror set" "$F/pub2.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U3 nothing pushed"; else bad "U3 nothing pushed"; fi
g "$F/work/constitution" config --unset remote.gitverse.mirror
run "$F/pub3.out" publish "$F"; succeeded "U3c publish exits 0 once the clone config matches again" "$F/pub3.out"

# ============================================ U4-U8 R2-F2 the mint must change the clone
fixture u4; F=$T/u4
run "$F/out" prepare_raw "$F" --mint-cmd 'echo CON-005'
refused "U4 mint that prints an id but changes nothing is refused" 1 'printed CON-005 but changed no file in the clone' "$F/out"
C=$F/work/constitution
if [ "$(g "$C" rev-parse main 2>/dev/null || true)" = "$(BASE_OF "$F")" ] && [ ! -e "$C/.git/land_vehicle.state" ]; then
  ok "U4 nothing landed (main = base, no state)"; else bad "U4 nothing landed"; fi
fixture u5; F=$T/u5
cat > "$F/mint_outside.sh" <<EOF
#!/usr/bin/env bash
printf 'CON-077\\n' >> "$F/outside_tracker.db"
echo CON-077
EOF
chmod +x "$F/mint_outside.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_outside.sh"
refused "U5 mint that writes outside the clone is refused" 1 'printed CON-077 but changed no file in the clone' "$F/out"
if [ -s "$F/outside_tracker.db" ]; then ok "U5 control: the outside mint really ran"; else bad "U5 control: the outside mint really ran"; fi
fixture u6; F=$T/u6
cat > "$F/mint_noid.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p docs; printf 'unrelated change\n' >> docs/other.txt
echo CON-778
EOF
chmod +x "$F/mint_noid.sh"
run "$F/out" env LANDER_TRACKER_PATHS="docs/tracker.fake docs/other.txt" PATH="$T/shim:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" \
  --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint_noid.sh"
refused "U6 mint whose changes do not contain the id is refused" 1 'no changed file in the clone contains it' "$F/out"
fixture u7; F=$T/u7
cat > "$F/mint_commits.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p docs; printf 'CON-779\n' >> docs/tracker.fake
git add docs/tracker.fake >/dev/null && git commit -q -m "engine commit" -m "Roadmap-Item: CON-779" >/dev/null
echo CON-779
EOF
chmod +x "$F/mint_commits.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_commits.sh"
refused "U7 mint that commits by itself is refused" 1 'moved HEAD or committed by itself' "$F/out"
# U8 engine read command (hermetic fake engine "show"): pass, fail, silent
fixture u8; F=$T/u8; U8=$T/u8
cat > "$F/show.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "$LAND_ITEM_ID" ] || { echo "arg/env mismatch" >&2; exit 5; }
grep -q "^$1 minted\$" docs/tracker.fake 2>/dev/null || { echo "no such item" >&2; exit 4; }
echo "## $1 (minted)"
EOF
printf '#!/usr/bin/env bash\necho "all good"\n' > "$F/show_silent.sh"
chmod +x "$F/show.sh" "$F/show_silent.sh"
# the documented contract: the id is $1 of the bash -c string
run "$F/prep.out" prepare "$F" --id-verify-cmd "\"$U8/show.sh\" \"\$1\""
if [ "$RC" -eq 0 ] && grep -q 'step 3b: id CON-777 confirmed by the engine' "$F/prep.out"; then
  ok "U8 engine read command confirms the minted id"; else bad "U8 engine read command confirms the minted id (rc=$RC)"; sed 's/^/    | /' "$F/prep.out"; fi
fixture u8b; F=$T/u8b
run "$F/out" prepare_raw "$F" --item-id CON-999 --id-verify-cmd "\"$U8/show.sh\" \"\$1\""
refused "U8b --item-id the engine does not know is refused" 1 'id verify command failed for CON-999' "$F/out"
if grep -q 'no such item' "$F/out"; then ok "U8b the engine itself said no such item"; else bad "U8b the engine itself said no such item"; fi
if [ ! -e "$F/work/constitution/.git/land_vehicle.state" ]; then ok "U8b nothing landed"; else bad "U8b nothing landed"; fi
fixture u8c; F=$T/u8c
run "$F/out" prepare "$F" --id-verify-cmd "\"$U8/show_silent.sh\" \"\$1\""
refused "U8c an engine read that does not print the id is refused" 1 'did not print CON-777' "$F/out"

# ============================================ U9-U10 R2-F3 trailer range from the remote tips
# U9 (A3): untrailered commit added, then state main_before and landed edited to main
fixture u9; F=$T/u9
run "$F/prep.out" prepare_raw "$F" --item-id CON-801
C=$F/work/constitution
{ printf 'q\n' > "$C/q" && g "$C" add q && g "$C" commit -q -m "no trailer at all"; } 2>/dev/null || true
m=$(g "$C" rev-parse main)
sed -i "s/^main_before=.*/main_before=$m/; s/^landed_vehicle_head=.*/landed_vehicle_head=$m/" "$C/.git/land_vehicle.state"
run "$F/pub.out" publish "$F"
refused "U9 an edited prepare state is refused" 2 'prepare state does not match git: main_before differs' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U9 no remote moved"; else bad "U9 no remote moved"; fi
# U9c-U9e: one state field at a time; U9e moves landed in state AND ref (tree differs)
fixture u9c; F=$T/u9c
run "$F/prep.out" prepare_raw "$F" --item-id CON-811
C=$F/work/constitution
{ printf 'q\n' > "$C/q" && g "$C" add q && g "$C" commit -q -m "extra" -m "Roadmap-Item: CON-811"; } 2>/dev/null || true
m=$(g "$C" rev-parse main)
cp "$C/.git/land_vehicle.state" "$F/state.orig"
sed -i "s/^landed_vehicle_head=.*/landed_vehicle_head=$m/" "$C/.git/land_vehicle.state"
run "$F/p1.out" publish "$F"
refused "U9c edited landed_vehicle_head refused" 2 'prepare state does not match git: landed_vehicle_head differs' "$F/p1.out"
cp "$F/state.orig" "$C/.git/land_vehicle.state"
sed -i "s/^vehicle_head=.*/vehicle_head=$m/" "$C/.git/land_vehicle.state"
run "$F/p2.out" publish "$F"
refused "U9d edited vehicle_head refused" 2 'prepare state does not match git: vehicle_head differs' "$F/p2.out"
cp "$F/state.orig" "$C/.git/land_vehicle.state"
sed -i "s/^landed_vehicle_head=.*/landed_vehicle_head=$m/" "$C/.git/land_vehicle.state"
g "$C" update-ref refs/land/landed "$m"
run "$F/p3.out" publish "$F"
refused "U9e landed head whose tree is not the vehicle tree refused" 2 "landed head's tree differs from the vehicle tree" "$F/p3.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U9c-e no remote moved"; else bad "U9c-e no remote moved"; fi
# U9b: state AND the recorded ref both moved to main: the range from the remote tips still refuses
fixture u9b; F=$T/u9b
run "$F/prep.out" prepare_raw "$F" --item-id CON-802
C=$F/work/constitution
{ printf 'q\n' > "$C/q" && g "$C" add q && g "$C" commit -q -m "no trailer at all"; } 2>/dev/null || true
m=$(g "$C" rev-parse main)
sed -i "s/^main_before=.*/main_before=$m/" "$C/.git/land_vehicle.state"
g "$C" update-ref refs/land/main_before "$m"
run "$F/pub.out" publish "$F"
refused "U9b untrailered commit refused even with state and ref edited" 1 'lacks a single real Roadmap-Item trailer' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U9b no remote moved"; else bad "U9b no remote moved"; fi
# U10: a remote moved AFTER prepare with an untrailered commit and the caller merged it into
# the clone: round 5 refuses it (only commits at or before the prepared base may lack a
# trailer); U10b: prepare again in a new workdir makes it part of the base
fixture u10; F=$T/u10
run "$F/prep.out" prepare_raw "$F" --item-id CON-803
git clone -q "$F/remotes/gitverse.git" "$F/mover"
printf 'n\n' > "$F/mover/n.txt"; g "$F/mover" add n.txt; g "$F/mover" commit -q -m "published elsewhere, no trailer"
g "$F/mover" push -q origin main
pubd=$(rmain "$F" gitverse)
C=$F/work/constitution
g "$C" fetch -q gitverse main
g "$C" merge -q --no-ff -m "merge gitverse main" -m "Roadmap-Item: CON-803" FETCH_HEAD
run "$F/pub.out" publish "$F"
refused "U10 a commit published elsewhere AFTER prepare, without a trailer, is refused" 1 \
  'lacks a single real Roadmap-Item trailer.*run prepare again in a new workdir' "$F/pub.out"
if [ "$(atcount "$F" "$(BASE_OF "$F")")" = 8 ] && [ "$(rmain "$F" gitverse)" = "$pubd" ]; then
  ok "U10 no remote moved (8 at base, gitverse at the commit published elsewhere)"; else bad "U10 remotes moved"; fi
mkdir -p "$F/work2"
run "$F/prep2.out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" \
  --workdir "$F/work2" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev2" --item-id CON-803
succeeded "U10b prepare again in a new workdir exits 0" "$F/prep2.out"
C2=$F/work2/constitution
run "$F/pub2.out" lv publish --workdir "$F/work2" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev2"
allok=1; lm=$(g "$C2" rev-parse main 2>/dev/null || echo none)
for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$lm" ] || allok=0; done
if [ "$RC" -eq 0 ] && [ $allok = 1 ] && g "$C2" merge-base --is-ancestor "$pubd" "$lm"; then
  ok "U10b the commit published before this prepare is not refused; 9 remotes at main"; else bad "U10b (rc=$RC)"; sed 's/^/    | /' "$F/pub2.out"; fi
wrows=$(tail -n +2 "$F/ev2/publish_warnings.tsv" 2>/dev/null || true)
if [ "$(grep -c $'\t'"$pubd"$'\t' <<<"$wrows")" -eq 8 ] && ! grep -q '^gitverse'$'\t' <<<"$wrows" \
   && [ "$(grep -c 'WARN: ' "$F/pub2.out")" -eq 8 ] && grep -q '^## warnings' "$F/ev2/publish.md"; then
  ok "V4 U10b the 8 remotes that receive the untrailered commit get a WARN row (gitverse none)"; else bad "V4 U10b WARN rows"; printf '%s\n' "$wrows" | sed 's/^/    | /'; fi

# ============================================ U11 R2-F4 workdir lock
fixture u11; F=$T/u11
: > "$F/work/.land_vehicle.lock"
run "$F/out" flock -n "$F/work/.land_vehicle.lock" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
  --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint.sh"
refused "U11 prepare refused while another run holds the workdir lock" 2 'holds the lock' "$F/out"
if [ ! -e "$F/work/constitution" ]; then ok "U11 no clone created while locked"; else bad "U11 no clone created while locked"; fi
run "$F/prep.out" prepare "$F"; succeeded "U11 prepare exits 0 once the lock is free" "$F/prep.out"
run "$F/out2" flock -n "$F/work/.land_vehicle.lock" "$LANDER" publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
refused "U11 publish refused while locked" 2 'holds the lock' "$F/out2"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U11 no remote moved while locked"; else bad "U11 no remote moved while locked"; fi
# U11b two concurrent prepares: exactly one wins, the other is refused cleanly (exit 2)
fixture u11b; F=$T/u11b
( rc=0; prepare "$F" > "$F/c1.out" 2>&1 || rc=$?; echo "$rc" > "$F/c1.rc" ) &
pa=$!
( rc=0; prepare "$F" > "$F/c2.out" 2>&1 || rc=$?; echo "$rc" > "$F/c2.rc" ) &
pb=$!
wait "$pa" "$pb" || true
r1=$(cat "$F/c1.rc" 2>/dev/null || echo none); r2=$(cat "$F/c2.rc" 2>/dev/null || echo none)
loser=$F/c1.out; [ "$r2" = 2 ] && loser=$F/c2.out
if { { [ "$r1" = 0 ] && [ "$r2" = 2 ]; } || { [ "$r1" = 2 ] && [ "$r2" = 0 ]; }; } && grep -q 'another land_vehicle run holds the lock' "$loser"; then
  ok "U11b concurrent prepares: one 0, one 2 (the loser says it holds the lock)"; else bad "U11b concurrent prepares (got $r1/$r2)"; cat "$F/c1.out" "$F/c2.out"; fi

# U21 the mint runs without the lock descriptor: a background child it leaves behind
# must not keep the workdir locked for the next run
fixture u21; F=$T/u21
cat > "$F/mint_bg.sh" <<EOF
#!/usr/bin/env bash
mkdir -p docs; printf 'CON-777 minted\\n' >> docs/tracker.fake
sleep 60 </dev/null >/dev/null 2>&1 &
echo \$! > "$F/bg.pid"
echo CON-777
EOF
chmod +x "$F/mint_bg.sh"
run "$F/prep.out" prepare_raw "$F" --mint-cmd "$F/mint_bg.sh"; rcp=$RC
run "$F/pub.out" publish "$F"; rcq=$RC
bgpid=$(cat "$F/bg.pid" 2>/dev/null || true)
# stop only the exact sleep this fixture started (pid recorded by the mint, cmdline checked)
if [[ "$bgpid" =~ ^[0-9]+$ ]] && [ "$(tr '\0' ' ' < "/proc/$bgpid/cmdline" 2>/dev/null)" = "sleep 60 " ]; then kill "$bgpid" 2>/dev/null || true; fi
if [ "$rcp" -eq 0 ] && [ "$rcq" -eq 0 ]; then ok "U21 a background child of the mint does not hold the workdir lock"
else bad "U21 mint child holds the lock (rc=$rcp/$rcq)"; sed 's/^/    | /' "$F/pub.out"; fi

# ============================================ U12 R2-F5 clone name stays inside the workdir
fixture u12; F=$T/u12
for cn in '../escape' 'a/b' '..' '.' '-x' 'a..b' ''; do
  run "$F/out" prepare_raw "$F" --item-id CON-804 --clone-name "$cn"
  if [ -z "$cn" ] || [[ "$cn" == -* ]]; then refused "U12 --clone-name '$cn' refused as a missing value" 2 'option --clone-name needs a value' "$F/out"
  else refused "U12 --clone-name '$cn' refused" 2 'one plain path component' "$F/out"; fi
done
if [ ! -e "$F/escape" ] && [ -z "$(find "$F/work" -mindepth 1 -maxdepth 1 ! -name .land_vehicle.lock)" ]; then
  ok "U12 nothing created outside or inside the workdir"; else bad "U12 nothing created"; ls -la "$F" "$F/work"; fi
run "$F/out" prepare_raw "$F" --item-id CON-804 --clone-name 'ok.name_1-x'
succeeded "U12 a plain --clone-name is accepted" "$F/out"

# ============================================ U13 R2-F6 ambient hooks never run in the clone
mkdir -p "$T/hk3"
for h in pre-commit commit-msg post-commit post-merge post-checkout pre-push reference-transaction post-rewrite pre-merge-commit pre-auto-gc; do
  # shellcheck disable=SC2016 # $PWD is expanded by the hook, not here
  printf '#!/bin/sh\necho "%s $PWD" >> "%s"\n' "$h" "$T/hook_marks" > "$T/hk3/$h"
  chmod +x "$T/hk3/$h"
done
printf 'exit 1\n' >> "$T/hk3/pre-push"
: > "$T/hook_marks"
fixture u13; F=$T/u13            # mint path: commit + merge commit
base_fixture u13b; F2=$T/u13b    # item-id path: fast-forward merge
vc "$F2" x 'feat x\n\nRoadmap-Item: CON-050\n'; mkbundle "$F2"
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$T/hk3"
run "$F/prep.out" prepare "$F"; rp1=$RC
run "$F/pub.out" publish "$F"; rp2=$RC
run "$F2/prep.out" prepare_raw "$F2" --item-id CON-805; rp3=$RC
run "$F2/pub.out" publish "$F2"; rp4=$RC
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath
marks=$(cat "$T/hook_marks")
inclone=$(awk -v a="$F/work/constitution" -v b="$F2/work/constitution" '$2==a || $2==b' <<<"$marks")
if [ "$rp1$rp2$rp3$rp4" = 0000 ] && [ -z "$inclone" ] && grep -q 'step 5: main fast-forwarded' "$F2/prep.out"; then
  ok "U13 no ambient hook ran in the clone (prepare+publish, merge and ff paths)"
else bad "U13 ambient hooks (rc=$rp1/$rp2/$rp3/$rp4)"; printf '%s\n' "$inclone" | sed 's/^/    | /'; cat "$F/pub.out" "$F2/pub.out"; fi
# control needle: the hooks are live (they do run for a plain git command in a repo)
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$T/hk3"
g "$F2/seed" checkout -q main 2>/dev/null || true
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath
if grep -q "post-checkout $F2/seed" "$T/hook_marks"; then ok "U13 control: the ambient hooks are live"; else bad "U13 control: the ambient hooks are live"; fi

# ============================================ U14 R2-F8 help
run "$T/h1.out" "$LANDER" --help
if [ "$RC" -eq 0 ] && grep -q '3 integration refused' "$T/h1.out" && grep -q 'land_vehicle.sh prepare' "$T/h1.out" && ! grep -q 'set -euo' "$T/h1.out"; then
  ok "U14 --help prints the whole usage incl. the exit codes, rc 0"; else bad "U14 --help (rc=$RC)"; fi
run "$T/h2.out" "$LANDER" prepare --help
if [ "$RC" -eq 0 ] && grep -q '3 integration refused' "$T/h2.out"; then ok "U14 prepare --help"; else bad "U14 prepare --help (rc=$RC)"; fi

# ============================================ U15 R2-F10 verify needs the prepare state
mkdir -p "$T/u15/work"
git init -q "$T/u15/work/constitution"
base_fixture u15r
run "$T/u15/out" lv verify --workdir "$T/u15/work" --remotes-file "$T/u15r/remotes.txt"
refused "U15 verify without prepare state refused" 2 'no prepare state' "$T/u15/out"
if [ ! -e "$T/u15/work/evidence" ]; then ok "U15 no evidence dir created"; else bad "U15 no evidence dir created"; fi
run "$T/u15/out2" lv verify --workdir "$T/u15r" --remotes-file "$T/u15r/remotes.txt" --clone-name nothere
refused "U15 verify without a clone refused" 2 'no clone at' "$T/u15/out2"

# ============================================ U16 R2-F7 odd trailer shapes stay fail-closed
base_fixture u16a; F=$T/u16a
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n\n# a comment\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-806
refused "U16 trailing # comment paragraph refused (fail closed)" 1 'lacks a single real Roadmap-Item trailer' "$F/out"
base_fixture u16b; F=$T/u16b
vc "$F" x 'feat x\n\nRoadmap-Item: CON-050\n  continued value\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-807
refused "U16 folded Roadmap-Item value refused (fail closed)" 1 'lacks a single real Roadmap-Item trailer' "$F/out"

# ============================================ U17 (N17) the newest remote tip is chosen at prepare
fixture u17; F=$T/u17
git clone -q "$F/remotes/origin.git" "$F/ahead"
printf 'a\n' > "$F/ahead/ahead.txt"; g "$F/ahead" add ahead.txt; g "$F/ahead" commit -q -m "origin ahead" -m "Roadmap-Item: CON-003"
g "$F/ahead" push -q origin main
ahead=$(rmain "$F" origin)
run "$F/prep.out" prepare_raw "$F" --item-id CON-808
C=$F/work/constitution
mb=$(sed -n 's/^main_before=//p' "$C/.git/land_vehicle.state" 2>/dev/null || true)
if [ "$RC" -eq 0 ] && [ "$mb" = "$ahead" ] && g "$C" merge-base --is-ancestor "$ahead" main; then
  ok "U17 prepare takes the newest remote tip (origin ahead) as main_before"; else bad "U17 newest remote tip (rc=$RC mb=$mb)"; fi
run "$F/pub.out" publish "$F"; succeeded "U17 publish exits 0 (8 behind remotes fast-forwarded)" "$F/pub.out"

# ============================================ U18 (N22) publish refuses a clone not on main
fixture u18; F=$T/u18
run "$F/prep.out" prepare "$F"
g "$F/work/constitution" checkout -q -b elsewhere
run "$F/pub.out" publish "$F"
refused "U18 publish refuses a clone not on main" 2 'clone is not on main' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "U18 no remote moved"; else bad "U18 no remote moved"; fi

# ============================================ U19 (N26/N27) push and ls-remote stderr not shown
fixture u19; F=$T/u19
mv "$F/remotes/m3w.git" "$F/remotes/m3w-SECRETMARK.git"
sed -i "s|^m3w .*|m3w $F/remotes/m3w-SECRETMARK.git|" "$F/remotes.txt"
run "$F/prep.out" prepare "$F"
printf '#!/bin/sh\necho "denied by test hook" >&2\nexit 1\n' > "$F/remotes/m3w-SECRETMARK.git/hooks/pre-receive"
chmod +x "$F/remotes/m3w-SECRETMARK.git/hooks/pre-receive"
run "$F/pub.out" publish "$F"
errlog=$(cat "$F/work/constitution/.git/land_git_stderr.log" 2>/dev/null || true)
if [ "$RC" -eq 1 ] && grep -q '| m3w | push-rejected |' "$F/ev/publish.md" && ! grep -q SECRETMARK "$F/pub.out" && grep -q SECRETMARK <<<"$errlog"; then
  ok "U19 rejected push: URL kept out of the output (and present in the stderr log: control)"; else bad "U19 push stderr (rc=$RC)"; sed 's/^/    | /' "$F/pub.out"; fi
mv "$F/remotes/m3w-SECRETMARK.git" "$F/remotes/m3w-moved.git"
: > "$F/work/constitution/.git/land_git_stderr.log"
run "$F/pub2.out" publish "$F"
errlog=$(cat "$F/work/constitution/.git/land_git_stderr.log" 2>/dev/null || true)
if [ "$RC" -eq 1 ] && grep -q '| m3w | refused-no-main-or-unreadable |' "$F/ev/publish.md" && ! grep -q SECRETMARK "$F/pub2.out" && grep -q SECRETMARK <<<"$errlog"; then
  ok "U19 unreadable remote: ls-remote URL kept out of the output (control: in the log)"; else bad "U19 ls-remote stderr (rc=$RC)"; sed 's/^/    | /' "$F/pub2.out"; fi
run "$F/ver.out" lv verify --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"
if [ "$RC" -eq 1 ] && ! grep -q SECRETMARK "$F/ver.out"; then ok "U19 verify: URL kept out of the output"; else bad "U19 verify stderr (rc=$RC)"; fi

# ============================================ U20 (N41) git bundle verify is enforced
base_fixture u20; F=$T/u20
g "$F/seed" checkout -q -b pre main
vc "$F" p.txt 'pre\n\nRoadmap-Item: CON-050\n'
g "$F/seed" checkout -q -B vehicle pre
vc "$F" v.txt 'v\n\nRoadmap-Item: CON-050\n'
g "$F/seed" bundle create -q "$F/vehicle.bundle" vehicle ^pre 2>/dev/null
g "$F/seed" rev-parse vehicle > "$F/head"
sha256sum "$F/vehicle.bundle" | awk '{print $1}' > "$F/sha"
run "$F/out" prepare_raw "$F" --item-id CON-809
refused "U20 bundle with a missing prerequisite refused by git bundle verify" 1 'git bundle verify failed' "$F/out"

# ##################################################################### round 4
# ============================================ V1 R3-1/R3-10 a remotes-file line never echoes a URL
fixture v1; F=$T/v1
printf 'https://user:SECRETTOKEN123@example.invalid/x.git\n' > "$F/r_urlonly.txt"
run "$F/o1" lv verify --workdir "$F/work" --remotes-file "$F/r_urlonly.txt"
refused "V1 a remotes line holding only a URL is refused by its line number" 2 'remotes file line 1: ' "$F/o1"
{ cat "$F/remotes.txt"; printf 'origin https://u:SECRETTOKEN124@example.invalid/y.git extra\n'; } > "$F/r_extra3.txt"
run "$F/o2" lv verify --workdir "$F/work" --remotes-file "$F/r_extra3.txt"
refused "V1 a remotes line with a third field is refused (line 10)" 2 'remotes file line 10: ' "$F/o2"
printf 'https://u:SECRETTOKEN125@example.invalid/z.git origin\n' > "$F/r_badname.txt"
run "$F/o3" lv verify --workdir "$F/work" --remotes-file "$F/r_badname.txt"
refused "V1 a remote name that is not a plain name is refused by line number" 2 'remotes file line 1: the remote name' "$F/o3"
leaks=$(cat "$F/o1" "$F/o2" "$F/o3")
if ! grep -q 'SECRETTOKEN' <<<"$leaks" && [ -z "$(grep -rl 'SECRETTOKEN' "$F/work" 2>/dev/null || true)" ] && [ ! -e "$F/ev" ] \
   && grep -q 'SECRETTOKEN12[345]' "$F/r_urlonly.txt" "$F/r_extra3.txt" "$F/r_badname.txt"; then
  ok "V1 the credential token appears 0 times in output and workdir (control: present in the inputs)"
else bad "V1 credential token leaked"; printf '%s\n' "$leaks" | sed 's/^/    | /'; fi
for nm in '-x' 'a/b' '.x'; do
  printf '%s %s\n' "$nm" "$F/remotes/origin.git" > "$F/r_nm.txt"
  run "$F/o4" env LANDER_REMOTES="$nm" PATH="$T/shim:$PATH" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/r_nm.txt"
  refused "V1d remote name '$nm' refused before any git call" 2 'remote name' "$F/o4"
done

sed 's|^origin .*|origin --upload-pack=touch_x|' "$F/remotes.txt" > "$F/r_dashurl.txt"
run "$F/o5" lv verify --workdir "$F/work" --remotes-file "$F/r_dashurl.txt"
refused "V1e a URL starting with '-' is refused by line number" 2 "remotes file line 9: the URL must not start with '-'" "$F/o5"

# ============================================ V2 R3-2 repository env vars of the caller are cleared
vsum() { # vsum <repo>: fingerprint of a scratch repo's git state and its work tree
  local V=$1 f
  ( cd "$V" && {
      for f in .git/config .git/index .git/HEAD .git/refs/heads/main .git/logs/HEAD .git/logs/refs/heads/main; do
        if [ -e "$f" ]; then sha256sum "$f"; else echo "absent $f"; fi
      done
      # shellcheck disable=SC2012 # the .git entry names are git's own, plain ASCII
      ls -A .git | LC_ALL=C sort | tr '\n' ' '; echo
      find .git/objects .git/refs -type f | LC_ALL=C sort | sha256sum
      find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs -r sha256sum
    } )
}
mkvictim() { # mkvictim <dir>: scratch repo with one local-only commit and a staged file (never a live checkout)
  git init -q "$1"; printf 'mine\n' > "$1/precious.txt"; g "$1" add precious.txt
  g "$1" commit -q -m "local only work" -m "Roadmap-Item: CON-005"
  printf 'staged-only\n' > "$1/staged.txt"; g "$1" add staged.txt
}
# (landed_all, lvenv, PREP_ARGS, seed_main_file and mkmint are defined with the round-5 helpers)
# V2a GIT_DIR exported by the caller (as in a git hook)
fixture v2a; F=$T/v2a; V=$T/v2a_victim; mkvictim "$V"; vb=$(vsum "$V")
mapfile -t pa < <(PREP_ARGS "$F")
run "$F/prep.out" lvenv GIT_DIR="$V/.git" -- prepare "${pa[@]}" --mint-cmd "$F/mint.sh"; r1=$RC
run "$F/pub.out" lvenv GIT_DIR="$V/.git" -- publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; r2=$RC
if [ "$r1$r2" = 00 ] && landed_all "$F" && [ "$(vsum "$V")" = "$vb" ] && [ -s "$F/work/constitution/.git/land_vehicle.state" ]; then
  ok "V2a exported GIT_DIR: prepare+publish land in the fresh clone, the victim repo is byte-identical"
else bad "V2a exported GIT_DIR (rc=$r1/$r2)"; sed 's/^/    | /' "$F/prep.out" | tail -5; fi
# V2b GIT_WORK_TREE exported by the caller
fixture v2b; F=$T/v2b; VW=$T/v2b_victim_wt; mkdir -p "$VW"; printf 'precious-a\n' > "$VW/a.txt"; printf 'keep\n' > "$VW/keep.txt"
wb=$(cd "$VW" && ls -A && sha256sum a.txt keep.txt)
mapfile -t pa < <(PREP_ARGS "$F")
run "$F/prep.out" lvenv GIT_WORK_TREE="$VW" -- prepare "${pa[@]}" --item-id CON-822; r1=$RC
if [ "$r1" = 0 ] && [ "$(cd "$VW" && ls -A && sha256sum a.txt keep.txt)" = "$wb" ] && [ -s "$F/work/constitution/v2.txt" ]; then
  ok "V2b exported GIT_WORK_TREE: prepare exits 0, the victim directory is unchanged"
else bad "V2b exported GIT_WORK_TREE (rc=$r1)"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
# V2c GIT_INDEX_FILE exported by the caller (git exports it to pre-commit hooks)
fixture v2c; F=$T/v2c; V=$T/v2c_victim; mkvictim "$V"; vb=$(vsum "$V")
mapfile -t pa < <(PREP_ARGS "$F")
run "$F/prep.out" lvenv GIT_INDEX_FILE="$V/.git/index" -- prepare "${pa[@]}" --mint-cmd "$F/mint.sh"; r1=$RC
run "$F/pub.out" lvenv GIT_INDEX_FILE="$V/.git/index" -- publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; r2=$RC
if [ "$r1$r2" = 00 ] && landed_all "$F" && [ "$(vsum "$V")" = "$vb" ] && [ -e "$F/work/constitution/.git/index" ]; then
  ok "V2c exported GIT_INDEX_FILE: the victim index is byte-identical, the clone uses its own index"
else bad "V2c exported GIT_INDEX_FILE (rc=$r1/$r2)"; tail -3 "$F/pub.out" | sed 's/^/    | /'; fi
# V2d GIT_NAMESPACE exported on publish (receive-pack would write refs/namespaces/...)
fixture v2d; F=$T/v2d
run "$F/prep.out" prepare_raw "$F" --item-id CON-823
run "$F/pub.out" lvenv GIT_NAMESPACE=evil -- publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; r2=$RC
nsr=0; for r in $REMOTES; do nsr=$((nsr + $(git --git-dir="$F/remotes/$r.git" for-each-ref refs/namespaces | wc -l))); done
if [ "$r2" = 0 ] && landed_all "$F" && [ "$nsr" = 0 ]; then ok "V2d exported GIT_NAMESPACE: refs/heads/main of all 9 remotes moved, no namespaced ref"
else bad "V2d exported GIT_NAMESPACE (rc=$r2, namespaced refs=$nsr)"; fi
# V2e/V2f config injected through the environment (GIT_CONFIG_COUNT / GIT_CONFIG_PARAMETERS)
for v in e f; do
  fixture "v2$v"; F=$T/v2$v
  git clone -q --bare "$F/remotes/origin.git" "$F/evil.git"
  git clone -q "$F/evil.git" "$F/evilw"; printf 'e\n' > "$F/evilw/e.txt"; g "$F/evilw" add e.txt
  g "$F/evilw" commit -q -m "evil" -m "Roadmap-Item: CON-666"; g "$F/evilw" push -q origin main
  evil=$(git --git-dir="$F/evil.git" rev-parse main)
  mapfile -t pa < <(PREP_ARGS "$F")
  if [ "$v" = e ]; then
    run "$F/prep.out" lvenv GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$F/evil.git.insteadOf" GIT_CONFIG_VALUE_0="$F/remotes/origin.git" -- prepare "${pa[@]}" --item-id CON-824
  else
    run "$F/prep.out" lvenv GIT_CONFIG_PARAMETERS="'url.$F/evil.git.insteadof'='$F/remotes/origin.git'" -- prepare "${pa[@]}" --item-id CON-825
  fi
  mb=$(sed -n 's/^main_before=//p' "$F/work/constitution/.git/land_vehicle.state" 2>/dev/null || true)
  # control needle: the same injection does redirect a plain git fetch outside the lander
  if [ "$v" = e ]; then cn=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$F/evil.git.insteadOf" GIT_CONFIG_VALUE_0="$F/remotes/origin.git" git ls-remote "$F/remotes/origin.git" refs/heads/main | awk '{print $1}')
  else cn=$(GIT_CONFIG_PARAMETERS="'url.$F/evil.git.insteadof'='$F/remotes/origin.git'" git ls-remote "$F/remotes/origin.git" refs/heads/main | awk '{print $1}'); fi
  if [ "$RC" = 0 ] && [ "$mb" = "$(BASE_OF "$F")" ] && ! g "$F/work/constitution" merge-base --is-ancestor "$evil" main 2>/dev/null && [ "$cn" = "$evil" ]; then
    ok "V2$v config injected via the environment is ignored (control: it redirects a plain git call)"
  else bad "V2$v env config injection (rc=$RC mb=$mb control=$cn evil=$evil)"; tail -3 "$F/prep.out" | sed 's/^/    | /'; fi
done
# V2g GIT_TRACE would print every remote URL to the caller's terminal
fixture v2g; F=$T/v2g
mv "$F/remotes/origin.git" "$F/remotes/origin-SECRETMARK.git"
sed -i "s|^origin .*|origin $F/remotes/origin-SECRETMARK.git|" "$F/remotes.txt"
mapfile -t pa < <(PREP_ARGS "$F")
run "$F/prep.out" lvenv GIT_TRACE=1 GIT_TRACE_SETUP=1 GIT_TRACE_PACKET=1 -- prepare "${pa[@]}" --item-id CON-826; r1=$RC
run "$F/pub.out" lvenv GIT_TRACE=1 GIT_TRACE_SETUP=1 GIT_TRACE_PACKET=1 -- publish --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev"; r2=$RC
tc=$(GIT_TRACE=1 git ls-remote "$F/remotes/origin-SECRETMARK.git" 2>&1 >/dev/null | grep -c SECRETMARK || true)
if [ "$r1$r2" = 00 ] && ! grep -q SECRETMARK "$F/prep.out" "$F/pub.out" && [ "$tc" -ge 1 ]; then
  ok "V2g GIT_TRACE* cleared: no URL in the output (control: GIT_TRACE prints it for a plain git call)"
else bad "V2g GIT_TRACE (rc=$r1/$r2 control=$tc)"; grep -m3 SECRETMARK "$F/prep.out" "$F/pub.out" | sed 's/^/    | /'; fi

# ============================================ V3 R3-3 the minted id must be new
base_fixture v3a; F=$T/v3a
seed_main_file "$F" docs/tracker.fake 'CON-100 old item\nCON-7770 other item\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/mint_old.sh" 'CON-777 minted' CON-100
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_old.sh"
refused "V3a a mint that prints a PRE-EXISTING id is refused" 1 'CON-100 already appears in docs/tracker.fake before the mint' "$F/out"
if [ ! -e "$F/work/constitution/.git/land_vehicle.state" ] && [ "$(g "$F/work/constitution" rev-parse main 2>/dev/null || true)" = "$(BASE_OF "$F")" ]; then
  ok "V3a nothing landed"; else bad "V3a nothing landed"; fi
base_fixture v3b; F=$T/v3b
seed_main_file "$F" docs/tracker.fake 'CON-100 old item\nCON-7770 other item\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/mint_new.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_new.sh"
succeeded "V3b a new id CON-777 is accepted although CON-7770 was already there (no false refusal)" "$F/out"
fixture v3c; F=$T/v3c
mkmint "$F/mint_sub.sh" 'CON-0770 minted' CON-077
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_sub.sh"
refused "V3c id CON-077 is not found inside CON-0770 (token match)" 1 'printed CON-077 but no changed file in the clone contains it' "$F/out"
fixture v3d; F=$T/v3d
printf '#!/usr/bin/env bash\necho "## CON-7770 (minted)"\n' > "$F/show_other.sh"; chmod +x "$F/show_other.sh"
run "$F/out" prepare "$F" --id-verify-cmd "\"$F/show_other.sh\" \"\$1\""
refused "V3d an engine read printing CON-7770 does not confirm CON-777" 1 'did not print CON-777' "$F/out"

# V3e a binary tracker file (holds a NUL byte): an earlier occurrence followed by a
# digit byte still counts as "already there" (fail closed: binary neighbours may be digits)
base_fixture v3e; F=$T/v3e
seed_main_file "$F" docs/tracker.fake 'head\0CON-7775\0tail\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
mkmint "$F/mint_bin.sh" 'CON-777 minted' CON-777
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_bin.sh"
refused "V3e binary tracker: CON-777 inside CON-7775 counts as already there (fail closed)" 1 'CON-777 already appears in docs/tracker.fake before the mint' "$F/out"

# ============================================ V4 R3-4 per-remote WARN rows for already-published commits
base_fixture v4; F=$T/v4
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-PENDING-early\n'; vc "$F" v2.txt 'feat: two\n\nRoadmap-Item: CON-PENDING-x\n'; mkbundle "$F"
early=$(g "$F/seed" rev-parse vehicle~1)
g "$F/seed" push -q "$F/remotes/github.git" vehicle~1:refs/heads/main
run "$F/prep.out" prepare_raw "$F" --item-id CON-831
run "$F/pub.out" publish "$F"
wrows=$(tail -n +2 "$F/ev/publish_warnings.tsv" 2>/dev/null || true)
if [ "$RC" -eq 0 ] && landed_all "$F" && [ "$(grep -c $'\t'"$early"$'\t' <<<"$wrows")" -eq 8 ] && ! grep -q '^github'$'\t' <<<"$wrows" \
   && [ "$(grep -c 'WARN: ' "$F/pub.out")" -eq 8 ]; then
  ok "V4 a placeholder commit already on github gets a WARN row for each of the 8 remotes it reaches"
else bad "V4 WARN rows (rc=$RC)"; printf '%s\n' "$wrows" | sed 's/^/    | /'; fi
if [ "$(head -1 "$F/ev/publish_warnings.tsv" 2>/dev/null)" = "$(printf 'remote\tcommit\treason')" ] && [ "$(wc -l < "$F/ev/publish_warnings.tsv")" -eq 9 ]; then
  ok "V4 publish_warnings.tsv has a header and exactly 8 rows"; else bad "V4 publish_warnings.tsv shape"; fi

# ============================================ V5 R3-5 a git child (gpg) never inherits the lock fd
fixture v5; F=$T/v5
: > "$F/bg.pids"
cat > "$T/fakegpg" <<EOF
#!/usr/bin/env bash
cat > /dev/null
( exec sleep 30 ) </dev/null >/dev/null 2>&1 &
echo \$! >> "$F/bg.pids"
printf '\n[GNUPG:] SIG_CREATED D 1 8 00 1 X\n' >&2
printf -- '-----BEGIN PGP SIGNATURE-----\n\nZmFrZQ==\n-----END PGP SIGNATURE-----\n'
EOF
chmod +x "$T/fakegpg"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign true
git config --file "$GIT_CONFIG_GLOBAL" gpg.program "$T/fakegpg"
git config --file "$GIT_CONFIG_GLOBAL" user.signingkey X
run "$F/prep.out" prepare "$F"; rcp=$RC
git config --file "$GIT_CONFIG_GLOBAL" --unset commit.gpgsign
git config --file "$GIT_CONFIG_GLOBAL" --unset gpg.program
git config --file "$GIT_CONFIG_GLOBAL" --unset user.signingkey
if flock -n "$F/work/.land_vehicle.lock" true; then free=1; else free=0; fi
run "$F/pub.out" publish "$F"; rcq=$RC
nsig=$(wc -l < "$F/bg.pids")
while IFS= read -r bgp; do   # stop only the sleeps this fixture started (pid recorded, cmdline checked)
  if [[ "$bgp" =~ ^[0-9]+$ ]] && [ "$bgp" -gt 1 ] && [ "$(tr '\0' ' ' < "/proc/$bgp/cmdline" 2>/dev/null)" = "sleep 30 " ]; then kill "$bgp" 2>/dev/null || true; fi
done < "$F/bg.pids"
if [ "$rcp" = 0 ] && [ "$nsig" -ge 1 ] && [ "$free" = 1 ] && [ "$rcq" = 0 ]; then
  ok "V5 a gpg child left running by a signed commit does not hold the workdir lock ($nsig gpg runs: control)"
else bad "V5 lock fd inherited by a git child (rc=$rcp/$rcq gpg_runs=$nsig lock_free=$free)"; tail -3 "$F/pub.out" | sed 's/^/    | /'; fi

# ============================================ V6 R3-6 ambient push.followTags pushes no tag
fixture v6; F=$T/v6
run "$F/prep.out" prepare_raw "$F" --item-id CON-836
g "$F/work/constitution" tag -a -m "derived step tag" v-derived main
git config --file "$GIT_CONFIG_GLOBAL" push.followTags true
run "$F/pub.out" publish "$F"; rcq=$RC
git config --file "$GIT_CONFIG_GLOBAL" --unset push.followTags
nt=0; for r in $REMOTES; do git --git-dir="$F/remotes/$r.git" rev-parse -q --verify refs/tags/v-derived >/dev/null && nt=$((nt + 1)); done
if [ "$rcq" = 0 ] && [ "$nt" = 0 ] && landed_all "$F"; then ok "V6 push.followTags=true in the caller config: 0 of 9 remotes got the tag"
else bad "V6 followTags (rc=$rcq, remotes with the tag: $nt)"; fi

# ============================================ V7 R3-7 ambient status.showUntrackedFiles=no
fixture v7; F=$T/v7
run "$F/prep.out" prepare_raw "$F" --item-id CON-837
printf 'derived\n' > "$F/work/constitution/derived_new.md"
git config --file "$GIT_CONFIG_GLOBAL" status.showUntrackedFiles no
run "$F/pub.out" publish "$F"
git config --file "$GIT_CONFIG_GLOBAL" --unset status.showUntrackedFiles
refused "V7 an untracked file is seen although status.showUntrackedFiles=no" 2 'uncommitted changes' "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "V7 no remote moved"; else bad "V7 no remote moved"; fi

# ============================================ V8 R3-8 the mint may only add or modify tracker paths
fixture v8a; F=$T/v8a
printf '#!/usr/bin/env bash\nrm -f a.txt; mkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake; echo CON-777\n' > "$F/mint_del.sh"; chmod +x "$F/mint_del.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_del.sh"
refused "V8a a mint that deletes a tracked file is refused" 1 'mint command changed a path it may not change \(D a\.txt\)' "$F/out"
if grep -qx $'D\ta.txt' "$F/ev/mint_changes.tsv" 2>/dev/null && [ ! -e "$F/work/constitution/.git/land_vehicle.state" ]; then
  ok "V8a the deletion is recorded in mint_changes.tsv; nothing landed"; else bad "V8a deletion evidence"; fi
fixture v8b; F=$T/v8b
printf '#!/usr/bin/env bash\nmkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake; printf "x\\n" > README.md; echo CON-777\n' > "$F/mint_out.sh"; chmod +x "$F/mint_out.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_out.sh"
refused "V8b a mint that writes outside LANDER_TRACKER_PATHS is refused" 1 'may not change \(A README\.md\)' "$F/out"

fixture v8c; F=$T/v8c
printf '#!/usr/bin/env bash\nmkdir -p docs; ln -s CON-777 docs/tracker.fake; echo CON-777\n' > "$F/mint_ln.sh"; chmod +x "$F/mint_ln.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_ln.sh"
refused "V8c a mint that leaves the tracker path as a symlink is refused" 1 'docs/tracker.fake as a non-regular file \(mode 120000\)' "$F/out"

# ============================================ V8d-V16 round-4 mutant-driven checks (Z09, Z14, Z20, Z23)
# V8d (Z09) a deleted file is refused even when it is inside LANDER_TRACKER_PATHS
base_fixture v8d; F=$T/v8d
seed_main_file "$F" docs/old.txt 'old\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\nrm -f docs/old.txt; printf "CON-777 minted\\n" >> docs/tracker.fake; echo CON-777\n' > "$F/mint_del2.sh"; chmod +x "$F/mint_del2.sh"
run "$F/out" env LANDER_TRACKER_PATHS="docs/old.txt docs/tracker.fake" PATH="$T/shim:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
  --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint_del2.sh"
refused "V8d deleting a file that IS a tracker path is still refused as a deletion" 1 'mint command changed a path it may not change \(D docs/old\.txt\)' "$F/out"

# V14 (Z14) a bad name in LANDER_REMOTES itself is refused with its own message
fixture v14; F=$T/v14
run "$F/out" env LANDER_REMOTES="origin a/b" "$LANDER" verify --workdir "$F/work" --remotes-file "$F/remotes.txt"
refused "V14 LANDER_REMOTES holding 'a/b' is refused" 2 'LANDER_REMOTES holds a bad remote name' "$F/out"

# V15 (Z20, round 5) a PATH shim changes the index inside the lander's `git write-tree`, after
# every check of the recorded mint changes: the tree differs from the record, so the lander refuses
mkdir -p "$T/shim_wt"
cat > "$T/shim_wt/git" <<'EOF'
#!/usr/bin/env bash
args=("$@"); n=$#; i=0; dir=
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    -c) i=$((i + 2)) ;;
    -C) dir=${args[$((i + 1))]}; i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) break ;;
  esac
done
if [ "$i" -lt "$n" ] && [ "${args[$i]}" = write-tree ] && [ -n "$dir" ]; then
  case "${LV_WT_MODE:-}" in
    swap) printf 'CON-777 minted\nswapped after the checks\n' > "$dir/docs/tracker.fake"; @REALGIT@ -C "$dir" add docs/tracker.fake ;;
    extra) printf 'injected\n' > "$dir/docs/injected.fake"; @REALGIT@ -C "$dir" add docs/injected.fake ;;
  esac
  echo "write-tree fault injected (${LV_WT_MODE:-none})" >&2
fi
exec @REALGIT@ "$@"
EOF
sed -i "s#@REALGIT@#$REALGIT#g" "$T/shim_wt/git"; chmod +x "$T/shim_wt/git"
for mode in swap extra; do
  fixture "v15$mode"; F=$T/v15$mode
  run "$F/out" env LV_WT_MODE="$mode" PATH="$T/shim_wt:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
    --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint.sh"
  refused "V15 ($mode) a mint tree that differs from the recorded mint changes is refused" 1 \
    'the mint commit differs from the recorded mint changes \(the index changed after the checks\)' "$F/out"
  if grep -qF "write-tree fault injected ($mode)" "$F/out" && [ ! -e "$F/work/constitution/.git/land_vehicle.state" ]; then
    ok "V15 ($mode) the fault was really injected (control); nothing landed"; else bad "V15 ($mode) fault not injected or state written"; fi
done

# V16 (Z23, round 5) a clean filter named by the caller's core.attributesFile does not apply: the
# lander pins core.attributesFile=/dev/null, so the staged tracker holds the id and prepare succeeds
fixture v16; F=$T/v16
gccopy "$F"
printf 'docs/tracker.fake filter=hideid\n' > "$F/attrs"
gcset "$F" core.attributesFile "$F/attrs"
gcset "$F" filter.hideid.clean 'sed s/CON-777/CON-XXX/'
run "$F/out" prep_gc "$F" --mint-cmd "$F/mint.sh"
committed=$(g "$F/work/constitution" show main:docs/tracker.fake 2>/dev/null || true)
git init -q "$F/ctl"; mkdir -p "$F/ctl/docs"; printf 'CON-777 minted\n' > "$F/ctl/docs/tracker.fake"
GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/ctl" add docs/tracker.fake 2>/dev/null || true
cstaged=$(git -C "$F/ctl" cat-file blob :docs/tracker.fake 2>/dev/null || true)
if [ "$RC" -eq 0 ] && grep -q 'CON-777' <<<"$committed" && grep -q 'CON-XXX' <<<"$cstaged"; then
  ok "V16 core.attributesFile from the caller config is ignored: the tracker is committed with CON-777 (control: git add under that config stages CON-XXX)"
else bad "V16 attributesFile (rc=$RC committed=[$committed] control=[$cstaged])"; sed 's/^/    | /' "$F/out"; fi
# V16c the same filter named by an IN-TREE .gitattributes cannot be pinned away; the presence
# check reads the staged blob, so it refuses
base_fixture v16c; F=$T/v16c
seed_main_file "$F" .gitattributes 'docs/tracker.fake filter=hideid\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
gccopy "$F"; gcset "$F" filter.hideid.clean 'sed s/CON-777/CON-XXX/'
run "$F/out" prep_gc "$F" --mint-cmd "$F/mint.sh"
refused "V16c an id that an in-tree attribute's clean filter strips from the staged tracker is refused" 1 'printed CON-777 but no changed file in the clone contains it' "$F/out"
staged=$(git -C "$F/work/constitution" cat-file blob :docs/tracker.fake 2>/dev/null || true)
if grep -q 'CON-777' "$F/work/constitution/docs/tracker.fake" 2>/dev/null && grep -q 'CON-XXX' <<<"$staged"; then
  ok "V16c control: the worktree holds CON-777 and the staged blob holds CON-XXX"; else bad "V16c control (staged: $staged)"; fi

# ============================================ V9 T-1 checks the earlier tests did not pin
# V9a (MR01) a second push URL behind a matching first one
fixture v9a; F=$T/v9a
run "$F/prep.out" prepare_raw "$F" --item-id CON-841
git init -q --bare "$F/sink.git"
g "$F/work/constitution" config --add remote.origin.pushurl "$F/remotes/origin.git"
g "$F/work/constitution" config --add remote.origin.pushurl "$F/sink.git"
run "$F/pub.out" publish "$F"
refused "V9a a second push URL after the declared one is refused" 2 "remote 'origin' push URL\(s\) in the clone differ" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")" && ! git --git-dir="$F/sink.git" rev-parse -q --verify main >/dev/null; then
  ok "V9a nothing pushed, the sink got nothing"; else bad "V9a nothing pushed"; fi
# V9b (MR02) receivepack and uploadpack
fixture v9b; F=$T/v9b
run "$F/prep.out" prepare_raw "$F" --item-id CON-842
for key in receivepack uploadpack; do
  g "$F/work/constitution" config "remote.origin.$key" "git-$key"
  run "$F/pub_$key.out" publish "$F"
  refused "V9b remote.origin.$key set in the clone is refused" 2 "remote.origin.$key set" "$F/pub_$key.out"
  g "$F/work/constitution" config --unset "remote.origin.$key"
done
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "V9b no remote moved"; else bad "V9b no remote moved"; fi
# V9c (MR04) a mint that switches branch without moving the commit
fixture v9c; F=$T/v9c
printf '#!/usr/bin/env bash\ngit checkout -q -b other\nmkdir -p docs; printf "CON-777 minted\\n" >> docs/tracker.fake; echo CON-777\n' > "$F/mint_br.sh"; chmod +x "$F/mint_br.sh"
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_br.sh"
refused "V9c a mint that switches the branch is refused" 1 'moved HEAD or committed by itself' "$F/out"
# V9d (MR08) the server accepts the push and a post-receive hook rewinds main
fixture v9d; F=$T/v9d
run "$F/prep.out" prepare_raw "$F" --item-id CON-844
printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$(BASE_OF "$F")" > "$F/remotes/m3w.git/hooks/post-receive"
chmod +x "$F/remotes/m3w.git/hooks/post-receive"
run "$F/pub.out" publish "$F"
if [ "$RC" -eq 1 ] && grep -q 'one or more remotes FAIL' "$F/pub.out" && grep -q '| m3w | pushed |.*| FAIL |' "$F/ev/publish.md" \
   && [ "$(grep -c '| PASS |' "$F/ev/publish.md")" -eq 8 ]; then
  ok "V9d a push the server rewound is FAIL in the read-back, not PASS"; else bad "V9d post-receive rewind (rc=$RC)"; cat "$F/ev/publish.md" 2>/dev/null || true; fi
# V9e (MR22) a clone URL that only starts with the declared URL
fixture v9e; F=$T/v9e
run "$F/prep.out" prepare_raw "$F" --item-id CON-845
sed "s|^origin .*|origin $F/remotes/origin|" "$F/remotes.txt" > "$F/r_prefix.txt"
run "$F/pub.out" lv publish --workdir "$F/work" --remotes-file "$F/r_prefix.txt" --evidence-dir "$F/ev"
refused "V9e a clone URL that merely starts with the declared URL is refused" 2 "remote 'origin' fetch URL in the clone differs" "$F/pub.out"
if no_remote_moved "$F" "$(BASE_OF "$F")"; then ok "V9e no remote moved"; else bad "V9e no remote moved"; fi

# ============================================ V11 R3-9 --workdir is never an option to cd; CDPATH ignored
fixture v11; F=$T/v11
mkdir -p "$F/oldpwd_decoy"
for wd in - -Pzz; do   # (never a bare -P/-L here: on a lander without the check, `cd -P` would go to HOME)
  run "$F/o_$wd" env OLDPWD="$F/oldpwd_decoy" PATH="$T/shim:$PATH" "$LANDER" verify --workdir "$wd" --remotes-file "$F/remotes.txt"
  refused "V11 --workdir '$wd' refused" 2 "--workdir must not start with '-'" "$F/o_$wd"
done
if [ ! -e "$F/oldpwd_decoy/.land_vehicle.lock" ]; then ok "V11 '--workdir -' did not take OLDPWD as the workdir"; else bad "V11 '--workdir -' used OLDPWD"; fi
mkdir -p "$F/decoy/work"
run "$F/o_cd" env -C "$F" CDPATH="$F/decoy" PATH="$T/shim:$PATH" "$LANDER" verify --workdir work --remotes-file "$F/remotes.txt"
if [ "$RC" -eq 2 ] && grep -qF "no clone at $F/work/constitution" "$F/o_cd" && [ ! -e "$F/decoy/work/.land_vehicle.lock" ]; then
  ok "V11 a relative --workdir is resolved against the current directory, not CDPATH"
else bad "V11 CDPATH (rc=$RC)"; sed 's/^/    | /' "$F/o_cd"; fi

# ============================================ V12 R3-10 dangling symlink at the clone path
fixture v12; F=$T/v12
ln -s "$T/v12_elsewhere/constitution" "$F/work/constitution"
run "$F/out" prepare_raw "$F" --item-id CON-846
refused "V12 a dangling symlink at the clone path is refused (exit 2, not a raw git code)" 2 'clone path already exists' "$F/out"
if [ ! -e "$T/v12_elsewhere" ]; then ok "V12 nothing created at the symlink target"; else bad "V12 nothing created at the symlink target"; fi

# ============================================ V13 R3-10 a raw git status never leaks as the exit code
# (fixture: a second PATH shim fails exactly `git ... rev-parse HEAD` with status 128)
fixture v13; F=$T/v13
mkdir -p "$T/shim_fail"
cat > "$T/shim_fail/git" <<EOF
#!/usr/bin/env bash
n=\$#
if [ \$n -ge 2 ] && [ "\${@:\$((n - 1)):1}" = rev-parse ] && [ "\${@:\$n:1}" = HEAD ]; then echo "fault injected" >&2; exit 128; fi
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/shim_fail/git"
run "$F/out" env PATH="$T/shim_fail:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
  --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint.sh"
refused "V13 a failing git call exits 1 (not git's 128) with a message" 1 'a command failed with status 128' "$F/out"
if grep -q 'fault injected' "$F/out"; then ok "V13 the fault was really injected (control)"; else bad "V13 fault not injected"; fi

# ============================================ SH0 exactly one push call site in the lander
push_sites() { grep -v '^[[:space:]]*#' "$1" | grep -cE '(^|[[:space:];|&(])(g|git)([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+(push|send-pack)[[:space:]]' || true; }
cp "$LANDER" "$T/needle.sh"; printf '%s\n' 'g push -q x y' >> "$T/needle.sh"
if [ "$(push_sites "$LANDER")" -eq 1 ] && [ "$(push_sites "$T/needle.sh")" -eq 2 ]; then
  ok "SH0 the lander has exactly one push call site (control: an added push line counts 2)"
else bad "SH0 push call sites: $(push_sites "$LANDER") (needle $(push_sites "$T/needle.sh"))"; fi
# shellcheck disable=SC2016 # the lander's literal source text is searched, nothing expands
if grep -qF 'g push -q --no-verify --no-follow-tags --recurse-submodules=no "${R_NAMES[$i]}" "$local_main:refs/heads/main"' "$LANDER"; then
  ok "SH0 the push call site pushes the checked sha to refs/heads/main"; else bad "SH0 the push call site text"; fi

# ============================================ SH2 every push the lander made in this run was plain
if push_log_clean; then ok "SH2 all $(wc -l < "$PUSHLOG") recorded pushes of the round-4 cases are plain <sha>:refs/heads/main pushes"; else bad "SH2 recorded pushes"; fi

printf '\nRESULT pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
