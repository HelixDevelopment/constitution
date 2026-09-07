#!/usr/bin/env bash
# ============================================================================
# test_skill_activation.sh — anti-bluff proof for the skill-activation engine.
# ============================================================================
# Every test runs against a REAL scratch project with REAL skill directories on
# a REAL filesystem. No mocks (unit-test-only per CONST-050(A) — this is an
# integration test). Each guard is PAIRED with a §1.1 mutation that must make
# it FAIL, so a guard that cannot fail is exposed as decoration.
# Usage: test_skill_activation.sh   ->  exit 0 all passed / 1 any failed
# ============================================================================
set -uo pipefail
SA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SA_DIR/skill_activate.sh"
GATE="$SA_DIR/skill_budget_gate.sh"
SHIM="$HOME/.claude-shared/bin/skill-activate"
PASS=0; FAIL=0
ok(){ printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL  %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
chk(){ if [ "$1" = "$2" ]; then ok "$3 (got $1)"; else no "$3 (expected $2, got $1)"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/proj/.helix/skills" "$T/proj/.claude"
mk(){ mkdir -p "$T/proj/.helix/skills/$1"; printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$1" "$2" > "$T/proj/.helix/skills/$1/SKILL.md"; }
mk core-one "A core skill that is always active."
mk demand-one "An on-demand skill, not active by default."
mk demand-two "Another on-demand skill."
cat > "$T/proj/.helix/skill-manifest.yaml" <<'M'
schema_version: 1
core:
  - core-one
sources:
  - .helix/skills
M
P="$T/proj"
echo "== skill-activation integration tests =="

# 1 session-init activates core, and the link is genuinely readable
"$CLI" session-init "$P" >/dev/null 2>&1
[ -r "$P/.claude/skills/core-one/SKILL.md" ] && ok "session-init activates core (link readable)" || no "session-init activates core"

# 2 on-demand skill is NOT active by default (this is the whole point)
[ -e "$P/.claude/skills/demand-one" ] && no "on-demand must not be active by default" || ok "on-demand not active by default"

# 3 discoverability survives deactivation: list still shows it
# NOTE: capture first -- `cmd | grep -q` under `set -o pipefail` reports a
# false failure, because grep -q closes the pipe early and SIGPIPEs cmd.
listout="$("$CLI" list "$P" 2>/dev/null)"
case "$listout" in *demand-one*) ok "inactive skill still DISCOVERABLE via list";; *) no "inactive skill vanished from list";; esac

# 4 activate works
"$CLI" activate demand-one "$P" >/dev/null 2>&1
[ -r "$P/.claude/skills/demand-one/SKILL.md" ] && ok "activate makes skill readable" || no "activate failed"

# 5 FAIL-SAFE: unknown skill -> non-zero + explicit message, never silent
out="$("$CLI" activate nope-not-real "$P" 2>&1)"; rc=$?
chk "$rc" "1" "unknown skill exits non-zero"
echo "$out" | grep -q "SKILL-ACTIVATION-FAILED" && ok "unknown skill reports explicitly" || no "unknown skill failed silently"

# 6 MUTATION (§1.1): break the target so the link dangles. Activation MUST fail.
#    If this passes, the fail-safe check is decoration.
mv "$T/proj/.helix/skills/demand-two/SKILL.md" "$T/proj/.helix/skills/demand-two/SKILL.md.hidden"
out="$("$CLI" activate demand-two "$P" 2>&1)"; rc=$?
if [ "$rc" != "0" ]; then ok "MUTATION broken-skill: activation refused (rc=$rc)"; else no "MUTATION broken-skill: activation wrongly SUCCEEDED"; fi
[ -e "$P/.claude/skills/demand-two" ] && no "MUTATION broken-skill: dangling link left behind" || ok "MUTATION broken-skill: no dangling link left"
mv "$T/proj/.helix/skills/demand-two/SKILL.md.hidden" "$T/proj/.helix/skills/demand-two/SKILL.md"

# 7 core is protected from deactivation
out="$("$CLI" deactivate core-one "$P" 2>&1)"; rc=$?
chk "$rc" "1" "deactivating a CORE skill is refused"
[ -r "$P/.claude/skills/core-one/SKILL.md" ] && ok "core skill still active after refused deactivate" || no "core skill was removed"

# 8 CONCURRENCY: a live claim from ANOTHER session must block unlinking
claimdir="$P/.claude/.skill-activation/claims/demand-one"
# a REAL-shaped claim: filename = sanitized session id, line 1 = the config
# dir that proves liveness. This host genuinely has a live claude5 session.
mkdir -p "$claimdir"; printf '%s\n%s\n' "$HOME/.claude-claude5" "now" > "$claimdir/claude-claude5"
HELIX_SKILL_SESSION="other-session" "$CLI" deactivate demand-one "$P" >/dev/null 2>&1
[ -r "$P/.claude/skills/demand-one/SKILL.md" ] && ok "CONCURRENCY: live claim blocks another session's deactivate" || no "CONCURRENCY: skill stripped while another session held it"

# 9 MUTATION (§1.1): replace the live claim with a provably-dead one.
#    The reaper must now allow the unlink -- if it still blocks, the liveness
#    oracle is not actually proving anything.
rm -f "$claimdir/claude-claude5"
printf '%s\n%s\n' "$HOME/.claude-NO-SUCH-SESSION" "now" > "$claimdir/claude-DEAD"
HELIX_SKILL_SESSION="other-session" "$CLI" deactivate demand-one "$P" >/dev/null 2>&1
[ -e "$P/.claude/skills/demand-one" ] && no "MUTATION dead-claim: stale claim wrongly blocked deactivate" || ok "MUTATION dead-claim: dead claim reaped, deactivate proceeded"

# 10 BUDGET GATE passes under a generous limit
HELIX_SKILL_BUDGET_NAME_BYTES=4096 HELIX_SKILL_BUDGET_DESC_BYTES=24576 "$GATE" "$P" >/dev/null 2>&1
chk "$?" "0" "budget gate PASSes under limit"

# 11 MUTATION (§1.1): squeeze the limit below the real surface. Gate MUST FAIL.
HELIX_SKILL_BUDGET_NAME_BYTES=1 "$GATE" "$P" >/dev/null 2>&1
chk "$?" "1" "MUTATION tight-budget: gate FAILs (name-only)"
HELIX_SKILL_BUDGET_NAME_BYTES=4096 HELIX_SKILL_BUDGET_DESC_BYTES=1 "$GATE" "$P" >/dev/null 2>&1
chk "$?" "1" "MUTATION tight-budget: gate FAILs (description-eager 14x cliff guard)"

# 12 MODE C: engine unreachable -> loud degradation, exit 3, never silent success
if [ -x "$SHIM" ]; then
  mkdir -p "$T/fakehome"
  out="$(cd "$T" && env -u HELIX_SKILL_ENGINE -u HELIX_CONSTITUTION_DIR HOME="$T/fakehome" bash "$SHIM" list . 2>&1)"; rc=$?
  chk "$rc" "3" "MODE C: exits 3 (engine absent), not 0"
  echo "$out" | grep -q "SKILL-ACTIVATION-UNAVAILABLE" && ok "MODE C: degrades LOUDLY with a named reason" || no "MODE C: degraded silently"
  echo "$out" | grep -q "EXISTING skills are untouched" && ok "MODE C: states existing skills still work" || no "MODE C: did not state fallback state"
  # MUTATION (§1.1): mode C must never be mistaken for success
  if [ "$rc" = "0" ]; then no "MUTATION mode-C: silent success (false-null)"; else ok "MUTATION mode-C: no false-null success"; fi
else
  echo "  SKIP  MODE C tests - shim not installed at $SHIM (honest skip, not a pass)"
fi

# ===========================================================================
# PRUNE-BY-DEFAULT (§11.4.272 / §11.4.122) — the operator's default since
# 2026-09-07. Pruning DELETES NOTHING, so every test below asserts a
# PRESERVATION property, not merely a removal.
# ===========================================================================
echo "-- prune-by-default --"

# A fresh scratch project: 1 core symlink-able skill, 1 on-demand pool skill,
# and a REAL directory dropped straight into the active dir (the shape that
# would be destroyed by `rm -rf` — .claude/* is gitignored + untracked, so a
# real dir there is single-copy and its loss is permanent).
P2="$T/proj2"
mkdir -p "$P2/.helix/skills" "$P2/.claude/skills"
mk2(){ mkdir -p "$P2/.helix/skills/$1"; printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$1" "$2" > "$P2/.helix/skills/$1/SKILL.md"; }
mk2 core-two   "The core skill for the prune scratch project."
mk2 demand-p   "A pool-backed on-demand skill."
cat > "$P2/.helix/skill-manifest.yaml" <<'M'
schema_version: 1
prune: true
core:
  - core-two
sources:
  - .helix/skills
M
# the REAL directory: unique content that must survive pruning verbatim
mkdir -p "$P2/.claude/skills/native-dir"
printf -- '---\nname: native-dir\ndescription: A real directory living in the active dir.\n---\nUNIQUE-CONTENT-MARKER\n' \
  > "$P2/.claude/skills/native-dir/SKILL.md"
# a pool-backed skill activated up-front so prune has a symlink to demote too
"$CLI" activate demand-p "$P2" >/dev/null 2>&1

before_n=$(ls -1 "$P2/.claude/skills" 2>/dev/null | wc -l)
"$CLI" session-init "$P2" >/dev/null 2>&1
after_n=$(ls -1 "$P2/.claude/skills" 2>/dev/null | wc -l)

# 13 prune is the DEFAULT: session-init reduced the surface to core alone
# (2 = the symlink + the real dir; core-two is not yet raised at this point)
chk "$before_n" "2" "prune: 2 non-core active before session-init"
chk "$after_n" "1" "prune BY DEFAULT: session-init reduced active set to core only"
[ -r "$P2/.claude/skills/core-two/SKILL.md" ] && ok "prune: core survived" || no "prune: core was pruned (must never happen)"
[ -e "$P2/.claude/skills/demand-p" ] && no "prune: non-core symlink still active" || ok "prune: non-core symlink demoted"
[ -e "$P2/.claude/skills/native-dir" ] && no "prune: non-core real dir still active" || ok "prune: non-core real dir demoted"

# 14 NOTHING WAS DELETED — the real dir's content is preserved byte-for-byte in
#    the attic. This is the property that makes pruning safe under §11.4.122.
atticP2="$P2/.claude/.skill-activation/pool"
if [ -r "$atticP2/native-dir/SKILL.md" ] && grep -q 'UNIQUE-CONTENT-MARKER' "$atticP2/native-dir/SKILL.md"; then
  ok "§11.4.122: pruned real dir CONTENT PRESERVED verbatim (moved, never deleted)"
else
  no "§11.4.122: pruned real dir content LOST — pruning deleted user content"
fi
# and the symlink's target is untouched (removing a link destroys nothing)
[ -r "$P2/.helix/skills/demand-p/SKILL.md" ] && ok "§11.4.122: pruned symlink's TARGET untouched" || no "§11.4.122: pruned symlink's target was destroyed"

# 15 STILL LISTED — discoverability survives pruning (the property that makes
#    a pruned skill "dormant and one command away", not removed)
listout2="$("$CLI" list "$P2" 2>/dev/null)"
case "$listout2" in *native-dir*) ok "§11.4.122: pruned real dir still LISTED by catalogue";; *) no "§11.4.122: pruned real dir vanished from catalogue";; esac
case "$listout2" in *demand-p*) ok "§11.4.122: pruned symlink still LISTED by catalogue";; *) no "§11.4.122: pruned symlink vanished from catalogue";; esac

# 16 STILL ACTIVATABLE — the other half of "one command away"
"$CLI" activate native-dir "$P2" >/dev/null 2>&1
if [ -r "$P2/.claude/skills/native-dir/SKILL.md" ] && grep -q 'UNIQUE-CONTENT-MARKER' "$P2/.claude/skills/native-dir/SKILL.md"; then
  ok "§11.4.122: pruned real dir is ACTIVATABLE again, with its content intact"
else
  no "§11.4.122: pruned real dir could not be re-activated"
fi
"$CLI" deactivate native-dir "$P2" >/dev/null 2>&1

# 17 CROSS-TRACK SAFETY: a skill claimed by ANOTHER live session is KEPT.
#    This is the hazard the engine's own refcounting exists for — verified
#    here specifically under the PRUNE path, not only the deactivate path.
"$CLI" activate demand-p "$P2" >/dev/null 2>&1
cd2="$P2/.claude/.skill-activation/claims/demand-p"
mkdir -p "$cd2"; printf '%s\n%s\n' "$HOME/.claude-claude5" "now" > "$cd2/claude-claude5"
HELIX_SKILL_SESSION="prune-session" "$CLI" prune "$P2" >/dev/null 2>&1
[ -e "$P2/.claude/skills/demand-p" ] && ok "CONCURRENCY: prune KEPT a skill another live session holds" || no "CONCURRENCY: prune STRIPPED a skill another live session holds"

# 18 MUTATION (§1.1): replace the live claim with a provably-dead one. Prune
#     must now proceed — else the concurrency check is not proving anything
#     and the test above is decoration (the false-null this engine's own
#     dot-prefixed-session-id bug already produced once).
rm -f "$cd2/claude-claude5"
printf '%s\n%s\n' "$HOME/.claude-NO-SUCH-SESSION" "now" > "$cd2/claude-DEAD"
HELIX_SKILL_SESSION="prune-session" "$CLI" prune "$P2" >/dev/null 2>&1
[ -e "$P2/.claude/skills/demand-p" ] && no "MUTATION dead-claim-prune: stale claim wrongly blocked prune" || ok "MUTATION dead-claim-prune: dead claim reaped, prune proceeded"

# 19 OPT-OUT (env): HELIX_SKILL_PRUNE=0 must genuinely leave the surface alone
"$CLI" activate demand-p "$P2" >/dev/null 2>&1
HELIX_SKILL_PRUNE=0 "$CLI" session-init "$P2" >/dev/null 2>&1
[ -e "$P2/.claude/skills/demand-p" ] && ok "OPT-OUT env: HELIX_SKILL_PRUNE=0 left non-core active" || no "OPT-OUT env: pruned anyway — the opt-out does not opt out"

# 20 OPT-OUT (manifest): `prune: false` must disable it per project.
#     Env is unset here so the manifest value is the one under test.
sed -i 's/^prune: true$/prune: false/' "$P2/.helix/skill-manifest.yaml"
"$CLI" session-init "$P2" >/dev/null 2>&1
[ -e "$P2/.claude/skills/demand-p" ] && ok "OPT-OUT manifest: 'prune: false' left non-core active" || no "OPT-OUT manifest: pruned anyway — manifest opt-out ignored"
# env must WIN over the manifest (per-session override beats per-project policy)
HELIX_SKILL_PRUNE=1 "$CLI" session-init "$P2" >/dev/null 2>&1
[ -e "$P2/.claude/skills/demand-p" ] && no "OPT-OUT precedence: env=1 did NOT override manifest 'prune: false'" || ok "OPT-OUT precedence: env overrides manifest"
sed -i 's/^prune: false$/prune: true/' "$P2/.helix/skill-manifest.yaml"

# 21 NEVER OVERWRITE PRESERVED CONTENT (§9.2): an attic entry of the same name
#     already exists -> prune must REFUSE and leave the skill ACTIVE, not
#     clobber the preserved copy.
mkdir -p "$P2/.claude/skills/collide"
printf -- '---\nname: collide\ndescription: active copy.\n---\nACTIVE\n' > "$P2/.claude/skills/collide/SKILL.md"
mkdir -p "$atticP2/collide"
printf -- '---\nname: collide\ndescription: attic copy.\n---\nPRESERVED-IN-ATTIC\n' > "$atticP2/collide/SKILL.md"
"$CLI" prune "$P2" >/dev/null 2>&1
if [ -r "$P2/.claude/skills/collide/SKILL.md" ] && grep -q 'PRESERVED-IN-ATTIC' "$atticP2/collide/SKILL.md"; then
  ok "§9.2: attic collision REFUSED — skill kept active, preserved copy untouched"
else
  no "§9.2: attic collision clobbered preserved content or dropped the skill"
fi

# 22 MUTATION (§1.1): make prune DESTRUCTIVE (rm -rf instead of mv) in a COPY
#     of the engine — never the live tree (§11.4.84 quiescence: this repo is
#     shared with another agent). The content-preservation guard MUST catch it;
#     if the mutated engine still "passes", guard 14 is decoration.
ENGM="$T/engine_mut"; mkdir -p "$ENGM"; cp "$SA_DIR"/*.sh "$SA_DIR"/*.yaml "$ENGM"/ 2>/dev/null
sed -i 's|if mv "\$e" "\$attic/\$n" 2>/dev/null && \[ -r "\$attic/\$n/SKILL.md" \]; then|if rm -rf "$e" 2>/dev/null \&\& true; then|' "$ENGM/skill_activate.sh"
if grep -q 'rm -rf "\$e"' "$ENGM/skill_activate.sh"; then
  P3="$T/proj3"; mkdir -p "$P3/.helix/skills" "$P3/.claude/skills/victim"
  printf -- '---\nname: victim\ndescription: content that must survive.\n---\nMUST-SURVIVE\n' > "$P3/.claude/skills/victim/SKILL.md"
  cat > "$P3/.helix/skill-manifest.yaml" <<'M'
schema_version: 1
prune: true
core: []
sources:
  - .helix/skills
M
  bash "$ENGM/skill_activate.sh" prune "$P3" >/dev/null 2>&1
  atticP3="$P3/.claude/.skill-activation/pool"
  if [ -r "$atticP3/victim/SKILL.md" ]; then
    no "MUTATION destructive-prune: content survived — mutation did not take, guard unproven"
  else
    ok "MUTATION destructive-prune: content DESTROYED by the mutated engine (guard 14 is load-bearing, not decoration)"
  fi
else
  no "MUTATION destructive-prune: could not apply mutation to the engine copy"
fi

# 24 REGRESSION (observed live 2026-09-07): a skill dir whose SKILL.md is a
#     RELATIVE symlink reaching up out of the dir. Moving it changes its depth,
#     so an un-absolutized relative link dangles and the demotion is refused.
#     RED was observed on the real project (5 skills refused with
#     "demotion to attic failed"); this is the standing guard for the fix.
P4="$T/proj4"
mkdir -p "$P4/.helix/skills" "$P4/.claude/skills/rellink" "$P4/upstream/rellink"
printf -- '---\nname: rellink\ndescription: reached through a relative symlink.\n---\nVIA-RELATIVE-LINK\n' \
  > "$P4/upstream/rellink/SKILL.md"
ln -s "../../../upstream/rellink/SKILL.md" "$P4/.claude/skills/rellink/SKILL.md"
cat > "$P4/.helix/skill-manifest.yaml" <<'M'
schema_version: 1
prune: true
core: []
sources:
  - .helix/skills
M
[ -r "$P4/.claude/skills/rellink/SKILL.md" ] && ok "rel-symlink fixture: readable before prune" || no "rel-symlink fixture: unreadable before prune (fixture broken)"
"$CLI" prune "$P4" >/dev/null 2>&1
atticP4="$P4/.claude/.skill-activation/pool"
if [ -r "$atticP4/rellink/SKILL.md" ] && grep -q 'VIA-RELATIVE-LINK' "$atticP4/rellink/SKILL.md"; then
  ok "REGRESSION rel-symlink: demotion SUCCEEDED and content still reachable"
else
  no "REGRESSION rel-symlink: demotion refused or content unreachable at new depth"
fi
[ -e "$P4/.claude/skills/rellink" ] && no "REGRESSION rel-symlink: still active after successful demotion" || ok "REGRESSION rel-symlink: no longer active"

# 25 MUTATION (§1.1): strip the relocation-safety call from the ENGINE COPY.
#     The demotion must then be REFUSED (and the skill kept active + intact) —
#     proving guard 24 is load-bearing and that the refusal path is real.
ENGM2="$T/engine_mut2"; mkdir -p "$ENGM2"; cp "$SA_DIR"/*.sh "$SA_DIR"/*.yaml "$ENGM2"/ 2>/dev/null
sed -i 's|^\( *\)sa_absolutize_relative_links "\$e"|\1: # MUTATED for paired §1.1 test|' "$ENGM2/skill_activate.sh"
if grep -q 'MUTATED for paired' "$ENGM2/skill_activate.sh"; then
  P5="$T/proj5"
  mkdir -p "$P5/.helix/skills" "$P5/.claude/skills/rellink" "$P5/upstream/rellink"
  printf -- '---\nname: rellink\ndescription: reached through a relative symlink.\n---\nVIA-RELATIVE-LINK\n' \
    > "$P5/upstream/rellink/SKILL.md"
  ln -s "../../../upstream/rellink/SKILL.md" "$P5/.claude/skills/rellink/SKILL.md"
  cp "$P4/.helix/skill-manifest.yaml" "$P5/.helix/skill-manifest.yaml"
  bash "$ENGM2/skill_activate.sh" prune "$P5" >/dev/null 2>&1
  if [ -r "$P5/.claude/skills/rellink/SKILL.md" ]; then
    ok "MUTATION no-absolutize: demotion REFUSED, skill kept ACTIVE and intact (guard 24 load-bearing; fail-safe real)"
  else
    no "MUTATION no-absolutize: mutated engine still demoted (guard 24 is decoration) OR content was lost"
  fi
else
  no "MUTATION no-absolutize: could not apply mutation to the engine copy"
fi

# 23 BUDGET GATE still fires on the post-prune project (the surface guard
#     survives the new default)
HELIX_SKILL_BUDGET_NAME_BYTES=4096 HELIX_SKILL_BUDGET_DESC_BYTES=24576 "$GATE" "$P2" >/dev/null 2>&1
chk "$?" "0" "budget gate PASSes on pruned project"
HELIX_SKILL_BUDGET_NAME_BYTES=1 "$GATE" "$P2" >/dev/null 2>&1
chk "$?" "1" "MUTATION tight-budget on pruned project: gate FAILs"

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" = "0" ]
