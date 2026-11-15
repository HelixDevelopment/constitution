#!/usr/bin/env bash
# byte_identity_run.sh W BASE_ROOT NEW_ROOT OUT — runs tools/byte_identity.sh on BASE and NEW, then on a copy of NEW
# with three control changes (one character of the help text, one of the action-prefix program, and the installer's
# hi_parse_stream program reporting rate_limited=2 instead of 1). The first run must say SAME (or SAME OUTPUT) on
# every line; the control run must say DIFFERS on exactly those three lines. Writes OUT; exit 0 when both hold.
set -u
W="${1:?W}"; base="${2:?BASE_ROOT}"; new="${3:?NEW_ROOT}"; out="${4:?OUT}"
C="$(mktemp -d "$W/bidctl.XXXX")" || exit 2
{ (cd "$W" && bash "$W/tools/byte_identity.sh" "$base" "$new"); echo "exit=$?"; } >"$out" 2>&1
mkdir -p "$C/scripts" && cp -a "$new/scripts/." "$C/scripts/"
python3 -I - "$C/scripts/install_constitution.sh" "$C/scripts/install_action_prefix.sh" <<'EOF' || { echo "control edit failed" >>"$out"; rm -rf -- "${C:?}"; exit 2; }
import sys
for p, old, new in ((sys.argv[1], "Needs bash >= 4.4 and git.", "Needs bash >= 4.4 and git!"),
                    (sys.argv[2], "import json, os, re, secrets, sys", "import json, os, re, secrets, sys "),
                    (sys.argv[1], "        if pat.search(line): rl = 1\n", "        if pat.search(line): rl = 2\n")):
    s = open(p, encoding="utf-8").read(); assert s.count(old) == 1, old
    s = s.replace(old, new); open(p, "w", encoding="utf-8").write(s)
EOF
{ echo "## control needle: one character changed in the new help text, one in the action-prefix program, and the"
  echo "## installer's hi_parse_stream program reports rate_limited=2 (all three must show DIFFERS)"
  (cd "$W" && bash "$W/tools/byte_identity.sh" "$base" "$C"); echo "exit=$?"; } >>"$out" 2>&1
rm -rf -- "${C:?}"
first="$(sed -n '1,/^exit=/p' "$out")"; ctl="$(sed -n '/^## control needle/,$p' "$out")"
ok=1
printf '%s\n' "$first" | grep -q '^exit=0$' || ok=0
printf '%s\n' "$first" | grep -q '^DIFFERS' && ok=0
[ "$(printf '%s\n' "$ctl" | grep -c '^DIFFERS')" = 3 ] || ok=0
printf '%s\n' "$ctl" | grep -q '^DIFFERS  install_constitution.sh --help' || ok=0
printf '%s\n' "$ctl" | grep -q '^DIFFERS  install_action_prefix.sh merge_with_python' || ok=0
printf '%s\n' "$ctl" | grep -q '^DIFFERS  install_constitution.sh hi_parse_stream' || ok=0
if [ "$ok" = 1 ]; then echo "RESULT: PASS (every item SAME or SAME OUTPUT; the three control changes DIFFER)" >>"$out"; exit 0; fi
echo "RESULT: FAIL" >>"$out"; exit 1
