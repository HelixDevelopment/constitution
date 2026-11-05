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

## CON-015 — env census F-EC1: jq detection false negatives (variable, ${X:-jq}, array, function, trailing pipe)

**Status:** Queued
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

## CON-016 — env census F-EC2: surviving mutants E1 (yq|gojq) and E5 ($'...' owner)

**Status:** Queued
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

