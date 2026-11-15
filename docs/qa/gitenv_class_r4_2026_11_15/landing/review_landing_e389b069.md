# Independent review: landing commit e389b069 (CON-402 gitenv vehicle onto main e90d4aea)

| Field | Value |
|---|---|
| Reviewer | independent review subagent, model Claude Opus 5.5 (claude-opus-5-5); effort UNKNOWN (not reported on this dispatch path) |
| Date | 2026-11-15 |
| Scope | only what the landing added beyond the reviewed vehicle head fd799642 (vehicle base bcac0882), plus its integration with main e90d4aea (CON-401) |
| Repository read | <scratch>/repo (read only; nothing committed, pushed or edited there) |
| Work dir | <scratch> (own clones `land` = e389b069, `main` = e90d4aea, `mut` = e389b069 for mutations; all three left clean) |
| Verdict | **GO-with-follow-ups** (every open finding is minor-class under §11.4.276(G.2); F1 is recorded `important` and should be fixed in the landing before the push, see below) |

## Findings

| Id | Severity | finding_layer | Minor-class | Summary |
|---|---|---|---|---|
| F1 | important | process-doc | yes (process-doc layer, §11.4.276(G.2)) | The landing silently dropped reviewed vehicle content: the paragraph of `docs/guides/full_suite_runner_guide.md` that documents the gate CM-FULL-SUITE-MANIFEST-COMPLETE (how to regenerate rows, what the gate judges, exit codes 0/1/2/3, the control needles, the clearing of ambient git variables, `tests/test_full_suite_manifest_gate_git_env.sh`, the mutation test, why it exists). Present at fd799642, absent at e389b069; not declared in the commit message, which lists the guide only as "census synced". |
| F2 | minor | process-doc | yes | Commit message: "Vehicle-only paths ... equal fd799642 byte for byte ... (proof in the landing pack README)". The landing README contains no such proof (no file list, no command, no output). The claim itself holds (independently checked, below), but its cited evidence does not exist. |
| F3 | minor | process-doc | yes | Landing README: "the mutation suite result is in the landing commit message". The commit message carries no result for `tests/security/test_security_scripts_mutations.sh`, a file the landing edited. The run is unrecorded. |
| F4 | minor | process-doc | yes | CON-402 acceptance (DB body, Issues.md) requires "review follow-ups F-R5-1 to F-R5-8 tracked" and the commit message cites "F-R5-4"; no F-R5 id is defined anywhere in the tracked tree (only in Issues.md, Issues_Summary.md and the DB, as references), and the review file `review_gitenv_r4.md` (sha256 664796e2...) is not in the repository. The follow-up list that binds this item lives outside the repo (§11.4.215); per §11.4.276(G.2) each follow-up must become an item in the §11.4.93 store. |
| F5 | minor | test-instrumentation | yes | Pre-existing census semantics, not introduced by the landing, but it bounds the truth of the landing's four new rows: reason `no-git-execution` claims "never git", while the census only fails a row when its write detector sees a git WRITE. Own mutant M4 (add `_m4_head=$(git -C "$here" rev-parse HEAD)` to `tests/security/test_forge_branch_protect.sh`) leaves the census PASS. The four rows are true today (every git word in the four files is a host or repository name), but a later git read would make a row false without detection. |
| F6 | nit | process-doc | yes | Fixture-tree row justification names `fake_gh.py` (not a census member, no `git` in its text) and gives `test_history_secret_scan.sh` as the caller; the process that executes the gitleaks shim is `scripts/security/history_secret_scan.sh` (also scrubbed, so the substance is right). |
| F7 | nit | process-doc | yes | `item_history` of CON-402: event 645 (states set at creation) has an empty reason and event 646 records a no-op transition `reproduced-host-fixture -> reproduced-host-fixture`; the UNSET-to-state transitions are not recorded as reasons, unlike CON-314 event 545. Engine-written; listed for completeness. |

### F1 detail (recommend fixing before the push)

Measured with `git show <rev>:docs/guides/full_suite_runner_guide.md | grep -c cm_full_suite_manifest_complete.sh`:
bcac0882 0, fd799642 1, e90d4aea 0, e389b069 0. Main never had the paragraph, so the only way it reached main was
this landing, and it did not. The only path both the vehicle and main changed are this guide and
`config/full_suite_manifest.tsv` (intersection of `git diff --name-only bcac0882 fd799642` and
`git diff --name-only bcac0882 e90d4aea`, C-locale sort, cross-checked in python: exactly these two).
A 3-way `git merge-file` (base bcac0882, ours e90d4aea, theirs fd799642) conflicts only on the generated census
line and keeps the paragraph; the landed file equals that merge minus the paragraph and its blank line (2 lines).
After the landing, no guide or manual in the tree documents the shipped gate (git grep outside docs/qa: only
CHANGELOG.md, the gate, its mutation test, post_update_hook.sh and two tests mention it), contrary to
§11.4.18 / §11.4.257, and the union rule of §11.4.41 step 3 / §11.4.288(B)(1) was not kept for this hunk.
Fix: restore the two lines from fd799642 (the paragraph starting "After adding, renaming or deleting a test file"
plus the following blank line, before "Output goes to"), re-run `--sync-guide` and `--verify-manifest`.
No gate catches this (`--verify-manifest` checks only the census block). If not fixed in the landing, file it as
a follow-up item.

## Claim-by-claim check

### Claim 1: vehicle paths

- `git diff --name-only bcac0882 fd799642`: 1488 paths. `git diff --name-status fd799642 e389b069` limited to them:
  17 files, all M, no A/D, no mode change.
- Placeholders: at fd799642 `CON-PENDING-gitenv*` occurs 12 times in 11 files (the exemptions TSV header holds two);
  at e389b069 zero (`git grep` rc=1; positive control: `CON-402` present in 15 files). Every replacement is the
  stated form; the four "placeholder" notes became "(minted at the landing on main)" (r1, r2, r3 READMEs and
  merge_main/README.md). Other `CON-PENDING-*` strings in the tree belong to other items and are untouched.
- SHA256SUMS: only the lines of edited files changed, plus the landing/ lines in the r4 pack. At fd799642 exactly
  one line was already stale (r1 `./README.md`: actual 1714a1b1..., listed 47e16855...), as the commit says.
  All four packs verify (`sha256sum -c --quiet`: rc 0, 108/175/498/137 lines); every tracked pack file is listed
  (only SHA256SUMS itself unlisted); negative control (one hash byte flipped) fails as expected.
- Guide: census line synced (total=936), but see F1 (a second, undeclared change).
- Manifest: vs fd799642 +10 rows (CON-401's tests/security entries); vs e90d4aea +3 rows (the vehicle's). Union kept.
- Exemptions TSV: header placeholder replaced, five rows appended at the end, nothing else changed.
- r4 README: placeholder line plus the new "Landing on main" section; landing/ is new (5 files).
- Outside the vehicle paths the landing changed exactly: the three scrub files, docs/workable_items.db,
  docs/Issues.md, docs/Issues_Summary.md and landing/ (1499 = 1488 + 11). F2: the "proof in the landing README"
  is missing, the claim itself holds.

### Claim 2: integration of CON-401 code

- Scrub lines: inserted right after the `set` line in the three files; identical to the canonical line
  (list = CL_GIT_SCRUB_VARS, 14 names, GIT_CEILING_DIRECTORIES not cleared). `bash -n` clean; shellcheck finding
  counts unchanged vs main (2 / 46 / 0).
- Census: `PASS - members=629 hermetic=490 exempt=139 unscrubbed=0`, unclassified=0, control needles seen (94).
  `--tsv`: the three files HERMETIC "canonical scrub at line 53/22/34", the seven others EXEMPT under the new rows.
  Reverting the integration on a copy (main's three files, last five rows dropped) gives
  `FAIL - members=629 hermetic=487 exempt=132 unscrubbed=10` with exactly the ten CON-401 files, as claimed.
- Rows, checked against the files: the four `no-git-execution` files contain no git invocation in any form
  (every bare `git` word is `git.m3w.org` or `caf-git-mcp`; they source nothing; the tests run only the scripts
  and python fixtures that contain no `git`); TRUE today, see F5 for how well that is protected. The fixture tree
  is safe: `bin/curl` is not a member, `bin/gh` runs no git, `bin/gitleaks` execs `fake_gitleaks.py`, which runs
  only git reads (`rev-parse`, `for-each-ref`, `ls-tree`, `cat-file`, `log`) with `-C target`; its only executors
  (history_secret_scan.sh, launched by test_history_secret_scan.sh) now clear the class, so `-C` is effective.
- Legitimate callers: history_secret_scan.sh takes remote URLs and works on its own `mktemp` mirror; no documented
  interface uses GIT_DIR or another class variable, so clearing them removes nothing a caller can rely on. On main
  an ambient GIT_DIR made it write needle objects and refs into the caller's repository AND scan that repository
  instead of the mirror, still printing "control OK" and exiting 0 (run hss_main_git_dir below): the scrub also
  removes a false-clean result. The tests set only GIT_AUTHOR/COMMITTER names, outside the class.
- `--help` (sed from line 2 to the set line, last line dropped): byte-identical on main and landed (50 lines,
  no scrub text).
- Mutation anchors: every HM/HR mutant of history_secret_scan.sh still matches exactly once (0 BROKEN) and is killed;
  forge/actions scripts are unchanged, so their anchors are untouched.
- Scrub placement accepted for the right reason: own mutants M1 (line moved below `trap`/`fail()`) and M2 (moved below
  the first `git clone`) both give UNSCRUBBED "not at column 0 in the preamble"; golden-FALSE M7 (moved above the
  `set` line, still preamble and behaviourally equivalent) stays PASS.

### Claim 3: CON-402 row

- Type Bug, status In progress, severity High, current_location Issues; reproduction `reproduced-host-fixture`,
  surface `host-only` (counts as REPRODUCED under §11.4.294(B), honest for a host-script class); investigation
  `root-cause-found-with-evidence`. Status In progress with no Verification line is consistent with §11.4.290(1)
  (no verification job scheduled), not an over-claim.
- Evidence paths `docs/qa/gitenv_class_2026_11_14/red2/arc_git_dir.result.txt` (SENTINEL=CHANGED under GIT_DIR,
  rc 0) and `.../arc_none.result.txt` (UNCHANGED control) are tracked (negative control path absent). They store a
  path without sha256, the same as every other item in this DB.
- No credential in the row or the landing pack (pattern scan, positive control hit 1, row 0, pack 0; no home paths).
- DB vs main: items 366 -> 367 (only CON-402 added), no other item changed, item_history 643 -> 646 (3 new rows,
  no old row changed), meta unchanged.
- `workable-items diff` on a copy: in sync (367 vs 367); negative control (CON-402 status edited in a copy of
  Issues.md) reports 2 differences. `validate`: OK, 367 items. Issues_Summary counts updated (Bug In progress
  19 -> 20, total 356 -> 357), one row added. DB sha256 unchanged by these reads.
- F4 and F7 above.

### Claim 4: re-runs

| Check | Tree | Result |
|---|---|---|
| `python3 scripts/validation/git_env_class_census.py` | e389b069 | rc 0, PASS members=629 hermetic=490 exempt=139 unscrubbed=0 |
| `bash scripts/run_full_suite.sh --verify-manifest` | e389b069 | rc 0, census total=936, RESULT: MANIFEST-OK |
| `sha256sum -c` in the four packs | e389b069 | all rc 0 |
| CM-CONSTITUTION-INDEX-FRESH | e389b069 | PASS |
| CM-GATE-LEDGER-RATCHET | e389b069 | PASS, unimplemented=394 baseline=394 |
| tests/security/test_history_secret_scan.sh | e389b069 | 45/45, rc 0 |
| tests/test_git_env_class.sh | e389b069 | rc 0, passed=142 failed=0 skipped=1 (SKIP B1: submodules/continuum not checked out in my clone), 4m21s |

Sentinel runs (own design: tool copied from docs/qa/gitenv_class_2026_11_14/tools/sentinel_run.sh.txt, sha256
513d0ac2...; target = the SCRIPT itself, not the lander's test, with a fresh local source repository, fake gitleaks
via GITLEAKS, SCRATCH per run):

| Label | Tree | Script | Mode | rc | Sentinel |
|---|---|---|---|---|---|
| hss_main_git_dir | e90d4aea | scripts/security/history_secret_scan.sh | GIT_DIR | 0 | CHANGED (needles written into the caller repo; reported "control OK", findings=0) |
| hss_main_both | e90d4aea | same | GIT_DIR+GIT_INDEX_FILE | 0 | CHANGED |
| hss_main_git_index_file | e90d4aea | same | GIT_INDEX_FILE | 0 | UNCHANGED (the script writes no index) |
| hss_main_none | e90d4aea | same | none | 0 | UNCHANGED |
| hss_land_git_dir / _both / _git_index_file / _none | e389b069 | same | all four | 0 | UNCHANGED (needles found in the mirror, control OK) |
| tst_main_git_dir | e90d4aea | tests/security/test_history_secret_scan.sh (lander's sequence) | GIT_DIR | 1 | CHANGED, 20/45 |
| tst_land_git_dir | e389b069 (committed) | same | GIT_DIR | 0 | UNCHANGED, 45/45 |
| mut_main_git_dir | e90d4aea | tests/security/test_security_scripts_mutations.sh HM1 | GIT_DIR | 1 | CHANGED; CONTROL FAIL history_secret_scan.sh |
| mut_land_git_dir | e389b069 | same, IDs HM1-HM13 HR2 HR4 HR5 HR9 | GIT_DIR | 0 | UNCHANGED; controls ok (3/3), killed 17/17, problems 0 |

An instrument error of my own (an exported `OUT` collided with the tool's own `OUT` variable, so the first
history_secret_scan.sh runs exited 7 in every mode including the control) was caught by the control run and the
runs were repeated with `env -u OUT`; only the repeated runs are reported.

Own census mutants (on the `mut` clone, working tree only, restored after each):

| Mutant | Change | Census | Caught |
|---|---|---|---|
| M1 | scrub line of history_secret_scan.sh moved below `trap`/`fail()` | FAIL, UNSCRUBBED line 55 | yes |
| M2 | scrub line moved below the first `git clone` | FAIL, UNSCRUBBED line 97 | yes |
| M3 | scrub removed and a `no-git-execution` row added for history_secret_scan.sh (a file that runs git writes) | FAIL, unscrubbed=1 | yes |
| M4 | git READ added to the no-git-execution file test_forge_branch_protect.sh | PASS | no (F5) |
| M5 | git WRITE (`update-ref`) added to fake_gitleaks.py under the fixture-tree prefix | FAIL, unscrubbed=1 | yes |
| M6 | GIT_INDEX_FILE dropped from the scrub list in test_history_secret_scan.sh | FAIL, unscrubbed=1 | yes |
| M7 (golden-FALSE) | scrub moved above the `set` line (still preamble) | PASS | correctly not fired |
| M8 | fixture-tree row deleted | FAIL, unscrubbed=3 | yes |

## Not checked

- The full heavy mutation suite (all FM/AM/RM/AR ids, about 60 minutes); only the 17 mutants of the one script
  whose text the landing changed were run.
- forge 168/168 and actions 44/44 were not re-run separately (their scripts and tests are byte-identical to main;
  their controls passed inside the mutation run).
- The vehicle's own content (reviewed at fd799642), as instructed.
