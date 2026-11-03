#!/usr/bin/env bash
# setup.sh — one-time constitution submodule setup for the consuming project.
#
# Wires the post-update auto-propagation hook so that every `git pull` /
# `git submodule update` of this constitution submodule automatically:
#   1. Registers new/modified skills (§11.4.164)
#   2. Installs new/modified hooks
#   3. Merges MCP configs
#   4. Syntax-validates changed scripts
#   5. Installs git hooks into the consuming project
#
# Idempotent: safe to re-run after every clone or when hooks go stale.
#
# Usage (from the consuming project root; standard layout first, legacy second):
#   bash submodules/constitution/scripts/setup.sh
#   bash constitution/scripts/setup.sh                      # legacy layout
#   bash <constitution>/scripts/setup.sh --project-root /path/to/project
#   bash <constitution>/scripts/setup.sh --project-root=/path/to/project
#   bash <constitution>/scripts/setup.sh --check-only       # verify, report drift
#   bash <constitution>/scripts/setup.sh --auto-propagate=off   # record the opt-out
#   bash <constitution>/scripts/setup.sh --allow-global-hooks-path
#
# Target selection (round 7): the ENVIRONMENT never chooses the repository
# this script writes to. The constitution dir is ALWAYS this script's own
# checkout ($SCRIPT_DIR/..); an exported $CONST_DIR naming any other directory
# is refused (exit 2, nothing written). Project root: --project-root (an
# explicit argument) wins; otherwise the checkout's OWNER — its git
# superproject when it is a submodule, or the work tree that holds it when it
# is a vendored plain copy — and an ambient $PROJECT_ROOT naming anything else
# is ignored with a warning; only a STANDALONE checkout (no owner) falls back
# to $PROJECT_ROOT, then the layout suffix resolved by
# scripts/lib/constitution_layout.sh. Never <project>/submodules.
# Propagation lock: step 2c takes the same lock as the installed hooks
# (<git-dir>/constitution-pending-update.lock, exclusive create; a lock whose
# recorded owner is provably dead -- no /proc/<pid>, or a different process
# start time -- is reclaimed with a warning, a live / unprovable / owner-less /
# symlink lock is never touched; the consumer hook additionally reclaims an
# owner-less lock older than 60 s, setup.sh and post-merge deliberately do not:
# they cannot tell a half-written lock of a live run from an abandoned one).
# When another propagation holds it, post_update_hook.sh is NOT run,
# the pending stamp is kept, and setup exits 1 ("setup is INCOMPLETE": re-run
# when the other run has finished, or remove a stale lock by hand).
# Git hooks go to the dir git really uses (`git rev-parse --git-path hooks`),
# only real git hook names are installed, and a different existing hook is
# backed up first to
#   $(git rev-parse --git-common-dir)/constitution-hook-backup/<UTC stamp>/<pass>/<name>
# (pass = constitution|project|submodule; never inside a core.hooksPath work
# tree). Regular files are copied with their mode; a SYMLINK hook is backed up
# AS A LINK (same target, never dereferenced, so a link to a file outside the
# repo is never copied); next to it <name>.link records TARGET= (as stored)
# and ABSOLUTE= (resolved against the hooks dir, so a RELATIVE target is still
# findable from the backup dir; restore the link itself with
# `cp -P <backup> <hooks>/<name>`); any other file type (FIFO, socket, directory, device)
# is refused and left in place, without ever being opened. A backup is NEVER
# overwritten: when that path is taken by a different hook the next free
# <name>.N is used. Backups made before 2026-10-29 live in the old location
# <hooks>/.constitution-hook-backup/ (kept, never deleted; there is no
# --restore mode — restore by copying a backup back by hand).
# Pending-update consumer (§11.4.164): when the constitution is a real
# submodule (gitlink) of the project, scripts/hooks/constitution-submodule-post-checkout
# is installed as the SUBMODULE's post-checkout (its own hooks dir, e.g.
# .git/modules/<name>/hooks), with the same backup rule (pass = submodule).
# git runs the parent's post-merge before it updates the submodule, so that
# hook runs the propagation once the checkout reaches the merged gitlink.
# Skipped with a warning when the submodule sets its own core.hooksPath.
# setup.sh itself consumes a matching pending stamp
# (<git-dir>/constitution-pending-update, PER WORKTREE: `git rev-parse
# --absolute-git-dir`, .git/worktrees/<name> in a linked worktree) only when
# its ROOT is this project (physical path), its REL is this submodule and its
# NEW equals the current checkout; it passes OLD/NEW to post_update_hook.sh
# and, when that hook succeeds, records <git-dir>/constitution-applied-ref.
# Step order: the post-update hook runs first; its failure (e.g. a fresh
# consumer without helix-deps.yaml fails CM-HELIX-DEPS-MANIFEST-PRESENT) is
# reported, the hooks are STILL installed (steps 3/3b), and setup exits 1 at
# the END (the stamp is kept and no applied ref is recorded, so a re-run
# retries).
# TRUST MODEL (printed by every run): after a pull the installed hooks run
# <constitution>/scripts/post_update_hook.sh of the NEWLY CHECKED-OUT gitlink
# commit (fetched code) automatically, but only when that commit is reachable
# from the submodule's upstream default branch (origin/HEAD|main|master, never
# fetched by the hooks) and is not a downgrade; otherwise they print the manual
# command. The installed hooks are self-contained copies: they source and run
# NOTHING from the checkout before those checks pass. setup.sh itself is
# different: it runs THIS checkout's post_update_hook.sh without those checks
# (you are running this checkout's code by hand). A branch switch, checkout or
# reset that moves the submodule through git's own recursion
# (submodule.recurse=true / --recurse-submodules) runs NO hook at all and prints
# nothing (measured: git 2.53.0, `checkout -B` with submodule.recurse=true);
# run setup.sh or post_update_hook.sh by hand after it. Disable with `git config constitution.autoPropagate false` (or
# --auto-propagate=off, which records exactly that in the project's local
# config; --auto-propagate=on records true) or env CONSTITUTION_AUTO_PROPAGATE=off.
# Without the flag the current setting is kept and printed (unset = on).
# Shared hooks dirs: setup refuses (exit 1, nothing written, nothing run) when
# core.hooksPath is set at a scope other than local/worktree (global/system/
# command line: a machine-wide hooks dir would be replaced), or when the hooks
# dir git uses resolves PHYSICALLY (every symlink followed, so a symlinked
# .git/hooks or a symlinked .git/modules/<name>/hooks counts too) to a
# directory outside the project's git dir, common dir and work tree — or, for
# the constitution submodule, outside the submodule's own git dir — unless
# --allow-global-hooks-path is given. Even with that flag the submodule
# consumer is NEVER installed into a hooks dir outside the submodule's own git
# dir (it is skipped with a warning); only the project hooks are written there.
# The checks and the install/backup code are the ONE implementation in
# scripts/lib/hook_install.sh, shared with post_update_hook.sh (STEP 4).
# --check-only: parse-checks post_update_hook.sh and compares the INSTALLED
# post-merge and submodule consumer with their sources (sha256); exit 1 on a
# parse error, a missing hook or drift (re-run setup.sh to refresh).
# Hook-name collision: when the project's scripts/git_hooks/ ships a hook with
# the SAME name as a constitution hook but different bytes, the constitution
# hook stays installed, the project hook is NOT installed, the collision is
# reported and the run exits 1 (refused, never a silent overwrite and never a
# flip-flop between re-runs). Merge the project logic into a hook with another
# name, or call it from your own wrapper, then re-run.
# A hooks dir that physically lies in a directory TRACKED by the project
# (core.hooksPath at a committed dir, or a .git/hooks symlinked into the work
# tree) is warned about (installing would modify tracked files).
# CONSTITUTION_SETUP_BACKUP_STAMP (optional, [A-Za-z0-9._-]) replaces the UTC
# stamp of the backup directory (deterministic tests); anything else -> exit 2.
# Exit: 0 ok · 1 failure (not a constitution, not a git work tree, a hook
# could not be installed or backed up, a hook-name collision: resolve it by
# renaming the project hook in scripts/git_hooks/ and re-run; the post-update
# hook failed; a refused core.hooksPath; --check-only found drift) · 2 usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CONST_DIR is ALWAYS this script's own checkout; an environment CONST_DIR is
# accepted only when it names the same directory (checked below, after the
# helpers exist): an ambient value exported for another project must never
# choose which constitution — and so which project — this run writes to.
_SELF_CONST="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf '%b[const]%b %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%b[const]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
error() { printf '%b[const]%b %s\n' "$RED" "$NC" "$*" >&2; }
usage() { sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

# The ONE layout resolver (both <project>/submodules/constitution and the
# legacy <project>/constitution; any .gitmodules path via the superproject).
# shellcheck source=lib/constitution_layout.sh
. "$SCRIPT_DIR/lib/constitution_layout.sh"
# The ONE hook install / backup / scope-check implementation (shared with
# post_update_hook.sh STEP 4).
# shellcheck source=lib/hook_install.sh
. "$SCRIPT_DIR/lib/hook_install.sh"
# Round 8: an ambient GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE & co. (left over
# for another repository) would choose which repository every `git -C` below
# reads and WRITES (hooks, constitution.autoPropagate). They are dropped here,
# once, with a notice; the repository is discovered from the project path.
cl_scrub_git_env

if [ -n "${CONST_DIR:-}" ] && ! cl_same_dir "$CONST_DIR" "$_SELF_CONST"; then
  error "CONST_DIR=$CONST_DIR (from the environment) is not this checkout ($_SELF_CONST): nothing was written."
  error "  Unset CONST_DIR, or run that checkout's own scripts/setup.sh."
  exit 2
fi
CONST_DIR="$_SELF_CONST"

CHECK_ONLY=0
ARG_PROJECT_ROOT=""
ALLOW_GLOBAL_HOOKS=0
AUTO_PROP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --project-root)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        error "--project-root needs a directory argument"; exit 2
      fi
      ARG_PROJECT_ROOT="$2"; shift ;;
    --project-root=*)
      ARG_PROJECT_ROOT="${1#--project-root=}"
      [ -n "$ARG_PROJECT_ROOT" ] || { error "--project-root= needs a directory"; exit 2; } ;;
    --allow-global-hooks-path) ALLOW_GLOBAL_HOOKS=1 ;;
    --auto-propagate=on|--auto-propagate=true) AUTO_PROP=true ;;
    --auto-propagate=off|--auto-propagate=false) AUTO_PROP=false ;;
    --auto-propagate*) error "--auto-propagate takes =on or =off"; exit 2 ;;
    -h|--help) usage; exit 0 ;;
    *) error "unknown argument: $1 (see --help)"; exit 2 ;;
  esac
  shift
done

BACKUP_STAMP="${CONSTITUTION_SETUP_BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
case "$BACKUP_STAMP" in
  ''|.|..|*[!A-Za-z0-9._-]*)
    error "CONSTITUTION_SETUP_BACKUP_STAMP must match [A-Za-z0-9._-]+ (and not . or ..): '$BACKUP_STAMP'"
    exit 2 ;;
esac

if [ -n "$ARG_PROJECT_ROOT" ]; then
  PROJECT_ROOT="$ARG_PROJECT_ROOT"
else
  # An AMBIENT $PROJECT_ROOT (exported in a shell for another project) must
  # never redirect writes into another repository: when this checkout has an
  # OWNER project (its git superproject, or the work tree holding a vendored
  # plain copy), the owner wins and the ambient value is reported. Only a
  # standalone checkout (no owner) takes $PROJECT_ROOT.
  _owner="$(cl_owner_project_of "$CONST_DIR")" || _owner=""
  if [ -n "$_owner" ]; then
    if [ -n "${PROJECT_ROOT:-}" ] && ! cl_same_dir "$PROJECT_ROOT" "$_owner"; then
      warn "ignoring the ambient PROJECT_ROOT=$PROJECT_ROOT: this constitution checkout belongs to $_owner (use --project-root to choose another project explicitly)."
    fi
    PROJECT_ROOT="$_owner"
  elif [ -z "${PROJECT_ROOT:-}" ]; then
    PROJECT_ROOT="$(cl_project_root_of "$CONST_DIR")" || PROJECT_ROOT=""
  fi
fi
if [ -z "${PROJECT_ROOT:-}" ] || [ ! -d "$PROJECT_ROOT" ]; then
  error "project root does not exist or could not be resolved: '${PROJECT_ROOT:-}'"
  exit 2
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

info "Constitution Setup"
info "  Constitution: $CONST_DIR"
info "  Project root: $PROJECT_ROOT"

# ─── 1. Verify identity ──────────────────────────────────────────────

if ! cl_is_constitution_dir "$CONST_DIR"; then
  error "Not a constitution submodule: $CONST_DIR"
  exit 1
fi

# ─── 2. Resolve git dirs, refuse shared hooks dirs ──────────────────

sha_of() { { sha256sum < "$1" || shasum -a 256 < "$1"; } 2>/dev/null | awk '{ print $1 }'; }

IS_GIT=0
GIT_HOOKS_DST="$(cl_git_hooks_dir "$PROJECT_ROOT" 2>/dev/null)" || GIT_HOOKS_DST=""
if [ -n "$GIT_HOOKS_DST" ] && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
fi
COMMON_DIR=""; STATE_DIR=""
if [ "$IS_GIT" -eq 1 ]; then
  COMMON_DIR="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  STATE_DIR="$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"
fi

# Is the constitution a real submodule (gitlink, mode 160000) of the project?
IS_SUBMODULE=0
SUB_REL="$(cl_rel_path "$PROJECT_ROOT" "$CONST_DIR")"
_proot_phys="$(cd "$PROJECT_ROOT" && pwd -P)"
if [ "$IS_GIT" -eq 1 ]; then
  case "$SUB_REL" in
    ''|/*|..|../*|*/..|*/../*) ;;
    *)
      _super="$(git -C "$CONST_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
      if [ -n "$_super" ] && [ "$_super" = "$_proot_phys" ] && \
         git -C "$PROJECT_ROOT" --literal-pathspecs ls-files -s -- "$SUB_REL" 2>/dev/null | \
           awk -v p="$SUB_REL" -F '\t' '{ split($1, a, " ") } a[1] == "160000" && $2 == p { f = 1 } END { exit !f }'; then
        IS_SUBMODULE=1
      fi ;;
  esac
fi
CONSUMER_SRC="$SCRIPT_DIR/hooks/constitution-submodule-post-checkout"
SUB_HOOKS_DST=""
if [ "$IS_SUBMODULE" -eq 1 ]; then
  SUB_HOOKS_DST="$(cl_git_hooks_dir "$CONST_DIR" 2>/dev/null)" || SUB_HOOKS_DST=""
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  CHK_ERR=0
  info "Check-only mode: post_update_hook.sh parse check + installed-hook drift (nothing written)"
  if [ -x "$SCRIPT_DIR/post_update_hook.sh" ]; then
    if bash -n "$SCRIPT_DIR/post_update_hook.sh" 2>&1; then info "  post_update_hook.sh: OK"
    else error "  post_update_hook.sh: PARSE ERROR"; CHK_ERR=1; fi
  else
    error "  post_update_hook.sh: MISSING or not executable"; CHK_ERR=1
  fi
  # chk_drift LABEL INSTALLED SOURCE
  chk_drift() {
    if [ ! -f "$3" ]; then warn "  $1: no source $3"; return 0; fi
    if [ ! -f "$2" ] || [ -L "$2" ]; then
      error "  $1: NOT INSTALLED as a regular file at $2 — run setup.sh"; CHK_ERR=1
    elif cmp -s "$2" "$3"; then
      info "  $1: in sync (sha256 $(sha_of "$3"))"
    else
      error "  $1: DRIFT — installed $2 sha256 $(sha_of "$2") != source $3 sha256 $(sha_of "$3"); re-run setup.sh"
      CHK_ERR=1
    fi
  }
  if [ "$IS_GIT" -eq 1 ]; then
    chk_drift "project post-merge" "$GIT_HOOKS_DST/post-merge" "$SCRIPT_DIR/hooks/post-merge"
    if [ "$IS_SUBMODULE" -eq 1 ] && [ -n "$SUB_HOOKS_DST" ]; then
      chk_drift "submodule post-checkout consumer" "$SUB_HOOKS_DST/post-checkout" "$CONSUMER_SRC"
    fi
  else
    warn "  $PROJECT_ROOT is not a git work tree: installed hooks not checked"
  fi
  exit "$CHK_ERR"
fi

# Git hooks need a real git work tree; never fabricate a .git directory.
if [ "$IS_GIT" -ne 1 ]; then
  error "$PROJECT_ROOT is not a git work tree — cannot install git hooks (nothing written)."
  exit 1
fi
if [ -z "$COMMON_DIR" ] || [ ! -d "$COMMON_DIR" ] || [ -z "$STATE_DIR" ] || [ ! -d "$STATE_DIR" ]; then
  error "cannot resolve the git dirs of $PROJECT_ROOT (nothing written)."
  exit 1
fi
BACKUP_ROOT="$COMMON_DIR/constitution-hook-backup"

# A shared hooks dir (core.hooksPath at a non-local scope, or a hooks dir that
# PHYSICALLY resolves outside the repository, e.g. a symlinked .git/hooks):
# refuse BEFORE anything is written or run. Same for the submodule's hooks dir.
SUB_HOOKS_OK=1
_refuse=()
if ! chi_hooks_dir_check "$PROJECT_ROOT" "$GIT_HOOKS_DST" repo; then
  if [ "$ALLOW_GLOBAL_HOOKS" -eq 1 ]; then
    warn "$CHI_WHY: installing there anyway (--allow-global-hooks-path); every repository using that dir is affected."
  else
    _refuse+=("project: $CHI_WHY")
  fi
fi
if [ "$IS_SUBMODULE" -eq 1 ] && [ -n "$SUB_HOOKS_DST" ] && \
   ! chi_hooks_dir_check "$CONST_DIR" "$SUB_HOOKS_DST" gitdir; then
  SUB_HOOKS_OK=0; _sub_why="$CHI_WHY"
  [ "$ALLOW_GLOBAL_HOOKS" -eq 1 ] || _refuse+=("constitution submodule: $_sub_why")
fi
if [ "${#_refuse[@]}" -gt 0 ]; then
  for _r in "${_refuse[@]}"; do error "$_r."; done
  error "  Installing would REPLACE the post-merge/post-checkout hooks of every repository using it. Nothing written, nothing run."
  error "  Either use a repository-local hooks dir (git -C $(printf '%q' "$PROJECT_ROOT") config --local core.hooksPath .git/hooks,"
  error "  or replace a symlinked hooks dir by a real directory), or re-run with --allow-global-hooks-path if you really"
  error "  want to modify that shared dir (the submodule consumer is never installed outside the submodule's own git dir)."
  exit 1
fi

# ─── 2b. Trust model of auto-propagation (§11.4.164) ─────────────────

if [ -n "$AUTO_PROP" ]; then
  git -C "$PROJECT_ROOT" config --local constitution.autoPropagate "$AUTO_PROP" || {
    error "could not record constitution.autoPropagate=$AUTO_PROP"; exit 1; }
elif [ -z "$(git -C "$PROJECT_ROOT" config --get constitution.autoPropagate 2>/dev/null || true)" ]; then
  git -C "$PROJECT_ROOT" config --local constitution.autoPropagate true || \
    warn "could not record constitution.autoPropagate=true (auto-propagation stays on by default)"
fi
_ap_raw="$(git -C "$PROJECT_ROOT" config --get constitution.autoPropagate 2>/dev/null || true)"
_ap_eff="$(git -C "$PROJECT_ROOT" config --type=bool --get constitution.autoPropagate 2>/dev/null || true)"
info ""
info "Trust model of auto-propagation (§11.4.164):"
info "  after a pull / submodule update, the installed hooks RUN <constitution>/scripts/post_update_hook.sh"
info "  of the NEWLY CHECKED-OUT constitution commit (code fetched from the submodule's upstream),"
info "  automatically, only when that commit is reachable from the submodule's upstream default branch"
info "  (origin/HEAD, origin/main or origin/master as last fetched; the hooks never fetch) and is not a"
info "  downgrade; otherwise they print the manual command and run nothing (git has still checked it out)."
info "  The installed hooks are self-contained copies: they run nothing from the checkout before those checks."
info "  setup.sh itself (this run) runs THIS checkout's post_update_hook.sh WITHOUT these checks."
info "  NOT covered: a branch switch / checkout / reset that moves the submodule via submodule.recurse=true"
info "  or --recurse-submodules runs NO hook and prints nothing; re-run setup.sh (or post_update_hook.sh) after it."
if [ "$_ap_eff" = true ]; then
  info "  current choice: ON (git config constitution.autoPropagate=$_ap_raw)."
  info "  disable: git -C $(printf '%q' "$PROJECT_ROOT") config constitution.autoPropagate false  (or env CONSTITUTION_AUTO_PROPAGATE=off,"
  info "  or re-run setup.sh --auto-propagate=off)"
else
  info "  current choice: OFF (git config constitution.autoPropagate=${_ap_raw:-<unset>}); run post_update_hook.sh by hand after each update."
fi
case "$(printf '%s' "${CONSTITUTION_AUTO_PROPAGATE:-}" | tr 'A-Z' 'a-z')" in
  off|0|false|no) info "  NOTE: CONSTITUTION_AUTO_PROPAGATE=${CONSTITUTION_AUTO_PROPAGATE} disables it for processes with that env." ;;
esac

# ─── 2c. Run post-update hook ────────────────────────────────────────

# kv FILE KEY -> value of the first KEY= line (regular files only).
kv() { [ -f "$1" ] || return 1; local l; while IFS= read -r l; do case "$l" in "$2="*) printf '%s' "${l#"$2"=}"; return 0 ;; esac; done < "$1"; return 1; }
PENDING_STAMP="$STATE_DIR/constitution-pending-update"
APPLIED_REF="$STATE_DIR/constitution-applied-ref"
SUB_HEAD=""
RANGE_OLD=""; RANGE_NEW=""; CONSUME_STAMP=0
if [ "$IS_SUBMODULE" -eq 1 ]; then
  SUB_HEAD="$(git -C "$CONST_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [ "$(kv "$PENDING_STAMP" ROOT || true)" = "$_proot_phys" ] && [ "$(kv "$PENDING_STAMP" REL || true)" = "$SUB_REL" ] && \
     [ -n "$SUB_HEAD" ] && [ "$(kv "$PENDING_STAMP" NEW || true)" = "$SUB_HEAD" ]; then
    RANGE_OLD="$(kv "$PENDING_STAMP" OLD || true)"
    if [ -z "$RANGE_OLD" ] || [[ "$RANGE_OLD" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
      RANGE_NEW="$SUB_HEAD"; CONSUME_STAMP=1
    else
      RANGE_OLD=""
    fi
  fi
fi

info ""
info "Running post-update hook (skill registry + hook wiring) ..."
PU_RC=0; PU_LOCK_BUSY=0
# Take the SAME propagation lock as the git hooks (post-merge, the submodule
# post-checkout consumer), so setup.sh never runs the post-update hook while
# another propagation runs. Exclusive create only (bash noclobber = open
# O_CREAT|O_EXCL; nothing is created or opened when the path exists). A lock
# whose recorded owner is provably dead (SIGKILLed run) is reclaimed
# (pu_lock_reclaim_dead); a live or unprovable holder is reported and the run
# is INCOMPLETE (exit 1; the pending stamp is kept).
PU_LOCK=""; PU_NONCE="setup.$$.$(date +%s%N 2>/dev/null).${RANDOM}${RANDOM}"
pu_start() { local s f; [ -r "/proc/$1/stat" ] || return 0; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0; s="${s##*) }"; read -r -a f <<<"$s"; printf '%s' "${f[19]:-}"; }
pu_lock_mine() { [ -n "$PU_LOCK" ] && [ -f "$PU_LOCK" ] && [ ! -L "$PU_LOCK" ] && [ "$(kv "$PU_LOCK" NONCE 2>/dev/null || true)" = "$PU_NONCE" ]; }
pu_lock_release() { if pu_lock_mine; then rm -f -- "$PU_LOCK"; fi; }
pu_lock_create() { # exclusive create only; 0 iff THIS process now holds the lock
  { [ -e "$PU_LOCK" ] || [ -L "$PU_LOCK" ]; } && return 1
  ( set -o noclobber; printf 'PID=%s\nSTART=%s\nNONCE=%s\n' "$$" "$(pu_start "$$")" "$PU_NONCE" > "$PU_LOCK" ) 2>/dev/null && pu_lock_mine
}
# pu_lock_reclaim_dead — reclaim PU_LOCK iff it is a REGULAR file whose owner
# record names a process that is provably gone: no /proc/<pid> (needs a
# readable /proc), or the pid exists with a DIFFERENT start time than the
# recorded one (pid reused). A live holder, a lock without a readable owner
# record, a symlink or anything else is left alone (busy). The lock is moved
# aside by one rename; if the renamed file is not the snapshot judged dead
# (a live holder created a new lock meanwhile) it is linked back at once.
pu_lock_reclaim_dead() {
  local pid st nonce cur snap u pid2 st2 nonce2
  [ -d /proc/self ] || return 1
  [ -f "$PU_LOCK" ] && [ ! -L "$PU_LOCK" ] || return 1
  pid="$(kv "$PU_LOCK" PID || true)"; st="$(kv "$PU_LOCK" START || true)"; nonce="$(kv "$PU_LOCK" NONCE || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && [ -n "$nonce" ] || return 1
  if [ -d "/proc/$pid" ]; then
    cur="$(pu_start "$pid")"
    [ -n "$st" ] && [ -n "$cur" ] && [ "$st" != "$cur" ] || return 1   # alive (or unprovable): keep
  fi
  u="$PU_LOCK.stale.$PU_NONCE"
  mv -- "$PU_LOCK" "$u" 2>/dev/null || return 1
  pid2="$(kv "$u" PID || true)"; st2="$(kv "$u" START || true)"; nonce2="$(kv "$u" NONCE || true)"
  if [ "$pid2" != "$pid" ] || [ "$st2" != "$st" ] || [ "$nonce2" != "$nonce" ]; then
    ln -- "$u" "$PU_LOCK" 2>/dev/null && rm -f -- "$u"      # a live holder's new lock: put it back
    return 1
  fi
  rm -f -- "$u"
  warn "reclaimed a stale propagation lock $PU_LOCK: its owner pid $pid is gone (${st:+recorded start $st; }a SIGKILLed setup.sh / hook leaves one)."
  return 0
}
# pu_lock_describe — one line: the holder record (PID / START) and WHY the lock
# could not be reclaimed (for the busy message).
pu_lock_describe() {
  local pid st cur
  if [ -L "$PU_LOCK" ]; then printf 'the lock is a symlink (never followed or reclaimed)'; return 0; fi
  [ -f "$PU_LOCK" ] || { printf 'the lock path is not a regular file (never reclaimed)'; return 0; }
  pid="$(kv "$PU_LOCK" PID || true)"; st="$(kv "$PU_LOCK" START || true)"
  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then printf 'no readable owner record (PID=%s START=%s): an owner-less lock is never reclaimed by setup.sh' "${pid:-<none>}" "${st:-<none>}"; return 0; fi
  if [ ! -d /proc/self ]; then printf 'PID=%s START=%s; /proc is not readable, so the owner cannot be proven gone' "$pid" "${st:-<none>}"; return 0; fi
  if [ -d "/proc/$pid" ]; then
    cur="$(pu_start "$pid")"
    if [ -n "$st" ] && [ -n "$cur" ]; then printf 'PID=%s START=%s: the owner is ALIVE (its start time matches), so it is not stale' "$pid" "$st"
    else printf 'PID=%s START=%s: the owner pid is alive and its start time cannot be compared, so it is not provably stale' "$pid" "${st:-<none>}"; fi
  else printf 'PID=%s START=%s: the owner is gone but the lock could not be reclaimed (rename/put-back raced, or it changed meanwhile)' "$pid" "${st:-<none>}"; fi
}
if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ]; then
  PU_LOCK="$STATE_DIR/constitution-pending-update.lock"
  if pu_lock_create || { pu_lock_reclaim_dead && pu_lock_create; }; then
    trap pu_lock_release EXIT
  else
    PU_LOCK_BUSY=1
  fi
fi
if [ "$PU_LOCK_BUSY" -eq 1 ]; then
  PU_RC=75
  error "the propagation lock $PU_LOCK exists (another propagation is running, or a stale lock is left):"
  error "  holder record: $(pu_lock_describe)"
  error "  post_update_hook.sh was NOT run by this setup.sh; a pending stamp (if any) is kept."
  error "  When no other propagation is running (remove a stale lock first), re-run setup.sh."
elif [ "$CONSUME_STAMP" -eq 1 ]; then
  info "  consuming the pending update stamp: ${RANGE_OLD:0:8}..${RANGE_NEW:0:8} ($SUB_REL)"
  ( cd "$PROJECT_ROOT" && CONST_DIR="$CONST_DIR" PROJECT_ROOT="$PROJECT_ROOT" \
    CONSTITUTION_UPDATE_OLD_REF="$RANGE_OLD" CONSTITUTION_UPDATE_NEW_REF="$RANGE_NEW" \
    CONSTITUTION_PENDING_UPDATE_RUNNING=1 bash "$SCRIPT_DIR/post_update_hook.sh" --project-root "$PROJECT_ROOT" ) || PU_RC=$?
else
  ( cd "$PROJECT_ROOT" && CONST_DIR="$CONST_DIR" PROJECT_ROOT="$PROJECT_ROOT" \
    CONSTITUTION_PENDING_UPDATE_RUNNING=1 bash "$SCRIPT_DIR/post_update_hook.sh" --project-root "$PROJECT_ROOT" ) || PU_RC=$?
fi
if [ -n "$PU_LOCK" ] && [ "$PU_LOCK_BUSY" -eq 0 ]; then
  pu_lock_mine || warn "the propagation lock $PU_LOCK was no longer this setup.sh's when the post-update hook finished (removed meanwhile): another propagation may have run concurrently."
  pu_lock_release
fi
if [ "$PU_LOCK_BUSY" -eq 1 ]; then
  :
elif [ "$PU_RC" -ne 0 ]; then
  error ""
  error "post_update_hook.sh FAILED (exit $PU_RC) — see its output above. The git hooks are still"
  error "  installed below, but setup.sh will exit 1. No applied ref is recorded and a pending stamp is"
  error "  kept, so re-running setup.sh after fixing the cause retries the propagation."
elif [ "$IS_SUBMODULE" -eq 1 ] && [ -n "$SUB_HEAD" ]; then
  _t="$(mktemp "$STATE_DIR/.constitution-applied-ref.XXXXXX")" && \
    printf 'REL=%s\nREF=%s\n' "$SUB_REL" "$SUB_HEAD" > "$_t" && mv -f "$_t" "$APPLIED_REF" || \
    warn "could not record $APPLIED_REF"
  if [ "$CONSUME_STAMP" -eq 1 ]; then rm -f "$PENDING_STAMP"; fi
fi

# ─── 3. Install git hooks ────────────────────────────────────────────
# Only real git hook names are installed (scripts/hooks/ also holds Claude Code
# guards, test suites and caches that must never land in .git/hooks). A
# consumer hook that differs from ours is BACKED UP before it is replaced:
#   <git-common-dir>/constitution-hook-backup/<UTC timestamp>/<pass>/<name>
# An identical hook is left alone, so a re-run is a no-op.

HOOK_ERRORS=0
CONST_HOOK_NAMES=" "   # names installed by the constitution pass (collision check)

# install_one_hook SRC NAME LABEL [HOOKS_DIR] — scripts/lib/hook_install.sh
# (backup to $BACKUP_ROOT/<stamp>/<label>/<name>, never overwriting a backup;
# a symlink hook is backed up AS A LINK; other file types refused).
install_one_hook() {
  chi_install_hook "$1" "$2" "${3:-constitution}" "${4:-$GIT_HOOKS_DST}" "$BACKUP_ROOT" "$BACKUP_STAMP"
}

# install_hooks_from DIR LABEL
install_hooks_from() {
  local src_dir="$1" label="$2" hook name n=0
  for hook in "$src_dir"/*; do
    [ -f "$hook" ] || continue
    name="$(basename "$hook")"
    if ! cl_is_git_hook_name "$name"; then
      continue
    fi
    if [ "$label" = project ]; then
      case "$CONST_HOOK_NAMES" in
        *" $name "*)
          if ! cmp -s "$hook" "$SCRIPT_DIR/hooks/$name"; then
            error "  $name: hook-name COLLISION — project hook $hook and the constitution hook"
            error "    $SCRIPT_DIR/hooks/$name differ. The constitution hook stays installed;"
            error "    the project hook is NOT installed, and setup exits 1 on every run until"
            error "    this is resolved: rename $hook (e.g. to scripts/git_hooks/$name.project,"
            error "    which is not installed) and call it from your own wrapper, or make it"
            error "    byte-identical to the constitution hook; then re-run setup."
            HOOK_ERRORS=$((HOOK_ERRORS + 1))
            continue
          fi ;;
      esac
    fi
    # recorded even when its install fails: a project hook must never take
    # a constitution hook's name just because the constitution install failed.
    if [ "$label" = constitution ]; then CONST_HOOK_NAMES="$CONST_HOOK_NAMES$name "; fi
    if install_one_hook "$hook" "$name" "$label"; then
      n=$((n + 1))
    else
      HOOK_ERRORS=$((HOOK_ERRORS + 1))
    fi
  done
  info "$n $label git hook(s) in place"
}

info ""
info "Installing constitution git hooks into $GIT_HOOKS_DST"

# A hooks dir holding TRACKED files (core.hooksPath at a committed dir, or a
# .git/hooks SYMLINKED into the work tree; physical path): installing writes
# into tracked files (differing ones are backed up first).
if chi_tracked_hooks_dir "$PROJECT_ROOT" "$GIT_HOOKS_DST"; then
  warn "the git hooks dir (core.hooksPath / .git/hooks) $GIT_HOOKS_DST resolves to $CHI_TRACKED_PHYS, a directory TRACKED by the project:"
  warn "  installing hooks there modifies TRACKED files — review 'git status' before committing."
fi

if ! mkdir -p "$GIT_HOOKS_DST"; then
  error "cannot create the git hooks dir $GIT_HOOKS_DST"
  exit 1
fi
if [ -d "$SCRIPT_DIR/hooks" ]; then
  install_hooks_from "$SCRIPT_DIR/hooks" "constitution"
else
  warn "No hooks source dir: $SCRIPT_DIR/hooks"
fi

# ─── 3b. Pending-update consumer in the constitution SUBMODULE ───────

if [ "$IS_SUBMODULE" -ne 1 ]; then
  warn "the constitution at $CONST_DIR is not a submodule (gitlink) of $PROJECT_ROOT:"
  warn "  the pending-update consumer hook was NOT installed; after a 'git pull' that moves the"
  warn "  constitution, run its scripts/post_update_hook.sh from the project root by hand."
elif [ ! -f "$CONSUMER_SRC" ]; then
  warn "No consumer hook source: $CONSUMER_SRC"
elif [ "$SUB_HOOKS_OK" -ne 1 ]; then
  warn "the constitution submodule's hooks dir $SUB_HOOKS_DST is outside its own git dir ($_sub_why):"
  warn "  the pending-update consumer hook was NOT installed there (never, even with --allow-global-hooks-path);"
  warn "  after a 'git pull' run post_update_hook.sh from the project root by hand."
else
  info ""
  info "Installing the pending-update consumer into the submodule hooks dir $SUB_HOOKS_DST"
  if [ -z "$SUB_HOOKS_DST" ] || ! mkdir -p "$SUB_HOOKS_DST"; then
    error "  cannot resolve or create the submodule hooks dir"; HOOK_ERRORS=$((HOOK_ERRORS + 1))
  elif ! install_one_hook "$CONSUMER_SRC" post-checkout submodule "$SUB_HOOKS_DST"; then
    HOOK_ERRORS=$((HOOK_ERRORS + 1))
  fi
fi

# ─── 4. Install project-level git hooks (project-side) ───────────────

PROJECT_HOOKS="$PROJECT_ROOT/scripts/git_hooks"
if [ -d "$PROJECT_HOOKS" ]; then
  info ""
  info "Installing project-level git hooks"
  install_hooks_from "$PROJECT_HOOKS" "project"
fi

if [ "$HOOK_ERRORS" -ne 0 ]; then
  error "$HOOK_ERRORS git hook(s) could not be installed — see above."
fi
if [ "$PU_LOCK_BUSY" -eq 1 ]; then
  error "post_update_hook.sh was NOT run (the propagation lock is busy): setup is INCOMPLETE — re-run setup.sh when no other propagation runs."
elif [ "$PU_RC" -ne 0 ]; then
  error "post_update_hook.sh failed (exit $PU_RC): setup is INCOMPLETE — fix the cause reported above and re-run setup.sh."
fi
if [ "$HOOK_ERRORS" -ne 0 ] || [ "$PU_RC" -ne 0 ]; then
  exit 1
fi

info ""
info "Constitution setup complete."
info "Hooks installed. Re-run after every constitution submodule update."
