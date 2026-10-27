# Destructive-Path Safeguard — keep an empty variable from deleting a home directory

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-10-23 |
| Last modified | 2026-10-27T09:00:00Z |
| Status | active |
| Status summary | How to register and use the PreToolUse guard `scripts/hooks/guard-destructive-paths.py` and the runtime helper `scripts/lib/safe_rm.sh`, what they block, what they cannot see, and how to test them. |
| Authority | Constitution §11.4.287. The canonical text in `Constitution.md` wins over this guide. |
| Scope | Universal (§11.4.17). Paths below are examples; the consumer supplies its own protected children and allowed roots. |
| Issues | none |
| Issues summary | — |
| Fixed | — |
| Fixed summary | — |
| Continuation | — |

Related: [manual](../manuals/destructive_path_safeguard_manual.md) (install, classes, escape hatch, `safe_rm_rf` configuration, troubleshooting, decision-flow diagram) · [FAQ](../faq/destructive_path_safeguard_faq.md)

## Table of contents

1. [Why it exists](#1-why-it-exists)
2. [What the guard blocks](#2-what-the-guard-blocks)
3. [Register the guard](#3-register-the-guard)
4. [Use the runtime helper](#4-use-the-runtime-helper)
5. [Script rules](#5-script-rules)
6. [Test it](#6-test-it)
7. [What it cannot see](#7-what-it-cannot-see)

## 1. Why it exists

On 2026-10-23 a review subagent ran a scratch script of the shape `W="$2"; export HOME="$W/home"; rm -rf "$HOME"` with empty arguments. `$W` was empty, `$HOME` became `/home`, and a recursive delete ran with the operator's rights until a timeout stopped it. One empty variable became an unbounded delete, and no rule refused it. Two layers now do.

## 2. What the guard blocks

| Class | Shape | Overridable |
|---|---|---|
| P | A recursive delete, `chmod -R`, `chown -R`, `find -delete` or `rsync --delete` aimed at the root, a system directory, `/home`, a user home, `$HOME`, `~`, an ancestor of `$HOME` or a protected child of it | Never. The allow marker does not downgrade it. |
| H | `HOME` reassigned from an unguarded expansion, then a recursive delete under it (the incident) | Yes, with `# guardrails:allow <reason>` |
| V | A recursive delete of a variable derived from an unguarded positional parameter | Yes, with `# guardrails:allow <reason>` |

A variable counts as guarded by `${VAR:?msg}`, by a `[ -n "$VAR" ] || exit` test, or by a literal or `mktemp` assignment. Text that cannot be parsed is allowed with a warning only when it contains no destructive command; with one, it is class X. An internal guard failure blocks (class X, fail closed); only a hook payload that is not JSON at all is allowed with a warning.

## 3. Register the guard

The guard reads the Claude Code hook JSON on stdin; exit 0 allows, exit 2 blocks and prints the reason. Add it to the consumer's `settings.json` (shown, not applied by the constitution; editing a user's settings needs that user's consent):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "python3 -I /path/to/constitution/scripts/hooks/guard-destructive-paths.py" }
        ]
      }
    ]
  }
}
```

Check it is live with a probe that must exit 2: pipe `{"tool_name":"Bash","tool_input":{"command":"<recursive delete of /home>"}}` into the command above.

## 4. Use the runtime helper

```bash
. /path/to/constitution/scripts/lib/safe_rm.sh
safe_rm_rf "${WORKDIR:?}/build"      # refuses empty, relative, system, home, ancestor-of-HOME and shallow targets
SAFE_RM_ALLOWED_ROOTS="$TMP_ROOT" safe_rm_rf "$TMP_ROOT/case1"   # optional second barrier
```

It returns 2 and deletes nothing on any refusal, and it validates every argument before deleting the first. `SAFE_RM_MIN_DEPTH` (default 3) sets the shallowest path it accepts. `SAFE_RM_EXTRA_HOMES` declares extra home directories (for a test fake home) and `SAFE_RM_EXTRA_HOME_ROOTS` extra directories whose direct children are homes, like `/home`; both are treated exactly like the real home.

## 5. Script rules

1. Expand a variable that names a path to delete as `"${VAR:?message}"`. An empty variable is still set, so `set -u` is not enough.
2. Never reassign `HOME` from an expansion that can be empty. A test that needs a fake home creates it with `mktemp -d` and checks it.
3. A test that deletes anything runs inside a sandbox whose root it created.
4. A brief for a subagent that may write scratch scripts states rules 1 to 3.
5. A block by the guard is a defect in the script. Fix the script; do not look for a way around the guard.

## 6. Test it

```bash
bash scripts/hooks/test_guard_destructive_paths.sh   # 65 cases, two paired mutations
bash scripts/lib/test_safe_rm.sh                     # 267 cases, one paired mutation, fake HOME in a sandbox
bash scripts/gates/cm_guard_class_p_not_overridable.sh
bash scripts/gates/cm_guard_class_p_not_overridable_mutation_test.sh
```

Measured 2026-10-27 (re-run after fix round 6): 65 passed and 0 failed (guard), 2429 passed and 0 failed (`python3 -I scripts/hooks/test_guard_bypasses.py`), 267 passed and 0 failed (`safe_rm`); the mutation test reports every mutant caught.

## 7. What it cannot see

The guard is a text scan, not a security boundary. It cannot see a command built at run time from a decoded string, a downloaded script, a binary, or a language runtime deleting through its own API (inline `python3 -c`/`node -e`/`perl -e` code is read; script files an interpreter runs are not). Also unmodelled: namerefs, array appends, extglob, scripts written with `echo >` and run later, environment inherited from the parent, `IFS` tricks, a Unicode slash, non-recursive `rmdir`/`unlink`. The payload `cwd` is the start directory for relative targets. It does not replace file-system permissions, backups (§9.2) or the host-safety rules (§12). `safe_rm_rf` protects only the calls routed through it.

## Known limits after review round 7 (best-effort tripwire)

The guard is a best-effort tripwire, not a security boundary. Round 7 (the last permitted review round) found seven bypass classes that are documented and not fixed: bash bracket globs (`[^...]`, `[[:class:]]`); `$(...)` evaluation (printf/echo escapes, trailing newline, `cd .. && pwd`); exec wrappers not on the fixed list; interpreter shell-out (`python3 -c` os.system or subprocess, `perl -e`, `node -e`); `tar --remove-files`; `shred -u` of a single file inside a protected child; a deep `../` chain in a Write script or a payload without cwd; a symlinked cwd combined with a glob. A tracked new item (OWED-GATE-156 to OWED-GATE-160) owns the structural replacement. The former `GUARD_R7_UV_OFF` survey switch was removed: the never-assigned-target rule is unconditional and has no environment switch. `safe_rm_rf` reads `protected_paths.list`, which is smaller than the guard's built-in set (Documents, Desktop, Downloads, Pictures, Music, Videos, Obsidian, bin, go, opt, Android, .git, .aws, .kube, .docker, .password-store are not in it), so the two are not a single source. Class V findings for a never-assigned variable (`rm -rf "$BUILD_DIR"`) and for a function argument are by design overridable with the audited marker.

## Fix round 3 (review round 2, F3 and F4): wrapper spellings and non-JSON payloads

Wrappers that carry a shell string are normalised in one function (`shnorm`) before the scan, so these spellings are all read as `-c STRING`: `su`, `runuser`, `flock`, `sg` and `script` with `--command STR`, `--command=STR`, `--session-command[=STR]` and the attached `-cSTR`; `env -S`, `--split-string=` and `-SSTR`; and `taskset -c0` or `--cpu-list=`. `unshare`, `nsenter`, `setpriv`, `prlimit`, `numactl`, `gosu`, `su-exec`, `fakeroot` and `eatmydata` are unwrapped with their option tables, and `ash`, `hush`, `fish`, `csh`, `tcsh`, `mksh`, `rbash` count as shells. Measured with the committed 75-spelling battery (`scripts/hooks/spelling_battery_report.py`, output `docs/qa/destructive_path_spelling_battery_output.txt`): 75 destructive rows blocked, 75 benign twins allowed. The two that remain are by design out of scope: a destructive string sent to another host (`ssh host 'rm -rf /home'`) and a string embedded in an interpreter program (`python3 -c "os.system('rm -rf /home')"`, which is already a listed bypass class). Other limits that stay: a wrapper or option that is not in the tables is not unwrapped, and `script -qcSTR` is now split into `-qc` plus the string.

A payload that is not valid JSON is no longer ignored. The guard extracts the `command`, `content` and `new_string` values with a tolerant scanner (an unterminated last value included) and scans them and the raw text; a destructive command that is visible blocks with exit code 2 and the message that the payload is not valid JSON but a destructive command is visible. Anything else is still allowed with a warning. That allow-by-default is a recorded tension with the conservative-safe default of section 11.4.201(4): when the payload cannot be parsed and nothing destructive is visible, the intent is unknowable, and refusing every malformed payload would stop all work.

## Fix round 4 (review round 3, R3-1): the working directory is state

The guard asks "where does this command run?" instead of listing spellings. The cwd is carried as KNOWN (a literal path), none (no cwd in the payload) or LOST (a construct moved the shell somewhere the text cannot resolve). `env -C`/`--chdir`, `sudo -D`/`--chdir`, `run0`, `systemd-run --working-directory`, `unshare -w` set it to their literal argument; `sudo -i`/`-R`, `su -`, `pkexec`, `nsenter`, `chroot`, `popd`, a bare `pushd`, `cd $UNSET`, `cd "$(cmd)"` and a `CDPATH` lookup mark it LOST. While it is LOST, a relative destructive target blocks if it walks `..`, is a whole-directory token of a recursive delete, or its components equal the tail of a protected path (`home`, `Projects`, `usr`); `build` and `dist/out` stay allowed. Remedies: cd to a literal path, guard with `${VAR:?}`, or use an absolute path.

Limits that remain (documented, not closed): a destructive string run on another host (`ssh`) or inside an interpreter (`python -c`); an unlisted wrapper that changes directory (strace, ltrace, gdb, faketime, proot, firejail, bwrap); an inherited `CDPATH` that the text does not set; a failed `cd` (the shell stays put); `shopt cdable_vars`; sourced scripts; Write/Edit payloads, which carry no cwd. A wrapper not in the table is assumed to keep the cwd. Added in fix round 6: a bare `cd` goes to the HOME the command text assigned (`HOME=/; cd; rm -rf usr` is blocked); a `/proc/<pid>/root` path is judged as `/` (textually, so a foreign pid's root is judged as the filesystem root too) and a glob is resolved through its glob-free prefix; `/proc/<pid>/cwd` is treated as a LOST directory; a `trap` body containing `cd`/`pushd`/`popd` marks the directory LOST (a body built from a variable, `trap "$X" DEBUG`, is not read); after an unknown wrapper option the first later destructive command word is taken as the command, which is a false positive for text such as `env -P x echo rm`.

## Fix round 5 (review round 4): option parsing, pipelines, eval, pushd, custom replace strings

- Wrapper options are parsed the way getopt does (one table per wrapper: `env`, `sudo`, `su`, `nice`, `timeout`, `xargs` and the rest). Clustered letters (`sudo -Eu root`, `env -vC /`, `env -iC /`, `sudo -nD /`), attached values (`-C/`, `-D/`, `--chdir=/`) and long spellings are read by the same code that strips the wrapper and that computes its working-directory effect, so the two can no longer disagree. A letter that is not in a wrapper's table is kept as an unknown option, never swallowed.
- A `cd` inside a pipeline element runs in a subshell and does not move the outer shell: `cd / | cat; rm -rf build` does not mark the outer cwd as moved. `eval 'cd /'` runs in the current shell, so its cwd effect and its text both count. `pushd +N` / `pushd -N` rotate the stack to a directory the text does not name, so they mark the cwd LOST.
- `xargs -I%`, `-J%`, `--replace=%` and `parallel -I%` / `--replace=%` use a custom replace string. That string stands for the piped item, not for a literal path, so `echo /home | xargs -I% rm -rf %` blocks (found by the round-5 own battery, before this fix it was allowed).
- Caveats that stay (documented, not closed). `${VAR:?}` only guards an EMPTY or unset variable, not a WRONG value: `X=/ ; rm -rf "${X:?}home"` is not stopped by the shell and is only seen by the guard when the text names the value. `cd "$(dirname "$0")" && rm -rf lib` is allowed: the cwd becomes LOST but `lib` is not a protected tail; `cd "$(dirname "$0")" && rm -rf *` blocks. The remaining unmodelled cases are the ones listed above: ssh and interpreter `-c`, unlisted wrappers (strace, ltrace, gdb, faketime, proot, firejail, bwrap, `machinectl shell`, container `exec`), inherited `CDPATH`, a failed `cd` (`cd /nonexistent || rm -rf home` is allowed because the shell stays where it was), `shopt cdable_vars`, sourced scripts, and Write/Edit payloads that carry no cwd.
