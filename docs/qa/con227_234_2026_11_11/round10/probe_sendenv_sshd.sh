#!/usr/bin/env bash
# docs/qa/con227_234_2026_11_11/round10/probe_sendenv_sshd.sh — LIVE probe of R9-1 (round-9 review): which caller
# variables the real ssh client sends to a real sshd when the real tag_and_release.sh --dry-run fetches over ssh.
#
# Class (§11.4.289): LIVE. A throwaway sshd of this user (own host key, own authorized key, 127.0.0.1, a free high
# port, AcceptEnv LANG LC_* COLORTERM NO_COLOR ZZ*, LogLevel DEBUG3) logs every "Setting env" line it receives. The
# client is the system ssh with a -F config that holds the default SendEnv line (LANG LC_* COLORTERM NO_COLOR) plus
# SendEnv ZZSENDX10 (a pattern only the run-time reader can know). Every value is a fabricated ZZFAKE marker.
#
# Usage: bash probe_sendenv_sshd.sh REPO OLDREV OUT
#   REPO   the checkout whose working-tree release scripts are probed (round 10)
#   OLDREV a commit of REPO whose release scripts are the RED baseline (round 9: 9d2171e4)
#   OUT    a file the result is written to (the sshd "Setting env" lines per case, and the verdicts)
# Exit 0 when the round-10 scripts send no ZZFAKE marker and the round-9 scripts do (the probe can see), else 1.
# The tag script then stops at its own CHANGELOG precondition (the probe tag is not in CHANGELOG.md); that is after the
# ssh fetch, which is the step measured here (one ssh session per case, the sshd log shows it).
set -u
REPO="$(cd "${1:?REPO}" && pwd)"; OLD="${2:?OLDREV}"; OUT="${3:?OUT}"
T="$(mktemp -d "${TMPDIR:-/tmp}/sendenv10.XXXXXX")"; : "${T:?}"
SSHD_PID=""
stop_sshd() { # signal only our own sshd: its pid > 1 and its command line names our own config
  [ -n "$SSHD_PID" ] && [ "$SSHD_PID" -gt 1 ] 2>/dev/null || return 0
  if tr '\0' ' ' <"/proc/$SSHD_PID/cmdline" 2>/dev/null | grep -qF -- "$T/sshd_config"; then kill -TERM "$SSHD_PID" 2>/dev/null; wait "$SSHD_PID" 2>/dev/null; fi
  SSHD_PID=""
}
cleanup() { stop_sshd; [ -d "$T" ] && . "$REPO/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "${T:?}" 2>/dev/null; }
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$T/hostkey" >/dev/null && ssh-keygen -q -t ed25519 -N '' -f "$T/clientkey" >/dev/null || { echo "BLIND: ssh-keygen" | tee "$OUT"; exit 1; }
cp "$T/clientkey.pub" "$T/authorized_keys"
PORT="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
cat >"$T/sshd_config" <<EOF
Port $PORT
ListenAddress 127.0.0.1
HostKey $T/hostkey
PidFile $T/sshd.pid
AuthorizedKeysFile $T/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
AcceptEnv LANG LC_* COLORTERM NO_COLOR ZZ*
LogLevel DEBUG3
EOF
cat >"$T/ssh_config" <<EOF
Host zzprobe10
  HostName 127.0.0.1
  Port $PORT
  User $(id -un)
  IdentityFile $T/clientkey
  IdentitiesOnly yes
  UserKnownHostsFile $T/known_hosts
  StrictHostKeyChecking no
  BatchMode yes
  SendEnv LANG LC_* COLORTERM NO_COLOR
  SendEnv ZZSENDX10
EOF
/usr/sbin/sshd -D -e -f "$T/sshd_config" 2>"$T/sshd.log" & SSHD_PID=$!
for _ in $(seq 1 50); do grep -q 'Server listening' "$T/sshd.log" 2>/dev/null && break; sleep 0.1; done
grep -q 'Server listening' "$T/sshd.log" || { echo "BLIND: sshd did not start: $(tail -n 3 "$T/sshd.log")" | tee "$OUT"; exit 1; }
# two clones: round 10 (the working-tree scripts committed into the clone) and round 9 (OLDREV)
mk() { # mk DIR REV|worktree
  git clone -q --no-local "$REPO" "$1" || return 1
  if [ "$2" = worktree ]; then
    cp "$REPO/scripts/release/"*.sh "$1/scripts/release/"; cp "$REPO/scripts/release_publish_gitea.sh" "$1/scripts/"
  else git -C "$1" checkout -q "$2" -- scripts/release scripts/release_publish_gitea.sh || return 1; fi
  git -C "$1" -c user.name=zz -c user.email=zz@zz.invalid commit -qam probe --allow-empty || return 1
  git -C "$1" checkout -q -B main || return 1   # the tag script fetches main from the remote
  git clone -q --bare "$1" "$1.remote.git" && git -C "$1" remote add r1 "zzprobe10:$1.remote.git"
}
mk "$T/w10" worktree && mk "$T/w9" "$OLD" || { echo "BLIND: clone" | tee "$OUT"; exit 1; }
HEX=0123456789abcdef0123456789abcdef01234567
run() { # run DIR LABEL: the real tag script, dry-run, over ssh; the sshd lines the run produced are printed
  local d="$1" n0 n1
  n0="$(wc -l <"$T/sshd.log")"
  ( cd "$d" && env -i PATH="$PATH" HOME="$T/home" GIT_SSH_COMMAND="ssh -F $T/ssh_config" \
      LANG=C.UTF-8 LC_TIME="$HEX" LANGUAGE="user:ZZFAKEPWL10@host" \
      LC_ZZ=user:ZZFAKEPW10@host LC_X="ZZFAKEHX10$HEX" LANGX=ZZFAKELX10 COLORTERM=ZZFAKECT10 NO_COLOR=ZZFAKENC10 ZZSENDX10=ZZFAKESX10 KEEPME=ZZFAKEKM10 \
      RELEASE_ENV_KEEP="LC_ZZ LC_X LANGX COLORTERM NO_COLOR ZZSENDX10 KEEPME" \
      timeout 120 bash scripts/release/tag_and_release.sh --tag zzv10 --sha "$(git rev-parse HEAD)" --remotes r1 --no-badge-check --dry-run ) >"$T/$2.out" 2>&1
  echo "rc=$?" >>"$T/$2.out"
  sleep 0.5
  n1="$(wc -l <"$T/sshd.log")"
  sed -n "$((n0 + 1)),${n1}p" "$T/sshd.log" | grep -E 'Setting env|Connection from|Accepted publickey' | sed 's/^/  /'
}
mkdir -p "$T/home"
{
  echo "PROBE sendenv sshd port=$PORT sshd=$(/usr/sbin/sshd -V 2>&1 | head -n 1) ssh=$(ssh -V 2>&1)"
  echo "CASE round10 (working tree of $REPO):"; L10="$(run "$T/w10" r10)"; printf '%s\n' "$L10"; echo "  script: $(tail -n 3 "$T/r10.out" | tr '\n' ' ')"
  echo "CASE round9 ($OLD):"; L9="$(run "$T/w9" r9)"; printf '%s\n' "$L9"; echo "  script: $(tail -n 3 "$T/r9.out" | tr '\n' ' ')"
  v=0
  case "$L10" in *"Setting env"*LANG=C.UTF-8*) echo "PASS control needle: sshd logs the env it receives (LANG=C.UTF-8, round 10)" ;; *) echo "FAIL control needle: no LANG line in round 10 (blind)"; v=1 ;; esac
  case "$L10" in *ZZFAKE*|*"$HEX"*) echo "FAIL round 10 sends a ZZFAKE marker or the hex token"; v=1 ;; *) echo "PASS round 10 sends no ZZFAKE marker and no hex token (LC_ZZ LC_X LANGX COLORTERM NO_COLOR ZZSENDX10 refused by name, LC_TIME dropped by the locale grammar; LANGUAGE is no SendEnv name, so ssh sends it in neither round)" ;; esac
  case "$L9" in *ZZFAKEPW10*) echo "PASS round 9 sends LC_ZZ=user:ZZFAKEPW10@host (the RED the probe must see)" ;; *) echo "FAIL round 9 sends no LC_ZZ marker: the probe cannot see the defect"; v=1 ;; esac
  case "$L9" in *"LC_TIME=$HEX"*) echo "PASS round 9 sends LC_TIME=<40-hex token> (F8: a bare token left the host)" ;; *) echo "FAIL round 9 does not send the LC_TIME token"; v=1 ;; esac
  case "$L9" in *ZZFAKESX10*) echo "PASS round 9 sends ZZSENDX10 (a pattern only the run-time reader knows)" ;; *) echo "FAIL round 9 does not send ZZSENDX10"; v=1 ;; esac
  echo "VERDICT=$v"
} >"$OUT"
stop_sshd
cat "$OUT"
grep -q '^VERDICT=0$' "$OUT"
