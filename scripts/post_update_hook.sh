#!/usr/bin/env bash
# ============================================================================
# post_update_hook.sh — Constitution submodule post-update auto-propagation
# ============================================================================
# Purpose:
#   After `git pull` or `git submodule update` fetches new constitution
#   content, detect changed files and install/register/merge them into the
#   consuming project.
#
#   §11.4.164 — Post-update auto-propagation mandate
#
# What it does:
#   1. Detects which files changed in the constitution submodule since HEAD
#   2. Installs newly added/modified skills from constitution/skills/
#   3. Merges newly added/modified MCP configs from constitution/mcp/
#   4. Installs newly added/modified hooks from constitution/scripts/hooks/
#   4b/4c/4d. Re-wires action directives, the label-sync Claude Code hooks
#      (LABEL_SYNC_AUTOWIRE, dry-run default) and the label-sync CLI-agent
#      adapters (LABEL_SYNC_ADAPTERS, dry-run default)
#   5. chmod +x and syntax-validate all new/modified scripts (label-sync's too)
#   6. Reports a summary of what was installed
#   Every step 2-5 is ISOLATED (run_step): a failing step is recorded as a
#   WARNING and the next step still runs — no step can abort the hook.
#
# Usage:
#   bash constitution/scripts/post_update_hook.sh
#   # or from any consuming project root:
#   bash <path-to-constitution>/scripts/post_update_hook.sh
#
# Inputs:
#   CONST_DIR  — path to the constitution submodule root
#                (default: the directory this script lives in, ../..)
#   PROJECT_ROOT — consuming project root (default: pwd)
#
# Outputs:
#   stdout — summary of installed/registered items
#   Exit 0 — all good
#   Exit 1 — errors encountered
#
# Dependencies:
#   git, diff (or git diff), shellcheck (optional, for validate)
#
# Side-effects:
#   - Copies/links skill directories into the consuming project
#   - Merges MCP config JSON snippets
#   - Installs git hooks into project .git/hooks/
#   - Sets executable bits on scripts
#
# Cross-references:
#   constitution/Constitution.md §11.4.164
#   constitution/scripts/hooks/post-merge
#   constitution/mcp/*.json
#   constitution/skills/*/
#
# Last verified: 2026-06-21
# ============================================================================

set -euo pipefail

# --- Resolve paths ----------------------------------------------------------
# NOTE (§11.4.201 — a guard must assert the REAL condition): CONST_DIR must be
# the CONSTITUTION root. This script lives at <constitution>/scripts/, so the
# root is ONE level up ("..") — NOT two. The previous default ("../..") resolved
# to the PARENT PROJECT root, so `git diff` ran against the parent repo, whose
# changed paths look like "constitution/skills/..." and therefore matched NONE of
# the "skills/*" / "actions/*" / "scripts/hooks/*" classifiers below: the hook
# reported "No relevant changes" and propagated NOTHING, silently. That was a
# reproduced defect (probe: default='<parent>', constitution='<parent>/constitution').
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_DIR="${CONST_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Fail loudly rather than silently propagating nothing (§11.4.6): the resolved
# CONST_DIR MUST actually look like the constitution submodule.
if [ ! -f "$CONST_DIR/Constitution.md" ] || [ ! -d "$CONST_DIR/scripts" ]; then
    echo "[ERROR] CONST_DIR does not look like the constitution root: $CONST_DIR" >&2
    echo "        (expected Constitution.md + scripts/ there). Set CONST_DIR explicitly." >&2
    exit 1
fi

# --- State ----------------------------------------------------------------
CHANGED_SKILLS=()
CHANGED_MCP=()
CHANGED_HOOKS=()
CHANGED_SCRIPTS=()
CHANGED_ACTIONS=()   # actions/registry.yaml + plugins/** — re-wire slash commands
CHANGED_LABELSYNC=() # scripts/label-sync/** + the labeler — re-wire the label-sync hooks (§11.4.228(D))
ERRORS=()
WARNINGS=()

# Safe expansion of a possibly-empty array under `set -u` (bash < 4.4).
arr_len() { eval "printf '%s' \"\${#$1[@]}\""; }

# --- Colour helpers -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}== $* ==${NC}"; }

# --- Cleanup trap ---------------------------------------------------------
cleanup() {
    :
}
trap cleanup EXIT

# ============================================================================
# STEP 1 — Detect changed files
# ============================================================================
detect_changes() {
    header "STEP 1: Detecting changes in constitution submodule"

    # Determine the diff base — if the script was just invoked, diff HEAD
    # against the previous HEAD (ORIG_HEAD if available, otherwise HEAD~1).
    # For `git pull` / `git submodule update` scenarios, ORIG_HEAD is set
    # by git before the merge.
    local old_ref
    if git -C "$CONST_DIR" rev-parse --verify ORIG_HEAD 2>/dev/null; then
        old_ref="ORIG_HEAD"
    else
        # Fall back to HEAD~1 — may miss some if HEAD is detached but it's
        # the best we can do without ORIG_HEAD.
        old_ref="HEAD~1"
        warn "ORIG_HEAD not set — using HEAD~1 as baseline (may miss deeper changes)"
    fi

    # List all files that changed (added or modified) in this update.
    # Deleted files are not installed — they stay removed.
    local changed_files
    changed_files="$(git -C "$CONST_DIR" diff --name-only --diff-filter=AM "$old_ref"..HEAD 2>/dev/null || true)"

    if [ -z "$changed_files" ]; then
        info "No files changed in this update — nothing to propagate."
        return 0
    fi

    # NOTE (§11.4.201 — a guard must assert the REAL condition): this loop MUST
    # NOT be fed by a pipe. `cmd | while ...` runs the loop body in a SUBSHELL,
    # so every `ARR+=(...)` is discarded when the subshell exits and the caller
    # sees EMPTY arrays — the hook then reports "no changes" and installs
    # NOTHING, silently. That was a real, reproduced defect (probe:
    # `AFTER-LOOP count = 0`). Process substitution keeps the loop in THIS shell.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # Classify by path prefix
        case "$f" in
            skills/*)
                # Extract the skill directory name (skills/<name>/...)
                local skill_name
                skill_name="$(echo "$f" | cut -d/ -f2)"
                CHANGED_SKILLS+=("$skill_name")
                ;;
            mcp/*.json)
                local mcp_name
                mcp_name="$(basename "$f")"
                CHANGED_MCP+=("$mcp_name")
                ;;
            scripts/hooks/*)
                local hook_name
                hook_name="$(basename "$f")"
                CHANGED_HOOKS+=("$hook_name")
                ;;
            actions/*|plugins/*|.claude-plugin/*)
                # A registry row, a plugin manifest, or a generated command changed
                # => the per-agent slash commands + plugin wiring must be refreshed.
                CHANGED_ACTIONS+=("$f")
                ;;
            scripts/label-sync/*|scripts/multitrack/track_branch_label.sh)
                # label-sync hooks/installer/labeler changed => the hook wiring is re-asserted
                # (step 4c; DRY-RUN by default, LABEL_SYNC_AUTOWIRE=apply writes).
                CHANGED_LABELSYNC+=("$f")
                ;;
            scripts/*.sh)
                local script_name
                script_name="$(basename "$f")"
                # Don't double-count hooks that are also under scripts/hooks/
                if [[ "$f" != scripts/hooks/* ]]; then
                    CHANGED_SCRIPTS+=("$script_name")
                fi
                ;;
            *)
                # Ignore other files (docs, md, etc.)
                ;;
        esac
    done < <(printf '%s\n' "$changed_files")

    # Deduplicate arrays (same file may appear multiple times across commits).
    # Guarded against the empty case: `"${ARR[@]}"` on an empty array is an
    # unbound-variable error under `set -u` on bash < 4.4.
    local IFS_SAVE="$IFS"
    IFS=$'\n'
    [ "$(arr_len CHANGED_SKILLS)"  -eq 0 ] || CHANGED_SKILLS=($(printf "%s\n" "${CHANGED_SKILLS[@]}"  | sort -u))
    [ "$(arr_len CHANGED_MCP)"     -eq 0 ] || CHANGED_MCP=($(printf "%s\n" "${CHANGED_MCP[@]}"        | sort -u))
    [ "$(arr_len CHANGED_HOOKS)"   -eq 0 ] || CHANGED_HOOKS=($(printf "%s\n" "${CHANGED_HOOKS[@]}"    | sort -u))
    [ "$(arr_len CHANGED_SCRIPTS)" -eq 0 ] || CHANGED_SCRIPTS=($(printf "%s\n" "${CHANGED_SCRIPTS[@]}" | sort -u))
    [ "$(arr_len CHANGED_ACTIONS)" -eq 0 ] || CHANGED_ACTIONS=($(printf "%s\n" "${CHANGED_ACTIONS[@]}" | sort -u))
    [ "$(arr_len CHANGED_LABELSYNC)" -eq 0 ] || CHANGED_LABELSYNC=($(printf "%s\n" "${CHANGED_LABELSYNC[@]}" | sort -u))
    IFS="$IFS_SAVE"

    info "Detected: ${#CHANGED_SKILLS[@]} skill(s), ${#CHANGED_MCP[@]} MCP config(s), ${#CHANGED_HOOKS[@]} hook(s), ${#CHANGED_SCRIPTS[@]} script(s), ${#CHANGED_ACTIONS[@]} action/plugin file(s), $(arr_len CHANGED_LABELSYNC) label-sync file(s) changed."
}

# ============================================================================
# STEP 2 — Install/register skills
# ============================================================================
install_skills() {
    header "STEP 2: Installing/registering skills"

    if [ ${#CHANGED_SKILLS[@]} -eq 0 ]; then
        info "No skills to install."
        return 0
    fi

    local project_skills_dir="${PROJECT_ROOT}/skills"
    mkdir -p "$project_skills_dir"

    for skill_name in "${CHANGED_SKILLS[@]}"; do
        local src="${CONST_DIR}/skills/${skill_name}"
        local dst="${project_skills_dir}/${skill_name}"

        if [ ! -d "$src" ]; then
            warn "Skill source directory '$src' not found — skipping."
            continue
        fi

        info "Installing skill: ${skill_name}"

        # DATA SAFETY (§9.2 / §11.4.122): only ever replace OUR OWN symlink or a
        # free slot. The previous `rm -rf "$dst"` destroyed, without confirmation,
        # any REAL directory a consuming project happened to keep at that path.
        # Never delete an operator's directory to make room for a link.
        if [ -L "$dst" ] || [ ! -e "$dst" ]; then
            rm -f "$dst"
            ln -s "$src" "$dst"
            info "  -> Linked: $dst -> $src"
        else
            warn "  -> $dst exists and is NOT a symlink — left untouched (remove it yourself to re-link)"
            WARNINGS+=("skill '${skill_name}': $dst is a real path, not a symlink — not replaced")
        fi

        # If skill has a registration file, source it
        local register="${src}/register.sh"
        if [ -f "$register" ]; then
            info "  -> Running registration script: $register"
            (bash "$register" "$PROJECT_ROOT") || warn "  -> Registration script exited non-zero (continuing)"
        fi

        # If skill has a README or SKILL.md, note it (SKILL.md first;
        # legacy lowercase skill.md still noted for backward compatibility)
        local skill_doc
        for skill_doc in "SKILL.md" "README.md" "skill.md"; do
            if [ -f "${src}/${skill_doc}" ]; then
                info "  -> Skill documentation: skills/${skill_name}/${skill_doc}"
                break
            fi
        done
    done
}

# ============================================================================
# STEP 3 — Merge MCP configs
# ============================================================================
install_mcp_configs() {
    header "STEP 3: Merging MCP configurations"

    if [ ${#CHANGED_MCP[@]} -eq 0 ]; then
        info "No MCP configs to merge."
        return 0
    fi

    # Determine the consuming project's MCP config path.
    # Claude Code uses .mcp.json in several locations; we try project root first.
    local mcp_dst="${PROJECT_ROOT}/.mcp.json"
    local mcp_src_dir="${CONST_DIR}/mcp"

    if ! command -v jq &>/dev/null; then
        warn "jq not available — MCP configs NOT merged. Merge ${mcp_src_dir}/*.json into $mcp_dst by hand."
        WARNINGS+=("MCP configs not merged: jq missing")
        return 0
    fi
    if [ ! -f "$mcp_dst" ]; then
        # Create a minimal .mcp.json if none exists
        info "Creating new .mcp.json at project root (none existed)."
        echo '{"mcpServers":{}}' > "$mcp_dst" || { warn "cannot create $mcp_dst"; WARNINGS+=("cannot create $mcp_dst"); return 0; }
    fi
    # A consumer .mcp.json jq cannot parse (comments, trailing commas, ...) is
    # NEVER touched and NEVER aborts the hook (review-2 finding C: under
    # `set -e` the failing jq used to end the run before steps 4-5).
    if ! jq -e 'type == "object"' "$mcp_dst" >/dev/null 2>&1; then
        warn "$mcp_dst is not a JSON object jq can parse (comments?) — left untouched; MCP configs NOT merged."
        WARNINGS+=("MCP configs not merged: $mcp_dst is not parseable JSON")
        return 0
    fi

    # Paths in a constitution MCP config are relative to the CONSTITUTION root
    # (e.g. scripts/label-sync/mcp/label-mcp.sh). In a consumer they must be
    # resolvable from the PROJECT root (review-2 finding D): such a path is
    # rewritten to <constitution-dir-relative-to-project>/<path> (absolute when
    # the constitution lives outside the project). Only strings that name an
    # existing file under the constitution and NOT under the project root are
    # rewritten. HONEST BOUNDARY: that Claude Code starts a project-scope stdio
    # server with the project root as its working directory is UNCONFIRMED
    # (not documented in this repository); the vendor-relative path relies on it.
    local croot proot cprefix
    croot="$(cd "$CONST_DIR" 2>/dev/null && pwd -P)" || croot="$CONST_DIR"
    proot="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || proot="$PROJECT_ROOT"
    case "$croot/" in "$proot"/*) cprefix="${croot#"$proot"/}" ;; *) cprefix="$croot" ;; esac

    for mcp_name in "${CHANGED_MCP[@]}"; do
        local src_file="${mcp_src_dir}/${mcp_name}"

        if [ ! -f "$src_file" ]; then
            warn "MCP config source '$src_file' not found — skipping."
            continue
        fi

        info "Merging MCP config: ${mcp_name}"
        local server_key="${mcp_name%.json}" frag tmpfile
        frag="$(mktemp "${mcp_dst}.frag.XXXXXX")" || { WARNINGS+=("MCP ${mcp_name}: no temp file"); continue; }
        tmpfile="$(mktemp "${mcp_dst}.new.XXXXXX")" || { rm -f "$frag"; WARNINGS+=("MCP ${mcp_name}: no temp file"); continue; }
        # The source has the shape { "mcpServers": { "<name>": {...} } } or is a
        # flat server object (wrapped under its file name).
        if ! jq -e --arg k "$server_key" 'if has("mcpServers") then . else {mcpServers: {($k): .}} end' "$src_file" >"$frag" 2>/dev/null; then
            warn "  -> $src_file is not valid JSON — skipped."; WARNINGS+=("MCP ${mcp_name}: source not valid JSON")
            rm -f "$frag" "$tmpfile"; continue
        fi
        local key idx str
        while IFS=$'\t' read -r key idx str; do
            [ -n "$str" ] || continue
            case "$str" in /*|*://*) continue ;; */*) ;; *) continue ;; esac
            [ -e "$croot/$str" ] && [ ! -e "$proot/$str" ] || continue
            if [ "$idx" = 0 ]; then
                jq --arg k "$key" --arg v "$cprefix/$str" '.mcpServers[$k].command = $v' "$frag" >"$frag.x" && mv -f "$frag.x" "$frag"
            else
                jq --arg k "$key" --argjson i "$((idx - 1))" --arg v "$cprefix/$str" '.mcpServers[$k].args[$i] = $v' "$frag" >"$frag.x" && mv -f "$frag.x" "$frag"
            fi
            info "  -> path resolved for the consumer: $str -> $cprefix/$str"
        done < <(jq -r '.mcpServers | to_entries[] | .key as $k | ([.value.command] + (.value.args // [])) | to_entries[] | [$k, (.key|tostring), (.value // "" | tostring)] | @tsv' "$frag" 2>/dev/null)
        if jq -s '.[0].mcpServers = ((.[0].mcpServers // {}) + .[1].mcpServers) | .[0]' "$mcp_dst" "$frag" >"$tmpfile" 2>/dev/null \
           && jq -e 'type == "object"' "$tmpfile" >/dev/null 2>&1 && mv -f "$tmpfile" "$mcp_dst"; then
            info "  -> Merged into: $mcp_dst"
        else
            warn "  -> merge of ${mcp_name} failed — $mcp_dst left unchanged."
            WARNINGS+=("MCP ${mcp_name}: merge failed")
        fi
        rm -f "$frag" "$frag.x" "$tmpfile"
    done
    return 0
}

# ============================================================================
# STEP 4 — Install git hooks
# ============================================================================
install_hooks() {
    header "STEP 4: Installing git hooks"

    if [ ${#CHANGED_HOOKS[@]} -eq 0 ]; then
        info "No hooks to install."
        return 0
    fi

    # NOTE (§11.4.201 + review finding 6): this step NEVER returns non-zero —
    # the script runs under `set -e`, and a failing step here used to abort the
    # WHOLE hook before step 4c (label-sync) and step 5 ever ran. Worktrees and
    # submodule checkouts have NO <root>/.git/hooks directory (.git is a FILE),
    # so the hooks dir is asked from git itself (`--git-path hooks`, which also
    # honours core.hooksPath), never assumed.
    local hooks_src="${CONST_DIR}/scripts/hooks" hooks_dst=""
    hooks_dst="$(cd "$PROJECT_ROOT" 2>/dev/null && git rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" || hooks_dst=""
    if [ -z "$hooks_dst" ]; then   # git < 2.31 has no --path-format: absolutise by hand
        hooks_dst="$(cd "$PROJECT_ROOT" 2>/dev/null && git rev-parse --git-path hooks 2>/dev/null)" || hooks_dst=""
        case "$hooks_dst" in ''|/*) ;; *) hooks_dst="$PROJECT_ROOT/$hooks_dst" ;; esac
    fi
    if [ -z "$hooks_dst" ]; then
        warn "$PROJECT_ROOT is not a git work tree — git hooks cannot be installed (skipped)."
        WARNINGS+=("git hooks not installed: $PROJECT_ROOT is not a git work tree")
        return 0
    fi
    if ! mkdir -p "$hooks_dst" 2>/dev/null; then
        warn "cannot create the git hooks dir $hooks_dst — hooks not installed."
        WARNINGS+=("git hooks dir $hooks_dst not writable")
        return 0
    fi

    local hook_name
    for hook_name in "${CHANGED_HOOKS[@]}"; do
        # ONLY real git hook names are installed: scripts/hooks/ also holds
        # Claude Code guards (guard-*.sh) and test suites (test_*.sh) that must
        # never be copied into .git/hooks.
        case "$hook_name" in
            applypatch-msg|pre-applypatch|post-applypatch|pre-commit|pre-merge-commit|\
            prepare-commit-msg|commit-msg|post-commit|pre-rebase|post-checkout|post-merge|\
            pre-push|pre-receive|update|proc-receive|post-receive|post-update|\
            reference-transaction|push-to-checkout|pre-auto-gc|post-rewrite|\
            sendemail-validate|fsmonitor-watchman|post-index-change) ;;
            *) info "Not a git hook name — not installed: ${hook_name}"; continue ;;
        esac
        local src_file="${hooks_src}/${hook_name}"
        local dst_file="${hooks_dst}/${hook_name}"

        if [ ! -f "$src_file" ]; then
            warn "Hook source '$src_file' not found — skipping."
            continue
        fi

        info "Installing hook: ${hook_name}"
        if cp "$src_file" "$dst_file" && chmod +x "$dst_file"; then
            info "  -> Installed: $dst_file"
        else
            warn "could not install $dst_file"
            WARNINGS+=("git hook ${hook_name} not installed")
        fi
    done
    return 0
}

# ============================================================================
# STEP 4b — Re-wire CLI-agent action directives (plugins + slash commands)
# ============================================================================
# §11.4.140 + §11.4.164: when a registry row, a plugin manifest, a generated
# command, or ANY skill changes, the per-agent slash commands are regenerated
# and the Claude Code plugin + skills are (re-)wired into the consuming project.
# Idempotent — safe on every pull.
install_action_plugins() {
    header "STEP 4b: Wiring CLI-agent action directives (plugins + skills)"

    if [ "$(arr_len CHANGED_ACTIONS)" -eq 0 ] && [ "$(arr_len CHANGED_SKILLS)" -eq 0 ]; then
        info "No action/plugin/skill changes — nothing to re-wire."
        return 0
    fi

    # NOTE (§11.4.201, same class as step 4's review finding 6): this step
    # NEVER returns non-zero. The script runs under `set -e`, so a non-zero
    # return here aborted the WHOLE hook before step 4c (label-sync) and
    # step 5 ever ran. A missing installer is surfaced as a WARNING (shown
    # in the step-6 summary), never as a silent success and never as an abort.
    local installer="${CONST_DIR}/scripts/install_cli_agent_plugins.sh"
    if [ ! -f "$installer" ]; then
        warn "installer missing: $installer — action directives NOT re-wired."
        WARNINGS+=("install_cli_agent_plugins.sh missing — slash commands may be stale")
        return 0
    fi

    info "Running: $installer $PROJECT_ROOT"
    if bash "$installer" "$PROJECT_ROOT"; then
        info "  -> Action directives + skills wired."
    else
        # A missing `claude` CLI is an honest, non-fatal state (other agents do
        # not need it) — the installer reports it and exits non-zero; we surface
        # it as a WARNING, never as a silent success (§11.4.6).
        warn "Installer reported problems — see its WARN lines above."
        WARNINGS+=("install_cli_agent_plugins.sh reported problems")
    fi

    # --- §11.4.272 dynamic skill activation: bring the declared CORE up ------
    # ADDITIVE. Never removes anything the installer linked; it only ensures
    # the manifest's core set is active and reports the resulting surface.
    # A missing engine is an honest WARNING, never a silent success (§11.4.6).
    local sa="${CONST_DIR}/scripts/skill_activation/skill_activate.sh"
    if [ -x "$sa" ]; then
        info "Running: skill_activate.sh session-init $PROJECT_ROOT"
        if bash "$sa" session-init "$PROJECT_ROOT"; then
            info "  -> Skill activation baseline applied (§11.4.272)."
        else
            warn "skill_activate.sh session-init reported problems — a CORE skill may NOT be available."
            WARNINGS+=("skill activation: a core skill failed to activate")
        fi
    else
        warn "skill_activate.sh not executable/missing at $sa — dynamic skill activation NOT applied."
        WARNINGS+=("skill_activate.sh missing — dynamic skill activation inactive")
    fi
    return 0
}

# ============================================================================
# STEP 4c — label-sync auto-wiring (hooks + statusLine into the consumer)
# ============================================================================
# §11.4.228(D) + §11.4.164 + §11.4.182: when label-sync scripts, the installer or
# the canonical labeler change, the Claude Code hook entries + statusLine of the
# consuming project's .claude/settings.json are re-asserted by the idempotent
# installer scripts/label-sync/install_label_sync.sh.
#
# DEFAULT IS NON-DESTRUCTIVE: without LABEL_SYNC_AUTOWIRE=apply the installer
# runs in --dry-run --brief mode and this step only RECORDS what WOULD be wired
# (nothing is written to the consumer). Modes (env LABEL_SYNC_AUTOWIRE):
#   dry-run (default) | apply (write; backup first) | off (skip silently)
install_label_sync() {
    header "STEP 4c: label-sync auto-wiring (§11.4.228(D))"

    if [ "$(arr_len CHANGED_LABELSYNC)" -eq 0 ]; then
        info "No label-sync changes — nothing to wire."
        return 0
    fi

    local installer="${CONST_DIR}/scripts/label-sync/install_label_sync.sh"
    if [ ! -f "$installer" ]; then
        warn "installer missing: $installer — label-sync hooks NOT (re-)wired."
        WARNINGS+=("install_label_sync.sh missing — label-sync auto-wiring inactive")
        return 0
    fi

    local mode="${LABEL_SYNC_AUTOWIRE:-dry-run}" out rc=0
    local -a args
    case "$mode" in
        off)     info "LABEL_SYNC_AUTOWIRE=off — label-sync auto-wiring skipped."; return 0 ;;
        apply)   args=(--apply) ;;
        dry-run) args=(--dry-run --brief) ;;
        *)       warn "unknown LABEL_SYNC_AUTOWIRE='$mode' — treating as dry-run (non-destructive)."
                 mode="dry-run"; args=(--dry-run --brief) ;;
    esac

    info "Running: install_label_sync.sh --project-root $PROJECT_ROOT ${args[*]}  (mode: $mode)"
    out="$(bash "$installer" --project-root "$PROJECT_ROOT" "${args[@]}" 2>&1)" || rc=$?
    while IFS= read -r line; do [ -n "$line" ] && info "  $line"; done <<<"$out"
    if [ "$rc" -ne 0 ]; then
        warn "label-sync installer exited $rc — see lines above (hooks NOT changed unless reported as wired)."
        WARNINGS+=("install_label_sync.sh exited $rc")
        return 0
    fi
    if [ "$mode" = "dry-run" ]; then
        info "label-sync auto-wiring is in DRY-RUN mode (default, non-destructive): nothing was written."
        info "  To wire the hooks + statusLine into $PROJECT_ROOT/.claude/settings.json re-run with LABEL_SYNC_AUTOWIRE=apply."
    fi
    return 0
}

# ============================================================================
# STEP 4d — label-sync CLI-agent adapters (kimi/opencode/crush/aider/codex/...)
# ============================================================================
# review-2 finding E: install_adapters.sh claimed post_update_hook ran it; it
# did not. It now runs here, OPT-IN like step 4c: dry-run by default (records
# what WOULD be wired into the user's agent configs, writes nothing). Modes
# (env LABEL_SYNC_ADAPTERS): dry-run (default) | apply | off. Agents are
# auto-detected by install_adapters.sh; their configs live in the USER's home
# (not the project), which is why writing is never the default.
install_label_sync_adapters() {
    header "STEP 4d: label-sync CLI-agent adapters (§11.4.228(D))"
    local changed=0 f
    for f in ${CHANGED_LABELSYNC[@]+"${CHANGED_LABELSYNC[@]}"}; do
        case "$f" in scripts/label-sync/adapters/*) changed=1 ;; esac
    done
    if [ "$changed" -eq 0 ]; then
        info "No adapter changes — nothing to wire."
        return 0
    fi
    local inst="${CONST_DIR}/scripts/label-sync/adapters/install_adapters.sh"
    if [ ! -f "$inst" ]; then
        warn "adapter installer missing: $inst"; WARNINGS+=("install_adapters.sh missing"); return 0
    fi
    local mode="${LABEL_SYNC_ADAPTERS:-dry-run}" out rc=0
    local -a args
    case "$mode" in
        off)     info "LABEL_SYNC_ADAPTERS=off — adapter wiring skipped."; return 0 ;;
        apply)   args=(--apply) ;;
        dry-run) args=(--dry-run) ;;
        *)       warn "unknown LABEL_SYNC_ADAPTERS='$mode' — treating as dry-run."; mode=dry-run; args=(--dry-run) ;;
    esac
    info "Running: install_adapters.sh ${args[*]}  (mode: $mode)"
    out="$(bash "$inst" "${args[@]}" 2>&1)" || rc=$?
    while IFS= read -r line; do [ -n "$line" ] && info "  $line"; done <<<"$out"
    if [ "$rc" -ne 0 ]; then
        warn "install_adapters.sh exited $rc — see lines above."; WARNINGS+=("install_adapters.sh exited $rc")
    fi
    [ "$mode" = dry-run ] && info "  Adapters are in DRY-RUN mode (default): nothing written. Re-run with LABEL_SYNC_ADAPTERS=apply to wire them."
    return 0
}

# run_step <function> : run one step ISOLATED. A step that returns non-zero (or
# hits an unexpected error) is recorded as a WARNING and the next step still
# runs (review-2 finding C: the documented "step 4c always runs" was false
# once any earlier step failed under `set -e`).
run_step() {
    local fn="$1" rc=0
    "$fn" || rc=$?
    if [ "$rc" -ne 0 ]; then
        warn "step $fn ended with exit $rc — recorded; continuing with the next step"
        WARNINGS+=("step $fn exited $rc")
    fi
    return 0
}

# ============================================================================
# STEP 5 — Validate scripts (chmod +x, syntax check)
# ============================================================================
validate_scripts() {
    header "STEP 5: Validating scripts (chmod +x, syntax)"

    # Collect all new/modified .sh files from ALL categories
    local all_scripts=()

    # Scripts from CHANGED_SCRIPTS
    for s in "${CHANGED_SCRIPTS[@]}"; do
        local full="${CONST_DIR}/scripts/${s}"
        [ -f "$full" ] && all_scripts+=("$full")
    done

    # Hook scripts
    for h in "${CHANGED_HOOKS[@]}"; do
        local full="${CONST_DIR}/scripts/hooks/${h}"
        [ -f "$full" ] && all_scripts+=("$full")
    done

    # Skill scripts (validate .sh files inside skill dirs)
    for sk in "${CHANGED_SKILLS[@]}"; do
        local skill_dir="${CONST_DIR}/skills/${sk}"
        if [ -d "$skill_dir" ]; then
            while IFS= read -r -d '' sh_file; do
                all_scripts+=("$sh_file")
            done < <(find "$skill_dir" -name '*.sh' -type f -print0 2>/dev/null)
        fi
    done

    # label-sync shell scripts (review-2 finding L: they were classified as
    # CHANGED_LABELSYNC and so skipped this syntax check). Only *.sh: the zsh /
    # fish integrations are not bash and are not checked with `bash -n`.
    for f in ${CHANGED_LABELSYNC[@]+"${CHANGED_LABELSYNC[@]}"}; do
        case "$f" in *.sh) [ -f "${CONST_DIR}/$f" ] && all_scripts+=("${CONST_DIR}/$f") ;; esac
    done

    # This script itself
    all_scripts+=("${SCRIPT_DIR}/post_update_hook.sh")

    if [ ${#all_scripts[@]} -eq 0 ]; then
        info "No scripts to validate."
        return 0
    fi

    # Deduplicate
    local IFS_SAVE="$IFS"
    IFS=$'\n'
    local unique_scripts
    unique_scripts=($(printf "%s\n" "${all_scripts[@]}" | sort -u))
    IFS="$IFS_SAVE"

    local validated=0
    for script in "${unique_scripts[@]}"; do
        # chmod +x
        chmod +x "$script" 2>/dev/null || true

        # Bash syntax check (works for almost all our scripts)
        if bash -n "$script" 2>/dev/null; then
            validated=$((validated + 1))
        else
            local err_msg="SYNTAX ERROR in $script"
            error "$err_msg"
            ERRORS+=("$err_msg")

            # Attempt to get the exact error
            bash -n "$script" 2>&1 | while IFS= read -r line; do
                error "  $line"
            done
        fi
    done

    info "Validated $validated/${#unique_scripts[@]} scripts (syntax OK)."

    # Optional: shellcheck if available
    if command -v shellcheck &>/dev/null; then
        info "Running shellcheck on scripts..."
        for script in "${unique_scripts[@]}"; do
            shellcheck -x -s bash "$script" 2>/dev/null || {
                warn "shellcheck warnings/errors in $script (non-blocking)"
            }
        done
    else
        warn "shellcheck not installed — skipping static analysis"
    fi
}

# ============================================================================
# STEP 6 — Report summary
# ============================================================================
report_summary() {
    header "SUMMARY"

    echo ""
    echo -e "  ${CYAN}Skills installed:${NC}   ${#CHANGED_SKILLS[@]}"
    for s in "${CHANGED_SKILLS[@]}"; do
        echo "    - $s"
    done

    echo ""
    echo -e "  ${CYAN}MCP configs merged:${NC} ${#CHANGED_MCP[@]}"
    for m in "${CHANGED_MCP[@]}"; do
        echo "    - $m"
    done

    echo ""
    echo -e "  ${CYAN}Hooks installed:${NC}    ${#CHANGED_HOOKS[@]}"
    for h in "${CHANGED_HOOKS[@]}"; do
        echo "    - $h"
    done

    echo ""
    echo -e "  ${CYAN}Scripts validated:${NC}  ${#CHANGED_SCRIPTS[@]}"

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Warnings (${#WARNINGS[@]}):${NC}"
        for w in "${WARNINGS[@]}"; do
            echo "    - $w"
        done
    fi

    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${RED}Errors (${#ERRORS[@]}):${NC}"
        for e in "${ERRORS[@]}"; do
            echo "    - $e"
        done
        echo ""
        echo -e "  ${RED}Post-update hook completed with errors.${NC}"
        return 1
    fi

    echo ""
    echo -e "  ${GREEN}Post-update hook completed successfully.${NC}"
    return 0
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo ""
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}  Constitution Post-Update Auto-Propagation${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    info "Constitution dir:  $CONST_DIR"
    info "Project root:      $PROJECT_ROOT"
    info "Script dir:        $SCRIPT_DIR"

    detect_changes

    if [ "$(arr_len CHANGED_SKILLS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_MCP)" -eq 0 ] && \
       [ "$(arr_len CHANGED_HOOKS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_SCRIPTS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_ACTIONS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_LABELSYNC)" -eq 0 ]; then
        info "No relevant changes detected. Nothing to propagate."
        return 0
    fi

    run_step install_skills
    run_step install_mcp_configs
    run_step install_hooks
    run_step install_action_plugins
    run_step install_label_sync
    run_step install_label_sync_adapters
    run_step validate_scripts
    report_summary
}

main "$@"
