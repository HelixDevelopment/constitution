#!/bin/bash
# f5_check.sh <check_deps.sh> : R6-F5 checks (usable = rc 0 AND any non-whitespace character in the
# captured output; first NON-blank line shown; locale independent). Prints `FAIL ...` lines only.
SUT=$1
BL=$(mktemp -d) || exit 2; trap 'rm -rf "$BL"' EXIT
OLDIFS=$IFS; IFS=:
for d in $PATH; do  # shim every executable except git, so ONLY the stub git is used
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b=${f##*/}; [ "$b" = git ] && continue
    [ -x "$f" ] && [ ! -e "$BL/$b" ] && { printf '#!/bin/sh\nexec "%s" "$@"\n' "$f" >"$BL/$b"; chmod +x "$BL/$b"; }
  done
done
IFS=$OLDIFS
stub() { printf '#!/bin/sh\n%s\nexit %s\n' "$1" "$2" >"$BL/git"; chmod +x "$BL/git"; }
run() { PATH="$BL" LC_ALL=${1:-} "$SUT" 2>&1; }
stub 'printf "\n\ngit version 9.9\n"' 0
run | grep -q "^FOUND git: git version 9.9$" || echo "FAIL r6-f5: blank-first-line version output not FOUND with its first non-blank line: $(run | grep git)"
stub 'printf " \t\n\n  \n"' 0
run | grep -q "^MISSING git" || echo "FAIL r6-f5: whitespace-only output must be unusable"
stub 'printf "\n\n\n"' 1
run | grep -q "^MISSING git" || echo "FAIL r6-f5: rc 1 with blank output must be unusable"
stub 'printf "\ngit version 9.9\n"' 3
run | grep -q "^MISSING git" || echo "FAIL r6-f5: rc 3 with output must be unusable"
stub 'printf "\n  first line\nsecond line\n"' 0
o=$(run); { echo "$o" | grep -q "^FOUND git:   first line$" && ! echo "$o" | grep -q "second line"; } || echo "FAIL r6-f5: only the first non-blank line must be shown: $(echo "$o" | grep -e git -e second)"
stub 'printf "\377\376\n"' 0
for lc in C "$(locale -a 2>/dev/null | grep -i -m1 -e '^en_US\.utf-\?8$' -e '^c\.utf-\?8$')"; do
  [ -n "$lc" ] || continue
  run "$lc" | grep -q "^FOUND git: " || echo "FAIL r6-f5: non-UTF-8 output under LC_ALL=$lc not FOUND: $(run "$lc" | grep git)"
done
# R7b (c20): a line holding a space and a NUL byte. NUL is not [:space:], so by the rule above ("any
# non-whitespace character anywhere") the tool DID print non-whitespace output: usable => FOUND. The shell
# strips the NUL from the captured value (the FOUND line shows a blank version); that display quirk is
# pinned here on purpose, not changed: the judgement is the rule's, made on the raw bytes.
stub 'printf " \000\n"' 0
run | grep -q "^FOUND git: " || echo "FAIL r7b-c20: space+NUL output holds a non-whitespace byte and must be FOUND: $(run | grep git)"
stub 'printf "\000\n"' 0
run | grep -q "^MISSING git" || echo "FAIL r7b-c20: a lone NUL is captured as empty output and must be MISSING: $(run | grep git)"
exit 0
