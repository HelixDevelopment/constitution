#!/usr/bin/env bash
# Purpose: test skills/constitution/register.sh (-> install_cli_agent_plugins.sh --skill constitution):
#   sandboxed, idempotent, correct link, nothing written outside the sandbox, and the refusal cases
#   (regular file at the link path, user-owned symlink, unrelated dangling links, symlinked .claude).
# Env: none. Exit 0 all pass, 1 any failure. Everything runs in ONE mktemp sandbox (safe_rm_rf).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
. "$here/scripts/lib/safe_rm.sh"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'safe_rm_rf "$sb"' EXIT
fail=0; ck(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
# tree checksum of everything under $1 (names, link texts, file hashes) -- no mtimes
tsum(){ ( cd "$1" && find . -mindepth 1 -type l -printf 'L %p -> %l\n' | LC_ALL=C sort; find . -mindepth 1 -type d | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum ) | sha256sum; }
mkdir -p "$sb/home" "$sb/proj" "$sb/outside_target"
printf 'precious\n' > "$sb/outside_target/keep.txt"
printf 'x\n' > "$sb/home/sentinel"
guard_before="$(tsum "$sb/home")$(tsum "$sb/outside_target")"
run(){ RC=0; HOME="$sb/home" bash "$here/skills/constitution/register.sh" "${1:-$sb/proj}" >"$sb/out" 2>&1 || RC=$?; }
run; ck "first run rc0" "[ $RC -eq 0 ]"
l="$sb/proj/.claude/skills/constitution"
ck "link exists" "[ -L '$l' ]"
ck "link target" "[ \"\$(readlink -f '$l')\" = '$here/skills/constitution' ]"
s1="$(tsum "$sb/proj")"
run; ck "second run rc0" "[ $RC -eq 0 ]"
ck "idempotent (tree checksum equal)" "[ '$s1' = \"\$(tsum '$sb/proj')\" ]"
ck "nothing written outside the project (home + outside_target unchanged)" "[ '$guard_before' = \"\$(tsum '$sb/home')\$(tsum '$sb/outside_target')\" ]"

# B1: a REGULAR file at the link path -> honest non-zero refusal, never a success line
rm -f "$l"; printf 'mine\n' > "$l"
run; ck "B1 regular file at link path: rc non-zero" "[ $RC -ne 0 ]"
ck "B1 regular file: refusal message present" "grep -q 'REFUSED' '$sb/out'"
ck "B1 regular file: no false 'linked 1'" "! grep -q 'linked 1 skill' '$sb/out'"
ck "B1 regular file left untouched" "[ \"\$(cat '$l')\" = mine ] && [ ! -L '$l' ]"
rm -f "$l"

# B2: --skill constitution must not remove unrelated dangling links, nor replace a user's symlink
mkdir -p "$sb/proj/.claude/skills"
ln -s "$sb/does_not_exist" "$sb/proj/.claude/skills/mine"
run; ck "B2 unrelated dangling link kept" "[ -L '$sb/proj/.claude/skills/mine' ]"
ck "B2 own link created next to it" "[ -L '$l' ]"
rm -f "$l" "$sb/proj/.claude/skills/mine"
ln -s "$sb/outside_target" "$l"
run; ck "B2 user symlink at our path: rc non-zero" "[ $RC -ne 0 ]"
ck "B2 user symlink untouched" "[ \"\$(readlink '$l')\" = '$sb/outside_target' ]"
rm -f "$l"
# our own stale (dangling) link IS replaced
ln -s "../../gone/skills/constitution" "$l"
run; ck "B2 own dangling link replaced rc0" "[ $RC -eq 0 ] && [ \"\$(readlink -f '$l')\" = '$here/skills/constitution' ]"
rm -f "$l"
# symlinked .claude pointing outside the project: refuse, write nothing there
mkdir -p "$sb/proj2"; ln -s "$sb/outside_target" "$sb/proj2/.claude"
before="$(tsum "$sb/outside_target")"
run "$sb/proj2"; ck "B2 symlinked .claude outside project: rc non-zero" "[ $RC -ne 0 ]"
ck "B2 symlinked .claude: nothing written outside" "[ '$before' = \"\$(tsum '$sb/outside_target')\" ]"
# symlinked .claude pointing INSIDE the project is fine
mkdir -p "$sb/proj3/real_claude"; ln -s real_claude "$sb/proj3/.claude"
run "$sb/proj3"; ck "B2 symlinked .claude inside project ok rc0" "[ $RC -eq 0 ] && [ -L '$sb/proj3/real_claude/skills/constitution' ]"
ck "final: nothing written outside the sandbox projects (home + outside_target)" "[ '$guard_before' = \"\$(tsum '$sb/home')\$(tsum '$sb/outside_target')\" ]"
exit $fail
