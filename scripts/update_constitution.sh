#!/usr/bin/env bash
# update_constitution.sh — risk-free, fast-forward-only update of the constitution submodule in a project.
#
# ── Usage (from a consuming project) ──────────────────────────────────────
#   bash submodules/constitution/scripts/update_constitution.sh [--check] [--ref REF] [--dry-run]
#        [--no-hook] [--jev-hook] [--commit] [--project-root DIR]
#   (the legacy layout works too: bash constitution/scripts/update_constitution.sh ...)
#
# ── What it does ──────────────────────────────────────────────────────────
#   1. Finds the submodule it lives in and the project that records it (both layouts).
#   2. Refuses (exit 3) if the submodule has local changes.
#   3. Fetches every remote (tags included). If every fetch fails: exit 3 (network).
#      Refuses (exit 3) if HEAD is not on any remote branch nor in a tag the REMOTE has (unpushed work; a tag
#      that exists only locally does not count: remote tags are read with `git ls-remote --tags`).
#   4. Target: --ref, else the newest RELEASE tag on a remote (helixconstitution-vN(.N)*, version order:
#      v9 < v10 < v100; pre-release tags such as -rc1 are never chosen by default), else origin/main.
#   5. Only a FAST-FORWARD is accepted: target == HEAD or behind HEAD => "already up to date" (exit 0);
#      diverged => refuse (exit 3). Never force, never reset, never rebase, never push.
#   6. Checks the target out (detached), runs scripts/post_update_hook.sh from the project root with
#      CONSTITUTION_JEV_HOOK=off (unless --jev-hook; skipped with --no-hook), prints before/after sha and
#      the changelog delta, and stages the new gitlink in the project (commits only with --commit).
#   --check and --dry-run are not offline: they still run step 3 (git fetch --quiet --tags per remote), which
#   updates the submodule's remote-tracking refs and tags; they never move HEAD or a local branch, never touch
#   the working tree, and never change the project.
#   git runs with a sanitised environment: inherited GIT_* variables are dropped (except the config-file
#   selection, author/committer identity, CA bundle and protocol limits) and ssh is always
#   "ssh -o BatchMode=yes -o ConnectTimeout=10"; put ssh keys/ports in ~/.ssh/config, not GIT_SSH_COMMAND.
#
# ── Interrupted runs ──────────────────────────────────────────────────────
#   An update cut off after the submodule checkout (killed, or `git add` failed because the project's
#   .git/index.lock was held) is FINISHED by the next run, never reported as "already up to date": the run
#   compares the submodule HEAD with the gitlink the project records, stages it, and runs the post-update hook if
#   a marker (.git/helix-update-pending in the project, written before the checkout, removed after the hook)
#   says the earlier hook never finished; with --commit it also commits a gitlink an earlier run staged.
#   --check then prints UPDATE_AVAILABLE=yes. LIMITS: the hook is re-run only while that marker exists (not when
#   --no-hook was used); a submodule HEAD that is AHEAD of the target with an older recorded gitlink is only
#   reported (NOTE), never staged; a commit made by --commit that is cut off half-way is git's own atomic step.
#   A gitlink the project records (staged or committed) is only ever replaced by a DESCENDANT of it. When the
#   project records a commit NEWER than the submodule checkout (a teammate bumped it and `git pull` did not move
#   the checkout), a commit that is not in the checkout, or a commit that has DIVERGED from it, the run refuses
#   (exit 3; --check and --dry-run too) and stages nothing: run `git submodule update -- <path>` first. Only a
#   recorded gitlink that is an ANCESTOR of the checkout counts as an update that was cut off. A STAGED gitlink
#   that differs from both the committed gitlink and the checkout (a change somebody staged) is never overwritten:
#   exit 3 on every path, unless the marker (written before every checkout, with or without the hook) is honoured:
#   it names the checkout AND its "staged-before" field equals the gitlink staged now (so a change somebody staged
#   after this script's own update was cut off is never taken for it); then that update is finished.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 updated or already up to date (--check: printed UPDATE_AVAILABLE=yes|no) · 1 post-update hook or
#   checkout failed · 2 usage · 3 blocked (dirty, unpushed, diverged, network, not a submodule, root = itself)
#
# Classification: universal (§11.4.17). Honours §11.4.113 (no force/reset/push) and §9.2 (no commit lost).
set -uo pipefail
# >>> hi_text_safe (identical in install_constitution.sh and update_constitution.sh)
# THE sanitiser for every byte this script did not write itself: text from git (log subjects, tag and branch
# names), from the agent, from the project's own paths, from an upstream CHANGELOG. Nothing external is printed
# raw: the emitters (hi_say/hi_warn/hi_err/hi_out, say/die) call it, and tests/install/test_unit.sh fails on a
# print site that does not go through an emitter. It keeps printable text (tab and newline too) and drops every
# control character (C0, DEL, C1), every format character (bidi controls such as U+061C, U+200E/F, U+202A-E,
# U+2066-9), the line and paragraph separators U+2028/2029 and private-use, unassigned and surrogate code
# points. Invalid UTF-8 (a raw 0x9B is a one-byte CSI to some terminals) becomes "?". Without python3 only
# printable ASCII survives. Output of child processes (setup.sh, the updater, the agent's own terminal) is
# theirs and is not filtered.
hi_text_filter() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import sys, unicodedata
t = sys.stdin.buffer.read().decode("utf-8", "replace").replace("�", "?")
sys.stdout.buffer.write("".join(c for c in t if c in "\t\n" or unicodedata.category(c) not in ("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp")).encode("utf-8"))
'
  else
    LC_ALL=C tr -cd '\11\12\40-\176'
  fi
}
hi_term_safe() { printf '%s' "$1" | hi_text_filter; }
# <<< hi_text_safe
say() { printf '[update-constitution] %s\n' "$(hi_term_safe "$*")" >&2; }
die() { local c="$1"; shift; printf '[update-constitution] ERROR: %s\n' "$(hi_term_safe "$*")" >&2; exit "$c"; }
usage() { sed -n '2,/^# Classification/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
# >>> hi_gx — the ONLY code in this file that runs git (CM-INSTALLER-NO-PUSH-NO-FORCE). This block is byte-identical
# in install_constitution.sh and update_constitution.sh; the gate compares the two copies, extracts the allow-list
# below and calls the wrapper with every forbidden form to prove it refuses at RUNTIME.
#   hi_gx [-C DIR] [-c protocol.file.allow=always] [--no-optional-locks] SUBCOMMAND ARGS...
# The check sees the words git would see, however the call was spelled (${P}ush, $'\x70ush', p\ush all arrive as
# "push"), so anything not listed is refused with exit 3 and a message. Subcommands that reach a remote or change
# refs/config are allowed ONLY in the exact shapes the two scripts use (fetch --quiet --tags REMOTE, clone --quiet
# [--filter=blob:none] --no-checkout -- URL DIR, …); a word starting with "+" (a forced refspec) or containing "::"
# (a transport helper such as ext::) is refused wherever it stands, also after "--". git itself is resolved ONCE to
# an absolute path (hi_gx_bin) and runs with a sanitised environment: every inherited GIT_* variable is removed
# except the user's config-file selection, author/committer identity, CA bundle and protocol restrictions, and
# GIT_SSH_COMMAND is always the installer's own non-interactive ssh. Options: HI_GX_TIMEOUT=N (seconds, via
# timeout); HI_GX_COMMIT_OK=1 (set once, only when a commit was asked for); HI_GX_INIT_OK=1 (only after consent).
hi_gx_refuse() {
  local m; m="$(printf '%s ' "$@" | sed -E 's|(://)[^/?#[:space:]]*@|\1|g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\1REDACTED/g' | LC_ALL=C tr -cd '\40-\176')"
  if { true >&9; } 2>/dev/null; then printf '[git-allowlist] ERROR: refused git call (not on the allow-list): %s\n' "$m" >&9
  else printf '[git-allowlist] ERROR: refused git call (not on the allow-list): %s\n' "$m" >&2; fi
  return 3
}
hi_gx_repo_ok() { case "$1" in ""|-*|+*|*::*) return 1 ;; esac; return 0; }   # a URL/path/remote word
hi_gx_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]; }              # a remote name
hi_gx_check() { # SUBCOMMAND ARGS... → 0 allowed, 3 refused (read-only; never runs git)
  local sub="${1:-}" a cached=0 dd=0; [ $# -gt 0 ] && shift
  local -a c=()
  for a in "$@"; do # every word, also after "--": no forced refspec, no transport helper
    case "$a" in +*|*::*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac
  done
  for a in "$@"; do # options that rewrite history, discard work, move refs, run commands or write outside the repo
    [ "$a" = -- ] && break
    case "$a" in
      --force|--force=*|--force-*|--amend|--hard|--mirror|--delete|--prune|--prune=*|--prune-tags|--upload-pack*|\
      --receive-pack*|--exec|--exec=*|--output|--output=*|--ext-diff|--template|--template=*|--config|--config=*|\
      --recurse-submodules*|--recursive|--refmap*|--update-head-ok|--separate-git-dir*|--reference*|--shared|\
      --fixup*|--squash*|--orphan*)
        hi_gx_refuse "$sub" "$@"; return 3 ;;
      -[A-Za-z]*) [ "$sub" = config ] && [ "$a" = -f ] && continue
        case "$a" in -*[fuc]*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac ;;
    esac
  done
  case "$sub" in
    rev-parse|rev-list|ls-files|ls-tree|status|show|log|diff|merge-base|for-each-ref|cat-file|check-ref-format) return 0 ;; # HI_GX_ALLOW
    fetch) # HI_GX_ALLOW — only: fetch --quiet --tags REMOTE-NAME (default refspec: remote-tracking refs and tags only)
      [ $# = 3 ] && [ "$1" = --quiet ] && [ "$2" = --tags ] && hi_gx_name_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    clone) # HI_GX_ALLOW — only: clone --quiet [--filter=blob:none] --no-checkout -- URL DIR
      c=("$@"); [ "${c[1]:-}" = --filter=blob:none ] && c=("${c[0]}" "${c[@]:2}")
      [ "${#c[@]}" = 5 ] && [ "${c[0]}" = --quiet ] && [ "${c[1]}" = --no-checkout ] && [ "${c[2]}" = -- ] \
        && hi_gx_repo_ok "${c[3]}" && hi_gx_repo_ok "${c[4]}" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    ls-remote) # HI_GX_ALLOW — only: ls-remote [--tags|--heads] [--] REPO [PATTERN]
      c=("$@"); case "${c[0]:-}" in --tags|--heads) c=("${c[@]:1}") ;; esac
      [ "${c[0]:-}" = -- ] && c=("${c[@]:1}")
      [ "${#c[@]}" -ge 1 ] && [ "${#c[@]}" -le 2 ] && hi_gx_repo_ok "${c[0]}" && hi_gx_repo_ok "${c[1]:-x}" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    add) # HI_GX_ALLOW — only: add -- PATH...
      [ $# -ge 2 ] && [ "$1" = -- ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    checkout) # HI_GX_ALLOW — only: checkout [-q|--quiet] --detach <full commit sha>
      [ $# -ge 2 ] && [[ "${!#}" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && [[ " $* " == *" --detach "* ]] || { hi_gx_refuse "$sub" "$@"; return 3; }
      for a in "${@:1:$(($# - 1))}"; do case "$a" in -q|--quiet|--detach) ;; *) hi_gx_refuse "$sub" "$@"; return 3 ;; esac; done
      return 0 ;;
    rm) # HI_GX_ALLOW — only: rm [-q] --cached [--ignore-unmatch] -- PATH... (the files stay)
      for a in "$@"; do
        [ "$dd" = 1 ] && continue
        case "$a" in --) dd=1 ;; --cached) cached=1 ;; -q|--quiet|--ignore-unmatch) ;; *) hi_gx_refuse "$sub" "$@"; return 3 ;; esac
      done
      [ "$cached" = 1 ] && [ "$dd" = 1 ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    config) # HI_GX_ALLOW — reads; writes only the installer marker and submodule.* sections
      c=("$@"); if [ "${c[0]:-}" = -f ]; then [ "${#c[@]}" -ge 3 ] || { hi_gx_refuse "$sub" "$@"; return 3; }; c=("${c[@]:2}"); fi
      case "${c[0]:-}" in
        --get|--get-all|--get-regexp|--list) return 0 ;;
        --remove-section) [ "${#c[@]}" = 2 ] && [[ "${c[1]}" == submodule.* ]] && return 0 ;;
        --unset) [ "${#c[@]}" = 2 ] && [ "${c[1]}" = helix-installer.clone ] && return 0 ;;
        helix-installer.clone) [ "${#c[@]}" = 2 ] && [ "${c[1]}" = true ] && return 0 ;;
      esac
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    remote) # HI_GX_ALLOW — only: remote | remote get-url NAME | remote set-url origin /ABSOLUTE/PATH
      [ $# = 0 ] && return 0
      [ "$1" = get-url ] && [ $# = 2 ] && hi_gx_name_ok "$2" && return 0
      [ "$1" = set-url ] && [ $# = 3 ] && [ "$2" = origin ] && [[ "$3" == /* ]] && hi_gx_repo_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    submodule) # HI_GX_ALLOW — only: add --quiet -- URL PATH | update --init --quiet -- PATH | absorbgitdirs -- PATH
      [ "${1:-}" = add ] && [ $# = 5 ] && [ "$2" = --quiet ] && [ "$3" = -- ] && hi_gx_repo_ok "$4" && hi_gx_repo_ok "$5" && return 0
      [ "${1:-}" = update ] && [ $# = 5 ] && [ "$2" = --init ] && [ "$3" = --quiet ] && [ "$4" = -- ] && hi_gx_repo_ok "$5" && return 0
      [ "${1:-}" = absorbgitdirs ] && [ $# = 3 ] && [ "$2" = -- ] && hi_gx_repo_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    commit) # HI_GX_ALLOW (only after --commit) — only: commit -q -m MESSAGE -- PATH...
      [ "${HI_GX_COMMIT_OK:-0}" = 1 ] && [ $# -ge 5 ] && [ "$1" = -q ] && [ "$2" = -m ] && [ "$4" = -- ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    init) # HI_GX_ALLOW (only after consent) — only: init -q
      [ "${HI_GX_INIT_OK:-0}" = 1 ] && [ $# = 1 ] && [ "$1" = -q ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    *) hi_gx_refuse "$sub" "$@"; return 3 ;;
  esac
}
hi_gx_bin() { # git resolved ONCE to an absolute path: a later PATH change cannot swap the binary
  [ -n "${HI_GX_BIN:-}" ] && return 0
  HI_GX_BIN="$(command -v git 2>/dev/null)"
  [[ "$HI_GX_BIN" == /* ]] && [ -x "$HI_GX_BIN" ] && return 0
  HI_GX_BIN=""; hi_gx_refuse "(git is not installed as an executable file on PATH)"; return 3
}
hi_gx() {
  local -a pre=(); local v
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) [ $# -ge 2 ] || { hi_gx_refuse "$@"; return 3; }; pre+=(-C "$2"); shift 2 ;;
      -c) [ "${2:-}" = protocol.file.allow=always ] || { hi_gx_refuse "$@"; return 3; }; pre+=(-c "$2"); shift 2 ;;
      --no-optional-locks) pre+=("$1"); shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { hi_gx_refuse "(no subcommand)"; return 3; }
  hi_gx_check "$@" || return 3
  hi_gx_bin || return 3
  ( # sanitised environment, in a subshell (the caller's variables stay as they are)
    for v in ${!GIT_*}; do
      case "$v" in
        GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_CEILING_DIRECTORIES|GIT_AUTHOR_*|GIT_COMMITTER_*|\
        GIT_SSL_CAINFO|GIT_SSL_CAPATH|GIT_ALLOW_PROTOCOL|GIT_PROTOCOL_FROM_USER) ;;
        *) unset "$v" ;;
      esac
    done
    export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
    if [ -n "${HI_GX_TIMEOUT:-}" ]; then exec timeout "$HI_GX_TIMEOUT" "$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"
    else exec "$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"; fi
  )
}
# <<< hi_gx
HI_GX_COMMIT_OK=0; HI_GX_INIT_OK=0; HI_GX_BIN=""; unset HI_GX_TIMEOUT
# >>> hi_remote_live (identical in install_constitution.sh and update_constitution.sh)
# What a remote has RIGHT NOW. `git fetch` never prunes (the wrapper forbids --prune), so refs/remotes/* keeps a
# branch the remote deleted long ago, and a local tag can name a commit no remote has: neither proves that a
# commit can be fetched by a fresh clone. Reachability is therefore always proved against the commit ids the
# remote advertises at this moment (ls-remote), never against refs/remotes/* or local tags. A remote that
# cannot be asked contributes nothing: unproven counts as not reachable.
# dir remote → the advertised commit ids (branches first, then tags, annotated tags unpeeled and peeled), one per line
hi_remote_live() {
  local d="$1" r="$2" k
  for k in --heads --tags; do
    HI_GX_TIMEOUT=60 hi_gx -C "$d" ls-remote "$k" "$r" 2>/dev/null \
      | awk '$1 ~ /^[0-9a-f]+$/ && (length($1) == 40 || length($1) == 64) { print $1 }'
  done
}
# dir remote → "name object-sha" of every tag the remote really has (annotated tags unpeeled; local-only tags never count)
hi_remote_tags_of() {
  HI_GX_TIMEOUT=60 hi_gx -C "$1" ls-remote --tags "$2" 2>/dev/null \
    | awk '$2 !~ /\^\{\}$/ { n = $2; sub(/^refs\/tags\//, "", n); print n, $1 }'
}
# dir sha live → 0 when sha is one of the live commits or an ancestor of one (so a fresh clone can fetch it)
hi_on_remote() {
  local l
  [[ "$2" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || return 1
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ "$l" = "$2" ] && return 0
    hi_gx -C "$1" merge-base --is-ancestor "$2" "$l" 2>/dev/null && return 0
  done <<<"$3"
  return 1
}
# <<< hi_remote_live
# >>> hi_gitlink_rel (identical in install_constitution.sh and update_constitution.sh)
# dir head recorded → how a gitlink the project RECORDS relates to the submodule checkout's HEAD:
#   same · recorded-older (a strict ancestor of HEAD: an update that was cut off) · recorded-newer (HEAD is a strict
#   ancestor of it: the checkout is stale) · diverged · unknown (the commit is not in the checkout).
# Only "same" and "recorded-older" may be replaced by the updater; every other answer is a refusal.
hi_gitlink_rel() {
  local d="$1" a="$2" b="$3"
  [ "$a" = "$b" ] && { printf same; return 0; }
  [[ "$b" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && hi_gx -C "$d" cat-file -e "$b^{commit}" 2>/dev/null || { printf unknown; return 0; }
  if hi_gx -C "$d" merge-base --is-ancestor "$b" "$a" 2>/dev/null; then printf recorded-older
  elif hi_gx -C "$d" merge-base --is-ancestor "$a" "$b" 2>/dev/null; then printf recorded-newer
  else printf diverged; fi
}
# dir relpath → the gitlink the HEAD COMMIT of dir records for that submodule (empty when none / no commit yet)
hi_gitlink_committed() {
  local l; l="$(hi_gx -C "$1" ls-tree HEAD -- "$2" 2>/dev/null | head -n 1)"
  case "$l" in "160000 commit "*) l="${l#160000 commit }"; printf '%s' "${l%%[[:space:]]*}" ;; esac
}
# <<< hi_gitlink_rel
# Release tags only, no part with a leading zero: the SAME regex as the installer and the setup prompt
# (tests/install/test_unit.sh fails if they drift apart).
HI_RELEASE_TAG_RE='^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$'
# Run lock: the SAME file as the installer's (<project git dir>/helix-constitution-install.lock), so an installer
# run and an updater run never change one project at the same time. The lock is created with link(2): `ln` fails
# on ANY existing path and never opens it, so a FIFO or symlink planted there is refused, not followed (bash
# noclobber would open a FIFO and block; mkdir is not an exclusive create on every host and is never used here).
# A stale lock (its pid is gone) is reclaimed under a second exclusive marker (LOCK.reclaim); a marker left by a
# run that was killed in the middle of a reclaim is reported, never removed (delete it by hand).
UP_LOCK=""; UP_ROOT=""; UP_LOCK_FILE=""
# >>> hi_lock_helpers (identical in install_constitution.sh and update_constitution.sh)
# pid lockfile → 0 when that pid may still be the process that wrote the lock. Only "No such process" counts
# as gone: "Operation not permitted" (a process of another user, or init) counts as alive. On Linux a process
# that started after the lock file was last written cannot have written it (its pid was reused): gone. When
# the start time cannot be read, the pid counts as alive (refuse rather than take a live run's lock).
hi_holder_alive() {
  local p="$1" f="$2" msg st hz bt start mt
  [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 0 ] || return 1
  if ! msg="$(LC_ALL=C kill -0 "$p" 2>&1)"; then
    case "$msg" in *"No such process"*) return 1 ;; esac
  fi
  st="$(cat "/proc/$p/stat" 2>/dev/null)" || return 0
  st="${st##*) }"; read -r -a st <<<"$st"; start="${st[19]:-}"
  hz="$(getconf CLK_TCK 2>/dev/null)"; bt="$(awk '$1 == "btime" { print $2; exit }' /proc/stat 2>/dev/null)"
  mt="$(stat -c %Y -- "$f" 2>/dev/null || stat -f %m -- "$f" 2>/dev/null)"
  [[ "$start" =~ ^[0-9]+$ && "$hz" =~ ^[1-9][0-9]*$ && "$bt" =~ ^[0-9]+$ && "$mt" =~ ^[0-9]+$ ]] || return 0
  [ $((bt + start / hz)) -gt $((mt + 2)) ] && return 1
  return 0
}
# TEST SEAM, honoured only with HELIX_INSTALLER_TEST=1: at the point named by HELIX_INSTALLER_TEST_PAUSE print
# "TEST PAUSE <point>" and wait (at most 60 s) until the file HELIX_INSTALLER_TEST_RESUME exists.
hi_test_pause() {
  [ "${HELIX_INSTALLER_TEST:-}" = 1 ] && [ -n "${HELIX_INSTALLER_TEST_PAUSE:-}" ] && [ "$HELIX_INSTALLER_TEST_PAUSE" = "$1" ] \
    && [ -n "${HELIX_INSTALLER_TEST_RESUME:-}" ] || return 0
  local n=0
  printf 'TEST PAUSE %s\n' "$1" >&2
  while [ ! -e "$HELIX_INSTALLER_TEST_RESUME" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
  return 0
}
# <<< hi_lock_helpers
UP_TMP=""; UP_RECLAIM=""
up_lock_pid() { # [FILE] → the pid recorded in FILE (default: our lock), read only from a regular non-symlink file (never blocks)
  local f="${1:-$UP_LOCK}"
  [ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] || return 1
  timeout 5 head -c 20 -- "$f" 2>/dev/null | tr -cd '0-9'
}
# UP_LOCK is set ONLY after this process created the lock file itself (ln succeeded): the EXIT/INT/TERM trap runs
# up_unlock at any point of up_lock, and it must never remove a lock that another run holds. The private temp
# file and the reclaim marker are tracked (UP_TMP, UP_RECLAIM) and removed by up_unlock, also after a signal.
up_lock() { # → 0 the lock is ours (or the installer that started us holds it); 3 refused
  local gd pid pid2 tmp lockp dlg="${HELIX_CONSTITUTION_LOCK_DELEGATED-}"
  unset HELIX_CONSTITUTION_LOCK_DELEGATED   # never passed on (the post-update hook, or anything it starts)
  gd="$(hi_gx -C "$UP_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$gd" ] || return 3
  lockp="$gd/helix-constitution-install.lock"; UP_LOCK_FILE="$lockp"
  # Hand-over: the installer runs the updater as a child while holding this lock and names its own pid in
  # HELIX_CONSTITUTION_LOCK_DELEGATED. It is honoured only when that exact pid is recorded in the lock right
  # now and is alive; the updater then works under that lock and never removes it (UP_LOCK stays empty).
  if [ -n "$dlg" ]; then
    pid="$(up_lock_pid "$lockp")"
    if [[ "$dlg" =~ ^[1-9][0-9]*$ ]] && [ "$pid" = "$dlg" ] && [ "$pid" != "$$" ] && hi_holder_alive "$pid" "$lockp"; then
      say "running under the installer's lock (pid $pid)"; return 0; fi
  fi
  tmp="$(mktemp "$lockp.XXXXXX" 2>/dev/null)" || { say "cannot create a temp file next to $lockp"; return 3; }
  UP_TMP="$tmp"
  printf '%s\n' "$$" >"$tmp" || { up_unlock; return 3; }
  if ln -- "$tmp" "$lockp" 2>/dev/null; then UP_LOCK="$lockp"; up_unlock_tmp; return 0; fi
  if [ ! -e "$lockp" ] && [ ! -L "$lockp" ]; then   # the create failed although nothing is there
    up_unlock; say "cannot create the lock $lockp (is ln on PATH and the git directory writable? if another run just finished, run again)"; return 3; fi
  if [ -L "$lockp" ] || [ ! -f "$lockp" ]; then
    up_unlock; say "$lockp exists and is not a regular file (symlink, FIFO, ...); not touching it - remove it yourself"; return 3; fi
  pid="$(up_lock_pid "$lockp")"
  hi_test_pause up_lock_read
  if [ -n "$pid" ] && [ "$pid" != "$$" ] && hi_holder_alive "$pid" "$lockp"; then
    up_unlock; say "another installer or updater run (pid $pid) holds $lockp"; return 3; fi
  hi_test_pause reclaim
  if ! ln -- "$tmp" "$lockp.reclaim" 2>/dev/null; then
    up_unlock; say "another run is reclaiming $lockp (if none is running, remove $lockp.reclaim by hand)"; return 3; fi
  UP_RECLAIM="$lockp.reclaim"
  pid2="$(up_lock_pid "$lockp")"   # re-read under the reclaim marker: another run may already have replaced the stale lock
  if [ "$pid2" != "$pid" ] || [ -L "$lockp" ]; then
    up_unlock; say "another run took $lockp"; return 3; fi
  say "removing a stale lock (pid ${pid:-?} is gone)"
  rm -f -- "$lockp"
  if ln -- "$tmp" "$lockp" 2>/dev/null; then UP_LOCK="$lockp"; up_unlock_tmp; return 0; fi
  up_unlock; say "cannot take the lock $lockp"; return 3
}
up_holder_pid() { local UP_LOCK="$UP_LOCK_FILE"; up_lock_pid; }   # pid holding the run lock now (ours or the installer's)
up_unlock_tmp() { # our private temp file and, once taken, our reclaim marker (never anyone else's)
  [ -n "$UP_TMP" ] && rm -f -- "$UP_TMP"
  UP_TMP=""
  [ -n "$UP_RECLAIM" ] && [ "$(up_lock_pid "$UP_RECLAIM")" = "$$" ] && rm -f -- "$UP_RECLAIM"
  UP_RECLAIM=""
  return 0
}
up_unlock() { # removes the lock only while it still records this process
  up_unlock_tmp
  [ -n "$UP_LOCK" ] && [ "$(up_lock_pid "$UP_LOCK")" = "$$" ] && rm -f -- "$UP_LOCK"
  UP_LOCK=""
  return 0
}
if [ "${HELIX_UPDATER_LIB_MODE:-}" = 1 ]; then   # tests source the functions above without running anything
  (return 0 2>/dev/null) && return 0   # only a SOURCED copy stops here
  printf 'update_constitution.sh: WARNING: ignoring HELIX_UPDATER_LIB_MODE=1 (a test switch for sourcing; this file is being run)\n' >&2
fi
exec 9>&2   # hi_gx refusals reach the user even when a call's stderr is redirected
hi_gx_bin || exit 3   # git resolved once, before anything can change PATH

CHECK=0; REF=""; DRY=0; HOOK=1; JEV=off; COMMIT=0; ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --no-hook) HOOK=0; shift ;;
    --jev-hook) JEV=on; shift ;;
    --commit) COMMIT=1; shift ;;
    --ref|--project-root)
      [ $# -ge 2 ] || die 2 "$1 needs a value"
      case "$2" in -*|"") die 2 "invalid value for $1" ;; esac
      [[ "$2" != *$'\n'* ]] || die 2 "invalid value for $1"
      if [ "$1" = --ref ]; then REF="$2"; else ROOT="$2"; fi; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die 2 "unknown argument: $(printf '%q' "$1")" ;;
  esac
done
[ "$COMMIT" = 1 ] && HI_GX_COMMIT_OK=1   # the only place that enables git commit (CM-INSTALLER-NO-PUSH-NO-FORCE)
if [ -n "$REF" ]; then
  [[ "$REF" =~ ^[A-Za-z0-9._/-]{1,200}$ ]] || die 2 "invalid --ref"
  [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]] || hi_gx check-ref-format --allow-onelevel "$REF" >/dev/null 2>&1 || die 2 "invalid --ref"
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUB="$(hi_gx -C "$here/.." rev-parse --show-toplevel 2>/dev/null)" || die 3 "not inside a git checkout of the constitution"
if [ -z "$ROOT" ]; then
  ROOT="$(hi_gx -C "$SUB" rev-parse --show-superproject-working-tree 2>/dev/null)"
  [ -n "$ROOT" ] || die 3 "the constitution at $SUB is not a submodule of a project (pass --project-root)"
fi
ROOT="$(cd -P -- "$ROOT" 2>/dev/null && pwd)" || die 2 "project root does not exist"
SUB="$(cd -P -- "$SUB" && pwd)"
case "$ROOT/" in "$SUB"/*) die 3 "the project root $ROOT is the constitution repository itself (or a directory inside it); refusing: run the updater from the project that records the constitution as a submodule (nothing changed)" ;; esac
case "$SUB/" in "$ROOT"/?*) REL="${SUB#"$ROOT"/}" ;; *) die 3 "$SUB is not inside the project $ROOT" ;; esac
hi_gx -C "$ROOT" ls-files -s -- "$REL" | grep -q '^160000 ' || die 3 "$REL is not a registered submodule of $ROOT"

UP_ROOT="$ROOT"
trap 'up_unlock' EXIT; trap 'exit 130' INT; trap 'exit 143' HUP TERM   # BEFORE any lock work
up_lock || die 3 "could not take the run lock of $ROOT (see above); nothing changed"
if [ -n "$(hi_gx -C "$SUB" status --porcelain 2>/dev/null)" ]; then
  PEND0="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"
  case "$PEND0" in /*|"") ;; *) PEND0="$ROOT/$PEND0" ;; esac
  if [ -n "$PEND0" ] && [ -f "$PEND0" ] && [ ! -L "$PEND0" ]; then
    die 3 "$REL has uncommitted changes and an earlier update to $(head -n 1 -- "$PEND0" 2>/dev/null | cut -d' ' -f1 | head -c 64 | tr -cd '0-9a-f') was interrupted (marker $PEND0): the changes are most likely that half-written checkout, not yours. Review them with: git -C $REL status; if none are yours: git -C $REL stash (keeps a copy) then re-run this script (nothing changed)"
  fi
  die 3 "$REL has local changes; commit/push or stash them first (nothing changed)"
fi
export GIT_TERMINAL_PROMPT=0
fetched=0; RTAGS=""; RLIVE=""   # RTAGS: "name object-sha" of every tag a reachable remote really has; RLIVE: every commit id the remotes advertise now
while read -r r; do
  [ -n "$r" ] || continue
  if HI_GX_TIMEOUT=300 hi_gx -C "$SUB" fetch --quiet --tags "$r" >/dev/null 2>&1; then
    fetched=$((fetched+1))
    RTAGS+="$(hi_remote_tags_of "$SUB" "$r")"$'\n'
    RLIVE+="$(hi_remote_live "$SUB" "$r")"$'\n'
  else say "fetch from remote '$r' failed"; fi
done < <(hi_gx -C "$SUB" remote)
[ "$fetched" -gt 0 ] || die 3 "could not fetch from any remote of $REL (network down?); nothing changed"

# >>> hi_resolve_ref_in (identical in install_constitution.sh and update_constitution.sh)
# dir ref remote-tags → "KIND SHA". The REMOTE state wins over local refs of the same name: a tag the remote
# has resolves to the remote's object, a branch name to a remote-tracking branch (origin first, then the other
# remotes), a hex string to that commit; a local tag/branch is used only when no remote has the name (KIND
# local-ref, which the caller announces). The caller still requires the commit to be on a remote.
hi_resolve_ref_in() {
  local d="$1" ref="$2" o r sha
  o="$(printf '%s\n' "$3" | awk -v n="$ref" '$1 == n { print $2; exit }')"
  if [ -n "$o" ] && sha="$(hi_gx -C "$d" rev-parse --verify --quiet "$o^{commit}" 2>/dev/null)"; then printf 'remote-tag %s\n' "$sha"; return 0; fi
  if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/remotes/$ref^{commit}" 2>/dev/null)"; then printf 'remote-branch %s\n' "$sha"; return 0; fi
  while read -r r; do
    [ -n "$r" ] || continue
    if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/remotes/$r/$ref^{commit}" 2>/dev/null)"; then printf 'remote-branch %s\n' "$sha"; return 0; fi
  done < <(hi_gx -C "$d" remote 2>/dev/null | awk '$0 == "origin" { print; next } { o[++n] = $0 } END { for (i = 1; i <= n; i++) print o[i] }')
  if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]] && sha="$(hi_gx -C "$d" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null)"; then printf 'commit %s\n' "$sha"; return 0; fi
  if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/tags/$ref^{commit}" 2>/dev/null)" \
     || sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/heads/$ref^{commit}" 2>/dev/null)"; then printf 'local-ref %s\n' "$sha"; return 0; fi
  return 1
}
# <<< hi_resolve_ref_in
CUR="$(hi_gx -C "$SUB" rev-parse HEAD)"
on_remote() { # sha → 0 when a commit a remote advertises right now (ls-remote) is or contains it; stale refs/remotes/* and local-only tags never count
  hi_on_remote "$SUB" "$1" "$(printf '%s' "$RLIVE" | awk 'NF && !s[$0]++')"
}
on_remote "$CUR" || die 3 "$REL HEAD $CUR is not on any remote branch or remote tag (unpushed work); refusing"
if [ -n "$REF" ]; then TARGET="$REF"
else
  TARGET="$(printf '%s' "$RTAGS" | awk '{ print $1 }' | grep -E "$HI_RELEASE_TAG_RE" | sort -u | sort -V | tail -n 1)"
  [ -n "$TARGET" ] || TARGET="origin/main"
fi
RES="$(hi_resolve_ref_in "$SUB" "$TARGET" "$RTAGS")" || die 3 "target $TARGET not found after fetch"
TSHA="${RES#* }"
[ "${RES%% *}" = local-ref ] && say "WARNING: no remote has a branch or tag named $TARGET: using the LOCAL ref $TARGET"
on_remote "$TSHA" || die 3 "target $TARGET ($TSHA) is not on any remote branch or remote tag: a gitlink to it could not be fetched by a fresh clone; refusing (nothing changed)"

say "project: $ROOT"; say "submodule: $REL"; say "before: $CUR"; say "target: $TARGET = $TSHA"
# State the project records vs the submodule HEAD (class: any state where they differ is reconciled on EVERY path).
# An update cut off after the submodule checkout (killed, or `git add` failed because .git/index.lock was held)
# leaves HEAD == target but the parent gitlink old, and (with the hook enabled) possibly the hook not yet run; a
# marker file in the project's git dir ("<target sha> <staged-before>", written before the checkout, removed after the hook) and the
# index gitlink are what the re-run reads to FINISH that update instead of reporting "already up to date".
up_gitlink_of() { # dir relpath → the commit the INDEX of dir records for that submodule (empty when none)
  local l; l="$(hi_gx -C "$1" ls-files -s -- "$2" 2>/dev/null | head -n 1)"
  case "$l" in "160000 "*) l="${l#160000 }"; printf '%s' "${l%% *}" ;; esac
}
# marker = "<target sha> <staged-before>" (staged-before: the gitlink staged at that moment, "-" when none); a symlinked
# marker is neither written nor read (same rule as the installer's hi_marker_set / hi_marker_get)
up_marker_set() { [ -n "$PEND" ] && [ ! -L "$PEND" ] && { printf '%s %s\n' "$TSHA" "${GL_CUR:--}" >"$PEND" 2>/dev/null || true; }; return 0; }
up_marker_line() { [ -n "$PEND" ] && [ -f "$PEND" ] && [ ! -L "$PEND" ] && head -n 1 -- "$PEND" 2>/dev/null; return 0; }
up_marker_target() { local l; l="$(up_marker_line)"; printf '%s' "${l%% *}"; }
# staged-before of the marker must equal the gitlink staged now, and the marker must name the checkout
up_marker_honored() { local l; l="$(up_marker_line)"; case "$l" in *" "*) ;; *) return 1 ;; esac; [ "${l%% *}" = "$CUR" ] && [ "${l#* }" = "${GL_CUR:--}" ]; }
up_marker_clear() { [ -n "$PEND" ] && rm -f -- "$PEND"; return 0; }
GL_CUR="$(up_gitlink_of "$ROOT" "$REL")"
GL_HEAD="$(hi_gitlink_committed "$ROOT" "$REL")"
PEND="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"
case "$PEND" in /*|"") ;; *) PEND="$ROOT/$PEND" ;; esac
# A recorded gitlink (staged or committed) is only ever replaced by a descendant of it (H-1 class): newer than the
# checkout, unknown to it, or diverged from it means the CHECKOUT is what is stale (e.g. `git pull` without
# `git submodule update`), never something to "finish". Refused on every path, --check and --dry-run included.
for gl_pair in "staged:$GL_CUR" "committed:$GL_HEAD"; do
  gl_kind="${gl_pair%%:*}"; gl_sha="${gl_pair#*:}"
  [ -n "$gl_sha" ] || continue
  case "$(hi_gitlink_rel "$SUB" "$CUR" "$gl_sha")" in
    same|recorded-older) ;;
    recorded-newer) die 3 "the project's $gl_kind gitlink records $REL at $gl_sha, which is NEWER than the checked-out $CUR (a teammate updated it and the checkout was not moved, e.g. git pull without git submodule update). Nothing changed. Run: git submodule update -- $REL   then re-run this script" ;;
    unknown) die 3 "the project's $gl_kind gitlink records $REL at $gl_sha, a commit the checkout ($CUR) does not have even after fetching. Nothing changed. Run: git submodule update -- $REL (or fix the recorded gitlink yourself), then re-run this script" ;;
    *) die 3 "the project's $gl_kind gitlink records $REL at $gl_sha, which has DIVERGED from the checked-out $CUR (neither contains the other). Nothing changed. Review it yourself, e.g. git submodule update -- $REL, then re-run this script" ;;
  esac
done
# A STAGED gitlink that differs from the committed one AND from the checkout is a change somebody staged by hand
# (round-10 F5): it is never overwritten. The one staged-differs state this script creates itself, a run cut off
# after its checkout and before `git add` (e.g. a held .git/index.lock) on top of an earlier uncommitted update,
# is recognised by the pending marker naming the checkout (written before every checkout) and is finished.
if [ -n "$GL_CUR" ] && [ -n "$GL_HEAD" ] && [ "$GL_CUR" != "$GL_HEAD" ] && [ "$GL_CUR" != "$CUR" ] \
   && ! up_marker_honored; then
  die 3 "the project's staged gitlink records $REL at $GL_CUR, which differs from both the committed gitlink ($GL_HEAD) and the checkout ($CUR): a change somebody staged; it is not overwritten. Nothing changed. To keep the checkout: git add -- $REL   to drop the staged change: git restore --staged -- $REL   then re-run this script"
fi
RESUME=""
if [ "$CUR" = "$TSHA" ]; then
  [ "$GL_CUR" = "$CUR" ] || RESUME="the project records ${GL_CUR:-no gitlink} but $REL is at $CUR (update cut off before the gitlink was staged)"
  [ -z "$RESUME" ] && [ "$HOOK" = 1 ] && [ "$(up_marker_target)" = "$CUR" ] \
    && RESUME="the post-update hook of an earlier, cut-off update never finished"
  [ -z "$RESUME" ] && [ "$COMMIT" = 1 ] && ! hi_gx -C "$ROOT" diff --cached --quiet -- "$REL" 2>/dev/null \
    && RESUME="a staged gitlink change of $REL is not committed yet"
  if [ -z "$RESUME" ]; then
    [ "$CHECK" = 1 ] && echo "UPDATE_AVAILABLE=no"
    say "already up to date ($TARGET)"; exit 0
  fi
  if [ "$CHECK" = 1 ]; then echo "UPDATE_AVAILABLE=yes"; say "an earlier update was interrupted: $RESUME; run without --check to finish it"; exit 0; fi
  if [ "$DRY" = 1 ]; then say "DRY RUN: an earlier update was interrupted: $RESUME; would finish it (stage the gitlink$([ "$HOOK" = 1 ] && echo ', run post_update_hook.sh'))"; exit 0; fi
  say "finishing an interrupted earlier update: $RESUME"
fi
if [ -z "$RESUME" ] && hi_gx -C "$SUB" merge-base --is-ancestor "$TSHA" "$CUR"; then
  [ "$CHECK" = 1 ] && echo "UPDATE_AVAILABLE=no"
  [ "$GL_CUR" = "$CUR" ] || say "NOTE: $REL is at $CUR (ahead of $TARGET) but the project records ${GL_CUR:-no gitlink}; not staged (review it yourself)"
  say "already up to date: current $CUR is ahead of $TARGET"; exit 0
fi
if [ -z "$RESUME" ]; then
  hi_gx -C "$SUB" merge-base --is-ancestor "$CUR" "$TSHA" \
    || die 3 "$TARGET is not a fast-forward of the current commit; refusing (no force, no reset)"
  for gl_sha in "$GL_CUR" "$GL_HEAD"; do   # the new gitlink must descend from every gitlink the project records
    [ -z "$gl_sha" ] || hi_gx -C "$SUB" merge-base --is-ancestor "$gl_sha" "$TSHA" \
      || die 3 "$TARGET ($TSHA) does not contain the gitlink the project records ($gl_sha); refusing to move it backwards (nothing changed)"
  done
  n="$(hi_gx -C "$SUB" rev-list --count "$CUR..$TSHA")"
  if [ "$CHECK" = 1 ]; then echo "UPDATE_AVAILABLE=yes"; say "$n new commit(s) up to $TARGET"; exit 0; fi
  if [ "$DRY" = 1 ]; then
    say "DRY RUN: would fast-forward $REL $CUR -> $TSHA ($n commits), stage the gitlink$([ "$HOOK" = 1 ] && echo ', run post_update_hook.sh')"
    exit 0
  fi
  up_marker_set   # always (the staged-gitlink rule above reads it); with --no-hook it is removed right after staging
  hi_gx -C "$SUB" checkout --quiet --detach "$TSHA" || die 1 "checkout of $TSHA failed"
  say "after: $TSHA ($n commit(s))"
  hi_gx -C "$SUB" log --oneline --no-decorate "$CUR..$TSHA" | head -n 20 | hi_text_filter | sed 's/^/  /' >&2
  hi_gx -C "$SUB" diff "$CUR" "$TSHA" -- CHANGELOG.md 2>/dev/null | hi_text_filter | sed -n 's/^+## /  changelog: /p' | head -n 10 >&2
fi
hi_gx -C "$ROOT" add -- "$REL" || die 1 "could not stage $REL (is $ROOT/.git/index.lock held by another git process?); $REL is already at $TSHA: re-run this script to finish the update"
[ "$HOOK" = 1 ] || up_marker_clear   # staged: nothing of this update is left to finish (no hook to run)
rc=0
if [ "$HOOK" = 1 ]; then
  if [ -f "$SUB/scripts/post_update_hook.sh" ]; then
    say "running scripts/post_update_hook.sh from $ROOT (CONSTITUTION_JEV_HOOK=$JEV)"
    if [ ! -e "$ROOT/helix-deps.yaml" ] && [ ! -L "$ROOT/helix-deps.yaml" ] && [ -f "$SUB/scripts/deps_manifest/verify_helix_deps_manifests.sh" ]; then
      say "NOTE: the project has no helix-deps.yaml (§11.4.31); the hook's CM-HELIX-DEPS-MANIFEST-PRESENT gate will report it. Create it with: bash $REL/scripts/deps_manifest/verify_helix_deps_manifests.sh --scaffold . --write, fill every UNKNOWN, --validate-file helix-deps.yaml, git add helix-deps.yaml"
    fi
    # CONST_DIR / PROJECT_ROOT are set from the paths resolved above, never inherited (an exported value in the
    # caller's shell would otherwise point the hook at another project). A hook that parses --project-root (W1
    # round 7 and later) also gets the project root as an explicit argument, which wins over every other rule in
    # the hook. Whether the hook understands the flag is declared by the hook itself with a capability line near the
    # top ("# HELIX_HOOK_CAPABILITIES: project-root ..."); a hook without that line gets no argument (older hooks
    # are not assumed to reject it, they are simply not given anything they did not declare). The hook takes no install lock
    # and ignores HELIX_CONSTITUTION_LOCK_DELEGATED; the variable is still set for older hooks that read it.
    hook_args=()
    head -n 80 -- "$SUB/scripts/post_update_hook.sh" 2>/dev/null \
      | grep -qE '^#[[:space:]]*HELIX_HOOK_CAPABILITIES:([^[:cntrl:]]*[[:space:]])?project-root([[:space:]]|$)' \
      && hook_args=(--project-root "$ROOT")
    # git variables that would redirect or reconfigure git (e.g. GIT_DIR from a git hook) are removed first
    (cd "$ROOT" && for v in ${!GIT_*}; do case "$v" in GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_CEILING_DIRECTORIES|GIT_AUTHOR_*|GIT_COMMITTER_*|GIT_SSL_CAINFO|GIT_SSL_CAPATH|GIT_ALLOW_PROTOCOL|GIT_PROTOCOL_FROM_USER|GIT_TERMINAL_PROMPT) ;; *) unset "$v" ;; esac; done
     CONST_DIR="$SUB" PROJECT_ROOT="$ROOT" CONSTITUTION_JEV_HOOK="$JEV" \
      HELIX_CONSTITUTION_LOCK_DELEGATED="$(up_holder_pid)" bash "$SUB/scripts/post_update_hook.sh" \
      ${hook_args[@]+"${hook_args[@]}"}) >&2 \
      || { rc=$?; say "post_update_hook.sh failed (exit $rc); the update itself is kept"; }
  else
    say "no scripts/post_update_hook.sh in this version; skipped"
  fi
fi
[ "$HOOK" = 1 ] && up_marker_clear   # the hook step is over (ran, failed visibly, or does not exist)
if [ "$COMMIT" = 1 ]; then
  hi_gx -C "$ROOT" commit -q -m "chore(constitution): update $REL to $TARGET (${TSHA:0:12})" -- "$REL" \
    && say "committed locally (not pushed)" || die 1 "commit failed"
else
  say "gitlink staged in the project; review and commit it yourself (never pushed by this script)"
fi
[ "$rc" = 0 ] || exit 1
exit 0
