#!/usr/bin/env bash
# caller_shell_compare.sh INSTALLER_BASE INSTALLER_NEW — class (b) and (a) side by side, base and new installer.
# For each inherited setting, and for "no writable temporary file" (ulimit -f 0, BASH_COMPAT=50), runs the read-only
# flags --version, --help and --print-snippets in an empty directory and prints, per flag, whether the output and exit
# status equal those of a clean run of the SAME installer, plus the first line of any difference.
# Read-only: these three flags write nothing and use no network.
set -u
base="${1:?}"; new="${2:?}"
sb="$(mktemp -d "${TMPDIR:-/tmp}/csc.XXXXXX")" || exit 2
settings=(POSIXLY_CORRECT=1 SHELLOPTS=posix SHELLOPTS=noglob:nounset SHELLOPTS=errexit
          BASHOPTS=nocasematch:extglob:failglob:nullglob BASH_COMPAT=44 CDPATH=/nonexistent 'GLOBIGNORE=*' TMOUT=1)
run() { # installer flag [setting|notemp] -> output then "rc=N"
  local inst="$1" flag="$2" how="${3:-}"
  if [ "$how" = notemp ]; then
    (cd "$sb" && trap '' XFSZ && ulimit -f 0 && env BASH_COMPAT=50 bash "$inst" "$flag" 2>&1; echo "rc=$?")
  elif [ -n "$how" ]; then
    (cd "$sb" && env "$how" bash "$inst" "$flag" 2>&1; echo "rc=$?")
  else
    (cd "$sb" && bash "$inst" "$flag" 2>&1; echo "rc=$?")
  fi
}
echo "bash: $BASH_VERSION"
for side in base new; do
  if [ "$side" = base ]; then inst="$base"; else inst="$new"; fi
  echo "== $side: $inst ($(sha256sum "$inst" | cut -c1-16))"
  for flag in --version --help --print-snippets; do
    clean="$(run "$inst" "$flag")"
    echo "  clean $flag: $(printf '%s' "$clean" | wc -c | tr -d ' ') bytes, $(printf '%s\n' "$clean" | tail -n 1)"
    for s in "${settings[@]}" notemp; do
      got="$(run "$inst" "$flag" "$s")"
      if [ "$got" = "$clean" ]; then
        printf '    %-46s %-16s same\n' "$s" "$flag"
      else
        first="$(diff <(printf '%s\n' "$clean") <(printf '%s\n' "$got") | grep -m 1 '^[<>]')"
        printf '    %-46s %-16s DIFFERS %s | first: %s\n' "$s" "$flag" "$(printf '%s\n' "$got" | tail -n 1)" "${first:0:150}"
      fi
    done
  done
done
rm -rf -- "${sb:?}"
