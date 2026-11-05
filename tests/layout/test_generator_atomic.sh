#!/usr/bin/env bash
# tests/layout/test_generator_atomic.sh -- scripts/generate_agent_prefix_commands.sh
# atomicity + concurrency + validation (11.4.224 / 11.4.115 / 9.2).
# Forensic: a SIGKILL mid-prune left tracked generated command files missing (gemini 0/24, qwen 7/24).
# Asserts:
#  (1) SIGKILL at each deterministic checkpoint leaves EVERY generated file in place;
#  (2) 3 runs are byte-identical to the COMMITTED output (git HEAD of the tree under test);
#  (3) prune removes a removed action's marker-carrying files and keeps hand-written ones;
#  (4) no .gen.* staging dir after a normal run, after SIGTERM (prompt exit), or after a killed run + rerun;
#  (5) two concurrent runs on one output root both succeed and the files stay complete (flock);
#  (6) validation compares against the registry's action count: a dropped (lookup-failing) action
#      and a lowercase-name collision abort with nothing changed; an invalid registry aborts with nothing changed;
#  (7) the test pause hook is inert without HELIX_TEST_MODE=1 and with a pause dir outside the temp root;
#  (8) staging lives inside each destination dir (same filesystem), and the header/.gitignore document it.
# Env: LAYOUT_SRC_ROOT (tree under test, default this repo; shared harness convention),
#      GEN_KILL_POINTS (default "after_stage mid_commit before_prune").
# The pause hook inside the generator is honoured only with HELIX_TEST_MODE=1 and a dir under the temp root.
LT_SUITE="generator_atomic"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"
GEN_SRC_ROOT="$LAYOUT_SRC_ROOT"
KILL_POINTS="${GEN_KILL_POINTS:-after_stage mid_commit before_prune}"
TB="$LT_SB"

mkwork() { # name -> prints work dir (copy of generator + registry, no generated output)
  local w="$TB/$1" f; mkdir -p "$w/actions"
  cp -a "$GEN_SRC_ROOT/scripts" "$w/scripts"
  for f in "$GEN_SRC_ROOT"/actions/*; do [ "$(basename "$f")" = generated ] || cp -a "$f" "$w/actions/" 2>/dev/null; done
  mkdir -p "$w/plugins/helix"; printf '%s\n' "$w"
}
gen() { # work [env...] -> run generator, quiet
  local w="$1"; shift
  env HELIX_ACTION_OUT_ROOT="$w" HELIX_ACTION_REGISTRY="$w/actions/registry.yaml" "$@" bash "$w/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1
}
gsetup() { # setup run: a failure is a SETUP failure, never mis-reported as the property under test (e.g. "SIGKILL lost files")
  gen "$@" || { SETUP_FAIL=1; lt_bad "SETUP FAILED: generator exited non-zero while preparing ${1##*/} (no property assertion below is meaningful)"; }
}
dirs() { echo "$1/plugins/helix/commands $1/actions/generated/gemini $1/actions/generated/qwen $1/actions/generated/codex"; }
snapeq() { snap "$1" > "$TB/_snapeq"; cmp -s "$TB/_snapeq" "$2"; }
snap() { ( cd "$1" && find actions/generated plugins/helix/commands plugins/helix/README.md -type f -not -path '*/.gen.*' | sort | xargs sha256sum ); }
cnt() { ls -A "$1" | grep -vc '^\(README\|\.gen\.\)'; }
nstage() { find "$1" -name '.gen.*' 2>/dev/null | wc -l; }
paused() { # work pausedir point [extra env...] -> background generator; sets PGP
  local w="$1" pd="$2" pt="$3"; shift 3; mkdir -p "$pd"
  ( env HELIX_ACTION_OUT_ROOT="$w" HELIX_ACTION_REGISTRY="$w/actions/registry.yaml" HELIX_TEST_MODE=1 HELIX_GEN_PAUSE_AT="$pt" HELIX_GEN_PAUSE_DIR="$pd" "$@" \
      bash "$w/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1 ) &
  PGP=$!
  local _; for _ in $(seq 1 300); do [ -e "$pd/reached.$pt" ] && return 0; sleep 0.1; done
  return 1
}
hardkill() { pkill -9 -P "$1" 2>/dev/null; kill -9 "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
mutreg() { # registry-file python-statement-on-d -> rewrite registry (d = loaded yaml)
  python3 - "$1" "$2" <<'PY'
import sys,yaml
p=sys.argv[1]; d=yaml.safe_load(open(p)); exec(sys.argv[2]); yaml.safe_dump(d,open(p,'w'))
PY
}

# committed baseline (F8): output as committed at HEAD of the tree under test, never self-generated.
CM="$TB/committed"; mkdir -p "$CM"
if git -C "$GEN_SRC_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$GEN_SRC_ROOT" archive HEAD actions/generated plugins/helix/commands plugins/helix/README.md | tar -x -C "$CM"   # redpin: not-a-red-builder the committed output is the expected side of a byte compare, not a RED artifact
else
  ( cd "$GEN_SRC_ROOT" && tar -c actions/generated plugins/helix/commands plugins/helix/README.md ) | tar -x -C "$CM"
fi
snap "$CM" > "$TB/committed.sha"
declare -A EXP; for d in $(dirs "$CM"); do EXP[${d#$CM}]=$(cnt "$d"); done
[ "$(wc -l < "$TB/committed.sha")" -gt 50 ] || { lt_bad "committed baseline implausibly small"; lt_summary; exit 1; }
echo "committed counts: $(for d in $(dirs "$CM"); do printf '%s=%s ' "${d##*/}" "${EXP[${d#$CM}]}"; done)"
counts_ok() { local w="$1" d n bad=0; for d in $(dirs "$w"); do n=$(cnt "$d"); [ "$n" -eq "${EXP[${d#$w}]}" ] || { bad=1; echo "  ${d#$w}: $n, expected ${EXP[${d#$w}]}"; }; done; return $bad; }

# (1) SIGKILL at checkpoints
for pt in $KILL_POINTS; do
  W="$(mkwork "k_$pt")"; gsetup "$W"
  if ! paused "$W" "$TB/pause_$pt" "$pt"; then lt_bad "(1) checkpoint $pt never reached"; hardkill $PGP; continue; fi
  hardkill $PGP
  if counts_ok "$W"; then lt_ok "(1) SIGKILL at $pt leaves all files in place"; else lt_bad "(1) SIGKILL at $pt lost files"; fi
  gen "$W"; [ "$(nstage "$W")" -eq 0 ] && lt_ok "(4) orphan .gen.* from killed run cleaned on next start ($pt)" || lt_bad "(4) orphan staging remains after rerun ($pt)"
  snapeq "$W" "$TB/committed.sha" && lt_ok "(1) rerun after kill at $pt is byte-identical to committed" || lt_bad "(1) rerun after kill at $pt differs from committed"
done

# (2) equivalence to the committed tree, 3 runs
W="$(mkwork eq)"; same=1
for i in 1 2 3; do gen "$W"; snapeq "$W" "$TB/committed.sha" || same=0; done
[ $same -eq 1 ] && lt_ok "(2) 3 runs byte-identical to committed HEAD output" || lt_bad "(2) output differs from committed HEAD output"

# (3) prune semantics
W="$(mkwork prune)"; gsetup "$W"
G="$W/actions/generated/gemini"; C="$W/plugins/helix/commands"
cp "$G/bug.toml" "$G/zzgone.toml"; cp "$C/bug.md" "$C/zzgone.md"      # marker-carrying stale files
printf 'hand written\n' > "$G/mine.toml"; printf 'hand written\n' > "$C/mine.md"
gen "$W"
[ ! -e "$G/zzgone.toml" ] && [ ! -e "$C/zzgone.md" ] && lt_ok "(3) stale marker-carrying files pruned" || lt_bad "(3) stale files not pruned"
[ -e "$G/mine.toml" ] && [ -e "$C/mine.md" ] && lt_ok "(3) hand-written files survive" || lt_bad "(3) hand-written files deleted"
mutreg "$W/actions/registry.yaml" "gone=d['actions'][-1]['name'].lower(); d['actions']=d['actions'][:-1]; open(sys.argv[1]+'.gone','w').write(gone)"
gone="$(cat "$W/actions/registry.yaml.gone")"
if gen "$W" && [ ! -e "$G/$gone.toml" ] && [ ! -e "$G/default-$gone.toml" ] && [ -e "$G/mine.toml" ]; then lt_ok "(3) removed action's files pruned, others kept ($gone)"; else lt_bad "(3) removed-action prune wrong ($gone)"; fi

# (4) staging cleanup: normal run and SIGTERM (prompt: no 60 s sleep to wait out)
W="$(mkwork st)"; gsetup "$W"; [ "$(nstage "$W")" -eq 0 ] && lt_ok "(4) no staging after normal run" || lt_bad "(4) staging left after normal run"
paused "$W" "$TB/pause_term" after_stage; had=$(nstage "$W")
t0=$(date +%s.%N); pkill -TERM -P $PGP 2>/dev/null; kill -TERM $PGP 2>/dev/null; wait $PGP 2>/dev/null; t1=$(date +%s.%N)
[ "$(nstage "$W")" -eq 0 ] && lt_ok "(4) no staging after SIGTERM (had $had while paused)" || lt_bad "(4) staging left after SIGTERM (had $had)"
awk -v a="$t0" -v b="$t1" 'BEGIN{exit !((b-a)<5)}' && lt_ok "(4) SIGTERM exits promptly (<5 s)" || lt_bad "(4) SIGTERM took >=5 s"
counts_ok "$W" && lt_ok "(4) tree untouched by SIGTERM at after_stage" || lt_bad "(4) tree changed by SIGTERM"

# (5) two concurrent runs on ONE output root (F1): A paused after staging, B runs meanwhile
W="$(mkwork conc)"; gsetup "$W"
paused "$W" "$TB/pause_conc" after_stage; A=$PGP
( gen "$W"; echo $? > "$TB/conc_b.rc" ) &
B=$!
sleep 1; touch "$TB/pause_conc/release.after_stage"
wait $A; arc=$?; wait $B
brc="$(cat "$TB/conc_b.rc" 2>/dev/null || echo missing)"
[ "$arc" -eq 0 ] && lt_ok "(5) run A (paused) exits 0 despite concurrent run B" || lt_bad "(5) run A rc=$arc (concurrent run B clobbered its staging)"
[ "$brc" = 0 ] && lt_ok "(5) run B exits 0" || lt_bad "(5) run B rc=$brc"
counts_ok "$W" && lt_ok "(5) files complete after concurrent runs (24/24/24/24 equivalent)" || lt_bad "(5) files missing after concurrent runs"
snapeq "$W" "$TB/committed.sha" && lt_ok "(5) concurrent result byte-identical to committed" || lt_bad "(5) concurrent result differs from committed"
[ "$(nstage "$W")" -eq 0 ] && lt_ok "(5) no staging left after concurrent runs" || lt_bad "(5) staging left after concurrent runs"

# (6) validation against the registry action count (F2) + invalid registry
W="$(mkwork bad)"; gsetup "$W"; snap "$W" > "$TB/bad_before.sha"
cp "$W/actions/registry.yaml" "$TB/bad_reg.orig"
mutreg "$W/actions/registry.yaml" "d['actions'][-1]['name']=123"   # lookup of this action fails (non-string name)
if gen "$W"; then lt_bad "(6) dropped-action (lookup fails) run exited 0"; else lt_ok "(6) dropped-action run aborts (rc!=0)"; fi
snapeq "$W" "$TB/bad_before.sha" && lt_ok "(6) dropped-action abort changed nothing" || lt_bad "(6) dropped-action run changed/pruned files"
cp "$TB/bad_reg.orig" "$W/actions/registry.yaml"
mutreg "$W/actions/registry.yaml" "a=d['actions']; b=dict(a[-1]); b['name']=a[-1]['name'].lower(); a.append(b)"  # NAME and name collide on file names
if gen "$W"; then lt_bad "(6) lowercase-collision run exited 0"; else lt_ok "(6) lowercase-collision run aborts (rc!=0)"; fi
snapeq "$W" "$TB/bad_before.sha" && lt_ok "(6) lowercase-collision abort changed nothing" || lt_bad "(6) lowercase-collision run changed files"
cp "$TB/bad_reg.orig" "$W/actions/registry.yaml"
printf 'garbage: [unterminated\n' > "$W/actions/registry.yaml"
if gen "$W"; then lt_bad "(6) invalid-registry run exited 0"; else lt_ok "(6) invalid registry aborts (rc!=0)"; fi
snapeq "$W" "$TB/bad_before.sha" && lt_ok "(6) invalid registry leaves all files in place" || lt_bad "(6) invalid registry changed/deleted files"
[ "$(nstage "$W")" -eq 0 ] && lt_ok "(6) no staging left after aborted runs" || lt_bad "(6) staging left after aborted runs"

# (7) test pause hook is inert outside test mode / outside the temp root (kills M4 / M4b)
W="$(mkwork inert)"; gsetup "$W"
PD="$TB/pause_inert1"; mkdir -p "$PD"
timeout 20 env HELIX_ACTION_OUT_ROOT="$W" HELIX_ACTION_REGISTRY="$W/actions/registry.yaml" HELIX_GEN_PAUSE_AT=after_stage HELIX_GEN_PAUSE_DIR="$PD" bash "$W/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$PD/reached.after_stage" ] && lt_ok "(7) pause hook inert without HELIX_TEST_MODE=1" || lt_bad "(7) pause hook active without HELIX_TEST_MODE=1 (rc=$rc)"
mkdir -p "$TB/tmp_a" "$TB/outside"
timeout 20 env TMPDIR="$TB/tmp_a" HELIX_TEST_MODE=1 HELIX_ACTION_OUT_ROOT="$W" HELIX_ACTION_REGISTRY="$W/actions/registry.yaml" HELIX_GEN_PAUSE_AT=after_stage HELIX_GEN_PAUSE_DIR="$TB/outside" bash "$W/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$TB/outside/reached.after_stage" ] && lt_ok "(7) pause hook inert with a pause dir outside the temp root" || lt_bad "(7) pause hook active outside temp root (rc=$rc)"

# (8) staging inside each destination dir (same filesystem) + documentation
W="$(mkwork where)"; gsetup "$W"
paused "$W" "$TB/pause_where" after_stage
okw=1
for d in $(dirs "$W"); do
  s="$(find "$d" -maxdepth 1 -type d -name '.gen.*' | head -1)"
  { [ -n "$s" ] && [ "$(stat -c %d "$s")" = "$(stat -c %d "$d")" ]; } || { okw=0; echo "  no same-fs staging dir in ${d#$W}"; }
done
[ "$(find "$W" -maxdepth 1 -name '.gen.*' | wc -l)" -eq 0 ] || okw=0
hardkill $PGP
[ $okw -eq 1 ] && lt_ok "(8) staging dirs live inside each destination dir" || lt_bad "(8) staging not inside destination dirs"
grep -q '\.gen\.' "$GEN_SRC_ROOT/scripts/generate_agent_prefix_commands.sh" && sed -n '/^# ── Outputs/,/^# ── Dependencies/p' "$GEN_SRC_ROOT/scripts/generate_agent_prefix_commands.sh" | grep -q '\.gen\.' \
  && lt_ok "(8) script header documents the .gen.* staging dirs" || lt_bad "(8) script header does not document .gen.* staging"
grep -qxF '.gen.*' "$GEN_SRC_ROOT/.gitignore" && lt_ok "(8) .gitignore ignores .gen.*" || lt_bad "(8) .gitignore lacks .gen.*"

# (9) the generator must run when copied ALONE with its lib (as CM-CLI-AGENT-PLUGINS-WIRED and
# tests/test_cli_agent_plugins.sh do): no dependency on scripts/lib/safe_rm.sh or other siblings.
S="$TB/solo"; mkdir -p "$S/scripts" "$S/actions"
cp "$GEN_SRC_ROOT/scripts/generate_agent_prefix_commands.sh" "$GEN_SRC_ROOT/scripts/action_prefix_lib.sh" "$S/scripts/"
cp "$GEN_SRC_ROOT/actions/registry.yaml" "$S/actions/"
( cd "$S" && env -u HELIX_ACTION_REGISTRY -u HELIX_ACTION_OUT_ROOT bash scripts/generate_agent_prefix_commands.sh >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && [ "$(cnt "$S/plugins/helix/commands")" -eq "${EXP[/plugins/helix/commands]}" ] && lt_ok "(9) generator works copied alone with action_prefix_lib.sh" || lt_bad "(9) standalone-copied generator failed (rc=$rc)"

# ---------------------------------------------------------------------------------------------
# (10) lock / timeout / stray-staging / commit-failure / env validation (review follow-ups 1-6).
# lock_suite SCRIPTDIR-WORKDIR TAG: a live run A (paused after staging, holds the flock) vs a
# contender B with HELIX_GEN_LOCK_WAIT=2. Prints one line per failed property; returns 0 when all hold.
# It is run on the real generator (must pass) and on mutants (must FAIL), see (11).
lock_suite() {
  local W="$1" tag="$2" PDIR="$TB/lk_$2" before after t0 t1 brc el berr="$TB/lk_$2.err" bad=0 arc
  gen "$W" || { echo "SETUP: generator failed before the lock scenario"; return 1; }
  paused "$W" "$PDIR" after_stage || { echo "A never reached after_stage"; hardkill $PGP; return 1; }
  local A=$PGP; before=$(nstage "$W")
  t0=$(date +%s.%N)
  timeout 30 env HELIX_ACTION_OUT_ROOT="$W" HELIX_ACTION_REGISTRY="$W/actions/registry.yaml" HELIX_GEN_LOCK_WAIT=2 \
    bash "$W/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>"$berr"; brc=$?
  t1=$(date +%s.%N); el=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')
  after=$(nstage "$W")
  [ "$brc" -ne 0 ] && [ "$brc" -ne 124 ] || { echo "contender rc=$brc (must fail closed, not 0/hang)"; bad=1; }
  awk -v e="$el" 'BEGIN{exit !(e>=1.5 && e<10)}' || { echo "contender took ${el}s (bound 2s not honoured)"; bad=1; }
  grep -q 'timed out waiting' "$berr" || { echo "no timeout message"; bad=1; }
  [ "$after" -eq "$before" ] && [ "$before" -ge 6 ] || { echo "live run's staging dirs touched by contender ($before -> $after)"; bad=1; }
  touch "$PDIR/release.after_stage"; wait $A; arc=$?
  [ "$arc" -eq 0 ] || { echo "live run A rc=$arc after contender"; bad=1; }
  counts_ok "$W" >/dev/null && snapeq "$W" "$TB/committed.sha" || { echo "result differs from committed"; bad=1; }
  return $bad
}
W="$(mkwork lock)"; out="$(lock_suite "$W" real)"; lrc=$?
[ $lrc -eq 0 ] && lt_ok "(10) lock: contender fails closed within HELIX_GEN_LOCK_WAIT, live run's staging untouched, live run completes" || lt_bad "(10) lock suite: $out"

# (10b) HELIX_GEN_LOCK_WAIT validation: empty / non-integer / negative / fractional / huge refused, nothing changed
W="$(mkwork envv)"; gsetup "$W"; snap "$W" > "$TB/envv.sha"; allok=1
for v in "" abc -1 1.5 "1 2" 9999999 "0x10"; do
  err="$TB/envv.err"; env HELIX_ACTION_OUT_ROOT="$W" HELIX_ACTION_REGISTRY="$W/actions/registry.yaml" HELIX_GEN_LOCK_WAIT="$v" bash "$W/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>"$err"; rc=$?
  if [ "$rc" -eq 0 ] || ! grep -q 'HELIX_GEN_LOCK_WAIT must be' "$err" || ! snapeq "$W" "$TB/envv.sha" || [ "$(nstage "$W")" -ne 0 ]; then allok=0; echo "  value '$v': rc=$rc"; fi
done
[ $allok -eq 1 ] && lt_ok "(10b) invalid HELIX_GEN_LOCK_WAIT values refused with a clear message, nothing changed" || lt_bad "(10b) invalid HELIX_GEN_LOCK_WAIT accepted or unclear"
allok=1
for v in 0 5 300; do gen "$W" HELIX_GEN_LOCK_WAIT="$v" || { allok=0; echo "  valid '$v' rejected"; }; done
[ $allok -eq 1 ] && lt_ok "(10b) valid HELIX_GEN_LOCK_WAIT values (0, 5, 300) accepted" || lt_bad "(10b) valid value rejected"

# (10c) stray pre-existing .gen.* entries: stale conforming dirs reaped; non-staging paths NEVER removed, never block
W="$(mkwork stray)"; gsetup "$W"
C="$W/plugins/helix/commands"; mkdir -p "$TB/outside_target"; echo precious > "$TB/outside_target/keep"
mkdir "$C/.gen.STALE1" "$W/actions/generated/qwen/.gen.STALE2"; echo junk > "$C/.gen.STALE1/x"
mkdir "$C/.gen.precious"; echo mine > "$C/.gen.precious/data"           # wrong name shape: not ours
ln -s "$TB/outside_target" "$C/.gen.LINK01"                              # symlink with a conforming name
echo f > "$C/.gen.file"                                                   # a plain file
if gen "$W"; then
  [ ! -e "$C/.gen.STALE1" ] && [ ! -e "$W/actions/generated/qwen/.gen.STALE2" ] && lt_ok "(10c) stale conforming staging dirs reaped" || lt_bad "(10c) stale staging dir not reaped"
  [ "$(cat "$C/.gen.precious/data" 2>/dev/null)" = mine ] && [ -f "$C/.gen.file" ] && lt_ok "(10c) non-conforming .gen.* paths left untouched" || lt_bad "(10c) non-conforming .gen.* path destroyed"
  [ -L "$C/.gen.LINK01" ] && [ "$(cat "$TB/outside_target/keep")" = precious ] && lt_ok "(10c) symlinked .gen.* not followed, target intact" || lt_bad "(10c) symlink target damaged"
  rm -rf -- "${C:?}/.gen.precious" "${C:?}/.gen.file" "${C:?}/.gen.LINK01"
  snapeq "$W" "$TB/committed.sha" && lt_ok "(10c) strays did not pollute generated output" || lt_bad "(10c) output differs with strays present"
else lt_bad "(10c) generator blocked by stray .gen.* entries"; fi

# (10d) commit failure is reported, not swallowed: a directory squats on a destination file name
W="$(mkwork cf)"; gsetup "$W"; C="$W/plugins/helix/commands"; errf="$TB/cf.err"
rm -f "$C/bug.md"; mkdir -p "$C/bug.md"; echo keep > "$C/bug.md/keep"
env HELIX_ACTION_OUT_ROOT="$W" HELIX_ACTION_REGISTRY="$W/actions/registry.yaml" bash "$W/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>"$errf"; rc=$?
[ "$rc" -ne 0 ] && lt_ok "(10d) failed commit exits non-zero (rc=$rc)" || lt_bad "(10d) failed commit reported success"
[ ! -e "$C/bug.md/bug.md" ] && [ "$(cat "$C/bug.md/keep")" = keep ] && lt_ok "(10d) nothing mis-moved INTO the squatting directory" || lt_bad "(10d) file silently moved into squatting dir"
[ "$(nstage "$W")" -eq 0 ] && lt_ok "(10d) staging cleaned after failed commit" || lt_bad "(10d) staging left after failed commit"
grep -q 'commit failed' "$errf" && ! grep -q 'generated [0-9]* action' "$errf" && lt_ok "(10d) failure message present and no success line" || lt_bad "(10d) missing failure message / success line printed"

# (10e) kill mid-run (TERM at mid_commit) leaves all tracked outputs intact and no staging
W="$(mkwork tm)"; gsetup "$W"; paused "$W" "$TB/pause_tm" mid_commit
pkill -TERM -P $PGP 2>/dev/null; kill -TERM $PGP 2>/dev/null; wait $PGP 2>/dev/null
counts_ok "$W" && [ "$(nstage "$W")" -eq 0 ] && lt_ok "(10e) TERM at mid_commit: all outputs present, staging cleaned" || lt_bad "(10e) TERM at mid_commit lost files or left staging"

# (10f) staging cleanup on HUP and INT (INT needs a python launcher: bash background jobs ignore SIGINT)
W="$(mkwork sig)"; gsetup "$W"
paused "$W" "$TB/pause_hup" after_stage
pkill -HUP -P $PGP 2>/dev/null; kill -HUP $PGP 2>/dev/null; wait $PGP 2>/dev/null
[ "$(nstage "$W")" -eq 0 ] && lt_ok "(10f) no staging after SIGHUP" || lt_bad "(10f) staging left after SIGHUP"
mkdir -p "$TB/pause_int"
python3 - "$W" "$TB/pause_int" <<'PY' && lt_ok "(10f) no staging after SIGINT; tree complete" || lt_bad "(10f) staging left / failure after SIGINT"
import os,signal,subprocess,sys,time,glob
w,pd=sys.argv[1:3]
env=dict(os.environ,HELIX_ACTION_OUT_ROOT=w,HELIX_ACTION_REGISTRY=w+"/actions/registry.yaml",HELIX_TEST_MODE="1",HELIX_GEN_PAUSE_AT="after_stage",HELIX_GEN_PAUSE_DIR=pd)
p=subprocess.Popen(["bash",w+"/scripts/generate_agent_prefix_commands.sh"],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True,preexec_fn=lambda:signal.signal(signal.SIGINT,signal.SIG_DFL))
for _ in range(300):
    if os.path.exists(pd+"/reached.after_stage"): break
    time.sleep(0.1)
else: sys.exit(1)
if not glob.glob(w+"/**/.gen.*",recursive=True): sys.exit(1)
assert p.pid>1; os.killpg(p.pid,signal.SIGINT); p.wait(timeout=10)  # like a terminal ^C: whole foreground group
sys.exit(1 if glob.glob(w+"/**/.gen.*",recursive=True) else 0)
PY
counts_ok "$W" && lt_ok "(10f) tree intact after SIGINT" || lt_bad "(10f) tree changed by SIGINT"

# (11) mutation proof: lock_suite and the stray test MUST fail on each mutant of the generator.
mutant() { # tag perl-expr-on-script ; makes a sandbox copy with the mutation applied, verifies it differs
  local W; W="$(mkwork "m_$1")"; cp "$W/scripts/generate_agent_prefix_commands.sh" "$TB/m_$1.orig"
  perl -0pi -e "$2" "$W/scripts/generate_agent_prefix_commands.sh"
  cmp -s "$TB/m_$1.orig" "$W/scripts/generate_agent_prefix_commands.sh" && { echo "MUTANT $1 DID NOT CHANGE THE SCRIPT" >&2; return 1; }
  printf '%s\n' "$W"
}
mut_expect_fail() { # tag description perl-expr kind(lock|stray)
  local W r
  W="$(mutant "$1" "$3")" || { lt_bad "(11) mutant $1 not applicable"; return; }
  if [ "$4" = lock ]; then lock_suite "$W" "m$1" >/dev/null 2>&1; r=$?
  elif [ "$4" = env ]; then
    gen "$W"; gen "$W" HELIX_GEN_LOCK_WAIT=abc && r=0 || r=1
  else
    gen "$W"; local C="$W/plugins/helix/commands"; mkdir "$C/.gen.precious"; echo mine > "$C/.gen.precious/data"
    gen "$W" >/dev/null 2>&1; [ "$(cat "$C/.gen.precious/data" 2>/dev/null)" = mine ] && r=0 || r=1
  fi
  [ "$r" -ne 0 ] && lt_ok "(11) mutant $1 ($2) is killed" || lt_bad "(11) mutant $1 ($2) SURVIVES"
}
mut_expect_fail A "no flock" 's/^flock -w "\$gen_lock_wait" 9.*$/true/m' lock
mut_expect_fail B "unbounded wait" 's/flock -w "\$gen_lock_wait" 9/flock 9/' lock
mut_expect_fail G "reap before lock" 's/^exec 9< /for _x in "\$out_root"\/.gen.* "\$claude_cmd_dir"\/.gen.* "\$out_root"\/gemini\/.gen.* "\$out_root"\/qwen\/.gen.* "\$out_root"\/codex\/.gen.* "\$claude_plugin_dir"\/.gen.*; do [ -d "\$_x" ] && rm -rf "\$_x"; done\nexec 9< /m' lock
mut_expect_fail F "apx_rm_stage guards removed" 's/case "\$\{p##\*\/\}" in.*?esac\n//s; s/\[ -d "\$p" \] && \[ ! -L "\$p" \] \|\| \{[^\n]*\n/[ -e "\$p" ] || return 0\n/' stray
mut_expect_fail H "no lock-wait validation" 's/case "\$gen_lock_wait" in.*?esac//s' env

# (12) A1: the commit is a rename, never an in-place write. A hardlink to a destination file keeps the OLD
# bytes across a run (rename swaps the inode); an in-place cp/overwrite would change the hardlinked copy too,
# i.e. a kill in the middle of writing a file would leave a half-written destination (mutant X6 must die).
rename_suite() { # work -> prints a failure reason, rc 0 when every destination was replaced by rename
  local W="$1" C d f n=0 bad=0
  gen "$W" || { echo "SETUP: generator failed"; return 1; }
  for d in "$W/plugins/helix/commands" "$W/actions/generated/gemini" "$W/actions/generated/qwen" "$W/actions/generated/codex"; do
    for f in "$d"/*; do
      case "${f##*/}" in README*) continue ;; esac
      [ -f "$f" ] || continue
      ln "$f" "$f.hl" && printf 'OLD\n' > "$f" || { echo "SETUP: cannot prepare $f"; return 1; }
      n=$((n+1))
    done
  done
  [ "$n" -gt 20 ] || { echo "SETUP: only $n files prepared"; return 1; }
  gen "$W" || { echo "regeneration failed"; return 1; }
  for d in "$W/plugins/helix/commands" "$W/actions/generated/gemini" "$W/actions/generated/qwen" "$W/actions/generated/codex"; do
    for f in "$d"/*.hl; do
      [ "$(cat "$f")" = OLD ] || { echo "hardlink of ${f##*/} was overwritten in place (non-atomic write)"; bad=1; break; }
    done
  done
  for f in "$W"/plugins/helix/commands/*.hl "$W"/actions/generated/*/*.hl; do rm -f -- "${f:?}"; done
  [ $bad -eq 0 ] && { snapeq "$W" "$TB/committed.sha" || { echo "result differs from committed"; return 1; }; }
  return $bad
}
W="$(mkwork rename)"; out="$(rename_suite "$W")"; rrc=$?
[ $rrc -eq 0 ] && lt_ok "(12) every destination is replaced by rename (old inode untouched, result == committed)" || lt_bad "(12) rename atomicity: $out"
W="$(mutant X6 's/mv -fT -- "\$f" "\$dest\/\$b"/{ cp -fT -- "\$f" "\$dest\/\$b" \&\& rm -f -- "\$f"; }/')" || W=""
if [ -n "$W" ]; then rename_suite "$W" >/dev/null 2>&1 && lt_bad "(12) mutant X6 (cp -fT && rm instead of mv -fT) SURVIVES" || lt_ok "(12) mutant X6 (cp -fT && rm instead of mv -fT) is killed"
else lt_bad "(12) mutant X6 not applicable"; fi

lt_summary
