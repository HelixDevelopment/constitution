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
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con030_review/con030_reproduction_2026_11_05.txt` — red-command `bash docs/qa/con030_review/con030_class_repro.sh <checkout at efe2cc6> <new dir>  (case 0: submodule path 'sub dir')` — green-command `bash docs/qa/con030_review/con030_class_repro.sh <checkout at f6567349> <new dir>  (case 0)` — env `host-only fixture: real git 2.53.0, python 3.14.4, engine scripts/full_suite/run_full_suite.py; record sha256 1520da66765645d83cfa3f82f09bedadaaeeddf7ac0106e6c5d0f23411d7ba9a` — signature `RED: rc=9 'TOPOLOGY: submodule sub: recorded commit ... is not in its object store' RESULT: REFUSED-TOPOLOGY for a clean checkout with submodule 'sub dir'; GREEN: rc=0 RESULT: PASS-FULL` — updated 2026-11-11T11:42:57Z — by `Claude Opus 5.5 (CON-030 round 7 fixer subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `sub_paths split the human-oriented 'git submodule status' line on whitespace, so the path 'sub dir' was read as 'sub' and topology looked for a non-existent submodule (decisive: same fixture without the space runs; with it refuses). Rounds 2-3 moved paths to 'git ls-files -s -z' and the quick identity to a structured QuickIdent. Round 4 (structural, review r3 H1 H2 H3) removes the remaining members of the same class found by the whole-engine enumeration: every governance file (manifest, known table, lock, roster) is read by one reader gov_lines() that splits on LF only, tolerates CRLF and refuses any other control or line-separator character by name (str.splitlines() had split on NEL/LS/CR, H2); the unit identity is the structured key (path, tuple(args)) end to end and plan() refuses duplicate keys and duplicate display ids (the joined 'path + space + args' uid collided, H1); every output line passes one escape function esc_out() and the census refuses control/line-separator names (raw CR forged output lines, H3). Class inventory: docs/qa/con030_review/con030_class_sweep_r4.py. Round 5 (review r4): the census markers of the guide are whole lines found structurally (K1, shape D of docs/qa/con030_review/con030_class_sweep_r5.py: a marker or delimiter found by substring); --sync-guide and --generate-manifest fail instead of reporting a write they did not do (K2, K12); esc_out decodes before it escapes (K3); --verify-manifest runs the plan check (K9).` — evidence `docs/qa/con030_review/con030_reproduction_2026_11_05.txt` — updated 2026-11-11T11:42:57Z — by `Claude Opus 5.5 (CON-030 round 7 fixer subagent)`

Review r6 follow-up 2: sub_paths splits the status line on whitespace, so a submodule path containing a space is truncated (probe E ended REFUSED-TOPOLOGY rc 9: fail-closed, cause not isolated). Latent: the real repository has none. Reproduce first (section 11.4.292), isolate the cause, then fix.

Source report(s) in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/: review_full_suite_runner_r6.md

Origin: independent-review follow-up, section 11.4.276(G.2).

**Affected scope / file-scope manifest:**
full-suite runner sub_paths


**Operator decision (section 11.4.276(E)(3)), recorded 2026-11-10, relayed verbatim by the conductor and naming this item:** "Keep running rounds until GO is reached!" CON-030 reached R_max at review round 4 (NO-GO); by this decision its review loop continues past R_max (round 5 onward) with the same bar: a zero-finding GO (section 11.4.134) on the section 11.4.209 substrate.

**Round history:** rounds 1-4 on vehicle/con030 (reviews in docs/qa/con030_review/); round 5 fixes review r4 K1-K12 and M1-M6, merges live main 90efceb8 and then live main 2e8cfb90 (K5) and re-mints the vehicle ids CON-108 -> CON-146 and CON-109 -> CON-147 (K6, section 11.4.214; the intermediate ids CON-116 and CON-117 of vehicle commit ede6686e are owned by other items on main 2e8cfb90 and are not used); K4 is registered as CON-148 (intermediate id CON-118 of ede6686e, owned on main 2e8cfb90 by another item). **Round 6 (review r5 NO-GO, 2026-11-11):** the standing operator decision of 2026-11-10 ("Keep running rounds until GO is reached!", section 11.4.276(E)(3), naming CON-030) covers round 6; the coordinator relayed it again with the review r5 verdict. Round 6 is structural for the guide-marker class (F1-F3): every marker-line shape and block shape is enumerated and each outcome pinned; F5 is registered as CON-149. The tracker of vehicle commit ede6686e uses CON-116, CON-117 and CON-118 for the items now numbered CON-146, CON-147 and CON-148; on main those three ids are other items (review r5 F11). **Id map (section 11.4.214), merge of live main 27dcf518 into vehicle/con030 (CON-030 round 6):** CON-146 -> CON-163, CON-147 -> CON-164, CON-148 -> CON-165, CON-149 -> CON-166. Main 27dcf518 owns CON-146 to CON-162 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id map (section 11.4.214), merge of live main 9cd7cacd into vehicle/con030 (CON-030 round 6):** CON-163 -> CON-186, CON-164 -> CON-187, CON-165 -> CON-188, CON-166 -> CON-189. Main 9cd7cacd owns CON-146 to CON-185 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id map (section 11.4.214), merge of live main 64ac151d into vehicle/con030 (CON-030 round 6):** CON-186 -> CON-192, CON-187 -> CON-193, CON-188 -> CON-194, CON-189 -> CON-195. Main 64ac151d owns CON-146 to CON-191 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id map (section 11.4.214), merge of live main fc57ad0c into vehicle/con030 (CON-030 round 7):** CON-192 -> CON-194, CON-193 -> CON-195, CON-194 -> CON-196, CON-195 -> CON-197. Main fc57ad0c owns CON-146 to CON-193 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 1: for this item and any vehicle that carries it, review rounds continue until GO; every round past R_max 5 is a STRUCTURAL round (fresh fixer instance, class-wide enumeration, re-derived ground truth); the GO bar is unchanged (section 11.4.276(E)(3) recorded decision naming this item).

**Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

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

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 1: for this item and any vehicle that carries it, review rounds continue until GO; every round past R_max 5 is a STRUCTURAL round (fresh fixer instance, class-wide enumeration, re-derived ground truth); the GO bar is unchanged (section 11.4.276(E)(3) recorded decision naming this item).

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 6: the agent may run 'bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <id>' for the excluded-lock rows after the reviewer's GO (relayed; mapping of the excluded-lock rows to this item's vehicle UNCONFIRMED). A fast-forward-only pull of the live checkout is authorised once landings settle and the live tree is clean.

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

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 1: for this item and any vehicle that carries it, review rounds continue until GO; every round past R_max 5 is a STRUCTURAL round (fresh fixer instance, class-wide enumeration, re-derived ground truth); the GO bar is unchanged (section 11.4.276(E)(3) recorded decision naming this item).

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 6: after this item has its GO and has landed, installing the pin-gate pre-commit hook in the live checkout is authorised (chmod +x scripts/hooks/pre-commit-submodule-pin-not-downgraded; ln -s ../../scripts/hooks/pre-commit-submodule-pin-not-downgraded .git/hooks/pre-commit). Not done by the record.

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

**Status:** In progress
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (author subagent, landed by Claude Sonnet 5.5)

Parent: CON-031 (manifest-triage vehicle). Id history (§11.4.214): minted in vehicle/manifest-triage as CON-100..CON-109 (CON-092 was CON-100, and so on in order), re-minted at landing because main already owns CON-064..CON-091. What: finding F3 of review round 1 of vehicle/manifest-triage (docs/qa/manifest_triage_review/review_manifest_triage_r1.md). The 24 fastcycle tests that source scripts/fastcycle/tests/lib/consumer_required.sh SKIP as a whole (exit 77) when consumer-project data is absent. Before the change they ran about 400 assertions that work on canon alone (for example consumer_audit 66 ok, catchset 67, plan_struct_causes 56, plan_struct_full 36, capture_triplet 25, escape_classify 23, limit_class 18, host_limits 17, alias_spread 15), and those assertions and their failures are now hidden. Scope: the 24 tests listed by 'grep -l consumer_required.sh scripts/fastcycle/tests/*.sh'. Reproduction: run any of them on canon alone; it prints one SKIP line and none of its canon-runnable checks. Acceptance: only the sections that read consumer data are skipped, each naming the effective path it reads; the canon-runnable sections run and report pass/fail; the runner records the remaining skips with reason=topology_unsupported.

## CON-093 — Nine more fastcycle tests fail on canon alone for missing consumer data, not converted (review F13)

**Status:** In progress
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

**Status:** In progress
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

Eleven fastcycle tests pass alone but fail in the batch (inventory class B)

Link (section 11.4.214, open original, link only; 2026-11-16; author follow-up CON-PENDING-2): measured on a fixed snapshot at load about 37, TIMEOUT at 240 s for test_baseline_replay_r2_findings.sh, test_collect_baseline_red.sh, test_consumer_migrate_red.sh, test_fastcycle_r6_mutations.sh, test_triple_harness_red.sh and test_fc_supervisor_v4r5 / v4r8 / v4r9; test_run_all.sh r7f2 / r7f3 signal cases failed at load about 37 and passed at about 19, on the vehicle tree and on unfixed main. Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

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

test_host_attribute_red.sh fails btrfs_binary_unavailable when the tool is absent (reported, not reproduced) (inventory class D)

Link (section 11.4.214, open original, link only; 2026-11-16): the fastcycle vehicle author saw test_host_attribute_red.sh fail with btrfs unavailable on this host again (CON-PENDING-3, linked on CON-264). Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

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

Follow-up fu_b (2026-11-11): mutant M1G (= reviewer M6) is now adopted as hand-table row CON102-M6 and killed by a spaced-path leg in Part 3b of scripts/fastcycle/tests/test_consumer_required_helper.sh (helper test 365/0 or see evidence docs/qa/con102_m6_2026_11_11.txt; RED survived, GREEN killed in bash and dash). Not claimed: M1A, M2A, M2C, M2D remain open, so this item stays Queued and nothing here is a fix claim for the whole item (section 11.4.290).

Review of the fu_b partial fix: independent Opus review, verdict GO for the M6 part (record docs/qa/review_fu_b_2026_11_11.md); this item stays Queued for M1A, M2A, M2C, M2D.

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

Env-read gate CM-GATE-ENV-READS-ALLOWLISTED fails on main: BLK read-before-assign in the PR-delivery and release-gate anchor-wired gates

Recurrence link (section 11.4.214, open original, link only; 2026-11-16): audit F5 found the gate red on main again: stale allowlist rows (cm_installer_no_push_no_force.sh HI_I, HI_U) since d0a6832f and uncovered cm_full_suite_manifest_complete.sh:146 XDG0 since 3281d92e. Symptoms repaired by 1c248515 (PR-0 v3); the landing seam (land_vehicle.sh publish step 6b runs the gate) landed with merge 6c743898; the pull-request path is CON-443. Related: CON-188. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d).

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

**Status:** In progress
**Type:** Bug
**Severity:** High
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con146_reproduction_2026_11_05.txt` — red-command `bash scripts/fastcycle/tests/test_custody_sweep_r11_regression.sh (also r13, r15, stash_patch_r22) on the pre-fix tool` — green-command `same commands on the fixed tool` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `NOT ok B2 stash golden-good: expected ALLOWED, got REFUSED (backup ... does NOT match the entry's freshly re-derived LIVE dirty content)` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `git 2.53.0 git stash show -p ignores the a/ b/ prefix options and emits run-varying header prefixes; git diff over the same two trees is correct` — evidence `docs/qa/con146_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-108 (rounds 1 to 3), then CON-116 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-146 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/orchestration/custody_sweep.py derived the stash patch (inventory hash and verify-proposal live hash) with git stash show -p <CANONICAL_PATCH_OPTS>. On git 2.53.0 that command ignores --src-prefix/--dst-prefix and prints headers that change on every run (diff --git f sf, diff --git f |f), so no backup can ever match and every stash land is REFUSED (fails closed, no data loss). Fix: derive with git diff <CANONICAL_PATCH_OPTS> <ref>^1 <ref>; self-check every diff --git header carries a/ b/ prefixes, else UNMEASURED (never hashed); tests r11, r13, r15 build their backups the same way; new guard scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh (host-independent via git shims, paired mutations M1-M3). Upstream git bug report: not filed (UNCONFIRMED whether fixed in a later git). Acceptance: r11, r13, r15 and the new guard GREEN on git 2.53.0; mutations caught. Fix round 2 (independent review round 1: NO-GO, findings F1-1 and F1-2): F1-1, git C-quotes each path on its own, so a header can mix a bare and a quoted path (diff --git a/c.txt "b/sp ace\ttab.txt"); the old header pattern refused that correct patch as UNMEASURED and the verify-proposal refusal named the wrong cause (git status/diff failed). The pattern now matches each side separately, ^diff --git (?:a/.*|"a/.*") (?:b/.*|"b/.*")$ (checked on 11 header shapes, still rejects f sf, f xf, c/x d/x, f |f), and the refusal names the real cause (the bad diff --git header, or the failed git diff with its rc) via stash_patch_bytes_why / unmeasured_why. F1-2, r22 gains a two-file mixed-quoting stash (G4, G5 GREEN), a shim that mangles only the SECOND header (B3, B4) and mutants M4 (reviewer R1g, check only the first header) and M5 (old pattern), both caught; r22 RED pass=15 fail=5 on the round-1 tool, GREEN pass=20 fail=0; r11, r13, r15 GREEN. Follow-up CON-157 (display-only file list). **Affected scope / file-scope manifest:** scripts/fastcycle/orchestration/custody_sweep.py; scripts/fastcycle/tests/test_custody_sweep_r11_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r13_regression.sh; scripts/fastcycle/tests/test_custody_sweep_r15_regression.sh; scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh; config/full_suite_manifest.tsv Fix round 3 (structural, independent review round 2 NO-GO, findings R2-F1-A/B/C; root-cause class: the guard's fixtures did not separate the mutants' axes): r22 now has a three-header stash (plain, mixed-quoting rename, plain) and a positional shim that garbles exactly the first, the middle, the last or every header, bare and as a quoted header with no prefixes (diff --git "f" "xf"); every mutant has named functional checks: M4 first-header-only, M5 old pattern, RV1 last-only, RV2 first-and-last, RV3 quoted headers trusted, RV4 loose pattern, RV5 rc cause dropped, RV6 first-two-only, all killed by their named checks (P1-P3, Q1-Q3, V2, V3, F1, G4, G5). R2-F1-B: F1 checks the refusal names 'git diff stash@{0}^1 stash@{0} failed (rc=3)'. R2-F1-C: the round-2 log said r22 RED pass=15 fail=5 on the round-1 tool; re-running that committed test gives pass=14 fail=6 (the reviewer's number), so the round-2 number was not reproducible; round-3 numbers are recorded with their commands in docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt. Old r22 (round 2) against the round-3 mutants: RV2, RV5, RV6 survive (rc 0); new r22: all 8 killed, GREEN pass=36 fail=0; the new r22 on the round-1 tool pass=24 fail=12, on the round-2 tool pass=33 fail=3 (G4, L1: the CON-157 file list). r6-r21 custody_sweep regressions rerun on the round-3 tool: same results as on the round-2 tool (r9 and custody_sweep_red fail identically on both, known and unrelated). Round 4 (review r22 NO-GO, recurrence 3 of the fixture class): the r22 test rebuilds its fixtures as a matrix over the whole class (header count 1..7, forward and reversed, three git configs, every header position, five garble forms, sections of type text-with-a-removed-line-that-looks-like-a-header, binary, new, empty new, deleted, mode-only, rename with tab and space name, copy, C-quoted) with an oracle independent of the tool (git diff -z --name-status), 527 cells; cases XS, XC, XB, XB1, XM, XG, XQ added; reviewer mutants NM1..NM13 adopted verbatim plus the FL1,3,4,5,6,7,8,9,10 set, each RED (survives the round-3 battery 24/0) then GREEN (killed by the new test); FL2 is equivalent and not adopted; result pass=81 fail=0, 34 mutation self-tests. Evidence: scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh. Round 5 (review of fsfix4 NO-GO, F2 and F3): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). The r22 matrix removed none of its mkdtemp repositories (measured on the round-4 test: one matrix.* dir per matrix run left under TMPDIR; the review measured 35 dirs, 168 MB per full run); the matrix now removes its base at exit and runs with its own TMPDIR, check MX fails on any leftover, and the whole test runs with TMPDIR under its own temp dir (check TD). An empty stash patch is now pinned: EP1 (untracked-only git stash -u) and EP2 (index-only change) give empty_patch, never UNMEASURED; EP1V: land of an untracked-only stash is refused for its untracked content, not as unreadable. Reviewer mutant RD adopted verbatim, RED (survives the round-4 test, pass=47 fail=1 with RD as a self-test) then killed by EP1/EP2; live-path twin RD2 killed by EP1V. Result pass=88 fail=0, nothing left under TMPDIR. Not changed, recorded: land of an index-only stash with an empty backup is REFUSED with a hash mismatch (the live hash of an empty patch is None); fail-closed, whether intended is UNCONFIRMED. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. M1: custody_sweep.py records index_unpatched for a stash (git diff --quiet ref^1 ref^2, run only when the tracked patch is empty), and verify refuses land of such a stash for its index (staged) content with a message that names it and says the backup is not stale (the round-5 hash-mismatch refusal was incidental). New check EP2V and paired mutant EP2M (the check disabled): EP2M caught by EP2V; r22 regression test pass=90 fail=0 (9 m 45 s). Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 2: status Queued -> In progress (the vehicle is in flight). No fix claimed (section 11.4.290).

## CON-147 — host_guard.sh: live thread limit unreadable under dash (ulimit -u), so every shard plan is clamped to N=1

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (full-suite fix subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con147_reproduction_2026_11_05.txt` — red-command `FC_GUARD_NPROC=64 FC_GUARD_THREADS=0 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 sh scripts/fastcycle/lib/host_guard.sh 1000000; sh scripts/fastcycle/tests/test_host_guard_red.sh` — green-command `same commands on the fixed guard` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, /bin/sh = dash, load ~30 on 16 CPUs` — signature `N=1 REASON=unreadable_ulimit under sh` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `dash has no ulimit -u, so the live read returned empty` — evidence `docs/qa/con147_reproduction_2026_11_05.txt` — updated 2026-11-05T20:42:18Z — by `Claude Opus 5.5 (full-suite fix subagent)`

Vehicle ids before re-mint: CON-109 (rounds 1 to 3), then CON-117 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-147 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-099 (inventory class C, manifest-triage; split out per CON-106). Source: full-suite root-cause report of 2026-11-05 (root cause proven there, reproduced again in the fix vehicle). What: scripts/fastcycle/lib/host_guard.sh read the soft RLIMIT_NPROC with ulimit -u, which dash (/bin/sh on Debian/Ubuntu) rejects; run via sh it reported N=1 REASON=unreadable_ulimit, so gate_runner.sh serialised every shard plan on such hosts. Fix: read the soft Max processes value from /proc/self/limits, fall back to ulimit -u; FC_GUARD_PROC_LIMITS names a fixture file for tests. Test scripts/fastcycle/tests/test_host_guard_red.sh reads its own expectation the same way, lowers the limit with prlimit when present, and adds fixture checks (soft 777 vs hard 999, unlimited, garbled, live control needle). Acceptance: GREEN under sh (dash) and bash; mutations (file ignored, hard field read) caught. Fix round 2 (independent review round 1: NO-GO, findings F2-1, F2-2, F2-3): F2-1, scripts/fastcycle/host/host_report.py _read_ulimit_threads still ran sh -c "ulimit -u" only, so probe_thread_headroom reported unmeasured on dash hosts; it now reads the soft Max processes value from /proc/self/limits (new _read_nproc_soft, same FC_GUARD_PROC_LIMITS test seam) with sh -c "ulimit -u" as the fallback; new guard scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh (dash-like sh shim, real dash, fixtures soft 4242 / hard 99999, unlimited, no line + bash fallback, end-to-end probe; mutants M1 old read, M2 hard column, M3 no fallback, all caught), RED pass=5 fail=9 / GREEN pass=14 fail=0 under sh and bash. Class census (git grep ulimit -u, control needles): host_guard.sh fixed in round 1, host_report.py fixed here, test_host_guard_red.sh:258 no-prlimit branch scoped out as CON-155, codegraph_safe.sh (bash) and prose not members. F2-2, behaviour change for callers, checked: on a dash host four callers that were silently serial (N=1) now get the guard's real limits: scripts/fastcycle/gates/gate_runner.sh:174 (xargs -P over at most --n-shards shards), scripts/fastcycle/gates/lib/backstop_run.py:223 (--jobs, never above the caller's request), scripts/fastcycle/host/host_report.py:1021 (a probe that only reads N, starts no jobs) and scripts/fastcycle/tests/test_foundational_mutations.sh:107 (MAXJ, at most 9). Each stays bounded by the guard's nproc, thread-headroom (section 12.12) and 60 % memory-ceiling (section 12.6) rules; the guard does not size N by per-job memory when no --per-job-mem-kb is passed (its existing I1 design). The reviewer measured the foundational driver at MAXJ 9: peak 43 processes, at most 30.1 % of MemTotal in use (all users), 2796 of 123694 threads. F2-3, FC_GUARD_PROC_LIMITS added to the host_guard.sh header Inputs list. **Affected scope / file-scope manifest:** scripts/fastcycle/lib/host_guard.sh; scripts/fastcycle/tests/test_host_guard_red.sh; scripts/fastcycle/host/host_report.py; scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh; config/full_suite_manifest.tsv Fix round 3 (structural, review round 2 finding R2-F2: HR1 and HR2 survived): the guard now lowers its own process limit with setrlimit before exec (soft THR+3000, hard soft+1000, a control needle checks it differs from pid 1), so reading /proc/1/limits instead of /proc/self/limits fails P1 (HR2 killed); missing (X1) and unreadable mode-000 (X3) limits files with a working 'ulimit -u' must use the fallback (HR1 killed); a fixture with a working 'ulimit -u' (L4B) proves the file wins (HR3 ulimit-first killed; in production both read the same kernel value, differential recorded); FC_GUARD_ULIMIT_U override (O1). Fixture axes listed in the test header. Old guard: HR1, HR2 survive (rc 0) under sh and bash; new guard pass=25 fail=0 under sh and bash, every mutant killed by its named check. Evidence: docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt. Round 4 (review r1 NO-GO): the thread-limit regression test adds RX1/RX2 (lower the limit to 5333:6333, then a missing and an unreadable limits file, read under bash as sh) killing mutant RVH1, plus RX3..RX8 and mutants RVH1..RVH11 (RVH12 is equivalent, documented); result pass=44 fail=0 under sh (dash) and under bash (both measured). Round 5 (review of fsfix4, F8): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). host_guard.sh's awk now skips a 'Max processes' line with fewer than four fields, as host_report.py does (it used to print the third field of a three-field line). RED: with the old awk, test_host_guard_red.sh fails its two new checks (three-field line read as N=5; three-field line then a full soft-888 line read as N=5), pass=135 fail=2; GREEN pass=137 fail=0 under sh and bash. host_report's test adds RX9 (three-field line, then a full line with soft 8888 -> 8888): pass=45 fail=0 under sh and bash. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. M2: the RLIMIT_NPROC readers' comments in host_guard.sh and host_report.py state the real boundary (four words: a two-word name, soft, hard; units not required). Reviewer mutant H1 adopted: RED, it survives the round-5 test (pass=137 fail=0 with H1 applied); new fixture "Max processes 5 6" must give N=5, H1 now killed (pass=137 fail=1). The decision-mutant census (scripts/validation/enumerate_decision_mutants.py, section 11.4.274) found host_guard's awk 2>/dev/null redirect unpinned: a directory as the limits path must give the no-line result with stderr empty (new checks). test_host_guard_red.sh pass=140 fail=0; host_report thread-limit test pass=45 fail=0. Census over host_guard.sh (46 mutants) and host_report.py's _read_nproc_soft (9): every mutant KILLED except three floor-at-1 comparisons (-lt 1 -> -le 1) proven equivalent in scripts/validation/decision_mutants_equivalent.tsv. Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 2: status Queued -> In progress (the vehicle is in flight). No fix claimed (section 11.4.290).

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

**Status:** In progress
**Type:** Bug
**Severity:** High
**Created-By:** Claude Opus 5.5 (custody/host_guard structural round 3 subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt` — red-command `bash scripts/validation/test_meta_test_verification_r1_regression.sh (against the pre-fix meta_test_verification.sh, plus the TERM-at-delay loop; evidence file section 'CON-120 reproduction' and 'CON-120 RED', vehicle id before re-mint)` — green-command `same command, on the fixed meta-test` — env `Linux 7.0.0, git 2.53.0, Python 3.14.4, bash, load ~30 on 16 CPUs` — signature `old meta_test_verification.sh stopped by TERM at 0.02 s: SUBMODULE_MOVED; at 0.12/0.25/0.30 s: TRACKED_FILE_MUTATED+bak_left` — updated 2026-11-10T23:30:39Z — by `Claude Opus 5.5 (fsfix round 5 subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `the old meta-test renamed the real verification submodule and edited the tracked gate in place, so a stop between the change and its restore left the checked tree changed; proven by the TERM-at-delay table (tree changed only at delays inside those windows) and by the scratch-root rewrite, which removed the windows (GREEN 11/0, then round 4/5 tests)` — evidence `docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt` — updated 2026-11-10T23:30:39Z — by `Claude Opus 5.5 (fsfix round 5 subagent)`

Vehicle ids before re-mint: CON-120 (rounds 1 to 3), then CON-128 (rounds 4 and 5, re-minted by merge 3d050dc3 of main 90efceb8 on 2026-11-10, map CON-108..CON-120 -> CON-116..CON-128); re-minted to CON-158 by merge 4003395b of main 2e8cfb90 on 2026-11-11 (section 11.4.214; map CON-116..CON-128 -> CON-146..CON-158; on main CON-116..CON-145 are other items). Parent: CON-150 / CON-156 class (review round 2 finding R2-F5-A, risk raised UNCONFIRMED by the conductor). What: scripts/validation/meta_test_verification.sh (manifest row: entry, heavy) renamed submodules/verification to verification.mut.bak and ran sed -i on the tracked scripts/validation/run_verification.sh, with fixed /tmp names and no trap. Reproduced on a scratch tree (docs/qa/con146_con147_con150_fix_round3_2026_11_06.txt): a TERM at 0.02 s left the submodule renamed and at 0.12, 0.25 and 0.30 s left the tracked gate mutated with a .mut.bak beside it (4 of 15 delays); a heavy-tier run on a real checkout that has submodules/verification would do the same to it (section 9.2). Its mutation 2 seds also rewrote every fi/else, so the mutated gate did not parse (bash -n rc 2): a syntax error fails whatever the gate checks, a bluff mutation. Its PASS path ended with prose the full-suite runner judged ERROR unparsed_fail_signal. Fix: the checked tree is never changed; each mutation runs on a mktemp -d scratch root under TMPDIR (a copy of the gate plus one symlink per real submodule), removed by an EXIT trap; mutation 2 edits a copy with two exact anchors and must pass bash -n; the summary line is printed last. New guard scripts/validation/test_meta_test_verification_r1_regression.sh (fake tree; full run unchanged tree, empty TMPDIR, runner judge PASS, mutation-2 parse; TERM and KILL at 12 delays (superseded in round 4 by 14 delays scaled to the measured run time); blind gate and always-fail gate make it fail): RED on the old script pass=6 fail=5, GREEN pass=11 fail=0. **Affected scope / file-scope manifest:** scripts/validation/meta_test_verification.sh; scripts/validation/test_meta_test_verification_r1_regression.sh; config/full_suite_manifest.tsv; docs/guides/full_suite_runner_guide.md (census line) Round 4 (review r1 NO-GO): the regression test adds fixtures B3 (gate that needs git) and B4 (reformatted gate) killing mutants MT1 and MT9, scales the TERM and KILL delays to the measured run time (14 points from 2 to 98 percent, with a control needle), and the script header documents the KILL gap: SIGKILL cannot run the EXIT trap, so the mktemp scratch root with symlinks is left behind; the checked tree is never changed. Result pass=17 fail=0. Round 5 (review of fsfix4 NO-GO, F1 and F7): Rounds continue past R_max by operator decision relayed 2026-11-10, verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)). Reviewer mutants Ma (control verdict ignored) and Mb (mutation-1 verdict ignored) adopted verbatim: RED, both survive the round-4 test; the test now lists every decision point of meta_test_verification.sh (DP1..DP13) and pins each with a fixture and a paired mutant: B5 always-pass gate with intact anchors (kills Mb), B6 README missing in the checked tree (kills Ma), B7 gate missing, B8 test submodule missing, B9/B10 scratch-root sabotage of mutation 1 and 2, B11 weakened gate that does not parse, signal fixtures TERM/INT/HUP (exit 143/130/129, nothing left) and a TERM during cleanup's rm. A real defect found while doing it: a TERM to the process group while the EXIT trap's rm ran killed the rm and left the scratch root (measured 8 of 280 stops at 90..105% of the run); cleanup now ignores HUP, INT and TERM before its rm (0 of 280); remaining window stated in the script: a second signal between the start of the EXIT trap and its first command. F7: after each timed stop the test waits until no process with the scratch path, or the meta-test's own command line (a killed meta-test's build_root subshell keeps running), is left before it removes the scratch root. Result pass=51 fail=0 (runs 3 and 4), nothing left under TMPDIR. Evidence: docs/qa/con146_con147_con158_fix_round5_2026_11_11.txt. Round 6 (review of fsfix5 NO-GO: N1..N3, M1, M2, n1, n2): the operator decision relayed 2026-11-10 is "Keep running rounds until GO is reached!" (section 11.4.276(E)(3)/(G)): rounds continue past R_max, the GO bar is unchanged. Merge 4003395b of main 2e8cfb90 re-minted the vehicle items CON-116..CON-128 as CON-146..CON-158. N1: every signal of the regression test is sent on an observed event (the sigwait gate's marker during the control run, or an rm shim's marker when the cleanup's rm starts), launched by sigrun.py in its own session with HUP/INT/TERM reset. N2: every wait is bounded (30 s, then SIGKILL of the process group; leftover session processes are killed and counted; a timeout or nomark verdict is BLIND and repeated once). N3: reviewer mutants R1b (twice), R2, R3, R4, R5b and R7 adopted verbatim: RED, 5 survive the round-5 test (pass=52 fail=5); new fixtures B12 (mktemp fails), B13 (duplicate anchor), B14 (cp fails), B15 (ln fails) kill them; TERM/INT/HUP pinned to exit 143/130/129. n1: every fixture runs in its own mktemp directory (the counter bumped inside $(...) is gone). Class narrowed (section 11.4.274; wording corrected by CON-159): scripts/validation/enumerate_decision_mutants.py enumerates the decision points of meta_test_verification.sh that its closed list of single-edit operators matches (60 single-edit mutants) and runs each against the regression test; this is not a completeness proof for decision points no operator generates. Census run 1 on the round-6 test: 15 survivors; the test then adds the diag= field (both streams of each gate run captured and indented; gates false, needs_git and stderr_missing write to stderr; mutants DP14a-g) and the stop= field (a scratch-root failure stops the run; mutants DP15a-c). Census run 2: killed=109 survived=0 equivalent=6 blind=0 over all three targets, the meta target's three equivalents proven in the ledger. Regression test pass=75 fail=0, three runs. Evidence: docs/qa/con146_con147_con158_fix_round6_2026_11_11.txt.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 2: status Queued -> In progress (the vehicle is in flight). No fix claimed (section 11.4.290).

## CON-159 — CON-158 census wording overstates coverage: every decision point matched by the closed operator list, not every decision point

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con159_census_wording_2026_11_11.txt` — red-command `bash scripts/validation/test_decision_mutant_census_wording_r1_regression.sh` — green-command `bash scripts/validation/test_decision_mutant_census_wording_r1_regression.sh (same command on the fixed tree)` — env `clone of main fc57ad0c; Linux 7.0.0, git 2.53.0, Python 3.14.4, bash 5.3.9(1)-release` — signature `NOT ok tool docstring still says it enumerates EVERY decision point` — updated 2026-11-11T12:36:29Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`
**Investigation:** root-cause-found-with-evidence — root-cause `the census tool docstring, the meta-test header and the CON-158 text were written as if the closed operator list covered every decision point; the operator list is closed (see the tool's Operators section)` — evidence `docs/qa/con159_census_wording_2026_11_11.txt` — updated 2026-11-11T12:36:29Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`

Review finding m1 (minor, process-doc, parent CON-158). The CON-158 body and commit 02e681a6 say enumerate_decision_mutants.py enumerates every decision point of meta_test_verification.sh and closes the class. It covers only decision points its closed list of single-edit operators matches. Reviewer mutants Y1, Y2, Y8, Y9 and Y10 are real decision-point mutants the operators do not generate (all five killed by existing tests, so nothing is unguarded today). Fix: reword the tracker text and commit-derived docs to every decision point matched by the closed operator list; optionally add operators for if-condition negation and awk field shifts. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Ready for testing: a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes (tail sentence corrected at landing, review nit n4).

**Verification:** provisional (section 11.4.290) -- job: re-run the new guard in a clean checkout of the landing commit (expect pass=4 fail=0) and the manifest check (MANIFEST-OK) -- checks: the three wording checks and three paired mutants; optional extra operators NOT added -- layer: host-only (class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit e51a8686 -- due: next full-suite run. Review: independent Opus review of the fu_a vehicle, verdict GO-with-follow-ups (record docs/qa/review_fu_a_2026_11_11.md; follow-ups registered as their own items). Not VERIFIED-DONE.

## CON-160 — EP2V does not pin stash_index_unpatched True vs None and no fixture makes git fail (reviewer mutants Y12, Y14 survive)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con160_stash_index_unpatched_2026_11_11.txt` — red-command `bash scripts/fastcycle/tests/test_custody_sweep_stash_patch_r22_regression.sh with reviewer mutant Y12 applied to custody_sweep.py (54 ok, 0 NOT ok: survives)` — green-command `bash scripts/fastcycle/tests/test_custody_sweep_stash_index_unpatched_r23_regression.sh (Y12 and Y14 killed)` — env `clone of main fc57ad0c; Linux 7.0.0, git 2.53.0, Python 3.14.4, bash 5.3.9(1)-release` — signature `Y12 survives r22 functional checks incl. EP2V` — updated 2026-11-11T12:37:41Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`
**Investigation:** root-cause-found-with-evidence — root-cause `EP2V only matches the message text; nothing pinned the True/False/None value of stash_index_unpatched or a git failure; source is correct (test-instrumentation)` — evidence `docs/qa/con160_stash_index_unpatched_2026_11_11.txt` — updated 2026-11-11T12:37:41Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`

Review finding m2 (minor, test-instrumentation, parent CON-146). EP2V checks only that the refusal message names index (staged) content. Mutant Y12 (rc==1 returns None instead of True) and mutant Y14 (final return None becomes False, a git failure reads as no index content) both survive r22 (90/0). The verdict stays REFUSED either way, so this is message precision, not safety. Fix: assert index_unpatched=True in EP2V, and add a git-failure fixture (a PATH shim making git diff --quiet ^1 ^2 return 128) asserting index_unpatched=None; both must kill Y12 and Y14. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Ready for testing: a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes (tail sentence corrected at landing, review nit n4).

**Verification:** provisional (section 11.4.290) -- job: re-run the new guard in a clean checkout of the landing commit (expect pass=5 fail=0) and the manifest check (MANIFEST-OK) -- checks: five axes (IDX WT EQ NONE GITF) and four paired mutants (Y12 Y14 Y15 Y16) killed; source unchanged -- layer: host-only (class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit c6a32f61 -- due: next full-suite run. Review: independent Opus review of the fu_a vehicle, verdict GO-with-follow-ups (record docs/qa/review_fu_a_2026_11_11.md; follow-ups registered as their own items). Not VERIFIED-DONE.

## CON-161 — host_report probe_thread_headroom arithmetic and thr-is-None guard have no canon-runnable test (reviewer mutants Y4, Y5, Y6 survive)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con161_probe_thread_headroom_2026_11_11.txt` — red-command `bash scripts/fastcycle/tests/test_host_report_thread_limit_r1_regression.sh with reviewer mutants Y4/Y5 applied to host_report.py (pass=45 fail=0, survives)` — green-command `bash scripts/fastcycle/tests/test_host_report_probe_thread_headroom_r2_regression.sh (same mutants: killed)` — env `clone of main fc57ad0c; Linux 7.0.0, git 2.53.0, Python 3.14.4, bash 5.3.9(1)-release` — signature `Y4 and Y5 SURVIVED r1 pass=45 fail=0` — updated 2026-11-11T12:36:39Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`
**Investigation:** root-cause-found-with-evidence — root-cause `no canon-runnable test pinned probe_thread_headroom's arithmetic or its thr-is-None guard; r1 pins only the soft limit read. Y6 not measured by me (r1 hung under that mutant, killed)` — evidence `docs/qa/con161_probe_thread_headroom_2026_11_11.txt` — updated 2026-11-11T12:36:39Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`

Review finding m3 (minor, test-instrumentation, pre-existing, outside round 6, CON-147 neighbourhood). Y4 (per_job = headroom), Y5 (headroom = ulim - 1) and Y6 (drop the thr is None guard, giving an uncaught TypeError in host_report.py limits) survive the only test that runs in a canon checkout (host_report r1, 45/0); test_host_limits_red.sh SKIPs outside a consumer layout. The source is correct today. Fix: a canon fixture pinning thread_headroom, threads_per_job_probed and reason=unmeasured when FC_GUARD_THREADS is unset and ps fails; optionally widen the census host_report scope to the probe. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Ready for testing: a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes (tail sentence corrected at landing, review nit n4).

**Verification:** provisional (section 11.4.290) -- job: re-run the new guard in a clean checkout of the landing commit (expect pass=6 fail=0) and the manifest check (MANIFEST-OK) -- checks: six cases and five paired mutants (Y4 Y5 Y6 Y9 Y10) killed -- layer: host-only (class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit 4bbc4310 -- due: next full-suite run. Review: independent Opus review of the fu_a vehicle, verdict GO-with-follow-ups (record docs/qa/review_fu_a_2026_11_11.md; follow-ups registered as their own items). Not VERIFIED-DONE.

## CON-162 — fsfix6 review nits: census timeout kill misses timeout's process groups, ledger KILLED-key staleness, porcelain git diff in stash_index_unpatched, vehicle items left Queued

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fsfix6 lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con162_census_nits_2026_11_11.txt` — red-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh on the pre-fix tool (n1 leftover processes)` — green-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh (same command on the fixed tool)` — env `clone of main fc57ad0c; Linux 7.0.0, git 2.53.0, Python 3.14.4, bash 5.3.9(1)-release` — signature `n1: run_bounded timeout left [timeout, sleep] alive in the run session` — updated 2026-11-11T12:36:39Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`
**Investigation:** root-cause-found-with-evidence — root-cause `n1: GNU timeout calls setpgid so its group differs from the run's; killpg(p.pid) misses it, the session id is kept so kill_session finds it. n2: the stale check only looked at generated keys. n3 not reproduced; n4 not acted (see evidence)` — evidence `docs/qa/con162_census_nits_2026_11_11.txt` — updated 2026-11-11T12:36:39Z — by `AI (Claude Sonnet 5.5, CON-159..162 follow-up subagent fu_a)`

Review nits n1 to n4. n1: the census run_bounded kills its own process group on timeout, but GNU timeout starts a new process group, so children can run up to 125 s into the next mutant (host load only). n2: a ledger entry is STALE only when its key is no longer generated; an entry whose mutant is later KILLED (equivalence proof now false) is accepted silently; flag it stale. n3: stash_index_unpatched uses porcelain git diff --quiet, subject to diff.ignoreSubmodules and external drivers; use git diff-tree --quiet ^1 ^2. n4: the 13 vehicle items stay Queued while fix rounds run; consider In progress for CON-146, CON-147, CON-158. Follow-up of the independent Opus review of the fsfix round-6 vehicle (verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; review record docs/qa/review_fsfix6_round6_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Ready for testing: a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes (tail sentence corrected at landing, review nit n4).

**Verification:** provisional (section 11.4.290) -- job: re-run the new guard in a clean checkout of the landing commit (expect pass=4 fail=0) and the manifest check (MANIFEST-OK) -- checks: n1 and n2 fixed with guard + three mutants + an end-to-end census run; n3 NOT reproduced and NOT fixed; n4 NOT acted -- layer: host-only (class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit 2249f21a -- due: next full-suite run. Review: independent Opus review of the fu_a vehicle, verdict GO-with-follow-ups (record docs/qa/review_fu_a_2026_11_11.md; follow-ups registered as their own items). Not VERIFIED-DONE.

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

test_unit_safe.sh U01-U46 read the host's real /proc/meminfo and df, so a busy or small host failed ~32 cases

Link (section 11.4.214, open original, link only; 2026-11-17): in the full-suite run /mnt/DATA1TB/claude-work/scratch/bl.frkt3d/out (SHA256SUMS sha256 063982826381bcfb66dd4cee60ece053b22d78af0cdde13de1fdd3b71695e4eb) test_unit_safe.sh ended TIMEOUT at 300.1 s (run.log line 81) with 50 PASS result lines and no FAIL result line in logs/000048.log, so this run shows slowness under load, not the case failures of this item; the timeout budget is tracked in CON-520.

## CON-167 — test_unit_safe.sh U28 and U35 fail intermittently under host load (newly visible once CON-149 removed the preflight failures)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)

test_unit_safe.sh U28 and U35 fail intermittently under host load (newly visible once CON-149 removed the preflight failures)

Link (section 11.4.214, open original, link only; 2026-11-17): in the full-suite run /mnt/DATA1TB/claude-work/scratch/bl.frkt3d/out (SHA256SUMS sha256 063982826381bcfb66dd4cee60ece053b22d78af0cdde13de1fdd3b71695e4eb) test_unit_safe.sh ended TIMEOUT at 300.1 s (run.log line 81) with 50 PASS result lines and no FAIL result line in logs/000048.log, so this run shows slowness under load, not the case failures of this item; the timeout budget is tracked in CON-520.

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

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con183_reproduction_2026_11_11.txt` — red-command `bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON183-M4 (against the helper test without Part 3b)` — green-command `same command on the fixed helper test` — env `main fc57ad0c plus CON-184 and CON-185; Linux 7.0.0, bash 5.3.9, dash` — signature `SURVIVED CON183-M4 (rc 0, 0 NOT ok lines)` — updated 2026-11-11T12:45:18Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`
**Investigation:** root-cause-found-with-evidence — root-cause `Part 4 is skipped when FC_HELPER_UNDER_TEST is set, so the symlinked-canon layout it builds never ran the mutated copy` — evidence `docs/qa/con183_reproduction_2026_11_11.txt` — updated 2026-11-11T12:45:18Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`

Parent: CON-178 (fc_require_items). Review round 8 R8-1. test_consumer_required_helper.sh skips Part 4 when FC_HELPER_UNDER_TEST is set (test_consumer_required_helper.sh:600 at vehicle head 4118f145), and both the sweep and the hand table set it, so a mutant that only the Part 4 legs kill is reported as survived. The reviewer's mutant M4 ($(cd "$(dirname -> $(cd -P "$(dirname) survives 338/0 through the harness path, while the same edit in the real helper fails Part 4 nine times (342/9). Acceptance: run Part 4 against the mutant (link the mutant into the scratch consumer layout instead of the checkout's helper), or state this bound beside the sweep's claim; then adopt M4 as a paired mutant. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). Status at landing (sentence corrected at landing of the fu_b vehicle): Ready for testing; a fix is claimed and is PROVISIONAL-DONE (§11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (follow-up fu_b, 2026-11-11): the stated bound is kept and narrowed instead of running the heavy real suites per mutant: a new Part 3b in scripts/fastcycle/tests/test_consumer_required_helper.sh builds the symlinked-canon layout of Part 4 around the helper UNDER TEST and runs even when FC_HELPER_UNDER_TEST is set, so the reviewer mutant M4 (cd -P) is adopted as CON183-M4 in the hand table and is killed (bash and dash); the Part 4 skip note and the header of test_consumer_required_mutations.sh state that other mutants only the real cycle_report suites kill are still reported survived and must be probed on the real helper. Helper test: 361 pass / 0 fail. The 169-mutant sweep and the full hand table were not re-run (UNCONFIRMED: the 21 registered equivalents are fc_require_items edits that Part 3b cannot reach).

**Verification:** provisional (section 11.4.290) -- job: re-run bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON183-M4 (expect killed) and bash scripts/fastcycle/tests/test_consumer_required_helper.sh (expect 0 fail), then the on-demand sweep (--sweep) to confirm the 21 registered equivalents still survive -- checks: M4 killed by Part 3b -- layer: gate-logic (test-instrumentation; class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit that lands the fu_b CON-183 change -- due: next full-suite run.

Review: independent Opus review of the fu_b vehicle, verdict GO (record docs/qa/review_fu_b_2026_11_11.md); follow-ups CON-224 (F3, mutant RV-C) and CON-225 (N2, evidence count note) registered as their own items.

## CON-184 — fc_require_items id contract: a lowercase letter inside the prefix (AtM-5) is a usage error but no fixture asserts it; mutant M3 [[:alnum:]] survives (review round 8 R8-3)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con184_reproduction_2026_11_11.txt` — red-command `bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON184-M3 (against the helper test without the AtM-5 leg)` — green-command `same command on the fixed helper test` — env `main fc57ad0c; Linux 7.0.0, bash 5.3.9, dash` — signature `SURVIVED CON184-M3 (rc 0, 0 NOT ok lines)` — updated 2026-11-11T12:31:16Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`
**Investigation:** root-cause-found-with-evidence — root-cause `the id contract check has no fixture for a lowercase letter inside the prefix, so the [:alnum:] mutant is not observable` — evidence `docs/qa/con184_reproduction_2026_11_11.txt` — updated 2026-11-11T12:31:16Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`

Parent: CON-178 (fc_require_items). Review round 8 R8-3. The id contract [A-Z][A-Z0-9]*-[0-9]+ is not fully pinned: the reviewer's mutant M3 changes the rest-of-prefix class *[!A-Z0-9]* to *[![:alnum:]]* and survives 338/0; on a foreign register the id AtM-5 exits 2 (usage error) on head and SKIPs 77 under M3, in bash and dash. Acceptance: add AtM-5 (and, for example, A_B-1) to the S7 or S7b usage-error list, and adopt M3 as a paired mutant. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). Status at landing (sentence corrected at landing of the fu_b vehicle): Ready for testing; a fix is claimed and is PROVISIONAL-DONE (§11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (follow-up fu_b, 2026-11-11): the S7b usage-error list of scripts/fastcycle/tests/test_consumer_required_helper.sh now also asserts AtM-5 and A_B-1 (exit 2 and the exact message, bash and dash), and the hand table of test_consumer_required_mutations.sh adopts the reviewer mutant M3 as CON184-M3 (the helper test: 355 pass / 0 fail). Class sweep: the id-contract classes first character, rest of prefix, number part were already pinned except the lowercase-inside-prefix class; the sweep generated-mutant check is unchanged.

**Verification:** provisional (section 11.4.290) -- job: re-run bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON184-M3 (expect killed) and bash scripts/fastcycle/tests/test_consumer_required_helper.sh (expect 0 fail) on main after landing -- checks: M3 killed by the AtM-5 leg -- layer: gate-logic (test-instrumentation; class floor: runtime for a test item) -- target: host, repo checkout -- artifact: commit that lands the fu_b CON-184 change -- due: next full-suite run.

Review: independent Opus review of the fu_b vehicle, verdict GO (record docs/qa/review_fu_b_2026_11_11.md); no follow-up for this item.

## CON-185 — L29 calls bad, not SKIP-with-reason, on a host with no UTF-8 locale that classes A-umlaut as [:upper:] (review round 8 N8-1)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con185_reproduction_2026_11_11.txt` — red-command `bash <copy of test_consumer_required_helper.sh with the L29 candidate list set to zz_ZZ.UTF-8>` — green-command `FC_L29_CANDIDATES=zz_ZZ.UTF-8 bash scripts/fastcycle/tests/test_consumer_required_helper.sh` — env `host fixture: simulated no-locale host; Linux 7.0.0, bash 5.3.9` — signature `NOT ok L29: no UTF-8 locale classes A-umlaut as upper; the leg cannot run (rc 1)` — updated 2026-11-11T12:40:32Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`
**Investigation:** root-cause-found-with-evidence — root-cause `leg L29 reported a missing locale class as bad() instead of a SKIP-with-reason` — evidence `docs/qa/con185_reproduction_2026_11_11.txt` — updated 2026-11-11T12:40:32Z — by `AI (Claude Sonnet 5.5, follow-up fu_b)`

Parent: CON-178 (fc_require_items). Review round 8 N8-1 (nit). Leg L29 of test_consumer_required_helper.sh calls bad when the host classes no listed UTF-8 locale's A-umlaut as [:upper:], so a host without such a locale FAILs the whole helper suite when only that leg lacks topology. Acceptance: that leg records a §11.4.3 SKIP-with-reason naming the missing locale class instead of a FAIL, with a test that proves both branches. On the review host the locales are present, so the leg ran. Source: independent review of round 8 of the full-suite fix vehicle (GO-with-follow-ups, 0 critical, 0 important, 3 minor, 1 nit), kept as docs/qa/review_cgs8_round8_2026_11_11.md. Finding layer: test-instrumentation, minor-class under §11.4.276(G.2). Status at landing (sentence corrected at landing of the fu_b vehicle): Ready for testing; a fix is claimed and is PROVISIONAL-DONE (§11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (follow-up fu_b, 2026-11-11): leg L29 of scripts/fastcycle/tests/test_consumer_required_helper.sh now prints a section 11.4.3 SKIP-with-reason line (reason=topology_unsupported) and does not count a failure when no listed locale classes A-umlaut as upper; both branches are proven on every run (the empty-list branch with a locale name no host has, the other with the host list), and FC_L29_CANDIDATES lets a test simulate such a host. Helper test on this host: 356 pass / 0 fail; simulated host: 347 pass / 0 fail with the SKIP line; paired mutant (SKIP line made a NOT ok) killed.

**Verification:** provisional (section 11.4.290) -- job: re-run bash scripts/fastcycle/tests/test_consumer_required_helper.sh and FC_L29_CANDIDATES=zz_ZZ.UTF-8 bash scripts/fastcycle/tests/test_consumer_required_helper.sh on main after landing -- checks: rc 0 for the first; rc 77 (not 0, since CON-222: a skipped leg is counted) for the second, which prints the L29 SKIP line -- layer: gate-logic (test-instrumentation; class floor: runtime for a test item) -- target: host, repo checkout; a real host without locales is UNCONFIRMED (not available) -- artifact: commit that lands the fu_b CON-185 change -- due: next full-suite run.

Review: independent Opus review of the fu_b vehicle, verdict GO-with-follow-ups (record docs/qa/review_fu_b_2026_11_11.md); follow-ups CON-222 (F1, the skip does not reach the suite verdict; mutants RV-E, RV-F) and CON-223 (F2, ambient FC_L29_CANDIDATES override) registered as their own items.

## CON-186 — fixu landing review follow-ups M1, M2, M3: case 11c closure-by-location, runner guide acceptance wording, tracked resolve1 proposal

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-116..CON-145 fixu landing (3bd34494, e6b16598, 2e8cfb90). Source: independent review docs/qa/fixu_review/landing/review_fixu_landing.md (GO-with-follow-ups, 0 critical, 0 important, 4 minor, 2 nit). M1: tests/test_run_full_suite.sh case 11c now also puts an Obsolete and a Completed item located in Fixed in the fixture and asserts both are named STALE; mutant X1 (check_known_open deciding closure from a status text starting with Fixed) survived the old fixture and fails exactly those 2 new assertions (274 passed, 2 failed). M2: docs/guides/full_suite_runner_guide.md no longer says an agent never runs the acceptance; it states that the runner enforces only that the id is on the committed roster and that the acceptances so far (2739c26b, bdc3ac43, e6b16598) were run by the landing agent on a conductor-relayed order, tier instance. M3: the cited proposal resolve1_lock_PROPOSAL_r2.md was recovered from a scratchpad and is now tracked as docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md (section 11.4.215). Finding layer: test-instrumentation and process-doc, minor-class under section 11.4.276(G.2). At registration the fixes were in the change that registered this item and had no independent review: the item was Queued and neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Superseded wording: the M2 text "tier instance" was later removed from the guide by CON-190 (no separate verifier instance is shown by the record).
Review: docs/qa/fixu_review/landing/review_fixu_fu.md, GO-with-follow-ups for M1-M3 (mutant X1 killed by the new case 11c rows; the tracked proposal sha matched). Its follow-ups are carried by the children CON-189 (F1, Y1), CON-190 (F2, F3, N2) and CON-191 (N3, N4). Reproduction and investigation states stay UNSET: this is a test-instrumentation and process-doc Task, not a defect item (section 11.4.294(E)); the X1 survival on the old fixture is the reviewer's measurement, not re-run at this landing.
**Verification:** provisional (section 11.4.290) -- job: bash tests/test_run_full_suite.sh case 11c (Obsolete and Completed rows in Fixed named STALE) and the review_fixu_fu mutant X1 (check_known_open: elif r[1] != "Issues" replaced by elif str(r[0]).startswith("Fixed"), applied by hand in a scratch copy; it is not a row of tests/test_run_full_suite_mutations.sh, whose own X1 is a different mutant) expected to fail exactly the two 11c assertions on the final main -- checks: X1 killed; guide and proposal text as reviewed in review_fixu_fu -- layer: host-only (test instrumentation, docs) -- target: host, repo checkout -- artifact: 65383536 and the commit that lands this status -- due: next full-suite run. Not VERIFIED-DONE: it reaches VERIFIED-DONE once its children CON-189, CON-190 and CON-191 are verified (review fu_c F-A).

## CON-187 — CON-099 reached GO-with-follow-ups at round 3 with no section 11.4.276(E) convergence assessment recorded (fixu landing review M4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-099. Source: docs/qa/fixu_review/landing/review_fixu_landing.md M4 (minor, process). Round 3 of CON-099 ended GO-with-follow-ups without the round-3 convergence assessment of section 11.4.276(E). The assessment is NOT written here: UNKNOWN: the author's round-3 assessment inputs (class-sharing findings, reappearing findings, wrong-layer evidence) are not recoverable from the tracker text alone, and inventing one would be a section 11.4.6 fabrication. Acceptance: before CON-099 round 4 the fixer records the assessment (or records why none was needed) in CON-099. Finding layer: process-doc, minor-class under section 11.4.276(G.2). Status Queued; no fix claimed (section 11.4.290).

Inputs for the assessment are tracked (CON-191 N4): docs/qa/fixu_review/review_fixu_r3.md section 5 (F099-4, same carrier class as F099-2), section 6 (reviewer class inventory; line 433 is the only open member) and the N099-6 note on CON-099. The fixer can write the section 11.4.276(E) assessment from them; it is still not written here (section 11.4.6). Status stays Queued.

## CON-188 — fixu landing review notes N1 and N2: no CHANGELOG entry for the landing; main red on the env-reads allowlist gate until CON-144

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixu follow-up subagent)

Parent: CON-116..CON-145 fixu landing. Source: docs/qa/fixu_review/landing/review_fixu_landing.md N1, N2 (nits, recorded as notes). N1: the landing (162 files) has no CHANGELOG entry; UNCONFIRMED whether the project expects one for a fix landing; the lander decides. N2: main stays red on CM-GATE-ENV-READS-ALLOWLISTED and the census closure test after the landing, as before it; it is tracked as CON-144 (medium) and should be fixed soon because a red gate hides a new failure of the same gate. Nothing is changed by this item. Finding layer: process-doc, minor-class under section 11.4.276(G.2). Status Queued; no fix claimed (section 11.4.290).
Note at the fu_c landing (review docs/qa/review_fu_c_2026_11_11.md F-D): N2 is resolved; CON-144 (fc57ad0c) made CM-GATE-ENV-READS-ALLOWLISTED PASS with uncovered=0 stale=0 needle=ok, measured by the fu_c reviewer on fc57ad0c. The census closure test named in N2 was not re-measured (UNCONFIRMED). N1 (whether this fix landing needs a CHANGELOG entry) remains open as an operator/lander decision; the fu_c lander did not decide it.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 4: N1 is resolved: no separate CHANGELOG entry for the fix landing; the consolidated CHANGELOG entry written at the v73.4 release covers it. Both notes N1 and N2 are now resolved; the item stays open until that release entry exists.

## CON-189 — Case 11c pins no unknown-id-only stale row: reviewer mutant Y3 (drop stale += 1 for an unknown id) survives (fixu follow-ups review F1, Y1 nit)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186. Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. F1 (minor, test-instrumentation): tests/test_run_full_suite.sh case 11c always pairs the unknown id with a closed one, so the exit code of check_known_open never proves that an unknown id alone counts as stale; reviewer mutant Y3 (remove stale += 1 in the r is None branch) survived 276 passed / 0 failed, and on a known table holding only ATM-77 it prints the STALE line and then RESULT: KNOWN-OPEN with rc 0. Pre-existing gap in the fixture M1 extended, not introduced by it. Acceptance: a --known table with only an unknown id, asserting rc 1 and RESULT: KNOWN-STALE, with Y3 adopted as a paired mutant that must fail the suite. Nit Y1: mutant elif r[1] == Fixed (any other location read as open) survived and is equivalent only because schema.sql closes current_location to Issues/Fixed while the test fixture DB has no such CHECK; optional fixture row with another location, or a note that the set is closed by the schema. Finding layer: test-instrumentation, minor-class under section 11.4.276(G.2). At registration no fix was claimed: the item was Queued, its reproduction and investigation states were UNSET, and it was neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290); the Fix and Verification lines below record its later state (review fu_c F-C).

Fix (section 11.4.224, test-first): tests/test_run_full_suite.sh case 11c gains a table holding only ATM-77 (asserts rc 1, STALE line, RESULT: KNOWN-STALE) and a fixture row ATM-10 with location Archive (asserts STALE); paired mutants F47d (Y3) and F47e (Y1) added to tests/test_run_full_suite_mutations.sh. Evidence: with the new cases, mutant F47d (Y3) is killed (2 failing checks) and F47e (Y1) is killed (1 failing check); baseline 280 passed, 0 failed. Not reproduced by me on the old suite: the survival of Y3/Y1 on the old suite is the reviewer's recorded measurement (UNCONFIRMED here).
**Verification:** provisional (section 11.4.290) -- job: bash tests/test_run_full_suite.sh (expect passed=280 failed=0) and bash tests/test_run_full_suite_mutations.sh F47d F47e (expect both killed) on the final main -- checks: unknown-id-only table gives rc 1 and RESULT: KNOWN-STALE; a non-Issues/non-Fixed location is named STALE -- layer: host-only (test instrumentation) -- target: host, repo checkout -- artifact: the commit that lands the CON-189 change -- due: next full-suite run. Not VERIFIED-DONE; no independent review yet.

## CON-190 — Runner guide acceptance paragraph: per-commit relay wording, unsupported instance label, stale 44-row opening, undersold enforcement (fixu follow-ups review F2, F3, N2)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186 (M2). Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. F2 (minor, process-doc): docs/guides/full_suite_runner_guide.md says the acceptances 2739c26b, bdc3ac43 and e6b16598 were run by the landing agent on an order relayed by the conductor and that each commit message says so; bdc3ac43's message records an operator acceptance from a genuine user message (2026-11-05 20:41 CET) run by the landing agent on that order, not a conductor relay; only 2739c26b and e6b16598 say relayed by the conductor. Reword per commit. F3 (minor, process-doc): the guide calls the achieved separation instance, but in e6b16598 the same landing agent replaced the two manifest rows and ran the acceptance of that change, so under section 11.4.240(F) no separate verifier instance is shown; state what the record supports (change and acceptance by one agent, on a recorded operator order, with a roster id) or record why instance applies (this also corrects the earlier review M2 suggestion). N2 (nit): the same paragraph still opens with 44 excluded rows accepted as fsr-r4-author, while the lock now has 55 rows last accepted by i@mvasic.ru on 2026-11-10; and the sentence that the runner enforces only the rostered id undersells the other refusals (roster tracked, equal to HEAD, not a symlink; chain intact; no other manifest problem); the accurate point is that it checks the id, not who typed it. Finding layer: process-doc, minor-class under section 11.4.276(G.2). At registration no fix was claimed: the item was Queued, its reproduction and investigation states were UNSET, and it was neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290); the Fix and Verification lines below record its later state (review fu_c F-C).

Fix: docs/guides/full_suite_runner_guide.md acceptance paragraph rewritten: per-commit wording (2739c26b relayed by the conductor; bdc3ac43 genuine operator message run by the landing agent; e6b16598 relayed, operator message not seen), the unsupported 'instance' label replaced by what the record supports (one agent, recorded order, roster id; no separate verifier instance shown), stale 44-row opening replaced by the 55-row lock with its last acceptor i@mvasic.ru 2026-11-10, enforcement listed in full (roster tracked, equal to HEAD, not a symlink, chain intact, no other manifest problem; id checked, not who typed it); the closing honest-limit sentence aligned.
**Verification:** provisional (section 11.4.290) -- job: bash scripts/run_full_suite.sh --verify-manifest (expect MANIFEST-OK; the guide census line is untouched) and a read of the paragraph against git log of the three commits -- layer: host-only (documentation) -- target: host, repo checkout -- artifact: the commit that lands the CON-190 change -- due: next full-suite run. Documentation item, no code behaviour changed. Not VERIFIED-DONE; no independent review yet.

## CON-191 — Tracked resolve1 proposal says not applied though e6b16598 applied it; CON-187 should cite the tracked round-3 inputs (fixu follow-ups review N3, N4)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Parent: CON-186 (M3), CON-187 (M4). Source: independent review of the fixu landing follow-ups 65383536 (CON-186..CON-188), GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit, kept as docs/qa/fixu_review/landing/review_fixu_fu.md. N3 (nit): docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md still says Status: PROPOSAL. Not applied in any tracked tree, but e6b16598 applied it; a one-line header note (applied in e6b16598, kept as the record under section 11.4.215) would stop it misleading. N4 (nit): CON-187 says the round-3 convergence-assessment inputs of CON-099 are not recoverable from the tracker text alone, but they are in tracked files: docs/qa/fixu_review/review_fixu_r3.md section 5 (F099-4 same carrier class as F099-2), section 6 (reviewer class inventory, line 433 the only open member) and the N099-6 note; CON-187 should cite them so the fixer can write the assessment from them. Finding layer: process-doc, minor-class under section 11.4.276(G.2). At registration no fix was claimed: the item was Queued, its reproduction and investigation states were UNSET, and it was neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290); the Fix and Verification lines below record its later state (review fu_c F-C).

Fix: N3 -- docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md header now says APPLIED in e6b16598 (lock 53 -> 55 rows) and keeps the original status text as the record; N4 -- CON-187 now cites the tracked round-3 inputs.
**Verification:** provisional (section 11.4.290) -- job: read both texts; scripts/workable-items validate and diff in sync -- layer: host-only (documentation) -- target: host, repo checkout -- artifact: the commit that lands the CON-191 change -- due: next tracker review. Not VERIFIED-DONE; no independent review yet.

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

## CON-211 — Writer default patch set of codegraph_safe.sh follows the fk_index_patch.py registry default (one source of truth: fkidx1,resolve1,resolve2); resolve2 was never deliberately excluded (review I6-2)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Assigned-To:** Claude Sonnet 5.5 (cg117 re-vehicle subagent)

Parent: CON-031. Operator instruction 2026-11-06 (relayed): investigate and fix on evidence. Investigation (section 11.4.124): the writer list fkidx1,resolve1 and resolve2 with its tests arrived in the same cascade commit b3a73cf5 (2026-09-25); the writer comment then said only fkidx1 and resolve1 had tests, which was already false, and mutant MB5 shows the list existed to keep the untested lockfix1/datafrag1 (then in the registry default) out. No record of a deliberate resolve2 exclusion was found; the round-2 wording 'validated on a live index' has no supporting record (the only writer runs on record, an ATMOSphere ledger, are three FAILs with 1.6.0-fkidx1-resolve1). resolve2 fixes the swift-objc bridge heap OOM of bulk resolve on large indexes. Since CON-164 Option A the registry default holds only tested patches, so the reason for a separate writer list is gone. Change: codegraph_safe.sh default is 'default' (synonym 'all'), which forwards no --patches, so the writer uses runner_patches/__init__.py DEFAULT_EXCLUDED complement; an explicit --patches fkidx1,resolve1 still selects the old runner. Test first: U38 RED (d1=--patches fkidx1,resolve1, d5) then GREEN; mutants MB4, MB5 (own list back), MB5b killed; test_patch_machinery 19/0/0; test_resolve2 Q1-Q3 PASS on 1.6.2; scratch A/B old vs new vs stock runner on the resolve2 fixture: byte-identical edge/ref dumps (evidence docs/qa/con117_writer_default/). Writer-level e2e REFUSED by the host disk floor (41 GB free < 60 GiB), not bypassed. Docs: codegraph_safe.md rev 6, fk_index_patch.md rev 5, resolve2.md rev 2, resolve1.md rev 4, lockfix1.md rev 3, fkidx1.md rev 2. Review (section 11.4.142/11.4.209) owed before landing. Effect after landing: the next writer bulk run builds a new runner key <version>-fkidx1-resolve1-resolve2 (one package copy, about 286 MB on 1.6.2) and existing indexes are not rewritten by the switch itself. Id map (re-minted 2026-11-11 at landing, CON-117 and CON-120 collided with other items on main): bundle CON-117 = this item; bundle CON-120 = CON-212.

Landing (2026-11-11): independent review GO-with-follow-ups (reviewer Claude Opus 5.5, all findings minor-class, section 11.4.276(G)); PROVISIONAL-DONE (section 11.4.290), writer-level e2e still owed (disk floor). Same question as CON-172 (link, section 11.4.214). Follow-ups: CON-213 (M1, CON-172 link and operator-decision confirmation, UNCONFIRMED), CON-214 (M2, stale line citations), CON-215 (M3 empty CG_SAFE_PATCHES test + R4 mutant, nits N1-N3).

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 3: the 2026-11-06 relayed instruction is confirmed by the operator as the section 11.4.66 decision approving the registry-driven writer default; CON-172 is closed Obsolete duplicate-of this item and CON-213 is closed Completed.

## CON-212 — test_unit_safe.sh U59 fails when TMPDIR is long: r1 matches the untruncated limits-file path text while codegraph_safe.sh echoes it through san (cut -c1-200)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (cg117 subagent)

Parent: CON-031. Found while running the full test_unit_safe.sh for CON-117 on 2026-11-06: U59 FAIL detail r=1000 on the bundle head 6435c2c3 without any CON-117 change, with TMPDIR under the session scratch directory (about 150 characters). With a short TMPDIR U59 passes. r1 checks has_txt 'config/index/writer_limits.yaml min_mem_avail_gib' but the tool prints min_mem_avail_source= through san, which cuts at 200 characters, so the file name is truncated. Fix in the test (use the s200 helper as other cases do), test first; evidence docs/qa/con117_writer_default/unit_safe_full.txt and u59_short_tmpdir.txt. Id map (re-minted 2026-11-11): bundle CON-120 = this item; its sibling bundle CON-117 = CON-211.

## CON-214 — codegraph_safe.md: refresh or drop the stale line citations in the rows edited by CON-211 (cg117 review M2)

**Status:** Queued
**Type:** Task
**Severity:** Low

Parent: CON-211. Review M2 (process-doc, minor): the revision-6 note says citations after line 77 are 'now 5 higher', but the rev-5 base citation for the PATCHES line was already wrong (doc 252, main had 257, vehicle 262). The edited table row still says '(line 252)'. Fix: cite 262, 296-298 and 559 as measured on the landed tree, or drop line numbers in favour of function/variable names.

## CON-215 — test_unit_safe.sh U38: add d6 for an empty CG_SAFE_PATCHES="" falling back to the registry default, plus the matching mutant (cg117 review M3, reviewer mutant R4 survived)

**Status:** Queued
**Type:** Task
**Severity:** Low

Parent: CON-211. Review M3 (test-instrumentation, minor): reviewer mutant R4 (${CG_SAFE_PATCHES:-default} -> ${CG_SAFE_PATCHES-default}) SURVIVED: no test asserts that CG_SAFE_PATCHES="" falls back to the default. Behaviour is pre-existing and unchanged; this is a coverage gap, not a defect. Fix: add a d6 assertion to U38 (empty env forwards no --patches) and a mutant matching R4 in test_bulk_classify_mutate.py; observe the mutant KILLED. Also in scope, nits N1-N3 of the same review: N1 the cg117 bundle ref was HEAD, not vehicle/cg117 (process note only); N2 the validation case arm 'default|all) ;;' in codegraph_safe.sh is redundant (R5 equivalent mutant) and may stay for readability or be removed; N3 the evidence directory docs/qa/con117_writer_default/ carries an id that names a different item on main (mapped in its README; rename optional, never rewrite history).

## CON-216 — CON-161 follow-up: pin reason=unmeasured when FC_GUARD_THREADS is unset and ps fails (reviewer mutant RD survives)

**Status:** Ready for testing
**Type:** Bug
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — red-command `PATH=<dir with ps that exits 3>:$PATH FC_GUARD_ULIMIT_U=1000 python3 -I -c '<import host_report; print(_read_ulimit_threads())>' (FC_GUARD_THREADS unset)` — green-command `bash scripts/fastcycle/tests/test_host_report_probe_thread_headroom_r2_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `_read_ulimit_threads returns thr 0 and probe_thread_headroom thread_headroom=1000 when ps fails` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `the thread count was read from 'ps | wc -l' in sh; the pipeline status is the one of wc, so a failed ps counted as 0 threads` — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-161. Review finding m1 (minor, test-instrumentation). The r2 guard test_host_report_probe_thread_headroom_r2_regression.sh reaches thr None only through FC_GUARD_THREADS=xyz (the int() path), never through the ps-failure path (rc != 0 or out is None) of _read_ulimit_threads in host_report.py. Reviewer mutant RD (a failed ps reads as 0 threads, so headroom becomes the whole soft limit) survives r2 6/0, host_report r1 45/0 and test_host_limits_red 140/0. Fix: a case with FC_GUARD_THREADS unset and a PATH shim ps (or sh) that exits non-zero, asserting reason=unmeasured; RD as its paired mutant. Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): the review called this test-instrumentation, but the live reproduction showed a source defect. In _read_ulimit_threads of scripts/fastcycle/host/host_report.py the thread count came from sh -c 'ps ... 2>/dev/null | wc -l', and the exit status of that pipeline is the one of wc, so a ps that fails read as "0" threads: with FC_GUARD_THREADS unset and a PATH shim ps that exits 3 the real function returned (1000, 0) and probe_thread_headroom went on with thread_headroom=1000 (the whole soft limit), exactly the behaviour of reviewer mutant RD. ps now runs directly (ps -L --no-headers -U <real uid>) and its lines are counted in Python, so a failed or unrunnable ps leaves the count None and the probe reports reason=unmeasured. Note: the count no longer includes the sh and wc processes of the old pipeline. Test: test_host_report_probe_thread_headroom_r2_regression.sh gains case PS_FAILS (FC_GUARD_THREADS unset, shim ps first on PATH, expect reason=unmeasured) and adopts RD verbatim as paired mutant RD_failed_ps_reads_zero (scoped to _read_ulimit_threads). RED: PS_FAILS failed on the pre-fix source (6 pass / 1 fail). GREEN: 7 pass / 0 fail under bash and sh, RD killed; r1 regression 45/0; test_host_limits_red SKIPs outside a consumer layout (as before). Evidence docs/qa/con216_220_fu_a_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/fastcycle/tests/test_host_report_probe_thread_headroom_r2_regression.sh and sh of the same file on main after landing, plus test_host_limits_red.sh in a consumer layout -- checks: 7 pass / 0 fail, RD killed; host_limits_red green in a consumer -- layer: runtime (host, real function with a PATH shim ps) -- target: host, repo checkout; consumer layout UNCONFIRMED here -- artifact: commit that lands the fix216 CON-216 change -- due: next full-suite run.

## CON-217 — CON-162 follow-up: pin the section 11.4.263 refusal of kill_session for sid 0, 1, negative and non-int (reviewer mutant RG survives)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — red-command `bash <pre-change test_enumerate_decision_mutants_r2_regression.sh> against a copy of the tool with RG applied` — green-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `mutant RG (if not isinstance(sid, int):) survives the r2 test rc 0` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `no test called kill_session with a refused sid, so the section 11.4.263 refusal was carried only by the code` — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-162 (n1). Review finding m2 (minor, test-instrumentation). kill_session in scripts/validation/enumerate_decision_mutants.py refuses a non-int sid or sid <= 1 with ValueError before any signal, but no test asserts it; reviewer mutant RG (drop the sid <= 1 refusal) survives the r2 test 4/0. Under section 11.4.263(C) the test, not only the code, must carry the guard. Fix: in the r2 driver call kill_session(1), kill_session(0), kill_session(-5) and kill_session('7') with os.kill patched to record-and-refuse (unit scope, so a mutated guard can never signal anything), asserting ValueError and zero recorded kills; RG as the paired mutant. Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): test_enumerate_decision_mutants_r2_regression.sh now calls kill_session(1), kill_session(0), kill_session(-5) and kill_session('7') with os.kill replaced by a record-and-refuse stub (restored afterwards), asserting ValueError for each and zero recorded signals; reviewer mutant RG (drop the sid <= 1 refusal) is adopted verbatim as paired mutant RG_drop_sid_le_1_refusal. RED: RG survived the pre-change r2 test (rc 0, 4/0). GREEN: r2 18 checks + 7 mutants pass, RG killed. Evidence docs/qa/con216_220_fu_a_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh on main after landing -- checks: pass=7 fail=0, RG killed -- layer: gate-logic (test-instrumentation, unit scope with a stubbed os.kill) -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-218 — CON-162 follow-up: test the STALE-on-KILLED wiring in main() of the decision-mutant census (reviewer mutant RI survives)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — red-command `bash <pre-change test_enumerate_decision_mutants_r2_regression.sh> against a copy of the tool with RI applied` — green-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `mutant RI (if False and is_stale_killed(...)) survives the r2 test rc 0` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `the r2 test called is_stale_killed directly and never drove main(), so the call site that bumps STALE was untested` — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-162 (n2). Review finding m3 (minor, test-instrumentation). The r2 test calls is_stale_killed directly; the call site in main() of scripts/validation/enumerate_decision_mutants.py that bumps res[STALE] (and so the exit code) has only the author's one-off end-to-end evidence (docs/qa/con162_census_nits_2026_11_11.txt). Reviewer mutant RI (call site becomes if False and ...) survives 4/0. Fix: drive main() on a scratch target whose single mutant is killed and planted in a temp ledger (or factor the classification loop), asserting the STALE line and exit 1; RI as the paired mutant. Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): the r2 driver now runs the REAL main() of scripts/validation/enumerate_decision_mutants.py on a synthetic target (a temp git root holding scripts/syn.sh, its test and a ledger entry for its one nz_flip mutant, which the test kills), asserting the STALE line ('mutant is KILLED') and return 1; control: the same run without the ledger entry returns 0 with no STALE line. Reviewer mutant RI (the call site made if False and ...) is adopted verbatim as RI_stale_call_site_off. RED: RI survived the pre-change r2 test (rc 0). GREEN: RI killed. Evidence docs/qa/con216_220_fu_a_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh on main after landing -- checks: pass=7 fail=0, RI killed -- layer: gate-logic (real main() on a synthetic target) -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-219 — CON-159 follow-up: the census wording guard only matches the three historical phrases (reviewer mutant RH survives)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — red-command `checks() of the pre-change wording guard on a copy of the tool with RH applied` — green-command `bash scripts/validation/test_decision_mutant_census_wording_r1_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `the wording guard returns 0 on 'enumerates all decision points'` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `the wording guard matched only the three historical phrases` — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-159. Review nit n1 (test-instrumentation). test_decision_mutant_census_wording_r1_regression.sh rejects only the three exact historical overstatements; a re-overstatement in other words (reviewer mutant RH: docstring 'enumerates the decision points' becomes 'enumerates all decision points') passes 4/0. Acceptable for a wording guard; optional fix: also require the scope sentence (not that every decision point is covered) to be present, with RH as the paired mutant. Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): test_decision_mutant_census_wording_r1_regression.sh now pins the docstring's accurate scope sentences (whitespace normalised: 'enumerates the decision points of a fixed set of target scripts that are matched by its closed list of single-edit operators' and 'not that every decision point is covered') and rejects any '(enumerates|covers|mutates|generates) (all|every|each) decision point' wording, case-insensitive. The reviewer's suggestion alone (require the scope sentence) would not have killed RH, since RH keeps that sentence; the pin of the first sentence does. Reviewer mutant RH adopted verbatim (RH_enumerates_all) plus M4 (scope sentence reworded). RED: the pre-change guard passed RH (rc 0). GREEN: 6 checks, 5 mutants killed. Evidence docs/qa/con216_220_fu_a_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/validation/test_decision_mutant_census_wording_r1_regression.sh on main after landing -- checks: pass=6 fail=0 -- layer: gate-logic (wording guard over the real files) -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-220 — CON-162 follow-up: decide whether a ledger key whose mutant is KILLED-TIMEOUT is flagged STALE

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — red-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh (new KILLED-TIMEOUT check) on the pre-fix tool` — green-command `bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `is_stale_killed('KILLED-TIMEOUT', key in ledger) returns False` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `is_stale_killed tested verdict == KILLED only, while the census counts KILLED-TIMEOUT as a kill` — evidence `docs/qa/con216_220_fu_a_followups_2026_11_11.txt` — updated 2026-11-11T15:08:14Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-162 (n2). Review nit n2. is_stale_killed in scripts/validation/enumerate_decision_mutants.py tests verdict == KILLED only; the census counts KILLED-TIMEOUT as a kill elsewhere, so a false equivalence proof passes silently when the mutant hangs. Fix: either flag KILLED-TIMEOUT as STALE too (with a test and paired mutant), or record in the script why a timeout is not a refutation (load-induced timeouts). Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): decision taken: a ledger key whose mutant is KILLED-TIMEOUT is STALE too. An equivalent mutant behaves like the original, and the original's test finished inside the same budget (the control needle), so a timeout either refutes the proof or leaves it unconfirmed (a load-induced timeout); either way the entry is re-examined, never passed silently (fail closed). is_stale_killed and the module docstring say so. Test: two new r2 checks (KILLED-TIMEOUT with and without a ledger entry) and paired mutant M4_stale_ignores_timeout (the pre-fix KILLED-only classifier). RED: the KILLED-TIMEOUT check failed on the pre-fix tool. GREEN: r2 pass, M4 killed; selftest 24/0; test_enumerate_decision_mutants.sh 13/0. Not run: the full census over the real targets (heavy); a ledger entry that now hits a load-induced timeout would show as STALE, which is the intended fail-closed outcome. Evidence docs/qa/con216_220_fu_a_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/validation/test_enumerate_decision_mutants_r2_regression.sh on main after landing, then the census run with every target -- checks: r2 pass=7 fail=0; census stale=0 -- layer: gate-logic -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-221 — CON-162 n3 own item: stash_index_unpatched uses porcelain git diff --quiet (diff.ignoreSubmodules, external drivers) instead of plumbing git diff-tree

**Status:** Queued
**Type:** Task
**Severity:** Low

Parent: CON-162 (n3). Review nit n3 (process-doc): n3 was recorded inside CON-162 as not reproduced and not fixed; this item gives it a tracked home (section 11.4.197). stash_index_unpatched in scripts/validation/custody_sweep.py runs porcelain git diff --quiet ^1 ^2, which is subject to diff.ignoreSubmodules and external diff drivers; plumbing git diff-tree --quiet ^1 ^2 is not. UNCONFIRMED: whether this changes a verdict on any real tree; reproduction needs a fixture with a real submodule (or a configured external driver) whose index differs only in a way porcelain ignores. Section 11.4.292: reproduce first, then fix. Follow-up of the independent Opus review of the fu_a vehicle (CON-159..CON-162; verdict GO-with-follow-ups, 0 critical, 0 important, 3 minor, 4 nit; record docs/qa/review_fu_a_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-222 — CON-185 follow-up: a skipped L29 leg does not change the helper suite's result (reviewer mutants RV-E and RV-F survive)

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — red-command `FC_L29_CANDIDATES=zz_ZZ.UTF-8 FC_HELPER_UNDER_TEST=<helper> bash <pre-change test_consumer_required_helper.sh with RV-E or RV-F applied>` — green-command `bash scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `a simulated no-locale run ends SUMMARY N pass / 0 fail and rc 0; RV-E and RV-F survive` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `the L29 SKIP line was only echoed; no skip count existed, so the suite verdict could not see it` — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-185. Review finding F1 (minor, test-instrumentation). The L29 SKIP-with-reason of scripts/fastcycle/tests/test_consumer_required_helper.sh is honest in wording (closed reason topology_unsupported, not passed through ok()), but it does not reach the suite verdict: the run still ends SUMMARY: N pass / 0 fail with exit 0 and no skip count, while the same script exits 77 when dash is absent. A host without the locale reports fully green with a leg not run (section 11.4.201(6) false-null at the aggregate). The branch proof covers l29_verdict's output only, not the dispatch: reviewer mutant RV-E (the SKIP counted as a PASS through ok) and RV-F (the SKIP line dropped) both survive rc 0 under FC_L29_CANDIDATES=zz_ZZ.UTF-8. Fix: when L29 skips, set a skip flag and exit 77 (or emit a counted skip= in SUMMARY), and add a leg or mutant that runs the dispatch under the simulated topology and asserts the SKIP line and the non-zero skip outcome, so RV-E and RV-F die. Follow-up of the independent Opus review of the fu_b vehicle (CON-183, CON-184, CON-185, CON-102 M6 partial; verdict GO-with-follow-ups, 0 critical, 0 important, 2 minor, 2 nit; record docs/qa/review_fu_b_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): scripts/fastcycle/tests/test_consumer_required_helper.sh now counts a skipped leg: skipped() raises S and names the leg, the L29 verdict line goes through the function l29_dispatch (an ok line through ok, a SKIP line printed AND counted, never through ok), the SUMMARY line reads 'N pass / F fail / S skip (skipped: L29)', and when S > 0 the run ends 'SKIP: S leg(s) did not run: L29 reason=topology_unsupported' with exit 77 instead of 0. The SKIP branch of l29_dispatch is proven on every run (a probe line must print and give P=0 S=1), plus an ok control. New regression test scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh runs the whole real helper test on a copy of the tracked scripts/ tree and Constitution.md under FC_L29_CANDIDATES=zz_ZZ.UTF-8 (Part 4 skipped through FC_HELPER_UNDER_TEST) and requires rc 77, 0 NOT ok, the SKIP: L29 line, the counted SUMMARY and the override note; paired mutants RV-E and RV-F (verbatim, on the dispatch function), M3 (the final exit ignores the count) and M4 (no note) are each killed. RED: on the pre-change test RV-E and RV-F survived rc 0 (344/0 and 343/0) and the unmutated simulated run ended rc 0. GREEN: control rc 77 (348 pass / 0 fail / 1 skip), 4 mutants killed, about 3.5 minutes. On this host (locales present) the real helper test still ends rc 0. Consequence for the CON-185 verification job: its simulated-host run now ends rc 77, not rc 0 (intended). Evidence docs/qa/con222_224_fu_b_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh and bash scripts/fastcycle/tests/test_consumer_required_helper.sh on main after landing -- checks: pass=5 fail=0; the real helper test rc 0 on a host with locales -- layer: gate-logic (test-instrumentation; the real helper test run whole on a copy) -- target: host, repo checkout; a real host without locales UNCONFIRMED (not available) -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-223 — CON-185 follow-up: an ambient FC_L29_CANDIDATES value is honoured silently and can turn L29 into a SKIP

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — red-command `FC_L29_CANDIDATES=zz_ZZ.UTF-8 FC_HELPER_UNDER_TEST=<helper> bash <pre-change test_consumer_required_helper.sh>` — green-command `bash scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `the run with the override set prints no note and ends rc 0` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `the test hook FC_L29_CANDIDATES was read without any notice and its SKIP did not reach the exit code` — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-185. Review finding F2 (minor, test-instrumentation). FC_L29_CANDIDATES is test-only (it lives in the test file; the production helper is untouched), but it is read unconditionally from the ambient environment: an unquoted ${FC_L29_CANDIDATES:-...} means a whitespace or bogus value (" " expands to empty) turns a real host's L29 into a SKIP with rc 0, and nothing says an override was in effect. With CON-185 F1 (the SKIP not reaching the verdict) this is a silent weakening switch for the test. Fix: print a note such as 'note: FC_L29_CANDIDATES override in effect' (with its value) whenever the variable is set, and make an override-driven SKIP non-zero per the F1 follow-up. Follow-up of the independent Opus review of the fu_b vehicle (CON-183, CON-184, CON-185, CON-102 M6 partial; verdict GO-with-follow-ups, 0 critical, 0 important, 2 minor, 2 nit; record docs/qa/review_fu_b_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): when FC_L29_CANDIDATES is set at all (also empty or blank), the helper test prints 'note: FC_L29_CANDIDATES override in effect: [<value>] (CON-223; a SKIP it causes ends the run with 77)', and a SKIP the override causes now ends the run with exit 77 (CON-222). The expansion is unchanged (an empty value still falls back to the default list, a blank one gives an empty list and so a counted SKIP). Pinned by the CON-222 regression test (the note must be present; paired mutant M4_no_override_note killed). RED: the pre-change simulated run printed no note (0 note lines) and ended rc 0. Evidence docs/qa/con222_224_fu_b_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh on main after landing -- checks: pass=5 fail=0, M4 killed -- layer: gate-logic (test-instrumentation) -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-224 — CON-183 follow-up: reviewer mutant RV-C (pwd -P in the consumer-root resolution) survives; add a symlinked consumer-root leg or record it equivalent

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — red-command `FC_HELPER_UNDER_TEST=<helper copy with RV-C> bash <pre-change test_consumer_required_helper.sh>` — green-command `bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON224-RVC` — env `host fixture; Linux 7.0.0, bash 5.3.9, python 3.14.4` — signature `RV-C (pwd -P) survives the helper test rc 0` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`
**Investigation:** root-cause-found-with-evidence — root-cause `no leg reached the consumer root through a symlinked parent, the only case where pwd and pwd -P differ for the message` — evidence `docs/qa/con222_224_fu_b_followups_2026_11_11.txt` — updated 2026-11-11T15:12:44Z — by `AI (Claude Opus 5.5, fixer fix216)`

Parent: CON-183. Review finding F3 (nit, pre-existing gap outside the fu_b change). Reviewer mutant RV-C (&& pwd) -> && pwd -P) in the root resolution of scripts/fastcycle/tests/lib/consumer_required.sh) survives both the mutation harness and the real-helper full suite including Part 4 (365/0, rc 0). It differs from mutant M4 only when the consumer root itself is reached through a symlink (the SKIP message then names the physical root). The CON-183 bound statement is accurate; RV-C is a coverage gap of both the harness and the real suites, not a mis-stated bound. Fix: a Part 3b leg with a consumer root under a symlinked parent that asserts the SKIP message names the logical root, with RV-C adopted as its paired mutant; or record RV-C as equivalent-for-behaviour with the reason. Follow-up of the independent Opus review of the fu_b vehicle (CON-183, CON-184, CON-185, CON-102 M6 partial; verdict GO-with-follow-ups, 0 critical, 0 important, 2 minor, 2 nit; record docs/qa/review_fu_b_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status at landing: Ready for testing; a fix is claimed and is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes; not VERIFIED-DONE.

Fix note (fix216, 2026-11-11): Part 3b of scripts/fastcycle/tests/test_consumer_required_helper.sh gains a leg with the consumer root reached through a symlinked PARENT ($SYM/lp -> $SYM; needle: logical and physical root differ) that asserts, in bash and dash, rc 77 and a SKIP line naming the logical root ($SYM/lp/consumer). Reviewer mutant RV-C ('&& pwd)' -> '&& pwd -P)') is adopted verbatim as hand-table row CON224-RVC in test_consumer_required_mutations.sh. RED: RV-C survived the pre-change helper test (352 pass / 0 fail, rc 0). GREEN: the harness run 'test_consumer_required_mutations.sh CON224-RVC CON183-M4' reports both killed (CON224-RVC by the new leg, 2 failing checks). Evidence docs/qa/con222_224_fu_b_followups_2026_11_11.txt.

**Verification:** provisional (section 11.4.290) -- job: bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON224-RVC on main after landing -- checks: killed -- layer: gate-logic (test-instrumentation; real helper in a symlinked layout) -- target: host, repo checkout -- artifact: commit that lands the fix216 change -- due: next full-suite run.

## CON-225 — fu_b review nit N2: the CON-183 evidence file cites 2 failing checks for M4 at 0ca66af7, the vehicle head gives 6; the bundle head ref was fu-b, not main

**Status:** Queued
**Type:** Task
**Severity:** Low

Parent: CON-183. Review finding N2 (nit, process-doc). docs/qa/con183_reproduction_2026_11_11.txt records 2 failing checks for mutant CON183-M4 at commit 0ca66af7; at the vehicle head 96702413 the same mutant fails 6 checks, because the spaced-path legs added later by the CON-102 partial fix also fail under it. The reviewer judged this consistent, not wrong, but a reader comparing the evidence with a fresh run sees a different count. Also, the brief named the bundle head ref main while the bundle carried fu-b. Fix: add a dated note to the CON-183 evidence file stating the commit each count was measured at and the head count (6), and name the bundle ref correctly in future landing briefs. Follow-up of the independent Opus review of the fu_b vehicle (CON-183, CON-184, CON-185, CON-102 M6 partial; verdict GO-with-follow-ups, 0 critical, 0 important, 2 minor, 2 nit; record docs/qa/review_fu_b_2026_11_11.md). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-226 — v73.4 release tooling: tag_and_release, derive release facts, render release entry, killpg guards (vehicle rel734)

**Status:** Ready for testing
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

Vehicle vehicle/rel734 (commits a24f935c, ec58c0ae on base fc57ad0c), landed on main 2026-11-11 by a merge commit that carries the Roadmap-Item trailer for this item. Content: CM-KILLPG-PGID-GUARD regression fixed (7 unguarded process-group signal sites on fc57ad0c guarded or marked with the audited killpg-gate:allow comment; gate PASS after); the PROVISIONAL Version-badge rule in scripts/badges/compute_badges.sh made case-insensitive; new scripts/release/derive_release_facts.sh (release counts and id lists from committed data and the tracker, no tracker value put back into SQL text), scripts/release/render_release_entry.py (fills a template, refuses an unfilled key), scripts/release/tag_and_release.sh (preflight of every remote before any write, atomic push per remote, read-back, releases only for remotes read back OK, resume, never force), the v73.4 entry template and docs/release/README.md, with tests tests/release/test_tag_and_release.sh (45), test_derive_release_facts.sh (29), test_render_release_entry.sh (16 with RRE_FACTS set). Section 11.4.293(A) record: the two vehicle commits carry no Roadmap-Item trailer and no item was registered before the work (review finding m-8); the commits were not rewritten (section 11.4.113), the trailer is on the landing merge commit instead. At landing main had added a new process-group signal text site (scripts/validation/test_enumerate_decision_mutants_r2_regression.sh:94, a mutant replacement string, not a call); it got the audited killpg-gate:allow marker in a real shell comment. Nothing was tagged or published; gh/glab are stubs in the tests (unit class, section 11.4.289(C)); no real platform release has been made with the script.

Landing (2026-11-11): independent review GO-with-follow-ups (reviewer Claude Opus 5.5, 0 critical, 0 important, 9 minor, 5 nit, section 11.4.276(G)), record docs/qa/review_rel734c_2026_11_11.md. The release commit the cut produces still needs its own review GO before tag_and_release.sh runs without --dry-run (docs/release/README.md step 7). Follow-ups (section 11.4.276(G.2)): CON-227 (m-1, m-7: 7 surviving mutants T2-T6, D1, D5), CON-228 (m-2 partial facts exit 0), CON-229 (m-3 waiver wording), CON-230 (m-4 FINAL waiver vs QA confirmation), CON-231 (m-5 fixed status/severity keys), CON-232 (m-6 silent smoke skip), CON-233 (m-9 gitea rc 3), CON-234 (nits n-1 to n-5); m-8 is handled by this item and the merge trailer.

**Verification:** provisional (section 11.4.290) -- job: re-run tests/release/test_tag_and_release.sh (45 passed, 0 failed), tests/release/test_derive_release_facts.sh (29/0), tests/release/test_render_release_entry.sh with RRE_FACTS from derive_release_facts.sh on main (16/0) and scripts/gates/cm_killpg_pgid_guard.sh (PASS) on main after landing, then the first real tag_and_release.sh run of the v73.4 cut read back on every remote -- checks: all pass, gate PASS, every remote read back OK or an honest GAP -- layer: runtime (host) -- target: host, repo checkout and the eight upstream remotes -- artifact: main after this landing -- due: 2026-11-18.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 4 (release v73.4): PROVISIONAL pre-release; the vasic-digital GitHub release API answers 404, so that platform release is skipped and the gap is recorded; section 11.4.271 agent-roster QA waiver authoriser milosvasic, expiry 30 days from the date the waiver is recorded (the waiver is recorded after the work lands, not yet); retest on final main first (default tier, then --include-heavy; --allow-topology-gaps gives PARTIAL, labelled PARTIAL) before tagging; one consolidated CHANGELOG entry at the release.

## CON-227 — CON-226 follow-up: tests that kill the 7 surviving reviewer mutants T2-T6 (tag_and_release.sh) and D1, D5 (derive_release_facts.sh)

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-1 and m-7. Surviving mutants, each checked correct in behaviour by the reviewer, so these are test gaps: T2 is_ok compares main only (resume skip must require the tag too); T3 drop the check that the remote tag equals the local tag object; T4 drop the clean-tree check; T5 gitea rc 3 reported as OK instead of GAP (no case runs the gitea leg); T6 drop the HEAD == SHA check; D1 verified count uses >= the previous tag date (needs a fixture closed exactly on that date and a decision whether that day is in or out); D5 the any-state count ignores investigation_state (needs an item with UNSET reproduction and a set investigation state). Add cases (reviewer harness cases a-f) to tests/release/test_tag_and_release.sh and tests/release/test_derive_release_facts.sh; each mutant must make its suite fail.
Done here: tests C13 (dirty tree, T4), C14 (HEAD later than SHA, T6), C15 (correct local tag and a remote impostor, T3), C16 (remote main already SHA without the tag, T2), C17-C20 (gitea leg through a publisher double, T5) in tests/release/test_tag_and_release.sh; the D1 (closed on the previous tag date: NOT counted, the stated rule; whether that day counts is not an operator decision on record) and D5 (UNSET reproduction with a set investigation state) fixture in tests/release/test_derive_release_facts.sh; new tests/release/test_release_tooling_mutations.sh applies T2, T3, T4, T6, D1, D5 verbatim and T5 re-applied to the rewritten rc 3 branch; all killed. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).


## CON-228 — CON-226 follow-up: derive_release_facts.sh exits 0 with a partial set of facts when a tracker column is missing

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con227_234_2026_11_11/red_all.txt` — red-command `DRF_SCRIPT=<git show 24bdca78:scripts/release/derive_release_facts.sh> bash tests/release/test_derive_release_facts.sh` — green-command `DRF_SCRIPT=<fixed script> bash tests/release/test_derive_release_facts.sh` — env `host, bash, git, sqlite3; fixtures built by the test` — signature `CON-228 [<column>]: missing column exits 3 (got 0)` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`
**Investigation:** root-cause-found-with-evidence — root-cause `q and qa ran sqlite3 with no status check, so a failed query left a fact empty and the script exited 0; mutants O3, O4, O7 restore it` — evidence `docs/qa/con227_234_2026_11_11/round2.txt` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-2. No pipefail and no check of sqlite exit codes: measured on a tracker without reproduction_state it prints 'Error: in prepare, no such column' twice, leaves open_items_with_any_state empty and omits every open_states line, and exits 0, against its own header (exit 3, never a partial set of facts). The renderer refuses the missing keys downstream, so no wrong entry is rendered, but the script must fail closed: check each query's status and exit 3, with a RED test first.
Done here: the script buffers stdout and flags any failed query in both wrappers q and qa; exit 3 with stdout empty. Three fixtures, each missing one column (reproduction_state, closure_date read only through q, body_md read only through qa); own mutants O3, O4, O5, O7 killed. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).
 Round 2 (review docs/qa/review_fix227.md, NO-GO on F1 only): the script now also fails closed (exit 3, empty stdout, CHANGELOG.md named) when the base has no CHANGELOG.md (F6; test F6, mutant F6); the temp-file check is made real with a private TMPDIR and a positive control (F2; adopted reviewer mutant R5 killed). Evidence: docs/qa/con227_234_2026_11_11/round2.txt.
 Round 3 (G5): the refusal for a missing CHANGELOG.md is one script-owned line (derive_release_facts: CHANGELOG.md is missing at the base ...) and no longer says a tracker query failed; the test asserts that line, not git's own text; the stderr of sqlite3 and git is flushed at exit through the redact-then-cut helper. Round 4: derive_release_facts.sh gained set +x, GIT_TRACE_REDACT=1 and HUP/INT/TERM traps ending through its EXIT cleanup; its exit-time flush goes through the rewritten helper with a truncation marker (docs/qa/con227_234_2026_11_11/round4/green_derive_release_facts.txt). The CON-228 behaviour itself is unchanged. Round 5: derive_release_facts.sh validates --base and --prev-tag and remote names before use and never echoes them (cases V1-V4), clears the caller's git trace switches, keeps its tracker copy in a 0700 directory (V13). Evidence docs/qa/con227_234_2026_11_11/round5/red_derive_release_facts.txt and green_derive_release_facts.txt. Round 6: derive_release_facts.sh calls rc_env_lockdown before any external command (date moved after it, K5), so git, sqlite3 and date get an allow-listed environment (case K3); its HUP/INT/TERM traps are exercised by signal (case X10). Evidence docs/qa/con227_234_2026_11_11/round6/red_derive_release_facts.txt and green_derive_release_facts.txt.

## CON-229 — CON-226 follow-up: the v73.4 entry template's waiver wording 'recorded operator override' overclaims a decision that may only be relayed

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-3. The template asserts the override is recorded while the same paragraph allows the decision to be 'relayed, not verbatim'. Say 'recorded' only when a tracked record is cited, otherwise 'a relayed operator decision' (section 11.4.6).
Done here: docs/release/helixconstitution-v73.4_entry.template.md says the decision is called recorded only where its field cites a tracked record, otherwise a relayed operator decision. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).


## CON-230 — CON-226 follow-up: FINAL precondition 2 in the v73.4 template must not accept a section 11.4.271 waiver in place of the section 11.4.185 QA confirmation

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-4. A production-class (FINAL) release needs every scope production-ready (section 11.4.230(F.3)(2)), which needs a valid qa-confirmation record (section 11.4.230(E.3)(a), Q). Remove the waiver alternative for FINAL, or state that a waived FINAL is another provisional-class release.
Done here: FINAL precondition 2 asks for a recorded section 11.4.185 confirmation; a section 11.4.271 waiver may stand in only as a tracked record naming the rostered non-producer authoriser, an unelapsed expiry and the tracked item owing the human QA, and the FINAL entry then says the confirmation is waived and that section 11.4.230(F.3)(2) is not passed. docs/release/README.md records the operator decision relayed 2026-11-11 (agent-roster QA under such a waiver, 30 days) as relayed, not as a record. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).


## CON-231 — CON-226 follow-up: template fixed status/severity keys let a new value at cut time drop silently from the release entry

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con227_234_2026_11_11/red_all.txt` — red-command `RRE_SCRIPT=<git show 24bdca78:scripts/release/render_release_entry.py> bash tests/release/test_render_release_entry.sh` — green-command `RRE_SCRIPT=<fixed script> bash tests/release/test_render_release_entry.sh` — env `host, bash, git, sqlite3; fixtures built by the test` — signature `CON-231 a status/severity value the template does not render is refused (0: )` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`
**Investigation:** root-cause-found-with-evidence — root-cause `the renderer refused missing template keys but not extra open_status/open_severity facts; mutant O6 restores it` — evidence `docs/qa/con227_234_2026_11_11/green_all.txt` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-5. The template names Queued, Ready for testing, In progress, Operator-blocked and high, medium, low. A value new at cut time (In testing, Reopened, critical, none) would be dropped without notice: the renderer refuses missing keys but not extra fact keys. Make the renderer refuse an open_status[...]/open_severity[...] key the template does not use, or render those lines from the facts as states_block is.
Done here: scripts/release/render_release_entry.py refuses (exit 3, stdout empty) an open_status[...] or open_severity[...] fact the template does not render; own mutant O6 killed; the shipped template renders from the facts of 24bdca78. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).
 Round 2 (review docs/qa/review_fix227.md, NO-GO on F1 only): no change in round 2; states set per section 11.4.294(E) (review F7).

## CON-232 — CON-226 follow-up: the shipped-template smoke case in test_render_release_entry.sh is skipped silently unless RRE_FACTS is set

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-6. Without RRE_FACTS the suite prints 15 checks instead of 16 and no SKIP line (section 11.4.3). Print a SKIP with a reason, or ship a small facts fixture so the case always runs.
Done here: the smoke case always runs over the shipped template with synthetic facts named by the template; the real-facts case prints an explicit SKIP line when RRE_FACTS is not set (old file: 15 checks, no SKIP line, docs/qa/con227_234_2026_11_11/red_render.txt). Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).


## CON-233 — CON-226 follow-up: tag_and_release.sh counts gitea publisher exit code 3 as a gap, but rc 3 also covers configuration failures

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con227_234_2026_11_11/red_all.txt` — red-command `TAR_SCRIPT=<git show 24bdca78:scripts/release/tag_and_release.sh> bash tests/release/test_tag_and_release.sh` — green-command `TAR_SCRIPT=<fixed script> bash tests/release/test_tag_and_release.sh` — env `host, bash, git, sqlite3; fixtures built by the test` — signature `C19 gitea rc 3 without SKIPPED-NO-TOKEN is a FAIL (got 5, want 1)` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`
**Investigation:** root-cause-found-with-evidence — root-cause `rc 3 of the gitea publisher was counted as a gap whatever its reason; mutants T5, R2 restore it` — evidence `docs/qa/con227_234_2026_11_11/round2.txt` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Review m-9. The publisher's rc 3 covers a missing token and also a bad token charset and a missing jq/curl, which are configuration failures, so exit 5 then reads as 'only gaps'. Make the publisher return a distinct code for a missing token, or report rc 3 as SKIPPED-OR-REFUSED and count it a failure unless its stderr says SKIPPED-NO-TOKEN.
Done here: tag_and_release.sh reads the publisher's stderr; exit 3 is a GAP only with the SKIPPED-NO-TOKEN line, any other exit 3 is a FAIL naming the publisher's message; the publisher is unchanged. C18, C19 (double) and C22, C23 (real publisher) cover it; own mutant O2 killed. Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).
 Round 2 (review docs/qa/review_fix227.md, NO-GO on F1 only): adopted reviewer mutants R2 (unanchored SKIPPED-NO-TOKEN, case C20b) and R6 (gitea temp file not removed, case C20c) are killed. Evidence: docs/qa/con227_234_2026_11_11/round2.txt.
 Round 3 note: the publisher scripts/release_publish_gitea.sh is no longer unchanged: its curl failure message and its other stderr go through the redact-then-cut helper (CON-234). Round 4: the publisher's stderr is captured into a variable (no temp file); rc 3 is still told apart by its SKIPPED-NO-TOKEN: line (C19-C23 unchanged and GREEN, docs/qa/con227_234_2026_11_11/round4/green_tag_and_release.txt); the publisher now refuses a non-numeric release id from the server (publisher case 15). Round 5: the gitea publisher's stderr is never printed raw; tag_and_release.sh prints only the publisher's own release_publish_gitea: line, redacted and cut (own1), cases C32, C32b, C32c; the publisher's own curl failure prints the curl exit status and a class word. Evidence docs/qa/con227_234_2026_11_11/round5/. Round 6: the gitea publisher runs through pub(), the only child that gets M3W_GITEA_TOKEN exported (C44); the own-line anchor is held by C46 (mutant X17). Evidence docs/qa/con227_234_2026_11_11/round6/.

## CON-234 — CON-226 follow-up: review nits n-1 to n-5 (changelog marker count, shellcheck level, --release URL check, fetch stderr, gate text-match false positive)

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con227_234_2026_11_11/round6/red_tag_and_release.txt` — red-command `bash tests/release/test_redact_cut.sh; bash tests/release/test_tag_and_release.sh; bash tests/release/test_publish_gitea.sh; bash tests/release/test_derive_release_facts.sh (round-6 tests, the round-5 scripts of 9cd1539a pinned with RC_LIB/TAR_SCRIPT/PUBLISH_SCRIPT/DRF_SCRIPT)` — green-command `the same four commands on the round-6 scripts, plus bash tests/release/test_channel_census.sh` — env `host, bash 5.3, git 2.53, gawk 5.3.2 and mawk, sqlite3; fixtures built by the tests` — signature `a ZZ needle or the token reaches the argv or environment of a child, a userinfo URL reaches git, or a real git fetch against a hanging server outlives the deadline (a git process left after the run)` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`
**Investigation:** root-cause-found-with-evidence — root-cause `round 5 controlled what the scripts print; the channels into each child (argv, environment, process group at the deadline) were not inventoried; fixed with a per-invocation channel census and its lint, rc_env_lockdown, the userinfo refusal and timeout without --foreground` — evidence `docs/qa/con227_234_2026_11_11/round6/threat_model.md` — updated 2026-11-12T00:30:00Z — by `Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)`

Follow-up of CON-226 (review docs/qa/review_rel734c_2026_11_11.md, verdict GO-with-follow-ups, section 11.4.276(G.2), minor class). Nits grouped in one item. n-1: the CHANGELOG says '13 allowed by marker'; the vehicle gate run prints 14 ALLOWED lines (12 on the base), recount (main added one more marked site at landing). n-2: 'shellcheck clean' holds at warning level only; info-level notes remain (SC2015 in the tests, SC2086 in sv()), state the level. n-3: a --release spec is not checked against the remote's URL (github:r1:other/repo is accepted); consider a URL/owner cross-check. n-4: on a failed fetch up to 400 bytes of git stderr are printed; with an HTTPS URL carrying a token this depends on git's URL redaction. n-5: the run_full_suite.py change rewords an error message only so the killpg gate stops reading it as a call, a false positive of the gate's text matching; consider a gate fix.
Done here: n-1 recount on 24bdca78: PASS, 30 sites guarded, 14 allowed by marker (docs/qa/con227_234_2026_11_11/n1_killpg_recount.txt; noted in the new CHANGELOG entry, the older entry is not rewritten); n-2 the new entry states shellcheck clean at warning level only; n-3 not implemented by decision (GitHub legs are de-duplicated by repository id, a name match would refuse aliases), stated in docs/release/README.md; n-4 fetch stderr redacted by the script, tested with a git double (C21, own mutant O1 killed); n-5 not done (a gate change, separate work). Fix on vehicle/fix227 (based on 24bdca78), not yet independently reviewed: the item is In progress, neither PROVISIONAL-DONE nor VERIFIED-DONE (section 11.4.290). Evidence: docs/qa/con227_234_2026_11_11/red_all.txt (RED on the unfixed scripts of 24bdca78 and on the reviewer mutants), docs/qa/con227_234_2026_11_11/green_all.txt (GREEN and tests/release/test_release_tooling_mutations.sh killed=14 survived=0).
 Round 2 (review docs/qa/review_fix227.md, NO-GO on F1 only): F1 (blocking, fixed): the fetch message is now redacted before the 400-byte cut, so a secret whose @ falls past byte 400 is no longer printed; cases C21 (positive needle for the redaction marker) and C21b (long message, RED on 5b630578, GREEN after), mutant F1 killed. Evidence: docs/qa/con227_234_2026_11_11/round2.txt.
 Round 3 (review docs/qa/review_fix227_r2.md, NO-GO on G1, G2, G3; class closed per section 11.4.276(C)): every external-command output the release scripts print now goes through ONE helper, scripts/release/redact_cut.sh (redact userinfo, then cut). G1: the git push failure message was printed unredacted (reproduced); now redacted, case C21c. G2: the pattern stopped at the first @, so a raw @ in the password leaked its tail; now (://)[^/[:space:]]*@ (greedy to the last @ before the path), cases C21c and H1-H4. G3: two URLs in one message (C21c), kills the g-flag mutant N1. G4: the 400-byte cap is asserted (C21e), kills N2. G5: the derive refusal is one script-owned line naming CHANGELOG.md and no longer blames a tracker query; the test asserts the script's own line, not git's. G8: the INFO line no longer says the tag was pushed when the push failed. Also routed through the helper: the fetch message, the gitea publisher refusal line, the exit-time flush of every other external command's stderr in tag_and_release.sh, derive_release_facts.sh and release_publish_gitea.sh (whose curl message was a print site; the publisher is therefore no longer unchanged). Census of the print sites with control needles: docs/qa/con227_234_2026_11_11/round3.txt. Mutants N1, N2, N4 adopted, own P1-P10 added; the full mutation run killed=32 survived=0 stale=0. G6 (other git commands in the buffered section of derive, a shallow clone gives a silently truncated count) stays minor-class, decided: no corrupt-repository fix; the shallow-clone risk is tracked as a follow-up item. G7: the guide census was regenerated with --sync-guide and --verify-manifest passes at the merge of main b20736f8. Not independently re-reviewed after round 3; still In progress. Round 4 (review docs/qa/review_fix227_r3.md, NO-GO on H1, H2, H3; the same class recurred in rounds 1-3 as F1, G2, H1, so this is the section 11.4.276(E)(3) structural round by a fresh fixer instance). The design was re-derived from a written threat model (docs/qa/con227_234_2026_11_11/round4/threat_model.md) instead of patching the pattern again: scripts/release/redact_cut.sh is now an awk filter applied per whole line (header lines, Bearer, URL userinfo from the first :// to the last @ of the line for every scheme, scheme-less user:password@host, credential-named query/fragment/form parameters in any case, known token shapes), redaction before the byte cut, LC_ALL=C inside, NUL dropped, an optional truncation marker (I-3). H1 (raw / in the password, printed verbatim by git 2.53): cases U2 and C25 with the real git binary. H2 (credential query parameters): Q-* cases and C25b. H3 (temp files left after a signal or an error path): one 0700 mktemp -d run directory per script, removed in the EXIT trap, HUP/INT/TERM traps end through it; fetch, push, fallback-push and publisher stderr are captured into variables, not files (C26 leftover census with a control, C27 TERM/HUP, publisher 13/14). I-1 fallback push reason printed redacted (C28); I-2 header lines (A1-A9, publisher 16); I-4 the publisher refuses a non-numeric server release id (publisher 15); I-5 SC2221/SC2222 fixed; GIT_TRACE_REDACT=1 exported and set +x in all three scripts (C26, C30). RED on 34bbeb4e and GREEN with the same commands: docs/qa/con227_234_2026_11_11/round4/red_*.txt and docs/qa/con227_234_2026_11_11/round4/green_*.txt. Reviewer mutants Q1-Q12 adopted plus own S1-S16; mutation run result in docs/qa/con227_234_2026_11_11/round4/mutations.txt. The round-3 claim that a raw / never reaches a message is corrected in threat_model.md (round3.txt kept as the record). Honest limits are listed in the helper header and in the threat model. Not independently re-reviewed after round 4; still In progress. Round 5 (review docs/qa/review_fix227_r4.md, NO-GO on J1..J7 and surviving mutants V3, V4, V5, V8, V11, V12, V13; structural round under section 11.4.276(E)(3), fresh fixer instance). Rules on printed text kept missing (J1: the header rule removed the @ the URL rule needs; J2: a shrinking replacement moved unscanned bytes into the printed window), which is the heuristic tower of section 11.4.250; the primitive defect is that the scripts printed a message whose content they do not control. Fix: the stderr of every network command (git fetch, push, ls-remote, curl) is never printed on any path; a failure prints its exit status and one word of a closed set (rc_err_class, an awk program that prints string literals only) or timeout. rc_redact_cut stays as defence in depth for local stderr and the publisher's own lines, with J1 (rule order R3, R4, R1, R2, R5, R6) and J2 (no scan window, whole-line rules, lines over 16384 bytes not shown) fixed. Every caller and server value that is printed is validated first and never echoed when invalid (tag, SHA, remote names, --release specs, unknown arguments, --base, --prev-tag, notes path, base URL; ls-remote ids through oid(), the GitHub id, the HTTP status). J4: the publisher token goes to curl -K - on stdin, never a file, never argv, never exported (the round-4 TOKEN= kept the export attribute of a caller's TOKEN, so a child process received it: publisher case 19 was RED on the round-4 code). J5: every network command runs under timeout --foreground -k 10 RELEASE_NET_TIMEOUT (default 600 s) plus git http.lowSpeedLimit, curl -m 60 --connect-timeout 20. J6: the trap probe is a committed script (probe_trap_exit_status.py); round 4's no-observable-difference claim for mutants Q12 and S11 was wrong (exit 143/129 with the trap, killed by the signal without it), they are ordinary mutants now. J7: incident_j7.md (unscoped pkill of the round-4 session, severity UNKNOWN). Class census with control needles: census_print_sites.py, census_red_head.txt (178 sites), census_green.txt (195 sites); static case C40 fails if any captured network output variable is printed. RED/GREEN and the threat model: docs/qa/con227_234_2026_11_11/round5/. Mutation run: docs/qa/con227_234_2026_11_11/round5/mutations.txt. Not independently re-reviewed after round 5; still In progress. Round 6 (review scratchpad/review_fix227_r5.md on head 9cd1539a, NO-GO on K1..K4, N1 and the surviving mutants X6, X7, X9, X10, X12, X13, X14, X15, X17; structural round under section 11.4.276(E)(3) by a fresh fixer instance, operator decision 2026-11-11: rounds until GO). The round-5 census looked at printed text only; the review found three defects on other channels. K2: timeout --foreground signalled only its direct child, git's transport helpers ran on for 60-300 s against a hanging server (the test double, exec sleep 30, had no grandchild); --foreground is dropped, timeout signals the whole process group, C41 drives real git and git-remote-http(s) against a hanging local listener (exit 1, class word timeout, no git process left). K1: a remote URL with a password (or any userinfo on http/https), also after an insteadOf rewrite, is in the argv of git-remote-https and readable in /proc by every local user; the tag script now reads every fetch and push URL and aborts before any network command without showing the URL (rc_url_has_userinfo, C42). K3: the token and every exported caller variable reached git, timeout, gh and glab; rc_env_lockdown un-exports everything not on an allow-list and every exported function, the token is exported only to the publisher's bash (C43, C44, publisher 25, derive K3). K4: rc_safe_url is the base-URL check of the publisher. N1: three more awk backup shapes, noted as unreachable for network output. Structural: a channel census over every external command invocation (argv, environment, stdin, cwd, files, signals and time bound): tests/release/channels.tsv (one row per invocation, closed vocabulary), the control-needled static instrument tests/release/channel_census.py with a lint (missing or stale row, value outside the vocabulary, secret channel on the wrong row, unlisted secret reference, external command before rc_env_lockdown), and tests/release/test_channel_census.sh (instrument needles, lint on mutated copies, runtime recorders generated from the table). The runtime census found K5: dirname (library load) and date (derive script) ran before rc_env_lockdown and received the caller's token; fixed (parameter expansion, date after the lockdown) and refused by the lint. K6 (found adopting mutant X11): --token-var may name a variable on the allow-list (GH_HOST), which the lockdown leaves exported; the publisher dropped it only after its first grep; it now reads and unsets it before any external command (publisher case 28, every table command recorded). The tag, publisher and derive suites run the census lint on the script under test (case L1), so an external command before the lockdown is killable in the harness (Y22..Y25); census part 3 records every command the table names or the instrument finds. RELEASE_ENV_KEEP refuses any name with TOK (the publisher's _rpg_tok). A sixth instrument blind spot (a command after a case-arm pattern) was fixed and needled. Reviewer mutants X1..X20 adopted (X12 recorded equivalent under the lockdown, X12b killed), fixer mutants Y1..Y25 added; mp lines count a kill only by a FAIL line that names the property. Threat model, RED/GREEN, census and mutation run: docs/qa/con227_234_2026_11_11/round6/. Not independently re-reviewed after round 6. Round 7 (structural, review scratchpad/review_fix227_r6.md NO-GO on L1..L7, Z8, Z9): the allow-list of round 6 was subtractive and worked by name, so an inherited allexport re-exported the publisher's token (L1) and environment entries whose names are not shell identifiers reached every child (L2). rc_env_clean (scripts/release/redact_cut.sh), the first action of the three scripts, re-executes the script with exec -c (empty environment, no caller shell option) and rebuilds the allow-listed and the read variables from NUL-separated records on a pipe; clean state = marker argv0 + empty /proc/$$/environ, unreadable /proc exits 3, reserved or invalid name exits 2. Runtime census tests/release/env_census.py (recorders read their own /proc/$$/environ; names only) checks every child under a dirty environment, SHELLOPTS=allexport and bash -a (tag C48, publisher 29, derive L2). C49 kills Z8, Z9; suites skip HUP cases under an ignored SIGHUP with a control, the harness reports INCONCLUSIVE (exit 3); suite and harness signal handlers exit; L6 CHANGELOG ids corrected; L7 is CON-310, the trap shape outside tests/release is CON-311. Z1..Z14 adopted (no Z10, Z6 equivalent), W1..W13 added. Record: docs/qa/con227_234_2026_11_11/round7/. Not independently re-reviewed after round 7; still In progress. Recurrence link (section 11.4.214, review r14 G1, /mnt/DATA1TB/claude-work/scratch/rev227_r14.sBmI/review_fix227_r14.md sha256 2cfd0529c8068754262e5edab6ff7302cdc8c824563d93f23806668727a4c826): the C43 positive needle failed 2 of 12 runs under 3 concurrent heavy jobs while the round-14 README calls it deterministic; same class as round-13 F2. Fix: reproduce with the sample kept, slow the needle or use an exec record, and correct the wording. Follow-ups G2, G3, G4 and K8 N2 are filed as CON-359, CON-360, CON-361 and CON-362.

## CON-235 — Full-suite runner: --accept-excluded-change replaces a symlinked excluded-set lock instead of refusing it

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** AI (lander fu_c, Opus 5.5)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fix235/con235_repro_red_green_2026_11_11.txt` — red-command `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change i@mvasic.ru (with config/full_suite_excluded.lock a symlink to an outside copy)` — green-command `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <rostered id> (lock a symlink) -> rc=3 refused, lock still a symlink, target unchanged` — env `host checkout, commit 9b2c3e8d` — signature `rc=0 and RESULT: MANIFEST-OK and the lock is a regular file afterwards` — updated 2026-11-11T15:09:19Z — by `AI (fixer vehicle/fix235, Opus 5.5)`
**Investigation:** root-cause-found-with-evidence — root-cause `main() calls excl_accept whenever excl_check reports problems and verify() reports none; excl_accept rewrites the lock with os.replace and never checks that the lock is a regular file` — evidence `docs/qa/fix235/con235_selftest_red_green_2026_11_11.txt` — updated 2026-11-11T15:09:19Z — by `AI (fixer vehicle/fix235, Opus 5.5)`

Parent: CON-190. Source: independent review docs/qa/review_fu_c_2026_11_11.md F-B (minor). In scripts/full_suite/run_full_suite.py main() the acceptance runs when accept and not probs and eprobs, so lock-side problems found by excl_check are overwritten by excl_accept instead of refused. Reproduced live on the host at landing commit 9b2c3e8d (section 11.4.292, host-only surface): with config/full_suite_excluded.lock replaced by a symlink to an outside copy, --verify-manifest exits 3 (lock is a symlink), and --verify-manifest --accept-excluded-change i@mvasic.ru exits 0, prints RESULT: MANIFEST-OK and leaves a regular file; the outside target is unchanged. Evidence: docs/qa/fu_c_landing/repro_symlink_lock_2026_11_11.txt. Impact low: the replacement shows in git as a modified lock. Acceptance (test-first, section 11.4.224): either excl_accept refuses a symlinked lock with exit 3, with a new case in tests/test_run_full_suite.sh section 37 and a paired mutant, or an operator decision records that replacement is intended. The guide now states the measured behaviour. Status Queued: no fix is claimed (section 11.4.290).

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 5: the fix is to REFUSE (fail closed): --accept-excluded-change on a symlinked lock exits 3 and writes nothing; test-first (section 11.4.224) with a case in tests/test_run_full_suite.sh section 37 and a paired mutant. The 'operator decision records that replacement is intended' branch of the acceptance is withdrawn. Status Queued, ready to fix.

Fix (vehicle/fix235, operator decision 2026-11-11 relayed: fail closed): excl_accept now raises Fatal(3) when the lock is a symlink, dangling or not, before anything is written; the symlink and its target stay untouched. Test-first: tests/test_run_full_suite.sh section 37 gained 8 CON-235 checks, RED on the unfixed engine (6 of the 8 failed), GREEN after the fix (288 checks in total, 288 passed, 0 failed); paired mutant L3 (the new islink branch disabled) added to tests/test_run_full_suite_mutations.sh, L2's anchor made unique. Re-reproduced live on the host with the same synthetic root: before rc=0 RESULT: MANIFEST-OK and a regular file, after rc=3 refused and still a symlink. Evidence: docs/qa/fix235/con235_repro_red_green_2026_11_11.txt, docs/qa/fix235/con235_selftest_red_green_2026_11_11.txt, docs/qa/fix235/mutants_2026_11_11.txt. The guide states the new behaviour. Independent review (docs/qa/review_fix235_2026_11_11.md): GO-with-follow-ups; follow-ups CON-246 (M-1), CON-247 (M-2), CON-248 (N-1). Status Ready for testing (PROVISIONAL-DONE, section 11.4.290): not verified-done; the live host-only re-run of the self-test is the verification job.

## CON-236 — Full-suite mutation harness runs a duplicate mutant id twice instead of refusing it

**Status:** Ready for testing
**Type:** Task
**Severity:** Low
**Created-By:** AI (lander fu_c, Opus 5.5)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/fix235/con236_repro_red_green_2026_11_11.txt` — red-command `(cd <scratch copy with a second M3 row> && bash tests/test_run_full_suite_mutations.sh M3)` — green-command `bash tests/test_run_full_suite_mutations_table.sh` — env `host scratch copy of commit 24bdca78, stand-in self-test (harness loop only)` — signature `two "killed M3" lines and exit 0 for one table holding M3 twice` — updated 2026-11-11T15:09:19Z — by `AI (fixer vehicle/fix235, Opus 5.5)`
**Investigation:** root-cause-found-with-evidence — root-cause `the harness reads the MUTANTS table row by row and never checks that ids are unique` — evidence `docs/qa/fix235/con236_repro_red_green_2026_11_11.txt` — updated 2026-11-11T15:09:19Z — by `AI (fixer vehicle/fix235, Opus 5.5)`

Parent: CON-189. Source: independent review docs/qa/review_fu_c_2026_11_11.md F-F (nit, test hygiene). tests/test_run_full_suite_mutations.sh has no check for duplicate mutant ids, so a row whose id repeats an existing one runs silently twice and prints two result lines with the same id; the reviewer hit it with Z7 (and Z4) while adding own mutants. Reproduce first (section 11.4.292): add a duplicate-id row in a scratch copy and record that both run. Acceptance (test-first, section 11.4.224): the harness refuses duplicate ids with a non-zero exit before running any mutant, with a test and a paired mutant.

Fix (vehicle/fix235): the harness computes the duplicate ids of its MUTANTS table and, when any exist, prints FAIL mutant table: duplicate mutant id(s) and exits 2 before the baseline or any mutant runs (also when the duplicate is not among the selected ids). Test-first: new tests/test_run_full_suite_mutations_table.sh (manifest row heavy/auto), RED on the unfixed harness (8 case checks failed), GREEN after the fix; its paired mutant (the check line removed) is killed (8 case checks fail). Evidence: docs/qa/fix235/con236_repro_red_green_2026_11_11.txt. Independent review (docs/qa/review_fix235_2026_11_11.md): GO-with-follow-ups. Status Ready for testing (PROVISIONAL-DONE, section 11.4.290): not verified-done.

## CON-237 — tests/test_consumer_required_helper.sh fails when run directly under dash (bash shebang, sourced bash library scripts/lib/safe_rm.sh: Bad substitution); decide fix or document

**Status:** Queued
**Type:** Task
**Severity:** Low

Registered from the relayed operator decisions of 2026-11-11 (item 9a, record docs/operator_decisions/2026-11-11_relayed_decisions.md). What: the consumer-required helper test of the full-suite fix vehicle (tests/test_consumer_required_helper.sh; absent on main 24bdca78, measured with git grep, so it lives on the vehicle) carries a bash shebang and sources the bash library scripts/lib/safe_rm.sh; run directly as 'dash tests/test_consumer_required_helper.sh' it fails with 'Bad substitution'. Not reproduced by this lander (UNCONFIRMED, relayed from earlier reviews). Affected scope: tests/test_consumer_required_helper.sh, scripts/lib/safe_rm.sh. Acceptance: either the test refuses a non-bash interpreter with a clear message (test-first, paired mutant), or the guide documents that it must be run with bash; the choice is recorded on this item. Status Queued; no fix claimed (section 11.4.290).

## CON-238 — Consumer-required helper: L16 pins a NULL-only id register as SKIP; record the direction under section 11.4.201(4) (review cgs6 N6-2)

**Status:** Queued
**Type:** Task
**Severity:** Low

Registered from the relayed operator decisions of 2026-11-11 (item 9b, record docs/operator_decisions/2026-11-11_relayed_decisions.md). Source: independent review review_cgs6.md N6-2 in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/ (full-suite fix vehicle, helper scripts/fastcycle/tests/lib/consumer_required.sh). Reviewer text: 'L16 (NULL-only SKIP) is consistent with CON-131's text and is not a regression (helper unchanged since round 3; real schema NOT NULL).' What: case L16 pins a register whose id column holds only NULL values as SKIP. The real schema declares atm_id NOT NULL, so the input cannot occur in a real tracker. Affected scope: scripts/fastcycle/tests/lib/consumer_required.sh and its helper test. Acceptance: the SKIP direction for a NULL-only register is recorded as a reasoned direction (schema reason) on this item or in the helper's documentation, or changed to RUN test-first with a paired mutant. Status Queued; no change claimed (section 11.4.290).

## CON-239 — Consumer-required helper: L17 pins a leading-space id (' ATM-953') as SKIP, the non-conservative direction under section 11.4.201(4) (review cgs6 N6-2, CR6-2)

**Status:** Queued
**Type:** Task
**Severity:** Low

Registered from the relayed operator decisions of 2026-11-11 (item 9c, record docs/operator_decisions/2026-11-11_relayed_decisions.md). Source: independent review review_cgs6.md N6-2 and CR6-2 in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/ (full-suite fix vehicle, helper scripts/fastcycle/tests/lib/consumer_required.sh). Reviewer text: 'L17 pins a leading-space id as SKIP (and ` ATM-953` also SKIPs on head) - the non-conservative direction under section 11.4.201(4) - but unlike L16 this direction is not registered with CON-131. Register it there as an open direction.' CR6-2: the recorded equivalent 'trim(k) in C2' is false; with raw key ' ATM-953' C3 is 0 but trim(k) IN makes C2 = 1, so head SKIPs and the mutant RV6-7 RUNs (probe p_lead953). Affected scope: scripts/fastcycle/tests/lib/consumer_required.sh and its helper test. Acceptance: the direction for a leading-space id is decided (SKIP with a recorded reason, or RUN as the conservative direction), pinned by a case with RV6-7 as its paired mutant, and the false equivalence claim is dropped. Status Queued; no change claimed (section 11.4.290).

## CON-240 — Apply operator decision 'allow and log' for vendor/ trees of undecidable ownership (G4-1, relayed 2026-11-11): treat as third-party by default and record in evidence

**Status:** Queued
**Type:** Task
**Severity:** Low

Registered from the relayed operator decisions of 2026-11-11 (item 7, record docs/operator_decisions/2026-11-11_relayed_decisions.md). Decision (relayed): a vendor/ tree whose ownership cannot be decided is allowed and logged: treated as third-party by default and recorded in the evidence. Finding of this lander: the only G4-1 found in the tracked tree and the review files is review_cgs4.md G4-1 (full-suite runner, Go module with a bare vendor/ directory), already decided fail-closed in review round 5 and landed on main (scripts/full_suite/run_full_suite.py line 3321, tests/test_run_full_suite_go.sh A14, docs/guides/full_suite_runner_guide.md rows 129/149). That question is Go vendoring consistency, not ownership. No codegraph item or review naming G4-1 was found (git grep of the tree and the tracker DB for G4-1; grep of review_*.md in the two session scratchpads). UNCONFIRMED: which source the decision targets (codegraph scope ownership classification of vendor/ under section 11.4.79(6), or the runner). Acceptance: the target is identified with the conductor; if a source change is implied it is made test-first (third-party default plus an evidence log line, with a paired mutant) and the existing fail-closed runner verdict for a bare vendor/ is not weakened without its own decision. Status Queued; no source changed (section 11.4.290).

## CON-241 — CON-216 follow-up: no test drives the success path of the thread read in _read_ulimit_threads (reviewer mutants RV2 and RV3 survive)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-216 (Roadmap: CON-161 thread headroom chain). Review finding F1 (minor, test-instrumentation). CON-216 rewrote the success path (Python counts the lines, uid filter), but neither test_host_report_probe_thread_headroom_r2_regression.sh nor test_host_report_thread_limit_r1_regression.sh drives it: RV2 (count off by 1000) and RV3 (-U uid replaced by -e, all users) survive both. Fix: a PATH-shim ps that prints N lines and an assertion that thr == N, an assertion that the argv carries -U <real uid>, and RV2 and RV3 adopted as paired mutants. Follow-up of the independent Opus review of the fix216 vehicle (CON-216..CON-220, CON-222..CON-224; verdict GO-with-follow-ups, 0 critical, 0 important; record scratchpad review_fix216.md, 2026-11-11). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-242 — CON-218/CON-220 follow-up: the census main() message for a KILLED-TIMEOUT ledger entry overstates (says the equivalence proof is false) and the branch is untested

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-220 (Roadmap: CON-162 decision-mutant census). Review finding F3 (minor, source-defect in a validation tool, not a host-safety surface). scripts/validation/enumerate_decision_mutants.py main() (about line 453) prints that the ledger entry's mutant is KILLED so its equivalence proof is false for a timeout, which only leaves the proof unconfirmed (section 11.4.6). No test drives main() on that branch. Fix: a distinct message for KILLED-TIMEOUT (unconfirmed: the mutant timed out) and a hanging mutant added to the CON-218 synthetic target. Follow-up of the independent Opus review of the fix216 vehicle (CON-216..CON-220, CON-222..CON-224; verdict GO-with-follow-ups, 0 critical, 0 important; record scratchpad review_fix216.md, 2026-11-11). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-243 — CON-222 follow-up: run_all.sh counts the new exit 77 of the helper test as FAIL and has no tier awareness for the heavy L29 test

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-222 (Roadmap: CON-185 chain). Review finding F4 (minor, process-doc). scripts/fastcycle/tests/run_all.sh treats any non-zero status, 77 included, as FAIL (lines 90-92), so on a host without a usable locale the helper test turns run_all red, and the new about 3.5 minute test_consumer_required_helper_l29_skip_r1_regression.sh is run with no tier awareness. run_full_suite.sh and the mutation harnesses handle 77 correctly. Fix: document that 77 is FAIL in run_all and that heavy members run, or map 77 to SKIP. Follow-up of the independent Opus review of the fix216 vehicle (CON-216..CON-220, CON-222..CON-224; verdict GO-with-follow-ups, 0 critical, 0 important; record scratchpad review_fix216.md, 2026-11-11). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-244 — CON-219 follow-up: the census wording guard uses a closed verb list (reviewer RV6b 'exercises all decision points' passes); record the limit

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-219 (Roadmap: CON-159 census wording). Review finding F5 (nit, test-instrumentation). The overstatement regex of test_decision_mutant_census_wording_r1_regression.sh has a closed verb list, so 'It exercises all decision points.' passes. Acceptable for a wording guard because the pinned scope sentences are the stronger half. Fix: record the limit in the test header, or widen the verb list. Follow-up of the independent Opus review of the fix216 vehicle (CON-216..CON-220, CON-222..CON-224; verdict GO-with-follow-ups, 0 critical, 0 important; record scratchpad review_fix216.md, 2026-11-11). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-245 — CON-216 follow-up: ps with exit 0 and empty output reads as 0 threads (full headroom) in _read_ulimit_threads; optional hardening

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-216 (Roadmap: CON-161 thread headroom chain). Review finding F6 (nit, test-instrumentation). With ps exiting 0 and printing nothing, thr is 0 and the headroom is full. Unreachable with real procps (ps lists itself) and identical to the old code. Optional hardening: zero lines counted means unmeasured. Add a test with a shim. Follow-up of the independent Opus review of the fix216 vehicle (CON-216..CON-220, CON-222..CON-224; verdict GO-with-follow-ups, 0 critical, 0 important; record scratchpad review_fix216.md, 2026-11-11). Registered under section 11.4.276(G.2) for the next iteration. Status Queued: no fix is claimed; when a fix lands it is PROVISIONAL-DONE (section 11.4.290) until its own verification job passes.

## CON-246 — CON-235 follow-up (review M-1): excl_accept opens its temp file lock_path+'.tmp.<pid>' with a plain open that follows a symlink

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-235 (Roadmap: CON-190 excluded-set lock chain). Review docs/qa/review_fix235_2026_11_11.md finding M-1 (minor, source-defect, pre-existing). In scripts/full_suite/run_full_suite.py excl_accept opens lock_path + '.tmp.<pid>' with open(..., 'w'), which follows a symlink planted at that name; use os.open(tmp, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0o644). Acceptance (test-first, section 11.4.224): a self-test plants a symlink at the tmp name and the acceptance refuses or never writes through it, with a paired mutant. Status Queued: no fix is claimed (section 11.4.290).

## CON-247 — CON-235 follow-up (review M-2): a lock reached through a symlinked config/ directory passes the islink check and the lock is never checked as tracked or equal to HEAD

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-235 (Roadmap: CON-190 excluded-set lock chain). Review docs/qa/review_fix235_2026_11_11.md finding M-2 (minor, source-defect, pre-existing). If config/ itself is a symlink, islink(lock_path) is False and the write goes through the directory link; the roster has a tracked / equals-HEAD check, the lock does not. Acceptance: either add the check with a test-first self-test and a paired mutant, or document the limit in docs/guides/full_suite_runner_guide.md. Status Queued: no fix is claimed (section 11.4.290).

## CON-248 — CON-235 follow-up (review N-1): the full-suite guide should state that a symlink swapped in between the islink check and os.replace is replaced, never written through

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

Parent: CON-235 (Roadmap: CON-190 excluded-set lock chain). Review docs/qa/review_fix235_2026_11_11.md finding N-1 (nit, process-doc). The guide says the symlink is left untouched; that holds for the non-racing case. Add one sentence stating the honest limit: a race between the islink check and os.replace ends in the pre-fix behaviour (link replaced by a regular file, nothing written through it), visible in git. Status Queued: no fix is claimed (section 11.4.290).

## CON-265 — CON-033 round 4 (structural): path-resolution and store-tier class fixed against a kernel oracle; the R4-CAP legs run on this host

**Status:** Ready for testing
**Type:** Task
**Severity:** Medium
**Created-By:** Conductor

Parent: CON-033 (vehicle/con033). Review round 3 (docs/qa/con033_review/review_con033_r3.md) found R3-F1 (G-T-DOT#1 listed equivalent but refuted) and R3-F2 (RVR3b survives) in the recurring class of path-resolution and tier mutants. Round 4: _resolution_chain follows the kernel; test_review_record_resolution_ground_truth.sh compares it with os.stat and an openat O_PATH walk over a 12348-path grid; store-tier suite gains L4/E5; RVR1, RVR3b and 12 RF-chain mutants are adopted into the mutation runner; R3-F3 (DSM-H), R3-F4, R3-F5, R3-F7 (r6 harness) folded in; the r4 capability legs now find /tmp as a writable all-root-owned base (the old walk stopped at the root-owned but non-writable /home), so they run (26 ok, rc 0). Verification of the sweep and the full mutation runner is recorded in the landing commit message. Id history (section 11.4.214): minted in vehicle/con033 as CON-132 (round 4), re-minted at the merge of main 2e8cfb90 as CON-162 (main owns up to CON-145); old to new map: CON-132 -> CON-162. Re-minted again at the merge of main 27dcf518 as CON-179 (main owns up to CON-162); old to new map: CON-162 -> CON-179. Re-minted again at the merge of main fc57ad0c as CON-210 (main owns up to CON-193); old to new map: CON-179 -> CON-210. Re-minted again at the merge of main b20736f8 as CON-265 (main owns up to CON-248); old to new map: CON-210 -> CON-265.

## CON-249 — CON-033 M5: owed anchors seam (regenerate_if_stale + index_commit_seam + post_update index freshness)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-092, re-minted at the merge of main bdc3ac43 as CON-108 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-116 (main owns up to CON-115); old to new map: CON-092 -> CON-108 -> CON-116. Re-minted again at the merge of main 2e8cfb90 as CON-146 (main owns up to CON-145); old to new map: CON-116 -> CON-146. Re-minted again at the merge of main 27dcf518 as CON-163 (main owns up to CON-162); old to new map: CON-146 -> CON-163. Re-minted again at the merge of main fc57ad0c as CON-194 (main owns up to CON-193); old to new map: CON-163 -> CON-194. Re-minted again at the merge of main b20736f8 as CON-249 (main owns up to CON-248); old to new map: CON-194 -> CON-249.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:40Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
Review of CON-033 (finding M5): the HELD snapshot 4b13814 on wip/review-pending-20261014/atm1220_r9 carries scripts/anchors/{regenerate_if_stale,index_commit_seam}.sh, 3 tests and a post_update_hook index-freshness change. They were not brought over (main removed regenerate_if_stale.sh in cf710b2 as untested, with no caller). After the ref is retired the owed seam exists only on the backup tag. Measured in round 1: test_regenerate_if_stale and test_index_commit_seam rc=0, test_post_update_index_freshness rc=1 (depends on the snapshot's superseded post_update_hook). Id history: vehicle/con033 at dd8bd9c registered this as CON-070 (that id stays reserved for the CON-030 vehicle). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/anchors/regenerate_if_stale.sh, scripts/anchors/index_commit_seam.sh, their 3 tests, scripts/post_update_hook.sh index-freshness step

**Reproduction / context:**
UNKNOWN: no reproduction yet; the round-1 measurement is in the report text.

**Acceptance criteria:**
The seam is implemented test-first on current main, or closed with an evidence-backed reason (section 11.4.197); the three tests pass on main; post_update_hook runs the freshness step.

## CON-250 — CON-033 RM1: land the review-round budget boundary suite

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-093, re-minted at the merge of main bdc3ac43 as CON-109 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-117 (main owns up to CON-115); old to new map: CON-093 -> CON-109 -> CON-117. Re-minted again at the merge of main 2e8cfb90 as CON-147 (main owns up to CON-145); old to new map: CON-117 -> CON-147. Re-minted again at the merge of main 27dcf518 as CON-164 (main owns up to CON-162); old to new map: CON-147 -> CON-164. Re-minted again at the merge of main fc57ad0c as CON-195 (main owns up to CON-193); old to new map: CON-164 -> CON-195. Re-minted again at the merge of main b20736f8 as CON-250 (main owns up to CON-248); old to new map: CON-195 -> CON-250.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:41Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
Reviewer mutant RM1 (rec[round] > round_budget changed to >=, refusing the last legal round of section 11.4.276) survived every suite on main and on the vehicle. The CON-033 vehicle adds test_review_record_round_budget_boundary_regression.sh (real tool 6/0; the mutant fails B1b and B2b) and adopts RM1 into the mutation runner. In round 3 the suite is also in the sub-clause sweep's SUITES (review R2-F5). This item tracks that it lands; it closes when CON-033 lands on main. Id history: vehicle/con033 at dd8bd9c registered this as CON-071. Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/review_record.py (G-Q-ROUND-BUDGET, G-R-ROUND-BUDGET), scripts/fastcycle/tests/test_review_record_round_budget_boundary_regression.sh

**Reproduction / context:**
Reviewer mutant RM1 (rec[round] > round_budget changed to >=) survived every suite on main.

**Acceptance criteria:**
The boundary suite is on main and the mutation runner lists RM1 (gate and record side) as KILLED. Closes when CON-033 lands on main.

## CON-251 — CON-033: regenerate the review_record sub-clause kill ledger under the new sweep name, and schedule the sweep

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-094, re-minted at the merge of main bdc3ac43 as CON-110 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-118 (main owns up to CON-115); old to new map: CON-094 -> CON-110 -> CON-118. Re-minted again at the merge of main 2e8cfb90 as CON-148 (main owns up to CON-145); old to new map: CON-118 -> CON-148. Re-minted again at the merge of main 27dcf518 as CON-165 (main owns up to CON-162); old to new map: CON-148 -> CON-165. Re-minted again at the merge of main fc57ad0c as CON-196 (main owns up to CON-193); old to new map: CON-165 -> CON-196. Re-minted again at the merge of main b20736f8 as CON-251 (main owns up to CON-248); old to new map: CON-196 -> CON-251.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:41Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
Round 2 of CON-033 renamed the sweep generator to sweep_review_record_subclauses.sh (a ~70-minute generator, not a run_all test). In round 3 the old name was replaced in the hashed files (test_review_record_subclause_cases.sh, lib/review_record_guard_analyzer.py) and in the ledger header, and the ledger was regenerated. NOT done: nothing runs the sweep on a schedule; a stale ledger is still only caught when guard_table runs. Id history: vehicle/con033 at dd8bd9c registered this as CON-072. Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/fixtures/review_record_subclause_kills.tsv, the hashed files (review_record.py, lib/review_record_guard_analyzer.py, lib/review_record_genuine.sh, the swept suites), scripts/fastcycle/tests/sweep_review_record_subclauses.sh

**Reproduction / context:**
A stale ledger is caught only when guard_table runs (M4).

**Acceptance criteria:**
The hashed files name sweep_review_record_subclauses.sh; the ledger is regenerated and test_review_record_guard_table.sh passes; the sweep runs on a declared cadence (a timer or a heavy-tier entry) so the ledger cannot go stale silently.

Recurrence link (section 11.4.214, open original, link only; 2026-11-16): audit F4 found the kill ledger stale again after CON-402 (3281d92e) changed the hashed tool files: test_review_record_guard_table.sh M4 'kill ledger is STALE: tool sha256 f2c1ffbc... != current 489cbe12...', 3/3 at main 09d3ad2f, PASS at e90d4aea. Same remedy (regenerate with sweep_review_record_subclauses.sh --out, about 70 min, on main) and the same missing schedule. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d).

## CON-252 — SPECKIT004 diagrams: mmd-08 and mmd-09 images missing on main

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-095, re-minted at the merge of main bdc3ac43 as CON-111 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-119 (main owns up to CON-115); old to new map: CON-095 -> CON-111 -> CON-119. Re-minted again at the merge of main 2e8cfb90 as CON-149 (main owns up to CON-145); old to new map: CON-119 -> CON-149. Re-minted again at the merge of main 27dcf518 as CON-166 (main owns up to CON-162); old to new map: CON-149 -> CON-166. Re-minted again at the merge of main fc57ad0c as CON-197 (main owns up to CON-193); old to new map: CON-166 -> CON-197. Re-minted again at the merge of main b20736f8 as CON-252 (main owns up to CON-248); old to new map: CON-197 -> CON-252.

Review of CON-033 (finding M4): main's SPECKIT004 document has 9 mermaid blocks but only mmd-01..07 images. The HELD snapshot carries an added mmd-09.png and three re-rendered action_prefix DIAGRAMS.mmd-01..03.png, which CON-033 did not bring over. The missing images must be regenerated from main's sources. Typed Bug (a defect: a shipped document lacks its images; review R2-F7). Id history: vehicle/con033 at dd8bd9c registered this as CON-073 (typed Task there). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
the SPECKIT004 document with 9 mermaid blocks and its DIAGRAMS images (main has mmd-01..07 only)

## CON-253 — kedge gitlink removal: operator ratification (section 11.4.122)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-096, re-minted at the merge of main bdc3ac43 as CON-112 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-120 (main owns up to CON-115); old to new map: CON-096 -> CON-112 -> CON-120. Re-minted again at the merge of main 2e8cfb90 as CON-150 (main owns up to CON-145); old to new map: CON-120 -> CON-150. Re-minted again at the merge of main 27dcf518 as CON-167 (main owns up to CON-162); old to new map: CON-150 -> CON-167. Re-minted again at the merge of main fc57ad0c as CON-198 (main owns up to CON-193); old to new map: CON-167 -> CON-198. Re-minted again at the merge of main b20736f8 as CON-253 (main owns up to CON-248); old to new map: CON-198 -> CON-253.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:42Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
fa3a9cb (REHEARSAL: remove kedge submodule, 2026-10-12) deleted the gitlink submodules/kedge. docs/label-sync/REVIEW-FIXES.md:88 records that the deletion had no recorded operator decision; the operator decided on 2026-10-14 to keep the untracked submodules/kedge directory untouched. The HELD snapshot also deletes the gitlink. Whether a ratification exists elsewhere is UNCONFIRMED. Raised by the CON-033 review. Id history: vehicle/con033 at dd8bd9c registered this as CON-074. Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
the removed gitlink submodules/kedge (fa3a9cb, 2026-10-12) and docs/label-sync/REVIEW-FIXES.md:88

**Reproduction / context:**
UNKNOWN: whether a ratification exists elsewhere.

**Acceptance criteria:**
A recorded operator decision keep-removed or restore exists; if restore, the gitlink is restored on main.

## CON-254 — select_sample: stale mutation anchor SS_N3_negative_gap_retroactive

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-097, re-minted at the merge of main bdc3ac43 as CON-113 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-121 (main owns up to CON-115); old to new map: CON-097 -> CON-113 -> CON-121. Re-minted again at the merge of main 2e8cfb90 as CON-151 (main owns up to CON-145); old to new map: CON-121 -> CON-151. Re-minted again at the merge of main 27dcf518 as CON-168 (main owns up to CON-162); old to new map: CON-151 -> CON-168. Re-minted again at the merge of main fc57ad0c as CON-199 (main owns up to CON-193); old to new map: CON-168 -> CON-199. Re-minted again at the merge of main b20736f8 as CON-254 (main owns up to CON-248); old to new map: CON-199 -> CON-254.

Review of CON-033: in a consumer layout (900 s cap) test_select_sample_r5_regression.sh reports mutation SS_N3_negative_gap_retroactive 'could not be applied (anchor drifted)' on both main and the vehicle, so it is a pre-existing stale anchor. The remaining NOT ok lines (S3/S5/S6/S13) need a live tracker DB or snapshot. Typed Bug (a defect: a mutation that cannot apply guards nothing; review R2-F7). Id history: vehicle/con033 at dd8bd9c registered this as CON-075 (typed Task there). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/test_select_sample_r5_regression.sh (mutation SS_N3_negative_gap_retroactive) and scripts/fastcycle/cycle/select_sample*

## CON-261 — test_review_record_backfill_evidence_r2_regression.sh exits 2 when run as sh (its shebang), on main 9eea893 too

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-104, re-minted at the merge of main bdc3ac43 as CON-120 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-128 (main owns up to CON-115); old to new map: CON-104 -> CON-120 -> CON-128. Re-minted again at the merge of main 2e8cfb90 as CON-158 (main owns up to CON-145); old to new map: CON-128 -> CON-158. Re-minted again at the merge of main 27dcf518 as CON-175 (main owns up to CON-162); old to new map: CON-158 -> CON-175. Re-minted again at the merge of main fc57ad0c as CON-206 (main owns up to CON-193); old to new map: CON-175 -> CON-206. Re-minted again at the merge of main b20736f8 as CON-261 (main owns up to CON-248); old to new map: CON-206 -> CON-261.

Found in CON-033 fix round 3. Measured 2026-11-05 on main 9eea893 (wt_main), the merge b3cecf7 and the round-3 tree: sh -> rc 2, bash -> rc 0. run_all.sh picks sh for a file whose first line has no 'bash'; the full suite uses the shebang. The mutation runner and the sub-clause sweep run it with bash, so it is green there. Outside the CON-033 scope (section 11.4.293); not fixed. Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/test_review_record_backfill_evidence_r2_regression.sh (#!/bin/sh), scripts/fastcycle/tests/lib/review_record_genuine.sh (bash-only)

## CON-262 — Wider SKIP class: suites and runners that print SKIP but exit 0, and run_all.sh labels exit 77 FAIL

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-105, re-minted at the merge of main bdc3ac43 as CON-121 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-129 (main owns up to CON-115); old to new map: CON-105 -> CON-121 -> CON-129. Re-minted again at the merge of main 2e8cfb90 as CON-159 (main owns up to CON-145); old to new map: CON-129 -> CON-159. Re-minted again at the merge of main 27dcf518 as CON-176 (main owns up to CON-162); old to new map: CON-159 -> CON-176. Re-minted again at the merge of main fc57ad0c as CON-207 (main owns up to CON-193); old to new map: CON-176 -> CON-207. Re-minted again at the merge of main b20736f8 as CON-262 (main owns up to CON-248); old to new map: CON-207 -> CON-262.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:46Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
CON-033 round 3 fixed the review_record suites only (R2-F3). Measured: run_all.sh prints FAIL for a member that exits 77 (still not-PASS; in default mode the full suite runs members alone and its judge maps 77 to SKIP); test_dispatch_stamp_class.sh prints '  SKIP  consumer policy file not present' and exits 0. The rest of the class is not measured: UNCONFIRMED. Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/run_all.sh; scripts/fastcycle/tokens/test_dispatch_stamp_class.sh (consumer policy file SKIP, exit 0); other suites UNCONFIRMED (dispatch r6, fc_timer selftest named by the conductor)

**Reproduction / context:**
grep -n 'SKIP' in each suite and compare its exit status with its skip lines.

**Acceptance criteria:**
Every suite that skips a proof leg exits 77 with the leg named; run_all.sh reports a 77 as SKIP and exits 77 when nothing failed; a census lists the remaining suites.

**Census (CON-033 review round 3, finding R3-F7, reviewer probe skipexit0.py over 1193 tracked .sh files on main b939266a; an `echo SKIP` line not carrying `exit 77`, followed within 3 lines by `exit 0`):** 11 sites in 8 files. CON-033 round 4 fixed one of them in the vehicle (scripts/fastcycle/tokens/test_dispatch_stamp_r6_mutations.sh:137, now `SKIP reason=topology_unsupported` and exit 77, measured rc 77). The other 10, pre-existing on main and NOT fixed here: test_io_trace_fork_cwd_and_faccessat_r2_regression.sh, test_precheck_shellcheck_red.sh, test_guard_branch_consistency.sh, test_guard_work_track_binding.sh (2 sites), test_multitrack_redpin_mutations.sh, test_multitrack_work_binding_submodule_db.sh (2 sites), tests/action_prefix/test_subsystem_shortcuts.sh (2 sites). Acceptance per site: the skip exits 77 with a section 11.4.69 reason, and a red test proves a skipped run is never counted as PASS.

Note (2026-11-16): the fastcycle vehicle landed in merge f090d082 fixes the run_all.sh half (exit 77 = SKIP; a run with a skipped member exits 77). The other half, suites and runners that print a SKIP line and still exit 0, is not fixed; this item stays open for it (author follow-up CON-PENDING-1, not minted). Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-263 — CON-033 round 4: accept two excluded-lock rows (review_record_guard_analyzer.py, sweep_review_record_subclauses.sh)

**Status:** Operator-blocked
**Type:** Task
**Operator-Block-Details:** WHAT: accepting the two excluded manifest rows needs run_full_suite.sh --accept-excluded-change WHY: the excluded set was locked on the operator's order (CON-031); changing it is the operator's decision UNBLOCK: [A] operator accepts both rows via --accept-excluded-change · [B] operator rejects them and names another treatment (for example a non-manifest location) · [C] operator accepts one row and names a treatment for the other WHO: Operator
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Found in CON-033 fix round 4 at the merge of main bdc3ac43: scripts/run_full_suite.sh --verify-manifest reports one problem, the excluded lock. The vehicle adds scripts/fastcycle/tests/lib/review_record_guard_analyzer.py and scripts/fastcycle/tests/sweep_review_record_subclauses.sh as excluded manifest rows (a helper library and a ~70-minute generator, neither a test entry), and main bdc3ac43 locked the excluded set at 52 rows on the operator's order (CON-031). Changing the lock needs the operator's --accept-excluded-change; the round-4 fixer did not run it. Acceptance: the operator decides (accept both rows, or name another treatment); after the decision --verify-manifest reports 0 problems.

## CON-264 — CON-033: run the review_record R4-CAP proof legs on a schedule (they SKIP when TMPDIR is under a home directory)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-123, re-minted at the merge of main 90efceb8 as CON-131 (main owns up to CON-115). Re-minted again at the merge of main 2e8cfb90 as CON-161 (main owns up to CON-145); old to new map: CON-131 -> CON-161. Re-minted again at the merge of main 27dcf518 as CON-178 (main owns up to CON-162); old to new map: CON-161 -> CON-178. Re-minted again at the merge of main fc57ad0c as CON-209 (main owns up to CON-193); old to new map: CON-178 -> CON-209. Re-minted again at the merge of main b20736f8 as CON-264 (main owns up to CON-248); old to new map: CON-209 -> CON-264. The R4-CAP legs of test_review_record_gate_authority_r4_regression.sh need podman unshare, a subordinate-uid range and a writable directory whose whole chain is root-owned. With TMPDIR under a home directory they SKIP (exit 77). CON-033 round 4 ran them once with TMPDIR=/tmp: 26 PASS, 0 FAIL, 0 SKIP, R4-CAP-needle..R4-CAP7 all PASS (log sha256 221ab05de2da4f64075658b7682d8a00840d6e50f4b5bf56a56729285118e525, cited in the round-4 report). Nothing runs them regularly, so a regression in the capability tier would be seen only on a host and TMPDIR where they run. Acceptance: a scheduled or pre-landing run with TMPDIR=/tmp (or another root-owned-chain directory) whose result is recorded; a SKIP of these legs is reported, never read as PASS.

Round 4 note: the legs were run once with the base fix in the test (CAPBASE falls back to /tmp, /var/tmp, /dev/shm when no writable root-owned ancestor exists): 26 ok, rc 0. What remains owed is running them on a schedule.

Link (section 11.4.214, open original, link only; 2026-11-16; author follow-up CON-PENDING-3): host-environment failures on this host, also on named main: review_record_* (resolution_ground_truth, store_tier_noncanonical_tmpdir, gate_authority_*, skip_status, guard_table) fail because the mandated TMPDIR /mnt/DATA1TB/claude-work/tmp is writable by others, so the capability controls cannot hold; guard_table also reports a STALE kill ledger (UNCONFIRMED whether host-only). Same note lists test_host_attribute_red.sh (btrfs binary unavailable, tracked as CON-100) and test_io_trace_build_map_r6_regression.sh (unshare cannot write uid_map on this host; no item of its own). Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-266 — CON-033 R7-M1: extend mutate_tier_legs.py to the module constants the tier reads and to cmd_gate's consumption of the tier result, and cross-check the call-site census against an independent token count

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Round 7 review finding R7-M1 (test-instrumentation, minor, follow-up): the mechanical enumerator covers tier function bodies and tier function call sites only; module constants (_FOREIGN_WRITE, _SUBID_FILES, HIGH_BLAST_SEAMS) and the gate-side consumption of the tier result are covered by hand-written mutants (all killed). Extend the enumerator and add a token-count cross-check of the census. Review: docs/qa/con033_review/review_con033_r7.md

## CON-267 — CON-033 R7-M2: self-test RED for mutate_tier_legs.py (a planted survivor must make it exit 1; a generator that drops mutation kinds must be noticed)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Round 7 review finding R7-M2 (test-instrumentation, minor, follow-up, carried from round 6): mutate_tier_legs.py has no self-test RED. Add a small RED suite that plants a survivor and a dropped-kind generator. Review: docs/qa/con033_review/review_con033_r7.md

## CON-268 — CON-033 R7-N1: mutate_tier_legs.py --keys must compute equivalence-key staleness against the full enumeration, not the filtered list

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Round 7 review nit R7-N1 (test-instrumentation, nit): with --keys every equivalence key outside the selected subset is printed STALE and the run exits 1; only a full run gives a meaningful stale check (the same happens with --only). Compute staleness against the full enumeration. Review: docs/qa/con033_review/review_con033_r7.md

## CON-269 — README-link review F1: 164 docs/*.md are not linked from README, contradicting the R18 'no orphan under docs/' claim (section 11.4.212)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

Review readme_link_v2 (GO-with-follow-ups; docs/qa copy not made, report at scratchpad review_readme_link.md). F1, minor, process-doc. 164 tracked docs/*.md are not reachable by any Markdown link path from README (research 49, scripts 46, qa 26, label-sync 7, jev 6, actions 5, amendment-log 5, guides 3, prompts 3, codegraph 2, release 2, plus Issues.md, Issues_Summary.md, Fixed.md, Fixed_Summary.md, CONTINUATION.md, BADGES.md, AGENT_GUARDRAILS.md, owed_gate_implementations.md, translations.md, optimization 1); many are named only as backtick paths. Pre-existing (165 at base b20736f8). Decide the reachability definition for 11.4.212 (link versus path mention), then link them or correct the R18 sentence in the README Status summary. Acceptance: census (census.py) reports 0 unreached under the chosen definition, or the R18 claim is corrected.

## CON-270 — README-link review F2: no gate CM-README-DOC-ENTRYPOINT-COMPLETE (silent gate debt, section 11.4.227(A))

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

F2, minor, test-instrumentation. No shipped gate enforces 11.4.212 README reachability; CM-README-DOC-ENTRYPOINT-COMPLETE is named in the corpus but neither implemented nor a registered deferral. Register a deferral in scripts/gates/gate_ledger_deferrals.tsv and docs/owed_gate_implementations.md, or implement it, seeded from the reviewer's census script (scratchpad review_tools/census.py) and its four mutants. Acceptance: the name is implemented or registered; if implemented, a paired mutation test fails when a doc becomes unreachable.

## CON-271 — README-link review F3: commits carry 'Roadmap-Item: none-doc-only', which is not an item id (section 11.4.293(A))

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

F3, nit, process-doc. Both README-link commits (c0223046, 4436af82) carry Roadmap-Item: none-doc-only. Register such work per 11.4.202 before it starts or agree a documented doc-only token. The landing merge commit carries the id of the F1 follow-up instead. Commits are not rewritten (11.4.113).

## CON-272 — README-link review F4: README Fixed header cell lists revisions only up to R14 (R15 to R23 missing)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude

F4, nit, process-doc. The README metadata table Fixed cell records rounds only up to R14; R15 to R23 are not recorded there. Pre-existing staleness. Bring the cell up to date or rotate it per 11.4.61(A).

## CON-070 — CON-030 class follow-up: whitespace and line splitting of git submodule names/paths in validate_submodule.py, three gates, baseline_replay.sh and helix_deps_manifest.py

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-applied by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-applied after the 27dcf518 merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-applied after the 9cd7cacd merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-applied after the 64ac151d merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-applied after the fc57ad0c merge by Claude Opus 5.5 (CON-030 round 7 fixer subagent); re-applied at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)

Class follow-up of CON-030 (parent: CON-030; review r1 F5 and review r2 G9, section 11.4.276(C)): tools outside the full-suite runner parse human-oriented git output by whitespace or by lines where a field is a submodule name or path, so a name or path with a space (and, for (7), a leading or trailing space, a CR-class character or a newline) is truncated, merged or not found. Members, each with its measured effect (2026-11-05, fixtures with submodules "submodules/my engine" and "submodules/plain"; control: the plain path is read correctly every time): (1) progressive/validate_submodule.py:60 `l.split()[1]` on `-` status lines: with a crafted --status-file an orphan path "x y" and a declared path "x" gives PASS (false PASS, measured by the r1 reviewer; control "zz" FAILs); with real git output a spaced uninitialised path gives a false FAIL. (2) scripts/gates/cm_hub_engine_no_ownorg_nesting.sh:68 `--get-regexp` plus an awk match on field 2: drops "submodules/my engine" from the inspected set (measured by the r1 reviewer), so that engine is never inspected: potential false PASS, end to end UNCONFIRMED. (3) scripts/gates/cm_gitlink_on_remote.sh:55 and :57 `ls-tree` / `ls-files -s` plus awk field 4 as the path: truncated at the first space (UNCONFIRMED end to end); :63 `--get-regexp` plus an awk equality on field 2 returns no key for "submodules/my engine" (measured). (4) scripts/fastcycle/cycle/baseline_replay.sh:1049-1052 `IFS=' ' read -r key path` over `--get-regexp` output: measured name=[submodules/my] path=[engine.path submodules/my engine] for the spaced submodule, plain one correct; effect on the replay (wrong modules/<name> reference) UNCONFIRMED. (5) scripts/gates/cm_helix_deps_ref_matches_gitlink.sh:79, :95, :105 `--get-regexp` plus an awk equality on field 2: measured key=[] for "submodules/my engine" (key found for the plain path), so line 79 reports a false DRIFT with url <none> (fail closed); end to end UNCONFIRMED. (6) low: scripts/fastcycle/consumers/migrate.sh:2432-2433 and docs/prompts/setup/latest.md:290 compare against fixed constitution paths. (7) scripts/deps_manifest/helix_deps_manifest.py:318-325 (review r2 G9): reads .gitmodules with `git config --get-regexp` text, `splitlines()`, the regex `^submodule\.(.*)\.(path|url) (.*)$` and `.strip()`, so a path with a leading or trailing space, a CR-class character or a newline is read wrong (by reading; not measured end to end, UNCONFIRMED). Fix shape proven in CON-030: NUL-separated machine formats (git config --null, git ls-files -s -z, git ls-tree -z), bytes decoded with os.fsdecode (surrogateescape), never whitespace or line splitting of a path. Each member needs its own RED on a spaced-path fixture first (section 11.4.292). Sources (tracked, section 11.4.215): docs/qa/con030_review/review_con030_r1.md (finding F5, with its measurements) and docs/qa/con030_review/review_con030_r2.md (finding G9, census of other users).

**Id note (section 11.4.214):** CON-070 is the id reserved on main for this CON-030 class item (docs/CONTINUATION.md); it is registered on main's tracker in CON-030 round 5 after the merge of main 90efceb8, which did not carry it.

## CON-290 — full-suite runner: tree_state hashes ignored files in the root only, so an ignored write inside a submodule is not detected (CON-030 review r3 H4)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-minted by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 2e8cfb90 merge by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 27dcf518 merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 9cd7cacd merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 64ac151d merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the fc57ad0c merge by Claude Opus 5.5 (CON-030 round 7 fixer subagent); re-minted at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)

**What:** the full-suite runner's tree-changed check misses an ignored file written inside a submodule. tree_state() in scripts/full_suite/run_full_suite.py lists and hashes ignored files with `git ls-files -o -i --exclude-standard -z` in the ROOT only; the `subs` record holds each submodule's status and diff, never its ignored files. A suite that writes an ignored file inside a submodule during the run therefore ends `RESULT: PASS-FULL` (rc 0), while the same write at the root (ignored by the root) ends `TREE CHANGED ... RESULT: FAIL` (rc 1). The same gap means a change of a submodule's ignored files does not change the resume key.

**Found by:** independent review of CON-030 round 3 (finding H4, pre-existing on main efe2cc6; outside CON-030's encoding/framing class, so registered as its own item per section 11.4.276(E)(2)). Parent: CON-030.

**Reproduction (reviewer's measurement, round-3 review sandbox, not repeated in this item):** submodule `lib` ignores `out/`, the suite writes `lib/out/x`, `--include-heavy` ends PASS-FULL rc 0; control: the same write at the root (`out/x`, ignored by the root) ends FAIL rc 1. Driver and log: docs/qa/con030_review/review_con030_r3.md (H4 row) and the driver copy docs/qa/con030_review/review_r3_drv_ign_sub.sh (sha256 0588354be227047b80d0531c65c96ee3c9560dae1b169d8dbb94a3328454fcef, as recorded in that review).

**Affected scope / file-scope manifest:** scripts/full_suite/run_full_suite.py (tree_state, IGNORED_NOT_HASHED), tests/test_run_full_suite.sh, tests/test_run_full_suite_mutations.sh, docs/guides/full_suite_runner_guide.md (the Results section and Limits; round 4 already states the root-only limit).

**Acceptance:** RED first on the broken engine with the reviewer's fixture (submodule ignored write ends PASS-FULL); the fix hashes the ignored files of every checked-out submodule (recursive), framed with hrec(), with the same exclusions; GREEN: the submodule write ends FAIL rc 1 and the control stays FAIL; a paired mutation that drops the submodule ignored-file records is killed; the guide's Limits line for this is removed.

**UNKNOWN:** the run-time cost of `git ls-files -o -i` in every submodule on this repository (not measured).

**Id history (section 11.4.214):** first minted on vehicle/con030 as CON-108 (commit 6a645831); re-minted as CON-116 in CON-030 round 5 (vehicle commit ede6686e, review r4 K6), because live main 90efceb8 already owns CON-108 for another item, and again as CON-146 after the merge of live main 2e8cfb90, which owns CON-116 for another item. The vehicle commits that name CON-108 are not rewritten (section 11.4.113). **Id history (section 11.4.214):** this item was CON-146 on vehicle/con030 before the merge of live main 27dcf518, which owns that id for another item; re-minted as CON-163. **Id map (section 11.4.214), merge of live main 27dcf518 into vehicle/con030 (CON-030 round 6):** CON-146 -> CON-163, CON-147 -> CON-164, CON-148 -> CON-165, CON-149 -> CON-166. Main 27dcf518 owns CON-146 to CON-162 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-163 on vehicle/con030 before the merge of live main 9cd7cacd, which owns that id for another item; re-minted as CON-186. **Id map (section 11.4.214), merge of live main 9cd7cacd into vehicle/con030 (CON-030 round 6):** CON-163 -> CON-186, CON-164 -> CON-187, CON-165 -> CON-188, CON-166 -> CON-189. Main 9cd7cacd owns CON-146 to CON-185 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-186 on vehicle/con030 before the merge of live main 64ac151d, which owns that id for another item; re-minted as CON-192. **Id map (section 11.4.214), merge of live main 64ac151d into vehicle/con030 (CON-030 round 6):** CON-186 -> CON-192, CON-187 -> CON-193, CON-188 -> CON-194, CON-189 -> CON-195. Main 64ac151d owns CON-146 to CON-191 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-192 on vehicle/con030 before the merge of live main fc57ad0c, which owns that id for another item; re-minted as CON-194. **Id map (section 11.4.214), merge of live main fc57ad0c into vehicle/con030 (CON-030 round 7):** CON-192 -> CON-194, CON-193 -> CON-195, CON-194 -> CON-196, CON-195 -> CON-197. Main fc57ad0c owns CON-146 to CON-193 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with.

**Id history (section 11.4.214):** this item was CON-194 on vehicle/con030 (head e5b1a74e); re-minted as CON-290 at the landing on main f25acdee, which names CON-194 as a former id of a CON-033 item. **Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

## CON-291 — full-suite runner: tree_ident splits git status and submodule status output with str.splitlines() (CON-030 round 4 class sweep, no verdict effect)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 4 fixer subagent); re-minted by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 2e8cfb90 merge by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 27dcf518 merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 9cd7cacd merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 64ac151d merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the fc57ad0c merge by Claude Opus 5.5 (CON-030 round 7 fixer subagent); re-minted at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)

**What:** found by the CON-030 round 4 class sweep (docs/qa/con030_review/con030_class_sweep_r4.py, shape B sites at tree_ident: the 'subs' hash of 'git submodule status --recursive' and the dirty-list hash of 'git status --porcelain=v1'). Both outputs are split with str.splitlines() (which also splits on NEL, LS, PS, CR, VT, FF) and joined with LF before hashing. With core.quotePath=false a path holding U+0085 is printed raw, so one untracked path 'a<NEL>?? b' and the two untracked paths 'a' and 'b' give the same dirty fragments and the same dirty hash. Parent: CON-030. **Why no verdict effect (reasoned from the code, not measured):** a dirty tree at the start already ends RESULT: PARTIAL-DIRTY-TREE rc 10, never PASS-FULL, and content changes during the run are caught by tree_state (TREE CHANGED, rc 1) and by the structured quick identity; so the collision changes only which identity message is shown. With the default core.quotePath=true git quotes these bytes. **Acceptance:** read both outputs NUL-terminated (git status -z, and the submodule list from git ls-files -s -z as quick_ident already does) or frame each line with hrec(); a test with core.quotePath=false and a NEL path shows two different dirty hashes; a paired mutation restoring splitlines() is killed. **UNKNOWN:** whether any consumer sets core.quotePath=false.

**Type (review r4 K11):** retyped from Task to Bug: an identity hash that two different trees can share is a defect, even when no verdict effect was found.

**Id history (section 11.4.214):** first minted on vehicle/con030 as CON-109 (commit a14824bd); re-minted as CON-117 in CON-030 round 5 (vehicle commit ede6686e, review r4 K6), because live main 90efceb8 already owns CON-109 for another item, and again as CON-147 after the merge of live main 2e8cfb90, which owns CON-117 for another item. The vehicle commits that name CON-109 are not rewritten (section 11.4.113). **Id history (section 11.4.214):** this item was CON-147 on vehicle/con030 before the merge of live main 27dcf518, which owns that id for another item; re-minted as CON-164. **Id map (section 11.4.214), merge of live main 27dcf518 into vehicle/con030 (CON-030 round 6):** CON-146 -> CON-163, CON-147 -> CON-164, CON-148 -> CON-165, CON-149 -> CON-166. Main 27dcf518 owns CON-146 to CON-162 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-164 on vehicle/con030 before the merge of live main 9cd7cacd, which owns that id for another item; re-minted as CON-187. **Id map (section 11.4.214), merge of live main 9cd7cacd into vehicle/con030 (CON-030 round 6):** CON-163 -> CON-186, CON-164 -> CON-187, CON-165 -> CON-188, CON-166 -> CON-189. Main 9cd7cacd owns CON-146 to CON-185 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-187 on vehicle/con030 before the merge of live main 64ac151d, which owns that id for another item; re-minted as CON-193. **Id map (section 11.4.214), merge of live main 64ac151d into vehicle/con030 (CON-030 round 6):** CON-186 -> CON-192, CON-187 -> CON-193, CON-188 -> CON-194, CON-189 -> CON-195. Main 64ac151d owns CON-146 to CON-191 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-193 on vehicle/con030 before the merge of live main fc57ad0c, which owns that id for another item; re-minted as CON-195. **Id map (section 11.4.214), merge of live main fc57ad0c into vehicle/con030 (CON-030 round 7):** CON-192 -> CON-194, CON-193 -> CON-195, CON-194 -> CON-196, CON-195 -> CON-197. Main fc57ad0c owns CON-146 to CON-193 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with.

**Id history (section 11.4.214):** this item was CON-195 on vehicle/con030 (head e5b1a74e); re-minted as CON-291 at the landing on main f25acdee, which names CON-195 as a former id of a CON-033 item. **Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

## CON-292 — full-suite runner: the resume context omits --timeout and the --env-extra variables, so a changed timeout or variable value reuses an earlier verdict (CON-030 review r4 K4)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 2e8cfb90 merge by Claude Opus 5.5 (CON-030 round 5 fixer subagent); re-minted after the 27dcf518 merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 9cd7cacd merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 64ac151d merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the fc57ad0c merge by Claude Opus 5.5 (CON-030 round 7 fixer subagent); re-minted at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)

**What:** a record in <out>/results.jsonl is reused when its key matches; the context part of the key (scripts/full_suite/run_full_suite.py, ctx) hashes the manifest, the known-failures table and the excluded lock only. The names and values of --env-extra variables, the caller environment the runner passes on (ENV_BASE) and --timeout are not in it. A run with a different value therefore resumes an earlier verdict.

**Found by:** independent review of CON-030 round 4 (finding K4, outside CON-030's declared class; pre-existing on main 90efceb8), registered as its own item per section 11.4.276(E)(2). Parent: CON-030.

**Reproduction (reviewer's measurement, round-4 review sandbox, not repeated in this item):** a fixture test passes only when FOO=1. Run 1 FOO=1 --env-extra FOO: PASS-FULL; run 2 FOO=0 --env-extra FOO with the same --out: resumed (PASS), PASS-FULL rc 0; control FOO=0 with a fresh --out: FAIL rc 1. A 3 s unit recorded with --timeout 60 is resumed by --timeout 1 (PASS-FULL rc 0; fresh control TIMEOUT rc 1). Drivers: drv/envextra_resume.sh and drv/timeout_resume.sh of the round-4 review (docs/qa/con030_review/review_con030_r4.md, K4 row).

**Why not fixed in CON-030 round 5:** putting variable VALUES into the context hash raises a credential question: the context hash is printed, and a truncated hash of a low-entropy secret can be guessed. The fix needs a decision: hash the values with a per-output-directory secret salt, refuse resume when --env-extra is given, or key on names plus --timeout only and document the rest. Round 5 documents the limit in docs/guides/full_suite_runner_guide.md (Results file and resume: use a new --out when these change).

**Affected scope / file-scope manifest:** scripts/full_suite/run_full_suite.py (ctx, ENV_BASE, env-extra handling), tests/test_run_full_suite.sh, tests/test_run_full_suite_mutations.sh, docs/guides/full_suite_runner_guide.md.

**Acceptance:** RED first with the reviewer's two fixtures on the unfixed engine; after the fix a changed --timeout and a changed --env-extra value each re-run the unit (GREEN), no value is printed or derivable from printed output (section 11.4.10), a paired mutation that drops each new key part is killed, and the guide states the rule. **Id history (section 11.4.214):** first minted on vehicle/con030 as CON-118 (commit ede6686e); re-minted as CON-148 after the merge of live main 2e8cfb90, which owns CON-118 for another item. **Id history (section 11.4.214):** this item was CON-148 on vehicle/con030 before the merge of live main 27dcf518, which owns that id for another item; re-minted as CON-165. **Id map (section 11.4.214), merge of live main 27dcf518 into vehicle/con030 (CON-030 round 6):** CON-146 -> CON-163, CON-147 -> CON-164, CON-148 -> CON-165, CON-149 -> CON-166. Main 27dcf518 owns CON-146 to CON-162 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-165 on vehicle/con030 before the merge of live main 9cd7cacd, which owns that id for another item; re-minted as CON-188. **Id map (section 11.4.214), merge of live main 9cd7cacd into vehicle/con030 (CON-030 round 6):** CON-163 -> CON-186, CON-164 -> CON-187, CON-165 -> CON-188, CON-166 -> CON-189. Main 9cd7cacd owns CON-146 to CON-185 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-188 on vehicle/con030 before the merge of live main 64ac151d, which owns that id for another item; re-minted as CON-194. **Id map (section 11.4.214), merge of live main 64ac151d into vehicle/con030 (CON-030 round 6):** CON-186 -> CON-192, CON-187 -> CON-193, CON-188 -> CON-194, CON-189 -> CON-195. Main 64ac151d owns CON-146 to CON-191 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-194 on vehicle/con030 before the merge of live main fc57ad0c, which owns that id for another item; re-minted as CON-196. **Id map (section 11.4.214), merge of live main fc57ad0c into vehicle/con030 (CON-030 round 7):** CON-192 -> CON-194, CON-193 -> CON-195, CON-194 -> CON-196, CON-195 -> CON-197. Main fc57ad0c owns CON-146 to CON-193 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with.

**Id history (section 11.4.214):** this item was CON-196 on vehicle/con030 (head e5b1a74e); re-minted as CON-292 at the landing on main f25acdee, which names CON-196 as a former id of a CON-033 item. **Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

## CON-293 — full-suite runner self-test: one run lost files from its own mktemp tree mid-run (8 FAIL, cause unknown, re-run passed)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 27dcf518 merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 9cd7cacd merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the 64ac151d merge by Claude Opus 5.5 (CON-030 round 6 fixer subagent); re-minted after the fc57ad0c merge by Claude Opus 5.5 (CON-030 round 7 fixer subagent); re-minted at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)
**Reproduction:** none — UNREPRODUCED — evidence `docs/qa/con030_review/con030_r5_selftest_flake_2026_11_10.log` — updated 2026-11-11T11:42:57Z — by `Claude Opus 5.5 (CON-030 round 7 fixer subagent)`
**Investigation:** not-started — updated 2026-11-11T11:42:57Z — by `Claude Opus 5.5 (CON-030 round 7 fixer subagent)`

**What:** one run of bash tests/test_run_full_suite.sh on the CON-030 vehicle (after the merge of main 90efceb8, 2026-11-10) reported 8 failures. Its log shows the self-test's own mktemp tree losing files while the run was going: git said 'fatal: cannot change to <tmp>/rfs_selftest.XXXXXX/good: No such file or directory'. The re-run of the identical files passed (364/0), and every later run passed (440/0, 454/0, 461/0). **Affected scope:** the proving suite of the full-suite runner (tests/test_run_full_suite.sh) and anything run beside it that may delete under the same TMPDIR. **Evidence:** docs/qa/con030_review/con030_r5_selftest_flake_2026_11_10.log (scratch paths replaced by <scratch>; the original log sha256 is in the CON-030 round-6 report). **Reproduction:** not reproduced; UNKNOWN which process removed the directory (candidates, none confirmed: another test's cleanup under a shared TMPDIR, a concurrent process cleaning the scratch tmp, a self-test path deleting its own fixture early). **Acceptance:** the cause is found with evidence, or a repeated-run campaign (N runs, N declared in advance) under an isolated TMPDIR shows it does not recur, with the result recorded. Reported by review r5 F5 (CON-030; sections 11.4.248, 11.4.197). **Id history (section 11.4.214):** this item was CON-149 on vehicle/con030 before the merge of live main 27dcf518, which owns that id for another item; re-minted as CON-166. **Id history (section 11.4.214):** this item was CON-166 on vehicle/con030 before the merge of live main 9cd7cacd, which owns that id for another item; re-minted as CON-189. **Id map (section 11.4.214), merge of live main 9cd7cacd into vehicle/con030 (CON-030 round 6):** CON-163 -> CON-186, CON-164 -> CON-187, CON-165 -> CON-188, CON-166 -> CON-189. Main 9cd7cacd owns CON-146 to CON-185 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-189 on vehicle/con030 before the merge of live main 64ac151d, which owns that id for another item; re-minted as CON-195. **Id map (section 11.4.214), merge of live main 64ac151d into vehicle/con030 (CON-030 round 6):** CON-186 -> CON-192, CON-187 -> CON-193, CON-188 -> CON-194, CON-189 -> CON-195. Main 64ac151d owns CON-146 to CON-191 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with. **Id history (section 11.4.214):** this item was CON-195 on vehicle/con030 before the merge of live main fc57ad0c, which owns that id for another item; re-minted as CON-197. **Id map (section 11.4.214), merge of live main fc57ad0c into vehicle/con030 (CON-030 round 7):** CON-192 -> CON-194, CON-193 -> CON-195, CON-194 -> CON-196, CON-195 -> CON-197. Main fc57ad0c owns CON-146 to CON-193 for other items, so the vehicle items were re-minted at the live next free id. Text written before this line keeps the ids it was written with.

**Id history (section 11.4.214):** this item was CON-197 on vehicle/con030 (head e5b1a74e); re-minted as CON-293 at the landing on main f25acdee, which names CON-197 as a former id of a CON-033 item. **Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

## CON-294 — full-suite runner: guide census near-marker test does not cover blank glyphs or look-alike letters that are not Default_Ignorable (CON-030 review r7 H3)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 8 fixer subagent); re-minted at the landing on main f25acdee by Claude Opus 5.5 (CON-030 round 8 lander subagent)

Parent: CON-030. **What:** the guide census near-marker test (marker_ignorable / marker_norm in scripts/full_suite/run_full_suite.py) removes white space, Zs, Cf, Default_Ignorable_Code_Point and U+FFFD before it compares a line with the census markers. Characters that render blank or look the same but are not in that class still hide a stale census block: review r7 measured verify rc 0 (MANIFEST-OK) with a stale block when the begin line starts with U+2800 (Braille pattern blank), when both markers use Cyrillic U+0441 (с) in place of the Latin letter c, and when the line starts with U+1D159 (a combining mark, Mn, not Default_Ignorable). **Affected scope:** --verify-manifest and --sync-guide on docs/guides/full_suite_runner_guide.md; no verdict of a test unit is affected. **Impact:** no worse than deleting the census block, which passes by design (guide line 34): a reader of the guide can be shown a stale census. **Reproduction:** review r7 probe probe7_head.txt (sha256 73ca19c886cb007de32ac8334f6b2a06480045693d0a87060780ed5668ec477e, reviewer sandbox, not in this repository): cases lead_braille_blank_U2800, homoglyph_cyr_es and lead_U1D159_Mn report verify rc 0 ok=True on head 3b919187. **Acceptance:** either (a) the near test also removes non-Default_Ignorable blank glyphs (at least U+2800) and compares markers through a confusable skeleton (Unicode UTS #39), with generated cells for each added member, RED on the round-8 engine and GREEN after, and a paired mutation per member; or (b) a recorded operator decision (section 11.4.66) that the guide must always carry a census block, so deletion, look-alike and blank-glyph routes are refused together, with the same RED/GREEN and mutation evidence. Found by CON-030 review r7 H3 (minor, section 11.4.276(G.2) follow-up).

**Id history (section 11.4.214):** this item was CON-198 on vehicle/con030 (head e5b1a74e); re-minted as CON-294 at the landing on main f25acdee, which names CON-198 as a former id of a CON-033 item. **Id map (section 11.4.214), landing of vehicle/con030 (head e5b1a74e) on main f25acdee:** CON-194 -> CON-290, CON-195 -> CON-291, CON-196 -> CON-292, CON-197 -> CON-293, CON-198 -> CON-294. Main f25acdee names CON-194 to CON-198 as former ids of the CON-033 items now CON-249 to CON-253, so the vehicle items were re-minted from CON-290 (CON-273 to CON-289 are claimed by other vehicles). CON-070 keeps its id (reserved on main for this CON-030 class item). Text written before this line keeps the ids it was written with.

## CON-295 — full-suite runner guide and test comment overstate the range-drop detection of section 2e (CON-030 review r8 N1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 8 lander subagent)

Review r8 N1 (process-doc): the guide and the self-test comment say a function that drops one DEFAULT_IGNORABLE range fails even when the table constant is right. That is not true for the 7 ranges that are entirely Cf (00AD, 061C, 200B-200F, 202A-202E, FEFF, 1BCA0-1BCA3, 1D173-1D17A; 0 non-Cf members each, measured by the reviewer): dropping one of them is behaviourally equivalent and section 2e does not detect it (the perl check still pins the constant). Acceptance: reword to 'a range with members outside Cf / white space'.

Source: CON-030 review r8 (docs/qa/con030_review/review_con030_r8.md, copied into the tree at landing), verdict GO-pending-table, minor-class nit registered as a follow-up per section 11.4.276(G.2). Parent: CON-030.

## CON-296 — full-suite runner self-test oracle shares the engine formula; compare marker_ignorable with the perl-derived set (CON-030 review r8 N2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 8 lander subagent)

Review r8 N2 (test-instrumentation): the in-suite oracle for marker_ignorable is independent code but the same formula (isspace, U+FFFD, Cf/Zs through the same unicodedata, the same table); only its DEFAULT_IGNORABLE table is independently anchored by perl. It pins the function against regression but would not catch a spec error shared by both. Optional acceptance: when perl is installed, compare marker_ignorable with the perl-derived set (expected delta U+001C-001F), RED first on a mutant that a shared-formula error would pass.

Source: CON-030 review r8 (docs/qa/con030_review/review_con030_r8.md, copied into the tree at landing), verdict GO-pending-table, minor-class nit registered as a follow-up per section 11.4.276(G.2). Parent: CON-030.

## CON-297 — full-suite runner self-test NEG control does not prove the BAD comparison path can see a dropped range (CON-030 review r8 N3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 8 lander subagent)

Review r8 N3 (test-instrumentation): the NEG control compares the oracle with the oracle minus one range, so it shows the oracle can see a range but not that the BAD comparison path can; mutant RV7c (row 195 of the mutation table) covers that path, so the value is low. Acceptance: either drive the comparison path with a known-bad function in the NEG control, or record the reasoned equivalence with RV7c.

Source: CON-030 review r8 (docs/qa/con030_review/review_con030_r8.md, copied into the tree at landing), verdict GO-pending-table, minor-class nit registered as a follow-up per section 11.4.276(G.2). Parent: CON-030.

## CON-298 — full-suite runner mutation table should adopt reviewer mutants M8c and M8b as rows (CON-030 review r8 N4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (CON-030 round 8 lander subagent)

Review r8 N4 (test-instrumentation): reviewer mutants M8c (category in (Cf,Zs) widened to category[0] == 'C') and M8b survive the round-7 self-test and are killed only by section 2e of the round-8 self-test (reviewer rows in the review sandbox rev_con030_r8/mut/rows.tsv). Acceptance: add M8c and M8b to tests/test_run_full_suite_mutations.sh verbatim, each observed killed on the current self-test.

Source: CON-030 review r8 (docs/qa/con030_review/review_con030_r8.md, copied into the tree at landing), verdict GO-pending-table, minor-class nit registered as a follow-up per section 11.4.276(G.2). Parent: CON-030.

## CON-299 — land_vehicle lander: land reviewed vehicle bundles onto main of every upstream (scripts/release/land_vehicle.sh)

**Status:** Queued
**Type:** Task
**Severity:** medium

Lander script scripts/release/land_vehicle.sh with its test tests/release/test_land_vehicle.sh and docs/qa/land_vehicle_r4, r5, r6 evidence; rounds 4 to 6 squashed into one commit on main; independent review round 7 verdict GO-with-follow-ups (review sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405); evidence class gate logic only; PROVISIONAL per 11.4.290.

## CON-300 — CON-234 follow-up: derive_release_facts.sh in a shallow clone prints a silently truncated commit count (G6 of review fix227 round 2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Sonnet 5.5 (fixer subagent, vehicle/fix227 round 3)

Review docs/qa/review_fix227_r2.md finding G6 (minor class, decided: no corrupt-repository fix in CON-234). Other git commands in the buffered section of scripts/release/derive_release_facts.sh (rev-list --count, diff --shortstat, log) are not flagged when they fail; the previous tag and the base are verified commits before the buffer, so a failure needs a corrupt repository. A shallow clone is different: it can give a silently truncated commits_since_prev or shortstat_since_prev without any error. To do: detect a shallow repository (git rev-parse --is-shallow-repository) and refuse with exit 3 naming it, or print the shallow state as a fact; add a test with a shallow clone fixture and a paired mutant. Re-minted CON-269 at the merge of main 581a2939 into vehicle/fix227: this item was CON-249 on the vehicle (main already used CON-249 for another item). Vehicle history of CON-249: Opened by User at 2026-11-11 16:26:51 UTC. Re-minted CON-300 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-269 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-269: Opened by User at 2026-11-11 19:08:24 UTC.

## CON-301 — CON-234 follow-up: tag_and_release.sh prints the GitHub repository id returned by gh api without checking that it is a number

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fresh-instance structural fixer subagent, vehicle/fix227 round 4)

tag_and_release.sh reads the repository id with gh api to de-duplicate GitHub legs and prints it in messages without checking it is numeric (server-controlled text, not a credential). The publisher already validates its server release id (round 4, I-4); do the same here. Found during the round-4 census (docs/qa/con227_234_2026_11_11/round4/threat_model.md section 3). Round 5: tag_and_release.sh now checks the id with ^[0-9]{1,20}$ before use and prints nothing else (case C38); left Queued until the independent review of round 5 confirms it. Re-minted CON-270 at the merge of main 581a2939 into vehicle/fix227: this item was CON-250 on the vehicle (main already used CON-250 for another item). Vehicle history of CON-250: Opened by User at 2026-11-11 17:20:42 UTC; Updated by AI at 2026-11-11 17:20:48 UTC. Round 6: unchanged (the tag script checks the id with ^[0-9]{1,20}$, case C38); left Queued until an independent review confirms it. Re-minted CON-301 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-270 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-270: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-302 — CON-234 follow-up: known limits of the redact-then-cut helper (parameter value with a raw blank or & # ; quote < >, a credential split over two lines, a bare-word secret)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fresh-instance structural fixer subagent, vehicle/fix227 round 4)

scripts/release/redact_cut.sh redacts five shapes per whole line (docs/qa/con227_234_2026_11_11/round4/threat_model.md). Left open by design and documented in the helper header: a credential-named parameter VALUE holding a raw blank or one of & # ; quote < > prints its tail after that character; a credential split by a raw newline is not seen; a secret in none of the shapes (a bare word) is not recognised; R4 scans the first N+4096 bytes. Decide whether any of these needs a rule (for example redact to end of line after a credential-named parameter). Round 5: the scan window limit (R4 scanned the first N+4096 bytes) is gone, every rule scans the whole line; the helper now matters only for local stderr and the publisher's own lines, because network stderr is never printed (threat_model.md section 5). The other limits remain. Re-minted CON-271 at the merge of main 581a2939 into vehicle/fix227: this item was CON-251 on the vehicle (main already used CON-251 for another item). Vehicle history of CON-251: Opened by User at 2026-11-11 17:20:42 UTC; Updated by AI at 2026-11-11 17:20:48 UTC. Round 6: three more shapes are covered (blanks around =, NAME%3Dvalue, JSON "name": "value"; cases N1a..f). The listed limits remain; they matter only for local stderr and the publisher's own lines. Re-minted CON-302 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-271 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-271: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-303 — CON-234 follow-up: the SIGINT trap of the release scripts is not exercised by a test

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fresh-instance structural fixer subagent, vehicle/fix227 round 4)

The round-4 tests drive SIGTERM and SIGHUP into tag_and_release.sh and release_publish_gitea.sh and check that the run directory is removed (C27, publisher 14). SIGINT is not driven because a background job of a non-interactive shell starts with SIGINT ignored; the INT trap uses the same exit path. Add a test that runs the script in its own process group (setsid) so SIGINT is delivered, or record why it cannot be. Re-minted CON-272 at the merge of main 581a2939 into vehicle/fix227: this item was CON-252 on the vehicle (main already used CON-252 for another item). Vehicle history of CON-252: Opened by User at 2026-11-11 17:20:42 UTC; Updated by AI at 2026-11-11 17:20:48 UTC. Re-minted CON-303 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-272 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-272: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-304 — CON-234 follow-up (J7): a guard that refuses pkill / killall / pgrep -f driven signals in agent sessions

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (round-5 structural fixer subagent, vehicle/fix227)

Review docs/qa/review_fix227_r4.md finding J7: the round-4 fixer ran pkill -f "sleep 30" -P 1, which signals every process of the uid whose parent is PID 1 and whose command line holds sleep 30, not only its own (record: docs/qa/con227_234_2026_11_11/round5/incident_j7.md, severity UNKNOWN, no record of the signalled PIDs). Add a PreToolUse guard (or extend scripts/hooks/guard-destructive-paths.py / the killpg gate) that refuses pkill, killall and a pgrep -f pipe into kill, with golden-true and golden-false fixtures and a paired mutant; section 11.4.174, 11.4.263, 11.4.201. Re-minted CON-304 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-273 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-273: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-305 — Incident (J7): unscoped pkill -f "sleep 30" -P 1 run by the round-4 release-tooling fixer; effect UNKNOWN

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-5 structural fixer subagent, vehicle/fix227)

Recorded by the round-5 fixer from the review (docs/qa/review_fix227_r4.md, J7); the round-5 fixer did not run or observe it. Known: the command was run. Not known: which PIDs matched, whose they were, whether any watchdog of another session fired early. Severity UNKNOWN (section 11.4.6). Record: docs/qa/con227_234_2026_11_11/round5/incident_j7.md. Close as not-reproducible with that evidence, or with a better record if one appears; prevention is CON-304. Re-minted CON-305 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-274 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-274: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-306 — CON-234 follow-up: release scripts run network commands unbounded when timeout(1) is absent

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-5 structural fixer subagent, vehicle/fix227)

Round 5 bounds every network command with timeout(1) (RELEASE_NET_TIMEOUT). When timeout(1) is not on PATH the tag script prints a warning and runs them unbounded; git http.lowSpeedLimit and curl -m still apply. Decide: refuse to run, or keep the warning (threat_model.md section 5). Round 6 correction (review scratchpad/review_fix227_r5.md, K2): this item's round-5 premise, that every network command is bounded when timeout(1) is present, was wrong: timeout --foreground signalled only its direct child and git's transport helpers ran on (60-300 s measured). Round 6 drops --foreground (the whole process group is signalled; C41 with real git). What this item tracks is unchanged: without timeout(1) the tag script warns and runs the network commands unbounded. Re-minted CON-306 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-275 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-275: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-307 — CON-234 follow-up: after SIGKILL the release scripts leave their 0700 run directory (release notes, local stderr)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-5 structural fixer subagent, vehicle/fix227)

No trap runs on SIGKILL, so the mktemp -d run directory stays under TMPDIR. After round 5 it never holds the token (publisher case 18); it can hold the release notes and local stderr. Decide whether a stale-run-directory sweep at start (own prefix, proven-dead owner, guarded delete) is worth adding. Re-minted CON-307 at the merge of main 66ad6efe into vehicle/fix227 (round 6, section 11.4.214): this item was CON-276 on the vehicle; main uses CON-269..CON-272 for the README-link review items, CON-280+ belongs to the CON-046 vehicle and CON-290..CON-298 are taken. Vehicle history of CON-276: Opened by User at 2026-11-11 19:08:25 UTC.

## CON-308 — CON-234 follow-up: limits of the round-6 channel census (static instrument; runtime recorders only for the publisher)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)

tests/release/channel_census.py finds external command invocations statically. It does not see a command assembled at run time (eval, "$cmd"), a command another program runs (git's transport helpers), or a script it is not given; the runtime half of tests/release/test_channel_census.sh runs only the publisher with recorders, while the tag script's children are covered at run time by C43 and C44 (real git under tests/release/net_probe.py), not by a recorder for every row. Decide whether a recorder run of the tag script (all rows) is worth adding. Record: docs/qa/con227_234_2026_11_11/round6/threat_model.md section 5. Round 7: the environment channel now has runtime recorders for every child of all three scripts (tests/release/env_census.py; tag C48, publisher case 29, derive L2), but only on the paths the suites drive; the static lint remains the only cover for a command on a path no suite reaches.

## CON-309 — CON-234 follow-up: rc_env_lockdown drops proxy variables, so the release scripts cannot reach a remote through a proxy

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-6 structural fixer subagent, vehicle/fix227)

rc_env_lockdown (round 6, K3) passes only an allow-list to children, and RELEASE_ENV_KEEP refuses any name that looks like a credential, PROXY included (a proxy URL can carry a user name and password). http_proxy, https_proxy, HTTPS_PROXY, ALL_PROXY and NO_PROXY therefore never reach git, curl, gh or glab. Decide: keep (a release host without a proxy), or pass the proxy variables after the same userinfo check as the remote URLs (rc_url_has_userinfo). Record: docs/qa/con227_234_2026_11_11/round6/threat_model.md.

## CON-310 — CON-234 follow-up (L7): a remote URL with an ssh user name or a token in its query string is not refused by the release scripts

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-7 structural fixer subagent, vehicle/fix227)

rc_url_has_userinfo (round 6, K1) refuses a remote URL that carries a userinfo part (user:password@ or token@ after a scheme), and rc_safe_url never prints a path or a query. Two shapes are not refused: an scp-like or ssh:// URL with a user name only (git@host:org/repo.git, the normal form, carries no secret but the user name reaches git argv and /proc/PID/cmdline), and an https URL whose query string holds a token (https://host/repo.git?token=...), which git puts in the argv of git-remote-https. Decide per shape: accept the ssh user name as not secret (likely), and refuse or strip a query string on a push or fetch URL. Found by the round-6 review (L7, scratchpad/review_fix227_r6.md); record: docs/qa/con227_234_2026_11_11/round7/threat_model.md.

## CON-311 — Follow-up of CON-234 L5: 35 scripts outside tests/release trap INT or TERM with a cleanup handler that does not exit, so the script runs on after the signal

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (round-7 structural fixer subagent, vehicle/fix227)

Round 7 found (L5 of the round-6 review) that a handler installed with 'trap cleanup EXIT INT TERM' (or a similar list) runs cleanup on INT or TERM and then returns, so bash continues with the next command instead of stopping; the release suites and the mutation harness were fixed (the handler exits with 128 plus the signal number). The same shape is in 35 tracked scripts outside tests/release (measured on the round-7 head with: git grep -nE '^\s*trap [a-z_]+ EXIT( INT)? (INT|TERM)' -- ':!tests/release'; 35 lines in 35 files). Out of scope of CON-234; each site needs the same fix and a test that sends TERM and checks the exit status and that no later command ran. Record: docs/qa/con227_234_2026_11_11/round7/threat_model.md.

## CON-312 — Installer SIGPIPE under pipefail: a pipe into an early-exit reader (grep -q) reads a match as no match

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `docs/qa/installer_sigpipe_2026_11_13/harness/harness_old_run1.txt` — red-command `bash docs/qa/installer_sigpipe_2026_11_13/tools/red_harness.sh (old = b5a1815a installer)` — green-command `bash docs/qa/installer_sigpipe_2026_11_13/tools/red_harness.sh (new = this change); bash tests/install/test_sigpipe.sh` — signature `hi_push_changed reads b == a as a push; Z line not seen (pipeline status 141 from SIGPIPE)` — updated 2026-11-15T09:28:26Z — by `Claude Opus 5.5 (lander subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `a pipe into an early-exit reader (grep -q) under pipefail: the writer dies of SIGPIPE and the pipeline status 141 turns a match into no match` — evidence `docs/qa/installer_sigpipe_2026_11_13/README.md` — updated 2026-11-15T09:28:26Z — by `Claude Opus 5.5 (lander subagent)`

scripts/install_constitution.sh runs under set -u -o pipefail; hi_push_changed tested membership with printf | grep -qxF. grep -q exits at the first match, printf dies of SIGPIPE, the pipeline returns 141 and a MATCH reads as NO MATCH: an unchanged remote is read as a push (false refusal, exit 5) and a missing fingerprint tool (Z line) is not seen (false pass of a fail-closed check). Fixed on vehicle/installer-sigpipe-r2 (head 2e397cba): no pipe into an early-exit reader under pipefail in the installer, updater and action-prefix libraries (here-string count 0), deny-by-default no-push gate scanner, test_sigpipe.sh (PASS 67 / FAIL 0, 3 of 3 runs), test_lock stale-poll race and test_round8 chaos-loop hardening (F9 race UNREPRODUCED). Review round 2 GO-with-follow-ups (review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997); follow-ups F1, F3, F4 filed separately. Evidence: docs/qa/installer_sigpipe_2026_11_13/. Status PROVISIONAL (section 11.4.290); evidence class gate-logic and unit (section 11.4.289). Installer SIGPIPE r2 follow-ups F2 and F6 filed as CON-389 and CON-390 (F1, F3, F4, F5 are CON-363 to CON-366).

## CON-313 — workable-items engine: close and sync md-to-db rewrite items.created_at; restore-created-at repairs rewritten rows

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `docs/qa/engine_created_at_2026_11_13/red_go_tests_base.txt` — red-command `go test ./... in scripts/workable-items on the base engine source (created_at_preservation_test.go)` — green-command `go test -count=1 ./... in scripts/workable-items on this change` — signature `close-*: section created_at rewritten to the command time, want the original value` — updated 2026-11-15T10:51:33Z — by `Claude Opus 5.5 (lander subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `close and sync md-to-db wrote items.created_at from the current time instead of keeping the stored value` — evidence `docs/qa/engine_created_at_2026_11_13/README.md` — updated 2026-11-15T10:51:33Z — by `Claude Opus 5.5 (lander subagent)`

The engine's close (and sync md-to-db) rewrote items.created_at to the time of the command, so a closed item lost its creation time. Fixed on the engine vehicle (head fa1c9302, rounds 1-4): close and sync md-to-db keep created_at; a new restore-created-at command restores a rewritten value from a committed evidence database (sha256-checked, audit history row, refuses a value later than the item's first history event); docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh applies restore_plan.tsv (CON-243, CON-308) through it. The vehicle's text calls this item CON-339, a provisional id of the unlanded tracker-intake vehicle b48091ea; re-minted at landing on main (section 11.4.214). Review round 4 GO-with-follow-ups (review_engine_r4.md sha256 c21872afec82e1bb1471f4f9314efc0990299bfa99c6c312e92cabadac243b6d). go test 877 PASS / 0 FAIL / 6 SKIP twice; applier suite 100/0. Evidence: docs/qa/engine_created_at_2026_11_13/. Status PROVISIONAL (section 11.4.290); evidence class gate-logic and unit (section 11.4.289). The restore plan was applied in part after landing: commit 464cd498 restored CON-243 (created_at 2026-11-11 15:38:57 to 15:34:35, history row 543, evidence bd0036bd:docs/workable_items.db sha256 117126b045a86f4387e3092836867e0dd82b6fa17676e23098ca81c70b2fcbf4). The CON-308 row was deliberately not applied: it assumes the tracker-intake vehicle's ids (main's CON-308 is a different item) and its evidence commit 1a307322 is not in this repository; it is tracked as CON-387. Follow-up register drafts filed (section 11.4.214, filing wave CON-388): CON-PENDING-MDRT-DATALOSS as CON-391, CON-PENDING-226-ROWS (D-05) as CON-392, CON-PENDING-CON243-NONUNIFORM as CON-393, CON-PENDING-EVIDENCE-PROVENANCE as CON-394, D-01 CON-395, D-02 CON-396, D-03 CON-397, D-04 CON-398, D-06 CON-399, D-07 CON-400; D-08 to D-10 are CON-370 to CON-372.

## CON-314 — Installer timeouts hang under uutils timeout when the command touches the terminal (SIGTTIN/SIGTTOU not ignored at every timeout reachable from install, update, post-update hook and bootstrap)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `docs/qa/installer_followups_r2_2026_11_14/runs/timeout_tty_RED_before_fix_r2.txt` — red-command `bash tests/install/test_timeout_tty.sh (on the round-1 sources e1bf1bad)` — green-command `bash tests/install/test_timeout_tty.sh (this change)` — signature `T8 post_update_hook install_jev_bootstrap [uutils]: rc=CAPPED (limit never fires; timeout stopped by SIGTTOU/SIGTTIN)` — updated 2026-11-15T11:17:51Z — by `Claude Opus 5.5 (lander subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `uutils timeout does not ignore SIGTTIN/SIGTTOU; a terminal-touching command in its background process group stops timeout with it, so the limit never fires` — evidence `docs/qa/installer_followups_2026_11_14/README.md` — updated 2026-11-15T11:17:51Z — by `Claude Opus 5.5 (lander subagent)`

uutils timeout (0.10.0) does not ignore SIGTTIN/SIGTTOU: without --foreground it runs the command in a background process group of the terminal, a command that touches the terminal stops timeout together with itself, and the limit never fires (GNU timeout ignores both and still fires). Every timeout reachable from install_constitution.sh, update_constitution.sh, post_update_hook.sh and jev/bootstrap.sh could hang the installer or the post-update hook (RED: T8 post_update_hook install_jev_bootstrap [uutils] rc=CAPPED). Same mechanism as CON-112, distinct scope (CON-112 is the gates runner route; section 11.4.214 distinct-but-similar, linked not merged). Fixed on the installer follow-ups vehicle (rounds 1-2, head d659fddd): trap '' TTIN TTOU before every reachable timeout (19 sites by a derived census, 15 yes / 4 no with exact assertions), pty driver session race, python3 -I for inline Python, stale no-push gate allow-list entries, patsub_replacement comment; tests/install/test_timeout_tty.sh (PASS 25 / FAIL 0, 3 of 3 runs, GNU and uutils), test_python_isolation.sh, test_shell_state_patsub.sh. Review round 2 GO-with-follow-ups (review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0); follow-ups R2-1..R2-5 filed separately. Evidence: docs/qa/installer_followups_2026_11_14/ and docs/qa/installer_followups_r2_2026_11_14/. Status PROVISIONAL (section 11.4.290); evidence class gate-logic and unit (section 11.4.289). Recurrence link (section 11.4.214, installer follow-ups r2 review R2-1, /mnt/DATA1TB/claude-work/scratch/rev_fu_r2.W98s/review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0 (verdict GO-with-follow-ups)): the census scan of tests/install/test_timeout_tty.sh credits a trap '' TTIN TTOU that does not reach the timeout (closed subshell RM-1, string carrier RM-2, trap - TTOU RM-3, background job RM-5); each surviving mutant hangs live. Same class as round-1 F-3. Fix: credit only adjacent forms, or add needles or live pty cases. Related follow-ups filed as CON-352, CON-353, CON-354, CON-355, CON-358.

## CON-315 — Follow-up filing wave 2026-11-15: register the approved review follow-ups through the engine (deduplicated per section 11.4.214)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: register, in one pass, the review follow-ups the operator approved (approve all, dedupe first, file through the engine, never hand-edit the DB): the 67-item list with its later severity and split changes, plus the new follow-ups of the installer r2, lander r7, fix227 r14, installer SIGPIPE r2, engine r4, idguard r9, case-alt r4 and Jev toolkit r3 reviews. Scope: docs/workable_items.db and the files exported from it (docs/Issues.md, docs/Issues_Summary.md). Items of vehicles still under review (sync r9, gitenv r4, tracker intake r9, Jev constitution r9, CON-046 r12) are held back and listed in the hand-back report, not filed. Reproduction: not applicable (process item). Acceptance: every filed item carries what, scope, reproduction, acceptance and source; duplicates are linked or skipped, never re-minted; engine validate OK and diff in sync; full-suite manifest verify MANIFEST-OK; pushed fast-forward to every reachable upstream. Source: session-74ce2b36 scratchpad (outside the repository)/followup_items_ready.md sha256 6c69ae0577e4e8ef0300723a4c91267a0f0b6e63a5e5c5e97ba251d14ec46938.

## CON-316 — Security scripts R4-1: forge branch-protect keys-file mode check is untested for mode 0604 (reviewer mutant V9 survives)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the keys-file permission check of the forge branch-protect script refuses group/other-readable files, but no test feeds a 0604 file, so reviewer mutant V9 (narrowed mode test) survives. Scope: tests/security/test_forge_branch_protect.sh of the security-scripts vehicle (not yet on main). Reproduction: UNKNOWN: not run in this filing; the reviewer recorded V9 surviving. Acceptance: a 0604 keys file is refused by a test and V9 is killed; adopt V9 in the mutant manifest. Source: session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; vehicle bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa (head e940110e, not on main). Approved list FU-01.

## CON-317 — Security scripts R4-2: the '.netrc is not used' claim of the forge branch-protect script has no test (mutant V7 survives)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the script documents that ~/.netrc is never read, but no test plants a .netrc and checks it is not used; mutant V7 survives. Scope: tests/security/test_forge_branch_protect.sh (security-scripts vehicle, not on main). Reproduction: UNKNOWN: not run in this filing. Acceptance: a test with a planted .netrc under a sandbox HOME proves the credential is not sent; V7 killed. Source: session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; vehicle bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa (head e940110e, not on main). Approved list FU-02.

## CON-318 — Security scripts R4-3: the test-only loopback exception is wider than documented (mutants V3, V13)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the test-only exception that allows a loopback endpoint accepts more than the documented shape; reviewer mutants V3 and V13 show the gap. Scope: forge branch-protect script and its test (security-scripts vehicle, not on main). Reproduction: UNKNOWN: not run in this filing. Acceptance: the exception accepts only the documented loopback form (or the documentation states the real shape), with tests that kill V3 and V13. Source: session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; vehicle bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa (head e940110e, not on main). Approved list FU-03.

## CON-319 — Security scripts R4-4: mutant V15 is probably equivalent; record the equivalence proof or add a killing test

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: reviewer mutant V15 survives; the review judges it likely equivalent given the curl URL parser, which is UNCONFIRMED. Scope: security-scripts vehicle mutant table (not on main). Reproduction: UNKNOWN: not run in this filing. Acceptance: either a recorded equivalence argument checked against curl's parser, or a test that kills V15. Source: session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; vehicle bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa (head e940110e, not on main). Approved list FU-04.

## CON-320 — Security scripts R4-5: re-run part 1 of the round-3 mutant set on the final tree

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the round-3 mutant part 1 was run on an earlier tree; the review asks for a re-run on the final head so the kill table matches the shipped code. Scope: security-scripts vehicle (head e940110e, not on main). Reproduction: not applicable (evidence refresh). Acceptance: the part-1 mutant table re-run on the final head, committed with its run count and sha256. Source: session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; vehicle bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa (head e940110e, not on main). Approved list FU-05.

## CON-321 — Security apply: record the second evidence leg on the next ordinary push

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the applied forge settings were read back once; the apply report leaves open a second evidence leg that is only observable on the next ordinary push (the push is accepted or refused as the settings say). Scope: own-org forge settings applied by the security apply; evidence dir of that apply. Reproduction: not applicable (evidence leg). Acceptance: after the next ordinary push, the observed outcome per forge is recorded next to the first read-back, with sha256. Source: session-74ce2b36 scratchpad (outside the repository)/security_apply_report.md sha256 e819623b215642534db606cec057fdf066665597d9917341f286819727cf8571. Approved list FU-06; same family as FU-07..09.

## CON-322 — Codeberg: force-push blocking cannot be read back (Forgejo 17.0.0 has no enable_force_push field)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the security apply could not read back whether force pushes are blocked on Codeberg: the Forgejo 17.0.0 branch-protection API returns no enable_force_push field, so the setting is UNCONFIRMED. Scope: the Codeberg mirror of the constitution (and any own-org Codeberg repository the apply covers). Reproduction: UNKNOWN: a read-back path other than the API field has not been tried. Acceptance: either a second read-back that shows force pushes are refused (for example a refused force push to a throw-away protected branch, without touching main), or the gap recorded as an accepted honest limit per section 11.4.6. Source: session-74ce2b36 scratchpad (outside the repository)/security_apply_report.md sha256 e819623b215642534db606cec057fdf066665597d9917341f286819727cf8571. Approved list FU-07; severity raised to important by the operator.

## CON-323 — Terminator: verify the GitHub Actions disable leg and that Dependabot runs stop

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: after disabling GitHub Actions and Dependabot on HelixDevelopment/terminator, check that no further workflow or Dependabot runs appear; the independent read-back was identical in 3 runs but the time-triggered part needs a later check. Scope: HelixDevelopment/terminator repository settings. Reproduction: time-triggered: re-check after about 2026-11-15. Acceptance: a dated read-back showing no runs since the disable, with sha256 of the evidence. Source: session-74ce2b36 scratchpad (outside the repository)/terminator_report.md sha256 c41e8e142a8cb91eed8505d87454c3fb779eee42deea8717f8355778bc87514a; session-74ce2b36 scratchpad (outside the repository)/terminator_followup_report.md sha256 6dc254d333d39bda1019c3af48a52dde9d8668bd05dd636c5d5779302c81bd5b. Approved list FU-08; Type Task (a check, not a defect).

## CON-324 — Terminator Dependabot change: mint a real id for the placeholder trailer CON-PENDING-TERMINATOR-DEPENDABOT (commits 347db45, 19fe5a7)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the terminator commits 347db45 and 19fe5a7 on HelixDevelopment/terminator main carry the placeholder Roadmap-Item CON-PENDING-TERMINATOR-DEPENDABOT; this item is the real id for that work. Scope: HelixDevelopment/terminator main; this tracker. Reproduction: not applicable (process item). Acceptance: the placeholder is mapped to this id in the terminator repository's records (a follow-up commit or note, never a history rewrite). Source: session-74ce2b36 scratchpad (outside the repository)/terminator_report.md sha256 c41e8e142a8cb91eed8505d87454c3fb779eee42deea8717f8355778bc87514a; session-74ce2b36 scratchpad (outside the repository)/terminator_followup_report.md sha256 6dc254d333d39bda1019c3af48a52dde9d8668bd05dd636c5d5779302c81bd5b. Approved list FU-09; relates to FU-08. FU-10 (close or keep Dependabot PRs 1, 3, 4) is an operator decision and is not filed here.

## CON-325 — Host tmux scope hits pids.max=6000 repeatedly (pids.events max 285 to 380); uutils sort/comm fail with EAGAIN

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: the tmux user scope hit its pids.max of 6000 (pids.events max counted 285 to 380); uutils sort and comm failed with EAGAIN and the first Actions apply was refused fail-closed. Scope: host session scope (section 12.12); the tools affected were run from it. Reproduction: UNREPRODUCED: observed during the terminator work; whether the cause is the scope limit or tool behaviour is UNCONFIRMED. Investigate first per section 11.4.292. Acceptance: a root cause backed by evidence (which processes fill the scope), and either a fixed limit or fixed process fan-out, with a check that records pids.current and pids.events before heavy runs. Source: session-74ce2b36 scratchpad (outside the repository)/terminator_report.md sha256 c41e8e142a8cb91eed8505d87454c3fb779eee42deea8717f8355778bc87514a; session-74ce2b36 scratchpad (outside the repository)/terminator_followup_report.md sha256 6dc254d333d39bda1019c3af48a52dde9d8668bd05dd636c5d5779302c81bd5b. Approved list FU-11; host safety, severity raised to important by the operator.

## CON-326 — llmctl svc_hook gate depends on /dev/shm ownership and leaves a failed unit that does not heal itself

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: llmctl-llama decide-nli ExecStartPre exited 75 four times (StartLimitBurst 3 per 900 s), leaving the unit failed; the svc_hook gate depended on /dev/shm ownership, which showed uid 65534 at the time. Today /dev/shm is root:root and the verdict is fits. Scope: llmctl (submodule) svc_hook gate and its unit template; the constitution pin of llmctl. Reproduction: UNREPRODUCED: why /dev/shm showed uid 65534 is UNCONFIRMED. Acceptance: the gate does not depend on /dev/shm ownership (or refuses with a clear reason that does not exhaust the start limit), and a failed unit recovers or is reported; fix lands in llmctl and the pin is bumped. Source: session-74ce2b36 scratchpad (outside the repository)/llmctl_failed_units_diagnosis.md sha256 6151f6c752e1fcd64923e9fbc3a4df0a3bb99a6008c71a22a50085b611b6a623. Approved list FU-12; severity raised to important by the operator.

## CON-327 — llmctl-llama@decide-kev-08b: identify the sender of SIGTERM behind the about 82 s start/stop cycles

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the unit llmctl-llama@decide-kev-08b started and was stopped by SIGTERM about every 82 s; the sender is UNCONFIRMED. The svc_hook.sh:272 cmdline race is harmless. A failed but fitting unit must not read as does_not_fit (section 11.4.291). Scope: llmctl decide units on this host. Reproduction: UNKNOWN: not re-run in this filing. Acceptance: the SIGTERM sender identified from evidence (journal, audit), and the cycle stopped or explained. Source: session-74ce2b36 scratchpad (outside the repository)/llmctl_failed_units_diagnosis.md sha256 6151f6c752e1fcd64923e9fbc3a4df0a3bb99a6008c71a22a50085b611b6a623. Approved list FU-13; related to FU-12.

## CON-328 — Jev gate: an uppercase HTTPS:// JEV_BASE_URL sends the decision body without the key pin to an unpinned origin (jev-gate.sh:353,454,466)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: the scheme check of the Jev gate compares case-sensitively, so JEV_BASE_URL=HTTPS://... is not treated as the pinned https origin; the decision body is sent keyless to an origin the pin does not cover. Scope: claude_toolkit Jev gate (scripts/jev-gate.sh), failover vehicle r2/r3 (not landed). Reproduction: UNREPRODUCED in this filing; reported by the r2 review (N1) and still open in r3. Acceptance: the base URL scheme and host are lower-cased before every comparison, with a test for HTTPS:// and mixed case. Source: claude_toolkit_jev_failover_r2.bundle sha256 5f9dd042f610980cf560b104fc6910ba168d9036abc1be8ce13b746ecea85b3b; session-74ce2b36 scratchpad (outside the repository)/rev_jevtk_r3.4iGB/review_jev_toolkit_r3.md sha256 74a00d771f2fa5cf150e25a341e1bf9956575e409def7b04370ab6669a46950c; vehicle bundle claude_toolkit_jev_failover_r3.bundle (head 5c6092f4, not landed). Approved list FU-39 (r2 N1); stays open in r3. Same class as FU-18 (scheme handling), which a fix vehicle covers: linked, not merged. Security-adjacent, severity important.

## CON-329 — Jev MCP: JEV_MCP_MAX_ATTEMPTS of 0 or less means 1 attempt while the gate maps the same values to 3 (jev_mcp.py:452 vs jev-gate.sh:444)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: jev_mcp.py uses max(1, int(...)), so 0 and -1 give one attempt and fail open after one 402; the gate maps unset, non-integer, 0 and negative values to 3. The guide and the M8 header claim the two behave the same. Scope: claude_toolkit scripts/jev_mcp.py, tests test_jev_failover.sh M8 and G9. Reproduction: reported by the r3 review with a hermetic probe (fixtures 402, 402, 200): gate 0 -> 3 attempts, MCP 0 -> 1 attempt. Acceptance: the MCP maps values below 1 to the default 3; M8 and G9 add 0 and -1; mutant X05 killed. Source: session-74ce2b36 scratchpad (outside the repository)/rev_jevtk_r3.4iGB/review_jev_toolkit_r3.md sha256 74a00d771f2fa5cf150e25a341e1bf9956575e409def7b04370ab6669a46950c; vehicle bundle claude_toolkit_jev_failover_r3.bundle (head 5c6092f4, not landed). r3 review F1.

## CON-330 — Jev toolkit tests: the default-value tests are one-sided, a larger default passes (mutants X03, X07, X09 survive)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: G9/M8 offer only 3 candidates, P6b never checks a re-probe after the interval, G10 never checks the budget stops; so raising the attempts, probe interval or budget defaults passes. Scope: claude_toolkit Jev failover tests (G9, G10, P6b and MCP twins M8, M9). Reproduction: not applicable (test coverage). Acceptance: tests with a fourth healthy candidate that must not be called, a stored probe older than 3600 s that must be re-probed, and a budget that must stop the fourth attempt; X03, X07, X09 killed. Source: session-74ce2b36 scratchpad (outside the repository)/rev_jevtk_r3.4iGB/review_jev_toolkit_r3.md sha256 74a00d771f2fa5cf150e25a341e1bf9956575e409def7b04370ab6669a46950c; vehicle bundle claude_toolkit_jev_failover_r3.bundle (head 5c6092f4, not landed). r3 review F2.

## CON-331 — Jev toolkit CHANGELOG over-claims the round-3 test coverage (request timeouts have no non-integer case)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the CHANGELOG says every default is checked at its default and with a non-integer value; JEV_MCP_TIMEOUT=abc makes every jev_ask fail with a float conversion error and JEV_GATE_TIMEOUT=abc is read as 0 by awk, and neither has a test. Scope: claude_toolkit CHANGELOG.md and the timeout validation of jev_mcp.py and jev-gate.sh. Reproduction: measured by the r3 review with probe_maxatt.sh. Acceptance: the sentence narrowed to what is tested; optionally both timeouts validated and abc cases added. Source: session-74ce2b36 scratchpad (outside the repository)/rev_jevtk_r3.4iGB/review_jev_toolkit_r3.md sha256 74a00d771f2fa5cf150e25a341e1bf9956575e409def7b04370ab6669a46950c; vehicle bundle claude_toolkit_jev_failover_r3.bundle (head 5c6092f4, not landed). r3 review F3.

## CON-332 — Jev toolkit: the CMA_JEV_LIVE=1 default cites an operator decision of 2026-11-12 that cannot be resolved

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the CHANGELOG says CMA_JEV_LIVE defaults to 1 by operator decision of 2026-11-12, but no request-history id or decision record is cited and the readable decision notes of that date do not mention it. Scope: claude_toolkit CHANGELOG.md and the CMA_JEV_LIVE default. Reproduction: not applicable (decision record). Acceptance: the CHANGELOG cites the recorded decision (request-history id); if none exists, the default is put to the operator as a decision owed (section 11.4.66) before landing. Source: session-74ce2b36 scratchpad (outside the repository)/rev_jevtk_r3.4iGB/review_jev_toolkit_r3.md sha256 74a00d771f2fa5cf150e25a341e1bf9956575e409def7b04370ab6669a46950c; vehicle bundle claude_toolkit_jev_failover_r3.bundle (head 5c6092f4, not landed); claude_toolkit_jev_failover_r2.bundle sha256 5f9dd042f610980cf560b104fc6910ba168d9036abc1be8ce13b746ecea85b3b. r3 review F4; also approved list FU-36 (r2 M2 residual: stale 'Changed (operator decision owed)' heading), merged here as the same finding.

## CON-333 — fix227 honest limit N-2: under a client 'SendEnv *' the base-list values of the release scripts reach the network child undeclared

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: round 11 lists N-2 as an honest limit in threat_model.md section 5: with a client ssh_config 'SendEnv *', the values of the base keep-list (locale and similar) are sent to the remote; they are not declared per call. Scope: scripts/release/redact_cut.sh rc_env_clean and docs/qa/con227_234_2026_11_11/round11/threat_model.md. Reproduction: UNKNOWN: not re-run in this filing; the round-11 sshd probe covers 18 configurations. Acceptance: either the base list is reduced for network children so nothing undeclared is sent under SendEnv *, or the limit stays documented with a test that shows exactly which names are sent. Source: docs/qa/con227_234_2026_11_11/round11/README.md and threat_model.md; approved list FU-45. Split of approved FU-45: N-1 (locale codeset), N-3 (tag suite git identity) and N-4 (evidence-class wording) were closed in fix227 round 11; FU-46 (LANGUAGE 'user:pw@host', r9 F8) was closed in round 10 (redact_cut.sh _rc_env_locale_ok). Parent CON-234.

## CON-334 — Git identity guard F4: git autostash and rebase --root write commits with the config identity

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: the identity guard does not cover commits written by git's autostash and by rebase --root; they take the configured identity without the guard's check. Scope: scripts/hooks/guard-git-identity.sh (idguard vehicle, not on main). Reproduction: UNREPRODUCED in this filing; reported by the r5 review. Whether rounds 6 to 9 covered it is UNCONFIRMED; the conflict path could raise the severity. Acceptance: the guard checks or refuses these commit-writing paths, with tests; recorded at the current idguard head. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-51; class recurrence of FU-48..50 (commit-writing subcommands).

## CON-335 — Git identity guard F5: a carried placeholder author passes the PreToolUse mode (git am); only the git hooks catch it

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: in PreToolUse mode the guard accepts git am of a patch whose author is a placeholder; only the git hook layer refuses it. Scope: guard-git-identity.sh and its guide (idguard vehicle). Reproduction: not applicable (documentation of a layer boundary). Acceptance: the guide states which layer catches a carried placeholder author, or the PreToolUse mode checks it too. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-52.

## CON-336 — Git identity guard F6: raw object writers (hash-object -t commit, mktag) are not in guide section 8, and the tag tagger is unchecked

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the guide's list of commit-writing commands omits raw object writers, and the tagger of a tag object is not checked. Scope: guard-git-identity.sh guide section 8 (idguard vehicle). Reproduction: not applicable. Acceptance: the guide lists raw writers and states how they are handled; the tagger is checked or the gap documented. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-53.

## CON-337 — Git identity guard F7: the guide's 'pull' class row disagrees with the code (--squash, --no-commit, pull.rebase)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the guide classifies git pull one way, the code another for --squash, --no-commit and pull.rebase. Scope: guard-git-identity.sh and its guide (idguard vehicle). Reproduction: not applicable. Acceptance: code and guide agree, with tests for each pull variant. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-54.

## CON-338 — Git identity guard F8: the class-table ground-truth script cited at guide line 113 is not in the repository

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the guide cites a ground-truth script for its command-class table that is not shipped. Scope: idguard guide line 113 (idguard vehicle). Reproduction: not applicable. Acceptance: the script is shipped, or its path and sha256 cited (section 11.4.215). Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-55.

## CON-339 — Git identity guard F9/F10: conservative-refusal wording; option table version GIT_OPT_VERSION is never compared with the running git

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the refusal wording overstates certainty, and the option table records a git version that is never compared with the git that runs. Scope: guard-git-identity.sh (idguard vehicle). Reproduction: not applicable. Acceptance: wording corrected; the guard warns or refuses when the running git differs from GIT_OPT_VERSION. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-56 (nit).

## CON-340 — Git identity guard F11-F13 test gaps: rebase --continue (RV5), am --continue/--skip, tag -s/--sign (RV8), fallback word list (RV16)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: reviewer mutants RV5, RV8 and RV16 survive because these commands and the fallback word list have no tests. Scope: idguard test suite (idguard vehicle). Reproduction: not applicable. Acceptance: tests for each command; RV5, RV8, RV16 adopted into the mutant manifest and killed. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-57.

## CON-341 — Git identity guard: the identity source is the hook environment, not the Bash tool shell

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the guard reads the identity from the hook process environment, which may differ from the shell in which the Bash tool runs git; whether the harness hook env differs is UNCONFIRMED. Scope: guard-git-identity.sh (idguard vehicle). Reproduction: UNKNOWN. Acceptance: a measured comparison of the hook env and the tool shell env, and the guard or its guide adjusted to the result. Source: review_idguard_r4.md F5; review_idguard_r5.md section 5c; idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-58.

## CON-342 — Git identity guard survey: the 100-command sample rerun of r5 (64/100) is not reproduced; only 63 refusals were kept

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the r5 false-positive survey reported 64 of 100 refusals, but the kept sample file holds 63, so the figure cannot be reproduced from evidence. Scope: idguard survey evidence (rv4.ao9D/sample_refusals.txt). Reproduction: not applicable (evidence). Acceptance: the survey re-run on the current idguard head with the full sample and refusal list kept and hashed. Source: idguard_r5.bundle sha256 83a840837637da30d05c6f924df8a65310aae18374104af49dce2d239394167d (head e7bf4d41); idguard is parked at round 9 (bundle fin9.03XH/ev/idguard_r9.bundle, head b9544a8f), scripts/hooks/guard-git-identity.sh is NOT on main. Approved list FU-59 (nit).

## CON-343 — Git identity guard: a git command assembled from split variables (a=g; b=it; nice $a$b $c$d) is not recognised

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: the guard looks for git at command position in the literal text; a command word assembled from several literal variable assignments is not seen. Scope: guard-git-identity.sh (idguard vehicle, parked at round 9, not on main). Reproduction: UNREPRODUCED in this filing; shown by the r7 review (F1) and the r8 fixer notes. Acceptance: literal assignments are substituted before the relevance check, or step D generalised to expansions in execution position, measured against the false-positive survey; tests with the split forms. Source: /mnt/DATA1TB/claude-work/scratch/fin9.03XH/ev/round9_in_repo/README.md sha256 08e40b28063de440d188df941d23254b39541e8f4811adc61c8e64b42bf18067 (idguard round 9, parked, not on main). idguard r9 follow-up.

## CON-344 — Git identity guard: bash 3.2 decodes \c?, \c\\ and a trailing \c differently from the bash-5 value the guard uses

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: for ANSI-C quoting the guard uses bash-5 values; bash 3.2 gives 0x1f instead of 0x7f for \c? and differs for \c\\ and a trailing \c. That this cannot change a verdict is UNCONFIRMED. Scope: guard-git-identity.sh ANSI-C decoder (idguard vehicle). Reproduction: not applicable (analysis). Acceptance: an argument, checked by test, that no verdict changes, or the decoder made version-aware. Source: /mnt/DATA1TB/claude-work/scratch/fin9.03XH/ev/round9_in_repo/README.md sha256 08e40b28063de440d188df941d23254b39541e8f4811adc61c8e64b42bf18067 (idguard round 9, parked, not on main). idguard r9 README section 6.

## CON-345 — Lander round-2 nits: re-verify which of R2-F3, R2-F7 and R2-F10 are still open in scripts/release/land_vehicle.sh

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the lander round-2 review listed R2-F3 (publish trailer range from an unauthenticated state file), R2-F7 (two odd trailer shapes refused although fixable) and R2-F10 (verify needs no prepare state). Rounds 3 to 7 changed the script; whether these three are closed is UNCONFIRMED. R2-F4 (flock), R2-F5 (--clone-name), R2-F6 (hooksPath), R2-F8 (--help), R2-F9 (placeholder documented at line 294) and R2-F11 (test under tests/release) show closure signs in the current script, also UNCONFIRMED by behaviour. Scope: scripts/release/land_vehicle.sh on main 584c287e sha256 73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8, tests/release/test_land_vehicle.sh. Reproduction: UNKNOWN: not re-run in this filing. Acceptance: each of R2-F3..R2-F11 marked closed (with the test or scenario that shows it) or fixed test-first. Source: session-74ce2b36 scratchpad (outside the repository)/review_lander_r2.md sha256 97ff37e6671ff1e0affa03efe3463b3963820a4734d3a8b191d752d11adbb2b0. Split of approved FU-71 (part 1). Parent CON-299.

## CON-346 — Lander R2-F12: confirm the lander test's recursive deletes all go through safe_rm_rf (section 11.4.287(B))

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: round 2 found the lander test deleting with guarded rm -rf instead of safe_rm_rf; the current test uses safe_rm_rf (3 calls) and no rm -rf, so this is probably closed, UNCONFIRMED. Scope: tests/release/test_land_vehicle.sh. Reproduction: not applicable. Acceptance: confirmed by reading the test and one sandboxed empty-argument run (section 11.4.287(D)), then closed. Source: session-74ce2b36 scratchpad (outside the repository)/review_lander_r2.md sha256 97ff37e6671ff1e0affa03efe3463b3963820a4734d3a8b191d752d11adbb2b0. Split of approved FU-71 (safety-adjacent part). Parent CON-299.

## CON-347 — Lander R7-C: LAND_VEHICLE_EXEC=$$ with exec bash -O nocasematch skips the clean re-run; an exported function 'env' blinds lv_dirty_env

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: (1) setting LAND_VEHICLE_EXEC to the caller pid and exec'ing bash -O nocasematch skips the clean re-run, so --item-id con-777 lands as 'Roadmap-Item: con-777'; (2) an exported function named env hides the environment from lv_dirty_env. Scope: scripts/release/land_vehicle.sh on main 584c287e sha256 73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8. Reproduction: UNREPRODUCED in this filing; shown by the r7 review scenarios. Acceptance: the dirty-shell check reads the real shell state ($-, shopt -p, declare -F, compgen -e) and refuses both cases, with tests. Source: /mnt/DATA1TB/claude-work/scratch/rv_lander_r7.bArH/review_lander_r7.md sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405. Class C, same class as R5-C. Parent CON-299.

## CON-348 — Lander R7-M: add probe Q02 (case-insensitive newness check)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the newness census has no probe for a case-insensitive match. Scope: tests/release/test_land_vehicle.sh newness probes. Reproduction: not applicable. Acceptance: probe Q02 added and run, with its paired mutant. Source: /mnt/DATA1TB/claude-work/scratch/rv_lander_r7.bArH/review_lander_r7.md sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405. Parent CON-299.

## CON-349 — Lander R7-S: the static T5 force-push grep misses "+$local_main:..."; add a behavioural push-argv guard (also round-2 R2-F13, mutant N01)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the static grep for a force refspec misses a + prefix carried in a variable ("+$local_main:...", round-2 mutant N01). The shipped script cannot force-push (its only push is a plain main:refs/heads/main), so this is a test gap. Scope: scripts/release/land_vehicle.sh on main 584c287e sha256 73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8, tests/release/test_land_vehicle.sh T5. Reproduction: shown by the r2 (N01) and r7 reviews. Acceptance: a git PATH shim records every push argv and the test fails on any refspec starting with + or a --force option; N01 and the r7 variant killed. Source: /mnt/DATA1TB/claude-work/scratch/rv_lander_r7.bArH/review_lander_r7.md sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405; session-74ce2b36 scratchpad (outside the repository)/review_lander_r2.md sha256 97ff37e6671ff1e0affa03efe3463b3963820a4734d3a8b191d752d11adbb2b0. Recurrence of round-2 R2-F13 (approved FU-71 split), linked here instead of a second item (section 11.4.214). Parent CON-299.

## CON-350 — Lander R7-N: newness greps at land_vehicle.sh lines 721, 723 and 813 fail open on grep exit status 2

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:21Z — by `Claude Opus 5.5 (filing subagent)`

What: three newness checks treat any non-zero grep status as 'no match', so a grep error (status 2) reads as new. Scope: scripts/release/land_vehicle.sh on main 584c287e sha256 73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8. Reproduction: UNREPRODUCED in this filing; shown by the r7 review. Acceptance: status 2 refuses (or is BLIND), with a test that forces a grep error. Source: /mnt/DATA1TB/claude-work/scratch/rv_lander_r7.bArH/review_lander_r7.md sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405. Parent CON-299.

## CON-351 — Lander: a gitlink to a commit that exists on no remote lands (scenario A8); state the limit in the header

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: scenario A8 of the r7 review: a vehicle that records a submodule gitlink to a commit no upstream has is landed without a refusal. Scope: scripts/release/land_vehicle.sh on main 584c287e sha256 73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8 header limits. Reproduction: shown by the r7 review scenario A8. Acceptance: the header limits state it (sections 11.4.233(G), 11.4.288(D)), or the lander checks gitlink reachability; tracked either way. Source: /mnt/DATA1TB/claude-work/scratch/rv_lander_r7.bArH/review_lander_r7.md sha256 38f9ace693a011984c6ecb0eb9e47a6ae858e0896fb79da893cb5bc275048405. Parent CON-299.

## CON-352 — Installer timeout census refuses equivalent trap spellings (SIGTTIN SIGTTOU, "", reversed order; mutant RM-6)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the census refuses trap forms that are equivalent to trap '' TTIN TTOU. Scope: tests/install/test_timeout_tty.sh. Reproduction: shown by the r2 review (RM-6). Acceptance: equivalent spellings accepted, with cases. Source: /mnt/DATA1TB/claude-work/scratch/rev_fu_r2.W98s/review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0 (verdict GO-with-follow-ups). Nit. Parent CON-314.

## CON-353 — Installer timeout census: the evidence tool census_new.py.txt differs from the census in the test; README sections 1 and 6 disagree (9 census-only sites)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the census tool kept as evidence is not the one the test runs, and the README gives two different site lists. Scope: docs/qa/installer_followups_r2_2026_11_14 and tests/install/test_timeout_tty.sh. Reproduction: not applicable. Acceptance: one census implementation, one site list. Source: /mnt/DATA1TB/claude-work/scratch/rev_fu_r2.W98s/review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0 (verdict GO-with-follow-ups). Nit. Parent CON-314.

## CON-354 — scripts/label-sync/render/statusline.sh:91 sets the TTIN/TTOU ignore for head -n 1 too

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the trap set for the timeout also applies to an unrelated head -n 1. Scope: scripts/label-sync/render/statusline.sh line 91. Reproduction: not applicable. Acceptance: the trap scoped to the timeout call only. Source: /mnt/DATA1TB/claude-work/scratch/rev_fu_r2.W98s/review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0 (verdict GO-with-follow-ups). Nit. Parent CON-314.

## CON-355 — Installer lock pid read: check-then-open race in hi_lock_pid and up_lock_pid ([ -f ] && [ ! -L ] then timeout 5 head -c 20)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the lock pid file is tested and then opened in two steps, so it can be replaced by a symlink in between. Scope: scripts/install_constitution.sh, scripts/update_constitution.sh. Reproduction: UNREPRODUCED. Acceptance: the file opened once with no-follow semantics and checked on the open descriptor, with a race test. Source: docs/qa/installer_followups_r2_2026_11_14/followup_drafts.md sha256 61feda7f872a2d94fb92aea362cc9e093fcbfe5311ee785767a5da38c6b2d072. Installer follow-up FU-1. Parent CON-314.

## CON-356 — 1972 python3 invocations without -I repo-wide: classify each site and add a census gate

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the census docs/qa/installer_followups_2026_11_14/census/py_isolation_census_repo.tsv lists 1972 python3 calls without -I (isolated mode). Scope: the whole repository. Reproduction: not applicable (census). Acceptance: each site classified (needs -I or justified), and a census gate like tests/install/test_python_isolation.sh covering the repository. Source: docs/qa/installer_followups_r2_2026_11_14/followup_drafts.md sha256 61feda7f872a2d94fb92aea362cc9e093fcbfe5311ee785767a5da38c6b2d072. Installer follow-up FU-2.

## CON-357 — cm_installer_no_push_no_force.sh reports SOURCE-FAILED on a relative --file

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the gate fails to source the file when --file is relative. Scope: scripts/gates/cm_installer_no_push_no_force.sh. Reproduction: UNREPRODUCED in this filing; recorded in the follow-up drafts. Acceptance: a relative path is resolved or refused with exit 64, with tests of both forms. Source: docs/qa/installer_followups_r2_2026_11_14/followup_drafts.md sha256 61feda7f872a2d94fb92aea362cc9e093fcbfe5311ee785767a5da38c6b2d072. Installer follow-up FU-3.

## CON-358 — Timeout sites the installer census cannot see: binaries, submodule installers, run-time names and extensionless scripts

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the census does not follow timeouts inside binaries (llmctl, claude_toolkit, labelctl), submodule installers or run-time names; it follows only .sh/.bash/.py and prunes tests at any depth, so extensionless scripts (scripts/hooks/post-merge, constitution-submodule-post-checkout, label-sync render/labelrun, multitrack-up/-down) are not scanned. Scope: tests/install/test_timeout_tty.sh census and its README boundary. Reproduction: not applicable. Acceptance: the boundary stated in the README and the reachable extensionless scripts added to the scan. Source: docs/qa/installer_followups_r2_2026_11_14/followup_drafts.md sha256 61feda7f872a2d94fb92aea362cc9e093fcbfe5311ee785767a5da38c6b2d072; /mnt/DATA1TB/claude-work/scratch/rev_fu_r2.W98s/review_installer_followups_r2.md sha256 e07f9c9ed374c0adf932ba73c8f925ebbbdda205ffff44b7c597974c44ae96f0 (verdict GO-with-follow-ups). Installer follow-up FU-4, with review R2-3 merged in. Parent CON-314.

## CON-359 — fix227 G2: C43b's label 'every caller-started git visible' is stronger than its needle (mutant RM9 survives C43b)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: C43b names a property its needle does not prove; a short-lived awk leak (RM9) survives C43b and is caught only by C48/C50. Scope: tests/release/ C43b (fix227). Reproduction: shown by the r14 review. Acceptance: the label narrowed or the needle extended so RM9 is killed by C43b. Source: /mnt/DATA1TB/claude-work/scratch/rev227_r14.sBmI/review_fix227_r14.md sha256 2cfd0529c8068754262e5edab6ff7302cdc8c824563d93f23806668727a4c826. Parent CON-234.

## CON-360 — fix227 G3: N5b proves final_exit exists, not that the real end path calls it (mutant RM6 survives); RTM_EXIT_SELFTEST should print a marker

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: N5b checks the function is defined, not that the end path reaches it. Scope: tests/release/ N5b (fix227). Reproduction: shown by the r14 review (RM6). Acceptance: a test that observes the real end path calling final_exit (marker printed under RTM_EXIT_SELFTEST); RM6 killed. Source: /mnt/DATA1TB/claude-work/scratch/rev227_r14.sBmI/review_fix227_r14.md sha256 2cfd0529c8068754262e5edab6ff7302cdc8c824563d93f23806668727a4c826. Parent CON-234.

## CON-361 — fix227 G4: c43 tools hard-code the scratch path; landing_gate14.sh has no standing test (LG2 survives); landing output outside the tree

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: c43/tools/c43_{new,only,red}.sh hard-code a scratch path, landing_gate14.sh has no standing test so LG2 survives, and the landing output is kept outside the repository. Scope: docs/qa/con227_234_2026_11_11/round14 tools. Reproduction: not applicable. Acceptance: paths parameterised, a standing test that kills LG2, landing output committed or cited with sha256. Source: /mnt/DATA1TB/claude-work/scratch/rev227_r14.sBmI/review_fix227_r14.md sha256 2cfd0529c8068754262e5edab6ff7302cdc8c824563d93f23806668727a4c826. Nit. Parent CON-234.

## CON-362 — fix227 K8 N2 accepts the loop-guard mutant B2 under a soft descriptor limit of 1024; count the passes

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/con227_234_2026_11_11/round13/b2_investigation/probe_nofile_toggle.txt` — red-command `tests/release/test_redact_cut.sh --only B2 under ulimit -Sn 1024` — env `this host, fix227 round-13 tree, soft RLIMIT_NOFILE 1024 and 524288 (round-13 review b2_investigation)` — signature `K8 N2 passes while B2 removes the loop guard` — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `the soft RLIMIT_NOFILE flips the K8 N2 verdict (two-way, 2/2 each): at 1024 the re-exec loop ends in EMFILE and rc_env_clean returns 4, which K8 N2 reads as the property; the exact mechanism line is UNCONFIRMED by the reviewer` — evidence `docs/qa/con227_234_2026_11_11/round13/b2_investigation/probe_nofile_toggle.txt` — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: without the rc_env_clean loop guard (mutant B2) the probe re-executes and leaks one descriptor per pass; at soft NOFILE 1024 exec fails after about 8 s, execfail keeps the shell and rc_env_clean returns 4, which is exactly what K8 N2 accepts. B2 is still killed by K6, so no defect ships. Scope: tests/release/test_redact_cut.sh case K8 N2; scripts/release/redact_cut.sh is correct. Reproduction: reproduced live by the round-13 review: --only B2, soft NOFILE 1024 2/2 'killed, but not by its property', 524288 2/2 'killed by its property'. Acceptance: K8 N2 requires exactly 2 entries into rc_env_clean besides rc=4 and a0=rc-clean-env; B2 killed by its property at both limits (N >= 3); the run records soft and hard NOFILE. Related nit: the netgate_pin.tsv line count is newline count plus one; fix in channel_census.py pin-regen. Source: docs/qa/con227_234_2026_11_11/round14/followup_k8_n2_nofile.md sha256 3e6cf51eae4455a5b005947120b29e349a910196f4dfae4758c14baa2e6b460f. Draft minted here as the draft asks; linked to CON-234, not a second id for the same weakness. Parent CON-234.

## CON-363 — Installer SIGPIPE scanner false negatives: until read, while read ... && cond, od -N, xxd -l, jq input, tee >(early-exit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the deny-by-default scanner does not flag these early-exit readers. Scope: scripts/gates/cm_installer_no_push_no_force.sh SIGPIPE scanner and tests/install/test_sigpipe.sh. Reproduction: shown by the r2 review. Acceptance: each form flagged, with cases. Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Parent CON-312.

## CON-364 — Installer test_round8: the stale index.lock branch (a5ee2ab4) is never exercised (M9 survives); the pgid==pid guard has no needle

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: one branch of the round-8 chaos test is dead in practice and one guard has no control needle. Scope: tests/install/test_round8.sh. Reproduction: shown by the r2 review (M9). Acceptance: the branch exercised and M9 killed; a needle for the pgid==pid guard. Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Parent CON-312.

## CON-365 — Installer hi_reset_shell_state does not reset globskipdots or varredir_close

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the shell-state reset misses two shopt options, so a caller setting them changes installer behaviour (latent). Scope: scripts/install_constitution.sh hi_reset_shell_state. Reproduction: UNREPRODUCED; latent per the r2 review. Acceptance: both options reset, with a test. Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Nit, latent source defect. Parent CON-312.

## CON-366 — Installer SIGPIPE round-2 evidence directory is not linked from README or CHANGELOG (section 11.4.212)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the round-2 evidence is unreachable from README. Scope: docs/qa/installer_sigpipe_2026_11_13 round 2. Reproduction: not applicable. Acceptance: linked from the CHANGELOG entry or README docs table. Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Parent CON-312.

## CON-367 — restore-created-at applier: a backslash in evidence_file gives a false BLIND (sha256sum escaping plus cut -c1-64)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: sha256sum prefixes the hash with a backslash for names with special characters, and cut -c1-64 takes the wrong 64 characters. Scope: the created_at restore applier of the workable-items engine. Reproduction: UNREPRODUCED in this filing; shown by the r4 review. Acceptance: hash read from stdin (sha256sum < file), with a test for a backslash in the name. Source: /mnt/DATA1TB/claude-work/scratch/rev_eng_r4.8oJ0/review_engine_r4.md sha256 c21872afec82e1bb1471f4f9314efc0990299bfa99c6c312e92cabadac243b6d. Parent CON-313.

## CON-368 — restore-created-at: whitespace normalisation differs between the applier and the engine (TrimSpace), giving exit 1 instead of BLIND

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the applier and the engine normalise whitespace differently, so a value the engine accepts makes the applier exit 1. Scope: created_at restore applier and engine. Reproduction: UNREPRODUCED in this filing; shown by the r4 review. Acceptance: one normalisation, with a test. Source: /mnt/DATA1TB/claude-work/scratch/rev_eng_r4.8oJ0/review_engine_r4.md sha256 c21872afec82e1bb1471f4f9314efc0990299bfa99c6c312e92cabadac243b6d. Parent CON-313.

## CON-369 — Engine created_at round 4 nits: MV12 text wrong, fileSHA256 unnamed, a refusal-table test missing from CENSUS_TESTS, tail -1, missing BLIND line on mkdir failure

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: F3: the MV12 text in round4/README.md is wrong; F4: fileSHA256 is not named and TestRestoreCreatedAtR3_RefusalTableNamesEveryCode is not in CENSUS_TESTS; F5: tail -1 is rejected by the host tail, and a mkdir failure prints no BLIND line. Scope: docs/qa/engine_created_at_2026_11_13/round4 and the applier. Reproduction: not applicable. Acceptance: each corrected. Source: /mnt/DATA1TB/claude-work/scratch/rev_eng_r4.8oJ0/review_engine_r4.md sha256 c21872afec82e1bb1471f4f9314efc0990299bfa99c6c312e92cabadac243b6d. Parent CON-313.

## CON-370 — restore-created-at: --root / gives the glob //* and every row reads BLIND

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: a root of / produces a doubled slash and no row resolves. Scope: created_at restore applier. Reproduction: UNREPRODUCED in this filing. Acceptance: --root / refused or tested. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-08. Parent CON-313.

## CON-371 — restore-created-at: the plan is read with IFS=$'\t', which collapses empty columns

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: tab is IFS whitespace in bash read, so consecutive tabs merge and an empty column shifts the others. Scope: created_at restore applier. Reproduction: UNREPRODUCED in this filing. Acceptance: the plan parsed so empty columns survive, with a test. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-09. Parent CON-313.

## CON-372 — fastcycle_sibling_search_test.go leaves a wi-fastcycle-siblingsearch-bin-* temp dir behind

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the Go test leaks a temporary directory per run. Scope: scripts/workable-items fastcycle_sibling_search_test.go. Reproduction: UNREPRODUCED in this filing. Acceptance: the directory removed by t.TempDir or cleanup, with a leak check. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-10.

## CON-373 — Destructive-path guard allows 'sh -s foo' (code from stdin, P07)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: guard-destructive-paths.py does not treat sh -s with arguments as code the guard cannot read. Scope: scripts/hooks/guard-destructive-paths.py (section 11.4.287). Reproduction: UNREPRODUCED in this filing; shown by the case-alt r4 review, allowed by every revision. Acceptance: the form treated as class U (or analysed), with a bypass-suite case. Source: session-74ce2b36 scratchpad (outside the repository)/review_casealt_r4.tXcqLv/REVIEW_r4.md sha256 5535bdb11d983c834c45b88dd32d6ee2a3bb21f537df613bc231d510c39441cb (case-alt vehicle parked for v73.5). case-alt r4 F6, pre-existing. Changing the guard needs operator consent (section 11.4.287).

## CON-374 — Destructive-path guard allows a shell fed from a function body (f() ( sh ); echo P | f 2>x, S08b)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: a pipe into a function whose body runs sh is not seen as code fed to a shell. Scope: guard-destructive-paths.py. Reproduction: UNREPRODUCED in this filing; shown by the case-alt r4 review. Acceptance: the form blocked or classed U, with a bypass-suite case. Source: session-74ce2b36 scratchpad (outside the repository)/review_casealt_r4.tXcqLv/REVIEW_r4.md sha256 5535bdb11d983c834c45b88dd32d6ee2a3bb21f537df613bc231d510c39441cb (case-alt vehicle parked for v73.5). case-alt r4 F6, pre-existing.

## CON-375 — Destructive-path guard: "${x:-'}" is parsed differently than by an outer dash (A01)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:22Z — by `Claude Opus 5.5 (filing subagent)`

What: the guard's quote handling inside ${...} differs from dash, so the guard and the shell can see different words. Scope: guard-destructive-paths.py tokenizer. Reproduction: UNREPRODUCED in this filing; shown by the case-alt r4 review. Acceptance: the dash reading modelled or the form refused as unparsable, with a case. Source: session-74ce2b36 scratchpad (outside the repository)/review_casealt_r4.tXcqLv/REVIEW_r4.md sha256 5535bdb11d983c834c45b88dd32d6ee2a3bb21f537df613bc231d510c39441cb (case-alt vehicle parked for v73.5). case-alt r4 F6, pre-existing.

## CON-376 — Retest C-5/C-7: traceability and temp-dir leaks of test_check_deps (leaked=6) and repo_verify (leaked=2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the retest found missing traceability (C-5, links CON-092/093) and temp-dir leaks: test_check_deps leaked 6 dirs and repo_verify 2. Scope: the named tests. Reproduction: UNKNOWN: not re-run in this filing. Acceptance: the leaks fixed with a leak check, and C-5/C-7 traceability recorded. Source: session-74ce2b36 scratchpad (outside the repository)/rtfix_lander_items.md sha256 4ce379c33afa6197ab93f434f016e056e06c45d5c2f3230d40550d0435085f3c; session-74ce2b36 scratchpad (outside the repository)/review_retest_items.md sha256 4df4946cf486891441873ac8d666d6851da774379e11be9bb30cfeffbcd0d10e. Approved list FU-81. The test_triple_harness_red leak (leaked=4) is the tracker-intake vehicle's item for lander C-6 and is not repeated here.

## CON-377 — CON-030 merge 66ad6efe follow-ups: M1 run the mutation table on the merged engine, M2 CHANGELOG entry and re-mint map, N1-N3

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: M1: the merge's evidence is the vehicle's table on an older engine, not the merged one; M2: no CHANGELOG entry records the CON-030 landing or the re-mint map; N1: the merge adds 7 files on neither parent; N2: 'CON-273 to CON-289 claimed by other vehicles' has no record; N3: commit message wording about which description was kept. Scope: merge commit 66ad6efe, CHANGELOG.md, full-suite runner mutation table. Reproduction: not applicable. Acceptance: M1 re-run on the merged engine and committed; M2 entry added; N1-N3 recorded or corrected. Source: session-74ce2b36 scratchpad (outside the repository)/review_con030_merge.md. Approved list FU-84.

## CON-378 — fix216 follow-ups F2 (CON-185 Verification line expects rc 0 where rc 77 is now by design) and F7 (CON-216 is Type Task although a source defect was fixed)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: F2: CON-185's Verification line still expects rc 0 both for FC_L29_CANDIDATES=zz_ZZ.UTF-8, which now ends rc 77; F7: CON-216's type should be Bug per sections 11.4.16 and 11.4.294(E). Scope: tracker items CON-185 and CON-216. Reproduction: not applicable. Acceptance: the Verification line corrected and CON-216 re-typed through the engine. Source: session-74ce2b36 scratchpad (outside the repository)/review_fix216.md. Approved list FU-86 remainder: F1, F3, F4, F5 and F6 are already CON-241, CON-242, CON-243, CON-244 and CON-245.

## CON-379 — v73.4 wrap-up: README.md and docs/CONTINUATION.md are stale (badge row, latest tag, remotes, pin table, release table, rev 3 of 2026-11-05)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the wrap-up audit lists stale README facts (latest tag says v72.2, remote count, script count 924 vs 1012, submodule pin table, release table rows) and a CONTINUATION at revision 3 that predates the 2026-11-11 decisions. Scope: README.md, docs/CONTINUATION.md. Reproduction: not applicable (documentation). Acceptance: both re-derived from measured facts at the v73.4 cut, README linking CONTINUATION (section 11.4.212). Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89 (umbrella, important).

Link (section 11.4.214, open original, link only; 2026-11-16): audit F6 found the README badge row stale (anchors 309/308, gates 195/194, mutation 199/198; 22 of 76 first-parent commits since v73.3). Symptom repaired by 1c248515; the landing seam (land_vehicle.sh publish step 6b runs compute_badges.sh --check) landed with merge 6c743898; the pull-request path is CON-443. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d).

Link (section 11.4.214, open original, link only; 2026-11-17, release prep): docs/CONTINUATION.md at main 60177435 is still revision 3 written 2026-11-05, and its 'In-flight vehicles' table lists the vehicles of that day (for example CON-030 round 3), none of the 2026-11-16 vehicles; the v73.4 wrap-up regenerates it (cut-day checklist step 15). Source: v73.4 release-prep draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft (outside the repository; SHA256SUMS sha256 c3096ff57234aff26af53012e320278e71d978077aab97cd5bbcba5f5c27f709, all entries verified OK by the lander 2026-11-17), read at main 60177435.

## CON-380 — v73.4 wrap-up: CHANGELOG first heading and release record for the cut (tag_and_release preflight requires the heading)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the first CHANGELOG heading must become the v73.4 heading at the cut, keeping older Unreleased entries; the release record and regenerated tracker docs follow. Scope: CHANGELOG.md, docs/release. Reproduction: not applicable. Acceptance: heading and release record match the cut facts. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89.

## CON-381 — v73.4: the section 11.4.40 full-suite retest is not registered in the tracker

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the release survey notes that the retest owed before promotion (sections 11.4.40, 11.4.185) has no item. Scope: release process for v73.4. Reproduction: not applicable. Acceptance: this item is the retest item; it closes when the retest runs on the cut fingerprint with evidence. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89.

Link (section 11.4.214, open original, link only; 2026-11-17, release prep): this is the v73.4 retest item the release entry cites as retest_item_id and the waiver's tracked item (GAPS.md and CUT_DAY_CHECKLIST.md step 3 said NOT TRACKED; no new item minted). The retest is the section 11.4.40 default tier (scripts/run_full_suite.sh) and then scripts/run_full_suite.sh --include-heavy --allow-topology-gaps on the cut fingerprint, followed by the section 11.4.185 confirmation; the verdict word comes from the runner's exit code (see the renderer vocabulary item filed the same day). Source: v73.4 release-prep draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft (outside the repository; SHA256SUMS sha256 c3096ff57234aff26af53012e320278e71d978077aab97cd5bbcba5f5c27f709, all entries verified OK by the lander 2026-11-17), read at main 60177435.

## CON-382 — v73.4 waiver: record the section 11.4.271 waiver (authoriser, expiry, source) and fix the draft wording 'relaxes (L7)'

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the waiver for the v73.4 cut is not recorded, and waiver_v734.draft.md still says it relaxes (L7), which a waiver cannot do. Scope: the v73.4 waiver record. Reproduction: not applicable. Acceptance: a recorded waiver with rostered authoriser, unelapsed expiry and tracked item; the wording corrected. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89; related to CON-229 and CON-230.

## CON-383 — v73.4: the release template amendment conflicts with fix227 and is neither landed nor reviewed

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: a release template amendment exists as a draft (release_amend_template/) and conflicts with fix227's release tooling. Scope: release template and tag_and_release.sh. Reproduction: not applicable. Acceptance: the amendment reconciled with fix227, reviewed, landed or dropped by decision. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89; related to CON-229 and CON-230.

## CON-384 — v73.4: the vasic-digital GitHub mirror release API returns 404 (record as a GAP and re-check at tag time)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the dry run reports the release API of the vasic-digital GitHub mirror as 404, so a release there would be a GAP (exit 5). Scope: release channels. Reproduction: not applicable. Acceptance: re-checked at tag time; the gap recorded honestly in the release notes or fixed. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89.

## CON-385 — v73.4: register the audit-3 follow-ups M1-M7 and N1-N4 as tracked items

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the release survey says the audit-3 findings M1-M7 and N1-N4 are not tracked; their text is not in the sources read for this filing (UNKNOWN). Scope: tracker. Reproduction: not applicable. Acceptance: each finding located in its audit report and filed (deduplicated) or closed with a reason. Source: session-74ce2b36 scratchpad (outside the repository)/wrapup_drift_audit.md sha256 2da39da4ee53c1fda37fc341d512e06aff0c5776d03f8dac8c2b2d12c1a82f14; session-74ce2b36 scratchpad (outside the repository)/release_survey.md sha256 2297f3fcd8723bc6cda30e9c37a5f69290132a12ec0c48aecb3856cd802a775e. Split of approved FU-89. The glab --prerelease child is held back (it belongs to the tracker-intake vehicle's GitLab pre-release items); the 'no scripts/redact_cut.sh on main' child is resolved, scripts/release/redact_cut.sh is on main.

## CON-386 — A tests/jev/fixtures/jev_server.py process outlives its test (observed alive for about 4 h under systemd --user)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T15:52:23Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T15:52:23Z — by `Claude Opus 5.5 (filing subagent)`

What: a jev_server.py fixture process was alive with parent systemd --user (re-parented) about 15280 s after start, from a scratch clone (gitenv_r4.R1kR); some Jev test does not stop its fixture server on every exit path. Which test leaks it is UNCONFIRMED; candidates are test_detection_matrix.sh, test_review_fixes_r2.sh, test_decision_layer_gaps.sh, test_bootstrap_e2e_stub_server.sh. Scope: tests/jev/ suites that start tests/jev/fixtures/jev_server.py. Reproduction: UNREPRODUCED: observed once on 2026-11-15 (ps: ppid 2551 systemd --user, etimes 15280, argv python3 .../tests/jev/fixtures/jev_server.py 0); not signalled, it is not this agent's process. Acceptance: the leaking test found and fixed so the server is stopped on success, failure and signal, with a leak check after each suite. Source: this filing's observation. Observation only; process left untouched.

## CON-387 — Restore CON-308's created_at when the tracker-intake vehicle lands (deliberately not applied with CON-243 in 464cd498)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the created_at restore plan of CON-313 had rows for CON-243 and CON-308; commit 464cd498 applied the CON-243 row only. The CON-308 row assumes the tracker-intake vehicle's ids and evidence commit 1a307322, which is not in this repository, so it was left for that landing and an operator decision. Scope: docs/workable_items.db row CON-308 (the intake vehicle's id map). Reproduction: not applicable. Acceptance: when tracker intake lands, the row re-derived against the landed ids and applied through the engine's restore-created-at with evidence, or dropped by operator decision. Source: commit 464cd498; CON-313. Parent CON-313.

## CON-388 — Follow-up filing wave 2 2026-11-15: register the follow-ups the audit found missing (installer SIGPIPE r2 F2/F6, engine created_at register drafts)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: register, through the engine, the approved follow-ups that the post-wave audit found missing from the tracker: installer SIGPIPE review r2 F2 and F6, and the engine created_at follow-up register drafts CON-PENDING-MDRT-DATALOSS, CON-PENDING-226-ROWS (register D-05), CON-PENDING-CON243-NONUNIFORM, CON-PENDING-EVIDENCE-PROVENANCE and D-01 to D-04, D-06, D-07. Scope: docs/workable_items.db and docs/Issues.md, docs/Issues_Summary.md regenerated from it. Not re-filed (already tracked): register D-08 to D-10 (CON-370 to CON-372), engine round-4 nits (CON-367 to CON-369), CON-308 restore row (CON-387), fix227 r14 G1 (recurrence link already in CON-234), round-13 review F4 pin sentence (already in CON-362). idguard round-9 items are held back (vehicle parked, unreviewed). Reproduction: not applicable (process item). Acceptance: every filed item carries what, scope, reproduction, acceptance and source; no duplicate minted; engine validate OK and diff in sync; run_full_suite.sh --verify-manifest MANIFEST-OK; pushed fast-forward to every reachable upstream. Source: the follow-up audit of 2026-11-15 (control-needled tracker census, reported to the conductor); session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997; docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754.

## CON-389 — Installer SIGPIPE scanner: a backtick command substitution inside an assignment makes the lexer report 'cannot lex' (rc 2, BLIND) for the whole file

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: one legal construct (a backtick command substitution in an assignment) makes the SIGPIPE scanner's lexer give up on the whole file with rc 2 (BLIND). This is fail-safe, but it blinds the scan of every other line of that file. Scope: scripts/gates/cm_installer_no_push_no_force.sh SIGPIPE scanner and tests/install/test_sigpipe.sh. Reproduction: shown by the installer SIGPIPE r2 review (finding F2, nit, test-instrumentation); not re-run in this filing. Acceptance: the lexer handles backtick substitution in an assignment (or reports BLIND only for the affected statement), with a needle case in test_sigpipe.sh. Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Review r2 F2. Parent CON-312; same scanner family as CON-363.

## CON-390 — Reviewer-process incident (SIGPIPE r2 F6): a sed range evaluated with empty SB/REPO/INSTALLER variables wrote to / (every write refused, no damage); harden extraction scripts and briefs

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: while extracting the scanner, the round-2 reviewer evaluated a sed range of test_sigpipe.sh with empty SB, REPO and INSTALLER variables; every write targeted / and failed with permission denied. The range held no rm, the repo was clean afterwards and nothing new was under /. This is the empty-variable shape of the section 11.4.287 incident, on writes instead of deletes; the destructive-path guard covers recursive deletes only. Scope: reviewer and subagent scratch tooling and the section 11.4.287(D) dispatch-brief text; scripts/hooks/guard-destructive-paths.py only if the operator decides to widen it. Reproduction: not applicable (incident record); the reviewer disclosed it and redid the extraction in Python. Acceptance: the dispatch-brief clause also tells agents to guard path variables used as write targets (${VAR:?} or a mktemp root check) and to extract code with a non-shell tool; whether the guard should also refuse writes aimed at / from an empty variable is recorded as an operator decision (changing the guard needs one). Source: session-74ce2b36 scratchpad (outside the repository)/rev_sigpipe_r2.7Vlo/review_installer_sigpipe_r2.md sha256 66c4b476a7efa8ff60046fd174c74392f8123528a0679ddf53a1756ec7d95997. Review r2 F6 (nit, process-doc, not a finding against the change). Related incident class: CON-305 (J7). Parent CON-312.

## CON-391 — workable-items engine: an unchanged sync db-to-md then md-to-db round trip rewrites description on 38 rows and sets severity to NULL on 3 rows (silent data loss)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T16:42:09Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T16:42:09Z — by `Claude Opus 5.5 (filing subagent)`

What: an unchanged sync db-to-md followed by sync md-to-db of the base tracker replaced description with different text on 38 rows (for example CON-030, CON-246) and set severity from Low to NULL on 3 rows (CON-266, CON-267, CON-268). Scope: workable-items engine sync db-to-md / sync md-to-db; pre-existing, measured by the engine created_at round-1 reviewer on the base bd0036bd binary and on the vehicle binary with the same result. Reproduction: UNREPRODUCED in this repository's evidence: the register records the reviewer's column census as reproduced-host-fixture, but that census file is not in the repository, so no state above UNREPRODUCED is set (section 11.4.294(C)). Reproduce first on a copy of docs/workable_items.db (section 11.4.292). Acceptance: a round trip of an unchanged database leaves every column of every row unchanged except last_modified, with a column census as the oracle and a regression test. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register CON-PENDING-MDRT-DATALOSS. Parent CON-313; related to register D-02 (filed as CON-396).

Link (section 11.4.214, open original, link only; 2026-11-16): the fc097 review re-measured the lossy md-to-db round trip on a scratch DB: description rewritten on 190 rows, parent_atm_id on 17, severity on 3, last_modified on 407, while 'workable-items diff' reports DB and Markdown in sync (the vehicle author measured 182 / 17 / 3 / 399 earlier the same day). Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-392 — Decide the 226 tracker rows whose created_at is later than their first item_history event (restore with restore-created-at, or record why not)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: at bd0036bd, 226 of 263 items hold a created_at later than their first item_history row; 222 hold 2026-11-11 15:38:57 and 4 hold 2026-11-11 15:34:52 (two batch times that fit earlier document rebuilds). The cause of each row was not traced. Scope: docs/workable_items.db items.created_at; the restore-created-at command and docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh. Reproduction: not applicable (decision item); counts are the register's measurement at bd0036bd, not re-measured here. Acceptance: one recorded operator decision; if restore, a plan file and an applier run with an audit row per item. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register CON-PENDING-226-ROWS = register D-05 (one item). Operator decision. Parent CON-313; CON-243 alone was restored in 464cd498; see CON-393.

## CON-393 — CON-243 is restored to its Opened time but its same-second siblings CON-242 and CON-244 keep 15:38:57 (created_at non-uniform)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the restore moved CON-243 to its Opened time 2026-11-11 15:34:35 (commit 464cd498); CON-242 and CON-244 were opened in the same second and keep 15:38:57, so the three disagree. Scope: items CON-242, CON-243, CON-244 created_at. Reproduction: not applicable (data consistency record). Acceptance: resolved together with CON-392: either the siblings are restored the same way or the non-uniformity is recorded as accepted. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register CON-PENDING-CON243-NONUNIFORM; listed separately so the non-uniformity stays visible. Parent CON-313.

## CON-394 — restore-created-at: evidence is checked only against the sha256 the caller names; read it from a committed git blob so a hand-built evidence file is refused

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: restore-created-at checks the sha256 the caller names, so a hand-built evidence file that records an earlier value inside the tracker's lifetime passes; round 2 added only the lower bound VALUE-BEFORE-TRACKER. Scope: workable-items restore-created-at and its applier. Reproduction: not applicable (design gap, by reading). Acceptance: --evidence-commit and --evidence-path read with git cat-file so the engine computes the sha itself, or a gate that resolves every audit row's evidence sha256 to a committed blob; a test with a hand-built evidence file that is not a committed blob is refused. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register CON-PENDING-EVIDENCE-PROVENANCE. Parent CON-313.

## CON-395 — workable-items: group set --item, repair-bodies, version-tags and sync md-to-db write no item_history rows

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`

What: these four write paths change items without an item_history row, so the section 11.4.34 audit trail misses their changes. Scope: workable-items engine commands group set --item, repair-bodies, version-tags, sync md-to-db. Reproduction: UNREPRODUCED in this filing; found while working on the engine created_at vehicle. Acceptance: each path writes a history row for every change (or the exception is documented and gated), with a test per path. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-01 (CON-PENDING-FOUND-DEFECTS). Parent CON-313.

## CON-396 — workable-items: close drops forensic_anchor, closure_criteria, composes_with, parent_atm_id, session_ref, version_tags; sync md-to-db drops destination, logic_group, parent_atm_id, session_ref, version_tags and resets last_modified

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`

What: close loses six columns of the closed item and sync md-to-db loses five columns and resets last_modified; silent field loss. Scope: workable-items engine close and sync md-to-db. Reproduction: UNREPRODUCED in this filing; found while working on the engine created_at vehicle. Acceptance: close and md-to-db keep every listed column (or carry it through the Markdown), proven by a column census before and after, with tests. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-02. Parent CON-313; related to CON-391.

Link (section 11.4.214, open original, link only; 2026-11-16): the fc097 review re-measured sync md-to-db on a scratch DB: description rewritten on 190 rows, parent_atm_id on 17, severity on 3, last_modified on 407; diff still reports in sync. See also CON-391. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-397 — Tracker-intake vehicle b48091ea holds duplicated Obsolete history rows (ids 592/593, 614/615, 616/617); dedupe before or at its landing

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the unlanded tracker-intake vehicle b48091ea has pairs of duplicated Obsolete item_history rows (ids 592/593, 614/615, 616/617). Scope: the tracker-intake vehicle's database (not on main); its landing. Reproduction: not re-checked in this filing (vehicle not on main). Acceptance: at landing, the duplicate pairs are explained or removed through the engine, and the cause (double write on Obsolete) is fixed or recorded. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-03. Related to CON-387 (same vehicle). Parent CON-313.

## CON-398 — workable-items: subtask add and subtask status are not dispatched by main()

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)
**Reproduction:** none — UNREPRODUCED — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`
**Investigation:** not-started — updated 2026-11-15T16:42:10Z — by `Claude Opus 5.5 (filing subagent)`

What: the subtask add and subtask status subcommands exist but main() does not dispatch them, so they cannot be run. Scope: workable-items engine main() dispatch. Reproduction: UNREPRODUCED in this filing; found by reading while working on the engine created_at vehicle. Acceptance: both subcommands are dispatched (or removed after the section 11.4.124 investigation), with a test that runs each. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-04. Parent CON-313.

## CON-399 — apply_restore_plan.sh applies plan rows one by one, not atomically across rows (documented in its header)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: the created_at restore applier applies each plan row in its own engine call; a failure part way leaves earlier rows applied. Scope: docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh. Reproduction: not applicable (documented limit). Acceptance: either the applier validates every row before the first write and applies them in one transaction, or the per-row limit stays documented with a recorded decision. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-06. Parent CON-313.

## CON-400 — restore-created-at --dry-run needs write access to the live database (opens it like a real run)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (filing subagent)

What: --dry-run opens the database the same way as a real run, so it needs write access and cannot run on a read-only copy. Scope: workable-items restore-created-at. Reproduction: not applicable (documented limit). Acceptance: --dry-run opens the database read-only (or the limit stays documented with a recorded decision), with a test on a read-only file. Source: docs/qa/engine_created_at_2026_11_13/round2/follow_up_register.md sha256 a0ef367d9884055cf81dc6e0d1a5c6184b46bc64f971ffa4b89ce8e35edb9754. Register D-07. Parent CON-313.

## CON-401 — Security hardening scripts: forge branch protection (force-push and deletion of main), GitHub Actions inventory and pinned disable, read-only history secret scan (landed from the security-scripts vehicle, review r4 GO-with-follow-ups)

**Status:** In progress
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

What: three security hardening scripts under scripts/security/ with their hermetic tests under tests/security/ and the guide docs/guides/security_hardening_scripts.md: forge_branch_protect.sh (blocks force-push and deletion of main on the forges that host the constitution; plan by default, apply guarded by FORGE_PROTECT_APPLY=yes, one target, a matching --apply-confirm and the built-in apply allowlist; each token bound to its host on port 443; gh pinned to --hostname github.com), github_actions_inventory_disable.sh (inventories GitHub Actions in the own orgs; disables Actions only for the 9 repositories pinned in scripts/security/actions_disable_allowlist.txt and built into the script) and history_secret_scan.sh (read-only full-history secret scan of one repository across all its remotes, with control needles planted inside the scanned mirror). Landed on main as one squash commit of the security-scripts vehicle head e940110e (bundle security_scripts_r3.bundle sha256 10210425e886491453bd8cc0059670648f6095e15cac8149f9eef8ba6c249faa, round 3 on rounds 1-2 70c3a26d and 3d6339b3, which were NO-GO intermediates and are not carried). The vehicle commits carry the placeholder trailer Roadmap-Item CON-PENDING-SECURITY; this item is its real id (section 11.4.214; vehicle text not rewritten). Scope: scripts/security/, tests/security/, docs/guides/security_hardening_scripts.md, docs/qa/security_scripts_2026_11_12/, the README docs link and the full-suite manifest rows. Reproduction: not applicable (new tooling, built test-first; RED and GREEN logs per round in docs/qa/security_scripts_2026_11_12/). Acceptance: independent review GO (done: review r4 GO-with-follow-ups, session-74ce2b36 scratchpad (outside the repository)/review_security_scripts_r4.md sha256 cc5bbe1a2e5012651ab71f22fafc0ba8b4f1b6a859716be34b94958d14338c4a; forge 168/168, actions 44/44, history 45/45, 5 of 17 reviewer mutants survive, all test-instrumentation); follow-ups R4-1 to R4-5 are CON-316 to CON-320 (filed earlier, not re-filed); VERIFIED only after a live run against the real forges under the separate operator authority (section 11.4.289; the tests are hermetic gate-logic tests against a loopback fixture and a fake gh and gitleaks, never a live proof). The guide's own header still says round 3 is not yet independently reviewed; that line is stale since review r4 and is part of the vehicle text, left as reviewed. Codeberg force-push blocking (CON-322), Gitea glob-rule ordering, the Dependabot effect (CON-323) and a real-gitleaks run stay UNCONFIRMED. Status PROVISIONAL (section 11.4.290); evidence class gate-logic and unit (section 11.4.289). No script was executed against a real forge or host by the landing.

## CON-402 — Ambient git variables (GIT_DIR, GIT_INDEX_FILE and the rest of the 14-name class) redirect a write into a foreign repository: whole class closed with a closed-world census over every tracked code file (landed from the gitenv vehicle rounds 1-4, review r4 GO-with-follow-ups)

**Status:** In progress
**Type:** Bug
**Severity:** High
**Created-By:** Claude Opus 5.5 (lander subagent)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/gitenv_class_2026_11_14/red2/arc_git_dir.result.txt` — red-command `bash docs/qa/gitenv_class_2026_11_14/tools/sentinel_run.sh.txt <repo> <out> arc_git_dir git_dir scripts/gates/cm_anchor_record_complete.sh (on 42fd1288)` — green-command `same command on the landed head; SENTINEL=UNCHANGED` — env `host, fresh sentinel repository, GIT_DIR=<sentinel>/.git` — signature `sentinel repository CHANGED under GIT_DIR while the gate exits 0` — updated 2026-11-15T20:22:33Z — by `Claude Opus 5.5 (lander subagent)`
**Investigation:** root-cause-found-with-evidence — root-cause `GIT_DIR beats git -C and cd; GIT_INDEX_FILE names the index every index-writing command uses; setting or clearing them toggles the sentinel change` — evidence `docs/qa/gitenv_class_2026_11_14/red2/arc_none.result.txt` — updated 2026-11-15T20:18:26Z — by `Claude Opus 5.5 (lander subagent)`

What: a script that runs a writing git command under a caller that set GIT_DIR or GIT_INDEX_FILE (a pre-commit hook, a wrapper) wrote into the caller repository (RED on 42fd1288: cm_agent_type_label.sh made a foreign commit under GIT_DIR; cm_anchor_record_complete.sh renamed a branch and added a commit, a false GREEN). Scope: every tracked code file whose text contains git; entry points scrub the 14-name class at file level, sourced libraries scrub in their git wrappers, GIT_CEILING_DIRECTORIES is kept as the caller limit; scripts/validation/git_env_class_census.py is a closed-world census over git ls-files with exemptions in config/git_env_class_exemptions.tsv; tests/test_git_env_class.sh and tests/test_full_suite_manifest_gate_git_env.sh prove it. Evidence: docs/qa/gitenv_class_2026_11_14/ (round 1), docs/qa/gitenv_class_r2_2026_11_14/, docs/qa/gitenv_class_r3_2026_11_15/, docs/qa/gitenv_class_r4_2026_11_15/. Acceptance: census PASS on main, the four packs SHA256SUMS verify, the class tests pass, review follow-ups F-R5-1 to F-R5-8 tracked as CON-403 to CON-410 (reviews kept in docs/qa/gitenv_class_r4_2026_11_15/landing/). Status PROVISIONAL (section 11.4.290); evidence class gate-logic and host-fixture (section 11.4.289), no live-target proof.

## CON-403 — git-env census: pinned-fixture rows are not checked against the file (a live gate or a new writer can be exempted by a row alone)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

What: the pinned-fixture reason (49 rows) is accepted without checking the file; reviewer mutants R503 and R514 survive. Scope: scripts/validation/git_env_class_census.py, config/git_env_class_exemptions.tsv. Reproduction: add a pinned-fixture row for a live gate that writes with git; the census stays PASS. Acceptance: a pinned-fixture row needs the path listed with a matching sha256 in a SHA256SUMS or config/full_suite_excluded.lock and not referenced by a manifest entry or non-docs code (or a closed-evidence-tool reason restricted to docs/qa/**); R503 and R514 killed. Class: test-instrumentation, important; close before the next release tag. Review F-R5-1 (F12). Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-404 — git-env census: placement of an own (LEGACY) scrub is not checked (reviewer mutant R505 survives)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: an own scrub (unset -v list form) is accepted wherever it sits; R505 survives. The 9 real instances are correct. Scope: scripts/validation/git_env_class_census.py. Acceptance: an own scrub after the first git call or inside a block is UNSCRUBBED; R505 killed. Class: test-instrumentation, minor. Review F-R5-2 (F13). Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-405 — git-env scrub lines moved 4 of 33 shellcheck directives: 3 disables became file-wide (56 findings hidden), 1 source= directive lost (SC1091)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: inserting the scrub line displaced shellcheck directives; three disable directives now apply file-wide and hide 56 findings, one source= directive no longer applies. The gitenv README claim that shellcheck results are unchanged is wrong for those 4 files. Scope: the 4 files named in review F9. Acceptance: each scrub sits above its directive (or the directive below the scrub); shellcheck results equal the pre-scrub results; README corrected. Class: test-instrumentation (lint scope, no behaviour change) + process-doc, minor. Review F-R5-3 (F9). Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-406 — Stale SHA256SUMS line docs/qa/engine_created_at_2026_11_13/round2 test_apply_restore_plan.sh after the git-env scrub

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: the git-env vehicle added a scrub line to docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh, so its pack SHA256SUMS line no longer verifies. The second stale line the review found (docs/qa/gitenv_class_2026_11_14/README.md) was refreshed at the CON-402 landing. No gate reads SHA256SUMS. Acceptance: decide whether the pack records the scrubbed file (update the line with a note) or the original (restore the original as a pinned copy); sha256sum -c passes. Class: process-doc, minor. Review F-R5-4 (F11). Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-407 — git-env census: no-git-execution rows are checked for writes only (a git read passes, R508); redact_cut.sh row wording imprecise

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: a no-git-execution row is only checked against the write detector, so a file that reads with git passes (R508). The redact_cut.sh row says it runs no git, but rc_net is the exec site of its callers' git (safe by its allow-list). Scope: scripts/validation/git_env_class_census.py, config/git_env_class_exemptions.tsv. Acceptance: no-git-execution also fails on git reads; R508 killed; the redact_cut row reworded. Class: test-instrumentation + process-doc, minor. Review F-R5-5. Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402. Also observed (linked, not a new item, section 11.4.214): multiforge landing review review_multiforge_r4_landing.md sha256 db00bd35ef624fc02abe98cbeb2ea118a85ecb79485cc2d0c32dd25e636bbee5 observation N1, reviewer mutant K13 (an exempted provider gains a git -C rev-parse read) survived the census.

## CON-408 — workable-items Go reads under an ambient GIT_DIR read the wrong repository (closure_seam.go fingerprint, db.go timer fingerprint, version_tags.go)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: Go code under scripts/workable-items runs git reads (git -C dir rev-parse HEAD and others) that inherit an ambient GIT_DIR, so closure_seam.go currentArtifactFingerprint, the db.go timer fingerprint and version_tags.go read another repository's state (section 11.4.201 subject drift). Pre-existing, not introduced by CON-402; the documented Go boundary (go-binary-owed). Scope: scripts/workable-items/cmd/workable-items/{closure_seam.go,db.go,version_tags.go} and the committed binary. Reproduction: UNREPRODUCED on this item; run the closure-seam fingerprint with GIT_DIR aimed at a sentinel repository and compare with the real HEAD. Acceptance: each exec.Command for git clears the 14-name class (env) and the binary is rebuilt; a test with an ambient GIT_DIR reads the right repository. Class: source-defect (pre-existing), minor. Review F-R5-6. Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-409 — Release-tooling mutation suite: about 206 of 383 mutants carry no kill verdict on the merged tree; full run owed before the next release tag

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

What: after the git-env scrub of the release scripts, the reviewer killed a 41-mutant sample (41/41) but about 206 mutants have no verdict on the merged tree. Scope: tests/release/test_release_tooling_mutations.sh on the CON-402 landed head. Acceptance: before the next release tag (section 11.4.40) run the full 383-mutant suite (about 8 h, or add sharding) on the landed head and record the verdict per mutant; every survivor filed. Class: test-instrumentation, important. Review F-R5-7 (F10). Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-410 — git-env class scope note: GIT_CONFIG_COUNT/KEY/VALUE and GIT_CONFIG_PARAMETERS stay outside the 14-name class; core.hooksPath injection not measured

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: the scrub list does not include GIT_CONFIG_* or GIT_CONFIG_PARAMETERS (documented). One probe (GIT_CONFIG_COUNT/KEY/VALUE core.worktree=<foreign>) did not redirect git -C A checkout -- f. core.hooksPath injection through these variables is not measured. Acceptance: measure core.hooksPath and other config-injected redirections; either extend the class with evidence or record why not. Class: process-doc, nit. Review F-R5-8. Source: docs/qa/gitenv_class_r4_2026_11_15/landing/review_gitenv_r4.md (original sha256 664796e26a87a1707ec83ee6af4c22d6274ade5a1e2b776f57a956a17b03b1f3, section 7). Parent CON-402.

## CON-411 — Full-suite manifest lacked rows for the 3 sonarqube registry-login tests on main bd0036bd (recurrence of the CON-086 class); gate CM-FULL-SUITE-MANIFEST-COMPLETE added at the pull seam

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

On main bd0036bd, bash scripts/run_full_suite.sh --verify-manifest ended RESULT: MANIFEST-MISMATCH (3 problems; nothing was run) because scripts/sonarqube/tests/test_registry_login.sh, test_registry_login_mutation_test.sh and test_registry_login_wiring.sh were committed (ff539dc8) without manifest rows. Same class as CON-086 (still open, linked per section 11.4.214; minted as a separate item because the files and the commit differ, the section 11.4.214(3) mint-with-link default). The vehicle adds scripts/gates/cm_full_suite_manifest_complete.sh (control-needled --verify-manifest of HEAD through a clean export, ambient git variables cleared), its paired mutation test, a git-environment sentinel test and post_update_hook.sh step 5b wiring. Placeholder id in the vehicle text: CON-PENDING-MANIFEST-SONARQUBE. Evidence: docs/qa/manifest_sonarqube_2026_11_13/. Independent review round 2: GO-with-follow-ups (N1 to N6, minor-class). Status PROVISIONAL (section 11.4.290). Review: review_manifest_r2.md sha256 86daee5ebb2bbcc08251f97c746da88bac2b886b4d5df2c504310eb73b950287 (session scratchpad, not in the tree). Landed inside the CON-402 squash (the gitenv vehicle descends from this vehicle head 42fd1288 and carries newer versions of its files, which also fix N1 to N6); no separate squash.

## CON-412 — Multi-forge release tool: one REST-over-curl entry point (scripts/forge/forge.sh) for GitHub, GitLab, Codeberg, git.m3w.org, GitFlic and GitVerse releases, with live read-only evidence (landed from the multiforge vehicle, rounds 1-4, review r4 GO-with-follow-ups)

**Status:** In progress
**Type:** Feature
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (landing-preparer subagent)

What: scripts/forge/forge.sh with lib/ (common, credentials, http) and providers/ (github, gitlab, gitea for m3w and Codeberg, gitflic, gitverse), live_probe.sh, the hosts map config/forge/hosts.tsv, hermetic tests under tests/forge/ (credentials, detect, gitea, gitflic, github_gitlab, gitverse, mutations), the guide docs/guides/multiforge_release_guide.md, manual docs/manuals/forge_tool_manual.md, FAQ docs/faq/forge_tool_faq.md, live read-only evidence docs/qa/multiforge_2026_11_12/ and the P4 patch proposal docs/release/multiforge_p4_patch_proposal.md. Subcommands detect, probe, repo-exists, release-get, tag-get, release-ensure; API keys only, tokens never printed (whole value for 8-11 characters, contiguous pieces of 12 or more otherwise). Affected scope: release publishing of the constitution to its forges. Reproduction: not applicable (new tool, Type Feature). Acceptance: the six forge suites and the mutation harness pass (87 mutants killed in round 4), git-env census PASS, MANIFEST-OK, and a live release-ensure run on each forge is recorded (owed; the vehicle's live evidence is read-only). Landing delta: the canonical git-env scrub line was added to forge.sh, live_probe.sh, test_forge_credentials.sh and test_forge_detect.sh, and 11 no-git-execution rows to config/git_env_class_exemptions.tsv, because the CON-402 closed-world census on main covers every shell script; this delta was not in the reviewed head 380ad64a. Status PROVISIONAL (section 11.4.290); evidence class of the suites is gate logic and host fixtures (section 11.4.289). Landed on main as e5879550 (landing delta reviewed: review_multiforge_r4_landing.md sha256 db00bd35ef624fc02abe98cbeb2ea118a85ecb79485cc2d0c32dd25e636bbee5, GO-with-follow-ups). Follow-ups: CON-413 (U3 substring test), CON-414 (fingerprinted live evidence), CON-415 (doc nits); census limit N1 linked to CON-407. The live release-ensure run on each forge stays in this item's acceptance.

## CON-413 — forge tests: U3 (fg_scrub multi-line) compares substrings only; reviewer mutants V2 and V3 survive

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: test U3 of the forge credential suite checks fg_scrub multi-line output by substring only, so reviewer mutant V2 (lines joined by a space) and V3 (blank lines dropped) survive. Scope: tests/forge/test_forge_credentials.sh, tests/forge/test_forge_mutations.sh. Acceptance: U3 compares the exact expected text, the input carries a blank line and a trailing newline, V2 and V3 are adopted into the mutation harness and killed. Class: test-instrumentation, minor. Source: review_multiforge_r4.md sha256 ca65b3400f8fd970cde813a949d22ea45c33ac8ccf23ed05ffc232e0bc77ad2a, finding 1. Parent CON-412.

## CON-414 — forge live evidence docs/qa/multiforge_2026_11_12 predates the tool fingerprint: re-run live_probe.sh on the landed main

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: the committed read-only live evidence under docs/qa/multiforge_2026_11_12/ was captured before the round-3 tool_fingerprint.txt existed, so which code produced it is UNCONFIRMED. Scope: scripts/forge/live_probe.sh, docs/qa/multiforge_2026_11_12/. Acceptance: live_probe.sh re-run on main e5879550 or later, the new evidence carries tool_fingerprint.txt matching the landed scripts/forge tree, committed with SHA256SUMS; credentials referenced by variable name only. Class: evidence, minor. Source: review r3 R2-m4 residue, carried in review_multiforge_r4.md sha256 ca65b3400f8fd970cde813a949d22ea45c33ac8ccf23ed05ffc232e0bc77ad2a. Parent CON-412. The live release-ensure (write path) run is NOT this item: it is part of CON-412's own acceptance.

## CON-415 — multiforge landing doc nits: REPLAY GIT_DIR wording, review citation, replay.sh dedupe by title only, guide/manual/FAQ Last modified order, lib.sh lock note

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: five process-doc nits. (1) landing review F1: the handback REPLAY.md claimed forge.sh newly ignores an ambient GIT_DIR; measured false as a behaviour change (fg_env_clean already re-execs with exec -c); the scrub line is a second layer. Corrected in the landed commit message e5879550 and in the handback REPLAY.md; reuse the corrected wording anywhere it is copied. (2) landing review F2: the commit message said the landing delta needed its own review; done in e5879550, which cites the landing review. (3) landing review F3: replay.sh dedupes only on the title prefix Multi-forge release tool; a later replay helper should search titles and descriptions. (4) review r4 finding 2: guide, manual and FAQ revision 4 move Last modified backwards (rev 3 23:30:00Z, rev 4 17:49:00Z); fix so it increases per revision. (5) review r3 m7: the manifest and lock row note for tests/forge/lib.sh says sourced by test_forge_credentials.sh, all six suites source it; reword or change the schema. Scope: docs/guides/multiforge_release_guide.md, docs/manuals/forge_tool_manual.md, docs/faq/forge_tool_faq.md, config/full_suite_manifest.tsv, config/full_suite_excluded.lock, future replay helpers. Acceptance: (3) to (5) fixed or decided; (1) and (2) recorded done. Class: process-doc, nit. Sources: review_multiforge_r4_landing.md sha256 db00bd35ef624fc02abe98cbeb2ea118a85ecb79485cc2d0c32dd25e636bbee5 findings F1-F3; review_multiforge_r4.md sha256 ca65b3400f8fd970cde813a949d22ea45c33ac8ccf23ed05ffc232e0bc77ad2a finding 2; review r3 m7. Parent CON-412.

## CON-416 — GitLab release of a --prerelease cut looked final: mark it by title and description, --no-update, optional released_at, read back through nt (glpre)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

What: on a --prerelease run, scripts/release/tag_and_release.sh published the GitLab release with no pre-release marking (GitLab's Releases API and glab 1.129.0 have no pre-release flag), so it looked like a final release. Fix (vehicle glpre, re-applied on bcac0882, landed on main): the GitLab leg prefixes the name with 'PROVISIONAL pre-release: ' once, starts the description with a fixed PROVISIONAL line, always passes --no-update, takes an optional --gitlab-released-at ISO8601 (future, --prerelease and a gitlab spec only) as --released-at, and reads the release back with glab api --hostname through nt: unmarked or unparsable is a FAIL, a failed read or a different upcoming state is a GAP, server text is never printed raw. Census rows and the netgate pin updated (pin regenerated on the merged tree at landing: rows=1590 sites=135 names=176, netgate findings=0). Tests GL1-GL17 (stub glab, gate-logic class, section 11.4.289(C)); mutants GP1-GP21 killed. Review: independent round 1 GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository). Evidence: docs/qa/release_tooling_glpre_reltpl_2026_11_15/. Limits: no live GitLab run; GitLab released_at/upcoming_release behaviour UNCONFIRMED; the create call is not pinned to a host (divergence gives a GAP). Status: In progress, PROVISIONAL (section 11.4.290), not VERIFIED-DONE: acceptance needs one live --prerelease cut read back MARKED on GitLab. Related: CON-385 (held-back glab --prerelease child), CON-226. Landed on main as 5296e74d. Follow-ups filed: CON-418 (notes-write failure path), CON-419 (read-back parsing guards), CON-422 (nits F6/F7).

## CON-417 — v73.4 entry template asserted the retest never ran and let (L7) ride open: retest_statement key verdict-checked by the renderer, (L7) wording corrected (reltpl)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** Claude Opus 5.5 (lander subagent)

What: docs/release/helixconstitution-v73.4_entry.template.md asserted a fixed sentence that the section 11.4.40 retest 'has never run on this candidate', whatever the facts were, and said that (L1), (L6) or (L7) entries 'ride open' and that the operator decision 'relaxes (L7)', which section 11.4.230(E.3) and (F.3)(2) forbid (an open (L7) blocks a release of every class and cannot be waived). Fix (vehicle reltpl, re-applied on bcac0882, landed on main): new manual key retest_statement replaces the fixed sentence; scripts/release/render_release_entry.py refuses (exit 3) a value that does not start with a verdict token PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN (PASS-FULLY/FAILED refused); the template says an open (L7) blocks every class, the release does not conform to (F.3)(2) for those entries, and the decision is an override of the rule, not a conforming waiver; docs/release/README.md revision 4 lists the key. Tests: test_render_release_entry.sh 37/0 (RED 25/12 before); mutants RV1-RV4 killed. Review: independent round 1 GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository). Evidence: docs/qa/release_tooling_glpre_reltpl_2026_11_15/ (includes a corrected waiver draft COPY only; no waiver is recorded, that stays CON-382). Limits: the renderer checks the verdict token only, not a machine section 11.4.40 verdict (follow-up filed). Status: In progress, PROVISIONAL (section 11.4.290). Related: CON-229, CON-382, CON-381, CON-226. Landed on main as 3f37d8d6. Follow-ups filed: CON-420 (template wording guards), CON-421 (bind PASS-FULL to a machine section 11.4.40 verdict), CON-422 (nit F9).

## CON-418 — CON-416 follow-up: the GitLab notes-write failure path (GL_NOTES_OK=0, FAIL 'not attempted') has no test; reviewer mutant X1b survives

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: review F2 (test-instrumentation, minor). Mutating the notes-write guard of scripts/release/tag_and_release.sh to never fire (X1b, '-eq 99') leaves tests/release/test_tag_and_release.sh at 388/0; X1 ('if false') is killed only by the C53 netgate name list, not by behaviour. Without the guard a partial marked notes file (mark written, notes truncated) would be published and read back MARKED. Acceptance: a case that makes the notes write fail and asserts the FAIL 'not attempted' result and that no glab create runs; X1b and X1 killed by that behaviour case. Reproduction: not applicable (instrumentation gap). Source: independent review round 1 of the glpre+reltpl vehicle, verdict GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository; reviewer mutant logs under /mnt/DATA1TB/claude-work/scratch/rv_glpre.ONFv/mw/, outside the repository). Landed as 5296e74d (CON-416) and 3f37d8d6 (CON-417).

## CON-419 — CON-416 follow-up: read-back parsing guards untested (first-line trim, multi-value JSON, trailing junk after an ISO released_at); reviewer mutants X6, X7, X10 survive

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: review F3 (test-instrumentation, minor). The unmutated read-back in scripts/release/tag_and_release.sh handles each case, but no fixture proves it: removing the first description line trim (X6, no CRLF or padded-mark fixture), removing the multi-line jq result guard (X7, no multi-value JSON fixture) and letting the released_at ISO check accept trailing junk (X10) all pass the suite. Acceptance: stub-glab fixtures for a CRLF/padded first line, a multi-value JSON answer and a released_at with trailing junk, each asserting the expected FAIL/GAP; X6, X7, X10 killed. Reproduction: not applicable. Source: independent review round 1 of the glpre+reltpl vehicle, verdict GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository; reviewer mutant logs under /mnt/DATA1TB/claude-work/scratch/rv_glpre.ONFv/mw/, outside the repository). Landed as 5296e74d (CON-416) and 3f37d8d6 (CON-417).

## CON-420 — CON-417 follow-up: template wording guards are fixed-phrase greps; '(L7) is waived' (X12) and a false 'manual-QA confirmation is recorded' (X13) pass the suite

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: review F4 (test-instrumentation, minor). tests/release/test_render_release_entry.sh guards the v73.4 entry template wording with three fixed phrases only. Acceptance: a negative guard on any 'waive' wording applied to (L7) and a positive guard on the manual-QA sentence ('No section 11.4.185 manual-QA confirmation is recorded.' unless a confirmation is cited); reviewer mutants X12 and X13 killed. Reproduction: not applicable. Source: independent review round 1 of the glpre+reltpl vehicle, verdict GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository; reviewer mutant logs under /mnt/DATA1TB/claude-work/scratch/rv_glpre.ONFv/mw/, outside the repository). Landed as 5296e74d (CON-416) and 3f37d8d6 (CON-417).

## CON-421 — CON-417 follow-up: retest_statement is checked by verdict token only; a hand-written PASS-FULL with no log makes the entry read (L6) closed

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: review F5 (source-defect, minor; stated in docs/release/README.md and the renderer docstring). scripts/release/render_release_entry.py accepts any retest_statement starting with PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN; nothing binds PASS-FULL to a machine-written section 11.4.40 full-suite verdict (section 11.4.262), so an unbacked claim reads as a closed (L6) entry. Acceptance: PASS-FULL (and PARTIAL-TOPOLOGY) accepted only with a cited machine verdict file whose fingerprint matches the candidate, else exit 3; a RED case first. Related: CON-381 (the section 11.4.40 retest is not registered in the tracker). Reproduction: UNREPRODUCED live; the reviewer described the input shape only. Source: independent review round 1 of the glpre+reltpl vehicle, verdict GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository; reviewer mutant logs under /mnt/DATA1TB/claude-work/scratch/rv_glpre.ONFv/mw/, outside the repository). Landed as 5296e74d (CON-416) and 3f37d8d6 (CON-417).

## CON-422 — CON-416/CON-417 follow-up nits: GL_HOST post-strip check is dead defence (X3), create vs read-back host resolution, leading-whitespace retest_statement untested (X11)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** Claude Opus 5.5 (lander subagent)

What: review nits grouped. F6 (process-doc, nit): the GL_HOST post-strip regex in tag_and_release.sh duplicates the GITLAB_HOST lockdown (X3 is equivalent); keep it with a comment saying so, or remove it after the section 11.4.124 check. F7 (source-defect, nit): the GitLab create resolves its host itself (glab config host, git remote) while the read-back pins GITLAB_HOST or gitlab.com; divergence yields a GAP (fail-safe, stated in docs/release/README.md); glab host resolution with -R GROUP/REPO is UNCONFIRMED; acceptance: pin the create host too, or record the measured glab behaviour. F9 (test-instrumentation, nit): a leading-whitespace retest_statement accepted via .strip() is untested (X11 survives, stricter direction); acceptance: a case for it. Reproduction: not applicable. Source: independent review round 1 of the glpre+reltpl vehicle, verdict GO-with-follow-ups (review_r1_independent.md sha256 5a9398ab709873084ebff8fb2f9961eb06a4d5643fdb9b21a7d55283bca002a5, session-74ce2b36 scratchpad, outside the repository; reviewer mutant logs under /mnt/DATA1TB/claude-work/scratch/rv_glpre.ONFv/mw/, outside the repository). Landed as 5296e74d (CON-416) and 3f37d8d6 (CON-417).

## CON-423 — history_secret_scan.sh exact-match pass deadlocks on a repository with a few thousand blobs

**Status:** In progress
**Type:** Bug
**Severity:** High
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/secscan_deadlock_2026_11_16/red_wchan_prefix.txt` — red-command `HSS_DL_TIMEOUT=60 bash tests/security/test_history_secret_scan_deadlock.sh (script sha256 e03c80988748a0cd)` — green-command `bash tests/security/test_history_secret_scan_deadlock.sh (fixed script, same test)` — env `host, clone of origin main bbdf4ac1, hermetic 8000-blob repository, fake gitleaks` — signature `case 1 rc=124; python3 matcher and git cat-file --batch both in wchan anon_pipe_write after 25 s` — updated 2026-11-16T14:22:15Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `all blob ids written to the cat-file stdin pipe before any stdout read; both pipe buffers fill. Toggling only that (ids from a file) removes the hang: green_wchan_fixed.txt shows the run finished within 25 s, and mutant DM1 (pipe write restored) hangs again` — evidence `docs/qa/secscan_deadlock_2026_11_16/green_wchan_fixed.txt` — updated 2026-11-16T14:22:15Z — by `AI`

What: the --keys-file exact-match pass of scripts/security/history_secret_scan.sh wrote every blob id into the stdin pipe of git cat-file --batch before it read any reply. With a few thousand blobs git fills its stdout pipe and stops reading stdin, the matcher fills the stdin pipe, and both wait for ever (observed on a real repository as a 2400 s timeout with 7,408 blob ids, about 300 KB). Scope: the exact-match matcher only; the gitleaks stage finishes first. Reproduction: tests/security/test_history_secret_scan_deadlock.sh builds a hermetic repository with 8000 blobs and runs the real script under timeout; on the unfixed script (sha256 e03c8098) case 1 fails with rc 124 after 60 s, and /proc wchan of both the python3 matcher and git cat-file --batch reads anon_pipe_write (docs/qa/secscan_deadlock_2026_11_16/red_wchan_prefix.txt). Fix: the ids reach git from a regular file in the work directory, and every reply is checked against the requested id (a missing or wrong reply is exit 7). Acceptance: the same test passes 17/17 within the bound, twice with identical output hashes; 14 paired mutants including the re-introduced deadlock are killed; the existing 45-case suite still passes. Evidence is gate-logic class (§11.4.289); a run with the real gitleaks binary stays owed (CON-401).

## CON-424 — history_secret_scan.sh exact-match pass: values shorter than 12 characters are not searched

**Status:** Queued
**Type:** Task
**Severity:** Medium

What: the --keys-file exact-match pass of scripts/security/history_secret_scan.sh never searches a value shorter than 12 characters (too many chance matches in a full history). Since CON-423 this limit is documented in the script header and in docs/guides/security_hardening_scripts.md, and every run prints the note 'not searched: N shorter than 12 characters (NAMES)' with variable names and count only, also when N is 0; tests/security/test_history_secret_scan_deadlock.sh checks the 11/12 character boundary and the names and count, and paired mutants DM6, DM7 and DM8 are killed. Owed: a way to check short values (for example a context-bound pattern such as NAME=value, or an operator decision that short values are out of scope), and the decision recorded. Acceptance: either short values are covered by a tested check with its own controls, or the operator decision to leave them out is recorded and cited by the guide.

## CON-425 — history_secret_scan.sh: a refs/replace entry hides a secret blob from the exact-match pass and from gitleaks (CON-423 review NEW-1)

**Status:** In progress
**Type:** Bug
**Severity:** High
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/secscan_replace_2026_11_16/red_current_main.txt` — red-command `bash docs/qa/secscan_replace_2026_11_16/red_toggle.sh.txt <checkout> <label> (script sha256 d6bd918ef33e0dbf, origin main cc51c320); HSS_SCRIPT=<main copy> bash tests/security/test_history_secret_scan_replace.sh (3/17)` — green-command `same probe and bash tests/security/test_history_secret_scan_replace.sh on the fixed script (17/17)` — env `host, clone of origin main cc51c320, git 2.53.0, hermetic local repositories with refs/replace entries, fake gitleaks` — signature `blob replaced by a clean blob: --exact-only rc=0 MYKEY=0, scanner pass rc=0 findings=0; forced blob->tree replace: --exact-only rc=7, scanner rc=0 findings=0; a caller's GIT_NO_REPLACE_OBJECTS=1 has no effect (cleared by the git-env scrub)` — updated 2026-11-16T15:54:50Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `git honours refs/replace/* by default and clone --mirror copies them; the script scrubbed GIT_NO_REPLACE_OBJECTS and never set it, so cat-file --batch and the scanner's git log read the replacement. Toggling only the export of GIT_NO_REPLACE_OBJECTS=1 (fixed script minus that line, toggle_minus_export.txt) brings back MYKEY=0, findings=0 and rc=7; with it every fixture is found (green_fixed.txt)` — evidence `docs/qa/secscan_replace_2026_11_16/toggle_minus_export.txt` — updated 2026-11-16T15:54:50Z — by `AI`

What: scripts/security/history_secret_scan.sh honours replace refs, so a repository that carries refs/replace/<secret-blob> -> <clean-blob> is scanned through the replacement. Measured by the CON-423 review round 2 (rev2_secscan_dl_ev, SHA256SUMS verified): replace_probe.txt, --exact-only, mode=plain rc=1 MYKEY=1, mode=replaced rc=0 MYKEY=0 (secret not found, clean verdict); replace_log_probe.txt: the mirror keeps 1 replace ref, git log -p --all -m sees the fake 0 times, with --no-replace-objects 1 time; rv16_probe.txt: a forced blob->tree replace makes cat-file --batch answer type tree for a blob id that --batch-check reports as blob. Pre-existing (not introduced by CON-423), source-defect, important; not fixed in the CON-423 landing. Fix idea: export GIT_NO_REPLACE_OBJECTS=1 right after the git-env scrub so every git call (mirror, cat-file, the scanner's git log) reads the stored objects, and refuse or report replace refs. Scope: scripts/security/history_secret_scan.sh, tests/security/test_history_secret_scan.sh, tests/security/test_history_secret_scan_deadlock.sh, docs/guides/security_hardening_scripts.md. Reproduction: reproduced-host-fixture by the reviewer probes above (host-only). Acceptance: RED first with the review fixtures (replaced blob; blob->tree replace) on the current script, then GREEN with the secret found (exit 1) in both the exact-match pass and the scanner pass; paired mutant that drops the setting is killed.

## CON-426 — CON-423/CON-424: schedule the background verification job and move to the PROVISIONAL-DONE form with a Verification line (review F2)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: the CON-423 fix landed on main (38c80398) but no verification job is scheduled, so section 11.4.290 does not allow the PROVISIONAL-DONE form; CON-423 is set to In progress at landing, not Ready for testing. Scope: tracker rows CON-423, CON-424 and a scheduled run of tests/security/test_history_secret_scan_deadlock.sh, test_history_secret_scan.sh and the deadlock mutation suite on the landed tree. Acceptance: a job id exists, the item carries the line Verification: provisional - job ... - checks ... - layer gate-logic - target host - artifact 38c80398 - due ..., and the status moves only then.

## CON-427 — CON-423 evidence: the reproduction tier and the evidence-class wording do not match (review F3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: independent review of the CON-423 vehicle, finding F3 (relayed by the conductor; the reviewer's full wording is not in the evidence directories, UNCONFIRMED in detail): the tier recorded for the reproduction/evidence (reproduced-host-fixture, host-only, gate-logic per section 11.4.289) and the tier stated elsewhere for the same evidence disagree. Scope: CON-423 Reproduction line, docs/qa/secscan_deadlock_2026_11_16/README.md. Acceptance: one tier, named the same way in the item, the README and the commit text, matching the section 11.4.292(B)/11.4.289 vocabulary.

## CON-428 — CON-423 evidence README: the RED note (4/16 pass, 16 vs 17 cases) is unclear (review F4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review finding F4 (relayed): docs/qa/secscan_deadlock_2026_11_16/README.md says the RED run passed 4/16 while GREEN has 17 cases; the README should state which case set the RED ran, that case 17 was added after the RED, and that case 1 is the one that proves the deadlock. Scope: that README. Acceptance: the note names the case count of each run and the red/green pair per section 11.4.292(E).

## CON-429 — CON-423 docs: the deadlock threshold wording (a few thousand blobs) is host-dependent (review F5)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review finding F5 (relayed): the script header, the guide and CON-423 say the old pass hung with a few thousand blobs; the point where both pipe buffers fill depends on the host pipe size and blob id lengths, so the number is host-dependent. Scope: scripts/security/history_secret_scan.sh header, docs/guides/security_hardening_scripts.md, CON-423. Acceptance: the wording says the threshold depends on the pipe buffer size and names the measured host value or none.

## CON-430 — CON-423 tests: reviewer mutants RV4, RV5, RV6 and RV16 survive the deadlock and history-scan suites (review F6/F7)

**Status:** In progress
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: rev2_secscan_dl_ev/rmut_out.txt: SURVIVED RV4 (trailing-data check reduced to read(1)), RV5 (cat-file exit status not checked), RV6 (no kill/wait before exit 7), RV16 (v in data[:-1], a value at the very end of a blob without a newline is missed; rv16_probe.txt shows rc=0 MYKEY=0). The mapping of these survivors to the reviewer labels F6 and F7 is inferred from the evidence, UNCONFIRMED. Test-instrumentation (section 11.4.235(D)). Scope: tests/security/test_history_secret_scan_deadlock.sh, tests/security/test_history_secret_scan_deadlock_mutations.sh. Acceptance: fixtures that kill RV4, RV5, RV6 and RV16 (RED with each mutant, GREEN without), added to the paired mutation suite. Progress 2026-11-16 (CON-425 fix vehicle, PROVISIONAL, not yet independently reviewed): RV5 and RV16 are now paired mutants DM15 and DM16 of tests/security/test_history_secret_scan_deadlock_mutations.sh, killed by two new cases of tests/security/test_history_secret_scan_deadlock.sh (a git shim whose cat-file --batch gives every correct reply and then exits 3 -> exit 7; a value as the last bytes of a blob with no trailing newline -> counted 1); RV1 (blob type check removed) is RM10 of tests/security/test_history_secret_scan_replace_mutations.sh, killed by a git shim that drops GIT_NO_REPLACE_OBJECTS on a forced blob->tree replace (exit 7). RV4 and RV6 are recorded as equivalent in the header of the deadlock mutation suite (RV4: a short read means git closed the pipe, the next read(1) is not a newline, still exit 7; RV6: exit 7 either way, git ends on EPIPE after python exits). Open until the independent review accepts the equivalence notes.

## CON-431 — codegraph_mcp_health.py: stderr=PIPE is never read while the session runs (bounded deadlock risk)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: docs/qa/secscan_deadlock_2026_11_16/class_census.md: scripts/codegraph/codegraph_mcp_health.py:459-496 starts the server with stderr=PIPE and never drains it during the session; a server that writes more than one pipe buffer of stderr would block. UNCONFIRMED whether any server does. Not fixed in CON-423 (section 11.4.293 scope). Scope: that file and its tests. Reproduction: not yet (UNREPRODUCED); a fixture server that writes more than 64 KiB to stderr is the RED. Acceptance: stderr goes to a file or is drained concurrently; RED then GREEN with the fixture.

## CON-432 — test_review_record_gate_authority_r3_regression.sh:423 writes ev.bytes into a fifo before the reader starts (bounded deadlock shape)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: class_census.md of CON-423: scripts/fastcycle/tests/test_review_record_gate_authority_r3_regression.sh:423 does exec 7<>fifo; cat ev.bytes >&7 before the reader starts; it blocks only if ev.bytes exceeds one pipe buffer (today a small generated file). Not fixed in CON-423 (section 11.4.293). Scope: that test. Reproduction: UNREPRODUCED (needs an ev.bytes larger than the pipe buffer). Acceptance: the writer starts after (or concurrently with) the reader, or the input comes from a regular file; a large-input RED then GREEN.

## CON-433 — scripts/forge/lib/credentials.sh: bracket ranges and classes in bash regexes are locale-dependent (no LC_ALL=C) (review I1)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review item I1 (relayed): credentials.sh matches variable names with [A-Z][A-Z0-9_] ranges and [[:space:]] classes in [[ =~ ]] without LC_ALL=C, so in some locales a range matches more characters than A-Z. Scope: scripts/forge/lib/credentials.sh (lines 71, 80, 135 at 38c80398), tests/forge/test_forge_credentials.sh. Reproduction: UNREPRODUCED; RED under a locale where [A-Z] matches lowercase. Acceptance: matching runs under LC_ALL=C (local to the functions), RED then GREEN, paired mutant.

## CON-434 — tests/release/test_tag_and_release.sh C49: a /proc stderr race makes the case output nondeterministic (review)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review item (relayed by the conductor, mechanism UNCONFIRMED): in case C49 of tests/release/test_tag_and_release.sh (lines 688-708 at 38c80398) the TERM-ignoring git double exits while /proc is still being read, and the resulting stderr line can appear or not between runs. Scope: that test case. Reproduction: UNREPRODUCED; repeated runs with a hash compare of the output are the RED. Acceptance: the case output is identical over N=3 runs, the race closed or the line filtered with a named reason.

## CON-435 — scripts/gitleaks/gitleaks_run_scan.sh: gitleaks detect over the full history never exports GIT_NO_REPLACE_OBJECTS, so a replace ref can hide a secret (CON-425 review F1)

**Status:** In progress
**Type:** Bug
**Severity:** medium
**Created-By:** AI
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/gitleaks_replace_2026_11_16/red/r2_red_real_1.txt` — red-command `GLRS_SCRIPT=<copy of cb7008c4:scripts/gitleaks/gitleaks_run_scan.sh> GLRS_GITLEAKS=<gitleaks 8.30.1> bash tests/security/test_gitleaks_run_scan_replace.sh (4/8)` — green-command `GLRS_GITLEAKS=<gitleaks 8.30.1> bash tests/security/test_gitleaks_run_scan_replace.sh on the fixed script (8/8)` — env `host, clone of origin main cb7008c4, real gitleaks 8.30.1 (sha256 88f91962aa2f93ac), git 2.53.0, local repositories with refs/replace entries` — signature `commit replaced by a clean commit: exit 1 with 1 finding (only the control), hidden secret missing; blob replaced by a clean blob: exit 0, 0 findings (false PASS); core.useReplaceRefs=true in repo config or GIT_CONFIG_PARAMETERS: hidden secret missing` — updated 2026-11-16T18:24:50Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `gitleaks detect reads history through git log -p, which follows refs/replace/*; the script's git-env scrub unsets GIT_NO_REPLACE_OBJECTS and never sets it. Toggling only the export after the scrub (mutant GM1 = unfixed behaviour) brings back the miss with the real binary; with it every case passes` — evidence `docs/qa/gitleaks_replace_2026_11_16/mutations/mut_real_1.txt` — updated 2026-11-16T18:24:50Z — by `AI`

What: review F1 (pre-existing, important): scripts/gitleaks/gitleaks_run_scan.sh runs gitleaks detect over the full history and scrubs the git environment but never exports GIT_NO_REPLACE_OBJECTS=1, the same class CON-425 fixed in scripts/security/history_secret_scan.sh. Measured since (CON-435 fix run, 2026-11-16): gitleaks detect does honour replace refs; with the real gitleaks 8.30.1 a blob-replace repository gave exit 0 with 0 findings on the unfixed script (the original wording here said UNCONFIRMED; corrected per CON-435 review F7). Related: CON-425 (same class, other script), CON-401. Scope: scripts/gitleaks/gitleaks_run_scan.sh and its tests. Reproduction: reproduced-live on the host (see the reproduction record; the original wording said UNREPRODUCED). Acceptance: a RED with a repository carrying refs/replace/<secret-blob> -> <clean-blob> scanned by the real gitleaks binary, then GREEN with the secret found; paired mutant that drops the export is killed. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289). Fix (this change, PROVISIONAL, not yet independently reviewed): export GIT_NO_REPLACE_OBJECTS=1 right after the git-env scrub of scripts/gitleaks/gitleaks_run_scan.sh. Live with the real gitleaks 8.30.1: RED 4/8 on the unfixed script (blob-replace repo exit 0 with 0 findings, a false PASS), GREEN 8/8 on the fix, three identical runs each; fake-scanner suite 9/9; mutants GM1-GM8 killed with both scanners, GE1/GE2 (value 0, empty) behaviour-equivalent. Evidence docs/qa/gitleaks_replace_2026_11_16/. The attributes class (caller or committed .gitattributes -diff gives a false PASS, measured live) is filed separately as CON-453.

## CON-436 — history_secret_scan.sh: a ref that two remotes both name under refs/fetched/r1/ is overwritten by the second forced fetch and hides a commit (CON-425 review F2)

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI

What: review F2 (pre-existing, important): the multi-remote fetch into refs/fetched/r<N>/... can collide; a forced fetch from remote #2 overwrites a ref written by remote #1, so a commit only reachable from the first copy is no longer scanned and the verdict can be clean. Related: CON-425. Scope: scripts/security/history_secret_scan.sh fetch layout, tests/security/test_history_secret_scan_replace.sh. Reproduction: UNREPRODUCED (reviewer description). Acceptance: RED with two remotes whose refs collide and a secret reachable only from the overwritten one, then GREEN (unique namespace per remote, or a refusal), paired mutant killed. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-437 — history_secret_scan.sh: a shallow source repository yields a silent clean verdict; add a history-incomplete signal (CON-425 review F3)

**Status:** Queued
**Type:** Bug
**Severity:** medium
**Created-By:** AI

What: review F3 (pre-existing, important): when the scanned source is a shallow clone the mirror lacks history beyond the graft and the scan reports clean without saying the history is incomplete. Related: CON-425; CON-300 is the same shape in another script. Scope: scripts/security/history_secret_scan.sh, its tests and docs/guides/security_hardening_scripts.md. Reproduction: UNREPRODUCED. Acceptance: RED with a shallow source whose secret sits behind the graft, then GREEN where the run refuses or exits with a distinct history-incomplete code and names it; paired mutant killed. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-438 — history_secret_scan.sh: caller global/system git config (for example core.attributesFile with -diff) is not neutralised (CON-425 review F4)

**Status:** Queued
**Type:** Bug
**Severity:** low
**Created-By:** AI

What: review F4 (minor): the script scrubs git environment variables but does not set GIT_CONFIG_GLOBAL=/dev/null and GIT_CONFIG_NOSYSTEM=1, so the caller's global or system config applies; a core.attributesFile marking files -diff could hide content from git log -p. Related: CON-410 (GIT_CONFIG_COUNT/KEY/VALUE and GIT_CONFIG_PARAMETERS outside the scrub class), CON-425. Scope: scripts/security/history_secret_scan.sh and tests. Reproduction: UNREPRODUCED. Acceptance: RED with a global attributes file setting -diff on the secret path, then GREEN with the config neutralised; paired mutant killed. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-439 — CON-425 tests: reviewer mutant RVA6 (replace-ref count by grep instead of wc -l) survives the replace suites (review F5)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI

What: review F5 (test-instrumentation): reviewer mutant RVA6 replaces rh=$(wc -l < "$RPL") with rh=$(grep -c refs/replace "$RPL" || true) in scripts/security/history_secret_scan.sh and survives test_history_secret_scan_replace.sh, test_history_secret_scan.sh and test_history_secret_scan_deadlock.sh (reviewer_mutants_run1.txt and run2_subset.txt). Related: CON-430 (CON-423 survivors, same class of follow-up), CON-425. Scope: tests/security/test_history_secret_scan_replace.sh and its mutation suite. Acceptance: a fixture that kills RVA6 (RED with the mutant, GREEN without), added to tests/security/test_history_secret_scan_replace_mutations.sh. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-440 — CON-425 tests: reviewer mutant RVA5 (remote index regex r[0-9]+ narrowed to r[0-9]) survives (review F6)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI

What: review F6 (test-instrumentation): reviewer mutant RVA5 narrows the pattern r[0-9]+/replace to r[0-9]/replace in scripts/security/history_secret_scan.sh and survives the three history-scan suites; no fixture uses ten or more remotes. Related: CON-430, CON-425. Scope: tests/security/test_history_secret_scan_replace.sh and its mutation suite. Acceptance: a fixture with a replace ref under a two-digit remote index that kills RVA5, added to the paired mutation suite. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-441 — CON-425 tests: reviewer mutants RVA4 (unanchored refs/replace match) and RVA18 (refs/fetched/ narrowed to refs/fetched/r1/) survive (review F7)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI

What: review F7 (test-instrumentation): RVA4 drops the ^ anchor from $1 ~ /^refs\/replace\// and RVA18 narrows the listed namespaces from refs/fetched/ to refs/fetched/r1/ in scripts/security/history_secret_scan.sh; both survive the three history-scan suites (no fixture with a non-replace ref containing refs/replace/, none with a replace ref fetched from a second remote). Related: CON-430, CON-425; reviewer survivors RVA14, RVA15 and RVA17 are not filed here (not in the conductor's follow-up list; whether they are equivalent is UNCONFIRMED). Scope: tests/security/test_history_secret_scan_replace.sh and its mutation suite. Acceptance: fixtures that kill RVA4 and RVA18, added to the paired mutation suite. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-442 — history_secret_scan.sh: decide whether harmless replace refs need an accept-list (CON-425 review F8, operator decision)

**Status:** Queued
**Type:** Task
**Severity:** low
**Created-By:** AI

What: review F8 (design): since CON-425 the script lists every replace ref and scans the stored objects; a repository that uses replace refs on purpose gets the report every run. Question for the operator (section 11.4.66): keep reporting all replace refs, or add a consumer-declared accept-list (DATA, section 11.4.35) of known harmless replace refs, which must never change what is scanned. Related: CON-425. Acceptance: the operator decision recorded and cited by docs/guides/security_hardening_scripts.md; if an accept-list is chosen, it is tested with a fixture showing an accepted ref is still scanned through the stored object. Source: independent review of the CON-425 vehicle (bundle 778debdb, landed as 5999ff05), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev425_173245/ev/ outside the repository (SHA256SUMS sha256 e446e8235d28b5ddeb814bfa9d30082795ec1905bb00ab299313032646ffaf7b), gate-logic class (section 11.4.289).

## CON-443 — Drift-seam checks do not run on the pull-request landing path (GitHub PR merges bypass land_vehicle.sh publish step 6b)

**Status:** In progress
**Type:** Task
**Severity:** High
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/pr_path_drift_2026_11_16/red/repro_run1.txt` — red-command `bash docs/qa/pr_path_drift_2026_11_16/tools/repro_pr_path.sh.txt <clone at 1dfbb4d1> <out> stale` — green-command `bash docs/qa/pr_path_drift_2026_11_16/tools/repro_pr_path.sh.txt <clone at 695de4d9> <out> stale` — env `host fixture: local bare forge cloned from main 1dfbb4d19bdd3b3e482d45814a9b9ad831f1c730; PR head 77c4952051b12704b199b815710e2895a083e5da` — signature `RESULT LANDED-STALE (forge_main_badge_check_rc=1 on merge 79744a48)` — updated 2026-11-16T21:15:33Z — by `fixer-con443`
**Investigation:** root-cause-found-with-evidence — root-cause `no PR-side entry point ran the step-6b drift checks: the check list and runner lived only inside land_vehicle.sh publish; toggling the cause (pr_landing_check.sh present, same repro) flips LANDED-STALE to REFUSED` — evidence `docs/qa/pr_path_drift_2026_11_16/green/repro_stale_run1.txt` — updated 2026-11-16T21:15:33Z — by `fixer-con443`

 Fix in a vehicle (PROVISIONAL, not landed, not verified): scripts/release/pr_landing_check.sh runs the step-6b checks through the shared library scripts/release/lib/landing_drift_checks.sh, commit 695de4d9; evidence docs/qa/pr_path_drift_2026_11_16/. Not enforced: a forge merge made without running the script is not refused by anything in this repository (no CI, section 11.4.156). Class inventory: docs/qa/pr_path_drift_2026_11_16/class_inventory.md (tag_and_release.sh runs the badge check only: follow-up). A second commit on the same vehicle adds D14/D14b (the lander fast-forward landing path, which no earlier D case took) and P15 (the PR binding LDC_REF=HEAD); mutant table docs/qa/pr_path_drift_2026_11_16/mutants/mutants.tsv.

## CON-444 — land_vehicle drift step 6b: untested failure branches (D9 timeout, D10 BLIND exit 2, D11 moved main, D12 log present) and surviving reviewer mutants R01, R02, R03, R07

**Status:** In progress
**Type:** Task
**Severity:** Medium
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/pr_path_drift_2026_11_16/mutants/base_mutants.tsv` — red-command `python3 -I docs/qa/pr_path_drift_2026_11_16/tools/base_mutants.py.txt <checkout at 1dfbb4d1> <out>` — green-command `python3 -I docs/qa/pr_path_drift_2026_11_16/tools/mutants_con443.py.txt <clone at the fix> <out> L01-no-timeout L02-rc2-pass L03-no-ref-moved L04-log-discarded (the same four mutations at their new location in the library; base_mutants.py itself reports STALE on the fix because the code moved)` — env `host fixture: checkout of main 1dfbb4d19bdd3b3e482d45814a9b9ad831f1c730, that checkout's own LANDER_TEST_DRIFT_ONLY suite` — signature `R01/R02/R03/R07 SURVIVED (suite rc 0) with CONTROL-PASS` — updated 2026-11-16T21:54:40Z — by `fixer-con443`
**Investigation:** root-cause-found-with-evidence — root-cause `the step-6b drift seam had no test for its timeout, rc-2 (BLIND), main-moved and per-check-log branches, so removing any of them left the suite green; adding D9-D12 makes each of the four mutants fail the suite` — evidence `docs/qa/pr_path_drift_2026_11_16/README.md` — updated 2026-11-16T21:54:40Z — by `fixer-con443`

What: review minor m2. tests/release/test_land_vehicle.sh drift cases D1-D8 cover the main paths of publish step 6b, but four branches have no case: D9 a check that exceeds the 900 s timeout, D10 a check that exits 2 (BLIND) must refuse publish, D11 main moved while the checks ran, D12 drift_checks.tsv present and complete in the evidence dir. Reviewer mutants R01, R02, R03 and R07 survive the suite (mutant record in the review evidence rmut.out). Scope: tests/release/test_land_vehicle.sh (and land_vehicle.sh only if a case exposes a defect). Reproduction: not applicable (test instrumentation). Acceptance: D9-D12 added, each RED on a mutant that removes the branch, R01/R02/R03/R07 killed. Source: independent review of the drift-seam vehicle (bundle fixF5 head 0b336ac0, landed on main as merge 6c743898), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/revF5.ILonzX/ev/ outside the repository (SHA256SUMS sha256 b402c26fd0ceb49a22a8bc7aa897782354792908f44fffc1691d7870da7eb31e), gate-logic class (section 11.4.289). Fix in a vehicle (PROVISIONAL, not landed, not verified): D9-D14b added to tests/release/test_land_vehicle.sh (drift-only suite pass=30 fail=0), the check list and runner moved to scripts/release/lib/landing_drift_checks.sh; reviewer mutants R01/R02/R03/R07 survive on base 1dfbb4d1 (docs/qa/pr_path_drift_2026_11_16/mutants/base_mutants.tsv) and are killed on the fix as L01-L04 (docs/qa/pr_path_drift_2026_11_16/mutants/mutants.tsv: 21 of 22 non-control mutants killed, V02 recorded equivalent-or-stricter). Evidence docs/qa/pr_path_drift_2026_11_16/README.md.

Link (section 11.4.214, open original, link only; 2026-11-17): review F6 (nit, process-doc): this item is Type Task and its text still says 'Reproduction: not applicable (test instrumentation)' while its reproduction state is now reproduced-host-fixture (surface host-only). Defensible under section 11.4.294(E), since its closure claims a defect removed (surviving mutants killed); reconcile the description text with the state fields. The reviewer notes CON-443's forge symptom was not exercised live, so neither item may reach VERIFIED-DONE on this evidence. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-445 — codegraph test suite: a T4 SKIP is invisible in the SUMMARY line and an unexpected SKIP exits 0 (lib_test t_finish has no skip count)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review minor m3 and author follow-up CON-PENDING-t4-skip-mutant (same symptom, one item). test_tripwire.sh T4 now SKIPs when no df target with 5..498 GiB free exists, but SUMMARY prints only cases= and failed=, because lib_test t_finish does not count skips; the author's mutant TW-skip (candidate selection never matches) turns T4 into a SKIP and the suite still exits 0. A consumer that needs T4 to run must read the RESULT T4 SKIP line. Candidate duplicate (section 11.4.214(3), UNDECIDED, minted with link): CON-262 (wider SKIP class: suites that print SKIP but exit 0). Scope: scripts/codegraph/tests/lib_test.sh (t_finish), test_tripwire.sh. Reproduction: not applicable (test instrumentation). Acceptance: SUMMARY carries skipped=N; a decision recorded (section 11.4.66) whether an unexpected SKIP fails the suite; TW-skip killed or recorded as accepted. Source: independent review of the drift-seam vehicle (bundle fixF5 head 0b336ac0, landed on main as merge 6c743898), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/revF5.ILonzX/ev/ outside the repository (SHA256SUMS sha256 b402c26fd0ceb49a22a8bc7aa897782354792908f44fffc1691d7870da7eb31e), gate-logic class (section 11.4.289). Source: author follow-ups of the drift-seam fix, docs/qa/drift_seam_2026_11_16/followups.md (landed with merge 6c743898).

## CON-446 — land_vehicle publish step 6b runs the drift-check scripts from the vehicle head, so a vehicle can weaken the check it is judged by

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: review minor m4 (trust boundary). Step 6b executes compute_badges.sh and cm_gate_env_reads_allowlisted.sh from the tree being landed; a vehicle that edits either script (or config/gate_env_allowlist.tsv) can make its own drift check pass. Producer and verifier are not separated (section 11.4.240). Options: run the scripts from main_before and the data from the landed tree, or refuse when the vehicle changes a check script without an explicit reviewed flag. Related: CON-299 (lander). Scope: scripts/release/land_vehicle.sh step 6b and its tests. Reproduction: UNREPRODUCED (review finding from code reading). Acceptance: RED with a vehicle whose compute_badges.sh always exits 0 over a stale badge row, GREEN when publish refuses; paired mutant killed. Source: independent review of the drift-seam vehicle (bundle fixF5 head 0b336ac0, landed on main as merge 6c743898), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/revF5.ILonzX/ev/ outside the repository (SHA256SUMS sha256 b402c26fd0ceb49a22a8bc7aa897782354792908f44fffc1691d7870da7eb31e), gate-logic class (section 11.4.289).

## CON-447 — drift-seam review nits n1-n3: T4 margin flake, topology_unsupported vs artifact_not_yet_built wording, undocumented FAIL-script-missing branch

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review nits. n1: test_tripwire.sh T4 asserts avail_bytes within 2 GiB of an independent df, which can flake when the volume fills or frees fast between the two reads. n2: scanner_gate_false_positive_repairs_test.sh labels the unpopulated third-party legs topology_unsupported; the reviewer asks whether artifact_not_yet_built (or the section 11.4.69 closed set) is the right code. n3: land_vehicle.sh step 6b has a FAIL branch for a required check script missing from the tree that the header and guide do not document. Scope: those three files and docs/guides for the lander. Reproduction: not applicable. Acceptance: each nit fixed or answered with a recorded reason. Source: independent review of the drift-seam vehicle (bundle fixF5 head 0b336ac0, landed on main as merge 6c743898), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/revF5.ILonzX/ev/ outside the repository (SHA256SUMS sha256 b402c26fd0ceb49a22a8bc7aa897782354792908f44fffc1691d7870da7eb31e), gate-logic class (section 11.4.289).

## CON-448 — test_tripwire.sh T4 hard-coded --min-gib 400 and could not trip on a volume with more than 400 GiB free (audit F7)

**Status:** In progress
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: audit F7 and author follow-up CON-PENDING-tripwire-t4. T4 expected a trip with --min-gib 400; on /mnt/DATA1TB (695-719 GiB free) the tripwire never tripped, RED 3/3 (docs/qa/drift_seam_2026_11_16/red/f7_*.txt). Fix landed with merge 6c743898 (vehicle 0b336ac0): threshold derived from the measured free space of the first df target with 5..498 GiB free, logged avail_bytes and min_bytes asserted, honest SKIP when no target fits; GREEN 3/3 (green/t4_final_*.txt). PROVISIONAL (section 11.4.290): no verification job scheduled yet. Candidate duplicate (section 11.4.214(3), UNDECIDED, minted with link): CON-166 (same class, host-reading test, test_unit_safe.sh). Follow-ups: the margin nit and the invisible SKIP are filed separately. Reproduction: reproduced on the host (RED 3/3 above). Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d), gate-logic/host class (section 11.4.289). Source: author follow-ups of the drift-seam fix, docs/qa/drift_seam_2026_11_16/followups.md (landed with merge 6c743898).

## CON-449 — scanner_gate_false_positive_repairs_test.sh e2e canon legs FAILed when superspec/open_design are not checked out (audit F10)

**Status:** In progress
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: audit F10 and author follow-up CON-PENDING-scanner-e2e-topology. The e2e canon opt-in leg FAILed (pattern absent) in a clone without the third_party:true submodules, RED 3/3 (docs/qa/drift_seam_2026_11_16/red/f10_*.txt). Fix landed with merge 6c743898 (vehicle 0b336ac0): without a populated third-party submodule the three canon legs SKIP (topology_unsupported); toggle with a populated superspec runs them and they pass (toggle/f10_pop_toggle.txt). PROVISIONAL (section 11.4.290). Related: CON-103 (superspec exclusion topology guard). Reproduction: reproduced on the host (RED 3/3 above). Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d), gate-logic/host class (section 11.4.289). Source: author follow-ups of the drift-seam fix, docs/qa/drift_seam_2026_11_16/followups.md (landed with merge 6c743898).

## CON-450 — CON-402 git-env scrub preamble in fc_supervisor.py:239-240 breaks the fastcycle path-operation census; test_fc_safepath_v4r12..v4r15 FAIL on main (audit F1)

**Status:** Queued
**Type:** Bug
**Severity:** High
**Created-By:** AI

What: audit F1 (regression). Commit 3281d92e (CON-402) inserted 'import os as _ge_os' plus the scrub loop at scripts/fastcycle/cycle/fc_supervisor.py:239-240; check_safepath_census.py fails closed on an import outside its modelled set (VIOLATION fc_supervisor.py:239 ... PY_IMPORTS), so test_fc_safepath_v4r12, v4r13, v4r14 and v4r15 FAIL. The preamble also sits before 'import _signal as _early_sig' (N6 early-signal design). Deterministic 3/3 FAIL at main 09d3ad2f, PASS at e90d4aea, FAIL at 3281d92e. Related: CON-402 (parent cause), CON-403..CON-410 (other CON-402 fallout, not this defect). Release-blocking for a --include-heavy section 11.4.40 retest. Scope: fc_supervisor.py scrub placement and/or check_safepath_census.py modelled forms; N6 signal-window tests re-run. Reproduction: reproduced on the host by the auditor (bash scripts/fastcycle/tests/test_fc_safepath_v4r12.sh in a clone named constitution). Acceptance: the four safepath tests GREEN on main, N6 tests GREEN, paired mutant that restores the unmodelled import is killed. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d), gate-logic/host class (section 11.4.289).

## CON-451 — CON-402 made two guard-viability mutants blind: test_repo_verify_red.sh round-5 env strip and test_custody_sweep_r8_regression.sh R8-I2 (audit F2/F3)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: audit F2 and F3 (regression, test instrumentation). After CON-402 the tools scrub GIT_DIR at the top of the file, so the paired mutants that strip the defended env strip can no longer reach the ambient-GIT_DIR vector: test_repo_verify_red.sh FAILs 'the mutant did not modify the inherited GIT_DIR repo -- fixture does not exercise the vector', test_custody_sweep_r8_regression.sh FAILs 'R8-I2 guard-viability BLIND'. 3/3 at main, PASS at e90d4aea, FAIL at 3281d92e. Related: CON-402, CON-148 (other guard-viability wording issue). Scope: the two tests' mutants. Reproduction: reproduced on the host by the auditor. Acceptance: mutants rebuilt to also remove the new top-of-file scrub (or point at it as the defended line); both tests GREEN and each mutant observed to fail the guard. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d), gate-logic/host class (section 11.4.289).

## CON-452 — test_guard_destructive_paths.sh: 4 cases (R4/R6 I1, R6 M2) FAIL under the full-suite runner's fresh HOME, PASS with the real HOME (audit F9)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: audit F9. The full-suite runner gives each unit a fresh HOME under TMPDIR (fsr_home.*); the home-ancestor cases of scripts/hooks/test_guard_destructive_paths.sh expect the real home shape, so four cases FAIL in the runner and PASS standalone. Mechanism UNCONFIRMED in detail. Scope: the test (derive expectations from the HOME it gets) or the manifest row (--env-extra). Reproduction: reproduced in the runner by the auditor; standalone PASS. Acceptance: the test PASSes both in the runner and standalone, with a control case proving the home-ancestor rule is still exercised. Source: pre-release regression audit of main 09d3ad2f, /mnt/DATA1TB/claude-work/scratch/audit.YfaTde/out/AUDIT_FINDINGS_2026-11-16.md outside the repository (sha256 726e4a0867c5c37dec72fbf45f7e2526bcc08721c478d5d450166d49b92a9c6d), gate-logic/host class (section 11.4.289).

## CON-453 — gitleaks_run_scan.sh: a -diff git attribute (committed .gitattributes, or the caller's core.attributesFile) hides secrets from gitleaks detect, false PASS (found while fixing CON-435)

**Status:** Queued
**Type:** Bug
**Severity:** High
**Created-By:** AI
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/gitleaks_replace_2026_11_16/probes/attributes_probe_result.txt` — red-command `bash scripts/gitleaks/gitleaks_run_scan.sh <repo> with gitleaks 8.30.1 on PATH: (a) GIT_CONFIG_GLOBAL=<config with core.attributesFile, *.env -diff>; (b) repo with committed .gitattributes *.env -diff` — env `host, clone of origin main cb7008c4 plus the CON-435 fix, gitleaks 8.30.1, git 2.53.0` — signature `control exit 1 with 2 leaks; (a) and (b) exit 0, PASS 0 real leak(s)` — updated 2026-11-16T18:24:50Z — by `AI`
**Investigation:** not-started — updated 2026-11-16T18:24:50Z — by `AI`

What: gitleaks detect reads history through git log -p, and git honours diff attributes: a path marked -diff is shown as a binary change, so gitleaks never sees its added lines. Measured live with the real gitleaks 8.30.1 and git 2.53.0 on the CON-435-fixed scripts/gitleaks/gitleaks_run_scan.sh (docs/qa/gitleaks_replace_2026_11_16/probes/attributes_probe_result.txt): control repository with no attributes exit 1 with 2 leaks; the same repository with the caller's GIT_CONFIG_GLOBAL naming a core.attributesFile that sets *.env -diff exit 0 PASS 0 leaks; a repository whose own committed .gitattributes holds *.env -diff, with a secret .env committed after it, exit 0 PASS 0 leaks. The committed case comes from the scanned history itself, so GIT_CONFIG_GLOBAL=/dev/null and GIT_CONFIG_NOSYSTEM=1 (the CON-438 fix idea) do not cover it. Related: CON-438 (same class in scripts/security/history_secret_scan.sh, UNCONFIRMED there for the committed case; its scanner runs on a bare mirror), CON-435, CON-425. Scope: scripts/gitleaks/gitleaks_run_scan.sh and its tests; check history_secret_scan.sh too. Fix idea (UNCONFIRMED): pass a log option that forces text diffs (for example --log-opts with --text) or neutralise attributes, and confirm with the real binary. Reproduction: reproduced-live on the host by the probe above; the probe repositories are outside the repository. Acceptance: RED with the real gitleaks on both attribute cases, GREEN with the secret found, positive and negative controls, paired mutant that drops the fix killed. Source: CON-435 fixer run 2026-11-16, evidence docs/qa/gitleaks_replace_2026_11_16/. Re-minted at landing from the placeholder CON-PENDINGcon435 (section 11.4.214).

## CON-454 — gitleaks_run_scan.sh: gitleaks detect reads history without -m, so a secret added only in a merge commit (evil merge) is missed (CON-435 review F1)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: review F1 (important, source defect, pre-existing). scripts/gitleaks/gitleaks_run_scan.sh runs gitleaks detect with the default log options; git log -p shows no diff for merge commits unless -m (or --cc/-c) is given, so a secret introduced only in the merge resolution is never scanned. scripts/security/history_secret_scan.sh already passes --log-opts="--all -m". Related: CON-435, CON-425. Scope: scripts/gitleaks/gitleaks_run_scan.sh and its tests. Reproduction: UNREPRODUCED (review finding). Acceptance: RED with the real gitleaks on a repository whose secret exists only in an evil merge, GREEN after the fix, positive and negative controls, paired mutant that drops -m killed. Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289).

## CON-455 — gitleaks_run_scan.sh: .git/info/grafts and .git/shallow in the scanned repository hide history; GIT_NO_REPLACE_OBJECTS does not disable them (CON-435 review F2)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: review F2 (important, pre-existing). A scanned repository can carry .git/info/grafts or .git/shallow, which rewrite or cut the parent chain git log follows; GIT_NO_REPLACE_OBJECTS=1 (the CON-435 fix) disables refs/replace only, so a graft can still hide a secret commit from gitleaks detect. Fix idea (UNCONFIRMED): scan a fresh --mirror clone, which carries neither file, and report a shallow source as history-incomplete. Related: CON-437 (shallow source in history_secret_scan.sh, other script), CON-435. Scope: scripts/gitleaks/gitleaks_run_scan.sh and its tests. Reproduction: UNREPRODUCED (review finding). Acceptance: RED with the real gitleaks on a repository with a graft that hides a secret commit, GREEN after the fix, paired mutant killed. Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289).

## CON-456 — workable-items add accepts a placeholder id with a second hyphen (CON-PENDING-x2) that the Markdown round trip drops (heading regex [A-Z]{3}-[0-9A-Za-z]+) (CON-435 review F3)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** AI
**Reproduction:** reproduced-live — REPRODUCED — surface host-only — evidence `docs/qa/engine_idgrammar_2026_11_16/red_table_base_ce3dfaea.tsv` — red-command `VALCWD=<repo> bash docs/qa/engine_idgrammar_2026_11_16/repro.sh <engine built from ce3dfaea> <copy of docs/workable_items.db> <out>` — green-command `same command with the fixed engine (green_table_fixed.tsv)` — env `host, scratch clone of origin main, sqlite copies of docs/workable_items.db` — signature `add rc 0 for CON-PENDING-x2; after db-to-md-to-db the id is absent (rt_kept 0) and diff rc 1 while validate rc 0` — updated 2026-11-17T03:18:55Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `renderer canonicalIDRe [A-Z]{3,}- disagreed with the parser's [A-Z]{3}- and non-canonical ids fell to the legacy dot heading that reads at most one hyphen part; decisive toggle: with one shared grammar the GREEN sweep keeps or refuses every shape (diff 0), with the old regexes 21 shapes are lost; round 2: every writer and sync md-to-db judged a part of the item (its id) instead of the whole text sync db-to-md writes for it, and md-to-db wrote one document per transaction; decisive toggle: the class sweep of 489 cases gives 171 violation verdicts on the round-1 engine and none on round 2 (331 RT_OK, 158 REFUSED with the database unchanged)` — evidence `docs/qa/engine_idgrammar_2026_11_17/class_green_r2_table.tsv` — updated 2026-11-17T03:18:55Z — by `AI`

What: review F3 (important, engine source defect). workable-items add --id accepts an id such as CON-PENDING-x2, but the heading parser (parse.go, ^## [A-Z]{3}-[0-9A-Za-z]+) does not match a second hyphen, so a db to Markdown to db round trip silently drops the item. The CON-435 fixer worked around it with the one-hyphen placeholder CON-PENDINGcon435. Either add refuses an id the parser cannot read back, or the parser accepts what add writes. Related: the 2026-10-08 key-grammar owed engine work recorded in the section 11.4.54 / 11.4.248 EXTENSION (add does not enforce a key grammar), CON-391 (round-trip rewrite, different defect). Scope: scripts/workable-items (add, parse.go) and its tests. Reproduction (2026-11-16): reproduced on the host with the real engine built from ce3dfaea on scratch copies of docs/workable_items.db, class sweep docs/qa/engine_idgrammar_2026_11_16/repro.sh (table red_table_base_ce3dfaea.tsv): add accepted 32 of 32 command-line id shapes and 21 of them were lost by the db-to-md-to-db round trip or came back under another id (second hyphen, lowercase key, four-letter key, digits only, empty suffix, leading hyphen, non-ASCII, whitespace, dot, hash, brackets, section sign, parenthesis, em dash, underscore, --prefix cat / CATS / CON-X); validate exited 0 on all of them. Root cause: several regular expressions for one grammar disagreed; the renderer treated [A-Z]{3,}- as canonical while the canonical heading parser reads exactly [A-Z]{3}-, and non-canonical ids fell back to the legacy dot heading, which reads at most one hyphen part. Acceptance: RED round trip with a two-hyphen id, GREEN after the fix, paired mutant killed. Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289). Fix (PROVISIONAL, not yet independently reviewed): one id grammar in cmd/workable-items/idgrammar.go read by the renderer, the parser, add, validate and sync md-to-db; add refuses (exit 1, nothing written) any explicit or --prefix-allocated id that does not round-trip through both trackers; validate reports a stored section body the parser does not read back; sync md-to-db refuses (nothing written) when an item would be dropped while its heading is still in the Markdown. The grammar is not widened; placeholders use one hyphen. GREEN: the same repro.sh command with the fixed engine (green_table_fixed.tsv, 3 identical runs): 13 shapes accepted and each round-trips with diff 0, 20 refused before any write. Known remaining defect: sub-task child ids of a canonical parent (ATM-025-001, subtaskAddCmd, not reachable from the command line) do not round-trip; validate now reports them; the child id grammar needs an operator decision. Round 2 (2026-11-17, PROVISIONAL, not yet independently reviewed): the round-1 review (NO-GO) found that the round-1 checks judged only the id, so a title or description the parser reads differently still round-tripped wrongly (F1 bracket title, F3 leading space, O1 heading line, O2 status suffix), that sync md-to-db wrote Issues before it judged Fixed (F2, an item lost after a refusal), and that the round trip did not compare the representation (F4). Root cause: every writer and md-to-db judged a part of the item (its id) instead of the whole text sync db-to-md writes for it, and md-to-db wrote one document per transaction. Fix: every command that writes an item (add, update, move, block, reopen, close, obsolete-details, states import, repair-bodies) reads the rendered text of the whole item back through the parser of its tracker before writing and refuses unless it is the same one item (exact id, representation, body bytes, carried fields, state records) with every embedded operator text intact; add does this before it opens the database; db-to-md writes the item's own Type, Severity, Created-By and Assigned-To lines from the columns; md-to-db judges both documents first and writes both in one transaction. Evidence: docs/qa/engine_idgrammar_2026_11_17/. Round 6 (2026-11-17, PROVISIONAL, gate-logic/host-only, not independently reviewed): review r5 F1/M1/M2 fixed by one fence-aware definition of an item's own lines (ownlines.go; fenced Status/Type/records are quoted text; CRLF kept), plus a fenced-heading phantom-item fix in parseIssues/parseFixed; evidence docs/qa/engine_idgrammar_2026_11_17/r6/. Owed: mutants N8, N9, N15, N19, N20 survived the identity-controlled run (N8 judged equivalent, UNCONFIRMED) and RV3, RV8, N11, N12, N18, N26 did not compile as written; see the r6 README.

## CON-457 — CON-435 tests: the fake gitleaks scanner ignores --log-opts, so mutant RM6 survives the fake-scanner suite (CON-435 review F4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F4 (minor, test instrumentation). tests/security/fixtures/fake_gitleaks_detect.py does not read --log-opts, so a mutant that changes the log options (RM6) passes the fake-scanner suite; only the real-scanner run kills it. Scope: the fake scanner and test_gitleaks_run_scan_replace_mutations.sh. Acceptance: the fake honours --log-opts (or the suite asserts the argv), RM6 killed with the fake scanner. Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289).

## CON-458 — CON-435 tests: no case asserts the scanned repository, refs/replace included, is unchanged after the scan (mutant RM15 survives) (CON-435 review F5)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F5 (minor, test instrumentation). No test checks that gitleaks_run_scan.sh leaves the scanned repository untouched (refs, refs/replace, config); reviewer mutant RM15 that writes to it survives. Scope: tests/security/test_gitleaks_run_scan_replace.sh. Acceptance: a before/after ref and config fingerprint case, RM15 killed. Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289).

## CON-459 — CON-435 class census covers replace refs only, not grafts, shallow, attributes or textconv (CON-435 review F6)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F6 (minor). docs/qa/gitleaks_replace_2026_11_16/class_census.md enumerates the history-hiding class for refs/replace only; grafts, .git/shallow, diff attributes (CON-453) and textconv drivers are members of the same class (git shows a history other than the stored objects) and are not enumerated. Related: CON-453, the F2 item of this review, CON-437, CON-438. Scope: the census document (and items for members not yet covered). Acceptance: every member enumerated with a control-needled instrument and closed or linked to a tracked item (section 11.4.276(C)). Source: independent review of the CON-435 vehicle (bundle 55b225f1, landed on main as merge 2ad83e18), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/rev_con435/ev/ outside the repository (SHA256SUMS sha256 56a680cb7d13c540ba086175cf1eac8470a27b98651993ca2420de26b38c04f8), gate-logic class for the fake scanner, host-only live for the real gitleaks (section 11.4.289).

## CON-460 — v73.5: land or retire the parked ref wip/continue-20261105/atm1217-replace (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/continue-20261105/atm1217-replace, tip f26ae1af9bd8be96bdd69260577c27ede8562fd9, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,m3w,origin, 15 commit(s) not on main, last commit 2026-11-04T23:32:36+01:00: 'fix(fastcycle): units helper round 5 - NUL/\c/\u words not static, fd-0 redirection rules,'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-461 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217-r3-20261013 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217-r3-20261013, tip 468f017a159ce06389d3065596d6395392c6a3e5, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 3 commit(s) not on main, last commit 2026-10-13T21:49:08+05:00: 'ATM-1217 r3 shellcheck baseline-delta (review candidate, local only)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-462 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217-r4-20261013 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217-r4-20261013, tip a6100a4a06a809cf94816edb924dd8f93c8065e6, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 3 commit(s) not on main, last commit 2026-10-13T22:48:28+05:00: 'ATM-1217 r4 shellcheck baseline-delta (review candidate, local only)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-463 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217-r5-20261013 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217-r5-20261013, tip 65fe773e1a20c220ceac2a41747092f06d2ad7d8, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 3 commit(s) not on main, last commit 2026-10-14T00:06:24+05:00: 'ATM-1217 r5 shellcheck baseline-delta (review candidate, local only)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-464 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217_r6 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217_r6, tip 15d2420ec56ae56f27979e6f3e2d95e1608cdfb7, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 3 commit(s) not on main, last commit 2026-10-14T11:33:55+05:00: 'ATM-1217 r6: shellcheck baseline-delta rule (review candidate)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-465 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217_r7 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217_r7, tip 45f5c86ea717a213aa876023555b9372e003e329, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 3 commit(s) not on main, last commit 2026-10-14T13:31:24+05:00: 'ATM-1217 r7: shellcheck baseline-delta rule (review candidate, round 5)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-466 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217_r8 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217_r8, tip 02c5612ab51af5620096e80f543ff7fd393b4930, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 4 commit(s) not on main, last commit 2026-10-14T15:30:21+05:00: 'ATM-1217 r8: tests + guide wording only, for the r7 review (K1, K3)'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-467 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1217_r9 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1217_r9, tip 99bd6dd5bd4496397750251c57f278374851fae1, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 5 commit(s) not on main, last commit 2026-10-14T17:47:26+05:00: 'ATM-1217 r9: command-unit line map (r8 review L1), L2 cases, reviewer mutants R01-R06'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-468 — v73.5: land or retire the parked ref wip/continue-20261105/census-followups (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/continue-20261105/census-followups, tip 0e4b197b0236d96fba09aec3b8e9487d2a1a8f8f, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,m3w,origin, 5 commit(s) not on main, last commit 2026-11-05T10:23:09+01:00: 'fix(gates): env census disowns an awk program written to a file and run as awk -f $FILE (C'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-469 — v73.5: land or retire the parked ref wip/evidence-con017-94a1d28 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/evidence-con017-94a1d28, tip 94a1d28f292540ff5962dd08c73aef566929d9ef, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,m3w,origin, 7 commit(s) not on main, last commit 2026-11-05T13:08:21+01:00: 'fix(gates): env census CON-017 disowns a program only when the whole class is proven non-j'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-470 — v73.5: land or retire the parked ref wip/preserve-20261115/agentlabel_r7 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/preserve-20261115/agentlabel_r7, tip 70b8cd9695d00d4d988835cb9aa6aebdbf27aa22, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 1 commit(s) not on main, last commit 2026-10-15T09:32:03+05:00: 'agent-label definitions round 2: T<N>-<branch>-<alias>-<model>-<effort> agent types (gener'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-471 — v73.5: land or retire the parked ref wip/preserve-20261115/issuerule_r7 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/preserve-20261115/issuerule_r7, tip 59f5a4ad1d0501ebe795260b62fab625fbe69a23, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 1 commit(s) not on main, last commit 2026-10-15T09:26:36+05:00: 'constitution: §11.4.102 EXTENDED with clause (E), round 7 (last round of the §11.4.276 bud'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-472 — v73.5: land or retire the parked ref wip/preserve-20261115/stash2_anchors_11_4_205_206 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/preserve-20261115/stash2_anchors_11_4_205_206, tip 00e29d0fa3ebb4c6172b21ef26d56323c7f67288, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 2 commit(s) not on main, last commit 2026-07-15T14:59:19+05:00: 'WIP on main: c3cd967 ATM-785 (t1 - claude4): fix §11.4.201 vanished-PID false-refuse in mu'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-473 — v73.5: land or retire the parked ref wip/review-pending-20261014/held_precheck-gate-20261012 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/held_precheck-gate-20261012, tip 4b13814917505d984bd96377d815c847c7f89946, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 4 commit(s) not on main, last commit 2026-10-12T19:20:11+05:00: 'HELD (local only, DO NOT PUSH): snapshot of all uncommitted constitution work, 2026-10-12'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a). Note (operator decision 2026-11-16): the HELD snapshot 4b138149 needs a sensitive-content check first (gitleaks scan of paths and classes only, approved) before any landing or publishing decision.

## CON-474 — v73.5: land or retire the parked ref wip/review-pending-20261014/atm1041-v4-r7-20261013 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/review-pending-20261014/atm1041-v4-r7-20261013, tip 33c9697b5b2f1b2063b4681f63586ff766b0ef98, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,origin, 9 commit(s) not on main, last commit 2026-10-13T20:27:40+05:00: 'fastcycle V4 round 7 (the LAST budget round, §11.4.276): close the round-6 review -- group'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-475 — v73.5: land or retire the parked ref wip/continue-20261105b/ownership-wave2-r2 (class D, work not on main)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decision 2026-11-16: the class D refs (work not on main) are parked for v73.5, listed as a gap in the v73.4 changelog, one tracked item each, never deleted before a decision. Ref wip/continue-20261105b/ownership-wave2-r2, tip 6b7462a51f6f8fb67befbfc469ca6eaf59db41fc, on remotes gitflic,github,github_vasic_digital,gitlab_helixdevelopment1,gitlab_vasic_digital,gitverse,m3w,origin, 1 commit(s) not on main, last commit 2026-11-05T14:24:25+01:00: 'WIP snapshot before reboot (unreviewed, not for main) ownership-wave2-r2'. Scope: decide per section 11.4.288 (B)(4)/(C.7)(4): land the work (review to GO, merge onto main) or retire it after a per-mirror bundle and an ls-remote read-back, with a recorded operator decision. Reproduction: not applicable. Acceptance: the ref is landed or retired and the decision is recorded. Source: ref audit /mnt/DATA1TB/claude-work/scratch/refaudit_288_UMPl/out/refs.tsv outside the repository (sha256 fa38a49d79f794b843ea198f14de5ce85e86ee715e6919fd6107cd676ee1c69a).

## CON-476 — v73.5: resume or retire the parked guard vehicle case-alt (destructive-path guard)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decisions 2026-11-14 and 2026-11-16: the guard vehicle case-alt (destructive-path guard) is parked for v73.5 (listed as a gap in the v73.4 changelog) and gets one tracked item. State: round 4 reviewed NO-GO; parked after three safety-classifier stops in a row. Bundle and evidence outside the repository: /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/guard_casealt_r4.QJoy/guard_casealt_r4.bundle (review REVIEW_r4.md sha 5535bdb1). Related findings already tracked: CON-373, CON-374, CON-375. Scope: resume with a fresh fixer and reviewer to GO and land on main, or retire with a recorded operator decision; never drop the bundle. Reproduction: not applicable. Acceptance: landed or retired, decision recorded.

## CON-477 — v73.5: resume or retire the parked guard vehicle PE+G1 (destructive-path guard)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decisions 2026-11-14 and 2026-11-16: the guard vehicle PE+G1 (destructive-path guard) is parked for v73.5 (listed as a gap in the v73.4 changelog) and gets one tracked item. State: round 3, not reviewed to GO. Bundle and evidence outside the repository: /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/guard_pe_g1.4a3x/guard_pe_g1_r3.bundle. Related findings already tracked: none found by title search. Scope: resume with a fresh fixer and reviewer to GO and land on main, or retire with a recorded operator decision; never drop the bundle. Reproduction: not applicable. Acceptance: landed or retired, decision recorded.

## CON-478 — v73.5: resume or retire the parked guard vehicle idguard (git identity guard) round 9

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: operator decisions 2026-11-14 and 2026-11-16: the guard vehicle idguard (git identity guard) round 9 is parked for v73.5 (listed as a gap in the v73.4 changelog) and gets one tracked item. State: round 9, not landed on main. Bundle and evidence outside the repository: /mnt/DATA1TB/claude-work/scratch/fin9.03XH/ev/idguard_r9.bundle. Related findings already tracked: CON-334 to CON-341. Scope: resume with a fresh fixer and reviewer to GO and land on main, or retire with a recorded operator decision; never drop the bundle. Reproduction: not applicable. Acceptance: landed or retired, decision recorded.

## CON-479 — forge.sh GitVerse leg: release-ensure ends UNVERIFIED-COMMIT (exit 5) for every annotated tag; the provider never reads the tag's commit (v73.4 rehearsal B-M6/Q-4)

**Status:** In progress
**Type:** Bug
**Severity:** High
**Created-By:** AI
**Reproduction:** reproduced-live — REPRODUCED — surface live-target — evidence `docs/qa/gitverse_tag_peel_20261116/repro_release_ensure_dryrun.txt` — red-command `bash scripts/forge/forge.sh release-ensure --remote gitverse --tag helixconstitution-v73.3 --sha aa5ae0a3cd21b3aa1184f47a46dd0fecd6a30ca2 --notes-file <notes> --dry-run --try-create-on-ambiguous (at cb7008c4)` — green-command `same command after the fix` — env `live gitverse.ru api.gitverse.ru peer 185.65.149.102:443 cert sha256 8fe542a4...; tag object e915eef7, commit aa5ae0a3` — signature `RED: NOTE tag_sha_unverified, REASON commit_unverified, RESULT UNVERIFIED-COMMIT rc 5; GREEN: TAG present sha=aa5ae0a3..., RESULT OK rc 0` — updated 2026-11-16T19:14:28Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `providers/gitverse.sh read the annotated tag's commit only via GET /git/tags/{sha}, which GitVerse answers 400; GET /commits/{tag-object-sha} answers 200 with the peeled commit (decisive toggle: with the fallback the live dry-run is OK, without it rc 5)` — evidence `docs/qa/gitverse_tag_peel_20261116/api_commits_tagobj.txt` — updated 2026-11-16T19:14:28Z — by `AI`

What: providers/gitverse.sh read an annotated tag's commit only through GET /git/tags/{sha}, which GitVerse answers 400 VALIDATION_ERROR, so tag-get printed sha=unknown and release-ensure ended RESULT: UNVERIFIED-COMMIT (exit 5) even for the existing tag helixconstitution-v73.3; the v73.4 cut was blocked on it (operator decision 2026-11-16). Root cause (FACT, verifier defect, not a mirror lag): git ls-remote gitverse gives the same tag object e915eef7 and peeled commit aa5ae0a3 as the local tag; GET /repos/{o}/{r}/commits/{tag-object-sha} (the object.url of the matching-refs answer) answers 200 with sha aa5ae0a3, unknown objects answer 422. Fix: prov_tag_get falls back to commits/{tag-object-sha} when git/tags/{sha} is not 200, by the tag-object sha (never the tag name), and accepts only a 200 whose sha is a full commit id other than the tag-object sha. Scope: scripts/forge/providers/gitverse.sh, tests/forge/test_forge_gitverse.sh (G1-G8, G5b), tests/forge/test_forge_mutations.sh (G01-G09, M17 adapted). Acceptance: suite cases G1-G3 RED on the unfixed provider and GREEN after; every G mutant killed; live read-only tag-get reports the commit and the release-ensure dry-run for v73.3 ends OK, a wrong --sha ends FAIL tag_sha_mismatch. Evidence: docs/qa/gitverse_tag_peel_20261116/ (LIVE reads, section 11.4.289; suite gate-logic). Not proven: the GitVerse release write path (POST /releases) stays LIVE-UNPROVEN. Re-minted at landing from the vehicle's placeholder id (vehicle commit 5fc0cef9) (section 11.4.214).

Link (section 11.4.214, open original, link only; 2026-11-17, release prep): the cut-day checklist step 13 still expects GitVerse to end UNVERIFIED-COMMIT (exit 5) at the real cut (rehearsal B-M6 on helixconstitution-v73.3); recorded there as an honest gap, not a PASS. Source: v73.4 release-prep draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft (outside the repository; SHA256SUMS sha256 c3096ff57234aff26af53012e320278e71d978077aab97cd5bbcba5f5c27f709, all entries verified OK by the lander 2026-11-17), read at main 60177435.

## CON-480 — CON-479 tests: no assertion that the API token is absent from output on the new GitVerse commits/{tag-object-sha} fallback path (reviewer mutant RV06 survives)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: review F1 (test gap). tests/forge/test_forge_gitverse.sh G1-G8 never check that the token stays out of stdout/stderr on the fallback call added by CON-479; reviewer mutant RV06 (token printed to stderr in the fallback) survives. The reviewer's patch idea, test_forge_gitverse_rvx.sh in the review evidence dir, kills it (reviewer_mutants_vs_extended_test.txt). Scope: tests/forge/test_forge_gitverse.sh. Acceptance: a token-absent assertion on the fallback path, RV06 killed. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-481 — CON-479 tests: a 422, a 3xx and any other 2xx (201/204) answer carrying a sha in the body are not tested on the GitVerse fallback (reviewer mutants RV01, RV10, RV02 survive)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: review F2 (test gap). The fallback must accept only a 200 whose sha is a full commit id; no case feeds a 422, a redirect (302) or a 201/204 with a sha in the body, so mutants RV01 (accept 422), RV10 (trust 3xx) and RV02 (accept any 2xx) survive. The reviewer's extended test kills RV01 and RV10; RV02 still survives it. Scope: tests/forge/test_forge_gitverse.sh. Acceptance: cases for 422, 302, 201 and 204 each ending sha=unknown, RV01, RV10 and RV02 killed. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-482 — CON-479 tests: a nested sha (.commit.sha, .parents[0].sha) and a curl failure on the commits call are not tested (reviewer mutants RV04, RV05 survive; fail-closed but wrong error class)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F3 (test gap). No case gives a commits answer whose only sha is nested (.commit.sha or .parents[0].sha) or makes the commits curl call fail; mutants RV04 (nested sha accepted) and RV05 (curl failure swallowed) survive. The behaviour stays fail-closed, but the reported error class is wrong. Scope: tests/forge/test_forge_gitverse.sh. Acceptance: both cases added with the expected error class asserted, RV04 and RV05 killed. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-483 — GitVerse commits/{X} also resolves branch names: a 40-hex branch named like the tag-object sha would answer the fallback (pathological, CON-479 review N1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review nit N1. GET /repos/{o}/{r}/commits/{X} resolves a branch name as well as a sha, so a branch whose name is the 40-hex tag-object sha could be read in its place. Pathological; record the limit in the provider header or guard against it. Scope: scripts/forge/providers/gitverse.sh header, multiforge guide. Acceptance: the limit documented, or a test showing it cannot occur. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-484 — Probe whether GitFlic .commitId is the peeled commit for an annotated tag (UNCONFIRMED; CON-479 review)

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: review follow-up. The GitFlic provider reads a tag's commit from .commitId; whether that is the peeled commit of an annotated tag or the tag object is UNCONFIRMED. If it is the tag object, the GitFlic leg has the same class as CON-479. Related: CON-412, CON-414. Scope: a read-only live probe of an annotated tag on gitflic.ru compared with git ls-remote, then scripts/forge/providers/gitflic.sh if needed. Reproduction: UNREPRODUCED. Acceptance: probe output recorded as evidence; a fix with RED/GREEN if the value is the tag object. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-485 — GitVerse release write path (POST /releases) is LIVE-UNPROVEN and the release list answers 404: prove it or SKIP it honestly at the real cut

**Status:** Queued
**Type:** Task
**Severity:** High
**Created-By:** AI

What: review follow-up and CON-479 boundary. CON-479 fixed the read path only (tag-get and release-ensure dry-run now OK live). The write path POST /repos/{o}/{r}/releases has never run live, and GET .../releases answers 404 REPO_NOT_FOUND for a repository that answers 200 (multiforge guide). The operator's block on the GitVerse cut is cleared at source level only. Related: CON-479, CON-412, CON-414. Scope: the real v73.4 cut on GitVerse: a live create with read-back, or an honest SKIP-with-reason in the release record. Reproduction: not applicable. Acceptance: a live release created and read back on gitverse.ru with captured evidence, or an explicit SKIP-with-reason recorded at the cut; never a claimed success without read-back. Source: independent review of the GitVerse release-verification vehicle (bundle 5fc0cef9, landed on main as merge a6f97681), verdict GO-with-follow-ups, evidence /mnt/DATA1TB/claude-work/scratch/gvrev_dMSU/ev/ outside the repository (SHA256SUMS sha256 e1c27e0a3abad8acffbf82373ae8764bf35f6e0b59d521f48c4675069ee16278; reviewer_mutants.txt, reviewer_mutants_vs_extended_test.txt), gate-logic class (section 11.4.289). Parent: CON-479.

## CON-486 — Eight vehicle landings since v73.3 were squashed; the reviewed heads are not ancestors of main (sections 11.4.288(B)(3), 11.4.297(A)); operator decision open

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: since tag helixconstitution-v73.3 (aa5ae0a3), eight vehicle landings reached main as one squash commit each, so the reviewed head is not an ancestor of main (measured 2026-11-16 in a full clone of main 3e5e7e7d: each head is absent from main's history, acff58ae is present locally and git merge-base --is-ancestor says no). The eight: 763726e0 CON-234 rounds 1-14 (reviewed head acff58ae); f4881591 land_vehicle lander rounds 4-6 (head b8f063e1, its message records a conductor decision, option (a), not to land the orphan history); d0a6832f CON-312 (head 2e397cba); 5da39508 CON-313 (head fa1c9302); 584c287e CON-314 (head d659fddd); e90d4aea CON-401 (head e940110e); 3281d92e CON-402 (head fd799642); e5879550 CON-412 (head 380ad64a). Landings by merge commit in the same range (for example 6c743898, 2ad83e18, a6f97681, 5999ff05, f4fc7215, 66ad6efe) keep their reviewed heads and are not affected. Rules: section 11.4.288(B)(3) says a vehicle lands fast-forward-only (main advanced with merge --ff-only after the vehicle merges main into itself) and (B)(4) says its unique commits must be on main on every upstream before the vehicle is retired; section 11.4.297(A) says the landing is a fast-forward or a merge commit whose second parent is the reviewed head, never a squash or rebase merge, but it binds only a project that declared PR mode (whether this repository declared it is UNCONFIRMED). A squash keeps the reviewed tree content (for 763726e0: 390 of 397 changed paths byte-equal to acff58ae, the other 7 are the shared files its message names as integrated) but not the reviewed commits. Open operator decision, not decided here: whether the existing history stays as it is (no rewrite, section 11.4.113 forbids it in any case) and whether future landings change practice (merge or fast-forward of the reviewed head instead of squash). Scope: landing practice and the land_vehicle lander (scripts/release/land_vehicle.sh); no code change in this item. Reproduction: not applicable (process observation). Acceptance: the operator decision recorded; if practice changes, the lander and landing docs follow it. Source: lander report 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/landF5.M2YZfU/ev_227/ (CON-234 r14 re-landing check). Related: CON-299 (lander), CON-234.

## CON-487 — fastcycle consumer-section tests: reviewer mutants RV4 (sticky section skip) and RV7 (skip count reset by a later present section, false PASS) survive test_consumer_section_con092_red.sh (fc097 review F1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F1 (minor, test-instrumentation). Mutants RV4 (a section skip that stays set for later sections) and RV7 (a later present section resets the skip count to 0, so the run reads PASS) both survive scripts/fastcycle/tests/test_consumer_section_con092_red.sh (reviewer log mymut.log). Scope: scripts/fastcycle/tests/test_consumer_section_con092_red.sh and its mutation companion. Reproduction: reviewer mutants on head d5d25e3f. Acceptance: RV4 and RV7 adopted as legs; each fails the suite. Parent CON-092. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-488 — fastcycle lib/consumer_section.sh reads FC_CONSUMER_SECTIONS_SKIPPED from the caller environment; an inherited -1 plus one real skip exits 0 (false PASS), an inherited 1 gives a false SKIP (fc097 review F2)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review F2 (minor, source-defect in the test library). scripts/fastcycle/tests/lib/consumer_section.sh does not initialise FC_CONSUMER_SECTIONS_SKIPPED when sourced, so the value is taken from the environment: inherited -1 with one real skip yields exit 0 (false PASS), inherited 1 yields a false SKIP. Fix: set the counter to 0 when the library is sourced. Scope: scripts/fastcycle/tests/lib/consumer_section.sh and the con092 tests. Reproduction: reviewer, environment-injection runs on head d5d25e3f (UNREPRODUCED by the lander). Acceptance: RED with an inherited value, GREEN after init to 0, paired mutant killed. Parent CON-092. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-489 — CON-097 RED test live half resolves the canon from $(pwd): mutant RV8 survives when the test runs with cwd = canon root; run the live half from a neutral directory (fc097 review F3)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F3 (minor, test-instrumentation). Mutant RV8 (the converted test resolves the canon root from $(pwd) instead of its own path) survives the CON-097 live half when scripts/fastcycle/tests/test_canon_root_rename_con097_red.sh is run with cwd = canon root (reviewer RV8_*.out). Scope: test_canon_root_rename_con097_red.sh. Acceptance: the live half cd's to a neutral directory and RV8 is killed. Parent CON-097. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-490 — CON-097 census pattern covers only $ROOT/ and $REPO_ROOT/ prefixes; test_render_keys_wiring_red.sh:62 uses $REPO_ROOT_REAL/constitution and is missed (fc097 review F4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F4 (minor, test-instrumentation). The CON-097 hard-coded-canon-name census matches only $ROOT/constitution and $REPO_ROOT/constitution; scripts/fastcycle/tests/test_render_keys_wiring_red.sh line 62 uses $REPO_ROOT_REAL/constitution, which is rename-fragile and not found. Scope: the CON-097 census and that test. Acceptance: the census matches any variable prefix (or names the variables it covers), with a control needle on line 62, and the test converted. Parent CON-097. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-491 — full_suite manifest note for scripts/fastcycle/tests/lib/consumer_section.sh names only test_anchor_citations_red.sh; about five tests source it (fc097 review F6, nit)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F6 (nit, process-doc). The excluded-lock / manifest note for scripts/fastcycle/tests/lib/consumer_section.sh names only test_anchor_citations_red.sh as its user; about five tests source it. Scope: config/full_suite_manifest.tsv / excluded-lock note. Acceptance: the note lists every sourcing test (or says 'sourced helper' without a partial list), re-accepted after review. Parent CON-092. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-492 — test_custody_sweep_red.sh: fixture proposal_golden_good_verified_hash.json derives REFUSED where ALLOWED is expected; also on named main (fc097 author follow-up CON-PENDING-4)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: author follow-up CON-PENDING-4. scripts/fastcycle/tests/test_custody_sweep_red.sh: the golden-good fixture proposal_golden_good_verified_hash.json derives REFUSED where ALLOWED is expected; it fails the same way on named main. PENDING_FORENSICS: not investigated (outside the canon-name / consumer-data class). Scope: custody_sweep and that fixture. Reproduction: UNREPRODUCED by the lander (author's runs). Acceptance: root cause established, the fixture or the derivation fixed with RED/GREEN. Related: CON-146, CON-157 (other custody_sweep defects, different symptom). Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-493 — test_consumer_required_mutations.sh helper sweep reports 2 uncovered unset sites in the git-env scrub line of lib/consumer_required.sh (pre-existing on main; fc097 author follow-up CON-PENDING-5)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: author follow-up CON-PENDING-5. The helper sweep of test_consumer_required_mutations.sh reports two uncovered 'unset' sites in the git-env scrub line of the fastcycle lib/consumer_required.sh; pre-existing on main, not introduced by the vehicle (the new section functions were kept in lib/consumer_section.sh so the sweep is unchanged). Scope: lib/consumer_required.sh and its mutation sweep. Reproduction: UNREPRODUCED by the lander. Acceptance: both sites covered by a killing mutant or recorded equivalent with a reason. Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-494 — context/governance_subset.py, cycle/collect_baseline.py, gates/batch_bisect.py and orchestration/handoff.py default the consumer root to the parent of the canon, which is not the project in a standalone clone (fc097 author follow-up CON-PENDING-6)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: author follow-up CON-PENDING-6. These production tools derive the consumer/repo root as the parent of the canon when --repo is not given. That is the intended submodule default, but in a standalone clone the parent is not the project. Proposal: when the derived root has no 'constitution' entry that is this canon, fall back to the canon root or refuse loudly (section 11.4.201(4)). The vehicle changed only the tests (they now pass --repo); tool defaults are unchanged. Scope: the four tools named. Reproduction: UNREPRODUCED by the lander. Acceptance: RED in a standalone clone, GREEN after the fix, paired mutant. Related: CON-097. Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-495 — workable-items engine: add a note / append-body subcommand so progress paragraphs can be added to an item body without the lossy md-to-db sync (fc097 author follow-up CON-PENDING-7)

**Status:** Queued
**Type:** Feature
**Severity:** Low
**Created-By:** AI

What: author follow-up CON-PENDING-7. The vehicle could not add progress paragraphs to item bodies through the engine: update has no append-body, and sync md-to-db is lossy (CON-391, CON-396). Proposal: an engine subcommand that appends a dated note to body_md (and history), never rewriting other fields. Scope: scripts/workable-items. Acceptance: subcommand with tests, history event, round-trip stable. Related: CON-391, CON-396. Source: vehicle follow-up file /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md of vehicle head d5d25e3f, landed on main as merge f090d082.

## CON-496 — Declare pull-request delivery (§11.4.297) for this repository and its own submodules (operator decision 2026-11-16)

**Status:** In progress
**Type:** Task
**Severity:** High
**Created-By:** AI

What: the operator decided on 2026-11-16 (interactive question, relayed) that this repository switches to pull-request delivery under §11.4.297, merged by the author agent, recursively for every own submodule. Scope: config/delivery.conf (the §11.4.297(A) declaration, DATA only), docs/guides/pr_delivery_landing_guide.md (landing procedure with exact commands), README link, evidence docs/qa/pr_delivery_decision_20261116/. Acceptance: declaration present with every §11.4.297(A) key; CM-PR-DELIVERY-ACCOUNT-NAME-FREE PASS with the config; guide reachable from README; open questions reported to the operator. Known blocker: the reviewer list holds only the author account, so §11.4.297(D)(2) makes every delivery end non-zero (open question Q1). Class: gate-logic / declaration; nothing ENFORCED; PROVISIONAL. Open questions for the operator (none answered by the agent): Q1 author-only reviewer list: does merge condition (C)(2)(c) hold when (D)(2) leaves no requestable reviewer, or must a second authoring account or a second reviewer account be configured, or §11.4.297(D)(2) amended by a recorded decision? Q2 where is the per-PR source-correctness GO record kept? Q3 confirm PR mode, reviewer list, branch prefix and upstream list for each of the 10 own submodule repositories in own_repositories. Q4 should the GitHub repository allow only merge commits and should the main ruleset require pull requests (platform changes not made; merge settings unreadable with the current token)? Q5 which tool-written ledger paths (tool_written_paths is empty)? Q6 merge window value (24 h is a placeholder)? Q7 fix for the account-name gate gap CON-497? Q8 keep the extra keys pr_repository, pr_assignees, decision_date, own_repositories in the declaration? Q9 is the shared_single_files list right? Q10 install a local direct-push guard (expected or enforced)? Landing form recommended and recorded: merge-commit (PRs 7, 8, 9 measured as merge commits whose second parent is the PR head). Round 2 (2026-11-16, operator decisions OPD-2026-11-16-PR-DELIVERY-R2, relayed, paraphrased): Q1 answered by decision (1): agent creates, self-reviews and merges, PRs assigned to the owner account; the author-only reviewer point is reported and the delivery ends non-zero, the agent still merges when every other condition holds; recorded as a consumer departure (author_only_reviewer_policy=report-and-merge), follow-up question CON-498. Q6 answered: merge window none. Q7 answered: CON-497 fixed in this vehicle. Q8 answered: the extra keys stay; the gate test pins that they parse. Answered conservatively by the agent and still UNCONFIRMED (operator may narrow or change): Q2 GO record = a pull-request comment naming the reviewed head, never committed into the task branch (whether a committed copy under docs/qa/<id>/ is also wanted is open); Q9 shared_single_files widened to the tracker and its rendered docs, canon and four mirrors, index, rule catalogue, deferral ledger, README; Q10 direct_push_guard stays off (no guard exists; installing one needs consent); Q5 tool_written_paths stays empty (candidates docs/workable_items.db and rendered Issues/Fixed docs listed in the config); Q3 every own submodule in pr mode with this file's values, each submodule's own upstream list and merge-method settings unmeasured. Q4 (GitHub merge-method settings, ruleset requiring pull requests) unchanged: platform changes not made. Evidence docs/qa/pr_delivery_decision_20261116/r2/.

## CON-497 — CM-PR-DELIVERY-ACCOUNT-NAME-FREE cannot serve a repository that is its own consumer: own config not found by default, --changed-since flags the config itself and goes BLIND on the tracker DB

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: measured 2026-11-16 in a scratch clone (evidence docs/qa/pr_delivery_decision_20261116/gate_account_free_default.txt, gate_account_free_changed_since.txt, probe_selfflag.txt). (1) Without --consumer-config the gate looks only at <root>/../config/delivery.conf (the submodule layout), so in this repository, whose declaration is config/delivery.conf inside the root, the post-update run SKIPs (exit 3). (2) With --changed-since, the consumer's own config/delivery.conf is in the corpus and is reported FAIL (it is the one file that must hold the account names). (3) With --changed-since, a changed docs/workable_items.db (binary, NUL bytes) makes the gate BLIND (exit 2). Affected: scripts/gates/cm_pr_delivery_account_name_free.sh and its post_update_hook.sh call. Acceptance: the declared config path is excluded from the corpus by path (not by content), the gate finds a root-level config/delivery.conf when the root is its own consumer, binary tracker files are handled without hiding text files; RED cases for each, paired mutants. Needs an operator decision on the exclusion mechanism (Q7 in CON-496); not fixed here. Round 2 (2026-11-16, operator decision (3) of OPD-2026-11-16-PR-DELIVERY-R2): fixed in this vehicle, pending independent review. Root cause, read in scripts/gates/cm_pr_delivery_account_name_free.sh: the default configuration was only $(dirname ROOT)/config/delivery.conf; the --changed-since loop added every changed file, including the configuration just read and a binary SQLite database, to the corpus. Fix: both <root>/config/delivery.conf and <root>/../config/delivery.conf are read by default; under --changed-since a configuration read in this run is left out by its resolved path, and a file starting with the SQLite header is left out; both are named in the output and in the verdict; a file of the fixed corpus is never left out and any other binary file stays BLIND. RED first: 5 of 8 new cases failed on the old gate (docs/qa/pr_delivery_decision_20261116/r2/red_baseline_con424.txt), 8 of 8 pass after the fix (green_con424.txt); 10 new gate mutants added to the paired mutation test.

## CON-498 — Author-only reviewer list under §11.4.297(D)(2): keep the recorded report-and-merge consumer departure, amend the anchor, or add a second account? (follow-up question, operator decision 2026-11-16)

**Status:** In progress
**Type:** Task
**Severity:** High
**Created-By:** AI

What: by the recorded operator decision OPD-2026-11-16-PR-DELIVERY-R2 (paraphrased by the conductor, not verbatim) every pull request of this repository is created, self-reviewed and merged by the agent and assigned to the main repository owner's account. The configured reviewer list (config/delivery.conf pr_reviewers) holds only that account, which is also the author, so §11.4.297(D)(2) skips it, no reviewer is possible, and the delivery reports that and ends non-zero; the platform may also refuse the agent's own review. The decision records that the refusal is REPORTED (never dropped or replaced) and that the agent still merges when every OTHER merge condition holds. This is recorded in config/delivery.conf (author_only_reviewer_policy=report-and-merge) and docs/guides/pr_delivery_landing_guide.md as a CONSUMER departure; Constitution.md is NOT amended. Question for the operator: (a) keep the consumer departure as is, (b) amend §11.4.297(C)/(D) through the normal anchor-amendment path so an author-only reviewer list is a declared case, or (c) add a second reviewer account or open pull requests from a different account so (D)(2) is met. Until answered, every delivery ends non-zero on the reviewer point and that is reported, never hidden. Acceptance: the operator's answer recorded, and config/guide (or the anchor, via its own vehicle and review) changed to match. Scope: config/delivery.conf, docs/guides/pr_delivery_landing_guide.md; nothing ENFORCED. Note: the id CON-498 may collide with another vehicle minting CON-496..427; re-mint above the current maximum at landing.

Round 3 (2026-11-16): answered. The operator chose to amend §11.4.297; the (D)(6) author-only reviewer clause and its relaxation of (C)(2)(c) only are in this same vehicle, PROVISIONAL until its independent §11.4.209 review.

## CON-499 — Section 11.4.297(D)(6) calls the operator quote verbatim, but the conductor relayed it; mark it '(relayed)' (PR-delivery r3 review finding 1)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review finding 1 (minor, process-doc). The (D)(6) amendment of section 11.4.297 presents the operator quote as verbatim, but it was relayed by the conductor; per section 11.4.6 it must say '(relayed)' (or carry the verbatim text if one is recorded). Scope: Constitution.md section 11.4.297(D)(6) and its lockstep mirrors (CLAUDE.md, AGENTS.md, GEMINI.md, QWEN.md, progressive/rules/11.4.297.md), index regenerated, propagation gate re-run. Not changed by the lander. Reproduction: not applicable (text). Acceptance: the wording corrected in every carrier, CM-COVENANT-114-297-PROPAGATION PASS. Related: CON-498. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-500 — Section 11.4.297 amendment wording nits: report-and-stop vs condition (c), 'quotes the platform's own text' with no reviewer request, pr_assignees missing from the DATA list (PR-delivery r3 review findings 2-4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review findings 2, 3 and 4 (nits, process-doc). (2) 'report-and-stop (point (2) as written, no merge)' is imprecise: the merge is blocked by condition (c), not by (D)(2) itself. (3) 'quotes the platform's own text' is ambiguous when no reviewer request was made and the platform returned no text. (4) pr_assignees is missing from the (D) / Classification DATA list. Scope: Constitution.md section 11.4.297 and its lockstep mirrors. Reproduction: not applicable (text). Acceptance: the three passages corrected in every carrier, propagation gate PASS. Related: CON-498, and the separate finding-1 item. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-501 — CM-PR-DELIVERY-ACCOUNT-NAME-FREE tests and coverage: adopt reviewer probes f2_glob_sibling and f1_newline_content_record (mutants V18, V19), fix the r2 header, scan conflict stages 2 and 3, document the compressed-BLOB limit (PR-delivery r3 review findings 5-8)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review findings 5 to 8 (test-instrumentation and gate coverage). (5, minor) The reviewer probes f2_glob_sibling and f1_newline_content_record are the only cases that kill mutants V18 (newline sort of the changed list) and V19 (index lookup without :(literal)); the fixer's suite has neither (evidence reviewer_mutants.txt, v18_v19_witness.txt; V20, V22 and V23 also survived the reviewer's run). Adopt them as legs. (6, nit) scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh header (line 41) still describes round 2 ('SQLite database left out and named'); round 3 scans the database. (7, minor) For a staged conflict only stage 1 is read (head -n 1); stages 2 and 3 are never scanned. (8, minor) A BLOB holding compressed binary passes silently while a binary file goes BLIND; document it as a limit (or treat it as BLIND). Scope: scripts/gates/cm_pr_delivery_account_name_free.sh and its mutation test. Reproduction: reviewer mutant runs (UNREPRODUCED by the lander). Acceptance: V18 and V19 killed by the suite, header corrected, stages 2/3 scanned with a RED case, the BLOB limit documented or closed. Related: CON-497. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-502 — The hub's tracked config/delivery.conf is now read by default in every consumer's post-update run: a consumer with no declaration of its own gets a PASS against this repository's accounts instead of a SKIP (PR-delivery r3 review finding 9)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review finding 9 (minor, source-defect in the gate default). After round 3, CM-PR-DELIVERY-ACCOUNT-NAME-FREE reads <root>/config/delivery.conf by default; run from scripts/post_update_hook.sh in a consumer, the hub's own tracked config/delivery.conf is found, so a consumer that has not declared pull-request delivery is checked against this repository's accounts and reports PASS instead of SKIP (no declaration). Fix: apply the hub default only when the hub is the repository being checked (its own consumer), or document the behaviour. Scope: scripts/gates/cm_pr_delivery_account_name_free.sh lookup order and scripts/post_update_hook.sh. Reproduction: UNREPRODUCED by the lander (review finding). Acceptance: RED in a consumer fixture without its own declaration (PASS today), GREEN as SKIP after the fix, paired mutant. Related: CON-497. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-503 — PR-delivery config, guide and records: pr_repository vs own_repositories names disagree, guide conf() truncates values with '=', step-8 is-ancestor only echoes, vehicle commit records misdescribe and use mixed placeholder forms (PR-delivery r3 review findings 10-12)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review findings 10 to 12 (process-doc). (10, minor) config/delivery.conf names pr_repository HelixDevelopment/constitution but own_repositories HelixDevelopment/HelixConstitution; reconcile (the old name redirects: a push to the HelixConstitution remote prints 'This repository moved', observed 2026-11-16). (11, nit) docs/guides/pr_delivery_landing_guide.md: the conf() awk helper truncates values containing '='; the step-8 is-ancestor check only echoes and does not fail. (12, nit) commit 8d86c8ef's message describes the pipefail test fix that is in 70860528; merge commit 9c79dbe5 uses CON-PENDING-prdeliv-* placeholders while later commits use the CON-PENDINGprgate form; correct in the landing record (history is not rewritten, section 11.4.113). Lander observation, same class: rounds 1-2 of the vehicle used CON-423 / CON-424 as its own ids, which are main's history_secret_scan items; citations remain in docs/qa/pr_delivery_decision_20261116/ (check_leak.sh, r2/*), CHANGELOG.md line 5 and the mutation test line 258 ('CON-423 decision'); the round-3 items are CON-496, CON-497, CON-498. Scope: config/delivery.conf, the guide, a landing-record note. Acceptance: names reconciled, guide helper and check fixed, a record note mapping the old ids and placeholders to CON-496..498. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

Link (section 11.4.214, open original, link only; 2026-11-16, live inventory finding (a)): GitHub reports repository id 1238419173 as full_name HelixDevelopment/constitution (gh.out), and forge_get.out prints 'NOTE: repo_moved canonical=HelixDevelopment/constitution' three times, while config/delivery.conf own_repositories still names .:HelixDevelopment/HelixConstitution (its header names both). Same defect as review finding 10. Source: live host inventory 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/live.MLQNpS/ev (SHA256SUMS sha256 c85e7e6f526f23efbb3b123ab9f53ea6d3b94b64fcdbb4e2d8b1fc0edc24458a), relayed by the coordinator; facts below re-read by the lander from that evidence.

## CON-504 — Replace the account-name test fixtures (@-fixtures in attribution_test.go and testdata) with a dedicated fixture account (PR-delivery r3 review F4)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F4 (process-doc). The declared reviewer account name appears in 9 tracked files outside the account-name gate corpus: GitHub-owner URLs, an email-like string in docs/research/quality/CROSS_PROJECT_HELIX_CODE.md (separate item), and @-fixtures in attribution_test.go and its testdata. Do not widen the corpus; replace the test fixtures with a fixture account that is not a real declared account. Scope: attribution_test.go and its testdata. Acceptance: the tests pass with the fixture account, and a census of the declared account name over tracked files lists only the expected owner URLs. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-505 — Review the personal email-like string in docs/research/quality/CROSS_PROJECT_HELIX_CODE.md (PR-delivery r3 review F4; file only, the document is not edited here)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F4 (process-doc). docs/research/quality/CROSS_PROJECT_HELIX_CODE.md contains an email-like string built on the declared account name. Review whether it is a personal address that should not be in a tracked research document (section 11.4.10 / privacy), and decide keep, redact or replace. The lander did not edit the document. Scope: that file. Acceptance: a recorded decision, and the change (if any) reviewed. Source: independent review round 3 of the pull-request delivery vehicle (reviewer Opus 5.5, verdict GO-with-follow-ups, all minor-class), findings relayed by the coordinator from the reviewer's hand-back text; review evidence /mnt/DATA1TB/claude-work/scratch/rev_prdeliv_r3.l5FP/ev (SHA256SUMS sha256 17ccc6f7673fdfe72d37df794035cdca3b3c4a844cd41eeafe2b95ad7e798965). Vehicle head 8d86c8ef landed on main as merge 83d3808a.

## CON-506 — config/delivery.conf line 131 says no rulesets were found, while HelixDevelopment/constitution has an active ruleset protect-main-no-force-no-delete (deletion, non_fast_forward; no review or pull-request rule) (live inventory finding b)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: live inventory finding (b), process-doc. config/delivery.conf line 131 says the docs/qa/pr_delivery_decision_20261116/sub_*.txt reads 'found no rulesets'. That statement covers the submodule repositories, but the file also declares the root repository, and the live read-back (gh2.out) shows an active ruleset on HelixDevelopment/constitution: id 27164960, name protect-main-no-force-no-delete, enforcement active, rules deletion and non_fast_forward, no required-review or pull-request rule. The wording is ambiguous or stale for the root. Scope: config/delivery.conf comments (and the landing guide if it repeats the claim). Acceptance: the comment states per repository what was measured, citing the read-back. Related: CON-496, CON-503. Source: live host inventory 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/live.MLQNpS/ev (SHA256SUMS sha256 c85e7e6f526f23efbb3b123ab9f53ea6d3b94b64fcdbb4e2d8b1fc0edc24458a), relayed by the coordinator; facts below re-read by the lander from that evidence.

## CON-507 — Jev bootstrap reports endpoints reachable=true from the toolkit cache while claude_toolkit and llmctl are unavailable; reachable=true is not live proof (live inventory finding c)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: live inventory finding (c). jev_bootstrap.out step 3 lists both endpoints as source=toolkit-cache reachable=true, although step 2 recorded llmctl and claude_toolkit as unavailable (no checkout, cloning needs consent) and step 4 skipped wiring. The archived jev-detection.json records reachable_basis=probe with probed_at equal to generated_at. The coordinator reports that the cache records carry null probe, key_variable and status_class fields; in the archived jev-detection.json those fields are populated, so that detail is UNCONFIRMED by the lander. Only jev-probe.sh gave a live answer (per the coordinator). Scope: the bootstrap detect-models step and its record (section 11.4.279, section 11.4.289(D)). Acceptance: a cache-sourced endpoint is labelled as cached (not reachable) unless a probe in this run answered, with a RED case. Source: live host inventory 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/live.MLQNpS/ev (SHA256SUMS sha256 c85e7e6f526f23efbb3b123ab9f53ea6d3b94b64fcdbb4e2d8b1fc0edc24458a), relayed by the coordinator; facts below re-read by the lander from that evidence.

## CON-508 — Section 11.4.291 note says llmctl capacity schema 1 does not carry RLIMIT_NPROC headroom, but live llmctl.capacity/1 output carries host.nproc.headroom (live inventory finding d)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: live inventory finding (d), process-doc. Constitution.md section 11.4.291 (line about 12714) states 'Schema 1 does not carry the RLIMIT_NPROC headroom ... the consumer measures the RLIMIT_NPROC headroom itself'. The live output llmctl_capacity.json has schema llmctl.capacity/1 and host.nproc = {headroom 121072, rlimit_soft 123694, rlimit_hard 123694, user_threads 2622, source 'getrlimit(RLIMIT_NPROC) + /proc/<pid>/status Threads of uid 1000'}. The note is stale for the current llmctl. No existing tracker item for the planned Jev landing amendment was found (dedupe 2026-11-16), so this is filed for that amendment to absorb. Scope: section 11.4.291 contract table and its mirrors. Acceptance: the note corrected (and the consumer's own measurement requirement re-stated against the field), propagation gate PASS. Source: live host inventory 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/live.MLQNpS/ev (SHA256SUMS sha256 c85e7e6f526f23efbb3b123ab9f53ea6d3b94b64fcdbb4e2d8b1fc0edc24458a), relayed by the coordinator; facts below re-read by the lander from that evidence.

## CON-509 — Owner action: vasic-digital/HelixConstitution is private and its branch protection and rulesets cannot be read or set (HTTP 403, needs GitHub Pro or a public repository) (live inventory finding e)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: live inventory finding (e), owner-only action. gh.out and gh2.out show the GitHub API answering 403 'Upgrade to GitHub Pro or make this repository public to enable this feature' for branch protection and rulesets of vasic-digital/HelixConstitution (private, admin permission present). Agents cannot change plan or visibility; until the owner decides (upgrade, make public, or accept no protection on this mirror) the protection read-back for this mirror is a SKIP-with-reason, never a PASS. Related: CON-401 (forge branch protection scripts). Acceptance: an owner decision recorded (section 11.4.66) and the read-back result per decision. Source: live host inventory 2026-11-16, evidence /mnt/DATA1TB/claude-work/scratch/live.MLQNpS/ev (SHA256SUMS sha256 c85e7e6f526f23efbb3b123ab9f53ea6d3b94b64fcdbb4e2d8b1fc0edc24458a), relayed by the coordinator; facts below re-read by the lander from that evidence.

## CON-510 — test_io_trace_build_map_r6_regression.sh fails on this host because unshare cannot write uid_map; report SKIP-with-reason instead of FAIL, or fix the host cause

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: scripts/fastcycle/tests/test_io_trace_build_map_r6_regression.sh fails on this host because unshare cannot write uid_map (user-namespace mapping refused), as reported by the fastcycle vehicle author; the failure is host-environment, not name- or consumer-related, and was also seen on named main. Source of the report: /mnt/DATA1TB/claude-work/scratch/fc097.IRoFwQ/out/followups.md (section CON-PENDING-3, host-environment failures). The fastcycle review findings /mnt/DATA1TB/claude-work/scratch/rev097.GcJx93/ev/findings.md (evidence SHA256SUMS sha256 bf9b3ffb7aaa1f44c6c4a409dc901da89bae3c72c009f6c7cfb3402aad08b5b4) do not mention this test; the detail comes from the author's file. Tracked logs disagree: docs/qa/gitenv_class_r3_2026_11_15/regress/logs_head/work__...test_io_trace_build_map_r6_regression.sh.log shows Sections A and B passing, and docs/qa/fixu_default_tier/u2_user_bus_class/fullsuite_test_io_trace_build_map_r6_regression.log shows B1 failing ('the mutation did NOT reproduce the bypass ... systemd-run exit: 1'); whether those runs hit the uid_map refusal is UNCONFIRMED. Scope: that test and its host preconditions. Reproduction: UNREPRODUCED by the lander. Acceptance: the refusal reproduced and captured (unshare error text, /proc/sys/kernel/unprivileged_userns_clone or AppArmor restriction state), and the test reports SKIP-with-reason topology_unsupported (exit 77) instead of FAIL when user namespaces cannot be mapped, with a RED/GREEN pair; or the host cause fixed by the operator. Related: CON-264 (the same PENDING-3 host-environment note), CON-262 (SKIP class). Section 11.4.214 dedupe 2026-11-16: no existing item covers this test or uid_map.

## CON-511 — ATM-1809 audit 3 follow-ups M1 to M7 and N1 to N4 of the section 11.4.297 / 11.4.298 series have no tracker item

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: the CHANGELOG entry 'Unreleased - 2026-11-07 - ATM-1809 follow-ups of audit 2' (CHANGELOG.md line 100 at 60177435) lists, under 'Not fixed here, open follow-ups of audit 3' (minor and nit), eleven findings with no tracker item: M1 the pin digest removes all whitespace, so splitting or joining a word keeps a pin; M2 a disguise glued to a table bar and the letters U+0269, U+1D0F, U+0585 are missed by the skeleton; M3 the mutation tests do not discriminate the U+01C0 mapping, the i side of the i/l class, the upper-case Greek row, the U+2212 minus or a weakened section 11.4.292 note pin in a gate copy; M4 --changed-since is BLIND when the change set holds a binary file; M5 the F10 sentence reads wider than section 11.4.293(A)(4); M6 two sentences of 11.4.297(C)(4) read across repositories can wait on each other; M7 (H)(2) still says the normaliser undoes look-alike letters of other scripts; N1 the 11.4.298 boundary says 'the refinement notes it adds' for one note; N2 text outside the pinned blocks is not pinned; N3 the account-name gate takes about twice as long as at d374d535; N4 a separate pin-bump pull request under (F)(3) and 'one open pull request per task id at a time' read together are ambiguous. Scope: scripts/gates/cm_pr_delivery_anchor_wired.sh, cm_release_gate_anchor_wired.sh, cm_pr_delivery_account_name_free.sh and their mutation tests; Constitution.md sections 11.4.297/11.4.298 and mirrors. Reproduction: as recorded by audit 3 (not re-run by the lander). Acceptance: each finding fixed with a RED case first or closed with a recorded reason; may be split into one item per finding. The v73.4 entry can cite this id as followups_tracking. Source: v73.4 release-prep draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft (outside the repository; SHA256SUMS sha256 c3096ff57234aff26af53012e320278e71d978077aab97cd5bbcba5f5c27f709, all entries verified OK by the lander 2026-11-17), read at main 60177435.

## CON-512 — Release template paragraph for section 11.4.297 says no config/delivery.conf and no mode: pr exist, but main declares mode=pr (merge 83d3808a)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: docs/release/helixconstitution-v73.4_entry.template.md line 66 (at 60177435) says 'no tracked file of this repository declares pull-request delivery (no config/delivery.conf ...), so section 11.4.288 applies as written and the release commit lands on main by a direct fast-forward push'. Since merge 83d3808a config/delivery.conf is tracked and line 49 reads mode=pr. A rendered v73.4 entry would state a false fact. Scope: that template paragraph (the draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/template_patched.md carries a proposed replacement). Reproduction: grep -n 'mode=' config/delivery.conf; sed -n 66p of the template (read by the lander). Acceptance: the paragraph states the declared mode and how this release commit actually lands, answered against rehearsal open question Q-6 (operator), reviewed. Related: CON-383 (template amendment), CON-496 (the declaration). Source: v73.4 release-prep draft /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft (outside the repository; SHA256SUMS sha256 c3096ff57234aff26af53012e320278e71d978077aab97cd5bbcba5f5c27f709, all entries verified OK by the lander 2026-11-17), read at main 60177435.

## CON-513 — render_release_entry.py accepts DRAFT and placeholder text in manual keys (cut_date not checked as YYYY-MM-DD) and exits 0 (rehearsal B-M4)

**Status:** Ready for testing
**Type:** Bug
**Severity:** Medium
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `/mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/run2/renderer_probes/summary.txt` — updated 2026-11-17T15:08:15Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `render_release_entry.py checked only TODO/TBD; no cut_date date check and no draft mode` — evidence `/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md` — updated 2026-11-17T15:08:15Z — by `AI`

What: rehearsal B-M4: scripts/release/render_release_entry.py refuses only TODO/TBD; cut_date = DRAFT or 'UNCONFIRMED-CUT-DATE ...', retest_item_id = '<CON-NNN>', waiver_expiry = '<recorded date + 30 days>' and killpg_summary_line = '<paste ...>' all render with rc 0 (negative controls rc 3 confirm the check runs); cut_date is never checked as a bare YYYY-MM-DD date and there is no --draft mode, so a rehearsal render and a cut render look alike. Evidence: /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/run2/renderer_probes/summary.txt (sha256 502693f4e27f7b15c3f215f5da755e5c3e16fdec0855697c7411346aecac062c). The lander confirmed statically at 60177435 that the renderer has no cut_date check. Acceptance: RED cases first, then cut_date must match ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ and placeholder/DRAFT shapes in any manual key exit non-zero; paired mutants. The rehearsal-fix vehicle (bundle /mnt/DATA1TB/claude-work/scratch/fix7_con423_abwj/fix_rehearsal_v73_4_r7.bundle, sha256 56f1626d38827487a9a73b3a90c950c31aa16813b02cffcd1f574b4fc5e1e5d8, head 3a5b462d, 19 commits not on main) names itself CON-423 in its commit subjects; on main CON-423 is the history_secret_scan.sh deadlock, so that id collides and the vehicle has no item on main yet. Its D5 and D9 fix this class; link or close this item when that vehicle lands. Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

Link (section 11.4.214, open original, link only; 2026-11-17): the rehearsal-fix vehicle that fixes this class is tracked as CON-521 (the vehicle's own CON-423 id collides with main and is re-minted to CON-521 at landing).

Implementation (landing 2026-11-17): landed by merge e1dab6f8 (main), merge of the release-machinery stack prefix 85f4e880 onto ebd8818c; the stack commits carry the placeholder trailers CON-PENDING-relmach-bm1 (=CON-514), CON-PENDING-relmach-bm4 (=CON-513) and CON-PENDING-relmach-bm2 (=CON-515), mapped here because history is not rewritten (section 11.4.113; review N7). B-M3 (CON-516) is not in this landing. Commit: 87923dc6 (B-M4). Review: GO-with-follow-ups, Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander. Follow-ups: CON-527, CON-528, CON-532, CON-535.

**Verification:** provisional (section 11.4.290) -- job: re-run tests/release/test_render_release_entry.sh (expect 100 passed, 0 failed), tests/release/test_publish_gitea.sh (238/0), tests/release/test_tag_and_release.sh (459/0) and tests/release/test_channel_census.sh (100/0) on main after landing -- checks: the RED cases of the slice stay GREEN and the paired mutants stay killed -- layer: gate-logic (host-only; class floor not met for a runtime claim) -- target: host, repo checkout -- artifact: main at merge e1dab6f8 -- due: next full-suite run.

## CON-514 — render_release_entry.py retest verdict vocabulary (PASS-FULL, PARTIAL-TOPOLOGY, FAIL, NOT RUN) differs from run_full_suite.sh's, so a true result can only be written as a wrong word (rehearsal B-M1)

**Status:** Ready for testing
**Type:** Bug
**Severity:** Medium
**Created-By:** AI
**Reproduction:** reproduced-host-fixture — UNREPRODUCED — surface host-only — evidence `/mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/run2/renderer_probes/summary.txt` — updated 2026-11-17T15:08:15Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `RETEST_VERDICT in render_release_entry.py was a hand-kept list narrower than the runner's verdict table` — evidence `/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md` — updated 2026-11-17T15:08:15Z — by `AI`

What: rehearsal B-M1: render_release_entry.py RETEST_VERDICT accepts only PASS-FULL, PARTIAL-TOPOLOGY, FAIL, NOT RUN (line 38 at 60177435), while scripts/run_full_suite.sh reports more verdicts, among them 3 MANIFEST-MISMATCH, 5 PARTIAL-DEFAULT-SET (the default tier the retest runs first), 6 PARTIAL-SKIPS, 7 PASS-FULL-WITH-KNOWN, 9 REFUSED-TOPOLOGY (header lines 98-104). Those are refused (rc 3), so the entry can only say FAIL or NOT RUN. Evidence: /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/run2/renderer_probes/summary.txt (sha256 502693f4e27f7b15c3f215f5da755e5c3e16fdec0855697c7411346aecac062c). Acceptance: the renderer's set derived from (or equal to) the runner's, a RED case per missing verdict, the open question Q-7 answered. Related: CON-381 (the retest), CON-417, CON-421 (verdict token not bound to a machine verdict). Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

Implementation (landing 2026-11-17): landed by merge e1dab6f8 (main), merge of the release-machinery stack prefix 85f4e880 onto ebd8818c; the stack commits carry the placeholder trailers CON-PENDING-relmach-bm1 (=CON-514), CON-PENDING-relmach-bm4 (=CON-513) and CON-PENDING-relmach-bm2 (=CON-515), mapped here because history is not rewritten (section 11.4.113; review N7). B-M3 (CON-516) is not in this landing. Commit: 87d61ba4 (B-M1). Review: GO-with-follow-ups, Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander. Follow-ups: CON-529, CON-531, CON-533.

**Verification:** provisional (section 11.4.290) -- job: re-run tests/release/test_render_release_entry.sh (expect 100 passed, 0 failed), tests/release/test_publish_gitea.sh (238/0), tests/release/test_tag_and_release.sh (459/0) and tests/release/test_channel_census.sh (100/0) on main after landing -- checks: the RED cases of the slice stay GREEN and the paired mutants stay killed -- layer: gate-logic (host-only; class floor not met for a runtime claim) -- target: host, repo checkout -- artifact: main at merge e1dab6f8 -- due: next full-suite run.

## CON-515 — tag_and_release.sh gitea leg passes no --token-var, so the m3w token is sent to whatever https host a gitea spec names (codeberg included) (rehearsal B-M2)

**Status:** Ready for testing
**Type:** Bug
**Severity:** High
**Created-By:** AI
**Reproduction:** none — UNREPRODUCED — updated 2026-11-17T15:08:15Z — by `AI`
**Investigation:** root-cause-found-with-evidence — root-cause `the gitea leg passed no --token-var and the publisher defaulted to the m3w token for any https base URL` — evidence `/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md` — updated 2026-11-17T15:08:15Z — by `AI`

What: rehearsal B-M2, credential routing (section 11.4.10). The gitea) case of scripts/release/tag_and_release.sh (line 397 at 60177435) builds the publisher arguments without --token-var, and scripts/release_publish_gitea.sh defaults TOKEN_VAR=M3W_GITEA_TOKEN (line 38) and accepts any https base URL, so a spec gitea:codeberg:https://codeberg.org:... would send the git.m3w.org token to codeberg.org. Static evidence only (code reading, re-read by the lander); not exercised at runtime because that would send a token. Mitigation now: the cut-day checklist forbids a codeberg gitea spec (codeberg goes through scripts/forge/forge.sh, per-host token map). Acceptance: the token variable bound to the spec's host (or the spec refused when the host is not the token's), a RED case with a fake token and a local listener, paired mutant. Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

Implementation (landing 2026-11-17): landed by merge e1dab6f8 (main), merge of the release-machinery stack prefix 85f4e880 onto ebd8818c; the stack commits carry the placeholder trailers CON-PENDING-relmach-bm1 (=CON-514), CON-PENDING-relmach-bm4 (=CON-513) and CON-PENDING-relmach-bm2 (=CON-515), mapped here because history is not rewritten (section 11.4.113; review N7). B-M3 (CON-516) is not in this landing. Commit: 85f4e880 (B-M2). Review: GO-with-follow-ups, Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander. Follow-ups: CON-530, CON-534. Reproduction stays UNREPRODUCED: the original finding was static and a live reproduction would send a real token to a foreign host (section 11.4.10); the fix is exercised only with a fake token and a curl shim (gate-logic), so this item tops out at PROVISIONAL-DONE labelled UNREPRODUCED (section 11.4.292(D)).

**Verification:** provisional (section 11.4.290) -- job: re-run tests/release/test_render_release_entry.sh (expect 100 passed, 0 failed), tests/release/test_publish_gitea.sh (238/0), tests/release/test_tag_and_release.sh (459/0) and tests/release/test_channel_census.sh (100/0) on main after landing -- checks: the RED cases of the slice stay GREEN and the paired mutants stay killed -- layer: gate-logic (host-only; class floor not met for a runtime claim) -- target: host, repo checkout -- artifact: main at merge e1dab6f8 -- due: next full-suite run.

## CON-516 — tag_and_release.sh verifies with git ls-remote, which reads the remote's fetch URL, while git push uses its push URL; a remote whose two differ is verified against another server (rehearsal B-M3)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: rehearsal B-M3: git ls-remote R uses remote.R.url, git push R uses remote.R.pushurl. Demonstrated by the rehearsal on two local bare repositories (push landed in b, ls-remote read a). In the live checkout origin is fetch=github, push=gitflic, so --remotes '... origin' would verify a different server than it pushed. Acceptance: tag_and_release.sh refuses a remote whose fetch and push URLs differ (or verifies against the push URL), RED case on two bare repositories, paired mutant. Related: CON-310 (URL shapes not refused). The rehearsal-fix vehicle (bundle /mnt/DATA1TB/claude-work/scratch/fix7_con423_abwj/fix_rehearsal_v73_4_r7.bundle, sha256 56f1626d38827487a9a73b3a90c950c31aa16813b02cffcd1f574b4fc5e1e5d8, head 3a5b462d, 19 commits not on main) names itself CON-423 in its commit subjects; on main CON-423 is the history_secret_scan.sh deadlock, so that id collides and the vehicle has no item on main yet. Its D10 (two remotes pushing to one repository, repeated names) is a neighbour, not this defect. Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

## CON-517 — tag_and_release.sh --dry-run skips the gh/glab auth check, the GitHub repository-id de-dup and the gitea token check, so a release leg that would be skipped or refused shows only in the real run (rehearsal B-M5)

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Created-By:** AI

What: rehearsal B-M5: --dry-run prints PLAN release for every spec and exits before any platform check (line 268 at 60177435: 'RESULT: OK dry-run'), so the two specs for GitHub repository id 1238419173 both show although the real run de-duplicates, and a would-be SKIPPED-NO-TOKEN appears only after the tags are pushed. The rehearsal had to probe the legs separately (/mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/scripts/probe_auth_in_release_env.sh). Acceptance: the dry run performs the read-only checks of every leg (auth, repository resolution and de-dup, token presence by name) and reports each leg's expected outcome; RED case first. The rehearsal-fix vehicle (bundle /mnt/DATA1TB/claude-work/scratch/fix7_con423_abwj/fix_rehearsal_v73_4_r7.bundle, sha256 56f1626d38827487a9a73b3a90c950c31aa16813b02cffcd1f574b4fc5e1e5d8, head 3a5b462d, 19 commits not on main) names itself CON-423 in its commit subjects; on main CON-423 is the history_secret_scan.sh deadlock, so that id collides and the vehicle has no item on main yet. Its D3 and D4 fix this class; link or close this item when that vehicle lands. Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

Link (section 11.4.214, open original, link only; 2026-11-17): the rehearsal-fix vehicle that fixes this class is tracked as CON-521 (the vehicle's own CON-423 id collides with main and is re-minted to CON-521 at landing).

## CON-518 — forge.sh release-ensure cannot be rehearsed before the release tag exists (tag_absent_on_forge, rc 3 on every forge), so the forge legs are only rehearsed against the previous tag (rehearsal B-M6)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: rehearsal B-M6, first part: scripts/forge/forge.sh release-ensure ends tag_absent_on_forge (rc 3) on codeberg, m3w, gitflic and gitverse until the tag is pushed, so the cut-day dry run cannot exercise the forge release legs for the new tag; the rehearsal ran them against helixconstitution-v73.3 instead (/mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/run2/forge/). Results there: codeberg would-enable-releases + would-create (a repository settings change, open question Q-3), m3w release present, gitflic would-create, gitverse UNVERIFIED-COMMIT (CON-479). Acceptance: a plan mode that reports what release-ensure would do for a tag not yet pushed (given the local tag object), or a recorded decision that the previous-tag rehearsal is the accepted proxy. Related: CON-412, CON-479, CON-485. Source: v73.4 cut rehearsal /mnt/DATA1TB/claude-work/scratch/rel_v734_dryrun_20261116T183651/BLOCKERS.md (outside the repository; sha256 dfbd4377ad1bdad5ec485f6bb6202b83cd1074622f4a8990aac4626da720cfe6; directory SHA256SUMS sha256 07c59dacec8a9aa792f0f1d8d4a48bcb256c62df05555b532e108326c17a2fb4, 90 entries verified OK by the lander 2026-11-17), carried into /mnt/DATA1TB/claude-work/scratch/relprep.GRc4vl/draft/CUT_DAY_CHECKLIST.md.

## CON-519 — Sync-all-upstreams vehicle (sync_all_upstreams.py, round 11, NO-GO) has no tracker item on main

**Status:** Queued
**Type:** Task
**Severity:** High
**Created-By:** AI

What: the sync-all-upstreams vehicle (operator order 2026-11-12: recursive fetch and pull of every upstream, wired into init and setup, seven or more test types, live and deterministic) has no item on main (dedupe 2026-11-17: no title or description mentions sync-upstreams, upstream sync or sync_all_upstreams). Vehicle: bundle /mnt/DATA1TB/claude-work/scratch/syncfix11.ZGqG/out/sync_upstreams_r11.bundle (sha256 b89a0b5a165a660d7ee9b435c14dd244beb62469228fa142dc4fbfcb36cc77fd, head 516207f2). Latest review: /mnt/DATA1TB/claude-work/scratch/rev_sync_r11.FeRl/review/review_sync_r11.md (sha256 6d90e55aa4ae1ad9c27049266dbb4937d438aa46d8021122231fadf48aa7583f), verdict NO-GO: RV11-1 (important, data safety) evaluate_upstream resolves the upstream with rev-parse, so a local tag or branch named refs/remotes/<r>/<b> is taken as the upstream and --apply --no-fetch fast-forwards to a commit not upstream; RV11-2 (important, data safety, partly an r11 regression) the widened env scrub drops the user's GIT_NO_REPLACE_OBJECTS=1, and replace refs or info/grafts let the ancestry check run on rewritten history; RV11-3 the vehicle's own CON-423, CON-424 and CON-425 collide with main (history_secret_scan.sh items) and are re-minted at its landing, with the citations in docs/faq/sync_upstreams_faq.md, docs/guides/sync_upstreams_user_guide.md, docs/manuals/sync_upstreams_manual.md and the sync_all_upstreams.py docstring. A round 12 directory (syncfix12.zGcd) exists; its state is not read here. Acceptance: the vehicle reaches GO within the round budget (section 11.4.276) and lands with a merge commit on main, its items re-minted through the engine; this item then carries the landing and verification line. Related: CON-425 (same replace-ref class in the history scan).

## CON-520 — Per-unit timeout budget for slow codegraph tests: test_codegraph_mcp_preflight.sh and test_unit_safe.sh hit the runner's 300 s per-unit limit under host load 40-56

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: the two codegraph test units end TIMEOUT (per_unit_timeout_reached) at about 300 s in a default-tier full-suite run on a loaded host, while their logs are still printing PASS results; a TIMEOUT counts as an unexplained failure (run_full_suite.sh exit 1), so the release retest cannot reach a clean verdict on such a host. The per-unit limit in that run was 300 s; run_full_suite.sh documents a default of 900 s (header line 114), so how 300 s was set for that run is UNCONFIRMED by the lander. Scope: scripts/codegraph/tests/test_codegraph_mcp_preflight.sh, scripts/codegraph/tests/test_unit_safe.sh and the runner's per-unit timeout data. Reproduction: as recorded in the run below (not re-run by the lander). Acceptance: either a declared, reviewed per-unit budget for these two units in the runner's data (with the reason), or the tests made faster (for example fewer subprocess spawns per case) so both finish well inside the default limit under load; a run on a loaded host shows both PASS with their durations. Related: CON-166 and CON-167 (test_unit_safe.sh case failures under load, a different defect), the fastcycle timeout class in docs/Issues.md (test_anchor_citations_red.sh timed out in the same run, line 94). Source: full-suite run /mnt/DATA1TB/claude-work/scratch/bl.frkt3d/out (outside the repository; SHA256SUMS sha256 063982826381bcfb66dd4cee60ece053b22d78af0cdde13de1fdd3b71695e4eb, all entries verified OK by the lander 2026-11-17): run.log line 59 TIMEOUT (per_unit_timeout_reached) scripts/codegraph/tests/test_codegraph_mcp_preflight.sh 300.2s, line 81 the same for scripts/codegraph/tests/test_unit_safe.sh 300.1s; logs/000026.log holds 16 PASS result lines (last F16) and logs/000048.log 50 (last U50), and neither holds a FAIL result line; relayed by the coordinator: host load 40-56, and two solo reruns of the preflight test at 330 s also ended rc=124 while still printing PASS lines (slow, not failing; the rerun logs are not in this directory).

## CON-521 — v73.4 rehearsal-fix vehicle (provisional-line checker, round 7): Verification-line checker, dry-run platform checks, DRAFT/cut_date refusal, remote de-dup (D2, D3, D4, D5, D9, D10)

**Status:** Queued
**Type:** Task
**Severity:** High
**Created-By:** AI

What: the v73.4 rehearsal-fix vehicle (provisional-line checker; round 7) has no item on main. Its commit subjects name it CON-423, which on main is the history_secret_scan.sh deadlock item, so that id collides and is re-minted to this item at landing. Vehicle: bundle /mnt/DATA1TB/claude-work/scratch/fix7_con423_abwj/fix_rehearsal_v73_4_r7.bundle (sha256 56f1626d38827487a9a73b3a90c950c31aa16813b02cffcd1f574b4fc5e1e5d8, head 3a5b462d 'fix(pvl): CON-423 r7 structural round, checker reads a markdown-it-py CommonMark parse', 19 commits not on main 60177435). Review state: round 7 under review (r7 result pending at filing). Description below copied from the vehicle's own draft /mnt/DATA1TB/claude-work/scratch/fix_rehearsal_v73_4_20261116T103117/evidence/con423.desc (sha256 ff72d0ed64edd8c8b0679ca6e270cce6e76996126828d1b9a6ab991907fffc0a):

Source: the v73.4 PROVISIONAL cut rehearsal of 2026-11-16 (REHEARSAL_REPORT.md sha256 74ecd83f35174902d7732b966d0393dfad21c46beb72eabd486d1b54f4a0b3d5, scratch clone of main 09d3ad2f, nothing pushed). Defects of the release tooling and tracker data, fixed class-wide in one vehicle:
- D2 (section 11.4.290): CON-211, CON-235, CON-236 and CON-265 are Ready for testing with no **Verification:** provisional line, so the count line said 25 provisional while 29 items were Ready for testing; CON-190 and CON-191 have a line with no checks field. No check refused either shape.
- D3: tag_and_release.sh --dry-run returned before any platform check, so a would-be SKIPPED-NO-TOKEN, an inaccessible repository or a GitHub repository-id dedup appeared only in the real run, after the tags were pushed.
- D4: the dry-run plan lines of GitHub (and gitea) release legs did not say whether the pre-release flag is passed; only GitLab lines did.
- D5: render_release_entry.py refused TODO/TBD but accepted DRAFT, so an entry full of DRAFT values rendered with exit 0.
- D9: the template appended "." after the last ref of the unmerged-refs block, and the heading takes MANUAL:cut_date whole with no check that it is a bare date.
- D10: --remotes accepted two remotes that push to one repository (the live checkout's origin pushes to gitflic; the scratch clone's origin is the same GitHub repository as github), and a repeated remote name.
Acceptance (test-first, section 11.4.224): RED tests on the unfixed tools, then GREEN; paired mutants killed; a checker refuses every Ready-for-testing or In-testing item without a complete verification line, run on the real database; the six items carry complete lines written through the engine. Follow-ups of the same rehearsal: D1 (CON-379), D6 (CON-381, CON-382), D7, D8 and D11 (filed separately).

Related: CON-513 (D5, D9), CON-517 (D3, D4), CON-516 (D10 is a neighbour), CON-379 (D1), CON-381 and CON-382 (D6).

## CON-522 — CON-443 review F1: mutant V02 (LDC_REF=HEAD in the lander) is not equivalent; add case D11b (HEAD detached at the same commit, then main moved) and correct the V02 note and the drift-check-head-repoint follow-up text

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F1 (minor, test-instrumentation). The author recorded V02 (LDC_REF=HEAD in scripts/release/land_vehicle.sh) as equivalent-or-stricter; the reviewer killed it with a direct ldc_run harness (/mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/v02_kill.log): a check that runs git checkout --detach <same commit> and then moves refs/heads/main gives FAIL ('landing candidate moved') on the original and PASS on the mutant. Harmless for what is pushed (publish pushes local_main read before the checks), but tests/release/test_land_vehicle.sh does not kill V02, because D11 moves main while HEAD is symbolic so both refs move. Scope: tests/release/test_land_vehicle.sh (new case D11b), docs/qa/pr_path_drift_2026_11_16/mutants notes and followups.md (the CON-PENDING-drift-check-head-repoint text describes the opposite scenario). Acceptance: D11b RED against the V02 mutant and GREEN on the original; the note and the follow-up text corrected. Related: CON-444. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-523 — CON-443 review F2: drift checks run from the candidate tree, so a pull request that rewrites its own check passes while stale; state the limit and consider running the base tree's copy

**Status:** Queued
**Type:** Task
**Severity:** Medium
**Created-By:** AI

What: review F2 (minor, process-doc; the caller may grade it a security surface under section 11.4.276(G.2)). scripts/release/pr_landing_check.sh (and the lander) run each drift check from the candidate tree, so a pull request that changes a check can pass while stale: reviewer bypass B5 (/mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/bypass.log) replaced the badge check by a symlink to a no-op script plus a stale marker and got RESULT: PASS. The Limits section of docs/qa/pr_path_drift_2026_11_16/README.md does not state it. Acceptance: the limit stated in the tool's documentation; then either run the base tree's copy of each DRIFT_CHECKS script as well (both must pass), or flag any pull request that touches a DRIFT_CHECKS script for explicit reviewer attention; a RED case of the B5 shape first. Related: CON-443. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-524 — CON-443 review F3: pr_landing_check.sh builds the merge candidate under the caller's git config (system, global, GIT_CONFIG_COUNT, GIT_CONFIG_PARAMETERS); merge.renames=false turns a clean merge into a refusal

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review F3 (minor, source-defect). The merge candidate (git merge-tree --write-tree plus commit-tree) is built with the caller's system and global git config and GIT_CONFIG_COUNT/GIT_CONFIG_PARAMETERS, none scrubbed or pinned. Reviewer case B12b (/mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/bypass.log): merge.renames=false via the environment turns a clean rename/edit merge (tree 782e285e, equal to a real git merge) into a refusal. Observed direction is safe (refusal); a config that gives a clean but different tree is UNCONFIRMED. Acceptance: run merge-tree and commit-tree with GIT_CONFIG_NOSYSTEM=1 and GIT_CONFIG_GLOBAL=/dev/null and with GIT_CONFIG_COUNT/GIT_CONFIG_PARAMETERS unset (or pin the merge keys), RED case B12b first; fold into the forge merge-engine parity follow-up. Related: CON-443, CON-410 (GIT_CONFIG_* outside the git-env class), CON-438 (same class in history_secret_scan.sh). Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-525 — CON-443 review F4: reviewer mutants RM02, RM03, RM04 and RM12 survive the pr_landing_check.sh suite (merge-tree error mapped to FAIL, no cleanup trap, annotated-tag base not peeled, hooksPath dropped)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F4 (minor, test-instrumentation). Surviving reviewer mutants of tests/release/test_pr_landing_check.sh (/mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/rmut.log, *.pr.log): RM02 a merge-tree error mapped to FAIL instead of BLIND (unrelated histories give BLIND rc 2 in bypass B2, no test asserts it); RM03 no cleanup trap (13 temporary clones were left in TMPDIR during the mutant run, removed by the reviewer with safe_rm_rf); RM04 an annotated-tag --base not peeled to a commit (fails safe as BLIND, no test); RM12 core.hooksPath=/dev/null dropped from the private-clone git wrapper (a global hooksPath hook would run; bypass B9 shows the original suppresses it, no test). RM08 (--ignore-submodules=all) was argued equivalent. Acceptance: one RED case per survivor (BLIND rc 2 on unrelated histories, no temporary clone left after the run, annotated-tag base accepted, a global hooksPath hook not run), each mutant then killed. Related: CON-443. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-526 — test_land_vehicle.sh case R5-N3b prints a run-varying count (78 vs 77) inside its PASS text, so a line-hash determinism check differs with identical verdicts (CON-443 review F7)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review F7 (nit, test-instrumentation, pre-existing, not introduced by the CON-443 vehicle). In the reviewer's determinism runs (/mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/det.log) tests/release/test_land_vehicle.sh gave pass=360 fail=0 twice with an identical verdict set, but the line hash differed because case R5-N3b embeds a count that varies between runs (78 vs 77) in its PASS line. Acceptance: the PASS text carries no run-varying value (move the count to a separate diagnostic line or assert a bound), so two runs give identical PASS/FAIL/RESULT lines; two-run evidence. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev443.6DcUhl/review/REVIEW.md (outside the repository; sha256 cc212d7e5c4920d907f7033a82c1d0a85af31a8f94740ae50daa6346dbd57d51; directory SHA256SUMS sha256 04dc8138780b45e24389c116741af9ac551eed651bb97e685d16728029d7ee78, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the CON-443/CON-444 vehicle head f27f64c5, landed on main by merge 22de662c. Follow-up per section 11.4.276(G.2); not re-run by the lander.

## CON-527 — CON-513 follow-up (review N1): reviewer mutant MV3 survives, no case puts a placeholder after a valid autolink or HTML tag in one value

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review N1 (minor, test-instrumentation). Mutant MV3 (only the first angle token of a value is checked) survives tests/release/test_render_release_entry.sh 100/0 (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/mut_MV3_render.txt); HEAD refuses the shape (rc 3 vs 0, /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/survivor_probe.txt), so this is a test gap, not a defect. Scope: tests/release/test_render_release_entry.sh. Acceptance: a case 'see <https://x> and <CON-NNN>' in one manual value expects exit 3; MV3 then killed. Parent: CON-513. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-528 — CON-513 follow-up (review N2): reviewer mutant MV11 survives, DRAFT on a non-first line of a multi-line MANUAL block is untested

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review N2 (nit, test-instrumentation). Mutant MV11 (DRAFT searched only on the first line of a value) survives the renderer suite 100/0 (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/mut_MV11_render.txt); HEAD refuses the shape (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/survivor_probe.txt). Scope: tests/release/test_render_release_entry.sh. Acceptance: a multi-line MANUAL value with DRAFT on its second line expects exit 3 (and renders with --draft); MV11 then killed. Parent: CON-513. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-529 — CON-514 follow-up (review N3): reviewer mutant MV1 survives, no runner table with one malformed row among good rows

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: review N3 (nit, test-instrumentation). Mutant MV1 (drop the len(words) != len(table) check, so a malformed runner-table row is silently dropped) survives tests/release/test_render_release_entry.sh 100/0 (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/mut_MV1_render.txt). The mutant's effect is still fail-closed for the dropped word, hence nit. Scope: tests/release/test_render_release_entry.sh. Acceptance: a temp-tree runner table with one malformed row among good rows expects exit 3; MV1 then killed. Parent: CON-514. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-530 — rc_gitea_binding treats a host-table row with fewer than four TABs (no note column, or CRLF) as not a row, while forge.sh accepts it (review N4)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review N4 (minor, source-defect, fails closed). The gitea token binding (rc_gitea_binding, used by scripts/release/tag_and_release.sh and scripts/release_publish_gitea.sh) skips a line with fewer than four TABs, while scripts/forge/forge.sh reads the same table with IFS=$'\t' read -r h p a t _note and accepts a row without the note column. A gitea row with no note (or a CRLF row ending in the token column) makes the release tools refuse with 'no gitea row' (exit 2/3) while forge.sh accepts it (reviewer probes T1, T3 in /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/probe_binding.txt). No token is misrouted; parser and message divergence only. Scope: the binding helper and its tests. Reproduction: host fixture by the reviewer (probe file above); not re-run by the lander. Acceptance: one shared parser, or 3-TAB rows (and CRLF) accepted identically by both readers; RED cases T1 and T3 first; paired mutant. Parent: CON-515. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-531 — render_release_entry.py verdict-word match is a prefix match: 'PASS-FULL<TAB>WITH-KNOWN' and other separators render as bare PASS-FULL (review N5, carried F1)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review N5 (minor, source-defect), extending the prior review's F1 (fu_plan row FU-RM-F1, /mnt/DATA1TB/claude-work/scratch/fu_plan_20261117_101442/fu_plan.tsv sha256 3fdea5fc1a4d22eeca8b1275c186d7af11d8b7ebd657b1f1ba0d7ffde1e05237): the retest verdict word is accepted when the next character is anything outside [\w-] (TAB, U+2013, '/', '.'), so 'PASS-FULL<TAB>WITH-KNOWN' renders as bare PASS-FULL (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/probe_render.txt). Scope: scripts/release/render_release_entry.py and its tests. Reproduction: host fixture by the reviewer; not re-run by the lander. Acceptance: whole-token match (the verdict word followed by end of line or a single space and text), RED cases for the TAB and lookalike separators first; paired mutant. Parent: CON-514. Related: CON-421. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-532 — render_release_entry.py lets one-word lower-case angle tokens (<sha>, <todo>, <date>) and lookalike placeholders render rc 0, also inside retest_statement (review N6, carried F2)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review N6 (minor, source-defect), part of the prior review's F2 (fu_plan row FU-RM-F2, /mnt/DATA1TB/claude-work/scratch/fu_plan_20261117_101442/fu_plan.tsv) and the renderer's documented limit: one-word lower-case angle tokens (<sha>, <todo>, <date>, 'PASS-FULL on base <sha>') and the F2 lookalikes (Cyrillic DRAFT, ZWSP, _DRAFT_, fullwidth <CON-NNN>, &lt;CON-NNN&gt;, padded cut_date) render with rc 0 (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/probe_render.txt). Scope: scripts/release/render_release_entry.py and its tests. Reproduction: host fixture by the reviewers; not re-run by the lander. Acceptance: an allowlist of the accepted angle forms (autolinks, the documented HTML subset) with every other angle token and the listed lookalikes refused (exit 3) unless --draft; RED cases first; paired mutants. Parent: CON-513. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-533 — render_release_entry.py: a retest_statement starting with a blank line renders the verdict word on the next line (review N8)

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Created-By:** AI

What: review N8 (nit, source-defect, cosmetic). A retest_statement whose first line is blank renders as 'retest:  ' followed by the verdict word on the next line (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/probe_render.txt). Scope: scripts/release/render_release_entry.py. Reproduction: host fixture by the reviewer; not re-run by the lander. Acceptance: leading blank lines refused or stripped, with a case. Parent: CON-514. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-534 — CON-515 follow-up (carried review F5): rc_gitea_binding accepts loopback look-alike forms for the loopback test token at library level (callers refuse first)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: carried F5 of the prior release-machinery review (nit, test-instrumentation; fu_plan row FU-RM-F5, /mnt/DATA1TB/claude-work/scratch/fu_plan_20261117_101442/fu_plan.tsv; prior mutant RV6): the binding helper accepts three loopback look-alike forms for the loopback test-token variable; its callers refuse them first, so no token is misrouted. Still open after this landing per /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md section 7. Scope: the binding helper's tests. Acceptance: the helper refuses the look-alike forms itself, with cases; RV6 killed. Parent: CON-515. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-535 — CON-513 follow-up (carried review F8): UNCONFIRMED-CUT-DATE in a field other than cut_date is not tested (prior mutant RV2 survives)

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: carried F8 of the prior release-machinery review (nit, test-instrumentation; fu_plan row FU-RM-F8, /mnt/DATA1TB/claude-work/scratch/fu_plan_20261117_101442/fu_plan.tsv): no case puts UNCONFIRMED-CUT-DATE in a manual key other than cut_date, so the prior reviewer's mutant RV2 survives. Still open after this landing per /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md section 7. Scope: tests/release/test_render_release_entry.sh. Acceptance: such a case expects exit 3 (renders with --draft); RV2 killed. Parent: CON-513. Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

## CON-536 — test environment note: test_redact_cut.sh K8 N1 reports BLIND under bwrap --unshare-net because ssh -G rejects root-owned config files seen as the overflow uid

**Status:** Queued
**Type:** Task
**Severity:** Low
**Created-By:** AI

What: test-environment note (minor; not a defect of the code under test). Under bwrap --unshare-net, tests/release/test_redact_cut.sh gives 434/1 with K8 N1 BLIND, on the base ebd8818c as well (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/base_redact_nonet.txt) and 435/0 with host network (/mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/ev/base_redact_hostnet.txt). Root cause reproduced by the reviewer: inside the bwrap user namespace ssh -G exits 255 with 'Bad owner or permissions on /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf' (root-owned files show as the overflow uid); ssh -G -F /dev/null prints the needle. The instrument correctly fails closed. Reproduction: reproduced on the host fixture by the reviewer; not re-run by the lander. Acceptance: either the test runs ssh -G against a controlled config (-F) where the system config is not under test, or the sandbox limit is documented in the test's guide with the expected BLIND; no change to the BLIND-is-never-PASS rule. Related: CON-362 (K8 N2, a different case). Source: independent review /mnt/DATA1TB/claude-work/scratch/rev_relmach_safe.CFVOB2/REVIEW.md (outside the repository; sha256 32480bf84cf64d245c75f800d7d4f2b34c0c450d66a5bb8caee0de4bf9982522; directory SHA256SUMS sha256 32fbefc36b0bf9675f83c9ffc93b45e5d4f75d1626907c6ff3eb4956ebf6f956, verified by the lander 2026-11-17), verdict GO-with-follow-ups of the release-machinery safe subset (B-M1 87d61ba4, B-M4 87923dc6, B-M2 85f4e880), landed on main by merge e1dab6f8. Follow-up per section 11.4.276(G.2); evidence class gate-logic (section 11.4.289); not re-run by the lander.

