# CON-031 excluded list: plan (2026-11-05)

> Archived 2026-11-05 at the landing of vehicle/con031-excluded on main, copied unchanged from the session scratchpad except for bracketed corrections marked "corrected at landing". Local scratch paths in the text are not part of the repository. Item ids in this file are the vehicle ids; on main they are: CON-064/CON-070 -> CON-083, CON-065/CON-071 -> CON-084, CON-066/CON-072 -> CON-085, CON-067/CON-073 -> CON-086; follow-ups FU-1 -> CON-087, FU-2 -> CON-088, FU-3 -> CON-089, FU-4 -> CON-090, X2 -> CON-091.

Source of every fact below: `excluded_analysis.md` in the same directory. The vehicle is
`vehicle/con031-excluded`, delivered as `excluded_vehicle.bundle` (base: main ecfe432, merged; not pushed).
"Operator" marks a judgement call this investigation does not make. Effort: S = under an hour,
M = a few hours, L = a day or more.

## Quality bar

No row loses coverage in any step below. The heavy tier is not a loss: only `--include-heavy` exit 0
counts as the §11.4.40 full retest, so a file exercised only by heavy units is still exercised by every full
retest. Every step that changes code is RED-first and keeps its paired mutation.

## Ordered work

| # | Step | State | Effort | Risk | Who |
|---|---|---|---|---|---|
| 1 | Independent review (§11.4.209, Opus at xhigh) of the vehicle's code commits: 4db86ed6 (new `test_parse_mutation.sh`, 9 mutants), 322c25ef (refusal order in `capture_fc_timer_triplet.sh`), 485c341d (27 manifest rows + 13 notes), 2595f06e (merge), 35e8d53f (tracker re-mint + docs/qa evidence), cd1e55ee (three note corrections) | done in the vehicle, not reviewed | S | low: one test added, one block moved, data rows | reviewer |
| 2 | Land the vehicle on main fast-forward after GO (merge main again first if it moved) | waiting for 1 | S | low | conductor |
| 3 | **Operator**: accept the excluded-set change once 2 has landed: `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <roster id>`. It adds 2 rows (`check_safepath_census.py`, `foreign_uid_cause.sh`) and accepts 13 changed notes; the diff is printed by `--verify-manifest`. Not run by this investigation, as instructed | waiting for 2 | S | none: the tool refuses while any other manifest problem exists | operator (O1) |
| 4 | CON-073 root cause: a seam that refuses a census file landing without a manifest row. Proposed: a pre-build gate that runs the manifest check without the lock comparison and FAILs on "census file without manifest row", plus a paired mutation (add an unlisted `test_*.sh` → FAIL). Without it the gap returns: main went from 0 to 26 missing rows unnoticed | not started; tracked CON-073 | M | low | next work item |
| 5 | CON-072: fix the parse_mutation trailing-quote description (the toggled regex in `docs/qa/con072_*` removes the signature), add the case and a mutant to `test_parse_mutation.sh`. Before landing, regenerate the catalog `scan.py` produces and review every description that changes | not started; tracked CON-072 | S | low to medium: generated catalog text changes | next work item |
| 6 | **Operator**: the codegraph tests (`test_codegraph_mcp.sh`, `test_mcp_readonly.sh` exit 2 BLIND; `run_scope_tests.sh` exit 3) need the npm-global codegraph package and `CODEGRAPH_RUNNER_DIST`. The full-suite runner judges exit 2 and 3 as FAIL. See O3 | measurement with the full PATH: see the trace section of the analysis | S to M | medium | operator (O3) |
| 7 | **Operator**: the orphan reference copies `scripts/fastcycle/lib/dec23_key_ref.py` and `scripts/fastcycle/lib/tce_normalize_ref.py`. See O2 | investigated, not changed | S | low | operator (O2) |
| 8 | **Operator**: default-tier override for heavy-named tests that are fast. See O4 | measured times: see O4 | S | low | operator (O4) |
| 8b | CON-006 (already tracked): several default fastcycle RED tests read consumer files three levels up (`specs/004-fast-dev-cycles/contracts/`, `scripts/testing/...`) and FAIL in every standalone clone; this removes the default coverage of oracles #12, 13, 16, 17 there (visible as FAIL, not silent). Fix belongs to CON-006, which should list these read-side cases | linked, not re-minted | M | low | CON-006 owner |
| 8c | Measurements not finished: `test_check_deps.sh` without strace, `test_gen_lumenignore.sh` with `LUMEN_BIN`, the codegraph tests with the full PATH, the remaining traced units, the heavy-unit timings for O4, and `tests/layout/test_hermetic_generator.sh` in the wave-2 copy | stopped at the coordinator's request | S each | none | next session |
| 9 | Wave 2: when the ownership wave-2 vehicle lands, its new excluded row `tests/layout/hermetic_lint.py` (not in its lock) needs the same acceptance as step 3 | waiting for wave 2 | S | none | operator (O1) |

## Operator decisions, each with a recommendation

**O1. Accept the lock changes (steps 3 and 9).** Recommendation: accept after reading the printed
diff. Every added row and changed note is listed with its evidence in the analysis table. The two added
rows are tools a default unit runs; none of the 13 note changes removes a file from any runnable unit.

**O2. The orphan copies under `scripts/fastcycle/lib/`.** Facts: both landed in a925a8da (2026-09-30),
two days after the copies the test uses (`scripts/fastcycle/tests/lib/`, e41f3b27, 2026-09-28). Their
logic differs (the docstring-stripped AST hashes differ), not only the comments. Nothing loads them: the
only test that uses a reference copy reads `$HERE/lib/...`, which is `tests/lib`. Their only other mention
is a file hash in `progressive/EVIDENCE/PREFLIGHT_MANIFEST.json`. The manifest has no row for them,
because the census does not match their names. Options: (a) retire them as obsolete (§11.4.90; git
history keeps them); (b) review both versions, and if the newer one is the correct oracle, point the
test at it and retire the older copy; (c) keep both and document why. Recommendation: (b) first, then (a)
for whichever copy loses. Two divergent oracles for one formula is exactly the §11.4.251 fork drift, and
the one being validated today is the older one. §11.4.122 and §11.4.124 apply: no deletion without your
decision.

**O3. Codegraph tests on a host without the npm codegraph package.** Facts: without the package the
tests stop at "BLIND: cannot resolve stock package source" (exit 2) or "runner lib/dist not found"
(exit 3), and `test_gen_lumenignore.sh` prints "SKIP: lumen binary not found" but exits 2. The runner's `judge()` maps exit 77 to SKIP and any other non-zero exit to FAIL. The §11.4.69
closed SKIP set has no "tool not installed" code. Options: (a) keep it as it is: the tests FAIL on such a
host, which treats the package as a mandatory host prerequisite (§11.4.78 makes the CodeGraph index
mandatory); write that prerequisite into the runner guide and into the runner's preflight, so the FAIL
names its cause; (b) exit 77 with an existing code (`topology_unsupported` is the closest, but it is not
exact); (c) add a code to the §11.4.69 closed set (a constitution amendment). Recommendation: (a). It
keeps the strictest reading and loses no quality; (b) would misstate the reason, and (c) is not worth an
amendment for one tool. Which runs on a host WITH the package: see the trace section.

**O4. Default-tier override for fast heavy-named tests.** The tier is decided by the name (`mutation`,
`mutant`, ...) unless the row says `override:`. A test that only carries the word because of what it
tests, and runs in seconds, can move to the default tier, so `run_full_suite.sh` without
`--include-heavy` also covers its files. The vehicle does this for one case (`test_parse_mutation.sh`,
4.7 s). Candidate times: NOT measured (the heavy runs were not reached); `test_parse_mutation.sh` (4.7 s) is the only measured case. Recommendation: override only where the
measured wall time is under 60 s on this host; leave genuine mutation sweeps heavy.

## Not done, and why

- No `--accept-excluded-change` was run (the task forbids it).
- Nothing was pushed. The vehicle exists only in the bundle and in the scratch clone.
- CON-072 and CON-073 are not fixed: both need review of their consequences (catalog text; a new gate).
- No file was deleted: the two orphan copies wait for O2.
