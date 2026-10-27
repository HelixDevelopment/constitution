#!/usr/bin/env bash
# scripts/lib/safe_rm.sh — runtime layer of constitution §11.4.287.
#
# Source this file and call `safe_rm_rf <path>...` instead of a bare recursive
# delete in any script. It REFUSES (returns 2, deletes nothing) when a target is:
#   - empty or unset                      (the 2026-10-23 incident: "$W/home" with W empty)
#   - option-like (starts with '-'), contains a newline, or ends in '.' or '..'
#   - not resolvable by `readlink -m`, or not absolute after resolution
#     (relative paths are resolved against $PWD first)
#   - the filesystem root or an absolute entry of protected_paths.list
#   - a direct child of /home or /Users (a user home directory)
#   - a home directory ($HOME or any SAFE_RM_EXTRA_HOMES entry) or an ANCESTOR of one
#   - a protected home-relative child of such a home (the '~/' entries of
#     protected_paths.list, e.g. ~/scripts, ~/.claude*)
#   - the temp root itself ($TMPDIR, default /tmp); the temp-root depth bonus is
#     withheld when the temp root is or contains a home or a home root
#   - fewer than SAFE_RM_MIN_DEPTH (default 3) path components deep
#     (a path strictly below the temp root counts as deep enough)
#   - outside every root in SAFE_RM_ALLOWED_ROOTS (colon-separated), when that is set
# Every rule is applied to the LEXICAL path (parent directories resolved, the last
# component NOT followed: this is what rm removes) and, when the argument ends in
# '/', also to the fully resolved path. The deletion itself always uses the stripped
# lexical path and never follows the link, so refusing "link/" when the link points at
# a protected path is DELIBERATELY CONSERVATIVE: it may refuse a call that would only
# have removed the link (use the plain "link" form for that). A plain symlink leaf
# that points at a protected path is removable as a link.
# Validation is atomic: all targets are validated before ANY is deleted, so one bad
# argument means nothing is deleted. The deletion is NOT atomic: if rm fails on
# argument k (permissions, busy file), arguments 1..k-1 are already gone and the
# function returns rm's status without trying the rest.
#
# Configuration:
#   protected_paths.list  next to this file — the list of protected paths this helper
#                         reads. It is NOT the single source shared with the PreToolUse
#                         guard: the guard carries its own built-in home-children set (a
#                         test checks only one direction of alignment), and that set is
#                         larger (Documents, Desktop, Downloads, Pictures, Music, Videos,
#                         Obsidian, bin, go, opt, Android, .git, .aws, .kube, .docker,
#                         .password-store are guard-protected but absent from the list, so
#                         safe_rm_rf can delete them; tracked gap, 2026-10-26). If it is missing,
#                         unreadable, malformed, has no absolute entry, or this file
#                         was sourced without a real file path (for example eval of
#                         its text), every call is refused (fail closed).
#   SAFE_RM_EXTRA_HOMES   colon-separated absolute dirs treated exactly like $HOME
#                         (lets tests use a fake home without reassigning HOME).
#                         Not glob-expanded; a relative entry is a config error.
#   SAFE_RM_EXTRA_HOME_ROOTS  colon-separated absolute dirs whose direct children are user
#                         homes (like /home and /Users, which are always included together
#                         with their symlink-resolved forms).
#   SAFE_RM_MIN_DEPTH     non-negative integer without leading zeros, default 3.
#   SAFE_RM_ALLOWED_ROOTS colon-separated opt-in allow-list of absolute roots.
#                         Not glob-expanded; a relative entry is a config error; when the
#                         variable is SET it must yield at least one entry (empty fails closed).
#
# Honest boundary (§11.4.6): this protects calls routed through it. It cannot stop
# a script that calls the delete directly — that is the PreToolUse guard's job
# (scripts/hooks/guard-destructive-paths.py) and the review rule that scripts use
# ${VAR:?} and safe_rm_rf. The deletion uses the validated lexical path, which
# narrows but does not close the check-to-use race (a parent directory swapped for
# a symlink between validation and rm). Absolute list entries match exactly, not as
# subtrees: system subtrees deeper than the listed entry (for example /usr/local/lib)
# are guarded only by the depth rule and the allow-list, and unlisted direct children
# of a home (for example ~/Documents) are not protected.

_SAFE_RM_LIB_DIR=""
_SAFE_RM_LIST=""
# The list is trusted only when this file really is a file named safe_rm.sh (symlinks are
# resolved, so the list is the one next to the REAL file). An eval-loaded copy, a renamed
# copy, or a library sourced from text reports the CALLER as BASH_SOURCE and is refused.
_SAFE_RM_SRC="${BASH_SOURCE[0]:-}"
_SAFE_RM_REAL=""
if [ -n "$_SAFE_RM_SRC" ] && [ -f "$_SAFE_RM_SRC" ]; then
  _SAFE_RM_REAL="$(readlink -f -- "$_SAFE_RM_SRC" 2>/dev/null)" || _SAFE_RM_REAL=""
fi
if [ -n "$_SAFE_RM_REAL" ] && [ "${_SAFE_RM_REAL##*/}" = "safe_rm.sh" ]; then
  _SAFE_RM_LIB_DIR="$(cd -- "$(dirname -- "$_SAFE_RM_REAL")" 2>/dev/null && pwd -P)" || _SAFE_RM_LIB_DIR=""
  if [ -n "$_SAFE_RM_LIB_DIR" ]; then _SAFE_RM_LIST="$_SAFE_RM_LIB_DIR/protected_paths.list"; fi
fi
unset _SAFE_RM_SRC _SAFE_RM_REAL

_safe_rm_refuse() { printf 'safe_rm_rf: REFUSED %s — %s\n' "$1" "$2" >&2; return 2; }

# Loads protected_paths.list into _SRM_ABS (absolute entries) and _SRM_REL
# (home-relative component patterns). Returns 1 and sets _SRM_ERR on any problem.
_safe_rm_load_list() {
  _SRM_ABS=(); _SRM_REL=(); _SRM_ERR=""
  local f="$_SAFE_RM_LIST" line rel n=0
  if [ -z "$f" ] || [ ! -f "$f" ] || [ ! -r "$f" ]; then
    _SRM_ERR="protected list not readable: ${f:-(library path unresolved)}"; return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|'#'*) continue;; esac
    case "$line" in
      /*)
        while [ "$line" != "/" ] && [ "${line%/}" != "$line" ]; do line="${line%/}"; done
        _SRM_ABS+=("$line")
        rel="$(readlink -m -- "$line" 2>/dev/null)" || rel=""
        [ -z "$rel" ] || [ "$rel" = "$line" ] || _SRM_ABS+=("$rel");;
      \~/*)  # a literal '~/' prefix (escaped, so no tilde expansion)
        rel="${line#\~/}"
        case "$rel" in ''|*/*|.|..) _SRM_ERR="protected list line $n: bad home-relative entry '$line'"; return 1;; esac
        _SRM_REL+=("$rel");;
      *) _SRM_ERR="protected list line $n: unrecognised entry '$line'"; return 1;;
    esac
  done < "$f" || { _SRM_ERR="protected list could not be read: $f"; return 1; }
  [ "${#_SRM_ABS[@]}" -gt 0 ] || { _SRM_ERR="protected list has no absolute entry: $f"; return 1; }
  return 0
}

# _safe_rm_split_abs VARNAME LIST NAME NEED: split a colon list into array VARNAME with no
# globbing; every entry must be absolute, the list must not contain a newline, and when NEED=1
# (the variable is SET) it must yield at least one entry. Returns 1 (message on stderr) otherwise.
_safe_rm_split_abs() {
  local __out="$1" __list="$2" __name="$3" __need="${4:-0}" __e __arr=() __parts=()
  case "$__list" in *$'\n'*) _safe_rm_refuse "(config)" "$__name contains a newline"; return 1;; esac
  if [ -n "$__list" ]; then
    IFS=: read -r -a __parts <<<"$__list"
    for __e in "${__parts[@]}"; do
      [ -n "$__e" ] || continue
      case "$__e" in /*) ;; *) _safe_rm_refuse "(config)" "$__name entry '$__e' is not absolute"; return 1;; esac
      case "$__e" in *'*'*|*'?'*|*'['*) _safe_rm_refuse "(config)" "$__name entry '$__e' contains a glob character"; return 1;; esac
      __arr+=("$__e")
    done
  fi
  if [ "$__need" = 1 ] && [ "${#__arr[@]}" -eq 0 ]; then
    _safe_rm_refuse "(config)" "$__name is set but yields no entries (failing closed)"; return 1
  fi
  eval "$__out=(\"\${__arr[@]}\")"
  return 0
}

safe_rm_rf() {
  local arg stripped base d pd phys rlf cand h rel pat p depth root ok tmp_real tmp_bonus tmp_depth min_depth hp need hr hrp rest hpre rpre
  local homes=() roots=() extra=() cands=() physlist=() hroots=() xroots=()
  [ "$#" -gt 0 ] || { _safe_rm_refuse "(no arguments)" "nothing to delete"; return 2; }
  _safe_rm_load_list || { _safe_rm_refuse "(all)" "$_SRM_ERR (failing closed)"; return 2; }
  min_depth="${SAFE_RM_MIN_DEPTH-3}"; [ -n "$min_depth" ] || min_depth=3
  case "$min_depth" in ''|*[!0-9]*) _safe_rm_refuse "(config)" "SAFE_RM_MIN_DEPTH must be a non-negative integer, got '$min_depth'"; return 2;; esac
  case "$min_depth" in 0) ;; 0*) _safe_rm_refuse "(config)" "SAFE_RM_MIN_DEPTH must not have leading zeros, got '$min_depth'"; return 2;; esac
  [ "${#min_depth}" -le 3 ] || { _safe_rm_refuse "(config)" "SAFE_RM_MIN_DEPTH has more than 3 digits"; return 2; }
  case "${TMPDIR:-/tmp}" in /*) ;; *) _safe_rm_refuse "(config)" "TMPDIR is not absolute"; return 2;; esac
  tmp_real="$(readlink -m -- "${TMPDIR:-/tmp}" 2>/dev/null)" || tmp_real=""
  [ -n "$tmp_real" ] || tmp_real=/tmp
  tmp_bonus=0
  # the temp-root depth bonus is granted only for /tmp, /var/tmp, or a temp root at least
  # 2 components deep that is not itself a protected path (TMPDIR=/usr must not buy depth)
  if [ "$tmp_real" = /tmp ] || [ "$tmp_real" = /var/tmp ]; then tmp_bonus=1
  else
    tmp_depth="$(printf '%s' "$tmp_real" | awk -F/ '{n=0; for(i=1;i<=NF;i++) if($i!="") n++; print n}')"
    if [ "$tmp_depth" -ge 2 ]; then
      tmp_bonus=1
      for p in "${_SRM_ABS[@]}"; do [ "$tmp_real" != "$p" ] || tmp_bonus=0; done
    fi
  fi

  # homes: $HOME plus SAFE_RM_EXTRA_HOMES, all resolved; an unresolvable or relative entry is a config error
  [ -n "${HOME:-}" ] || { _safe_rm_refuse "(config)" "HOME is unset or empty (failing closed)"; return 2; }
  case "$HOME" in /*) ;; *) _safe_rm_refuse "(config)" "HOME is not absolute"; return 2;; esac
  hp="$(readlink -m -- "$HOME" 2>/dev/null)" || { _safe_rm_refuse "(config)" "cannot resolve \$HOME"; return 2; }
  [ -n "$hp" ] || { _safe_rm_refuse "(config)" "cannot resolve \$HOME"; return 2; }
  homes+=("$hp")
  _safe_rm_split_abs extra "${SAFE_RM_EXTRA_HOMES:-}" SAFE_RM_EXTRA_HOMES || return 2
  for h in "${extra[@]}"; do
    hp="$(readlink -m -- "$h" 2>/dev/null)" || { _safe_rm_refuse "(config)" "cannot resolve SAFE_RM_EXTRA_HOMES entry '$h'"; return 2; }
    homes+=("$hp")
  done
  need=0; [ -z "${SAFE_RM_ALLOWED_ROOTS+x}" ] || need=1
  _safe_rm_split_abs roots "${SAFE_RM_ALLOWED_ROOTS:-}" SAFE_RM_ALLOWED_ROOTS "$need" || return 2
  # roots under which user homes live: /home, /Users, their resolved forms, and injected ones
  hroots=(/home /Users)
  for h in /home /Users; do hp="$(readlink -m -- "$h" 2>/dev/null)" && [ -n "$hp" ] && hroots+=("$hp"); done
  _safe_rm_split_abs xroots "${SAFE_RM_EXTRA_HOME_ROOTS:-}" SAFE_RM_EXTRA_HOME_ROOTS || return 2
  for h in "${xroots[@]}"; do
    hp="$(readlink -m -- "$h" 2>/dev/null)" || { _safe_rm_refuse "(config)" "cannot resolve SAFE_RM_EXTRA_HOME_ROOTS entry '$h'"; return 2; }
    hroots+=("$h" "$hp")
  done

  # no depth bonus when the temp root is, or is an ancestor of, a home or a home root (TMPDIR=$HOME would
  # otherwise make everything below it "deep enough")
  if [ "$tmp_bonus" -eq 1 ]; then
    for h in "${homes[@]}" "${hroots[@]}"; do
      hp="${h%/}"; [ -n "$hp" ] || continue
      if [ "$tmp_real" = "$hp" ]; then tmp_bonus=0; break; fi
      case "$hp/" in "$tmp_real"/*) tmp_bonus=0; break;; esac
    done
  fi

  for arg in "$@"; do
    [ -n "$arg" ] || { _safe_rm_refuse "(empty)" "empty path (unset or empty variable?)"; return 2; }  # MUT:empty-arg
    case "$arg" in -*) _safe_rm_refuse "$arg" "looks like an option, not a path"; return 2;; esac
    case "$arg" in *$'\n'*) _safe_rm_refuse "(newline)" "path contains a newline"; return 2;; esac
    stripped="$arg"
    while [ "$stripped" != "/" ] && [ "${stripped%/}" != "$stripped" ]; do stripped="${stripped%/}"; done
    base="${stripped##*/}"
    case "$base" in .|..) _safe_rm_refuse "$arg" "last path component is '$base'"; return 2;; esac
    # lexical path: resolve the parent directory, keep the last component unfollowed
    if [ -z "$base" ]; then phys="/"
    else
      case "$stripped" in */*) d="${stripped%/*}"; [ -n "$d" ] || d=/;; *) d=.;; esac
      pd="$(readlink -m -- "$d" 2>/dev/null)" || { _safe_rm_refuse "$arg" "readlink -m failed"; return 2; }
      [ -n "$pd" ] || { _safe_rm_refuse "$arg" "cannot resolve"; return 2; }
      if [ "$pd" = "/" ]; then phys="/$base"; else phys="$pd/$base"; fi
    fi
    cands=()
    cands+=("$phys")  # MUT:lexical
    if [ "$arg" != "$stripped" ]; then
      # trailing slash: rm follows a symlink leaf, so the resolved target is checked too
      rlf="$(readlink -m -- "$arg" 2>/dev/null)" || { _safe_rm_refuse "$arg" "readlink -m failed"; return 2; }
      [ -n "$rlf" ] || { _safe_rm_refuse "$arg" "cannot resolve"; return 2; }
      cands+=("$rlf")
    fi
    for cand in "${cands[@]}"; do
      case "$cand" in /*) ;; *) _safe_rm_refuse "$arg" "not absolute after resolution"; return 2;; esac
      [ "$cand" != "/" ] || { _safe_rm_refuse "$arg" "resolves to the filesystem root"; return 2; }
      for p in "${_SRM_ABS[@]}"; do
        [ "$cand" != "$p" ] || { _safe_rm_refuse "$arg" "resolves to protected system path $cand"; return 2; }
      done
      for hr in "${hroots[@]}"; do
        hrp="${hr%/}"; [ -n "$hrp" ] || continue
        [ "$cand" != "$hrp" ] || { _safe_rm_refuse "$arg" "resolves to a home root ($hrp)"; return 2; }
        case "$hrp/" in "$cand"/*) _safe_rm_refuse "$arg" "is an ancestor of a home root ($hrp)"; return 2;; esac
        case "$cand" in "$hrp"/*)
          rel="${cand#"$hrp"/}"
          case "$rel" in
            */*) rest="${rel#*/}"
              case "$rest" in */*) ;; *)
                # shellcheck disable=SC2254
                for pat in "${_SRM_REL[@]}"; do case "$rest" in $pat) _safe_rm_refuse "$arg" "is protected home child ~/$pat of a user home under $hrp"; return 2;; esac; done;;
              esac;;
            *) _safe_rm_refuse "$arg" "resolves to a user home directory $cand"; return 2;;
          esac;;
        esac
      done
      [ "$cand" != "$tmp_real" ] || { _safe_rm_refuse "$arg" "resolves to the temp root $tmp_real"; return 2; }
      for h in "${homes[@]}"; do
        [ "$cand" != "$h" ] || { _safe_rm_refuse "$arg" "resolves to a home directory ($h)"; return 2; }
        case "$h/" in "$cand"/*) _safe_rm_refuse "$arg" "is an ancestor of a home directory ($h)"; return 2;; esac
        hpre="${h%/}"
        case "$cand" in "$hpre"/*)
          rel="${cand#"$hpre"/}"
          case "$rel" in */*) ;; *)
            # $pat is intentionally an unquoted glob taken from the list (e.g. .claude*)
            # shellcheck disable=SC2254
            for pat in "${_SRM_REL[@]}"; do case "$rel" in $pat) _safe_rm_refuse "$arg" "is protected home child ~/$pat of $h"; return 2;; esac; done  # MUT:protected-child
            ;;
          esac;;
        esac
      done
      depth="$(printf '%s' "$cand" | awk -F/ '{n=0; for(i=1;i<=NF;i++) if($i!="") n++; print n}')"
      if [ "$tmp_bonus" -eq 1 ]; then case "$cand" in "$tmp_real"/?*) depth=$((depth + 10#$min_depth));; esac; fi
      if ! [ "$depth" -ge "$min_depth" ] 2>/dev/null; then
        _safe_rm_refuse "$arg" "only $depth path components deep (minimum $min_depth)"; return 2
      fi
      if [ "${#roots[@]}" -gt 0 ]; then
        ok=1
        for root in "${roots[@]}"; do
          root="$(readlink -m -- "$root" 2>/dev/null)" || continue
          rpre="${root%/}"
          case "$cand/" in "$rpre"/*) ok=0; break;; esac
        done
        [ "$ok" -eq 0 ] || { _safe_rm_refuse "$arg" "outside SAFE_RM_ALLOWED_ROOTS"; return 2; }
      fi
    done
    physlist+=("$phys")
  done
  # delete the validated lexical paths (trailing slashes stripped), not the raw arguments
  for phys in "${physlist[@]}"; do
    [ -e "$phys" ] || [ -L "$phys" ] || continue
    command rm -rf -- "$phys" || return $?
  done
  return 0
}
