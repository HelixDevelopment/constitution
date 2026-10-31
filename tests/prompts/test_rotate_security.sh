#!/usr/bin/env bash
# test_rotate_security.sh — SECURITY tests: hostile NAME values (path traversal,
# spaces, newline, shell metacharacters), directories outside docs/prompts/setup,
# symlink tricks. Every refusal must leave the tree byte-identical and must not
# create any file outside the setup directory.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -r "$ROTATE" ] || { no "rotate script present"; summary security; exit 1; }
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; before="$(tree_digest "$S")"

nl_name="$(printf 'a\nb')"
for n in "../evil" "../../etc/x" "a b" "$nl_name" 'a;touch PWNED' '$(touch PWNED)' '`touch PWNED`' "A" "a/b" "-rf" "--dir" "a*" ".hidden" "latest"; do
  rc=0; bash "$ROTATE" "$n" --dir "$D" >/dev/null 2>&1 || rc=$?
  label="NAME $(printf %q "$n")"
  # 'latest' is reserved (an archive named NN_latest.md would be confusing)
  [ "$rc" -eq 2 ] && ok "$label refused rc=2" || no "$label rc=$rc (want 2)"
done
[ ! -e "$S/PWNED" ] && [ ! -e "$D/PWNED" ] && [ ! -e "$PWD/PWNED" ] && ok "no injected command executed" || no "injection created PWNED"
[ "$(tree_digest "$S")" = "$before" ] && ok "hostile names changed nothing" || no "hostile names modified the sandbox"

# directory outside docs/prompts/setup
O="$S/other"; mkdir -p "$O"; prompt_doc o >"$O/latest.md"
expect_rc "--dir outside docs/prompts/setup refused" 3 bash "$ROTATE" ok_name --dir "$O"
[ ! -e "$O/01_ok_name.md" ] && ok "nothing archived in foreign dir" || no "foreign dir modified"
# a symlink named docs/prompts/setup pointing elsewhere must be refused (real path checked)
L="$S/l"; mkdir -p "$L/docs/prompts"; ln -s "$O" "$L/docs/prompts/setup"
expect_rc "symlinked setup dir to foreign target refused" 3 bash "$ROTATE" ok_name --dir "$L/docs/prompts/setup"
# a traversal in --dir that resolves outside
expect_rc "--dir with ../ escaping refused" 3 bash "$ROTATE" ok_name --dir "$D/../../../other"
# latest.md as a symlink is refused (could redirect writes)
S2="$(mk_sandbox)"; D2="$(mk_setup_dir "$S2")"; mv "$D2/latest.md" "$S2/real.md"; ln -s "$S2/real.md" "$D2/latest.md"
expect_rc "latest.md symlink refused" 3 bash "$ROTATE" ok_name --dir "$D2"
[ -L "$D2/latest.md" ] && [ -f "$S2/real.md" ] && ok "symlink case left intact" || no "symlink case modified"
# source pointing to /dev/zero or a fifo must be refused (not a regular file)
expect_rc "--source /dev/zero refused" 3 bash "$ROTATE" ok_name --source /dev/zero --dir "$D"
mkfifo "$S/fifo"
expect_rc "--source fifo refused" 3 timeout 10 bash "$ROTATE" ok_name --source "$S/fifo" --dir "$D"
# output never echoes file content of an unrelated secret-looking env var
SECRET_TOKEN_FOR_TEST=s3cr3tvalue123 bash "$ROTATE" sec_name --dir "$D" >"$S/out.txt" 2>&1
grep -q s3cr3tvalue123 "$S/out.txt" && no "env value leaked to output" || ok "no env value in output"
summary security
