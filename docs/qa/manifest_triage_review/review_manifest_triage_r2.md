# Review round 2: manifest-triage vehicle, fix round 2

| Field | Value |
|---|---|
| Review | independent, §11.4.209 / §11.4.142, round 2 of max 5 (§11.4.276(G)) |
| Reviewed | bundle `manifest_triage_r2.bundle`, range `efe2cc6c..7560e0f8` (`vehicle/manifest-triage`) |
| Author report | `scratchpad/manifest_triage_fix_r2_report.md` |
| Round-1 review | `scratchpad/review_manifest_triage_r1.md` (F1 to F13) |
| Main used for the merge check | `1e0c9cbb` (CON-031 landed) |
| Sandbox | `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvmt2.m7T4md` (fresh clones; HOME and TMPDIR inside it) |
| Reviewer model | Opus (claude-opus-5-5). The effort is not reported on this dispatch path, so none is claimed |
| Not done | I did not run `--accept-excluded-change`. I did not land, push or touch the real checkout. Every mutant and layout change was restored, and `git status` is clean in every sandbox clone I changed |

## Verdict

**GO-with-follow-ups.** Every round-1 blocker I was asked to check (F1, F2, F4, F5, F6, F7, F8, F9) is closed. I confirmed each one with RED and GREEN runs of my own. Every new finding is minor-class under §11.4.276(G.2): each is a `test-instrumentation` or `process-doc` finding, and in every case I proved the protected behaviour with a live run of my own (§11.4.235(D)).

Two things must happen before the runner can run anything. Neither is something this vehicle can fix:

1. **The operator must accept the excluded lock (CON-031).** This is already needed on main itself. Main `1e0c9cbb` alone gives `MANIFEST-MISMATCH` (rc 3): CON-031 landed but the lock was not accepted. Until it is, nothing is planned or run on main or on the merge.
2. **The landing merge needs the resolutions in section 1.** In particular, take main's excluded row for `check_safepath_census.py`, and re-add CON-100..CON-109 through the engine, because `docs/workable_items.db` is a binary conflict.

## 1. Merge with main 1e0c9cbb (throwaway clone `merge_wt`, not committed)

`git merge 1e0c9cbb` on `7560e0f8` gives these conflicts:

| File | Conflict |
|---|---|
| `config/full_suite_manifest.tsv` | 4 hunks: `check_safepath_census.py` (vehicle: member of `test_fc_safepath_v4r12.sh`; main: excluded `tool`); the dec*/`foreign_uid_cause` note block; the `precheck_shellcheck` note; the wiring-ledger notes |
| `docs/Issues.md` | 3 hunks (tracker sections) |
| `docs/Issues_Summary.md` | 2 hunks |
| census line in the full-suite guide | conflicting census numbers |
| `docs/workable_items.db` | binary conflict |

How I resolved it in the sandbox:
- **Manifest:** main's side in every hunk, plus the vehicle-only row `scripts/fastcycle/tests/lib/consumer_required.sh`.
- **Guide:** regenerated with `--sync-guide`.
- **Tracker:** the ids do not collide. The vehicle DB has 90 items and main's has 89, with no id in common. At landing, take main's DB and re-add CON-100..CON-109 through the engine, then export. A binary DB cannot be merged as text.

Post-merge `--verify-manifest`, exact result: **rc 3, `RESULT: MANIFEST-MISMATCH (1 problem(s); nothing was run)`**. The one problem is the lock:
- added: `test_resolve1_count_hook.js`, `test_resolve1_drive.js`, `test_resolve1_equiv_real.js`, `test_resolve1_probe.js`, `test_resolve2_probe.js`, `check_safepath_census.py`, `lib/consumer_required.sh`, `lib/foreign_uid_cause.sh`
- removed: none
- notes changed (13): `parse_mutation.py`, `t_scope_fixture.py`, `mutation_reuse.py`, `dec07_key_ref.py`, `dec15_flake_ref.py`, `dec17_drift_ref.py`, `dec23_key_ref.py`, `guard_freshness_ref.py`, `render_keys_ref.py`, `shard_ref.py`, `tce_normalize_ref.py`, `cm_setup_prompt_latest_present.sh`, `mutation_harness.sh`

Census after the merge: `go/entry=5 js/excluded=5 py/entry=9 py/excluded=22 py/fixture=14 py/member=26 runall/entry=9 sh/entry=331 sh/excluded=25 sh/fixture=111 sh/member=294 total=851`.

For comparison, measured the same way:

| Tree | rc | Lock problem | total |
|---|---|---|---|
| Main `1e0c9cbb` alone | 3 | added `check_safepath_census.py` and `foreign_uid_cause.sh`; the same 13 notes changed | 847 (`js/entry=5`) |
| Vehicle alone | 3 | lock only | 850 |

So main already needs the lock acceptance. The merge adds six paths to the same pending acceptance (the 5 js files and `consumer_required.sh`). A single operator acceptance covers both. All three trees keep the manifest rows sorted (`LC_ALL=C sort -c`).

Plan check, read-only. I imported the runner and called `read_manifest` and `plan` while bypassing only the lock:

| Tree | Units | Run |
|---|---|---|
| Vehicle | 597 | 331 |
| Main | 600 | 334 |
| Merge | 598 | 332 |

On main the 5 js helpers are `entry` rows and are planned as units. The vehicle makes them excluded tools, which is the right class: they need arguments. In the vehicle and in the merge, `foreign_uid_cause.sh` and the js files are not units, because `plan()` skips excluded rows. Accepting the lock does not change `plan()`, so this holds once the lock is accepted. This answers the author's UNCONFIRMED point 1 with runtime evidence.

## 2. Round-1 blockers: my own RED and GREEN

| Id | RED (old code, same check) | GREEN (vehicle head) | Status |
|---|---|---|---|
| F1 POSIX root | Round-1 helper: helper test 17 pass / 20 fail; the dash legs false-SKIP | Helper test 37 / 0 under bash and dash, with a plain root, a root with a space, and a relative `$0`. All 24 converted tests: rc 77 under their own shebang shell, last line `reason=topology_unsupported`, judge `SKIP topology_unsupported`, no "Bad substitution". Positive layout (consumer data present) under dash and bash: no false SKIP (churn_rank ran 7/4, consumer_audit 71/5, io_trace 6/0 rc 0, render_keys 9/2, render_keys_wiring control needle PASS, consumer_enumerate ran until its timeout) | CLOSED |
| F2 effective path | Round-1: a stub override still gave rc 77 | timer_prebuild with a broken dependency: rc 1 (it ran). monday RED_MODE=0 with a broken mock: rc 1 (19/15). monday RED_MODE=1 with a broken mock: PASS (the mock is not used). pid_status, supervisor_wiring and balance_autoselect with a broken dependency: rc 1. A present but broken dependency gives FAIL, not SKIP or PASS | CLOSED |
| F7 superspec | Round-1 test with no submodules: rc 0 on a vacuous zero | Guard 7 / 0. Real submodules checked out: rc 0, pass=3. Gate blinded (exclusion row removed): rc 1, so the needle discriminates | CLOSED |
| F8 install upstream | Round-1 lib: 6 / 2. Main's lib fails both layouts with `src refspec main does not match` | `test_upstream_main` 8 / 0: in both layouts upstream `main` is the commit under test and the upstream HEAD is `main` | CLOSED |
| F9 reason code | Round-1 line `SKIP topology_unsupported:` (not parsed) | `topology_unsupported` is in the §11.4.69 closed set, and `judge()` returns `('SKIP','topology_unsupported')` | CLOSED |
| F4 / F5 / F6 | see below | see below | CLOSED |

**F4 / F5 / F6 detail.** The 7 new excluded rows are:
- 5 node tools, each with an `override: reason: tool:` note;
- `consumer_required.sh`, `helper`, "sourced by" a real sourcing test (the runner's shell model checks this);
- `foreign_uid_cause.sh`, `tool`.

The classes are correct. No real test is hidden (§11.4.27 / §11.4.289):
- none of the 7 is a self-contained test;
- the tests that use them (the 24 helper users, and the codegraph tests that drive the js tools) are still planned units.

Two minor notes on these rows:
- the `consumer_required.sh` note names 1 of the 24 sourcing tests (finding R2-8);
- `check_safepath_census.py` should take main's excluded `tool` row at landing (section 1).

The runner judges `PASS` for the helper test, `test_upstream_main`, the topology test and the real superspec test.

## 3. My own mutants (13; none written by the author)

| Id | Target | Mutation | Result |
|---|---|---|---|
| M1A | helper | `[ -e ]` to `[ -f ]` | **survives** the helper test (37/0) |
| M1C | helper | missing path returns 0 instead of exit 77 | killed (24 / 13) |
| M1G | helper | `for _fcr_p in "$@"` to `$*` | **survives** (37/0) |
| M2A | commit_stage | guard on the default path instead of `$REAL_COMMIT_ALL` | **survives** (37/0) |
| M2C | monday | `[ "$RED_MODE" = "1" ] && continue` to `!= "0"` | **survives** (37/0) |
| M2D | prebuild_tsv | guard on the default path instead of `$PREBUILD` | **survives** (37/0) |
| M7A | superspec test | fixture check `-f file` to `-d submodule dir` | killed (6 / 1) |
| M7B | superspec test | needle `($1>0)` to `($1>=0)` (always yes) | **survives** the topology guard (7/0) |
| M7C | superspec test | `[ "$F" -eq 0 ] \|\| exit 1` to exit 77 when a carrier is missing | **survives** the topology guard (7/0) |
| M8A | install lib | prefer the local `main` over HEAD | killed (6 / 2) |
| M8B | install lib | update-ref only when upstream has no main | killed (6 / 2) |
| M8C | install lib | `HEAD` to `HEAD~1` | killed (4 / 4) |
| M8D | install lib | upstream HEAD to the REPO's branch | killed (2 / 2) |

Killed: 6. Survived: 7.

For every survivor I proved the protected behaviour with a live run outside the guard test, so each is a guard-coverage gap (`test-instrumentation`), not an unproven fix (§11.4.235(D)):

| Survivor | Correct code, live | Mutant, live |
|---|---|---|
| M1A | directory arguments, absolute and relative, under bash and dash: rc 0, body runs; churn_rank in the consumer layout also needs a directory and ran | rc 77, false SKIP |
| M1G | an absolute path containing a space, under bash and dash: rc 0 | rc 77, false SKIP |
| M2A | layout with overrides set and the default path absent: rc 124 (it ran until its timeout) | rc 77 |
| M2D | `PREBUILD_SRC=<stub>`, consumer tests directory present, default file absent: rc 1 (the guard passed, the body ran, its control needle failed loudly on the stub) | rc 77 |
| M2C | `RED_MODE=2`: rc 77, honest SKIP, which matches the comment at line 139 | rc 1, a false FAIL. Inputs are documented as 0 or 1 only, hence severity nit |
| M7B | blinded gate with both submodules present: rc 1 | (the guard has no blinded layout) |
| M7C | superspec present, toolkit carrier hidden, gate blinded: rc 1 (`fail=2`) | rc 77, so a real failure is masked as SKIP |

## 4. Claim "the merge took main's pid_status / supervisor_wiring versions"

Confirmed. In the vehicle's merge `d64aa77a`, `scripts/multitrack/test_multitrack_sessions_pid_status.sh` and `test_multitrack_supervisor_wiring.sh` are byte-identical to main `efe2cc6c`.

Main's mock-reachability check (with the `MT_TEST_MOCK_CLAUDE` override) runs before the vehicle's round-1 rb05 lines would have run, so dropping those lines loses nothing functional. With a broken mock, both files FAIL (rc 1). On canon alone they SKIP.

The SKIP reason is main's `reason=rb05_mock_absent`. That code is **not** in the §11.4.69 closed set (finding R2-6, main-side, not this vehicle).

## 5. Tracker CON-100..CON-109 (read-only from the vehicle DB)

What is right:
- Types are sensible: Task for CON-100..103 and 105; Bug for 104 and 106..109.
- Status is `Queued` throughout.
- Every Bug carries reproduction `UNREPRODUCED` and investigation `not-started`. That is honest; none was reproduced in this round.
- Validate OK; the DB and the Markdown are in sync (author's evidence; the ids I read match).

Problems:
- `parent_atm_id` is empty on all ten. §11.4.276(G.2) wants follow-ups linked to their parent (R2-7).
- CON-106 and CON-107 each bundle 11 tests with possibly different causes (§11.4.148 slicing, §11.4.292 one reproduction per issue) (R2-7).
- The CON-108 title states the behaviour as fact ("fails ... where the tool is absent") while the item is UNREPRODUCED (§11.4.6) (R2-7).
- `created_by` is `Conductor`, but the author subagent created the rows (§11.4.104) (R2-7).

## 6. Roadmap-Item trailers (§11.4.293(A))

- The 14 round-1 commits (11 non-merge commits, 3 merges) carry no `Roadmap-Item:` trailer.
- The 6 round-2 commits `d64aa77a`..`2dc6c553` carry the placeholder `Roadmap-Item: manifest-triage (id pending registration)`.
- `7560e0f8` carries `Roadmap-Item: CON-031`. That fits: CON-031 is the operator item for the excluded-list acceptance.
- The vehicle has no Roadmap item of its own.

This is not fixable by rewriting history (§11.4.113). The remedy is to register a Roadmap item for the vehicle and record the commit-to-item mapping in the landing merge commit message (R2-9, process-doc).

## 7. Install suite on the vehicle head

(not recorded by the reviewer; the author ran the install suites: unit 220/0, detection 41/0, updater 110/0, e2e 31/0)

## 8. Findings

Every finding below is minor-class (§11.4.276(G.2)).

| Id | finding_layer | severity | Finding | Evidence |
|---|---|---|---|---|
| R2-1 | test-instrumentation | minor | The helper test has no directory case and no absolute-path-with-space case, so M1A and M1G survive | section 3; behaviour proven live |
| R2-2 | test-instrumentation | minor | The helper test part 2 pins the effective path for 2 of the 5 override callers. commit_stage, prebuild_tsv and metatest_r4 are unpinned (M2A, M2D survive). Monday's RED_MODE other than 0/1 is unpinned (M2C, nit) | section 3 |
| R2-3 | test-instrumentation | minor | The superspec topology guard has no blinded-gate layout (M7B survives) and no "real failure with a missing carrier" layout (M7C survives) | section 3 |
| R2-4 | test-instrumentation | minor | `test_multitrack_sessions_balance_autoselect.sh` is inconsistent with its siblings. With the project root present but no mock it is still FATAL 91, and it has no `MT_TEST_MOCK_CLAUDE` override | source read, plus a broken-dependency run (rc 1) |
| R2-5 | test-instrumentation | nit | The helper's `cd "$(dirname "$0")/..."` does not clear `CDPATH`. With `CDPATH` set and a relative `$0`, the root could resolve elsewhere. Found by reading, not run; the impact is UNCONFIRMED | source read |
| R2-6 | test-instrumentation (main-side) | minor | Main's `reason=rb05_mock_absent` (pid_status, supervisor_wiring, redpin_mutations) is not in the §11.4.69 closed set. The judge does not map it to a closed reason | §11.4.69 set, source read |
| R2-7 | process-doc | minor | Tracker: no parent links. CON-106 and CON-107 are bags of 11 tests. The CON-108 title asserts unreproduced behaviour. `created_by` is wrong | section 5 |
| R2-8 | process-doc | nit | The `consumer_required.sh` helper note names 1 of its 24 sourcing tests | manifest row |
| R2-9 | process-doc | minor | §11.4.293(A): 14 commits have no trailer, 6 have a placeholder, and the vehicle has no Roadmap item | section 6 |

Outside this vehicle, UNCONFIRMED, and not a finding of this round: in my constructed consumer layout, `test_render_keys_wiring_red.sh` (shebang sh) ends with `sync_all_markdown_exports.sh: 619: Syntax error` after its needle passes. The vehicle changed only the guard line of this test (+1). Whether the same thing happens in the real consumer layout is not checked.

## 9. Per-slice verdicts

| Slice | Verdict | Condition or follow-up |
|---|---|---|
| S1 manifest (rows, classes, census) | GO-with-follow-ups | Take main's excluded `check_safepath_census.py` row at landing; R2-8. Lock acceptance is the operator's act (CON-031) |
| S2 helper and fastcycle conversions (F1, F2, F9) | GO-with-follow-ups | R2-1, R2-2, R2-5 |
| S5 install fixture (F8) | GO-with-follow-ups | killed M8A..M8D |
| S7 multitrack (F2 monday, merge of pid_status / supervisor_wiring) | GO-with-follow-ups | R2-4, R2-6 (main-side) |
| S8 superspec exclusion (F7) | GO-with-follow-ups | R2-3 |
| S9 merges, tracker, trailers | GO-with-follow-ups | R2-7, R2-9; tracker re-add through the engine at landing |

## 10. Follow-up items to register (parent: the vehicle's Roadmap item, R2-9)

1. Helper test: add a directory case and an absolute-path-with-space case; pin commit_stage, prebuild_tsv and metatest_r4 effective paths; pin monday RED_MODE values (R2-1, R2-2). Kill M1A, M1G, M2A, M2C, M2D.
2. Superspec topology guard: add a blinded-gate layout and a "failure with a missing carrier" layout (R2-3). Kill M7B, M7C.
3. balance_autoselect: align it with its siblings (mock override, honest SKIP) (R2-4).
4. Main: map `rb05_mock_absent` to a §11.4.69 closed reason (`topology_unsupported`) (R2-6).
5. Tracker hygiene: add parent links to CON-100..109; split CON-106 and CON-107 per test or per cause; reword the CON-108 title; correct `created_by` (R2-7).
6. Clear `CDPATH` in the helper's root `cd` (R2-5).

## 11. Not checked (honest boundary)

- I did not run the full suite end to end. It cannot run until the lock is accepted.
- I did not reproduce CON-104..CON-109.
- I did not run the real consumer project. The consumer layouts I used were constructed in the sandbox.
- I did not review the round-1 items F3 and F10..F13 beyond checking that they are tracked (CON-100..105).
