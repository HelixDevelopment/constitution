#!/usr/bin/env bash
# test_setup_prompt_round3.sh — regression tests for the review round 3 findings of
# docs/prompts/setup/latest.md, its follow-ups, rotate_setup_prompt.sh and the
# setup-prompt gate. Every test was written first and observed RED against the
# unfixed files. It EXECUTES the marked shell blocks (`# <ID>-BEGIN` / `# <ID>-END`)
# of the real prompt files against throw-away git repositories.
#   R4-1   STEP5: a submodule with an untracked file (a local change that does not
#          conflict with the checkout) stops rc=3 "has local changes", HEAD unchanged
#   R4-2   STEP4: staged / unstaged .gitmodules edits and an unrecorded gitlink move
#          of the legacy path stop rc=3 BEFORE git mv
#   R4-5   rotate: a fresh lock directory without a pid file is NOT reaped within
#          the grace period, and IS recovered once it is older
#   R4-6   STEP10: every remote is checked before any push; one remote ahead ->
#          rc=3 and NOTHING pushed to any remote
#   I2     STEP2/4/5: core.worktree pointing elsewhere (status ' ', toplevel is
#          another directory) stops rc=3 with a message naming the real directory
#   I3     STEP2/4/5: a parent worktree created at the submodule path, and a foreign
#          nested repository, stop rc=3; a legitimate non-absorbed clone of the
#          .gitmodules URL passes (golden-FALSE)
#   I4     STEP2/4/5: a .git file pointing nowhere prints git's own error
#   I5     S7 (latest.md) and V6 (follow-up 01): a stale path whose file name contains
#          "legacy" (constitution/scripts/legacy_x.sh) is counted; the word "legacy"
#          excludes; class-matched control needles run
#   I7     STEP4G: file names and counts only; secret-class files never searched; a
#          decoy secret never appears in the output
#   I9     gate: an extractor library outside the gate's own scripts/lib is refused
#          (BLIND) unless SETUP_PROMPT_EXTRACT_LIB_TRUST=1
# Overrides (used by test_setup_prompt_round3_mutants.sh to run this suite against
# mutated copies): R3_LATEST, R3_FU01, R3_ROTATE, R3_GATE_DIR (a directory holding
# scripts/gates/<gate> and scripts/lib/setup_prompt_extract.sh).
# Nothing outside a mktemp -d sandbox is written; no network; $HOME untouched.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_ALLOW_PROTOCOL=file   # local bare remotes only
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }

LATEST="${R3_LATEST:-$REPO/docs/prompts/setup/latest.md}"
FU01="${R3_FU01:-$REPO/docs/prompts/setup/followups/01_verify_incorporation.md}"
ROT="${R3_ROTATE:-$ROTATE}"
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || no "PROMPT block extracted"
blk_of() { # <id> <text> -> lines between `# <id>-BEGIN` and `# <id>-END`
  awk -v b="# $1-BEGIN" -v e="# $1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$2"
}
for n in 2 4 4G 5 10 S7; do [ -n "$(blk_of "STEP$n" "$block")$(blk_of "$n" "$block")" ] && ok "block $n present" || no "block $n missing"; done
[ -n "$(blk_of V6 "$(cat "$FU01")")" ] && ok "follow-up 01 V6 block present" || no "follow-up 01 V6 block missing"
run_txt() { # <code> <dir> -> runs the code in <dir> with bash; output in <dir>.out
  ( cd "$2" && bash -c "$1" ) >"$2.out" 2>&1
}
run_step() { run_txt "$(blk_of "STEP$1" "$block")" "$2"; }
out_of() { cat "$1.out"; }

mk_remote() { # <sandbox> -> bare repo <sandbox>/remote.git: c1(v1) c2(v2) on main
  local s="$1" w="$1/work"
  git_q init -q "$w"; printf 'one\n' >"$w/f"; printf 'keep\n' >"$w/k"; git -C "$w" add f k; git -C "$w" commit -q -m c1
  git -C "$w" tag helixconstitution-v1
  printf 'two\n' >"$w/f"; git -C "$w" commit -q -am c2; git -C "$w" tag helixconstitution-v2
  git_q clone -q --bare "$w" "$s/remote.git"
}
mk_p0() { # <sandbox> <subpath> -> <sandbox>/p0 with the submodule at <subpath> @ v1, committed
  local s="$1" sp="$2"
  git_q init -q "$s/p0"; printf '# p\n' >"$s/p0/README.md"; git -C "$s/p0" add README.md; git -C "$s/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$s/p0/submodules"
  git_q -C "$s/p0" submodule add -q "$s/remote.git" "$sp" >/dev/null 2>&1
  git -C "$s/p0/$sp" checkout -q helixconstitution-v1; git -C "$s/p0" add "$sp"; git -C "$s/p0" commit -q -m sub
}
mk_full() { # <sandbox> <subpath> -> <sandbox>/p: a clone WITH the submodule checked out
  mk_p0 "$1" "$2"; git_q clone -q --recurse-submodules "$1/p0" "$1/p" >/dev/null 2>&1
}
mk_bare_clone() { # <sandbox> <subpath> -> <sandbox>/p: a clone WITHOUT the submodule (empty dir)
  mk_p0 "$1" "$2"; git_q clone -q "$1/p0" "$1/p"
}
pstate() { printf '%s %s %s' "$(git -C "$1" symbolic-ref -q HEAD || echo DETACHED)" "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" diff --cached --name-status | tr '\n' ';')"; }

# ---------------- R4-1: STEP5 untracked file in the submodule -------------------------
S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" submodules/constitution; c="$S/p/submodules/constitution"
printf 'mine\n' >"$c/untracked_note"; before="$(git -C "$c" rev-parse HEAD)"
run_step 5 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'STOP: submodules/constitution has local changes' "$S/p.out" \
  && ok "R4-1 STEP5 untracked file in the submodule stops rc=3 (local changes)" || no "R4-1 STEP5 untracked rc=$rc: $(out_of "$S/p")"
[ "$(git -C "$c" rev-parse HEAD)" = "$before" ] && [ -z "$(git -C "$S/p" diff --cached --name-only)" ] \
  && ok "R4-1 STEP5 untracked: HEAD unchanged, nothing staged" || no "R4-1 STEP5 untracked: submodule moved or staged"
# non-conflicting edit of a tracked file (k does not change between v1 and v2)
S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" submodules/constitution; c="$S/p/submodules/constitution"
printf 'edit\n' >>"$c/k"; before="$(git -C "$c" rev-parse HEAD)"
run_step 5 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'has local changes' "$S/p.out" && [ "$(git -C "$c" rev-parse HEAD)" = "$before" ] \
  && ok "R4-1 STEP5 non-conflicting tracked edit stops rc=3, HEAD unchanged" || no "R4-1 STEP5 tracked edit rc=$rc: $(out_of "$S/p")"

# ---------------- R4-2: STEP4 uncommitted .gitmodules / legacy gitlink -----------------
legacy_unmoved() { [ -d "$1/constitution" ] && [ ! -e "$1/submodules/constitution" ] && ! grep -qE '^R' <<<"$(git -C "$1" status --porcelain)"; }
S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" constitution
git -C "$S/p" config -f .gitmodules submodule.constitution.branch main; git -C "$S/p" add .gitmodules
run_step 4 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'uncommitted changes' "$S/p.out" && legacy_unmoved "$S/p" \
  && ok "R4-2 STEP4 staged .gitmodules edit stops rc=3, nothing moved" || no "R4-2 STEP4 staged .gitmodules rc=$rc: $(out_of "$S/p")"
S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" constitution
git -C "$S/p" config -f .gitmodules submodule.constitution.branch main
run_step 4 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'STOP: .gitmodules or the legacy path has uncommitted changes' "$S/p.out" && legacy_unmoved "$S/p" \
  && ok "R4-2 STEP4 unstaged .gitmodules edit stops rc=3 with the precondition message" || no "R4-2 STEP4 unstaged .gitmodules rc=$rc: $(out_of "$S/p")"
S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" constitution
git -C "$S/p/constitution" checkout -q helixconstitution-v2   # gitlink moved, not recorded
run_step 4 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'uncommitted changes' "$S/p.out" && legacy_unmoved "$S/p" \
  && ok "R4-2 STEP4 unrecorded gitlink move stops rc=3, nothing moved" || no "R4-2 STEP4 gitlink move rc=$rc: $(out_of "$S/p")"

# ---------------- R4-5: rotate lock-creation grace -------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; old="$(cat "$D/latest.md")"; mkdir "$D/.rotate.lock"
out="$(bash "$ROT" r45 --dir "$D" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'being created' <<<"$out" && [ -d "$D/.rotate.lock" ] && [ ! -e "$D/03_r45.md" ] && [ "$(cat "$D/latest.md")" = "$old" ] \
  && ok "R4-5 fresh lock without pid NOT reaped within the grace (rc=3, nothing changed)" || no "R4-5 fresh lock rc=$rc: $out"
touch -d '1 minute ago' "$D/.rotate.lock"
out="$(bash "$ROT" r45 --dir "$D" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$D/.rotate.lock" ] && [ "$(cat "$D/03_r45.md" 2>/dev/null)" = "$old" ] \
  && ok "R4-5 the same lock older than the grace is recovered and the rotation done" || no "R4-5 old lock rc=$rc: $out"

# ---------------- R4-6: STEP10 checks every remote before any push --------------------
S="$(mk_sandbox)"; git_q init -q "$S/p"; printf 'a\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init
git_q init -q --bare "$S/a_fine.git"; git_q init -q --bare "$S/b_ahead.git"
git -C "$S/p" push -q "$S/a_fine.git" main; git -C "$S/p" push -q "$S/b_ahead.git" main
git_q clone -q "$S/b_ahead.git" "$S/other"; printf 'o\n' >"$S/other/o"; git -C "$S/other" add o; git -C "$S/other" commit -q -m o; git -C "$S/other" push -q origin main
printf 'b\n' >"$S/p/b"; git -C "$S/p" add b; git -C "$S/p" commit -q -m local
git -C "$S/p" remote add a_fine "$S/a_fine.git"; git -C "$S/p" remote add b_ahead "$S/b_ahead.git"
fine_before="$(git -C "$S/a_fine.git" rev-parse main)"
run_step 10 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'b_ahead/main has commits HEAD lacks' "$S/p.out" \
  && ok "R4-6 STEP10 remote ahead stops rc=3 with the precondition message" || no "R4-6 STEP10 rc=$rc: $(out_of "$S/p")"
[ "$(git -C "$S/a_fine.git" rev-parse main)" = "$fine_before" ] \
  && ok "R4-6 STEP10 nothing pushed to ANY remote when one is ahead" || no "R4-6 STEP10 pushed to a_fine before checking b_ahead"
# golden-FALSE: every remote behind or equal -> both pushed
S2="$(mk_sandbox)"; git_q init -q "$S2/p"; printf 'a\n' >"$S2/p/a"; git -C "$S2/p" add a; git -C "$S2/p" commit -q -m init
git_q init -q --bare "$S2/r1.git"; git_q init -q --bare "$S2/r2.git"; git -C "$S2/p" remote add r1 "$S2/r1.git"; git -C "$S2/p" remote add r2 "$S2/r2.git"
run_step 10 "$S2/p"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$S2/r1.git" rev-parse main 2>/dev/null)" = "$(git -C "$S2/p" rev-parse HEAD)" ] && [ "$(git -C "$S2/r2.git" rev-parse main 2>/dev/null)" = "$(git -C "$S2/p" rev-parse HEAD)" ] \
  && ok "R4-6 STEP10 golden-FALSE: no remote ahead -> every remote pushed (rc=0)" || no "R4-6 STEP10 golden-FALSE rc=$rc: $(out_of "$S2/p")"

# ---------------- I2/I3/I4: identity of the checkout, STEP2/4/5 -----------------------
for st in 2 5 4; do
  sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
  # I2: core.worktree set elsewhere
  S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" "$sp"; mkdir "$S/elsewhere"
  git -C "$S/p" config -f ".git/modules/$sp/config" core.worktree "$S/elsewhere"
  sst="$(git -C "$S/p" submodule status -- "$sp" 2>&1 | cut -c1)"; pb="$(pstate "$S/p")"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(pstate "$S/p")" = "$pb" ] && legacy_ok=1 || legacy_ok=0
  [ "$legacy_ok" = 1 ] && ok "I2 STEP$st core.worktree elsewhere (status prefix '$sst') stops rc=3, parent untouched" || no "I2 STEP$st core.worktree rc=$rc: $(out_of "$S/p")"
  grep -q "elsewhere" "$S/p.out" && ! grep -q 'git would act on the parent project' "$S/p.out" \
    && ok "I2 STEP$st message names the real directory, not 'the parent project'" || no "I2 STEP$st message: $(out_of "$S/p")"
  # I3a: a worktree of the PARENT created at the submodule path after `git submodule init`
  S="$(mk_sandbox)"; mk_remote "$S"; mk_bare_clone "$S" "$sp"
  git -C "$S/p" submodule init >/dev/null 2>&1; git -C "$S/p" worktree add -q --detach "$sp" >/dev/null 2>&1
  pb="$(pstate "$S/p")"; wtb="$(git -C "$S/p/$sp" rev-parse HEAD)"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(pstate "$S/p")" = "$pb" ] && [ "$(git -C "$S/p/$sp" rev-parse HEAD)" = "$wtb" ] && [ -d "$S/p/$sp" ] \
    && ok "I3 STEP$st parent worktree at the submodule path stops rc=3, nothing changed" || no "I3 STEP$st parent worktree rc=$rc: $(out_of "$S/p")"
  grep -q 'worktree of the parent' "$S/p.out" && ok "I3 STEP$st parent worktree: message says so" || no "I3 STEP$st parent worktree message: $(out_of "$S/p")"
  # I3b: a foreign nested repository at the submodule path
  S="$(mk_sandbox)"; mk_remote "$S"; mk_bare_clone "$S" "$sp"; git -C "$S/p" submodule init >/dev/null 2>&1
  git_q init -q "$S/p/$sp"; printf 'z\n' >"$S/p/$sp/z"; git -C "$S/p/$sp" add z; git -C "$S/p/$sp" commit -q -m z
  git -C "$S/p/$sp" remote add origin "$S/elsewhere.git"
  pb="$(pstate "$S/p")"; fb="$(git -C "$S/p/$sp" rev-parse HEAD)"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(pstate "$S/p")" = "$pb" ] && [ "$(git -C "$S/p/$sp" rev-parse HEAD)" = "$fb" ] && [ -d "$S/p/$sp" ] \
    && ok "I3 STEP$st foreign nested repository stops rc=3, nothing changed" || no "I3 STEP$st foreign repo rc=$rc: $(out_of "$S/p")"
  grep -q 'another repository' "$S/p.out" && ok "I3 STEP$st foreign repo: message says so" || no "I3 STEP$st foreign message: $(out_of "$S/p")"
  # I3 golden-FALSE: a legitimate non-absorbed clone of the .gitmodules URL passes the guard
  S="$(mk_sandbox)"; mk_remote "$S"; mk_bare_clone "$S" "$sp"; git -C "$S/p" submodule init >/dev/null 2>&1
  rmdir "$S/p/$sp"; git_q clone -q "$S/remote.git" "$S/p/$sp"; git -C "$S/p/$sp" checkout -q helixconstitution-v1
  run_step "$st" "$S/p"; rc=$?
  ! grep -qE 'not the submodule.s own checkout|another repository|worktree of the parent' "$S/p.out" && [ "$rc" -eq 0 ] \
    && ok "I3 STEP$st golden-FALSE: non-absorbed legitimate clone accepted (rc=0)" || no "I3 STEP$st legit non-absorbed clone rc=$rc: $(out_of "$S/p")"
  # I4: .git file pointing nowhere
  S="$(mk_sandbox)"; mk_remote "$S"; mk_full "$S" "$sp"
  printf 'gitdir: %s/nowhere\n' "$S" >"$S/p/$sp/.git"; pb="$(pstate "$S/p")"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && grep -q 'not a git repository' "$S/p.out" && ! grep -q 'not a registered submodule' "$S/p.out" && [ "$(pstate "$S/p")" = "$pb" ] \
    && ok "I4 STEP$st .git pointing nowhere: rc=3 with git's real error" || no "I4 STEP$st dangling .git rc=$rc: $(out_of "$S/p")"
done

# ---------------- I5: S7 (latest.md) and V6 (follow-up 01) ------------------------------
for which in S7 V6; do
  if [ "$which" = S7 ]; then code="$(blk_of S7 "$block")"; else code="$(blk_of V6 "$(cat "$FU01")")"; fi
  S="$(mk_sandbox)"; P="$S/p"; mkdir -p "$P/.claude"
  printf '# p\n\n## INHERITED FROM submodules/constitution/CLAUDE.md\n\nRun bash constitution/scripts/legacy_x.sh first.\n' >"$P/CLAUDE.md"
  printf '# p\n\nThe old legacy path ./constitution/ was migrated.\n' >"$P/AGENTS.md"
  printf '{"hooks":{}}\n' >"$P/.claude/settings.json"
  run_txt "$code" "$P"; rc=$?; o="$(out_of "$P")"
  grep -qE "^$which hits: 1$" <<<"$o" && ok "I5 $which counts the stale path inside a 'legacy_x' file name (1 hit)" || no "I5 $which: $o"
  grep -qE "^$which needle regex: 1$" <<<"$o" && grep -qE "^$which needle exclusion: 3$" <<<"$o" \
    && ok "I5 $which class-matched control needles pass" || no "I5 $which needles: $o"
  for f in CLAUDE.md AGENTS.md .claude/settings.json; do
    grep -qE "^$which needle file: $f [1-9]" <<<"$o" && ok "I5 $which file needle sees $f" || no "I5 $which file needle $f: $o"
  done
  # a blank-first-line file that is otherwise empty must show 0 (BLIND), never a positive
  printf '\n\n' >"$P/QWEN.md"; run_txt "$code" "$P"; o="$(out_of "$P")"
  grep -qE "^$which needle file: QWEN.md 0$" <<<"$o" && ok "I5 $which blank file reads 0 (BLIND), not trivially true" || no "I5 $which blank file: $o"
done

# ---------------- I7: STEP4G file names and counts only, secrets never searched -------
S="$(mk_sandbox)"; P="$S/p"; git_q init -q "$P"; mkdir -p "$P/src" "$P/.claude" "$P/deep/x"
printf '[submodule "constitution"]\n\tpath = submodules/constitution\n' >"$P/.gitmodules"
printf 'bash ./constitution/x.sh # legacy\nsee constitution/CLAUDE.md\n' >"$P/src/a.sh"
DECOY='DECOY_SECRET_9f3b2c'
for f in .env .env.local deep/x/.env .claude/settings.local.json server.pem deep/x/id.key credentials.json deep/x/credentials; do
  printf 'TOKEN=%s ./constitution/x.sh\n' "$DECOY" >"$P/$f"
done
printf '.env*\n*.pem\n' >"$P/.gitignore"
run_step 4G "$P"; rc=$?; o="$(out_of "$P")"
grep -qF "$DECOY" <<<"$o" && no "I7 STEP4G leaked the decoy secret" || ok "I7 STEP4G decoy secret never printed"
grep -qE '(^|/)(\.env|\.env\.local|settings\.local\.json|server\.pem|id\.key|credentials(\.json)?):' <<<"$o" \
  && no "I7 STEP4G listed a secret-class file: $o" || ok "I7 STEP4G secret-class files not searched"
grep -qx 'src/a.sh:2' <<<"$o" && ok "I7 STEP4G lists src/a.sh:2 (file:count)" || no "I7 STEP4G listing: $o"
grep -qE 'hits: 2 in 1 files' <<<"$o" && ok "I7 STEP4G total count" || no "I7 STEP4G total: $o"
lst="$(awk '/legacy reference hits:/{f=1;next} /control needle/{f=0} f' <<<"$o")"
[ -n "$lst" ] && ! grep -qvE '^[^:]+:[0-9]+$' <<<"$lst" && ok "I7 STEP4G listing is file:count only (no hit lines)" || no "I7 STEP4G listing not file:count: $lst"
grep -qE 'control needle: .gitmodules:[1-9]' <<<"$o" && ok "I7 STEP4G control needle sees .gitmodules" || no "I7 STEP4G needle: $o"

# ---------------- I9: gate refuses an untrusted extractor library ----------------------
GD="${R3_GATE_DIR:-}"
if [ -z "$GD" ]; then
  GD="$(mk_sandbox)"; mkdir -p "$GD/scripts/gates" "$GD/scripts/lib"
  cp "$GATE" "$GD/scripts/gates/"; cp "$REPO/scripts/lib/setup_prompt_extract.sh" "$GD/scripts/lib/"
fi
G="$GD/scripts/gates/cm_setup_prompt_latest_present.sh"
FX="$(mk_sandbox)"; mk_setup_dir "$FX" >/dev/null; mkdir -p "$FX/scripts"; printf '#!/bin/sh\n# --help\n' >"$FX/scripts/real.sh"
printf '# x\n\n## PROMPT\n\n```\nbash submodules/constitution/scripts/real.sh --help\n```\n' >"$FX/docs/prompts/setup/latest.md"
OUT="$(mk_sandbox)"; cp "$REPO/scripts/lib/setup_prompt_extract.sh" "$OUT/evil_lib.sh"
o="$(env -u SETUP_PROMPT_EXTRACT_LIB_TRUST bash "$G" --root "$FX" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "I9 gate default library accepted (PASS)" || no "I9 gate default rc=$rc: $o"
o="$(env -u SETUP_PROMPT_EXTRACT_LIB_TRUST SETUP_PROMPT_EXTRACT_LIB="$GD/scripts/lib/setup_prompt_extract.sh" bash "$G" --root "$FX" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "I9 gate explicit library inside its own scripts/lib accepted" || no "I9 gate own lib rc=$rc: $o"
o="$(env -u SETUP_PROMPT_EXTRACT_LIB_TRUST SETUP_PROMPT_EXTRACT_LIB="$OUT/evil_lib.sh" bash "$G" --root "$FX" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && grep -q 'outside' <<<"$o" && ok "I9 gate library outside scripts/lib refused (BLIND rc=2)" || no "I9 gate outside lib rc=$rc: $o"
o="$(SETUP_PROMPT_EXTRACT_LIB_TRUST=1 SETUP_PROMPT_EXTRACT_LIB="$OUT/evil_lib.sh" bash "$G" --root "$FX" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "I9 gate outside library accepted with SETUP_PROMPT_EXTRACT_LIB_TRUST=1" || no "I9 gate trusted outside lib rc=$rc: $o"

summary round3
