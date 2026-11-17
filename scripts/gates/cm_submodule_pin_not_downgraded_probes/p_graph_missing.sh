#!/usr/bin/env bash
# p_graph_missing.sh <gate>... : reviewer probe (round 7), REAL git only, no wrapper.
# Submodule history A <- M <- T (main). A commit-graph is written while only A exists; then M and T are committed, so
# M and T are NOT in the graph. The loose object of M is removed (an incomplete object store; A and T present, so both
# presence checks pass; the repository is not shallow).
#   DOWNGRADE: base pin T, staged A. The truth is a downgrade (A is an ancestor of T), but the history between them is
#              incomplete, so the header promises BLIND ("cannot be decided", shallow or incomplete history).
#   CTL:       the same shape with M present: FAIL (1, ANCESTOR) -- the control proves the downgrade is real.
#   NOGRAPH:   the same incomplete store without a commit-graph: merge-base returns 128 -> BLIND.
# With a commit-graph, git 2.53 `merge-base --is-ancestor A T` prints "error: Could not read <M>" and returns 1 (not an
# ancestor) instead of 128; the gate discards stderr, so it sees fwd=1 back=1 shallow=false and prints WARN, exit 0.
# Output per gate: MODE=<rc>/<n FAIL>/<n WARN>/<n cannot be decided>[mb back rc] ...
set -u
t="$(mktemp -d "${TMPDIR:?}/pgm.XXXXXX")"; [ -n "$t" ] && [ -d "$t" ] || exit 9
export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1; : >"$GIT_CONFIG_GLOBAL"   # HOME is NOT reassigned
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fx() { # <dir> <graph:0|1> <break:0|1> -> super at $1/super pins T, staged A
  local sb="$1/super/sub"; mkdir -p "$sb"; git init -q -b main "$sb"
  GIT_COMMITTER_DATE='2020-01-01T00:00:00' git -C "$sb" commit -q --allow-empty -m A; A=$(git -C "$sb" rev-parse HEAD)
  [ "$2" = 1 ] && git -C "$sb" commit-graph write --reachable >/dev/null 2>&1
  GIT_COMMITTER_DATE='2020-01-02T00:00:00' git -C "$sb" commit -q --allow-empty -m M; M=$(git -C "$sb" rev-parse HEAD)
  GIT_COMMITTER_DATE='2020-01-03T00:00:00' git -C "$sb" commit -q --allow-empty -m T; T=$(git -C "$sb" rev-parse HEAD)
  [ "$3" = 1 ] && rm -f "$sb/.git/objects/${M:0:2}/${M:2}"
  git init -q -b main "$1/super"; git -C "$1/super" update-index --add --cacheinfo 160000,"$T",sub; git -C "$1/super" commit -q -m base
  git -C "$1/super" update-index --cacheinfo 160000,"$A",sub
}
for g in "$@"; do
  o=""
  for mode in DOWNGRADE CTL NOGRAPH; do
    d="$(mktemp -d "$t/fx.XXXXXX")"
    case $mode in DOWNGRADE) fx "$d" 1 1 ;; CTL) fx "$d" 1 0 ;; NOGRAPH) fx "$d" 0 1 ;; esac
    r="$d/super"; bash "$g" --root "$r" >"$t/out" 2>&1; rc=$?
    mb="$(git -C "$r/sub" merge-base --is-ancestor "$A" "$T" 2>"$t/err"; echo $?)/err$(grep -c 'Could not read' "$t/err")"
    o+="$mode=$rc/$(grep -c ': FAIL' "$t/out")/$(grep -c 'WARN' "$t/out")/$(grep -c 'cannot be decided' "$t/out")[mb:$mb] "
  done
  echo "$(basename "$g"): $o"
done
rm -rf "${t:?}"
