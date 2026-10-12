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
#   5. chmod +x and syntax-validate all new/modified scripts
#   6. Reports a summary of what was installed
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
ERRORS=()
WARNINGS=()

# Safe expansion of a possibly-empty array under `set -u` (bash < 4.4).
arr_len() { eval "printf '%s' \"\${#$1[@]}\""; }
# sort_unique_inplace NAME — replace array NAME by its sorted, de-duplicated, non-empty elements.
# bash-3.2 portable on purpose (V5 F7): `mapfile` / `readarray` need bash >= 4.0 and nothing else in this
# hook does (macOS ships bash 3.2 as /bin/bash), and the older `NAME=($(...))` form word-split AND
# glob-expanded every element. A `while read` over a here-document does neither. NAME must be one
# of this hook's own array names (it is eval'd); callers guard the empty case (see arr_len).
sort_unique_inplace() {
    local _su_name="$1" _su_line
    local _su_sorted
    _su_sorted="$(eval "printf '%s\\n' \"\${${_su_name}[@]}\"" | sort -u)"
    eval "$_su_name=()"
    while IFS= read -r _su_line; do
        [ -n "$_su_line" ] || continue
        eval "$_su_name+=(\"\$_su_line\")"
    done <<EOF_SU
$_su_sorted
EOF_SU
}

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
    [ "$(arr_len CHANGED_SKILLS)"  -eq 0 ] || sort_unique_inplace CHANGED_SKILLS
    [ "$(arr_len CHANGED_MCP)"     -eq 0 ] || sort_unique_inplace CHANGED_MCP
    [ "$(arr_len CHANGED_HOOKS)"   -eq 0 ] || sort_unique_inplace CHANGED_HOOKS
    [ "$(arr_len CHANGED_SCRIPTS)" -eq 0 ] || sort_unique_inplace CHANGED_SCRIPTS
    [ "$(arr_len CHANGED_ACTIONS)" -eq 0 ] || sort_unique_inplace CHANGED_ACTIONS
    IFS="$IFS_SAVE"

    info "Detected: ${#CHANGED_SKILLS[@]} skill(s), ${#CHANGED_MCP[@]} MCP config(s), ${#CHANGED_HOOKS[@]} hook(s), ${#CHANGED_SCRIPTS[@]} script(s), ${#CHANGED_ACTIONS[@]} action/plugin file(s) changed."
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

    for skill_name in ${CHANGED_SKILLS[@]+"${CHANGED_SKILLS[@]}"}; do
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

        # If skill has a README or skill.md, note it
        local skill_doc
        for skill_doc in "skill.md" "README.md" "SKILL.md"; do
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

    if [ ! -f "$mcp_dst" ]; then
        # Create a minimal .mcp.json if none exists
        info "Creating new .mcp.json at project root (none existed)."
        echo '{"mcpServers":{}}' > "$mcp_dst"
    fi

    for mcp_name in ${CHANGED_MCP[@]+"${CHANGED_MCP[@]}"}; do
        local src_file="${mcp_src_dir}/${mcp_name}"

        if [ ! -f "$src_file" ]; then
            warn "MCP config source '$src_file' not found — skipping."
            continue
        fi

        info "Merging MCP config: ${mcp_name}"

        # Read the source — it should be a JSON fragment with a single
        # MCP server definition (the full server object under the key).
        local server_key="${mcp_name%.json}"

        # Use jq to merge the new server into the existing config.
        if command -v jq &>/dev/null; then
            local tmpfile
            tmpfile="$(mktemp)"
            # The source file must have the shape: { "mcpServers": { "<name>": {...} } }
            # or be a flat fragment. We handle both.
            if jq -e '.mcpServers' "$src_file" &>/dev/null; then
                # Source already has mcpServers wrapper
                jq -s ".[0].mcpServers = (.[0].mcpServers + .[1].mcpServers) | .[0]" \
                    "$mcp_dst" "$src_file" > "$tmpfile"
            else
                # Source is a flat server object — wrap it first
                local wrapped
                wrapped="$(mktemp)"
                jq "{mcpServers: { \"${server_key}\": . }}" "$src_file" > "$wrapped"
                jq -s ".[0].mcpServers = (.[0].mcpServers + .[1].mcpServers) | .[0]" \
                    "$mcp_dst" "$wrapped" > "$tmpfile"
                rm -f "$wrapped"
            fi
            mv "$tmpfile" "$mcp_dst"
            info "  -> Merged into: $mcp_dst"
        else
            warn "  -> jq not available — cannot merge ${mcp_name}. Manually merge contents of $src_file into $mcp_dst"
            WARNINGS+=("MCP config ${mcp_name} not merged: jq missing")
        fi
    done
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

    local hooks_src="${CONST_DIR}/scripts/hooks"
    local hooks_dst="${PROJECT_ROOT}/.git/hooks"

    if [ ! -d "$hooks_dst" ]; then
        warn "No .git/hooks directory found at $hooks_dst — hooks cannot be installed."
        WARNINGS+=("No .git/hooks — run from a git repository root")
        return 1
    fi

    for hook_name in ${CHANGED_HOOKS[@]+"${CHANGED_HOOKS[@]}"}; do
        local src_file="${hooks_src}/${hook_name}"
        local dst_file="${hooks_dst}/${hook_name}"

        if [ ! -f "$src_file" ]; then
            warn "Hook source '$src_file' not found — skipping."
            continue
        fi

        info "Installing hook: ${hook_name}"
        cp "$src_file" "$dst_file"
        chmod +x "$dst_file"
        info "  -> Installed: $dst_file"
    done
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

    local installer="${CONST_DIR}/scripts/install_cli_agent_plugins.sh"
    if [ ! -f "$installer" ]; then
        warn "installer missing: $installer — action directives NOT re-wired."
        WARNINGS+=("install_cli_agent_plugins.sh missing — slash commands may be stale")
        return 1
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
# STEP 5 — Validate scripts (chmod +x, syntax check)
# ============================================================================
validate_scripts() {
    header "STEP 5: Validating scripts (chmod +x, syntax)"

    # Collect all new/modified .sh files from ALL categories
    local all_scripts=()

    # Scripts from CHANGED_SCRIPTS
    for s in ${CHANGED_SCRIPTS[@]+"${CHANGED_SCRIPTS[@]}"}; do
        local full="${CONST_DIR}/scripts/${s}"
        [ -f "$full" ] && all_scripts+=("$full")
    done

    # Hook scripts
    for h in ${CHANGED_HOOKS[@]+"${CHANGED_HOOKS[@]}"}; do
        local full="${CONST_DIR}/scripts/hooks/${h}"
        [ -f "$full" ] && all_scripts+=("$full")
    done

    # Skill scripts (validate .sh files inside skill dirs)
    for sk in ${CHANGED_SKILLS[@]+"${CHANGED_SKILLS[@]}"}; do
        local skill_dir="${CONST_DIR}/skills/${sk}"
        if [ -d "$skill_dir" ]; then
            while IFS= read -r -d '' sh_file; do
                all_scripts+=("$sh_file")
            done < <(find "$skill_dir" -name '*.sh' -type f -print0 2>/dev/null)
        fi
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
    local unique_scripts=(${all_scripts[@]+"${all_scripts[@]}"})   # all_scripts is non-empty here (guarded above)
    sort_unique_inplace unique_scripts
    IFS="$IFS_SAVE"

    local validated=0
    for script in ${unique_scripts[@]+"${unique_scripts[@]}"}; do
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
        for script in ${unique_scripts[@]+"${unique_scripts[@]}"}; do
            shellcheck -x -s bash "$script" 2>/dev/null || {
                warn "shellcheck warnings/errors in $script (non-blocking)"
            }
        done
    else
        warn "shellcheck not installed — skipping static analysis"
    fi
}

# ============================================================================
# STEP 0 — Constitution index freshness (R4-01, every run)
# ============================================================================
# constitution_index.yaml records the sha256 of the Constitution.md it was
# generated from; anchor_citations.py refuses a stale index (BLIND, exit 4). An
# amendment that lands without regenerating the index therefore blinds every
# consumer of the index. This step runs on EVERY invocation -- Constitution.md is
# not one of the propagated categories above, so gating it on detect_changes
# would let a stale index through silently. Read-only by default (a consuming
# project must not silently dirty its constitution submodule); the operator opts
# into regeneration with CONST_INDEX_REGENERATE=1.
#
# V5 N2: a fresh CHECKSUM is not enough. regenerate_if_stale.sh --check compares only
# the checksum, so a pulled tree whose groups/*.md was hand-edited (checksum untouched)
# would pass as "fresh". Once the checksum reads fresh, the
# generator's own drift check runs too -- the SAME `constitution_generate.py check` the
# commit seam (F5) and CM-CONSTITUTION-INDEX-FRESH run (~0.03 s) -- with the same
# blocking semantics as a stale index.
INDEX_STALE=0
check_constitution_index_drift() { # 0 = no drift; 1 = drift or BLIND (recorded in ERRORS + INDEX_STALE)
    local gen="${CONST_DIR}/scripts/anchors/constitution_generate.py" dout drc=0
    if [ ! -f "$gen" ]; then  # drift-check generator guard
        error "constitution index: drift check BLIND -- the generator $gen is missing"
        ERRORS+=("constitution index drift check BLIND (generator constitution_generate.py missing)")
        INDEX_STALE=1
        return 1
    fi
    # `|| drc=$?`, never `; drc=$?`: under `set -e` a failing assignment would abort the hook.
    dout="$(python3 "$gen" check --source "$CONST_DIR/Constitution.md" --groups-dir "$CONST_DIR/groups" \
        --index-out "$CONST_DIR/constitution_index.yaml" 2>&1)" || drc=$?
    if [ "$drc" -ne 0 ]; then
        error "constitution index: DRIFT -- the index/groups do not match a fresh generation of Constitution.md (generator check rc=$drc) although the checksum matches: a generated file was hand-edited"
        printf '%s\n' "$dout" | head -n 10 | sed 's/^/    /'
        error "  regenerate in the constitution checkout and commit the result: python3 $gen generate --source $CONST_DIR/Constitution.md --groups-dir $CONST_DIR/groups --index-out $CONST_DIR/constitution_index.yaml"
        ERRORS+=("constitution index/groups DRIFT from a fresh generation of Constitution.md (generator check rc=$drc)")
        INDEX_STALE=1
        return 1
    fi
    return 0
}
check_constitution_index() {
    header "STEP 0: Constitution index freshness"
    local regen="${CONST_DIR}/scripts/anchors/regenerate_if_stale.sh"
    if [ ! -f "$regen" ]; then
        error "constitution index: cannot be checked -- $regen is missing"
        ERRORS+=("constitution index freshness could not be checked ($regen missing)")
        INDEX_STALE=1
        return 0
    fi
    local out rc=0
    # `|| rc=$?`, never `; rc=$?`: under `set -e` a failing assignment would abort the hook.
    out="$(bash "$regen" --root "$CONST_DIR" --check 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
        check_constitution_index_drift || return 0
        info "constitution index: fresh -- $out"
        return 0
    fi
    if [ "$rc" -eq 1 ] && [ "${CONST_INDEX_REGENERATE:-0}" = "1" ]; then
        if out="$(bash "$regen" --root "$CONST_DIR" 2>&1)"; then
            info "constitution index: regenerated (CONST_INDEX_REGENERATE=1)"
            printf '%s\n' "$out" | sed 's/^/    /'
            warn "the constitution submodule now has uncommitted index/groups changes -- commit them there"
            WARNINGS+=("constitution index regenerated in $CONST_DIR (uncommitted)")
            return 0
        fi
        error "constitution index: regeneration FAILED"
        printf '%s\n' "$out" | sed 's/^/    /'
        ERRORS+=("constitution index regeneration failed")
        INDEX_STALE=1
        return 0
    fi
    # Report the REAL cause per exit code of regenerate_if_stale.sh --check (fail-closed in every case):
    #   1 stale | 4 BLIND (generator/source unreadable) | 75 lock not acquired | anything else unexpected.
    case "$rc" in
        1)
            error "constitution index: STALE (rc=$rc) -- $out"
            error "  anchor_citations.py will refuse this index (E_INDEX_SHA_MISMATCH). Regenerate it in the"
            error "  constitution checkout and commit the result: bash $regen --root $CONST_DIR"
            error "  (or re-run this hook with CONST_INDEX_REGENERATE=1)"
            ERRORS+=("constitution index STALE against Constitution.md")
            ;;
        4)
            error "constitution index: BLIND (rc=4) -- the freshness check could not run (generator or Constitution.md missing/unreadable): $out"
            ERRORS+=("constitution index freshness BLIND (rc=4: generator/source unreadable)")
            ;;
        75)
            error "constitution index: freshness check could not take the regeneration lock (rc=75) -- $out"
            ERRORS+=("constitution index freshness check blocked by lock (rc=75)")
            ;;
        *)
            error "constitution index: freshness check failed with unexpected rc=$rc -- $out"
            ERRORS+=("constitution index freshness check failed (unexpected rc=$rc)")
            ;;
    esac
    INDEX_STALE=1
    return 0
}

# ============================================================================
# STEP 6 — Report summary
# ============================================================================
report_summary() {
    header "SUMMARY"

    echo ""
    echo -e "  ${CYAN}Skills installed:${NC}   ${#CHANGED_SKILLS[@]}"
    for s in ${CHANGED_SKILLS[@]+"${CHANGED_SKILLS[@]}"}; do
        echo "    - $s"
    done

    echo ""
    echo -e "  ${CYAN}MCP configs merged:${NC} ${#CHANGED_MCP[@]}"
    for m in ${CHANGED_MCP[@]+"${CHANGED_MCP[@]}"}; do
        echo "    - $m"
    done

    echo ""
    echo -e "  ${CYAN}Hooks installed:${NC}    ${#CHANGED_HOOKS[@]}"
    for h in ${CHANGED_HOOKS[@]+"${CHANGED_HOOKS[@]}"}; do
        echo "    - $h"
    done

    echo ""
    echo -e "  ${CYAN}Scripts validated:${NC}  ${#CHANGED_SCRIPTS[@]}"

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Warnings (${#WARNINGS[@]}):${NC}"
        for w in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
            echo "    - $w"
        done
    fi

    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${RED}Errors (${#ERRORS[@]}):${NC}"
        for e in ${ERRORS[@]+"${ERRORS[@]}"}; do
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

    check_constitution_index
    detect_changes

    if [ "$(arr_len CHANGED_SKILLS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_MCP)" -eq 0 ] && \
       [ "$(arr_len CHANGED_HOOKS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_SCRIPTS)" -eq 0 ] && \
       [ "$(arr_len CHANGED_ACTIONS)" -eq 0 ]; then
        info "No relevant changes detected. Nothing to propagate."
        if [ "$INDEX_STALE" -ne 0 ]; then
            error "Post-update hook: the constitution index is stale (see STEP 0)."
            return 1
        fi
        return 0
    fi

    install_skills
    install_mcp_configs
    install_hooks
    install_action_plugins
    validate_scripts
    report_summary
}

main "$@"
