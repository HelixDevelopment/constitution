# CON-425 class census: git calls that could follow replace refs (§11.4.276(C))

Class: a git call that reads objects or walks history and honours
`refs/replace/*`, so a scanned secret can be shown as a clean object.
Measured 2026-11-16 by `census_git_calls.sh.txt` (output `census_git_calls.txt`)
on the fixed working tree of a clone of origin main cc51c320.

## scripts/security/history_secret_scan.sh

Every git call, and how it is made replace-proof. All of them inherit
`GIT_NO_REPLACE_OBJECTS=1`, exported once right after the git-env scrub (the
scrub clears a caller's value first). The only `env -i` in the script starts the
bash that sources the keys file; that bash runs no git.

| Call | Reads objects or history? | Replace-proof by |
|---|---|---|
| `git clone -q --mirror` (remote #1) | copies refs, including `refs/replace/*` | the export; the copied replace refs are listed (below) |
| `git -C M fetch` (remotes #2..n) | refs; now also `+refs/replace/*:refs/fetched/r<n>/replace/*` | the export; fetched replace refs are listed |
| `git -C M for-each-ref ... refs/replace/ refs/fetched/` (new) | ref names and object ids only | lists every replace ref into `$OUT.replace.tsv`; each counts as a finding (exit 1) |
| `git -C M hash-object -w`, `mktree`, `commit-tree`, `update-ref` (needles) | write new objects and refs | the export (they read no replaced object) |
| python3 `git cat-file --batch-all-objects --batch-check` | object ids and types | the export (inherited environment) |
| python3 `git cat-file --batch` | object contents | the export; the type check `hdr[1] != b"blob"` stays as defence in depth (a git that still honours replace refs gives exit 7, test case 17 of `test_history_secret_scan_replace.sh`) |
| `"$GL" git ...` (gitleaks) | history via its own `git log -p` | the export (inherited environment); proven with the fake scanner only. Whether the real gitleaks v8 passes the environment to its git is UNCONFIRMED (no run with the real binary) |

Measured on git 2.53.0 (`probe_git_sem.txt`): with `GIT_NO_REPLACE_OBJECTS=1`
the replaced blob is seen by `git log -p --all -m` (1 of 1), also when
`core.useReplaceRefs=true` is given with `-c`, in `GIT_CONFIG_PARAMETERS` or in
the repository config; a replaced commit's diff is seen too. A ref that points at
a blob (the replace ref itself) does not make `git log --all` fail (rc 0, no
stderr). Other git versions: UNCONFIRMED.

## Siblings and libraries

| File | Local git calls | Note |
|---|---|---|
| `scripts/security/forge_branch_protect.sh` | 0 | forge APIs over curl only; reads no git object |
| `scripts/security/github_actions_inventory_disable.sh` | 0 | `gh api` only; reads no git object |
| `scripts/lib/safe_rm.sh` | 0 | no git |

Control needles of the census: the same pattern finds 18 git calls in
`history_secret_scan.sh` (positive); a fabricated token is found 0 times
(negative). The first version of the census read `$?` after a pipeline and
printed `rc=0` for "no match"; the stored version counts per file
(§11.4.273(g)).

## Outside scripts/security (not changed, for the record)

Searching `scripts/` for `cat-file --batch`, `log -p`, `rev-list --all` and
`--batch-all-objects` found, besides this script,
`scripts/fastcycle/orchestration/custody_sweep.py` and
`scripts/release/land_vehicle.sh`. Both already pass `--no-replace-objects` on
the calls found (`custody_sweep.py` lines 1169 and 1194, `land_vehicle.sh` line
562), and `scripts/fastcycle/consumers/migrate.sh` line 956 exports
`GIT_NO_REPLACE_OBJECTS=1`. Whether every git call in those files is covered
was not checked (UNCONFIRMED), and a history reader that uses another git
command is not found by that search (UNCONFIRMED).

## Known limit kept

Remotes #2..n are still fetched for heads, tags and (now) replace refs only.
Objects reachable only from other refs of those remotes (notes, pull refs) are
not scanned. Remote #1 is a full mirror. Pre-existing; not changed here.
