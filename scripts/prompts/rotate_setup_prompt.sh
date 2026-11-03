#!/usr/bin/env bash
# rotate_setup_prompt.sh — rotate the constitution setup prompt.
#
# Purpose:
#   docs/prompts/setup/ holds numbered history (01_old.md, 02_middle.md, ...) and
#   latest.md (the current prompt, always this name). A rotation archives the
#   current latest.md as NN_NAME.md (NN = highest existing numeric prefix + 1,
#   zero-padded to 2 digits, 3 digits after 99, more digits after 999) and makes
#   the new content latest.md. latest.md is present at every instant.
#
# Usage:
#   rotate_setup_prompt.sh NAME [--source FILE] [--dry-run] [--dir DIR] [--require-clean-git|--allow-dirty]
#   rotate_setup_prompt.sh --help
#     NAME      lowercase snake_case: ^[a-z][a-z0-9]*(_[a-z0-9]+)*$, at most 64
#               characters; `latest` is reserved.
#     --source  the new prompt document. It MUST contain a `## PROMPT` heading
#               followed by a non-empty fenced block (the installer reads that
#               block). Without --source the new latest.md is a copy of the
#               archived one (edit it afterwards).
#     --dry-run print the plan, write nothing (not even the lock).
#     --dir     the setup directory (default: <repo>/docs/prompts/setup, where
#               <repo> is two levels above this script). Its real path MUST end
#               in /docs/prompts/setup, otherwise the rotation is refused.
#     --require-clean-git  refuse (exit 3) unless DIR is inside a git work tree
#               and `git status --porcelain -- DIR` prints nothing.
#     --allow-dirty  rotate even when DIR has uncommitted changes. By default
#               (review round 7, M-g) a DIR inside a git work tree with
#               uncommitted or untracked changes (the lock directory aside) is
#               refused (exit 3), so a rotation never archives unreviewed edits
#               silently; a DIR outside any git work tree (or without git) is
#               rotated without a git check.
#   NAME matching is byte-wise (LC_ALL=C is forced): only ASCII a-z, 0-9, _.
#
# Exit codes:
#   0 rotated (or dry-run printed, or an interrupted rotation of the same NAME
#     was completed by recovery) · 1 internal failure (state left recoverable)
#   2 usage error (bad flag, bad NAME) · 3 refused (precondition: missing or
#     symlinked latest.md, collision, numbering gap/duplicate, bad --source,
#     directory outside docs/prompts/setup, live lock held by another rotation,
#     inconsistent interrupted state that cannot be recovered without a human,
#     non-canonical number prefix such as 003_x.md or 3_x.md: rename it to 03_x.md)
#
# Atomicity and recovery:
#   A lock directory <dir>/.rotate.lock holds `pid` (pid and a per-run nonce) and a
#   `journal` (name, target, sha256 of the new content). `mkdir` is NOT relied on for
#   exclusion: it is not an exclusive create on every coreutils (uutils coreutils 0.8.0,
#   measured: two simultaneous mkdir of one path both succeed in 45-86 of 200 rounds).
#   Ownership is decided by creating `pid` with bash's noclobber redirection, which opens
#   with O_CREAT|O_EXCL (the kernel decides; no coreutils involved): exactly one run
#   creates it, every other run is refused (exit 3). A `pid` that already exists in any
#   form (regular file, FIFO, symlink, ...) is never opened by the claim. After taking
#   the lock the run re-reads the numbered history and refuses (exit 3, nothing written)
#   if it changed while the run was waiting. A stale lock of the same directory form
#   whose owner is dead is reclaimed as before; a `pid` that is a symlink or not a
#   regular file is refused (exit 3) and left for a human. Before a stale lock is recovered the
#   run takes it over exclusively: it renames `pid` away (only one recoverer can), checks that the
#   renamed file still holds the dead owner it judged, puts a different (new, live) owner back
#   and refuses, and otherwise writes its own `pid` with O_EXCL, so the release at the end of
#   recovery only removes a lock this run owns (review round 7, M-b).
#   A .rotate.lock that is a symlink, not a directory, or not owned by the
#   current user is refused (exit 3) and nothing in it is read or deleted. Steps: stage the new content inside the lock dir,
#   hard-link latest.md to NN_NAME.md (`ln` never overwrites; fallback
#   `mv -n` copy-then-verify where hard links are unsupported), rename the staged
#   file over latest.md (atomic rename on the same filesystem), drop the lock.
#   Between the link and the rename, NN_NAME.md and latest.md are the SAME file
#   (two hard links to one inode); the rename then gives latest.md a new inode.
#   The lock is released only when its pid file still holds this run's identity.
#   If the process dies (SIGKILL, power loss, SIGINT/SIGTERM), the lock stays;
#   the next run sees the owner is dead (kill -0 + /proc cmdline) and rolls the
#   journaled rotation forward (archive exists and equals latest.md, staged file
#   present, regular, and matching the journaled sha256) or back (archive
#   absent). An archive that exists but differs from latest.md while a staged
#   file is present, or a staged file that is a symlink or fails its checksum, is
#   refused with exit 3 and NOTHING is deleted. If the re-run names the same
#   NAME but asks for different content (another --source, or none after a run
#   that had one), the interrupted rotation is completed and the request is then
#   refused with exit 3, stating which content is now in latest.md. No path outside <dir> is ever written; nothing is ever deleted
#   except this script's own staged/lock files.
#
# Test-only seams (inert unless ROTATE_SETUP_PROMPT_TEST_MODE=1):
#   ROTATE_SETUP_PROMPT_TEST_KILL_AT=before_lock|after_lock|after_journal|after_stage|after_link|after_rename
#     -> SIGKILL self at that point;  ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=<same> -> sleep 60
#     (ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=<0-999> changes the 60; PAUSE_AT may list several
#     stages separated by spaces). Extra stages: before_lock (checks done, lock not taken) and
#     claim_window (inside the claim: directory present, pid absent, pid not yet created) and
#     before_recover (a stale lock was judged dead, the takeover has not started).
#   ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 when sourcing -> define functions only.
#
# Dependencies: bash >= 4, coreutils (ln, mv, cp, cmp, readlink, mkdir, rmdir,
# sha256sum); git for the dirty-tree check (skipped when DIR is not in a work tree).
# Side effects: only inside the setup directory. No network. git is only read (rev-parse, status).
# Classification: universal (§11.4.17). Safety: §9.2 (never lose a file),
# §11.4.287 (no recursive delete), §11.4.201 (lock liveness from the real process).

# Byte-wise matching: under a UTF-8 locale [a-z] also matches é, ß and
# full-width letters, so the locale is pinned (review round 1, finding I1).
LC_ALL=C
export LC_ALL
RSP_NAME_RE='^[a-z][a-z0-9]*(_[a-z0-9]+)*$'
RSP_LOCK_ID=
RSP_STALE_PID=   # the renamed pid file of a dead owner while this run recovers its lock
RSP_NUM_FILE_RE='^([0-9]+)_([^/]*)\.md$'
RSP_STAGES=" before_recover before_lock claim_window after_lock after_journal after_stage after_link after_rename "

rsp_err() { printf 'rotate_setup_prompt: %s\n' "$*" >&2; }
rsp_info() { printf 'rotate_setup_prompt: %s\n' "$*"; }

# rsp_valid_name NAME -> 0 if lowercase snake_case, 1..64 chars, not reserved
rsp_valid_name() {
  local n="${1-}"
  [ "${#n}" -ge 1 ] && [ "${#n}" -le 64 ] || return 1
  case "$n" in *$'\n'*|*$'\r'*) return 1 ;; esac
  [[ "$n" =~ $RSP_NAME_RE ]] || return 1
  [ "$n" != latest ] || return 1
  return 0
}

# rsp_format_number N -> zero-padded to 2 digits; wider numbers unpadded
rsp_format_number() {
  local n=$((10#${1:?number}))
  if [ "$n" -lt 100 ]; then printf '%02d\n' "$n"; else printf '%d\n' "$n"; fi
}

# rsp_numbers DIR -> one "number<TAB>file" line per numbered *.md file
rsp_numbers() {
  local d="${1:?dir}" f b
  for f in "$d"/*.md; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    if [[ "$b" =~ $RSP_NUM_FILE_RE ]]; then
      printf '%d\t%s\n' "$((10#${BASH_REMATCH[1]}))" "$b"
    fi
  done
}

# rsp_next_number DIR -> highest numeric prefix + 1 (1 when none)
rsp_next_number() {
  local max=0 n _b
  while IFS=$'\t' read -r n _b; do
    [ "$n" -gt "$max" ] && max="$n"
  done < <(rsp_numbers "$1")
  printf '%d\n' "$((max + 1))"
}

# rsp_scan_numbering DIR -> 0 when numbered files are 1..N, unique, canonically
# numbered (rsp_format_number: 01..99, then 100, 101, ...), snake_case names
rsp_scan_numbering() {
  local d="${1:?dir}" n b name expect=1 rc=0
  local -A seen=()
  while IFS=$'\t' read -r n b; do
    name="${b#*_}"; name="${name%.md}"
    if [ "${b%%_*}" != "$(rsp_format_number "$n")" ]; then
      rsp_err "non-canonical number prefix: $b (canonical: $(rsp_format_number "$n")_$name.md; two digits below 100, no extra zero padding)"; rc=1
    fi
    if ! [[ "$name" =~ $RSP_NAME_RE ]]; then rsp_err "file name not lowercase snake_case: $b"; rc=1; fi
    if [ -n "${seen[$n]:-}" ]; then rsp_err "duplicate number $n: ${seen[$n]} and $b"; rc=1; fi
    seen[$n]="$b"
  done < <(rsp_numbers "$d")
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if [ "$n" -ne "$expect" ]; then rsp_err "numbering gap: expected $expect, found $n"; rc=1; break; fi
    expect=$((expect + 1))
  done < <(printf '%s\n' "${!seen[@]}" | sort -n)
  return "$rc"
}

# rsp_has_prompt_block FILE -> 0 when the installer's extractor finds a closed
# PROMPT block with at least one non-blank line. The extractor is the ONE shared
# implementation in scripts/lib/setup_prompt_extract.sh (same semantics as the
# installer: backtick or tilde fences, a later `## ` heading ends the search).
# Missing library -> refuse (fail closed, never a silent pass).
RSP_SPX_LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/setup_prompt_extract.sh"
rsp_has_prompt_block() {
  if ! declare -F spx_has_prompt_block >/dev/null; then
    # shellcheck source=../lib/setup_prompt_extract.sh
    [ -r "$RSP_SPX_LIB" ] && . "$RSP_SPX_LIB" \
      || { rsp_err "PROMPT-block library missing: $RSP_SPX_LIB (refusing)"; return 1; }
  fi
  spx_has_prompt_block "${1:?file}"
}

rsp_lock_owner_alive() { # LOCKDIR -> 0 when the recorded owner is a live rotation
  rsp_pidfile_alive "$1/pid"
}

rsp_pidfile_alive() { # PIDFILE -> 0 when the pid it names is a live rotation (never this run)
  local f="$1" pid
  [ -f "$f" ] || return 1
  pid="$(head -n1 "$f" 2>/dev/null | head -c 64 | cut -d' ' -f1 | tr -cd '0-9')"
  [ -n "$pid" ] || return 1
  [ "$pid" != "$$" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    grep -q 'rotate_setup_prompt' <<<"$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" || return 1
  fi
  return 0
}

rsp_lock_age_sec() { # LOCKDIR -> seconds since mtime
  local m; m="$(stat -c %Y "$1" 2>/dev/null)" || { echo 0; return; }
  echo $(( $(date +%s) - m ))
}

rsp_sha() { sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1; }

rsp_lock_is_safe() { # LOCKDIR -> 0 when it is a real directory owned by us (no symlink)
  local lk="$1"
  [ ! -L "$lk" ] && [ -d "$lk" ] && [ -O "$lk" ]
}

# rsp_claim_lock LOCKDIR ID -> 0 when THIS run created LOCKDIR/pid exclusively.
# mkdir only makes sure the directory exists (it is not exclusive on every coreutils);
# the O_EXCL create of pid (bash noclobber) is the one exclusive step.
rsp_claim_lock() {
  local lk="${1:?lockdir}" id="${2:?id}"
  mkdir -- "$lk" 2>/dev/null || true
  rsp_lock_is_safe "$lk" || return 1
  if [ -e "$lk/pid" ] || [ -L "$lk/pid" ]; then return 1; fi   # never open an existing pid (FIFO, symlink)
  rsp_seam claim_window
  ( set -o noclobber; printf '%s\n' "$id" >"$lk/pid" ) 2>/dev/null || return 1
  [ ! -L "$lk/pid" ] && [ -f "$lk/pid" ] && [ "$(head -n1 -- "$lk/pid" 2>/dev/null)" = "$id" ]
}

rsp_release_lock() { # LOCKDIR -> remove only our own known files, then the dir
  local lk="${1:?lockdir}"
  rsp_lock_is_safe "$lk" || { rsp_err "lock $lk is not a real directory owned by us; not touched"; return 1; }
  if [ -n "$RSP_LOCK_ID" ] && [ "$(head -n1 "$lk/pid" 2>/dev/null)" != "$RSP_LOCK_ID" ]; then
    rsp_err "lock $lk now carries another identity; not released"; return 1
  fi
  rm -f -- "$lk/staged" "$lk/journal" "$lk/pid" "$lk/archive.tmp"
  [ -z "$RSP_STALE_PID" ] || [ "${RSP_STALE_PID%/*}" != "$lk" ] || rm -f -- "$RSP_STALE_PID"
  rmdir -- "$lk" 2>/dev/null || { rsp_err "lock directory $lk holds unexpected files; left in place"; return 1; }
}

RSP_RECOVERED_NAME=""
RSP_RECOVERED_SHA=""
RSP_RECOVERED_TARGET=""
# rsp_recover DIR LOCKDIR -> completes or rolls back an interrupted rotation
# 0 recovered (or nothing to do) · 3 refused (inconsistent; nothing deleted)
rsp_recover() {
  local d="$1" lk="$2" target="" name="" line
  if [ -f "$lk/journal" ]; then
    while IFS= read -r line; do
      case "$line" in
        name=*) name="${line#name=}" ;;
        target=*) target="${line#target=}" ;;
        sha=*) RSP_RECOVERED_SHA="${line#sha=}" ;;
      esac
    done <"$lk/journal"
  fi
  if [ -z "$target" ]; then
    rsp_info "recovery: interrupted before the journal was written; nothing was changed; clearing the stale lock"
    rsp_release_lock "$lk" || return 3
    return 0
  fi
  if ! rsp_valid_name "$name" || [[ "$target" == */* ]] || ! [[ "$target" =~ $RSP_NUM_FILE_RE ]]; then
    rsp_err "recovery: journal in $lk is malformed (name='$name' target='$target'); fix by hand, nothing deleted"
    return 3
  fi
  if [ ! -e "$d/$target" ]; then
    rsp_info "recovery: archive $target was never created; rolling back (latest.md was not touched)"
    rsp_release_lock "$lk" || return 3
    return 0
  fi
  if [ -e "$lk/staged" ] || [ -L "$lk/staged" ]; then
    if [ -L "$lk/staged" ] || [ ! -f "$lk/staged" ]; then
      rsp_err "recovery: $lk/staged is not a regular file; nothing installed, inspect $lk by hand"
      return 3
    fi
    if [ -n "$RSP_RECOVERED_SHA" ] && [ "$(rsp_sha "$lk/staged")" != "$RSP_RECOVERED_SHA" ]; then
      rsp_err "recovery: $lk/staged does not match the journaled sha256; nothing installed, inspect $lk by hand"
      return 3
    fi
    if [ -L "$d/latest.md" ]; then rsp_err "recovery: latest.md is a symlink; nothing changed"; return 3; fi
    if cmp -s "$d/$target" "$d/latest.md"; then
      mv -f -- "$lk/staged" "$d/latest.md" || { rsp_err "recovery: rename of staged file failed"; return 1; }
      rsp_info "recovery: completed interrupted rotation ($target archived, staged content installed as latest.md)"
    else
      rsp_err "recovery: $target exists, a staged file exists, but $target differs from latest.md — inconsistent; nothing deleted, inspect $lk by hand"
      return 3
    fi
  else
    rsp_info "recovery: interrupted rotation had already installed latest.md; clearing the lock"
  fi
  rsp_release_lock "$lk" || return 3
  RSP_RECOVERED_NAME="$name"
  RSP_RECOVERED_TARGET="$target"
  return 0
}

# rsp_take_over_stale LOCKDIR OBSERVED -> 0 when THIS run now owns the stale lock (RSP_LOCK_ID set).
# The decision "the owner is dead" was taken on OBSERVED (the first line of pid, or empty when there
# was no pid). Between that decision and the recovery another run may have recovered the lock and a
# NEW live run may own it now (review round 7, M-b). So the pid file is first renamed away (rename is
# atomic: only one recoverer gets it), its content is compared with OBSERVED, and a pid that is not
# the observed dead one is put back (ln never overwrites) and the run refuses. Then this run creates
# its own pid with O_EXCL, so the release at the end of recovery is identity-checked.
rsp_take_over_stale() {
  local lk="${1:?lockdir}" obs="$2" st="" got id
  id="$$ $(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')$RANDOM"
  rsp_lock_is_safe "$lk" || return 3
  if [ -n "$obs" ]; then
    st="$lk/stale.${id#* }"
    mv -T -- "$lk/pid" "$st" 2>/dev/null \
      || { rsp_err "the stale lock $lk was taken over by another run meanwhile; nothing done, retry"; return 3; }
    if [ -L "$st" ] || [ ! -f "$st" ] || [ "$(head -n1 -- "$st" 2>/dev/null)" != "$obs" ] \
       || rsp_pidfile_alive "$st"; then
      if ln -T -- "$st" "$lk/pid" 2>/dev/null; then rm -f -- "$st"
      else rsp_err "lock $lk: could not put back the pid file (saved as $st); inspect it by hand"; fi
      rsp_err "the lock $lk now belongs to another run (its owner changed after it was judged stale); refusing, nothing done"
      return 3
    fi
  elif [ -e "$lk/pid" ] || [ -L "$lk/pid" ]; then
    rsp_err "lock $lk gained an owner after it was judged stale; refusing, nothing done"; return 3
  fi
  if ! ( set -o noclobber; printf '%s\n' "$id" >"$lk/pid" ) 2>/dev/null \
     || [ -L "$lk/pid" ] || [ "$(head -n1 -- "$lk/pid" 2>/dev/null)" != "$id" ]; then
    rsp_err "lock $lk was claimed by another run during recovery${st:+ (the pid file of the dead owner is kept as $st)}; refusing"
    return 3
  fi
  RSP_STALE_PID="$st"
  RSP_LOCK_ID="$id"
  return 0
}

rsp_seam() { # STAGE
  [ "${ROTATE_SETUP_PROMPT_TEST_MODE:-0}" = 1 ] || return 0
  if [ "${ROTATE_SETUP_PROMPT_TEST_KILL_AT:-}" = "$1" ]; then kill -KILL "$$"; fi
  if [[ " ${ROTATE_SETUP_PROMPT_TEST_PAUSE_AT:-} " == *" $1 "* ]]; then
    local sec="${ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC:-60}"; [[ "$sec" =~ ^[0-9]{1,3}$ ]] || sec=60
    sleep "$sec" & wait $!
  fi
  return 0
}

rsp_usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | sed '$d'; }

rsp_main() {
  local name="" source="" dry=0 dir="" name_set=0 clean=0 allow_dirty=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) rsp_usage; return 0 ;;
      --dry-run) dry=1; shift ;;
      --source) [ $# -ge 2 ] || { rsp_err "--source needs a value"; return 2; }; source="$2"; shift 2 ;;
      --dir) [ $# -ge 2 ] || { rsp_err "--dir needs a value"; return 2; }; dir="$2"; shift 2 ;;
      --require-clean-git) clean=1; shift ;;
      --allow-dirty) allow_dirty=1; shift ;;
      --) shift; break ;;
      -*) rsp_err "unknown flag: $(printf %q "$1")"; return 2 ;;
      *) if [ "$name_set" = 0 ]; then name="$1"; name_set=1; shift
         else rsp_err "unexpected argument: $(printf %q "$1")"; return 2; fi ;;
    esac
  done
  if [ "$name_set" = 0 ]; then rsp_err "NAME is required (see --help)"; return 2; fi
  if ! rsp_valid_name "$name"; then
    rsp_err "invalid NAME $(printf %q "$name"): must match $RSP_NAME_RE, 1..64 chars, not 'latest'"
    return 2
  fi

  if [ -z "$dir" ]; then
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/docs/prompts/setup"
  fi
  local real
  real="$(readlink -e -- "$dir" 2>/dev/null)" || { rsp_err "setup directory not found: $dir"; return 3; }
  [ -d "$real" ] || { rsp_err "not a directory: $dir"; return 3; }
  case "$real" in
    */docs/prompts/setup) ;;
    *) rsp_err "refusing: $real is not a docs/prompts/setup directory"; return 3 ;;
  esac
  dir="$real"
  local latest="$dir/latest.md" lk="$dir/.rotate.lock"
  if [ -L "$lk" ] || { [ -e "$lk" ] && ! rsp_lock_is_safe "$lk"; }; then
    rsp_err "refusing: $lk is a symlink, not a directory, or not owned by you; nothing read or deleted (inspect it by hand)"
    return 3
  fi
  if [ "$clean" = 1 ]; then
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || { rsp_err "refusing (--require-clean-git): $dir is not inside a git work tree"; return 3; }
    local dirty
    dirty="$(git -C "$dir" status --porcelain -- . 2>/dev/null)" \
      || { rsp_err "refusing (--require-clean-git): git status failed in $dir"; return 3; }
    [ -z "$dirty" ] || { rsp_err "refusing (--require-clean-git): uncommitted changes in $dir:"; printf '%s\n' "$dirty" >&2; return 3; }
  elif [ "$allow_dirty" = 0 ] && command -v git >/dev/null 2>&1 \
       && [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    local dirty
    dirty="$(git -C "$dir" status --porcelain -- . ':(exclude).rotate.lock' 2>/dev/null)" \
      || { rsp_err "refusing: git status failed in $dir (pass --allow-dirty to rotate without the check)"; return 3; }
    [ -z "$dirty" ] || { rsp_err "refusing: uncommitted changes in $dir (commit them, or pass --allow-dirty):"; printf '%s\n' "$dirty" >&2; return 3; }
  fi

  # Recovery of an interrupted rotation (never in dry-run: dry-run writes nothing)
  if [ -e "$lk" ]; then
    if [ -L "$lk/pid" ] || { [ -e "$lk/pid" ] && [ ! -f "$lk/pid" ]; }; then
      rsp_err "refusing: $lk/pid is a symlink or not a regular file; nothing read or deleted (inspect it by hand)"
      return 3
    fi
    if rsp_lock_owner_alive "$lk"; then
      rsp_err "another rotation is in progress (lock $lk, pid $(cat "$lk/pid" 2>/dev/null)); refusing"
      return 3
    fi
    if [ ! -f "$lk/pid" ] && [ "$(rsp_lock_age_sec "$lk")" -lt 10 ]; then
      rsp_err "lock $lk is being created by another process; retry in a few seconds"
      return 3
    fi
    if [ "$dry" = 1 ]; then
      rsp_info "DRY-RUN: an interrupted rotation (stale lock $lk) would be recovered first; nothing written"
    else
      local rrc=0 obs=""
      [ ! -f "$lk/pid" ] || obs="$(head -n1 -- "$lk/pid" 2>/dev/null)"
      rsp_seam before_recover
      rsp_take_over_stale "$lk" "$obs" || return 3
      rsp_recover "$dir" "$lk" || rrc=$?
      if [ "$rrc" -ne 0 ] && [ -e "$lk" ]; then
        # recovery refused: the lock stays for a human exactly as it was found (the dead
        # owner's pid file back in place, or no pid at all when there was none)
        if [ -n "$RSP_STALE_PID" ]; then mv -fT -- "$RSP_STALE_PID" "$lk/pid" 2>/dev/null
        elif [ "$(head -n1 -- "$lk/pid" 2>/dev/null)" = "$RSP_LOCK_ID" ]; then rm -f -- "$lk/pid"; fi
      fi
      RSP_LOCK_ID=""; RSP_STALE_PID=""
      [ "$rrc" -eq 0 ] || return "$rrc"
      if [ -n "$RSP_RECOVERED_NAME" ] && [ "$RSP_RECOVERED_NAME" = "$name" ]; then
        local want_sha have_sha
        have_sha="$(rsp_sha "$latest")"
        if [ -n "$source" ]; then want_sha="$(rsp_sha "$source")"
        else want_sha="$(rsp_sha "$dir/$RSP_RECOVERED_TARGET")"; fi
        if [ -z "$want_sha" ] || [ "$want_sha" != "$have_sha" ]; then
          rsp_err "the interrupted rotation '$name' was completed: latest.md now holds the content of that run (sha256 $have_sha); the content you asked for now ${source:+(--source $source) }differs (sha256 ${want_sha:-unreadable}); nothing else changed — rotate again under a NEW name to apply it"
          return 3
        fi
        rsp_info "the requested rotation '$name' was the interrupted one and is now complete"
        return 0
      fi
    fi
  fi

  if [ -L "$latest" ]; then rsp_err "refusing: $latest is a symlink"; return 3; fi
  if [ ! -f "$latest" ]; then rsp_err "refusing: $latest is missing (nothing to archive)"; return 3; fi
  if ! rsp_scan_numbering "$dir"; then
    rsp_err "refusing: the numbered history in $dir is not gap-free/unique (fix it first)"
    return 3
  fi
  local n b
  while IFS=$'\t' read -r n b; do
    if [ "$b" = "${b%%_*}_$name.md" ]; then rsp_err "refusing: NAME '$name' already used by $b (collision)"; return 3; fi
  done < <(rsp_numbers "$dir")

  local content_src="$latest"
  if [ -n "$source" ]; then
    local sreal
    sreal="$(readlink -e -- "$source" 2>/dev/null)" || { rsp_err "refusing: --source not found: $source"; return 3; }
    if [ ! -f "$sreal" ]; then rsp_err "refusing: --source is not a regular file: $source"; return 3; fi
    content_src="$sreal"
  fi
  if ! rsp_has_prompt_block "$content_src"; then
    rsp_err "refusing: $content_src has no '## PROMPT' heading followed by a closed, non-empty fenced block"
    return 3
  fi

  local num target
  num="$(rsp_format_number "$(rsp_next_number "$dir")")"
  target="${num}_$name.md"
  if [ -e "$dir/$target" ]; then rsp_err "refusing: $target already exists"; return 3; fi

  if [ "$dry" = 1 ]; then
    rsp_info "DRY-RUN plan (nothing written):"
    rsp_info "  archive: $dir/latest.md -> $dir/$target"
    rsp_info "  new latest.md from: $content_src"
    return 0
  fi

  # --- lock --------------------------------------------------------------------
  rsp_seam before_lock
  RSP_LOCK_ID="$$ $(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')$RANDOM"
  if ! rsp_claim_lock "$lk" "$RSP_LOCK_ID"; then
    RSP_LOCK_ID=""
    rsp_err "could not take lock $lk (another rotation holds it, or it is not a plain directory owned by you); refusing"
    return 3
  fi
  # the history may have changed while this run waited for the lock: re-check under the lock
  if ! rsp_scan_numbering "$dir" 2>/dev/null || [ "$(rsp_format_number "$(rsp_next_number "$dir")")" != "$num" ] \
     || [ -e "$dir/$target" ] || [ -L "$latest" ] || [ ! -f "$latest" ]; then
    rsp_err "refusing: $dir changed while this run was waiting for the lock (another rotation finished first); nothing written"
    rsp_release_lock "$lk"; return 3
  fi
  trap 'exit 130' INT
  trap 'exit 143' TERM
  rsp_seam after_lock
  local csha; csha="$(rsp_sha "$content_src")"; [ -n "$csha" ] || { rsp_err "cannot checksum $content_src"; rsp_release_lock "$lk"; return 1; }
  printf 'name=%s\ntarget=%s\nsha=%s\n' "$name" "$target" "$csha" >"$lk/journal.tmp" && mv -f -- "$lk/journal.tmp" "$lk/journal" \
    || { rsp_err "could not write journal"; rm -f -- "$lk/journal.tmp"; rsp_release_lock "$lk"; return 1; }
  rsp_seam after_journal
  cp -- "$content_src" "$lk/staged" && [ "$(rsp_sha "$lk/staged")" = "$csha" ] \
    || { rsp_err "staging failed (or the source changed while copying)"; rm -f -- "$lk/staged"; rsp_release_lock "$lk"; return 1; }
  sync -- "$lk/staged" 2>/dev/null || true
  # the bytes that will be installed are validated, not only the file checked before the lock
  # (review round 7, M-f: --source may change between that check and the copy)
  if ! rsp_has_prompt_block "$lk/staged"; then
    rsp_err "refusing: the staged copy of $content_src has no '## PROMPT' heading followed by a closed, non-empty fenced block (the source changed after it was checked); nothing installed"
    rm -f -- "$lk/staged"; rsp_release_lock "$lk"; return 3
  fi
  rsp_seam after_stage
  if ! ln -- "$latest" "$dir/$target" 2>/dev/null; then
    # hard links unsupported (or failed): copy to a temp file, then no-clobber move
    cp -p -- "$latest" "$lk/archive.tmp" && mv -n -- "$lk/archive.tmp" "$dir/$target" \
      && cmp -s "$latest" "$dir/$target" \
      || { rsp_err "archiving failed; state left recoverable in $lk (re-run to recover)"; return 1; }
  fi
  rsp_seam after_link
  mv -f -- "$lk/staged" "$latest" || { rsp_err "installing latest.md failed; re-run to recover"; return 1; }
  rsp_seam after_rename
  rsp_release_lock "$lk" || return 1
  trap - INT TERM
  rsp_info "archived previous latest.md as $target; latest.md updated from $content_src"
  return 0
}

if [ "${ROTATE_SETUP_PROMPT_SOURCE_ONLY:-0}" = 1 ]; then
  return 0 2>/dev/null || exit 0
fi
set -uo pipefail
rsp_main "$@"
