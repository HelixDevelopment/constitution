#!/usr/bin/env bash
# tests/forge/fixtures/curl_recorder.sh -- TEST DOUBLE (section 11.4.289(C)(2)), copied by tests/forge/lib.sh
# (ft_curl_wrap) into a sandbox bin dir as "curl". It appends its own argv (one word per line) and its own
# start environment (/proc/self/environ, one entry per line) to curl.log beside itself, then runs the real
# curl (path in real_curl beside itself) with the same arguments and standard input. The tests read
# curl.log to prove that no credential reaches the argv or the environment of the HTTP client.
d="${0%/*}"
{
  printf '=== argv\n'; printf '%s\n' "$@"
  printf '=== environ\n'; tr '\0' '\n' </proc/$$/environ; printf '\n'
} >>"$d/curl.log"
exec "$(cat "$d/real_curl")" "$@"
