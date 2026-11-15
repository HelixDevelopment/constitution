#!/usr/bin/env bash
# red_harness.sh INSTALLER N  -> counts of misreads by hi_push_changed (b == a, no push) plus a control needle
set -u -o pipefail
INST="${1:?installer path}"; N="${2:?runs}"
HELIX_INSTALLER_LIB_MODE=1 . "$INST" || { echo "source failed"; exit 9; }
set -u -o pipefail
hi_warn() { :; }; hi_err() { printf 'ERR %s\n' "$*"; }
sha=0123456789abcdef0123456789abcdef01234567
# (1) control needle: a pipe whose reader exits first MUST show 141 in PIPESTATUS (proves the harness sees SIGPIPE)
c=0; for k in 1 2 3; do yes | grep -q y; [ "${PIPESTATUS[0]}" = 141 ] && c=$((c+1)); done
echo "control_needle_yes_grep_141=$c/3"
# (2) raw pipeline race, small input (3 lines, match on line 1)
x="$(for j in 1 2 3; do printf 'R 0 refs/remotes/origin/b%s %s 0\n' "$j" "$sha"; done)"
p=0; h=0
for ((k=0;k<N;k++)); do printf '%s\n' "$x" | grep -qxF -- "R 0 refs/remotes/origin/b1 $sha 0"; [ "${PIPESTATUS[0]}" = 141 ] && p=$((p+1)); done
for ((k=0;k<N;k++)); do grep -qxF -- "R 0 refs/remotes/origin/b1 $sha 0" <<<"$x" || h=$((h+1)); done
echo "raw_small_pipe_141=$p/$N herestring_misses=$h/$N"
# (2b) medium input: 60 lines (about 4 KiB), match on line 1
y="$(for ((j=0;j<60;j++)); do printf 'R 0 refs/remotes/origin/m%s %s 1\n' "$j" "$sha"; done)"
q=0; for ((k=0;k<N;k++)); do printf '%s\n' "$y" | grep -qxF -- "R 0 refs/remotes/origin/m0 $sha 1"; [ "${PIPESTATUS[0]}" = 141 ] && q=$((q+1)); done
mm="$(printf 'R 0 refs/remotes/origin/first %s 0\nL 0 origin sha256sum:aa\nN 0 origin\n%s' "$sha" "$y")"; mq=0
for ((k=0;k<N;k++)); do hi_push_changed "$mm" "$mm" && mq=$((mq+1)); done
echo "raw_medium_pipe_141=$q/$N real_medium_false_push=$mq/$N"
# (3) real function, realistic small marks (2 repos, a few refs), b == a  -> must return 1 (no push) every time
mk() { printf 'D 0 /p\n'; for j in 1 2 3; do printf 'R 0 refs/remotes/origin/b%s %s 0\n' "$j" "$sha"; done
       printf 'N 0 origin\nL 0 origin sha256sum:aa\nD 1 /p/s\n'
       for j in 1 2; do printf 'R 1 refs/remotes/origin/c%s %s 0\n' "$j" "$sha"; done; printf 'N 1 origin\nL 1 origin sha256sum:bb\n'; }
m="$(mk)"; fp=0
for ((k=0;k<N;k++)); do hi_push_changed "$m" "$m" && fp=$((fp+1)); done
echo "real_small_false_push=$fp/$N"
# (4) real function, large marks (20000 remote-tracking refs; f>0 lines skip the inner grep), b == a: deterministic
big="$(printf 'R 0 refs/remotes/origin/first %s 0\n' "$sha"; printf 'L 0 origin sha256sum:aa\nN 0 origin\n'; for ((j=0;j<20000;j++)); do printf 'R 0 refs/remotes/origin/x%s %s 1\n' "$j" "$sha"; done)"
bp=0; for k in 1 2 3; do hi_push_changed "$big" "$big" && bp=$((bp+1)); done
echo "real_large_false_push=$bp/3 bytes=${#big}"
# (5) positive needle: a real change MUST be seen (a moved ref with no fetch)
m2="${m/b1 $sha/b1 1123456789abcdef0123456789abcdef01234567}"
pn=0; for k in 1 2 3; do hi_push_changed "$m" "$m2" && pn=$((pn+1)); done
echo "positive_needle_change_seen=$pn/3"
# (6) Z line (no fingerprint tool) must fail closed with its error, also when the marks are large
zb="$(printf 'Z 0 origin\n%s' "$big")"; zs=0
for k in 1 2 3; do out="$(hi_push_changed "$zb" "$zb")"; r=$?; [ "$r" = 0 ] && [[ "$out" == *"no cksum or sha256sum"* ]] && zs=$((zs+1)); done
echo "z_fail_closed_large=$zs/3"
