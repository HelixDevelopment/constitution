#!/usr/bin/env bash
# test_repo_guard_mutants.sh — §1.1 mutants of tests/decisions/repo_guard.sh. Each mutant weakens one part of the
# scoped repo-change guard; it is KILLED when the guard's own control needles (guard_selftest) then FAIL.
# A mutant that no longer applies (a stale anchor) is NOT-APPLIED: listed by name and the run FAILS.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(cd "$here/../.." && pwd)"
. "$repo/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dec_guardmut.XXXXXX")" || exit 1
trap 'safe_rm_rf "${tmp:?}"' EXIT
killed=0; survived=0; applied=0; not_applied=0; not_applied_names=""
gmutant() { # name old new
  local name="$1" m="$tmp/$1.sh"
  if ! python3 -I - "$here/repo_guard.sh" "$m" "$2" "$3" <<'PY'
import sys; src, dst, old, new = sys.argv[1:5]; s = open(src).read()
if old not in s: sys.exit(1)
open(dst, "w").write(s.replace(old, new, 1))
PY
  then echo "  NOT-APPLIED $name (stale anchor)"; not_applied=$((not_applied+1)); not_applied_names="$not_applied_names $name"; return; fi
  applied=$((applied+1))
  if (cd "$tmp" && . "$m" && guard_selftest) >"$tmp/$name.out" 2>&1; then
    survived=$((survived+1)); echo "  SURVIVED $name"
  else killed=$((killed+1)); echo "  killed  $name ($(grep -m1 'needle BAD' "$tmp/$name.out" | sed 's/^ *//'))"; fi
}
# baseline: the unmutated guard must pass its own needles
if (cd "$tmp" && . "$here/repo_guard.sh" && guard_selftest) >"$tmp/base.out" 2>&1; then echo "  ok   baseline selftest PASS"
else echo "  BAD  baseline selftest FAILED"; cat "$tmp/base.out"; exit 1; fi
gmutant G1_top_level_disabled "printf 'TOP %s\n' \"\$e\"; done" ": ; done"
gmutant G2_scoping_removed "    find . \\( -path ./.git -o -path ./.remember \\) -prune -o \\" "    find . -print | sed 's/^/ART /'
    find . \\( -path ./.git -o -path ./.remember \\) -prune -o \\"
gmutant G3_artefacts_disabled "\\( -name decisions.yml -o -name decisions.sha256 -o -name decisions.intent -o -name '.decisions*' \\" "\\( -name NOPE_ \\"
gmutant G4_block_region_disabled "printf 'DOC %s %s\n' \"\$p\" \"\$(_guard_region \"\$p\")\"" "printf 'DOC %s %s\n' \"\$p\" none"
gmutant G5_docfull_always_compared 'if grep -q "^DOCFULL $name " "$after"; then printf' 'if true; then printf'
gmutant G6_own_hashes_disabled "printf 'OWN %s %s\n'" ": printf 'OWN %s %s\n'"
gmutant G7_removed_own_ignored '    case "$line" in OWN\ *|OWNDIR\ *|DOC\ *|DOCFULL\ *) echo "  removed/changed' '    case "$line" in NOPE\ *) echo "  removed/changed'
echo "repo guard mutants: applied=$applied killed=$killed survived=$survived not_applied=$not_applied"
[ "$not_applied" -eq 0 ] || echo "repo guard mutants: FAIL - stale anchors:$not_applied_names"
[ "$survived" -eq 0 ] && [ "$not_applied" -eq 0 ]
