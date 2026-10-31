#!/usr/bin/env bash
# test_rotate_integration.sh — INTEGRATION tests: the real rotate script run as a
# process against real files in a mktemp sandbox, including a real git repository.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

[ -r "$ROTATE" ] || { no "rotate script present"; summary integration; exit 1; }

# 1. rotation with --source -----------------------------------------------------
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
old="$(cat "$D/latest.md")"; prompt_doc newone >"$S/new.md"
out="$(bash "$ROTATE" first_rot --source "$S/new.md" --dir "$D" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "rotate with --source rc=0" || no "rotate with --source rc=$rc: $out"
[ -f "$D/03_first_rot.md" ] && ok "archive 03_first_rot.md created" || no "archive missing"
[ "$(cat "$D/03_first_rot.md" 2>/dev/null)" = "$old" ] && ok "archive holds the previous latest.md" || no "archive content differs"
cmp -s "$D/latest.md" "$S/new.md" && ok "latest.md now holds the source" || no "latest.md not the source"
[ ! -e "$D/.rotate.lock" ] && ok "lock released" || no "lock left behind"
[ "$(cat "$D/01_old.md")" = "$(prompt_doc old)" ] && ok "01_old.md untouched" || no "01_old.md modified"

# 2. rotation without --source keeps latest.md (copy) --------------------------
cur="$(cat "$D/latest.md")"
expect_rc "rotate without --source" 0 bash "$ROTATE" second_rot --dir "$D"
[ "$(cat "$D/04_second_rot.md")" = "$cur" ] && ok "04 archive = previous latest" || no "04 archive wrong"
[ "$(cat "$D/latest.md")" = "$cur" ] && ok "latest.md unchanged copy without --source" || no "latest.md changed without --source"
[ "$(stat -c %i "$D/latest.md")" != "$(stat -c %i "$D/04_second_rot.md")" ] && ok "latest.md and archive are distinct files" || no "latest.md shares inode with archive"

# 3. dry-run writes nothing ----------------------------------------------------
before="$(tree_digest "$D")"
out="$(bash "$ROTATE" third_rot --source "$S/new.md" --dir "$D" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "dry-run rc=0" || no "dry-run rc=$rc"
grep -q '05_third_rot.md' <<<"$out" && ok "dry-run plan names 05_third_rot.md" || no "dry-run plan missing target: $out"
[ "$(tree_digest "$D")" = "$before" ] && ok "dry-run changed nothing (digest equal)" || no "dry-run modified the tree"

# 4. refusals ------------------------------------------------------------------
expect_rc "same NAME again is a collision" 3 bash "$ROTATE" first_rot --dir "$D"
expect_rc "missing --source file" 3 bash "$ROTATE" xx --source "$S/nope.md" --dir "$D"
expect_rc "--source is a directory" 3 bash "$ROTATE" xx --source "$S" --dir "$D"
printf '# no prompt block\n' >"$S/bad.md"
expect_rc "--source without PROMPT block" 3 bash "$ROTATE" xx --source "$S/bad.md" --dir "$D"
expect_rc "no NAME" 2 bash "$ROTATE" --dir "$D"
expect_rc "unknown flag" 2 bash "$ROTATE" xx --bogus --dir "$D"
expect_rc "--help" 0 bash "$ROTATE" --help
S5="$(mk_sandbox)"; D5="$(mk_setup_dir "$S5")"; rm -f "$D5/latest.md"
expect_rc "latest.md missing refuses" 3 bash "$ROTATE" xx --dir "$D5"
[ "$(tree_digest "$D")" = "$before" ] && ok "refusals changed nothing" || no "a refusal modified the tree"

# 5. real git repository -------------------------------------------------------
G="$(mk_sandbox)"; git -C "$G" init -q; GD="$(mk_setup_dir "$G")"
git -C "$G" add -A && git -C "$G" commit -q -m init
src="$S/gitnew.md"; prompt_doc gitnew >"$src"
expect_rc "rotate inside git repo" 0 bash "$ROTATE" git_rot --source "$src" --dir "$GD"
st="$(git -C "$G" status --porcelain)"
grep -q '^ M docs/prompts/setup/latest.md$' <<<"$st" && ok "git sees latest.md modified" || no "git status latest: $st"
grep -q '^?? docs/prompts/setup/03_git_rot.md$' <<<"$st" && ok "git sees new 03_git_rot.md" || no "git status archive: $st"
[ "$(git -C "$G" show HEAD:docs/prompts/setup/latest.md)" = "$(cat "$GD/03_git_rot.md")" ] && ok "archive equals committed latest.md" || no "archive != committed latest"
[ "$(printf '%s\n' "$st" | wc -l)" -eq 2 ] && ok "exactly two paths changed in git" || no "unexpected git changes: $st"
summary integration
