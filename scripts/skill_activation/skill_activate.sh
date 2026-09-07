#!/usr/bin/env bash
# ============================================================================
# skill_activate.sh — the operator/agent CLI for dynamic skill activation.
# ============================================================================
# Usage:
#   skill_activate.sh list            [PROJECT_ROOT]   # full catalogue (always)
#   skill_activate.sh status          [PROJECT_ROOT]   # active set + byte budget
#   skill_activate.sh activate  NAME  [PROJECT_ROOT]   # hot-load one skill NOW
#   skill_activate.sh deactivate NAME [PROJECT_ROOT]   # release; unlink if unclaimed
#   skill_activate.sh prune           [PROJECT_ROOT]   # demote non-core to attic
#   skill_activate.sh session-init    [PROJECT_ROOT]   # prune + apply baseline
#   skill_activate.sh gc              [PROJECT_ROOT]   # reap dead claims
#
# Honest boundary (§11.4.6): ACTIVATION takes effect in the RUNNING session
# (proven). DEACTIVATION/PRUNE takes effect at the NEXT session start (proven)
# — it unlinks or demotes the skill so the next session does not pay for it;
# it does NOT shrink the current session's cached surface.
#
# PRUNE IS THE DEFAULT in session-init (operator decision 2026-09-07). It
# DELETES NOTHING — see the `prune` case body for the full §11.4.122 argument.
# Opt out with HELIX_SKILL_PRUNE=0 (session) or `prune: false` (manifest).
#
# Exit codes: 0 success · 1 failure (always with an explicit reason on stderr).
# ============================================================================
set -uo pipefail
SA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SA_DIR/skill_activation_lib.sh"

cmd="${1:-list}"; shift || true

case "$cmd" in
  activate|deactivate)
    name="${1:-}"; root="$(sa_project_root "${2:-$PWD}")"
    [ -n "$name" ] || { sa_die "usage: skill_activate.sh $cmd NAME [PROJECT_ROOT]"; exit 1; }
    ;;
  *) root="$(sa_project_root "${1:-$PWD}")" ;;
esac

mf="$(sa_manifest_path "$root")"
adir="$(sa_active_dir "$root")"

case "$cmd" in

  # -- ACTIVATE ------------------------------------------------------------
  activate)
    src="$(sa_find_skill "$root" "$name")" || {
      sa_die "'$name' is not in any configured skill source. Run 'skill_activate.sh list' to see the catalogue."; exit 1; }
    mkdir -p "$adir" || { sa_die "cannot create $adir"; exit 1; }
    link="$adir/$name"
    if [ -e "$link" ] || [ -L "$link" ]; then
      sa_claim "$root" "$name"
      sa_info "already active: $name (claim recorded for $(sa_session_id))"; exit 0
    fi
    # relocation-proof relative link where the shared library is available
    # hc_ln_relative stores a target RELATIVE to the link's own directory, so the
    # link keeps resolving in every checkout on every host (§11.4.177). Falling
    # back to a raw relative $src would create a link that resolves against
    # .claude/skills/ and therefore dangles -- the exact defect the fail-safe
    # check below catches, so the fallback uses an ABSOLUTE target instead.
    if command -v hc_ln_relative >/dev/null 2>&1; then
      hc_ln_relative "$src" "$link" >/dev/null 2>&1 || ln -sfn "$(cd "$src" && pwd)" "$link"
    else
      ln -sfn "$(cd "$src" && pwd)" "$link"
    fi
    # FAIL SAFE, NEVER SILENT (§11.4.201): prove the skill is really readable.
    if [ ! -r "$link/SKILL.md" ]; then
      rm -f "$link" 2>/dev/null || true
      sa_die "'$name' could not be activated (link created but SKILL.md unreadable at $link). The skill is NOT available — do not assume it is loaded."
      exit 1
    fi
    sa_claim "$root" "$name"
    sa_info "ACTIVATED: $name -> $src"
    sa_info "It is live in the running session now (activation hot-loads)."
    exit 0
    ;;

  # -- DEACTIVATE ----------------------------------------------------------
  deactivate)
    link="$adir/$name"
    core_hit=0
    sa_is_core "$root" "$name" && core_hit=1
    if [ "$core_hit" = "1" ]; then
      sa_die "'$name' is declared CORE in $mf — refusing to deactivate. Edit the manifest if this is intended."; exit 1
    fi
    sa_unclaim "$root" "$name"
    others="$(sa_live_claimants "$root" "$name")"
    if [ -n "$others" ]; then
      sa_info "KEPT ACTIVE: $name — still claimed by another live session: $(echo "$others" | tr '\n' ' ')"
      sa_info "(concurrency safety: one session never strips a skill another is using)"
      exit 0
    fi
    if [ -e "$link" ] || [ -L "$link" ]; then
      rm -rf "$link" && sa_info "DEACTIVATED: $name (unlinked)"
    else
      sa_info "not active: $name (nothing to unlink)"
    fi
    sa_info "NOTE: the current session keeps its cached copy; this takes effect at the NEXT session start."
    exit 0
    ;;

  # -- LIST (discoverability is never lost) --------------------------------
  list)
    echo "# Skill catalogue — manifest: $mf"
    echo "# legend: [*] active now   [ ] available, activate on demand"
    echo
    declare -A seen=()
    echo "## core (always active)"
    while IFS= read -r n; do
      [ -n "$n" ] || continue; seen[$n]=1
      if sa_is_active "$root" "$n"; then printf '  [*] %s\n' "$n"; else printf '  [!] %s  (declared core but NOT active — run session-init)\n' "$n"; fi
    done < <(sa_parse_manifest "$mf" core)
    echo
    echo "## on-demand (activate with: skill_activate.sh activate NAME)"
    while IFS= read -r d; do
      [ -d "$d" ] || continue
      for p in "$d"/*/SKILL.md; do
        [ -e "$p" ] || continue
        n="$(basename "$(dirname "$p")")"
        [ -n "${seen[$n]:-}" ] && continue
        seen[$n]=1
        if sa_is_active "$root" "$n"; then printf '  [*] %s\n' "$n"; else printf '  [ ] %s\n' "$n"; fi
      done
    done < <(sa_pool_dirs "$root")
    exit 0
    ;;

  # -- STATUS + BYTE BUDGET ------------------------------------------------
  status)
    n_active=0; b_name=0; b_desc=0
    if [ -d "$adir" ]; then
      for p in "$adir"/*/SKILL.md; do
        [ -e "$p" ] || continue
        nm="$(basename "$(dirname "$p")")"
        n_active=$((n_active+1))
        b_name=$((b_name + ${#nm} + 3))
        d="$(awk -F': *' '/^description:/{sub(/^description: */,"");print;exit}' "$p" 2>/dev/null)"
        b_desc=$((b_desc + ${#nm} + ${#d} + 5))
      done
    fi
    pool=0
    while IFS= read -r dd; do
      [ -d "$dd" ] || continue
      c=$(ls -1 "$dd" 2>/dev/null | wc -l); pool=$((pool+c))
    done < <(sa_pool_dirs "$root")
    echo "manifest        : $mf"
    echo "active dir      : $adir"
    echo "session id      : $(sa_session_id)"
    echo "pool skills     : $pool"
    echo "ACTIVE skills   : $n_active"
    echo "render bytes    : name-only=${b_name}  name+description=${b_desc}"
    echo "approx tokens   : name-only=$((b_name/4))  name+description=$((b_desc/4))"
    exit 0
    ;;

  # -- PRUNE ---------------------------------------------------------------
  # Demote every non-core active skill so the session pays only for `core`.
  #
  # WHY THIS IS NOT A §11.4.122 SILENT REMOVAL — the reasoning is load-bearing,
  # do NOT "fix" this back out on §11.4.122 grounds without re-reading it:
  #
  #   §11.4.122 forbids removing an end-user CAPABILITY without asking. Pruning
  #   removes no capability, because all three properties that make it
  #   reversible and visible are preserved BY CONSTRUCTION:
  #     1. LISTED    — `skill-catalog` is always-core, so every pruned skill
  #                    stays in `skill_activate.sh list` output. Nothing
  #                    becomes unfindable (§11.4.102(B) keeps binding).
  #     2. ACTIVATABLE — `skill_activate.sh activate <name>` brings it back,
  #                    hot-loading into the RUNNING session (proven behaviour).
  #     3. NOT DELETED — a symlink loses only the LINK (its target is
  #                    untouched); a real directory is MOVED to the attic
  #                    (sa_attic_dir), never removed. Zero bytes are destroyed.
  #
  #   A pruned skill is DORMANT AND ONE COMMAND AWAY, not gone. That is
  #   materially different from dropping a component from a build — which is
  #   what §11.4.122 exists to prevent.
  #
  # Refusals are LOUD, never silent (§11.4.201): a skill that cannot be pruned
  # safely stays ACTIVE and says why.
  prune)
    if ! sa_prune_enabled "$root"; then
      sa_info "prune DISABLED (HELIX_SKILL_PRUNE / manifest 'prune: false') — active set left untouched."
      exit 0
    fi
    [ -d "$adir" ] || { sa_info "nothing active to prune"; exit 0; }
    attic="$(sa_attic_dir "$root")"
    pruned=0; kept=0; skipped=0
    shopt -s nullglob
    for e in "$adir"/*; do
      n="$(basename "$e")"
      # 1. core is never pruned
      if sa_is_core "$root" "$n"; then continue; fi
      # 2. CROSS-TRACK SAFETY (§11.4.119/§11.4.176): release OUR claim, then ask
      #    whether any OTHER live session still holds one. If so, KEEP — one
      #    session never strips a skill another session is using.
      sa_unclaim "$root" "$n"
      others="$(sa_live_claimants "$root" "$n")"
      if [ -n "$others" ]; then
        sa_info "KEPT: $n — claimed by another live session: $(echo "$others" | tr '\n' ' ')"
        sa_claim "$root" "$n"   # restore our claim; we are not pruning it
        kept=$((kept+1)); continue
      fi
      if [ -L "$e" ]; then
        # SYMLINK: removing the link destroys nothing. But it must stay
        # RE-ACTIVATABLE, so if its name resolves in no pool source, plant an
        # attic symlink to the same target FIRST (property 2 above).
        if ! sa_find_skill "$root" "$n" >/dev/null 2>&1; then
          tgt="$(readlink -f "$e" 2>/dev/null || true)"
          if [ -n "$tgt" ] && [ -r "$tgt/SKILL.md" ]; then
            mkdir -p "$attic" && ln -sfn "$tgt" "$attic/$n"
          fi
          if [ ! -r "$attic/$n/SKILL.md" ]; then
            sa_warn "KEPT ACTIVE: $n — not resolvable in any pool source and could not be made re-activatable; refusing to prune (it would become unfindable)."
            sa_claim "$root" "$n"; skipped=$((skipped+1)); continue
          fi
        fi
        rm -f "$e" && { sa_info "PRUNED: $n (link removed; target untouched, still activatable)"; pruned=$((pruned+1)); }
      elif [ -d "$e" ]; then
        # REAL DIRECTORY: MOVE, never remove. This is the only content-safe
        # option — on this project these are untracked and single-copy.
        mkdir -p "$attic" || { sa_warn "KEPT ACTIVE: $n — cannot create attic $attic"; sa_claim "$root" "$n"; skipped=$((skipped+1)); continue; }
        if [ -e "$attic/$n" ]; then
          sa_warn "KEPT ACTIVE: $n — attic already holds an entry of that name; refusing to overwrite it (§9.2 — never clobber preserved content)."
          sa_claim "$root" "$n"; skipped=$((skipped+1)); continue
        fi
        # Relocation-safety FIRST: a skill dir may hold RELATIVE symlinks that
        # would dangle at the attic's different depth (found live 2026-09-07).
        # Re-point them at their current absolute target — same file, new text.
        sa_absolutize_relative_links "$e"
        if mv "$e" "$attic/$n" 2>/dev/null && [ -r "$attic/$n/SKILL.md" ]; then
          sa_info "PRUNED: $n (moved to attic; content preserved, still listed + activatable)"
          pruned=$((pruned+1))
        else
          # move failed or landed unreadable -> put it back, keep it active.
          [ -e "$attic/$n" ] && [ ! -e "$e" ] && mv "$attic/$n" "$e" 2>/dev/null
          sa_warn "KEPT ACTIVE: $n — demotion to attic failed; the skill is UNCHANGED and still active."
          sa_claim "$root" "$n"; skipped=$((skipped+1))
        fi
      else
        sa_warn "KEPT ACTIVE: $n — not a skill directory or symlink; left alone."
        skipped=$((skipped+1))
      fi
    done
    sa_info "prune complete: pruned=$pruned kept-for-other-session=$kept refused=$skipped"
    sa_info "Every pruned skill is still listed by 'skill_activate.sh list' and returns with 'activate <name>'. Nothing was deleted."
    exit 0
    ;;

  # -- SESSION INIT --------------------------------------------------------
  session-init)
    mkdir -p "$adir"
    rc=0
    # PRUNE FIRST, then raise core. Order matters: prune only ever demotes
    # NON-core skills, and raising core afterwards guarantees the session ends
    # with exactly the declared core set active even if a core skill was
    # somehow inactive going in.
    "$SA_DIR/skill_activate.sh" prune "$root" || rc=1
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      "$SA_DIR/skill_activate.sh" activate "$n" "$root" >/dev/null || { sa_warn "core skill '$n' FAILED to activate — it is NOT available"; rc=1; }
    done < <(sa_parse_manifest "$mf" core)
    "$SA_DIR/skill_activate.sh" gc "$root" >/dev/null 2>&1 || true
    "$SA_DIR/skill_activate.sh" status "$root"
    exit $rc
    ;;

  # -- GC ------------------------------------------------------------------
  gc)
    cdir="$(sa_state_dir "$root")/claims"
    [ -d "$cdir" ] || { sa_info "no claims"; exit 0; }
    reaped=0
    for nd in "$cdir"/*; do
      [ -d "$nd" ] || continue
      sa_live_claimants "$root" "$(basename "$nd")" >/dev/null
      rmdir "$nd" 2>/dev/null && reaped=$((reaped+1))
    done
    sa_info "gc complete (empty claim dirs removed: $reaped)"
    exit 0
    ;;

  *) sa_die "unknown command '$cmd'"; exit 1 ;;
esac
