#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_e2e.sh — full lifecycle with the real engine: add (git source, pinned) → enable → wire into
# every supported agent layout → verify → disable (commands unwired) → re-enable/wire → unwire →
# remove, asserting the on-disk shims, the lock file and that the extension code never ran.
T_NAME=e2e
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
export CONSTITUTION_EXT_FIXTURE_MARKER="$SB/HOOK_RAN"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
HS="$(ext_git_repo "$FIX/hooks-fixture" "$SB/hooks-src")"
HD="$(bash "$ENGINE" --json validate "$SB/hooks-src" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')"
e() { eng --root "$R" --project-root "$P" "$@"; }
ej() { engj --root "$R" --project-root "$P" --json "$@"; }

e add "$SB/hooks-src" --sha "$HS" --sha256 "$HD" --yes; eq "add" 0 "$RC"; has "consent shows capabilities" "executes:hooks/session_start.sh" "$OUT"
has "consent shows mcp" "mcp:hooks-fixture-mcp" "$OUT"
e wire hooks-fixture --agent claude --target "$P"; eq "wire of disabled ext refused (3)" 3 "$RC"
e enable hooks-fixture; eq "enable without consent refused (3)" 3 "$RC"
e enable hooks-fixture --yes; eq "enable" 0 "$RC"
e enable hello-fixture --yes; eq "enable bundled" 0 "$RC"
ej info hooks-fixture; eq "enabled" "true" "$(jget "$OUT" enabled)"; eq "hooks component enabled" "enabled" "$(jget "$OUT" components.hooks)"

mkdir -p "$P/.qwen/commands"; printf 'user owned\n' >"$P/.qwen/commands/hello-fixture.toml"
e wire --agent qwen --target "$P"; eq "wire refuses to overwrite an unmanaged file (3)" 3 "$RC"
eq "unmanaged file untouched" "user owned" "$(cat "$P/.qwen/commands/hello-fixture.toml")"
rm -f "$P/.qwen/commands/hello-fixture.toml"
e wire --agent all --target "$P"; eq "wire all agents" 0 "$RC"
check "claude symlink" test -L "$P/.claude/skills/hooks-fixture-run"
check "claude symlink resolves to SKILL.md" test -f "$P/.claude/skills/hooks-fixture-run/SKILL.md"
check "claude bundled symlink" test -L "$P/.claude/skills/hello-fixture"
check "opencode md" test -f "$P/.opencode/commands/hello-fixture.md"
check "gemini toml" test -f "$P/.gemini/commands/hello-fixture.toml"
check "qwen toml" test -f "$P/.qwen/commands/hello-fixture.toml"
check "pi prompt" test -f "$P/.pi/prompts/hello-fixture.md"
g="$(cat "$P/.gemini/commands/hello-fixture.toml")"
has "toml description" 'description = "TEST FIXTURE command that prints a greeting"' "$g"
has "toml args placeholder" '{{args}}' "$g"; has "toml managed marker" "managed-by: constitution_ext" "$g"
o="$(cat "$P/.opencode/commands/hello-fixture.md")"; has "opencode frontmatter" "description: " "$o"
# shellcheck disable=SC2016
has "opencode body" '$ARGUMENTS' "$o"
python3 -I -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$P/.gemini/commands/hello-fixture.toml"; eq "toml parses" 0 $?

e verify; eq "verify all" 0 "$RC"
e disable hooks-fixture; eq "disable" 0 "$RC"
check "disable unwired claude link" test ! -e "$P/.claude/skills/hooks-fixture-run"
check "disable unwired opencode" test ! -e "$P/.opencode/commands/hooks-fixture-run.md"
check "other ext still wired" test -L "$P/.claude/skills/hello-fixture"
ej info hooks-fixture; eq "hooks back to disabled" "disabled" "$(jget "$OUT" components.hooks)"

printf 'user edit\n' >>"$P/.pi/prompts/hello-fixture.md"
e unwire --agent all --target "$P"; eq "unwire all" 0 "$RC"
check "user-modified shim left in place" test -f "$P/.pi/prompts/hello-fixture.md"
rm -f "$P/.pi/prompts/hello-fixture.md"
check "claude link gone" test ! -e "$P/.claude/skills/hello-fixture"
check "gemini toml gone" test ! -e "$P/.gemini/commands/hello-fixture.toml"
e remove hooks-fixture --yes; eq "remove" 0 "$RC"
check "tree gone" test ! -e "$R/extensions/_installed/hooks-fixture"
hasnt "lock no longer lists it" "hooks-fixture" "$(cat "$P/.constitution/extensions.lock.yml")"
e remove hello-fixture --yes; eq "removing a bundled extension refused (3)" 3 "$RC"
check "bundled tree untouched" test -f "$R/extensions/hello-fixture/extension.yml"
e disable hello-fixture; eq "disable bundled" 0 "$RC"
check "extension code never executed" test ! -e "$SB/HOOK_RAN"
e doctor; eq "doctor healthy at end" 0 "$RC"
finish
