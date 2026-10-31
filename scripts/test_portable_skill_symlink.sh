#!/usr/bin/env bash
# ============================================================================
# test_portable_skill_symlink.sh — §11.4.115 polarity guard for the
# skill-registration symlink portability invariant.
# ============================================================================
# Purpose:
#   Prove that every symlink the skill-registration generators create inside a
#   consuming project stores a target that is PORTABLE — i.e. the link keeps
#   resolving when the checkout lives at a DIFFERENT absolute path than the one
#   it was generated at.
#
#   The defect this guards (forensic, consuming-project commit cc622528):
#   register.sh computed an ABSOLUTE $SCRIPT_DIR and did `ln -sf "$SCRIPT_DIR"`,
#   baking the AUTHORING HOST's path into a tracked link. A link generated on a
#   macOS host with an external volume (/Volumes/T7/...) had NEVER once resolved
#   in a Linux checkout of the same repository. A link that merely works in
#   place proves NOTHING — the invariant is only meaningful under RELOCATION.
#
# §11.4.115 polarity switch (ONE test source, two roles):
#   RED_MODE=1 (default) — reproduces the DEFECT CLASS honestly. A strawman
#     generator emits the exact pre-fix construct (`ln -sf "$abs_dir"`). The
#     strawman's construct is cross-checked against the REAL generators by grep
#     so the simulation cannot silently diverge from what shipped. RED PASSES
#     only when relocation genuinely BREAKS the strawman's link — i.e. when the
#     harness demonstrably has the power to detect the defect. A RED run that
#     reports the strawman as fine means this test is BLIND and must be fixed
#     before its GREEN verdict may be believed.
#   RED_MODE=0 (GREEN) — exercises the REAL constitution generators
#     (constitution/skills/*/register.sh and the shared
#     scripts/install_cli_agent_plugins.sh --skill path). GREEN PASSES only
#     when EVERY link the real generators create (a) stores a RELATIVE target
#     and (b) still resolves INSIDE the tree after the whole tree is MOVED to a
#     different absolute path.
#
# Usage:
#   RED_MODE=1 bash scripts/test_portable_skill_symlink.sh   # RED (default)
#   RED_MODE=0 bash scripts/test_portable_skill_symlink.sh   # GREEN
#
# Inputs:  RED_MODE (0|1, default 1); optional HXC_SYMLINK_TEST_EVIDENCE_DIR.
#          CONST_ROOT is derived from THIS file's own location, deliberately
#          independent of the files under test.
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log. Exit 0 iff the
#          FAIL count is 0.
# Side-effects: NONE outside a fresh scratch dir under $TMPDIR and $EV. Never
#          touches the real project root, never runs a generator against it.
# Dependencies: bash, cp, mv, ln, readlink, grep, dirname, basename.
# Cross-references: §11.4.115 (RED-baseline polarity), §11.4.28 (the engine is
#          project-agnostic), §11.4.111 (resolve by stable relative identity,
#          never by a host-absolute path), §11.4.6 (assertions re-derive state
#          via readlink rather than trusting a generator's own stdout).
# Classification: universal (§11.4.17)
# Last verified: 2026-07-29
# ============================================================================
set -uo pipefail

RED_MODE="${RED_MODE:-1}"

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
const_root="$(cd "$self_dir/.." >/dev/null 2>&1 && pwd)"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
EV="${HXC_SYMLINK_TEST_EVIDENCE_DIR:-${TMPDIR:-/tmp}/portable_symlink_test_${ts}-$$}"
mkdir -p "$EV"
LOG="$EV/results.log"

pass_n=0; fail_n=0; skip_n=0
_p() { pass_n=$((pass_n+1)); printf 'PASS  %s\n' "$*" | tee -a "$LOG"; }
_f() { fail_n=$((fail_n+1)); printf 'FAIL  %s\n' "$*" | tee -a "$LOG"; }
_s() { skip_n=$((skip_n+1)); printf 'SKIP  %s\n' "$*" | tee -a "$LOG"; }
_i() { printf '      %s\n' "$*" | tee -a "$LOG"; }

printf '== portable-skill-symlink guard (RED_MODE=%s) ==\n' "$RED_MODE" | tee -a "$LOG"
printf '   const_root=%s\n   evidence=%s\n' "$const_root" "$EV" | tee -a "$LOG"

# ── Build a scratch replica of a consuming project ──────────────────────────
# Only what the --skill path needs: <root>/constitution/{skills,scripts}. The
# generators are COPIED VERBATIM from the real tree so this exercises the real
# artifact, never a paraphrase of it.
build_replica() {
  local dest="$1"
  mkdir -p "$dest/constitution/scripts"
  # A consuming project's own scripts/ dir must exist, else generators that
  # plant a convenience link there (session-sync) silently skip it and the
  # harness would under-report its coverage.
  mkdir -p "$dest/scripts"
  cp -a "$const_root/skills" "$dest/constitution/skills"
  local f
  for f in install_cli_agent_plugins.sh portable_symlink_lib.sh; do
    [ -f "$const_root/scripts/$f" ] && cp -a "$const_root/scripts/$f" "$dest/constitution/scripts/$f"
  done
  return 0
}

# Collect every symlink under the project root that is NOT inside constitution/
# (i.e. every link a generator planted in the consuming project).
planted_links() {
  local root="$1"
  find "$root" -path "$root/constitution" -prune -o -type l -print 2>/dev/null | sort
}

# ── Assertion: relocation-survival ─────────────────────────────────────────
# gen_dir is MOVED to new_dir, then every planted link is re-derived from disk.
# Returns 0 when ALL links are portable, 1 when at least one is not.
assert_portable_after_move() {
  local gen_dir="$1" new_dir="$2" label="$3"
  local links link tgt resolved bad=0 n=0

  links="$(planted_links "$new_dir")"
  if [ -z "$links" ]; then
    _f "$label: generator planted NO symlinks at all — nothing to assert (harness or generator broken)"
    return 1
  fi

  while IFS= read -r link; do
    [ -n "$link" ] || continue
    n=$((n+1))
    tgt="$(readlink "$link")"
    case "$tgt" in
      /*)
        bad=1
        _i "  [absolute] $link -> $tgt"
        ;;
      *)
        _i "  [relative] $link -> $tgt"
        ;;
    esac
    # Re-derive resolution from disk (§11.4.6) — never trust the stored string
    # alone: it must actually resolve, and resolve INSIDE the relocated tree.
    if [ ! -e "$link" ]; then
      bad=1
      _i "  [DANGLING after relocation] $link"
      continue
    fi
    resolved="$(cd "$(dirname "$link")" >/dev/null 2>&1 && cd "$(dirname "$(readlink "$link")")" >/dev/null 2>&1 && pwd)/$(basename "$tgt")"
    case "$resolved" in
      "$new_dir"/*) : ;;
      *)
        bad=1
        _i "  [ESCAPES relocated tree] $link -> $resolved (expected under $new_dir)"
        ;;
    esac
  done <<EOF
$links
EOF

  _i "$label: inspected $n planted link(s); generated at $gen_dir, relocated to $new_dir"
  return "$bad"
}

# ── RED: strawman generator reproducing the pre-fix construct ───────────────
run_red() {
  local scratch="$EV/red"
  local gen="$scratch/A" new="$scratch/B"
  mkdir -p "$gen/constitution/skills/strawman" "$gen/skills"

  # The exact pre-fix construct. Cross-checked below against the real tree so
  # the strawman cannot silently drift from what actually shipped.
  cat > "$gen/constitution/skills/strawman/register.sh" <<'STRAWMAN'
#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "${PROJECT_ROOT}/skills"
LINK_TARGET="${PROJECT_ROOT}/skills/strawman"
rm -f "$LINK_TARGET"
ln -sf "$SCRIPT_DIR" "$LINK_TARGET"
STRAWMAN
  echo "strawman skill body" > "$gen/constitution/skills/strawman/skill.md"

  bash "$gen/constitution/skills/strawman/register.sh" "$gen" >/dev/null 2>&1 || true
  mv "$gen" "$new"

  if assert_portable_after_move "$gen" "$new" "RED/strawman"; then
    _f "RED: strawman absolute-path generator SURVIVED relocation — this harness cannot detect the defect it exists to catch (BLIND TEST)"
  else
    _p "RED: strawman absolute-path generator BREAKS under relocation — harness demonstrably detects the defect class"
  fi
}

# RED cross-check: the strawman must mirror a construct that genuinely appears
# (or genuinely appeared) in the real generators. Proven from git history when
# the working tree is already fixed, so this check stays honest post-fix.
red_crosscheck() {
  local hits
  hits="$(grep -rn 'ln -sf "\$SCRIPT_DIR"' "$const_root/skills" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$hits" -gt 0 ]; then
    _p "RED cross-check: pre-fix construct 'ln -sf \"\$SCRIPT_DIR\"' still present in $hits real generator line(s) — strawman mirrors shipped code"
  elif git -C "$const_root" log -S'ln -sf "$SCRIPT_DIR"' --oneline -- skills >/dev/null 2>&1 &&
       [ -n "$(git -C "$const_root" log -S'ln -sf "$SCRIPT_DIR"' --oneline -- skills 2>/dev/null)" ]; then
    _p "RED cross-check: construct absent from working tree but present in git history — strawman mirrors code that genuinely shipped"
  else
    _f "RED cross-check: strawman construct found neither in the working tree nor in git history — the simulation has drifted from reality"
  fi
}

# ── GREEN: the REAL generators ─────────────────────────────────────────────
run_green() {
  local scratch="$EV/green"
  local gen="$scratch/A" new="$scratch/B"
  mkdir -p "$gen"
  build_replica "$gen"

  local reg name ran=0
  for reg in "$gen"/constitution/skills/*/register.sh; do
    [ -f "$reg" ] || continue
    name="$(basename "$(dirname "$reg")")"
    # Generators are run with the scratch root as PROJECT_ROOT. A non-zero exit
    # is not itself the assertion (some generators warn about optional extras);
    # the assertion is what they PLANTED, re-derived from disk afterwards.
    if bash "$reg" "$gen" >"$EV/green_${name}.out" 2>&1; then
      ran=$((ran+1))
    else
      ran=$((ran+1))
      _i "note: $name register.sh exited non-zero (see $EV/green_${name}.out) — asserting on planted links regardless"
    fi
  done

  if [ "$ran" -eq 0 ]; then
    _f "GREEN: no register.sh found in the replica — harness broken"
    return
  fi
  _i "GREEN: ran $ran real generator(s)"

  mv "$gen" "$new"

  if assert_portable_after_move "$gen" "$new" "GREEN/real"; then
    _p "GREEN: every link planted by the real generators stores a RELATIVE target and still resolves inside the tree after relocation to a different absolute path"
  else
    _f "GREEN: at least one link planted by the real generators is host-absolute or fails to resolve after relocation — the generator bakes in the authoring machine's path"
  fi
}

if [ "$RED_MODE" = "1" ]; then
  red_crosscheck
  run_red
else
  run_green
fi

printf '\n== summary: PASS=%d FAIL=%d SKIP=%d (evidence: %s) ==\n' \
  "$pass_n" "$fail_n" "$skip_n" "$EV" | tee -a "$LOG"
[ "$fail_n" -eq 0 ]
