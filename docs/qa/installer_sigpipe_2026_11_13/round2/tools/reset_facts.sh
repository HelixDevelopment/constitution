#!/usr/bin/env bash
# reset_facts.sh BASHES_DIR — two facts hi_reset_shell_state relies on, measured on every bash copy in BASHES_DIR and
# on the host bash:
#   1. `shopt -u` / `shopt -s` with several names, one of them unknown to this bash: the known names still change,
#      the unknown one is skipped, the status is 1 (so one call per direction is enough, whatever the version).
#   2. `unset POSIXLY_CORRECT` turns posix mode off, whether posix mode came from `set -o posix`, from
#      POSIXLY_CORRECT=1 in the environment or from SHELLOPTS=posix (this makes mutant N22t equivalent).
# Control needles: the same probes without the unknown name (status 0) and without the unset (posix stays on).
# Output: one line per bash and probe. Exit 0 when every line matches the expectation, 1 otherwise.
set -u
bd="${1:?BASHES_DIR}"
bad=0
probe1='shopt -s extglob nullglob; shopt -u extglob no_such_option_xyz nullglob 2>/dev/null; rc=$?
e=$(shopt -q extglob && echo on || echo off); n=$(shopt -q nullglob && echo on || echo off)
shopt -s no_such_option_xyz dotglob 2>/dev/null; rc2=$?; d=$(shopt -q dotglob && echo on || echo off)
shopt -u dotglob extglob; rc3=$?
echo "rc_u=$rc extglob=$e nullglob=$n rc_s=$rc2 dotglob=$d control_rc=$rc3"'
probe2='before=$(shopt -oq posix && echo on || echo off); unset POSIXLY_CORRECT; after=$(shopt -oq posix && echo on || echo off); echo "$before->$after"'
probe2c='before=$(shopt -oq posix && echo on || echo off); after=$(shopt -oq posix && echo on || echo off); echo "$before->$after"'
for d in host "$bd"/*/; do
  if [ "$d" = host ]; then B=/usr/bin/bash; else B="${d%/}/bin/bash"; [ -x "$B" ] || continue; fi
  v="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH "$B" -c 'echo ${BASH_VERSION%%(*}')"
  r1="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH "$B" --norc -c "$probe1" 2>&1)"
  want1="rc_u=1 extglob=off nullglob=off rc_s=1 dotglob=on control_rc=0"
  [ "$r1" = "$want1" ] && s1=ok || { s1=UNEXPECTED; bad=1; }
  printf '%-8s shopt-unknown-name       %-66s %s\n' "$v" "$r1" "$s1"
  for how in set-o-posix env-POSIXLY_CORRECT env-SHELLOPTS; do
    case "$how" in
      set-o-posix) r2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u POSIXLY_CORRECT -u SHELLOPTS "$B" --norc -c "set -o posix; $probe2" 2>&1)"
                   c2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u POSIXLY_CORRECT -u SHELLOPTS "$B" --norc -c "set -o posix; $probe2c" 2>&1)" ;;
      env-POSIXLY_CORRECT) r2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH POSIXLY_CORRECT=1 "$B" --norc -c "$probe2" 2>&1)"
                   c2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH POSIXLY_CORRECT=1 "$B" --norc -c "$probe2c" 2>&1)" ;;
      env-SHELLOPTS) r2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u POSIXLY_CORRECT SHELLOPTS=posix "$B" --norc -c "$probe2" 2>&1)"
                   c2="$(env -u LD_PRELOAD -u LD_LIBRARY_PATH -u POSIXLY_CORRECT SHELLOPTS=posix "$B" --norc -c "$probe2c" 2>&1)" ;;
    esac
    [ "$r2" = "on->off" ] && [ "$c2" = "on->on" ] && s2=ok || { s2=UNEXPECTED; bad=1; }
    printf '%-8s unset-POSIXLY_CORRECT %-22s unset: %-8s control (no unset): %-8s %s\n' "$v" "$how" "$r2" "$c2" "$s2"
  done
done
echo "RESULT: $([ "$bad" = 0 ] && echo PASS || echo FAIL)"
exit "$bad"
