# Independent review: tracker-intake vehicle (head 1a307322 on base 02c10935)

Reviewer: fresh independent subagent, Opus 5.5 (effort not settable or readable on this dispatch path; §11.4.231(F.2), so no effort is claimed). Live checkout untouched. Work dir: `revti.9LAo/` under the scratchpad, clone named `constitution`, built from `secr3.UYVh/c` (02c10935 is an ancestor; checked) plus the bundle. Engine built from the head tree (`go build ./cmd/workable-items`). Everything ran with nice 10, one step at a time.

## Verdict: NO-GO (two important data findings, both cheap to fix through the engine)

The intake work is careful and nearly correct. Two shipped tracker facts are wrong: one is a §11.4.214 duplicate, one is an invented cross-reference. The vehicle's product is tracker data, so I class both as `source-defect` / important rather than as minor-class `process-doc`. Each one is a single `update` call (or a lander decision at re-mint time). After that, every remaining finding is minor-class, and GO-with-follow-ups would apply.

## Checks run (captured output)

| Check | Result |
|---|---|
| bundle sha256 | `c8ac1d871a69…9eed`, matches. `git bundle verify` okay, requires 02c10935, head 1a3073229cf0 |
| commit shape | one commit, parent 02c10935; touches only docs/Issues.md, docs/Issues_Summary.md, docs/workable_items.db |
| `validate` head DB (from repo root) | `OK — 298 items` (base: 263) |
| `diff --issues --fixed` | `in sync (298 vs 298)` |
| `sync db-to-md` regeneration | Issues.md and Fixed.md byte-identical to the committed files |
| `run_full_suite.sh --verify-manifest` | `total=901 … RESULT: MANIFEST-OK` |
| engine provenance | item_history ids 510–544: one `Opened` row per CON-299..CON-333; 545–546: two `Updated` rows for CON-046. No other base row changed (column-by-column join of base and head: only CON-046 differs; 0 base rows missing) |
| Status/Type | all 35 are `Queued`; Types Task ×33, Bug ×2 (CON-308, CON-311), all inside the closed sets |
| §11.4.148 sections | all 35 carry What / Affected scope / Reproduction / Acceptance / Parent-links (SQL check, 0 missing) |
| minted TSV | ids and titles identical to the DB (`diff` empty) |
| CON-300 verbatim | no invented quote. The text matches the memory file `project_order_sync_all_upstreams_2026_11_12.md` word for word and says the verbatim original is UNKNOWN (only the relayed form exists) |
| CON-331/332/333 | match the memory file `project_operator_decisions_2026_11_12_night.md` |
| GitLab / retest / multiforge items | severities, classes, mutant ids and counts checked against review_gitlab_prerelease.md (+ its mutants file: 8 survivors, M19 pre-existing) and review_retest_items.md F1–F8: faithful |
| CON-046 restore | the head text equals the vehicle 7bdffcf6 DB text byte for byte, with three paragraphs appended: main's decision 1 and decision 6 (identical to main's Issues.md body) and a restore note. body_md carries both |
| CON-333 secrets | 0 hits for ghp_/github_pat_/AKIA/AIza/eyJ…/BEGIN/hf_ in the full diff (negative control: the pattern does match a planted `AIza`). 0 of the 1059 unique scan paths appear in the diff (positive needle: one path appended to a copy of the diff is found) |
| fix227 collision | fix227 r9 DB uses CON-300..CON-311 for unrelated items (checked). The collision is stated in the commit body, CON-299, CON-329 and CON-330 |

## Findings

| # | Severity | finding_layer | Finding |
|---|---|---|---|
| I1 | important | source-defect (tracker data, §11.4.214) | **CON-308 duplicates two open items.** Both CON-243 ("run_all.sh counts the new exit 77 … as FAIL") and CON-262 ("… run_all.sh labels exit 77 FAIL") already describe the same defect in the same file. Under §11.4.214 an open match gets a link only, never a new id. CON-308 links neither (it cites CON-092 and CON-098). Fix: do not mint CON-308. Instead, append the retest-lander C-2 context to CON-262 (or CON-243) through `update`. Or close CON-308 as `duplicate-of` CON-262 and link it. |
| I2 | important | source-defect (invented fact) | **CON-300 and CON-332 cite "CON-296 (GitHub issues sync)".** CON-296 on main is "full-suite runner self-test oracle shares the engine formula…". The GitHub-issues rule is anchor §11.4.296, not an item, so the anchor number was mistaken for an item id. Fix: replace the link with "§11.4.296 (anchor)" or remove it. |
| I3 | minor | process-doc (§11.4.294) | The Bugs CON-308 and CON-311 state reproduction/investigation states in prose ("UNREPRODUCED"; "reproduced-host-fixture once … Investigation: in-progress"), but their DB columns are `UNSET`/`UNSET`. §11.4.294(A) makes the column the source. A `reproduced-host-fixture` state also needs an evidence path and sha256 (§11.4.294(C)), and CON-311 has neither. Fix: set the columns with `update --reproduction-state …` and add evidence, or reword the prose to "not assessed". |
| I4 | minor | process-doc | CON-299 says the children "are listed in the tracker history of each item as 'Umbrella: <this id>'". History rows 510–544 have an empty reason field; the link lives only in each child's description. The sentence is false. |
| I5 | minor | process-doc | CON-333 mixes two units without naming them. "1082 rows" are unique (repo, kind, path) rows. The per-repository "hit counts" come from the raw per-repo scan files (they sum to 2216; sftp shows 1922 hits against 991 unique rows). The item also names a session-scratchpad path as the only record of per-file paths and SKIPPED.tsv, and that path is lost when the scratchpad is cleaned. Fix: name both units, and record where the operator's copy will live. |
| I6 | nit | process-doc | CON-306 and CON-309 are instances of the CON-092 class (skip per section, not the whole test), and CON-309 says so itself. They link CON-092 only as "related". A §11.4.214 candidate-duplicate or parent link would keep the class in one place. Classing them DISTINCT is defensible, because CON-092 covers the 24 consumer_required.sh tests and these use the new probe. |
| I7 | nit | process-doc | The Issues_Summary.md row for CON-046 is now 6460 bytes, because the summary generator prints the whole restored description. That hurts §11.4.91 readability, but it is generator behaviour, not this vehicle's. |
| I8 | nit | process-doc | CON-299 says it registers "the operator decisions of 2026-11-12 23:30". Three of those seven decisions are not tracked: Jev `CMA_JEV_PREFER` "until toolkit failover fix lands" (no item for the owed failover fix; 0 hits on main), orphan reaping, and disk prunes. The last two are one-off operations, but the failover fix is owed work. |
| I9 | nit | (engine, pre-existing) | `crud.go:176` hard-codes `Opened` by `User`, so the 35 history rows say User while `created_by` says Conductor. |

Collision note for the lander: re-minting CON-300..CON-311 (and possibly CON-299) also means rewriting "umbrella CON-299" in the 34 children, the CON-046 restore note, and the cross-references in CON-329/CON-330. The vehicle discloses this, but it is a mechanical text rewrite that `update` has to do item by item.

## Reviewer-authored mutants (12; run on scratch copies, never on the vehicle DB)

| # | Mutant | Detector | Caught? |
|---|---|---|---|
| M1 | duplicate CON-310 heading in Issues.md | `diff` | yes (rc 1, body differs, 299 vs 298) |
| M1b | same, then `sync md-to-db` | engine | yes (UNIQUE constraint) |
| M2 | drop CON-313's UNKNOWN gap, invent a path (description column) | `validate` / `diff` / regen | **no** (validate OK, diff in sync, regen identical: description vs body_md divergence is invisible) |
| M3 | break link: umbrella CON-299 changed to CON-999 | `validate` / `diff --db-only` | **no** |
| M4 | `update --status Done` (and `Bogus`) | engine | **no, fail-open**: rc 0, status silently stays Queued |
| M5 | `add Story …` | engine | **no, fail-open**: rc 0, item created as Type Task |
| M6 | description of 2 words | engine | yes (§11.4.91 floor) |
| M7 | delete CON-305 row | `validate` + `diff` | yes (dangling segment; rc 1) |
| M8 | flip CON-306 Status in Markdown | `diff` | yes (status md≠db) |
| M9 | AWS-key-shaped string in CON-333 | `validate` | **no** (no secret scan) |
| M10 | remove the "Acceptance criteria" header | `validate` | **no** (no §11.4.148 section check) |
| M11 | `**Reproduction:** reproduced-live` line in CON-311 text vs UNSET column | `validate` | **no** (inconclusive: I appended to description, not body_md, so the body-line check may never have seen it) |

Caught: 5 of 12 (M1, M1b, M6, M7, M8). Not caught: 7 (M2, M3, M4, M5, M9, M10, M11). Survivors M2/M3/M9/M10 mean the validator proves structure and DB-to-Markdown sync, not description content. That is why I1 and I2 needed a human reading. M4 and M5 are pre-existing engine fail-open defects. The lander should file them (not in this vehicle's scope): invalid `--status` and invalid type must exit non-zero.

Restored state: the scratch clone working tree is clean (`git diff --quiet`).
