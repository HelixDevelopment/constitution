#!/usr/bin/env bash
# notemp_run.sh W C -> the reviewer's repro_tmp.sh and control_same.sh on r1 / head / alt, host bash and 5.2.37,
# with temp files made unwritable by `ulimit -f 0` (XFSZ ignored) and BASH_COMPAT=50 (here-strings via temp files).
# stdout goes to a PIPE (RLIMIT_FSIZE limits regular files only), so the results are not lost.
set -u
W="$1"; C="$2"
for b in host 5.2.37; do
  if [ "$b" = host ]; then B=bash; else B="$W/bashes/$b/bin/bash"; fi
  for v in r1 head alt; do
    I="$W/altx/install_constitution.$v.sh"
    for mode in temp notemp; do
      echo "== bash=$b installer=$v ($(sha256sum "$I" | cut -c1-16)) mode=$mode"
      if [ "$mode" = notemp ]; then
        env -u LD_PRELOAD -u LD_LIBRARY_PATH BASH_COMPAT=50 bash -c 'trap "" XFSZ; ulimit -f 0; exec "$1" "$2" "$3"; ' _ "$B" "$C/repro_tmp.sh" "$I"
        env -u LD_PRELOAD -u LD_LIBRARY_PATH BASH_COMPAT=50 bash -c 'trap "" XFSZ; ulimit -f 0; exec "$1" "$2" "$3"; ' _ "$B" "$C/control_same.sh" "$I"
      else
        env -u LD_PRELOAD -u LD_LIBRARY_PATH BASH_COMPAT=50 "$B" "$C/repro_tmp.sh" "$I"
        env -u LD_PRELOAD -u LD_LIBRARY_PATH BASH_COMPAT=50 "$B" "$C/control_same.sh" "$I"
      fi
    done
  done
done
echo "notemp_run: done"
