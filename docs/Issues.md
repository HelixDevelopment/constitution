## CON-001 — speckit F-A: assert the REDUCED label in the PASS verdict line

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:30Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Reviewer mutant M3 survives: the text 'REDUCED ... NOT the full suite' in the PASS verdict line is not asserted. NET-LIVE's child PASSes in reduced mode, so asserting the label in netlive.out would kill M3. Severity nit, finding_layer test-instrumentation.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/extensions speckit bridge tests (NET-LIVE)

**Reproduction / context:**
Mutant M3 (verdict line never says REDUCED) run against the suite.

**Acceptance criteria:**
Mutant M3 is KILLED; suite stays green.

## CON-002 — speckit F-B: net_probe_state must have an undetermined state, plus an up golden-TRUE

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:31Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Reviewer mutant M7 (net_probe_state always down) survives, and the probe is not a decided signal: missing getent/timeout, or a leaked BRIDGE_NET_PROBE_HOST, reads as down instead of undetermined (section 11.4.201(4)). No test pins up on a networked host. Severity minor, test-instrumentation. Suggested fix: an undetermined state that FAILs, plus an up golden-TRUE assertion when the outside probe resolves.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
net_probe_state in the speckit bridge test tooling

**Reproduction / context:**
Remove getent or timeout from PATH, or set BRIDGE_NET_PROBE_HOST=x.invalid, and run the probe.

**Acceptance criteria:**
Probe reports undetermined (FAIL) rather than down in those cases; an up case is asserted on a networked host; M7 killed.

## CON-003 — speckit F-C: NET-LIVE reduced child must record and assert net_probe_state=down

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:31Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Reviewer mutant M8 (NET-LIVE child run without bwrap, so with network) survives. NET-LIVE checks that bwrap removes the network in a separate control, but not that the child under test ran without network; a child run with network passes identically. Severity minor, test-instrumentation. Suggested fix: have the reduced child record net_probe_state in its output and assert down there.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
NET-LIVE test of the speckit bridge

**Reproduction / context:**
Run the NET-LIVE child with network (mutant M8).

**Acceptance criteria:**
M8 is KILLED because the child's recorded net_probe_state must be down.

## CON-004 — speckit F-D: classify the network signature only on the failing step's output

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:32Z
**Reported-By:** Conductor

**What (the report, verbatim):**
The N5 classifier greps the network signature in ANY step's output, not in the failing step's. When offline, a warning from a successful init plus an unrelated failure in ext/submodule/commit is classified network and SKIPped, which can hide a real build failure. The submodule-add and commit steps have no captured output at all. Severity minor, test-instrumentation. Fix: record which step failed in make_live_fixture and classify only on that step's output; capture output for submodule-add and commit.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
make_live_fixture and the N5 network classifier

**Reproduction / context:**
With the network down, a network-signature warning in init.out plus an unrelated later-step failure.

**Acceptance criteria:**
That case FAILs (not SKIP); only a network signature in the failing step's output yields SKIP.

## CON-005 — speckit F-E: scp-shaped path warning gives advice that does not work

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:33Z
**Reported-By:** Conductor

**What (the report, verbatim):**
The scp-shaped warning advises 'use ./%s', but ./u@h:p still matches *@*:*, so the advice does not work. Severity nit, finding_layer process-doc. Suggest advising an absolute path only.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scp-shaped warning text in the speckit bridge scripts

**Reproduction / context:**
Pass a path like u@h:p and follow the advice ./u@h:p.

**Acceptance criteria:**
Warning advises an absolute path; the advised form is accepted.

## CON-006 — Default ROOT three levels up writes qa-results outside a standalone clone (~40 scripts)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:34Z
**Reported-By:** Conductor

**What (the report, verbatim):**
CONFIRMED as a class by the reviewer: the default ROOT=.../../.. (three levels up) is in all four scripts/extensions scripts, including the installer (install_speckit_superpowers_bridge.sh:113) and probe_bridge_layers.sh:78, and about 40 more scripts repo-wide (fastcycle, multitrack, some gates). In a vendored layout (constitution/scripts/x) three levels up is the consumer root, which is intended; in a standalone clone it is the clone's parent, so qa-results and other output are written outside the clone. Pre-existing, not introduced by the speckit change. Supporting evidence: scratchpad/qa-results/{fastcycle,multitrack,...} exists next to scratch clones. The author's specific claim (qa-results/hxc159 in the clone's parent) is UNCONFIRMED: the directory no longer exists. Needs its own item covering the whole class (section 11.4.276(C), 11.4.202). Severity minor.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_speckit_n1_n5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
every script whose default ROOT is three levels up (grep the class; scripts/extensions, fastcycle, multitrack, gates)

**Reproduction / context:**
Run any such script from a standalone clone without ROOT set and look for qa-results next to the clone.

**Acceptance criteria:**
Default ROOT resolves to the repository root (or a guarded consumer root) so no write leaves the clone; a census gate lists the class with a control needle.

## CON-007 — killpg N-1: fixture for the uncommitted git mv (index-only name source)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:35Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Reviewer note N-1 (test-instrumentation) from the killpg review round 5: the reviewer's mutants ME/MA have no probe-level discriminator. Recommend confirming that glnamesrc/glreq cover the index-only name source (uncommitted git mv) and adding a fixture on the uncommitted-mv state.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_killpg_r5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
killpg submodule-name resolution tests

**Reproduction / context:**
Mutants ME and MA against the killpg suite.

**Acceptance criteria:**
A fixture on an uncommitted git mv exists and kills ME and MA.

## CON-008 — killpg N-2: gitlink with no recorded name falls to the HEAD rule (documented limit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:35Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Reviewer note N-2 (a stated limit, not a defect) from killpg review round 5: a gitlink with no recorded name while a module directory exists under another name falls to the HEAD rule. It needs index/HEAD/.git edits outside the worktree-only threat model. Track it so the limit stays documented and is re-evaluated if the threat model widens.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_killpg_r5.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
killpg guard documentation of limits

**Reproduction / context:**
Not applicable (documented limit).

**Acceptance criteria:**
The limit is listed in the guard's documented limits; decision recorded whether the threat model widens.

## CON-009 — atm1220 surviving reviewer mutants A, C, G, H, I (baseline_replay trusted parent)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:36Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r4 of the ATM-1220 carry (GO-with-follow-ups) ran 6 own mutants against the v4r5 suite (96 tests); F was killed and these SURVIVE: A both mask tests 4007->4003 (QUIT bit dropped: a caller that blocks HUP,INT,TERM but not QUIT is treated as already blocked, no re-exec; the most meaningful); C probe check '= 0' -> '-le 1'; G malformed SigBlk read treated as blocked (4007); H probe TERM trap exit 143 -> exit 0; I re-exec "$BASH" -> bash (PATH lookup). C and G are near-equivalent on real hosts. Severity minor, test-instrumentation. Suggested rows: SigBlk lacking only QUIT (A); a TERM-during-probe row (H); a PATH-shadow row (I).

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r4.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/fastcycle baseline_replay trusted-parent tests (v4r5)

**Reproduction / context:**
Apply mutants A, C, G, H, I to baseline_replay.sh and run the v4r5 suite.

**Acceptance criteria:**
Each of A, C, G, H, I is killed (or documented as equivalent with evidence) by a suite row.

## CON-010 — atm1220: group Ctrl-C is delayed by a hung caller-side check (needs timeout -s KILL)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r4: with a 3 s hung check the group Ctrl-C stop is delayed 2.89 s (never lost, rc 130, no gate runs). Documented in the guide Limits; no host resource is held. Minor; keep tracked. Suggested fix: a bounded timeout -s KILL around caller-side checks.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r4.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/fastcycle baseline_replay caller-side checks

**Reproduction / context:**
Run a group with a hung (3 s) caller-side check and send Ctrl-C.

**Acceptance criteria:**
Stop latency is bounded by a declared timeout (-s KILL) and measured in a test; guide Limits updated.

## CON-011 — atm1220 N8: census SH_EXEMPT row trusts $BASH without proving it

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r3 finding N8 (minor, test-instrumentation): the census SH_EXEMPT row trusts "$BASH" unproved. A mutant that adds BASH="$1" at the top passes the census with 0 violations while the exempt re-exec runs an argument-chosen program. The environment cannot set BASH (bash overrides it) and the shipped code never assigns it, so it is not live. The census should detect an assignment to BASH.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r3.md (N8); carried as tracked in review_atm1220_carry_r4.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
safepath / mutation anchor census (check_safepath_census)

**Reproduction / context:**
Mutant adding BASH="$1" at the top of the exempt script.

**Acceptance criteria:**
Census FAILs on any assignment to BASH in an exempt script; control needle recorded.

## CON-012 — atm1220 N9 / RW5: the guide and notes under-claim whether RW5 is killed

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r3 (N4/RW5) found the claim WRONG (an under-claim): RW5 (needle code if False and ...) IS killed, because [AC-needle] fails when the checker is mutated (the test copies the checker under test), contradicting the note 'observationally equivalent, not killed'. Minor process-doc. Carried as N9 in review r4. Correct the note and any guide text.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r3.md; review_atm1220_carry_r4.md; atm1220_followups_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/fastcycle docs and notes for the census tests

**Reproduction / context:**
Read the RW5 note against a run of mutant RW5.

**Acceptance criteria:**
The note states RW5 is killed by [AC-needle], with the mutation run as evidence.

## CON-013 — atm1220: RW6 and RW7 are not registered as r6 rows

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r4 follow-up 3: the RW6 and RW7 cases (unit [SKIP-counts] for RW7, v4r8 [R8SKIP] for RW6) exist as tests but are not registered as rows of the r6 mutation runner, so the r6 run does not exercise them. Register them as r6 rows.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r4.md; atm1220_followups_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/fastcycle r6 mutation runner rows

**Reproduction / context:**
Run the r6 runner and look for RW6, RW7.

**Acceptance criteria:**
RW6 and RW7 are r6 rows and each is CAUGHT in a MUT_ONLY run.

## CON-014 — atm1220: the full ~100-minute r6 mutation run has not been done

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r4 and the carry reports state the full r6 run (about 100 minutes) was not repeated; only MUT_ONLY subsets were run. Run it once on a quiescent host under nice (section 11.4.89 background, 12.6 headroom), record the survivors and the closed-* cells that remain unobservable on this host.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_atm1220_carry_r4.md; atm1220_followups_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/fastcycle r6 mutation runner

**Reproduction / context:**
Run the r6 runner with no MUT_ONLY filter.

**Acceptance criteria:**
A full-run log with per-mutant verdicts is committed as evidence; survivors are tracked.

## CON-015 — env census F-EC1: jq detection false negatives (variable, ${X:-jq}, array, function, trailing pipe) (implemented, PROVISIONAL-DONE)

**Status:** Ready for testing
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:37Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Runner canon-fixes review r1 (important, test-instrumentation; the most important follow-up of the batch). The narrowing of the env-census jq regions creates false negatives: jq run through a variable or ${X:-jq} default (RE_JQ_WORD's lookbehind rejects ':-jq'), the program in an array, in a function, or on a pipeline continued by a trailing '|' (only backslash continuations are joined). No real tree file uses these shapes today (census diff). Suggested direction: keep the default ARMED when ownership cannot be decided and disarm only for regions provably owned by awk/perl/python/sed; and the report's 'Known limit' must name A1-A5.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; review_runner_canon_fixes_r2.md; runner_canon_fixes_r2_fix_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/gates/lib/gate_env_census.py and its test

**Reproduction / context:**
Feed the five shapes (variable, ${X:-jq}, array, function, trailing pipe) to the census.

**Acceptance criteria:**
Each shape is detected or the region stays armed; cases added to the regions test.

**Implementation:** vehicle/census-safe, landed 2026-11-05 (fix e37aa4b: the env census keeps the jq environment check armed when region ownership is undecidable and disarms it only for regions provably owned by awk/perl/python/sed; cases G1-G9, W1/W2 and the F-EC1 shapes in tests/gates/test_gate_env_census_jq_regions.sh; reviewer mutants RM8, RM14, RN1, RN7 killed). Independent review round 3 of max 5: GO-with-follow-ups (finding follow-ups CON-064..CON-069; structural rewrite of the regex owner rules deferred to CON-047 by operator decision of 2026-11-05).

**Verification:** provisional (section 11.4.290) -- job: re-run tests/gates/test_gate_env_census_jq_regions.sh (expect 52 passed, 0 failed, 5 known-failure, rc 3), tests/gates/test_gate_env_census_closure.sh (31 passed, 0 failed, 1 known-failure, rc 3), scripts/gates/cm_gate_env_reads_allowlisted.sh (VERDICT PASS) and scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh (META PASS) on main after landing -- checks: real-tree census byte-identical across census variants, no false negative for the five shapes of the report -- layer: gate-logic plus real tree (class floor: runtime) -- target: host, repo checkout -- artifact: commit that lands vehicle/census-safe -- due: next full-suite run.

## CON-016 — env census F-EC2: surviving mutants E1 (yq|gojq) and E5 ($'...' owner) (implemented, PROVISIONAL-DONE)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:38Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r1 own mutants surviving the regions and closure suites: E1 drop yq|gojq from RE_JQ_WORD (31/0, 9/0 still green); E5 do not set the owner for a $'...' region (owner leaks from the previous region). Add a yq case and a $'..' case. Severity minor, test-instrumentation.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/gates/lib/gate_env_census.py tests

**Reproduction / context:**
Mutants E1 and E5.

**Acceptance criteria:**
Both mutants are killed by new cases.

**Implementation:** vehicle/census-safe, landed 2026-11-05 (cases Y1-Y4 (yq/gojq words) and D1/D2 (the $'..' region owner) in tests/gates/test_gate_env_census_jq_regions.sh; whether they kill review-r1 mutants E1 and E5 was not re-measured at landing (UNCONFIRMED; the allowlist mutation test does not run E1/E5); independent review round 3 of max 5: GO-with-follow-ups; follow-ups CON-064 pins the $'..' separator member).

**Verification:** provisional (section 11.4.290) -- job: re-run tests/gates/test_gate_env_census_jq_regions.sh (52 passed, 0 failed, 5 known-failure, rc 3) and the allowlist mutation test (META PASS) on main after landing -- checks: Y1-Y4 and D1 fire, D2 quiet, E1/E5 mutants (to be re-measured) fail the suite -- layer: gate-logic (class floor: runtime for a gate-logic item) -- target: host, repo checkout -- artifact: commit that lands vehicle/census-safe -- due: next full-suite run.

## CON-017 — codegraph resync F-CG2: surviving mutants A, B, C of the resync tests

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:38Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r1 own mutants surviving U1-U6 of codegraph_update_and_resync.sh tests: A '-e .codegraph/codegraph.db' -> '-d .codegraph' (a .codegraph/ without a DB would sync instead of init); B skip commit/push on writer failure (owner decision (b) unpinned); C pwd instead of git toplevel (run from a subdirectory untested). Mutant D (127 -> 1) was closed in round 2 (U5 asserts exactly 127). Severity minor, test-instrumentation.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; review_runner_canon_fixes_r2.md; runner_canon_fixes_r2_fix_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/codegraph_update_and_resync.sh tests

**Reproduction / context:**
Mutants A, B, C.

**Acceptance criteria:**
Rows for a .codegraph/ without a DB, commit/push after writer failure, and a subdirectory run; A, B, C killed.

## CON-018 — codegraph_guard.sh misses a variable subcommand (codegraph "$OP" || true) F-CG3

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:38Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r1 F-CG3 (author's own finding, confirmed by reading): codegraph_guard.sh misses 'codegraph "$OP" || true' (a variable subcommand). Severity minor, test-instrumentation. Detection completeness of a guard.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; review_runner_canon_fixes_r2.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/codegraph/codegraph_guard.sh

**Reproduction / context:**
Run the guard over a script containing codegraph "$OP" || true.

**Acceptance criteria:**
The guard flags the variable-subcommand shape (or keeps armed when the subcommand is undecidable); test added.

## CON-019 — label-sync wrapper F-LS3: surviving mutants L1, L2, L4, L6 (no latency or hang assertions)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:38Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r1 own mutants surviving the 196-case suite: L1 remove the 127 fallback (rare path); L2 poll without kill -0 (would hang forever if readiness never arrives); L4 on_ready stops counting traps; L6 poll sleep 2 instead of 0.01 (adds up to 2 s to every start; no latency assertion). Killed: L3, L5. Severity minor, test-instrumentation.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; review_runner_canon_fixes_r2.md; runner_canon_fixes_r2_fix_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
label-sync agent wrapper tests (scripts/label_sync)

**Reproduction / context:**
Mutants L1, L2, L4, L6.

**Acceptance criteria:**
Latency and never-ready (hang) assertions added; L1, L2, L4, L6 killed.

## CON-020 — label-sync wrapper F-LS5: a USR1 before traps are installed kills the wrapper (pre-existing)

**Status:** Queued
**Type:** Bug
**Severity:** Medium

Review r1 F-LS5 (minor, source-defect, pre-existing, not introduced by the canon-fixes batch): a USR1 sent to the wrapper before its traps are installed kills it with the default action ('User defined signal 1', rc 138). Only external senders hit it. Noted for completeness; fix or document.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; runner_canon_fixes_r2_fix_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
label-sync agent wrapper signal setup

## CON-021 — label-sync lost-status branch untested (R2-1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:39Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r2 R2-1 (minor, test-instrumentation): the lost-status branch (pid grep / non-empty stderr) of the wrapper has no test, only the reachable silent-127 side; mutants X1 and X2 survive. Unavoidable without a way to induce bash's loss; consider a stub wait via a function-injection seam in test mode.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes_r2.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
label-sync agent wrapper wait/status logic

**Reproduction / context:**
Mutants X1, X2.

**Acceptance criteria:**
A test-mode seam induces the lost status; X1 and X2 are killed.

## CON-022 — jvm-daemons test: missing header cross-reference and evidence dir written under the parent toplevel

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:39Z
**Reported-By:** Conductor

**What (the report, verbatim):**
From the runner canon-fixes author report and review r1/r2: the jvm test has a header cross-reference to a non-existent target, and its evidence directory is written under the PARENT toplevel's qa-results/ (observed by the reviewer too: rb02 wrote into rv_rcf/qa-results/). Same class as the default-ROOT item. Fix the cross-reference and put evidence under the repository's own root or a declared directory.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_runner_canon_fixes.md; runner_canon_fixes_r2_fix_report.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
jvm-daemons RED test (rb02) header and evidence location

**Reproduction / context:**
Run the test from a standalone clone and look for qa-results next to the clone.

**Acceptance criteria:**
Header references an existing file; evidence stays inside the clone.

## CON-023 — test_gate_env_overrides_guarded.sh reports 116 passed / 1 failed

**Status:** Ready for testing
**Type:** Bug
**Severity:** Medium

The runner canon-fixes author reported test_gate_env_overrides_guarded.sh at 116 passed, 1 failed; the reviewers read the log but did not re-run it (review r1 and r2). Commit ef18fea made the cm_jev_detection env-override matrix case hermetic (section 11.4.292). Re-run this session on the vehicle/con043 tree that contains ef18fea (HOME=fresh mktemp dir): 117 passed, 0 failed, rc 0 (the same count was reported by the independent CON-043 round-2 reviewer on f8a45db). The root cause of the original single failure is recorded only in the ef18fea commit subject (non-hermetic case); a RED on the pre-fix tree was not reproduced in this run (UNREPRODUCED), so this is not VERIFIED-DONE.

**Verification:** provisional (section 11.4.290) -- job: re-run tests/gates/test_gate_env_overrides_guarded.sh on main after landing -- checks: 117 passed, 0 failed -- layer: runtime (host) -- target: host, repo checkout -- artifact: main after the CON-043 landing -- due: next full-suite run.

Source report(s) in the session scratchpad: review_runner_canon_fixes.md; runner_canon_fixes_report.md. Origin: independent-review follow-up, section 11.4.276(G.2).

## CON-024 — full-suite runner R5-3: ignored files can change the code that runs while ident says dirty=clean

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:39Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r5 R5-3 (minor, source-defect): ignored files, including ones excluded via .git/info/exclude, can change the code that runs (probe A4: a planted ignored package shadowed a committed module, PASS-FULL with dirty=clean and only tree= differing). Documented, but the ident claims 'identity of the code that ran'. Suggested fix: add ign=<hash of ignored non-pycache files> to ident, or treat local and global exclude rules as dirty.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r5.md; full_suite_runner_report6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner tree identity

**Reproduction / context:**
Plant an ignored package that shadows a committed module and run.

**Acceptance criteria:**
The ident changes or the run is dirty; test added.

## CON-025 — full-suite runner R5-4: an orphan gitlink (no .gitmodules entry) is not a topology gap

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:39Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r5 R5-4 (minor, source-defect): a gitlink with no .gitmodules entry and no checkout makes git submodule status exit 0 with no output, so the result is submodules=0 gaps=0 and PASS-FULL (probe A5). Latent: the real repo has 27 gitlinks and 27 status lines. Fix: compare the ls-files -s 160000 entries with the paths in submodule status; any extra is a gap.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r5.md; full_suite_runner_report6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner topology check

**Reproduction / context:**
Add a gitlink with no .gitmodules entry and run.

**Acceptance criteria:**
The orphan gitlink is reported as a gap.

## CON-026 — full-suite runner R5-5: status-model residuals and an inaccurate guide sentence

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:39Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r5 R5-5 (minor, source-defect): status-model residuals ('|| rc=$?; exit 0', 'x=$rc', 'case $?', 'rc=0' overwrite, 'while' condition). The guide's sentence 'conservative in one direction only' is inaccurate. Correct the sentence; optionally treat an assignment-only '||' right-hand side as absorbing unless the variable reaches exit/return/test-with-exit.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r5.md; full_suite_runner_report6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner status model and its guide (docs/guides/full_suite_runner_guide.md)

**Reproduction / context:**
Run the listed shapes through the status model.

**Acceptance criteria:**
Guide sentence corrected; residual shapes either handled or listed as limits.

## CON-027 — full-suite runner R5-7: a forged re-chained results.jsonl record is resumed without re-judging its log

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:40Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r5 R5-7 (minor, source-defect, documented limit): a forged, re-chained results.jsonl record is resumed without its log being re-judged (probe A8). Fix: on resume verify log_sha256 and recompute judge(rc, log); on mismatch report a results integrity error.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r5.md; full_suite_runner_report6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner resume path

**Reproduction / context:**
Forge and re-chain a record, then resume.

**Acceptance criteria:**
Resume reports a results integrity error.

## CON-028 — full-suite runner R5-8: commit trailers name the wrong model (nit, process-doc)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:40Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r5 R5-8 (nit): the commit trailers name Sonnet on 46015f5 and d4dfe7b while both rounds ran on Opus. Record it in the review record; do NOT rewrite history (section 11.4.113).

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r5.md; full_suite_runner_report6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
review record only

**Reproduction / context:**
Compare the trailers with the dispatch records.

**Acceptance criteria:**
The review record states the correct model for both commits; no history rewrite.

## CON-029 — full-suite runner Q2-Q5: unpinned reviewer mutants need self-test rows

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:40Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Review r6 own mutants that survive and are unpinned: Q2 drop the '?' in qid fail-closed; Q3 status part of quick_ident removed (only the early stop is unpinned); Q4 end-of-run full tree_ident compare removed (the only detector of an edit to an already-dirty tracked file per probe G; still caught by the tree_state hash); Q5 sub_paths without --recursive (nested dirt/moves still visible in root status). Add one self-test row each: Q2 git failure mid-run, Q3 untracked file written by a unit stops before the next unit, Q4 edit of an already-dirty file caught at the end, Q5 nested submodule move. Severity minor, test-instrumentation.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner self-tests

**Reproduction / context:**
Mutants Q2, Q3, Q4, Q5.

**Acceptance criteria:**
Four rows added; each mutant killed.

## CON-030 — full-suite runner: sub_paths splits the status line on whitespace (submodule path with a space)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con030_review/con030_reproduction_2026_11_05.txt` — red-command `bash docs/qa/con030_review/con030_class_repro.sh <checkout at efe2cc6> <new dir>  (case 0: submodule path 'sub dir')` — green-command `bash docs/qa/con030_review/con030_class_repro.sh <checkout at f6567349> <new dir>  (case 0)` — env `host-only fixture: real git 2.53.0, python 3.14.4, engine scripts/full_suite/run_full_suite.py; record sha256 1520da66765645d83cfa3f82f09bedadaaeeddf7ac0106e6c5d0f23411d7ba9a` — signature `RED: rc=9 'TOPOLOGY: submodule sub: recorded commit ... is not in its object store' RESULT: REFUSED-TOPOLOGY for a clean checkout with submodule 'sub dir'; GREEN: rc=0 RESULT: PASS-FULL` — updated 2026-11-10T23:16:06Z — by `Claude Opus 5.5 (CON-030 round 5 fixer subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `sub_paths split the human-oriented 'git submodule status' line on whitespace, so the path 'sub dir' was read as 'sub' and topology looked for a non-existent submodule (decisive: same fixture without the space runs; with it refuses). Rounds 2-3 moved paths to 'git ls-files -s -z' and the quick identity to a structured QuickIdent. Round 4 (structural, review r3 H1 H2 H3) removes the remaining members of the same class found by the whole-engine enumeration: every governance file (manifest, known table, lock, roster) is read by one reader gov_lines() that splits on LF only, tolerates CRLF and refuses any other control or line-separator character by name (str.splitlines() had split on NEL/LS/CR, H2); the unit identity is the structured key (path, tuple(args)) end to end and plan() refuses duplicate keys and duplicate display ids (the joined 'path + space + args' uid collided, H1); every output line passes one escape function esc_out() and the census refuses control/line-separator names (raw CR forged output lines, H3). Class inventory: docs/qa/con030_review/con030_class_sweep_r4.py. Round 5 (review r4): the census markers of the guide are whole lines found structurally (K1, shape D of docs/qa/con030_review/con030_class_sweep_r5.py: a marker or delimiter found by substring); --sync-guide and --generate-manifest fail instead of reporting a write they did not do (K2, K12); esc_out decodes before it escapes (K3); --verify-manifest runs the plan check (K9).` — evidence `docs/qa/con030_review/con030_reproduction_2026_11_05.txt` — updated 2026-11-10T23:16:06Z — by `Claude Opus 5.5 (CON-030 round 5 fixer subagent)`

Review r6 follow-up 2: sub_paths splits the status line on whitespace, so a submodule path containing a space is truncated (probe E ended REFUSED-TOPOLOGY rc 9: fail-closed, cause not isolated). Latent: the real repository has none. Reproduce first (section 11.4.292), isolate the cause, then fix.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner sub_paths


**Operator decision (section 11.4.276(E)(3)), recorded 2026-11-10, relayed verbatim by the conductor and naming this item:** "Keep running rounds until GO is reached!" CON-030 reached R_max at review round 4 (NO-GO); by this decision its review loop continues past R_max (round 5 onward) with the same bar: a zero-finding GO (section 11.4.134) on the section 11.4.209 substrate.

**Round history:** rounds 1-4 on vehicle/con030 (reviews in docs/qa/con030_review/); round 5 fixes review r4 K1-K12 and M1-M6, merges live main 90efceb8 (K5) and re-mints the vehicle ids CON-108 -> CON-116 and CON-109 -> CON-117 (K6, section 11.4.214); K4 is registered as CON-118.

## CON-031 — OPERATOR ACTION: review the full-suite runner excluded list and run --accept-excluded-change i@mvasic.ru

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:40Z
**Reported-By:** Conductor

**What (the report, verbatim):**
config/full_suite_operators.roster holds exactly one operator (i@mvasic.ru). A real run ends exit 11 until the operator reviews the excluded list and runs `--verify-manifest --accept-excluded-change i@mvasic.ru`; the lock currently has only the fsr-r4-author acceptance, which is not on the roster. Review r6 confirms it was NOT self-accepted. The author recategorised and accepted all 44 rows 'pending independent review' (report 4: each row needs a second look). This item is operator-blocked (section 11.4.21) and must not be done by an agent.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r6.md; full_suite_runner_report6.md; full_suite_runner_report4.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
config/full_suite_excluded.lock and config/full_suite_operators.roster

**Reproduction / context:**
Run the runner with --verify-manifest.

**Acceptance criteria:**
Operator reviewed the excluded rows and accepted; a full run no longer ends exit 11.

## CON-032 — post_update_hook.sh captures CONST_DIR, _pu_owner and PROJECT_ROOT with plain $(...) (newline class)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:41Z
**Reported-By:** Conductor

**What (the report, verbatim):**
From the agentlabel round-8 fix report: scripts/post_update_hook.sh derives CONST_DIR, _pu_owner and the PROJECT_ROOT fallback with plain $(...), the same trailing-newline capture class fixed in the installer via exact_out; the installer re-canonicalises its input byte-exactly, but a stripped PROJECT_ROOT could still name the newline-less sibling project. Candidate tracked item per the author.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: agentlabel_fix_report8.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
scripts/post_update_hook.sh

**Reproduction / context:**
Run the hook with a PROJECT_ROOT or constitution path ending in a newline.

**Acceptance criteria:**
Captures use an exact-output helper and refuse a path containing a newline; test added.

## CON-033 — Retire ref atm1220_r9 (13 unique commits incl. the HELD snapshot) after an operator decision

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-04T22:00:41Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Local ref atm1220_r9 (and wip/review-pending-20261014/atm1220_r9 on the upstreams) holds 13 commits not on origin/main, including 4b13814 'HELD (local only, DO NOT PUSH): snapshot of all uncommitted constitution work, 2026-10-12' (615 files). Per branch_analysis.md the merge needs an operator decision: merge with 535 export conflicts resolved as delete, or extract only b61583e + the V4 rounds onto main and drop the snapshot. Section 11.4.288(C.7)(5): merge to main then retire; never delete a ref with unique commits (9.2, 11.4.122). Operator-blocked: needs the operator's go-ahead.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: branch_analysis.md; conf_atm1220_r9.txt

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
ref atm1220_r9 and its wip/review-pending-20261014/atm1220_r9 mirrors

**Reproduction / context:**
git rev-list --count origin/main..atm1220_r9 (13 at measurement time).

**Acceptance criteria:**
Unique commits are on main on every upstream (or the operator records a drop decision), then the ref is retired on all upstreams.

## CON-034 — atm1217 redirect-target class: appends to /dev/stdin or "$0" are credited by the baseline-delta check

**Status:** Queued
**Type:** Bug
**Severity:** Medium

The atm1217 census credits 'echo "touch M" >> /dev/stdin' and '>> "$0"' (redirect targets that rewrite the running script or its stdin) via the baseline-delta check. Baseline-delta was ABANDONED and the whole-file check was kept; this item tracks closing the redirect-target class itself (enumerate every member of the class per §11.4.276(C), control-needled).

**Affected scope / file-scope manifest:**
atm1217 census/check (UNKNOWN: exact script path; locate via git log atm1217 and grep on the check name)

## CON-035 — env-census BASH misses: line continuation after a builtin, quote-spliced name, string-literal false positives

**Status:** Queued
**Type:** Bug
**Severity:** Medium

The env-census BASH detection misses (a) a line continuation after a builtin, (b) a quote-spliced command name (e.g. ba""sh), and reports false positives on string literals that merely mention the name. Fix the three shapes with golden-TRUE and golden-FALSE-with-carrier fixtures (§11.4.201).

**Affected scope / file-scope manifest:**
env-census tooling (UNKNOWN: exact path; locate via grep for the census name)

## CON-036 — census blind spots: sed-produced jq program run later; bash -c with inner single quote inside double quotes; per-line interpreter detection; literal-path alias false-disown

**Status:** Queued
**Type:** Bug
**Severity:** Medium

Census blind spots: (1) a jq program produced by sed and run later is not seen; (2) 'bash -c' whose inner script has a single quote inside a double-quoted string is mis-parsed; (3) interpreter detection is per line, not per command: 'awk -f "$F" in; $cmd "$F"' stays quiet, and the pre-existing 'grep -q x f && "$J" -n "$P"' likewise; add a test pinning that shape; (4) a literal-path alias is falsely disowned.

**Affected scope / file-scope manifest:**
census tooling (UNKNOWN: exact path)

## CON-037 — replica_for lacks a symlink-write guard

**Status:** Queued
**Type:** Bug
**Severity:** Medium

replica_for can write through a symlink at the replica path. Add a guard that refuses a symlinked target (lexical and resolved), with a test.

**Affected scope / file-scope manifest:**
replica_for (UNKNOWN: defining file; locate with grep)

## CON-038 — ownership wave 1 M1: rollback preflight does not check the ledger dir is writable

**Status:** Queued
**Type:** Bug
**Severity:** Medium

Repro: take a backup with no ledger, record a file, chmod 555 .constitution, run rollback: it exits 3 AFTER unlinking files. Either make the preflight check the ledger dir writability before any unlink, or soften the design doc claim.

**Affected scope / file-scope manifest:**
ownership wave 1 rollback (UNKNOWN: file paths; see ownership wave1 vehicle merge f4bcb26)

## CON-039 — ownership wave 1 M2: mutant N9 survives (guard stopping rollback from unlinking json-entry rows)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T11:02:32Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Mutant N9 (removing the guard that stops rollback unlinking json-entry rows, which would delete a consumer .claude/settings.json) survives the suite. Add a pinning test.

**Affected scope / file-scope manifest:**
ownership wave 1 tests

**Reproduction / context:**
Apply mutant N9; suite stays green.

**Acceptance criteria:**
Pinning test kills N9.

## CON-040 — ownership wave 1 M3: mutants N2, N3, N4, N8, N10, N11 survive

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T11:02:32Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Six reviewer mutants survive the ownership wave 1 suite: N2, N3, N4, N8, N10, N11. Add tests that kill each, or record each as equivalent with proof.

**Affected scope / file-scope manifest:**
ownership wave 1 tests

**Reproduction / context:**
Apply each mutant; suite stays green.

**Acceptance criteria:**
Each mutant killed or recorded equivalent with evidence.

## CON-041 — ownership wave 1 M4: preflight may create an empty .constitution dir before refusal

**Status:** Queued
**Type:** Bug
**Severity:** Medium

The preflight may create an empty .constitution directory before it refuses. A refusal must leave no side effects.

**Affected scope / file-scope manifest:**
ownership wave 1 preflight

## CON-042 — ownership wave 1 F6: TOCTOU only narrowed; refs never pruned; gc/doctor handling of X.refs (wave 4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T11:02:32Z
**Reported-By:** Conductor

**What (the report, verbatim):**
F6: the check-to-use race is only narrowed, not closed; X.refs files are never pruned; gc/doctor handling of X.refs is owed for wave 4.

**Affected scope / file-scope manifest:**
ownership wave 4 (gc/doctor)

**Reproduction / context:**
UNKNOWN: n/a, design item.

**Acceptance criteria:**
Decision recorded on TOCTOU residual; gc/doctor prune stale X.refs with tests.

## CON-043 — frozen-evidence exclusion gate for the 64 oracle-baseline entries (implemented, PROVISIONAL-DONE)

**Status:** Ready for testing
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

The 64 oracle-baseline entries (3 frozen RED-evidence files under submodules/llmctl/specs/009-jev-decision-models/evidence/p1-red-original/harness/py/) are now covered by a checked-in exclusion list, config/oracle_frozen_evidence_exclusions.tsv, enforced by scripts/gates/cm_oracle_strategy_named_and_independent.sh: closed class set, no globs, the git blob id of the owning repository voids an entry on mismatch, a monotone-nonincreasing ceiling, a malformed list is BLIND, and a path that is not a regular file (/dev/null) means no list. The ratchet baseline went from 64 entries to 0. Tests: tests/gates/test_oracle_frozen_exclusions.sh (79 pass, 0 fail) and tests/gates/test_oracle_ratchet_and_consumer_skips.sh. Landing was ordered by the conductor; the operator decision record itself is not verified by this run (UNKNOWN). Independent review: round 2 of max 5, verdict GO-with-follow-ups (section 11.4.276(G)), report scratchpad/review_con043_r2.md; vehicle head f8a45db. Follow-ups: see the items registered with this landing (CON-049 to CON-053).

**Verification:** provisional (section 11.4.290) -- job: re-run tests/gates/test_oracle_frozen_exclusions.sh, tests/gates/test_oracle_ratchet_and_consumer_skips.sh and the oracle gate on main after landing -- checks: gate on the real tree PASS excluded=3 voided=0, control with --exclusions /dev/null FAIL ratchet total=64 -- layer: gate-logic plus real tree (class floor: runtime) -- target: host, repo checkout -- artifact: commit that lands f8a45db -- due: next full-suite run.

## CON-044 — the '# basis:' line is not enforced by cm_oracle_strategy_named_and_independent.sh

**Status:** Queued
**Type:** Bug
**Severity:** Medium

The gate cm_oracle_strategy_named_and_independent.sh does not enforce the '# basis:' line. Enforce it or document why not.

**Affected scope / file-scope manifest:**
scripts/gates/cm_oracle_strategy_named_and_independent.sh

## CON-045 — re-run Sonnet-reviewed independent reviews on Opus-xhigh (§11.4.209)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T11:02:33Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Independent reviews of oracle waves b2/b3 and the census/ownership re-reviews ran on Sonnet 5.5 with no recorded Opus-unavailability fact. Re-run them on Opus at xhigh when available, or record the genuine unavailability fact.

**Affected scope / file-scope manifest:**
oracle waves b2/b3; census re-review; ownership re-review

**Reproduction / context:**
UNKNOWN: n/a.

**Acceptance criteria:**
Each review re-run on Opus-xhigh with captured evidence, or the Opus-unavailability fact recorded.

## CON-046 — auto-commit tooling downgraded the Containers submodule pin (724d818); restored in 84084a2

**Status:** Queued
**Type:** Bug
**Severity:** Medium

Operator auto-commit 724d818 regressed submodules/containers from 5ea870a to 22b4970 (an ancestor); restored in 84084a2. Investigate the cause first (§11.4.102), then make the auto-commit tooling not downgrade submodule pins (§11.4.288(D)).

**Affected scope / file-scope manifest:**
auto-commit tooling (UNKNOWN: location); submodules/containers

## CON-049 — CON-043 FU-1 (NF1): adopt reviewer mutants N1-N4 as killing mut() cases in test_oracle_frozen_exclusions.sh

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

Four reviewer mutants survive the suite (pass=69 fail=0 in the mutant copy): N1 duplicate '# ceiling:' header check removed; N2 leading '../' path check removed; N3 leading or trailing TAB accepted; N4 a last line without a trailing newline ignored (a false FAIL, section 11.4.201(1)). Adopt each verbatim as a mut() case using the reviewer fixtures ceil_dup_after, lead_dotdot, leadtab, trailtab and no_trailing_nl, so the suite fails on each mutant (section 11.4.194(6)(d), 11.4.276(D)). Classified test-instrumentation, minor: the gate behaviour itself is correct. review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/. Origin: independent-review follow-up, section 11.4.276(G.2), CON-043 round 2. Scope: scripts/gates/cm_oracle_strategy_named_and_independent.sh and tests/gates/test_oracle_frozen_exclusions.sh. Parent: CON-043.

## CON-050 — CON-043 FU-2 (NF2): hash fixtures in the owning repository in test_oracle_frozen_exclusions.sh and add a run-from-sha256-cwd case

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

Lines 69, 210 and 222 of tests/gates/test_oracle_frozen_exclusions.sh call 'git hash-object --no-filters <path>' without -C, so git uses the object format of the repository that contains the cwd. Run from inside a sha256 repository the test reports pass=72 fail=7 (false FAILs), while the gate itself PASSes there with excluded=3. Hash inside the fixture's own repository (git -C $d/frozen hash-object --path=test_frozen.py -- test_frozen.py, as probe_lib does) and add one run-from-sha256-cwd case. Same class as round-1 F3 (section 11.4.276(C)). Classified test-instrumentation, minor. UNCONFIRMED: whether any runner invokes the test from a sha256 cwd. review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/. Origin: independent-review follow-up, section 11.4.276(G.2), CON-043 round 2. Scope: scripts/gates/cm_oracle_strategy_named_and_independent.sh and tests/gates/test_oracle_frozen_exclusions.sh. Parent: CON-043.

## CON-051 — CON-043 FU-3 (NF3): the RED steps in test_oracle_frozen_exclusions.sh assert the exit code, not the reason

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

The step 'RED: pinned pre-change gate FAILs the frozen file (rc=1)' checks rc only. A pinned gate that FAILed for an unrelated reason (a missing lib, for example) would still read as RED. Also assert that the FAIL names the frozen file, or shows 'ratchet total=' with the expected count. Mitigated today by the pin assertion and the T/R_redpin_head kills. Nit, test-instrumentation. review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/. Origin: independent-review follow-up, section 11.4.276(G.2), CON-043 round 2. Scope: scripts/gates/cm_oracle_strategy_named_and_independent.sh and tests/gates/test_oracle_frozen_exclusions.sh. Parent: CON-043.

## CON-052 — CON-043 FU-4 (NF4): print a stderr NOTE when an explicit --exclusions path is not a regular file

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

An explicit --exclusions path with a typo, or one naming a directory or a FIFO, is visible only as exclusion_entries=0. The behaviour is fail-closed (more files are scanned, never fewer), but the operator is not told. Print a NOTE on stderr when the operator names a path explicitly and it is not a regular file; keep /dev/null as the silent idiom. Nit, source-defect (diagnosis only). review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/. Origin: independent-review follow-up, section 11.4.276(G.2), CON-043 round 2. Scope: scripts/gates/cm_oracle_strategy_named_and_independent.sh and tests/gates/test_oracle_frozen_exclusions.sh. Parent: CON-043.

## CON-053 — CON-043 FU-5 (NF5): report a voided exclusion entry before rule 3 resolves the base

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

A voided entry with no candidate files and no remote main gives BLIND no_nonsliding_base (rc 2) instead of a FAIL that names the void. Non-zero and fail-closed, but the reported reason is not the real cause. When a void is the only problem, report it before rule 3 (base resolution). Nit, source-defect (diagnosis only). review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/. Origin: independent-review follow-up, section 11.4.276(G.2), CON-043 round 2. Scope: scripts/gates/cm_oracle_strategy_named_and_independent.sh and tests/gates/test_oracle_frozen_exclusions.sh. Parent: CON-043.

## CON-054 — five default-tier multitrack guard tests build their RED artifact from 'git show HEAD:' and fail on main

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Conductor

Five default-tier tests exit non-zero on main 8e496db, on vehicle/con043 and in a shallow clone, so the full suite is red; this predates CON-043. Two classes. HEAD-RED proper: scripts/multitrack/test_multitrack_orchestrator_reconcile.sh (rc 94), test_multitrack_orchestrator_reconcile_rc.sh (rc 94), test_multitrack_sessions_argparse.sh (rc 1, PASS=1 FAIL=6): the HEAD copy already holds the fix, so the RED construct is absent; each passes with RED_MODE=0. Consumer-layout precondition: test_multitrack_sessions_pid_status.sh (rc 90, no outer project root) and test_multitrack_supervisor_wiring.sh (rc 91, missing consumer fixture rb05_fixtures/mock_claude.sh); the HEAD-RED construct is latent behind the precondition. Census with control needles: 16 files match the HEAD: read query, 5 are runtime RED builders. A candidate fix exists, unreviewed and unlanded: vehicle/redpin commit 2ca4d1b (bundle redpin.bundle in the session directory, report scratchpad/redpin_report.md) pins the RED artifacts to e60cbde. Reproduce first (section 11.4.292), get the independent review, then land. Origin: observation in the CON-043 round-2 review, review report scratchpad/review_con043_r2.md (vehicle/con043 head f8a45db), evidence in scratchpad/review_con043_r2_evidence/.

## CON-055 — atm1217-base FU-1 (R2-1): widen the shell= directive value list in precheck_pack_run.py to the table measured against shellcheck, with a bats parse rule

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:50Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-1, minor, source-defect. _SHELLCHECK_SHELLS = (sh, bash, dash, ksh, busybox) rejects five values that shellcheck 0.11.0 honours for a shell= directive: ash, ksh88, ksh93, oksh, bats (mksh and zsh are unknown to shellcheck, SC1103). The gate then falls back to sh and refuses with findings shellcheck would not report (false refusal, section 11.4.201(1); never a false PASS). The comment claiming the list is what shellcheck 0.11 accepts is false (written from memory, not measured, section 11.4.276(C)). Tree reach is 0 (all directive values in the 18 shebang-less tree files are bash or sh). Fix: derive the accepted-value table by running shellcheck itself (reuse the reviewer fixtures sc/ and matrix/), add the five values, correct the comment, pin each value with a shellcheck-measured fixture row. bats needs its own parse rule: bash -n and sh -n both reject '@test "x" { ... }' with rc=2 (control: bash -n on plain 'echo ok' is rc=0), so passing bats through would trade a lint false refusal for a parse false refusal. ksh88/ksh93/oksh fall under the already documented ksh sh -n residual. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (_SHELLCHECK_SHELLS), scripts/fastcycle/tests/test_precheck_shellcheck_red.sh

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-056 — atm1217-base FU-2 (R2-2 and R2-5): map shebang ash to dash and busybox sh to busybox, adopt reviewer mutant NM5

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:51Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-2, minor, source-defect (pre-existing): the shebangs '#!/bin/ash' and '#!/bin/busybox sh' map to sh, but shellcheck lints them as dash and busybox (matrix rows s1: false refusal, s2: over-refusal). Tree reach is 0 (census with positive control: 233 '#!/bin/sh' matched, 0 ash or busybox shebangs). R2-5, minor, test-instrumentation: reviewer mutant NM5 (_INTERP_DIALECT[ash]: sh to bash) survives (shellcheck_red 176/0); it points in the false-PASS direction (bash-isms in an ash script would pass). Fix together: ash to dash, busybox sh to busybox, and adopt NM5 verbatim as a killing mutation case plus tests for both mappings. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (_INTERP_DIALECT), scripts/fastcycle/tests/test_precheck_shellcheck_red.sh

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-057 — atm1217-base FU-3 (R2-3 and R2-4): adopt reviewer mutants NM1, NM2 and NM3 verbatim as killing cases

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:51Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-3, minor, test-instrumentation: NM1 (_shebangless_exec_text: drop 'b"\0" not in head') and NM2 (drop the has-an-extension exclusion) survive (shellcheck_red 176/0). NM1 would lint the 2 tracked ELF binaries under scripts/workable-items/bin and refuse them with 'shell script contains NUL byte(s)'; NM2 would lint an executable note.txt without a shebang. Head excludes both (probe m1/). Negatives to add: an executable ELF-like file containing a NUL, and an executable file with an extension but no shebang. R2-4, minor, test-instrumentation: NM3 (dialects.append(...) replaced by pass) survives; the evidence.dialects list advertised under section 11.4.201(5) is never asserted. Assert evidence.dialects with file, dialect and source for at least the directive, shebang, extension and default sources. Each mutant must fail the suite before the next review (section 11.4.276(D)). review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (_shebangless_exec_text, dialects evidence), scripts/fastcycle/tests/test_precheck_shellcheck_red.sh

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-058 — atm1217-base FU-4 (R2-6): assert rc == 0 in the D14 RM1 flip of test_precheck_pack_build_red.sh

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:51Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-6, nit, test-instrumentation: the D14 RM1 flip asserts only the absence of the co-pack reason, not rc == 0. At head RM1V=0 so the flip is valid today; it would also pass if the mutated build failed for an unrelated reason. Add the rc == 0 assertion. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/test_precheck_pack_build_red.sh

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-059 — atm1217-base FU-5 (R2-7 and R2-8): correct the _shell_dialect docstring and decide the unknown shell= directive fall-through

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:51Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-7, nit, process-doc: the docstring describes step (4) POSIX sh as if it were shellcheck's own order. shellcheck's fallback for .sh and for files with no extension is bash plus SC2148; defaulting to sh is the gate's own stricter choice (matrix row e4). State it as such. R2-8, nit, source-defect: for an unknown directive value (zsh, mksh) the gate falls through to the shebang while shellcheck falls through to the extension or bash. Both sides refuse (SC1103 is an error) so the outcome is the same; only the extra findings differ (rows u1, u2). Decide the fall-through (shebang or extension) and pin it with a test. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (_shell_dialect docstring and unknown-directive branch)

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-060 — atm1217-base FU-6 (R2-10): route _symlink_is_script and base_is_shell through the main shell detector

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:51Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-10, minor, source-defect (round-1 M1 residue): _symlink_is_script (256-byte probe) and base_is_shell use the shebang-only _bytes_are_shell and not _shebangless_exec_text, unlike the main selection site. Reach today is 0 (1 tracked symlink, a dangling fixture, out of 1110 mode-100755 entries counted as control). Under-detection is possible only for a symlink to, or a base blob of, a shebang-less extensionless executable text file. Route both through the same detector as the main site. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (_symlink_is_script, base_is_shell, _bytes_are_shell)

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-061 — atm1217-base FU-7 (N1, N2, N4 carried from round 1): shellcheck-absent skipped PASS, LOCAL ONLY commit subject, accepted keyboard-mash disable justification

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:52Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Carried from review round 1 (scratchpad/review_atm1217_base.md), nits. N1, process-doc: when shellcheck is absent from PATH check_shellcheck returns verdict PASS with mode skipped (about line 1622); pre-existing, and the verifier refuses such a pack (it requires whole-file mode), but a skip labelled PASS goes against sections 11.4.3 and 11.4.289(E); report it as a SKIP-with-reason. N2, process-doc: the subject of bc0953e contains 'LOCAL ONLY pending independent review' and stays in main history (never rewritten, section 11.4.113); the body of 3be7f1a is empty so the round-6 mechanisms have no recorded RED evidence; noted here, no action on history. N4, source-defect, documented by the author: D5 accepts a keyboard-mash justification (p9: '# aaaa beee ciii dooo' disables SC2086; blocking_rule_disabled lists it); decide whether a justification-quality check is wanted. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/precheck_pack_run.py (check_shellcheck mode skipped, disable-justification check), commit bc0953e subject

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-062 — atm1217-base note (R2-9): Roadmap-Item trailers missing on bc0953e, 3be7f1a, 8ad0e53 and 17dd803

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:52Z
**Reported-By:** Conductor

**What (the report, verbatim):**
R2-9, nit, process-doc: required by section 11.4.293(A), the commits bc0953e, 3be7f1a, 8ad0e53 and the merge 17dd803 carry no Roadmap-Item trailer (the round-2 commits 4cd886e and a5c5df3 carry Roadmap-Item: CON-033). Recorded here and in the landing merge message; history is NOT rewritten (section 11.4.113). Close as a no-action record once the commit-names-roadmap-item gate (OWED-GATE-175) is evaluated against it. review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
git history of vehicle/atm1217-base (commits bc0953e, 3be7f1a, 8ad0e53, 17dd803)

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-063 — atm1217-base observation: test_precheck_pack_build_red.sh C2 chmod 000 on the live checkout breaks parallel suites

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T16:21:52Z
**Reported-By:** Conductor

**What (the report, verbatim):**
Observation outside the declared scope of the atm1217-base review, not a finding against that change. C2 sets chmod 000 on precheck_pack.sh and slicer.py in the live checkout for a short window (pre-existing, commit 03f911e). Any other suite reading those files from the same checkout at that moment fails with a misleading error (observed: cp Permission denied in the shellcheck_red M11 case, 173/3 instead of 174/2). Do the chmod on a copy so the suites can run in parallel (section 11.4.230(C)). review report scratchpad/review_atm1217_base_r2.md (vehicle/atm1217-base head a5c5df3, round 2, verdict GO-with-follow-ups, section 11.4.276(G)). Origin: independent-review follow-up, section 11.4.276(G.2), atm1217-base round 2. Scope: scripts/fastcycle/review/precheck_pack_run.py and scripts/fastcycle/tests/test_precheck_*. Parent: CON-033 (Roadmap-Item of the atm1217-base landing).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/test_precheck_pack_build_red.sh (case C2)

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
The reported behaviour is resolved AND proven by captured physical evidence on a clean deployment (§11.4.5 / §11.4.69 / §11.4.108), with a permanent regression guard (§11.4.135).

## CON-047 — Env census false positive: awk -f program attributed to jq (closure N3 negative)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con047_reproduction_2026_11_05.txt` — red-command `append 'echo "a command . b"; jq -e . "$0" >/dev/null; # eval ". x"' to a copy of scripts/gates/cm_killpg_pgid_guard.sh, then bash scripts/gates/cm_gate_env_reads_allowlisted.sh --root <copy> (closure test case N3 negative)` — env `host, python3 -I, census at vehicle/census-safe 7ed1fe7 (sha256 4d98f55f...); control: main 8e496db census gives PASS rc 0` — signature `rc 1, exactly one row: UNCOVERED scripts/gates/cm_killpg_pgid_guard.sh:425 jq-env (indirect)` — updated 2026-11-05T16:53:27Z — by `AI (Claude Sonnet 5.5, landing of vehicle/census-safe; reproduction by Claude Opus 5.5, census round 3)`
**Investigation:** in-progress — updated 2026-11-05T16:53:27Z — by `AI (Claude Sonnet 5.5, landing of vehicle/census-safe; reproduction by Claude Opus 5.5, census round 3)`

What: the env-read census (scripts/gates/lib/gate_env_census.py, gate CM-GATE-ENV-READS-ALLOWLISTED) gives a false positive on the closure test case "N3 negative: words in echo/jq argument/comment do not trigger" (tests/gates/test_gate_env_census_closure.sh). The case appends `echo "a command . b"; jq -e . "$0" >/dev/null; # eval ". x"` to scripts/gates/cm_killpg_pgid_guard.sh. Once that file runs jq, the census reports `UNCOVERED scripts/gates/cm_killpg_pgid_guard.sh:425 jq-env (indirect)`; line 425 is inside the awk classifier SHAWK (a quoted heredoc read at line 357, written to $SHAWKF at line 1110 and run as `awk -f "$SHAWKF"` at line 1237), not jq code. Measured 2026-11-05: with the census of main cb31e32 and the two allowlist rows of the census-safe landing this case gives PASS (rc 0); with the CON-015/CON-016 census change (keep the jq env check armed when region ownership is undecidable) it gives FAIL (rc 1). So the false positive is the cost of that fail-closed change, not a pre-existing defect of main's census. (On main cb31e32 the case also fails, for a different reason: the real tree itself is FAIL with uncovered=2 because two eval rows of the 11.4.294/295 anchor gates are not allowlisted.) In the census-safe landing the case is kept and marked KNOWN-FAIL pinned to this item (never counted as PASS); the closure test then exits 3 (known failure outstanding), not 0, and the allowlist mutation test counts only closure rc 1 as a kill.

History: a disown rule for this shape (CON-017, commit 0e4b197) and a rewrite of it (commit 94a1d28) each got a NO-GO from an independent Opus review: review_census_delta3_opus.md and review_census_con017_fix.md in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/. Two consecutive NO-GO rounds on regex disown heuristics are a heuristic tower (section 11.4.250, 11.4.276(E)); neither commit was landed.

Structural direction: replace the regex-based disown with a parse of jq's own command line: judge only the program operand of a jq invocation (the first non-option argument, or the file named by -f/--from-file), never its data arguments and never text that belongs to another command (awk, sed, echo). Case corpus to preserve and reuse: commit 94a1d28 (branch fix/con017-class, +212/-32 in gate_env_census.py, +402 jq-region test lines), preserved 2026-11-05 as a self-contained git bundle with complete history (no --shared alternates): /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/con017_evidence_94a1d28.bundle, sha256 9814832c16f5b9fa40a7d53b6d91234d27ce7b8956df282e1ea3efcdd595cf7d (git bundle verify OK; a fresh clone of it has 94a1d28 at fix/con017-class and git fsck --full rc 0). Its review evidence directory rv4_opus_evidence is archived as /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/con017_rv4_opus_evidence.tar.gz, sha256 d417cbefdddd575ac61a48abdb3f42ee7fdadca0f183ad6253b4d35dabf49dec (94 entries). Durable locations (landing of vehicle/census-safe, 2026-11-05): the 94a1d28 bundle is pushed to the wip ref `wip/evidence-con017-94a1d28` on origin (fast-forward, new ref) and the archive con017_rv4_opus_evidence.tar.gz (sha256 above) stays host-local; the probe corpora and review rounds 1-3 are tracked under docs/qa/con047_probe_corpora/ (scripts carry a .txt suffix so no scanner or runner treats them as repository code; rename by dropping .txt to run).

Residual shapes for the structural rewrite (review census_safe rounds 2 and 3, recorded on this item rather than as new ids, section 11.4.214): (1) KNOWN-FAIL corpus cases K1..K5 in tests/gates/test_gate_env_census_jq_regions.sh, each pinned to this item with a signature check: `awk -v re='^(sudo|env|time)$'`, `PAT='env|x' awk ...`, `env PAT='^(env|nice)$' sed ...`, `grep -E -e x='(env|sudo)' f` (the assignment owner rule reads an option argument or an environment prefix as a variable assignment) and `jq -n '.a' 'env'` (a data argument of jq, its own region since the round-3 separator); quiet is the wanted result. (2) Shapes quiet on main and on the census-safe head, not yet cases: the line is classified as a whole, not per simple command (`"${JQ:-jq}" -n '$ENV' | sed ...`, `x=$(grep -c f g); jq_run -n 'env | keys'` and their variable forms); a generated program file read by jq through a path, a default or another spelling (`/usr/bin/jq -f "$f"`, `"${JQ:-jq}" -f "$f"`, `jq -f "${f}"`); a herestring read not recognised as an assignment. Residual shapes added in round 3 (review_census_safe_r3.md): (3) the separator at the closing quote widens the false-positive class of K5: any quoted word that is or starts with `env`, belonging to ANY command on a jq line, is reported (for example `jq -r '.a' f | grep -v 'env'`, `jq '.a' f; echo 'env'`, `jq -r '.k' f | tr -d 'env'`, `jq -n '$x' --arg x 'env'`); zero real instances in the repository (1224 tracked shell files); it needs at least one more KNOWN-FAIL case beside K5, e.g. `jq -r '.a' f | grep -v 'env'`. (4) Still missed (quiet on main and on the head): F08, F09, F26 (`'env'` followed by another region on the line), F11 (`jq -n '$ENV' | jq '.PATH'` read as a named PATH read), F16 (`[env]`), F13 (double-quoted jq dump program, tracked separately). (5) RULE: a false positive of this class is NEVER cured with an allowlist row, because the census keeps one jq-env row per file and the allowlist matches (glob, VAR) for the whole file, so such a row would hide every later real jq dump in that file; the cure is a code change under this item. (6) Full-suite runner: rc 3 is FAIL `rc_3`; a known-failure row for the closure test or the jq-region test MUST use `reason:rc_3`, never a log-substring signature (a substring row also marks a log that carries a new real FAIL beside the known one as KNOWN). Probe sources are tracked under docs/qa/con047_probe_corpora/ (probe.sh.txt..probe5.sh.txt, probe_corpus*.py.txt, judge_probe, fuzz_mono, wide_diff, realtree, runwith, and review_census_safe.md, _r2, _r3).

Operator decision (section 11.4.66, 2026-11-05, interactive question; relayed, not verbatim): ACCEPT the deferral of the structural census rewrite to this item under section 11.4.276(E)(1); the decision names vehicle/census-safe (landed with review round 3 GO-with-follow-ups, head 2e5f352) and CON-047. The 11.4.276(E)(1) structural trigger fired in round 3 (N1 important + N2 minor in one class); the rewrite is not done in the vehicle, and no further regex owner rule may be added meanwhile.

Stop rule: no further regex owner rule in gate_env_census.py; every new residual becomes a case here (section 11.4.250).

Attribution note: this item was created by an agent; its item_history Opened row records `User` (the engine default of that intake path). History rows are append-only, so the correction is recorded here.

**Affected scope / file-scope manifest:**
scripts/gates/lib/gate_env_census.py; tests/gates/test_gate_env_census_closure.sh; tests/gates/test_gate_env_census_jq_regions.sh

## CON-064 — CON-047 census FU-1 (R3-1, R3-2): pin the separator's $'..' member and its neutrality in test_gate_env_census_jq_regions.sh

**Status:** Queued
**Type:** Task
**Severity:** Low

Round-3 review of vehicle/census-safe (review_census_safe_r3.md, docs/qa/con047_probe_corpora/, verdict GO-with-follow-ups, section 11.4.276(G.2)). Reviewer mutant mD (the region separator applied only to plain single-quoted regions, not to $'..') survives the whole suite at 52/0/5 and turns F27-F29 quiet; reviewer mutant mM (separator "|" instead of newline) survives and adds 424 of 3000 fuzz reports. Add test-only cases: F27 `jq --arg nl $'\n' -n 'env | keys'`, F28 `jq -n --arg t $'a\tb' 'env | keys'`, F29 `jq -r $'.a' f; jq -n 'env | keys'` as fire cases (they fire on the head and are quiet on mD, on the version without the separator and on main), and Q02 `jq --arg src 'env' -n '$src'` as a quiet case (quiet on the head, fires on mM); then adopt mD and mM as killing mutants in the allowlist mutation test. Severity minor, finding layer test-instrumentation; no batch claim of the vehicle is invalidated.

**Affected scope / file-scope manifest:**
tests/gates/test_gate_env_census_jq_regions.sh; scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh

## CON-065 — CON-047 census FU-2 (R3-4, R3-5): record the known-failure row rule (reason:rc_3) and the no-allowlist-cure rule for census false positives

**Status:** Queued
**Type:** Task
**Severity:** Low

Round-3 review of vehicle/census-safe, findings R3-4 and R3-5 (minor, section 11.4.276(G.2)). R3-4: the full-suite runner reads exit status 3 as FAIL rc_3 (measured with the runner's own judge and known-row matcher). A known-failure row with a log-substring signature such as [tracked CON-047] also marks a log that carries a NEW real FAIL beside the known one as KNOWN; a reason:rc_3 row does not. When the runner manifest stops refusing, the rows for tests/gates/test_gate_env_census_closure.sh and tests/gates/test_gate_env_census_jq_regions.sh MUST use reason:rc_3. Record this in the runner guide and the manifest header. R5: the census keeps one jq-env row per file and the allowlist matches (glob, variable) for the whole file, so curing a false positive of the K-shape class with an allowlist row hides every later real jq dump in that file; the cure is a code change under CON-047. Record the rule next to config/gate_env_allowlist.tsv. Both rules are also recorded on CON-047. Documentation only.

**Affected scope / file-scope manifest:**
docs/guides/full_suite_runner_guide.md; config/full_suite_manifest.tsv (comment); config/gate_env_allowlist.tsv (header comment)

## CON-066 — Env census does not report double-quoted jq dump programs (jq -n "env | keys", jq -n "\$ENV")

**Status:** Queued
**Type:** Bug
**Severity:** Low

Round-3 review of vehicle/census-safe, finding R3-6 (minor, source-defect, pre-existing, section 11.4.276(G.2)). Double-quoted jq whole-environment dump programs (`jq -n "env | keys"`, `jq -n "\$ENV"`) are not reported by the env census on main or on the census-safe head; the census only treats single-quoted regions as jq code. Zero real instances in the repository (1224 tracked shell files scanned). Checked against CON-036 (census blind spots: sed-produced jq program, bash -c inner quote, per-line interpreter detection, literal-path alias) and CON-047 (false positives): neither covers double-quoted jq programs, so this is a separate item, not a duplicate (section 11.4.214). Reproduction: not yet assessed as a tracked record (state UNSET); the shape is quiet in the reviewer probe corpus (docs/qa/con047_probe_corpora/, shape F13), which is the starting point for the RED case. Cure belongs to the structural census rewrite of CON-047, not a new regex rule (stop rule of CON-047).

**Affected scope / file-scope manifest:**
scripts/gates/lib/gate_env_census.py; tests/gates/test_gate_env_census_jq_regions.sh

## CON-067 — CON-047 census FU-3 (R3-7): record the attribution and out-of-scope reasons for the census-safe vehicle commits

**Status:** Queued
**Type:** Task
**Severity:** Low

Round-3 review of vehicle/census-safe, finding R3-7 (minor, process-doc). Commit 7ed1fe7 changes three paths outside CON-047's file-scope manifest without Out-of-scope trailers (section 11.4.293(A)): config/full_suite_manifest.tsv, docs/guides/full_suite_runner_guide.md, scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh (reason class fix-gate-or-test: the jq-region suite joins the manifest and the allowlist mutation test). The cases G6-G9 prove the CON-015 fix but are attributed to CON-047; the region separator closes defect F7, which had no item of its own; earlier vehicle commits (bc788b7 and before) carry no Roadmap-Item trailer. History cannot be rewritten (section 11.4.113), so the attribution is stated on the landing merge commit and recorded here. No code change.

**Affected scope / file-scope manifest:**
vehicle/census-safe commit history (record only)

## CON-068 — CON-047 census FU-4 (R3-12): durable evidence for the census-safe rounds (bundle ref, probe corpora)

**Status:** Queued
**Type:** Task
**Severity:** Low

Round-3 review of vehicle/census-safe, finding R3-12 (minor, process-doc). The 94a1d28 bundle, the evidence archive and the probe sources cited by CON-047 sat in the session cache directory only. At landing (2026-11-05) the 94a1d28 history was pushed to the wip ref wip/evidence-con017-94a1d28 on origin (fast-forward new ref) and the probe corpora and review rounds 1-3 were copied into docs/qa/con047_probe_corpora/ (scripts with a .txt suffix). Remaining: the evidence archive con017_rv4_opus_evidence.tar.gz (sha256 d417cbefdddd575ac61a48abdb3f42ee7fdadca0f183ad6253b4d35dabf49dec, 94 entries) is still host-local; decide whether to push it to a wip ref or a tracked docs/qa location, and retire the wip ref under section 11.4.288(B)(4) when CON-047's rewrite lands.

**Affected scope / file-scope manifest:**
docs/qa/con047_probe_corpora/; wip/evidence-con017-94a1d28 (ref)

## CON-069 — CON-047 census FU-5 (R3-8 to R3-11): nits from review round 3 of vehicle/census-safe

**Status:** Queued
**Type:** Task
**Severity:** Low

Round-3 review of vehicle/census-safe, nits (section 11.4.276(G.2), process-doc): R3-8 the author report counted the runner manifest problems as 26 to 24 while the measured counts are 25 at c41b6c7, bc788b7 and 8e496db and 24 at the head (no action beyond this note); R3-9 the engine's Updated history reason names a state change but not a description change made in the same call (optional engine follow-up); R3-10 the CLASS RULE comment in scripts/gates/lib/gate_env_census.py lists K5 under rule (2) (assignment) while K5 comes from rule (1) plus the separator (fix the comment together with the widened false-positive class of CON-047, which should also be named in that comment); R3-11 CON-047's investigation state was UNSET and is set to in-progress at landing (done through the engine).

**Affected scope / file-scope manifest:**
scripts/gates/lib/gate_env_census.py (comment); scripts/workable-items (engine, optional)

## CON-071 — multitrack_sessions.sh: 'shift 2>/dev/null || true' is fatal under dash on an empty argument list, so the no-argument call prints nothing

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Conductor
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con071_reproduction_2026_11_05.txt` — red-command `sh scripts/multitrack/multitrack_sessions.sh; echo rc=$?` — green-command `sh scripts/multitrack/multitrack_sessions.sh; echo rc=$? (stderr carries the usage text)` — env `host anton, dash 0.5.12-12ubuntu3, file blob 2650500c4ffb1eb6440876f2ef36a913dc2f2485 (sha256 8a84d647c26ab9506f640dc75c7a095dbe1494cdcace2c2870fe3c6bc9bf1b63)` — signature `under sh (dash) the no-argument call exits 2 with zero stderr bytes (usage never printed)` — updated 2026-11-05T17:53:34Z — by `Conductor`
**Investigation:** root-cause-found-with-evidence — root-cause `dash treats shift on an empty positional list as a special-builtin error that exits the non-interactive shell; '2>/dev/null || true' cannot catch a shell exit. Toggle: guarded '[ $# -gt 0 ] && shift' survives, unguarded aborts (decisive experiment in the record).` — evidence `docs/qa/con071_reproduction_2026_11_05.txt` — updated 2026-11-05T17:53:34Z — by `Conductor`

What: under sh (dash) scripts/multitrack/multitrack_sessions.sh run with no arguments exits 2 with no output; bash prints the usage text on stderr and exits 2. main() does _cmd="${1:-}"; shift 2>/dev/null || true. In dash a shift with no positional parameters is a special-builtin error that exits the non-interactive shell, so the redirect and the || true cannot catch it. The same shape sits at three sites: lines 327 (cmd_spawn), 472 (cmd_drive/resume) and 588 (main). test_multitrack_sessions_pid_status.sh works around it by sourcing with a 'help' argument (C3). Found by the round-1 independent review of vehicle/redpin (docs/qa/redpin_review/review_redpin_r1.md, V12) and the redpin author report (docs/qa/redpin_review/redpin_author_report_r1.md, follow-up 3). Out of scope for the test-only redpin change (section 11.4.293(A)). Supersedes the id CON-064/CON-065 that commit ce775c9 on vehicle/redpin gave this item (those ids belong to other items on main; review R2-1, section 11.4.54). Attribution note: created by an agent (redpin landing subagent) through the engine; if item_history records a different opener, that is the engine default of this intake path and this note is the correction (history is append-only).

**Reproduction / context:**
reproduced-live on the host (the code runs only on the host), record docs/qa/con071_reproduction_2026_11_05.txt: RED 'sh scripts/multitrack/multitrack_sessions.sh' rc=2 with 0 stderr bytes, 3 of 3 runs; control under bash rc=2 with 490 stderr bytes starting 'usage: multitrack_sessions.sh <command> [args]'. Decisive experiment in the same record: sh -c 'shift 2>/dev/null || true; echo survived' prints nothing (rc 2); sh -c '[ $# -gt 0 ] && shift; echo survived' prints survived (rc 0); bash prints survived for both.

**Acceptance criteria:**
(1) All three sites use a guarded shift ([ $# -gt 0 ] && shift, or an equivalent that never runs shift on an empty list), class-wide per section 11.4.276(C): every 'shift ... || true' site in scripts/multitrack/ is enumerated with a control-needled scan and fixed or scoped out. (2) A dash regression test that is RED on the current file (no-argument call under sh prints no usage) and GREEN after the fix with the same command, the same host and the same signature (section 11.4.292(E)), plus a paired mutation that restores the unguarded shift and makes the test FAIL. (3) The C3 'help' workaround in test_multitrack_sessions_pid_status.sh is removed or kept with a reason.

**Affected scope / file-scope manifest:**
scripts/multitrack/multitrack_sessions.sh lines 327, 472, 588; scripts/multitrack/test_multitrack_sessions_pid_status.sh (C3 workaround)

## CON-072 — Vendor the RB-05 mock claude into the constitution so the two mock-driven multitrack guards and the redpin carrier legs run standalone

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: round-1 review finding F4 of vehicle/redpin (docs/qa/redpin_review/review_redpin_r1.md): without the consumer-only RB-05 mock the two mock-driven tests always SKIP in the canonical repository. The suite-level absorption of those SKIPs is fixed in round 2 (the mutation suite exits 77 when any leg skipped). The remaining work is to vendor the mock (it is a test double; verdicts through it stay UNIT-CLASS, section 11.4.289) with its provenance, and have the tests find it in-tree. Same environment class, also open: test_multitrack_sessions_balance_autoselect.sh (rc 90) and test_multitrack_monday_dryrun.sh (rc 91), per docs/qa/redpin_review/redpin_author_report_r1.md follow-up 5. Supersedes the id CON-064/CON-065 that commit ce775c9 on vehicle/redpin gave this item (those ids belong to other items on main; review R2-1, section 11.4.54). Attribution note: created by an agent (redpin landing subagent) through the engine; if item_history records a different opener, that is the engine default of this intake path and this note is the correction (history is append-only).

**Reproduction / context:**
Measured 2026-11-05 on a clean clone of vehicle/redpin with no MT_TEST_MOCK_CLAUDE: test_multitrack_sessions_pid_status.sh and test_multitrack_supervisor_wiring.sh exit 77 reason=rb05_mock_absent; test_multitrack_redpin_mutations.sh exits 77 with 3 leg groups skipped (PASS=12 SKIP=3); re-measured by the round-2 review (docs/qa/redpin_review/review_redpin_r2.md V3, V5). In the canonical repository their coverage is zero.

**Acceptance criteria:**
On a standalone constitution clone with no MT_TEST_MOCK_CLAUDE, both tests and the redpin mutation suite run their legs and exit 0; the vendored mock carries its source repository, commit and sha256.

**Affected scope / file-scope manifest:**
scripts/multitrack/rb05_fixtures/mock_claude.sh (new in the constitution; today only in the consumer project), scripts/multitrack/test_multitrack_sessions_pid_status.sh, scripts/multitrack/test_multitrack_supervisor_wiring.sh, scripts/multitrack/test_multitrack_redpin_mutations.sh

## CON-073 — Census guard tests/test_no_head_red_builder.sh scans its own positive-control copies when TMPDIR is inside tests/ (third self-carrier, review R2-2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: the guard writes its ctrl_*.sh positive-control copies into its scratch dir $S and only then builds the census list; with TMPDIR pointing at a non-ignored directory under tests/ the census scans the copies, flags 7 lines and exits 1 (reproduced by the reviewer with TMPDIR=tests/tmpx). Same class as round-1 F1, third instance. Acceptance: build the census list before writing the controls, exclude $S, or refuse a scratch dir inside the repository root; add a mutation leg that runs the guard with TMPDIR inside tests/ and asserts rc 0. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
tests/test_no_head_red_builder.sh; tests/test_no_head_red_builder_mutations.sh

## CON-074 — Adopt reviewer mutant RM-1 (census file filter drops _mutation_test.sh) as a leg of the census mutation test (review R2-3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: deleting the '|_mutation_test\.sh$' alternative from the census grep -E filter survives the whole census mutation suite (13/0) while the scanned set shrinks from 681 to 489 files; a builder line appended to scripts/gates/cm_agent_type_label_mutation_test.sh is then missed. Acceptance: a leg that appends a HEAD-built RED builder to a scripts/gates/*_mutation_test.sh file and requires the census to name it; RM-1 must make that leg FAIL (section 11.4.276(D)). Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
tests/test_no_head_red_builder_mutations.sh

## CON-075 — Census guard scope is narrower than the full-suite runner's census: 18 runner-run sh/py units are never scanned (review R2-4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: the guard's own name filter misses *_test.sh (e.g. the five scripts/gates/covenant_propagation_*_test.sh), *_selftest*.sh, scripts/label-sync/prove_*mutations.sh, meta_test_inheritance.sh and progressive/mutation_matrix.py, so any of them could gain a HEAD-built RED artifact unseen. Acceptance: the guard scans the runner's own census set (the file list --verify-manifest uses) instead of a second name filter, with a control-needled count and a leg on one of the formerly missed files. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
tests/test_no_head_red_builder.sh; scripts/run_full_suite.py (census set reuse)

## CON-076 — HEAD-red builder detector: 25 further blind-spot shapes, header overclaims Python coverage; invert the default instead of closing shapes one at a time (review R2-5)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: 25 new probe shapes (process substitution, defaulted revisions, git show :path, implicit HEAD via git log, moving refs main:/origin/main:, git checkout HEAD --, git restore --source=HEAD, worktree add HEAD~1, heredoc bodies, git wrapper functions, HEAD@{0}, prefix redirects, cat-file --textconv, Python shell=True/os.system and string concatenation) are all missed by the detector; header line 19 claims any Python show/cat-file HEAD read is covered, which three shapes contradict. No live instance found (broad tree scan, 3 hits, none builds a RED artifact). The round-2 fix closed exactly the 8 named shapes, the instance-at-a-time closure section 11.4.276(C) warns about. Acceptance: invert the default (flag every HEAD-relative, moving-ref or index blob/tree read in a test; the reason-carrying opt-out marker covers compare-only reads), correct the header to the real limits, and adopt the 25 shapes as mutation legs. If this class reappears in a later round it forces a structural round (section 11.4.276(E)). Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
tests/test_no_head_red_builder.sh; tests/test_no_head_red_builder_mutations.sh

## CON-077 — Adopt reviewer mutant RM-3 (delete the SKIP-to-77 block) as a leg: the round-1 F4 fix has no regression guard (review R2-6)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: deleting the 'if [ "$SKIP" -gt 0 ] ... exit 77' block from scripts/multitrack/test_multitrack_redpin_mutations.sh, run without the mock, gives PASS=12 FAIL=0 SKIP=3 rc 0, which the runner's judge() reads as PASS; the unmutated suite is SKIP rb05_mock_absent. Acceptance: a leg that runs the suite with the mock absent and asserts rc 77 and the trailing 'reason=rb05_mock_absent' line; RM-3 must make it FAIL. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
scripts/multitrack/test_multitrack_redpin_mutations.sh

## CON-078 — CARRIER_IMMUNE comment overclaims: its worker half is an equivalent mutant on this path (review R2-8, nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: mutant m_worker restores only the worker pattern to the pre-RB-02 default and passes every leg with one and four carriers, because sessions passes its own live-worker count. Acceptance: reword the block comment to say what the worker half protects (or drop it), with the equivalence recorded. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
scripts/multitrack/test_multitrack_sessions_pid_status.sh; scripts/multitrack/test_multitrack_supervisor_wiring.sh

## CON-079 — Carrier visibility control needle in the redpin mutation suite is tautological (review R2-9, nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: the control that proves the carrier process is visible reuses the same _bw token it checks for. Acceptance: prove visibility with an independent read (for example pgrep -f of the real pre-RB-02 build pattern), so the control can fail when the carrier is not visible (section 11.4.273). Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
scripts/multitrack/test_multitrack_redpin_mutations.sh

## CON-080 — Stale 'measured 5.6 s' timing note on the census mutation test manifest row (review R2-10, nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: config/full_suite_manifest.tsv says override fast (measured 5.6 s) for tests/test_no_head_red_builder_mutations.sh; the reviewer measured 36 s wall time under CPU pressure (load about 33 on 16 CPUs). Acceptance: re-measure and record the figure together with the load it was measured under. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
config/full_suite_manifest.tsv

## CON-081 — Redpin carrier process is visible host-wide for about 40 s and can be counted by other sessions' bare-pgrep guards (review R2-11, nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

What: the carrier started by the carrier-immune legs is visible to every bare-pgrep guard on the host for about 40 s. Acceptance: run it in its own PID namespace (unshare --pid --fork --map-root-user) where available, else keep its lifetime minimal, with the choice recorded. Source: review round 2 of vehicle/redpin, docs/qa/redpin_review/review_redpin_r2.md (section 11.4.276(G.2) follow-up; the code slice landed GO-with-follow-ups). Created by an agent (redpin landing subagent) through the engine.

**Affected scope / file-scope manifest:**
scripts/multitrack/test_multitrack_redpin_mutations.sh; scripts/multitrack/test_multitrack_sessions_pid_status.sh; scripts/multitrack/test_multitrack_supervisor_wiring.sh

## CON-082 — tests/layout/test_generator_atomic.sh SIGTERM legs (4) and (10e) give different verdicts on the same committed file (nondeterministic, cause UNCONFIRMED)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Conductor
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T17:53:34Z — by `Conductor`
**Investigation:** not-started — updated 2026-11-05T17:53:34Z — by `Conductor`

What: observation O1 of review round 2 of vehicle/redpin (docs/qa/redpin_review/review_redpin_r2.md). The same committed file gave PASS=55 FAIL=2 rc 1 (11 m 56 s; failures '(4) staging left after SIGTERM (had 6)' and '(10e) TERM at mid_commit lost files or left staging') and, on re-run of the same tree, PASS=57 FAIL=0 rc 0 (9 m 16 s); main 7f72395 run concurrently passed 57/0. The vehicle changes this file only by a trailing comment. Cause UNCONFIRMED; CPU contention (pressure about 56 % avg10 at the time) is a hypothesis only. Not caused by the redpin change (section 11.4.293(A)). Created by an agent (redpin landing subagent) through the engine.

**Reproduction / context:**
UNCONFIRMED: no deterministic reproduction yet; the two verdicts come from the reviewer's runs (evidence tracked at docs/qa/redpin_review/r2_evidence/gen_atomic.out, gen_atomic_rerun.out, gen_atomic_main.out, copied from the reviewer's session evidence). A reproduction MUST be established first (section 11.4.292), for example by running legs (4) and (10e) N times under controlled CPU load.

**Acceptance criteria:**
Legs (4) and (10e) give the same verdict in N >= 3 consecutive runs (section 11.4.50) under the load the full suite runs them with; root cause established by a decisive experiment; a permanent regression guard (section 11.4.135).

**Affected scope / file-scope manifest:**
tests/layout/test_generator_atomic.sh (SIGTERM legs 4 and 10e) and the generator it drives

## CON-085 — parse_mutation.py keeps the trailing double quote of the echo in the description when a mutation banner has no closing em-dash

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 excluded-list investigation)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con085_reproduction_2026_11_05.txt` — red-command `python3 -I run.py scripts/catalog-engine/lib/parse_mutation.py meta.sh meta_ctl.sh (fixtures in the evidence file)` — env `host, vehicle 2595f06 (parser sha256 edfd1270, identical on main efe2cc6c)` — signature `meta.sh description='text"'` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`
**Investigation:** root-cause-found-with-evidence — root-cause `_RE_MUT_DEF ends the description at a closing em-dash or at end of line, so without the em-dash the closing double quote of the echo is captured; the closing em-dash control returns text; toggling only the regex removes the signature` — evidence `docs/qa/con085_reproduction_2026_11_05.txt` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`

Measured 2026-11-05: for the line  echo "— CM-X mutation: text"  (no closing em-dash) parse_mutation_file returns description 'text"' (with the quote; for an empty text it returns the single character "), because _RE_MUT_DEF ends at an em-dash or end of line. The catalog records a wrong description and derivation_gaps misses no-mutation-description. Not changed by the CON-083 test (it does not pin the defect). The reviewer's surviving mutant rv_require_close belongs with this fix. Id history (review F2, §11.4.214): first minted in the vehicle as CON-066 (commit e581a31), then CON-072 (commit 35e8d53f), re-minted as CON-085 at landing on main, because main already owns CON-064..CON-082 and CON-070 is reserved for the CON-030 vehicle. Vehicle commits 4db86ed6, 485c341d and 322c25ef name the first ids and are not rewritten (§11.4.113). Authorship (review F10): the code commits 4db86ed6, 485c341d, 322c25ef and the first registration e581a31 were written by Claude Sonnet 5.5; the merge 2595f06e, the evidence files and state records (35e8d53f) and the note corrections cd1e55ee were written by Claude Opus 5.5; the landing re-mint was done by Claude Opus 5.5. Sources (tracked, §11.4.215): docs/qa/con031_excluded_review/excluded_analysis.md, excluded_plan.md and the independent review docs/qa/con031_excluded_review/review_con031_excluded_r1.md (round 1, GO-with-follow-ups).

**Affected scope / file-scope manifest:**
scripts/catalog-engine/lib/parse_mutation.py

## CON-086 — full-suite manifest lacked rows for 25 census files on main ecfe4325 (26 on 7f72395), so --verify-manifest ended MANIFEST-MISMATCH and the operator could not run --accept-excluded-change

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 excluded-list investigation)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con086_reproduction_2026_11_05.txt` — red-command `bash scripts/run_full_suite.sh --verify-manifest (fresh clone of main ecfe432)` — env `host, fresh clones of main ecfe432 and efe2cc6c` — signature `census file without manifest row (25 on ecfe432 and efe2cc6c, 26 on 7f72395)` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`
**Investigation:** root-cause-unconfirmed — root-cause `UNCONFIRMED: census files land on main without manifest rows because no commit-time or pre-build seam refuses that; the missing rows are measured, the absent seam is not yet shown by a toggling experiment` — evidence `docs/qa/con086_reproduction_2026_11_05.txt` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`

Measured 2026-11-05 on main 7f723954: bash scripts/run_full_suite.sh --verify-manifest exit 3, RESULT: MANIFEST-MISMATCH (26 problems), all 'census file without manifest row'; re-measured 25 on main ecfe4325 and on main efe2cc6c (review F13). The runner refuses --accept-excluded-change while any other manifest problem exists, so CON-031 cannot be done on main. Vehicle commit 485c341d regenerates the manifest (27 rows incl. the new CON-083 test, two new excluded rows with reasons; one of the 27 also landed on main with census-safe, so the net change against ecfe4325 is 26 rows, review F12) and syncs the guide. On the landed tree --verify-manifest reports only the excluded-lock difference, which the operator accepts (O1). The rows are a symptom fix: the recurrence seam (a pre-build check that refuses a census file without a manifest row) is not built, so this item stays open. Id history (review F2, §11.4.214): first minted in the vehicle as CON-067 (commit e581a31), then CON-073 (commit 35e8d53f), re-minted as CON-086 at landing on main, because main already owns CON-064..CON-082 and CON-070 is reserved for the CON-030 vehicle. Vehicle commits 4db86ed6, 485c341d and 322c25ef name the first ids and are not rewritten (§11.4.113). Authorship (review F10): the code commits 4db86ed6, 485c341d, 322c25ef and the first registration e581a31 were written by Claude Sonnet 5.5; the merge 2595f06e, the evidence files and state records (35e8d53f) and the note corrections cd1e55ee were written by Claude Opus 5.5; the landing re-mint was done by Claude Opus 5.5. Sources (tracked, §11.4.215): docs/qa/con031_excluded_review/excluded_analysis.md, excluded_plan.md and the independent review docs/qa/con031_excluded_review/review_con031_excluded_r1.md (round 1, GO-with-follow-ups).

**Affected scope / file-scope manifest:**
config/full_suite_manifest.tsv, docs/guides/full_suite_runner_guide.md

## CON-087 — CON-031 excluded FU-1 (review F5, F6): adopt the 7 surviving reviewer mutants of test_parse_mutation.sh and report LOAD-FAILED separately

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)

The independent review (docs/qa/con031_excluded_review/review_con031_excluded_r1.md, findings F5 and F6) ran 10 own mutants of scripts/catalog-engine/lib/parse_mutation.py against scripts/catalog-engine/tests/test_parse_mutation.sh: 3 killed, 7 survive (rv_atm_on_line, rv_hdr_last_wins, rv_strict_utf8, rv_expect_no_b, rv_require_close, rv_hdr_one_dash, rv_type_hardcode). Add the cases that kill them: an ATM id outside the description, two headers for one gate, a non-UTF-8 byte, expect_prebuild_failX, a banner without closing em-dash (with the CON-085 fix), a one-dash header, a second type_root value. Also report a mutant that fails to load separately from killed, or assert that only the named mutant may fail to load (F6). Acceptance: every listed mutant is a paired leg of the test and is killed.

## CON-088 — CON-031 excluded FU-2 (review F1): have a test run render_keys_ref.py against the render_keys key fixtures

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)

Review finding F1 (docs/qa/con031_excluded_review/review_con031_excluded_r1.md): scripts/fastcycle/tests/lib/render_keys_ref.py is not executed by any test. test_render_keys_red.sh assigns REFKEY (line 75) and only checks that the file exists (lines 323 to 326); the oracle was run once by hand to make the fixtures/render_keys/*/key_*.json files (fixtures README line 115). Add a test step that runs the oracle against the fixtures and compares its output with the recorded keys, so the fixture keys stay grounded in a live computation; then update the excluded note of the row in config/full_suite_manifest.tsv. Acceptance: the oracle runs in a default unit and a paired mutation of it fails that unit.

## CON-089 — CON-031 excluded FU-3 (review X1, X4): test_gen_lumenignore.sh prints SKIP but exits 2, cannot find lumen under the runner's sandbox HOME, and deletes without ${W:?}

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)

Review finding X1 (docs/qa/con031_excluded_review/review_con031_excluded_r1.md): scripts/lumen/tests/test_gen_lumenignore.sh FAILs in every full-suite run. Its fallback looks for the lumen binary under $HOME/.claude-shared/..., the runner gives each unit a sandbox HOME, and LUMEN_BIN is not in the runner's environment base. It then prints 'SKIP: lumen binary not found' but exits 2, which judge() records as FAIL rc_2. Measured by the reviewer: sandbox HOME without LUMEN_BIN rc 2 in 0 s; with LUMEN_BIN set rc 0, 4 checks pass. Fix: the test prints what it does (a FAIL naming the missing prerequisite, per operator decision O3), and the runner passes LUMEN_BIN or resolves it in a preflight. X4: the same test deletes with a bare rm -rf "$W"; use ${W:?} or safe_rm_rf (§11.4.287(C)(1)). Acceptance: the unit passes under the full-suite runner on a host with lumen installed, and its output matches its exit code.

## CON-090 — CON-031 excluded FU-4 (review X3): workable-items update records an evidence path but no sha256

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)

Review finding X3 (docs/qa/con031_excluded_review/review_con031_excluded_r1.md): the workable-items engine stores reproduction_evidence and investigation_evidence as paths only; §11.4.294(C) asks for a captured evidence path plus its sha256 written in the same transaction, and a demotion when the evidence no longer resolves. Add the sha256 columns (computed by the engine at write time), render them in the Reproduction and Investigation body lines, and check them in validate. Acceptance: an item whose evidence file changes after recording is reported by validate.

## CON-091 — CON-031 excluded X2: two orphan reference copies under scripts/fastcycle/lib/ diverge from the copies the test uses (awaiting operator decision O2)

**Status:** Operator-blocked
**Type:** Task
**Operator-Block-Details:** WHAT: awaiting operator decision O2 on the two orphan reference copies under scripts/fastcycle/lib/; no agent may delete them (section 11.4.122, 11.4.124) WHY: deleting or re-pointing shipped files needs an operator decision; the evidence is recorded in the review (X2, O2) UNBLOCK: [A] retire both copies as obsolete duplicates (reviewer recommendation, section 11.4.90) · [B] review both versions, point the test at the correct one, retire the other · [C] keep both and document why WHO: AI (Claude Opus 5.5)
**Severity:** Low
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)

Review finding X2 (docs/qa/con031_excluded_review/review_con031_excluded_r1.md): scripts/fastcycle/lib/dec23_key_ref.py and scripts/fastcycle/lib/tce_normalize_ref.py (added in a925a8da on 2026-09-30) are never loaded; the only test reads scripts/fastcycle/tests/lib/. They are not only reworded: for fixture mr_good_killed_reuse/put_envelope.json the used copy prints dc6819b0..., the orphan dec23_key_ref.py prints 4b6e4fc0... (canonical JSON instead of U+001F-joined fields); the product gates/mutation_reuse.py uses U+001F-joined fields like the used copy. Do NOT delete them before the operator decides (§11.4.122, §11.4.124). The reviewer recommends retiring both as obsolete duplicates (§11.4.90). Acceptance: the operator's decision O2 is recorded and applied.

## CON-092 — Fastcycle consumer-data guard: skip per section, not the whole test (review F3)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F3 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). The 24 fastcycle tests that source scripts/fastcycle/tests/lib/consumer_required.sh SKIP as a whole (exit 77) when consumer-project data is absent. Before the change they ran about 400 assertions that work on canon alone (for example consumer_audit 66 ok, catchset 67, plan_struct_causes 56, plan_struct_full 36, capture_triplet 25, escape_classify 23, limit_class 18, host_limits 17, alias_spread 15), and those assertions and their failures are now hidden. Scope: the 24 tests listed by 'grep -l consumer_required.sh scripts/fastcycle/tests/*.sh'. Reproduction: run any of them on canon alone; it prints one SKIP line and none of its canon-runnable checks. Acceptance: only the sections that read consumer data are skipped, each naming the effective path it reads; the canon-runnable sections run and report pass/fail; the runner records the remaining skips with reason=topology_unsupported.

## CON-093 — Nine more fastcycle tests fail on canon alone for missing consumer data, not converted (review F13)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F13 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md, inventory class A). Nine tests fail on canon alone because they read consumer-project data, the same class as the 24 converted tests: test_backstop_red.sh, test_flake_ledger_red.sh, test_mutation_reuse_red.sh (control needle needs specs/004-fast-dev-cycles/contracts/); test_evidence_ref_red.sh, test_governance_subset_red.sh, test_reopen_rate_red.sh, test_resume_revalidate_red.sh (tracker DB read at the consumer root; verified for test_reopen_rate_red.sh, which reads DB=$ROOT/docs/workable_items.db with ROOT four levels up; the other three are UNCONFIRMED); test_fc_commit_stage_timer_mutations.sh and test_fc_timer_prebuild_mutations.sh (inputs missing). Reviewer runs: docs/qa/manifest_triage_review/r1_unconfirmed_fastcycle_runs.tsv. Acceptance: each test checks the effective path it reads and skips only the consumer-dependent sections (fold into CON-092, never another whole-test SKIP); a tracker-DB needle uses the canon DB where that is the intent.

## CON-094 — Manifest-triage wording nits: 24 not 26 tests, census 844 not 843, row order (review F10)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F10 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). Commit 1f65b061 and the round-1 author report said 26 tests source the consumer-data helper; grep finds 24. Merge 0313ffd said census 843; verify-manifest gave 844. Two appended manifest rows were out of sort order. Scope: commit messages and reports only (history is not rewritten). Acceptance: the round-2 commit message and report state the measured numbers (24 tests; the census as printed by --verify-manifest), the manifest rows are in sorted order, and this item closes when that round lands.

## CON-095 — Bisect escape probe: compute the ../ depth from TMPDIR and use a per-run victim file (review F11)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F11 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). scripts/fastcycle/tests/test_batch_bisect_r3_regression.sh hard-codes a chain of 40 '../' and its victim file is a shared name /tmp/m1_escape_probe*.txt. A TMPDIR deeper than 40 levels breaks the probe, and concurrent runs share the victim. Acceptance: the depth is computed from the real TMPDIR depth plus a margin, the victim is a per-run mktemp name outside the sandbox root, and the test is RED on the pre-fix bisect code and GREEN on the current one at TMPDIR depths 5 and 60.

## CON-096 — Two multitrack RED tests pinned to history fail when their dependency is present (review F12)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** not-started — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F12 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). With the RB-05 mock and project root present, scripts/multitrack/test_multitrack_sessions_pid_status.sh gives rc 94 and scripts/multitrack/test_multitrack_supervisor_wiring.sh fails 'RED(A) headhit=3'. They are RED tests pinned to history (same class as orchestrator_reconcile); on canon alone the SKIP hides them. Reporter: the reviewer's own runs with the dependency present but a broken mock; not reproduced by the author. Reproduction: run each with MT_TEST_MOCK_CLAUDE pointing at the real consumer mock. Acceptance: reproduce live (section 11.4.292), find the root cause, and either fix the pin or re-anchor the RED leg to a recorded commit, with a deterministic live test.

## CON-097 — 62 fastcycle tests hard-code $ROOT/constitution/, so they run only when the canon directory is named constitution (inventory class A)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: the wider pattern under inventory class A of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md): 62 of the 160 fastcycle tests reach canon files as $ROOT/constitution/..., where ROOT is the consumer root four levels above the test. Canon checked out under another name (submodules/constitution, a scratch clone, a review clone) breaks them. Scope: grep -l 'ROOT/constitution/' scripts/fastcycle/tests/*.sh (count to be re-measured with a control needle before work). Acceptance: canon paths are resolved from the test's own location (three levels up), consumer paths from the consumer root, and a test proves a test still finds canon when the directory is renamed.

## CON-098 — Eleven fastcycle tests pass alone but fail in the batch (inventory class B)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** not-started — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: inventory class B of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md; reviewer runs docs/qa/manifest_triage_review/r1_unconfirmed_fastcycle_runs.tsv). Each gives rc 0 when run alone and fails in the batch: test_backstop_compare_exit_codes_r2_regression.sh, test_backstop_compare_r3_regression.sh, test_io_trace_build_map_device_safety_r2_regression.sh, test_io_trace_build_map_r3_regression.sh, test_io_trace_build_map_r5_regression.sh, test_io_trace_build_map_setsid_r5_regression.sh, test_io_trace_fork_cwd_and_faccessat_r2_regression.sh, test_precheck_pack_build_red.sh, test_precheck_pack_multi_slice_sibling_search_r5_regression.sh, test_precheck_sibling_blast_radius_honest_verdict_red.sh, test_precheck_sibling_search_unmeasured_literal_r6_regression.sh. Cause UNCONFIRMED (load, ordering, shared state or the batch timeout). Reproduction: run scripts/fastcycle/tests/run_all.sh with the exact batch order and record each failure (section 11.4.199). Acceptance: a recorded live reproduction in the batch, a proven root cause per test, and a fix with a deterministic test.

## CON-099 — Eleven fastcycle tests show behaviour mismatches that need a root cause (inventory class C)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** not-started — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: inventory class C of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md; reviewer runs docs/qa/manifest_triage_review/r1_unconfirmed_fastcycle_runs.tsv). Custody-sweep family: r11, r13 and r15 REFUSE a plain stash that should be ALLOWED (backup patch sha256 does not match the re-derived live content; suspected git config or version effect in a sandbox HOME, UNCONFIRMED), r6 hits a Python traceback in guard-viability, r9 gets rc 2 from custody_sweep.py --repo-root on a long sandbox path. Also: test_escape_classify_malformed_red.sh (non_mapping_entry exits 2, expected a named refusal exit 1), test_fc_entry_r10_regression.sh (B1 inventory with --out gets rc 2), test_gate_shard_r3_regression.sh (Python traceback), test_io_trace_build_map_r6_regression.sh (mutation precondition not reached on this host, proves nothing either way), test_precheck_slicer_red.sh (sh -n under dash did not reject broken_syntax_gate.sh), test_host_guard_red.sh (got reason=unreadable_ulimit where thread_headroom was expected under sh; dash ulimit has no -u is a suspicion, UNCONFIRMED). Acceptance: each reproduced live first (section 11.4.292), root cause proven, fixed or honestly reclassified, with a deterministic test.

## CON-100 — test_host_attribute_red.sh fails btrfs_binary_unavailable when the tool is absent (reported, not reproduced) (inventory class D)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** not-started — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: inventory class D of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). scripts/fastcycle/tests/test_host_attribute_red.sh reports btrfs_binary_unavailable because the exclusive-bytes instrument needs a btrfs tool this host lacks. Whether the tool is truly absent was not checked. Reproduction: run the test on a host with no btrfs binary and record the output and rc. Acceptance: when the tool is proven absent (control needle), the affected legs SKIP with reason=hardware_not_present or topology_unsupported, never FAIL; when present, they run.

## CON-101 — test_precheck_shellcheck_red.sh times out under load with an M11 mutation-flip traceback (inventory class D2)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** not-started — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: inventory class D2 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). scripts/fastcycle/tests/test_precheck_shellcheck_red.sh got rc 124 after 240 s in the reviewer's run, with 'NOT ok: M11 mutation-flip ... Traceback' before the timeout. The failure predates the vehicle (the vehicle only added its member row, which the reviewer judged correct). Reproduction: run it alone with its shebang interpreter and nice -n 10 at host load about 40, record rc, time and the traceback. Acceptance: live reproduction, root cause of the M11 traceback, a fix, and a run time inside the fastcycle per-test bound.

## CON-102 — Fastcycle consumer-data helper test: directory case, absolute-path-with-space, pin commit_stage/prebuild_tsv/metatest_r4/monday effective paths (review R2-1, R2-2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). Surviving mutants M1A, M1G, M2A, M2C, M2D; protected behaviour proven live by the reviewer. Acceptance: tests that kill all five.

## CON-103 — Superspec exclusion topology guard: add a blinded-gate layout and a missing-carrier failure layout (review R2-3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). Surviving mutants M7B, M7C. Acceptance: both killed.

## CON-104 — test_multitrack_sessions_balance_autoselect.sh: align with siblings (mock override, honest SKIP) (review R2-4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). Still FATAL 91 with project root present and no mock; no MT_TEST_MOCK_CLAUDE override.

## CON-105 — Map reason=rb05_mock_absent to a section 11.4.69 closed reason on main (review R2-6)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). Not in the closed set; affects pid_status, supervisor_wiring, redpin_mutations. Use topology_unsupported.

## CON-106 — Tracker hygiene for CON-092..CON-101: split the per-test bundles, correct created_by, parent links (review R2-7)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). CON-098 and CON-099 each bundle 11 tests; the engine has no parent flag, so parents are recorded as a Parent line only (UNCONFIRMED whether a parent column exists).

## CON-107 — Clear CDPATH in the consumer-data helper root cd (review R2-5); name more sourcing tests in its manifest note (R2-8)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Source: review round 2 (docs/qa/manifest_triage_review/review_manifest_triage_r2.md). R2-5 impact UNCONFIRMED (found by reading, not run).

## CON-108 — ownership F1: a byte copy of a checkout can remove the shared extension tree

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Conductor

First minted on the vehicle as CON-070 (CON-070 is reserved on main for the CON-030 class item), re-minted at landing as CON-108. Reported by the independent wave 2 review (finding F1), not reproduced by the reporter of this item. The E01 install fact binds the constitution root and the tree identity, not the project path. A byte copy of a checkout that holds the state directory carries the same signed fact, so running remove from the copy deletes the tree the original still uses. Pre-existing. Wave 2 round 2 made the refusal text honest about this; the defect itself is NOT fixed. Fix belongs with E03 (per-checkout refcount) or a project-realpath binding in the fact; related to CON-042.

**Affected scope / file-scope manifest:**
scripts/constitution_ext/ext_engine.py (remove, E01 fact); E03 refcount

## CON-109 — WIT-C02 stays open: confirm the hermetic-suite remedy with an independent review and a full-suite run

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T12:59:59Z
**Reported-By:** ownership wave 2 WIP session (minted 2026-11-05 12:59 UTC; that session recorded its model as Opus 5.5, UNCONFIRMED by round 3). First minted on the vehicle as CON-050; main had already given CON-050 to another item, so round 3 re-minted it as CON-071; main then gave CON-071 to another item, so it was re-minted at landing (wave 2 round 4) as CON-109 (§11.4.54: an id is never reused).

**What (the report, verbatim):**
Operator decision 2026-11-05 (relayed): the C02 reinterpretation is rejected; C02 stays open. Wave 2 round 2 landed: a per-unit fingerprint (inode, mtime, size, content) of the tracked generated sets checked after every unit by the full-suite runner; a rewritten lint that flags the reviewer's six violators; the two suites measured rewriting the real tree converted to throw-away constitution copies. Open: an independent review of that work, and a full-suite run showing no unit trips the fingerprint, before C02 is closed.

**Affected scope / file-scope manifest:**
scripts/full_suite/run_full_suite.py (gen_fingerprint); tests/layout/hermetic_lint.py; tests/layout/test_hermetic_generator.sh; tests/action_prefix/test_hook_e2e.sh; tests/constitution_cmd/test_install_cli_agent_plugins_ownership.sh

**Reproduction / context:**
UNKNOWN: not stated in the report — a reproduction MUST be established before any fix (§11.4.102 / §11.4.146 / §11.4.199 / §11.4.292)

**Acceptance criteria:**
Independent review GO on the C02 changes; a full-suite run on a clean checkout ends without IDENTITY CHANGED for the gen field; then close WIT-C02 in the design doc.

**Open after round 3 (measured 2026-11-05):**
`hermetic_lint.py` flags 13 of the round-2 reviewer's 14 violators; it does not see an installer reached by a path relative to a `cd` into the real tree (violator v08). That gap stays open under this item.

**Decision after review round 3 (N5, recorded 2026-11-05 by the round-4 fix session; the review recommended it and the conductor's brief ordered it, operator confirmation UNCONFIRMED):**
`tests/layout/hermetic_lint.py` is an ADVISORY tripwire: its findings on the real tests are printed as ADVISORY lines by `tests/layout/test_hermetic_generator.sh` and do not fail it. The BINDING C02 check is the full-suite runner's per-unit fingerprint of the generated sets plus its end-of-run tree identity (`scripts/full_suite/run_full_suite.py` gen_fingerprint / quick_ident, pinned by `tests/test_run_full_suite.sh` section 39 and mutants I1 I2 I3 G1). No new shapes are added to the lint per review round (§11.4.250); the round-3 review's 8 missed shapes and 1 false positive are listed in the lint's docstring as known limits. The acceptance criterion above (a clean full-suite run with no IDENTITY CHANGED) is unchanged.

## CON-110 — ownership wave 2 FU (round 4 N1): on budget expiry timeout --foreground signals only the engine, not its git children

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

First minted on the vehicle as CON-072, re-minted at landing as CON-110. Found while fixing review round 3 N1 (vehicle/ownership-wave2, round 4). The dispatcher now runs extensions add, install-extension, enable and adopt-install with timeout --foreground so the engine can read /dev/tty. With --foreground, timeout signals only its direct child (the engine, because constitution_ext.sh execs python3); a git subprocess the engine started (git clone/fetch for a git source) is not signalled when the budget expires and may outlive the dispatcher. Measured: the no-answer budget case (4 s) ends with rc 124 and no engine process left, but it does not start git. UNCONFIRMED: whether a git child survives a timeout during a git-source add. Round 4 review (N9) CONFIRMED by measurement: in the real topology both timeout implementations return 124 after 5 s while the engine's git clone child is alive at +10 s (reparented to systemd --user). Fix direction: the engine installs a SIGTERM handler that kills its own child process group (pgid > 1 checked, §11.4.263) and then runs the normal cleanup, or starts git in a new process group and kills that group on exit. Acceptance: a pty test with a git source and a stalled git step shows no process left after rc 124, or the engine forwards SIGTERM to its children.

**Affected scope / file-scope manifest:**
scripts/constitution_cmd/constitution_cmd.sh (tmo); scripts/constitution_ext/ext_engine.py (_git subprocess handling)

## CON-111 — ownership wave 2 FU (round 4): extensions FAQ item 10 still says the /constitution command is planned, not landed

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

First minted on the vehicle as CON-073, re-minted at landing as CON-111. Found while documenting review round 3 N1 (vehicle/ownership-wave2, round 4). docs/faq/extensions_faq.md item 10 says the /constitution slash command is planned and not landed (UNCONFIRMED), but scripts/constitution_cmd/constitution_cmd.sh ships the extensions route and FAQ 12b (added in round 4) describes it. Acceptance: item 10 states what is shipped (the dispatcher and its generated commands) with a pointer to the dispatcher and its tests, and no longer calls it planned.

**Affected scope / file-scope manifest:**
docs/faq/extensions_faq.md

## CON-112 — ownership wave 2 FU (round 4 N8): gates run cm_label_sync_render hangs forever at a terminal under uutils timeout; structural terminal handling for every delegated route plus a class-wide pty probe

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Conductor

Review round 4 of vehicle/ownership-wave2 (N8, minor source-defect, pre-existing on main; the second occurrence of the N1 mechanism class, so §11.4.276(E)(3) was triggered and the operator decided on 2026-11-05 to land as GO-with-follow-ups and register the structural rework as this tracked follow-up, no round 5). Mechanism: scripts/constitution_cmd/constitution_cmd.sh cmd_gates runs the gate via deleg/tmo without --foreground; a gate that touches the controlling terminal (cm_label_sync_render runs util-linux script, which calls tcgetattr/tcsetattr on its tty stdin) is in a background process group and is stopped by SIGTTOU. Measured by the reviewer: uutils timeout 0.8.0 not exited at 130 s with a 40 s budget (unbounded); GNU timeout ends at the budget with rc 124. With no controlling tty the run is bounded. The author's enumeration of the N1 class searched for /dev/tty opens and could not see terminal access through an inherited tty stdin or tcsetattr (§11.4.273 class-incomplete needle). Fix direction: non-interactive routes run detached from the controlling terminal (setsid -w, stdin </dev/null) so no member of the class can exist for them and timeout's group kill covers their children; add a class-wide pty probe that runs EVERY dispatcher route (all 189 gates included) at a real pty under both timeout implementations and asserts exit within budget. Acceptance: the probe reports 0 STOPPED routes; paired mutation. Severity minor: fails safe, agents have no controlling tty. Roadmap-Item: wave 2 round 4.

**Affected scope / file-scope manifest:**
scripts/constitution_cmd/constitution_cmd.sh (cmd_gates, deleg, tmo); tests/constitution_cmd/test_constitution_cmd_pty.sh (class-wide probe)

## CON-113 — ownership wave 2 FU (round 4 N10): adopt the reviewer's surviving mutants RV4-2, RV4-3, RV4-4, RV4-7, RV4-8 as killing legs

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

Review round 4 of vehicle/ownership-wave2 (N10). Five reviewer mutants survived their suites and are non-equivalent; adopt each verbatim as a leg that kills it (§11.4.276(D)). RV4-2 (minor source-defect, attacks the N1 fix): dispatcher interactive routing made conditional on [ -t 0 ]; at a pty with stdin </dev/null typing y to enable gives rc 0 on the real code, the mutant is killed only by a driver timeout. RV4-3 (minor test-instrumentation, pre-existing consent()): consent defaults to yes on an empty answer; survives every suite including tests/run_all.sh --quick. RV4-4 (minor test-instrumentation, pre-existing): the CONSTITUTION_EXT_NO_TTY=1 refusal removed in consent(); RN3 covers that knob for _confirm_adopt only. RV4-7 (nit): ledger default mode 0o644 to 0o666, not pinned under umask 002. RV4-8 (minor): restored wiring.local.json written with mode None instead of 0600, no test checks a restored record mode under umask 022. Acceptance: each mutant fails a suite leg in the vehicle's own suites; the mutant patterns are listed in the round-4 review record. Roadmap-Item: wave 2 round 4.

**Affected scope / file-scope manifest:**
tests/constitution_cmd/test_constitution_cmd_pty.sh; tests/extensions/test_ownership_e01.sh; tests/extensions/test_wiring_ledger.sh; scripts/constitution_ext/ext_engine.py (consent)

## CON-114 — ownership wave 2 FU (round 4 N11): three documentation overclaims about the dispatcher budget and the pty test coverage

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

Review round 4 of vehicle/ownership-wave2 (N11, minor process-doc). (1) Manual and FAQ 12b say when the budget runs out the dispatcher exits 124 and nothing is changed; for add a clone may remain in a staging dir until the next mutating command and the git child may still run (CON-110). (2) The tmo comment says the budget still bounds it; false when the operator backgrounds an interactive route (engine and timeout are stopped by SIGTTIN, measured not exited at 40 s with a 5 s budget under both timeout implementations); a backgrounded prompt being stopped is normal job control, so wording only. (3) The pty test header says these four routes are the whole class; it should name the class it closes (engine /dev/tty prompts) and state that terminal access by other delegated tools is not covered (CON-112). Acceptance: the three texts corrected. Roadmap-Item: wave 2 round 4.

**Affected scope / file-scope manifest:**
docs/manuals/extensions_manual.md; docs/faq/extensions_faq.md; scripts/constitution_cmd/constitution_cmd.sh (tmo comment); tests/constitution_cmd/test_constitution_cmd_pty.sh (header)

## CON-115 — ownership wave 2 FU (round 4 N5): make the C02 hermetic property hold by construction (the lint stays advisory)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Conductor

Review round 4 of vehicle/ownership-wave2 (N5; operator decision 2026-11-05: the hermetic lint stays advisory, the by-construction fix is this tracked follow-up). tests/layout/hermetic_lint.py is an ADVISORY tripwire (§11.4.250: no new shapes per round); the binding check is the full-suite runner per-unit fingerprint, which is detective and sees a rewrite of the tracked generated sets only under run_full_suite.py (a test run directly can rewrite the real tree and only git status sees it). Primitive fix per §11.4.250 steps 2-4: the generator refuses to write into the checkout's own tracked tree unless HELIX_ACTION_OUT_ROOT is explicit, or tests run against a copy by construction. Related: CON-109 (WIT-C02 stays open). Acceptance: a test run directly cannot rewrite the tracked generated sets; paired mutation; then the lint can be retired or kept as documentation. Roadmap-Item: wave 2 round 4.

**Affected scope / file-scope manifest:**
the action generator scripts; tests/layout/test_hermetic_generator.sh; tests/layout/hermetic_lint.py; scripts/full_suite/run_full_suite.py (gen_fingerprint)

## CON-070 — CON-030 class follow-up: whitespace and line splitting of git submodule names/paths in validate_submodule.py, three gates, baseline_replay.sh and helix_deps_manifest.py

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-applied by Claude Opus 5.5 (CON-030 round 5 fixer subagent)

Class follow-up of CON-030 (parent: CON-030; review r1 F5 and review r2 G9, section 11.4.276(C)): tools outside the full-suite runner parse human-oriented git output by whitespace or by lines where a field is a submodule name or path, so a name or path with a space (and, for (7), a leading or trailing space, a CR-class character or a newline) is truncated, merged or not found. Members, each with its measured effect (2026-11-05, fixtures with submodules "submodules/my engine" and "submodules/plain"; control: the plain path is read correctly every time): (1) progressive/validate_submodule.py:60 `l.split()[1]` on `-` status lines: with a crafted --status-file an orphan path "x y" and a declared path "x" gives PASS (false PASS, measured by the r1 reviewer; control "zz" FAILs); with real git output a spaced uninitialised path gives a false FAIL. (2) scripts/gates/cm_hub_engine_no_ownorg_nesting.sh:68 `--get-regexp` plus an awk match on field 2: drops "submodules/my engine" from the inspected set (measured by the r1 reviewer), so that engine is never inspected: potential false PASS, end to end UNCONFIRMED. (3) scripts/gates/cm_gitlink_on_remote.sh:55 and :57 `ls-tree` / `ls-files -s` plus awk field 4 as the path: truncated at the first space (UNCONFIRMED end to end); :63 `--get-regexp` plus an awk equality on field 2 returns no key for "submodules/my engine" (measured). (4) scripts/fastcycle/cycle/baseline_replay.sh:1049-1052 `IFS=' ' read -r key path` over `--get-regexp` output: measured name=[submodules/my] path=[engine.path submodules/my engine] for the spaced submodule, plain one correct; effect on the replay (wrong modules/<name> reference) UNCONFIRMED. (5) scripts/gates/cm_helix_deps_ref_matches_gitlink.sh:79, :95, :105 `--get-regexp` plus an awk equality on field 2: measured key=[] for "submodules/my engine" (key found for the plain path), so line 79 reports a false DRIFT with url <none> (fail closed); end to end UNCONFIRMED. (6) low: scripts/fastcycle/consumers/migrate.sh:2432-2433 and docs/prompts/setup/latest.md:290 compare against fixed constitution paths. (7) scripts/deps_manifest/helix_deps_manifest.py:318-325 (review r2 G9): reads .gitmodules with `git config --get-regexp` text, `splitlines()`, the regex `^submodule\.(.*)\.(path|url) (.*)$` and `.strip()`, so a path with a leading or trailing space, a CR-class character or a newline is read wrong (by reading; not measured end to end, UNCONFIRMED). Fix shape proven in CON-030: NUL-separated machine formats (git config --null, git ls-files -s -z, git ls-tree -z), bytes decoded with os.fsdecode (surrogateescape), never whitespace or line splitting of a path. Each member needs its own RED on a spaced-path fixture first (section 11.4.292). Sources (tracked, section 11.4.215): docs/qa/con030_review/review_con030_r1.md (finding F5, with its measurements) and docs/qa/con030_review/review_con030_r2.md (finding G9, census of other users).

**Id note (section 11.4.214):** CON-070 is the id reserved on main for this CON-030 class item (docs/CONTINUATION.md); it is registered on main's tracker in CON-030 round 5 after the merge of main 90efceb8, which did not carry it.

## CON-116 — full-suite runner: tree_state hashes ignored files in the root only, so an ignored write inside a submodule is not detected (CON-030 review r3 H4)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-minted by Claude Opus 5.5 (CON-030 round 5 fixer subagent)

**What:** the full-suite runner's tree-changed check misses an ignored file written inside a submodule. tree_state() in scripts/full_suite/run_full_suite.py lists and hashes ignored files with `git ls-files -o -i --exclude-standard -z` in the ROOT only; the `subs` record holds each submodule's status and diff, never its ignored files. A suite that writes an ignored file inside a submodule during the run therefore ends `RESULT: PASS-FULL` (rc 0), while the same write at the root (ignored by the root) ends `TREE CHANGED ... RESULT: FAIL` (rc 1). The same gap means a change of a submodule's ignored files does not change the resume key.

**Found by:** independent review of CON-030 round 3 (finding H4, pre-existing on main efe2cc6; outside CON-030's encoding/framing class, so registered as its own item per section 11.4.276(E)(2)). Parent: CON-030.

**Reproduction (reviewer's measurement, round-3 review sandbox, not repeated in this item):** submodule `lib` ignores `out/`, the suite writes `lib/out/x`, `--include-heavy` ends PASS-FULL rc 0; control: the same write at the root (`out/x`, ignored by the root) ends FAIL rc 1. Driver and log: docs/qa/con030_review/review_con030_r3.md (H4 row) and the driver copy docs/qa/con030_review/review_r3_drv_ign_sub.sh (sha256 0588354be227047b80d0531c65c96ee3c9560dae1b169d8dbb94a3328454fcef, as recorded in that review).

**Affected scope / file-scope manifest:** scripts/full_suite/run_full_suite.py (tree_state, IGNORED_NOT_HASHED), tests/test_run_full_suite.sh, tests/test_run_full_suite_mutations.sh, docs/guides/full_suite_runner_guide.md (the Results section and Limits; round 4 already states the root-only limit).

**Acceptance:** RED first on the broken engine with the reviewer's fixture (submodule ignored write ends PASS-FULL); the fix hashes the ignored files of every checked-out submodule (recursive), framed with hrec(), with the same exclusions; GREEN: the submodule write ends FAIL rc 1 and the control stays FAIL; a paired mutation that drops the submodule ignored-file records is killed; the guide's Limits line for this is removed.

**UNKNOWN:** the run-time cost of `git ls-files -o -i` in every submodule on this repository (not measured).

**Id history (section 11.4.214):** first minted on vehicle/con030 as CON-108 (commit 6a645831); re-minted as CON-116 in CON-030 round 5 (review r4 K6), because live main 90efceb8 already owns CON-108 for another item. The vehicle commits that name CON-108 are not rewritten (section 11.4.113).

## CON-117 — full-suite runner: tree_ident splits git status and submodule status output with str.splitlines() (CON-030 round 4 class sweep, no verdict effect)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-minted by Claude Opus 5.5 (CON-030 round 5 fixer subagent)

**What:** found by the CON-030 round 4 class sweep (docs/qa/con030_review/con030_class_sweep_r4.py, shape B sites at tree_ident: the 'subs' hash of 'git submodule status --recursive' and the dirty-list hash of 'git status --porcelain=v1'). Both outputs are split with str.splitlines() (which also splits on NEL, LS, PS, CR, VT, FF) and joined with LF before hashing. With core.quotePath=false a path holding U+0085 is printed raw, so one untracked path 'a<NEL>?? b' and the two untracked paths 'a' and 'b' give the same dirty fragments and the same dirty hash. Parent: CON-030. **Why no verdict effect (reasoned from the code, not measured):** a dirty tree at the start already ends RESULT: PARTIAL-DIRTY-TREE rc 10, never PASS-FULL, and content changes during the run are caught by tree_state (TREE CHANGED, rc 1) and by the structured quick identity; so the collision changes only which identity message is shown. With the default core.quotePath=true git quotes these bytes. **Acceptance:** read both outputs NUL-terminated (git status -z, and the submodule list from git ls-files -s -z as quick_ident already does) or frame each line with hrec(); a test with core.quotePath=false and a NEL path shows two different dirty hashes; a paired mutation restoring splitlines() is killed. **UNKNOWN:** whether any consumer sets core.quotePath=false.

**Type (review r4 K11):** retyped from Task to Bug: an identity hash that two different trees can share is a defect, even when no verdict effect was found.

**Id history (section 11.4.214):** first minted on vehicle/con030 as CON-109 (commit a14824bd); re-minted as CON-117 in CON-030 round 5 (review r4 K6), because live main 90efceb8 already owns CON-109 for another item. The vehicle commits that name CON-109 are not rewritten (section 11.4.113).

## CON-118 — full-suite runner: the resume context omits --timeout and the --env-extra variables, so a changed timeout or variable value reuses an earlier verdict (CON-030 review r4 K4)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 5 fixer subagent)

**What:** a record in <out>/results.jsonl is reused when its key matches; the context part of the key (scripts/full_suite/run_full_suite.py, ctx) hashes the manifest, the known-failures table and the excluded lock only. The names and values of --env-extra variables, the caller environment the runner passes on (ENV_BASE) and --timeout are not in it. A run with a different value therefore resumes an earlier verdict.

**Found by:** independent review of CON-030 round 4 (finding K4, outside CON-030's declared class; pre-existing on main 90efceb8), registered as its own item per section 11.4.276(E)(2). Parent: CON-030.

**Reproduction (reviewer's measurement, round-4 review sandbox, not repeated in this item):** a fixture test passes only when FOO=1. Run 1 FOO=1 --env-extra FOO: PASS-FULL; run 2 FOO=0 --env-extra FOO with the same --out: resumed (PASS), PASS-FULL rc 0; control FOO=0 with a fresh --out: FAIL rc 1. A 3 s unit recorded with --timeout 60 is resumed by --timeout 1 (PASS-FULL rc 0; fresh control TIMEOUT rc 1). Drivers: drv/envextra_resume.sh and drv/timeout_resume.sh of the round-4 review (docs/qa/con030_review/review_con030_r4.md, K4 row).

**Why not fixed in CON-030 round 5:** putting variable VALUES into the context hash raises a credential question: the context hash is printed, and a truncated hash of a low-entropy secret can be guessed. The fix needs a decision: hash the values with a per-output-directory secret salt, refuse resume when --env-extra is given, or key on names plus --timeout only and document the rest. Round 5 documents the limit in docs/guides/full_suite_runner_guide.md (Results file and resume: use a new --out when these change).

**Affected scope / file-scope manifest:** scripts/full_suite/run_full_suite.py (ctx, ENV_BASE, env-extra handling), tests/test_run_full_suite.sh, tests/test_run_full_suite_mutations.sh, docs/guides/full_suite_runner_guide.md.

**Acceptance:** RED first with the reviewer's two fixtures on the unfixed engine; after the fix a changed --timeout and a changed --env-extra value each re-run the unit (GREEN), no value is printed or derivable from printed output (section 11.4.10), a paired mutation that drops each new key part is killed, and the guide states the rule.

