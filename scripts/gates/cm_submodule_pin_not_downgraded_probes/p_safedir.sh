#!/usr/bin/env bash
# p_safedir.sh <gate>... : reviewer probe (round 7) for the keep-list members of line
#   unsets=(); for v in "${lev[@]}"; do case "$v" in GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;; *) unsets+=(-u "$v") ;; esac; done
# A submodule owned by another user is refused by git unless safe.directory allows it; safe.directory is read only from
# protected config (system, global, command line). `git -c safe.directory=... commit` hands the hook GIT_CONFIG_PARAMETERS
# (the GIT_CONFIG_COUNT/KEY/VALUE form is the other command-line channel). Git's own switch GIT_TEST_ASSUME_DIFFERENT_OWNER=1
# makes every repository look foreign, so the shape needs no second user. Each mode runs a FORWARD and a DOWNGRADE fixture:
#   PARAMS: safe.directory=* via GIT_CONFIG_PARAMETERS     COUNT: the same via GIT_CONFIG_COUNT=1 KEY_0 VALUE_0
#   NONE:   control without safe.directory (the superproject itself is refused -> 2)
# The keep-list exists so these reach the submodule calls; a gate that drops a member answers BLIND (2) instead.
set -u
t="$(mktemp -d "${TMPDIR:?}/psd.XXXXXX")"; [ -n "$t" ] && [ -d "$t" ] || exit 9
export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1; : >"$GIT_CONFIG_GLOBAL"   # HOME is NOT reassigned
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fx() { # <dir> -> super pins B; FWD stages C (B <- C), DOWN stages A
  local sb="$1/super/sub"; mkdir -p "$sb"; git init -q -b main "$sb"
  for c in A B C; do git -C "$sb" commit -q --allow-empty -m "$c"; done
  A=$(git -C "$sb" rev-parse HEAD~2); B=$(git -C "$sb" rev-parse HEAD~1); C=$(git -C "$sb" rev-parse HEAD)
  git init -q -b main "$1/super"; git -C "$1/super" update-index --add --cacheinfo 160000,"$B",sub; git -C "$1/super" commit -q -m base
}
for g in "$@"; do
  o=""
  for mode in PARAMS COUNT NONE; do
    for k in FWD DOWN; do
      d="$(mktemp -d "$t/fx.XXXXXX")"; fx "$d"; r="$d/super"
      [ $k = FWD ] && git -C "$r" update-index --cacheinfo 160000,"$C",sub || git -C "$r" update-index --cacheinfo 160000,"$A",sub
      case $mode in
        PARAMS) env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_PARAMETERS="'safe.directory'='*'" bash "$g" --root "$r" >"$t/out" 2>&1 ;;
        COUNT)  env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' bash "$g" --root "$r" >"$t/out" 2>&1 ;;
        NONE)   env GIT_TEST_ASSUME_DIFFERENT_OWNER=1 bash "$g" --root "$r" >"$t/out" 2>&1 ;;
      esac
      o+="$mode$k=$?/$(grep -c 'not a repository' "$t/out") "
    done
  done
  echo "$(basename "$g"): $o"
done
rm -rf "${t:?}"
