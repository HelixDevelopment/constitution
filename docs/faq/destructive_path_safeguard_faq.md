# Destructive-Path Safeguard FAQ

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-24 |
| Last modified | 2026-10-24T14:30:00Z |
| Status | active |
| Status summary | Questions and answers drawn from behaviour of `scripts/hooks/guard-destructive-paths.py` and `scripts/lib/safe_rm.sh` as run on 2026-10-24 (62 guard cases, 305 bypass cases and 138 `safe_rm_rf` cases passed). Where an answer states an exit code it was reproduced by feeding a hook payload built in Python. |
| Authority | Constitution §11.4.287. The canonical text wins where this FAQ and the constitution disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | — |
| Fixed summary | — |
| Continuation | — |

Related: [guide](../guides/destructive_path_safeguard.md) · [manual](../manuals/destructive_path_safeguard_manual.md)

## Table of contents

- [Blocks and false positives](#blocks-and-false-positives)
- [Overrides](#overrides)
- [Registration and scope](#registration-and-scope)
- [safe_rm_rf](#safe_rm_rf)
- [What it cannot see](#what-it-cannot-see)

## Blocks and false positives

**Q1. Why was my command blocked?**
Read the first stderr line. It starts with `guardrails: BLOCKED — §11.4.287 class <letter>:` and names the command, the target and the reason. P means the target is or can glob to a protected path, X means the text could not be parsed, H means `HOME` was reassigned from something that can be empty, V means the target comes from an unguarded or unknown variable, U means code is piped into a shell from a source the guard cannot read. The manual section 4 lists each class.

**Q2. I only used a variable and it is set. Why class V?**
The guard cannot know what a variable holds at run time. It accepts a variable as guarded when the text has `${VAR:?msg}`, a `[ -n "$VAR" ]` test whose failure branch leaves, or a literal or `mktemp` assignment. A variable from `$1`, `read`, a `for` loop, an indirect expansion or `$(...)` that is not guarded stays unknown. Fix: write `"${VAR:?need a directory}"` at the use. In the probe, `W="${1:?need dir}"; rm -rf "$W/build"` was allowed and `rm -rf "$1/build"` was blocked.

**Q3. Is a plain `set -u` enough?**
No. An empty variable is still set, so `set -u` does not stop `rm -rf "$W/home"` with `W=""` from becoming `rm -rf /home`. Only `${VAR:?}` or an explicit non-empty test does.

**Q4. Does the guard block a command that merely mentions a delete, such as `grep -n "rm -rf /" file` or `echo "rm -rf /"`?**
No. Both were allowed in the probe: text inside quotes passed to a non-shell command is not a command. A trigger text inside `bash -c "..."`, `eval`, a trap, `$(...)` or a heredoc written to a script or fed to a shell is analysed as code.

**Q5. Is `rm -rf /tmp/foo/bar` a false positive?**
No, it is allowed (rc 0 in the probe). `rm -rf /tmp` itself is blocked as a system directory (class P). The guard protects the directory, not its descendants, except for protected home children, which are protected as exact paths.

**Q6. Why is `rm -rf ~/.claude-something` blocked but `rm -rf ~/Documents/old` allowed?**
`~/.claude-*` is in the protected set as a direct child of the home (prefix `.claude-`). `Documents` is protected as a direct child, but `Documents/old` is deeper and is not on the list. Both results were reproduced.

**Q7. My harmless script is blocked because it ends with `| sh`. Why?**
Class U: code piped into a shell (`sh`, `bash`, `zsh`, `dash`, `ksh`) from a source the guard cannot read. The probes `cat foo | bash` and `curl x | sh; <delete of /tmp/a>` were both blocked, so the pipe alone is enough. Write the script to a file, let the guard inspect it (Write is scanned), then run the file.

**Q8. Why does an unmatched quote block a command that has a delete in it?**
Class X. If the text cannot be parsed reliably (unterminated quote, `$(`, backtick, heredoc, or nesting deeper than 5) and it contains a destructive command, the guard fails closed. Without a destructive command in the text, parse problems do not block.

## Overrides

**Q9. How do I override a block?**
For classes H, V and U only, add a real top-level comment `# guardrails:allow <reason>` with a non-empty reason, for example `... # guardrails:allow scratch test in sandbox`. The findings are then printed as warnings and the call is allowed. The reproduced incident script with a marker returned rc 0, without it rc 2.

**Q10. Why is class P not overridable?**
Because a protected target is wrong whatever the reason given, and a text marker is trivially added by whoever (or whatever) wrote the command. In the probe, deleting `/` with a marker still returned rc 2. Class X is also not overridable: a marker cannot make unparsable text safe. The gate `cm_guard_class_p_not_overridable.sh` and its mutation test exist to keep it that way.

**Q11. I put the marker in an `echo "..."`, inside `bash -c` or a heredoc and it did nothing. Why?**
Only a real comment at the top level of the command counts. Text inside quotes, heredoc bodies, `bash -c`, traps and `$(...)` does not. A marker with no reason after it does not count either (rc 2 in the probe).

**Q12. Does the marker cover only the command next to it?**
No. It is payload-global. One marker anywhere at top level downgrades all H, V and U findings in the same tool call. In the probe, a marker on line 1 allowed a second unguarded delete on line 2. Keep one destructive command per call when you use a marker, and give a reason that explains why the value is safe.

## Registration and scope

**Q13. I installed the constitution. Is the guard active now?**
No. The constitution ships the hook but does not register it in any settings file. Until the operator adds the `PreToolUse` snippet (manual section 2) to a `settings.json`, nothing calls it. Only scripts that call `safe_rm_rf` are protected by the helper.

**Q14. What does the hook inspect?**
Bash commands, and the content of Write, Edit and MultiEdit calls when the file looks like something a shell executes (`.sh`, `.bash`, `.zsh`, `.ksh`, a shell shebang, `Makefile`, `*.mk`, `justfile`, CI yaml, Dockerfile `RUN` lines). Other tools, and Write of a file with no such name or shebang, are not inspected. A probe Write of a recursive delete in an unnamed, shebang-less text was allowed.

**Q15. What happens if the hook itself crashes or gets malformed input?**
It allows the call (exit 0) and prints a message: `WARNING — unparsable payload, allowing (cannot inspect)` or `ERROR — internal failure ...; allowing, the command was NOT inspected`. This is deliberate: Claude Code treats any non-2 exit as allow, and a guard that blocks on its own failure blocks all work. Watch stderr for these lines.

## safe_rm_rf

**Q16. Why did `safe_rm_rf` return 2 and delete nothing?**
It prints `safe_rm_rf: REFUSED <arg> — <reason>`. Common reasons: empty argument, root, a protected system path, `$HOME` or an ancestor of it, a protected `~/` child, the temp root, fewer than `SAFE_RM_MIN_DEPTH` components, outside `SAFE_RM_ALLOWED_ROOTS`, or a configuration problem. With several arguments, one bad argument means nothing is deleted.

**Q17. How do I test a script that needs a fake home?**
Do not reassign `HOME` from an expansion that can be empty. Create the sandbox with `mktemp -d`, check it, and pass the fake home with `SAFE_RM_EXTRA_HOMES="$SANDBOX/home"` so it is protected exactly like the real one. The shipped `test_safe_rm.sh` does this.

**Q18. How do I restrict deletions to my work area?**
Set `SAFE_RM_ALLOWED_ROOTS` (colon-separated absolute roots) for the call: `SAFE_RM_ALLOWED_ROOTS="$TMP_ROOT" safe_rm_rf "$TMP_ROOT/case1"`. A target outside every root is refused. If the variable is set but empty, every call is refused (fail closed), so unset it rather than clearing it.

**Q19. Why can I delete `$HOME/proj` but not `$HOME/.cache`?**
`.cache` is a protected home child in `protected_paths.list` (an exact match below each home), `proj` is not. Deeper paths under a protected child are not refused by the list either, so `~/.cache/x/y` depends on the depth rule and the allow-list.

**Q20. `safe_rm_rf` refuses everything with "protected list not readable". What is wrong?**
`protected_paths.list` must sit next to the real `safe_rm.sh`. The library also refuses to trust the list when it is eval-loaded, sourced from text, or sourced under another file name. Source the real file by path.

**Q21. Does `safe_rm_rf` make a bare `rm -rf` in my script safe?**
No. It protects only calls routed through it. The hook is the layer that looks at direct deletes, and only when registered.

## What it cannot see

**Q22. What can still slip through the hook?**
By measurement or by its own header: a guard placed after the use (`rm -rf "$1/x"; : "${1:?}"` was allowed), a guard in a dead branch, an uncalled function or a subshell whose `exit` does not stop the parent; an alias; partial values from command substitution (`y=$(echo foo); rm -rf "$y/b"` was allowed); `declare -n` namerefs; `{a..b}` brace ranges; `source` of a file that already exists on disk (the guard does not open files); a command built from a decoded string; a downloaded script; a binary; a language runtime deleting through its own API. It is a text scan at the tool-call boundary, not a security boundary.

**Q23. Is this a replacement for backups and permissions?**
No. File-system permissions, pre-operation backups (§9.2) and the host-safety rules (§12) still apply. The guard lowers the chance of one empty variable becoming an unbounded delete; it does not undo one.

**Q24. The guide says 32 safe_rm cases; this FAQ says 138. Which is right?**
Both were true of different copies. The guide has since been corrected to 138; the older 32 came from an earlier staged version of `safe_rm.sh`, and the implementation measured on 2026-10-24 reports 138 cases for `scripts/lib/test_safe_rm.sh`. Run the tests on the copy you ship and trust that number.
