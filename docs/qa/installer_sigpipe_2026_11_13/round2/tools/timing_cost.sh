# timing_cost.sh INSTALLER N F — wall time of hi_push_changed "$M" "$M" (b == a) with N R lines per mark whose last
# field (reflog fetch count) is F. F=0 makes every R line take the membership test (the costly path); F=1 skips it.
# Informative only: one run, the wall clock of a loaded host; rc=1 means "no push" (correct for b == a).
set -u
HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1 || { echo srcfail; exit 1; }
sha=0123456789abcdef0123456789abcdef01234567
n=$2; f=$3
T="$(for ((j=0;j<n;j++)); do printf 'R 0 refs/remotes/origin/x%s %s %s\n' "$j" "$sha" "$f"; done)"
M="R 0 refs/remotes/origin/first $sha $f
$T"
t0=$(date +%s%N)
hi_push_changed "$M" "$M"; echo "rc=$? ms=$(( ($(date +%s%N)-t0)/1000000 )) bytes_per_mark=${#M}"
