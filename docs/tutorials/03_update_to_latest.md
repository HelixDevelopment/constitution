# Tutorial 03 - Update to the latest release

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | Updating an installed constitution. Reconciled with the final scripts (--help and source) on 2026-10-29; not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Step-by-step tutorial for the installer. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

1. Check without changing the project (prints `UPDATE_AVAILABLE=yes` or `no`; it still runs `git fetch`, so it needs the network and updates remote-tracking refs and tags).

```bash
bash submodules/constitution/scripts/update_constitution.sh --check
```

2. Preview, then update.

```bash
bash submodules/constitution/scripts/update_constitution.sh --dry-run
bash submodules/constitution/scripts/update_constitution.sh
```

3. Review the printed before/after SHA and changelog delta, then commit the staged gitlink: `git commit -m "chore: update constitution"` (or pass `--commit` to the updater). The post-update hook runs unless `--no-hook`.
4. To target a specific tag: `--ref helixconstitution-v73` (the release-1 tag, the minimum supported ref; older tags predate the installer and the installer exits 3 on them).
5. If it refuses (exit 3), the submodule has local changes, unpushed commits or the target is not a fast-forward. Resolve, do not force.

Back: [installer guide](../guides/installer_user_guide.md).
