#!/usr/bin/env bash
# jev-probe.sh <endpoint-id> <url> — replayable reachability probe for cm_jev_detection (JEV_PROBE_CMD).
# Exit 0 when the endpoint ANSWERED an HTTP request (any status: a 401 proves the server is there);
# exit 1 on no answer (refused, timeout, TLS failure); exit 2 when it cannot determine (curl absent, key send refused,
# or a URL that is neither loopback (anchored parse) nor a provider pin; the record's id is not trusted).
# A credential is sent ONLY to an https origin that matches a provider pin and that pin's own key variable.
# CA file: a request that carries a KEY uses system trust or the OPERATOR's JEV_CA_FILE environment variable only;
# the detection record is untrusted input and its `ca_file` is honoured solely for UNKEYED local llmctl-* probes.
# Path probed: <url>/healthz for local llmctl endpoints, <url> itself otherwise.
set -uo pipefail
id="${1:-}"; url="${2:-}"
[ -n "$url" ] || { echo "usage: jev-probe.sh <id> <url>" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "jev-probe: curl absent (cannot determine)" >&2; exit 2; }
# shellcheck source=lib_keys.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib_keys.sh"
ca="${JEV_CA_FILE:-}"
rec_ca=""
if [ -n "${JEV_DETECTION_FILE:-}" ] && [ -f "$JEV_DETECTION_FILE" ] && command -v jq >/dev/null 2>&1; then
  rec_ca="$(jq -r --arg i "$id" '[.endpoints[]? | select(.id == $i) | .ca_file // empty][0] // empty' "$JEV_DETECTION_FILE" 2>/dev/null || true)"
fi
# Hosted endpoint with a key variable: replay the minimal AUTHENTICATED probe (key read by NAME, sent on stdin;
# an HTTP answer of any class proves the server is there).
if [ -n "${JEV_DETECTION_FILE:-}" ] && [ -f "$JEV_DETECTION_FILE" ] && command -v jq >/dev/null 2>&1; then
  kv="$(jq -r --arg i "$id" '[.endpoints[]? | select(.id == $i) | .key_var // empty][0] // empty' "$JEV_DETECTION_FILE" 2>/dev/null || true)"
  if [ -n "$kv" ]; then
    pp="$(jq -r --arg i "$id" '[.endpoints[]? | select(.id == $i) | .probe_path // empty][0] // "/v1/systemone"' "$JEV_DETECTION_FILE" 2>/dev/null || echo /v1/systemone)"
    md="$(jq -r --arg i "$id" '[.endpoints[]? | select(.id == $i) | .model // empty][0] // "jev-latest"' "$JEV_DETECTION_FILE" 2>/dev/null || echo jev-latest)"
    # The record is UNTRUSTED input: a key is only ever sent to an https URL whose origin AND variable name match a
    # provider pin (jev_pin_ok, inside auth_probe). A refusal is an honest "cannot determine" (rc 2), never a probe.
    refusal="$(jev_pin_ok "$kv" "${url%/}${pp}" 2>&1 >/dev/null)" || {
      echo "jev-probe: refused to send a key: $(printf '%s' "$refusal" | tr -d '\n' | cut -c1-200)" >&2; exit 2; }
    cls="$(auth_probe "$kv" "${url%/}${pp}" "$md" "$ca")"
    case "$cls" in 2xx|401|403|other) exit 0 ;; timeout) exit 1 ;; refused) exit 2 ;; esac
  fi
fi
# Unkeyed plain GET. The URL comes from the untrusted record, so it is fetched ONLY when its host is loopback by the
# anchored authority parse (jev_url_host_class: userinfo, backslash, '%', whitespace and control characters make a URL
# `invalid`, never loopback) or its origin is a provider pin. The record's own `id` (llmctl-*) is NOT trusted to widen
# that (review r3 m-r3-1); anything else is not requested at all (no SSRF).
hc="$(jev_url_host_class "$url")"
allowed=1
[ "$hc" = "loopback" ] && allowed=0
if [ "$allowed" -ne 0 ] && jev_origin_pinned "$url"; then allowed=0; fi
if [ "$allowed" -ne 0 ]; then
  echo "jev-probe: refused: url is not loopback (class=$hc), nor a provider pin (not requested)" >&2
  exit 2
fi
case "$id" in
  llmctl-*) target="${url%/}/healthz"; [ -n "$ca" ] || ca="$rec_ca" ;;
  *) target="$url" ;;
esac
args=(-q -sS --globoff -o /dev/null -w '%{http_code}' --proto '=http,https' --proto-redir '=http,https' --max-time "${JEV_PROBE_TIMEOUT:-3}")
[ -n "$ca" ] && [ -f "$ca" ] && args+=(--cacert "$ca")
code="$(curl "${args[@]}" "$target" 2>/dev/null)" || code="000"
[ -n "$code" ] && [ "$code" != "000" ]
