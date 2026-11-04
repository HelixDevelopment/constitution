#!/usr/bin/env bash
# =============================================================================
# install_agent_label_defs.sh — install the §11.4.182 / §11.4.231(F) agent-type
#   label definitions (T<N>-<branch>-<model>-<effort>) into a consuming
#   project's .claude/agents directory, for every track the project declares.
#
# Purpose : consumers regenerate their label agent types on every constitution
#   pull (wired from scripts/post_update_hook.sh, §11.4.164), idempotently and
#   without ever touching hand-made agent definitions.
# Usage   : install_agent_label_defs.sh [--project-root <dir>] [--out-dir <dir>]
#             [--models sonnet,opus] [--efforts low,medium,high,xhigh,max]
#             [--check] [--dry-run] [--no-prune]
# Inputs  : the consumer's config/multitrack/<host>.yaml via multitrack_config.sh
#   (tracks -> `track-<N>` ids; a literal `branch:` is used as is, a glob
#   `branch_pattern:` is resolved from the HEAD of the track's `mount` checkout;
#   an unresolvable track is reported and skipped, never guessed) PLUS the
#   current checkout's own (track, branch) from track_branch_label.sh
#   (trunk = T1). With no config at all only the current checkout is used.
#   Env: MT_HOST / MT_CONFIG_DIR / MT_REPO_ROOT as for multitrack_config.sh.
# Outputs : <out-dir>/ (default <project-root>/.claude/agents) gets one
#   definition per track x model x effort via gen_agent_label_defs.sh.
# Exit codes: 0 ok · 1 drift (--check) · 2 usage · 3 some target is HAND-MADE
#   (left untouched) · 4 some target is a HAND-EDITED generated file (left
#   untouched) · 5 internal error · 6 REFUSED: the project root or the out-dir
#   is the home directory, an ancestor of it, or a user-level agent config
#   directory (CLAUDE_CONFIG_DIR, ~/.claude, ~/.claude-*) or inside one;
#   nothing is written. A per-track refusal (3/4) never stops the other tracks.
#   Also refused (6): the filesystem root, and the system directories of
#   scripts/lib/protected_paths.list as project root or out-dir.
# Known limits (honest residuals, review rounds 3-4): (a) the refusal compares
#   symlink-resolved paths, so a BIND MOUNT of a user config dir is invisible to it
#   (UNCONFIRMED by experiment: unshare was denied; it follows from what path resolution does);
#   (b) the refusal runs once before generation: a path component swapped for a symlink
#   between that check and the mkdir/mv writes (check-to-write race, same-user attacker)
#   is not caught; (c) $XDG_CONFIG_HOME/claude and other platforms' user dirs are not in
#   the protected set; (d) the comparison is case-sensitive, so on a case-insensitive file
#   system (macOS default) ~/.CLAUDE/agents is not refused; (e) canonicalisation uses pure
#   bash + flag-less readlink, never 'realpath -m' (R4-1): if a symlink on the path cannot be
#   read, the run is REFUSED (exit 6), never guessed; (f) a path through a per-process link
#   (/proc/self, /proc/<pid>/..., /dev/fd, /dev/stdin|stdout|stderr) is REFUSED (exit 6, R5-1),
#   even where it would land somewhere harmless, and the kernel's own 'cd -P' resolution of the
#   existing prefix must agree with the pure-bash walk; (g) a cwd or path of PATH_MAX bytes or more, a
#   component it cannot lstat (EACCES), past a non-directory, or longer than NAME_MAX, and a newline in a
#   path are REFUSED (exit 6, R6-1); '-' is a directory name, never $OLDPWD; CDPATH is ignored.
# Side-effects: writes generated files; prunes ONLY genuine generated
#   T<N>-*.md files whose (track, branch) is no longer declared (a declared
#   track whose branch is unresolvable keeps its files; with no usable consumer
#   config nothing is pruned) AND whose
#   model and effort are inside this run's --models / --efforts filter (a
#   partial run never prunes files outside its filter); never a hand-made or
#   hand-edited file; --no-prune disables pruning. Track numbers are decimal
#   (track-007 == T7). Two declared branches of one track that sanitise to the
#   same type names are a COLLISION: the first is kept, the second skipped
#   and reported (no flip-flop between reruns).
# Deps    : bash, git, the sibling gen_agent_label_defs.sh / multitrack_config.sh
#   / track_branch_label.sh.
# Cross-refs: §11.4.182, §11.4.231(F), §11.4.164, §11.4.177, §11.4.111,
#   gate CM-AGENT-TYPE-LABEL, docs/scripts/install_agent_label_defs.md.
# Classification: universal (§11.4.17).
# =============================================================================
set -uo pipefail
unset CDPATH   # a relative cd must never be redirected by CDPATH (review round 6); children inherit no CDPATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GEN="$HERE/gen_agent_label_defs.sh"
LABELER="$HERE/track_branch_label.sh"

project_root=""; out_dir=""; models="sonnet,opus"; efforts="low,medium,high,xhigh,max"
do_check=0; dry=0; prune=1
die2() { echo "install_agent_label_defs: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root) [ $# -ge 2 ] || die2 "--project-root needs a value"; project_root="$2"; shift 2 ;;
    --out-dir)      [ $# -ge 2 ] || die2 "--out-dir needs a value"; out_dir="$2"; shift 2 ;;
    --models)       [ $# -ge 2 ] || die2 "--models needs a value"; models="$2"; shift 2 ;;
    --efforts)      [ $# -ge 2 ] || die2 "--efforts needs a value"; efforts="$2"; shift 2 ;;
    --check)        do_check=1; shift ;;
    --dry-run)      dry=1; shift ;;
    --no-prune)     prune=0; shift ;;
    -h|--help)      sed -n '2,44p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die2 "unknown argument '$1'" ;;
  esac
done
[ -n "$project_root" ] || project_root="${PROJECT_ROOT:-$(pwd -P)}"
[ -d "$project_root" ] || die2 "project root '$project_root' is not a directory"
# A project root that cannot be entered (e.g. /root for a normal user) is still checked by the
# refusals below on its raw path, so a system or user-level directory reports exit 6; only
# after those checks does an un-enterable root stop with exit 2.
pr_unentered=0
# a relative root is entered as ./<root>: 'cd -- -' would mean $OLDPWD (review round 6, R6-1/R6-2)
case "$project_root" in /*) _prd="$project_root" ;; *) _prd="./$project_root" ;; esac
if _pr="$(CDPATH='' cd -P -- "$_prd" 2>/dev/null && pwd -P)" && [ -n "$_pr" ]; then project_root="$_pr"; else pr_unentered=1; fi
[ -n "$out_dir" ] || out_dir="$project_root/.claude/agents"

# --- 0. refuse user-level targets (review 2026-11-03, F1) ----------------------------------
# The project root must not be the home directory or an ancestor of it, and neither the
# project root nor the out-dir may be (or lie inside, or contain) a user-level agent
# config directory: those hold the user's own agents, not a project's.
# canon PATH: the physical absolute path, in pure bash plus a flag-less 'readlink' (GNU, BSD,
# macOS and busybox all have it). It does NOT use 'realpath -m', which BSD/macOS and busybox
# lack (review round 4, R4-1). Components are walked left to right: '' and '.' are dropped,
# a symlink is followed BEFORE a following '..' (the kernel's order), '..' pops the already
# resolved prefix, and components that do not exist are kept lexically (as realpath -m does).
# It prints nothing and returns 1 when the path cannot be established (empty input, no
# working directory, an unreadable link, more than 40 links): the caller refuses (exit 6).
# Undecidable components (review round 6, R6-1): a component whose lstat cannot be decided is
# never walked lexically. canon returns 1 (refuse) for a path containing a newline, an absolute
# candidate of PATH_MAX bytes or more (lstat would fail with ENAMETOOLONG and hide a link), a
# component longer than NAME_MAX, a component after an existing non-directory (ENOTDIR), and a
# component inside a directory it may not search (EACCES). Only a component whose parent is a
# searchable directory or itself does not exist is kept lexically (ENOENT, as realpath -m does).
# Per-process links (review round 5, R5-1): a symlink located under /proc (/proc/self,
# /proc/thread-self, /proc/<pid>/cwd|root|exe|fd/*, /proc/mounts, ...) or at /dev/fd,
# /dev/stdin, /dev/stdout, /dev/stderr means something different in every process, and
# 'readlink' would answer for its own short-lived process (a following '..' then escapes
# /proc). Such a link is never followed: canon returns 2 and the caller refuses (exit 6).
canon() {
  local rest comp t l cur=/ n=0 base pmax nmax LC_ALL=C
  [ -n "$1" ] || return 1
  case "$1" in *$'\n'*) return 1 ;; esac
  pmax="$(getconf PATH_MAX / 2>/dev/null)"; case "$pmax" in ''|*[!0-9]*) pmax=1024 ;; esac
  nmax="$(getconf NAME_MAX / 2>/dev/null)"; case "$nmax" in ''|*[!0-9]*) nmax=255 ;; esac
  case "$1" in
    /*) rest="$1" ;;
    *) base="$(pwd -P 2>/dev/null)" || return 1; [ -n "$base" ] || return 1; rest="$base/$1" ;;
  esac
  while [ -n "$rest" ]; do
    comp="${rest%%/*}"
    if [ "$comp" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    if [ "$cur" != / ] && [ -e "$cur" ] && [ ! -d "$cur" ]; then return 1; fi   # ENOTDIR
    case "$comp" in
      ''|.) continue ;;
      ..) cur="${cur%/*}"; [ -n "$cur" ] || cur=/; continue ;;
    esac
    [ "${#comp}" -le "$nmax" ] || return 1                                     # ENAMETOOLONG (name)
    if [ "$cur" = / ]; then t="/$comp"; else t="$cur/$comp"; fi
    [ "${#t}" -lt "$pmax" ] || return 1                                        # ENAMETOOLONG (path)
    if [ -L "$t" ]; then
      case "$t" in /proc|/proc/*|/dev/fd|/dev/stdin|/dev/stdout|/dev/stderr) return 2 ;; esac
      n=$((n+1)); [ "$n" -le 40 ] || return 1
      l="$(readlink -- "$t" 2>/dev/null)" || return 1
      [ -n "$l" ] || return 1
      case "$l" in /*) cur=/ ;; esac
      rest="$l${rest:+/$rest}"
    elif [ -e "$t" ]; then
      cur="$t"
    elif [ -d "$cur" ] && [ ! -x "$cur" ]; then
      return 1                                                                 # EACCES: undecidable
    else
      cur="$t"                                                                 # ENOENT: lexical
    fi
  done
  printf '%s\n' "$cur"
}
# canon_kcheck PATH CANON: second, independent opinion (R5-1). The longest prefix of PATH that
# the kernel can enter is resolved with 'cd -P' in a subshell (the kernel follows every link,
# magic ones included, in a process that has the installer's working directory), and must
# equal what canon says for the same prefix. A prefix nobody can enter gives no opinion
# (return 0); a disagreement, or a canon failure on the prefix, returns 1 (caller refuses).
canon_kcheck() {
  local p="$1" kp="" cp="" i=0 cdp
  while :; do
    # a relative prefix is entered as ./<prefix>: a bare 'cd -- -' means $OLDPWD (R6-1/R6-2)
    case "$p" in /*) cdp="$p" ;; *) cdp="./$p" ;; esac
    if [ -d "$cdp" ] && kp="$(CDPATH='' cd -P -- "$cdp" 2>/dev/null && pwd -P)" && [ -n "$kp" ]; then break; fi
    case "$p" in /|.|'') return 0 ;; esac
    case "$p" in */*) p="${p%/*}"; [ -n "$p" ] || p=/ ;; *) p=. ;; esac
    i=$((i+1)); [ "$i" -le 100000 ] || return 1
  done
  cp="$(canon "$p")" || return 1
  [ "$kp" = "$cp" ]
}
# canon_to VAR PATH: VAR := canon PATH, or refuse (exit 6, fail closed, §11.4.201(4)).
canon_to() {
  local -n _cv="$1"; local _crc=0
  _cv="$(canon "$2")" || _crc=$?
  [ "$_crc" -ne 2 ] || refuse6 "'$2' passes through a per-process magic link (/proc/self, /proc/<pid>/..., /dev/fd, /dev/stdin): its meaning depends on the resolving process, so it cannot be proven not to be a user-level or system directory"
  [ "$_crc" -eq 0 ] || refuse6 "cannot canonicalise '$2' (unreadable symlink or no usable readlink); cannot prove it is not a user-level or system directory"
  [ -n "$_cv" ] || refuse6 "cannot canonicalise '$2'"
  canon_kcheck "$2" "$_cv" || refuse6 "'$2': the canonical path disagrees with the kernel's own resolution (cd -P); cannot prove it is not a user-level or system directory"
}
# $1 equal to or inside $2. The filesystem root is an ancestor of every absolute path (R3-1:
# the pattern "$2"/* would be '//*' for '/', which matches nothing).
under() { [ "$1" = "$2" ] && return 0; [ "$2" = / ] && return 0; case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac; }
refuse6() { echo "install_agent_label_defs: REFUSED: $* — nothing written" >&2; exit 6; }
# Every user-level entry is kept in BOTH its lexical and its canonical (symlink-resolved)
# form, so a symlinked ~/.claude or ~/.claude-x (stow/dotfiles) cannot bypass the refusal
# (review round 2, R2-1). The home directory is taken from $HOME and, when that is empty or
# unset, from the passwd database; both are checked when they differ.
declare -a HOMES=() USERCFG=()
add_uniq() { # array-name value
  local -n _a="$1"; local v="$2" x
  [ -n "$v" ] || return 0
  for x in "${_a[@]:-}"; do [ "$x" = "$v" ] && return 0; done
  _a+=("$v")
}
pw_home=""
if command -v getent >/dev/null 2>&1; then pw_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"; fi
_cz=""
[ -n "${HOME:-}" ] && { add_uniq HOMES "$HOME"; canon_to _cz "$HOME"; add_uniq HOMES "$_cz"; }
[ -n "$pw_home" ] && { add_uniq HOMES "$pw_home"; canon_to _cz "$pw_home"; add_uniq HOMES "$_cz"; }
add_cfg() { local _cc=""; add_uniq USERCFG "$1"; canon_to _cc "$1"; add_uniq USERCFG "$_cc"; }
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && add_cfg "$CLAUDE_CONFIG_DIR"
for h in "${HOMES[@]:-}"; do
  [ -n "$h" ] || continue
  add_cfg "$h/.claude"
  for c in "$h"/.claude-*; do { [ -e "$c" ] || [ -L "$c" ]; } && add_cfg "$c"; done
done
if [ "${#HOMES[@]}" -eq 0 ] && [ "$do_check" -eq 0 ]; then
  refuse6 "the home directory cannot be resolved (HOME empty and no passwd entry); cannot prove the target is not a user-level directory"
fi
# System directories (R3-6). Mirrors the absolute entries of scripts/lib/protected_paths.list
# (unit test I17e asserts every absolute entry there except /Users is refused as an out-dir;
# I17f/g pin both lists below, I17h probes a child of every strict entry, I17i every exact
# entry itself, I17j a child of every exact entry as golden-FALSE). SYS_STRICT: the directory, anything
# inside it and any ancestor are refused. SYS_EXACT: only the directory itself (and ancestors),
# because ordinary projects live below them (/var/tmp, /mnt/x, /media/x, /tmp/x).
SYS_STRICT=(/bin /boot /dev /etc /lib /lib32 /lib64 /libx32 /opt /proc /root /run /sbin /srv /sys /usr)
SYS_EXACT=(/var /home /mnt /media /snap /tmp /Users)
sys_refuse() { local t sd
for t in "$@"; do
  [ "$t" = / ] && refuse6 "'$t' is the filesystem root or an ancestor of everything (project root / out-dir)"
  for sd in "${SYS_STRICT[@]}"; do
    under "$t" "$sd" && refuse6 "'$t' is the system directory $sd or inside it"
    under "$sd" "$t" && refuse6 "'$t' is an ancestor of the system directory $sd"
  done
  for sd in "${SYS_EXACT[@]}"; do
    [ "$t" = "$sd" ] && refuse6 "'$t' is the system directory $sd itself"
    under "$sd" "$t" && refuse6 "'$t' is an ancestor of the system directory $sd"
  done
done
}
# The project root is checked first, so an un-enterable root stops with exit 2 (R5-3) before its
# out-dir is canonicalised (canon refuses a component it cannot lstat, R6-1).
pr_c=""; od_c=""; canon_to pr_c "$project_root"
sys_refuse "$pr_c"
for h in "${HOMES[@]:-}"; do
  [ -n "$h" ] || continue
  under "$h" "$pr_c" && refuse6 "project root '$pr_c' is the home directory or an ancestor of it"
done
for c in "${USERCFG[@]:-}"; do
  [ -n "$c" ] || continue
  under "$pr_c" "$c" && refuse6 "project root '$pr_c' is a user-level agent config directory or inside one ($c)"
done
[ "$pr_unentered" -eq 0 ] || die2 "project root '$project_root' cannot be entered"
canon_to od_c "$out_dir"
sys_refuse "$od_c"
for h in "${HOMES[@]:-}"; do
  [ -n "$h" ] || continue
  under "$h" "$od_c" && refuse6 "out-dir '$od_c' is the home directory or an ancestor of it"
done
for c in "${USERCFG[@]:-}"; do
  [ -n "$c" ] || continue
  under "$od_c" "$c" && refuse6 "out-dir '$od_c' is inside the user-level agent config directory $c"
  under "$c" "$od_c" && refuse6 "out-dir '$od_c' contains the user-level agent config directory $c"
done
# The writers get the checked canonical path, never the raw string (no second interpretation of
# '-', '--', a relative path or a cwd that changed meaning, R6-1/R6-2).
out_dir="$od_c"
[ -x "$GEN" ] || [ -r "$GEN" ] || die2 "generator missing: $GEN"

declare -a PAIRS=()          # "N<TAB>branch"
declare -A PREFIX_OF=()      # "T<N>-<san>" -> branch that claimed it first
sanitise() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's#/#-#g' -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'; }
add_pair() { # N branch
  local n="$1" b="$2" p k
  [ "${#n}" -le 9 ] || { echo "SKIP     track $n: track number has more than 9 digits"; return 0; }
  n="$((10#$n))"                                    # track-007 == T7 (review 2026-11-03, F9)
  for p in "${PAIRS[@]:-}"; do [ "$p" = "$n	$b" ] && return 0; done
  k="T${n}-$(sanitise "$b")"
  if [ -n "${PREFIX_OF[$k]:-}" ]; then
    echo "COLLISION T${n}: branch '$b' sanitises to the same type names ($k-*) as branch '${PREFIX_OF[$k]}'; kept '${PREFIX_OF[$k]}', skipped '$b'" >&2
    echo "COLLISION T${n}: branch '$b' skipped (same type names as '${PREFIX_OF[$k]}')"
    return 0
  fi
  PREFIX_OF[$k]="$b"
  PAIRS+=("$n	$b")
}

# --- 1. declared tracks from the consumer config ------------------------------------------
cfg_ok=0
declare -A UNRESOLVED=()     # track numbers declared but with no resolvable branch (never pruned)
export MT_REPO_ROOT="${MT_REPO_ROOT:-$project_root}"
if [ -r "$HERE/multitrack_config.sh" ]; then
  # shellcheck disable=SC1091 # the sourced library path is resolved at runtime from this script directory
  . "$HERE/multitrack_config.sh" 2>/dev/null
  if type mt_resolve_and_load >/dev/null 2>&1 && mt_resolve_and_load >/dev/null 2>&1; then cfg_ok=1; fi
  # With no host config file the loader falls back to its BUILT-IN default single-track
  # config (MT_DEFAULT_MODE=1): that is not a consumer declaration, so it is not used
  # (review 2026-11-03, F10).
  [ "${MT_DEFAULT_MODE:-0}" = 1 ] && cfg_ok=0
fi
if [ "$cfg_ok" -eq 1 ]; then
  i=1
  while [ "$i" -le "${MT_TRACK_COUNT:-0}" ]; do
    tid=""; tbr=""; tmount=""
    eval "tid=\${MT_TRACK_${i}_ID:-}; tbr=\${MT_TRACK_${i}_BRANCH:-}; tmount=\${MT_TRACK_${i}_MOUNT:-}"
    i=$((i+1))
    case "$tid" in track-[0-9]*) tn="${tid#track-}" ;; *) echo "SKIP     ${tid:-<no id>}: id is not track-<N>"; continue ;; esac
    case "$tn" in ''|*[!0-9]*) echo "SKIP     ${tid}: id is not track-<N>"; continue ;; esac
    case "$tbr" in
      ''|*'*'*|*'?'*|*'['*)
        hb=""
        if [ -n "$tmount" ] && [ -d "$tmount" ]; then hb="$(git -C "$tmount" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"; fi
        # shellcheck disable=SC2053 # the right side is the config's glob pattern on purpose (R3-5)
        if [ -n "$hb" ] && [ "$hb" != HEAD ] && [ -n "$tbr" ] && [[ "$hb" != $tbr ]]; then
          UNRESOLVED["$((10#$tn))"]=1; echo "SKIP     ${tid}: the mount's HEAD '$hb' does not match branch_pattern '$tbr' (not used, files kept)"
        elif [ -n "$hb" ] && [ "$hb" != HEAD ]; then add_pair "$tn" "$hb"
        else UNRESOLVED["$((10#$tn))"]=1; echo "SKIP     ${tid}: branch ${tbr:-<unset>} cannot be resolved (mount '${tmount:-<unset>}' is not a checkout with a named HEAD)"; fi ;;
      *) add_pair "$tn" "$tbr" ;;
    esac
  done
else
  echo "NOTE     no usable multitrack host config; using the current checkout only"
fi

# --- 2. the current checkout's own identity ----------------------------------------------------
if [ -r "$LABELER" ]; then
  lab="$(cd -- "$project_root" && bash "$LABELER" 2>/dev/null || true)"
  if [[ "$lab" =~ ^\(T([0-9]+)/([^\ ]+)\ - ]]; then
    case "${BASH_REMATCH[2]}" in '?') : ;; *) add_pair "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ;; esac
  fi
fi
if [ "${#PAIRS[@]}" -eq 0 ]; then echo "install_agent_label_defs: no track/branch could be derived; nothing to do"; exit 0; fi

# --- 3. generate per track ----------------------------------------------------------------------
gen_flags=(--models "$models" --efforts "$efforts")
[ "$do_check" -eq 1 ] && gen_flags+=(--check)
[ "$dry" -eq 1 ] && gen_flags+=(--dry-run)
declare -A DECLARED=()       # "T<N>-<san>" prefixes declared in this run
declare -A INFILTER=()       # "<model>-<effort>" pairs this run generates
read -r -a ML <<<"$(printf '%s' "$models" | tr ',' ' ')"
read -r -a EL <<<"$(printf '%s' "$efforts" | tr ',' ' ')"
for m in "${ML[@]}"; do for e in "${EL[@]}"; do INFILTER["${m}-${e}"]=1; done; done
any1=0; any3=0; any4=0; any5=0; nw=0; nu=0
for p in "${PAIRS[@]}"; do
  n="${p%%	*}"; b="${p#*	}"
  san="$(sanitise "$b")"
  DECLARED["T${n}-${san}"]=1
  out="$(bash "$GEN" --track "$n" --branch "$b" --out-dir "$out_dir" "${gen_flags[@]}")"; r=$?
  printf '%s\n' "$out"
  case "$r" in 0) ;; 1) any1=1 ;; 3) any3=1 ;; 4) any4=1 ;; *) any5=1 ;; esac
  w="$(printf '%s\n' "$out" | sed -n 's/.*written=\([0-9][0-9]*\) unchanged=\([0-9][0-9]*\).*/\1/p' | tail -n1)"
  u="$(printf '%s\n' "$out" | sed -n 's/.*written=\([0-9][0-9]*\) unchanged=\([0-9][0-9]*\).*/\2/p' | tail -n1)"
  nw=$((nw + ${w:-0})); nu=$((nu + ${u:-0}))
done

# --- 4. prune: genuine generated files of tracks that are no longer declared ---------------------
npruned=0
# Never prune on a guess (§11.4.201(4)): with no loadable consumer config the declared set is
# unknown, and a declared track whose branch is unresolvable keeps its files (R2-2).
[ "$cfg_ok" -eq 1 ] || echo "NOTE     no usable multitrack config: stale-file pruning skipped"
if [ "$cfg_ok" -eq 1 ] && [ -d "$out_dir" ]; then
  shopt -s nullglob
  for f in "$out_dir"/T[0-9]*-*.md; do
    b="${f##*/}"
    [[ "$b" =~ ^(T[0-9]+-[a-z0-9-]+)-(sonnet|opus)-(low|medium|high|xhigh|max)\.md$ ]] || continue
    # keep every file of a declared-but-unresolvable track (mount absent / host mismatch) (R2-2)
    tnum="${BASH_REMATCH[1]#T}"; tnum="${tnum%%-*}"
    [ -n "${UNRESOLVED[$((10#$tnum))]:-}" ] && continue
    # keep every file of a declared (track, branch), whatever its model/effort (F4) ...
    [ -n "${DECLARED[${BASH_REMATCH[1]}]:-}" ] && continue
    # ... and never prune a file outside this run's --models/--efforts filter (F4)
    [ -n "${INFILTER[${BASH_REMATCH[2]}-${BASH_REMATCH[3]}]:-}" ] || continue
    case "$(bash "$GEN" --classify "$f")" in
      genuine)
        if [ "$do_check" -eq 1 ]; then echo "DRIFT    $b (stale generated file; track/branch no longer declared)"; any1=1
        elif [ "$prune" -eq 0 ]; then echo "KEEP     $b (stale generated file; --no-prune)"
        elif [ "$dry" -eq 1 ]; then echo "PLAN     $b (prune stale generated file)"; npruned=$((npruned+1))
        else rm -f -- "$f" && { echo "PRUNED   $b (stale generated file)"; npruned=$((npruned+1)); }; fi ;;
      edited) echo "WARN     $b is a stale generated file that was hand-edited; left untouched" >&2 ;;
    esac
  done
  shopt -u nullglob
fi

echo "install_agent_label_defs: ${#PAIRS[@]} track/branch pair(s), written=${nw} unchanged=${nu} pruned=${npruned}$([ "$dry" -eq 1 ] && echo ' (dry-run)')$([ "$do_check" -eq 1 ] && echo ' (check)')"
if   [ "$any5" -eq 1 ]; then exit 5
elif [ "$any3" -eq 1 ]; then exit 3
elif [ "$any4" -eq 1 ]; then exit 4
elif [ "$any1" -eq 1 ]; then exit 1
fi
exit 0
