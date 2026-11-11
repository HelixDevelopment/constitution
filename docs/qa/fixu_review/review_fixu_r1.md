# Independent review: fixu vehicle (bdc3ac43..270e4867, 12 commits)

| Field | Value |
|---|---|
| Reviewer | independent subagent, not the author (§11.4.142, §11.4.240) |
| Substrate | Opus (claude-opus-5-5) as dispatched; effort xhigh requested by the conductor; the effort actually applied is not readable from inside the run (§11.4.231(F.2)), so it is not claimed |
| Date | 2026-11-06 |
| Subject | `S/scratchpad/fixu/fixu.bundle` |
| Bundle check | sha256 `875d64c5d4ccec75c6a104d25fc8c300f4acc085188f3bee74774336a0a82bbe` (match); head `270e4867deb171d3ae67a03fbe45a2d5528e3da3` (match); `git rev-list --count bdc3ac43..HEAD` = 12 (match) |
| Clones | `S/scratchpad/rvx/constitution` (head), `rvb/constitution` (base bdc3ac43), `rvm/constitution` and `rvtmp/*` (mutants). Live checkout not touched, nothing pushed. All four are retired with `safe_rm_rf` after the last run; `rvev/` (evidence) and `rvscripts/` (reviewer scripts) are kept |
| Evidence | `S/scratchpad/rvev/` (paths below are relative to it). `S` = `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46` |
| Host | `/bin/sh` is dash; GNU grep 3.12 in child shells (the interactive harness `grep` function, which routes to ugrep, is not exported to child shells, checked) |

## Verdicts

| Item | Verdict | Blocking finding |
|---|---|---|
| CON-108 review_record_genuine.sh POSIX | GO | none |
| CON-109 ruler suite discovery + redpin RED_MODE | **NO-GO** | F109-1 (important, source-defect): a vendored consumer reached through a symlinked path silently loses its device-tree ruler tests and still passes. This is a regression against the base. |
| CON-110 persistent-launch XDG_RUNTIME_DIR | GO-with-follow-ups | none |
| CON-111 AF_UNIX socket | GO | none |
| CON-112 select_sample restored symbols | GO-with-follow-ups | none |
| CON-113 env-census allowlist row for an eval | GO-with-follow-ups | none |
| CON-047 known rows (rc_3) | GO | none |
| CON-114 sa_session_alive under pipefail | GO-with-follow-ups | none |
| CON-089 lumen absent prerequisite | GO-with-follow-ups | none |
| CON-099 slicer case-insensitive | GO-with-follow-ups | none |
| CON-119 round8 fixture .gitignore | GO | none |
| Tracker commit 7b51c4bf (+ tracker rows in the other commits) | GO-with-follow-ups | none |
| resolve1 lock proposal (not applied; the operator decides) | correct in substance; two errors in its steps | see P-1 and P-2 |

The vehicle as a whole is **not ready to land as one unit while F109-1 is open**. The other ten fix commits are independent of `test_multitrack_ruler_suite.sh`, so they could land without CON-109's commit c1881ae1. The redpin half of c1881ae1 is GREEN; only the ROOT detection needs fixing.

## Per-item review

### CON-108: `scripts/fastcycle/tests/lib/review_record_genuine.sh` (GO)

- **RED (base) and GREEN (head) under dash.**
  - Base: all three `/bin/sh` users abort at line 119 with a bash-array syntax error. Evidence: `u1_B_sh_backfill_evidence_r2_regression.out`, `u1_B_sh_evidence_hash_r5_regression.out` and `u1_B_sh_finding_layer_red.out`.
  - Head under sh: backfill 11/0, evidence_hash 7/0, finding_layer 21/0. Evidence: `u1_H_sh_*`.
  - Head under busybox: evidence_hash r5 7/0 (base fails). Evidence: `u1_H_busybox_r5.out` vs `u1_B_busybox_r5.out`.
  - Bash users still pass at head: gate_authority r1 44/0, r2 39/0, r3 71/0. Evidence: `u1_H_bashuser_r{1,2,3}.out`.
- **Reviewer mutants** (`u1m_M{1,2,3}_*`):
  - M1 moved the caller's extra options before the fixed ones, so a caller override is lost. Killed: gate_authority_r1 43/1, "B1-H ... opus/? disagrees with --tier/--effort opus/xhigh".
  - M2 dropped `"$@"`. Killed: r1 41/3.
  - M3 always passed `--precheck` even under `RR_NO_PRECHECK=1`. It survived, and it is EQUIVALENT: `review_record.py:1061` defaults `precheck_path` to `<batch dir>/precheck.json`, and the branch deletes that file, so passing or omitting the flag reaches the same `precheck_used=False`. The author's "known gap" mutant (drop `--precheck`) is equivalent for the same reason.
- **N108-1 (nit, process-doc).** The commit and comment say "POSIX again", but the file uses `local`, which POSIX does not define; dash and busybox accept it. Say "dash/busybox compatible" or drop `local`.

### CON-109: ruler suite discovery and redpin RED_MODE (NO-GO)

**Discovery fixture** (`S/scratchpad/rvscripts/ruler_fixture.sh`; output `con109_fixture_rvb.txt` and `con109_fixture_rvx.txt`; evidence directories `con109_{base,head}_C5_evidence/`). Every run used `env -i` with members that are stub tests:

| Case | Base | Head |
|---|---|---|
| C1 standalone canon, pass plus skip | rc 2, TOTAL=0 | rc 0, both members found |
| C2 standalone, all skip | rc 2 | rc 77 with a reason |
| C3 standalone with a fail | rc 2 | rc 1 |
| C7 sibling `constitution` dir | rc 1 (hijacked) | rc 0, own members |
| C6 canon named `constitution`, non-git parent | parent's device test included | excluded (correct) |
| C4 vendored consumer, physical path | 3 tests | 3 tests |
| C8 relative invocation | 3 tests | 3 tests |
| C9 nested repo | 3 tests | 3 tests |
| **C5 the same consumer reached through a symlink** | root `…/c5link/P`, 3 tests including `test_multitrack_dev.sh` | root `…/c5link/P/constitution`, **2 tests, device roster dropped, rc 0** |

**F109-1 (important, source-defect, NO-GO).** The new ROOT test compares a logical path with a physical one:

```sh
_parent=$(cd "$CANON/.." 2>/dev/null && pwd)                       # logical
[ "$(cd "$_parent" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" = "$_parent" ]  # physical
```

When the canon is reached through a symlinked directory, `git rev-parse --show-toplevel` returns the physical path and the test is false. ROOT then falls back to the canon, the consumer's device ruler tests are not discovered, and the suite reports PASS over fewer tests. That is a silent coverage drop (a false green). The base handled this case. Classification under §11.4.235(D) and §11.4.201(1)/(2): the slice delivers suite discovery, and the defect makes that deliverable report PASS while skipping real tests, so it is a source-defect (the conservative default also applies), severity important.

- **Fix:** compare physical paths on both sides. For example, set `_parent=$(cd "$CANON/.." && pwd -P)` and keep the `pwd -P` comparison you already use for `$CANON`, or compare `git -C "$_parent" rev-parse --show-toplevel` against `$(cd "$_parent" && pwd -P)`.
- **Add C5** (and C1, C2, C3, C7) as an in-tree meta-test (see F109-3).

**Redpin RED_MODE leak: GREEN.**
- Base under `RED_MODE=0` ran two passes: 23/0, then 17 PASS / 10 FAIL.
- Head: 27/0 with `RED_MODE=0` and 27/0 with `RED_MODE` unset (`u3_redpin_{base_RM0,head_RM0,head_unset}.out`).
- Reviewer mutant: dropping the `RUN_RED_MODE` passthrough gave 27/0 (`u3_redpin_mut_noRUNREDMODE_RM0.out`). It is equivalent, because no caller sets `RUN_RED_MODE` in these runs.

**Real tree under `env -i`:** all members ran (`ruler_head_envi/`; e.g. alias_priority 28/0, bootstrap 9/0, rb02 31/0 with 2 SKIP). `monday_dryrun` SKIPs with "consumer-project fixture absent", which is correct for a standalone canon.

**SKIP semantics:** an all-skip run exits 77 with `reason=topology_unsupported` on the last line, a FAIL exits 1, and zero tests exits 2. There is no SKIP followed by exit 0.

- **F109-2 (minor, test-instrumentation).** The aggregate SKIP reason is hard-coded to `topology_unsupported` whatever the members reported. A member that skipped with `artifact_not_yet_built` would be restated as a different §11.4.69 code. Fix: propagate the members' reason when they share one, otherwise name the mixed set.
- **F109-3 (minor, test-instrumentation).** Nothing in the tree pins the aggregator's discovery and exit semantics (C1 to C9 above). The reviewer's fixture proves them today; land it as a test so F109-1-class regressions are caught.

### CON-110: persistent-launch `XDG_RUNTIME_DIR` (GO-with-follow-ups)

- **RED/GREEN under `env -i`.** Base reports "SKIP: systemd --user bus unreachable (reason: topology_unsupported)" (`u2_rvb_envi.out`). Head runs PASS=3 FAIL=0: T1 RED characterisation, T2 GREEN, and T3 MUT (`u2_rvx_envi.out`). The base SKIP was a false SKIP, because the bus was live.
- **Exit semantics:** an absent UUT is now FAIL exit 1, which is correct; a missing canon file is not missing topology. SKIP stays exit 77, never exit 0.
- **F110-1 (minor, test-instrumentation).** When `XDG_RUNTIME_DIR` is set to a directory without a bus while `/run/user/<uid>/bus` is live, the test still SKIPs. The derivation only runs when the variable is empty, so this is a false SKIP in the opposite direction.
- **F110-2 (minor, test-instrumentation).** The derivation requires the socket to be owned by the user (`-O`), but the FAIL branch tests only `-S`. A live bus not owned by the user gives FAIL instead of a reasoned SKIP or BLIND.
- **F110-3 (minor, process-doc).** The inline derivation duplicates what CON-117's planned helper will do. When CON-117 lands, replace the duplicate with a call to the helper, and track that in CON-117.

### CON-111: AF_UNIX socket (GO)

- **RED:** under a long `TMPDIR`, base crashes with `OSError: AF_UNIX path too long` (`u4_rvb_LONG.out`).
- **GREEN:** head runs pass=140 fail=0 skip=12 with both long and short `TMPDIR` (`u4_rvx_{LONG,SHORT}.out`).
- **Reviewer mutant:** dropping the chdir-back in `finally` gave 140/0 (`u4_mut_nochdirback.out`). It is equivalent for this test, because every later path is absolute. The second bind (lines 886-890) already uses the same pattern.

### CON-112: `select_sample.py` restored symbols (GO-with-follow-ups)

- **§11.4.124 history check.**
  - `retroactive_state`, `UNPARSEABLE_REASON` and the classify branch are byte-identical to ee581e37's version.
  - f77a7851 removed them while touching four other files; the patch-ids of those four files are unchanged, so nothing else from f77a7851 was overwritten.
  - No caller depends on the removal: `cycle_report.py` and the other users import `detect_retroactive_registration`, which keeps its boolean contract.
- **RED/GREEN** (`u6_*`):
  - At base, the r5 regression test cannot apply two mutation anchors ("anchor drifted": SS_N3 and R3). At head both apply.
  - `test_unparseable_timestamp_regression.sh` passes at both commits.
- **Reviewer mutant:** keeping an unparseable item as a sample (`elif rstate == "unparseable": pass`) is killed. The test reports "NOT ok unit+integration: tri-state parity, exclusion reason" and rc 1 (`con112_mut_unparseable_kept.out`).
- **Downstream:** see the appendix.
- **F112-1 (minor, test-instrumentation).** `check_mutation_anchors.py` covers only `test_fastcycle_r6_mutations.sh` and `test_baseline_replay_worktree_cleanup.sh`. Its output is identical at base and head (`u6_anchors_{rvb,rvx}.out`: mutants=393, drift=0), so it is blind to the select_sample anchors. The commit's anchor-census evidence therefore proves nothing about this file. Extend the census, or stop citing it for this file.
- **F112-2 (minor, process-doc).** The r5 test still reports NOT ok for S3, S5 and S6 ("live tracker DB unavailable" or "live snapshot unavailable") in a clean clone at head, so the unit is red in the full suite. The tracker item does not name the item that owns those three cases.
- **N112-1 (nit).** The docstring says "normal" for the no-history case, while the old wording said "none". Make the wording consistent.

### CON-113: env-census allowlist row for `<eval>` (GO-with-follow-ups)

- **Is the row legitimate?** Yes. `cm_github_issues_source_anchor_wired.sh:334` evals the fixed string `case "$DG" in CM-?*) grep -F -q -- "$DG" "$BLK" ;; *) false ;; esac`.
  - `DG` is read at line 332 from the gate's own deferrals TSV, and `BLK` is a local temp path (line 179).
  - Both are quoted inside the eval string, so the eval reads no environment variable and cannot inject.
  - RED/GREEN: base VERDICT FAIL, uncovered=1 at :334 (`u11_gate_rvb.out`); head VERDICT PASS, allowlisted=117 uncovered=0 needle=ok (`u11_gate_rvx.out`).
- **Reviewer mutants:**
  - A direct env read added to the same file is caught: UNCOVERED at :348 `GITHUB_ISSUES_FORCE_PASS` (`u11_mut_direct.out`).
  - A second `eval "SNEAK=\$GITHUB_ISSUES_FORCE_PASS"` in the same file **survives** (`u11_mut_second_eval.out`, VERDICT PASS).
- **F113-1 (minor, test-instrumentation; class recurrence).** `<eval>` allowlist rows are file-scoped, so any later env-reading eval in that file is hidden. The class covers 8 rows: 5 sibling `*_anchor_wired.sh` gates with the same pattern plus 3 libraries (control token count 0). This change adds one more instance. Suggest line- or content-hash-scoped `<eval>` rows, under CON-047's structural rewrite or a new item.

### CON-047: known rows `reason:rc_3` (GO)

- Both tests run `set -uo pipefail` without `set -e` and have no other `exit 3` path. Exit 3 is reachable only when fail=0 and known>0.
- KNOWN cases are signature-pinned. `kcase_` in jq_regions requires exactly one jq-env row at the pinned line, otherwise it records FAIL or XPASS. Closure N3 requires rc 1, one UNCOVERED jq-env row in the named gate, and no UNRESOLVED-SOURCE; anything else is `chk 1`, a FAIL.
- So the rc_3 row cannot hide a different failure.
- Runner match: exact path plus `reason:rc_3`. Measured: jq_regions rc 3 with 52 passed, 0 failed, 5 known; closure rc 3 with 31 passed, 0 failed, 1 known (`u47_*`). Exit 1 still fails the run.
- **F047-1 (minor, test-instrumentation).** The match is on the reason only. If a later KNOWN case pinned to a different item is added to either test, its rc 3 is attributed to CON-047.
- **F047-2 (minor, process-doc).** No detector flags a stale row once CON-047 closes. The table comment says "remove both rows", but nothing enforces it.

### CON-114: `sa_session_alive` under pipefail (GO-with-follow-ups)

**Decisive experiment** (own; `S/scratchpad/rvscripts/prim_probe.sh` and `alive_probe.sh`):

| Probe | Base reader (`tr \| grep -qx`) | Head reader (`grep -qzxF`) |
|---|---|---|
| Primitive, one live pid, 120 KB environment (`con114_primitive_big.txt`) | 0/500 matches; PIPESTATUS `141 0`, i.e. grep matched, tr died of SIGPIPE, pipefail turned it false | 500/500 |
| Full `sa_session_alive`, live peer with 120 KB environment (`con114_full_*_big.txt`) | 0/20 alive | 20/20 |
| Full `sa_session_alive`, live peer with 2 KB environment (`con114_full_*_small.txt`) | 20/20 | 20/20 |

- **Controls** (`con114_neg_*.txt`): positive exact 1/1 everywhere; absent 0; prefix 0.
- **Regex-dot control.** Probe `…/dot.test` against a live `…/dotYtest`: base gives **1** (a false alive, because the base reader matched as a regex), head gives 0.
- **Primitive controls:** absent, prefix and dot all 0/50 for both readers (`con114_primitive_neg_*.txt`). The primitive dot control runs in the non-discriminating direction; the full-function control above is the discriminating one.
- **End to end through the CLI** (own mutant of the test: the CONCURRENCY live peer is given a 100 KB environment):
  - With the head library: 39 passed, 0 failed.
  - With the base library swapped in: 36/3, "CONCURRENCY: skill stripped while another session held it", "CONCURRENCY: prune STRIPPED a skill another live session holds" and LIVENESS 0/3 (`con114_test_e2e_{head,baselib}.out`).
  - This confirms the product defect on both the deactivate path and the prune path, and the fix.
- **Side effect at base:** the reader printed "Permission denied" to the caller's stderr, because `<` is applied before `2>/dev/null`. The head reader opens the file inside grep, so this is gone.
- **Reviewer mutants:** dropping `-F` gives 39/0 (survived); dropping `-x` gives 39/0 (survived) (`con114_test_mut{F,X}.out`). Both reintroduce a false alive, one for a regex metacharacter and one for a prefix, as the controls show.
- **F114-1 (minor, test-instrumentation).** The suite pins only the pipefail case, not exact-literal matching. Add one live-peer case whose directory contains `.` (probe a sibling name) and one with a strict-prefix name. A false alive fails safe (it keeps a skill), hence minor.

### CON-089: lumen absent prerequisite (GO-with-follow-ups)

- **Behaviour.**
  - Absent, base: stdout "SKIP: lumen binary not found", rc 2. The message and the verdict disagreed, because the runner records FAIL rc_2.
  - Absent, head: stderr "FAIL: prerequisite absent … operator decision O3", rc 2.
  - Present (`LUMEN_BIN` set, sandbox HOME): RESULT PASS at both commits (`con089_rv{b,x}_{absent,present}.*`).
  - The mktemp directory is removed after the present run: the sandbox TMPDIR was empty afterwards, while the run created `lumenignore_test.*` during it.
- **§11.4.69 / §11.4.289(E).** No closed reason code fits "tool not installed", and inventing one is forbidden, so exit 2 with an honest FAIL message, pending O3, is the §11.4.201(4) conservative choice. It is not a FAIL disguising a SKIP-able condition. O3 is correctly recorded as pending (`docs/CONTINUATION.md:52`).
- **Reviewer mutant:** reverting the cleanup to an unguarded `rm -rf "$W"` changes no observable output in any run. It is equivalent while `W` is set, because the guard is defence in depth. See F089-1.
- **F089-1 (minor, test-instrumentation, §11.4.287(C)(3)).** `W=$(mktemp …)` is not checked. With an unwritable TMPDIR the test continues with `W=""` and writes to `/repo`, `/scope.json` and `/a.ignore`. Measured: `mkdir: Permission denied`, rc 1 (`con089_mktemp_fail.out`). It is harmless only because the run is not root. Add `[ -d "$W" ] || { echo "FAIL: mktemp" >&2; exit 2; }`.
- **F089-2 (minor, process-doc).** The CON-089 description says "per operator decision O3" as if O3 were decided, while the code comment correctly says it is pending.
- **F089-3 (minor, process-doc).** The runner half is not done (`ENV_BASE` does not pass `LUMEN_BIN`, and there is no preflight), so the unit still FAILs rc_2 in the full suite on a host where lumen is installed. That is consistent with Status Queued; keep it open until the runner half lands.

### CON-099: slicer case-insensitive (GO-with-follow-ups)

- **RED/GREEN under dash:** base 15 ok / 1 NOT ok (B1: dash prints "Syntax error"); head 16/0 (`con099_rv{b,x}.out`).
- **Reviewer mutant:** reverting the second hunk (`.lower()` in the C2a check) gives 16/0, so it survives (`con099_mut_nolower.out`).
- **Masking, confirmed on the real `precheck_pack.sh` output.** The parse check's evidence is "…: 11: Syntax error: …". Without `.lower()` it would not match, but C2a ORs it with the shellcheck `SC2086` evidence, which matches. With the SC2086 entries removed, head gives YES and base gives NO.
- **F099-1 (minor, test-instrumentation).** C2a accepts either the parse leg or the shellcheck leg, while the golden case requires both (the in-file comment says so). Require a parse FAIL citing "syntax error" (case-insensitively) AND a shellcheck FAIL citing SC2086. This is pre-existing, but it is the reason the new `.lower()` is untested.

### CON-119: round8 fixture `.gitignore` (GO)

- **RED/GREEN** under `env -i HOME=<tmp> PATH=/usr/bin:/bin bash`: base PASS=125 FAIL=2 (CM-2 porcelain not empty, CM-3 rc 3); head PASS=127 FAIL=0 (`con119_rv{b,x}.out`).
- **Reviewer mutant:** a non-ignored stray untracked file in the fixture submodule before CM-2 makes CM-2 and CM-3 FAIL again (`con119_mut_stray.out`). So the copied `.gitignore` (which ignores `__pycache__/`, `*.pyc`, env files and others) does not blind the porcelain check.
- **N119-1 (nit, class recurrence note).** `round7` copies the same list without `.gitignore`, but it has no porcelain check, so it is latent there.

### Tracker commit (7b51c4bf) and tracker rows (GO-with-follow-ups)

- **Engine check on a copy of `docs/workable_items.db`:** `validate` reports OK with 117 items. `diff --issues docs/Issues.md --fixed docs/Fixed.md` reports in sync, 117/117. Every reproduction and investigation evidence path of CON-108..119 resolves.
- **T-1 (minor, process-doc).** All 12 new items have an empty `reproduction_env`, so every Reproduction line renders `reproduced-host-fixture — UNREPRODUCED` (states.go reproLabel). No item can reach VERIFIED-DONE until `--reproduction-env` is recorded (§11.4.292(C), §11.4.294(B)). The evidence exists, so this is one `update --reproduction-env` per item.
- **T-2 (minor, process-doc).** CON-089, CON-099 and CON-119 are fixed in this vehicle but still Queued, while CON-108..114 moved to In progress. Make the status consistent.
- **CON-115..118 read.** They are well formed and honestly labelled (CON-116 and CON-118 have `root-cause-unconfirmed`).
  - CON-118 records that case C2 does `chmod 000` on the real `slicer.py` and `precheck_pack.sh`. There is an EXIT/INT/TERM trap that restores the modes, but a SIGKILL leaves two tracked files unreadable, and parallel readers fail meanwhile. That is a data-safety-adjacent danger zone, so consider raising CON-118's severity, or splitting the chmod hazard into its own item.
  - CON-117's 13-file user-bus class includes product code. Its fix should absorb F110-3.

## Proposal: `fixu/resolve1_lock_diff_PROPOSED.txt` (assessed, not applied to any real tree)

- **Substance is correct.**
  - Both files are argv-driven: `sys.argv[1]` / `[2]`, and IndexError with no arguments (rc 1 standalone, measured).
  - `test_resolve1.sh` (lines 59, 65, 93, 94, 103) and `test_resolve2.sh` (line 53) invoke them.
  - `tool` is in `EXCL_CATS`, and both names are test-named, so the `override:` prefix is required and present.
  - The proposed lock hashes are exactly sha256(note)[:16] as `excl_check` computes them: `b936cad3425d32bc` and `949a083d5d9e16cd`, recomputed and matching.
- **P-1 (minor).** The procedure is incomplete. After applying the two manifest rows in a scratch clone, `--verify-manifest` reports two problems: the lock difference and "docs/guides/full_suite_runner_guide.md: census block is stale (run --sync-guide)", because py/excluded goes 22 → 24 and py/member 26 → 24. After `--sync-guide`, only the lock problem remains (`proposal_verify_*.out`, `proposal_sync_guide.out`). Add `--sync-guide` before the acceptance.
- **P-2 (minor).** "rows 57 -> 59" does not match this tree. The head lock and the manifest both have 52 excluded rows (last acceptance `rows=52`), so the result would be 52 → 54. Hand-adding the lock rows is also unnecessary, because `excl_accept` rewrites the whole body from the manifest.
- **Note.** A reviewer ran the acceptance step in no tree; it needs a roster operator id, which is the operator's act.

## Findings by severity

| Id | Severity | Layer | Item |
|---|---|---|---|
| F109-1 | important | source-defect | CON-109 (blocks) |
| F109-2, F109-3 | minor | test-instrumentation | CON-109 |
| F110-1, F110-2 | minor | test-instrumentation | CON-110 |
| F110-3 | minor | process-doc | CON-110 |
| F112-1 | minor | test-instrumentation | CON-112 |
| F112-2 | minor | process-doc | CON-112 |
| F113-1 | minor (class recurrence, 8 rows) | test-instrumentation | CON-113 |
| F047-1 | minor | test-instrumentation | CON-047 |
| F047-2 | minor | process-doc | CON-047 |
| F114-1 | minor | test-instrumentation | CON-114 |
| F089-1 | minor | test-instrumentation | CON-089 |
| F089-2, F089-3 | minor | process-doc | CON-089 |
| F099-1 | minor | test-instrumentation | CON-099 |
| T-1, T-2 | minor | process-doc | tracker |
| P-1, P-2 | minor | process-doc | proposal |
| N108-1, N112-1, N119-1 | nit | process-doc | |
| F-PRE-1 | important | test-instrumentation (false PASS) | pre-existing, outside the range; needs a new item |
| F-PRE-2 | minor | test-instrumentation | pre-existing, outside the range; same class as F112-2 |

**Pre-existing findings found while reviewing (not in the reviewed diff, not blocking these items).**
- **F-PRE-1 (important, test-instrumentation, false PASS).** `scripts/multitrack/test_multitrack_supervisor_wiring.sh` step (f) starts a real watch daemon with `MT_SUPERVISOR_WATCH_INTERVAL=99872<iter>`. It kills only the daemon's `sh` pid (lines 534-537, and the trap at 229-246 does the same), so the daemon's foreground child `sleep 99872<iter>` (`multitrack_supervisor.sh:323`) is orphaned to the user manager and lives about 11.5 days. The step then reports `GREEN(f2): watch daemon ... killed cleanly by this test, no orphan left (§11.4.14)`. That PASS is false: it checks the parent pid only. Measured on this host: 37 orphaned `sleep 998721`..`998723` processes, uid 1000, ppid 2441 (the user manager), `TMPDIR` or cwd inside my clones, all from my CON-109 redpin runs, which drive this test. The file is byte-identical at base and head (`git diff --stat bdc3ac43..HEAD` is empty for it), so the defect predates this vehicle. This is the §11.4.201(12) checklist class: an early disarm orphans a `sleep` grandchild. Fix: kill the daemon's process tree, children first by `/proc/<pid>/task/*/children` or `pkill -P`, never by process group (§11.4.263). Then make f2 assert that no process carrying the interval token remains, using a real-cmdline scan with a control needle. Product side, UNCONFIRMED (not measured): stopping the production watch daemon the same way would leave its sleep for one interval. I verified ownership before cleanup: only `sleep 99872[123]` processes whose `TMPDIR` or cwd was in my clones were signalled, by single positive pid (37 killed; any other process was reported and left alone, and there were none).
- **F-PRE-2 (minor, test-instrumentation).** `scripts/fastcycle/tests/test_reopen_rate_red.sh` exits rc 1 in a clean environment with no `sqlite3` on PATH. Its only not-ok line is `NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable ... this is an environment gap, not a finding`. The test calls it a SKIP but returns FAIL. Under the runner's `judge`, that is a FAIL for a genuinely absent capability, not an rc 77 SKIP (§11.4.289(E), §11.4.69). The behaviour is identical at base and head, so it predates this vehicle. It is the same class as F112-2: environment-dependent reds in a clean clone.

**Class recurrences flagged:**
- File-scoped `<eval>` allowlist rows (F113-1; 8 rows).
- The `.gitignore` copy-list pattern, latent in round7 (N119-1).
- A surviving mutant masked by an OR of two evidence legs (F099-1); this is the same shape as the reason-only known-row match (F047-1). In both, one signal stands in for two required ones.
- Clean-environment bus derivation duplicated per caller (F110-3 / CON-117).
- Environment-dependent reds in a clean clone that are labelled SKIP but exit as FAIL (F112-2, F-PRE-2).
- Killing a parent shell and asserting "no orphan" from the parent pid alone (F-PRE-1; §11.4.201(12) class). Other tests that stop a daemon by its `sh` pid should be checked in the same sweep (§11.4.276(C)); I did not run that sweep.

**SKIP-semantics audit (§11.4.289(E), §11.4.69).**
- No change introduces a SKIP followed by exit 0.
- CON-109 and CON-110 SKIP exit 77 with the reason on the last line, which the runner's `judge` reads.
- CON-089's absent tool is an honest FAIL, pending O3.
- No runner fail-word check was weakened; `run_full_suite.py` is unchanged in the range.

## Appendix: CON-112 downstream runs

Each of the three downstream users of `select_sample.py` was run once at base (rvb, bdc3ac43) and once at head (rvx, 270e4867), in parallel per test, with `env -i HOME=<fresh mktemp> PATH=/usr/bin:/bin TMPDIR=<same> timeout 600`. `sqlite3` is not on that PATH; on this host it exists only at `~/Android/Sdk/platform-tools/sqlite3`. Comparison: normalised `diff` (clone paths, mktemp suffixes and ISO timestamps replaced) of the base and head outputs.

| Test | Base | Head | Normalised diff | Reading |
|---|---|---|---|---|
| `test_collect_baseline_red.sh` | rc 0, pass=18 fail=0 | rc 0, pass=18 fail=0 | one line, a timing value (`545ms` vs `532ms` in C-F9) | equivalent |
| `test_reopen_rate_red.sh` | rc 1, 17 ok, 1 NOT ok | rc 1, 17 ok, 1 NOT ok | none (rc 0 from diff) | identical; the one NOT ok is the sqlite3-absent "SKIPPED" control needle (F-PRE-2) |
| `test_cycle_report_red.sh` | rc 124 (timeout at 600 s), 55 ok, 16 NOT ok | rc 124 (timeout at 600 s), 55 ok, 16 NOT ok | none (rc 0 from diff) | identical as far as it ran; did NOT complete |

- **`test_cycle_report_red.sh` did not complete in 600 s at either commit under the host load at the time.** Another agent's runs of the same test had been running more than 46 minutes under a 3600 s budget. This is an honest timeout, not a PASS. The claim I can make is narrower: over the 180 output lines both runs produced, base and head are byte-identical after normalisation, including every mutation-kill line that was reached (for example `R3_bulk_uses_first_closure killed (17 failing check(s))`).
- The 16 NOT ok lines are the same at both commits, and all trace to the clean environment, not to CON-112:
  - the `sqlite3`-absent and tracker-DB-absent cases (`ct_determinism SKIPPED`, `R5-C8`, the CT-009 needle);
  - `cycle_report.py` invocations failing with rc 4, followed by R5-C5, C6, C6b, C10 and C14 tracebacks that are `FileNotFoundError` on the JSON output an earlier failed invocation never wrote.
  - `R5-C11`, the check that ties `cycle_report` to `select_sample` (one sample, the same items, exclusions and usable counts), is `ok` at head.
- **Conclusion for CON-112.** No downstream regression is visible: head equals base on every line that was produced. The one remaining uncertainty is the unreached tail of `test_cycle_report_red.sh`. Re-run it with `sqlite3` on PATH and a 3600 s budget before landing, and record the result, if the conductor wants that tail covered.
- Evidence: `rvev/con112_test_{collect_baseline_red,reopen_rate_red,cycle_report_red}_{rvb,rvx}.out`, with `rc=` on the last line of each.
