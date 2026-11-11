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

**Status:** Queued
**Type:** Bug
**Severity:** Medium

Review r6 follow-up 2: sub_paths splits the status line on whitespace, so a submodule path containing a space is truncated (probe E ended REFUSED-TOPOLOGY rc 9: fail-closed, cause not isolated). Latent: the real repository has none. Reproduce first (section 11.4.292), isolate the cause, then fix.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner sub_paths

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

Operator decision on record (relayed by the conductor, verbatim, 2026-11-10): "Keep running rounds until GO is reached!"; it names the codegraph/full-suite items CON-122, CON-127 and CON-031 (by the ids of that day; CON-122 and CON-127 are re-minted since as CON-152 and CON-157) and authorises review round 6 under section 11.4.276(G).

**Affected scope / file-scope manifest:**
config/full_suite_excluded.lock and config/full_suite_operators.roster

**Reproduction / context:**
Run the runner with --verify-manifest.

**Acceptance criteria:**
Operator reviewed the excluded rows and accepted; a full run no longer ends exit 11.

Round 7 (2026-11-11): the same operator decision ("Keep running rounds until GO is reached!", relayed verbatim 2026-11-10) authorises review round 7 of CON-152 and CON-157. Section 11.4.276(G) caps any extension at round 7 by recorded decision naming the item (review round 6 N6-3), so round 7 is the last round this decision can authorise; a further round needs the section 11.4.276(E)(3) escalation to an operator decision.

Round 8 (2026-11-11): operator decision on record (relayed by the conductor, verbatim, 2026-11-11, section 11.4.276(E)(3)/(G)): "Authorise round 8". It names this item (the codegraph/full-suite vehicle, CON-152/CON-157/CON-031 line) and is scoped to the review round 7 findings CR7-1..CR7-4 and N7-1..N7-4.

Id map, round 8 (§11.4.214): at the merge of main 27dcf518 into the full-suite fix vehicle head 4118f145 (2026-11-11) the vehicle's items were re-minted CON-146..CON-165 -> CON-163..CON-182 (+17, in order), because main already owns CON-146..CON-162. Ids CON-146..CON-165 in the text above this note that were written on the vehicle name the vehicle's items; read them through this map. The text above is kept unchanged.

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

fixu round 2 (2026-11-06), review F047-1 and F047-2: the two known-failure rows use the new signature form reason:rc_3+tracked (the reason AND every [tracked <id>] token in the unit log names CON-047, at least one), so an rc 3 from a KNOWN-FAIL case pinned to another item is not attributed to CON-047; and bash scripts/run_full_suite.sh --check-known-open exits 1 naming a row whose tracked item has left Issues (2 when the DB is absent or empty). Runner self-test 11b/11c (RED 244/1 before the change, GREEN 253/0) and runner mutants F47a-F47c. Evidence docs/qa/fixu2_round2/f047/.

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

**Status:** In progress
**Type:** Task
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 landing)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con031_excluded_review/review_con031_excluded_r1.md` — red-command `full-suite runner unit for scripts/lumen/tests/test_gen_lumenignore.sh (sandbox HOME, no LUMEN_BIN)` — green-command `same command after the runner half lands` — env `host anton, full-suite runner sandbox HOME, lumen installed only under the real HOME` — signature `SKIP: lumen binary not found, then exit 2 (judge records FAIL rc_2)` — updated 2026-11-06T10:56:14Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `the runner gives a sandbox HOME and does not pass LUMEN_BIN; the test labelled the absence SKIP but exited 2` — evidence `docs/qa/con031_excluded_review/review_con031_excluded_r1.md` — updated 2026-11-06T10:56:14Z — by `AI (Claude Opus 5.5, fixu2)`

Review finding X1 (docs/qa/con031_excluded_review/review_con031_excluded_r1.md): scripts/lumen/tests/test_gen_lumenignore.sh FAILs in every full-suite run. Its fallback looks for the lumen binary under $HOME/.claude-shared/..., the runner gives each unit a sandbox HOME, and LUMEN_BIN is not in the runner's environment base. It then prints 'SKIP: lumen binary not found' but exits 2, which judge() records as FAIL rc_2. Measured by the reviewer: sandbox HOME without LUMEN_BIN rc 2 in 0 s; with LUMEN_BIN set rc 0, 4 checks pass. Fix: the test prints what it does (a FAIL naming the missing prerequisite; operator decision O3, missing tool FAIL or SKIP, is still PENDING, so FAIL is the interim reading and changes if O3 decides SKIP), and the runner passes LUMEN_BIN or resolves it in a preflight. X4: the same test deletes with a bare rm -rf "$W"; use ${W:?} or safe_rm_rf (§11.4.287(C)(1)). Acceptance: the unit passes under the full-suite runner on a host with lumen installed, and its output matches its exit code.

fixu round 2 (2026-11-06): the test half landed in 3e423d43 (FAIL naming the missing lumen binary, guarded cleanup); review F089-1 fixed here: an unchecked mktemp no longer lets the test write to /repo, /scope.json and /a.ignore (it now exits 2 with a clear message; RED rc 1 mkdir Permission denied, GREEN rc 2, evidence docs/qa/fixu2_round2/f089/). Still open (review F089-3): the runner half. ENV_BASE does not pass LUMEN_BIN and there is no preflight, so the unit still FAILs rc_2 in the full suite on a host where lumen is installed under the real HOME. The item stays Queued until that lands.

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

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-05T19:43:29Z — by `Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)`
**Investigation:** in-progress — updated 2026-11-06T10:56:14Z — by `AI (Claude Opus 5.5, fixu2)`

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: inventory class C of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md; reviewer runs docs/qa/manifest_triage_review/r1_unconfirmed_fastcycle_runs.tsv). Custody-sweep family: r11, r13 and r15 REFUSE a plain stash that should be ALLOWED (backup patch sha256 does not match the re-derived live content; suspected git config or version effect in a sandbox HOME, UNCONFIRMED), r6 hits a Python traceback in guard-viability, r9 gets rc 2 from custody_sweep.py --repo-root on a long sandbox path. Also: test_escape_classify_malformed_red.sh (non_mapping_entry exits 2, expected a named refusal exit 1), test_fc_entry_r10_regression.sh (B1 inventory with --out gets rc 2), test_gate_shard_r3_regression.sh (Python traceback), test_io_trace_build_map_r6_regression.sh (mutation precondition not reached on this host, proves nothing either way), test_precheck_slicer_red.sh (sh -n under dash did not reject broken_syntax_gate.sh), test_host_guard_red.sh (got reason=unreadable_ulimit where thread_headroom was expected under sh; dash ulimit has no -u is a suspicion, UNCONFIRMED). Acceptance: each reproduced live first (section 11.4.292), root cause proven, fixed or honestly reclassified, with a deterministic test.

fixu round 2 (2026-11-06), test_precheck_slicer_red.sh only (review F099-1): case C2a accepted the dash parse error OR the shellcheck finding, so a mutant that dropped the case-insensitive match survived on the shellcheck leg; it now requires both legs (parse error, case-insensitive, AND SC2086) and prints each leg. GREEN 16/0; the no-lower() mutant is now killed (15/1). The other ten tests of this item are untouched.

fixu round 3 (2026-11-06), test_precheck_slicer_red.sh only (review F099-2, F099-3): the shellcheck leg of C2a matched SC2086 in the FAIL entries, which also carry the pack's severity_floor config echo (a carrier); it now reads evidence.findings[].rule == SC2086 in the planted file and requires files_linted > 0. With shellcheck off PATH the pack reports an honest skip and the leg is SKIP (control needle: command -v), the parse leg still required. New test_precheck_slicer_c2a_mutants.sh adopts the reviewer's mutants (blind leg, defect removed) plus a config-echo stub and the no-shellcheck case: old test 1/4 (RED), new test 5/0. Evidence docs/qa/fixu3_round3/f099/. Awaits re-review of this slice.

fixu round 3 re-review (2026-11-06, docs/qa/fixu_review/review_fixu_r3.md, landed 2026-11-10): F099-2 and F099-3 closed, verdict GO-with-follow-ups, every open finding minor-class (section 11.4.276(G.2)). Follow-ups: CON-140 (F099-4, the parse leg is still a carrier match), CON-141 (F099-5, F099-6, N099-1, N099-3, harness strength), CON-142 (F099-8, N099-2, N099-4, harness SIGTERM leak), CON-143 (F099-7, the C2a FAIL message). Verdict change (F099-7): under the full-suite runner default isolation (no XDG_RUNTIME_DIR, no bus) test_precheck_slicer_red.sh and test_precheck_slicer_c2a_mutants.sh FAIL since ec047648, because the shellcheck leg is now reported BLIND instead of passed by the config echo; the cause is CON-125, and with the bus variables passed through (--env-extra XDG_RUNTIME_DIR --env-extra DBUS_SESSION_BUS_ADDRESS) both PASS. Round count (section 11.4.276(E)(1), N099-6): this slice has used 3 review rounds; the fixer recorded no round-3 convergence assessment. The reviewer's class inventory (review section 6) found the carrier class open in exactly one member, line 433 (CON-140); the next fix of this slice is round 4 of at most 5 and must close that class, not only that line. The other ten tests of this item are untouched. Stays open.

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

Recurrence link (§11.4.214, review round 8 R8-2, 2026-11-11): the review of round 8 of the full-suite fix vehicle (docs/qa/review_cgs8_round8_2026_11_11.md) found that mutant M1G of this item (for _fcr_p in "$@" -> $*, in fc_require_consumer of scripts/fastcycle/tests/lib/consumer_required.sh) still survives; the reviewer's M6 is the same edit, and a path argument that contains a space gets a false SKIP (head RAN, M6 SKIP, bash and dash). This item is open, so the recurrence is linked here and no new item is minted. Acceptance addition: adopt M6 as a paired mutant when this item is fixed. No fix is claimed (§11.4.290).

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

## CON-116 — review_record_genuine.sh used a bash array while sourced by /bin/sh tests (dash syntax error)

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u1/U1_RED_test_review_record_finding_layer_red.out` — red-command `sh scripts/fastcycle/tests/test_review_record_finding_layer_red.sh` — green-command `sh scripts/fastcycle/tests/test_review_record_finding_layer_red.sh` — env `host anton, sh = dash, scratch clone of main bdc3ac43 plus the fixu vehicle` — signature `Syntax error: "(" unexpected` — updated 2026-11-06T10:48:38Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `bash array syntax in a library sourced by /bin/sh (dash) tests; introduced by ef82977b` — evidence `docs/qa/fixu_default_tier/u1/U1_RED_test_review_record_finding_layer_red.out` — updated 2026-11-06T08:50:13Z — by `AI`

scripts/fastcycle/tests/lib/review_record_genuine.sh is sourced by three /bin/sh tests (backfill_evidence_r2, evidence_hash_r5, finding_layer_red). Since ef82977b its rr_record used local pre=(...) and "${pre[@]}", which dash rejects with Syntax error: "(" unexpected, so all three exit 2 before running a case. Fix: rebuild the argument list with POSIX set --, keeping the original order so the caller's extra options still come last (argparse last-wins). The bash users (gate_authority r1/r2/r3 and the mutation driver) stay GREEN. Known gap, not caused by this change: a mutant that drops --precheck survives all six tests.

Id history (§11.4.214): first minted in the fixu vehicle as CON-108 (commit 64c338e3), re-minted as CON-116 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-117 — multitrack ruler suite discovered zero tests on a standalone canon, and leaked RED_MODE=0 into redpin's children

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u3_ruler/U3_ruler_RED.out` — red-command `bash scripts/multitrack/test_multitrack_ruler_suite.sh (canon checkout not named constitution, env -i)` — green-command `same command` — env `host anton, env -i HOME=<tmp> PATH=/usr/bin:/bin, canon checkout not named constitution` — signature `TOTAL=0 then exit 2; redpin with RED_MODE=0: FAIL 6` — updated 2026-11-06T10:48:38Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `test directory derived from a vendored-layout path; RED_MODE inherited by redpin children` — evidence `docs/qa/fixu_default_tier/u3_ruler/U3_ruler_RED.out` — updated 2026-11-06T08:51:15Z — by `AI`

scripts/multitrack/test_multitrack_ruler_suite.sh resolved its test directory as $ROOT/constitution/scripts/multitrack, which exists only when the canon is vendored, so on the constitution repository itself it discovered 0 tests and exited 2; a sibling directory named constitution could also hijack discovery. ROOT is now the parent only when the canon is a submodule named constitution of a real git toplevel; discovery reads the canon's own directory. A member's exit 77 is counted as SKIP and the summary prints SKIP=. Second defect, found when the suite ran its members: the suite exports RED_MODE=0, and test_multitrack_redpin_mutations.sh passed it on to its children, which skipped the RED leg (6 FAIL). _run now clears RED_MODE unless RUN_RED_MODE sets it.

fixu round 2 (2026-11-06), review NO-GO F109-1 fixed: the repository root was taken from a logical pwd, so a consumer reached through a symlinked directory was not recognised as vendored and its device-roster member was dropped (reviewer fixture C5: total 2, dev 0). The parent is now resolved with pwd -P. F109-2: an all-SKIP aggregate restated reason=topology_unsupported regardless of the members; it now carries the members' shared reason, and when the reasons differ it names them all without a single reason= token. F109-3: new meta-test scripts/multitrack/test_ruler_suite_discovery.sh (cases C1-C9 plus C2/C2m; its name avoids the test_multitrack_* glob so the aggregator never runs it). RED at the fixu head 9/3, GREEN 12/0; mutants (pwd reverted, hard-coded reason, mixed branch disabled) each killed. Evidence docs/qa/fixu2_round2/f109/.

Id history (§11.4.214): first minted in the fixu vehicle as CON-109 (commit c1881ae1), re-minted as CON-117 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-118 — persistent-launch test read a present systemd user bus as absent under a clean environment and exited 2

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u2_persistent_launch/U2_persistent_launch_RED.out` — red-command `env -i HOME=<tmp> PATH=/usr/bin:/bin bash scripts/multitrack/test_multitrack_persistent_launch_survives_session_teardown.sh` — green-command `same command` — env `host anton, env -i HOME=<tmp> PATH=/usr/bin:/bin, live user manager at /run/user/1000/bus` — signature `SKIP printed, exit 2 under env -i` — updated 2026-11-06T10:48:38Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `capability probe ran without XDG_RUNTIME_DIR, which the clean environment does not carry` — evidence `docs/qa/fixu_default_tier/u2_persistent_launch/U2_persistent_launch_RED.out` — updated 2026-11-06T08:51:30Z — by `AI`

scripts/multitrack/test_multitrack_persistent_launch_survives_session_teardown.sh probed systemctl --user without XDG_RUNTIME_DIR. The full-suite runner gives each unit a clean environment with no XDG_RUNTIME_DIR, so the probe failed although /run/user/<uid>/bus was live, and the test printed SKIP but exited 2 (a FAIL to the runner). Control needle: env -i systemctl --user rc 1, the same with XDG_RUNTIME_DIR=/run/user/1000 rc 0. The test now derives XDG_RUNTIME_DIR from a bus socket we own; a present socket that does not answer is a FAIL; a genuinely absent bus or missing systemd-run/systemctl exits 77 reason=topology_unsupported; an absent unit under test is a FAIL (it was SKIP tool_absent with exit 2).

fixu round 2 (2026-11-06), review F110-1/F110-2/F110-3: the inline derivation is replaced by the shared helper scripts/lib/user_bus_env.sh (CON-125). F110-1: an inherited XDG_RUNTIME_DIR pointing at a directory without a bus no longer hides a live standard bus (RED SKIP 77 with the bus live, GREEN rc 0 PASS=3). F110-2: a bus socket not owned by the caller is a SKIP naming it, never used. A present owned bus whose systemctl --user does not answer stays a FAIL naming the bus path. Evidence docs/qa/fixu2_round2/f110/.

Id history (§11.4.214): first minted in the fixu vehicle as CON-110 (commit 258b2bb3), re-minted as CON-118 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-119 — fc_supervisor_unit spy socket bound a full path and failed with AF_UNIX path too long under a deep TMPDIR

**Status:** In progress
**Type:** Bug
**Severity:** low
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u4_supervisor_socket/U4_RED.out` — red-command `TMPDIR=<195-char dir> bash scripts/fastcycle/tests/test_fc_supervisor_unit.sh` — green-command `same command` — env `host anton, TMPDIR = a 195-character scratch directory` — signature `AF_UNIX path too long` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `absolute socket path longer than sun_path (108 bytes) under a deep TMPDIR` — evidence `docs/qa/fixu_default_tier/u4_supervisor_socket/U4_RED.out` — updated 2026-11-06T08:51:45Z — by `AI`

scripts/fastcycle/tests/test_fc_supervisor_unit.sh bound its spy AF_UNIX socket by absolute path. AF_UNIX paths are limited to 108 bytes; with the scratch TMPDIR (195 characters) the bind failed with AF_UNIX path too long. The lease bind in the same file already used chdir plus a relative name; the spy bind now does the same. Every other .bind( site in the file was checked and none binds a full path.

Id history (§11.4.214): first minted in the fixu vehicle as CON-111 (commit ee2c4261), re-minted as CON-119 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-120 — select_sample.py lost the retroactive_state tri-state (unparseable history) when f77a7851 replaced the file from a held snapshot

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u6_select_sample/U6_unparseable_RED.out` — red-command `bash scripts/fastcycle/tests/test_select_sample_unparseable (see U6_unparseable_RED.out)` — green-command `same command` — env `host anton, clean clone, python3 -I` — signature `AttributeError: module has no attribute retroactive_state` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `f77a7851 restored the file from snapshot 4b13814 that predates ee581e37` — evidence `docs/qa/fixu_default_tier/u6_select_sample/U6_unparseable_RED.out` — updated 2026-11-06T08:51:55Z — by `AI`

ee581e37 (2026-10-31) added retroactive_state() with three results (retroactive, unparseable, normal), UNPARSEABLE_REASON and the matching branch in classify_exclusions. f77a7851 (2026-11-03) took scripts/fastcycle/cycle/select_sample.py from the held snapshot 4b13814, which is not an ancestor of main and predates ee581e37, so those lines were dropped while their tests stayed: the unparseable-history test fails with AttributeError retroactive_state. Decided by git history (section 11.4.124): the product regressed, the test is current. The function, the reason and the branch are restored; the V4-4 and V4-6 changes of f77a7851 are kept. test_select_sample_r5_regression.sh mutant R3 anchor updated to the current except line (mutation anchor census drift 0 before and after).

fixu round 2 (2026-11-06): the anchor-census sentence above is withdrawn as evidence for this file (review F112-1): scripts/fastcycle/tests/check_mutation_anchors.py covers only test_fastcycle_r6_mutations.sh and test_baseline_replay_worktree_cleanup.sh (its docstring now says so); the R3 anchor is proven by the r5 test's own mutation leg, which refuses a drifted anchor. The r5 cases S3, S5 and S6 that stay NOT ok in a clean clone are owned by CON-131 (review F112-2).

Id history (§11.4.214): first minted in the fixu vehicle as CON-112 (commit 1113e352), re-minted as CON-120 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-121 — env-read census reported cm_github_issues_source_anchor_wired.sh:334 eval as UNCOVERED since 090e8062

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u11_env_census/U11_RED.out` — red-command `bash scripts/gates/cm_gate_env_reads_allowlisted.sh` — green-command `same command` — env `host anton, clean clone at 090e8062 and later, python3 -I` — signature `UNCOVERED scripts/gates/cm_github_issues_source_anchor_wired.sh:334 <eval> (indirect)` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `new gate from 090e8062 shipped without its allowlist row` — evidence `docs/qa/fixu_default_tier/u11_env_census/U11_RED.out` — updated 2026-11-06T08:56:46Z — by `AI`

Commit 090e8062 (section 11.4.296) added scripts/gates/cm_github_issues_source_anchor_wired.sh, which at line 334 evals a fixed case statement over its own local DG, the same shape as the four sibling anchor-wired gates (repro_first, scope_and_image_noworse, state_fields, geo_substitute) that are registered in config/gate_env_allowlist.tsv as indirect-mechanism. The new gate got no row, so CM-GATE-ENV-READS-ALLOWLISTED reported uncovered=1 and tests/gates/test_gate_env_census_closure.sh failed its control. Read of the eval: it reads only DG and BLK, both set by the gate itself; no environment variable is read through it. A row with the same class and wording as the siblings is added.

fixu round 2 (2026-11-06), review F113-1 (class recurrence: <eval> rows were file-scoped, so a later env-reading eval in the same file was hidden): the census now emits one pseudo-variable per eval statement, <eval>#<first 12 hex of sha256 of the stripped source line>, and the 8 eval rows of config/gate_env_allowlist.tsv are pinned to their own statements (5 *_anchor_wired.sh gates bea59a1ee0f8, shell_mutation_engine 44edb45288f3, constitution_layout 33c450208749, safe_rm fa157096b76d). RED: a second eval appended to the github gate gave VERDICT PASS; GREEN: real tree PASS (allowlisted=117), the second eval is UNCOVERED <eval>#b1e750228c4a (rc 1). The meta-test has two new discriminators (pinned row covers its own eval rc 0; second eval uncovered rc 1, its hash computed independently with sha256sum) and mutant M13 (hash the path instead of the statement) is killed. Evidence docs/qa/fixu2_round2/f113/. Honest limit: a byte change of a pinned eval line makes its row stale (it then reports UNCOVERED and the row must be re-pinned after review), which is the intended direction.

Id history (§11.4.214): first minted in the fixu vehicle as CON-113 (commit a7fc8328), re-minted as CON-121 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-122 — skill-activation liveness probe read a live session as dead under pipefail, so a skill another session held could be stripped

**Status:** In progress
**Type:** Bug
**Severity:** high
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u8_skill_activation/U8b_liveness_RED_envi.out` — red-command `env -i HOME=<tmp> PATH=/usr/bin:/bin bash scripts/skill_activation/test_skill_activation.sh` — green-command `same command` — env `host anton, env -i HOME=<tmp> PATH=/usr/bin:/bin, 114 KB peer environment` — signature `LIVENESS ... (expected 3, got 0); normal env: CONCURRENCY: skill stripped while another session held it` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `tr | grep -q under set -o pipefail: SIGPIPE on tr turns a match into a non-zero pipeline status` — evidence `docs/qa/fixu_default_tier/u8_skill_activation/U8b_liveness_RED_envi.out` — updated 2026-11-06T08:58:01Z — by `AI`

scripts/skill_activation/skill_activation_lib.sh runs under set -uo pipefail. sa_session_alive matched CLAUDE_CONFIG_DIR with tr '\0' '\n' < /proc/<pid>/environ | grep -qx ...; grep -q exits on the first match, tr then dies of SIGPIPE (141) and pipefail makes the match a failure. A live session therefore read as dead whenever the environment took more than one write: 72 of 200 probes on a 14 KB environment, every probe at 114 KB. A claim read as dead is reaped, and deactivate/prune then unlinks a skill that another live session holds. The reader now uses grep -qzxF on the environ file directly (no pipe; -F so the dir is a literal). Second, test-side: test_skill_activation.sh depended on a live claude5 alias on the host and inherited the caller's CLAUDE_CONFIG_DIR; it now uses per-session fixture config dirs and a real live peer process, and has a new LIVENESS case with a 114 KB environment.

fixu round 2 (2026-11-06), review F114-1: the liveness test now has killing cases for the two grep flags of the fix: a live peer whose CLAUDE_CONFIG_DIR differs only by a regex metacharacter (cfg-dotXtest vs cfg-dot.test, kills a mutant without -F) and a live peer whose dir has the probed dir as a prefix (cfg-prefix-live vs cfg-prefix, kills a mutant without -x); control: both exact dirs read alive. Evidence docs/qa/fixu2_round2/f114/.

Id history (§11.4.214): first minted in the fixu vehicle as CON-114 (commit 3f1c0934), re-minted as CON-122 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-123 — label-sync opencode adapter is not loaded by opencode 2.x (plugin path must be a directory; serve needs auth)

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u9_opencode2/U9_opencode_only_normal.out` — red-command `bash scripts/label-sync/adapters/tests/test_real_agents.sh --only opencode` — green-command `same command` — env `host anton, opencode v2.2.0, normal environment` — signature `configured plugin path must be a directory` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `upstream opencode 2.x requires a directory plugin and authenticated serve; the adapter and its test target 1.x` — evidence `docs/qa/fixu_default_tier/u9_opencode2/U9_opencode_only_normal.out` — updated 2026-11-06T09:01:03Z — by `AI`

scripts/label-sync/adapters/tests/test_real_agents.sh --only opencode fails 4 of 4 in the normal environment too, so it is not a fresh-HOME artefact. The host now has opencode v2.2.0 (installed 2026-10-27, after the adapter landed in 7c77547c on 2026-10-12). Measured: install_adapters.sh writes a file:// URL to label-sync.mjs under the plugin key; opencode 2.2 logs WARN configured plugin path must be a directory and does not load it (no plugin debug log is written); debug config now prints an array of sources with the key plugins, so the test's .plugin[0] jq expression no longer matches; opencode serve prints a per-run server password and POST /session returns an empty body without it. So the adapter is broken for opencode 2.x users and the test is stale. Fix is not small: package the plugin as a directory in the layout opencode 2.x accepts, verify the 2.x event names, and authenticate the serve leg; UNCONFIRMED whether the 1.x session.created/deleted events are unchanged in 2.x.

Id history (§11.4.214): first minted in the fixu vehicle as CON-115 (commit 7b51c4bf), re-minted as CON-123 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-124 — test_run_all.sh signal cases fail when the test has no controlling terminal (full-suite units run in a new session)

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u7_run_all_signals/U7_run_all_setsid_RED.out` — red-command `setsid -w env -i HOME=<tmp> PATH=/usr/bin:/bin bash scripts/fastcycle/tests/test_run_all.sh </dev/null` — green-command `same command` — env `host anton, setsid -w env -i HOME=<tmp> PATH=/usr/bin:/bin, no controlling terminal` — signature `set: can't access tty; job control turned off; NOT ok r7f2 ...` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-unconfirmed — root-cause `UNCONFIRMED: no controlling terminal disables set -m; the HUP part and the setsid signature are not explained` — evidence `docs/qa/fixu_default_tier/u7_run_all_signals/U7_run_all_setsid_RED.out` — updated 2026-11-06T09:01:17Z — by `AI`

The full-suite runner starts each unit with start_new_session=True, so it has no controlling terminal. test_run_all.sh relies on set -m (job control) so that a backgrounded runner does not start with SIGINT ignored and leads its own process group; without a terminal dash prints set: can't access tty; job control turned off and the premise does not hold. Full-suite log 000204: pid-HUP and pid-INT NOT ok (runner still alive after 15 s), group-INT and group-TERM SKIP (no own process group). Reproduction: rc 0 with a terminal-bearing session under env -i, under the normal environment, and with INT or INT+HUP inherited as ignored; under setsid -w env -i (no terminal) rc 1, but the failing case is graceful-TERM (the test never got a TERM before the KILL), not pid-HUP/INT. Root cause proven only for the missing job control; why HUP was ignored in the full-suite run, and why the failing case differs under setsid, is UNCONFIRMED. A fix needs a launch that resets INT/HUP to default without job control (for example env --default-signal or a small exec helper) and a decision on the group cases.

Id history (§11.4.214): first minted in the fixu vehicle as CON-116 (commit 7b51c4bf), re-minted as CON-124 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-125 — systemd user-bus callers do not find a live bus when XDG_RUNTIME_DIR is unset (clean environments, full-suite units)

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u2_user_bus_class/fullsuite_test_precheck_shellcheck_red.log` — red-command `full-suite default run (clean env) of scripts/fastcycle/tests/test_precheck_shellcheck_red.sh` — green-command `same command after the helper lands` — env `host anton, full-suite runner clean environment (no XDG_RUNTIME_DIR), live user manager` — signature `Failed to connect to user scope bus via local transport` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `callers rely on an inherited XDG_RUNTIME_DIR that clean environments do not carry` — evidence `docs/qa/fixu_default_tier/u2_user_bus_class/fullsuite_test_precheck_shellcheck_red.log` — updated 2026-11-06T09:04:26Z — by `AI`

The full-suite runner gives each unit a clean environment without XDG_RUNTIME_DIR. systemctl --user and systemd-run --user then fail with Failed to connect to user scope bus via local transport although /run/user/<uid>/bus is live (control needle measured for CON-118: env -i rc 1, with XDG_RUNTIME_DIR=/run/user/1000 rc 0). test_precheck_shellcheck_red.sh fails its N2 control needle (the hard memory cap mechanism is not usable) and test_io_trace_build_map_r6_regression.sh fails on systemd-run exit 1. Inventory (inventory.tsv, by line pattern, a lead not a finding): 13 files call the user bus, only the CON-118 test derives XDG_RUNTIME_DIR; the non-deriving set includes product code (scripts/fastcycle/review/precheck_pack.sh, precheck_pack_run.py, fc_common.py, fc_supervisor.py, multitrack_persistent_launch.sh, credscan/install_timer.sh), so under cron or any clean environment the memory-capped scope is unavailable there too. Proposed fix: one shared helper that exports XDG_RUNTIME_DIR from a bus socket the caller owns, used by every caller; a genuinely absent bus stays a reasoned refusal or SKIP. Not done here: it touches product code across several subsystems.

fixu round 2 (2026-11-06): the shared helper landed: scripts/lib/user_bus_env.sh (ub_user_bus_env, dash/busybox/bash; returns 0 inherited or derived and exports XDG_RUNTIME_DIR, 1 absent, 2 a bus socket not owned by the caller; the same -S and -O rule in every branch), with scripts/lib/test_user_bus_env.sh (U1-U6, U5 foreign via a symlink to a root-owned socket, SKIP topology_unsupported when the host has none). The CON-118 test now calls it (review F110-1: an inherited XDG_RUNTIME_DIR pointing at a dir without a bus no longer hides a live standard bus; F110-2: a foreign bus is a SKIP, never used; F110-3: the inline duplicate is gone). Remaining callers, NOT converted (product code across subsystems, still this item): scripts/fastcycle/lib/fc_common.py, scripts/fastcycle/lib/fc_supervisor.py, scripts/fastcycle/review/precheck_pack_run.py, scripts/fastcycle/review/precheck_pack.sh, scripts/multitrack/multitrack_persistent_launch.sh, scripts/credscan/install_timer.sh, probe_bridge_layers.sh, the r3/r6 io_trace tests and test_precheck_shellcheck_red.sh. The Python callers need a Python twin of the rule (UNCONFIRMED whether they can source a shell helper). Stays open.

Id history (§11.4.214): first minted in the fixu vehicle as CON-117 (commit 7b51c4bf), re-minted as CON-125 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

fixu landing (2026-11-10, review F099-7 of docs/qa/fixu_review/review_fixu_r3.md): add to the affected list scripts/fastcycle/tests/test_precheck_slicer_red.sh (its C2a shellcheck leg is BLIND without the bus and the test FAILs under the full-suite runner default isolation since ec047648) and scripts/fastcycle/tests/test_precheck_slicer_c2a_mutants.sh (FAILs the same way).

## CON-126 — test_precheck_pack_build_red.sh fails when run alone (not only in a batch), and it chmods real repository files during its run

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u5_pack_build/U5_pack_build_serial_withSC.out` — red-command `setsid -w env -i HOME=<tmp> PATH=$HOME/.local/bin:/usr/bin:/bin sh scripts/fastcycle/tests/test_precheck_pack_build_red.sh` — green-command `same command` — env `host anton, setsid -w env -i HOME=<tmp> PATH=$HOME/.local/bin:/usr/bin:/bin, serial run` — signature `FAIL: B1: expected rc=0/all_pass=true, got rc=1 all_pass=False` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-unconfirmed — root-cause `UNCONFIRMED: not investigated past the failing case list` — evidence `docs/qa/fixu_default_tier/u5_pack_build/U5_pack_build_serial_withSC.out` — updated 2026-11-06T09:04:26Z — by `AI`

Run alone and serially under setsid env -i: 14 FAIL without shellcheck on PATH, 16 FAIL with ~/.local/bin/shellcheck on PATH; clean fixtures (B1, B3) report all_pass=false, D2/D7/D8 report NOT-READY (provenance binding, shellcheck mode). So CON-098's classification of this test as passes-alone-fails-in-batch does not hold here. Separately, case C2 does chmod 000 on the real scripts/fastcycle/review/slicer.py and precheck_pack.sh for a window; any other test reading those files at the same time fails with Permission denied (observed: a parallel run in the same tree), which is a plausible contributor to the batch-only failures of the precheck family, UNCONFIRMED. Modes were restored at the end of the run (git status clean). Root cause of the alone failures not established.

Id history (§11.4.214): first minted in the fixu vehicle as CON-118 (commit 7b51c4bf), re-minted as CON-126 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-127 — test_round8_git_env CM-2/CM-3 fail: fixture copy lacks .gitignore, hook leaves scripts/deps_manifest/__pycache__ untracked

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** AI
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu_default_tier/u10_round8` — red-command `env -i HOME=$(mktemp -d) PATH=/usr/bin:/bin bash tests/layout/test_round8_git_env.sh` — green-command `env -i HOME=$(mktemp -d) PATH=/usr/bin:/bin bash tests/layout/test_round8_git_env.sh` — env `host anton, env -i HOME=$(mktemp -d) PATH=/usr/bin:/bin` — signature `FAIL: CM-2 porcelain ?? scripts/deps_manifest/__pycache__/` — updated 2026-11-06T10:48:39Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `fixture missing .gitignore; pycache from hook gates shows as untracked` — evidence `docs/qa/fixu_default_tier/u10_round8` — updated 2026-11-06T09:08:52Z — by `AI`

The round8 fixture copies scripts/Constitution.md/CLAUDE.md/AGENTS.md into a fake submodule but not .gitignore. The post-update hook's STEP 5b Python gates write scripts/deps_manifest/__pycache__/, porcelain is non-empty, CM-2 and CM-3 fail (and the real update_constitution.sh --check refuses on local changes). Fix: copy .gitignore into the fixture. test_round7_ambient.sh:138 has the same list but no porcelain check (not changed).

Review N119-1 (class note): tests/layout/test_round7_ambient.sh:138 copies the same file list without .gitignore; it has no porcelain check, so the defect is latent there (not changed).

Id history (§11.4.214): first minted in the fixu vehicle as CON-119 (commit 270e4867), re-minted as CON-127 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-128 — multitrack supervisor watch left its sleep child running after SIGTERM, and its wiring test checked orphans by the parent pid only

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI (Claude Opus 5.5, fixu2)
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu2_round2/fpre1/fpre1_product_red.out` — red-command `start multitrack_supervisor.sh watch --interval <token> in the background, SIGTERM it, list sleep <token> processes` — green-command `same command; and bash scripts/multitrack/test_multitrack_supervisor_wiring.sh (step f3)` — env `host anton, bash, scratch clone` — signature `orphan sleep <token> with a new ppid after the daemon died` — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `foreground sleep in cmd_watch is not signalled when the shell gets SIGTERM; the test checked orphans by the dead parent's pid` — evidence `docs/qa/fixu2_round2/fpre1/fpre1_test_red.out` — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`

Pre-existing finding F-PRE-1 of the fixu review (S/scratchpad/review_fixu.md). Product: scripts/multitrack/multitrack_supervisor.sh cmd_watch slept with a foreground sleep; SIGTERM to the daemon killed the shell but the sleep child kept running with a new parent (measured: an orphan sleep with ppid 2441 after the daemon died, evidence docs/qa/fixu2_round2/fpre1/fpre1_product_red.out). Fix: the loop sleeps in the background and waits on it, and TERM/INT/HUP traps kill that child (pid > 1, section 11.4.263) before exiting 143/130/129; --once clears the traps. Test: scripts/multitrack/test_multitrack_supervisor_wiring.sh asserted no orphan from the dead parent's pid (always true once the parent is gone) with a token shared by other runs; it now uses a per-run token, counts token processes host-wide with a positive control before the signal, kills its own process tree children first, and a new step f3 requires the daemon to stop its own children on SIGTERM. Host note: about 100 orphan sleep 99872N processes from earlier runs of other sessions exist on the host; not ours, left alone. Class sweep: scripts/label-sync/adapters/tests/test_adapters.sh:237 has the same vacuous parent-pid orphan check (registered as CON-130).

Id history (§11.4.214): first minted in the fixu vehicle as CON-120 (commit 351fe277), re-minted as CON-128 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-129 — test_reopen_rate_red.sh needle #2 needed the sqlite3 CLI and the vendored DB path, so it failed (rc 1) in a clean environment while calling it a SKIP

**Status:** In progress
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu2)
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fixu2_round2/fpre2/fpre2_red.out` — red-command `env -i HOME=<tmp> PATH=/usr/bin:/bin bash scripts/fastcycle/tests/test_reopen_rate_red.sh` — green-command `same command` — env `host anton, env -i, no sqlite3 CLI on PATH, standalone canon` — signature `NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable; rc 1` — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-found-with-evidence — root-cause `needle #2 shelled out to the sqlite3 CLI and looked only at the vendored DB path` — evidence `docs/qa/fixu2_round2/fpre2/fpre2_red.out` — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`

Pre-existing finding F-PRE-2 of the fixu review. Under env -i PATH=/usr/bin:/bin (no sqlite3 CLI) and on a standalone canon (no constitution/docs/workable_items.db under ROOT) needle #2 printed SKIPPED but returned FAIL (rc 1). The conductor's brief proposed exit 77 with a closed reason code, but no section 11.4.69 code fits a missing tool and operator decision O3 (missing tool: FAIL or SKIP) is pending, so the dependency was removed instead: the needle reads the DB with python3's sqlite3 module (file: URI, mode=ro, immutable=1, so no -wal/-shm side files), with a positive control (the first atm_id must be found; CLEAN/HIT/BLIND), and falls back to the standalone path docs/workable_items.db. RED rc 1, GREEN rc 0 (18 ok); mutants collide and blind both killed (rc 1). Same class still open elsewhere: test_cycle_report_red.sh uses the sqlite3 CLI; the r5 select_sample live-DB cases (CON-131).

Id history (§11.4.214): first minted in the fixu vehicle as CON-121 (commit 351fe277), re-minted as CON-129 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-130 — test_adapters.sh 'no orphan sleep left' check is vacuous: pgrep -P of a dead parent, global 'sleep 30' token

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu2)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** root-cause-unconfirmed — root-cause `UNCONFIRMED: read from the code only (pgrep -P of an exited parent)` — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`

Found by the F-PRE-1 class sweep (CON-128). scripts/label-sync/adapters/tests/test_adapters.sh:237 asserts ok 'run: no orphan sleep left' with ! pgrep -f 'sleep 30' -P $wp. Once the wrapper $wp has exited, an orphaned sleep is re-parented, so pgrep -P $wp can never find it and the check always passes; the token 'sleep 30' is also shared with any other process on the host. Not fixed in fixu2 (outside its items). Fix shape: the CON-128 pattern (unique per-run token, host-wide count with a positive control before the kill, children-first cleanup). Not reproduced live as a leak; the vacuity is a reading of the code (UNCONFIRMED whether the adapter actually leaks).

Id history (§11.4.214): first minted in the fixu vehicle as CON-122 (commit 351fe277), re-minted as CON-130 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-131 — test_select_sample_r5_regression.sh S3, S5 and S6 report NOT ok in a clean clone (live tracker DB / live snapshot unavailable)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu2)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`
**Investigation:** not-started — updated 2026-11-06T10:49:32Z — by `AI (Claude Opus 5.5, fixu2)`

Review finding F112-2 of the fixu review: CON-120 did not name the item owning these cases. In a clean clone at the fixu head, scripts/fastcycle/tests/test_select_sample_r5_regression.sh prints NOT ok 'S3 sqlite3 or live tracker DB unavailable' (line 213) and 'S5 live snapshot unavailable' (line 268) and S6, so the unit is red in the full suite. Same class as CON-129 (environment-dependent reds labelled as unavailability but exiting as FAIL). Not investigated past the reviewer's report; root cause UNCONFIRMED (suspected: sqlite3 CLI absent and the vendored DB path, as in CON-129).

Id history (§11.4.214): first minted in the fixu vehicle as CON-123 (commit 351fe277), re-minted as CON-131 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-132 — SQLite readers opened with immutable=1 are blind to rows still in the WAL (F121-1, F047-3, and two older codegraph readers)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). One class of four members. (1) F121-1 scripts/fastcycle/tests/test_reopen_rate_red.sh needle #2 opens the tracker DB with mode=ro&immutable=1, which ignores the -wal file: a colliding row held only in the WAL is reported CLEAN, rc 0 (reviewer ev/rr_mut_wal_only.out). (2) F047-3 scripts/full_suite/run_full_suite.py check_known_open (around line 2913) reads immutable=1 and prints KNOWN-OPEN rc 0 for a closure still in the WAL (reviewer ev/kopen_wal.out.walonly), a clean 0 on a state it did not see. (3) scripts/codegraph/tests/test_resolve1_equiv_real.js:21 and (4) scripts/codegraph/tests/test_resolve2_probe.js:15 use the same pattern; scripts/codegraph/tests/test_mcp_readonly.sh:28 already records the lesson. Fix shape: open with immutable=1 only when no non-empty -wal exists, else copy the DB and its -wal to a temp directory and read the copy. Enumerate all members with git grep -n immutable=1 (section 11.4.276(C)). Exposure is transient (a writer must hold the WAL open). (N099-8 of docs/qa/fixu_review/review_fixu_r3.md: the elided path above was written in full at the landing, 2026-11-10.)

Id history (§11.4.214): first minted in the fixu vehicle as CON-124 (commit 5dc6097e), re-minted as CON-132 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-133 — Env-read gate eval pin hashes the first physical line only, so a continuation line of an eval can change unseen (F113-2)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). The CON-121 census walks physical lines and hashes the stripped first line of an eval. An eval whose argument continues after a backslash is pinned by its first line; the continuation can be edited without changing the hash (reviewer fixture ev/ge_probe_cont.out: gate PASS). Latent today: none of the nine pinned eval lines ends with a backslash. Fix: hash the full logical statement (join continuation lines and multi-line quoted arguments) and add the continuation fixture.

Id history (§11.4.214): first minted in the fixu vehicle as CON-125 (commit 5dc6097e), re-minted as CON-133 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-134 — Env-read gate documents one row per eval but keys rows by (var, kind), so an identical copy shares a row (F113-3, N113-1)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:09Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). The allowlist header and census docstring say each eval needs its own row. Rows are keyed by (var, kind), so an identical copy of a reviewed eval in the same file shares the row (reviewer ev/ge_probe_dup.out: PASS); live instance scripts/gates/cm_scope_and_image_noworse_anchor_wired.sh lines 340 and 348, one row. Either reword to covers this eval text in this file or add the line number to the key. N113-1: add an indented-eval fixture so the self-test kills the no-strip mutant too (the live gate already does).

Id history (§11.4.214): first minted in the fixu vehicle as CON-126 (commit 5dc6097e), re-minted as CON-134 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-135 — Full-suite self-test lets two reviewer mutants survive: foreign-only tracked token and unreadable DB (F047-4)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). Head code is correct; the tests do not cover it. FM6: replacing ids != {tid} with len(ids) != 1 in match_known survives 252/0 (a log with only another item's tracked token is attributed to the row); add a foreign-only case to 11b. FM3: the cannot-read branch of check_known_open returning 0 instead of 2 survives 252/0; add an unreadable (non-database) file case to 11c. Also N047-1 (commit message RED count 244/1 does not match a run of the committed test, 246/6) and N047-2 (an items table without current_location or status raises an uncaught OperationalError instead of exit 2).

Id history (§11.4.214): first minted in the fixu vehicle as CON-127 (commit 5dc6097e), re-minted as CON-135 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-136 — user_bus_env.sh unit test lets two helper mutants survive (F117-1)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). Two mutants of scripts/lib/user_bus_env.sh survive its unit test 9/0. rv1: the derived branch no longer exports XDG_RUNTIME_DIR (killed only by the persistent-launch integration test). rv2: -S becomes -e in the inherited-XDG branch (integration kill UNCONFIRMED). Fix: a unit case that reads XDG_RUNTIME_DIR from a child after sourcing, and a case with a regular file named bus in the inherited directory.

Id history (§11.4.214): first minted in the fixu vehicle as CON-128 (commit 5dc6097e), re-minted as CON-136 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-137 — Ruler aggregator unstated-reason branch has no discriminating case (F109-4, N109-1)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). Mutant rs_rv1 (the case pattern *" "*|unstated) becomes *" "*) survives the discovery meta-test 12/0 and prints reason=unstated as if it were a shared reason code. Add a meta-test case where every member SKIPs without a reason. N109-1: the sed takes the last reason occurrence on the line while the runner judge() takes the first, so the comment the same way the runner reads it is not exact.

Id history (§11.4.214): first minted in the fixu vehicle as CON-129 (commit 5dc6097e), re-minted as CON-137 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-138 — Supervisor wiring test sends only SIGTERM, not SIGINT or SIGHUP (F120-1, N120-1..3)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). Mutant noint (INT trap removed) orphans the sleep on SIGINT and survives the wiring test. Add an f3 variant per signal (a daemon launched with nohup ignores HUP on entry, so launch with default dispositions). Nits: N120-1 between sleep "$_iv" & and _sup_sleep_pid=$! a signal finds no pid; N120-2 the foreground sleep 1 fallback is not covered by the stop path; N120-3 f3 reads the children list once (race UNCONFIRMED).

Id history (§11.4.214): first minted in the fixu vehicle as CON-130 (commit 5dc6097e), re-minted as CON-138 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-139 — test_reopen_rate_red.sh falls back to the canon DB whenever the consumer DB is absent, without saying so (F121-2)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Sonnet 5.5, fixu3)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`
**Investigation:** not-started — updated 2026-11-06T12:22:10Z — by `AI (Claude Sonnet 5.5, fixu3)`

Review follow-up of fixu round 2 (S/scratchpad/review_fixu2.md, reviewer evidence under the reviewer's scratch ev/ directory, not tracked). Not fixed in fixu3 (registered only). The line [ -f $DB ] || [ ! -f $ROOT/constitution/docs/workable_items.db ] || DB=... switches to the canon DB whenever the consumer DB is absent, not only for a standalone canon checkout, so a consumer with a missing DB is silently checked against the canon DB. Fix: print which DB was read, and switch only when ROOT is the canon itself.

Id history (§11.4.214): first minted in the fixu vehicle as CON-131 (commit 5dc6097e), re-minted as CON-139 at the landing on main (2026-11-10), because main already owns CON-108..CON-115 (merge f3751e51). The vehicle commits and the evidence files under docs/qa/fixu_default_tier/, docs/qa/fixu2_round2/ and docs/qa/fixu3_round3/ name the first ids and are not rewritten (§11.4.113); this note is the map.

## CON-140 — Slicer test C2a parse leg is still a carrier match: any FAIL evidence that contains "syntax error" satisfies it (F099-4, N099-5)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`
**Investigation:** not-started — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`

Review follow-up of fixu round 3 (docs/qa/fixu_review/review_fixu_r3.md, landed with this item; the reviewer evidence named there as ev/... lived in the reviewer's scratch directory and is not tracked). Not fixed at the landing (registered only). scripts/fastcycle/tests/test_precheck_slicer_red.sh line 433 computes parse_leg = any("syntax error" in e.lower() for e in fails) over the string form of the evidence of EVERY FAIL check, so a shellcheck finding text, a message or a fixture comment satisfies it; the reviewer showed it on the real pack (P5: parse check broken plus one innocent fixture comment, C2a PASSes) and with a stub (S6). Same carrier class as F099-2 (section 11.4.201(7)(a)), in the sibling leg; the reviewer's class inventory (section 6) found this line the only open member. Fix: select the check whose check == "parse", require verdict == "FAIL" and an evidence.failures[] entry with file == "broken_syntax_gate.sh" and a case-insensitive "syntax error" message; add P5 and S6 as harness cases. Parent: CON-099.

## CON-141 — C2a mutants harness lets 7 of 8 reviewer mutants survive and never proves its cases reached their precondition (F099-5, F099-6, N099-1, N099-3)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`
**Investigation:** not-started — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`

Review follow-up of fixu round 3 (docs/qa/fixu_review/review_fixu_r3.md, landed with this item; the reviewer evidence named there as ev/... lived in the reviewer's scratch directory and is not tracked). Not fixed at the landing (registered only). scripts/fastcycle/tests/test_precheck_slicer_c2a_mutants.sh: reviewer mutants TM1-TM7 of test_precheck_slicer_red.sh survive the harness 5/0 (TM1, TM4 and TM7 are not equivalent on the real pack); under section 11.4.276(D) a surviving reviewer mutation is adopted and must fail the suite before the next review. The harness asserts only "FAIL: C2a" and rc != 0: M1 blinds the shellcheck leg indirectly (env -i, no bus, relying on open CON-125), so a fixed CON-125 turns M1 into a false FAIL; when the baseline B0 fails, M1, M2 and M4 are still counted PASS (section 11.4.199(2)). Fix: real-pack cases P1, P2, P4 and stub cases S2, S3, S8, S10; blind the leg directly with a stub and assert shellcheck=NO or files_linted 0; assert each case's precondition line; stop or report not-proven when B0 fails; exit 77 (SKIP with a reason) when shellcheck is absent instead of a full PASS (N099-1); add the positive needle for M2 (the unmodified fixture yields SC2086, N099-3). Parent: CON-099.

## CON-142 — C2a mutants harness leaks its temp tree on SIGTERM under dash because it traps EXIT only (F099-8, N099-2, N099-4)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`
**Investigation:** not-started — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`

Review follow-up of fixu round 3 (docs/qa/fixu_review/review_fixu_r3.md, landed with this item; the reviewer evidence named there as ev/... lived in the reviewer's scratch directory and is not tracked). Not fixed at the landing (registered only). scripts/fastcycle/tests/test_precheck_slicer_c2a_mutants.sh installs trap cleanup EXIT only; under sh (dash) SIGTERM does not run the EXIT trap. Reviewer measurement: timeout -s TERM 2 gives rc 124 and leaves tmp.*/{b0,m1,out}, 42 MB, after 2 s; a full run copies the 21 MB scripts/fastcycle five times. Which signal the full-suite runner sends on its own timeout is UNCONFIRMED. Also: BASEENV is expanded unquoted with SC2086 disabled (N099-2), and the cleanup guard case $TMP in /*/tmp.*|/*/*.*) is nearly vacuous because * matches / in case (N099-4; safety rests on mktemp -d plus ${TMP:?}; section 11.4.287(B) prefers safe_rm_rf). Fix: trap cleanup on INT, TERM and HUP with exit 130/143/129, a SIGTERM case in the test, and safe_rm_rf. Reproduction: by the reviewer only, not re-run at the landing. Parent: CON-099.

## CON-143 — Slicer test C2a FAIL message does not say BLIND and does not quote the shellcheck check verdict, files_linted or the pack error (F099-7)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`
**Investigation:** not-started — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`

Review follow-up of fixu round 3 (docs/qa/fixu_review/review_fixu_r3.md, landed with this item; the reviewer evidence named there as ev/... lived in the reviewer's scratch directory and is not tracked). Not fixed at the landing (registered only). Under the full-suite runner default isolation (no XDG_RUNTIME_DIR, no bus) test_precheck_slicer_red.sh and the c2a mutants harness FAIL since ec047648 (the base 351fe277 passed through the carrier); with --env-extra XDG_RUNTIME_DIR --env-extra DBUS_SESSION_BUS_ADDRESS they PASS. The new red is a true red (a blind shellcheck leg is now reported) whose cause is open CON-125, but the C2a FAIL message does not name the cause (section 11.4.201(5)). The process-doc parts of F099-7 (CON-125 affected list, CON-099 note) are done at the landing. Fix left: make the C2a FAIL print the shellcheck check verdict, files_linted and any pack error, and say BLIND when the leg could not see. Parent: CON-099.

## CON-144 — Env-read gate CM-GATE-ENV-READS-ALLOWLISTED fails on main: BLK read-before-assign in the PR-delivery and release-gate anchor-wired gates

**Status:** Ready for testing
**Type:** Bug
**Severity:** medium
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con144_reproduction_2026_11_11.txt` — red-command `bash scripts/gates/cm_gate_env_reads_allowlisted.sh` — green-command `bash scripts/gates/cm_gate_env_reads_allowlisted.sh (same command on the fixed tree; guard: bash tests/gates/test_con144_blk_read_order.sh)` — env `clean checkouts of main 27dcf518, 9cd7cacd and 64ac151d; Linux 7.0.0, git 2.53.0, Python 3.14.4, bash 5.3.9` — signature `UNCOVERED scripts/gates/cm_pr_delivery_anchor_wired.sh:130 BLK (read-before-assign)` — updated 2026-11-11T10:51:47Z — by `AI (Claude Opus 5.5, CON-144 fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `the static env census judges text order: names_cm_gate_in_block() reads $BLK in a body defined above the top-level BLK= assignment; the only call runs after it (ambient BLK changes nothing; moving the definition removes the row)` — evidence `docs/qa/con144_reproduction_2026_11_11.txt` — updated 2026-11-11T10:51:47Z — by `AI (Claude Opus 5.5, CON-144 fix subagent)`

Found at the fixu landing (2026-11-10). On a clean worktree of main 90efceb8, bash scripts/gates/cm_gate_env_reads_allowlisted.sh exits 1 with uncovered=3: scripts/gates/cm_github_issues_source_anchor_wired.sh:334 <eval> (fixed by the fixu vehicle, CON-121), scripts/gates/cm_pr_delivery_anchor_wired.sh:130 BLK (read-before-assign) and scripts/gates/cm_release_gate_anchor_wired.sh:118 BLK (read-before-assign); on the merged tree the first one is gone and the other two remain (uncovered=2). Both lines are the names_cm_gate_in_block() helper, added by c87745de (section 11.4.297) and 2d783401 (section 11.4.298), which reads $BLK inside a function defined before BLK is assigned. Whether the read can happen before the assignment, or the census reports a safe read, is UNCONFIRMED (not investigated at the landing; out of the landing scope, section 11.4.293). Fix: route BLK through cm_gate_env_set, or add allowlist rows with a reason, after reading when the helper runs. Evidence: docs/qa/fixu_review/landing/envgate_main_90efceb8.out (main) and docs/qa/fixu_review/landing/envgate_merged.out (merged tree). Fix (2026-11-11, CON-144 fix vehicle, commit 77553d02 on main 27dcf518, merged with main 64ac151d in c41cf08f): reproduced first on clean 27dcf518, 9cd7cacd and 64ac151d (rc 1, uncovered=2, byte-identical output). Root cause established: the census judges text order; names_cm_gate_in_block() is defined above the top-level BLK= assignment, so its body read of $BLK is reported read-before-assign although its only call runs after the assignment. Decisive experiments: an ambient BLK=/nonexistent leaves both gates' output byte-identical (rc 0); moving only the definition below BLK= removes the census row. The UNCONFIRMED question above is answered: the read cannot happen before the assignment; the census row is a text-order report, not an ambient read. Fix: the helper takes the block file as its second argument and the call site passes "$BLK". Guard tests/gates/test_con144_blk_read_order.sh (needles N0/N1, C1..C5, paired mutants M1..M3): RED 7 FAIL with the fix stashed, GREEN 15/0; env gate PASS uncovered=0 stale=0 on the merged tree; the two anchor gates' mutation tests and the env gate's mutation test PASS. Evidence: docs/qa/con144_reproduction_2026_11_11.txt. Not done: full suite; independent review pending. **Affected scope / file-scope manifest:** scripts/gates/cm_pr_delivery_anchor_wired.sh; scripts/gates/cm_release_gate_anchor_wired.sh; tests/gates/test_con144_blk_read_order.sh; config/full_suite_manifest.tsv; docs/guides/full_suite_runner_guide.md
**Verification:** provisional (section 11.4.290) -- job: re-run scripts/gates/cm_gate_env_reads_allowlisted.sh (expect PASS uncovered=0) and the guard tests/gates/test_con144_blk_read_order.sh (expect 15 passed, 0 failed) on the final main -- checks: census no longer reports BLK read-before-assign for the two anchor-wired gates; guard mutants M1..M3 fail -- layer: host-only (class floor: runtime for a gate item) -- target: host, repo checkout -- artifact: the commit that lands the CON-144 vehicle (9a4ea101 plus the tracker commit) -- due: next full-suite run. Independent Opus review GO-with-follow-ups (0 critical, 0 important, 1 minor, 1 nit); follow-ups CON-192 (F1) and CON-193 (F3). Not VERIFIED-DONE.

## CON-145 — Full-suite manifest auto note of scripts/fastcycle/tests/run_all.sh says 12 heavy members while 14 are listed (N099-7)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI (Claude Opus 5.5, fixu landing)
**Assigned-To:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`
**Investigation:** not-started — updated 2026-11-10T22:30:00Z — by `AI (Claude Opus 5.5, fixu landing)`

Review follow-up of fixu round 3 (docs/qa/fixu_review/review_fixu_r3.md, landed with this item; the reviewer evidence named there as ev/... lived in the reviewer's scratch directory and is not tracked). Not fixed at the landing (registered only). config/full_suite_manifest.tsv row scripts/fastcycle/tests/run_all.sh carries the note "auto: covers 12 heavy member(s)"; at the landing 14 rows name run_all.sh as their heavy member runner (13 at the base of the vehicle). The note is pre-existing and stale, --verify-manifest does not check it. Fix: regenerate the auto note, or make --verify-manifest compare the count with the member rows.

## CON-146 — custody_sweep.py: stash patch from git stash show -p is garbled on git 2.53.0, so every stash land is refused

**Status:** Queued
**Type:** Bug
**Severity:** High
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con146_reproduction_2026_11_05.txt` — red-command `bash scripts/fastcycle/tests/test_custody_sweep_r11_regression.sh (also r13, r15, stash_patch_r22) on the pre-fix tool` — green-command `same commands on the fixed tool` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `NOT ok B2 stash golden-good: expected ALLOWED, got REFUSED (backup ... does NOT match the entry's freshly re-derived LIVE dirty content)` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `git 2.53.0 git stash show -p ignores the a/ b/ prefix options and emits run-varying header prefixes; git diff over the same two trees is correct` — evidence `docs/qa/con146_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-108 (rounds 1 to 3), then CON-116 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-146 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/orchestration/custody_sweep.py derived the stash patch (inventory hash and verify-proposal live hash) with git stash show -p <CANONICAL_PATCH_OPTS>. On git 2.53.0 that command ignores --src-prefix/--dst-prefix and prints headers that change on every run (diff --git f sf, diff --git f |f), so no backup can ever match and every stash land is REFUSED (fails closed, no data loss). Fix: derive with git diff <CANONICAL_PATCH_OPTS> <ref>^1 <ref>; self-check every diff --git header carries a/ b/ prefixes, else UNMEASURED (never hashed); tests r11, r13, r15 build their backups the same way; new guard scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh (host-independent via git shims, paired mutations M1-M3). Upstream git bug report: not filed (UNCONFIRMED whether fixed in a later git). Acceptance: r11, r13, r15 and the new guard GREEN on git 2.53.0; mutations caught. Fix round 2 (independent review round 1: NO-GO, findings F1-1 and F1-2): F1-1, git C-quotes each path on its own, so a header can mix a bare and a quoted path (diff --git a/c.txt "b/sp ace\ttab.txt"); the old header pattern refused that correct patch as UNMEASURED and the verify-proposal refusal named the wrong cause (git status/diff failed). The pattern now matches each side separately, ^diff --git (?:a/.*|"a/.*") (?:b/.*|"b/.*")$ (checked on 11 header shapes, still rejects f sf, f xf, c/x d/x, f |f), and the refusal names the real cause (the bad diff --git header, or the failed git diff with its rc) via stash_patch_bytes_why / unmeasured_why. F1-2, r22 gains a two-file mixed-quoting stash (G4, G5 GREEN), a shim that mangles only the SECOND header (B3, B4) and mutants M4 (reviewer R1g, check only the first header) and M5 (old pattern), both caught; r22 RED pass=15 fail=5 on the round-1 tool, GREEN pass=20 fail=0; r11, r13, r15 GREEN. Follow-up CON-157 (display-only file list). **Affected scope / file-scope manifest:** scripts/fastcycle/orchestration/custody_sweep.py; scripts/fastcycle/tests/test_custody_sweep_r11_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r13_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r15_regression.sh; scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh; config/full_suite_manifest.tsv Fix round 3 (structural, independent review round 2 NO-GO, findings R2-F1-A/B/C; root-cause class: the guard's fixtures did not separate the mutants' axes): r22 now has a three-header stash (plain, mixed-quoting rename, plain) and a positional shim that garbles exactly the first, the middle, the last or every header, bare and as a quoted header with no prefixes (diff --git "f" "xf"); every mutant has named functional checks: M4 first-header-only, M5 old pattern, RV1 last-only, RV2 first-and-last, RV3 quoted headers trusted, RV4 loose pattern, RV5 rc cause dropped, RV6 first-two-only, all killed by their named checks (P1-P3, Q1-Q3, V2, V3, F1, G4, G5). R2-F1-B: F1 checks the refusal names 'git diff stash@{0}^1 stash@{0} failed (rc=3)'. R2-F1-C: the round-2 log said r22 RED pass=15 fail=5 on the round-1 tool; re-running that committed test gives pass=14 fail=6 (the reviewer's number), so the round-2 number was not reproducible; round-3 numbers are recorded with their commands in docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt. Old r22 (round 2) against the round-3 mutants: RV2, RV5, RV6 survive (rc 0); new r22: all 8 killed, GREEN pass=36 fail=0; the new r22 on the round-1 tool pass=24 fail=12, on the round-2 tool pass=33 fail=3 (G4, L1: the CON-157 file list). r6-r21 custody_sweep regressions rerun on the round-3 tool: same results as on the round-2 tool (r9 and custody_sweep_red fail identically on both, known and unrelated). Round 4 (review r22 NO-GO, recurrence 3 of the fixture class): the r22 test rebuilds its fixtures as a matrix over the whole class (header count 1..7, forward and reversed, three git configs, every header position, five garble forms, sections of type text-with-a-removed-line-that-looks-like-a-header, binary, new, empty new, deleted, mode-only, rename with tab and space name, copy, C-quoted) with an oracle independent of the tool (git diff -z --name-status), 527 cells; cases XS, XC, XB, XB1, XM, XG, XQ added; reviewer mutants NM1..NM13 adopted verbatim plus the FL1,3,4,5,6,7,8,9,10 set, each RED (survives the round-3 battery 24/0) then GREEN (killed by the new test); FL2 is equivalent and not adopted; result pass=81 fail=0, 34 mutation self-tests. Evidence: scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh. Round 5 (review of fsfix4 NO-GO, F2 and F3): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). The r22 matrix removed none of its mkdtemp repositories (measured on the round-4 test: one matrix.* dir per matrix run left under TMPDIR; the review measured 35 dirs, 168 MB per full run); the matrix now removes its base at exit and runs with its own TMPDIR, check MX fails on any leftover, and the whole test runs with TMPDIR under its own temp dir (check TD). An empty stash patch is now pinned: EP1 (untracked-only git stash -u) and EP2 (index-only change) give empty_patch, never UNMEASURED; EP1V: land of an untracked-only stash is refused for its untracked content, not as unreadable. Reviewer mutant RD adopted verbatim, RED (survives the round-4 test, pass=47 fail=1 with RD as a self-test) then killed by EP1/EP2; live-path twin RD2 killed by EP1V. Result pass=88 fail=0, nothing left under TMPDIR. Not changed, recorded: land of an index-only stash with an empty backup is REFUSED with a hash mismatch (the live hash of an empty patch is None); fail-closed, whether intended is UNCONFIRMED. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. M1: custody_sweep.py records index_unpatched for a stash (git diff --quiet ref^1 ref^2, run only when the tracked patch is empty), and verify refuses land of such a stash for its index (staged) content with a message that names it and says the backup is not stale (the round-5 hash-mismatch refusal was incidental). New check EP2V and paired mutant EP2M (the check disabled): EP2M caught by EP2V; r22 regression test pass=90 fail=0 (9 m 45 s). Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

## CON-147 — host_guard.sh: live thread limit unreadable under dash (ulimit -u), so every shard plan is clamped to N=1

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con147_reproduction_2026_11_05.txt` — red-command `FC_GUARD_NPROC=64 FC_GUARD_THREADS=0 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 sh scripts/fastcycle/lib/host_guard.sh 1000000; sh scripts/fastcycle/tests/test_host_guard_red.sh` — green-command `same commands on the fixed guard` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `N=1 REASON=unreadable_ulimit under sh` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `dash has no ulimit -u, so the live read returned empty` — evidence `docs/qa/con147_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-109 (rounds 1 to 3), then CON-117 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-147 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/lib/host_guard.sh read the soft RLIMIT_NPROC with ulimit -u, which dash (/bin/sh on Debian/Ubuntu) rejects; run via sh it reported N=1 REASON=unreadable_ulimit, so gate_runner.sh serialised every shard plan on such hosts. Fix: read the soft Max processes value from /proc/self/limits, fall back to ulimit -u; FC_GUARD_PROC_LIMITS names a fixture file for tests. Test scripts/fastcycle/tests/test_host_guard_red.sh reads its own expectation the same way, lowers the limit with prlimit when present, and adds fixture checks (soft 777 vs hard 999, unlimited, garbled, live control needle). Acceptance: GREEN under sh (dash) and bash; mutations (file ignored, hard field read) caught. Fix round 2 (independent review round 1: NO-GO, findings F2-1, F2-2, F2-3): F2-1, scripts/fastcycle/host/host_report.py _read_ulimit_threads still ran sh -c "ulimit -u" only, so probe_thread_headroom reported unmeasured on dash hosts; it now reads the soft Max processes value from /proc/self/limits (new _read_nproc_soft, same FC_GUARD_PROC_LIMITS test seam) with sh -c "ulimit -u" as the fallback; new guard scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh (dash-like sh shim, real dash, fixtures soft 4242 / hard 99999, unlimited, no line + bash fallback, end-to-end probe; mutants M1 old read, M2 hard column, M3 no fallback, all caught), RED pass=5 fail=9 / GREEN pass=14 fail=0 under sh and bash. Class census (git grep ulimit -u, control needles): host_guard.sh fixed in round 1, host_report.py fixed here, test_host_guard_red.sh:258 no-prlimit branch scoped out as CON-155, codegraph_safe.sh (bash) and prose not members. F2-2, behaviour change for callers, checked: on a dash host four callers that were silently serial (N=1) now get the guard's real limits: scripts/fastcycle/gates/gate_runner.sh:174 (xargs -P over at most --n-shards shards), scripts/fastcycle/gates/lib/backstop_run.py:223 (--jobs, never above the caller's request), scripts/fastcycle/host/host_report.py:1021 (a probe that only reads N, starts no jobs) and scripts/fastcycle/tests/test_foundational_mutations.sh:107 (MAXJ, at most 9). Each stays bounded by the guard's nproc, thread-headroom (section 12.12) and 60 % memory-ceiling (section 12.6) rules; the guard does not size N by per-job memory when no --per-job-mem-kb is passed (its existing I1 design). The reviewer measured the foundational driver at MAXJ 9: peak 43 processes, at most 30.1 % of MemTotal in use (all users), 2796 of 123694 threads. F2-3, FC_GUARD_PROC_LIMITS added to the host_guard.sh header Inputs list. **Affected scope / file-scope manifest:** scripts/fastcycle/lib/host_guard.sh; scripts/fastcycle/tests/test_host_guard_red.sh; scripts/fastcycle/host/host_report.py; scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh; config/full_suite_manifest.tsv Fix round 3 (structural, review round 2 finding R2-F2: HR1 and HR2 survived): the guard now lowers its own process limit with setrlimit before exec (soft THR+3000, hard soft+1000, a control needle checks it differs from pid 1), so reading /proc/1/limits instead of /proc/self/limits fails P1 (HR2 killed); missing (X1) and unreadable mode-000 (X3) limits files with a working 'ulimit -u' must use the fallback (HR1 killed); a fixture with a working 'ulimit -u' (L4B) proves the file wins (HR3 ulimit-first killed; in production both read the same kernel value, differential recorded); FC_GUARD_ULIMIT_U override (O1). Fixture axes listed in the test header. Old guard: HR1, HR2 survive (rc 0) under sh and bash; new guard pass=25 fail=0 under sh and bash, every mutant killed by its named check. Evidence: docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt. Round 4 (review r1 NO-GO): the thread-limit regression test adds RX1/RX2 (lower the limit to 5333:6333, then a missing and an unreadable limits file, read under bash as sh) killing mutant RVH1, plus RX3..RX8 and mutants RVH1..RVH11 (RVH12 is equivalent, documented); result pass=44 fail=0 under sh (dash) and under bash (both measured). Round 5 (review of fsfix4, F8): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). host_guard.sh's awk now skips a 'Max processes' line with fewer than four fields, as host_report.py does (it used to print the third field of a three-field line). RED: with the old awk, test_host_guard_red.sh fails its two new checks (three-field line read as N=5; three-field line then a full soft-888 line read as N=5), pass=135 fail=2; GREEN pass=137 fail=0 under sh and bash. host_report's test adds RX9 (three-field line, then a full line with soft 8888 -> 8888): pass=45 fail=0 under sh and bash. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. M2: the RLIMIT_NPROC readers' comments in host_guard.sh and host_report.py state the real boundary (four words: a two-word name, soft, hard; units not required). Reviewer mutant H1 adopted: RED, it survives the round-5 test (pass=137 fail=0 with H1 applied); new fixture "Max processes 5 6" must give N=5, H1 now killed (pass=137 fail=1). The decision-mutant census (scripts/validation/enumerate_decision_mutants.py, section 11.4.274) found host_guard's awk 2>/dev/null redirect unpinned: a directory as the limits path must give the no-line result with stderr empty (new checks). test_host_guard_red.sh pass=140 fail=0; host_report thread-limit test pass=45 fail=0. Census over host_guard.sh (46 mutants) and host_report.py's _read_nproc_soft (9): every mutant KILLED except three floor-at-1 comparisons (-lt 1 -> -le 1) proven equivalent in scripts/validation/decision_mutants_equivalent.tsv. Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

## CON-148 — test_custody_sweep_r6: guard-viability pattern misses the Python 3.14 TypeError wording

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con148_reproduction_2026_11_05.txt` — red-command `bash scripts/fastcycle/tests/test_custody_sweep_r6_regression.sh` — green-command `same command` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `NOT ok R6-I3(1)/int guard-viability BLIND` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `Python 3.14 changed the TypeError text of 'k in <int>'` — evidence `docs/qa/con148_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-110 (rounds 1 to 3), then CON-118 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-148 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/tests/test_custody_sweep_r6_regression.sh greps the pinned pre-fix tool's crash for 'is not iterable'; Python 3.14 words it 'is not a container or iterable', so both guard-viability legs reported BLIND. Fix: pattern 'is not (a container or )?iterable' with a self-check (both wordings match, an unrelated TypeError does not). **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_custody_sweep_r6_regression.sh

## CON-149 — test_fc_common_run_gate_reaped_r6: dash echo turns the literal backslash-n into a newline

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con149_reproduction_2026_11_05.txt` — red-command `sh scripts/fastcycle/tests/test_fc_common_run_gate_reaped_r6_regression.sh` — green-command `same command` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `FAIL: 4: normal stdout/stderr capture regressed` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `dash echo interprets backslash escapes` — evidence `docs/qa/con149_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-111 (rounds 1 to 3), then CON-119 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-149 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-031 (full-suite runner). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/tests/test_fc_common_run_gate_reaped_r6_regression.sh (#!/bin/sh) piped $RESULT through echo; dash's echo interprets the backslash-n that repr() prints in SECTION_C, so check 4 failed under sh and passed under bash. Fix: printf '%s\n'. **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_fc_common_run_gate_reaped_r6_regression.sh

## CON-150 — handoff_i4, handoff_r9, custody_sweep_r17: prose with fail words after the summary line, runner reads ERROR

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con150_reproduction_2026_11_05.txt` — red-command `bash scripts/fastcycle/tests/test_handoff_i4_regression.sh (also handoff_r9, custody_sweep_r17), then judge() of scripts/full_suite/run_full_suite.py on the output` — green-command `same` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `('ERROR', 'fail_signal_after_summary', 'summary', {})` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `prose with fail words printed after the summary line` — evidence `docs/qa/con150_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-112 (rounds 1 to 3), then CON-120 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-150 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-031 (full-suite runner). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: the three tests exit 0 with every check passing, but print explanatory prose containing 'fails CLOSED' / 'failure' after their summary line; the full-suite runner's fail-word check (unchanged, deliberately conservative) reports ERROR fail_signal_after_summary. Fix: the prose is printed first and the summary line last. Fix round 2 (independent review round 1: GO-with-follow-ups, finding F5-1 minor-class, class not exhausted): the reviewer's census found two more members, both edited the same way: scripts/fastcycle/tests/test_limit_class_place_r5i3_regression.sh (live: judged ERROR fail_signal_after_summary before, PASS after, rc 0 both) and scripts/fastcycle/tests/test_custody_sweep_r9_regression.sh (latent: that test still fails for the known consumer-root reason, same two NOT ok lines as the reviewer's run). Census TOTAL 2 before, 0 after; a planted needle is still found. Census gate registered as CON-156. **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_handoff_i4_regression.sh; scripts/fastcycle/tests/test_handoff_r9_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r17_regression.sh; scripts/fastcycle/tests/test_limit_class_place_r5i3_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r9_regression.sh Fix round 3: scripts/fastcycle/tests/test_metatest_per_mutant_red.sh ended without a summary line, so the full-suite runner judged its PASS output ERROR unparsed_fail_signal (review round 2 finding R2-F5-A); it now prints '=== metatest per-mutant RED baseline (T017): fail=N ===' last; runner judge PASS after. Evidence: docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt.

## CON-151 — test_gate_shard_r3 B1: the M3c mutant copy cannot import fc_common, never plans, and is misread as not flipped

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con151_reproduction_2026_11_05.txt` — red-command `sh scripts/fastcycle/tests/test_gate_shard_r3_regression.sh` — green-command `same command` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `NOT ok B1: mutation-flip FAILED -- with M3c applied, g_protected_writer STILL landed outside the parallel set` — updated 2026-11-05T20:42:19Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `the mutant copy could not import fc_common (FileNotFoundError plan_m3c/plan.json)` — evidence `docs/qa/con151_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:19Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-113 (rounds 1 to 3), then CON-121 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-151 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/tests/test_gate_shard_r3_regression.sh copied the mutant to $WORK/*.py; gate_runner_shard.py imports fc_common from <its dir>/../../lib, so the copy crashed, wrote no plan.json, and B1 reported 'mutation-flip FAILED'. Fix: the mutant (and an unmutated control copy) run in a scratch copy of the gates/lib + lib layout; a mutant or control that writes no plan reports BLIND. With the fix the mutant flips (g_protected_writer lands in the parallel set). **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_gate_shard_r3_regression.sh

## CON-152 — test_foundational_mutations.sh spins one CPU after a process-group TERM and leaks its work dir (up to 334 MB) on KILL

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-114 (rounds 1 to 3), then CON-122 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-152 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-147. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding PRE-1 (pre-existing; present on base and fix). What: run as timeout -k N T bash scripts/fastcycle/tests/test_foundational_mutations.sh (the run_all.sh shape: TERM to the whole process group), the driver stays in state R with no children at about 100 % of one CPU until the kill-after (measured 10.6 s and 11.4 s at -k 12); a direct TERM to the driver alone exits in 2-4 s. The spin is inside cleanup() before rm -rf "$W", so a run ending in KILL leaves $W behind (three leftovers of 334 MB, 21 MB, 334 MB measured by the reviewer; section 12.9). A minimal model (helpers/spinrepro) spun in 5 of 16 runs when the TERM trap's cleanup runs wait, 0 of 8 without it; mechanism UNCONFIRMED (intermittent). **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_foundational_mutations.sh **Reproduction / context:** timeout -k 12 20 bash scripts/fastcycle/tests/test_foundational_mutations.sh, sample /proc/<pid>/stat utime while it runs, then look for the leftover $TMPDIR/tmp.* work dir. **Acceptance criteria:** reproduce with the run_all.sh shape; root cause decided by experiment; no spin and no leftover work dir in many repeated group-TERM runs; the reproduction becomes a regression guard.

## CON-153 — triple harness fails standalone on the signal-window checks (postwait, postcanary), about 815 s at load about 30

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-115 (rounds 1 to 3), then CON-123 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-153 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding PRE-2 (pre-existing; base and fix identical). What: the triple-harness test run on its own exits rc 1 after about 815 s with r6-f1/f2/r7 signal window (harness, postwait): got '' want 'RESULT fired=1 rc=2 orphan=0 sleeper=na canary=na' and the postcanary variant. It makes the foundational driver's M2 and M4 controls fail (control th rc=1) on this host regardless of CON-147. Root cause UNCONFIRMED (the signal-window checks may be load-sensitive). **Affected scope / file-scope manifest:** the triple-harness test under scripts/fastcycle/tests (the th control of test_foundational_mutations.sh) **Reproduction / context:** run the triple-harness test standalone with sh on a 16-CPU host at load about 30; evidence th_base.* and th_fix.* in the review evidence dir. **Acceptance criteria:** reproduced, root cause proven by a decisive experiment, the two checks GREEN under load or honestly bounded; regression guard added.

## CON-154 — test_foundational_mutations.sh 900 s bound is too tight on a loaded 16-CPU host

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-116 (rounds 1 to 3), then CON-124 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-154 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding PRE-3 (pre-existing). What: the driver declares fastcycle-timeout-s 900, set on a 64-CPU host (header: 68 s at load about 38). Measured by the reviewer on 16 CPUs at load 14-50: serial (old guard under dash) 1382 s, parallel (fixed guard, MAXJ 9) 883 s, of which the triple-harness control alone was about 815 s, so the margin is 17 s. Severity minor, test-instrumentation. UNCONFIRMED how much of the 815 s is load-dependent. **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_foundational_mutations.sh (fastcycle-timeout-s header); the triple-harness control **Reproduction / context:** time the driver under run_all.sh on a 16-CPU host under load. **Acceptance criteria:** a host-adaptive bound or a shortened triple-harness control, measured to finish with margin on the small host; no change to what the driver proves.

## CON-155 — test_host_guard_red.sh no-prlimit branch lowers the limit with sh -c 'ulimit -u', which dash rejects

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-117 (rounds 1 to 3), then CON-125 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-155 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-147. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding F2-1 class census (scope-out row). What: the F2-1 census (git grep ulimit -u, with control needles) found one executable member left outside host_report.py and host_guard.sh: scripts/fastcycle/tests/test_host_guard_red.sh:258, the branch taken only when prlimit(1) is absent, which runs sh -c 'ulimit -u "$1" && ...'. On a dash host without prlimit that check FAILs (RAW_OUT empty), it never gives a false PASS. Scoped out of the CON-147 fix round 2 because no portable /bin/sh way to lower RLIMIT_NPROC exists; a python3 resource.setrlimit wrapper is the likely fix. Other census rows: codegraph_safe.sh:416 runs under bash (not a member); host_guard.sh:172 is the fallback after /proc/self/limits (fixed member); cm_killpg_pgid_guard_scope_selftest.sh:455 uses ulimit -f under bash (not a member); Constitution.md and mirrors are prose. **Affected scope / file-scope manifest:** scripts/fastcycle/tests/test_host_guard_red.sh **Reproduction / context:** run test_host_guard_red.sh under dash with prlimit removed from PATH. **Acceptance criteria:** the lowered-limit check works under dash without prlimit (or SKIPs with a closed reason), proven by a run with prlimit hidden.

## CON-156 — Census gate for test PASS branches that print fail words after the summary line

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-118 (rounds 1 to 3), then CON-126 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-156 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-150. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding F5-1 follow-up. What: the reviewer's static census (helpers/census5.py: an echo or printf holding ALL CHECKS PASS or similar, then the rest of that line and the following echo lines up to exit/else/fi, tested with the runner's own _FAILWORD) found two more members after CON-150, both fixed in round 2 (test_limit_class_place_r5i3_regression.sh, test_custody_sweep_r9_regression.sh; census TOTAL 0 after, a planted needle still found). Making the census a gate would stop new members landing; not done in round 2 because a gate needs its own self-test, paired mutation and manifest row. **Affected scope / file-scope manifest:** scripts/gates (new gate), scripts/full_suite/run_full_suite.py (_FAILWORD reused, not changed) **Reproduction / context:** python3 census5.py scripts/full_suite/run_full_suite.py . on the tree. **Acceptance criteria:** a gate with golden-TRUE (planted member) and golden-FALSE fixtures, control needle, paired mutation; TOTAL 0 on main. Round 3 decision: the gate is NOT built in this round. Review round 2 (R2-F5-A) named two more members, both fixed here: test_metatest_per_mutant_red.sh (CON-150 round 3) and scripts/validation/meta_test_verification.sh (CON-158, PASS path judged ERROR unparsed_fail_signal before, PASS after). A census over the runner's classify() needs a model of which output a test prints last on each path; the static census tried here gave false leads (5 of 10 candidates were false on reading), so a precise gate is not small; it stays the open work of this item.

## CON-157 — custody_sweep stash_files_touched lists only the source path of a rename and misses C-quoted paths

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (custody/host_guard fix round 2 subagent)

Vehicle ids before re-mint: CON-119 (rounds 1 to 3), then CON-127 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-157 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-146. Source: independent Opus review of the custody/host_guard fix vehicle (scratchpad review_custody_hostguard_fixes.md, evidence dir review_custody_hostguard_ev/), finding item 1 note (not a finding of that batch) plus round 2 observation. What: stash_files_touched parses headers with DIFF_FILE_RE ^diff --git a/(.+?) b/, so a rename lists only its source path, and a header with a C-quoted path (diff --git a/c.txt "b/sp ace\ttab.txt", now accepted by the round-2 header check) is not listed at all. The list is display-only per its docstring and no hash or verdict uses it; UNCONFIRMED whether anything relies on it. **Affected scope / file-scope manifest:** scripts/fastcycle/orchestration/custody_sweep.py (stash_files_touched_why, DIFF_FILE_RE) **Reproduction / context:** inventory a stash holding git mv c.txt 'sp ace<TAB>tab.txt' plus an edit to d.txt; files_touched shows only d.txt. **Acceptance criteria:** decide (display-only, documented) or list both rename paths and unquoted names; covered by a test. Fixed in round 3 (test first): stash_files_touched_why now reads paths with _patch_file_paths: both paths of a rename (rename from/to), copy targets, ---/+++ lines (C-quoted names unquoted, the trailing TAB git adds after names with spaces dropped), and the same-path header fallback for binary, mode-only and deleted sections, so 'x b/y.txt', non-ASCII, quoted and spaced names are listed whole. Still display-only; no hash or verdict uses it. r22 checks L1 (nine shapes, expected list from git diff -z --name-status) and G4 (rename both paths): RED on the round-2 tool (G4, L1 fail), GREEN after; mutation L1_old_file_list (the old DIFF_FILE_RE parse) killed by G4 and L1. Evidence: docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt. Round 4: the docstring of _patch_file_paths now says no custody verdict reads the list and it is not part of the patch hash, but it is a field of the inventory entry and so inside body_hash (fc_common.body_hash_of); mutants FL6 (copies), FL7 (removed line starting with two dashes and a space) adopted and killed in the r22 test.

## CON-158 — meta_test_verification.sh renamed a submodule and sed -i edited the tracked gate in place, and its mutation 2 was a syntax error

**Status:** Queued
**Type:** Bug
**Severity:** High
**Created-By:** Claude Opus 5.5 (custody/host_guard structural round 3 subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt` — red-command `bash scripts/validation/test_meta_test_verification_r1_regression.sh (against the pre-fix meta_test_verification.sh, plus the TERM-at-delay loop; evidence file section 'CON-120 reproduction' and 'CON-120 RED', vehicle id before re-mint)` — green-command `same command, on the fixed meta-test` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, bash, load ~30 on 16 CPUs` — signature `old meta_test_verification.sh stopped by TERM at 0.02 s: SUBMODULE_MOVED; at 0.12/0.25/0.30 s: TRACKED_FILE_MUTATED+bak_left` — updated 2026-11-10T23:30:39Z — by `Claude Opus 5.5 (fsfix round 5 subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `the old meta-test renamed the real verification submodule and edited the tracked gate in place, so a stop between the change and its restore left the checked tree changed; proven by the TERM-at-delay table (tree changed only at delays inside those windows) and by the scratch-root rewrite, which removed the windows (GREEN 11/0, then round 4/5 tests)` — evidence `docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt` — updated 2026-11-10T23:30:39Z — by `Claude Opus 5.5 (fsfix round 5 subagent)`

Vehicle ids before re-mint: CON-120 (rounds 1 to 3), then CON-128 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-158 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-150 / CON-156 class (review round 2 finding R2-F5-A, risk raised UNCONFIRMED by the conductor). What: scripts/validation/meta_test_verification.sh (manifest row: entry, heavy) renamed submodules/verification to verification.mut.bak and ran sed -i on the tracked scripts/validation/run_verification.sh, with fixed /tmp names and no trap. Reproduced on a scratch tree (docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt): a TERM at 0.02 s left the submodule renamed and at 0.12, 0.25 and 0.30 s left the tracked gate mutated with a .mut.bak beside it (4 of 15 delays); a heavy-tier run on a real checkout that has submodules/verification would do the same to it (section 9.2). Its mutation 2 seds also rewrote every fi/else, so the mutated gate did not parse (bash -n rc 2): a syntax error fails whatever the gate checks, a bluff mutation. Its PASS path ended with prose the full-suite runner judged ERROR unparsed_fail_signal. Fix: the checked tree is never changed; each mutation runs on a mktemp -d scratch root under TMPDIR (a copy of the gate plus one symlink per real submodule), removed by an EXIT trap; mutation 2 edits a copy with two exact anchors and must pass bash -n; the summary line is printed last. New guard scripts/validation/test_meta_test_verification_r1_regression.sh (fake tree; full run unchanged tree, empty TMPDIR, runner judge PASS, mutation-2 parse; TERM and KILL at 12 delays (superseded in round 4 by 14 delays scaled to the measured run time); blind gate and always-fail gate make it fail): RED on the old script pass=6 fail=5, GREEN pass=11 fail=0. **Affected scope / file-scope manifest:** scripts/validation/meta_test_verification.sh; scripts/validation/test_meta_test_verification_r1_regression.sh; config/full_suite_manifest.tsv; docs/guides/full_suite_runner_guide.md (census line) Round 4 (review r1 NO-GO): the regression test adds fixtures B3 (gate that needs git) and B4 (reformatted gate) killing mutants MT1 and MT9, scales the TERM and KILL delays to the measured run time (14 points from 2 to 98 percent, with a control needle), and the script header documents the KILL gap: SIGKILL cannot run the EXIT trap, so the mktemp scratch root with symlinks is left behind; the checked tree is never changed. Result pass=17 fail=0. Round 5 (review of fsfix4 NO-GO, F1 and F7): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). Reviewer mutants Ma (control verdict ignored) and Mb (mutation-1 verdict ignored) adopted verbatim: RED, both survive the round-4 test; the test now lists every decision point of meta_test_verification.sh (DP1..DP13) and pins each with a fixture and a paired mutant: B5 always-pass gate with intact anchors (kills Mb), B6 README missing in the checked tree (kills Ma), B7 gate missing, B8 test submodule missing, B9/B10 scratch-root sabotage of mutation 1 and 2, B11 weakened gate that does not parse, signal fixtures TERM/INT/HUP (exit 143/130/129, nothing left) and a TERM during cleanup's rm. A real defect found while doing it: a TERM to the process group while the EXIT trap's rm ran killed the rm and left the scratch root (measured 8 of 280 stops at 90..105% of the run); cleanup now ignores HUP, INT and TERM before its rm (0 of 280); remaining window stated in the script: a second signal between the start of the EXIT trap and its first command. F7: after each timed stop the test waits until no process with the scratch path, or the meta-test's own command line (a killed meta-test's build_root subshell keeps running), is left before it removes the scratch root. Result pass=51 fail=0 (runs 3 and 4), nothing left under TMPDIR. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. N1: every signal of the regression test is sent on an observed event (the sigwait gate's marker during the control run, or an rm shim's marker when the cleanup's rm starts), launched by sigrun.py in its own session with HUP/INT/TERM reset. N2: every wait is bounded (30 s, then SIGKILL of the process group; leftover session processes are killed and counted; a timeout or nomark verdict is BLIND and repeated once). N3: reviewer mutants R1b (twice), R2, R3, R4, R5b and R7 adopted verbatim: RED, 5 survive the round-5 test (pass=52 fail=5); new fixtures B12 (mktemp fails), B13 (duplicate anchor), B14 (cp fails), B15 (ln fails) kill them; TERM/INT/HUP pinned to exit 143/130/129. n1: every fixture runs in its own mktemp directory (the counter bumped inside $(...) is gone). Class closed (section 11.4.274): scripts/validation/enumerate_decision_mutants.py enumerates every decision point of meta_test_verification.sh (60 single-edit mutants) and runs each against the regression test. Census run 1 on the round-6 test: 15 survivors; the test then adds the diag= field (both streams of each gate run captured and indented; gates false, needs_git and stderr_missing write to stderr; mutants DP14a-g) and the stop= field (a scratch-root failure stops the run; mutants DP15a-c). Census run 2: killed=109 survived=0 equivalent=6 blind=0 over all three targets, the meta target's three equivalents proven in the ledger. Regression test pass=75 fail=0, three runs. Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

## CON-159 — CON-158 census wording overstates coverage: every decision point matched by the closed operator list, not every decision point

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)

Review finding m1 (minor, process-doc, parent CON-158). The CON-158 body and commit 02e681a6 say enumerate_decision_mutants.py enumerates every decision point of meta_test_verification.sh and closes the class. It covers only decision points its closed list of single-edit operators matches. Reviewer mutants Y1, Y2, Y8, Y9 and Y10 are real decision-point mutants the operators do not generate (all five killed by existing tests, so nothing is unguarded today). Fix: reword the tracker text and commit-derived docs to every decision point matched by the closed operator list; optionally add operators for if-condition negation and awk field shifts. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-160 — EP2V does not pin stash_index_unpatched True vs None and no fixture makes git fail (reviewer mutants Y12, Y14 survive)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)

Review finding m2 (minor, test-instrumentation, parent CON-146). EP2V checks only that the refusal message names index (staged) content. Mutant Y12 (rc==1 returns None instead of True) and mutant Y14 (final return None becomes False, a git failure reads as no index content) both survive r22 (90/0). The verdict stays REFUSED either way, so this is message precision, not safety. Fix: assert index_unpatched=True in EP2V, and add a git-failure fixture (a PATH shim making git diff --quiet ^1 ^2 return 128) asserting index_unpatched=None; both must kill Y12 and Y14. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-161 — host_report probe_thread_headroom arithmetic and thr-is-None guard have no canon-runnable test (reviewer mutants Y4, Y5, Y6 survive)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)

Review finding m3 (minor, test-instrumentation, pre-existing, outside round 6, CON-147 neighbourhood). Y4 (per_job = headroom), Y5 (headroom = ulim - 1) and Y6 (drop the thr is None guard, giving an uncaught TypeError in host_report.py limits) survive the only test that runs in a canon checkout (host_report r1, 45/0); test_host_limits_red.sh SKIPs outside a consumer layout. The source is correct today. Fix: a canon fixture pinning thread_headroom, threads_per_job_probed and reason=unmeasured when FC_GUARD_THREADS is unset and ps fails; optionally widen the census host_report scope to the probe. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-162 — fsfix6 review nits: census timeout kill misses timeout's process groups, ledger KILLED-key staleness, porcelain git diff in stash_index_unpatched, vehicle items left Queued

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)

Review nits n1 to n4. n1: the census run_bounded kills its own process group on timeout, but GNU timeout starts a new process group, so children can run up to 125 s into the next mutant (host load only). n2: a ledger entry is STALE only when its key is no longer generated; an entry whose mutant is later KILLED (equivalence proof now false) is accepted silently; flag it stale. n3: stash_index_unpatched uses porcelain git diff --quiet, subject to diff.ignoreSubmodules and external drivers; use git diff-tree --quiet ^1 ^2. n4: the 13 vehicle items stay Queued while fix rounds run; consider In progress for CON-146, CON-147, CON-158. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-163 — fk_index_patch.py: REUSED could reuse a damaged runner (whole-tree + launcher check), duplicate list anchors were not refused, stale .partial kept, corrupt-receipt error did not name --force

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031 (full-suite failures root-cause report of 2026-11-05). What: tests/test_patch_machinery.py cases P1b P1c P2c P2d P2e P2f P4a P4b were RED against scripts/codegraph/fk_index_patch.py (SUMMARY fails=9). Fix (fix vehicle 2026-11-05): fkidx1.parse_lists refuses a list anchor that occurs more than once; receipt_valid requires an executable launcher and a whole-tree equality (sha256 + exec bit per file, symlink targets) between <dst> and the source with this run's edits; a stale <dst>.partial is removed on REUSED; load_receipt refuses an unreadable/corrupt receipt with a message naming --force. RED/GREEN: same command PYTHONDONTWRITEBYTECODE=1 python3 scripts/codegraph/tests/test_patch_machinery.py; before fails=9, after fails=1 (P3, see CON-147). Paired mutants M1 M2 M4 M5 M6 M23 killed; M3 (launcher check alone) equivalent, subsumed by the tree check. Cost: REUSED on the real 1.6.2 package 1.13 s vs 0.30 s before (both trees hashed). Reproduction surface host-only; evidence was captured in the vehicle scratch area and is not committed: re-run the command to reproduce. Acceptance: independent review, then the state fields set with committed evidence. Round 2 (2026-11-06): test_patch_machinery.py gained P2g (planted symlink), P2h (exec bit), P4d (.partial file) and P4e ([] receipt refused, --force named); reviewer mutants R1a2/R1b/R1d/R1e killed; the summary line is now SUMMARY pass=N fail=F skip=S and a skip-only result exits 77 with reason=artifact_not_yet_built so the runner reads SKIP (it used to read the old shape as ERROR unparsed_fail_signal). Round 3 (2026-11-06): P2i (planted directory symlink, reviewer X6) and P2j (retargeted shipped symlink, X7) added; P5 pins the skip contract (a forced P3b skip exits 77, counted line, reason=topology_unsupported); the reason code is now topology_unsupported, not artifact_not_yet_built (review I1-5/I1-6/I1-7); mutants N1a/N1b/N1c killed by scripts/codegraph/tests/test_patch_machinery_mutations.sh. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-108 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-116 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-116, re-minted as CON-146 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-146 (rounds 7-8), re-minted as CON-163 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-164 — CON-147 decided Option A: default runner patch set of fk_index_patch.py is the tested set fkidx1,resolve1,resolve2 (lockfix1, datafrag1 opt-in by name)

**Status:** In progress
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. P3 of scripts/codegraph/tests/test_patch_machinery.py expects runner_patches.load() with no ids to give fkidx1,resolve1,resolve2; the registry gives fkidx1,lockfix1,datafrag1,resolve1,resolve2. Not changed, by brief: the operator decides. Option A, make the registry default the tested subset (drop lockfix1 and datafrag1 from the default, keep them opt-in): matches the test, CLAUDE.md §11.4.78 note (untested patches excluded) and codegraph_safe.sh (default fkidx1,resolve1); consequence: a bare fk_index_patch.py run builds a different runner key, and on the installed 1.6.2 it would stop refusing (measured 2026-11-05: the five-patch default refuses with 'datafrag1: anchor const MAX_FILE_SIZE occurs 0x'). Option B, keep five and change P3 to expect five: the test then pins a default that includes two patches with no behavioural test and that refuses on 1.6.2. Until decided, the test stays RED on P3 only. Decision (operator, AskUserQuestion 2026-11-05 21:50 CET, relayed by the conductor): Option A. Implemented in the fix vehicle, second commit: runner_patches/__init__.py adds UNTESTED={lockfix1,datafrag1} and DEFAULT_EXCLUDED=OPT_IN|UNTESTED, so load() with no ids gives fkidx1,resolve1,resolve2; lockfix1/datafrag1 stay selectable by name. test_patch_machinery.py gains P3b (bare run on the real installed package must build <ver>-fkidx1-resolve1-resolve2; SKIP artifact_not_yet_built when the package cannot be resolved) and P3c (opt-in by name). RED: fails=2 P3 P3b; GREEN: fails=0; bare run on 1.6.2 went from REFUSED (datafrag1 anchor) to CREATED 1.6.2-fkidx1-resolve1-resolve2. codegraph_safe.sh default unchanged (fkidx1,resolve1); its --patches all now means the tested default. Review (§11.4.142/§11.4.209) owed. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-109 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-117 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-117, re-minted as CON-147 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-147 (rounds 7-8), re-minted as CON-164 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-165 — test_resolve1.sh: R5 probe used a cpp ref the 1.6.2 vue resolver rejects; helper exit statuses were discarded (P5 ran test_resolve1_dump.py / _fixture.py alone)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. R5: CodeGraph 1.6.2 vue.resolve returns null for languages outside VUE_SCRIPT_LANGUAGES before scanning; the probe ref (language cpp) never reached the code. Fix: probe ref language javascript (tools/web/src/app.js) and R5 also requires vue_scan_1st > 0 (precondition reached). RED: ONLY=R5 bash scripts/codegraph/tests/test_resolve1.sh -> vue_resolve_ok=false FAIL; GREEN same command -> 1st=335 2nd=0 PASS; negative control DIST=<stock 1.6.2> -> 1st=335 2nd=335 FAIL; full file 7/7 PASS. Helpers: every test_resolve1_dump.py / test_resolve1_fixture.py call now consumes its status (|| t_bad DUMP/FIXTURE), so the runner's P5 model no longer plans them alone (discarded_members for codegraph drops from 6 to 4) without any manifest or excluded-lock change. Mutants: dump exits 3, fixture exits 4, probe back to cpp: all killed. Out of scope, still planned alone: test_bulk_classify_mutate.py, test_memfloor_mutate.py, test_resolve1_mutate.py, test_resolve2_mutate.py. Round 2 (2026-11-06): R5b adds a stale .vue subset case (a .vue file added after the first scan must be found after clearCaches); mutant R2a now dies on R5b. probe() no longer runs inside a command substitution, so its helper-exit t_bad is counted (mutant I5: cases=2 failed=1, was cases=1 uncounted). Id history (§11.4.214): minted in the full-suite fix vehicle as CON-110 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-118 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-118, re-minted as CON-148 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-148 (rounds 7-8), re-minted as CON-165 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-166 — test_unit_safe.sh U01-U46 read the host's real /proc/meminfo and df, so a busy or small host failed ~32 cases

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Fix: U01-U46 now run against a copy of the tooling with /proc/meminfo redirected to a fake file (64 GiB total, 48 GiB available) and a stub df (default 999999999999 bytes; CG_FAKE_DF_AVAIL per case), the U47-U63 mechanism, plus a control that fails HERMETIC if any meminfo read is not redirected. U17 keeps its low-disk condition: 200 GiB free, above the 60 GiB preflight floor and below the 400 GiB tripwire. Thread headroom stays real. RED (host MemAvailable 22 GiB, free disk 57 GB): SUMMARY cases=63 failed=33; GREEN same command: failed=3 (U28, U35, U59; see CON-150, CON-151). Mutants: drop the U17 df value -> U17 FAIL; drop the meminfo redirect -> HERMETIC FAIL + preflight FAILs; set U17 df above the tripwire -> U17 FAIL: all killed. Round 2 (2026-11-06): the stub df refuses any call other than -B1 --output=avail <existing path>, and new U64 runs the REAL df in the codegraph_safe.sh preflight and checks free_bytes against an independent df within 1 GiB; mutant U3a now dies on U01, U17 and U64. Round 3 (2026-11-06): U65, the stub df logs its argument and the preflight's df read must name the target (review I3-4); reviewer mutant N3b (df on HOME) is killed by U65 and survives U64. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-111 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-119 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-119, re-minted as CON-149 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-149 (rounds 7-8), re-minted as CON-166 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-167 — test_unit_safe.sh U28 and U35 fail intermittently under host load (newly visible once CON-149 removed the preflight failures)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Observed 2026-11-05 at host load ~30: full run U28 FAIL (r1=1 r2=1 r3=1) and U35 FAIL (rc=4, lock refused); ONLY=U28,U35 run twice: 1 of 2 runs U28 FAIL; ONLY=U28 alone 16 of 16 PASS. Root cause UNCONFIRMED (candidate classes: stub timing with --poll-s 1 under load, or a stub process of an earlier case still alive; not investigated). Acceptance: reproduce with the exact sequence, root cause, fix. Also observed 2026-11-05 (load about 37): U38 failed once inside the GOLD copy of test_bulk_classify_mutations.sh (d3 and d4 empty: the CG_SAFE_PATCHES=fkidx1 and --patches all runs never reached the stub patch tool), then passed in the full test_unit_safe.sh run and in the next GOLD rerun; U35 failed once in a full run and passed 3/3 alone. Root cause UNCONFIRMED. GOLD of test_bulk_classify_mutations.sh, three runs the same evening: FAIL (U38), PASS, FAIL (U36, ra=4 rb=4: both runs exited 4); a different case each time. In that change set the codegraph_safe.sh diff is comment-only, so the flake is not caused by it. Round 2 (2026-11-06): the reviewer also saw U20, U22 and U27 fail intermittently under load in the full run; they join this item (same unconfirmed root-cause classes). Not investigated in round 2. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-112 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-120 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-120, re-minted as CON-150 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-150 (rounds 7-8), re-minted as CON-167 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-168 — test_unit_safe.sh U59 fails when TMPDIR is deep: the r1 check greps the full source path the tool truncates to 200 characters

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. The tool echoes min_mem_avail_source through san (cut -c1-200); U59's r1 check has_txt 'config/index/writer_limits.yaml min_mem_avail_gib' is not compared through s200, so with a work dir longer than about 140 characters the suffix is cut and the case FAILs (seen with TMPDIR under the vehicle scratch area, 2026-11-05; the case's own helper s200 exists for exactly this). Not fixed in the fix vehicle (out of scope). Id history (§11.4.214): minted in the full-suite fix vehicle as CON-113 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-121 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-121, re-minted as CON-151 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-151 (rounds 7-8), re-minted as CON-168 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-169 — full-suite runner: a Go unit whose module dependency is not in the offline module cache was FAIL; now a named SKIP (closest reason code network_unreachable_external, flagged)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Before: the runner sets GOPROXY=off with the host GOMODCACHE, so a missing module made the unit FAIL rc_1 (scripts/doc_integrity with an empty cache). Fix: before each go-test unit the runner runs go mod download in the unit env; when it fails and every error line is 'module lookup disabled by GOPROXY=off', the unit is SKIP network_unreachable_external (verdict_source go-module-preflight) and the progress line names go_module_not_cached: <mod>@<ver> (first missing only) and the prepare command; any other failure is not reclassified. Guide gained a prepare step. FLAG for the operator: the §11.4.69 closed set has no code for 'dependency not in the offline cache'; network_unreachable_external is the closest true one. RED/GREEN (tests/test_run_full_suite.sh sections 22/22b, run as a slice): 3 FAIL -> 5/5 ok; mutants no-skip, any-error-is-missing, SKIP-as-PASS killed. Real unit: old runner + empty GOMODCACHE FAIL rc_1; new runner SKIP naming github.com/mattn/go-sqlite3@v1.14.48; new runner + prepared private cache PASS. A SKIP keeps the run PARTIAL-SKIPS (exit 6), never PASS-FULL. Round 2 (2026-11-06, after review NO-GO): the probe now runs go mod download -modfile=<scratch copy> on scratch copies of go.mod and go.sum, so the unit's own tree is never written (RV-G3, a committed module with GOSUMDB=off, used to leave m/go.sum and trip IDENTITY CHANGED); and a unit is SKIP only when every named module is also absent from GOMODCACHE/cache/download (a cached module with a go.sum gap gives the same Go message and now stays FAIL, RV-G1). Tests 22c: RV-G0/G1/G3 and a classifier table; RED 7/15, GREEN 15/15; mutants M1, M2, gR1 (all->any), M4, G1, G3 killed. Guide: fresh --out after preparing, typo fixed. Round 3 (structural, review round 2 G5/G7b): the go mod download preflight is removed; every Go unit runs and only its own go test output, under a closed grammar, can turn a FAIL into SKIP network_unreachable_external (verdict_source go-test-output). One fixture and one paired mutant per axis in tests/test_run_full_suite_go.sh and tests/test_run_full_suite_go_mutations.sh. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-114 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-122 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2). Round 6: Operator decision on record (relayed by the conductor, verbatim, 2026-11-10): "Keep running rounds until GO is reached!"; it names the codegraph/full-suite items CON-122, CON-127 and CON-031 (by the ids of that day; CON-122 and CON-127 are re-minted since as CON-152 and CON-157) and authorises review round 6 under section 11.4.276(G).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-122, re-minted as CON-152 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Round 7 (2026-11-11, the last round §11.4.276(G) allows; authorised by the recorded operator decision "Keep running rounds until GO is reached!", relayed 2026-11-10, which named this item as CON-122/CON-127 by the ids of that day): review round 6 NO-GO on CR6-1 (C3 over a bounded sample survived). Fixed in the tests: L11b row count (10 000 foreign rows, ATM-5 last, want run; a sample larger than the fixture is out of scope and stated in the leg table); all 12 reviewer mutants RV6-1..RV6-12 adopted verbatim, RED first (9 of 12 survived the round-6 suite), then all 12 killed; L17b, L18 quoted path, L19 view, L20 empty string, L21 BLOB, L22 stdout contract, L23 stderr silence, L14 read-only shim and WAL side files. The class is closed by a scripted single-edit sweep embedded in test_consumer_required_mutations.sh (--sweep; the cheap coverage/stale check runs on every run): 144 mutants over every SQL clause, shell test, grep, redirection and exit code, 0 uncovered sites, 125 killed, 19 registered equivalents with proofs in scripts/fastcycle/tests/consumer_required_equivalents.tsv. The round-6 equivalence claims for trim(k) in C2 and -readonly dropped are withdrawn (both now killed). The helper's code is unchanged; only its header comment was corrected.

Round 8 (2026-11-11): operator decision on record (relayed by the conductor, verbatim, 2026-11-11, section 11.4.276(E)(3)/(G)): "Authorise round 8". It names this item (the codegraph/full-suite vehicle, CON-152/CON-157/CON-031 line) and is scoped to the review round 7 findings CR7-1..CR7-4 and N7-1..N7-4.

Round 8 work: CR7-1 L26 WAL fixture (ATM-5 committed only in the uncheckpointed -wal, built by copying db + -wal while the writer is open; want run) with reviewer mutants RV7-4 (immutable=1) and RV7-11 (nolock=1) adopted verbatim; CR7-2 registry row from-items-sample.2 removed (not equivalent when items has a column named k) and pinned by L27 l27_kcol.db; CR7-3 the runner guide again states the two CON-047 rows of config/full_suite_known_failures.tsv (signature reason:rc_3+tracked); CR7-4 the sweep gains a param operator class (19 sites: parameter expansions, shift and argument count, relative-path root, SQL quoting of an id, db-path quoting, unset) and its bound is stated; RV7-7 (L28 path ending in a newline) and RV7-10 (L29 [:upper:] in UTF-8 locales) pinned as hand mutants; L22b and S7b pin the SKIP line and the usage messages; N7-1 citation fixed, N7-2 per-run sweep timeout (FC_SWEEP_TIMEOUT) and --sweep stated as on-demand, N7-3 case-alt.0 proof corrected, N7-4 IFS bound documented in the helper. RED: on the round-7 suite (309/0) RV7-4, RV7-7, RV7-10 and CR7-2 SURVIVED, RV7-11 was killed. GREEN: hand table 42/42 killed; sweep 169 mutants, 0 uncovered, 3 new param survivors registered with proofs (21 rows). The helper code is unchanged (comment only). Not claimed GO; an independent review follows.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-152 (rounds 7-8), re-minted as CON-169 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-170 — fk_index_patch.py fkidx1 counts LIST_RE matches, not list openers: a commented opener before the real list merges into one match (review I1-2)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Found by the round-1 review (nit, source), not fixed in round 2. A commented line '// static BULK_PARSE_INDEX_NAMES = [' with no closer placed before the real list merges with it into one LIST_RE match, so the exactly-once check passes; the reviewer's shape A still edits the real list, shape B refuses later. Acceptance: count list openers, RED test with the commented-opener shape, paired mutation. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-115 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-123 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-123, re-minted as CON-153 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-153 (rounds 7-8), re-minted as CON-170 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-171 — fk_index_patch.py REUSED path removes <dst>.partial without a lock; a concurrent --force build of the same key could lose its .partial (review I1-3)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Found by the round-1 review (nit, source). The force build then fails loudly; the live runner is not corrupted. UNCONFIRMED: whether this race is reachable through codegraph_safe.sh (which serialises writers). Acceptance: reproduce or show unreachable with evidence, then fix or close. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-116 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-124 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-124, re-minted as CON-154 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-154 (rounds 7-8), re-minted as CON-171 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-172 — Operator question: should the codegraph_safe.sh writer default (fkidx1,resolve1) follow the CON-147 Option A runner default (fkidx1,resolve1,resolve2)? (review I6-2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. The round-1 review asked whether Option A covers the writer default; UNCONFIRMED. The default stays fkidx1,resolve1 until a recorded operator decision (section 11.4.66). Round 2 only fixed the comment wording at codegraph_safe.sh line 44. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-117 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-125 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-125, re-minted as CON-155 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-155 (rounds 7-8), re-minted as CON-172 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-173 — full-suite runner Go units are not fully offline: with GOPROXY=off and no GOSUMDB, a partial go.sum made Go contact sum.golang.org (review observation)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Pre-existing, observed by the round-1 review: the 404 text from sum.golang.org was returned, so the unit environment can reach the network. The CON-152 go mod download preflight inherits the same environment and so has the same property. Also UNCONFIRMED: the end-to-end behaviour of the classifier on real mixed Go error output (the all-versus-any mutant gR1 is killed only by the classifier table). Acceptance: decide GOSUMDB/GOFLAGS for go-test units (for example GOSUMDB=off or GONOSUMDB plus GOFLAGS=-mod=mod), test with a network-blocked run. Round 3: the classifier reads GOPROXY and GOFLAGS from the environment the unit really ran with; a host GOPROXY=file:// or GOSUMDB is replaced by the unit env (fixtures A5x, A3). Id history (§11.4.214): minted in the full-suite fix vehicle as CON-118 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-126 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2). Round 4 (review round 3 G3-2): the guide row and the 'nothing is written' claim are corrected (host GOSUMDB/GONOSUMDB are not passed; --env-extra GOSUMDB/GONOSUMDB reaches the unit, and a workspace without a checksum then makes Go write go.work.sum into the repository under test, which the identity guard stops). Still open: either reject GOSUMDB/GONOSUMDB/GONOSUMCHECK/GOFLAGS/GOPROXY in --env-extra for go-test units, or keep the documented caveat; and the source comment at scripts/full_suite/run_full_suite.py near line 2726 ('with network the same unit passes') holds only for modules the public checksum database knows (UNCONFIRMED for a private module).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-126, re-minted as CON-156 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-156 (rounds 7-8), re-minted as CON-173 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-174 — fastcycle tests: test_check_deps.sh signal race and cost; test_cycle_report_red/s12 FAIL in canon and give empty mutation kills on a red baseline

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Found by the round-1 review of the full-suite fixes. (1) test_check_deps.sh raced against a marker the tool itself carries (r6b TERM/HUP/INT failed at HEAD, 750 s under load) and built 3402 PATH shims 17 times; check_deps.sh ran its timeout self-probe before its traps, so a signal then gave 143 or 4 instead of 2. (2) test_cycle_report_red.sh and test_cycle_report_s12_fix_red.sh read the consumer tracker DB and named ATM items, so in canon or a consumer without those items they FAILed (HEAD: rc=1, 15 and 31 NOT ok, 1034 s and 1163 s); the red file's R5 block then counted 51 mutant kills against that red baseline; s12 check 8 re-ran the whole red suite. Round 2: ready-file wait in a G7 git shim, shim template built once and copied, self-probe moved after the traps, consumer guard (fc_require_consumer docs/workable_items.db plus a content check on the ATM items, SKIP 77 topology_unsupported), R5 block reports BLIND when the baseline failed, check 8 behind FC_S12_NESTED_RED=1. Round 3: the cycle_report guard moved into fc_require_items (lib/consumer_required.sh): SKIP only on proven absence, both atm_id and ticket_id, a lost item or a query error never SKIPs (review CR-1/CR-3, mutants MG1..MG6); s12 prints a counted SUMMARY naming the skipped check 8 (C2-2); the self-probe signal loop checks for survivors (C2-1, N7b); the signal-window flake C2-3 stays UNCONFIRMED, a FAIL now prints its timing. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-119 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-127 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2). Round 4 (review round 3 CD3-1, recurrence of the flaky-under-load class now CONFIRMED): in the round-3 review run test_check_deps.sh failed once with an empty result for the 'r6-f1/f2/r7 signal window (deps, postwait)' check (signal windows 172 s, load average 19.6 on 16 CPUs; the load was partly the reviewer's own parallel run). The rig prints a RESULT line when it completes, so an empty result means the rig did not finish its protocol, not that check_deps.sh gave a wrong verdict; that reading is UNCONFIRMED. Acceptance: give the window its own measured, bounded wait so a slow rig reports BLIND or SKIP with its timing instead of FAIL, and track the test under §11.4.248 until stable. Round 4 (review round 3 CR3-1, CR3-2): fc_require_items now has fixtures and paired mutants for a data query that errors after the pragma answered (view failing at step time; MG7 = reviewer RMG-A) and for no sqlite3 on PATH (MG8 = RMG-B), and examines both atm_id and ticket_id when both exist (MG9). RED: with the round-3 test file MG7 and MG8 SURVIVE; GREEN: all 9 mutants killed. Round 6 (review round 5 CR5-1, important; CR5-2..CR5-4, minor): fc_require_items gains a leg per remaining input axis, L11 rows (multiplicity and position: a foreign row first, the prefixed row later), L12 the dash of the prefix, L13 column names (exact and case), L14 no write (an absent path stays absent), L15 case of ids, L16 NULL ids (current behaviour pinned), L17 whitespace and other tables; each with fixtures and a paired mutant MG16..MG25 (reviewer RV5-1, RV5-1b, RV5-3, RV5-4, RV5-5 verbatim as MG16..MG20; R4-G as MG21, R4-I as MG23). RED: on the round-5 suite MG16, MG18..MG25 SURVIVE and MG17 dies only through m2_half; GREEN: all killed. Operator decision on record (relayed by the conductor, verbatim, 2026-11-10): "Keep running rounds until GO is reached!"; it names the codegraph/full-suite items CON-122, CON-127 and CON-031 (by the ids of that day; CON-122 and CON-127 are re-minted since as CON-152 and CON-157) and authorises review round 6 under section 11.4.276(G).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-127, re-minted as CON-157 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Round 7 (2026-11-11, the last round §11.4.276(G) allows; authorised by the recorded operator decision "Keep running rounds until GO is reached!", relayed 2026-11-10, which named this item as CON-122/CON-127 by the ids of that day): review round 6 NO-GO on CR6-1 (C3 over a bounded sample survived). Fixed in the tests: L11b row count (10 000 foreign rows, ATM-5 last, want run; a sample larger than the fixture is out of scope and stated in the leg table); all 12 reviewer mutants RV6-1..RV6-12 adopted verbatim, RED first (9 of 12 survived the round-6 suite), then all 12 killed; L17b, L18 quoted path, L19 view, L20 empty string, L21 BLOB, L22 stdout contract, L23 stderr silence, L14 read-only shim and WAL side files. The class is closed by a scripted single-edit sweep embedded in test_consumer_required_mutations.sh (--sweep; the cheap coverage/stale check runs on every run): 144 mutants over every SQL clause, shell test, grep, redirection and exit code, 0 uncovered sites, 125 killed, 19 registered equivalents with proofs in scripts/fastcycle/tests/consumer_required_equivalents.tsv. The round-6 equivalence claims for trim(k) in C2 and -readonly dropped are withdrawn (both now killed). The helper's code is unchanged; only its header comment was corrected.

Round 8 (2026-11-11): operator decision on record (relayed by the conductor, verbatim, 2026-11-11, section 11.4.276(E)(3)/(G)): "Authorise round 8". It names this item (the codegraph/full-suite vehicle, CON-152/CON-157/CON-031 line) and is scoped to the review round 7 findings CR7-1..CR7-4 and N7-1..N7-4.

Round 8 work: CR7-1 L26 WAL fixture (ATM-5 committed only in the uncheckpointed -wal, built by copying db + -wal while the writer is open; want run) with reviewer mutants RV7-4 (immutable=1) and RV7-11 (nolock=1) adopted verbatim; CR7-2 registry row from-items-sample.2 removed (not equivalent when items has a column named k) and pinned by L27 l27_kcol.db; CR7-3 the runner guide again states the two CON-047 rows of config/full_suite_known_failures.tsv (signature reason:rc_3+tracked); CR7-4 the sweep gains a param operator class (19 sites: parameter expansions, shift and argument count, relative-path root, SQL quoting of an id, db-path quoting, unset) and its bound is stated; RV7-7 (L28 path ending in a newline) and RV7-10 (L29 [:upper:] in UTF-8 locales) pinned as hand mutants; L22b and S7b pin the SKIP line and the usage messages; N7-1 citation fixed, N7-2 per-run sweep timeout (FC_SWEEP_TIMEOUT) and --sweep stated as on-demand, N7-3 case-alt.0 proof corrected, N7-4 IFS bound documented in the helper. RED: on the round-7 suite (309/0) RV7-4, RV7-7, RV7-10 and CR7-2 SURVIVED, RV7-11 was killed. GREEN: hand table 42/42 killed; sweep 169 mutants, 0 uncovered, 3 new param survivors registered with proofs (21 rows). The helper code is unchanged (comment only). Not claimed GO; an independent review follows.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-157 (rounds 7-8), re-minted as CON-174 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-175 — full-suite runner Go units: a go.sum with only the zip line plus an empty module cache hides the go.sum gap (SKIP where a full cache gives FAIL)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Measured with Go 1.26.8 under GOPROXY=off GOFLAGS=-mod=readonly (fixture A4, tests/test_run_full_suite_go.sh): when go.sum carries a module's zip hash but not its /go.mod line and the module is not cached, go test stops at the lookup-disabled line, so the runner records SKIP network_unreachable_external; with the module cached the same tree fails with missing go.sum entry. The repository defect is therefore visible only on a host with a full cache. Honest limit of classifying from go test output; a fix would need a go.sum completeness check that does not predict network needs (review round 2 axis cached-with-go.sum-gap). Round 4 (review round 3 G3-1): the limit is general, not specific to the go.sum shape. A SKIP network_unreachable_external means 'could not be decided offline'; any defect that Go would only see AFTER fetching the module is hidden behind it until the cache is prepared. Measured instances: untidy go.mod (R3a), a non-existent package in an uncached module (R4e), a tampered zip hash (R7e), a version that does not exist upstream (R12): all SKIP offline and would FAIL once fetched. Acceptance: the guide states the general limit (not one shape); the SKIP stays honest (never a PASS).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-128, re-minted as CON-158 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-158 (rounds 7-8), re-minted as CON-175 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-176 — fastcycle tests: patch-machinery whole-tree manifest does not pin the launcher bin/codegraph content (reviewer mutant RP3 survives)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 PM3-1 (test-instrumentation, minor). The reviewer's mutant RP3 removes the launcher bin/codegraph from the whole-tree manifest (the condition 'rel in (RECEIPT_NAME, "bin/codegraph")') and survives test_patch_machinery_mutations.sh (22 pass, 0 fail): no case changes the launcher's content while keeping it executable (P2d only deletes it). Acceptance: add a case that truncates or rewrites the launcher and expects CREATED, and adopt RP3 as a paired mutant. Evidence: scratchpad rev_cgs3/ev/pm_RP3.txt in the review of round 3.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-129, re-minted as CON-159 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-159 (rounds 7-8), re-minted as CON-176 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-177 — fastcycle tests: U65 reads only the first logged df path, so a df on the target followed by a df on HOME survives (reviewer mutant N3c)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 US3-1 (test-instrumentation, minor). The reviewer's mutant N3c calls df on the target first, discards it, then reads the value from df on $HOME; U64 and U65 both still pass because U65 reads only the first logged path and the stub prints the same value for every path. Acceptance: assert the df log holds exactly one line equal to the target, or make the stub print a value that depends on the path and check free_bytes; adopt N3c as a paired mutant.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-130, re-minted as CON-160 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-160 (rounds 7-8), re-minted as CON-177 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-178 — fc_require_items residual nits: NULL-id rows count as items present, LIKE is case-insensitive, a foreign register with any ATM-* row runs the checks

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 CR3-3, CR3-4, CR3-5 (nits). CR3-3: rows whose id is NULL count as items present (fixture v6 SKIPs); the real schema has atm_id NOT NULL; COUNT(key) would close it (reviewer mutant RMG-H). CR3-4: LIKE is case-insensitive, so atm-* ids count as the prefix (fail-closed direction: the checks run); no fixture pins the dash in 'ATM-%' (RMG-G). CR3-5: a foreign register that holds any ATM-* row runs the checks and FAILs; the helper header now says so (done in round 4). Acceptance: decide CR3-3/CR3-4, adopt RMG-G and RMG-H as mutants with fixtures v5 and v6, or record them as equivalent with the reason. Round 5: review round 4 recorded reviewer mutants R4-G (LIKE to GLOB, the CR3-4 direction, fixture v3) and R4-I (items counted as non-NULL keys, the CR3-3 direction, fixture v6); the author adopted them as the pins of these two nits in test_consumer_required_mutations.sh. Naming: RMG-G (round 3, the dash dropped from 'ATM-%') and R4-G (round 4, LIKE to GLOB) are two different mutants. Round 6 (review round 5 N5-1, CR5-4): the dash is pinned (fixture l12_atmx, mutant MG18 = RV5-3 = RMG-G); R4-G is adopted as MG21 (fixture l15_lower: atm-5 runs the checks, the current fail-closed direction) and R4-I as MG23 (fixture l16_nullonly: a table of NULL ids SKIPs, the current behaviour). Both pins hold the CURRENT behaviour; the CR3-3 direction (should NULL-only ids run the checks?) remains this item's decision, and changing it means flipping l16_nullonly together with MG23.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-131, re-minted as CON-161 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Round 7 (review round 6 N6-2, CR6-2, CR6-5): three more pins hold the CURRENT, non-conservative direction (section 11.4.201(4)) and are registered here as open directions, like L16: L17 (fixture l17_lead: an id with a leading space, ' ATM-5', is not the prefix, the register SKIPs), L17b (fixture l17b_lead953: the named id with a leading space, ' ATM-953', SKIPs; paired mutant RV6-7 = trim(k) IN in C2, which runs the checks) and L20 (fixture l20_emptystr: a table of empty-string ids only SKIPs, like NULL ids in L16; paired mutant RV6-6). Changing any of these directions means flipping the fixture's want together with its paired mutant. The round-6 claim that trim(k) in C2 is equivalent was false (review round 6 CR6-2) and is withdrawn.

Round 8 (review round 7 N7-4, recorded open direction): with a caller IFS that lacks a space (IFS=, or empty) fc_require_items never SKIPs (the counts arrive as one field; the checks run and FAIL on a foreign register: fail-closed). Measured by the reviewer, now documented in the helper header; not changed (no caller sets such an IFS). Whether the helper should set IFS locally is this item's decision.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-161 (rounds 7-8), re-minted as CON-178 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-179 — full-suite runner Go classifier nits: file paths with a space give a false FAIL; the mutation harness decodes anchors with unicode_escape and prints DeprecationWarning

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 G3-4 and G3-5 (nits). G3-4 (source-defect, fail-closed): GO_NET_LINE requires the file part to match [^\s:]+\.go, so a Go file path containing a space gives a false FAIL, never a false SKIP. G3-5 (test-instrumentation): tests/test_run_full_suite_go_mutations.sh decodes anchors with unicode_escape; regex anchors with backslash-dot and backslash-s print three DeprecationWarning lines, and a future Python that rejects them would turn those mutants into BAD. Acceptance: decide G3-4; replace the decoder (for example a literal-backslash-safe decode).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-132, re-minted as CON-162 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-162 (rounds 7-8), re-minted as CON-179 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-180 — status of items fixed in the full-suite vehicle must be set at landing (CON-146, CON-149, CON-152 and others stay Queued)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 D3-2 (process-doc, nit). Items whose fix is in the full-suite vehicle (for example CON-146, CON-149, CON-152) stay Queued in the vehicle. At landing they need the §11.4.290 status (Ready for testing with a Verification line), not Queued. Acceptance: at the landing step, set the status of each fixed item through the engine and re-export the trackers.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-133, re-minted as CON-163 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-163 (rounds 7-8), re-minted as CON-180 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-181 — cycle_report s12 wrapper: the temp copy of stdout is not removed when the outer process is killed (no trap)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 3 note, registered in round 5 (review round 4 item 4, unregistered nit). The s12 wrapper of the cycle_report suite writes a temp copy of stdout and removes it only on a normal exit; a SIGTERM or SIGKILL of the outer process leaves the file behind under the temp root. Type test-instrumentation, fail-safe (no verdict changes). Acceptance: add an EXIT/INT/TERM trap that removes the copy through safe_rm_rf or a ${VAR:?}-guarded rm, with a test that kills the wrapper and checks no copy is left.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-134, re-minted as CON-164 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-164 (rounds 7-8), re-minted as CON-181 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-182 — full-suite vehicle merge messages must say how a census conflict was resolved

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

Parent: CON-031. Review round 4 item 5, unregistered nit (process-doc). The round-4 merge 97be3740 of main 90efceb8 resolved a conflict in the census line of docs/guides/full_suite_runner_guide.md by regenerating it, but the merge message does not say so. Acceptance: every merge of main into the vehicle that touches the generated census states in its message that the census was regenerated with run_full_suite.sh --sync-guide and checked with --verify-manifest, naming the resulting total.

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-135, re-minted as CON-165 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-165 (rounds 7-8), re-minted as CON-182 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

## CON-183 — Mutation harness cannot see Part 4: test_consumer_required_helper.sh skips Part 4 when FC_HELPER_UNDER_TEST is set, so a mutant only Part 4 kills is reported survived (review round 8 R8-1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-178 (fc_require_items). Review round 8 R8-1. test_consumer_required_helper.sh skips Part 4 when FC_HELPER_UNDER_TEST is set (test_consumer_required_helper.sh:600 at vehicle head 4118f145), and both the sweep and the hand table set it, so a mutant that only the Part 4 legs kill is reported as survived. The reviewer's mutant M4 ($(cd "$(dirname -> $(cd -P "$(dirname) survives 338/0 through the harness path, while the same edit in the real helper fails Part 4 nine times (342/9). Acceptance: run Part 4 against the mutant (link the mutant into the scratch consumer layout instead of the checkout's helper), or state this bound beside the sweep's claim; then adopt M4 as a paired mutant. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (§11.4.290).

## CON-184 — fc_require_items id contract: a lowercase letter inside the prefix (AtM-5) is a usage error but no fixture asserts it; mutant M3 [[:alnum:]] survives (review round 8 R8-3)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con184_reproduction_2026_11_11.txt` — red-command `bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON184-M3 (against the helper test without the AtM-5 leg)` — green-command `same command on the fixed helper test` — env `main fc57ad0c; Linux 7.0.0, bash 5.3.9, dash` — signature `SURVIVED CON184-M3 (rc 0, 0 NOT ok lines)` — updated 2026-11-11T12:31:16Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`
**Investigation:** root-cause-found-with-evidence — root-cause `the id contract check has no fixture for a lowercase letter inside the prefix, so the [:alnum:] mutant is not observable` — evidence `docs/qa/con184_reproduction_2026_11_11.txt` — updated 2026-11-11T12:31:16Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`

Parent: CON-178 (fc_require_items). Review round 8 R8-3. The id contract [A-Z][A-Z0-9]*-[0-9]+ is not fully pinned: the reviewer's mutant M3 changes the rest-of-prefix class *[!A-Z0-9]* to *[![:alnum:]]* and survives 338/0; on a foreign register the id AtM-5 exits 2 (usage error) on head and SKIPs 77 under M3, in bash and dash. Acceptance: add AtM-5 (and, for example, A_B-1) to the S7 or S7b usage-error list, and adopt M3 as a paired mutant. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (§11.4.290).

Fix note (follow-up fu_b, 2026-11-11): the S7b usage-error list of scripts/fastcycle/tests/test_consumer_required_helper.sh now also asserts AtM-5 and A_B-1 (exit 2 and the exact message, bash and dash), and the hand table of test_consumer_required_mutations.sh adopts the reviewer mutant M3 as CON184-M3 (the helper test: 355 pass / 0 fail). Class sweep: the id-contract classes first character, rest of prefix, number part were already pinned except the lowercase-inside-prefix class; the sweep generated-mutant check is unchanged.

**Verification:** provisional (section 11.4.290) -- job: re-run bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON184-M3 (expect killed) and bash scripts/fastcycle/tests/test_consumer_required_helper.sh (expect 0 fail) on main after landing -- checks: M3 killed by the AtM-5 leg -- layer: gate-logic (test-instrumentation; class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit that lands the fu_b CON-184 change -- due: next full-suite run.

## CON-185 — L29 calls bad, not SKIP-with-reason, on a host with no UTF-8 locale that classes A-umlaut as [:upper:] (review round 8 N8-1)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con185_reproduction_2026_11_11.txt` — red-command `bash <copy of test_consumer_required_helper.sh with the L29 candidate list set to zz_ZZ.UTF-8>` — green-command `FC_L29_CANDIDATES=zz_ZZ.UTF-8 bash scripts/fastcycle/tests/test_consumer_required_helper.sh` — env `host fixture: simulated no-locale host; Linux 7.0.0, bash 5.3.9` — signature `NOT ok L29: no UTF-8 locale classes A-umlaut as upper; the leg cannot run (rc 1)` — updated 2026-11-11T12:40:32Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`
**Investigation:** root-cause-found-with-evidence — root-cause `leg L29 reported a missing locale class as bad() instead of a SKIP-with-reason` — evidence `docs/qa/con185_reproduction_2026_11_11.txt` — updated 2026-11-11T12:40:32Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`

Parent: CON-178 (fc_require_items). Review round 8 N8-1 (nit). Leg L29 of test_consumer_required_helper.sh calls bad when the host classes no listed UTF-8 locale's A-umlaut as [:upper:], so a host without such a locale FAILs the whole helper suite when only that leg lacks topology. Acceptance: that leg records a §11.4.3 SKIP-with-reason naming the missing locale class instead of a FAIL, with a test that proves both branches. On the review host the locales are present, so the leg ran. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (§11.4.290).

Fix note (follow-up fu_b, 2026-11-11): leg L29 of scripts/fastcycle/tests/test_consumer_required_helper.sh now prints a section 11.4.3 SKIP-with-reason line (reason=topology_unsupported) and does not count a failure when no listed locale classes A-umlaut as upper; both branches are proven on every run (the empty-list branch with a locale name no host has, the other with the host list), and FC_L29_CANDIDATES lets a test simulate such a host. Helper test on this host: 356 pass / 0 fail; simulated host: 347 pass / 0 fail with the SKIP line; paired mutant (SKIP line made a NOT ok) killed.

**Verification:** provisional (section 11.4.290) -- job: re-run bash scripts/fastcycle/tests/test_consumer_required_helper.sh and FC_L29_CANDIDATES=zz_ZZ.UTF-8 bash scripts/fastcycle/tests/test_consumer_required_helper.sh on main after landing -- checks: rc 0 both, the second prints the L29 SKIP line -- layer: gate-logic (test-instrumentation; class floor: runtime for a test item) -- target: host, repo checkout; a real host without locales is UNCONFIRMED (not available) -- artifact: commit that lands the fu_b CON-185 change -- due: next full-suite run.

## CON-186 — fixu landing review follow-ups M1, M2, M3: case 11c closure-by-location, runner guide acceptance wording, tracked resolve1 proposal

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-116..CON-145 fixu landing (3bd34494, e6b16598, 2e8cfb90). Source: independent review docs/qa/fixu_review/landing/review_fixu_landing.md (GO-with-follow-ups, 0 critical, 0 important, 4 minor, 2 nit). M1: tests/test_run_full_suite.sh case 11c now also puts an Obsolete and a Completed item located in Fixed in the fixture and asserts both are named STALE; mutant X1 (check_known_open deciding closure from a status text starting with Fixed) survived the old fixture and fails exactly those 2 new assertions (274 passed, 2 failed). M2: docs/guides/full_suite_runner_guide.md no longer says an agent never runs the acceptance; it states that the runner enforces only that the id is on the committed roster and that the acceptances so far (2739c26b, bdc3ac43, e6b16598) were run by the landing agent on a conductor-relayed order, tier instance. M3: the cited proposal resolve1_lock_PROPOSAL_r2.md was recovered from a scratchpad and is now tracked as docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md (section 11.4.215). Finding layer: test-instrumentation and process-doc, minor-class under section 11.4.276(G.2). Fixes are in the change that registers this item and are not verified by an independent review: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290).

## CON-187 — CON-099 reached GO-with-follow-ups at round 3 with no section 11.4.276(E) convergence assessment recorded (fixu landing review M4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-099. Source: docs/qa/fixu_review/landing/review_fixu_landing.md M4 (minor, process). Round 3 of CON-099 ended GO-with-follow-ups without the round-3 convergence assessment of section 11.4.276(E). The assessment is NOT written here: UNKNOWN: the author's round-3 assessment inputs (class-sharing findings, reappearing findings, wrong-layer evidence) are not recoverable from the tracker text alone, and inventing one would be a section 11.4.6 fabrication. Acceptance: before CON-099 round 4 the fixer records the assessment (or records why none was needed) in CON-099. Finding layer: process-doc, minor-class under section 11.4.276(G.2). Status Queued; no fix claimed (section 11.4.290).

## CON-188 — fixu landing review notes N1 and N2: no CHANGELOG entry for the landing; main red on the env-reads allowlist gate until CON-144

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-116..CON-145 fixu landing. Source: docs/qa/fixu_review/landing/review_fixu_landing.md N1, N2 (nits, recorded as notes). N1: the landing (162 files) has no CHANGELOG entry; UNCONFIRMED whether the project expects one for a fix landing; the lander decides. N2: main stays red on CM-GATE-ENV-READS-ALLOWLISTED and the census closure test after the landing, as before it; it is tracked as CON-144 (medium) and should be fixed soon because a red gate hides a new failure of the same gate. Nothing is changed by this item. Finding layer: process-doc, minor-class under section 11.4.276(G.2). Status Queued; no fix claimed (section 11.4.290).

## CON-189 — Case 11c pins no unknown-id-only stale row: reviewer mutant Y3 (drop stale += 1 for an unknown id) survives (fixu follow-ups review F1, Y1 nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186. Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. F1 (minor, test-instrumentation): tests/test_run_full_suite.sh case 11c always pairs the unknown id with a closed one, so the exit code of check_known_open never proves that an unknown id alone counts as stale; reviewer mutant Y3 (remove stale += 1 in the r is None branch) survived 276 passed / 0 failed, and on a known table holding only ATM-77 it prints the STALE line and then RESULT: KNOWN-OPEN with rc 0. Pre-existing gap in the fixture M1 extended, not introduced by it. Acceptance: a --known table with only an unknown id, asserting rc 1 and RESULT: KNOWN-STALE, with Y3 adopted as a paired mutant that must fail the suite. Nit Y1: mutant elif r[1] == Fixed (any other location read as open) survived and is equivalent only because schema.sql closes current_location to Issues/Fixed while the test fixture DB has no such CHECK; optional fixture row with another location, or a note that the set is closed by the schema. Finding layer: test-instrumentation, minor-class under section 11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290).

## CON-190 — Runner guide acceptance paragraph: per-commit relay wording, unsupported instance label, stale 44-row opening, undersold enforcement (fixu follow-ups review F2, F3, N2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186 (M2). Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. F2 (minor, process-doc): docs/guides/full_suite_runner_guide.md says the acceptances 2739c26b, bdc3ac43 and e6b16598 were run by the landing agent on an order relayed by the conductor and that each commit message says so; bdc3ac43's message records an operator acceptance from a genuine user message (2026-11-05 20:41 CET) run by the landing agent on that order, not a conductor relay; only 2739c26b and e6b16598 say relayed by the conductor. Reword per commit. F3 (minor, process-doc): the guide calls the achieved separation instance, but in e6b16598 the same landing agent replaced the two manifest rows and ran the acceptance of that change, so under section 11.4.240(F) no separate verifier instance is shown; state what the record supports (change and acceptance by one agent, on a recorded operator order, with a roster id) or record why instance applies (this also corrects the earlier review M2 suggestion). N2 (nit): the same paragraph still opens with 44 excluded rows accepted as fsr-r4-author, while the lock now has 55 rows last accepted by i@mvasic.ru on 2026-11-10; and the sentence that the runner enforces only the rostered id undersells the other refusals (roster tracked, equal to HEAD, not a symlink; chain intact; no other manifest problem); the accurate point is that it checks the id, not who typed it. Finding layer: process-doc, minor-class under section 11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290).

## CON-191 — Tracked resolve1 proposal says not applied though e6b16598 applied it; CON-187 should cite the tracked round-3 inputs (fixu follow-ups review N3, N4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186 (M3), CON-187 (M4). Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. N3 (nit): docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md still says Status: PROPOSAL. Not applied in any tracked tree, but e6b16598 applied it; a one-line header note (applied in e6b16598, kept as the record under section 11.4.215) would stop it misleading. N4 (nit): CON-187 says the round-3 convergence-assessment inputs of CON-099 are not recoverable from the tracker text alone, but they are in tracked files: docs/qa/fixu_review/review_fixu_r3.md section 5 (F099-4 same carrier class as F099-2), section 6 (reviewer class inventory, line 433 the only open member) and the N099-6 note; CON-187 should cite them so the fixer can write the assessment from them. Finding layer: process-doc, minor-class under section 11.4.276(G.2). No fix is claimed: the item is Queued, its reproduction and investigation states are UNSET, and it is neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290).

## CON-192 — Census CLI gate_env_census.py crashes with a traceback on --help; reject unknown options with exit 64 and a test (CON-144 review F1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (lander subagent)

Parent: CON-144. Source: independent review of the CON-144 fix, GO-with-follow-ups. F1 (minor, test-instrumentation): scripts/gates/lib/gate_env_census.py has no argument validation; --help or any unknown option is treated as a file and dies with FileNotFoundError traceback. The gate wrapper is not affected (it builds argv itself). Acceptance: reject unknown options with a usage message and exit 64, with a test. Finding layer: test-instrumentation, minor-class under section 11.4.276(G.2). No fix is claimed: Queued, reproduction and investigation UNSET (section 11.4.290).

## CON-193 — Guard test_con144_blk_read_order.sh mutant M1 re-checks the census rather than mutating the gate under test (CON-144 review F3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (lander subagent)

Parent: CON-144. Source: independent review of the CON-144 fix, GO-with-follow-ups. F3 (nit, test-instrumentation): guard mutant M1 does not mutate the gate under test in the real tree; it re-proves the census sees the old text in a copy (overlaps N0). It is fail-closed, so not a bluff; checks C1/C2/C3 already kill a reintroduced read. Optional: relabel M1 as a census control in the header comment. Finding layer: test-instrumentation, nit. No fix is claimed: Queued, reproduction and investigation UNSET (section 11.4.290).

