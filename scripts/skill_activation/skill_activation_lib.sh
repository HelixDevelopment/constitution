#!/usr/bin/env bash
# ============================================================================
# skill_activation_lib.sh — dynamic, on-demand Skill/extension activation.
# ============================================================================
# Purpose:
#   Keep the agent's ACTIVE skill surface at the minimum needed right now, so
#   the per-turn token cost of the available-skills list stays small, while
#   every other skill remains DISCOVERABLE and one command away.
#
#   Measured motivation (this host, 2026-09-07, claude 2.1.263): a pool of 955
#   skills renders as ~29 KB (~7.3K tokens) of skill names in EVERY turn's
#   system prompt. A description-eager render of the same pool would be
#   ~423 KB (~106K tokens/turn) — a 14x cliff that an upstream change could
#   introduce with no gate watching. See skill_budget_gate.sh.
#
# Platform facts this design is built on (PROVEN first-hand, not assumed —
# evidence: docs/qa/skill_activation_20260907/probe_activation.md):
#   * ACTIVATION HOT-LOADS. Creating <project>/.claude/skills/<name>/SKILL.md
#     makes the skill appear in the ALREADY-RUNNING session's available-skills
#     list with no restart.
#   * DEACTIVATION DOES **NOT** HOT-UNLOAD. After deleting the directory, the
#     same session still invoked the skill successfully from cache.
#   => The saving is a MINIMAL SESSION-START BASELINE plus on-demand growth.
#      Deactivation takes effect at the NEXT session start. Claiming that
#      deactivation frees tokens in the live session would be a bluff.
#
# Design constraints:
#   * PROJECT-AGNOSTIC (§11.4.28 / CONST-051(B)). Knows no project name, no
#     layout, no skill names. The consumer supplies its manifest as DATA.
#   * INHERITED BY REFERENCE, never copied into a consumer (§11.4.80/§11.4.177).
#   * FAIL SAFE, NEVER SILENT (§11.4.201). A failed activation prints an
#     explicit failure and exits non-zero, so the agent is TOLD the skill is
#     unavailable instead of assuming it is present.
#   * DISCOVERABILITY PRESERVED. `list` always shows the whole catalogue, so a
#     deactivated skill is never unfindable (superpowers:using-superpowers /
#     §11.4.102(B) must keep working).
#   * CONCURRENCY SAFE. Several agent aliases share one checkout; one session's
#     deactivation MUST NOT strip a skill another session is using (§11.4.119 /
#     §11.4.176). Reference-counted claims with PROVEN liveness (§11.4.180).
#   * IDEMPOTENT. Re-running changes nothing.
#
# Cross-references:
#   §11.4.141 (token efficiency), §11.4.28, §11.4.35, §11.4.74, §11.4.80,
#   §11.4.102(B), §11.4.119, §11.4.164, §11.4.174, §11.4.176, §11.4.177,
#   §11.4.180, §11.4.201, §11.4.6.
# ============================================================================
set -uo pipefail

SA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SA_CONST_DIR="$(cd "$SA_LIB_DIR/../.." && pwd)"

# --- portable relative symlinks (reuse, never reimplement — §11.4.74) -------
if [ -r "$SA_CONST_DIR/scripts/portable_symlink_lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$SA_CONST_DIR/scripts/portable_symlink_lib.sh" 2>/dev/null || true
fi

sa_die()  { printf 'SKILL-ACTIVATION-FAILED: %s\n' "$*" >&2; return 1; }
sa_warn() { printf 'skill-activation: WARN: %s\n' "$*" >&2; }
sa_info() { printf 'skill-activation: %s\n' "$*"; }

# ---------------------------------------------------------------------------
# sa_project_root [dir] — consuming project root (default: $PWD).
# ---------------------------------------------------------------------------
sa_project_root() { ( cd "${1:-$PWD}" 2>/dev/null && pwd ) || printf '%s\n' "${1:-$PWD}"; }

# ---------------------------------------------------------------------------
# sa_active_dir <project_root> — the native project-scoped discovery path.
# This is the ONE directory whose membership decides the agent's live surface.
# ---------------------------------------------------------------------------
sa_active_dir() { printf '%s/.claude/skills\n' "$1"; }

# ---------------------------------------------------------------------------
# sa_state_dir <project_root> — claims + ledger. Host-local, never versioned.
# ---------------------------------------------------------------------------
sa_state_dir() { printf '%s/.claude/.skill-activation\n' "$1"; }

# ---------------------------------------------------------------------------
# sa_session_id — identity of the CLAIMING session.
#   Defaults to the agent config-dir basename, which is exactly what separates
#   one concurrent alias from another on this host (claude1..claude5, prov-*).
#   Honest bound (§11.4.6): two sessions sharing ONE config dir share ONE
#   claim identity; they are counted as one claimant. Override with
#   HELIX_SKILL_SESSION to make them distinct.
# ---------------------------------------------------------------------------
# sa_session_cfgdir — the session's real config dir (liveness key).
sa_session_cfgdir() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-}"; }

# sa_session_id — SANITIZED claim FILENAME.
#   Forensic (found by this engine's own paired test): config-dir basenames
#   start with a dot (".claude-claude5"), so a claim written under that name was
#   INVISIBLE to the `for f in "$dir"/*` reader -- claims were written and never
#   read, and reference counting silently never blocked anything while
#   reporting itself as concurrency-safe. That is exactly the §11.4.201
#   false-null this engine exists to avoid, so the id is now dot-stripped and
#   the readers additionally enable dotglob for any legacy claim files.
sa_session_id() {
  local raw
  if [ -n "${HELIX_SKILL_SESSION:-}" ]; then raw="$HELIX_SKILL_SESSION"
  elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then raw="$(basename "$CLAUDE_CONFIG_DIR")"
  else raw="default"; fi
  raw="${raw#.}"; printf '%s\n' "${raw//\//_}"
}

# ---------------------------------------------------------------------------
# sa_session_alive <session_id> — PROVE liveness, never assume it (§11.4.6).
#   A session is alive if a process exists whose environment names that config
#   dir AND which is genuinely ours (§11.4.174 — no loose name matching; we
#   read /proc/<pid>/environ, not a pgrep pattern that could match another
#   project's process or this very check).
#   Honest fallback where /proc is absent (macOS): TTL-based staleness only,
#   reported as such by the caller.
# ---------------------------------------------------------------------------
# sa_session_alive <config_dir> — PROVE a session is live from its config dir.
sa_session_alive() {
  local cfg="$1" self=$$
  [ -n "$cfg" ] || return 2
  [ -d /proc ] || return 2   # 2 = cannot determine (caller falls back to TTL)
  local pid
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    [ "$pid" = "$self" ] && continue
    # Unreadable environ (another user / hardened proc) is NOT evidence of
    # death -- we simply cannot see it. Same-user agent processes are always
    # readable here, so this is a bounded, stated limitation (§11.4.6), and the
    # 2>/dev/null keeps a permission-denied from polluting the caller's stderr.
    [ -r "/proc/$pid/environ" ] || continue
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
         | grep -qx "CLAUDE_CONFIG_DIR=${cfg}" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# sa_parse_manifest <manifest> <section> — emit the items of one list section.
#   Deliberately a tiny, dependency-free parser over the flat subset we
#   specify (no yq/python required, so the engine works on a bare host).
# ---------------------------------------------------------------------------
sa_parse_manifest() {
  local file="$1" section="$2"
  [ -r "$file" ] || return 0
  awk -v sec="$section" '
    /^[[:space:]]*#/ { next }
    /^[a-zA-Z_]+:[[:space:]]*$/ { in_s = ($0 ~ "^" sec ":") ? 1 : 0; next }
    /^[a-zA-Z_]+:/ { in_s = 0; next }
    in_s && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, "")
      if (length($0)) print
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# sa_manifest_path <project_root> — consumer manifest, with a shipped default.
# ---------------------------------------------------------------------------
sa_manifest_path() {
  local root="$1"
  if [ -n "${HELIX_SKILL_MANIFEST:-}" ] && [ -r "${HELIX_SKILL_MANIFEST}" ]; then
    printf '%s\n' "$HELIX_SKILL_MANIFEST"; return
  fi
  if [ -r "$root/.helix/skill-manifest.yaml" ]; then
    printf '%s\n' "$root/.helix/skill-manifest.yaml"; return
  fi
  printf '%s\n' "$SA_LIB_DIR/skill-manifest.default.yaml"
}

# ---------------------------------------------------------------------------
# sa_manifest_scalar <manifest> <key> — read one top-level scalar `key: value`.
#   Companion to sa_parse_manifest (which reads LIST sections). The two do not
#   collide: sa_parse_manifest treats any `key:` line with a value as a
#   section-ender, so a scalar never leaks into a list.
# ---------------------------------------------------------------------------
sa_manifest_scalar() {
  local file="$1" key="$2"
  [ -r "$file" ] || return 0
  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    $0 ~ ("^" k ":[[:space:]]*") {
      sub("^" k ":[[:space:]]*", ""); sub(/[[:space:]]*(#.*)?$/, "")
      if (length($0)) { print; exit }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# sa_attic_dir <project_root> — the DEMOTION target for pruning.
# ---------------------------------------------------------------------------
# WHY AN ATTIC EXISTS AT ALL (this is the §11.4.122 argument in code form):
#
#   Pruning must never DELETE anything. The active dir can hold two kinds of
#   entry:
#     * a SYMLINK the engine created -- removing the link destroys nothing,
#       the pool source it points at is untouched.
#     * a REAL DIRECTORY that predates the engine (a project dropped its skill
#       straight into .claude/skills/). On this project those are UNTRACKED
#       (.claude/* is gitignored) and single-copy: `rm -rf` would be permanent,
#       unrecoverable loss -- a genuine §11.4.122 removal AND a §9.2
#       data-safety violation.
#
#   So a real directory is MOVED here, never removed. The attic is itself a
#   pool source (see sa_pool_dirs), so a demoted skill remains LISTED by
#   `skill_activate.sh list` and ACTIVATABLE by `activate <name>` -- content
#   preserved byte-for-byte, one command away.
#
#   It lives under the host-local state dir, which is already inside
#   `.claude/` and therefore gitignored exactly where the content already was:
#   demotion changes NOTHING about the file's version-control status
#   (§11.4.30 hygiene preserved -- no git-status noise, no accidental tracking).
# ---------------------------------------------------------------------------
sa_attic_dir() { printf '%s/pool\n' "$(sa_state_dir "$1")"; }

# ---------------------------------------------------------------------------
# sa_absolutize_relative_links <dir> — make <dir> RELOCATION-SAFE in place.
# ---------------------------------------------------------------------------
# Forensic (found by the first live prune run, 2026-09-07): several skill
# directories in .claude/skills/ are not plain content — they contain a
# `SKILL.md` that is itself a RELATIVE symlink reaching several levels up
# (`../../../.specify/.../SKILL.md`). Moving such a directory to the attic
# changes its depth, so every relative link inside it dangles at the new
# location and the skill becomes unreadable. The prune guard caught that and
# reverted the move (correct, and proven live) -- but the right outcome is for
# the demotion to SUCCEED, not to be permanently refused.
#
# So before relocating a directory, every RELATIVE symlink inside it is
# re-pointed at the ABSOLUTE path it currently resolves to. This is
# semantics-preserving: the link resolves to the exact same file before and
# after, only its stored text changes. Absolute links survive relocation by
# construction. Links that are already absolute, and links whose target does
# not currently resolve, are left untouched (never invent a target -- §11.4.6).
#
# Honest boundary (§11.4.6): this makes the directory relocation-safe for
# SYMLINKS. A directory whose content depends on its own path in some other
# way (a relative path baked into a file's TEXT) is not repaired by this, and
# the caller's post-move readability check remains the backstop that refuses
# and reverts rather than leaving a broken skill behind.
# ---------------------------------------------------------------------------
sa_absolutize_relative_links() {
  local dir="$1" l raw abs
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' l; do
    raw="$(readlink "$l" 2>/dev/null)" || continue
    case "$raw" in /*) continue ;; esac          # already absolute -> safe
    abs="$(readlink -f "$l" 2>/dev/null)" || continue
    [ -n "$abs" ] && [ -e "$abs" ] && ln -sfn "$abs" "$l"
  done < <(find "$dir" -type l -print0 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# sa_pool_dirs <project_root> — where skill definitions may be found.
#   Sources come from the manifest; ~ and $VARS are expanded; missing dirs are
#   skipped with a WARN (never a silent drop — §11.4.201). The attic is
#   appended last (lowest precedence) and only when it exists, so a demoted
#   skill stays discoverable + activatable without warning when absent.
# ---------------------------------------------------------------------------
sa_pool_dirs() {
  local root="$1" mf; mf="$(sa_manifest_path "$root")"
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    d="${d/#\~/$HOME}"
    case "$d" in /*) : ;; *) d="$root/$d" ;; esac
    if [ -d "$d" ]; then printf '%s\n' "$d"; else sa_warn "source not found, skipped: $d"; fi
  done < <(sa_parse_manifest "$mf" sources)
  local attic; attic="$(sa_attic_dir "$root")"
  [ -d "$attic" ] && printf '%s\n' "$attic"
  return 0
}

# ---------------------------------------------------------------------------
# sa_is_core <project_root> <name> — is this skill declared core?
# ---------------------------------------------------------------------------
sa_is_core() {
  local root="$1" name="$2" mf c
  mf="$(sa_manifest_path "$root")"
  while IFS= read -r c; do [ "$c" = "$name" ] && return 0; done < <(sa_parse_manifest "$mf" core)
  return 1
}

# ---------------------------------------------------------------------------
# sa_prune_enabled <project_root> — is prune-to-core the active policy?
# ---------------------------------------------------------------------------
#   DEFAULT: ON (operator decision 2026-09-07 — "token use is ALWAYS at the
#   minimum", "we MUST use actively only Skills we need at particular moment").
#
#   OPT-OUT, two levels, env wins over manifest (env is the per-SESSION
#   override, the manifest is the per-PROJECT policy):
#     HELIX_SKILL_PRUNE=0|false|no|off   -> pruning disabled for this session
#     HELIX_SKILL_PRUNE=1|true|yes|on    -> pruning forced on for this session
#     manifest `prune: false`            -> pruning disabled for this project
#
#   The escape hatch is deliberate: a mechanism with no way out gets worked
#   around destructively (someone deletes the engine, or stops running
#   session-init at all, and the surface silently grows back with no gate
#   watching it). An explicit, documented opt-out keeps the engine in play.
# ---------------------------------------------------------------------------
sa_prune_enabled() {
  local root="$1" v
  if [ -n "${HELIX_SKILL_PRUNE:-}" ]; then
    case "${HELIX_SKILL_PRUNE,,}" in 0|false|no|off) return 1 ;; *) return 0 ;; esac
  fi
  v="$(sa_manifest_scalar "$(sa_manifest_path "$root")" prune)"
  case "${v,,}" in 0|false|no|off) return 1 ;; *) return 0 ;; esac
}

# ---------------------------------------------------------------------------
# sa_find_skill <project_root> <name> — resolve a skill name to its pool dir.
# ---------------------------------------------------------------------------
sa_find_skill() {
  local root="$1" name="$2" d
  while IFS= read -r d; do
    if [ -f "$d/$name/SKILL.md" ]; then printf '%s\n' "$d/$name"; return 0; fi
  done < <(sa_pool_dirs "$root")
  return 1
}

# ---------------------------------------------------------------------------
# sa_is_active <project_root> <name>
# ---------------------------------------------------------------------------
sa_is_active() { [ -e "$(sa_active_dir "$1")/$2/SKILL.md" ]; }

# ---------------------------------------------------------------------------
# sa_claim / sa_unclaim / sa_live_claimants — reference counting.
# ---------------------------------------------------------------------------
sa_claim() {
  local root="$1" name="$2" sid; sid="$(sa_session_id)"
  local cd; cd="$(sa_state_dir "$root")/claims/$name"
  mkdir -p "$cd" || return 1
  # line 1 = config dir (the liveness key), line 2 = claim time.
  printf '%s\n%s\n' "$(sa_session_cfgdir)" "$(date -u +%FT%TZ)" > "$cd/$sid"
}
sa_unclaim() {
  local root="$1" name="$2" sid; sid="$(sa_session_id)"
  rm -f "$(sa_state_dir "$root")/claims/$name/$sid" 2>/dev/null || true
}
# Emits the session ids that still hold a PROVEN-live claim, excluding us.
sa_live_claimants() {
  local root="$1" name="$2" me; me="$(sa_session_id)"
  local cd; cd="$(sa_state_dir "$root")/claims/$name"
  [ -d "$cd" ] || return 0
  local f sid cfg
  shopt -s nullglob dotglob 2>/dev/null || true
  for f in "$cd"/*; do
    [ -e "$f" ] || continue
    sid="$(basename "$f")"
    [ "$sid" = "$me" ] && continue
    cfg="$(head -1 "$f" 2>/dev/null)"
    if sa_session_alive "$cfg"; then
      printf '%s\n' "$sid"
    else
      case $? in
        1) rm -f "$f" ;;                      # proven dead -> reap (§11.4.180)
        2) printf '%s(liveness-unknown)\n' "$sid" ;;   # honest: cannot prove
      esac
    fi
  done
}
