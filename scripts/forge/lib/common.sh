# shellcheck shell=bash
# scripts/forge/lib/common.sh -- shared parts of scripts/forge/forge.sh (sourced, never executed).
#
# 1. fg_env_clean "$@": the environment of every child process is built POSITIVELY. Called first, before any
#    external command. In the caller's process it re-executes the script ONCE with an EMPTY environment
#    (bash `exec -c`, argv[0] "forge-clean-env") and sends the values it needs over file descriptor 9 (a pipe
#    written by shell builtins in a forked subshell: never an argv, never a file). Carried over:
#      - exported again (children see them): PATH HOME USER LOGNAME LANG LANGUAGE TZ TMPDIR SSH_AUTH_SOCK
#        XDG_RUNTIME_DIR; LC_ALL is then set to C;
#      - as plain shell variables NO child receives: every name of the shape [A-Z][A-Z0-9_]*TOKEN (the
#        candidate token variables of config/forge/hosts.tsv) and every FORGE_* setting.
#    Nothing else crosses: no environment entry whose name is not a shell identifier, no SHELLOPTS/BASHOPTS
#    (an inherited xtrace or allexport), no BASH_ENV, no exported function, no proxy variable, no other
#    secret. Status 3: /proc/$$/cmdline or /proc/$$/environ cannot be read (Linux /proc is required; without
#    it the state cannot be checked, so the tool refuses). Status 4: the re-exec failed. Status 5: the
#    re-executed process still has a non-empty environment (refused, no loop).
# 2. Output and exit helpers: every run ends with "RESULT: <WORD>" on stdout, preceded by "REASON: <code>"
#    when there is one. Exit codes: 0 OK, 1 FAIL, 2 USAGE, 3 GAP (precondition/forge state; reason code),
#    4 API (network or unexpected HTTP answer).
# 3. Validators for every string that reaches a URL path or the output.
#
# Rules carried over from the fix227 release tooling (CON-234): no token in argv, URL, child environment,
# file or log; set +x first; allexport undone; non-identifier environment names dropped.

FG_MARK=forge-clean-env
FG_ENV_EXPORT=" PATH HOME USER LOGNAME LANG LANGUAGE TZ TMPDIR SSH_AUTH_SOCK XDG_RUNTIME_DIR "

_fg_reserved() { # NAME: status 0 when NAME is never carried over (bash meanings, internal names)
  case "$1" in BASH*|SHELLOPTS|ENV|IFS|PS[0-4]|POSIXLY_CORRECT|CDPATH|GLOBIGNORE|EXECIGNORE|FUNCNEST|TMOUT|HISTFILE|PROMPT_COMMAND|FG_*|_FG_*|_fg_*) return 0 ;; esac
  return 1
}
_fg_carry_shell() { # NAME: status 0 when NAME is carried as an unexported shell variable
  [[ $1 =~ ^[A-Z][A-Z0-9_]{0,62}TOKEN$ ]] && return 0
  [[ $1 =~ ^FORGE_[A-Z0-9_]{1,58}$ ]] && return 0
  return 1
}
_fg_env_dump() { # builtins only (runs in a forked subshell): records "e|s NUL NAME NUL VALUE NUL"
  local v
  for v in $(compgen -e); do
    [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || continue
    _fg_reserved "$v" && continue
    case "$FG_ENV_EXPORT" in *" $v "*) printf 'e\0%s\0%s\0' "$v" "${!v}"; continue ;; esac
    _fg_carry_shell "$v" && printf 's\0%s\0%s\0' "$v" "${!v}"
  done
}
_fg_env_restore() {
  local k n val
  if { : <&9; } 2>/dev/null; then
    while IFS= read -r -d '' k <&9 && IFS= read -r -d '' n <&9 && IFS= read -r -d '' val <&9; do
      [[ $n =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || continue
      _fg_reserved "$n" && continue
      case "$k" in
        e) case "$FG_ENV_EXPORT" in *" $n "*) printf -v "$n" '%s' "$val" 2>/dev/null && export "${n?}" ;; esac ;;
        s) _fg_carry_shell "$n" && printf -v "$n" '%s' "$val" 2>/dev/null ;;
      esac
    done
    exec 9<&-
  fi
  LC_ALL=C; export LC_ALL
}
_fg_env_state() { # sets _FG_STATE: clean | dirty | blind (from /proc/$$)
  local a0="" e n=0
  _FG_STATE=blind
  { [ -r "/proc/$$/cmdline" ] && [ -r "/proc/$$/environ" ]; } || return 0
  { IFS= read -r -d '' a0 <"/proc/$$/cmdline"; } 2>/dev/null || [ -n "$a0" ] || return 0
  while IFS= read -r -d '' e || [ -n "$e" ]; do n=$((n + 1)); e=""; done <"/proc/$$/environ" 2>/dev/null || return 0
  _FG_A0="$a0"
  if [ "$a0" = "$FG_MARK" ] && [ "$n" -eq 0 ]; then _FG_STATE=clean; else _FG_STATE=dirty; fi
}
fg_env_clean() {
  _fg_env_state
  case "$_FG_STATE" in
    clean) _fg_env_restore; return 0 ;;
    blind) return 3 ;;
  esac
  [ "${_FG_A0:-}" = "$FG_MARK" ] && return 5
  { [ -n "${BASH:-}" ] && [ -f "$0" ] && [ -r "$0" ]; } || return 4
  shopt -s execfail
  exec -c -a "$FG_MARK" "$BASH" "$0" "$@" 9< <(_fg_env_dump)
  return 4
}

# ---- the one output sanitiser (round 3, review finding R2-I2) -----------------------------------------------
# FG_SEC_NAMES / FG_SEC_VALS (filled by fg_secrets_load in lib/credentials.sh): every candidate token value the
# tool can know of -- every *TOKEN variable of EVERY hosts-map row, of the environment, of the keys file and of
# the .env files -- as plain, unexported shell arrays (never a file, never an argv, never a child environment).
# fg_secret_hit TEXT: status 0 when TEXT holds a "window" of one of them: the whole value when it is shorter
# than 12 characters, otherwise any 12-character piece of it (so a prefix, a suffix or a reflected part of a
# token counts too). Sets FG_SECRET_NAME (a NAME, never a value). Long text goes to grep through a pipe.
FG_SEC_NAMES=() FG_SEC_VALS=() FG_SECRET_NAME=""
FG_SEC_WIN=12
_fg_windows() { # VALUE -> one window per line
  local v="$1" i n="${#1}"
  if [ "$n" -lt "$FG_SEC_WIN" ]; then printf '%s\n' "$v"; return 0; fi
  for ((i = 0; i + FG_SEC_WIN <= n; i++)); do printf '%s\n' "${v:i:FG_SEC_WIN}"; done
}
# shellcheck disable=SC2034  # FG_SECRET_NAME is read by the callers (forge.sh, live_probe.sh)
fg_secret_hit() {
  local t="$1" i v w n
  FG_SECRET_NAME=""
  [ "${#FG_SEC_VALS[@]}" -gt 0 ] && [ -n "$t" ] || return 1
  if [ "${#t}" -gt 4096 ]; then
    # a quick filter first (one grep, the windows through a pipe), then the name by the slower loop below
    printf '%s' "$t" | grep -qF -f <(for v in "${FG_SEC_VALS[@]}"; do _fg_windows "$v"; done) 2>/dev/null
    # status 1 = no window anywhere; 0 = a hit, and 2 (grep could not run) also falls through to the exact loop:
    # an instrument error is never read as "no secret" (section 11.4.201(6))
    [ "$?" -eq 1 ] && return 1
  fi
  for i in "${!FG_SEC_VALS[@]}"; do
    v="${FG_SEC_VALS[$i]}"; n="${#v}"
    if [ "$n" -lt "$FG_SEC_WIN" ]; then
      [[ $t == *"$v"* ]] && { FG_SECRET_NAME="${FG_SEC_NAMES[$i]}"; return 0; }
      continue
    fi
    for ((w = 0; w + FG_SEC_WIN <= n; w++)); do
      [[ $t == *"${v:w:FG_SEC_WIN}"* ]] && { FG_SECRET_NAME="${FG_SEC_NAMES[$i]}"; return 0; }
    done
  done
  return 1
}
# fg_scrub TEXT -> TEXT with every space-separated word that holds a secret window replaced by "unsafe"
# ("key=value" words keep a clean key: "request_id=unsafe"). Every line the tool prints goes through it.
# A multi-line TEXT is scrubbed line by line, and every line is kept (review round 3, m6).
fg_scrub() {
  local t="$1" w k out="" words lines l
  if ! fg_secret_hit "$t"; then printf '%s' "$t"; return 0; fi
  if [[ $t == *$'\n'* ]]; then
    mapfile -t lines <<<"$t"
    for l in "${!lines[@]}"; do
      [ "$l" -gt 0 ] && out+=$'\n'
      out+="$(fg_scrub "${lines[$l]}")"
    done
    printf '%s' "$out"
    return 0
  fi
  IFS=' ' read -r -a words <<<"$t"
  for w in "${words[@]}"; do
    if fg_secret_hit "$w"; then
      k="${w%%=*}"
      if [ "$k" != "$w" ] && ! fg_secret_hit "$k"; then w="$k=unsafe"; else w=unsafe; fi
    fi
    out="${out:+$out }$w"
  done
  printf '%s' "$out"
}

# ---- output -----------------------------------------------------------------------------------------------
fg_msg() { printf 'forge: %s\n' "$(fg_scrub "$*")" >&2; }
fg_line() { printf '%s\n' "$(fg_scrub "$*")"; }
fg_end() { # WORD RC [REASON]
  [ -n "${3:-}" ] && printf 'REASON: %s\n' "$(fg_scrub "$3")"
  printf 'RESULT: %s\n' "$1"
  exit "$2"
}
fg_usage_err() { fg_msg "$1"; fg_end USAGE 2 "${2:-}"; }
fg_gap() { [ -n "${2:-}" ] && fg_msg "$2"; fg_end GAP 3 "$1"; }
fg_api_err() { fg_msg "$2"; fg_end API 4 "$1"; }
fg_fail() { fg_msg "$2"; fg_end FAIL 1 "$1"; }

# ---- validators -------------------------------------------------------------------------------------------
fg_ok_segment() { [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] && [[ $1 != *..* ]]; }
fg_ok_tag() { [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] && [[ $1 != *..* ]]; }
fg_ok_sha() { [[ ${1:-} =~ ^[0-9a-f]{40}$ ]]; }
fg_ok_id() { [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,63}$ ]]; }   # numeric ids and UUIDs; never / or .
fg_ok_port() { [[ ${1:-} =~ ^[0-9]{1,5}$ ]] && [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 65535 ]; }
fg_ok_varname() { [[ ${1:-} =~ ^[A-Z][A-Z0-9_]{0,62}TOKEN$ ]]; }
fg_bool() { case "${1:-}" in true|false) printf '%s' "$1" ;; *) printf 'unknown' ;; esac; }
