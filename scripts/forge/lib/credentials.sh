# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/lib/credentials.sh -- token discovery for scripts/forge/forge.sh (sourced, never executed).
#
# fg_token_resolve NAME... sets FG_TOKEN (a plain shell variable, never exported), FG_TOKEN_NAME and
# FG_TOKEN_SOURCE (env | keys_file | dotenv), or leaves FG_TOKEN empty. FG_TOKEN_STATE is one of
# found | absent | invalid. Order (first usable value wins; within a source the names are tried in the
# order config/forge/hosts.tsv lists them):
#   1. the process environment (carried over by fg_env_clean as unexported shell variables);
#   2. the operator keys file: FORGE_KEYS_FILE, default $HOME/api_keys.sh (the same convention as
#      JEV_API_KEYS_FILE, section 11.4.279(E)). It is sourced in a CHILD bash (bounded by timeout, standard
#      output and error discarded while sourcing) that prints exactly ONE variable, by name, into a pipe;
#      the main shell never sources it;
#   3. the project .env: FORGE_ENV_FILE, default <repository root>/.env. It is PARSED (NAME=VALUE lines,
#      optional `export `, optional matching single or double quotes, last assignment wins), never executed.
#      The DEFAULT is used only when forge.sh itself lies inside that repository (the project that vendors
#      the tool); the .env of any other repository the command is run from is NOT read (a clone of
#      someone else's repository must not be able to hand the tool a token), with the note
#      "dotenv_not_trusted". FORGE_ENV_FILE given explicitly is always used (with the file checks below).
# A keys file or .env that is not a regular file owned by this user, is a symlink, or is readable or
# writable by group or others is refused with the warning "keys_file_insecure" and skipped (never read).
# A placeholder value counts as absent: empty, shorter than 8 characters, one repeated character, or a known
# dummy word (changeme, xxx, placeholder, <...>, your-token..., todo, none, null, dummy, test).
# A value with characters outside [A-Za-z0-9._~+/=-] or longer than 400 characters is "invalid" and never
# sent anywhere (it could break out of the curl config line). An invalid value STOPS the search: a lower
# source is never used in its place (the operator set that variable; a silent substitute would hide it).
# Nothing here prints a value; messages name variables and files only.

FG_TOKEN="" FG_TOKEN_NAME="" FG_TOKEN_SOURCE="" FG_TOKEN_STATE=absent FG_TOKEN_BAD=""

_fg_is_placeholder() { # VALUE: status 0 when the value counts as absent
  local v="$1" l first
  [ -n "$v" ] || return 0
  [ "${#v}" -lt 8 ] && return 0
  l="${v,,}"
  case "$l" in
    *changeme*|*change-me*|*replace-me*|*replaceme*|*placeholder*|your-*|your_*|\<*\>|xxx*|todo|none|null|dummy|test|example*) return 0 ;;
  esac
  first="${v:0:1}"
  [ -z "${v//"$first"/}" ] && return 0
  return 1
}
_fg_valid_token() { [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{8,400}$ ]]; }

_fg_file_safe() { # PATH: status 0 when PATH is a regular, non-symlink file owned by us with mode & 077 == 0
  local f="$1" mode owner
  [ -e "$f" ] || [ -L "$f" ] || return 2       # absent: not a warning
  { [ -f "$f" ] && [ ! -L "$f" ]; } || return 1
  mode="$(stat -c '%a' -- "$f" 2>/dev/null)" || return 1
  owner="$(stat -c '%u' -- "$f" 2>/dev/null)" || return 1
  [ "$owner" = "$(id -u)" ] || return 1
  [[ $mode =~ ^[0-7]+$ ]] || return 1
  [ $(( 8#$mode & 8#077 )) -eq 0 ] || return 1
  return 0
}

# _fg_keys_value FILE NAME -> value on stdout (empty when unset); runs a child bash in the clean environment
# shellcheck disable=SC2016  # the child script is single-quoted on purpose: it expands in the child
_fg_keys_value() {
  timeout -k 2 "${FORGE_KEYS_TIMEOUT:-10}" "$BASH" --noprofile --norc -c '
    set +x +a +e +u
    exec 4>&1 >/dev/null 2>&1 </dev/null
    . "$1"
    unset -f builtin printf 2>/dev/null
    builtin printf "%s" "${!2-}" >&4' fg-keys "$1" "$2" 2>/dev/null
}

# _fg_dotenv_value FILE NAME -> value on stdout; a parser, never an interpreter
_fg_dotenv_value() {
  local f="$1" name="$2" line val="" re q
  re="^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=(.*)$"
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ $re ]] || continue
    val="${BASH_REMATCH[2]}"
    val="${val%$'\r'}"
    q="${val:0:1}"
    if { [ "$q" = '"' ] || [ "$q" = "'" ]; } && [ "${#val}" -ge 2 ] && [ "${val: -1}" = "$q" ]; then
      val="${val:1:${#val}-2}"
    else
      val="${val%%[[:space:]]#*}"
      val="${val%"${val##*[![:space:]]}"}"
    fi
  done <"$f"
  printf '%s' "$val"
}

_fg_try_value() { # SOURCE NAME VALUE: accept, mark invalid, or skip
  if _fg_is_placeholder "$3"; then return 1; fi
  if ! _fg_valid_token "$3"; then
    FG_TOKEN_BAD="$2" FG_TOKEN_STATE=invalid
    return 2        # stop: a malformed value the operator set is never replaced by a lower source
  fi
  FG_TOKEN="$3"; FG_TOKEN_NAME="$2"; FG_TOKEN_SOURCE="$1"; FG_TOKEN_STATE=found
  return 0
}

# fg_keys_file_path / fg_env_file_path -> the path the search uses (empty when none applies)
fg_keys_file_path() { printf '%s' "${FORGE_KEYS_FILE:-${HOME:-/nonexistent}/api_keys.sh}"; }
fg_env_file_path() {
  if [ -n "${FORGE_ENV_FILE:-}" ]; then printf '%s' "$FORGE_ENV_FILE"; return 0; fi
  [ -n "${FG_REPO_ROOT:-}" ] || return 0
  case "${FG_DIR_PHYS:-/nonexistent}/" in "$FG_REPO_ROOT"/*) printf '%s' "$FG_REPO_ROOT/.env" ;; esac
  return 0
}

# fg_is_credential_file PATH: status 0 when PATH is (the same file as) the keys file or the .env the search
# uses -- compared by device:inode after following links, so a symlink or a hard link is caught too
fg_is_credential_file() {
  local p="$1" a b f
  a="$(stat -L -c '%d:%i' -- "$p" 2>/dev/null)" || return 1
  for f in "$(fg_keys_file_path)" "$(fg_env_file_path)" "${FG_REPO_ROOT:+$FG_REPO_ROOT/.env}"; do
    [ -n "$f" ] || continue
    b="$(stat -L -c '%d:%i' -- "$f" 2>/dev/null)" || continue
    [ "$a" = "$b" ] && return 0
  done
  return 1
}

# _fg_keys_all FILE -> "NAME NUL VALUE NUL" for every variable of the shape [A-Z][A-Z0-9_]*TOKEN the keys file
# sets, through a pipe (stdout of a child bash in the clean environment; nothing is written to a file)
# shellcheck disable=SC2016  # the child script is single-quoted on purpose: it expands in the child
_fg_keys_all() {
  timeout -k 2 "${FORGE_KEYS_TIMEOUT:-10}" "$BASH" --noprofile --norc -c '
    set +x +a +e +u
    exec 4>&1 >/dev/null 2>&1 </dev/null
    . "$1"
    unset -f builtin printf compgen 2>/dev/null
    for _n in $(builtin compgen -v); do
      [[ $_n =~ ^[A-Z][A-Z0-9_]{0,62}TOKEN$ ]] || continue
      builtin printf "%s\0%s\0" "$_n" "${!_n-}" >&4
    done' fg-keys "$1" 2>/dev/null
}
# _fg_dotenv_names FILE -> the [A-Z][A-Z0-9_]*TOKEN names a .env file assigns (one per line; names only)
_fg_dotenv_names() {
  local line re='^[[:space:]]*(export[[:space:]]+)?([A-Z][A-Z0-9_]{0,62}TOKEN)[[:space:]]*='
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ $re ]] && printf '%s\n' "${BASH_REMATCH[2]}"
  done <"$1"
}
_fg_sec_add() { # NAME VALUE: remember a candidate secret (8+ characters, not a placeholder; no duplicates)
  local v="$2" i
  [ "${#v}" -ge 8 ] || return 0
  _fg_is_placeholder "$v" && return 0
  for i in "${!FG_SEC_VALS[@]}"; do [ "${FG_SEC_VALS[$i]}" = "$v" ] && return 0; done
  FG_SEC_NAMES+=("$1"); FG_SEC_VALS+=("$v")
}

# fg_secrets_load: fill FG_SEC_NAMES / FG_SEC_VALS (lib/common.sh) with every candidate token value the tool
# can know of: the resolved token; every [A-Z][A-Z0-9_]*TOKEN variable of the environment (carried over by
# fg_env_clean as unexported shell variables); every name of EVERY hosts-map row (FG_ALL_TOKEN_VARS) and
# every *TOKEN name the keys file sets, from the keys file (when it passes the file check); every *TOKEN
# name of the .env the search uses and of the current repository's .env (parsed, never executed; when they
# pass the file check). Status 1 when the keys file could not be read to its end (timeout): the caller
# then refuses to publish, because the set would be incomplete.
fg_secrets_load() {
  local n v kf ef f rc=0 names=" "
  FG_SEC_NAMES=() FG_SEC_VALS=()
  [ -n "${FG_TOKEN:-}" ] && _fg_sec_add "${FG_TOKEN_NAME:-token}" "$FG_TOKEN"
  for n in $(compgen -v); do
    fg_ok_varname "$n" || continue
    case "$n" in FG_TOKEN) continue ;; esac
    _fg_sec_add "$n" "${!n-}"
  done
  kf="$(fg_keys_file_path)"
  if [ -n "$kf" ] && _fg_file_safe "$kf"; then
    local kv=() i st
    mapfile -d '' kv < <(_fg_keys_all "$kf")
    wait "$!" 2>/dev/null; st=$?
    for ((i = 0; i + 1 < ${#kv[@]}; i += 2)); do fg_ok_varname "${kv[i]}" && _fg_sec_add "${kv[i]}" "${kv[i+1]}"; done
    kv=()
    # a child that timed out or failed did not read the whole keys file: the set may be incomplete
    [ "$st" -eq 0 ] || rc=1
  fi
  v=""
  ef="$(fg_env_file_path)"
  for f in "$ef" "${FG_REPO_ROOT:+$FG_REPO_ROOT/.env}"; do
    if [ -z "$f" ] || ! _fg_file_safe "$f"; then continue; fi
    for n in ${FG_ALL_TOKEN_VARS//,/ } $(_fg_dotenv_names "$f"); do
      fg_ok_varname "$n" || continue
      case "$names" in *" $f:$n "*) continue ;; esac
      names="$names$f:$n "
      v="$(_fg_dotenv_value "$f" "$n")"; _fg_sec_add "$n" "$v"
    done
  done
  v=""
  return "$rc"
}

# fg_text_has_secret TEXT: status 0 when TEXT holds a window (lib/common.sh fg_secret_hit) of any candidate
# token value of fg_secrets_load -- all hosts, all sources, not only the target host's row. Sets
# FG_SECRET_NAME (a variable NAME). No value is printed, written or passed to a child as an argument.
fg_text_has_secret() { fg_secret_hit "$1"; }

fg_token_resolve() {
  local n v kf ef rc
  FG_TOKEN="" FG_TOKEN_NAME="" FG_TOKEN_SOURCE="" FG_TOKEN_STATE=absent FG_TOKEN_BAD=""
  for n in "$@"; do
    fg_ok_varname "$n" || continue
    v="${!n-}"
    _fg_try_value env "$n" "$v"; case $? in 0) return 0 ;; 2) return 1 ;; esac
  done
  kf="$(fg_keys_file_path)"
  _fg_file_safe "$kf"; rc=$?
  if [ "$rc" -eq 0 ]; then
    for n in "$@"; do
      fg_ok_varname "$n" || continue
      v="$(_fg_keys_value "$kf" "$n")"
      _fg_try_value keys_file "$n" "$v"; case $? in 0) return 0 ;; 2) return 1 ;; esac
    done
  elif [ "$rc" -eq 1 ]; then
    fg_msg "WARNING keys_file_insecure: the keys file is not a regular file of this user with mode 0600 (or stricter); it is not read"
  fi
  ef="$(fg_env_file_path)"
  if [ -z "$ef" ]; then
    [ -n "${FG_REPO_ROOT:-}" ] && [ -e "$FG_REPO_ROOT/.env" ] && \
      fg_msg "NOTE dotenv_not_trusted: the .env of the current repository is not read (forge.sh is not inside that repository); set FORGE_ENV_FILE to use it"
    ef=/nonexistent
  fi
  _fg_file_safe "$ef"; rc=$?
  if [ "$rc" -eq 0 ]; then
    for n in "$@"; do
      fg_ok_varname "$n" || continue
      v="$(_fg_dotenv_value "$ef" "$n")"
      _fg_try_value dotenv "$n" "$v"; case $? in 0) return 0 ;; 2) return 1 ;; esac
    done
  elif [ "$rc" -eq 1 ]; then
    fg_msg "WARNING keys_file_insecure: the project .env is not a regular file of this user with mode 0600 (or stricter); it is not read"
  fi
  return 1
}
