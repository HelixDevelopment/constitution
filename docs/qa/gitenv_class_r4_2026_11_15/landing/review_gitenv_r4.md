# Independent review: gitenv-class vehicle, round 4 merged onto main (whole vehicle)

| Field | Value |
|---|---|
| Reviewer | fresh independent subagent, model Opus; effort could not be set or read on the Agent dispatch path (§11.4.231(F.2)), UNKNOWN, not claimed as xhigh |
| Date | 2026-11-15 |
| Bundle | `<scratch>/handback/gitenv_r4_merge.bundle`, sha256 `1e6c41c36735a84e4d4ae5b5573aaca9eef4f910bdd82e5b7078c82048ddbb61` (re-checked, matches), `git bundle verify` OK |
| Ref | `refs/heads/gitenv-r4` = `fd799642329db8e03a2971313f8b126a63005e9c`; 26 commits not on main `bcac0882` |
| Workspace | `<scratch>/` (clone `repo/`, worktrees `wt_fast`, `wt_merge`, `wt_main`, `wt_rtm2`; outputs `out/`; tools `tools/`). Nothing pushed; the live checkout was not touched |
| Evidence class | gate logic plus host behaviour runs; PROVISIONAL (§11.4.289 / §11.4.290) |
| Verdict | **GO-with-follow-ups** (no source-defect of important or critical severity in the batch; open findings are test-instrumentation and process-doc, plus one pre-existing out-of-batch read-path item) |

## 1. Runs (this session, on fd799642 unless stated)

| Run | Result |
|---|---|
| Census `--tsv` (out/census_head.tsv) | PASS, rc 0: tracked=accounted=6158 (6155 + the 3 files of the final evidence commit), universe=1820, members=619, hermetic=487 (473 canonical, 9 own scrub, 5 cl_scrub_git_env), exempt=132, unscrubbed=0, unclassified=0, 94 control needles |
| `tests/test_git_env_class.sh --fast` ×3 (out/fast_run1..3.txt) | each rc 0, **138 passed / 0 failed / 2 skipped**; the three outputs are byte-identical, sha256 prefix `f3b07b487a1b72a4`, the same hash as the author's runs |
| `run_full_suite.sh --verify-manifest` | `RESULT: MANIFEST-OK`, census total=926 |
| `run_full_suite.sh --sync-guide` on the ff-merged tree | rc 0, guide census line already equal (no change) |
| Evidence pack SHA256SUMS | r4 pack 132 entries OK; r3 pack 498 entries OK |
| `tests/install/test_timeout_tty.sh` | `PASS 25 FAIL 0` |
| Release mutation suite, `--only X15` | `PASS X15 killed by its property (C45)` |
| Release mutation suite, sample of 40 un-verdicted mutants | see section 6 |

## 2. R4-1 and every r3 finding, re-verified with the r3 reviewer's probes (sentinel harness `tools/sent.sh`, copied unchanged)

Positive control (unscrubbed writer `ctl_unscrubbed.sh`): none UNCHANGED 0 hits; gitdir CHANGED 3 hits; both CHANGED 6 hits. The harness sees.

| r3 finding | r3 probe | Now |
|---|---|---|
| R4-1 (writes outside the universe) | `install_upstreams.sh` in a throwaway clone; `progressive/mutation_matrix.py` via `mm_sandbox.py` | install_upstreams: none/gitdir/both all rc 0, UNCHANGED, hits 0 (remotes landed in the clone itself). mm_sandbox: none/gitdir/both UNCHANGED, hits 0. Universe is now the whole tracked tree. **FIXED** |
| R4-2 (readers of sourced libraries) | `multitrack_device_lock.sh --help`, gitdir | gitdir and both: UNCHANGED, hits 0 (r3: 2 hits); `multitrack_fallback_monitor.sh --help` also 0. My mutant R507 (device_lock scrub moved below its `. multitrack_config.sh`) is KILLED. **FIXED** |
| R4-3 (preamble prefix match) | RV4, RV4b | both KILLED. **FIXED** |
| R4-4 (entry-function rows) | RV12 | KILLED. **FIXED** |
| R4-5 (list_clear carriers) | author M11/M12 | not re-probed by me beyond the author's kills; RV5/RV6 (needle tampering) KILLED |
| R4-6 (Go wording) | text | README and docstring now say a Go file is a member only on a detected write. **FIXED** (but see F-R5-6) |
| R4-7 (guards) | decision | `subject-follows-caller` reason with a write check; accepted as a recorded decision |
| Other r3 reviewer mutants | RV5 RV6 RV7 RV8 RV8b RV10 RV11 RV13 re-run on fd799642 | all KILLED (out/rv_mut.tsv). RV8b, which survived in r3, is now KILLED |

## 3. Class-exhaustive hunt with my own instrument

`tools/myscan.py`: reads `git ls-files -s` itself (class cleared), scans EVERY tracked text file (not only the census universe) for invocation shapes: shell command-position git (after `;&|({`, backtick, `$(`, then/do/else/exec/command/env/nice/sudo/xargs), python list and string forms (`["git",`, `subprocess.run("git ...`, `os.system`), `which("git")`, Go `exec.Command(..."git"`, JS child_process, Make recipe lines, and `git <subcommand>` words.

- Control needles (separate temp repo): `git -C "$d" commit` found; `subprocess.run(["git", "init"])` found; `echo digit commit` / `legit add` NOT found; a no-git file NOT found.
- Result (out/myscan.txt): 1304 tracked files carry an invocation shape; every shell, python, JS and Makefile one is a census member. The 895 non-members are data (.log 316, .md 263, .txt 211, .json 33, .tsv 23, .diff 11, .canon 9, .out 5, .toml 4, .yaml 2, .jsonl 2, .mdy 1, .template 1, `.gitignore`/`.gitmodules`/a golden `expected`) plus **11 Go files**. None of the non-members is executable.
- The Go files that execute git (`closure_seam.go:568`, `db.go:698`, `version_tags.go:129`) run only `rev-parse` / read helpers, so they are outside membership by the documented Go rule. See F-R5-6.
- Conclusion: no member is missed by the census within the text-detectable class. The no-letters boundary (RV1–RV3) stays as documented.

## 4. Exemption rows

- 51 rows added by the merges: 49 pinned-fixture, 2 no-git-execution.
- pinned-fixture: every row file I checked is recorded in its pack's SHA256SUMS with a matching hash (38 directly; the 11 land_vehicle rows use repo-root-relative SUMS paths and the hash I spot-checked, `scen_r5.sh` `ce5b7643…`, matches). Reference graph (`tools/pinned_refs.py`, out/pinned_refs.txt): every referencer of a pinned-fixture row is another closed-round docs/qa tool, `config/full_suite_excluded.lock`, or a HERMETIC test (custody_sweep pre-fix copies, run by HERMETIC regression tests, so they run in a cleared environment). No suite or gate runs a pinned writer in an uncleared environment. The rows are true today.
- `scripts/release/redact_cut.sh` (no-git-execution): it runs no git at top level and has no non-comment git command line. Its `rc_net` does `builtin exec "$@"` (callers pass `git ...`), so "runs no git itself" is literally imprecise: it is the exec site of the callers' git. The class is still safe there by construction: `rc_net` un-exports every name outside `_RC_NET_KEEP`/`_RC_NET_CONST`, neither of which holds any of the 14 class names, and it re-checks with a second `compgen -e` census. Wording: F-R5-5.
- `tests/release/env_allow.sh`: GIT_* names appear only as allow-list data; no git command line. Sound.
- All 24 no-git-execution rows: no non-comment git command line in any of them (python `gen_evidence.py` runs only other progressive scripts, which are HERMETIC members).
- F12 judgement: the stretch is real but harmless today; the weakness is that the reason is unchecked (F-R5-1).

## 5. Merge regressions and F9 / F11

- X15: I put the scrub back between `set +x` and `set -u` in `tag_and_release.sh`; `STALE_ONLY=1 --only X15` gives `FAIL X15 STALE` (stale=1). On the head it gives `PASS X15 applies` and the full `--only X15` run kills it by C45. Polarity confirmed.
- test_timeout_tty: making `nocomment()` return its input unchanged turns the test BLIND, rc 2 ("control needles failed"); the head gives 25/0. Polarity confirmed.
- F9, all 33 files (`tools/f9_check.py`, out/f9.txt; shellcheck 0.11.0, `-x`, head versus the same file with the scrub moved above its directive): **29 same count, 4 differ**. In `scripts/fastcycle/tests/test_capture_fc_timer_triplet.sh`, `test_fc_commit_stage_timer_mutations.sh` and `test_fc_commit_stage_timer_red.sh` the displaced `# shellcheck disable=SC2015/SC2016` now precedes the FIRST command, so shellcheck applies it to the whole file: head 0 findings versus 17, 16 and 23 with the directive in place (56 findings hidden). In `scripts/translation/render-articles.sh` the `source=` directive no longer reaches the `.` line: head 1 finding (SC1091) versus 0. Totals head 310 / fixed 365. The README claim "three checked, unchanged" does not hold for these four. F-R5-3.
- F11 (`sha256sum -c` over every tracked SHA256SUMS, main bcac0882 versus head): main already has 726 failing lines; the vehicle adds exactly 2: `docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh` and the vehicle's own `docs/qa/gitenv_class_2026_11_14/README.md` (stale since the round-2 commit 005bcfd1). No gate, hook or the full-suite runner reads any SHA256SUMS (searched scripts/gates, scripts/hooks, run_full_suite, tests/*.sh), and `--verify-manifest` is MANIFEST-OK, so nothing breaks. F-R5-4.

## 6. Mutants

### My own (none written by the author), census + `--only-census` (out/r5_mut.tsv)

| Id | Mutation | Result |
|---|---|---|
| NONE | control | SURVIVED (expected) |
| R501 | one canonical line drops GIT_INDEX_FILE | KILLED |
| R502 | GIT_INDEX_FILE dropped consistently from CL_GIT_SCRUB_VARS and every scrub | KILLED (BLIND, plus C1c/C1d) |
| R503 | live gate `cm_agent_type_label.sh` loses its scrub and gets a `pinned-fixture` row | **SURVIVED** |
| R504 | new executable under fixture-tree `scripts/gates/fixtures/jev/bin/` running `command git … commit` | KILLED |
| R505 | `derive_release_facts.sh` own `unset -v` scrub moved below its first git call | **SURVIVED** (confirms F13) |
| R507 | `multitrack_device_lock.sh` scrub moved below its library `.` | KILLED |
| R508 | top-level git READ added to no-git-execution `redact_cut.sh` | **SURVIVED** |
| R509 | git WRITE in a new function of `redact_cut.sh` | KILLED |
| R510 | a member deleted from the worktree only | KILLED |
| R511 | new Makefile recipe `git -C … commit` | KILLED |
| R512 | new python `os.system("git … commit")` | KILLED |
| R513 | python scrub moved inside `if True:` | KILLED |
| R514 | NEW unscrubbed writer `scripts/r514.sh` with a `pinned-fixture` row | **SURVIVED** |

Survivor analysis on the real tree:
- R503/R514: `pinned-fixture` is accepted for any path without a check. Real tree: all 52 pinned rows verified (section 4). F-R5-1.
- R505: real tree: all 9 own-scrub files (incl. the 3 release scripts relying on the LEGACY `unset -v` form this vehicle introduced) place the scrub before their first git line (checked line by line). F-R5-2.
- R508: real tree: no no-git-execution row has a git command line. F-R5-5.

### Release tooling mutation sample (F10)

How the sample was chosen:
- The 383 names come from the author's `STALE_ONLY` listing. The verdicted ones are the names in the author's 3 h partial run (137 plus the control lines).
- That leaves **246** names with no verdict on the merged tree.
- I took every 6th of the 246: A1 A2 A8 AN13 AN20 AN26 AN31 AN37 AN42 B1 B4 CW1 CW6 G1 G6 GN3 H3 J5 K6 MR5x NN1 NN15 NN6 NR11 NR17 NR22 NR27 NR33 NR9 PN14 PN2 PN8 RD1 RM20 RM30 RM9 RR8 RT19 W12 W6.
- X15 was added.

How it ran: each name with `--only NAME`, which also re-runs the suite's controls, in two worktrees of fd799642. It took about 150 s per mutant, concurrency 2, with a load guard (out/rtm_sample_res.tsv, sha256 `41b4d82a6943907fb10ed7736b14b0d0e08e5f3a1b9ded92f781d8cb2f617471`; out/rtm_X15.txt).

Result: **41/41 KILLED, 0 survived, 0 stale, 0 control failures.** 32 were killed by their target property, 8 by a named FAIL of their property group, and X15 by C45.

The remaining ~206 un-verdicted mutants are still unmeasured. This sample is evidence, not proof:
- all 383 apply (STALE_ONLY);
- the vehicle's only change to the release scripts is one scrub line each, and the netgate pin diff shows nothing else;
- the release suites are rc 0 in both sentinel modes.

My judgement is that F10 can ride as a follow-up. Plan:
- before the next release tag (§11.4.40), run the full 383-mutant suite on the landed head, about 8 h, or add sharding to the suite;
- record the verdict per mutant.

## 7. Findings

| Id | Finding | finding_layer | severity | Blocking |
|---|---|---|---|---|
| F-R5-1 | `pinned-fixture` (and the 49 rows it now carries) is not validated against the file: a live gate or a new writer under scripts/ can be exempted by a row alone (R503, R514 survive). The real rows are true (sha256 recorded, no uncleared runner). Fix: require the path to be listed with a matching hash in a SHA256SUMS or the excluded lock and not referenced by a manifest entry or non-docs code; or a dedicated `closed-evidence-tool` reason restricted to `docs/qa/**` (F12) | test-instrumentation | important | no (§11.4.235(D); current instances verified) |
| F-R5-2 | F13 confirmed: own-scrub (LEGACY) placement not checked (R505 survives). Real 9 instances correct | test-instrumentation | minor | no |
| F-R5-3 | F9: 4 of 33 displaced directives change shellcheck: 3 disable directives became file-wide (56 findings hidden), 1 source= directive lost (SC1091). README "unchanged" claim wrong for those. Fix: move each scrub above its directive (or the directive below the scrub) | test-instrumentation (lint scope; no behaviour change) + process-doc | minor | no |
| F-R5-4 | F11: 2 newly stale SHA256SUMS lines (one in the vehicle's own r1 pack); no gate reads them | process-doc | minor | no |
| F-R5-5 | no-git-execution rows are checked for writes only; a git read passes (R508). redact_cut.sh row text "runs no git itself" is imprecise (rc_net is the exec site of callers' git; safe by its allow-list). Fix: check reads too for this reason, and reword the redact_cut row | test-instrumentation + process-doc | minor | no |
| F-R5-6 | Pre-existing, out of batch: Go read paths under an ambient GIT_DIR read the wrong repository: `closure_seam.go` `currentArtifactFingerprint` (`git -C dir rev-parse HEAD`, a closure-seam fingerprint), `db.go` timer fingerprint, `version_tags.go`. Documented Go boundary; file as its own item (§11.4.201 subject drift) | source-defect (pre-existing, not introduced) | minor | no (not part of this batch) |
| F-R5-7 | F10: about 246 release-tooling mutants carry no kill verdict on the merged tree; see section 6 sample | test-instrumentation | important | no, with the plan below |
| F-R5-8 | Scope note: GIT_CONFIG_* / GIT_CONFIG_PARAMETERS stay outside the 14-name class (documented). One probe: `GIT_CONFIG_COUNT/KEY/VALUE core.worktree=<foreign>` did NOT redirect `git -C A checkout -- f` (A restored, foreign dir untouched). `core.hooksPath` injection not measured | process-doc | nit | no |

## 8. Merge dry-run and what the lander must do

- `bcac0882` is an ancestor of `fd799642`; in scratch worktree `wt_merge`, `git merge --ff-only fd799642` from bcac0882 fast-forwards cleanly (no conflicts). The filewave2 source repo's main is still bcac0882.
- Placeholders to replace with an engine-minted id above CON-400 (highest id in docs/Issues.md + docs/Fixed.md is CON-400): `CON-PENDING-gitenv-class` (4), `-r2` (2), `-r3` (3), `-r4` (3), in `config/git_env_class_exemptions.tsv`, `tests/test_git_env_class.sh` (comment), `scripts/helix_code/helix_code_home.sh` (comment), and the README/FOLLOW_UPS files of the four gitenv packs and `docs/qa/manifest_sonarqube_2026_11_13/README.md`.
- After the replacement: re-run the census (comment-only edits), regenerate the touched packs' SHA256SUMS (the r4 pack's README is listed there), `run_full_suite.sh --sync-guide` then `--verify-manifest`; check the netgate pin is untouched (none of the placeholder files is netgate-pinned to my reading, UNCONFIRMED).
- Re-run fast tier once on the landed head.

## 9. Safety

No llmctl enable, no hosted calls, no credentials, no pushes, no force, no history rewrite. All work under `<scratch>` with TMPDIR `<tmp>`. Heavy runs under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, at most 2 concurrent; load stayed below 36. Fixture mutant texts are fake. Every mutant worktree removed.

## 10. Verdict

**GO-with-follow-ups.** R4-1 and all r3 findings are fixed and re-proven with the r3 probes; the closed-world census holds against an independent whole-tree instrument; fast tier 138/0/2 ×3 byte-identical; manifest OK; the two merge regressions are fixed with verified polarity. Follow-ups: F-R5-1 .. F-R5-8 (F-R5-1 and F-R5-7 important test-instrumentation, to be closed before the next release tag; F-R5-6 filed as its own item).
