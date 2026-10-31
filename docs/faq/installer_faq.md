# Installer FAQ

| Field | Value |
|---|---|
| Revision | 9 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T12:00:00Z |
| Status | draft |
| Status summary | Questions and answers about the one-command installer. Reconciled with the scripts (--help and source) on 2026-10-30 (round 11: marker format, symlink refusal, fingerprint tool rule); not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Anyone installing or updating the constitution. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

Answers describe the behavior of `install_constitution.sh 1.0.0`. Read the script's `--help` for the version you downloaded.

## Safety

**1. Is `curl | bash` safe?** It runs whatever the URL serves. The script is built so a truncated download executes nothing (everything is inside `main()`, called last), but you should still read it first: download to a file, read it, then run it. See the user guide.

**2. What does it change in my project?** The submodule at `submodules/constitution` (`.gitmodules` and the gitlink), the outputs of `setup.sh`, and with your consent the inheritance blocks in agent instruction files and hook registration. See the manual's files table.

**3. Does it push anything?** No. It never pushes and never force-pushes. A push made by the agent during its run is detected afterwards and fails the run (exit 5); a remote that answered before the run and cannot be asked after it fails the run too (fail closed), and a remote that could not be asked before the run is skipped and named on stderr.

**4. Can I undo it?** Every modified file is first copied to `.constitution-install-backup/<timestamp>/` (mode 700; it must stay untracked and owned by you for `--restore` to accept it). Run `bash install_constitution.sh --restore .constitution-install-backup/<timestamp>` to copy them back (or copy by hand), and remove the submodule with the usual git steps if you want it gone.

**5. Can I preview without changes?** Yes: `--dry-run` writes nothing and prints the plan.

**6. Does it delete my files?** No. The installer runs no recursive delete (§11.4.287). Leftovers of an interrupted ADD are moved into the backup folder under `moved-aside/`, never deleted.

**7. Can I run it as root?** Only with `--yes`; otherwise it refuses (exit 3).

**8. Will it print my API keys?** No. Only variable names are shown, never values; URLs are printed with credentials removed and query values as `REDACTED`.

**8b. Why is `GIT_SSH_COMMAND` ignored?** git runs with a sanitised environment (inherited `GIT_*` dropped; ssh is `ssh -o BatchMode=yes -o ConnectTimeout=10`). Put keys and ports in `~/.ssh/config`.

**8c. Does updating run code from the new version?** Yes, by design: the hooks `setup.sh` installed run the new checkout's `post_update_hook.sh`, only when that commit is on the submodule's upstream default branch and not a downgrade. Disable: `git config constitution.autoPropagate false` or `CONSTITUTION_AUTO_PROPAGATE=off`. See [trust model](../diagrams/trust_model.md).

**8d. Is `update_constitution.sh --check` offline?** No; it still fetches remotes and tags (it never moves HEAD or touches the project).

## Layout and migration

**9. Where does the constitution go?** `submodules/constitution`, the standard for new installs.

**10. My project uses `./constitution`.** That legacy layout stays supported. The installer detects it, explains, and does not move it automatically; migration is handed to the agent prompt (with backups) or exact manual steps are printed. See tutorial 02.

**11. Do both layouts work with the scripts?** That is the contract: every script supports both.

**12. Why a submodule and not a copy?** One source of truth, pinned by commit, updated by fast-forward.

## Agents, models and cost

**13. Which agent runs the prompt?** You choose: `claude`, native accounts `claudeN`, provider aliases, `kimi`, `opencode` or `pi`; the default is `none`. `aider`, `codex`, `gemini`, `qwen`, `cursor-agent`, `amp` and `goose` are listed detect-only and are refused as `--agent` (exit 3). Only unit-class tests cover agent driving; provider aliases, `kimi`, `opencode` and `pi` are UNCONFIRMED against a live run.

**14. What does it cost?** `--agent none` costs nothing. With an agent the defaults cap spend at 2 USD, model `sonnet`, effort `medium`, 30 minutes. Change with `--max-budget-usd`, `--model`, `--effort`, `--timeout-sec`.

**13a. Is a non-Claude agent sandboxed?** No. `kimi`, `opencode` and `pi` run with their own default permissions; the installer has no verified option to restrict them, so `--non-interactive` needs `--allow-unrestricted-agent` (otherwise exit 3) and the interactive run asks separately (default no). The report records `consent.unrestricted_agent`.

**15. How does it know the agent succeeded?** For the Claude family and `kimi`, from the final `result` event (`is_error` false), not the exit code. For `opencode` and `pi` there is no readable result event; the installer finishes with exit 6 ("success UNVERIFIED") and you review the agent transcript under the backup folder.

**16. What are follow-ups?** Extra prompts from `docs/prompts/setup/followups/` (`01_verify_incorporation.md`, `02_wire_decision_layer_optional.md`, `03_final_report.md`) run by resuming the same session; `--followups on`, off by default. A follow-up with `requires_previous_success: true` is skipped after a failure. Only the Claude family can resume.

**17. What is the decision layer?** The optional Jev layer (§11.4.279 to §11.4.286). `--decision-layer off|shadow|enforce`, default `off`; anything else runs `scripts/jev/bootstrap.sh --non-interactive`. Shadow only logs.

**18. Does detection call an LLM?** No.

## Environment

**19. Does it work offline?** Not for ADD from an upstream; it needs network or a reachable mirror (exit 3 otherwise). Use `--upstream KEY` or `--upstream-url`, including a local path or `file://` URL. An existing submodule can be updated only if its remotes are reachable.

**20. Private mirrors or a different host?** Use `--upstream-url URL` (repeatable; add `--ssh` for the table's SSH URLs). A URL that carries a password is skipped; use SSH keys. The private `m3w` Gitea (`git.m3w.org`) is reachable over SSH only: it has no anonymous curl snippet and is not an installer upstream; clone with your SSH key and run the script from the checkout, or pass its SSH URL with `--upstream-url`.

**21. Can I use it in CI?** Yes: `--non-interactive --agent none --report-json out.json`. Without a terminal and without `--non-interactive` it exits 2. Add `--git-init` only if the directory is not yet a repository.

**22. Does it need `jq`?** No. With an agent it needs `python3` or `jq` (and `timeout`) to read the agent's stream, otherwise exit 3 names it. It always needs bash 4.4+ and git.

**23. Is it idempotent?** A second run is a no-op that says so.

## Updating and removing

**24. How do I update?** (default target: the newest release tag `helixconstitution-vN(.N)*`, never a pre-release.) Re-run the curl command or `bash submodules/constitution/scripts/update_constitution.sh` (`--check` first prints `UPDATE_AVAILABLE=yes|no`). It requires a fast-forward and never forces.

**25. What if the submodule has local changes?** The updater refuses (exit 3). Commit or stash them first. If an earlier update was interrupted, the message says so and names the marker file.

**25a. The updater says my staged gitlink "is not overwritten".** You staged a constitution commit by hand that differs from both the committed one and the checkout. Nothing changed (exit 3). Keep the checkout with `git add -- submodules/constitution`, or drop your staged change with `git restore --staged -- submodules/constitution`, then re-run. An update the updater itself started and that was cut off before staging is recognised by `.git/helix-update-pending` and finished normally.

**25aa. An interrupted update was not finished, the updater still refuses. Why?** The pending marker (`.git/helix-update-pending`) is `<target sha> <staged-before>` and is honoured only if it names the current checkout and records the gitlink that is staged right now. A marker from an older run, a marker in the old one-field format and a symlinked marker are ignored (never read, never written through), so the refusal stays; use `git add -- submodules/constitution` to keep the checkout or `git restore --staged -- submodules/constitution` to drop the staged change.

**25ab. The installer says no cksum or sha256sum is available.** The no-push check fingerprints what the remotes advertise with `sha256sum` (or `cksum`). With neither on PATH it cannot compare and fails closed (the run is refused). Install coreutils (or `cksum`) and re-run.

**25ac. What do `--project-root` and `--detect-layout` do?** `--project-root DIR` installs into or updates the project at DIR instead of the current directory (if the directory is a submodule of a superproject, the installer refuses with exit 3 only when that directory came from the current directory; an explicit `--project-root` is allowed and prints a warning). `--detect-layout` is read-only: it prints `none`, `standard`, `legacy`, `both`, `partial`, `inconsistent` or `constitution-repo` and exits before anything is asked, locked, backed up or written.

**25ad. Does a green `CM-INSTALLER-NO-PUSH-NO-FORCE` prove the installer cannot push?** No. It is a best-effort tripwire (operator decision 2026-10-31), like the destructive-path guard. Known limits: a path producer inside a pinned helper that uses a command substitution or `printf` of another value is not recognised; a value passed as a function argument is pinned at its binding, not at the callers; a duplicate function definition that shares a line with other code (nested definitions that start their own line are counted); unmodelled binding forms (namerefs, indirect expansions) are caught only by the raw switch-token count; agent behaviour inside its own run and other scripts are out of scope. The real protection is the runtime tests, the runtime no-push check after an agent run (tested in `test_round6.sh` with real `git push` commands run by a labelled FAKE `claude` (unit-class, §11.4.289) into bare repositories the test creates) and `test_git_wrapper.sh` (every forbidden git form is refused). See the guide section "No-push source gate".

**25b. The updater says the project records a NEWER constitution commit. Why?** A teammate updated the gitlink and you pulled without moving the checkout. The updater never moves a recorded gitlink backwards: run `git submodule update -- submodules/constitution`, then re-run. Nothing was changed.

**25c. The install created `helix-deps.yaml`. Why, and what if it is untracked?** The post-update hook requires a tracked, valid dependency manifest (§11.4.31). The installer scaffolds it on a fresh install (never overwriting one you have). A valid skeleton is staged; one with `UNKNOWN` placeholders is left untracked with printed next steps, and the run reports `manifest-needs-completion` (exit 1) if `setup.sh` stops on it. Fill the placeholders, run `bash submodules/constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh --validate-file helix-deps.yaml`, `git add helix-deps.yaml`, then run `setup.sh` again.

**26. How do I uninstall?** `git submodule deinit -f submodules/constitution`, `git rm -f submodules/constitution`, remove the inheritance blocks you accepted, and review `git status`. The installer has no uninstall command.

**27. Is the latest tag always used?** By default the newest `helixconstitution-v*` tag, else `main`; override with `--ref`.

## Troubleshooting by exit code

**28. Exit 2.** Usage error or no TTY: add `--non-interactive` or fix the flag.

**29. Exit 3.** Not a git repo, dirty `.gitmodules` or agent-doc files, no reachable upstream, root without `--yes`, a missing agent or tool, bash older than 4.4, another installer holding the lock, or the target is the constitution repository itself (pass `--not-constitution-repo` only if your project merely uses it and has its own `Constitution.md`). Run `git status`, fix, re-run.

**30. Exit 4.** The agent run failed. Check the report JSON and the agent's quota; re-run with `--agent none` to install without it.

**31. Exit 5.** Post-verify failed. The report names the check; restore from the backup folder if needed and re-run.

**31b. Exit 6.** The agent (`opencode`, `pi`) exited 0 but the installer cannot verify success; the constitution step is done. Read the agent transcript in `.constitution-install-backup/<timestamp>/agent/` and verify the project yourself.

**32. Exit 1.** Generic failure (for example `setup.sh` failed, or report status `manifest-needs-completion`: see 25c); read the last printed message. Exit 130 / 143 means interrupted; re-run the same command.

Related: [user guide](../guides/installer_user_guide.md), [manual](../manuals/installer_manual.md), [tutorial 06](../tutorials/06_recovering_from_a_failed_run.md).
