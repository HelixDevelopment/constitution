# Independent review: vehicle/redpin, round 1 of 5

| Field | Value |
|---|---|
| Subject | vehicle/redpin head `2ca4d1b47f0391888b02ff052e4c47d237a95672`, one commit on main `8e496db76bf4b8570b0b14db55fd94468260884b` |
| Bundle | `redpin.bundle`, sha256 `cc4d30561be7ceb3b4d40358f0ea06f71a0100690819e6874fa40e901c714f59` (checked), range `8e496db..` |
| Anchors | §11.4.142 / §11.4.209 review, §11.4.276(G) round budget (round 1 of 5) |
| Reviewer | independent subagent, model Opus (claude-opus-5-5); effort not settable or readable on this dispatch path, so none is claimed (§11.4.231(F.2)) |
| Sandbox | throwaway root `/home/milosvasic/.cache/claude-tmp/rvredpin.UtACru` (mktemp -d, fresh HOME, removed after the review) |
| Evidence | `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/review_redpin_evidence/` (61 files, `SHA256SUMS` inside) |

## Verdict: NO-GO

There are two important `source-defect` findings, F1 and F2. Under §11.4.276(G.2) an important finding is never minor-class, so this round cannot be GO-with-follow-ups.

Most of the change holds up:

- The RED_PIN cure is sound.
- RED-before and GREEN-after hold on the same command.
- The fail-closed rc 93 and rc 94 paths work.
- The rc 77 SKIP is honest and is not counted as a PASS.
- The manifest problem set is unchanged.
- Every product mutant I wrote was killed.

Two things block the landing:

1. The new default-tier census guard fails on the committed tree, so the default tier goes red after the landing.
2. Pinning the sibling `multitrack_host_budget.sh` to the pre-fix commit brings back the pre-RB-02 carrier footgun inside the RED leg. That makes the RED leg depend on what else is running on the host.

## What I verified, and the results

### V1. RED_PIN is the right pre-fix commit and is reachable

- `e60cbde2e33e7d0542a937331763f6be7e739c9a` is the first parent of fix commit `55998fb` (checked with `git rev-parse 55998fb^`).
- e60cbde is an ancestor of main 8e496db (checked with `git merge-base --is-ancestor`).

### V2. RED before, GREEN after, same command

At head, with the RB-05 mock and the default `RED_MODE=both`, under both `sh` (dash) and `bash`:

| Test | PASS / FAIL |
|---|---|
| orchestrator_reconcile | 16 / 0 |
| orchestrator_reconcile_rc | 34 / 0 |
| sessions_argparse | 46 / 0 |
| sessions_pid_status | 25 / 0 |
| supervisor_wiring | 31 / 0 |

All five exit with rc 0.

Same command with the e60 product artifacts swapped into the checkout (the pre-fix state): every test exits rc 1, and every failure is a behavioural failure of a GREEN leg. With `RED_MODE=0`:

| Test | FAIL count | Example failure |
|---|---|---|
| reconcile | 7 | snapshot DIVERGED, plus a gawk syntax error |
| reconcile_rc | 13 | e1/e2/e3/f |
| argparse | 31 | rc 124 hang under bash, rc 2 under sh |
| pid_status | 9 | C2a/C2b/C3a |
| supervisor | 10 | GREEN(a)/(b)/(c) |

`RED_MODE=both` gives the same FAIL counts. Evidence: `redbefore_*`.

On main 8e496db (the old tests, which build RED from `HEAD:`) the exit codes were 94, 94, 1, 90 and 91. These match the author's report.

### V3. The fail-closed paths work

- **Shallow clone (`--depth 1`):** with the default mode, all five exit rc 93. With `RED_MODE=0` they still pass (`shallow*`).
- **Pin pointed at the fixed commit:** refused with rc 94.
- **Pin set to the absent sha `000…001`:** refused with rc 93.

Both refusals were confirmed through the author's heavy mutation suite.

### V4. My own product mutants (not written by the author)

Each mutant was applied to a fresh copy at head. The control needles stayed intact, and a GREEN leg killed every mutant (`tasks/bl8twmtfi`):

| Mutant | What it changes | Killed by |
|---|---|---|
| RM1 | argparse guard returns 0 | 30 GREEN fails |
| RM2 | `_term_status="running"` | C3a |
| RM3 | `MTS_SUPERVISOR` points at a missing file | GREEN(b) |
| RM4 | `true; _reconcile_awk_rc=$?` | e1 |
| RM5 | `te[tr]=""` (expiry dropped) | snapshot diverged |

### V5. The author's mutation suite

| Run | Result | Time |
|---|---|---|
| With the mock | rc 0, PASS 20 / FAIL 0 | 94 s |
| Without the mock | rc 0, PASS 12 / SKIP 2 | 56 s |

Cleanup with `safe_rm_rf "${S:?}"` left nothing behind.

### V6. The SKIP is honest

- Without the mock, pid_status and supervisor_wiring exit rc 77 and print `reason=rb05_mock_absent` as their last line.
- `run_full_suite.py` `judge()` maps that to `('SKIP','rb05_mock_absent')`. It is never a PASS.
- rc 93 maps to FAIL `rc_93`.
- Any SKIP makes the run `PARTIAL-SKIPS`.
- See F4 for the one place where SKIPs are absorbed.

### V7. `--verify-manifest`

It reports rc 3 with 25 problems on both main and the vehicle. The sorted sets are identical (`vm_main.sorted` against the vehicle run). The 3 new manifest rows parse, and the census line in the guide was updated from 315/816 to 318/819.

### V8. supervisor_wiring no longer writes outside the checkout

At head, `REPO_ROOT` is the git toplevel above the checkout, or empty. Evidence goes to `${REPO_ROOT:-$CONST_ROOT}/qa-results/...`. I observed it written to `repo/qa-results` (gitignored) and nothing written to the parent directory. The code fix is correct; see F6 for the report's claim.

### V9. Parse and lint

`sh -n` and `bash -n` are clean on all 8 changed or new scripts, and `shellcheck -S error` exits rc 0.

### V10. Deletes

The new code uses `safe_rm_rf "${S:?}"`. The five tests still contain the pre-existing bare `rm -rf "$WORK"` (F9). No new destructive pattern is introduced.

### V11. Census for other live instances of the HEAD-builder class

I ran my own regex over all tracked files, needle-checked: positive control = the PENDING file is found, negative control = a fabricated token is not. No live HEAD-builder instance exists outside the declared PENDING file (`tests/gates/test_oracle_ratchet_and_consumer_skips.sh`, owned by CON-043). The hits in fastcycle and in the worktree-add cases are comments, pinned copies or synthetic repositories.

### V12. Follow-up 3 is correctly out of scope

With no arguments, `sh scripts/multitrack/multitrack_sessions.sh` exits rc 2 with no output. `bash` prints usage and exits rc 2. Positive control: `sh … help` prints usage.

So the product defect (`_cmd="${1:-}"; shift 2>/dev/null || true` at line 588 under dash, where `shift` on an empty argument list is a fatal special-builtin error) is real. Leaving it out of this test-instrumentation change is correct under §11.4.293(A). The pid_status test works around it honestly by passing a `help` argument (C3). It should be registered as its own tracked item.

## Findings

### F1. The census guard fails on the committed tree

**Severity:** important. **Layer:** source-defect (it breaks a shipped gate).

`tests/test_no_head_red_builder.sh` exits rc 1 on the committed vehicle tree. Its census flags 8 lines (lines 114–122) of its own golden-TRUE heredoc, which sits inside the guard's own file.

`tests/test_no_head_red_builder_mutations.sh` fails as a consequence: "control: unmutated guard exited 1", PASS 3 / FAIL 1.

Both are default-tier manifest rows, so landing this commit turns the default tier red.

**Root cause.** `census()` lists files with `git ls-files`. The author's run (676 files) matches the tracked set at 8e496db, before the guard file itself was tracked; the committed head tracks 679. The evidence therefore came from an index state that is not the committed artifact. That is the same "evidence from the wrong artifact" class this change exists to cure.

**Tested remedy.** I tried a baseline that excludes the guard's own file from the census: rc 0, and the control builder is still caught.

**Alternatives:**

- Build the golden-TRUE fixture text without the literal revision token, for example by concatenating it at runtime.
- Add `--others --exclude-standard` to the census, so an untracked new test is also scanned (see F3 shape 8).

After the fix, re-record the evidence on the committed tree.

### F2. The pinned sibling host_budget makes the RED legs depend on host state

**Severity:** important. **Layer:** source-defect (it makes a shipped test's verdict depend on host state).

pid_status and supervisor_wiring also pin the sibling `multitrack_host_budget.sh` to e60. That is the pre-RB-02 version, and its two guards use a bare `pgrep -f`:

- the build pattern `m -j|gradle|build_maxres|GradleDaemon|…` (exit 2 = heavy build);
- the worker pattern `claude .*--output-format[= ]stream-json`.

The head version (fixed in 7adc5ff) excludes carriers; the e60 version does not.

**Demonstration.** I started a carrier process with argv `claude -p please fix the gradle build --output-format stream-json`, the shape of any agent prompt that mentions a build. With it running:

- pid_status `RED_MODE=1`: FAIL 6. All three C2 iterations recorded an empty pid, because the spawn was refused.
- supervisor `RED_MODE=1`: FAIL 3. RED(B) shows `spawn_rc=2` in all three iterations.
- `RED_MODE=0` passes for both, because the head guard excludes the carrier.

Before this change, the RED legs used the current sibling, which is carrier-proof. At the time of the check there was also one real stream-json `claude` process under my user id on this host. This is a §11.4.201(1) false FAIL and a §11.4.50 determinism break on exactly the multi-agent hosts this suite runs on. It is a §11.4.196(D) regression brought back by the pin.

**Remedy, confirmed.** Setting `MT_HOST_BUDGET_BUILD_PGREP_PATTERN` to a unique token built at runtime (`printf 'QXZZ_%s_%s' sentinel nobuild`, so the joined string never appears in any command line) made both RED legs pass with the carrier still running: pid_status PASS 12 / FAIL 0 and supervisor PASS 9 / FAIL 0 (`carrier3_*.out`).

My first attempt used a literal sentinel written inline in the command text and still failed. The most likely cause is that the literal token itself appeared in a live command line, which is the carrier footgun applied to the sentinel; that cause is UNCONFIRMED.

**Recommended fix, either:**

- (a) pin only the artifact under test and keep the current, carrier-proof sibling host_budget in the RED leg; or
- (b) in both modes, set the build pattern to a runtime-generated unique token and raise the worker cap.

Add a carrier regression leg either way. Separately, and pre-existing: the GREEN leg also refuses during a real heavy build on the host.

### F3. Detector blind spots

**Severity:** minor. **Layer:** test-instrumentation.

The detector does not flag these 8 shapes. These are my mutants; each survived (guard rc 0, not flagged):

1. `git show --no-textconv HEAD:path`
2. `git show @:path`
3. `git show HEAD:path 1> out` (the `1>` redirect escapes `(?<![0-9&<])`)
4. a two-step build: `rev=HEAD:path; git show "$rev" > out`
5. `git show "$(git rev-parse HEAD)":path > out`
6. `git archive HEAD path | tar -x`
7. a Python f-string, `subprocess.run(["git","show",f"{rev}:{p}"])`
8. a new, untracked test file (`git ls-files` does not see it)

None of these shapes exists live today (V11). Widen the detector, or state its coverage honestly in the guard header and the guide.

### F4. Two tests always SKIP in the canonical repository

**Severity:** minor. **Layer:** test-instrumentation.

In the canonical repository, without `MT_TEST_MOCK_CLAUDE`, pid_status and supervisor_wiring now always SKIP (rc 77). Their coverage there is zero until follow-up 4 (shipping the mock) lands.

In addition, the heavy redpin mutation suite with 2 internal SKIPs exits rc 0 with a summary line that the runner judges PASS, so those partial skips are absorbed at the suite level.

Track follow-up 4. Either have the mutation suite exit 77 when any leg skipped, or report its SKIP count in the summary line.

### F5. RB-05 verdicts are not labelled UNIT-CLASS

**Severity:** minor. **Layer:** process-doc (§11.4.289).

The RB-05 mock `claude` and the HSS host-safety stub are test doubles. Every verdict produced through them is UNIT-CLASS (gate and logic evidence), not live evidence that the supervisor or a spawn works. The change does not present them as live. However, nothing labels them as UNIT-CLASS, and the RED(B) message touched by this diff still says "a real (mocked) spawn".

Reword the message, for example "a spawn through the RB-05 test double", and label the class in the test header.

### F6. The report misattributes outside writes

**Severity:** minor. **Layer:** process-doc (§11.4.6).

The author's report attributes `/home/milosvasic/Projects/qa-results` pollution to supervisor_wiring. That directory holds `fastcycle/`, `hxc159/` and `us1_scenarios/`, and no `multitrack/` directory. At main, the test exits rc 91 before its `mkdir`. The `hxc159` entries come from `scripts/extensions/*` (for example `probe_bridge_layers.sh`).

The code fix (V8) is right, but the claim of observed pollution is unsupported. Correct the report.

### F7. Roadmap-Item trailer is a placeholder

**Severity:** nit. **Layer:** process-doc (§11.4.293(A)).

The trailer reads `redpin-class (id pending registration)`. Register the item and cite its id.

### F8. Short sha in CTRL_REV

**Severity:** nit. **Layer:** test-instrumentation.

`CTRL_REV=8e496db` is a short sha. Use the full 40-character sha so it can never become ambiguous.

### F9. Bare `rm -rf "$WORK"` in the five tests

**Severity:** nit. **Layer:** test-instrumentation (pre-existing, not introduced here).

The five tests still clean up with a bare `rm -rf "$WORK"` (§11.4.287(C)(1)). Move them to `safe_rm_rf "${WORK:?}"` in a follow-up.

### F10. The default tier needs full history

**Severity:** nit. **Layer:** process-doc.

On a shallow clone the default tier now exits rc 93 FAIL. That is fail-closed by design, and correct. State in the runner guide that the default tier needs full history, or name the unshallow step.

## Required for GO in the next round

1. **F1:** make the census guard pass on the committed tree, with the control builder still caught, and re-record its evidence there.
2. **F2:** make the RED legs of pid_status and supervisor_wiring independent of host processes, using remedy (a) or (b), and add a carrier regression leg.

F3–F10 can become tracked follow-ups (§11.4.276(G.2)).

## Not claimed

- I did not run the whole full suite.
- Behaviour on other hosts was not measured.
- The cause of the failed literal-sentinel attempt in F2 is UNCONFIRMED.
