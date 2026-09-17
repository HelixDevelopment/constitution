#!/usr/bin/env bash
# =============================================================================
# multitrack_resolve_worktree.sh
#
# Purpose:
#   Deterministic resolver: given a Claude-Toolkit alias name (claude1/claude2/
#   claude3), print the absolute path of the git worktree that alias should work
#   in — i.e. its bound track drive's <project> checkout (/mnt/trackN/<project>)
#   — so the "permanent multi-track switch" can `cd` a fresh alias session into
#   its own worktree instead of the shared /home checkout (removes git-lock
#   contention between the three aliases).
#
#   This is the CORE of the permanent switch. It is consumed by
#   multitrack_cwd_hook.sh (the thin adapter the Claude Toolkit `cma_run`
#   wrapper invokes on session start).
#
# Resolution (deterministic, config-driven — NO hardcoded track/alias map,
# per §11.4.28 decoupling + §11.4.111 resolve-by-stable-name):
#   0. §11.4.177 auto-conductor: if the alias equals the config `conductor:`
#      key, it is NEVER worktree-bound — resolve prints nothing / exit 0 and the
#      session stays on the shared /home checkout (same as role:main / disabled).
#   1. If the alias-orchestrator (multitrack_alias_orchestrator.sh) has an
#      ACTIVE binding for this alias in its bindings.snapshot, take that binding's
#      track (and its recorded worktree if it is itself a valid checkout). An
#      alias MAY now serve MULTIPLE tracks (operator mandate 2026-07); when it
#      does, its MOST-RECENT binding wins (greatest acq column) — the alias
#      resolves to the track it most recently switched onto.
#   2. Otherwise fall back to the STABLE default map derived from
#      config/multitrack/<host>.yaml: the ordered `native` aliases are mapped
#      positionally onto the ordered `feature`-role tracks, EXCLUDING the
#      configured conductor alias (§11.4.177 — never worktree-bound, so it must
#      not consume a track slot). On <host> with conductor=claude1 that yields
#      claude2->track-2, claude3->track-3, claude4->track-4. The `main`
#      track (track-1) is NEVER worktree-bound — main stays on the /home checkout
#      (git forbids the main branch in two worktrees), so whichever alias needs
#      main simply gets no worktree here and falls back to /home.
#   3. The worktree path = <track mount>/<subdir>, where <subdir> defaults to the
#      repo basename ("<project>"). Overridable via MT_WORKTREE_SUBDIR.
#
#   The candidate is then GUARDED (never cd into an unmounted/empty/half-seeded
#   track): the mount must be a live mountpoint AND <worktree>/.git must exist AND
#   `git rev-parse --is-inside-work-tree` must pass. Only then is the path printed
#   (exit 0). If anything fails, nothing is printed and exit is non-zero (3) so
#   the caller falls back to /home.
#
# Usage:
#   multitrack_resolve_worktree.sh resolve <alias>   # print worktree or exit 3
#   multitrack_resolve_worktree.sh track <alias>     # print resolved track id or exit 3/10
#   multitrack_resolve_worktree.sh map               # table: alias track worktree state
#   multitrack_resolve_worktree.sh -h | --help
#
# Inputs (env):
#   MULTITRACK_DISABLE=1   Escape hatch: print nothing, exit 0 (switch disabled).
#   MT_REPO_ROOT           Override repo root (default: this script's ../..).
#   MT_CONFIG_DIR          Override per-host config dir (testability).
#   MT_ALIAS_DIR           Orchestrator runtime dir holding bindings.snapshot
#                          (default: ${XDG_RUNTIME_DIR:-/tmp}/<project>/multitrack/aliasorch).
#   MT_WORKTREE_SUBDIR     Worktree subdir under a track mount (default: repo basename).
#
# Outputs:
#   stdout: the resolved absolute worktree path (resolve), or a table (map).
#   exit:   0 = printed a valid worktree / disabled; 3 = no valid worktree
#           (caller falls back to /home); 2 = usage error.
#
# Side-effects: NONE (read-only: reads config + bindings snapshot + findmnt/git).
#
# Dependencies: bash, awk, git, findmnt (util-linux); multitrack_config.sh
#   (sourced for mt_resolve_host / mt_config_file / mt_load_config).
#
# Cross-references:
#   scripts/multitrack/multitrack_cwd_hook.sh          (the toolkit adapter)
#   scripts/multitrack/multitrack_alias_orchestrator.sh (bindings.snapshot source)
#   scripts/multitrack/multitrack_config.sh            (per-host config loader)
#   config/multitrack/<host>.yaml                 (tracks[] + aliases[])
#   docs/guides/MULTITRACK_PERMANENT_SWITCH.md         (design + activation)
#   §11.4.28 decoupling · §11.4.111 resolve-by-stable-name · §11.4.167 worktrees
#   §11.4.6 no-guessing (guard verifies mount+worktree, never assumes)
# =============================================================================

# No `set -e` (we source config.sh and expect controlled non-zero returns); be
# disciplined with ${x:-} instead. No `set -u` for the same sourcing safety.

_mrw_self_dir() {
    # dirname of THIS script, resolving the common symlink case.
    local src="${BASH_SOURCE[0]:-$0}"
    while [ -h "$src" ]; do
        local dir; dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
    done
    cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

MRW_DIR="$(_mrw_self_dir)"
# RB-01 (§11.4.111 / §11.4.35): remember whether the operator explicitly pinned
# MT_REPO_ROOT / MT_ALIAS_DIR (e.g. a consumer shim). When MT_REPO_ROOT was NOT
# pinned, _mrw_load_cfg lets multitrack_config.sh:mt_repo_root() self-locate the
# CONSUMER project root (git superproject when embedded as a submodule) instead
# of the ../.. guess that resolves to the SUBMODULE root — the twin of the
# mt_repo_root bug (a bare `constitution/…/resolve … map` from any cwd must find
# the consumer config, not the submodule's non-existent config/multitrack).
MRW_REPO_ROOT_EXPLICIT="${MT_REPO_ROOT:+1}"
MRW_ALIAS_DIR_EXPLICIT="${MT_ALIAS_DIR:+1}"
# repo root = scripts/multitrack -> ../.. ; overridable for tests. When NOT
# operator-pinned this is only a provisional value; _mrw_load_cfg replaces it
# with the config-driven self-located consumer root before any config lookup.
MRW_REPO_ROOT="${MT_REPO_ROOT:-$(cd "$MRW_DIR/../.." 2>/dev/null && pwd)}"
# §11.4.111 G2b env→config→basename precedence: defer here (env only). The
# config + basename fallback resolve after _mrw_load_cfg in _mrw_pick + _mrw_map.
MRW_WT_SUBDIR="${MT_WORKTREE_SUBDIR:-}"

# Orchestrator runtime bindings (same default as the orchestrator). Recomputed in
# _mrw_load_cfg if the repo root is self-located (RB-01) and MT_ALIAS_DIR unset.
MRW_ALIAS_DIR="${MT_ALIAS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/$(basename "$MRW_REPO_ROOT")/multitrack/aliasorch}"
MRW_BIND="$MRW_ALIAS_DIR/bindings.snapshot"

MRW_CFG=""   # resolved per-host config path (set by _mrw_load_cfg)

# --- config load (reuses multitrack_config.sh) -------------------------------
_mrw_load_cfg() {
    local cfglib="$MRW_DIR/multitrack_config.sh"
    [ -r "$cfglib" ] || { echo "resolve-worktree: missing $cfglib" >&2; return 1; }
    # shellcheck source=scripts/multitrack/multitrack_config.sh
    . "$cfglib" || return 1
    # RB-01 (§11.4.111 / §11.4.35): resolve the CONSUMER project root. An
    # operator-pinned MT_REPO_ROOT (a consumer shim) wins as-is; otherwise let
    # config.sh's mt_repo_root() self-locate it — base/config directly, else the
    # git superproject when embedded as a submodule — so a bare
    # `constitution/…/resolve … map` from ANY cwd finds the consumer config
    # instead of the submodule root's non-existent config/multitrack. (The
    # subshell forces mt_repo_root's discovery via an empty MT_REPO_ROOT +
    # MT_SELF pinned to this engine's config.sh path — robust vs $0.)
    if [ -z "$MRW_REPO_ROOT_EXPLICIT" ]; then
        MRW_REPO_ROOT="$(MT_REPO_ROOT= MT_SELF="$cfglib" mt_repo_root)"
        if [ -z "$MRW_ALIAS_DIR_EXPLICIT" ]; then
            MRW_ALIAS_DIR="${XDG_RUNTIME_DIR:-/tmp}/$(basename "$MRW_REPO_ROOT")/multitrack/aliasorch"
            MRW_BIND="$MRW_ALIAS_DIR/bindings.snapshot"
        fi
    fi
    # Pin the resolved root so config.sh's config-dir lookup is deterministic.
    MT_REPO_ROOT="$MRW_REPO_ROOT"; export MT_REPO_ROOT
    local host rc
    host="$(mt_resolve_host)"
    # §11.4.187: a real per-host config loads exactly as before; a host with NO
    # config falls back to the universal DEFAULT single-track mode (track-1 =
    # the invocation project root) with a loud stderr notice; a config that
    # EXISTS but is malformed still fails (never silently defaulted past).
    mt_resolve_and_load
    rc=$?
    [ "$rc" -eq 0 ] || return 1
    MRW_CFG="${MT_CFG_FILE:-}"
    if [ "${MT_DEFAULT_MODE:-0}" = "1" ]; then
        # Default mode has no config FILE, so the file-reading accessors cannot
        # supply the worktree subdir — take it from the loaded default, and pin
        # the repo root to the resolved project root so downstream composition
        # ("<mount>/<subdir>") yields the project root itself.
        MRW_REPO_ROOT="${MT_DEFAULT_TRACK1_ROOT:-$MRW_REPO_ROOT}"
        MT_REPO_ROOT="$MRW_REPO_ROOT"; export MT_REPO_ROOT
        [ -n "$MRW_WT_SUBDIR" ] || MRW_WT_SUBDIR="${MT_WORKTREE_SUBDIR:-}"
    fi
    return 0
}

# --- ordered feature-role tracks: emit "track-id<TAB>mount" -------------------
_mrw_feature_tracks() {
    local i=1 id role mount
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        eval "id=\${MT_TRACK_${i}_ID:-}"
        eval "role=\${MT_TRACK_${i}_ROLE:-}"
        eval "mount=\${MT_TRACK_${i}_MOUNT:-}"
        [ "$role" = "feature" ] && [ -n "$id" ] && printf '%s\t%s\n' "$id" "$mount"
        i=$((i + 1))
    done
}

# --- mount for a given track id ----------------------------------------------
_mrw_mount_for_track() {
    local want="$1" i=1 id mount
    while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
        eval "id=\${MT_TRACK_${i}_ID:-}"
        eval "mount=\${MT_TRACK_${i}_MOUNT:-}"
        if [ "$id" = "$want" ]; then printf '%s' "$mount"; return 0; fi
        i=$((i + 1))
    done
    return 1
}

# --- ordered `native` aliases from the config aliases: block -----------------
# Same tolerant parse the orchestrator uses (_roster_from_config), filtered to
# kind==native and preserving file order.
_mrw_native_aliases() {
    [ -n "$MRW_CFG" ] && [ -r "$MRW_CFG" ] || return 1
    awk '
        /^[a-zA-Z0-9_]+:/ { inblk = ($1=="aliases:") ? 1 : 0 }
        inblk==1 {
            if (match($0, /name:[ \t]*/)) { s=substr($0,RSTART+RLENGTH); gsub(/[",]/,"",s); split(s,a," "); n=a[1] }
            if (match($0, /kind:[ \t]*/)) { s=substr($0,RSTART+RLENGTH); gsub(/[",]/,"",s); split(s,a," "); k=a[1] }
            if (n!="" && $0 ~ /kind:/) { if (k=="native") print n; n=""; k="" }
        }
    ' "$MRW_CFG" 2>/dev/null
}

# --- active orchestrator binding for an alias: emit "track<TAB>worktree" ------
# bindings.snapshot columns: alias|track|worktree|pid|acq|exp|state
# An alias MAY now hold MULTIPLE Tracks (operator mandate 2026-07 — the same
# alias may be reused on more than one Track). When it does, resolve to its
# MOST-RECENT / current Track binding — the row with the greatest acq ($5) among
# its non-expired rows (§11.4.111 resolve-by-stable-name; §11.4.6 no-guessing —
# never an arbitrary first-match). Ties keep the later-in-file row.
_mrw_binding_for_alias() {
    local alias="$1" now
    [ -r "$MRW_BIND" ] || return 1
    now="$(date +%s 2>/dev/null || echo 0)"
    awk -F'|' -v a="$alias" -v now="$now" '
        $1==a && $6+0 > now { if ($5+0 >= best) { best=$5+0; tr=$2; wt=$3; found=1 } }
        END { if (!found) exit 1; print tr "\t" wt }
    ' "$MRW_BIND"
}

# --- ATM-834: machine-readable alias-exclusion set ---------------------------
# `excluded_aliases:` (§11.4.187(4)) names aliases that must NEVER be bound to a
# worktree — a dead/disabled subscription, an operator-excluded alias. Before
# this, the ONLY machine-readable alias policy was the single `conductor:`
# scalar, so any further exclusion could live only in prose comments the engine
# cannot read (§11.4.6: policy READ from config, never inferred from comments).
#
# ADDITIVE + ZERO-CHANGE-WHEN-ABSENT: an absent key yields an EMPTY set, so
# `_mrw_alias_excluded` is always false and `_mrw_eligible_native_aliases`
# degenerates to the previous non-conductor list. Consumers that do not set the
# key observe byte-identical behaviour.
_mrw_excluded_aliases() {
    mt_config_excluded_aliases "$MRW_CFG" 2>/dev/null || true
}

# True (exit 0) IFF $1 is a member of the configured exclusion set.
# Exact whole-line match — never a substring (§11.4.201(7)(a) carrier-vs-thing:
# a substring match would exclude `claude1` because `claude10` is listed).
_mrw_alias_excluded() {
    local alias="$1" a
    [ -n "$alias" ] || return 1
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        [ "$a" = "$alias" ] && return 0
    done <<EOF
$(_mrw_excluded_aliases)
EOF
    return 1
}

# The native aliases eligible for a positional feature-track slot: every native
# alias MINUS the conductor MINUS every excluded alias, order preserved.
_mrw_eligible_native_aliases() {
    local cond a
    cond="$(mt_config_conductor "$MRW_CFG" 2>/dev/null || true)"
    _mrw_native_aliases | while IFS= read -r a; do
        [ -n "$a" ] || continue
        [ -n "$cond" ] && [ "$a" = "$cond" ] && continue
        _mrw_alias_excluded "$a" && continue
        printf '%s\n' "$a"
    done
}

# --- default positional map: native alias -> feature track (id + mount) -------
# emit "track-id<TAB>mount" for the alias, or non-zero if unmapped.
_mrw_default_track_for_alias() {
    local alias="$1" idx=0 want=-1 a
    # §11.4.111/RB-01 FIX: index over NON-CONDUCTOR natives. The configured
    # conductor alias is NEVER worktree-bound (§11.4.177) -- it MUST NOT consume a
    # feature-track positional slot, otherwise the feature track at the
    # conductor's index is orphaned (with conductor=claude1 the feature track at
    # index 0, track-2, was never resolved by ANY alias). Filtering the conductor
    # out of the positional list maps the N non-conductor natives 1:1 onto the N
    # feature tracks in order (conductor=claude1 => claude2->track-2, claude3->
    # track-3, claude4->track-4), matching operator intent and covering track-2.
    # index of alias among ELIGIBLE native aliases (non-conductor AND
    # non-excluded). ATM-834: an `excluded_aliases:` member must ALSO be filtered
    # out of the positional list — leaving it in would shift every later alias
    # onto the wrong track and orphan the last one, the exact off-by-one the
    # conductor filter above already fixes for the conductor.
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        [ "$a" = "$alias" ] && { want="$idx"; break; }
        idx=$((idx + 1))
    done <<EOF
$(_mrw_eligible_native_aliases)
EOF
    [ "$want" -ge 0 ] || return 1
    # the want-th feature track
    #
    # §11.4.6 / §11.4.201: an EMPTY line is NOT a track. A here-doc built from an
    # empty command substitution still yields one blank line, so a host with
    # FEWER feature tracks than aliases (canonically: a single main-only track,
    # e.g. §11.4.187 default single-track mode) used to "match" that blank at
    # index 0 and return an EMPTY track+mount — which downstream composed into a
    # bogus worktree path ("/<subdir>"). Skipping blanks makes the no-such-track
    # case return 1 (correctly rendered as "-"/fallback) instead of a wrong path.
    local i=0 line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if [ "$i" -eq "$want" ]; then printf '%s' "$line"; return 0; fi
        i=$((i + 1))
    done <<EOF
$(_mrw_feature_tracks)
EOF
    return 1
}

# --- guard: is <worktree> under <mount> a live, valid git worktree? ----------
_mrw_validate() {
    local mount="$1" wt="$2" fstype
    [ -n "$mount" ] && [ -n "$wt" ] || return 1
    # mount must be a live mountpoint (btrfs per config, but accept any real fs)
    fstype="$(findmnt -rno FSTYPE "$mount" 2>/dev/null)" || return 1
    [ -n "$fstype" ] || return 1
    # worktree checkout must exist and be a git worktree
    [ -e "$wt/.git" ] || return 1
    git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    return 0
}

# --- core pick: (track, mount, wt) for an alias ------------------------------
# The SINGLE alias->track decision point, shared by BOTH `resolve` (prints the
# worktree) and `track` (prints the track) so the two can NEVER disagree on
# which track an alias belongs to (§11.4.6 no-guessing). Applies, in order:
#   1. MULTITRACK_DISABLE escape hatch  -> stay-home (rc 10, no track)
#   2. §11.4.177 conductor key          -> stay-home (rc 10, no track): the
#      configured conductor alias is NEVER worktree-bound (its session stays on
#      the shared /home checkout, exactly the role:main / disabled path)
#   3. active orchestrator binding (most-recent wins), else
#   4. the stable positional default map
# Echoes "track<TAB>mount<TAB>worktree" on a real pick. Return:
#   0  = picked (caller MUST still _mrw_validate the mount+worktree)
#   10 = stay-home silently (disabled OR conductor — no track)
#   3  = unmapped / config-load failure ;  2 = usage (empty alias)
_mrw_pick() {
    local alias="$1"
    [ -n "$alias" ] || return 2
    # Escape hatch: switch disabled -> no worktree (caller stays on /home).
    [ "${MULTITRACK_DISABLE:-0}" = "1" ] && return 10
    _mrw_load_cfg || return 3
    # §11.4.111 G2b env→config→basename: resolve worktree-subdir after config load.
    [ -n "$MRW_WT_SUBDIR" ] || MRW_WT_SUBDIR="$(mt_config_worktree_subdir "$MRW_CFG" 2>/dev/null || true)"
    [ -n "$MRW_WT_SUBDIR" ] || MRW_WT_SUBDIR="$(basename "$MRW_REPO_ROOT")"
    # §11.4.177 auto-conductor: the configured conductor alias stays on /home
    # (no worktree, never a bindings.snapshot row). Empty/absent conductor key
    # => no alias is special-cased. mt_config_conductor is provided by the
    # sourced multitrack_config.sh; the VALUE is consumer config, not a literal
    # (§11.4.28(B)). Checked BEFORE any binding lookup so the conductor is
    # deterministically home even if a stale binding row existed.
    local cond
    cond="$(mt_config_conductor "$MRW_CFG" 2>/dev/null || true)"
    [ -n "$cond" ] && [ "$alias" = "$cond" ] && return 10
    # ATM-834 / §11.4.187(4): an alias listed in the machine-readable
    # `excluded_aliases:` set is treated EXACTLY like the conductor — never
    # worktree-bound, never a bindings.snapshot row. Additive: an absent key
    # yields an empty set, so configs without it behave identically (§11.4.6 —
    # the policy is READ from config, never inferred from prose comments).
    if _mrw_alias_excluded "$alias"; then return 10; fi

    local track="" mount="" wt="" b btrack bwt
    # 1) active orchestrator binding wins
    if b="$(_mrw_binding_for_alias "$alias")"; then
        btrack="${b%%$'\t'*}"; bwt="${b#*$'\t'}"
        track="$btrack"
        # a recorded worktree that is ITSELF a valid checkout is honored as-is;
        # otherwise it is treated as the mount (the orchestrator records the
        # mount in the worktree column) and the subdir is appended below.
        if [ -n "$bwt" ] && [ -e "$bwt/.git" ]; then
            wt="$bwt"
        fi
        mount="$(_mrw_mount_for_track "$track" 2>/dev/null)"
        [ -n "$mount" ] || mount="$bwt"
    fi
    # 2) fall back to the stable default map
    if [ -z "$track" ]; then
        local d
        d="$(_mrw_default_track_for_alias "$alias")" || return 3
        track="${d%%$'\t'*}"; mount="${d#*$'\t'}"
    fi
    [ -n "$mount" ] || return 3
    # 3) worktree = <mount>/<subdir> unless a valid one was already taken
    [ -n "$wt" ] || wt="$mount/$MRW_WT_SUBDIR"
    printf '%s\t%s\t%s' "$track" "$mount" "$wt"
    return 0
}

# --- resolve one alias -> worktree (or non-zero) -----------------------------
_mrw_resolve() {
    local p rc track mount wt
    p="$(_mrw_pick "$1")"; rc=$?
    case "$rc" in
        10) return 0 ;;        # disabled / conductor -> silent stay-home (/home)
        0)  ;;                 # picked -> validate below
        *)  return "$rc" ;;    # 2 usage, 3 unmapped / config-load failure
    esac
    IFS=$'\t' read -r track mount wt <<<"$p"
    if _mrw_validate "$mount" "$wt"; then
        printf '%s\n' "$wt"
        return 0
    fi
    return 3
}

# --- resolve one alias -> its TRACK id (PWU-3 bind-on-start) ------------------
# Prints ONLY the resolved track id, gated by the SAME _mrw_validate as
# `resolve` — so a track is emitted IFF `resolve` would emit a worktree (a real,
# live, cd-able track). Empty output + non-zero for conductor / disabled /
# unmapped / unmounted. The cwd-hook uses this to bind ONLY a real track
# (the conductor is never bound — task PWU-3).
_mrw_resolve_track() {
    local p rc track mount wt
    p="$(_mrw_pick "$1")"; rc=$?
    [ "$rc" -eq 0 ] || return "$rc"   # 10 conductor/disabled, 3 unmapped, 2 usage -> no track
    IFS=$'\t' read -r track mount wt <<<"$p"
    if _mrw_validate "$mount" "$wt"; then
        printf '%s\n' "$track"
        return 0
    fi
    return 3
}

# --- map: table over all native aliases --------------------------------------
_mrw_map() {
    _mrw_load_cfg || { echo "resolve-worktree: config load failed" >&2; return 1; }
    # §11.4.111 G2b env→config→basename: resolve worktree-subdir after config load.
    [ -n "$MRW_WT_SUBDIR" ] || MRW_WT_SUBDIR="$(mt_config_worktree_subdir "$MRW_CFG" 2>/dev/null || true)"
    [ -n "$MRW_WT_SUBDIR" ] || MRW_WT_SUBDIR="$(basename "$MRW_REPO_ROOT")"
    printf '%-10s %-9s %-32s %s\n' ALIAS TRACK WORKTREE STATE
    local a cond
    cond="$(mt_config_conductor "$MRW_CFG" 2>/dev/null || true)"
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        # §11.4.177 conductor: never worktree-bound; its session stays on /home.
        if [ -n "$cond" ] && [ "$a" = "$cond" ]; then
            printf '%-10s %-9s %-32s %s\n' "$a" "-" "-" "conductor(/home)"
            continue
        fi
        # ATM-834: an `excluded_aliases:` member is never worktree-bound either.
        if _mrw_alias_excluded "$a"; then
            printf '%-10s %-9s %-32s %s\n' "$a" "-" "-" "excluded(/home)"
            continue
        fi
        local d track mount wt state
        if d="$(_mrw_default_track_for_alias "$a")"; then
            track="${d%%$'\t'*}"; mount="${d#*$'\t'}"; wt="$mount/$MRW_WT_SUBDIR"
        else
            track="-"; wt="-"; mount=""
        fi
        # binding override for display
        local b
        if b="$(_mrw_binding_for_alias "$a")"; then
            track="${b%%$'\t'*}"; mount="$(_mrw_mount_for_track "$track" 2>/dev/null)"
            wt="$mount/$MRW_WT_SUBDIR"
        fi
        if [ "$wt" != "-" ] && _mrw_validate "$mount" "$wt"; then
            state="ok"
        else
            state="fallback(/home)"
        fi
        printf '%-10s %-9s %-32s %s\n' "$a" "$track" "$wt" "$state"
    done <<EOF
$(_mrw_native_aliases)
EOF
}

_mrw_usage() {
    cat >&2 <<'USG'
usage: multitrack_resolve_worktree.sh <command> [args]
  resolve <alias>   print the alias's bound worktree path (exit 0), or exit 3
                    when no valid worktree (caller falls back to /home)
  track <alias>     print the alias's resolved TRACK id (exit 0), or exit 3/10
                    when no track (conductor/disabled/unmapped) — used by the
                    cwd-hook to bind ONLY a real track (PWU-3 bind-on-start)
  map               print alias -> track -> worktree -> state for all native aliases
  -h | --help       this help
env: MULTITRACK_DISABLE=1 disables the switch (resolve prints nothing, exit 0)
     the `conductor:` config key names an alias that always stays on /home
USG
}

main() {
    local cmd="${1:-}"; shift 2>/dev/null || true
    case "$cmd" in
        resolve) _mrw_resolve "${1:-}" ;;
        track)   _mrw_resolve_track "${1:-}" ;;
        map)     _mrw_map ;;
        -h|--help|help|'') _mrw_usage; [ -n "$cmd" ] && return 0 || return 2 ;;
        *)       _mrw_usage; return 2 ;;
    esac
}

main "$@"
