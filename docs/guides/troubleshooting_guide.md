# Troubleshooting Guide - installer, updater, hooks, extensions

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T10:30:00Z |
| Status | draft |
| Status summary | Symptom to cause to fix, built from the scripts' own messages and exit codes. Reconciled with the scripts on 2026-10-29; not verified by live failure injection. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Anyone whose install, update, hook or extension command failed. |
| Issues | none |

Start with the exit code, then the last message printed. Backups are in `.constitution-install-backup/<timestamp>/`.

## Installer (`install_constitution.sh`)

| Symptom | Exit | Cause | Fix |
|---|---|---|---|
| "needs bash 4.4" | 3 | older bash (macOS ships 3.2) | install a newer bash, run `bash install_constitution.sh` with it |
| "not a git repository" | 3 | no repo | `git init` yourself or pass `--git-init` |
| refuses the target | 3 | the directory is the constitution repository itself | run it in your own project; if your project only uses the constitution and has its own `Constitution.md`, add `--not-constitution-repo` |
| "another installer run (pid N) holds ...lock" | 3 | a live installer | wait; a stale lock (owner gone) is reclaimed automatically; a lock that is not a regular file must be removed by you |
| no reachable upstream | 3 | network, or mirror down | `--upstream KEY` (`gitlab`, `gitlab-vasic`, `gitflic`, `gitverse`, `github-vasic`) or `--upstream-url`; the private `m3w` Gitea needs SSH keys and is not an installer upstream |
| ssh options ignored | - | `GIT_SSH_COMMAND` is no longer inherited | put keys/ports in `~/.ssh/config` |
| insecure URL refused | 2 | `http://` or `git://` | use https/ssh, or `--allow-insecure-url` knowingly |
| "limit the agent cannot enforce" | 2 | `--model`/`--effort` given for `kimi`, `opencode`, `pi` | drop those flags |
| no terminal | 2 | piped without `--non-interactive` | add `--non-interactive` |
| agent failed | 4 | `result` event had `is_error` true, no result or timeout | check quota, use `--agent none` or another alias |
| verification failed | 5 | a post-verify check failed (report names it) | read the report, `--restore`, re-run |
| agent success unverified | 6 | `opencode`/`pi` exit 0 without a readable result | review `.constitution-install-backup/<timestamp>/agent/` |
| interrupted | 130/143 | signal | re-run the same command |
| `--restore` refuses | 3 | backup dir not directly inside `.constitution-install-backup/`, wrong owner/mode, or tracked | fix ownership (`chmod 700`), keep it untracked |

## Updater (`update_constitution.sh`)

| Symptom | Cause | Fix |
|---|---|---|
| exit 3 "local changes" | submodule dirty | commit or stash inside `submodules/constitution` |
| exit 3 unpushed | HEAD on no remote branch or remote tag | push or go back to a published commit |
| exit 3 diverged | target is not a fast-forward | never forced; choose a descendant tag/ref |
| exit 3 network | every fetch failed (`--check` and `--dry-run` fetch too) | restore connectivity |
| exit 1 | post-update hook or checkout failed | read the hook output; re-run `post_update_hook.sh` by hand |
| newest tag not chosen | pre-release tags (`-rc1`) are never default | pass `--ref` |

## Hooks (`setup.sh`)

- Hooks not firing after a branch switch with `submodule.recurse=true`: git runs no hook then; run `setup.sh` or `post_update_hook.sh` by hand.
- "refusing: core.hooksPath at a machine-wide scope" or hooks dir outside the project: fix the config, or pass `--allow-global-hooks-path` knowingly (the submodule's own consumer hook is still never installed outside its git dir).
- Auto-propagation did not run: it is off (`git config constitution.autoPropagate`, `CONSTITUTION_AUTO_PROPAGATE=off`), or the new commit is not reachable from the submodule's `origin` default branch, or it is a downgrade. The hook prints the manual command.
- `setup.sh --check-only` compares installed hooks with their sources and exits 1 on drift.
- Hook-name collision with a project hook: the constitution hook stays, setup exits 1 and names the collision; move your logic to another hook name.

## Extensions (`constitution_ext.sh`)

Exit codes: 0 ok, 1 failure, 2 usage, 3 refused by policy, 5 verification failed. Run `doctor` first.

| Symptom | Fix |
|---|---|
| `verify` exit 5 after a fresh clone | expected: local state records are git-ignored; re-consent each entry with `enable <id> --yes` |
| installed tree missing in a clone | `_installed/` is git-ignored; reinstall with the pins in the lock |
| journal present, `add`/`remove` refuse | an interrupted run left a journal that does not validate; a person must inspect and delete it |
| undeclared `!{...}` / `@path` refused | declare under `capabilities.agent_shell` / `reads_files` |
| clone of a private repo fails | git global config and credential helpers are ignored (R15); use SSH keys |

## Setup prompt rotation

`rotate_setup_prompt.sh` exits 3 on a name collision, a bad `--source`, a numbering gap, a live `.rotate.lock`, or uncommitted changes under `docs/prompts/setup` (commit them, or pass `--allow-dirty`; checked 2026-10-31 with `--dry-run`); a crashed rotation is rolled forward or back by the next run.

Related: [FAQ](../faq/installer_faq.md), [manual](../manuals/installer_manual.md), [extensions FAQ](../faq/extensions_faq.md).

## Decisions wizard

`constitution_decisions.sh` exit codes (from `--help`): 0 done, 1 internal failure, 2 usage or no TTY without `--non-interactive`, 3 precondition (bad project root, python3/PyYAML missing, path outside the project, no inherited constitution; use `--inherits PATH` to confirm one), 4 refused (unknown key, weakening a locked rule such as `hosted.enforce=true`, secret-like value, tampered file), 5 another run holds the lock.
