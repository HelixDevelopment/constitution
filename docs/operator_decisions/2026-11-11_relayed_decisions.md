# Relayed operator decisions, 2026-11-11

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-11 |
| Last modified | 2026-11-11T14:49:17Z |
| Status | active |
| Source | relayed operator decisions, 2026-11-11: the operator (milosvasic) answered interactive questions; the conductor relayed the answers in the operator's words of intent. Not verbatim. |
| Recorded by | lander subagent (Opus 5.5), fresh clone of `main` at `24bdca78` |
| Items changed | CON-030, CON-033, CON-046, CON-146, CON-147, CON-158, CON-172, CON-188, CON-211, CON-213, CON-226, CON-229, CON-235 |
| Items created | CON-237, CON-238, CON-239, CON-240 |

This record is the §11.4.66 decision record for the questions below. The answers were given by the
operator in an interactive session and relayed by the conductor; they are not quoted verbatim, and
where this record maps an answer to an item, the mapping is the lander's (marked UNCONFIRMED where
it was not stated).

## Decisions

### 1. Review rounds for CON-030, CON-033 and CON-046

For CON-030, CON-033 and CON-046, and for any vehicle that carries them, the standing per-item
decision (§11.4.276(E)(3)) is: rounds continue until GO; every round past `R_max` 5 MUST be a
STRUCTURAL round (a fresh fixer instance, a class-wide enumeration, ground truth re-derived); the
review bar is unchanged (§11.4.134). Note: review_cgs6 N6-3 observed that §11.4.276(G) caps an
extension at round 7 when a decision names the item; this record names the three items and states
"until GO" as the operator's answer. Whether it authorises rounds past 7 is the operator's reading
of his own answer and is UNCONFIRMED here.

### 2. CON-146, CON-147, CON-158 move to In progress

Their vehicles are in flight. Status set from Queued to In progress. No fix is claimed (§11.4.290).

### 3. CON-172 and CON-213 (codegraph writer default)

The 2026-11-06 relayed instruction ("investigate and fix on evidence") IS the §11.4.66 decision
that approves the registry-driven writer default of `codegraph_safe.sh` (CON-211: the writer
default follows the `fk_index_patch.py` registry default, `fkidx1,resolve1,resolve2`). The
operator confirmed this on 2026-11-11. Applied:

- CON-172 closed Obsolete, §11.4.90 reason `duplicate-of`, superseding item CON-211.
- CON-213 closed Completed: its work (link, then close CON-172 once the decision is confirmed) is
  done by this record.
- CON-211: a note records that its default change now has the decision it needed.

### 4. Release v73.4

- The release is a PROVISIONAL pre-release (§11.4.290(5)).
- The vasic-digital GitHub mirror answers 404 for the release API: skip that platform release and
  record the gap in the release entry (the `tag_and_release.sh` GAP path, exit 5).
- §11.4.271 waiver for the agent-roster QA: authoriser `milosvasic`, expiry 30 days from the date
  the waiver is recorded. Only the decision is recorded here. The waiver itself is recorded after
  the release work lands; it is NOT recorded by this record.
- Before tagging, retest on the final `main`: first the default tier, then `--include-heavy`; with
  `--allow-topology-gaps` the result is PARTIAL and is labelled PARTIAL.
- A consolidated CHANGELOG entry is written at the release. This resolves CON-188 N1 (whether the
  fix landing needs its own CHANGELOG entry): no separate entry; the release entry covers it.

### 5. CON-235 (symlinked excluded-set lock)

Fix = refuse (fail closed): `--accept-excluded-change` on a symlinked lock exits 3 and writes
nothing; test-first (§11.4.224), with a case in `tests/test_run_full_suite.sh` section 37 and a
paired mutant. The item stays Queued, ready to fix.

### 6. CON-033 / CON-046: excluded-lock rows, pin-gate hook, live checkout pull

- The operator authorised the agent to run `bash scripts/run_full_suite.sh --verify-manifest
  --accept-excluded-change <id>` for the CON-033 excluded-lock rows after the reviewer's GO
  (relayed). Mapping note: CON-033 on `main` is the ref-retirement task; the excluded-lock rows
  are presumably carried by its vehicle (UNCONFIRMED).
- After CON-046 has its GO and has landed, the install of the pin-gate pre-commit hook in the live
  checkout is authorised:
  `chmod +x scripts/hooks/pre-commit-submodule-pin-not-downgraded` and
  `ln -s ../../scripts/hooks/pre-commit-submodule-pin-not-downgraded .git/hooks/pre-commit`.
- A fast-forward-only pull of the live checkout is authorised once the landings have settled and
  the live tree is clean. Nothing in the live checkout was touched by this record.

### 7. G4-1, `vendor/` of undecidable ownership

Decision: allow and log. A `vendor/` tree whose ownership cannot be decided is treated as
third-party by default, and the classification is recorded in the evidence.

What the lander found (measured): the only G4-1 in the tracked tree and in the review files is
review_cgs4 G4-1 (full-suite runner, a Go module with a bare `vendor/` directory), already decided
fail-closed in review round 5 and on `main` (`scripts/full_suite/run_full_suite.py` near line
3321, `tests/test_run_full_suite_go.sh` case A14, `docs/guides/full_suite_runner_guide.md`). That
question is Go vendoring consistency, not ownership. No codegraph item or review naming G4-1 was
found (`git grep` of the tree and a query of the tracker DB; grep of `review_*.md` in both
session scratchpads). The decision implies a source change whose target is UNCONFIRMED, so it is
registered as CON-240 (Queued); no source was changed here.

### 8. Pull-request delivery mode

Delivery stays direct, fast-forward only (§11.4.288). No `config/delivery.conf` is created
(§11.4.297(A) mode stays `direct`).

### 9. New Queued items (Task, Low)

| Id | Subject |
|---|---|
| CON-237 | `tests/test_consumer_required_helper.sh` fails when run directly under dash (bash shebang; sources the bash library `scripts/lib/safe_rm.sh`: "Bad substitution"); decide fix or document |
| CON-238 | consumer-required helper L16: a NULL-only id register pinned as SKIP (review_cgs6 N6-2) |
| CON-239 | consumer-required helper L17: a leading-space id (` ATM-953`) pinned as SKIP, the non-conservative direction (review_cgs6 N6-2, CR6-2) |
| CON-240 | apply decision 7 (allow and log for `vendor/` of undecidable ownership) |

Source text for CON-238 and CON-239: review_cgs6.md in
`/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/`.
The helper test of CON-237 is not on `main` at `24bdca78` (it lives on the full-suite fix vehicle).

## What this record does not do

- It records no §11.4.271 waiver (decision 4 says the waiver is recorded later).
- It changes no source, no hook and nothing in the live checkout.
- It claims no fix, verification or release.
