#!/usr/bin/env bash
# launch_standing13.sh W: start the standing mutation harness of the round-13 commit as a transient systemd user
# service, so it outlives the fixer's session. W is the work directory (repo/, tools/, sqlbin/). A detached worktree
# at the commit is the tree under test; output and the summary file go to $W/standing/out. Prints the unit name, the
# head and the paths.
set -u
W="$(cd "${1:?W: the round-13 work directory (it holds repo/, tools/ and sqlbin/)}" && pwd)" || exit 2
st="$W/standing"
head="$(git -C "$W/repo" rev-parse HEAD)" || exit 2
[ -e "$st" ] && { echo "refusing: $st exists" >&2; exit 2; }
mkdir -p "$st/out" || exit 2
# the harness HOME: a mktemp -d directory, checked non-empty and under $st before use (never an expansion
# that could be empty; §11.4.287(C)(2))
fhome="$(mktemp -d "$st/home.XXXXXX")" || exit 2
case "${fhome:?}" in "$st"/home.??????) ;; *) echo "refusing: fake home $fhome not under $st" >&2; exit 2 ;; esac
[ -d "$fhome" ] || exit 2
git -C "$W/repo" worktree add --detach "$st/tree" "$head" >/dev/null 2>&1 || { echo "worktree add failed" >&2; exit 2; }
[ "$(git -C "$st/tree" rev-parse HEAD)" = "$head" ] || { echo "tree head mismatch" >&2; exit 2; }
[ -z "$(git -C "$st/tree" status --porcelain)" ] || { echo "tree not clean" >&2; exit 2; }
unit="fix227-r13-standing-${head:0:8}"
systemd-run --user --quiet --collect --unit="$unit" -p TasksMax=3000 \
  /usr/bin/env -i PATH="$W/sqlbin:/usr/local/bin:/usr/bin:/bin" HOME="${fhome:?}" LANG=C.UTF-8 USER=zzfixer LOGNAME=zzfixer \
  /usr/bin/nice -n 10 /bin/bash "$W/tools/run_full_harness13.sh" "$st/tree" "$st/out" || { echo "systemd-run failed" >&2; exit 2; }
printf 'unit=%s head=%s tree=%s out=%s/mutations_full_r13.txt summary=%s/summary.txt\n' "$unit" "$head" "$st/tree" "$st/out" "$st/out"
