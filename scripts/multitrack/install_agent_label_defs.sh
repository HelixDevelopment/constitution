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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
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
    -h|--help)      sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die2 "unknown argument '$1'" ;;
  esac
done
[ -n "$project_root" ] || project_root="${PROJECT_ROOT:-$(pwd -P)}"
[ -d "$project_root" ] || die2 "project root '$project_root' is not a directory"
project_root="$(cd "$project_root" && pwd -P)"
[ -n "$out_dir" ] || out_dir="$project_root/.claude/agents"

# --- 0. refuse user-level targets (review 2026-11-03, F1) ----------------------------------
# The project root must not be the home directory or an ancestor of it, and neither the
# project root nor the out-dir may be (or lie inside, or contain) a user-level agent
# config directory: those hold the user's own agents, not a project's.
canon() { realpath -m -- "$1" 2>/dev/null || printf '%s\n' "$1"; }
under() { [ "$1" = "$2" ] || case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac; }  # $1 equal to or inside $2
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
[ -n "${HOME:-}" ] && { add_uniq HOMES "$HOME"; add_uniq HOMES "$(canon "$HOME")"; }
[ -n "$pw_home" ] && { add_uniq HOMES "$pw_home"; add_uniq HOMES "$(canon "$pw_home")"; }
add_cfg() { add_uniq USERCFG "$1"; add_uniq USERCFG "$(canon "$1")"; }
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && add_cfg "$CLAUDE_CONFIG_DIR"
for h in "${HOMES[@]:-}"; do
  [ -n "$h" ] || continue
  add_cfg "$h/.claude"
  for c in "$h"/.claude-*; do { [ -e "$c" ] || [ -L "$c" ]; } && add_cfg "$c"; done
done
if [ "${#HOMES[@]}" -eq 0 ] && [ "$do_check" -eq 0 ]; then
  refuse6 "the home directory cannot be resolved (HOME empty and no passwd entry); cannot prove the target is not a user-level directory"
fi
pr_c="$(canon "$project_root")"; od_c="$(canon "$out_dir")"
[ "$pr_c" = / ] && refuse6 "project root is the filesystem root"
for h in "${HOMES[@]:-}"; do
  [ -n "$h" ] || continue
  under "$h" "$pr_c" && refuse6 "project root '$pr_c' is the home directory or an ancestor of it"
  under "$h" "$od_c" && refuse6 "out-dir '$od_c' is the home directory or an ancestor of it"
done
for c in "${USERCFG[@]:-}"; do
  [ -n "$c" ] || continue
  under "$pr_c" "$c" && refuse6 "project root '$pr_c' is a user-level agent config directory or inside one ($c)"
  under "$od_c" "$c" && refuse6 "out-dir '$od_c' is inside the user-level agent config directory $c"
  under "$c" "$od_c" && refuse6 "out-dir '$od_c' contains the user-level agent config directory $c"
done
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
        if [ -n "$hb" ] && [ "$hb" != HEAD ]; then add_pair "$tn" "$hb"
        else UNRESOLVED["$((10#$tn))"]=1; echo "SKIP     ${tid}: branch ${tbr:-<unset>} cannot be resolved (mount '${tmount:-<unset>}' is not a checkout with a named HEAD)"; fi ;;
      *) add_pair "$tn" "$tbr" ;;
    esac
  done
else
  echo "NOTE     no usable multitrack host config; using the current checkout only"
fi

# --- 2. the current checkout's own identity ----------------------------------------------------
if [ -r "$LABELER" ]; then
  lab="$(cd "$project_root" && bash "$LABELER" 2>/dev/null || true)"
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
