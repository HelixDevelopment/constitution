# Tutorial 06 - Recovering from a failed run

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | What to do after a non-zero exit. Reconciled with the final scripts (--help and source) on 2026-10-29; not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Step-by-step tutorial for the installer. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

1. Read the last message and the exit code (see the manual's table).
2. Look at `git status` and at `.constitution-install-backup/`; the newest timestamp folder holds your pre-change files.
3. Restore: `bash install_constitution.sh --restore .constitution-install-backup/<timestamp>` copies every saved file back (files listed in `created.txt` were created by the run and are not removed). The directory must sit directly inside `.constitution-install-backup/`, be owned by you, mode 700 and untracked; entries under `.git/`, absolute paths, `..` and anything through a symlink are skipped.
4. Re-run with `--dry-run` to see what it would do now; the installer is idempotent.
5. Exit 4: re-run with `--agent none`, or pick another agent or alias (quota). Exit 5: the report names the failed check; fix and re-run. Exit 3: fix the precondition (bash 4.4+, clean tree, another installer running, or the target is the constitution repository itself). Exit 6: the agent exited 0 but the installer cannot verify it (`opencode`/`pi`); read `.constitution-install-backup/<timestamp>/agent/`.
6. If interrupted by a signal mid-run (exit 130 / 143), re-run the same command: leftovers of a half-added submodule are moved into the backup, and a stale lock is removed once its process is gone.

Back: [safety model](../diagrams/safety_backup_model.md), [FAQ](../faq/installer_faq.md).
