# Destructive-Path Safeguard FAQ

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-10-24 |
| Last modified | 2026-10-27T09:00:00Z |
| Status | active |
| Status summary | Questions and answers drawn from behaviour of `scripts/hooks/guard-destructive-paths.py` and `scripts/lib/safe_rm.sh` as run on 2026-10-24 and re-run on 2026-10-26 (65 guard cases, 921 bypass cases and 267 `safe_rm_rf` cases passed). Where an answer states an exit code it was reproduced by feeding a hook payload built in Python. |
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
The guard cannot know what a variable holds at run time. It accepts a variable as guarded when the text has `${VAR:?msg}`, a `[ -n "$VAR" ]` test whose failure branch leaves, or a literal or `mktemp` assignment. A variable from `$1`, `read` or `mapfile`, an indirect expansion or `$(...)` that is not guarded is blocked as class V when it is deleted under; a `for` loop over literal words is judged on the words (so `for t in /home` is class P), over unknown words it stays unknown. Fix: write `"${VAR:?need a directory}"` at the use. In the probe, `W="${1:?need dir}"; rm -rf "$W/build"` was allowed and `rm -rf "$1/build"` was blocked.

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
Class X. If the text cannot be parsed reliably (unterminated quote, `$(`, backtick or heredoc) and it contains a destructive command, the guard fails closed. Without a destructive command in the text, parse problems do not block. Class X is also what the degraded check (Q12a) reports for a recursive or forced delete it cannot judge, or a command word it cannot resolve that is used with a recursive or force flag or a protected path; and it is what an internal guard failure or a non-string command or content reports (Q15).

**Q8a. My script uses arithmetic such as `x=$((a * b / 2))`. Can it be blocked?**
Not for the arithmetic (changed in review round 4). Bash evaluates `$((...))` as an expression and runs nothing inside it, so the guard never treats `*`, `/` or any other operand as a command or a target. Only a command substitution inside the arithmetic is analysed: `x=$(( $(rm -rf /) + 1 ))` is still class P. One limit: after 2,000,000 characters of arithmetic in one call (`ARITH_SCAN_LIMIT`) the guard reads `$((` the way bash reads `$(` plus a subshell, and may then report a class V that a marker overrides.

## Overrides

**Q9. How do I override a block?**
For classes H, V and U only, add a real top-level comment `# guardrails:allow <reason>` with a non-empty reason, for example `... # guardrails:allow scratch test in sandbox`. The findings are then printed as warnings and the call is allowed. The reproduced incident script with a marker returned rc 0, without it rc 2.

**Q10. Why is class P not overridable?**
Because a protected target is wrong whatever the reason given, and a text marker is trivially added by whoever (or whatever) wrote the command. In the probe, deleting `/` with a marker still returned rc 2. Class X is also not overridable: a marker cannot make unparsable text safe. The gate `cm_guard_class_p_not_overridable.sh` and its mutation test exist to keep it that way.

**Q11. I put the marker in an `echo "..."`, inside `bash -c` or a heredoc and it did nothing. Why?**
Only a real comment at the top level of the command counts. Text inside quotes, heredoc bodies, `bash -c`, traps and `$(...)` does not. A marker with no reason after it does not count either (rc 2 in the probe).

**Q12. Does the marker cover only the command next to it?**
No. It is payload-global. One marker anywhere at top level downgrades all H, V and U findings in the same tool call. In the probe, a marker on line 1 allowed a second unguarded delete on line 2. Keep one destructive command per call when you use a marker, and give a reason that explains why the value is safe.

**Q12a. A very long or deeply nested command is blocked with "analysis budget ran out". Why, and how do I allow it?**
The full analysis stops after 4,000,000 characters of cumulative work, 3,000 function expansions, a string re-parsed as code more than 5 levels deep (eval, `sh -c`), a total nesting of substitutions and function calls deeper than 40 (review round 4: function calls and `$(...)` no longer count towards the 5 levels, because ordinary libraries chain them deeper), or a 25 s last-resort clock (rewritten in review round 3; the old limits were 600,000 characters and 6 s, which made real scripts depend on host speed). Then one degraded check reads the whole text. It keeps class P, blocks with class X (not overridable) any recursive or forced delete it cannot judge and any command word it cannot resolve that is used with a recursive or force flag or a protected path, and reports any other uncertain delete, or an unresolvable command word next to a destructive word, as class U. Since review round 4 it splits statements with the same quote-aware tokenizer as the full analysis, so a quoted awk program (`'$0 ~ /x/'`) is no longer read as a command. Deletes of literal scratch paths and of `mktemp` values stay allowed. Measured 2026-10-26: a 4.1 MB padded command with `d=$(mktemp -d); rm -rf "$d"` is allowed, the same padding with `rm -rf /home`, a split verb or a `/home` variable is blocked in about 3 s, and the repository's own large scripts get the same verdict on every run. For class U only, a `# guardrails:allow <reason>` on line 1 (line 2 after a shebang) allows it; a marker further down does not count here, because the guard may not have read it. Do not set `GUARD_TIME_BUDGET` in the hook environment: it can only shorten the clock (0 to 25 s) and exists for tests.

**Q12b. Why is `rm -rf "$(cat list)"` blocked when the list is fine?**
The guard cannot compute the output of `cat`, so the whole target may be empty or anything (class V, overridable). Only a small set of substitutions is evaluated (`echo`, literal `printf`, `pwd`, `dirname`, `basename`, `realpath`, `readlink -f`, `which`, `command -v`; `mktemp` is trusted). Read the list into a variable guarded with `${var:?}` instead, or add a reasoned marker.

## Registration and scope

**Q13. I installed the constitution. Is the guard active now?**
No. The constitution ships the hook but does not register it in any settings file. Until the operator adds the `PreToolUse` snippet (manual section 2) to a `settings.json`, nothing calls it. Only scripts that call `safe_rm_rf` are protected by the helper.

**Q14. What does the hook inspect?**
Bash commands, and the content of Write, Edit and MultiEdit calls when the file looks like something a shell executes (`.sh`, `.bash`, `.zsh`, `.ksh`, a shell shebang, `Makefile`, `*.mk`, `justfile`, CI yaml, Dockerfile or Containerfile `RUN` lines). `NotebookEdit` and MCP shell or file tools (for example desktop-commander) are not inspected at all, and neither is Write of a file with no such name or shebang. Edit of such a file is scanned only when its on-disk head shows a shell shebang. A probe Write of a recursive delete in an unnamed, shebang-less text was allowed.

**Q15. What happens if the hook itself crashes or gets malformed input?**
It fails closed. An internal failure during the analysis is class X (`internal failure in the guard ... blocked (fail closed)`), and the degraded check still runs; an exception that escapes the analysis makes the hook exit 2 (`ERROR — internal failure ...; BLOCKED`). A Bash command or Write/Edit content that is not a string is class X too. The one exception is a payload that is not JSON at all: it carries no tool input to inspect, so it is allowed with `WARNING — unparsable payload, allowing (cannot inspect)` on stderr. The cost, stated honestly: a guard defect can block harmless commands until it is fixed (§11.4.201(4)); the false-positive survey over real scripts is the check against that.

## safe_rm_rf

**Q16. Why did `safe_rm_rf` return 2 and delete nothing?**
It prints `safe_rm_rf: REFUSED <arg> — <reason>`. Common reasons: empty argument, root, a protected system path, `$HOME` or an ancestor of it, a protected `~/` child, the temp root, fewer than `SAFE_RM_MIN_DEPTH` components, outside `SAFE_RM_ALLOWED_ROOTS`, or a configuration problem. With several arguments, one bad argument means nothing is deleted.

**Q17. How do I test a script that needs a fake home?**
Do not reassign `HOME` from an expansion that can be empty. Create the sandbox with `mktemp -d`, check it, and pass the fake home with `SAFE_RM_EXTRA_HOMES="$SANDBOX/home"` (and `SAFE_RM_EXTRA_HOME_ROOTS` for a directory whose children are homes) so it is protected exactly like the real one. The shipped `test_safe_rm.sh` does this.

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

**Q22a. Which destructive commands does the guard not model at all?**
Measured 2026-10-26 (all allowed, rc 0): `mkfs.ext4 /dev/sda1`, `wipefs -a /dev/sda`, `echo x > /dev/sda`, `shutil.rmtree` inside a Python script FILE (since review round 6 an inline `python3 -c`/`node -e`/`perl -e` with a literal protected path is class P and with a computed path class V), `alias zap='rm -rf'; zap /home`, `declare -n`, and a relative computed target (`y=$(echo foo); rm -rf "$y/b"`). `git clean -fdx` is checked only when its directory is known (`-C` or a preceding `cd`). `dd of=/dev/sda` and `shred /dev/sda` are class P.

**Q23. Is this a replacement for backups and permissions?**
No. File-system permissions, pre-operation backups (§9.2) and the host-safety rules (§12) still apply. The guard lowers the chance of one empty variable becoming an unbounded delete; it does not undo one.

**Q24. The guide once said 32 safe_rm cases; this FAQ says 151. Which is right?**
Both were true of different copies. The guide has since been corrected; the older 32 came from an earlier staged version of `safe_rm.sh`, and the implementation measured on 2026-10-24 reported 151 cases for `scripts/lib/test_safe_rm.sh` (267 when re-measured on 2026-10-27). Run the tests on the copy you ship and trust that number.

**Q25. Why is `rm -rf /tmp/*` class P (no marker) but `rm -rf ~/.cache/*` class V (marker allowed)?**
Deliberate (review round 6, M8/M9). `/tmp` is a system directory shared by every user and process on the host, so its contents are never ours to wipe in bulk: use `rm -rf /tmp/build-*` or a `mktemp -d` value. `~/.cache` is the invoking user's own cache; a bulk delete of its contents is plausible and recoverable, so it is overridable with a reasoned `# guardrails:allow <reason>`. The tests assert the class of both.

**Q26. Why was `rm -rf "$W"` blocked when `W` is set nowhere in the file?**
Review round 6: a recursive delete of a whole target that is a variable the analysed text never assigns is unknown (the caller's environment decides it), so it is class V and a reasoned marker allows it. A variable that is assigned anywhere (`mktemp`, a `read` loop) is not flagged; measured on this repository and one consumer repository the rule added no block here and one genuine one there.

## Why is `env -C / rm -rf home` blocked, and what still gets through?

The guard tracks the working directory as state. `env -C /`, `sudo -D /`, `run0 --chdir=/`, `cd $UNSET`, `pushd`, `popd` and a `CDPATH` lookup either set a literal cwd or mark it lost, and with a lost cwd a relative target such as `home` or `*` (recursive) blocks. `env -C /tmp rm -rf build` stays allowed. Not modelled: ssh, interpreter `-c`, unlisted wrappers (strace, ltrace, gdb, faketime, proot, firejail, bwrap, machinectl shell, container exec), inherited `CDPATH`, a failed `cd`, `shopt cdable_vars`, sourced scripts, Write/Edit cwd.

## Why was `su --command='rm -rf /home'` not blocked before, and is everything blocked now?

It was missed because only the short `-c STRING` form was read. Round 3 normalises the long and attached spellings for `su`, `runuser`, `flock`, `sg` and `script`, and adds more wrappers. Not everything is blocked: a string sent to a remote host and a string inside an interpreter program stay out of scope, and a wrapper that is not in the guard's tables is not unwrapped. The guard is a best-effort tripwire, not a security boundary.

## What happens when the hook receives a payload that is not valid JSON?

The guard scans the raw text and the tolerantly extracted `command`, `content` and `new_string` values. A visible destructive command blocks (exit 2); otherwise it warns and allows, because the intent cannot be known.

## Does `${VAR:?}` make `rm -rf "${VAR:?}/x"` safe, and what about `cd "$(dirname "$0")" && rm -rf lib`?

`${VAR:?}` only stops an empty or unset variable. A variable that holds the wrong value (`/`, a parent directory) passes it, so the guard still looks at the text. `cd "$(dirname "$0")" && rm -rf lib` is allowed: the cwd is LOST after the command substitution, but `lib` is not a protected tail (`home`, `Projects`, `usr`); the same line with `rm -rf *` blocks. Use a literal `cd` or an absolute path when you want the guard to be certain.

## Do `cd` in a pipeline, `eval`, `pushd +1` and `xargs -I%` change the verdict?

Yes. A `cd` inside a pipeline element runs in a subshell and does not move the outer shell. `eval 'cd /'` moves the current shell and its text is also scanned. `pushd +N` and `pushd -N` mark the cwd LOST. A custom replace string (`xargs -I%`, `-J%`, `--replace=%`, `parallel -I%`) stands for the piped item, so `echo /home | xargs -I% rm -rf %` blocks while `echo /tmp/a | xargs -I% rm -rf %` is allowed. Still not modelled: ssh and interpreter `-c`, unlisted wrappers (strace, gdb, faketime, firejail, bwrap, `machinectl shell`, container exec), inherited `CDPATH`, a failed `cd`, `cdable_vars`, sourced scripts, Write/Edit without cwd.
