# install_agent_label_defs.sh — install label agent types into a project

**Revision:** 4
**Last modified:** 2026-10-15T03:50:00Z
**Authority:** constitution submodule §11.4.182 clause (8) · §11.4.231 (F.5) · §11.4.164 (post-update registration seam) · §11.4.177 (inherited by reference) · §11.4.201 · §11.4.18
**Classification:** universal (§11.4.17)

## What it does

Generates the label agent types of the **current checkout** into
`<project>/.claude/agents/` with `gen_agent_label_defs.sh`:

- **Identity** — track, branch and Claude Toolkit alias come from
  `track_branch_label.sh`, run in `--project-root` on **every** run (nothing is
  cached): track = T1 on `main`/`master`, else `/mnt/track<N>`; branch = that
  checkout's own HEAD (never a mount or an enclosing repository); alias = the
  `CLAUDE_CONFIG_DIR` basename `.claude-<alias>`. If any of the three is `?`,
  the installer **refuses with exit 6 and writes, prunes and edits nothing**.
  `--identity <N>:<branch>:<alias>` supplies the triple explicitly instead (a
  `?` field is refused).
- **Default set** — `sonnet-medium, sonnet-high, opus-high, opus-xhigh`;
  `--types` / `--all-types` choose others.
- **Several aliases, one checkout** — topology probe (2026-10-15, reference
  host): `git worktree list` shows ONE T1 checkout; T2-T4 are separate clones,
  each with its own `.claude/agents` and `.git/info/exclude`. The conductor stays
  on the T1 checkout and every trunk session is T1, so several aliases share it:
  its `.claude/agents` holds claude1, claude4 and claude5 types side by side
  (conductor configured as claude1, the live session running as claude4). A
  session's alias can also change on resume. The installer cannot tell a retired
  alias from a live session of another alias, so **ownership decides**: a
  generated file belongs to the alias in its description label (`gen
  --owner-alias`). A run prunes only round-1 (v1) files and its OWN alias's
  generated files that are no longer desired (old branch, track or type),
  together with their `.html`/`.pdf`/`.docx` export siblings. Another alias's
  generated types are **never** pruned (ownership is EXACT equality of the
  sanitised aliases, so `kimi` and `kimi-for-coding` never touch each other).
  A hand-made file is never touched; a hand-edited superseded file of this
  alias is kept with a WARN.
- **Retiring an alias** — `install_agent_label_defs.sh --remove-alias <alias>`
  (add `--dry-run` to see the plan) removes ONLY that alias's GENERATED, unedited
  files with their export siblings, keeps its hand-made and hand-edited files and
  every other alias's files, and refreshes the exclude block. It needs no live
  identity. It is a separate mode: only `--project-root`, `--out-dir`,
  `--dry-run` and `--no-git-exclude` are accepted with it; any other flag
  (`--check`, `--no-prune`, `--identity`, `--types`, `--all-types`) is refused
  with exit 2 before anything is read or touched (so `--remove-alias --check`
  can never delete). Do
  not use `rm .claude/agents/T1-main-<alias>-*`: that would also delete that
  alias's hand-made files and leave the exclude block stale.
- **Other tracks** — not generated here. Each track's worktree generates its
  own types on its own hook run. Another track's alias cannot be derived from
  this session, and the multitrack config does not reliably name the real
  checkout (measured on the reference host: `worktree_subdir: atmosphere` while
  the checkouts are `/mnt/trackN/atmosphere-tN`). The multitrack config is not
  an input: a malformed or unreadable config can neither change nor prune
  anything.
- **git** — unless `--no-git-exclude`, a managed block in the repository's
  `.git/info/exclude` (local, never committed) lists
  EVERY generated file in the directory — any alias, v1 or v2, genuine or
  hand-edited — and their `.html`/`.pdf`/`.docx` export siblings, rebuilt from
  the directory on every run, so files kept by `--no-prune`, kept hand-edited
  files and other aliases' types all stay out of a `git add -A` commit. Linked
  worktrees share one `info/exclude` (the common git dir; separate clones do
  not), so the block is keyed by the ABSOLUTE out-dir path — one block per
  worktree and directory — and its begin/end lines are matched by exact
  full-line equality (`# >>> agent-label-defs v2 <abs-path>` /
  `# <<< agent-label-defs v2 <abs-path>`). One grammar covers every block
  state: a managed begin line pairs ONLY with the first matching end line that
  comes before the next managed begin line of any key. A paired block of this
  directory (or an older round-3/4 block of the same relative directory) is
  replaced; a begin with no such end is a lone marker and only that line is
  dropped, so an unterminated block never swallows the user's lines or another
  directory's block; an end line of this directory that closes nothing is
  dropped. Keys are compared byte-exactly (they reach `awk` through `ENVIRON`,
  never `-v`, which would interpret backslashes) and nothing is stripped from a
  key; a trailing CR on a FILE line (a CRLF-converted exclude file) is ignored,
  which can only make this directory's own rewritten marker match, because no
  key can contain a CR (see the path rule below). The shared file is rewritten
  only under `flock` (util-linux, REQUIRED: without it the installer refuses
  with exit 8 before writing or pruning anything; `--no-git-exclude`,
  `--check` and `--dry-run` need no lock) and is replaced atomically (temp file
  + rename), so concurrent installs in linked worktrees never lose a block. A
  holder killed while it holds the lock releases it with its death (kernel
  `flock`), and its leftover temp file is removed by the next install; a live
  holder makes the next install warn and skip the block after
  `AGENT_LABEL_LOCK_WAIT` seconds (default 30). A block whose directory no
  longer exists and lies under no `git worktree list` worktree (a removed
  worktree, a moved checkout) is collected, begin line, entries and end line; a
  worktree that is moved away or unmounted but still listed by git keeps its
  block. Gitignore metacharacters in the path are escaped. Enumerated and
  tested states: none, empty block, complete, duplicated, unterminated, nested,
  reordered (end before begin), CRLF, backslash path, glob characters in the
  path, a 5000-line file, 100 concurrent linked-worktree install pairs, 3
  widened-window pairs, a killed and a live lock holder, a killed holder's temp
  file, stale block of a removed worktree, unmounted still-listed worktree.
- **Paths and option values** — one rule each. Every path (`--project-root`,
  `--out-dir`, as given and as resolved, including through a symlink) is
  refused with exit 2, before anything is written, if it contains any control
  character (`[[:cntrl:]]` in the C locale: TAB, LF, CR and every other byte
  0x01-0x1f, and 0x7f); a NUL cannot reach the script at all (the shell drops it
  from argv). Every option that takes a value (`--project-root`, `--out-dir`,
  `--identity`, `--types`, `--remove-alias`) refuses a missing value, an empty
  value and a value starting with `-` with exit 2 naming the option, so a
  forgotten value never swallows the next flag (write a path that starts with
  `-` as `./-name`). The generator applies the same two rules to its own
  options.
- **Opt-out** — `AGENT_TYPE_LABEL_DEFS=off` (or `0`/`false`/`no`), or a file
  `<out-dir>/.agent-label-defs-disabled`: nothing is written or pruned.

## Usage

```bash
bash constitution/scripts/multitrack/install_agent_label_defs.sh [--project-root DIR]
  [--out-dir DIR] [--identity N:branch:alias] [--types m-e,...|--all-types]
  [--check] [--dry-run] [--no-prune] [--no-git-exclude]
bash constitution/scripts/multitrack/install_agent_label_defs.sh --remove-alias <alias>
  [--project-root DIR] [--out-dir DIR] [--dry-run] [--no-git-exclude]
```

Exit codes: `0` ok (or opted out) · `1` drift (`--check`) · `2` usage · `3` a
hand-made file collides (left untouched) · `4` a hand-edited generated file
(left untouched) · `5` internal error · `6` identity unresolvable (nothing
touched) · `7` bash older than 4 · `8` flock (util-linux) missing while the
exclude file would be written (nothing written or pruned). `--dry-run` and `--check` write, prune and edit
nothing. Requires **bash >= 4**.

## Wiring

`scripts/post_update_hook.sh` STEP 4c runs it on **every** constitution pull and
then runs the `CM-AGENT-TYPE-LABEL` gate as a health check. Every outcome is
non-fatal there (collision, unknown identity — for example a pull run outside a
Claude Toolkit session — or bash < 4 are warnings).

## Load boundary (§11.4.6)

When new or changed definitions become dispatchable is decided by the agent
platform. **No load time is guaranteed.** Measured:

| When | Session | Write | Result |
|---|---|---|---|
| round 1 | headless | temp + rename | dispatchable after about 2 min |
| review round 1 | interactive | temp + rename | not found after 11 min; replaced definitions kept serving stale descriptions |
| 2026-10-15 | interactive | temp + rename | written about 03:29, available about 03:39 (about 10 min) |
| 2026-10-15 (same subagent, later) | resumed subagent session | another session's temp + rename (22:34 UTC) | the new types appeared in the agent list at about 23:06 UTC (about 32 min) |
| 2026-10-15 (round-2 probe) | resumed subagent session | one file in-place, one temp + rename | neither found in 15 min (5 tries, 22:44-22:59 UTC); files another session wrote 24 min earlier were not visible either |

Round-2 probe finding: the write method (in-place vs temp + rename) made no
difference; the session in which the dispatch happens decides. The registry
refreshes on its own schedule (here after about 32 minutes). The generator keeps temp + rename
(no reader ever sees a half-written file).

After an install that changed files, restart the session (or wait for the
registry to refresh) before dispatching the new types; under
`AGENT_TYPE_LABEL_ENFORCE=1` the guard never blocks a catch-all dispatch when
only types of another (stale) identity exist.

## Tests

`test_install_agent_label_defs.sh` (161 cases, including the hook wiring in a
hermetic fixture constitution and a bash < 4 stand-in for the hook); gate
`CM-AGENT-TYPE-LABEL`.

**Last verified:** 2026-10-15.
