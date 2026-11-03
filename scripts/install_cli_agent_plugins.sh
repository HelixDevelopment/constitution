#!/usr/bin/env bash
# scripts/install_cli_agent_plugins.sh
#
# ── Purpose ──────────────────────────────────────────────────────────────────
#   The ONE idempotent seam that makes the constitution's CLI-agent plugins AND
#   skills load out-of-the-box in a consuming project (§11.4.140 / §11.4.164 /
#   §11.4.75):
#
#     1. REGENERATE every registered action's slash command for every supported
#        agent (Claude Code plugin `helix`, Gemini CLI, Qwen Code, Codex CLI)
#        from actions/registry.yaml — so a newly-registered directive is live.
#     2. LINK every constitution skill into <project>/.claude/skills/<name>, the
#        native project-scoped Agent-Skills discovery path (BY REFERENCE — a
#        symlink, NEVER a copy, per §11.4.28 / §11.4.80 / §11.4.177).
#     3. REGISTER the local marketplace + INSTALL the `helix` plugin via the
#        non-interactive `claude plugin` CLI when it is available; when it is
#        NOT, print the EXACT one-time commands rather than claiming success
#        (§11.4.6 — never assume an install happened).
#
#   Re-running is safe and idempotent. It is invoked automatically on every
#   constitution pull by scripts/post_update_hook.sh (§11.4.164).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash <constitution>/scripts/install_cli_agent_plugins.sh [PROJECT_ROOT | --project-root DIR] [OPTS]
#     (<constitution> is submodules/constitution (standard) or constitution (legacy))
#     PROJECT_ROOT   consuming project root. Chosen in this order: the explicit
#                    argument (positional or --project-root DIR); else the OWNER
#                    of this checkout (its git superproject / the work tree
#                    holding a vendored copy; an ambient $PROJECT_ROOT or cwd
#                    naming another directory is ignored with a WARN); only a
#                    STANDALONE checkout (no owner) uses $PROJECT_ROOT, else $PWD
#     --skills-only  only link skills (skip generation + plugin install)
#     --skill NAME   link just this one skill (implies --skills-only)
#     --no-plugin    skip the marketplace/plugin install step
#     --check        report state, change nothing (exit 0 = fully wired)
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   $HELIX_ACTION_REGISTRY  optional registry override (forwarded to generator)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   <project>/.claude/skills/<name>       symlink per constitution skill
#   plugins/helix/commands/*.md           regenerated Claude Code commands
#   actions/generated/<agent>/*           regenerated per-agent commands
#   stdout: one line per action; a WIRED / NOT-WIRED verdict.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates <project>/.claude/skills/. Registers a marketplace + installs the
#   `helix` plugin in the CURRENT Claude Code config dir (honours
#   $CLAUDE_CONFIG_DIR). Never writes outside the project + the agent config.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, ln; `claude` CLI (optional — absence is reported honestly, not faked);
#   scripts/generate_agent_prefix_commands.sh.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.140 (action-prefix system), §11.4.164 (post-update auto-propagation),
#   §11.4.75 (mechanical enforcement), §11.4.28 / §11.4.177 (decoupling — the
#   constitution is inherited BY REFERENCE, never copied into the project),
#   §11.4.6 (no-guessing — an unavailable installer is reported, never assumed).
#
# Classification: universal (§11.4.17)
# Last verified: 2026-07-15

set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
const_root="$(cd "$self_dir/.." >/dev/null 2>&1 && pwd)"

# Relocation-proof symlink creation (§11.4.111): every link planted in the
# consuming project MUST store a target RELATIVE to the link itself. An
# absolute target bakes in the installing machine's path and resolves nowhere
# else — the exact defect that shipped a /Volumes/T7/... link into a Linux
# checkout where it had never once resolved.
. "$self_dir/portable_symlink_lib.sh"

project_root=""
skills_only=0
one_skill=""
do_plugin=1
check_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skills-only) skills_only=1 ;;
    --skill)       shift; one_skill="${1:-}"; skills_only=1 ;;
    --no-plugin)   do_plugin=0 ;;
    --check)       check_only=1 ;;
    --project-root)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then echo "[install-plugins] --project-root needs a directory" >&2; exit 2; fi
      project_root="$2"; shift ;;
    --project-root=*) project_root="${1#--project-root=}"
      [ -n "$project_root" ] || { echo "[install-plugins] --project-root= needs a directory" >&2; exit 2; } ;;
    -h|--help)     sed -n '3,36p' "$0"; exit 0 ;;
    *)             [ -n "$project_root" ] || project_root="$1" ;;
  esac
  shift || true
done

# Owner rule (round 8, same as setup.sh / post_update_hook.sh): explicit
# argument > the OWNER of this checkout > ($PROJECT_ROOT, $PWD) only when the
# checkout is standalone. An ambient value left for another project never
# redirects the writes (.claude/skills, settings, generated commands).
if [ -f "$self_dir/lib/constitution_layout.sh" ]; then
  # shellcheck source=lib/constitution_layout.sh
  . "$self_dir/lib/constitution_layout.sh"
  cl_scrub_git_env
  if [ -z "$project_root" ]; then
    _owner="$(cl_owner_project_of "$const_root" 2>/dev/null)" || _owner=""
    if [ -n "$_owner" ]; then
      _amb="${PROJECT_ROOT:-$PWD}"
      if [ -n "${PROJECT_ROOT:-}" ] && ! cl_same_dir "$_amb" "$_owner"; then
        printf '[install-plugins] WARN: ignoring the ambient PROJECT_ROOT=%s: this constitution checkout belongs to %s (pass --project-root to choose another project explicitly).\n' "$PROJECT_ROOT" "$_owner" >&2
      fi
      project_root="$_owner"
    fi
  fi
fi
project_root="${project_root:-${PROJECT_ROOT:-$PWD}}"
project_root="$(cd "$project_root" >/dev/null 2>&1 && pwd)" || { echo "[install-plugins] project root does not exist: ${project_root}" >&2; exit 2; }

# ── Ownership / containment helpers (class: never act on a path we cannot prove is ours) ──
# Every ln/rm/mv/unlink in THIS script goes through one of these; the scripts it chains to
# (install_action_prefix.sh: own containment check; generate_agent_prefix_commands.sh: the installer
# runs it with HELIX_ACTION_OUT_ROOT unset (env -u), so it writes only inside the constitution tree;
# the generator itself still honours that variable for tests/dry-runs) are covered separately:
#   ic_dir_inside_project DIR  -> DIR (symlinks resolved, may not exist yet) lies strictly inside the project
#   ic_link_owned LINK SUBDIR  -> LINK is a symlink whose fully-resolved target (dangling allowed) lies under
#                                 THIS constitution tree's SUBDIR (skills, actions/generated)
const_real="$(cd "$const_root" && pwd -P)"
proj_real_global="$(cd "$project_root" && pwd -P)"
ic_dir_inside_project() {
  local r
  r="$(readlink -m -- "$1" 2>/dev/null)" || return 1
  case "$r" in "$proj_real_global"/*) return 0 ;; *) return 1 ;; esac
}
ic_link_owned() {
  local r
  [ -L "$1" ] || return 1
  r="$(readlink -m -- "$1" 2>/dev/null)" || return 1
  case "$r" in "$const_real/$2"/*|"$const_root/$2"/*) return 0 ;; *) return 1 ;; esac
}

MARKETPLACE_NAME="helix-constitution"
PLUGIN_NAME="helix"

ok()   { printf '[install-plugins] %s\n' "$*"; }
warn() { printf '[install-plugins] WARN: %s\n' "$*" >&2; }

# ── 1. Regenerate the per-agent slash commands from the registry ─────────────
regen_commands() {
  local gen="$const_root/scripts/generate_agent_prefix_commands.sh"
  if [ ! -f "$gen" ]; then
    warn "generator missing: $gen — commands NOT regenerated"
    return 1
  fi
  if env -u HELIX_ACTION_OUT_ROOT bash "$gen" >/dev/null 2>&1; then
    local n
    n="$(find "$const_root/plugins/$PLUGIN_NAME/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    ok "regenerated slash commands from registry ($n Claude Code command file(s))"
    return 0
  fi
  warn "generator FAILED — commands may be stale"
  return 1
}

# ── 2. Link constitution skills into the project's native skills dir ─────────
# BY REFERENCE (symlink), never a copy: a copy diverges silently (§11.4.80).
link_skills() {
  local skills_src="$const_root/skills"
  local skills_dst="$project_root/.claude/skills"
  [ -d "$skills_src" ] || { warn "no skills dir at $skills_src"; return 1; }
  # The project's .claude (and .claude/skills) must really live inside the project: a symlinked
  # .claude pointing elsewhere would make us write outside it. Refuse, honestly.
  local proj_real claude_real
  proj_real="$(cd "$project_root" && pwd -P)"
  if [ -L "$project_root/.claude" ] || [ -L "$skills_dst" ]; then
    claude_real="$(readlink -m -- "$skills_dst" 2>/dev/null)" || claude_real=""
    case "$claude_real" in
      "$proj_real"/*) ;;
      *) warn "$project_root/.claude (or .claude/skills) is a symlink that resolves outside the project — REFUSED, nothing written"; return 1 ;;
    esac
  fi
  mkdir -p "$skills_dst"
  case "$(cd "$skills_dst" && pwd -P)" in
    "$proj_real"/*) ;;
    *) warn "$skills_dst resolves outside the project — REFUSED"; return 1 ;;
  esac

  # Reap OUR dangling skill links only: a dangling link whose resolved target lies under THIS
  # constitution's skills dir. A user's own dangling link, whatever its text, is never touched.
  local stale
  for stale in "$skills_dst"/*; do
    if [ -L "$stale" ] && [ ! -e "$stale" ] && ic_link_owned "$stale" skills; then
      rm -f "$stale"
    fi
  done

  local linked=0 skipped=0 refused=0 name src dst cur
  for src in "$skills_src"/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"
    [ -z "$one_skill" ] || [ "$name" = "$one_skill" ] || continue

    # Only link real Agent Skills — a directory with a SKILL.md. Legacy skill
    # dirs that carry only skill.md/register.sh are NOT discoverable as Agent
    # Skills; say so honestly instead of linking something that cannot load.
    if [ ! -f "${src}SKILL.md" ]; then
      skipped=$((skipped + 1))
      continue
    fi

    dst="$skills_dst/$name"
    if [ -L "$dst" ]; then
      # Replace only a link that already points at OUR skill (or is our own dangling one).
      cur="$(readlink -f -- "$dst" 2>/dev/null || true)"
      if [ "$cur" = "$(readlink -f -- "${src%/}")" ] || { [ ! -e "$dst" ] && ic_link_owned "$dst" skills; }; then
        hc_ln_relative "${src%/}" "$dst"
        linked=$((linked + 1))
      else
        warn "$dst is a symlink to somewhere else (user-owned?) — REFUSED, left untouched"
        refused=$((refused + 1))
      fi
    elif [ ! -e "$dst" ]; then
      hc_ln_relative "${src%/}" "$dst"
      linked=$((linked + 1))
    else
      warn "$dst exists and is NOT a symlink ($([ -d "$dst" ] && echo directory || echo 'regular file')) — REFUSED, left untouched (remove it to re-link)"
      refused=$((refused + 1))
    fi
  done

  ok "linked $linked skill(s) into .claude/skills/ (${skipped} legacy dir(s) without SKILL.md skipped, ${refused} refused)"
  [ "$refused" -eq 0 ] || return 1
  return 0
}

# ── 2a. Wire the OTHER CLI agents' slash commands (Gemini / Qwen / Codex) ────
# The generated command files are linked (never copied — §11.4.28/§11.4.80) into
# each agent's project-level command directory, exactly as actions/generated/
# README.md declares. Claude Code is NOT handled here: it gets the real plugin.
link_agent_commands() {
  local gen="$const_root/actions/generated"
  [ -d "$gen" ] || { warn "actions/generated missing — other agents NOT wired"; return 1; }

  # agent:source-subdir:destination-dir-relative-to-project:extension
  local specs="gemini:.gemini/commands:toml qwen:.qwen/commands:toml codex:prompts:md"
  local spec agent dst_rel ext src_dir dst_dir f base total=0 refused_dirs=0

  for spec in $specs; do
    agent="${spec%%:*}"
    dst_rel="${spec#*:}"; dst_rel="${dst_rel%%:*}"
    ext="${spec##*:}"
    src_dir="$gen/$agent"
    [ -d "$src_dir" ] || continue
    dst_dir="$project_root/$dst_rel"
    # Containment first, mkdir second: a symlinked .gemini/.qwen/prompts pointing outside the project
    # must receive nothing (and mkdir -p through it would already write outside).
    if ! ic_dir_inside_project "$dst_dir"; then
      warn "$dst_dir resolves outside the project — REFUSED, nothing written"
      refused_dirs=$((refused_dirs + 1))
      continue
    fi
    mkdir -p "$dst_dir"

    # Reap DANGLING symlinks first: when an action is removed from the registry
    # the generator prunes its command file, which would otherwise leave a broken
    # link here — an agent offering a directive that no longer exists.
    local stale
    for stale in "$dst_dir"/*; do
      if [ -L "$stale" ] && [ ! -e "$stale" ] && ic_link_owned "$stale" actions/generated; then
        rm -f "$stale"
      fi
    done

    local n=0
    for f in "$src_dir"/*."$ext"; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      # Only ever replace our own symlink or a free slot — never clobber a real
      # file the operator wrote by hand.
      if [ ! -e "$dst_dir/$base" ] && [ ! -L "$dst_dir/$base" ]; then
        hc_ln_relative "$f" "$dst_dir/$base"
        n=$((n + 1))
      elif ic_link_owned "$dst_dir/$base" actions/generated; then
        hc_ln_relative "$f" "$dst_dir/$base"
        n=$((n + 1))
      else
        warn "$dst_dir/$base exists and is not our symlink (user-owned file or link) — left untouched"
      fi
    done
    [ "$n" -eq 0 ] || ok "wired $n $agent command(s) → $dst_rel/"
    total=$((total + n))
  done

  [ "$total" -gt 0 ] || warn "no per-agent commands linked (nothing generated?)"
  [ "$refused_dirs" -eq 0 ] || return 1
  return 0
}

# ── 2b. Wire the free-form prompt-prefix hook (UserPromptSubmit) ─────────────
# The plugin ships COMMANDS ONLY and deliberately ships NO UserPromptSubmit hook:
# if both the plugin and install_action_prefix.sh registered one, a prompt would
# be expanded TWICE. install_action_prefix.sh stays the single owner of that hook
# and is genuinely idempotent (it refuses to append a hook command it already
# finds), so chaining it here is safe and makes ONE command wire everything:
# free-form `NAME :: task` prefixes AND `/name` slash commands AND skills.
wire_prompt_hook() {
  local inst="$const_root/scripts/install_action_prefix.sh"
  if [ ! -f "$inst" ]; then
    warn "install_action_prefix.sh missing — free-form prefix expansion NOT wired"
    return 1
  fi
  # Containment before delegating (the callee also checks, as it can be run standalone).
  if ! ic_dir_inside_project "$project_root/.claude" || ! ic_dir_inside_project "$project_root/.claude/settings.json"; then
    warn "$project_root/.claude resolves outside the project — prompt hook REFUSED, nothing written"
    return 1
  fi
  if bash "$inst" "$project_root" >/dev/null 2>&1; then
    ok "wired the UserPromptSubmit prefix hook (free-form 'NAME :: task' forms)"
    return 0
  fi
  warn "install_action_prefix.sh FAILED — free-form prefix expansion may be unwired"
  return 1
}

# ── 3. Register the marketplace + install the plugin (non-interactive) ───────
# marketplace_hint_path — the constitution path as the operator types it from
# the project root: ./submodules/constitution (standard), ./constitution
# (legacy), or the absolute path when it lives outside the project.
marketplace_hint_path() {
  local rel=""
  if [ -f "$self_dir/lib/constitution_layout.sh" ]; then
    # shellcheck source=lib/constitution_layout.sh
    . "$self_dir/lib/constitution_layout.sh"
    rel="$(cl_rel_path "$project_root" "$const_root")"
  fi
  case "$rel" in
    '') printf '%s\n' "$const_root" ;;
    /*) printf '%s\n' "$rel" ;;
    *)  printf './%s\n' "$rel" ;;
  esac
}

install_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    warn "the \`claude\` CLI is NOT on PATH — the plugin was NOT installed."
    warn "ONE-TIME operator step, from the project root:"
    warn "    claude plugin marketplace add $(printf '%q' "$(marketplace_hint_path)")"
    warn "    claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    return 1
  fi

  # Idempotent: `marketplace add` on an already-known marketplace is a no-op we
  # tolerate; we assert the END STATE below rather than trusting either exit code
  # (§11.4.6 — a tool's own success message is not proof, §11.4.200).
  claude plugin marketplace add "$const_root" >/dev/null 2>&1 || true
  claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}" >/dev/null 2>&1 || true

  if claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME"; then
    ok "plugin '${PLUGIN_NAME}@${MARKETPLACE_NAME}' is INSTALLED (verified via \`claude plugin list\`)"
    return 0
  fi

  warn "plugin '${PLUGIN_NAME}' is NOT listed after install — NOT claiming success."
  warn "Run manually and read the error:"
  warn "    claude plugin marketplace add $const_root"
  warn "    claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}"
  return 1
}

# ── --check: report the wiring state, change nothing ─────────────────────────
if [ "$check_only" -eq 1 ]; then
  rc=0
  [ -f "$const_root/.claude-plugin/marketplace.json" ] || { warn "marketplace.json MISSING"; rc=1; }
  [ -f "$const_root/plugins/$PLUGIN_NAME/.claude-plugin/plugin.json" ] || { warn "plugin.json MISSING"; rc=1; }
  n_cmds="$(find "$const_root/plugins/$PLUGIN_NAME/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n_cmds" -gt 0 ] || { warn "no generated commands"; rc=1; }
  n_skills="$(find "$const_root/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n_skills" -gt 0 ] || { warn "no SKILL.md skills"; rc=1; }
  ok "constitution side: marketplace + plugin manifests present; ${n_cmds} command(s); ${n_skills} skill(s)"

  # PROJECT side — a constitution-only check would be a §11.4.201 proxy signal:
  # it would report WIRED while the project had nothing installed.
  n_linked="$(find "$project_root/.claude/skills" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n_linked" -ge "$n_skills" ] && [ "$n_skills" -gt 0 ]; then
    ok "project side: ${n_linked} skill symlink(s) in .claude/skills/"
  else
    warn "project side: only ${n_linked}/${n_skills} skill(s) linked into .claude/skills/"; rc=1
  fi

  if grep -q 'action_prefix_expand' "$project_root/.claude/settings.json" 2>/dev/null; then
    ok "project side: UserPromptSubmit prefix hook is registered"
  else
    warn "project side: UserPromptSubmit prefix hook NOT registered in .claude/settings.json"; rc=1
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME"; then
      ok "project side: plugin '${PLUGIN_NAME}' is installed + enabled"
    else
      warn "project side: plugin '${PLUGIN_NAME}' is NOT installed"; rc=1
    fi
  else
    warn "project side: \`claude\` CLI absent — plugin state UNKNOWN (not claiming either way)"
  fi

  [ "$rc" -eq 0 ] && ok "VERDICT: WIRED" || warn "VERDICT: NOT-WIRED"
  exit "$rc"
fi

rc=0
if [ "$skills_only" -eq 0 ]; then
  regen_commands || rc=1
  link_agent_commands || rc=1
  wire_prompt_hook || rc=1
fi
link_skills || rc=1
if [ "$skills_only" -eq 0 ] && [ "$do_plugin" -eq 1 ]; then
  # A missing `claude` CLI is a legitimate, honestly-reported state (other
  # agents do not need it) — it does not fail the whole install.
  install_plugin || true
fi

if [ "$rc" -eq 0 ]; then
  ok "done — action directives + skills are wired for this project"
else
  warn "completed WITH problems (see WARN lines above)"
fi
exit "$rc"
