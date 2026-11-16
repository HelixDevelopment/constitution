#!/usr/bin/env bash
# unbornprobe.sh <gate>: run a gate on unborn sha1 and sha256 repos with one new gitlink; print rc per format.
set -u; g="${1:?gate}"; d=$(mktemp -d -p /mnt/DATA1TB/claude-work/tmp) || exit 2
for f in sha1 sha256; do u="$d/$f"; git init -q --object-format=$f "$u"; h=$(printf x | git -C "$u" hash-object --stdin)
  git -C "$u" update-index --add --cacheinfo 160000,"$h",sub; ( cd "$u" && bash "$g" --root "$u" >/dev/null 2>&1 ); rc=$?; printf '%s=%s ' "$f" "$rc"; done; echo
rm -rf "${d:?}"
