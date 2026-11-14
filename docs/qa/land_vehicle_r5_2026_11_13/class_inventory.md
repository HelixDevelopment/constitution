# land_vehicle.sh round 5: class inventory

| Field | Value |
|---|---|
| Created | 2026-11-14 |
| Status | fixer working document, awaiting independent review (no GO is claimed) |
| Rule | §11.4.276(C) and (E): name each class, enumerate every member with a control-needled instrument, then close every member or scope it out explicitly |
| Lander | `scripts/release/land_vehicle.sh` (round 5) |
| Test | `tests/release/test_land_vehicle.sh` (round 5) |

The round-4 review (NO-GO, F1-F13) reported five classes. This file lists every member found in each class, not only the reported ones. Each member has one of three dispositions:

- **CLOSED**: code changed, and a named test drives the real lander through it.
- **BOUNDARY**: left open on purpose. It is documented in the lander header and listed under "Honest boundaries" below.
- **NON-MEMBER**: measured, and shown not to apply. The measurement is cited.

Three members were not in the review. The inventory found them, they were measured, and they are now closed: **N1** (merge strategy from config), **N2** (gitlinks hidden from the mint record), **N3** (a shared repository mode on a clone that holds the remote URLs).

## Instruments (with control needles, §11.4.273)

| Instrument | Result | Positive control | Negative control |
|---|---|---|---|
| `git help --config` (git 2.53.0): every config variable git documents | 979 variables in 94 sections | `log.showSignature` found 1 time; `pull.twohead` found 1 time | `fake.zzNeedle` found 0 times |
| `strings $(command -v git)` matched against `^GIT_[A-Z0-9_]+$`: environment names | 167 names | `GIT_TEMPLATE_DIR` found 1 time; **`GIT_DIR` found 0 times** | `GIT_ZZ_NEEDLE` found 0 times |
| `grep -nE '\bg [a-z-]+'` over the lander: every git call against the clone | each call site listed in class C below | `g push` occurs exactly once (SH0 asserts this) | not applicable |

The environment list fails its positive control: `GIT_DIR` is missing, so the list is incomplete and is NOT the enumeration. The lander's scrub does not depend on it. The scrub removes every `GIT_*` name except an allow-list, so the enumeration is complete by construction (every name, known or not).

## Class A: check, then use (the clone or an input can change in between)

| # | Member | Check | Use | How round 5 binds check and use | Test |
|---|---|---|---|---|---|
| A1 | the bundle file | sha256 of `--bundle` | bundle verify, list-heads, fetch | the bundle is copied into the clone's `.git`, the COPY is hashed again, and only the copy is used from then on | T6, T7, R5-BUNDLE-COPY |
| A2 | a remote's URL and config (F1/R04b) | `--remotes-file` at start-up | fetch, ls-remote, push | `assert_remote` runs immediately before EVERY fetch, ls-remote and push. It checks the fetch URLs (`get-url --all`, so `insteadOf` counts), the push URLs (`get-url --push --all`, so `pushurl` and `pushInsteadOf` count) and every `remote.<name>.*` key in any config file against an allow-list. A refusal in the middle of the push loop names the remotes this run already pushed the checked main to (`ar_note`) and pushes no further remote. Residual window: see the boundaries below | R5-R04b, R5-RB, R5-F1g (a global `insteadOf` at prepare: refused before the first fetch), V14, R5-RM31 |
| A3 | clone main at publish (F1/R04, K01) | trailer checks on the commits after the base | push, read-back | main is read ONCE (`local_main`). Both trailer checks run on `local_main`. The push sends `<local_main sha>:refs/heads/main`, never the name `main`. The read-back compares with `local_main`. Main is read again after the read-back; if it moved, publish exits 1 | R5-K01, SH0 |
| A4 | the WARN carve-out (F1/R04 laundering) | the commit is on a remote | publish without refusing | only a commit that is an ancestor of `main_before` (already published when prepare ran) can be a WARN. Every commit after `main_before` must carry one real trailer, even when a remote already has it | U10, U10b |
| A5 | the mint's staged content (F1/R15) | id presence and newness | the mint commit | ONE raw record (`diff-index --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none`) is taken once. Every check reads the record's blob ids, never the work tree. `write-tree` is diffed against the base and compared with the record byte for byte. The `commit-tree` result is compared again. `update-ref` uses the old value (compare-and-swap). Afterwards the index and work tree must be clean | V15 (two modes: `swap`, the content of a listed path is swapped; `extra`, an extra path is staged), V8d |
| A6 | **N2, new**: a gitlink change hidden from that record | the record | the mint commit | measured: `submodule.<name>.ignore=all`, from config OR from the in-tree `.gitmodules`, hides a gitlink change from `diff-index` AND from `diff-tree`. So the record and the compare agreed, and the commit carried an unrecorded gitlink. Now `--ignore-submodules=none` is passed on every `diff-index`, `diff-tree` and `status`, and `diff.ignoreSubmodules=none` is pinned | R5-N2 |
| A7 | HEAD and main around the mint | before the mint command | the mint commit | after the mint command, HEAD must still be the symbolic ref `refs/heads/main` and main must still be `head0`; `update-ref` is a compare-and-swap on `head0` | V7 (moved HEAD) |
| A8 | `--head` (F3) | the head is a ref tip in the bundle | integration | the fetched ref must equal `--head`, and its object type must be `commit` (objects are content-addressed, so the type cannot change later) | R5-F3a |
| A9 | the re-committed object | the message and header the lander built | integration | every post-check reads the object back from git (`cat-file commit <new sha>`), not the text in memory | T2, S3, R5-F4 |
| A10 | the merge result (N1) | parents | publish | parents are checked, and the merge tree is compared with an independent oracle (below) | R5-N1 (both `ours` settings), R5-N1c |
| A11 | the prepare state | written by prepare | publish, verify | read ONCE into memory. Unknown and duplicated keys are refused. The values are compared with the refs prepare recorded (`refs/land/*`) | U9, U9b, U9c, U9d, U15 |
| A12 | a remote's main between preflight and push | preflight (ancestor of `local_main`) | push | the push is never forced, so the remote itself refuses a non-fast-forward. The read-back then reports FAIL | T3, T4 |

## Class B: minting an id, and showing it is new

| # | Member | Rule in round 5 | Test |
|---|---|---|---|
| B1 | canonical form (F10) | `^<KEY>-(00[1-9]\|0[1-9][0-9]\|[1-9][0-9]{2,})$`, the engine's `%s-%03d` form (measured in round 4). `CON-0100`, `CON-07` and `CON-77` are refused wherever an id is read | R5-F10, S5g, S5g-b |
| B2 | a placeholder used as a real id (F3) | a value matching `--placeholder-re` is refused as the mint's id, as `--item-id`, and in every trailer check (prepare's post-checks, prepare's final range, both publish checks) | R5-F3b, R5-F3c, R5-F3d, V3b |
| B3 | newness against tracker files (F2a, F2c) | EVERY blob at main before the mint whose path matches `LANDER_TRACKER_PATHS` is searched (added, modified and untouched files alike) | R5-F2a, R5-F2c |
| B4 | newness against trailers (F2b) | every `Roadmap-Item` line of every commit reachable from main or the vehicle is searched (raw `cat-file --batch`) | R5-F2b |
| B5 | leading zeros | newness ignores leading zeros: `CON-7`, `CON-07` and `CON-007` are one id | R5-F2z (tracker files), R5-F2zh (trailers in the history) |
| B6 | fail closed on a neighbour byte | newness has NO left boundary, and a file that holds a NUL byte is matched by substring | R5-RM15, R5-F2n |
| B7 | presence | the id must occur as a token (with a left boundary) in the recorded blob of a changed file | R5-RM13, V3c |
| B8 | the printed id | last stdout line; one trailing CR, spaces and tabs are removed; any other control character makes it fail the id pattern | R5-RM28, V3a |
| B9 | `--item-id` | canonical and not a placeholder. Not checked for newness: an id minted earlier is, by definition, not new (documented) | L6, U8b |
| B10 | `--id-verify-cmd` | runs in the clone, without the lock descriptor; must print the id as a token | U8, R5-RM10 |

## Class C: ambient git configuration and environment

### Environment

| Variable | Disposition | Reason |
|---|---|---|
| every `GIT_*` name not listed below | removed at start-up | none of them may select another repository, index, work tree, object store, namespace, template, config injection (`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`), trace, attribute source or replace-ref base |
| `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_NOSYSTEM` | kept | the caller's choice of config FILES (their contents are class C config, below) |
| `GIT_SSH`, `GIT_SSH_COMMAND`, `GIT_SSH_VARIANT`, `GIT_ASKPASS`, `GIT_TERMINAL_PROMPT` | kept | transport authentication (boundary) |
| `GIT_AUTHOR_NAME/EMAIL/DATE`, `GIT_COMMITTER_NAME/EMAIL/DATE` | kept | identity of the lander's own two commits (mint, merge); re-commits copy the original header lines |
| `CDPATH` | removed | a `cd` must not land somewhere else |
| `LC_ALL` | set to `C`; the caller's value (or none) is given back to the mint and id-verify commands | byte semantics for every regex |
| file mode creation mask | **N3, new**: `umask 077`, plus `core.sharedRepository=false` on `git init` AND on every later git call (measured: with a global `core.sharedRepository=world`, a commit without the per-call pin gave 13 entries under `.git` with group or other bits; with the pin, 0) | the clone's `.git/config` holds the remote URLs, which may carry a credential. Tests: R5-N3 (`.git` and `config` modes), R5-N3b (no entry under `.git` with a group or other bit after prepare) |
| `HOME`, `XDG_CONFIG_HOME` | not touched | they only choose the global config file (config class) |
| `TZ`, `EMAIL`, `PATH`, `TMPDIR`, proxy variables | not touched | time zone and identity of the lander's own commits, tool lookup, temporary files, transport (boundary) |

### Config, by section (all 94 sections of `git help --config`)

| Sections | Read by a command the lander runs? | Disposition |
|---|---|---|
| `core` | yes | pinned: `hooksPath=/dev/null`, `fsmonitor=false`, `attributesFile=/dev/null`, `excludesFile=/dev/null`, `autocrlf=false`, `eol=lf`, `sparseCheckout=false`, `useReplaceRefs=false`, `commentChar=#`, `sharedRepository=false` (N3), `untrackedCache=false`, `checkStat=default`. Plus `--no-replace-objects` and `--literal-pathspecs`. `core.worktree` and `core.bare` are overridden by explicit `--git-dir`/`--work-tree`. `fileMode`, `symlinks`, `ignoreCase` are written by `git init` into the clone's local config and win over the global file. `sshCommand`, `askPass`: transport (boundary) |
| `init` | yes | `--template=`, `-b main`, `--object-format`, `--ref-format=files` (F6) |
| `merge`, `pull`, `branch` | yes (merge) | **N1, new, measured**: `pull.twohead=ours` and `branch.main.mergeOptions=-s ours` each made `git merge` drop the vehicle's content while the merge commit had the right parents. An explicit `-s ort` alone does NOT override `branch.main.mergeOptions=-s ours` (measured). Closed three ways: pins `pull.twohead=ort`, `pull.octopus=octopus`, `branch.main.mergeOptions=` (empty), `merge.renormalize=false`, `merge.log=false`, `merge.autoStash=false`, `rerere.enabled=false`; `-s ort`, `--no-verify-signatures`, `--no-log`, `--cleanup=strip` on the command line; and an independent oracle: the merge tree must equal `git merge-tree --write-tree` run with no global and no system config. The oracle covers every other `merge.*`/`diff.renames*` setting and any merge driver from config at once |
| `diff` | yes (plumbing) | raw output with `--no-renames --no-abbrev -z`; `diff.ignoreSubmodules=none` pinned and `--ignore-submodules=none` passed (N2) |
| `submodule` | yes | `submodule.recurse=false`; `submodule.<name>.ignore` neutralised by `--ignore-submodules=none` (N2) |
| `status` | yes | only "is the output empty" is used; `--untracked-files=all --ignore-submodules=none` on the command line |
| `fetch`, `transfer`, `remote`, `remotes`, `url` | yes | `--no-tags --refmap=`; `fetch.prune=false`, `fetch.pruneTags=false`, `fetch.recurseSubmodules=false`, `fetch.bundleURI=`, `transfer.bundleURI=false`; `remote.<name>.*` and `url.*` checked by `assert_remote` at every use. NON-MEMBER, measured: a group `remotes.github=evil` does NOT redirect `git fetch github <refspec>` (the right remote's commit was fetched) |
| `push` | yes | `push.pushOption=` (empty clears the list, F5), `push.gpgSign=false`, `push.followTags=false`, `push.recurseSubmodules=no`, `push.default=nothing`; `--no-verify --no-follow-tags --recurse-submodules=no`; the refspec is `<sha>:refs/heads/main` |
| `log`, `format`, `pretty`, `color`, `i18n` | only display | F4: every value is read from raw objects (`cat-file`, raw diffs), never from `git log`. Pinned anyway: `log.showSignature=false`, `color.*=never`, `i18n.logOutputEncoding=UTF-8`, `i18n.commitEncoding=UTF-8` |
| `trailer` | no (isolated) | `git interpret-trailers --parse` runs with no repository and no config (`GIT_DIR=/nonexistent`, no global, no system file) |
| `gc`, `maintenance`, `pack`, `repack`, `index`, `splitIndex`, `commitGraph`, `fsck`, `feature`, `reftable` | yes (housekeeping) | `gc.auto=0`, `maintenance.auto=false`; the rest change performance or make git stricter (fail closed), not content |
| `protocol` | yes (transport) | `protocol.ext.allow=never`; the rest is transport (boundary) |
| `user`, `author`, `committer`, `gpg`, `commit` | yes (identity) | the caller's identity and signing for the lander's two commits (boundary, documented). `commit-tree` ignores `commit.gpgSign` (measured), so the lander passes `-S` itself when it is true |
| `http`, `credential`, `credentialCache`, `credentialStore`, `ssh` | yes (transport) | boundary |
| `uploadpack`, `uploadpackfilter`, `receive`, `lsrefs` | server side | boundary (with local file remotes, `uploadpack.packObjectsHook` from the caller's global config runs locally) |
| `attr`, `filter` | yes (attributes) | `core.attributesFile=/dev/null`; `GIT_ATTR_SOURCE` removed. `attr.tree` and in-tree `.gitattributes` drivers: boundary (below) |
| `trace2` | yes | boundary: git reads global `trace2.*` before any `-c` option |
| `advice`, `alias`, `am`, `apply`, `bitmapPseudoMerge`, `blame`, `browser`, `bundle`, `checkout`, `clean`, `clone`, `column`, `completion`, `difftool`, `extensions`, `fastimport`, `fsmonitor`, `gitcvs`, `gitweb`, `grep`, `gui`, `guitool`, `hasconfig`, `help`, `imap`, `include`, `includeIf`, `instaweb`, `interactive`, `mailinfo`, `mailmap`, `man`, `mergetool`, `notes`, `pager`, `promisor`, `rebase`, `replay`, `rerere`, `revert`, `safe`, `sendemail`, `sequence`, `showBranch`, `sparse`, `stash`, `tag`, `tar`, `uploadarchive`, `versionsort`, `web`, `worktree`, and the section-less entries | no, or only stderr text | not read by any command the lander runs, or only change messages on stderr. `include`/`includeIf` only add more config of the sections above. `alias`: the lander only runs built-in commands, which an alias cannot shadow. `fsmonitor`: `core.fsmonitor=false`. `rerere`: pinned off. `promisor`: `remote.<name>.promisor` is refused by `assert_remote`. `extensions`: written only by the lander's own `git init` |

## Class D: input parsing

| Input | Rule in round 5 | Test |
|---|---|---|
| subcommand | first argument; `-h`/`--help` there prints the usage | U1, U2 |
| options (F7) | `-h`/`--help` means help only where an option NAME is expected. Every option needs a non-empty value that does not start with `-`, and may be given once. Unknown options, and options the subcommand does not use, are refused (exit 2) | R5-F7, U12 |
| path values | no control characters | U13 |
| `--head` | 40 or 64 lower-case hex digits; a ref tip in the bundle; object type commit (F3) | T7, R5-F3a |
| `--sha256` | 64 hex digits | T6 |
| `--item-id`, `--key-prefix`, `--placeholder-re` | class B; `^[A-Z][A-Z0-9]*$`; a valid ERE | L6 |
| `--clone-name` | one plain path component, no `..` | U12 |
| remotes file (F11) | NUL refused; a control character other than TAB refused by line number (a CR from a CRLF file included); exactly two fields; plain names; a URL must not start with `-`; exactly the names of `LANDER_REMOTES`, each once; a last line without a newline is read | R5-F11, R5-RM04, V14 |
| `LANDER_TRACKER_PATHS` (F9) | no control characters; relative, no `..`; must contain `/`; the first component is a literal name (not `.`). `*`, `docs`, `*/x`, `./x` are refused at start-up; `docs/*` is accepted | R5-F9 (including `../docs/x`), R5-F2a and R5-F2c (glob patterns) |
| the prepare state | read once; unknown or duplicated keys refused; values checked against the refs | U6, U7 |
| the mint's stdout | class B (B8) | V3a, R5-RM28 |
| the mint's changes | class A (A5) plus: status A or M only, mode 100644 or 100755, no control character in the path, path matches `LANDER_TRACKER_PATHS` | V8a, V8b, V8c, V8d, R5-RM06, R5-RM23 |
| trailer values (F13) | git's own parser decides the trailer; the value is validated as git reports it, with no normalisation: a CR anywhere (`CON-9<CR>05`) is refused | R5-F13 |
| ls-remote, rev-list, cat-file, raw diffs | `--refs` plus an exact `refs/heads/main` match; full hashes; `-z` records | covered by T1-T4 |

## Class E: commit identity

| # | Member | Rule in round 5 | Test |
|---|---|---|---|
| E1 | re-committed commits (F4) | written as raw objects with `hash-object -t commit`. Every header line is copied byte for byte (tree, author, committer, encoding, mergetag, any other) except parent lines (mapped) and a signature (dropped, recorded per commit). Post-checked against the stored object. Read from `cat-file`, so no log, pretty, signature-display or re-encoding setting can change author, date or message | T2, S3, R5-F4 |
| E2 | a commit that already carries one real trailer | kept byte for byte; same sha when its parents are unchanged | R5-KEEP |
| E3 | the mint commit | `commit-tree` with the caller's identity; signed with `-S` when `commit.gpgSign` is true | T1 |
| E4 | the merge commit | the caller's identity; two `-m` paragraphs; `--cleanup=strip` with `core.commentChar=#` pinned; its tree must equal the oracle (N1) | T8, R5-N1 |
| E5 | encodings | `i18n.commitEncoding=UTF-8` is pinned, so the lander's own commits get no encoding header; a re-commit copies the original `encoding` header line | no suite test (a gap): only the round-4 reviewer's scenario R13 exercised it |

## Honest boundaries (open on purpose, documented in the header)

- **Transport and credentials**: ssh command, credential helpers, `http.*`, protocol allow lists other than `ext`, proxy settings. The caller owns them.
- **Identity and signing** of the lander's own two commits: the caller's config.
- **Attribute drivers and filters**: a filter or merge driver named by an in-tree `.gitattributes` file (or by `attr.tree`) runs the caller's command on checkout and `add`. The content checks above then apply to what was recorded. For the merge, the oracle refuses a result that a driver from the caller's config changed.
- **Global `trace2.*`**: git reads it before any `-c` option, so it cannot be neutralised. It only writes traces.
- **Server-side config** of the remotes (`receive.*`), and, for local file remotes only, `uploadpack.packObjectsHook` from the caller's global config.
- **The window between a check and the use**: `assert_remote` runs immediately before each operation, but git reads its config again for the operation itself. A writer that changes the clone's config inside that window is not caught. The F1 triggers in the round-4 review were made deterministic on purpose; whether such a race happens in real use is UNCONFIRMED.
