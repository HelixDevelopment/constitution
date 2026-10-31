# Quick Start - install the constitution in one page

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | One-page path from nothing to an installed, checked constitution. Reconciled with `install_constitution.sh --help` on 2026-10-29; not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Anyone adding the Helix Constitution to a git project. |
| Issues | none |

## 1. Preview

```bash
cd your-project        # a git repository (bash 4.4+ and git required)
curl -fsSL 'https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh' -o install_constitution.sh
less install_constitution.sh            # read it: curl | bash trusts the server
bash install_constitution.sh --dry-run  # prints the plan, writes nothing
```

## 2. Install

```bash
bash install_constitution.sh --agent none
```

Result: submodule at `submodules/constitution` (checked out at the newest `helixconstitution-vN` release tag, else `main`), `setup.sh` run, inheritance blocks written into `CLAUDE.md` / `AGENTS.md`. Nothing is committed and nothing is pushed. Every changed file is backed up under `.constitution-install-backup/<timestamp>/`.

## 3. Check

```bash
git status
git submodule status
bash submodules/constitution/scripts/update_constitution.sh --check   # prints UPDATE_AVAILABLE=yes|no (it still fetches)
```

## 4. Commit and update later

```bash
git commit -m "chore: add constitution"
bash submodules/constitution/scripts/update_constitution.sh           # fast-forward only
```

## If something goes wrong

Exit codes: 0 ok, 1 failure, 2 usage, 3 blocked, 4 agent failed, 5 verification failed, 6 agent success unverified. See [troubleshooting](troubleshooting_guide.md), [recovering from a failed run](../tutorials/06_recovering_from_a_failed_run.md) and the [manual](../manuals/installer_manual.md).

Opt-out of automatic post-update propagation: `git config constitution.autoPropagate false`. Trust details: [trust model](../diagrams/trust_model.md). More: [user guide](installer_user_guide.md), [FAQ](../faq/installer_faq.md).
