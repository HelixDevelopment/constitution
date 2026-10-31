#!/usr/bin/env bash
# scripts/constitution_cmd/constitution_cmd.sh -- the ONE engine behind the /constitution command
# family (bare /constitution via skills/constitution, /helix:constitution via the generated plugin
# command, generated shims for Gemini/Qwen/Codex). Release 2, workstream E2.
#
# Usage:
#   constitution_cmd.sh <subcommand> [args]        (a single string argument is split on blanks)
#   constitution_cmd.sh --args-file PATH           (same, from /tmp/constitution_args_<[a-z0-9]{8,64}>.txt the agent wrote; deleted after use)
#     status                       layout, pinned version, latest local release tag, Jev state
#     update [--check|--dry-run] [--ref REF]
#                                  delegates to scripts/update_constitution.sh; --check is the
#                                  default and nothing here ever applies an update (run the script
#                                  directly for that). The delegated script may fetch (its choice).
#     doctor                       read-only diagnosis: layout, registry row, shims, drift, skill
#                                  link, hooks, collisions with user /constitution commands
#     anchors <N>                  print the block of anchor 11.4.<N> from Constitution.md
#                                  (N = ^[0-9]{1,3}(\.[0-9]+)?$, output bounded)
#     gates [list]                 list the cm_* gates;  gates run <name|CM-NAME>  run one (timeout)
#     report|issue|bug|task|feature <text>
#                                  delegates to scripts/reporting/report_item.sh (section 11.4.202)
#     skills [list|status]         delegates to scripts/skill_activation/skill_activate.sh
#     extensions <list|info|add|update|remove|enable|disable|verify|lock|catalog|wire|unwire|doctor|validate> [args]
#     install-extension <src>      alias of: extensions add <src>
#                                  both delegate to scripts/constitution_ext/constitution_ext.sh
#     jev                          decision-layer status (jev-status.sh --no-validate)
#     release-notes                head of CHANGELOG.md
#     help
# Exit codes: 0 ok, 1 failure / not found, 2 usage or rejected argument, 3 delegated tool
#   unavailable, 124 delegated tool timed out.
# Inputs (env, names only): CONSTITUTION_CMD_GATE_TIMEOUT (1..600, default 120),
#   CONSTITUTION_CMD_USER_HOME (default $HOME; read only, used to look for user /constitution
#   commands).
# Side-effects: none of its own (doctor writes a throw-away tree under mktemp, removed with
#   safe_rm_rf). Writes happen only through delegated tools. No network of its own.
# Security: no eval; every argument is validated against an allow-list; control characters are
#   refused; delegated output is passed through a credential-shape redactor and size-bounded.
# Dependencies: bash, awk, git (optional), coreutils; scripts/lib/constitution_layout.sh.
# Cross-references: section 11.4.28 (resolver), 11.4.287 (safe delete), 11.4.202 (reporting),
#   11.4.272 (skill activation), 11.4.228 (extension lifecycle), 11.4.10 (credentials).
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_DIR="$(cd "$SELF_DIR/../.." && pwd)"
USER_HOME="${CONSTITUTION_CMD_USER_HOME:-${HOME:-}}"
LAYOUT_LIB="$CONST_DIR/scripts/lib/constitution_layout.sh"
HAVE_LAYOUT=0
if [ -f "$LAYOUT_LIB" ]; then
    # shellcheck source=/dev/null
    . "$LAYOUT_LIB" && HAVE_LAYOUT=1
fi

usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | sed '$d'; }
die()   { printf 'constitution: %s\n' "$*" >&2; }

# ---- argument intake: reject control chars; split a lone string argument on blanks ---------------
# --args-file PATH (used by the generated commands/skill): the agent writes the user's text to a file
# with its FILE-WRITE tool, so the text is never part of any shell command and no heredoc delimiter
# exists to break out of. PATH must be EXACTLY <dir>/constitution_args_<id>.txt with dir = /tmp or
# $TMPDIR (absolute, no extra components, no ".."), id = [a-z0-9]{8,64}; the verification (fd-relative
# O_NOFOLLOW open, regular file, one link, owner = caller, size cap, same-inode check) and the
# deletion of that one verified file are done by args_file_read.py. At most 8000 characters are used.
if [ "${1:-}" = "--args-file" ] && [ $# -eq 2 ]; then
    command -v python3 >/dev/null 2>&1 || { die "--args-file needs python3"; exit 3; }
    [ -f "$SELF_DIR/args_file_read.py" ] || { die "--args-file helper missing"; exit 3; }
    _line="$(python3 -I "$SELF_DIR/args_file_read.py" "$2"; _r=$?; printf x; exit "$_r")"; _rc=$?
    [ "$_rc" -eq 0 ] || { exit 2; }
    _line="${_line%x}"
    _line="${_line%$'\n'}"
    [ "${#_line}" -le 8000 ] || { die "arguments longer than 8000 characters"; exit 2; }
    set -- "$_line"
fi
for _a in "$@"; do
    case "$_a" in *[[:cntrl:]]*) die "control characters are not allowed in arguments"; exit 2 ;; esac
done
if [ $# -eq 1 ]; then
    set -f; read -r -a ARGS <<<"$1"; set +f
else
    ARGS=("$@")
fi
SUB="${ARGS[0]:-help}"
REST=("${ARGS[@]:1}")

redact() {
    sed -E \
      -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\[REDACTED PRIVATE KEY]' \
      -e 's/AIza[0-9A-Za-z_-]{30,}/[REDACTED]/g' \
      -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://[^/:@[:space:]]+):[^/@[:space:]]+@#\1:[REDACTED]@#g' \
      -e 's/(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/[REDACTED]/g' \
      -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
      -e 's/glpat-[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
      -e 's/sk-[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
      -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
      -e 's/xox[bap]-[A-Za-z0-9-]{10,}/[REDACTED]/g' \
      -e 's/([Bb]earer) [A-Za-z0-9._~+\/=-]{16,}/\1 [REDACTED]/g' \
      -e 's/([Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Aa][Pp][Ii][-_]?[Kk][Ee][Yy])([A-Za-z_]*)[[:space:]]*[=:][[:space:]]*(\"[^\"]*\"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)/\1\2=[REDACTED]/g' \
      -e 's/([Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][-_]?[Kk][Ee][Yy]) [A-Za-z0-9._~+\/=-]{12,}/\1 [REDACTED]/g' \
      -e 's/(sk_live|sk_test|pk_live|rk_live)_[A-Za-z0-9]{8,}/[REDACTED]/g'
}
tmo() { local t="$1"; shift; if command -v timeout >/dev/null 2>&1; then timeout "$t" "$@"; else "$@"; fi; }
# deleg TIMEOUT CMD ARGS... : run, redact, bound; propagate the tool's exit code.
deleg() {
    local t="$1" rc raw red; shift
    raw="$(mktemp)" && red="$(mktemp)" || { die "cannot create temp file"; return 1; }
    tmo "$t" "$@" >"$raw" 2>&1
    rc=$?
    redact <"$raw" >"$red"
    head -c 40000 "$red"
    if [ "$(wc -c <"$red")" -gt 40000 ]; then printf '\n[truncated: delegated output exceeded 40000 bytes; exit status of the tool is preserved]\n'; fi
    rm -f -- "${raw:?}" "${red:?}"
    if [ "$rc" -eq 124 ]; then die "delegated tool timed out after ${t}s"; fi
    return "$rc"
}

project_root() {   # prints the consuming project root, or CONST_DIR for a standalone checkout
    if [ "$HAVE_LAYOUT" -eq 1 ]; then
        local o; o="$(cl_owner_project_of "$CONST_DIR" 2>/dev/null)" && [ -n "$o" ] && { printf '%s\n' "$o"; return 0; }
    fi
    printf '%s\n' "$CONST_DIR"
}
git_c() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR git -C "$CONST_DIR" "$@"; }

need_tool() {      # need_tool PATH LABEL -> 0 or prints unavailable + returns 3
    [ -f "$1" ] && return 0
    die "unavailable: $2 not found at ${1#"$CONST_DIR"/}"; return 3
}

# ---- status -------------------------------------------------------------------------------------
cmd_status() {
    [ ${#REST[@]} -eq 0 ] || { die "status takes no arguments"; return 2; }
    local proj layout="unknown (constitution_layout.sh missing)" sha tag latest
    proj="$(project_root)"
    if [ "$HAVE_LAYOUT" -eq 1 ]; then
        if cl_owner_project_of "$CONST_DIR" >/dev/null 2>&1; then
            layout="$(cl_rel_path "$proj" "$CONST_DIR" 2>/dev/null)" || layout="unknown"
        else
            layout="standalone (hub checkout)"
        fi
    fi
    printf 'layout: %s\n' "$layout"
    printf 'constitution_dir: %s\n' "$CONST_DIR"
    printf 'project_root: %s\n' "$proj"
    if sha="$(git_c rev-parse --short HEAD 2>/dev/null)" && [ -n "$sha" ]; then
        tag="$(git_c describe --tags --always 2>/dev/null)"
        printf 'pinned: %s (%s)\n' "$sha" "${tag:-no tag}"
        latest="$(git_c tag -l 'helixconstitution-v*' 2>/dev/null | grep -E '^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$' | sort -V | tail -1)"
        printf 'latest_local_release_tag: %s\n' "${latest:-none}"
    else
        printf 'pinned: unknown (not a git checkout)\n'
        printf 'latest_local_release_tag: unknown\n'
    fi
    if [ -f "$CONST_DIR/scripts/jev/jev-status.sh" ]; then
        printf 'jev:\n'
        deleg 30 bash "$CONST_DIR/scripts/jev/jev-status.sh" --no-validate | sed 's/^/  /'
    else
        printf 'jev: unavailable (jev-status.sh not found)\n'
    fi
    return 0
}

# ---- update -------------------------------------------------------------------------------------
cmd_update() {
    local args=() i=0 have_mode=0 n=${#REST[@]}
    while [ $i -lt $n ]; do
        case "${REST[$i]}" in
            --check|--dry-run) have_mode=1; args+=("${REST[$i]}") ;;
            --ref)
                i=$((i+1)); [ $i -lt $n ] || { die "--ref needs a value"; return 2; }
                [[ "${REST[$i]}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] && [[ "${REST[$i]}" != *..* && "${REST[$i]}" != *//* ]] || { die "invalid --ref value"; return 2; }
                args+=(--ref "${REST[$i]}") ;;
            *) die "update accepts only --check, --dry-run, --ref REF (apply by running update_constitution.sh directly)"; return 2 ;;
        esac
        i=$((i+1))
    done
    [ "$have_mode" -eq 1 ] || args=(--check "${args[@]}")
    need_tool "$CONST_DIR/scripts/update_constitution.sh" update_constitution.sh || return 3
    ( cd "$(project_root)" && deleg 180 bash "$CONST_DIR/scripts/update_constitution.sh" "${args[@]}" )
}

# ---- anchors ------------------------------------------------------------------------------------
cmd_anchors() {
    [ ${#REST[@]} -eq 1 ] || { die "usage: anchors <N>"; return 2; }
    local id="${REST[0]}"
    [[ "$id" =~ ^[0-9]{1,3}(\.[0-9]+)?$ ]] || { die "invalid anchor id (expected N or N.M)"; return 2; }
    local f="$CONST_DIR/Constitution.md"
    [ -f "$f" ] || { die "Constitution.md not found"; return 1; }
    local out
    out="$(awk -v id="$id" 'BEGIN{p="### §11.4." id " — "; q="**§11.4." id " — "; max=120}
        { if (inb && (index($0,"### ")==1 || index($0,"## ")==1)) exit
          if (inb==2 && $0=="") exit
          if (!inb && index($0,p)==1) inb=1
          if (!inb && index($0,q)==1) inb=2
          if (inb) { n++; if (n<=max) print; else { print "[truncated: block exceeds " max " lines; read Constitution.md for the rest]"; exit } } }' "$f")"
    [ -n "$out" ] || { die "anchor 11.4.$id not found in Constitution.md"; return 1; }
    if [ "${#out}" -gt 24000 ]; then out="${out:0:24000}"$'\n[truncated: output byte limit]'; fi
    printf '%s\n' "$out" | redact
}

# ---- gates --------------------------------------------------------------------------------------
gate_list() {
    local f b
    for f in "$CONST_DIR"/scripts/gates/cm_*.sh; do
        [ -e "$f" ] || continue
        b="$(basename "$f" .sh)"
        case "$b" in *_mutation_test) continue ;; esac
        printf '%s\n' "$b"
    done | LC_ALL=C sort
}
cmd_gates() {
    local mode="${REST[0]:-list}"
    case "$mode" in
        list) [ ${#REST[@]} -le 1 ] || { die "usage: gates [list]"; return 2; }; gate_list; return 0 ;;
        run) ;;
        *) die "usage: gates [list] | gates run <name>"; return 2 ;;
    esac
    [ ${#REST[@]} -eq 2 ] || { die "usage: gates run <name>"; return 2; }
    local n="${REST[1]}"
    if [[ "$n" =~ ^CM-[A-Z0-9-]{1,100}$ ]]; then n="$(printf '%s' "$n" | tr 'A-Z-' 'a-z_')"; fi
    [[ "$n" =~ ^[a-z0-9_]{1,100}$ ]] || { die "invalid gate name"; return 2; }
    case "$n" in *_mutation_test) die "mutation tests are not run from here"; return 2 ;; esac
    local gdir="$CONST_DIR/scripts/gates" f real rdir
    f="$gdir/$n.sh"
    [ -f "$f" ] || { die "gate not found: $n"; return 1; }
    real="$(realpath -e -- "$f" 2>/dev/null)" && rdir="$(realpath -e -- "$gdir" 2>/dev/null)" || { die "cannot resolve gate path"; return 2; }
    case "$real" in "$rdir"/*) ;; *) die "gate resolves outside scripts/gates; refused"; return 2 ;; esac
    local t="${CONSTITUTION_CMD_GATE_TIMEOUT:-120}"
    [[ "$t" =~ ^[0-9]{1,3}$ ]] && [ "$t" -ge 1 ] && [ "$t" -le 600 ] || { die "CONSTITUTION_CMD_GATE_TIMEOUT must be 1..600"; return 2; }
    ( cd "$(project_root)" && deleg "$t" bash "$real" )
}

# ---- report family ------------------------------------------------------------------------------
cmd_report() {   # $1 = kind word
    local word="$1" text
    [ ${#REST[@]} -ge 1 ] || { die "usage: $word <text>"; return 2; }
    text="${REST[*]}"
    [ "${#text}" -le 4000 ] || { die "report text longer than 4000 characters"; return 2; }
    need_tool "$CONST_DIR/scripts/reporting/report_item.sh" report_item.sh || return 3
    local a
    case "$word" in
        bug)   a=(--kind bug) ;;
        task)  a=(--kind task) ;;
        feature) a=(--kind issue --type Feature) ;;
        *)     a=(--kind issue --autonomous) ;;
    esac
    ( cd "$(project_root)" && deleg 120 bash "$CONST_DIR/scripts/reporting/report_item.sh" "${a[@]}" --report "$text" )
}

# ---- skills / extensions / jev / release notes --------------------------------------------------
cmd_skills() {
    local m="${REST[0]:-list}"
    case "$m" in list|status) ;; *) die "skills accepts: list | status"; return 2 ;; esac
    [ ${#REST[@]} -le 1 ] || { die "skills takes one argument"; return 2; }
    need_tool "$CONST_DIR/scripts/skill_activation/skill_activate.sh" skill_activate.sh || return 3
    deleg 60 bash "$CONST_DIR/scripts/skill_activation/skill_activate.sh" "$m" "$(project_root)"
}
cmd_extensions() {
    local sub="${REST[0]:-}"
    case "$sub" in
        list|info|add|update|remove|enable|disable|verify|lock|catalog|wire|unwire|doctor|validate) ;;
        *) die "extensions subcommands: list info add update remove enable disable verify lock catalog wire unwire doctor validate"; return 2 ;;
    esac
    local a
    local allow
    case "$sub" in
        add) allow=" --json --dry-run --dev --sha --sha256 " ;;
        *)   allow=" --json --dry-run " ;;
    esac
    for a in "${REST[@]:1}"; do
        case "$a" in
            --*) case "$allow" in *" $a "*) ;; *) die "rejected extension option: $(printf '%.30s' "$a" | tr -c 'A-Za-z0-9._-' '?')"; return 2 ;; esac ;;
        esac
        [[ "$a" =~ ^(--[a-z][a-z-]{0,30}|[A-Za-z0-9._/:@=+,~-]{1,300})$ ]] || { die "rejected extension argument"; return 2; }
        case "/$a/" in */../*) die "rejected extension argument (parent-directory segment)"; return 2 ;; esac
    done
    if [ ! -f "$CONST_DIR/scripts/constitution_ext/constitution_ext.sh" ]; then
        die "extensions engine not installed"; return 3
    fi
    deleg 300 bash "$CONST_DIR/scripts/constitution_ext/constitution_ext.sh" --project-root "$(project_root)" "${REST[@]}"
}
cmd_jev() {
    [ ${#REST[@]} -eq 0 ] || { die "jev takes no arguments"; return 2; }
    need_tool "$CONST_DIR/scripts/jev/jev-status.sh" jev-status.sh || return 3
    deleg 60 bash "$CONST_DIR/scripts/jev/jev-status.sh" --no-validate
}
cmd_release_notes() {
    [ ${#REST[@]} -eq 0 ] || { die "release-notes takes no arguments"; return 2; }
    [ -f "$CONST_DIR/CHANGELOG.md" ] || { die "CHANGELOG.md not found"; return 1; }
    head -n 60 "$CONST_DIR/CHANGELOG.md" | redact
}

# ---- doctor -------------------------------------------------------------------------------------
DOC_FAIL=0
d_ok()   { printf 'OK %s %s\n' "$1" "$2"; }
d_warn() { printf 'WARN %s %s\n' "$1" "$2"; }
d_fail() { printf 'FAIL %s %s\n' "$1" "$2"; DOC_FAIL=1; }
cmd_doctor() {
    [ ${#REST[@]} -eq 0 ] || { die "doctor takes no arguments"; return 2; }
    local proj; proj="$(project_root)"
    if [ "$HAVE_LAYOUT" -eq 1 ]; then
        if cl_is_constitution_dir "$CONST_DIR"; then d_ok layout "constitution dir valid, project_root=$proj"; else d_fail layout "not a constitution dir: $CONST_DIR"; fi
    else
        d_fail layout-lib "scripts/lib/constitution_layout.sh missing"
    fi
    [ -f "$CONST_DIR/Constitution.md" ] && d_ok constitution-md present || d_fail constitution-md missing
    if grep -q '^  - name: CONSTITUTION$' "$CONST_DIR/actions/registry.yaml" 2>/dev/null; then d_ok registry "CONSTITUTION row present"; else d_fail registry "CONSTITUTION row missing in actions/registry.yaml"; fi
    if [ -f "$CONST_DIR/plugins/helix/commands/constitution.md" ]; then d_ok shim-plugin "plugins/helix/commands/constitution.md"; else d_fail shim-plugin "plugins/helix/commands/constitution.md missing (run scripts/generate_agent_prefix_commands.sh)"; fi
    # drift: regenerate into a throw-away tree and compare file by file
    if [ -f "$CONST_DIR/scripts/generate_agent_prefix_commands.sh" ] && [ -f "$CONST_DIR/scripts/lib/safe_rm.sh" ]; then
        # shellcheck source=/dev/null
        . "$CONST_DIR/scripts/lib/safe_rm.sh"
        local tmp; tmp="$(mktemp -d)" && [ -n "$tmp" ] && [ -d "$tmp" ] || { d_warn drift "cannot create temp dir"; tmp=""; }
        if [ -n "$tmp" ]; then
            if HELIX_ACTION_OUT_ROOT="$tmp" bash "$CONST_DIR/scripts/generate_agent_prefix_commands.sh" >/dev/null 2>&1; then
                local f rel diffs=0 first=""
                while IFS= read -r f; do
                    rel="${f#"$tmp"/}"
                    if ! cmp -s "$f" "$CONST_DIR/$rel"; then diffs=$((diffs+1)); [ -n "$first" ] || first="$rel"; fi
                done < <(find "$tmp" -type f | LC_ALL=C sort)
                if [ "$diffs" -eq 0 ]; then d_ok drift "generated shims match the registry"; else d_warn drift "$diffs generated file(s) differ or are missing (first: $first); run scripts/generate_agent_prefix_commands.sh"; fi
            else
                d_warn drift "generator failed; drift not checked"
            fi
            safe_rm_rf "$tmp"
        fi
    else
        d_warn drift "generator or safe_rm.sh missing; drift not checked"
    fi
    # skill link for bare /constitution in Claude Code
    local link="$proj/.claude/skills/constitution"
    if [ -e "$link" ]; then
        if cl_same_dir "$link" "$CONST_DIR/skills/constitution" 2>/dev/null; then d_ok skills-link ".claude/skills/constitution -> this checkout"; else d_warn skills-link ".claude/skills/constitution exists but is not this checkout's skills/constitution"; fi
    else
        d_warn skills-link ".claude/skills/constitution missing: bare /constitution unavailable (use /helix:constitution)"
    fi
    # git hooks
    if [ "$HAVE_LAYOUT" -eq 1 ]; then
        local hd; hd="$(cl_git_hooks_dir "$proj" 2>/dev/null)"
        if [ -n "$hd" ] && [ -e "$hd/post-merge" ]; then d_ok hooks "post-merge present"; else d_warn hooks "post-merge hook not installed"; fi
    fi
    # name collisions with user-defined /constitution commands
    local c found=0
    for c in "$USER_HOME/.claude/commands/constitution.md" "$proj/.claude/commands/constitution.md" \
             "$proj/.opencode/commands/constitution.md" "$USER_HOME/.config/opencode/command/constitution.md" \
             "$USER_HOME/.gemini/commands/constitution.toml" "$proj/.gemini/commands/constitution.toml" \
             "$USER_HOME/.qwen/commands/constitution.toml" "$proj/.qwen/commands/constitution.toml"; do
        [ -f "$c" ] || continue
        if grep -q 'Generated by scripts/generate_agent_prefix_commands.sh' "$c" 2>/dev/null; then d_ok collision "ours: $c"; else d_warn collision "user command shadows/collides: $c"; found=1; fi
    done
    [ "$found" -eq 1 ] || d_ok collision "no user /constitution command collisions found"
    # delegated tools
    local t
    for t in update_constitution.sh reporting/report_item.sh skill_activation/skill_activate.sh constitution_ext/constitution_ext.sh; do
        if [ -f "$CONST_DIR/scripts/$t" ]; then d_ok tool "$t"; else d_warn tool "$t not installed (its subcommand reports unavailable)"; fi
    done
    return "$DOC_FAIL"
}

# ---- dispatch -----------------------------------------------------------------------------------
case "$SUB" in
    help|-h|--help) [ ${#REST[@]} -eq 0 ] || { die "help takes no arguments"; usage >&2; exit 2; }; usage; exit 0 ;;
    status)        cmd_status; exit $? ;;
    update)        cmd_update; exit $? ;;
    doctor)        cmd_doctor; exit $? ;;
    anchors)       cmd_anchors; exit $? ;;
    gates)         cmd_gates; exit $? ;;
    report|issue|bug|task|feature) cmd_report "$SUB"; exit $? ;;
    skills)        cmd_skills; exit $? ;;
    extensions)    cmd_extensions; exit $? ;;
    install-extension) REST=(add "${REST[@]}"); cmd_extensions; exit $? ;;
    jev)           cmd_jev; exit $? ;;
    release-notes) cmd_release_notes; exit $? ;;
    *) die "unknown subcommand: $(printf '%.40s' "$SUB" | tr -c 'A-Za-z0-9._-' '?')"; usage >&2; exit 2 ;;
esac
