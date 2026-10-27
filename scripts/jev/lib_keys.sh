#!/usr/bin/env bash
# lib_keys.sh — hosted-key discovery helpers (source, don't exec). Shared by bootstrap.sh, jev-probe.sh
# and the CM-JEV-DETECTION gate so all three classify a key the same way.
#
# A key is only ever read BY VARIABLE NAME inside a subshell: first the process environment, then the
# operator's keys file. The VALUE is classified (or sent to curl on STDIN) inside that subshell and is
# never printed, logged, stored or placed on a command line.
#
# Keys file precedence (documented in docs/jev/bootstrap-reference.md):
#   1. JEV_API_KEYS_FILE   2. CMA_KEYS_FILE (the claude_toolkit name)   3. $HOME/api_keys.sh

jev_keys_file() { printf '%s' "${JEV_API_KEYS_FILE:-${CMA_KEYS_FILE:-$HOME/api_keys.sh}}"; }

is_var_name() { case "$1" in ""|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; *) return 0 ;; esac; }

# _jev_key_value <VAR> -> prints the value on stdout (INTERNAL, only ever called inside a command
# substitution that classifies or pipes it; never echoed). Reads the environment first, then sources the
# keys file in a BOUNDED subshell (JEV_KEYS_FILE_TIMEOUT, default 5 s) so a keys file that never returns
# cannot stall detection. rc 0 value found / 1 absent / 3 keys file timed out.
_jev_key_value() {
  local v="$1" kf="${KEYS_FILE:-$(jev_keys_file)}" tmo="${JEV_KEYS_FILE_TIMEOUT:-5}"
  [ -n "${!v:-}" ] && { printf '%s' "${!v}"; return 0; }
  [ -f "$kf" ] && [ -r "$kf" ] || return 1
  local out rc
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout --kill-after=1 "$tmo" bash -c 'set +e +u +o pipefail; . "$1" >/dev/null 2>&1 </dev/null; v="$2"; printf "%s" "${!v:-}"' _ "$kf" "$v" 2>/dev/null)"; rc=$?
    [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] && return 3
  else
    out="$(bash -c 'set +e +u +o pipefail; . "$1" >/dev/null 2>&1 </dev/null; v="$2"; printf "%s" "${!v:-}"' _ "$kf" "$v" 2>/dev/null)"
  fi
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# key_state <VAR> -> "real" | "absent<TAB>reason" | "placeholder<TAB>reason"
key_state() {
  local v="$1" kf k rc lk first
  kf="${KEYS_FILE:-$(jev_keys_file)}"
  is_var_name "$v" || { printf 'absent\tinvalid variable name in the provider pin\n'; return 0; }
  if [ -z "${!v:-}" ]; then
    [ -e "$kf" ] || { printf 'absent\tkeys file missing (variable not in the environment either)\n'; return 0; }
    { [ -r "$kf" ] && [ -f "$kf" ]; } || { printf 'absent\tkeys file not readable\n'; return 0; }
  fi
  k="$(KEYS_FILE="$kf" _jev_key_value "$v")"; rc=$?
  if [ "$rc" -eq 3 ]; then printf 'absent\tkeys file timed out while sourcing (never treated as a key)\n'; return 0; fi
  [ -n "$k" ] || { printf 'absent\tvariable not set in the environment or the keys file\n'; return 0; }
  lk="$(printf '%s' "$k" | tr 'A-Z' 'a-z')"
  # The dummy list is checked BEFORE the length rule, so 'changeme' is reported as what it is.
  case "$lk" in x|xx|xxx|changeme|change-me|replace-me|replaceme|your-key-here|your_api_key|placeholder|dummy|test|none|null|todo|empty|"<"*">")
    printf 'placeholder\tknown dummy value (treated as absent)\n'; return 0 ;; esac
  if [ "${#k}" -lt 16 ]; then printf 'placeholder\tvalue shorter than 16 characters (treated as absent)\n'; return 0; fi
  first="${k:0:1}"
  if [ -z "${k//"$first"/}" ]; then printf 'placeholder\tvalue is one repeated character (treated as absent)\n'; return 0; fi
  case "$k" in *[[:cntrl:]]*) printf 'placeholder\tvalue contains control characters (never sent anywhere)\n'; return 0 ;; esac
  printf 'real\n'
}

# ---- provider-pin allowlist: the ONLY places a key may be sent -----------------------------------------------------------
# jev_pin_rows -> "<key_var>\t<base_url>" per hosted pin. Source order: JEV_PINS_FILE, CMA_JEV_PINS_FILE, the
# claude_toolkit checkout under JEV_CONSTITUTION_ROOT or this tree, else the builtin defaults (the same two
# hosted pins bootstrap.sh falls back to). Local-gateway rows (no base URL) are never listed.
jev_pin_rows() {
  local f="${JEV_PINS_FILE:-${CMA_JEV_PINS_FILE:-}}" d
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for c in "${JEV_CONSTITUTION_ROOT:-/nonexistent}/submodules/claude_toolkit/scripts/providers/jev.json" "$d/../../submodules/claude_toolkit/scripts/providers/jev.json"; do
      [ -f "$c" ] && { f="$c"; break; }
    done
  fi
  if [ -n "$f" ] && [ -f "$f" ] && command -v jq >/dev/null 2>&1; then
    local rows
    rows="$(jq -r '(.hosted // {}) | to_entries[] | select(.value.enabled != false) | select((.value.base_url // "") != "") | [(.value.key_var // ""), .value.base_url] | @tsv' "$f" 2>/dev/null)" || rows=""
    if [ -n "$rows" ]; then printf '%s\n' "$rows"; return 0; fi
  fi
  printf 'TYPESAFE_API_KEY\thttps://api.typesafe.ai\nOPENROUTER_API_KEY\thttps://openrouter.ai/api\n'
}

# _jev_split_url <url> -> sets _U_ORIGIN (https://host[:port], lower-case, an explicit :443 dropped) and _U_PATH (no
# trailing /). rc 1 if not a plain https URL: userinfo, whitespace, control characters, a query/fragment, a '..' segment
# or a percent-encoded dot / slash / backslash / control byte (%2e %2f %5c %00-%1f, any case) all refuse.
_jev_split_url() {
  local u="$1" rest auth lc
  case "$u" in https://*) ;; *) return 1 ;; esac
  case "$u" in *[[:space:][:cntrl:]]*|*\\*|*\?*|*\#*) return 1 ;; esac
  lc="$(printf '%s' "$u" | tr 'A-Z' 'a-z')"
  case "$lc" in *%*|*..\;*|*\{*|*\}*|*\[*|*\]*) return 1 ;; esac   # any percent-encoding (%2e %2f %5c %25 %7f %u %00-%1f), '..;' and curl glob characters
  rest="${u#https://}"; auth="${rest%%/*}"
  [ -n "$auth" ] || return 1
  case "$auth" in *@*|*" "*) return 1 ;; esac
  auth="$(printf '%s' "$auth" | tr 'A-Z' 'a-z')"
  auth="${auth%:443}"
  _U_ORIGIN="https://$auth"
  if [ "$rest" = "${rest%%/*}" ]; then _U_PATH=""; else _U_PATH="/${rest#*/}"; fi
  _U_PATH="${_U_PATH%/}"
  case "$_U_PATH/" in */../*|*/./*|*//*) return 1 ;; esac
  return 0
}

# jev_url_host_class <url> -> prints loopback | other | invalid  (anchored authority parse, never a substring split).
# invalid: not http(s), or whitespace / control / backslash / '%' / '@' (userinfo) anywhere in the URL. loopback: the
# authority is EXACTLY 127.0.0.1, localhost or [::1] with an optional :port. Everything else is `other` (a hosted or
# LAN host). A userinfo trick such as http://127.0.0.1:80@evil.example/ is `invalid`, never `loopback` (review r3 m-r3-1).
jev_url_host_class() {
  local u="${1:-}" rest auth lc
  case "$u" in http://*|https://*) ;; *) echo invalid; return 0 ;; esac
  case "$u" in *[[:space:][:cntrl:]]*|*\\*|*%*|*@*) echo invalid; return 0 ;; esac
  rest="${u#*://}"; auth="${rest%%[/?#]*}"
  [ -n "$auth" ] || { echo invalid; return 0; }
  lc="$(printf '%s' "$auth" | tr 'A-Z' 'a-z')"
  if [[ "$lc" =~ ^(127\.0\.0\.1|localhost|\[::1\])(:([0-9]{1,5}))?$ ]]; then
    # the port must be 1..65535 (review r4 m4-6)
    [ -z "${BASH_REMATCH[3]}" ] || { [ "$((10#${BASH_REMATCH[3]}))" -ge 1 ] && [ "$((10#${BASH_REMATCH[3]}))" -le 65535 ]; } || { echo invalid; return 0; }
    echo loopback
  else echo other; fi
}

# jev_origin_pinned <url> -> rc 0 when the URL is a plain https URL whose origin equals a provider pin's origin.
jev_origin_pinned() {
  local u="$1" pv pu
  _jev_split_url "$u" || return 1
  local uo="$_U_ORIGIN"
  while IFS=$'\t' read -r pv pu; do
    [ -n "$pv" ] || continue
    _jev_split_url "$pu" || continue
    [ "$_U_ORIGIN" = "$uo" ] && return 0
  done < <(jev_pin_rows)
  return 1
}

# jev_pin_ok <VAR> <url> -> rc 0 only when url is an https URL on a pinned origin, a pin on that origin names VAR as
# its OWN key variable, and the URL path equals or extends that pin's base path at a '/' boundary. Several pins may
# share an origin: ANY row whose variable and path both match allows. Otherwise rc 1 and a reason on stderr (never the
# key). This is the single choke point that keeps a key off any unpinned or non-https host.
jev_pin_ok() {
  local v="$1" u="$2" pv pu po pp ok=1 reason=""
  is_var_name "$v" || { echo "refused: invalid variable name" >&2; return 1; }
  _jev_split_url "$u" || { echo "refused: url is not a plain https URL ($(printf '%s' "${u%%[?#]*}" | cut -c1-80))" >&2; return 1; }
  local uo="$_U_ORIGIN" up="$_U_PATH"
  while IFS=$'\t' read -r pv pu; do
    [ -n "$pv" ] || continue
    _jev_split_url "$pu" || continue
    po="$_U_ORIGIN"; pp="$_U_PATH"
    [ "$po" = "$uo" ] || continue
    if [ "$pv" != "$v" ]; then [ -n "$reason" ] || reason="refused: variable $v is not the pinned key variable for $uo"; continue; fi
    if [ -z "$pp" ] || [ "$up" = "$pp" ] || [ "${up#"$pp"/}" != "$up" ]; then ok=0; break; fi
    reason="refused: path is outside the pinned base path"
  done < <(jev_pin_rows)
  [ "$ok" -eq 0 ] && return 0
  if [ -n "$reason" ]; then echo "$reason" >&2; return 1; fi
  echo "refused: origin $uo is not a provider pin (no key is sent to an unpinned host)" >&2
  return 1
}

# auth_probe <VAR> <url> [model] [ca_file] -> 2xx | 401 | 403 | other | timeout | unavailable | refused
# A minimal authenticated POST with one harmless noul question (the documented wire format). The key goes to curl on
# STDIN (-K -), never argv; only the HTTP status CLASS is returned. REFUSES (class `refused`, reason on stderr, curl
# never started) unless jev_pin_ok VAR url holds; curl is pinned to https for the request AND any redirect.
auth_probe() {
  local v="$1" u="$2" m="${3:-jev-latest}" ca="${4:-}" kf; kf="${KEYS_FILE:-$(jev_keys_file)}"
  command -v curl >/dev/null 2>&1 || { echo unavailable; return 0; }
  is_var_name "$v" || { echo unavailable; return 0; }
  jev_pin_ok "$v" "$u" || { echo refused; return 0; }
  case "$m" in ""|*[!A-Za-z0-9._/:-]*) m="jev-latest" ;; esac
  local body
  body="$(printf '{"model":"%s","state":"probe","questions":{"p":{"type":"noul","instructions":"Is 2 greater than 1?","criteria":{"true":"yes","false":"no"}}}}' "$m")"
  local k rc
  k="$(KEYS_FILE="$kf" _jev_key_value "$v")"; rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$k" ]; then echo unavailable; return 0; fi
  case "$k" in *[[:cntrl:]]*) echo unavailable; return 0 ;; esac
  local ek="${k//\\/\\\\}"; ek="${ek//\"/\\\"}"
  local args=(-q -K - -sS --globoff -o /dev/null -w '%{http_code}' --proto '=https' --proto-redir '=https' --max-time "${JEV_PROBE_TIMEOUT:-5}" -H 'Content-Type: application/json' -d "$body")
  [ -n "$ca" ] && [ -f "$ca" ] && args+=(--cacert "$ca")
  local c
  c="$(printf 'header = "Authorization: Bearer %s"\n' "$ek" | curl "${args[@]}" "$u" 2>/dev/null)" || c=000
  case "$c" in 000|"") echo timeout ;; 2??) echo 2xx ;; 401) echo 401 ;; 403) echo 403 ;; *) echo other ;; esac
}

keys_file_mode() { stat -c '%a' "${KEYS_FILE:-$(jev_keys_file)}" 2>/dev/null || stat -f '%Lp' "${KEYS_FILE:-$(jev_keys_file)}" 2>/dev/null || echo ""; }
