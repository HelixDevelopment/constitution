#!/usr/bin/env bash
# =============================================================================
# multitrack_cwd_hook.sh
#
# Purpose:
#   The thin, project-specific adapter that the (generic) Claude-Toolkit `cma_run`
#   wrapper invokes on every alias session start to learn WHICH directory the
#   alias should work in. Given the alias label (claude1/claude2/claude3) it
#   prints the alias's bound track worktree (/mnt/trackN/<project>) on stdout,
#   or prints NOTHING when there is no valid worktree — in which case `cma_run`
#   leaves the session in the shared /home checkout (safe fallback).
#
#   This is the "hook" half of the permanent multi-track switch. The toolkit
#   knows nothing about tracks/<project>; it only `cd`s into whatever real
#   directory this hook prints (see cma_run's CMA_CWD_HOOK integration).
#
#   Contract with the toolkit (MUST stay stable):
#     * invoked as:   claude-cwd-hook <alias-label>
#     * on success:   print ONE absolute directory path on stdout, exit 0
#     * otherwise:    print nothing (any exit) -> toolkit stays on /home
#     * MUST be fast, read-only, and NEVER hang/fail a session.
#
# Usage:
#   multitrack_cwd_hook.sh <alias>          # hook mode: print worktree or nothing
#   multitrack_cwd_hook.sh --install        # symlink ~/.local/bin/claude-cwd-hook -> here
#   multitrack_cwd_hook.sh --uninstall      # remove that symlink (only if ours)
#   multitrack_cwd_hook.sh --status         # show symlink + per-alias resolution
#   multitrack_cwd_hook.sh --consumer-root [alias]
#                                           # diagnostic: print the resolved
#                                           # consumer project root + WHY
#   multitrack_cwd_hook.sh -h | --help
#
# Inputs (env):
#   MULTITRACK_DISABLE=1   Escape hatch: print nothing, exit 0 (switch off).
#   CMA_CWD_HOOK           (read by the toolkit) path the toolkit calls; --install
#                          points ~/.local/bin/claude-cwd-hook at this script.
#   MT_REPO_ROOT           Explicit consumer-project-root pin. Highest precedence
#                          (see the CONSUMER-ROOT RESOLUTION block below).
#   MT_CONSUMER_ROOTS      Path to the operator-owned alias->consumer-root binding
#                          file (default
#                          ${XDG_CONFIG_HOME:-$HOME/.config}/multitrack/consumer_roots.conf).
#                          Consumer/operator DATA — never a project literal here.
#   (all resolver env vars are honored, e.g. MT_CONFIG_DIR / MT_ALIAS_DIR)
#   --- §11.4.119 checkout-owner advisory check (ATM-833) ---
#   MT_CHECKOUT_OWNER_POLICY   off | warn | enforce. Unset/unrecognised => the
#                              PERMISSIVE default `warn` (see below). `enforce`
#                              withholds the worktree on a contended checkout so
#                              the session stays where it is (it NEVER refuses a
#                              session — the toolkit simply does not `cd`).
#   MULTITRACK_AUTOMATED=1     An automated launcher DECLARING itself; selects
#                              `enforce` when no explicit policy is set. A human
#                              never sets it, so an interactive session is never
#                              silently redirected (§11.4.201 real-condition).
#   MT_CHECKOUT_OWNER_LOCK     Explicit path to the checkout-owner-lock tool
#                              (consumer DATA / testability). Otherwise resolved
#                              as a sibling of this script, then as
#                              <resolved-worktree>/$MT_CHECKOUT_OWNER_LOCK_RELPATH.
#   MT_CHECKOUT_OWNER_LOCK_RELPATH  default scripts/multitrack/multitrack_checkout_owner_lock.sh
#   MT_CHECKOUT_OWNER_LOG      Append-only advisory log (default
#                              ${XDG_RUNTIME_DIR:-/tmp}/multitrack_checkout_owner_guard.log).
#   EVERY failure path of this check FAILS OPEN (tool absent / unreadable
#   registry / unwritable lock dir / crash / timeout => pre-existing behaviour).
#
# Outputs: stdout = one worktree path (hook mode) or human text (--status).
# Side-effects: --install/--uninstall create/remove ONE symlink under ~/.local/bin.
#               Hook mode: relays the resolver's worktree on stdout AND fires THREE
#               BEST-EFFORT, NON-FATAL, FULLY-DETACHED side-effects for the alias's
#               resolved track (all with all fds -> /dev/null before `&`, so NONE
#               can corrupt the single-line stdout NOR block the toolkit's
#               `cd "$(hook ...)"` substitution):
#                 (a) §4.1 bind-on-start (PWU-3) — `orchestrator bind --alias A
#                     --track T`;
#                 (b) §4.2(C) monitor-auto-start (PWU-5) — one detached
#                     `multitrack_fallback_monitor.sh --daemon` per alias, tailing
#                     the alias's newest transcript for a rate-limit signature
#                     (idempotent: one monitor per alias/track);
#                 (c) §11.4.35 constitution auto-sync — one detached
#                     `multitrack_constitution_sync.sh for-alias A` that ancestor-
#                     guarded fast-forwards the worktree's constitution submodule
#                     to latest <remote>/main (ff-only, WIP-preserving, never
#                     force/reset — "always up to date with main, Everywhere!").
#               The conductor alias resolves to no track and is therefore NEVER
#               bound, NEVER monitored, and NEVER synced (same no-track path as
#               role:main — its /home checkout is kept current by its own workflow).
#
# Dependencies: bash; multitrack_resolve_worktree.sh (sibling, `resolve`+`track`);
#               multitrack_alias_orchestrator.sh (sibling, `bind`);
#               multitrack_fallback_monitor.sh (sibling, `--daemon`, PWU-5);
#               pgrep (optional idempotency guard), tail (in the monitor).
#
# Cross-references:
#   scripts/multitrack/multitrack_resolve_worktree.sh   (the resolver it wraps)
#   scripts/multitrack/multitrack_alias_orchestrator.sh (bind-on-start target)
#   scripts/multitrack/multitrack_fallback_monitor.sh   (monitor-auto-start target)
#   scripts/multitrack/multitrack_constitution_sync.sh  (constitution auto-sync target, §11.4.35)
#   scripts/multitrack/multitrack-up                    (session launcher, PWU-5)
#   claude_toolkit scripts/lib.sh  (cma_run CMA_CWD_HOOK integration)
#   docs/guides/MULTITRACK_PERMANENT_SWITCH.md
#   docs/research/universal_auto_multitrack_20260704/DESIGN.md §3.2 / §4.2(C)
#   §11.4.28 decoupling (toolkit stays generic; <project> logic lives here)
#   §11.4.177 auto bind-on-start + monitor-auto-start + auto-conductor
# =============================================================================

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
_cwh_self() {
    local src="${BASH_SOURCE[0]:-$0}"
    while [ -h "$src" ]; do
        local dir; dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
    done
    # Absolutize: a relative invocation (e.g. `bash multitrack_cwd_hook.sh`)
    # leaves $src relative, which would make --install write a broken symlink.
    local d; d="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    printf '%s/%s' "$d" "$(basename "$src")"
}

CWH_SELF="$(_cwh_self)"
CWH_DIR="$(cd -P "$(dirname "$CWH_SELF")" >/dev/null 2>&1 && pwd)"
CWH_RESOLVER="$CWH_DIR/multitrack_resolve_worktree.sh"
CWH_LINK="${CMA_CWD_HOOK:-$HOME/.local/bin/claude-cwd-hook}"

# =============================================================================
# §11.4.177 CONSUMER-ROOT RESOLUTION — which consumer project is this hook for?
# -----------------------------------------------------------------------------
# THE DEFECT THIS CLOSES. Every other engine entry point runs from INSIDE a
# consumer checkout, so multitrack_config.sh:mt_repo_root's SELF-LOCATION
# (<engine>/../.. carrying config/multitrack, else the git superproject) is the
# right answer. This hook is the ONE entry point that runs from OUTSIDE any
# checkout — the toolkit invokes it only when cwd is NOT a git repo — and it is
# customarily installed ONCE on a shared PATH. Self-location therefore answers a
# question it cannot know: it returns whichever checkout physically holds the
# engine, SHADOWING every sibling consumer on the host that ships its own
# config/multitrack/ (the §11.4.177 re-coupling: one global entry point wired to
# one hardcoded project).
#
# PRECEDENCE (first hit wins; each step is a REAL, checkable condition —
# §11.4.201, never a guess):
#   1. MT_REPO_ROOT              explicit pin (operator / launcher / test seam)
#   2. invocation context        nearest ancestor of $PWD carrying
#                                config/multitrack/  (§11.4.177 "take the target
#                                from the invocation directory")
#   3. operator binding file     alias key, else `default` key, from a file
#                                OUTSIDE every checkout. HONEST BOUNDARY
#                                (§11.4.6): when the hook fires there is by
#                                construction NO cwd project context, so the
#                                alias->consumer mapping is host policy that
#                                nothing in-tree can derive. This minimal
#                                operator-owned artifact is the only way to
#                                satisfy §11.4.177 (project-agnostic tooling)
#                                and §11.4.187 (automatic, out-of-the-box)
#                                simultaneously.
#   4. NOTHING RESOLVED          export nothing -> the resolver falls back to its
#                                unchanged self-location behaviour. This is the
#                                load-bearing back-compat guarantee: a host with
#                                no binding file and no cwd context behaves
#                                EXACTLY as before this block existed, so no
#                                existing consumer of the engine can break.
#
# A candidate is accepted ONLY if it really carries config/multitrack/ — a stale
# or mistyped binding is REPORTED and IGNORED, never silently trusted (§11.4.6),
# and never fails the session (§11.4.187: the hook must never break a launch).
# NOTHING here writes to stdout: fd 1 is the toolkit's `cd` target.
# =============================================================================

# Operator-owned binding file. Consumer/operator DATA — this engine carries NO
# project literal (§11.4.28(B) / §11.4.177).
CWH_CONSUMER_ROOTS="${MT_CONSUMER_ROOTS:-${XDG_CONFIG_HOME:-$HOME/.config}/multitrack/consumer_roots.conf}"

# A directory is a consumer project root IFF it carries config/multitrack/ —
# the same marker mt_repo_root uses, so "consumer root" means one thing engine-wide.
_cwh_is_consumer_root() { [ -n "${1:-}" ] && [ -d "$1/config/multitrack" ]; }

# Diagnostic note — stderr + the advisory log ONLY, NEVER stdout.
_cwh_root_note() {
    { printf 'multitrack: %s\n' "$1" >&2; } 2>/dev/null || true
    { printf '%s multitrack-consumer-root: %s\n' \
        "$(date -u +%FT%TZ 2>/dev/null || echo unknown-time)" "$1" \
        >>"${MT_CHECKOUT_OWNER_LOG:-${XDG_RUNTIME_DIR:-/tmp}/multitrack_checkout_owner_guard.log}"; } 2>/dev/null || true
    return 0
}

# Step 2 — nearest ancestor of $PWD that is a consumer root.
_cwh_root_from_cwd() {
    local d
    d="$(pwd -P 2>/dev/null)" || return 1
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        if _cwh_is_consumer_root "$d"; then printf '%s' "$d"; return 0; fi
        d="$(dirname "$d" 2>/dev/null)" || return 1
    done
    if _cwh_is_consumer_root "/"; then printf '%s' "/"; return 0; fi
    return 1
}

# Step 3 — operator binding file. Format (project-agnostic, PARSED not sourced,
# so a typo or a hostile line can never execute):
#     # comment
#     default = /abs/path/to/consumer
#     <alias> = /abs/path/to/other/consumer
# The alias key wins over `default`; the LAST assignment of a given key wins.
_cwh_root_from_binding() {
    local alias="${1:-}" hit
    [ -r "$CWH_CONSUMER_ROOTS" ] || return 1
    hit="$(awk -v want="$alias" '
        { sub(/[ \t]*#.*$/, "") }                       # strip comments
        {
            i = index($0, "=");  if (i == 0) next
            k = substr($0, 1, i-1); v = substr($0, i+1)
            gsub(/^[ \t]+|[ \t]+$/, "", k)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            if (k == "" || v == "") next
            if (want != "" && k == want) a = v
            else if (k == "default")     d = v
        }
        END { if (a != "") print a; else if (d != "") print d }
    ' "$CWH_CONSUMER_ROOTS" 2>/dev/null)"
    [ -n "$hit" ] || return 1
    printf '%s' "$hit"
}

# Resolve the consumer root for <alias>.
#
# Emits ONE line, TAB-separated:  <reason><TAB><root>
# On "no opinion" the root field is EMPTY and the exit code is 1, so the caller
# leaves the resolver's own self-location behaviour completely intact.
#
# WHY a single packed line rather than a variable: every caller reads this via
# command substitution, which runs a SUBSHELL — a global assigned in here would
# be silently discarded, and the reason would read "unknown" on every refusal
# (§11.4.201(5): a guard MUST be able to print the evidence behind its decision).
_cwh_consumer_root() {
    local alias="${1:-}" c
    if [ -n "${MT_REPO_ROOT:-}" ]; then
        printf 'MT_REPO_ROOT env pin\t%s' "$MT_REPO_ROOT"; return 0
    fi
    if c="$(_cwh_root_from_cwd)" && [ -n "$c" ]; then
        printf 'invocation context (nearest ancestor of $PWD carrying config/multitrack)\t%s' "$c"
        return 0
    fi
    if c="$(_cwh_root_from_binding "$alias")" && [ -n "$c" ]; then
        if _cwh_is_consumer_root "$c"; then
            printf 'operator binding %s\t%s' "$CWH_CONSUMER_ROOTS" "$c"; return 0
        fi
        _cwh_root_note "binding in $CWH_CONSUMER_ROOTS names '$c', which carries no config/multitrack — IGNORED (§11.4.6)"
        printf 'binding named a path with no config/multitrack — IGNORED; resolver keeps its self-location default\t'
        return 1
    fi
    printf 'unresolved (no env pin, no cwd context, no operator binding) — resolver keeps its self-location default\t'
    return 1
}

# Export the resolved root so the resolver's existing operator-pin clause picks
# it up. No resolution -> export NOTHING (unchanged legacy behaviour).
_cwh_bind_consumer_root() {
    local out root
    out="$(_cwh_consumer_root "${1:-}")"
    root="${out#*$'\t'}"
    if [ -n "$root" ]; then MT_REPO_ROOT="$root"; export MT_REPO_ROOT; fi
    return 0
}

# =============================================================================
# §11.4.119 CHECKOUT-OWNER ADVISORY CHECK (ATM-833) — the cwd-hook half.
# -----------------------------------------------------------------------------
# The supervisor launch path takes a canonical, checkout-keyed owner lock; this
# (the toolkit-alias launch path) previously had NO lock / claim / ownership
# logic at all, so an alias session could join a checkout a supervisor already
# owned => two `claude` writers on ONE git index (§9.2 data-safety risk).
#
# ABSOLUTE CONSTRAINT — this code MUST NEVER prevent a session from starting.
#   * The toolkit consumes this hook as `cd "$(hook <alias>)" 2>/dev/null || true`
#     and only cd's when the printed path is a real directory. Printing NOTHING
#     therefore leaves the session on its current dir (/home) — the session
#     ALWAYS starts. There is no code path here that can refuse a shell.
#   * The only real hazard is HANGING (command substitution waits for us), so
#     every probe is NON-BLOCKING and, where `timeout` exists, hard-bounded.
#   * EVERY error path FAILS OPEN — unresolvable tool, unreadable registry,
#     unwritable lock dir, unexpected exit code, timeout => behave exactly as
#     before this section existed (print the worktree, no warning).
#
# POLICY (three-valued; see _cwh_owner_policy):
#   warn    (DEFAULT) — print the worktree as always, but emit a loud, evidence-
#                       bearing WARNING and skip the contended git-WRITE side
#                       effect (constitution auto-sync). An interactive human is
#                       NEVER silently redirected.
#   enforce           — additionally print NOTHING (session stays home) so the
#                       automated launcher does not become a 2nd writer.
#                       Selected ONLY by an explicit policy value or by an
#                       automated launcher DECLARING itself (§11.4.201: a real
#                       declared condition, never a guessed interactive-vs-
#                       automated heuristic).
#   off               — the check is skipped entirely (pre-existing behaviour).
#
# §11.4.177: no project literal here. The lock tool is located from the
# invocation context (env override -> sibling in this engine dir -> a path
# relative to the RESOLVED worktree), never from a hardcoded project path.
# =============================================================================

CWH_OWNER_TOOL_BASENAME="multitrack_checkout_owner_lock.sh"
# Consumer-overridable relative location, used only as the last resort and only
# relative to the alias's own resolved worktree (invocation context, §11.4.177).
CWH_OWNER_TOOL_RELPATH="${MT_CHECKOUT_OWNER_LOCK_RELPATH:-scripts/multitrack/$CWH_OWNER_TOOL_BASENAME}"

# Resolve the checkout-owner-lock tool, or print nothing when unavailable.
# Order: explicit env (testability / consumer DATA) -> sibling of this engine
# script -> <resolved-worktree>/<relpath>. Absent => the caller fails open.
_cwh_owner_tool() {
    local wt="${1:-}" cand
    cand="${MT_CHECKOUT_OWNER_LOCK:-}"
    if [ -n "$cand" ] && [ -r "$cand" ]; then printf '%s' "$cand"; return 0; fi
    cand="$CWH_DIR/$CWH_OWNER_TOOL_BASENAME"
    if [ -r "$cand" ]; then printf '%s' "$cand"; return 0; fi
    if [ -n "$wt" ]; then
        cand="$wt/$CWH_OWNER_TOOL_RELPATH"
        if [ -r "$cand" ]; then printf '%s' "$cand"; return 0; fi
    fi
    return 1
}

# Three-valued policy. Unrecognised values fall back to the PERMISSIVE default
# (`warn`) — a typo in an env var must never silently start refusing worktrees.
_cwh_owner_policy() {
    case "${MT_CHECKOUT_OWNER_POLICY:-}" in
        off)     printf 'off' ;    return 0 ;;
        warn)    printf 'warn' ;   return 0 ;;
        enforce) printf 'enforce'; return 0 ;;
    esac
    # An automated launcher DECLARES itself; a human never sets this (§11.4.201
    # — a declared condition, not a proxy signal such as tty-ness, which cannot
    # separate a tmux-launched worker from a human in tmux).
    [ "${MULTITRACK_AUTOMATED:-0}" = "1" ] && { printf 'enforce'; return 0; }
    printf 'warn'
}

# Operator-visible notification. cma_run captures our stdout as the cd target
# and DISCARDS our stderr (`2>/dev/null`), so a warning written only to stderr
# would be invisible. /dev/tty bypasses that redirection; every write is
# best-effort and non-fatal, and NOTHING is ever written to stdout.
_cwh_owner_notify() {
    local msg="$1" logf
    # NOTE the redirection ORDER: `2>/dev/null` FIRST so that if opening
    # /dev/tty fails (no controlling terminal — nohup/cron/CI), the shell's own
    # "cannot open" diagnostic is already swallowed. Never touches stdout.
    { printf '%s\n' "$msg" 2>/dev/null >/dev/tty; } 2>/dev/null || true
    { printf '%s\n' "$msg" >&2; } 2>/dev/null || true
    logf="${MT_CHECKOUT_OWNER_LOG:-${XDG_RUNTIME_DIR:-/tmp}/multitrack_checkout_owner_guard.log}"
    { printf '%s %s\n' "$(date -u +%FT%TZ 2>/dev/null || echo unknown-time)" "$msg" \
        >>"$logf"; } 2>/dev/null || true
    return 0
}

# Probe ownership of <worktree>. Prints the tool's resolved evidence line on
# stdout when (and only when) the checkout is PROVABLY owned by another live
# agent; returns 3 in that case, 0 otherwise.
#
# FAIL-OPEN by construction: any outcome that is not an unambiguous exit-3
# "BUSY" (tool absent, non-executable, usage error, crash, timeout, empty
# checkout) returns 0 = treat as free.
_cwh_owner_busy() {
    local wt="${1:-}" tool out rc
    [ -n "$wt" ] || return 0
    tool="$(_cwh_owner_tool "$wt" 2>/dev/null)" || return 0
    [ -n "$tool" ] || return 0
    # Non-blocking by contract (the tool's `check` uses `flock -n`); `timeout`
    # is defence-in-depth against a wedged filesystem on the realpath call.
    if command -v timeout >/dev/null 2>&1; then
        # SIGTTIN/SIGTTOU ignored inside the substitution only (uutils timeout does not ignore them itself)
        out="$(trap '' TTIN TTOU; timeout 5 bash "$tool" check "$wt" 2>/dev/null)"; rc=$?
    else
        out="$(bash "$tool" check "$wt" 2>/dev/null)"; rc=$?
    fi
    [ "$rc" -eq 3 ] || return 0          # 0=FREE, 2=usage, 124=timeout, else -> FAIL OPEN
    printf '%s' "$out"
    return 3
}

# Hook mode: print the alias's worktree (or nothing). Never fail a session.
_cwh_hook() {
    local alias="$1" wt policy evidence contended=0
    [ -n "$alias" ] || return 0
    [ "${MULTITRACK_DISABLE:-0}" = "1" ] && return 0
    [ -r "$CWH_RESOLVER" ] || return 0
    # 0) §11.4.177 consumer-root resolution — decide WHICH consumer project this
    #    invocation is for BEFORE delegating, and export it so the resolver's
    #    existing MT_REPO_ROOT pin honours it. Without this, a globally-installed
    #    hook answers every alias with whichever checkout physically holds the
    #    engine. Resolving to nothing is a clean no-op (unchanged behaviour).
    #    Exported here so the detached bind / monitor / constitution-sync side
    #    effects below inherit the SAME consumer — never a split-brain where the
    #    printed worktree and the bind/sync target disagree.
    _cwh_bind_consumer_root "$alias"
    # 1) Resolve the worktree (unchanged, load-bearing: cma_run cd's into
    #    whatever single dir this prints). The resolver guards mount+worktree
    #    validity and prints nothing on failure; errors -> fall back /home.
    wt="$(bash "$CWH_RESOLVER" resolve "$alias" 2>/dev/null || true)"
    # 1b) §11.4.119 checkout-owner advisory check (ATM-833). Runs ONLY when a
    #     real worktree resolved (the conductor resolves to none => no check),
    #     and CANNOT prevent the session from starting — see the block comment
    #     above. `enforce` merely withholds the worktree so the session stays
    #     on /home instead of becoming a 2nd writer in one git index.
    policy="$(_cwh_owner_policy)"
    if [ -n "$wt" ] && [ "$policy" != "off" ]; then
        if evidence="$(_cwh_owner_busy "$wt")"; then
            : # free (or unresolvable => fail open)
        else
            contended=1
            _cwh_owner_notify "multitrack: checkout already owned by another live agent — ${evidence:-no evidence resolved} (alias=$alias policy=$policy) [§11.4.119]"
        fi
    fi
    if [ "$contended" = "1" ] && [ "$policy" = "enforce" ]; then
        _cwh_owner_notify "multitrack: staying on the current directory instead of joining a contended checkout (set MT_CHECKOUT_OWNER_POLICY=off to override)"
        return 0                          # print NOTHING -> session starts where it is
    fi
    [ -n "$wt" ] && printf '%s\n' "$wt"
    # 2) §4.1 bind-on-start (PWU-3): engage/refresh the alias<->track lease so the
    #    (existing) fallback machinery tracks the alias<->track binding. BEST-EFFORT,
    #    NON-FATAL, FULLY DETACHED — see _cwh_bind_start for why this can NEVER
    #    block, slow, or fail shell startup. Only a REAL track binds (the conductor
    #    resolves to no track, so it is never bound).
    _cwh_bind_start "$alias"
    # 3) §4.2(C) + §3.2-step-4 monitor-auto-start (PWU-5): spawn ONE per-alias
    #    rate-limit transcript monitor for this session, FULLY DETACHED with the
    #    IDENTICAL never-block/never-corrupt guard the bind above uses (all fds ->
    #    /dev/null BEFORE `&`, so it can neither corrupt this hook's single-line
    #    stdout contract nor block cma_run's `cd "$(hook ...)"` substitution). Only
    #    a REAL track gets a monitor (the conductor resolves to no track -> no
    #    monitor, mirroring no-bind). Idempotent (never a 2nd monitor per alias).
    _cwh_monitor_start "$alias"
    # 4) §11.4.35 constitution auto-sync (operator mandate 2026-07-04: "Constitution
    #    Submodule MUST BE ALWAYS up to date (fetch and pull all) with the main
    #    branch! Everywhere!"). On every track activation, fast-forward the
    #    activated worktree's constitution submodule to latest <remote>/main.
    #    FULLY DETACHED with the IDENTICAL never-block/never-corrupt guard used by
    #    the bind + monitor above (all fds -> /dev/null BEFORE `&`), because the
    #    fetch is a NETWORK op that MUST NOT delay cma_run's `cd "$(hook ...)"`
    #    substitution. The sync is ancestor-guarded, fast-forward-ONLY, WIP-
    #    preserving, and NEVER force/reset/rewind (see multitrack_constitution_sync.sh).
    #    Only a REAL track (a resolved worktree) is synced — the conductor resolves
    #    to no worktree (NOOP), its /home checkout kept current by its own workflow.
    #    §11.4.119/§11.4.84 (ATM-833): SKIPPED when the checkout is provably owned
    #    by another live agent. This sync is a git WRITE (fetch + ff-merge) INSIDE
    #    the contended worktree — running it while another agent commits there is
    #    a real write-race. Skipping is the reversible-safe choice (§11.4.101): a
    #    not-yet-synced submodule is the status quo, a raced index is not. Applies
    #    in `warn` mode too (defence in depth), since `warn` still hands the
    #    worktree over.
    if [ "$contended" = "1" ]; then
        _cwh_owner_notify "multitrack: skipping constitution auto-sync — contended checkout (git write-race guard, §11.4.119)"
    else
        _cwh_constitution_sync_start "$alias"
    fi
    return 0
}

# Fire the bind FULLY DETACHED so it can never harm shell startup. Two dangers,
# both eliminated by redirecting ALL of the subshell's std fds to /dev/null
# BEFORE backgrounding:
#   (a) cma_run captures this hook via `cd "$("$CMA_CWD_HOOK" <alias>)"` — any
#       byte the bind writes to fd 1 would CORRUPT the cd target. The detached
#       bind inherits /dev/null (never the hook's stdout), so it cannot.
#   (b) command substitution `$(...)` blocks until EVERY process holding the
#       write end of the captured pipe exits — a child inheriting fd 1 would HANG
#       shell startup until the bind finished. With fds -> /dev/null the bind
#       holds NO copy of the hook's stdout, so `cd "$(...)"` returns the instant
#       the foreground `resolve` finishes, regardless of the bind still running.
# The `( ... & )` returns immediately (does not wait on `&`); the child is
# reparented away. `|| true` keeps the whole thing non-fatal.
_cwh_bind_start() {
    local alias="$1"
    ( _cwh_bind_async "$alias" & ) >/dev/null 2>&1 </dev/null || true
}

# Determine the alias's resolved track (binding-aware; empty for conductor /
# unmapped / unmounted — the resolver's `track` verb is validate-gated, so a
# track prints IFF a real cd-able worktree resolved) and engage/refresh its
# lease. Read-only + idempotent; any failure is swallowed. Runs detached (all
# fds already redirected by _cwh_bind_start), so it never touches the hook's
# stdout contract. Inherits the hook's env (MT_REPO_ROOT / MT_CONFIG / MT_ALIAS_DIR)
# so it resolves the SAME config the foreground `resolve` used.
_cwh_bind_async() {
    local alias="$1" orch track
    orch="$CWH_DIR/multitrack_alias_orchestrator.sh"
    [ -r "$orch" ] || return 0
    track="$(bash "$CWH_RESOLVER" track "$alias" 2>/dev/null || true)"
    [ -n "$track" ] || return 0     # conductor / no valid track -> NO bind
    bash "$orch" bind --alias "$alias" --track "$track" >/dev/null 2>&1 || true
    return 0
}

# Fire the §4.2(C) rate-limit monitor FULLY DETACHED — the EXACT same guard as
# _cwh_bind_start: all std fds -> /dev/null BEFORE `&`, so the spawn (a) cannot
# write a byte to this hook's fd 1 (which cma_run captures as the cd target), and
# (b) holds NO copy of the hook's stdout pipe, so `cd "$(hook ...)"` returns the
# instant the foreground `resolve` finishes — the long-lived `tail -F` daemon the
# monitor starts NEVER blocks shell startup. `( ... & )` returns immediately.
_cwh_monitor_start() {
    local alias="$1"
    ( _cwh_monitor_async "$alias" & ) >/dev/null 2>&1 </dev/null || true
}

# Start ONE per-alias fallback monitor (§4.2(C)) for this session, tailing the
# alias's newest Claude Code transcript under its worktree's projects dir. Runs
# detached (all fds already redirected by _cwh_monitor_start). Rules:
#   * REAL track only — the resolver's validate-gated `track` verb prints a track
#     IFF a live cd-able worktree resolved, so the conductor / unmapped / unmounted
#     alias yields NO track and therefore NO monitor (mirrors the no-bind path).
#   * IDEMPOTENT — never a 2nd monitor for the same (alias,track): a pgrep on the
#     daemon's own argv is the stateless guard.
#   * <transcript> = newest *.jsonl under $CLAUDE_CONFIG_DIR/projects/<enc>/ where
#     <enc> is the worktree path with every '/'→'-' (the Claude Code transcript
#     dir convention, DESIGN §4.2(C)). No transcript yet -> SKIP cleanly (a future
#     hook run at the next session start starts it once a transcript exists).
#   * Log under the worker's own <worktree>/qa-results/multitrack/ (§11.4.89),
#     falling back to a tmp dir when that tree is not writable. Best-effort +
#     non-fatal throughout; any failure is swallowed (never harms the session).
_cwh_monitor_async() {
    local alias="$1" mon track wt enc projdir tp logdir logf ccdir
    mon="$CWH_DIR/multitrack_fallback_monitor.sh"
    [ -r "$mon" ] || return 0
    track="$(bash "$CWH_RESOLVER" track "$alias" 2>/dev/null || true)"
    [ -n "$track" ] || return 0     # conductor / no valid track -> NO monitor
    # Idempotency: one monitor per (alias,track). Skip if one is already live.
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "multitrack_fallback_monitor.sh --daemon --alias $alias --track $track" \
            >/dev/null 2>&1 && return 0
    fi
    wt="$(bash "$CWH_RESOLVER" resolve "$alias" 2>/dev/null || true)"
    [ -n "$wt" ] || return 0
    ccdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    enc="$(printf '%s' "$wt" | tr '/' '-')"
    projdir="$ccdir/projects/$enc"
    tp="$(ls -1t "$projdir"/*.jsonl 2>/dev/null | head -n1 || true)"
    [ -n "$tp" ] || return 0        # no transcript yet -> skip cleanly (DESIGN §4b)
    logdir="$wt/qa-results/multitrack"
    mkdir -p "$logdir" 2>/dev/null || logdir="${TMPDIR:-/tmp}/multitrack_monitor_logs"
    mkdir -p "$logdir" 2>/dev/null || true
    logf="$logdir/monitor_${alias}_$(date +%s).log"
    nohup bash "$mon" --daemon --alias "$alias" --track "$track" --transcript "$tp" \
        >"$logf" 2>&1 &
    return 0
}

# Fire the §11.4.35 constitution auto-sync FULLY DETACHED — the EXACT same guard
# as _cwh_bind_start / _cwh_monitor_start: all std fds -> /dev/null BEFORE `&`, so
# the sync (a) cannot write a byte to this hook's fd 1 (which cma_run captures as
# the cd target), and (b) holds NO copy of the hook's stdout pipe, so
# `cd "$(hook ...)"` returns the instant the foreground `resolve` finishes — the
# sync's NETWORK fetch NEVER blocks shell startup. `( ... & )` returns immediately.
_cwh_constitution_sync_start() {
    local alias="$1"
    ( _cwh_constitution_sync_async "$alias" & ) >/dev/null 2>&1 </dev/null || true
}

# Fast-forward the alias's resolved worktree's constitution submodule to latest
# <remote>/main via the sibling helper (ancestor-guarded, ff-only, WIP-preserving,
# never force/reset — the helper owns all safety). Runs detached (all fds already
# redirected by _cwh_constitution_sync_start), so it never touches the hook's
# stdout contract. `for-alias` resolves the worktree itself and NOOPs cleanly for
# the conductor / unmapped / unmounted alias (no worktree -> nothing to sync),
# mirroring the no-bind / no-monitor path. Inherits the hook's resolver env.
_cwh_constitution_sync_async() {
    local alias="$1" cs
    cs="$CWH_DIR/multitrack_constitution_sync.sh"
    [ -r "$cs" ] || return 0
    bash "$cs" for-alias "$alias" >/dev/null 2>&1 || true
    return 0
}

_cwh_install() {
    mkdir -p "$(dirname "$CWH_LINK")" 2>/dev/null || true
    if [ -L "$CWH_LINK" ]; then
        local cur; cur="$(readlink "$CWH_LINK" 2>/dev/null)"
        if [ "$cur" = "$CWH_SELF" ]; then
            echo "already installed: $CWH_LINK -> $CWH_SELF"; return 0
        fi
        rm -f "$CWH_LINK"
    elif [ -e "$CWH_LINK" ]; then
        echo "refusing to overwrite non-symlink: $CWH_LINK" >&2; return 1
    fi
    ln -s "$CWH_SELF" "$CWH_LINK" && echo "installed: $CWH_LINK -> $CWH_SELF"
}

_cwh_uninstall() {
    if [ -L "$CWH_LINK" ]; then
        local cur; cur="$(readlink "$CWH_LINK" 2>/dev/null)"
        if [ "$cur" = "$CWH_SELF" ]; then rm -f "$CWH_LINK" && echo "removed: $CWH_LINK"; return 0; fi
        echo "not ours (leaving): $CWH_LINK -> $cur" >&2; return 1
    fi
    echo "no symlink at $CWH_LINK"; return 0
}

# Operator diagnostic (§11.4.201(5) — a resolution always shows its evidence).
# Read-only; prints the resolved consumer root + WHY, or an honest "unresolved".
_cwh_consumer_root_report() {
    local alias="${1:-}" out why root
    out="$(_cwh_consumer_root "$alias" 2>/dev/null)"
    why="${out%%$'\t'*}"
    root="${out#*$'\t'}"
    printf 'alias           : %s\n' "${alias:-<none>}"
    printf 'cwd             : %s\n' "$(pwd -P 2>/dev/null)"
    printf 'binding file    : %s%s\n' "$CWH_CONSUMER_ROOTS" \
        "$( [ -r "$CWH_CONSUMER_ROOTS" ] && printf '' || printf '  (absent)' )"
    if [ -n "$root" ]; then
        printf 'consumer root   : %s\n' "$root"
    else
        printf 'consumer root   : <unresolved>\n'
    fi
    printf 'reason          : %s\n' "${why:-unknown}"
    return 0
}

_cwh_status() {
    printf 'hook script : %s\n' "$CWH_SELF"
    printf 'resolver    : %s\n' "$CWH_RESOLVER"
    if [ -L "$CWH_LINK" ]; then
        printf 'installed   : %s -> %s\n' "$CWH_LINK" "$(readlink "$CWH_LINK" 2>/dev/null)"
    else
        printf 'installed   : NO (%s absent)\n' "$CWH_LINK"
    fi
    printf 'MULTITRACK_DISABLE=%s\n\n' "${MULTITRACK_DISABLE:-0}"
    # §11.4.177: show which consumer project this hook would answer for, so an
    # operator can SEE a mis-binding instead of inferring it from a wrong cd.
    _cwh_consumer_root_report ""
    printf '\n'
    # Map through the SAME resolved consumer root the hook path would use, so
    # --status can never report a different project than a live invocation.
    ( _cwh_bind_consumer_root ""; bash "$CWH_RESOLVER" map 2>/dev/null ) || true
}

case "${1:-}" in
    --install)   _cwh_install ;;
    --uninstall) _cwh_uninstall ;;
    --status)    _cwh_status ;;
    --consumer-root) _cwh_consumer_root_report "${2:-}" ;;
    -h|--help)   grep -E '^#( |$)' "$CWH_SELF" | sed 's/^# \{0,1\}//' | head -40 ;;
    '')          exit 0 ;;                 # no label -> nothing (safe)
    *)           _cwh_hook "$1" ;;         # treat arg as the alias label
esac
