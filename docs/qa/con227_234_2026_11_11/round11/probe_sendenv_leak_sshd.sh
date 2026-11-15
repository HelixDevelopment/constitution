#!/usr/bin/env bash
# docs/qa/con227_234_2026_11_11/round11/probe_sendenv_leak_sshd.sh: the standing LIVE probe of R10-1 (round-10
# review). Does a variable the caller opted in through RELEASE_ENV_KEEP reach a real sshd when the real
# tag_and_release.sh --dry-run fetches over ssh, for every way the round-10 review found to make ssh send it?
#
# Class (§11.4.289): LIVE. Two throwaway sshd processes of this user run on 127.0.0.1 (own host key, own authorized
# key, a free high port each, LogLevel DEBUG3): server A accepts "LANG LC_* ZZ*", server B has no AcceptEnv line at
# all. Server A logs "Setting env N: NAME=VALUE" for every accepted name; server B logs "Ignoring env request NAME:
# disallowed name" for every request (an RFC 4254 "env" request carries the value, so a request that arrives is a
# value that left the host). The client is the system ssh, reached through git, through the tag script's own fetch.
# Every value is a fabricated ZZFAKE marker; nothing leaves 127.0.0.1.
#
# Cases (the 13 leak configurations of R10-1, its three controls, and C7/C8, which the review refuted):
#   C1 -F ~/x          C2 -F "$HOME"/x      C3 -qF /abs/x        C4w core.sshCommand, linked worktree
#   C4s core.sshCommand, run from a subdirectory                 C5 a quoted Include path with a blank
#   C9 GIT_SSH wrapper C10 include.path holding core.sshCommand C12 ProxyCommand session with -o SendEnv
#   C13 ProxyCommand session with its own -F file               C14 Send"Env"  C15 "SendEnv"  C16 -F '/a dir/x'
#   controls: C4m core.sshCommand in the main checkout, C6 a separate absolute -F, C11 a plain -F with no SendEnv
#   refuted:  C7 ProxyCommand -W with -o SendEnv, C8 ProxyCommand -W with its own -F file
# Every client configuration also says "SendEnv LANG LC_ALL" (the positive needle, §11.4.273): a case counts only
# when the server logged an env line for LANG or LC_ALL in that case's window, which proves the ssh session happened
# and the env requests are visible in the log. A case with a ZZFAKE marker in its window is LEAK; a case with the
# needle and no marker is CLEAN; a case without the needle is BLIND (no verdict). The script also records whether
# the needle value is LC_ALL=C (the rc_net constant) and whether the caller's LANG value arrived.
#
# Usage: bash probe_sendenv_leak_sshd.sh CHECKOUT OUT
#   (debugging only: PROBE_CASES="C1 C4w" runs only these cases; PROBE_KEEP=1 keeps the scratch directory and prints it)
#   CHECKOUT  a checkout whose WORKING-TREE tracked files are probed (copied, committed into a throwaway repository)
#   OUT       the file the result is written to
# Exit 0: every case CLEAN on both servers. Exit 1: at least one LEAK. Exit 2: no LEAK, but at least one BLIND case.
# RED reference: the round-10 head 3fe216bd gives LEAK on the 13 leak cases. GREEN: the round-11 tree gives CLEAN on
# all 18 cases on both servers. The tag script stops at its own CHANGELOG precondition after the fetch (the probe tag
# is not in CHANGELOG.md); the fetch is the step measured here.
# Safety: only the two sshd processes this script started are signalled (pid > 1 and a command line that names this
# run's own config); the scratch directory is removed with safe_rm_rf (§11.4.287).
set -u
SRC="$(cd "${1:?CHECKOUT}" && pwd)"; OUT="${2:?OUT}"
# the directory name must not hold the word "sendenv": the round-10 reader (3fe216bd) fails closed on that word
# anywhere in ./.git/config, and the throwaway remote's URL holds this path (measured: a run under a directory named
# sendenv11.* refused every RELEASE_ENV_KEEP name and the RED baseline showed 4 leaks instead of 13)
T="$(mktemp -d "${TMPDIR:-/tmp}/probe11.XXXXXX")"; : "${T:?}"
PIDA=""; PIDB=""
stop_one() { # stop_one PID CONFIG: signal only our own sshd
  local p="$1" c="$2"
  [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null || return 0
  if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -qF -- "$c"; then kill -TERM "$p" 2>/dev/null; wait "$p" 2>/dev/null; fi
}
cleanup() { stop_one "$PIDA" "$T/A/sshd_config"; stop_one "$PIDB" "$T/B/sshd_config"; PIDA=""; PIDB=""
  [ -n "${PROBE_KEEP:-}" ] && return 0; [ -d "$T" ] && . "$SRC/scripts/lib/safe_rm.sh" 2>/dev/null && SAFE_RM_ALLOWED_ROOTS="${T%/*}" safe_rm_rf "${T:?}" 2>/dev/null; }
trap cleanup EXIT
blind() { printf 'BLIND: %s\n' "$1" | tee "$OUT"; exit 2; }
ssh-keygen -q -t ed25519 -N '' -f "$T/hostkey" >/dev/null && ssh-keygen -q -t ed25519 -N '' -f "$T/clientkey" >/dev/null || blind ssh-keygen
cp "$T/clientkey.pub" "$T/authorized_keys"
freeport() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# ---- the probed tree: the tracked files of CHECKOUT as they are in its working tree, in a throwaway repository ----
mkdir -p "$T/w" && (cd "$SRC" && git ls-files -z | tar --null -T - -cf -) | tar -C "$T/w" -xf - || blind "copy of the working tree"
G=(git -c user.email=zz-probe@example.invalid -c user.name=zz-probe -c init.defaultBranch=main -c commit.gpgsign=false)
"${G[@]}" -C "$T/w" init -q && "${G[@]}" -C "$T/w" add -A && "${G[@]}" -C "$T/w" commit -q -m probe || blind "commit of the copy"
git clone -q --bare "$T/w" "$T/w.remote.git" && git -C "$T/w" remote add r1 "zzprobe11:$T/w.remote.git" || blind "bare remote"
git -C "$T/w" worktree add -q --detach "$T/wt" HEAD || blind worktree
mkdir -p "$T/w/zzsub"
PROBED="$(git -C "$SRC" rev-parse HEAD)$(git -C "$SRC" diff --quiet HEAD -- scripts tests 2>/dev/null || printf '+worktree')"

# ---- one sshd and one set of client configurations per server ----
setup_server() { # setup_server NAME ACCEPTENV-LINE
  local d="$T/$1" port; port="$(freeport)"; mkdir -p "$d/home" "$d/a dir"
  { printf 'Port %s\nListenAddress 127.0.0.1\nHostKey %s\nPidFile %s\nAuthorizedKeysFile %s\n' "$port" "$T/hostkey" "$d/sshd.pid" "$T/authorized_keys"
    printf 'StrictModes no\nUsePAM no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nLogLevel DEBUG3\n'
    [ -n "$2" ] && printf '%s\n' "$2"; } >"$d/sshd_config"
  hostcfg() { # hostcfg FILE HOST [EXTRA-LINE...]
    local f="$1" h="$2"; shift 2
    { printf 'Host %s\n  HostName 127.0.0.1\n  Port %s\n  User %s\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$h" "$port" "$(id -un)" "$T/clientkey"
      printf '  UserKnownHostsFile %s\n  StrictHostKeyChecking no\n  BatchMode yes\n  SendEnv LANG LC_ALL\n' "$d/known_hosts"
      for l in "$@"; do printf '  %s\n' "$l"; done; } >"$f"; }
  hostcfg "$d/home/c1.cfg" zzprobe11 'SendEnv ZZLEAKA'
  hostcfg "$d/home/c2.cfg" zzprobe11 'SendEnv ZZLEAKB'
  hostcfg "$d/c3.cfg" zzprobe11 'SendEnv ZZLEAKC'
  hostcfg "$d/c4.cfg" zzprobe11
  hostcfg "$d/c5.cfg" zzprobe11; printf 'SendEnv ZZLEAKE\n' >"$d/a dir/inc5.conf"; printf 'Include "%s"\n' "$d/a dir/inc5.conf" >>"$d/c5.cfg"
  hostcfg "$d/c6.cfg" zzprobe11 'SendEnv ZZLEAKF'
  hostcfg "$d/innerA.cfg" zzinner11; hostcfg "$d/innerH.cfg" zzinner11 'SendEnv ZZLEAKH'
  hostcfg "$d/c7.cfg" zzprobe11 "ProxyCommand ssh -F $d/innerA.cfg -o SendEnv=ZZLEAKG -W %h:%p zzinner11"
  hostcfg "$d/c8.cfg" zzprobe11 "ProxyCommand ssh -F $d/innerH.cfg -W %h:%p zzinner11"
  hostcfg "$d/c9.cfg" zzprobe11; printf '#!/bin/sh\nexec ssh -F %s -o SendEnv=ZZLEAKI "$@"\n' "$d/c9.cfg" >"$d/wrap9.sh"; chmod +x "$d/wrap9.sh"
  hostcfg "$d/c10.cfg" zzprobe11; printf '[core]\n\tsshCommand = ssh -F %s -o SendEnv=ZZLEAKJ\n' "$d/c10.cfg" >"$d/inc10.gitconfig"
  hostcfg "$d/c11.cfg" zzprobe11
  hostcfg "$d/c12.cfg" zzprobe11 "ProxyCommand ssh -F $d/innerA.cfg -o SendEnv=ZZLEAKK zzinner11 nc %h %p"
  hostcfg "$d/c13.cfg" zzprobe11 "ProxyCommand ssh -F $d/innerH.cfg zzinner11 nc %h %p"
  hostcfg "$d/c14.cfg" zzprobe11 'Send"Env" ZZLEAKN'
  hostcfg "$d/c15.cfg" zzprobe11 '"SendEnv" ZZLEAKO'
  hostcfg "$d/a dir/c16.cfg" zzprobe11 'SendEnv ZZLEAKP'
  /usr/sbin/sshd -D -e -f "$d/sshd_config" 2>"$d/sshd.log" &
  printf '%s' "$!" >"$d/pid"
  for _ in $(seq 1 50); do grep -q 'Server listening' "$d/sshd.log" 2>/dev/null && break; sleep 0.1; done
  grep -q 'Server listening' "$d/sshd.log" || blind "sshd $1: $(tail -n 3 "$d/sshd.log")"
}
setup_server A 'AcceptEnv LANG LC_* ZZ*'; PIDA="$(cat "$T/A/pid")"
setup_server B ''; PIDB="$(cat "$T/B/pid")"

CANARIES="ZZLEAKA ZZLEAKB ZZLEAKC ZZLEAKD ZZLEAKE ZZLEAKF ZZLEAKG ZZLEAKH ZZLEAKI ZZLEAKJ ZZLEAKK ZZLEAKN ZZLEAKO ZZLEAKP"
run() { # run SERVER LABEL DIR [VAR=VALUE...]: the real tag script, dry-run, fetching over ssh; verdict of its window
  local s="$1" lab="$2" dir="$3" d="$T/$1" n0 n1 win v envs
  shift 3
  case " ${PROBE_CASES:-$lab} " in *" $lab "*) ;; *) return 0 ;; esac   # PROBE_CASES="C1 C4w": run only these (debugging)
  n0="$(wc -l <"$d/sshd.log")"
  envs=(PATH="$PATH" HOME="$d/home" LANG=C.UTF-8 KEEPME=/srv/zzkeep RELEASE_ENV_KEEP="KEEPME $CANARIES")
  for c in $CANARIES; do envs+=("$c=ZZFAKE-${c#ZZLEAK}-leak"); done
  ( cd "$dir" && env -i "${envs[@]}" "$@" timeout 120 bash "$T/w/scripts/release/tag_and_release.sh" --tag zzv11probe \
      --sha "$(git -C "$T/w" rev-parse HEAD)" --remotes r1 --no-badge-check --dry-run ) >"$d/$lab.out" 2>&1
  echo "rc=$?" >>"$d/$lab.out"; sleep 0.5
  n1="$(wc -l <"$d/sshd.log")"
  win="$(sed -n "$((n0 + 1)),${n1}p" "$d/sshd.log" | tr -d '\r' | grep -E 'Setting env|Ignoring env request|Accepted publickey')"
  if printf '%s\n' "$win" | grep -q 'ZZFAKE\|ZZLEAK'; then v=LEAK
  elif printf '%s\n' "$win" | grep -qE '(Setting env [0-9]+: |Ignoring env request )(LANG|LC_ALL)'; then v=CLEAN
  else v=BLIND; fi
  printf 'CASE %s %-4s %-5s lc_all_c=%s caller_lang=%s script=%s\n' "$s" "$lab" "$v" \
    "$(printf '%s\n' "$win" | grep -qE 'Setting env [0-9]+: LC_ALL=C$' && echo yes || { [ "$s" = B ] && echo n/a || echo no; })" \
    "$(printf '%s\n' "$win" | grep -qE 'LANG=C\.UTF-8' && echo arrived || echo absent)" \
    "$(grep -E '^rc=' "$d/$lab.out")"
  printf '%s\n' "$win" | sed 's/^/    /'
  printf '%s\n' "$v" >>"$T/verdicts"
}
cases() { # cases SERVER
  local s="$1" d="$T/$1"
  run "$s" C1  "$T/w" 'GIT_SSH_COMMAND=ssh -F ~/c1.cfg'
  run "$s" C2  "$T/w" 'GIT_SSH_COMMAND=ssh -F "$HOME"/c2.cfg'
  run "$s" C3  "$T/w" "GIT_SSH_COMMAND=ssh -qF $d/c3.cfg"
  run "$s" C5  "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c5.cfg"
  run "$s" C6  "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c6.cfg"
  run "$s" C7  "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c7.cfg"
  run "$s" C8  "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c8.cfg"
  run "$s" C9  "$T/w" "GIT_SSH=$d/wrap9.sh"
  run "$s" C11 "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c11.cfg"
  run "$s" C12 "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c12.cfg"
  run "$s" C13 "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c13.cfg"
  run "$s" C14 "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c14.cfg"
  run "$s" C15 "$T/w" "GIT_SSH_COMMAND=ssh -F $d/c15.cfg"
  run "$s" C16 "$T/w" "GIT_SSH_COMMAND=ssh -F '$d/a dir/c16.cfg'"
  git -C "$T/w" config core.sshCommand "ssh -F $d/c4.cfg -o SendEnv=ZZLEAKD"
  run "$s" C4m "$T/w"
  run "$s" C4w "$T/wt"
  run "$s" C4s "$T/w/zzsub"
  git -C "$T/w" config --unset core.sshCommand
  git -C "$T/w" config include.path "$d/inc10.gitconfig"
  run "$s" C10 "$T/w"
  git -C "$T/w" config --unset include.path
}
{
  echo "PROBE11 probed=$PROBED $(ssh -V 2>&1) $(/usr/sbin/sshd -V 2>&1 | head -n 1)"
  echo "server A: $(grep -E '^(Port|AcceptEnv)' "$T/A/sshd_config" | tr '\n' ' ')"
  echo "server B: $(grep -E '^(Port|AcceptEnv)' "$T/B/sshd_config" | tr '\n' ' ')(no AcceptEnv)"
  cases A
  cases B
  printf 'SUMMARY cases=%s clean=%s leak=%s blind=%s\n' "$(wc -l <"$T/verdicts")" "$(grep -cx CLEAN "$T/verdicts")" \
    "$(grep -cx LEAK "$T/verdicts")" "$(grep -cx BLIND "$T/verdicts")"
} >"$OUT" 2>&1
cleanup
[ -n "${PROBE_KEEP:-}" ] && echo "kept: $T"
cat "$OUT"
if grep -q '^SUMMARY .* leak=0 ' "$OUT"; then grep -q '^SUMMARY .* blind=0$' "$OUT" && exit 0; exit 2; fi
exit 1
