# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: FT_* results are read by the test files
# tests/forge/lib.sh -- shared helpers of the forge tool tests (sourced by tests/forge/test_*.sh; not a test).
#
# CLASS (section 11.4.289(C)(2)): gate-logic / unit test support. The fixture server
# (tests/forge/fixtures/forge_fixture_server.py) imitates forge APIs on 127.0.0.1; these tests prove
# how scripts/forge/forge.sh decides on given answers, never that a real forge works.
#
# Provides: ft_init (sandbox + counters), ft_server SCENARIO_JSON (starts the fixture, sets FT_PORT),
# ft_hosts LINE... (writes a hosts file whose api bases point at the fixture), ft_run ARGS... (runs
# forge.sh, sets FT_OUT FT_ERR FT_RC), ft_curl_wrap (puts a recording curl wrapper first on PATH),
# assertions ft_ok / ft_no / ft_eq / ft_has / ft_lacks, and ft_done (prints the summary, exit status).
# FORGE_UNDER_TEST overrides the script path (the mutation harness uses it).

FT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORGE="${FORGE_UNDER_TEST:-$FT_ROOT/scripts/forge/forge.sh}"
FT_PASS=0 FT_FAIL=0 FT_SBX="" FT_SRV_PID=""

ft_init() {
  FT_SBX="$(mktemp -d "${TMPDIR:-/tmp}/forge_test.XXXXXX")" || { echo "cannot create sandbox"; exit 3; }
  : "${FT_SBX:?}"
  trap ft_cleanup EXIT
}

ft_cleanup() {
  ft_server_stop
  # guarded delete: only the sandbox this test created (a mktemp child of TMPDIR with our prefix)
  case "${FT_SBX:-}" in
    */forge_test.??????) rm -rf -- "${FT_SBX:?}" ;;
  esac
}

ft_server_stop() {
  if [ -n "${FT_SRV_PID:-}" ]; then
    # our own child only: the pid we started, checked to still be our python fixture
    if kill -0 "$FT_SRV_PID" 2>/dev/null && grep -q forge_fixture_server "/proc/$FT_SRV_PID/cmdline" 2>/dev/null; then
      kill "$FT_SRV_PID" 2>/dev/null
      wait "$FT_SRV_PID" 2>/dev/null
    fi
    FT_SRV_PID=""
  fi
}

# ft_server SCENARIO_JSON_TEXT: (re)start the fixture with this scenario; sets FT_PORT; clears the request log
ft_server() {
  ft_server_stop
  printf '%s' "$1" >"$FT_SBX/scenario.json"
  rm -f -- "$FT_SBX/port" "$FT_SBX/requests.log"; : >"$FT_SBX/requests.log"
  python3 -I "$FT_ROOT/tests/forge/fixtures/forge_fixture_server.py" "$FT_SBX/scenario.json" "$FT_SBX/port" "$FT_SBX/requests.log" &
  FT_SRV_PID=$!
  local i=0
  while [ ! -s "$FT_SBX/port" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  FT_PORT="$(cat "$FT_SBX/port" 2>/dev/null)"
  [ -n "$FT_PORT" ] || { echo "fixture server did not start"; exit 3; }
}

# ft_hosts "host<TAB>provider<TAB>api_base<TAB>token_vars<TAB>note" ...: @PORT@ is replaced by FT_PORT
ft_hosts() {
  local l
  : >"$FT_SBX/hosts.tsv"
  for l in "$@"; do printf '%s\n' "${l//@PORT@/${FT_PORT:-0}}" >>"$FT_SBX/hosts.tsv"; done
}

# ft_run ARGS...: run forge.sh with the sandbox hosts file and loopback http allowed; the caller's extra
# environment is given with `env` words in FT_ENV (an array) -- e.g. FT_ENV=(TEST_TOKEN=abc...)
# FT_NO_ENVFILE=1 leaves FORGE_ENV_FILE unset (the default .env rule is then in force); FT_CWD runs forge.sh
# from that directory (default: the current one)
ft_run() {
  local envw=() efw=()
  [ "${#FT_ENV[@]}" -gt 0 ] 2>/dev/null && envw=("${FT_ENV[@]}")
  [ "${FT_NO_ENVFILE:-0}" = 1 ] || efw=(FORGE_ENV_FILE="${FT_DOTENV:-$FT_SBX/no.env}")
  ( cd "${FT_CWD:-.}" && exec env -i PATH="${FT_PATH:-$PATH}" HOME="${FT_HOME:-$FT_SBX/home}" TMPDIR="$FT_SBX" \
    FORGE_HOSTS_FILE="${FT_HOSTS_FILE:-$FT_SBX/hosts.tsv}" FORGE_TEST_ALLOW_HTTP_LOOPBACK=1 \
    FORGE_KEYS_FILE="${FT_KEYS:-$FT_SBX/no_keys.sh}" "${efw[@]}" \
    "${envw[@]}" bash "$FORGE" "$@" ) >"$FT_SBX/out" 2>"$FT_SBX/err" </dev/null
  FT_RC=$?
  FT_OUT="$(cat "$FT_SBX/out")"; FT_ERR="$(cat "$FT_SBX/err")"
}

# ft_curl_wrap: a curl wrapper first on PATH that records its argv and environment, then runs the real curl
ft_curl_wrap() {
  mkdir -p "$FT_SBX/bin"
  command -v curl >"$FT_SBX/bin/real_curl"
  cp -- "$FT_ROOT/tests/forge/fixtures/curl_recorder.sh" "$FT_SBX/bin/curl"
  chmod 755 "$FT_SBX/bin/curl"
  : >"$FT_SBX/bin/curl.log"
  FT_PATH="$FT_SBX/bin:$PATH"
}

ft_reqs() { cat "$FT_SBX/requests.log"; }
ft_tmpdirs() { find "$FT_SBX" -maxdepth 1 -name 'forge.??????' | wc -l; }   # forge.sh temp dirs left behind
ft_skip() { echo "SKIP $1 (reason: $2)"; }
ft_req_count() { grep -c "\"method\": \"$1\"" "$FT_SBX/requests.log"; }

ft_ok()   { if [ "$2" = "$3" ]; then FT_PASS=$((FT_PASS + 1)); echo "PASS $1"; else FT_FAIL=$((FT_FAIL + 1)); echo "FAIL $1 (expected [$3], got [$2])"; printf '  out: %s\n  err: %s\n' "$FT_OUT" "$FT_ERR" | head -20; fi; }
ft_has()  { if printf '%s' "$2" | grep -qF -- "$3"; then FT_PASS=$((FT_PASS + 1)); echo "PASS $1"; else FT_FAIL=$((FT_FAIL + 1)); echo "FAIL $1 (missing [$3])"; printf '  out: %s\n  err: %s\n' "$FT_OUT" "$FT_ERR" | head -20; fi; }
ft_lacks(){ if printf '%s' "$2" | grep -qF -- "$3"; then FT_FAIL=$((FT_FAIL + 1)); echo "FAIL $1 (must not contain [$3])"; else FT_PASS=$((FT_PASS + 1)); echo "PASS $1"; fi; }

ft_done() {
  echo "SUMMARY: $FT_PASS passed, $FT_FAIL failed"
  [ "$FT_FAIL" -eq 0 ] && [ "$FT_PASS" -gt 0 ]
}
