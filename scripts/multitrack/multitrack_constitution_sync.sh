#!/usr/bin/env bash
# =============================================================================
# multitrack_constitution_sync.sh   (§11.4.35 constitution auto-sync)
# -----------------------------------------------------------------------------
# Purpose:
#   Keep a consuming project's `constitution/` submodule ALWAYS up to date with
#   its upstream `main` branch, on every track activation — the durable form of
#   the operator directive (2026-07-04):
#     "Constitution Submodule MUST BE ALWAYS up to date (fetch and pull all)
#      with the main branch! Everywhere!"
#
#   Given a constitution CHECKOUT path (or an alias, via the sibling resolver),
#   it fetches `<remote> <branch>` and fast-forwards the checkout to that tip —
#   but ONLY when doing so is a pure, loss-free fast-forward. It is the ONE safe
#   half of "always current": it can only ever move a checkout FORWARD along its
#   own history; it can never rewind, force, reset, or drop a local commit.
#
#   It is deliberately NOT `git submodule update`: that command re-pins the OLD
#   gitlink commit recorded in the superproject, which would UNDO this sync (and
#   can DETACH HEAD). This helper advances the submodule's OWN `main` instead.
#
# Safety contract (the operator's absolute rule — no corruption, no loss):
#   * FETCH is read-only wrt the working tree + local branches (only updates
#     FETCH_HEAD / remote-tracking refs). A fetch failure => log SKIPPED, return.
#   * ANCESTOR-GUARDED: advance IFF the current HEAD is an ancestor of the
#     fetched tip (`git merge-base --is-ancestor`). If not (diverged / local
#     ahead) => log SKIPPED-not-ff and DO NOTHING. Never force. Never reset.
#   * FAST-FORWARD ONLY: `git merge --ff-only <tip>` while attached to <branch>.
#     git itself ABORTS the ff (before moving anything) if uncommitted WIP would
#     be overwritten => log SKIPPED-ff-blocked, no loss. WIP the ff does NOT
#     touch is left byte-for-byte intact (that is what preserves the in-flight
#     scripts/multitrack/ machinery this very directory holds).
#   * ATTACH-TO-BRANCH: only advances when HEAD is already ON <branch> (so the
#     branch ref moves and HEAD stays attached). A detached / other-branch HEAD
#     => log SKIPPED-not-on-branch and DO NOTHING (never risk a re-checkout with
#     WIP present). In the real deployment the constitution is always on `main`.
#   * Every path returns 0 (this is a best-effort side-effect of session start;
#     it must NEVER fail a shell / block a session).
#
#   Every decision (SYNCED old->new / ALREADY-CURRENT / SKIPPED-*) is logged as
#   captured evidence (§11.4.6) to stderr AND appended to a per-checkout log.
#
# Usage:
#   multitrack_constitution_sync.sh sync <constitution-checkout-path>
#   multitrack_constitution_sync.sh for-alias <alias>   # resolve wt, sync its constitution
#     (<wt>/submodules/constitution — the standard layout — or the legacy
#      <wt>/constitution, or any .gitmodules path; resolved by
#      scripts/lib/constitution_layout.sh, ignoring any ambient
#      $CONSTITUTION_DIR. None found => logged
#      SKIPPED-no-constitution, never a silent no-op.)
#   multitrack_constitution_sync.sh -h | --help
#
# Inputs (env, all optional — safe defaults):
#   MTCS_REMOTE   remote to fetch from (default: origin)
#   MTCS_BRANCH   branch to track      (default: main)
#   MTCS_LOG_DIR  evidence log dir     (default: <worktree>/qa-results/multitrack,
#                                       tmp fallback; <worktree> = dirname CHECKOUT)
#   MT_* resolver env (MT_REPO_ROOT / MT_CONFIG* / MT_ALIAS_DIR ...) honored by
#        the sibling resolver in `for-alias` mode.
#
# Outputs: stdout = the single decision line (also -> stderr + log). exit: always 0.
# Side-effects: at most a fast-forward of <checkout>'s `main` (loss-free by the
#   contract above) + an appended log line. NEVER a force/reset/rewind.
#
# Dependencies: bash, git; sibling multitrack_resolve_worktree.sh (for-alias only).
#
# Cross-references:
#   scripts/multitrack/multitrack_cwd_hook.sh          (fires this on activation)
#   scripts/multitrack/multitrack_resolve_worktree.sh  (alias -> worktree, for-alias)
#   §11.4.6 no-guessing (every decision is a logged fact) · §11.4.28 decoupling
#   (zero project literal) · §11.4.35 canonical-root · §11.4.167/§11.4.177 multi-track
# =============================================================================

set -u

MTCS_REMOTE="${MTCS_REMOTE:-origin}"
MTCS_BRANCH="${MTCS_BRANCH:-main}"

# --- self / sibling resolution (symlink-safe) --------------------------------
_mtcs_self_dir() {
    src="${BASH_SOURCE[0]:-$0}"
    while [ -h "$src" ]; do
        d=$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)
        src=$(readlink "$src"); case "$src" in /*) ;; *) src="$d/$src" ;; esac
    done
    cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}
MTCS_DIR="$(_mtcs_self_dir)"

# --- evidence log ------------------------------------------------------------
# Resolve the log dir lazily against the checkout's worktree (dirname of the
# constitution checkout), with a tmp fallback, mirroring the fallback-monitor's
# <worktree>/qa-results/multitrack convention.
_mtcs_logfile() {
    local checkout="$1" wt logdir
    if [ -n "${MTCS_LOG_DIR:-}" ]; then
        logdir="$MTCS_LOG_DIR"
    else
        wt="$(cd -P "$(dirname "$checkout")" >/dev/null 2>&1 && pwd || true)"
        [ -n "$wt" ] && logdir="$wt/qa-results/multitrack" || logdir="${TMPDIR:-/tmp}/multitrack_constitution_sync"
    fi
    mkdir -p "$logdir" 2>/dev/null || { logdir="${TMPDIR:-/tmp}/multitrack_constitution_sync"; mkdir -p "$logdir" 2>/dev/null || true; }
    printf '%s/constitution_sync.log' "$logdir"
}

# _mtcs_log <decision> <details...> — one captured-evidence line to stderr + log.
# The <checkout> currently being processed is passed via the caller-set
# $_MTCS_CUR so the log lands under that checkout's worktree.
_mtcs_log() {
    local decision="$1"; shift
    local ts line logf
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u 2>/dev/null || echo '?')"
    line="[constitution-sync] $ts $decision $*"
    printf '%s\n' "$line"                       # stdout (captured by callers/tests)
    printf '%s\n' "$line" >&2                    # stderr (interactive visibility)
    if [ -n "${_MTCS_CUR:-}" ]; then
        logf="$(_mtcs_logfile "$_MTCS_CUR")"
        printf '%s\n' "$line" >>"$logf" 2>/dev/null || true
    fi
}

# --- core: fast-forward ONE constitution checkout to <remote>/<branch> --------
# Returns 0 on every path (best-effort side-effect; never fatal).
_mtcs_sync_one() {
    local checkout="$1"
    local _MTCS_CUR="$checkout"          # scope the log target to this checkout
    local old cur target

    [ -n "$checkout" ] || { _mtcs_log SKIPPED-empty-path "(no checkout given)"; return 0; }
    if [ ! -e "$checkout/.git" ] || ! git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _mtcs_log SKIPPED-not-a-git-checkout "$checkout"; return 0
    fi
    old="$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$old" ] || { _mtcs_log SKIPPED-no-head "$checkout"; return 0; }
    cur="$(git -C "$checkout" symbolic-ref --quiet --short HEAD 2>/dev/null || echo '')"

    # FETCH (read-only wrt working tree + local branches). Network failure -> skip.
    if ! git -C "$checkout" fetch --quiet "$MTCS_REMOTE" "$MTCS_BRANCH" 2>/dev/null; then
        _mtcs_log SKIPPED-fetch-failed "$checkout ($MTCS_REMOTE $MTCS_BRANCH unreachable) HEAD=${old:0:12}"
        return 0
    fi
    target="$(git -C "$checkout" rev-parse FETCH_HEAD 2>/dev/null || true)"
    [ -n "$target" ] || { _mtcs_log SKIPPED-no-fetch-head "$checkout"; return 0; }

    if [ "$old" = "$target" ]; then
        _mtcs_log ALREADY-CURRENT "$checkout @ ${old:0:12} == $MTCS_REMOTE/$MTCS_BRANCH"
        return 0
    fi

    # ANCESTOR GUARD: old MUST be an ancestor of target (pure fast-forward).
    if ! git -C "$checkout" merge-base --is-ancestor "$old" "$target" 2>/dev/null; then
        _mtcs_log SKIPPED-not-ff "$checkout HEAD=${old:0:12} is NOT an ancestor of $MTCS_REMOTE/$MTCS_BRANCH ${target:0:12} (diverged/local-ahead) — refusing to move (no force, no reset)"
        return 0
    fi

    # ATTACH-TO-BRANCH: only advance while already on <branch> (keeps HEAD
    # attached; never re-checkouts a detached HEAD with WIP present).
    if [ "$cur" != "$MTCS_BRANCH" ]; then
        _mtcs_log SKIPPED-not-on-branch "$checkout HEAD='${cur:-DETACHED}' != $MTCS_BRANCH — refusing auto-advance (attach to $MTCS_BRANCH manually); no change"
        return 0
    fi

    # FAST-FORWARD ONLY. git aborts (before touching anything) if uncommitted WIP
    # would be overwritten -> loss-free SKIPPED-ff-blocked. WIP the ff does not
    # touch survives byte-for-byte.
    if git -C "$checkout" merge --ff-only "$target" >/dev/null 2>&1; then
        _mtcs_log SYNCED "$checkout ${old:0:12} -> ${target:0:12} (fast-forward on $MTCS_BRANCH; local WIP preserved)"
        return 0
    fi
    _mtcs_log SKIPPED-ff-blocked "$checkout ff to ${target:0:12} blocked — uncommitted WIP would be overwritten; git aborted safely (no loss). Commit/stash then re-activate. HEAD unchanged=${old:0:12}"
    return 0
}

# --- for-alias: resolve the alias's worktree, sync its constitution checkout --
_mtcs_for_alias() {
    local alias="$1" resolver wt
    [ -n "$alias" ] || { _mtcs_log SKIPPED-empty-alias "(no alias given)"; return 0; }
    resolver="$MTCS_DIR/multitrack_resolve_worktree.sh"
    [ -r "$resolver" ] || { _MTCS_CUR="" _mtcs_log SKIPPED-no-resolver "$resolver"; return 0; }
    wt="$(bash "$resolver" resolve "$alias" 2>/dev/null || true)"
    if [ -z "$wt" ]; then
        _MTCS_CUR="" _mtcs_log NOOP-no-worktree "alias '$alias' -> no worktree (conductor/home/unmapped) — nothing to sync"
        return 0
    fi
    local lib="$MTCS_DIR/../lib/constitution_layout.sh" cdir=""
    if [ ! -r "$lib" ]; then
        _MTCS_CUR="" _mtcs_log SKIPPED-no-layout-resolver "$lib missing — cannot locate the constitution in $wt"
        return 0
    fi
    # shellcheck source=../lib/constitution_layout.sh
    . "$lib"
    # The WORKTREE's own checkout: an ambient $CONSTITUTION_DIR (exported for
    # some other project) must never redirect the sync to another checkout.
    if command -v cl_find_in_project_no_override >/dev/null 2>&1; then
        cdir="$(cl_find_in_project_no_override "$wt" 2>/dev/null || true)"
    else
        cdir="$(CONSTITUTION_DIR='' cl_find_in_project "$wt" 2>/dev/null || true)"
    fi
    if [ -z "$cdir" ]; then
        _MTCS_CUR="" _mtcs_log SKIPPED-no-constitution "alias '$alias' -> $wt has no constitution checkout (looked for $CONSTITUTION_LAYOUT_RELS and .gitmodules paths)"
        return 0
    fi
    _mtcs_sync_one "$cdir"
}

_mtcs_usage() {
    sed -n '2,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-}"; shift 2>/dev/null || true
    # Ambient git environment (round 8): GIT_DIR & co. beat `git -C <checkout>`,
    # so a leftover for another repository would fetch/merge the WRONG one.
    # Dropped here (unset-and-proceed, with a notice). Inline copy of
    # scripts/lib/constitution_layout.sh CL_GIT_SCRUB_VARS (this engine file may
    # run without the lib; tests/layout/test_round8_git_env.sh checks equality).
    local _v _dropped=""
    for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do
        if [ -n "${!_v+x}" ]; then _dropped="${_dropped:+$_dropped }$_v"; unset "$_v"; fi
    done
    [ -z "$_dropped" ] || printf '[constitution-sync] NOTICE: ignoring the ambient git environment (%s); each checkout is addressed by its own path.\n' "$_dropped" >&2
    case "$cmd" in
        sync)       _mtcs_sync_one "${1:-}" ;;
        for-alias)  _mtcs_for_alias "${1:-}" ;;
        -h|--help|help) _mtcs_usage; return 0 ;;
        '')         _mtcs_usage >&2; return 2 ;;
        *)          printf 'multitrack_constitution_sync.sh: unknown command %s\n' "$cmd" >&2; _mtcs_usage >&2; return 2 ;;
    esac
}

main "$@"
