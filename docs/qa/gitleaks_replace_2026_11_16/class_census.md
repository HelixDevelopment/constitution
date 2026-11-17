# CON-435 class census (§11.4.276(C)): scripts that run a secret scanner or scan git history

Measured 2026-11-16 on a clone of origin main cb7008c4, with `git grep` over
`scripts/` (tracked files only).

Queries (both case-sensitive, extended regex):

1. scanner invokers: `(^|[^a-z_])gitleaks( |"|$)|\$GL\b|GITLEAKS`
2. history readers: `log (-p|--all|.*-p )|rev-list --all|rev-list .*--objects|cat-file --batch|log --all|trufflehog|detect-secrets|git-secrets`

Controls:

- Positive: `scripts/gitleaks/gitleaks_run_scan.sh` and
  `scripts/security/history_secret_scan.sh` are listed by query 1, and
  `history_secret_scan.sh` by query 2 as well.
- Negative: a fabricated token gives 0 files.

| Hit | Runs a secret scan over git history? | Neutralises replace refs? |
|---|---|---|
| `scripts/gitleaks/gitleaks_run_scan.sh` | yes. It runs `gitleaks detect`, and gitleaks runs `git log -p` | Before this change: NO. The scrub unsets `GIT_NO_REPLACE_OBJECTS` and nothing set it again (the defect). After: YES. It exports `GIT_NO_REPLACE_OBJECTS=1` after the scrub. |
| `scripts/security/history_secret_scan.sh` | yes (`gitleaks git`, `cat-file --batch`) | YES. It exports the variable after the scrub (CON-425). |
| `scripts/gitleaks/gitleaks_install_check.sh` | no. It runs `gitleaks version` only | not applicable |
| `scripts/gitleaks/gitleaks_lib.sh` | no. It is a sourced helper and starts no scanner | not applicable |
| `scripts/hooks/credential_scan_lib.sh` | no. It reads the staged index only (`git show ":$f"`), not history | not applicable. The index blob is read by its path, and replace refs apply to object ids. UNCONFIRMED whether a replaced index blob would change what it reads. |
| `scripts/fastcycle/consumers/migrate.sh` | no. It is a consumer migration | exports the variable already (line 956) |
| `scripts/fastcycle/cycle/baseline_replay.sh` | no. It runs `git log --all --grep=<id>` (commit messages, not secrets) | not applicable |
| `scripts/install_constitution.sh` | no. It runs `rev-list --objects --missing=print` (missing-object check) | not applicable |
| `scripts/release/land_vehicle.sh` | no. It runs `rev-list \| cat-file --batch` (newness check of a vehicle) | not a secret scan. Whether a replace ref can change its verdict: UNCONFIRMED, outside this item. |
| `scripts/anchors/anchor_lib.py` and the other `.py`/`.txt`/binary hits | no. The hits are comments, the scrub list or data | not applicable |

Result: exactly two scripts run a secret scan over git history. After this
change both export `GIT_NO_REPLACE_OBJECTS=1` after the git-env scrub.

## CON-438 class (caller git config and attributes), checked on the same script

The CON-438 fix (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`) is not
the same one-line primitive. It does not cover the case below either: a
`.gitattributes` file committed in the scanned repository. So it is NOT done
here. It was measured with the real gitleaks 8.30.1 on the fixed script
(`probes/attributes_probe_result.txt`):

- Control: plain repository, no attributes. Exit 1, 2 leaks.
- The same repository, with the caller's `GIT_CONFIG_GLOBAL` naming a
  `core.attributesFile` that sets `*.env -diff`. Exit 0, `PASS ... 0 real
  leak(s)`. This is a false PASS.
- A repository whose own committed `.gitattributes` holds `*.env -diff`,
  with a secret `.env` file committed later. Exit 0, `PASS ... 0 real
  leak(s)`. This is a false PASS, and it comes from the scanned history
  itself, not from the caller.

This is filed as the new tracker item `CON-453` (follow-up). It is
not fixed here.
