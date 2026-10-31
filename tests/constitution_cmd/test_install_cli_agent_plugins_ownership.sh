#!/usr/bin/env bash
# Purpose: install_cli_agent_plugins.sh must act ONLY on link paths it can prove are its own
#   (B1 user dangling links in .gemini/.qwen/prompts kept, B2 user symlink at a generated name kept,
#   B3 every target dir containment-checked, B4 user dangling */skills/<name> link kept).
#   Tree checksums of the project sandbox and of an outside decoy prove "untouched".
# Env: none. Exit 0 all pass. One mktemp sandbox, safe_rm_rf. Does not reassign HOME.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$here/scripts/lib/safe_rm.sh"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'safe_rm_rf "$sb"' EXIT
fail=0; ck(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
tsum(){ ( cd "$1" && find . -mindepth 1 -type l -printf 'L %p -> %l\n' | LC_ALL=C sort; find . -mindepth 1 -type d | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum ) | sha256sum; }
inst(){ RC=0; HOME="$sb/home" bash "$here/scripts/install_cli_agent_plugins.sh" --no-plugin "$1" >"$sb/out" 2>&1 || RC=$?; }
mkdir -p "$sb/home" "$sb/decoy"; printf 'precious\n' > "$sb/decoy/keep.txt"
gen="$here/actions/generated/gemini"; one="$(ls "$gen"/*.toml | head -1)"; base="$(basename "$one")"

# B1 + B4 + B2 in one project
p="$sb/p1"; mkdir -p "$p/.gemini/commands" "$p/.qwen/commands" "$p/prompts" "$p/.claude/skills" "$p/mine"
printf 'u\n' > "$p/mine/file"
ln -s "$p/gone" "$p/prompts/my_dangling.md"
ln -s "$p/gone" "$p/.gemini/commands/my_dangling.toml"
ln -s "$p/gone" "$p/.qwen/commands/my_dangling.toml"
ln -s "/x/skills/foo" "$p/.claude/skills/foo"
ln -s "$p/mine/file" "$p/.gemini/commands/$base"
inst "$p"
ck "B1 user dangling prompts link kept" "[ -L '$p/prompts/my_dangling.md' ]"
ck "B1 user dangling gemini link kept" "[ -L '$p/.gemini/commands/my_dangling.toml' ]"
ck "B1 user dangling qwen link kept" "[ -L '$p/.qwen/commands/my_dangling.toml' ]"
ck "B4 user dangling */skills/foo link kept" "[ \"\$(readlink '$p/.claude/skills/foo')\" = /x/skills/foo ]"
ck "B2 user symlink at generated name kept" "[ \"\$(readlink '$p/.gemini/commands/$base')\" = '$p/mine/file' ]"
ck "B2 user target file untouched" "[ \"\$(cat '$p/mine/file')\" = u ]"
ck "B2 refusal reported (rc non-zero or warn)" "grep -q 'left untouched' '$sb/out'"
# ours still wired + ours-dangling reaped
ck "own links wired (a different gemini cmd linked)" "[ \$(find '$p/.gemini/commands' -type l -name '*.toml' | wc -l) -gt 3 ]"
ln -s "$here/actions/generated/gemini/zz_removed.toml" "$p/.gemini/commands/zz_removed.toml"
ln -s "$here/skills/zz_removed_skill" "$p/.claude/skills/zz_removed_skill"
inst "$p"
ck "own dangling command link reaped" "[ ! -L '$p/.gemini/commands/zz_removed.toml' ]"
ck "own dangling skill link reaped" "[ ! -L '$p/.claude/skills/zz_removed_skill' ]"
ck "user dangling still kept after 2nd run" "[ -L '$p/prompts/my_dangling.md' ] && [ -L '$p/.claude/skills/foo' ]"

# B3 every target dir symlinked outside the project: nothing written outside
for d in .gemini .qwen prompts .claude; do
  q="$sb/q_${d#.}"; mkdir -p "$q"; ln -s "$sb/decoy" "$q/$d"
  before="$(tsum "$sb/decoy")"
  inst "$q"
  ck "B3 $d symlinked outside: decoy untouched" "[ '$before' = \"\$(tsum '$sb/decoy')\" ]"
  ck "B3 $d symlinked outside: rc non-zero" "[ $RC -ne 0 ]"
done
# parent-level: .gemini real dir, commands symlinked outside
q="$sb/q_sub"; mkdir -p "$q/.gemini"; ln -s "$sb/decoy" "$q/.gemini/commands"
before="$(tsum "$sb/decoy")"; inst "$q"
ck "B3 .gemini/commands symlinked outside: decoy untouched" "[ '$before' = \"\$(tsum '$sb/decoy')\" ]"
# symlink INSIDE the project is fine
q="$sb/q_in"; mkdir -p "$q/real_g"; ln -s real_g "$q/.gemini"; inst "$q"
ck "B3 .gemini symlinked inside project ok" "[ -L '$q/real_g/commands/$base' ]"
# R1: a user link to a NON-skills, NON-generated constitution file at a generated name is left untouched
q="$sb/q_r1"; mkdir -p "$q/.gemini/commands"
ln -s "$here/docs/guides/constitution_command_guide.md" "$q/.gemini/commands/$base"
inst "$q"
ck "R1 user link to other constitution file kept" "[ \"\$(readlink '$q/.gemini/commands/$base')\" = '$here/docs/guides/constitution_command_guide.md' ]"
# R4: sibling-prefix (<project>-evil) must be refused and the sibling stays empty
q="$sb/q_r4"; mkdir -p "$q" "$sb/q_r4-evil"; ln -s "../q_r4-evil" "$q/.qwen"
inst "$q"
ck "R4 .qwen -> sibling-prefix dir: sibling empty" "[ -z \"\$(ls -A '$sb/q_r4-evil')\" ]"
ck "R4 .qwen -> sibling-prefix dir: rc non-zero" "[ $RC -ne 0 ]"
# F1: .claude symlinked outside must not receive settings.json(.bak) even via the standalone prefix installer
q="$sb/q_f1"; mkdir -p "$q"; ln -s "$sb/decoy" "$q/.claude"; before="$(tsum "$sb/decoy")"
RC=0; bash "$here/scripts/install_action_prefix.sh" "$q" >/dev/null 2>&1 || RC=$?
ck "F1 standalone install_action_prefix refuses outside .claude" "[ '$before' = \"\$(tsum '$sb/decoy')\" ] && [ $RC -ne 0 ]"
ck "final: decoy + home untouched" "[ \"\$(cat '$sb/decoy/keep.txt')\" = precious ] && [ ! -e '$sb/decoy/commands' ]"
exit $fail
