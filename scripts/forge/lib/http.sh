# shellcheck shell=bash
# scripts/forge/lib/http.sh -- the one HTTP client of scripts/forge/forge.sh (sourced, never executed).
#
# fg_http METHOD PATH [PAYLOAD_FILE]  (PATH starts with "/", relative to FG_API_BASE)
# fg_http_url METHOD URL [PAYLOAD_FILE] (an absolute URL; it MUST share the origin of FG_API_BASE)
#   Sets FG_CODE (three digits), the body in "$FG_TMP/resp". Status 0 = an HTTP answer arrived (any code);
#   status 1 = no answer: FG_NET is one word of {timeout, dns, refused, tls, protocol, other}.
# Rules (the fix227 rules, CON-234): the token is a header line in a curl config on curl's STANDARD INPUT
# (curl -K -; printf is a builtin, so the token is in no argv and no file); the token charset check of
# credentials.sh rules out quotes, backslashes and newlines, so that line cannot be broken out of. The token
# is sent ONLY to the origin of FG_API_BASE (the pin; any other URL is refused before curl starts).
# curl runs with -q (no ~/.curlrc), --globoff, no redirect following (a 3xx is an answer the caller refuses),
# --proto =https (=http only for a loopback API base when FORGE_TEST_ALLOW_HTTP_LOOPBACK=1, the tests),
# a connect timeout and a total timeout, inside timeout(1) WITHOUT --foreground so a hung curl is killed
# with its whole process group. curl's own error text is never read or printed (it can carry a URL with a
# credential); only curl's exit status is mapped to the closed set above. Children get the clean
# environment of fg_env_clean only.
# curl runs as a BACKGROUND job that the shell `wait`s for, so a SIGTERM/SIGINT/SIGHUP is handled at once:
# the trap stops that one child (our own pid, $!), removes the temporary directory and ends the run with
# "REASON: interrupted" and "RESULT: INTERRUPTED" (exit 143, 130 or 129), never in silence.
# Endpoint identity (section 11.4.289(D)): every answer also records the peer the request reached
# (FG_PEER_IP, FG_PEER_PORT, FG_PEER_HTTP, FG_PEER_TLS = curl's ssl_verify_result, 0 = chain and name
# verified, FG_PEER_CERT = sha256 of the leaf certificate (DER), FG_PEER_SUBJECT, FG_PEER_REQID = the
# provider's request id header when it sends one). fg_peer_fields prints them as key=value words; values
# outside a safe character set, or holding a window of any known token value (lib/common.sh fg_secret_hit,
# review finding R2-I2), are shown as "unsafe", absent ones as "none"; every printed line passes fg_scrub. The response headers are kept
# in the private temporary directory only (they never carry the request's Authorization header).

FG_TMP="" FG_CODE="" FG_NET="" FG_CHILD=""
FG_PEER_IP="" FG_PEER_PORT="" FG_PEER_HTTP="" FG_PEER_TLS="" FG_PEER_CERT="" FG_PEER_SUBJECT="" FG_PEER_REQID=""

fg_tmp_init() {
  FG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/forge.XXXXXX")" || return 1
  : "${FG_TMP:?}"
  chmod 700 -- "$FG_TMP" || return 1
  trap fg_tmp_cleanup EXIT
  trap 'fg_interrupted 129' HUP; trap 'fg_interrupted 130' INT; trap 'fg_interrupted 143' TERM
}
fg_interrupted() { # RC: a signal arrived; stop our own curl child (the pid of timeout(1), which passes the
  # signal to curl), then end with a REASON and a RESULT line (the EXIT trap removes the temporary directory)
  trap - HUP INT TERM
  if [ -n "${FG_CHILD:-}" ]; then kill -TERM "$FG_CHILD" 2>/dev/null; wait "$FG_CHILD" 2>/dev/null; FG_CHILD=""; fi
  fg_msg "interrupted by a signal; any request in flight was stopped (a write may or may not have reached the forge: read the release back)"
  printf 'REASON: interrupted\nRESULT: INTERRUPTED\n'
  exit "$1"
}
fg_tmp_cleanup() {
  # guarded: only the directory this run created (a mktemp child with our prefix), files only, no -r
  case "${FG_TMP:-}" in
    */forge.??????)
      [ -d "$FG_TMP" ] || return 0
      rm -f -- "$FG_TMP"/resp "$FG_TMP"/code "$FG_TMP"/hdrs "$FG_TMP"/payload.json "$FG_TMP"/notes.txt "$FG_TMP"/page.json
      rmdir -- "$FG_TMP" 2>/dev/null ;;
  esac
  return 0
}

# fg_origin URL -> "scheme://host[:port]" or empty when URL is not a clean http(s) URL (no userinfo,
# no whitespace, no backslash, no percent sign outside the path encoding the providers produce themselves;
# a port must be 1..65535)
fg_origin() {
  local re='^(https?)://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?(/[A-Za-z0-9._~%/?=&,:+-]*)?$'
  local sc ho po
  [[ ${1:-} =~ $re ]] || return 1
  sc="${BASH_REMATCH[1]}" ho="${BASH_REMATCH[2],,}" po="${BASH_REMATCH[3]}"
  if [ -n "$po" ]; then fg_ok_port "${po#:}" || return 1; fi
  printf '%s://%s%s' "$sc" "$ho" "$po"
}
fg_origin_is_loopback() { [[ ${1:-} =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$ ]]; }

fg_http() { fg_http_url "$1" "$FG_API_BASE$2" "${3:-}"; }

fg_http_url() {
  local m="$1" url="$2" f="${3:-}" o proto crc tmo cfg h
  FG_CODE="" FG_NET=""
  o="$(fg_origin "$url")" || { FG_NET=protocol; return 1; }
  [ "$o" = "$FG_API_ORIGIN" ] || { FG_NET=pin; return 1; }
  case "$o" in
    https://*) proto='=https' ;;
    http://*) if [ "${FORGE_TEST_ALLOW_HTTP_LOOPBACK:-0}" = 1 ] && fg_origin_is_loopback "$o"; then proto='=http'; else FG_NET=protocol; return 1; fi ;;
    *) FG_NET=protocol; return 1 ;;
  esac
  case "$m" in GET|POST|PATCH|PUT) ;; *) FG_NET=protocol; return 1 ;; esac
  tmo="${FORGE_HTTP_TIMEOUT:-60}"; [[ $tmo =~ ^[0-9]{1,4}$ ]] || tmo=60
  local args=(-q -sS --globoff --max-redirs 0 --proto "$proto" --proto-redir "$proto" -m "$tmo" --connect-timeout 15
              -K - -X "$m" -o "$FG_TMP/resp" -D "$FG_TMP/hdrs"
              -w '%{http_code}\n%{remote_ip}\n%{remote_port}\n%{http_version}\n%{ssl_verify_result}\n%{certs}'
              -H 'User-Agent: helix-forge-tool/1')
  for h in "${FG_HDRS[@]}"; do args+=(-H "$h"); done
  [ -n "$f" ] && args+=(-H 'Content-Type: application/json' --data-binary "@$f")
  : >"$FG_TMP/resp"; : >"$FG_TMP/code"; : >"$FG_TMP/hdrs"
  FG_PEER_IP="" FG_PEER_PORT="" FG_PEER_HTTP="" FG_PEER_TLS="" FG_PEER_CERT="" FG_PEER_SUBJECT="" FG_PEER_REQID=""
  cfg=""
  if [ -n "${FG_TOKEN:-}" ]; then
    # shellcheck disable=SC2059   # FG_AUTH_FMT is a fixed provider format with one %s
    printf -v cfg "header = \"$FG_AUTH_FMT\"\n" "$FG_TOKEN"
  fi
  # background job + wait: a trapped signal interrupts the wait at once (fg_interrupted stops the child)
  printf '%s' "$cfg" | timeout -k 5 "$((tmo + 10))" curl "${args[@]}" "$url" >"$FG_TMP/code" 2>/dev/null &
  FG_CHILD=$!
  cfg=""
  wait "$FG_CHILD"; crc=$?
  FG_CHILD=""
  if [ "$crc" -ne 0 ]; then
    case "$crc" in
      124|137|28) FG_NET=timeout ;;
      6) FG_NET=dns ;;
      7) FG_NET=refused ;;
      35|51|53|54|58|59|60|77|80|83|90|91) FG_NET=tls ;;
      1|3|47) FG_NET=protocol ;;
      *) FG_NET=other ;;
    esac
    return 1
  fi
  { IFS= read -r FG_CODE; IFS= read -r FG_PEER_IP; IFS= read -r FG_PEER_PORT; IFS= read -r FG_PEER_HTTP
    IFS= read -r FG_PEER_TLS; } <"$FG_TMP/code" 2>/dev/null
  [[ $FG_CODE =~ ^[0-9]{3}$ ]] || { FG_NET=other; FG_CODE=""; return 1; }
  _fg_peer_read
  local pth="${url#"$o"}"; pth="${pth%%\?*}"
  fg_peer_trace "$m ${pth:-/}"
  return 0
}

# _fg_peer_read: validate the peer fields; leaf certificate digest and subject from curl's %{certs};
# the request id from the response headers (names known to be ids, value checked)
_fg_peer_read() {
  local l pem="" inb=0 seen=0 n v
  [[ $FG_PEER_IP =~ ^[0-9A-Fa-f.:]{2,45}$ ]] || FG_PEER_IP=unsafe
  [[ $FG_PEER_PORT =~ ^[0-9]{1,5}$ ]] || FG_PEER_PORT=unsafe
  [[ $FG_PEER_HTTP =~ ^[0-9.]{1,4}$ ]] || FG_PEER_HTTP=unsafe
  [[ $FG_PEER_TLS =~ ^[0-9]{1,10}$ ]] || FG_PEER_TLS=unsafe
  while IFS= read -r l; do
    l="${l%$'\r'}"
    if [ "$seen" -eq 0 ] && [ -z "$FG_PEER_SUBJECT" ] && [[ $l =~ ^Subject:(.*)$ ]]; then
      FG_PEER_SUBJECT="${BASH_REMATCH[1]}"
    fi
    case "$l" in
      '-----BEGIN CERTIFICATE-----') [ "$seen" -eq 0 ] && inb=1 ;;
      '-----END CERTIFICATE-----') [ "$inb" -eq 1 ] && { inb=0; seen=1; } ;;
      *) [ "$inb" -eq 1 ] && pem="$pem$l" ;;
    esac
  done < <(tail -n +6 -- "$FG_TMP/code" 2>/dev/null)
  if [ -n "$pem" ] && [[ $pem =~ ^[A-Za-z0-9+/=]+$ ]]; then
    v="$(printf '%s' "$pem" | base64 -d 2>/dev/null | sha256sum 2>/dev/null)"; v="${v%% *}"
    [[ $v =~ ^[0-9a-f]{64}$ ]] && FG_PEER_CERT="$v"
  fi
  FG_PEER_SUBJECT="${FG_PEER_SUBJECT# }"
  [ -z "$FG_PEER_SUBJECT" ] || [[ $FG_PEER_SUBJECT =~ ^[A-Za-z0-9\ =*.,_-]{1,200}$ ]] || FG_PEER_SUBJECT=unsafe
  FG_PEER_SUBJECT="${FG_PEER_SUBJECT// /_}"
  # no server-supplied field may carry a known token value (review finding R2-I2); fg_line scrubs again
  for n in FG_PEER_IP FG_PEER_PORT FG_PEER_HTTP FG_PEER_TLS FG_PEER_SUBJECT; do
    fg_secret_hit "${!n}" && printf -v "$n" '%s' unsafe
  done
  while IFS= read -r l; do
    l="${l%$'\r'}"
    [[ $l =~ ^([A-Za-z0-9-]{1,60}):[[:space:]]*(.*)$ ]] || continue
    n="${BASH_REMATCH[1],,}"; v="${BASH_REMATCH[2]}"
    case "$n" in
      x-github-request-id|x-request-id|x-correlation-id|x-trace-id|request-id|x-amz-request-id|x-gitea-request-id) ;;
      x-gitlab-meta) [[ $v =~ \"correlation_id\":\"([A-Za-z0-9._:-]{1,100})\" ]] && v="${BASH_REMATCH[1]}" || v="" ;;
      *) continue ;;
    esac
    [[ $v =~ ^[A-Za-z0-9._:-]{1,100}$ ]] || v=unsafe
    fg_secret_hit "$v" && v=unsafe      # a server that reflects a token value in its id (review R2-I2)
    [ -n "$v" ] && { FG_PEER_REQID="$n=$v"; break; }
  done <"$FG_TMP/hdrs"
  return 0
}

# fg_peer_fields -> "peer=IP:PORT http=V tls_verify=N cert_sha256=H subject=S request_id=NAME=VALUE"
fg_peer_fields() {
  printf 'peer=%s:%s http=%s tls_verify=%s cert_sha256=%s subject=%s request_id=%s' \
    "${FG_PEER_IP:-none}" "${FG_PEER_PORT:-none}" "${FG_PEER_HTTP:-none}" "${FG_PEER_TLS:-none}" \
    "${FG_PEER_CERT:-none}" "${FG_PEER_SUBJECT:-none}" "${FG_PEER_REQID:-none}"
}
# fg_peer_trace WHAT: with FORGE_TRACE_PEER=1 (scripts/forge/live_probe.sh sets it) print one PEER line for
# the last answer; otherwise nothing
fg_peer_trace() {
  [ "${FORGE_TRACE_PEER:-0}" = 1 ] || return 0
  fg_line "PEER: $1 status=${FG_CODE:-none} $(fg_peer_fields)"
}

# fg_json FILTER -> jq -r over the last response body (stderr dropped; empty on bad JSON)
fg_json() { jq -r "$1" <"$FG_TMP/resp" 2>/dev/null; }

# fg_keys_summary -> "object keys=a,b" | "array items=N item_keys=a,b" | "type=..." (names only, never
# values; key names outside [A-Za-z0-9_.-]{1,40} are counted, not shown)
fg_keys_summary() {
  # shellcheck disable=SC2016  # a jq program: $k is a jq variable
  fg_json '
    def ks: (keys | map(select(test("^[A-Za-z0-9_.-]{1,40}$"))) | join(",")) as $k
            | (keys | map(select(test("^[A-Za-z0-9_.-]{1,40}$") | not)) | length) as $h
            | $k + (if $h > 0 then " (+\($h) unnamed)" else "" end);
    if type == "object" then
      "object keys=" + ks
      + (if (._embedded | type) == "object" then
           " " + ([._embedded | to_entries[] | select(.value | type == "array")
                   | "embedded." + (.key | if test("^[A-Za-z0-9_.-]{1,40}$") then . else "?" end)
                     + " items=" + (.value | length | tostring)
                     + (if (.value | length) > 0 and (.value[0] | type) == "object" then " item_keys=" + (.value[0] | ks) else "" end)]
                  | join(" "))
         else "" end)
    elif type == "array" then
      "array items=" + (length | tostring)
      + (if length > 0 and (.[0] | type) == "object" then " item_keys=" + (.[0] | ks) else "" end)
    else "type=" + type end' | head -c 2000
}

# fg_net_end: end the run for a request that got no answer
fg_net_end() {
  case "$FG_NET" in
    pin) fg_api_err redirect_refused "refused: a URL outside the pinned API origin (no token is sent there)" ;;
    *) fg_api_err "network_${FG_NET:-other}" "no HTTP answer (class ${FG_NET:-other}); curl's own message is withheld" ;;
  esac
}
