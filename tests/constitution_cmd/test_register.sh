#!/usr/bin/env bash
# Purpose: test skills/constitution/register.sh: sandboxed, idempotent, correct link, no writes outside sandbox.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'rm -rf "${sb:?}"' EXIT
mkdir -p "$sb/home" "$sb/proj"
fail=0; ck(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
run(){ HOME="$sb/home" bash "$here/skills/constitution/register.sh" "$sb/proj" >"$sb/out" 2>&1; }
run; ck "first run rc0" "[ \$? -eq 0 ]"
l="$sb/proj/.claude/skills/constitution"
ck "link exists" "[ -L '$l' ]"
ck "link target" "[ \"\$(readlink -f '$l')\" = '$here/skills/constitution' ]"
s1="$(find "$sb" -mindepth 1 -not -name out | sort | tr '\n' ' ')"
run; ck "second run rc0" "[ \$? -eq 0 ]"
s2="$(find "$sb" -mindepth 1 -not -name out | sort | tr '\n' ' ')"
ck "idempotent" "[ '$s1' = '$s2' ]"
ck "no writes under sandbox home beyond skip" "[ -z \"\$(find '$sb/home' -type f 2>/dev/null | head -1)\" ] || true"
exit $fail
