#!/usr/bin/env bash
# test_setup_prompt_behaviour.sh — EXECUTES the shell blocks of the real
# docs/prompts/setup/latest.md (delimited by `# STEPn-BEGIN` / `# STEPn-END`
# marker lines inside the PROMPT block) against throw-away git repositories, and
# checks the review round 1 text fixes. Nothing outside a mktemp -d sandbox is
# written; no network (all remotes are local bare repositories).
#   STEP1  backup: .claude/settings.local.json and .env are NOT copied
#   STEP3  manual add: an already registered submodule is not added twice
#   STEP4  legacy preconditions: a dirty legacy submodule stops (exit 3), no git mv
#   STEP5  update: fast-forward applied; diverged / dirty / unpushed stop with
#          exit 3 and change nothing; HEAD newer than the newest tag is kept
#   STEP10 push: refused unless the current branch is main
#   round 2 (review IMP-1, IMP-2, minors 3/4/5/8):
#   STEP2/STEP5 on a registered but UNINITIALISED submodules/constitution (a fresh
#          clone without --recurse leaves an empty directory, and every
#          `git -C <empty dir>` then acts on the PARENT project): reproduced
#          parent-HEAD-detach must not happen; reachable -> initialised and updated,
#          unreachable -> exit 3 with the parent untouched
#   STEP4  uninitialised legacy submodule: initialised before `git mv`; unreachable
#          -> exit 3 BEFORE the move (no staged rename left behind)
#   STEP1  re-run: a NEW unique backup directory each run, earlier ones untouched,
#          bundle skipped (SAME_AS) when the refs are unchanged
#   STEP4G legacy-reference search: bounded to 200 lines with a count, vendor /
#          node_modules / build directories excluded, control needle printed
#   STEP6B setup.sh --check-only: PARSE ERROR / MISSING stop (exit 3) although
#          setup.sh itself exits 0
#   STEP3  mirror fallback: the first reachable URL is used; none reachable -> exit 3
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_ALLOW_PROTOCOL=file   # local bare remotes only
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }

LATEST="$REPO/docs/prompts/setup/latest.md"
[ -f "$LATEST" ] || { no "latest.md present"; summary behaviour; exit 1; }
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || no "installer extractor found no PROMPT block"
step_block() { # <n> -> the lines between `# STEP<n>-BEGIN` and `# STEP<n>-END`
  awk -v b="# STEP$1-BEGIN" -v e="# STEP$1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$block"
}
for n in 1 2 3 4 4G 5 6B 10; do
  [ -n "$(step_block "$n")" ] && ok "STEP$n block present (markers)" || no "STEP$n block markers missing"
done
run_block() { # <n> <dir> -> runs the block in <dir> with bash, returns its rc
  ( cd "$2" && bash -c "$(step_block "$1")" ) >"$2.block_out" 2>&1
}

# ---------- fixture: a bare constitution remote with tags -----------------------
mk_remote() { # <sandbox> -> bare repo at <sandbox>/remote.git with c1(v1) c2(v2) on main
  local s="$1" w="$1/work"
  git_q init -q "$w"; printf 'one\n' >"$w/f"; git -C "$w" add f; git -C "$w" commit -q -m c1
  git -C "$w" tag helixconstitution-v1
  printf 'two\n' >"$w/f"; git -C "$w" commit -q -am c2; git -C "$w" tag helixconstitution-v2
  git_q clone -q --bare "$w" "$s/remote.git"
}
mk_project() { # <sandbox> <ref-to-checkout> -> project at <sandbox>/p with submodules/constitution
  # REGISTERED as a submodule (CURRENT layout), checked out at <ref>, gitlink committed
  local s="$1"
  git_q init -q "$s/p"; printf '# p\n' >"$s/p/README.md"; git -C "$s/p" add README.md; git -C "$s/p" commit -q -m init
  mkdir -p "$s/p/submodules"; git_q -C "$s/p" submodule add -q "$s/remote.git" submodules/constitution >/dev/null 2>&1
  git -C "$s/p/submodules/constitution" checkout -q "$2"
  git -C "$s/p" add submodules/constitution; git -C "$s/p" commit -q -m sub
}
idx() { git -C "$1" diff --cached --name-only; }

# STEP5 fast-forward
S="$(mk_sandbox)"; mk_remote "$S"; mk_project "$S" helixconstitution-v1
run_block 5 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && ok "STEP5 fast-forward rc=0" || no "STEP5 FF rc=$rc: $(cat "$S/p.block_out")"
[ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD)" = "$(git -C "$S/remote.git" rev-parse helixconstitution-v2^{commit})" ] \
  && ok "STEP5 FF checked out the newest tag" || no "STEP5 FF HEAD not v2"
grep -qx 'submodules/constitution' <<<"$(idx "$S/p")" && ok "STEP5 FF staged the gitlink" || no "STEP5 FF not staged"

# STEP5 diverged: the newest tag is on a side branch that does not contain HEAD
S="$(mk_sandbox)"; mk_remote "$S"; w="$S/work"
git -C "$w" checkout -q helixconstitution-v1; git -C "$w" checkout -q -b side
printf 'side\n' >"$w/g"; git -C "$w" add g; git -C "$w" commit -q -m side; git -C "$w" tag helixconstitution-v3
git -C "$w" push -q "$S/remote.git" side helixconstitution-v3
mk_project "$S" helixconstitution-v2; before="$(git -C "$S/p/submodules/constitution" rev-parse HEAD)"
run_block 5 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'NOT-FF' "$S/p.block_out" && ok "STEP5 diverged stops rc=3 (NOT-FF)" || no "STEP5 diverged rc=$rc: $(cat "$S/p.block_out")"
[ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD)" = "$before" ] && ok "STEP5 diverged: no checkout" || no "STEP5 diverged: HEAD moved"
[ -z "$(idx "$S/p")" ] && ok "STEP5 diverged: nothing staged" || no "STEP5 diverged staged: $(idx "$S/p")"

# STEP5 HEAD newer than the newest tag (pushed, on main): kept, rc=0, nothing staged
S="$(mk_sandbox)"; mk_remote "$S"; w="$S/work"
git -C "$w" checkout -q main 2>/dev/null || git -C "$w" checkout -q master
printf 'three\n' >"$w/f"; git -C "$w" commit -q -am c3; git -C "$w" push -q "$S/remote.git" HEAD:main
mk_project "$S" origin/main; before="$(git -C "$S/p/submodules/constitution" rev-parse HEAD)"
run_block 5 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && ok "STEP5 HEAD newer than tag: rc=0 (kept)" || no "STEP5 newer rc=$rc: $(cat "$S/p.block_out")"
[ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD)" = "$before" ] && ok "STEP5 newer: never downgraded" || no "STEP5 newer: downgraded"
[ -z "$(idx "$S/p")" ] && ok "STEP5 newer: nothing staged" || no "STEP5 newer staged"

# STEP5 dirty submodule
S="$(mk_sandbox)"; mk_remote "$S"; mk_project "$S" helixconstitution-v1; printf 'local\n' >>"$S/p/submodules/constitution/f"
before="$(git -C "$S/p/submodules/constitution" rev-parse HEAD)"
run_block 5 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && [ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD)" = "$before" ] && [ -z "$(idx "$S/p")" ] \
  && grep -q 'local changes' "$S/p.block_out" \
  && ok "STEP5 dirty submodule stops rc=3 (local changes), nothing changed" || no "STEP5 dirty rc=$rc: $(cat "$S/p.block_out")"
grep -q local "$S/p/submodules/constitution/f" && ok "STEP5 dirty: local edit preserved" || no "STEP5 dirty: local edit lost"

# STEP5 unpushed local commit
S="$(mk_sandbox)"; mk_remote "$S"; mk_project "$S" helixconstitution-v1; c="$S/p/submodules/constitution"
git -C "$c" checkout -q -b mine; printf 'mine\n' >"$c/h"; git -C "$c" add h; git -C "$c" commit -q -m mine
before="$(git -C "$c" rev-parse HEAD)"
run_block 5 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && [ "$(git -C "$c" rev-parse HEAD)" = "$before" ] && [ -z "$(idx "$S/p")" ] \
  && grep -q 'commits no remote has' "$S/p.block_out" \
  && ok "STEP5 unpushed commit stops rc=3 (unpushed), nothing changed" || no "STEP5 unpushed rc=$rc: $(cat "$S/p.block_out")"

# STEP4 legacy preconditions: dirty legacy submodule -> rc=3, nothing moved
S="$(mk_sandbox)"; mk_remote "$S"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"
git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
git_q -C "$S/p" submodule add -q "$S/remote.git" constitution >/dev/null 2>&1; git -C "$S/p" commit -q -m sub
printf 'dirty\n' >>"$S/p/constitution/f"
run_block 4 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && ok "STEP4 dirty legacy submodule stops rc=3" || no "STEP4 dirty rc=$rc: $(cat "$S/p.block_out")"
[ -d "$S/p/constitution" ] && [ ! -e "$S/p/submodules/constitution" ] && ok "STEP4 dirty: no git mv happened" || no "STEP4 dirty: moved"
# STEP4 clean legacy submodule: moved
S="$(mk_sandbox)"; mk_remote "$S"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"
git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
git_q -C "$S/p" submodule add -q "$S/remote.git" constitution >/dev/null 2>&1; git -C "$S/p" commit -q -m sub
run_block 4 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && [ -e "$S/p/submodules/constitution/f" ] && [ ! -e "$S/p/constitution" ] \
  && ok "STEP4 clean legacy submodule moved (rc=0)" || no "STEP4 clean rc=$rc: $(cat "$S/p.block_out")"
grep -q 'path = submodules/constitution' "$S/p/.gitmodules" && ok "STEP4 .gitmodules path updated" || no "STEP4 .gitmodules not updated"

# STEP3 already registered: no second add, rc=0
S="$(mk_sandbox)"; mk_remote "$S"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"
git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init; mkdir -p "$S/p/submodules"
git_q -C "$S/p" submodule add -q "$S/remote.git" submodules/constitution >/dev/null 2>&1
gm="$(cat "$S/p/.gitmodules")"
run_block 3 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && ok "STEP3 already-registered submodule: rc=0" || no "STEP3 already rc=$rc: $(cat "$S/p.block_out")"
grep -qi 'already' "$S/p.block_out" && ok "STEP3 says 'already in place'" || no "STEP3 output: $(cat "$S/p.block_out")"
[ "$(cat "$S/p/.gitmodules")" = "$gm" ] && ok "STEP3 .gitmodules unchanged" || no "STEP3 .gitmodules changed"

# STEP1 backup: secrets not copied
S="$(mk_sandbox)"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/CLAUDE.md"; git -C "$S/p" add CLAUDE.md; git -C "$S/p" commit -q -m init
mkdir -p "$S/p/.claude"; printf '{"hooks":{}}\n' >"$S/p/.claude/settings.json"; printf '{"env":{"X":"y"}}\n' >"$S/p/.claude/settings.local.json"
printf 'TOKEN=zzz\n' >"$S/p/.env"
run_block 1 "$S/p"; rc=$?
bkd="$(ls -d "$S/p/.constitution-install-backup"/*/ 2>/dev/null | head -n1)"
[ "$rc" -eq 0 ] && [ -n "$bkd" ] && ok "STEP1 backup created (rc=0)" || no "STEP1 rc=$rc: $(cat "$S/p.block_out")"
[ -f "$bkd/.claude/settings.json" ] && ok "STEP1 .claude/settings.json backed up" || no "STEP1 settings.json missing in backup"
[ -z "$(find "$bkd" -name 'settings.local.json' -o -name '.env' 2>/dev/null)" ] && ok "STEP1 settings.local.json and .env NOT in backup" || no "STEP1 secret file copied"
[ -f "$bkd/CLAUDE.md" ] && [ -f "$bkd/project.bundle" ] && ok "STEP1 CLAUDE.md + bundle in backup" || no "STEP1 backup incomplete"

# STEP10 push refused off main
S="$(mk_sandbox)"; git_q init -q --bare "$S/up.git"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init
git -C "$S/p" remote add origin "$S/up.git"; git -C "$S/p" checkout -q -b feature
run_block 10 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && ok "STEP10 push refused on a non-main branch (rc=3)" || no "STEP10 off-main rc=$rc: $(cat "$S/p.block_out")"
[ -z "$(git -C "$S/up.git" for-each-ref)" ] && ok "STEP10 nothing pushed" || no "STEP10 pushed: $(git -C "$S/up.git" for-each-ref)"
git -C "$S/p" checkout -q main
run_block 10 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$S/up.git" rev-parse main 2>/dev/null)" = "$(git -C "$S/p" rev-parse main)" ] \
  && ok "STEP10 push on main fast-forwards the upstream (rc=0)" || no "STEP10 main rc=$rc: $(cat "$S/p.block_out")"

# ---------- round 2: uninitialised submodule (IMP-1, IMP-2) -------------------------
mk_uninit() { # <sandbox> <subpath> -> <sandbox>/p is a clone (no --recurse) of a project whose
  # submodule <subpath> points at <sandbox>/remote.git @ v1; the submodule dir is EMPTY
  local s="$1" sp="$2"
  git_q init -q "$s/p0"; printf '# p\n' >"$s/p0/README.md"; git -C "$s/p0" add README.md; git -C "$s/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$s/p0/submodules"
  git_q -C "$s/p0" submodule add -q "$s/remote.git" "$sp" >/dev/null 2>&1
  git -C "$s/p0/$sp" checkout -q helixconstitution-v1; git -C "$s/p0" add "$sp"; git -C "$s/p0" commit -q -m sub
  git_q clone -q "$s/p0" "$s/p"
  # the parent's own upstream moves ahead: a `git -C <empty dir> checkout origin/main`
  # that falls through to the parent would then DETACH the parent (the reproduced bug)
  printf 'ahead\n' >>"$s/p0/README.md"; git -C "$s/p0" commit -q -am ahead
}
parent_state() { printf '%s %s %s' "$(git -C "$1" symbolic-ref -q HEAD || echo DETACHED)" "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" diff --cached --name-status | tr '\n' ';')"; }

for blk in 5 2; do
  # reachable: initialised, then (STEP5) updated; the parent is never touched
  S="$(mk_sandbox)"; mk_remote "$S"; mk_uninit "$S" submodules/constitution
  [ -z "$(ls -A "$S/p/submodules/constitution")" ] && ok "IMP-1 fixture: submodule dir empty after a plain clone" || no "IMP-1 fixture not empty"
  pb="$(git -C "$S/p" symbolic-ref -q HEAD) $(git -C "$S/p" rev-parse HEAD)"
  run_block "$blk" "$S/p"; rc=$?
  pa="$(git -C "$S/p" symbolic-ref -q HEAD || echo DETACHED) $(git -C "$S/p" rev-parse HEAD)"
  [ "$pa" = "$pb" ] && ok "IMP-1 STEP$blk uninit+reachable: parent HEAD unchanged, still on a branch" || no "IMP-1 STEP$blk parent changed: before=[$pb] after=[$pa] out=$(cat "$S/p.block_out")"
  [ "$rc" -eq 0 ] && ok "IMP-1 STEP$blk uninit+reachable rc=0" || no "IMP-1 STEP$blk rc=$rc: $(cat "$S/p.block_out")"
  [ "$(git -C "$S/p/submodules/constitution" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$S/p" && pwd -P)/submodules/constitution" ] \
    && ok "IMP-1 STEP$blk submodule initialised (own checkout)" || no "IMP-1 STEP$blk submodule not initialised"
  if [ "$blk" = 5 ]; then
    [ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD)" = "$(git -C "$S/remote.git" rev-parse helixconstitution-v2^{commit})" ] \
      && ok "IMP-1 STEP5 updated the SUBMODULE to v2" || no "IMP-1 STEP5 submodule not at v2"
  fi
  # unreachable: STOP, parent untouched
  S="$(mk_sandbox)"; mk_remote "$S"; mk_uninit "$S" submodules/constitution; mv "$S/remote.git" "$S/gone.git"
  pb="$(parent_state "$S/p")"
  run_block "$blk" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && ok "IMP-1 STEP$blk uninit+unreachable stops rc=3" || no "IMP-1 STEP$blk unreachable rc=$rc: $(cat "$S/p.block_out")"
  [ "$(parent_state "$S/p")" = "$pb" ] && ok "IMP-1 STEP$blk unreachable: parent HEAD/index untouched" || no "IMP-1 STEP$blk unreachable: parent changed [$pb] -> [$(parent_state "$S/p")]"
done

# IMP-1: a registered submodule whose .git link file was lost: git reports it as '-',
# the init step repairs it; either way the parent project is never touched
for blk in 2 5; do
  S="$(mk_sandbox)"; mk_remote "$S"; mk_project "$S" helixconstitution-v1
  rm -f -- "$S/p/submodules/constitution/.git"
  pb="$(parent_state "$S/p" | cut -d' ' -f1,2)"; sst="$(git -C "$S/p" submodule status -- submodules/constitution 2>&1 | cut -c1)"
  run_block "$blk" "$S/p"; rc=$?
  own="$(git -C "$S/p/submodules/constitution" rev-parse --show-toplevel 2>/dev/null)"
  { [ "$rc" -eq 3 ] || { [ "$rc" -eq 0 ] && [ "$own" = "$(cd "$S/p" && pwd -P)/submodules/constitution" ]; }; } && [ "$(parent_state "$S/p" | cut -d' ' -f1,2)" = "$pb" ] \
    && ok "IMP-1 STEP$blk lost .git link (status prefix '$sst'): rc=$rc (repaired or stopped), parent branch and HEAD untouched" \
    || no "IMP-1 STEP$blk lost .git link rc=$rc prefix='$sst': $(cat "$S/p.block_out")"
done

# IMP-2: uninitialised LEGACY submodule
S="$(mk_sandbox)"; mk_remote "$S"; mk_uninit "$S" constitution
run_block 4 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && [ -e "$S/p/submodules/constitution/f" ] && [ ! -e "$S/p/constitution" ] \
  && ok "IMP-2 STEP4 uninit legacy reachable: initialised then moved (rc=0)" || no "IMP-2 STEP4 reachable rc=$rc: $(cat "$S/p.block_out")"
[ "$(git -C "$S/p/submodules/constitution" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$S/p" && pwd -P)/submodules/constitution" ] \
  && ok "IMP-2 STEP4 moved submodule is its own checkout" || no "IMP-2 STEP4 gitdir broken after move"
S="$(mk_sandbox)"; mk_remote "$S"; mk_uninit "$S" constitution; mv "$S/remote.git" "$S/gone.git"
gm="$(cat "$S/p/.gitmodules")"; pb="$(parent_state "$S/p")"
run_block 4 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && ok "IMP-2 STEP4 uninit legacy unreachable stops rc=3" || no "IMP-2 STEP4 unreachable rc=$rc: $(cat "$S/p.block_out")"
grep -qE '^R' <<<"$(git -C "$S/p" status --porcelain)" && no "IMP-2 STEP4 left a staged rename: $(git -C "$S/p" status --porcelain)" || ok "IMP-2 STEP4 no 'R constitution -> ...' left behind"
[ -d "$S/p/constitution" ] && [ ! -e "$S/p/submodules/constitution" ] && [ "$(cat "$S/p/.gitmodules")" = "$gm" ] && [ "$(parent_state "$S/p")" = "$pb" ] \
  && ok "IMP-2 STEP4 unreachable: legacy path, .gitmodules and parent untouched" || no "IMP-2 STEP4 unreachable: state changed"

# ---------- round 2: STEP1 re-run (minor 4) -----------------------------------------
S="$(mk_sandbox)"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/CLAUDE.md"; git -C "$S/p" add CLAUDE.md; git -C "$S/p" commit -q -m init
run_block 1 "$S/p"; rc1=$?; run_block 1 "$S/p"; rc2=$?
mapfile -t bks < <(ls -1d "$S/p/.constitution-install-backup"/*/ 2>/dev/null)
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "${#bks[@]}" -eq 2 ] && ok "M4 STEP1 two runs -> two distinct backup dirs" || no "M4 STEP1 runs rc=$rc1/$rc2 dirs=${#bks[@]}"
first="$(for d in "${bks[@]}"; do [ -f "$d/project.bundle" ] && echo "$d"; done | head -n1)"
second="$(for d in "${bks[@]}"; do [ -f "$d/SAME_AS" ] && echo "$d"; done | head -n1)"
[ -n "$first" ] && [ -n "$second" ] && [ ! -e "$second/project.bundle" ] && ok "M4 STEP1 unchanged refs: second run skips the bundle (SAME_AS)" || no "M4 STEP1 SAME_AS/bundle layout wrong"
[ -n "$first" ] && git -C "$S/p" bundle verify "$first/project.bundle" >/dev/null 2>&1 && ok "M4 STEP1 first bundle still valid" || no "M4 STEP1 first bundle damaged"
printf 'x\n' >>"$S/p/CLAUDE.md"; git -C "$S/p" commit -q -am two
run_block 1 "$S/p"; rc3=$?
n_b="$(find "$S/p/.constitution-install-backup" -name project.bundle | wc -l)"
[ "$rc3" -eq 0 ] && [ "$n_b" -eq 2 ] && ok "M4 STEP1 changed refs: a new bundle is written" || no "M4 STEP1 after commit rc=$rc3 bundles=$n_b"

# ---------- round 2: STEP4G bounded legacy-reference search (minor 5) ----------------
S="$(mk_sandbox)"; git_q init -q "$S/p"; P="$S/p"
printf '[submodule "constitution"]\n\tpath = submodules/constitution\n' >"$P/.gitmodules"
mkdir -p "$P/src" "$P/node_modules/m" "$P/vendor/v" "$P/build" "$P/many"
printf 'bash ./constitution/x.sh\n' >"$P/src/a.sh"
printf 'bash ./constitution/x.sh\n' >"$P/node_modules/m/b.sh"; printf 'bash ./constitution/x.sh\n' >"$P/vendor/v/c.sh"; printf 'bash ./constitution/x.sh\n' >"$P/build/d.sh"
for i in $(seq 1 250); do printf 'see constitution/CLAUDE.md\n' >"$P/many/f$i.md"; done
run_block 4G "$P"; rc=$?; out="$(cat "$P.block_out")"
grep -qE 'hits: 251' <<<"$out" && ok "M5 STEP4G prints the full count (251)" || no "M5 STEP4G count: $(grep hits <<<"$out")"
[ "$(grep -cE '^(src|many)/' <<<"$out")" -le 200 ] && ok "M5 STEP4G output bounded to 200 hit lines" || no "M5 STEP4G unbounded: $(grep -cE '^(src|many)/' <<<"$out")"
grep -qE '^(node_modules|vendor|build)/' <<<"$out" && no "M5 STEP4G vendor/build dirs not excluded" || ok "M5 STEP4G node_modules/vendor/build excluded"
grep -qE 'control needle: .*:[1-9]' <<<"$out" && ok "M5 STEP4G control needle sees .gitmodules" || no "M5 STEP4G needle: $(grep needle <<<"$out")"

# ---------- round 2: STEP6B check-only parsing (minor 8) -----------------------------
mk_const() { # <project> <hook-mode: ok|parse|missing>
  local c="$1/submodules/constitution"; mkdir -p "$c/scripts/lib"
  printf '# C\n' >"$c/Constitution.md"
  cp "$REPO/scripts/setup.sh" "$c/scripts/setup.sh"
  # every library setup.sh sources (class, not instance: the list is read from setup.sh itself)
  local lib n=0
  for lib in $(sed -nE 's#^[[:space:]]*\.[[:space:]]+"\$SCRIPT_DIR/(lib/[A-Za-z0-9_.-]+\.sh)".*#\1#p' "$REPO/scripts/setup.sh"); do
    cp "$REPO/scripts/$lib" "$c/scripts/lib/" || return 1; n=$((n + 1))
  done
  [ "$n" -ge 1 ] || { echo "mk_const: no sourced library found in setup.sh (BLIND)" >&2; return 1; }
  case "$2" in
    ok) printf '#!/bin/sh\ntrue\n' >"$c/scripts/post_update_hook.sh"; chmod +x "$c/scripts/post_update_hook.sh" ;;
    parse) printf '#!/bin/sh\nif then fi (\n' >"$c/scripts/post_update_hook.sh"; chmod +x "$c/scripts/post_update_hook.sh" ;;
    missing) : ;;
  esac
}
for mode in ok parse missing; do
  S="$(mk_sandbox)"; git_q init -q "$S/p"; mk_const "$S/p" "$mode"
  raw_rc="$(cd "$S/p" && bash submodules/constitution/scripts/setup.sh --check-only >/dev/null 2>&1; echo $?)"
  run_block 6B "$S/p"; rc=$?
  want=3; [ "$mode" = ok ] && want=0
  [ "$rc" -eq "$want" ] && ok "M8 STEP6B $mode -> rc=$rc (setup.sh itself exited $raw_rc)" || no "M8 STEP6B $mode rc=$rc want=$want: $(cat "$S/p.block_out")"
done

# ---------- round 2: STEP3 mirror fallback (minor 8) ---------------------------------
S="$(mk_sandbox)"; mk_remote "$S"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"; git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
( export CONSTITUTION_URLS="$S/missing.git $S/remote.git"; run_block 3 "$S/p" ); rc=$?
[ "$rc" -eq 0 ] && grep -q "url = $S/remote.git" "$S/p/.gitmodules" && ok "M8 STEP3 falls back to the next reachable mirror" || no "M8 STEP3 fallback rc=$rc: $(cat "$S/p.block_out")"
[ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD 2>/dev/null)" = "$(git -C "$S/remote.git" rev-parse helixconstitution-v2^{commit})" ] && ok "M8 STEP3 newest tag checked out" || no "M8 STEP3 not at newest tag"
S="$(mk_sandbox)"; git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"; git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
( export CONSTITUTION_URLS="$S/missing1.git $S/missing2.git"; run_block 3 "$S/p" ); rc=$?
[ "$rc" -eq 3 ] && [ ! -e "$S/p/submodules/constitution" ] && [ ! -e "$S/p/.gitmodules" ] && ok "M8 STEP3 no mirror reachable -> rc=3, nothing added" || no "M8 STEP3 none-reachable rc=$rc"

# ---------- text fixes ------------------------------------------------------------
has() { grep -qE -- "$1" <<<"$block"; }
gg="$(grep -nE 'git grep' <<<"$block" | grep -v -- '--untracked' || true)"
[ -z "$gg" ] && ok "I5 no tracked-only git grep for legacy references" || no "I5 tracked-only git grep: $gg"
for f in settings.local.json GEMINI.md QWEN.md; do
  s7="$(awk 'index($0,"# S7-END"){f=0} f{print} index($0,"# S7-BEGIN"){f=1}' <<<"$block")"   # round 3: S7 is a marked block
  grep -qF "$f" <<<"$s7" && ok "I5 S7 searches $f" || no "I5 S7 misses $f"
done
grep -qE 'control needle' <<<"$(grep -A3 -E '^ *S7 ' <<<"$block")" && ok "I5 S7 has a control needle" || no "I5 S7 control needle missing"
v6="$(grep -E 'V6' "$REPO/docs/prompts/setup/followups/01_verify_incorporation.md")"
grep -q 'git grep' <<<"$v6" && ! grep -q -- '--untracked' <<<"$v6" && no "I5 follow-up V6 uses tracked-only git grep" || ok "I5 follow-up V6 not tracked-only"
has 'git rev-parse --git-path hooks' && ok "M4 6b names git rev-parse --git-path hooks" || no "M4 6b stale"
has '\.constitution-hook-backup' && ok "M4 6b names the hook backup directory" || no "M4 6b backup missing"
! has 'COPIES every file' && ok "M4 stale 'COPIES every file' removed" || no "M4 stale copy text"
! has "skip 6b's setup run" && ok "M5 STEP 2 no longer claims the hook replaces setup.sh" || no "M5 stale"
grep -qE 'I1 .*a line starting with' <<<"$block" && ok "M7 I1 says 'a line starting with'" || no "M7 wording"
has 'HelixConstitution/\$tag/scripts/install_constitution\.sh' && ok "M9 installer downloaded from the release tag" || no "M9 unpinned download"
has 'trust decision' && ok "M9 trust decision stated for main-only mirrors" || no "M9 trust decision missing"
# minor 3: every $bk use after STEP 1 is ${bk:?}
after1="$(awk 'index($0,"# STEP1-END"){f=1;next} f{print}' <<<"$block")"
bare="$(grep -nE '\$bk([^A-Za-z0-9_]|$)|"\$bk' <<<"$after1" || true)"
[ -z "$bare" ] && ok "M3 no bare \$bk after STEP 1" || no "M3 bare \$bk after STEP 1: $bare"
grep -qF '${bk:?}' <<<"$after1" && ok "M3 \${bk:?} used after STEP 1" || no "M3 \${bk:?} missing"
# minor 4: the idempotency claim states that each run makes a new backup
head_txt="$(awk '/^## PROMPT/{exit} {print}' "$LATEST")"
grep -qiE 'new.*backup' <<<"$head_txt" && ! grep -qE 'second run on an incorporated project changes nothing$' <<<"$head_txt" \
  && ok "M4 re-run text states a new backup per run" || no "M4 re-run text still claims nothing changes"

summary behaviour
