#!/usr/bin/env bash
# credscan_check_timer.sh - unattended, low-priority ratchet check (the systemd timer's ExecStart).
#
# Runs `credscan.py check` against the counts-only baseline and records a counts-only
# status file. It NEVER creates or refreshes a baseline (accepting the current exposure is a
# deliberate operator act) and never prints a credential value.
#
# Environment (all optional):
#   CREDSCAN_STATE_DIR  state directory (default ~/.local/state/credscan, mode 0700)
#   CREDSCAN_ROOTS      colon-separated roots; default = credscan's default roots
#   CREDSCAN_TIMEOUT    seconds before the scan is killed (default 6600 (first, uncached run reads everything at ~15 MB/s; later runs reread only changed files))
# Exit: 0 clean (or another run in progress), 1 ratchet violated, 2 cannot run (no baseline /
#       missing roots / no HOME / no flock), 3 blind instrument, 4 internal error, 5 partial scan, 124 timeout, >=125 killed.
# status.json is set to state=running before the scan, so a run killed by the OOM killer or SIGKILL
# can never leave a stale "ok" behind: a reader sees "running" (check its `time` for staleness).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${CREDSCAN_STATE_DIR:-${HOME:+$HOME/.local/state/credscan}}"
[ -n "$STATE" ] || { echo "credscan: HOME is unset and CREDSCAN_STATE_DIR not given" >&2; exit 2; }
command -v flock >/dev/null 2>&1 || { echo "credscan: flock not found, cannot guarantee non-overlap" >&2; exit 2; }
mkdir -p -- "$STATE" && chmod 700 -- "$STATE" || { echo "credscan: cannot prepare state dir" >&2; exit 2; }
STATUS="$STATE/status.json"
BASE="$STATE/baseline.json"

exec 9>>"$STATE/lock"
flock -n 9
frc=$?
if [ "$frc" -eq 1 ]; then
  echo "credscan: already running, skipping this tick"
  exit 0
elif [ "$frc" -ne 0 ]; then
  echo "credscan: flock failed (rc=$frc)" >&2
  exit 2
fi

put_status() {   # $1 = state, $2 = exit ; counts-only record, atomic, 0600
  local tmp="$STATUS.tmp"
  rm -f -- "$tmp"
  ( umask 077; printf '{"exit": %s, "state": "%s", "time": %s, "violations": 0}\n' "$2" "$1" "$(date +%s)" >"$tmp" ) \
    && mv -f -- "$tmp" "$STATUS"
}
put_status running -1

args=(check --baseline "$BASE" --status-file "$STATUS" --cache "$STATE/cache.json")
if [ -n "${CREDSCAN_ROOTS:-}" ]; then
  IFS=: read -r -a roots <<<"$CREDSCAN_ROOTS"
  for r in "${roots[@]}"; do args+=(--root "$r"); done
else
  args+=(--default-roots)
fi

cmd=(python3 -I "$HERE/credscan.py" "${args[@]}")
command -v nice >/dev/null && cmd=(nice -n 19 "${cmd[@]}")
command -v ionice >/dev/null && cmd=(ionice -t -c 3 "${cmd[@]}")
timeout "${CREDSCAN_TIMEOUT:-6600}" "${cmd[@]}"
rc=$?
if [ "$rc" -eq 124 ]; then
  echo "credscan: timed out" >&2
  put_status timeout 124
fi
# Any end the engine did not record itself (SIGKILL/OOM 137, import failure, ...) must not leave "running".
if grep -q '"state": "running"' "$STATUS" 2>/dev/null; then
  if [ "$rc" -ge 125 ]; then put_status killed "$rc"; elif [ "$rc" -eq 0 ]; then put_status error 4; else put_status error "$rc"; fi
fi
# python exited 0 but never recorded a result: that is an error, not a clean run.
if [ "$rc" -eq 0 ] && grep -q '"state": "error"' "$STATUS" 2>/dev/null; then rc=4; fi
exit "$rc"
