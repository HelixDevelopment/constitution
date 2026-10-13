#!/bin/bash
# sigwin_rig.sh <harness|deps> <plain|inherit|postwait|shim|shimord> <tests-dir>   (R6-F1 / R6-F2 / R7 signal-window rig)
# Sends TERM to the unit under test at a chosen instant of its tool call and reports what survived:
#   plainzsh as plain, but the unit runs under zsh (R7-F1: `jobs -rp` prints whole job lines there);
#            SKIP when zsh is absent. (harness: an `sh` symlink to zsh leads PATH, so zsh runs AS sh.)
#   plain    the shell is parked between the `&` fork of the tool (timeout child) and its own
#            bookkeeping of that child (strace delays the fork's return, clone/clone3 delay_exit,
#            in the unit ONLY, no -f); a watcher polls ps for the `timeout` child and signals its parent.
#   inherit  as plain, and the unit's environment carries tpid=<pgid of an unrelated setsid sleeper>
#            (R6-F1: the unit must not treat an inherited tpid as its own child).
#   postwait the tool already exited but left a background sleeper; the unit is parked right after its
#            blocking wait4 returned, at the rt_sigprocmask that unblocks SIGCHLD: the TERM and the child's
#            exit are then handled together, the job is already DONE (`jobs -r` no longer lists it) and only
#            tpid names the group. The N-th rt_sigprocmask is found by a calibration run (SKIP if it fails).
#   postcanary as postwait, and an UNRELATED `setsid sleep 30` canary is started the moment the tool's own
#            sleeper is seen (R7-F7): the rig must take ONLY its own sleeper (unique argv `sleep 31.<nonce>`),
#            never signal the canary, and report canary=alive.
#   shim     a slow `timeout` shim (2.5 s, no own process group yet) stands in front of the real one.
#   shimord  as shim, but TERM arrives 0.3 s later (the unit is in `wait`) and the THIRD kill(2) of the
#            unit is delayed 3 s: the shim turns into the real timeout (own group + tool) in that gap, so
#            the unit must have killed the PID first and the GROUP second (a swapped order orphans the tool).
# Prints one line:
#   RESULT fired=<0|1> rc=<exit code of the unit> orphan=<0|1: a member of the tool's group survived>
#          sleeper=<alive|dead|na: unrelated sleeper whose pgid the unit inherited as tpid>
#          canary=<alive|dead|na: the unrelated `sleep 30` of postcanary>
#   or SKIP <reason> (strace / setsid unusable). Own children are always reaped.
kind=$1; mode=$2; here=$3
command -v strace >/dev/null 2>&1 || { echo "SKIP strace_unavailable"; exit 0; }
command -v setsid >/dev/null 2>&1 || { echo "SKIP setsid_unavailable"; exit 0; }
strace -o /dev/null -e trace=clone,clone3 -e inject=clone:delay_exit=1 -e inject=clone3:delay_exit=1 true >/dev/null 2>&1 \
  || { echo "SKIP strace_cannot_trace_or_inject (ptrace denied?)"; exit 0; }
W=$(mktemp -d) || exit 2
grp=""; sp=""; dog=""; canpid=""
# gone <pgid|pid>: never signal a value that is not a plain integer > 1 (kill -- -1 is every process: 11.4.263).
gone() { case $1 in ''|*[!0-9]*) return 0 ;; esac; [ "$1" -gt 1 ] || return 0; kill -s KILL -- "-$1" 2>/dev/null; kill -s KILL "$1" 2>/dev/null; }
fin() { [ -z "$grp" ] || gone "$grp"; [ -z "$sp" ] || gone "$sp"; [ -z "$canpid" ] || gone "$canpid"; [ -z "$dog" ] || kill -s KILL "$dog" 2>/dev/null; rm -rf "$W"; }
trap fin EXIT
REALT=$(command -v timeout)
ZSHB=""
if [ "$mode" = plainzsh ]; then
  ZSHB=$(command -v zsh) || { echo "SKIP zsh_unavailable"; exit 0; }
  mode=plain
fi
CAN=""
if [ "$mode" = postcanary ]; then CAN=1; mode=postwait; fi
# The tool's own sleeper has a UNIQUE duration (31.<nonce>): no other process on the host can match it.
SLP="31.${RIG_NONCE:-$$}"
envtp=""
if [ "$mode" = inherit ]; then
  setsid sh -c 'echo $$ >"$1"; exec sleep 55' _ "$W/sp" >/dev/null 2>&1 </dev/null &
  i=0; while [ ! -s "$W/sp" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  sp=$(cat "$W/sp" 2>/dev/null); [ -n "$sp" ] || { echo "SKIP sleeper_never_started"; exit 0; }
  envtp="tpid=$sp"
fi
if [ "$mode" = postwait ]; then TOOLBODY="sleep $SLP &"; else TOOLBODY='sleep 30'; fi
D=500000; [ "$mode" = postwait ] && D=800000; INJ="clone:delay_exit=$D -e inject=clone3:delay_exit=$D"; TR=clone,clone3
if [ "$mode" = postwait ]; then
  # calibration: which rt_sigprocmask (1-based) follows the blocking wait4 of the first tool call
  if [ "$kind" = harness ]; then
    printf '#!/bin/sh\nsleep 0.3\nsleep 30 &\n' >"$W/cal.sh"; chmod +x "$W/cal.sh"
    timeout -k 2 60 strace -o "$W/cal.txt" -e trace=rt_sigprocmask,wait4,kill sh "$here/lib/triple_harness.sh" --tool "$W/cal.sh" --fixtures "$here/fixtures/triple_harness/sound" >/dev/null 2>&1
  else
    mkdir "$W/calbin"; for b in mktemp head rm sh bash sleep sed timeout; do ln -s "$(command -v $b)" "$W/calbin/$b"; done
    printf '#!/bin/sh\nsleep 0.3\nsleep 30 &\n' >"$W/calbin/git"; chmod +x "$W/calbin/git"
    env PATH="$W/calbin" timeout -k 2 60 "$(command -v strace)" -o "$W/cal.txt" -e trace=rt_sigprocmask,wait4,kill /bin/bash "$here/check_deps.sh" >/dev/null 2>&1
  fi
  NSIG=$(awk '/^kill\(-[0-9]+, SIGKILL\)/ && !k {k=NR}
    /^rt_sigprocmask/ {c++; if (!k) cnt[NR]=c}
    /^wait4\(-1, \[.*\], 0, NULL\) = [0-9]+$/ && !k {w=NR; cw=c}
    END { if (k && w) print cw+1 }' "$W/cal.txt" 2>/dev/null)
  case $NSIG in ''|*[!0-9]*) echo "SKIP postwait_calibration_failed (no wait4/kill pattern in the strace of a calibration run)"; exit 0 ;; esac
  INJ="rt_sigprocmask:delay_exit=1000000:when=$NSIG"; TR=rt_sigprocmask
fi
[ "$mode" = shimord ] && { INJ="kill:delay_enter=3000000:when=3"; TR="kill"; }
SHIM=0; { [ "$mode" = shim ] || [ "$mode" = shimord ]; } && SHIM=1
mkdir "$W/bin"
if [ "$kind" = harness ]; then
  printf '#!/bin/sh\n%s\n' "$TOOLBODY" >"$W/slow.sh"; chmod +x "$W/slow.sh"
  key="-k 2 60 $W/slow.sh"; P=$PATH
  if [ -n "$ZSHB" ]; then mkdir "$W/zbin"; ln -s "$ZSHB" "$W/zbin/sh"; P="$W/zbin:$PATH"; fi
  if [ "$SHIM" = 1 ]; then printf '#!/bin/sh\nsleep 2.5\nexec "%s" "$@"\n' "$REALT" >"$W/bin/timeout"; chmod +x "$W/bin/timeout"; P="$W/bin:$PATH"; fi
  # shellcheck disable=SC2086
  env PATH="$P" $envtp FASTCYCLE_TOOL_TIMEOUT=60 strace -o /dev/null -e trace=$TR -e inject=$INJ sh "$here/lib/triple_harness.sh" --tool "$W/slow.sh" --fixtures "$here/fixtures/triple_harness/sound" >/dev/null 2>&1 &
else
  for b in mktemp head rm sh bash sleep sed; do ln -s "$(command -v $b)" "$W/bin/$b"; done
  if [ "$SHIM" = 1 ]; then printf '#!/bin/sh\nsleep 2.5\nexec "%s" "$@"\n' "$REALT" >"$W/bin/timeout"; chmod +x "$W/bin/timeout"; else ln -s "$REALT" "$W/bin/timeout"; fi
  DEPSH=/bin/bash
  # zsh mode: zsh runs AS sh (argv0 `sh`, emulate sh) so the bash-syntax-free unit is parsed by zsh.
  if [ -n "$ZSHB" ]; then rm -f "$W/bin/sh"; ln -s "$ZSHB" "$W/bin/sh"; DEPSH="$W/bin/sh"; fi
  printf '#!/bin/sh\n%s\n' "$TOOLBODY" >"$W/bin/git"; chmod +x "$W/bin/git"
  key="-k 2 60 git --version"
  # shellcheck disable=SC2086
  env PATH="$W/bin" $envtp FC_PROBE_TIMEOUT_S=60 "$(command -v strace)" -o /dev/null -e trace=$TR -e inject=$INJ "$DEPSH" "$here/check_deps.sh" >/dev/null 2>&1 &
fi
sp_h=$!
( sleep 100; kill -s KILL "$sp_h" 2>/dev/null ) >/dev/null 2>&1 & dog=$!
fired=0; i=0
while [ "$fired" -eq 0 ] && [ "$i" -lt 3000 ]; do
  snap=$(ps -eo pid=,ppid=,pgid=,args= 2>/dev/null)
  if [ "$mode" = postwait ]; then
    # tool exited (its `timeout` is gone) while its group's background sleeper lives
    if [ -n "$CAN" ] && [ -z "$canpid" ] && printf '%s\n' "$snap" | awk -v s="$SLP" '$4=="sleep" && $5==s{f=1} END{exit !f}'; then
      setsid sleep 30 >/dev/null 2>&1 </dev/null & canpid=$!
      sleep 0.15; continue
    fi
    g=$(printf '%s\n' "$snap" | awk -v k="$key" -v s="$SLP" 'index($0,k){f=1} $4=="sleep" && $5==s{g=$3} END{if(!f && g!="")print g}')
    if [ -n "$g" ]; then
      tr=$(printf '%s\n' "$snap" | awk -v p="$sp_h" '$2==p{print $1; exit}')
      if [ -n "$tr" ]; then grp=$g; kill -s TERM "$tr" 2>/dev/null; fired=1; break; fi
    fi
  else
    # the unit (tracee) is the child of strace; the tool's `timeout` (or shim) is a child of the unit
    hit=$(printf '%s\n' "$snap" | awk -v p="$sp_h" -v k="$key" '
      { par[$1]=$2; line[$1]=$0 }
      END { for (c in par) if (index(line[c],k) && par[par[c]]==p) { print par[c], c; exit } }')
    if [ -n "$hit" ]; then tr=${hit% *}; grp=${hit#* }; [ "$mode" != shimord ] || sleep 0.3; kill -s TERM "$tr" 2>/dev/null; fired=1; break; fi
  fi
  sleep 0.02; i=$((i + 1))
done
wait "$sp_h" 2>/dev/null; rc=$?
sleep 0.7
orphan=0
if [ -n "$grp" ]; then
  ps -eo pid=,pgid= 2>/dev/null | awk -v g="$grp" '$1==g || $2==g{f=1} END{exit !f}' && orphan=1
fi
slp=na; if [ "$mode" = inherit ]; then if kill -0 "$sp" 2>/dev/null; then slp=alive; else slp=dead; fi; fi
can=na; if [ -n "$CAN" ]; then if [ -n "$canpid" ] && kill -0 "$canpid" 2>/dev/null; then can=alive; else can=dead; fi; fi
echo "RESULT fired=$fired rc=$rc orphan=$orphan sleeper=$slp canary=$can"
