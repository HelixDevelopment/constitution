# Jev S3/S4 round 7 (CON-299): structural round for the independent review of `eb29803b` (NO-GO: NF-1 to NF-3, T6-1, T6-2, observation O6-1, nits N6-a to N6-e)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | evidence (CON-299, In progress; no GO claimed) |
| Evidence class | gate-logic only (stub llmctl, stub curl, fixture records, a flock gate, tripwires; §11.4.289(C)(2)). Nothing here is live evidence. |

## Why there is a round 7

Round 6 ended without GO. `R_max` for this item is 5 (§11.4.276); the standing operator decision recorded on 2026-11-11
(review rounds past `R_max` continue until GO, each with a fresh structural fixer and a fresh reviewer) is the
§11.4.276(E)(3) operator decision for this item. This round was run by a fresh fixer as a structural round: the classes
the review named were re-derived from the code first (`inventory.md`: every row of the (C) contract table, every path
from a capacity read to `llmctl start`, every place a mark is cleared), then RED tests, then the fixes. The point fixes
of round 6 for NF-2 were replaced by ONE freshness rule (a generation counter plus the sha256 of the lease registry,
checked at the plan and again at the start mark).

Every run was hermetic: bwrap with the real home hidden, no network, its own pid namespace, `env -i`, a decoy `HOME`,
fake keys only, `JEV_HOSTED_PROBE=0`, `GIT_SSH_COMMAND=/bin/false`, and a guard directory first on PATH whose `llmctl`,
`claude-providers`, `curl` (except loopback), `ssh`, `gh`, `glab`, `systemctl`, `systemd-run`, `docker`, `podman`,
`scp` and `wget` refuse and record the call. No real `llmctl`, gateway, hosted endpoint, network or forge call was made,
and nothing was pushed. Races are replayed in a fixed order by the test seam `tests/jev/fixtures/bin-flockgate/flock`
(pause or SIGKILL one jev-place process at its N-th flock call) and the stub's `PLACE_CAP_GATE` (pause one capacity
call), never by sleeping. Paths: `<W>` is the scratch work directory, `<HOME>` the operator home.

## RED then GREEN

RED on the round-6 producer (`eb29803b`, `scripts/jev/jev-place.sh` sha256 `efb90416…`) with the FINAL round-7 test file,
GREEN on the final tree of this round (`0685ab31`; the producer is unchanged since commit 1):

| File | Round-6 producer (RED) | Round-7 producer (GREEN) |
|---|---|---|
| `tests/jev/test_s4_round7.sh` (157 rows) | pass 75 / fail 82 (rc 1) (`red_final_round7_on_r6.txt`) | pass 157 / fail 0 in pass A and in pass B |

Failing rows on the round-6 producer (FAIL lines per row): P72 46, P73 4, P74 2, P75 3, P75b 3, P76 1, P78 5, P79 1, P81a 1, P81c 1, P82 4, P82b 2, P84 2, P85 1, P87 1, P88 2, P89 1, P90 2. P73 and P74 show the review's NF-2 repro (two starts from one stale answer); the P72 rows show a contract field absent or of the wrong type that the round-6 producer accepted or did not name. P89 and P90 fail there only on their log-line assertions (round 6 had no reap floor and no re-plan to report); what they guard is shown by the mutant rows NM02 and NM07.
`red_round7_on_r6_earlier_test_version.txt` is the RED of an earlier version of the same file (70 / 77), kept for the
record: the version the mutants first ran against (snapshot `s2`), before the shellcheck clean-up of its helpers and
before the later mutant rows (P89, P90), the bounded waits and the stricter per-profile P72 needles were added (notes
below; `s2_vs_final_test_s4_round7.diff`).

## Commits of this round

| Commit | What |
|---|---|
| `8855e8b1` | the round-7 fixes, tests, inventory, docs and the two canon notes |
| `f8d36417` | a comment in the stub `llmctl` cited §11.4.277(E) without naming the llmctl validation anchor; `test_anchor_renumber_integrity.sh` failed in `run_all` of the first pass A (below); comment-only fix |
| `26893670` | FAQ question 23: a dated correction (the capacity source IS vendored now; revision 5) |
| `735d0069` | P89, a killing row for mutant NM02 (below). Correction: its commit message says NM02 survived every suite of the snapshot; at that time it had survived only the round-7 suite; it then survived the round-6 suite and was killed by the placement suite (P21) |
| `365f87dd` | the P89 header line states what P89 does on the round-6 producer (comment only) |
| `d62b42ac` | P90, a killing row for mutant NM07; `waitb` bounds all 17 waits on a background `jev-place` process; the per-profile P72 needles name the contract phrase (mutant NM14) (notes below) |
| `0685ab31` | the P72 host cases name the `host` row itself and a `host a string` case was added (mutant CT04, notes below); the P90 header states its round-6 result (comment) |
| this commit | this evidence pack and the CHANGELOG entry |

## Findings

| Finding | What changed | Closing tests | Mutants |
|---|---|---|---|
| NF-1 the (C) contract table | `capacity_read` checks every row of the canon table, held as data (`CONTRACT_TABLE`, 22 rows; the canon `host` row split into its named fields), plus llmctl's `measurement.critical_inputs_unreadable`; `inst_state` checks the per-profile fields; every check is wrapped in `try`. An absent field, a `null` where a value is required or a value of the wrong type makes the WHOLE answer `undetermined`, the reason names the field, nothing is started. The test field list is written from the canon table, not from the producer. | P72 (one absent and one wrong-type case per field, plus controls served raw and computed) | CT01 to CT22, NM10 to NM14, VM01 |
| NF-2 stale answer between plan and mark | ONE freshness rule: every registry write raises `gen`; the token is `"<gen>:<sha256 of leases.json>"`; the answer is read after an observation ticket that records it; seam 1 (`plan_locked`) and seam 2 (`mark_start_locked`) compare it; a stale answer is read again (at most 3 times, then joins and stops only), a stale mark re-plans (at most 3 times, then no start, `stale_answer`). A further start also needs the lease this acquire took. Every path from a capacity read to `llmctl start` is in `inventory.md`, class 2. | P73, P74, P75, P75b, P77, P81 (inventory property over the stub's call log), P82, P82b, P83, P86, P87, P88 | NM01 to NM07, NM15 to NM22, NM26, VM04, VM10, VM11, VM13, OM03 |
| NF-3 floor when reap clears a mark | `reap_locked` sets `health = {state: pending, seq: obs_counter}` when it clears a `starting` / `stopping` mark; `MARK_TTL` = start/stop timeout + 2 s + `JEV_RECORD_RETRIES` × `JEV_LOCK_TIMEOUT` + 30 s, so a live starter still waiting for its record lock keeps its mark. An acquire whose own reap changes the registry after its capacity read reads again, so its old ticket never judges the floored set. | P78, P79, P89 | NM02, NM08, NM09, VM06 |
| T6-1 VM01, VM06, VM07, VM13; VM10 | A killing row for each; VM10 is now the plan's freshness check (seam 1) and is killed. | P72 (VM01 row), P79, P80, P76, P77 | VM01, VM06, VM07, VM13, VM10 |
| T6-2 P5 timing | P5 waits for the stub's `cap.done` completion marker (written only by a capacity call that ran to its end) instead of a timing window; the marker has its own control row. | `test_s4_placement.sh` P5 | VM09 |
| O6-1 intermittent `test_review_fixes_r2.sh` P2 | Instrument, not a fix: on a P1/P2 failure the assertion prints `[bootstrap rc=N]`, the tail of the bootstrap's stderr, and the run's files are kept (`O6-1 evidence kept in …`). Root cause UNKNOWN (below). | `test_review_fixes_r2.sh` P1/P2; control run with the bootstrap forced to fail (`o61/control.txt`) | — |
| N6-a uppercase `HTTPS://` | NOT changed: a separate item by operator decision N1. Noted in the producer header and in the docs (the scheme is matched case-sensitively and fails closed). | — | — |
| N6-b `status` exit code | `status` with no placement record exits 0 and says "placement: none recorded yet". | P84 | NM25 |
| N6-c §11.4.282 note | The note gains the https-gateway condition (one appended sentence). | — | — |
| N6-e reason in the record | The placement record carries the specific reason of an undetermined or not-fitting candidate. | P85, P72 | NM23, NM24 |
| Found in round 7 | A further start without the lease this acquire took: round-6 P70 relied on the stopping mark alone and became timing-dependent under the round-7 rule. | P88, P70 (message) | NM19, NM20 |

## Mutants

93 mutants plus the unmodified control `REAL`: 3 equivalent, 90 killed; `REAL` survived every suite it was run against. Proven equivalent: RM09, OM13, NM04 (arguments in `mutants.md`). No mutant survived.

The table, the decisive rows and the equivalence arguments are in `mutants.md` (generated from `mutants/results.tsv`
and `mutants/index.tsv` by `tools/gen_mutants_md.py`); per-run outputs are `mutants/<ID>_<suite>.txt`. No mutant lane
created a guard log, so no mutant reached a real tool.

Notes on the runs:

- The mutants ran against a frozen copy of the tests (snapshot `s2`, taken before commit 1). The final test files
  differ from it in: helpers and messages (`wait_file` and `proc_start_of` rewritten for shellcheck, `A && B || C`
  turned into `if` in P5, P75b and P78; `proc_start_of` was checked to return the same value as the old form for `$$`,
  pid 1, the parent and an absent pid); and, in `test_s4_round7.sh` only, what the mutant runs below showed was
  missing: the rows P89 and P90, the `waitb` helper bounding all 17 waits on a background `jev-place` process, and the
  per-profile P72 needles (`s2_vs_final_test_s4_round7.diff`, `s2_vs_final_test_s4_placement.diff`). Those mutants
  were re-run on snapshot `s3` (the final test file) and its extracts; the producer is byte-identical throughout.
- Each mutant ran suite by suite and stopped at its first kill. The suite order of RM and OM mutants was changed during
  the run so the suite holding the round-6 killing row runs first (`mutants/index.before_reorder.tsv` is the order before;
  the change only saves time: RM01, RM02 and RM03 had already started and ran the round-7 suite first).
- `r7p72` is a P72-only extract of `test_s4_round7.sh` (`mutants/zz_r7_p72_only.sh`, present only in the snapshot), used
  as the first suite for the contract-table mutants so they are killed in seconds.
- NM02 (the plan's own reap changes the registry after the capacity read, and the plan goes on) survived the round-7
  and round-6 suites of `s2` (the placement suite killed it later, P21, by an indirect effect). P89 was written for it
  and committed (`735d0069`); snapshot `s3` was then the committed tests plus P89 (it later received the final test
  file), and NM02 and
  `REAL` were run on the P89-only extract `r7p89` (`mutants/zz_r7_p89_only.sh`): NM02 killed (rc 5 `refused_join`
  instead of joining), `REAL` survived. The same extract on the final producer passed 5 / 0 twice and on the round-6
  producer 4 / 1 (only the new log line is missing: round 6 set no floor at the reap, so its old answer still judged the
  set); `p89/`. P89 is a mutant row, not a RED row for a round-6 defect.
- NM05 (the generation is not raised) was first killed by the CONTROL row of P75b, which only checks that the scenario
  is the ABA the row needs. A control row alone is not a behaviour kill, so NM05 and `REAL` were also run on the whole
  P75b block without stopping at the first FAIL (`mutants/zz_r7_p75b_only.sh`, `p75b/`): `REAL` 7 / 0; NM05 4 / 3,
  failing the control row and both behaviour rows (B expected `0 decide-a placed`, got `0 decide-a joined_running`, the
  gone unit adopted; no unit runs afterwards). NM05 is a behaviour kill.
- NM07 (a refused or failed start is tried again by the same acquire) made that acquire loop: the round-7 suite of
  `s2` hung at P75b until the runner's 1800 s timeout (rc 124, killed, but by no named row). P90 was added for it
  (`d62b42ac`), and every wait on a background `jev-place` process in `test_s4_round7.sh` is now bounded (`waitb`,
  300 s), so a loop is a named FAIL there. On the P90 extract (`mutants/zz_r7_p90_only.sh`, `p90/`): the final
  producer 4 / 0; NM07 0 / 4, with 85 and 116 starts of one profile in 300 s (rc 124 from the row's own timeout); the
  round-6 producer 2 / 4, only the log line missing (it never re-planned after a failed start). P90 is a mutant row,
  not a RED row for a round-6 defect. The round-6 and placement suites keep unbounded waits on purpose (not changed
  by this round); each test there is bounded by `run_all`'s 600 s timeout.
- NM14 (the per-profile verdict type check removed) survived the P72 extract of `s2`: a number verdict was still
  undetermined, refused by the later closed-set check as "verdict outside the closed set". NF-1 promises the field is
  named by the contract check, so the per-profile P72 needles now require the contract phrase
  (`contract fields of profiles.decide-a missing or wrong: <field>`, `d62b42ac`); on the final P72 extract (`r7p72f`,
  `mutants/zz_r7_p72_only_final.sh`) NM14 is killed and `REAL` survives.
- CT04 (the contract-table row `host` removed) survived the P72 extract of `s2`. For the decision the row is implied
  by its nine field rows (a field of a host that is not an object is never a number), so its only effect is the
  reason: without it an absent host is reported as its nine fields, not as `host`. The P72 host cases now require the
  row itself, named before its first field (`host,host.cpus_online`), and a `host a string` case was added
  (`0685ab31`); on the final P72 extract CT04 is killed and `REAL` survives. `r7p72f` was run for `REAL` twice,
  before and after this needle; both survived. CT04 also survived the full round-7, round-6 and placement suites of
  `s2` (`results.tsv`), as expected for a reason-only change.

## Final checks

| Step | Pass A | Pass B |
|---|---|---|
| `run_all` | rc=0, 2763s, guard lines guard=101: `ran 37, failed 0` | rc=0, 2358s, guard lines guard=101: `ran 37, failed 0` |
| `gate_pairs_nokeys` | rc=0, 170s, guard lines guard=1: `[test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent)` | rc=0, 146s, guard lines guard=1: `[test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent)` |
| `gate_pairs_fakekeys` | rc=0, 183s, guard lines guard=1: `[test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent)` | rc=0, 133s, guard lines guard=1: `[test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent)` |
| `fake_key_values_in_output` | 0 | 0 |
| `gate_bootstrap_idempotent_mutation` | rc=0, 111s, guard lines guard=1: `[mutation:bootstrap] PASS: cm_jev_bootstrap_idempotent.sh genuinely discriminates (GREEN genuine / RED mutated)` | rc=0, 84s, guard lines guard=1: `[mutation:bootstrap] PASS: cm_jev_bootstrap_idempotent.sh genuinely discriminates (GREEN genuine / RED mutated)` |
| `gate_detection_mutation` | rc=0, 12s, guard lines guard=0: `[mutation:detection] PASS: cm_jev_detection.sh genuinely discriminates (GREEN genuine / RED mutated)` | rc=0, 9s, guard lines guard=0: `[mutation:detection] PASS: cm_jev_detection.sh genuinely discriminates (GREEN genuine / RED mutated)` |
| `gate_token_reduction_mutation` | rc=0, 3s, guard lines guard=0: `[mutation:token] PASS: cm_jev_token_reduction.sh genuinely discriminates (GREEN genuine / RED mutated)` | rc=0, 2s, guard lines guard=0: `[mutation:token] PASS: cm_jev_token_reduction.sh genuinely discriminates (GREEN genuine / RED mutated)` |
| `gate_wiring_mutation` | rc=0, 3s, guard lines guard=0: `[mutation:wiring] PASS: cm_jev_wiring.sh genuinely discriminates (GREEN genuine / RED mutated)` | rc=0, 3s, guard lines guard=0: `[mutation:wiring] PASS: cm_jev_wiring.sh genuinely discriminates (GREEN genuine / RED mutated)` |
| `test_s4_placement` | rc=0, 488s, guard lines guard=0: `# test_s4_placement.sh: pass=266 fail=0 skip=0` | rc=0, 414s, guard lines guard=0: `# test_s4_placement.sh: pass=266 fail=0 skip=0` |
| `test_s4_round6` | rc=0, 526s, guard lines guard=0: `# test_s4_round6.sh: pass=183 fail=0 skip=0` | rc=0, 431s, guard lines guard=0: `# test_s4_round6.sh: pass=183 fail=0 skip=0` |
| `test_s4_round7` | rc=0, 429s, guard lines guard=0: `# test_s4_round7.sh: pass=157 fail=0 skip=0` | rc=0, 310s, guard lines guard=0: `# test_s4_round7.sh: pass=157 fail=0 skip=0` |
| `test_review_fixes_r2` | rc=0, 24s, guard lines guard=0: `# test_review_fixes_r2.sh: pass=51 fail=0 skip=0` | rc=0, 20s, guard lines guard=0: `# test_review_fixes_r2.sh: pass=51 fail=0 skip=0` |
| `test_jev_status_health` | rc=0, 11s, guard lines guard=0: `# test_jev_status_health.sh: pass=110 fail=0 skip=0` | rc=0, 7s, guard lines guard=0: `# test_jev_status_health.sh: pass=110 fail=0 skip=0` |
| `test_tab_fields` | rc=0, 9s, guard lines guard=0: `# test_tab_fields.sh: pass=15 fail=0 skip=0` | rc=0, 5s, guard lines guard=0: `# test_tab_fields.sh: pass=15 fail=0 skip=0` |
| `test_no_real_tools` | rc=0, 174s, guard lines guard=1: `# test_no_real_tools.sh: pass=11 fail=0 skip=0` | rc=0, 135s, guard lines guard=1: `# test_no_real_tools.sh: pass=11 fail=0 skip=0` |

Tree fingerprint (HEAD and sha256 of `git status --porcelain --untracked-files=all`), identical before and after each pass: A `0685ab31499148081f6e07bbc81ec8ee25853435 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  -`, B `0685ab31499148081f6e07bbc81ec8ee25853435 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  -`. Every guard line is a `curl` the guard allowed: a request to a fixture server on 127.0.0.1, or `curl --version` (6 lines in each pass); no refused call was recorded, and the runs had no network.

A first pass A on commit `8855e8b1` was stopped after `run_all` reported "ran 37, failed 1": `test_anchor_renumber_integrity.sh` (pass 15 / fail 1) flagged the new stub comment that cited §11.4.277(E) without its llmctl meaning (`suites/aborted_passA_commit1/`, `checks/anchor_red_commit1.txt`). The suites run one by one before commit 1 did not include every test of `run_all`; that gap is why it was found only there. After the comment-only fix `f8d36417` the test passes 16 / 0 (`checks/anchor_green_fix.txt`) and both final passes ran on the final tree.

Static checks on the final tree (`checks/`): verify_manifest	rc=0	guard=0	RESULT: MANIFEST-OK
cm_constitution_index_fresh	rc=0	guard=0	CM-CONSTITUTION-INDEX-FRESH: PASS -- the index and groups match a fresh generation from Constitution.md
cm_gate_ledger_ratchet	rc=0	guard=0	✅ CM-GATE-LEDGER-RATCHET: PASS — every named CM-* gate is implemented-or-deferred within the checked-in monotone-decrease baseline; no uncited vanished name
cm_covenant_114_282_propagation	rc=0	guard=0	✅ CM-COVENANT-114-282-PROPAGATION: PASS — every owned carrier carries exactly one byte-identical §11.4.282 block
cm_covenant_114_282_propagation_mutation_test	rc=0	guard=0	======================================================================
cm_covenant_114_291_propagation	rc=0	guard=0	✅ CM-COVENANT-114-291-PROPAGATION: PASS — every owned carrier carries exactly one byte-identical §11.4.291 block
cm_covenant_114_291_propagation_mutation_test	rc=0	guard=0	======================================================================
shellcheck_delta	rc=0	-	1 files with a new code vs round 6
STATIC_DONE post

## Canon notes flagged for the independent review

The two round-6 refinement notes each gain one appended sentence (no other byte of `Constitution.md` changed;
`checks/constitution_diff.txt`; the Revision header is unchanged, 96, for the lander):

- §11.4.282 (N6-c): the `llmctl-local` entry also requires a recorded `https://` gateway object in the lease registry;
  the scheme is matched case-sensitively, so `HTTPS://` is refused, fail-closed (a separate item, N6-a).
- §11.4.291 (NF-1 to NF-3): the producer checks every row of the (C) contract table and llmctl's
  `measurement.critical_inputs_unreadable`; a start is decided only on a capacity answer read after the last change of
  the lease registry; a reap that clears a mark sets the pending-health floor.

`constitution_index.yaml` and two `groups/*.md` files were regenerated (`cm_constitution_index_fresh.sh` PASS).

## O6-1: what was done, and what is still unknown

The reviewer saw `test_review_fixes_r2.sh` P2 fail once in five runs (`expected [1] got [X]`: no parseable
`jev-detection.json` after `bootstrap.sh --non-interactive`), in a `run_all` pass, and could not reproduce it. Round 7:

- Instrument: P1 and P2 now print the bootstrap's exit code and the tail of its stderr, and keep the run's files. A
  control run with the bootstrap forced to exit 3 before it writes the record shows the instrument working
  (`o61/control.txt`, `o61/control_kept/`).
- Repetitions: 12 standalone runs of `test_review_fixes_r2.sh` under the shared scope at load 33 to 37: 12 of 12 passed 51 / 0 (`o61/loop/summary.tsv`); it also passed inside `run_all` of the stopped first pass A and of both final passes. No failure was seen, so the instrument has nothing to show yet.
- Ruled out by reading the code: cross-test state (each case gets a fresh `HOME` and temp dir from
  `make_fixture_env`); background jobs in the bootstrap (none); an unguarded `SIGPIPE` pipeline (none).
- Hypotheses still open (UNKNOWN which, if either): H1, a `manifest_field` / python failure makes the bootstrap exit 2
  before the detection record is written (`set -euo pipefail`, `|| exit 2`); H3, process or fork exhaustion in a shared
  `TasksMax` scope (the reviewer's pass ran next to mutant lanes) makes `jq` or the bootstrap fail. The next failure
  under the instrument will show the exit code and stderr and decide between them.

## Deviations from the canon wording

Unchanged from round 6 and still disclosed (`inventory.md`): disposal of a lease-less owned set instead of silent
removal; the non-canon reason code `endpoint_starting`; the placement entry is merged only into an existing detection
record; a failed start that could not be recorded returns 4 and may leave a lease; the (D) cadence, the drain before the
last stop and the (D)(2) hold window are not built; no session calls `acquire` / `heartbeat` / `release` today. New in
round 7: the reason code `stale_answer` (not in the canon list).

## Not done / UNCONFIRMED

- Nothing live: no real `llmctl`, gateway, hosted endpoint, device or model ran. Every result here is gate-logic class
  (§11.4.289(C)(2)); the decision layer's status stays "gate logic proven, behaviour not live-proven".
- The NF-2 window under real load is proven only on the replayed orders the flock gate produces; the window between the
  mark and `llmctl start` still exists (llmctl is never called under the lease lock); a second session reading in it sees
  the `starting` mark.
- A model started OUTSIDE the lease registry (an operator `llmctl start`, another tool) changes the host without changing
  the token; only llmctl's own start gate (exit 75 under pressure) covers that case.
- O6-1 root cause UNKNOWN (above).
- N6-a (`HTTPS://` refused) is not changed; it is a separate item.
- No session calls `acquire`, `heartbeat` or `release` today; the §11.4.291(D) cadence, the drain before the last stop
  and the (D)(2) hold window are not built.
- `helix-deps.yaml` records llmctl `ref: 3877467` while the gitlink is `391d8177`; this is so at the base `02c10935`
  already, outside this item, and whether the two name the same commit is UNCONFIRMED (the submodule is not checked out
  in the vehicle clone). Not touched.
- The commit trailers use the placeholder `Roadmap-Item: CON-PENDING-JEV`; the lander sets the real item id.
- The `Co-Authored-By` trailer names Claude Sonnet 5.5 because the dispatch brief prescribed it; the fixer that wrote
  these commits ran as Claude Opus 5.5 (reasoning effort not readable on this path, §11.4.231(F.2)). The lander decides
  which trailer to keep.
- The two canon notes need the independent review before they are accepted.
