set -u
HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1 || { echo srcfail; exit 1; }
sha=0123456789abcdef0123456789abcdef01234567
n=$2
T="$(for ((j=0;j<n;j++)); do printf 'R 0 refs/remotes/origin/x%s %s 1\n' "$j" "$sha"; done)"
M="R 0 refs/remotes/origin/first $sha 0
$T"
s=$SECONDS; t0=$(date +%s%N)
hi_push_changed "$M" "$M"; echo "rc=$? ms=$(( ($(date +%s%N)-t0)/1000000 ))"
