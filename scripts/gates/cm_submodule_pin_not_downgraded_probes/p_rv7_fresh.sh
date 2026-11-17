#!/usr/bin/env bash
# p_rv7_fresh.sh <gate>... : reviewer killer probes (round 7), real git, no wrapper, for three gate members the suite
# never drives with a distinguishing input:
#   ITEM4     tracked_item CON-1234 (4 digits; the header says "3+ digits"), authoriser ops  -> real: WAIVED (0)
#   ITEM3     tracked_item CON-046 control                                                -> WAIVED (0) on every gate
#   SELFTRAIL authoriser "t " (TRAILING space) where committer/author name is t          -> real: refused (1)
#   SELFLEAD  authoriser " t" (leading space, the suite's own shape) control             -> refused (1)
#   HELPLONG  --help                                                                       -> real: 0, text printed
#   HELPSHORT -h control                                                                   -> 0
# Output per gate: KEY=<rc>/<n WAIVED> ...  (HELP*: <rc>/<n lines>)
set -u
t="$(mktemp -d "${TMPDIR:?}/prf.XXXXXX")"; [ -n "$t" ] && [ -d "$t" ] || exit 9
export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1; : >"$GIT_CONFIG_GLOBAL"   # HOME is NOT reassigned
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
exp="$(date -d '+10 days' +%F)"
fx() { # <dir> <authoriser> <item> -> super pins B, staged A, waiver row (B -> A) in the index
  local sb="$1/super/sub"; mkdir -p "$sb"; git init -q -b main "$sb"
  git -C "$sb" commit -q --allow-empty -m A; A=$(git -C "$sb" rev-parse HEAD)
  git -C "$sb" commit -q --allow-empty -m B; B=$(git -C "$sb" rev-parse HEAD)
  git init -q -b main "$1/super"; git -C "$1/super" update-index --add --cacheinfo 160000,"$B",sub; git -C "$1/super" commit -q -m base
  local h; h=$(git -C "$1/super" rev-parse HEAD)
  git -C "$1/super" update-index --cacheinfo 160000,"$A",sub
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub "$B" "$A" "$2" "$exp" "$3" "$h" >"$1/super/.submodule_pin_waivers"
  git -C "$1/super" add .submodule_pin_waivers
}
for g in "$@"; do
  o=""
  for k in ITEM4:ops:CON-1234 ITEM3:ops:CON-046 'SELFTRAIL:t :CON-046' 'SELFLEAD: t:CON-046'; do
    IFS=: read -r key au it <<<"$k"
    d="$(mktemp -d "$t/fx.XXXXXX")"; fx "$d" "$au" "$it"
    bash "$g" --root "$d/super" >"$t/out" 2>&1; rc=$?
    o+="$key=$rc/$(grep -c 'WAIVED' "$t/out") "
  done
  bash "$g" --help >"$t/out" 2>&1; o+="HELPLONG=$?/$(wc -l <"$t/out") "
  bash "$g" -h >"$t/out" 2>&1; o+="HELPSHORT=$?/$(wc -l <"$t/out")"
  echo "$(basename "$g"): $o"
done
rm -rf "${t:?}"
