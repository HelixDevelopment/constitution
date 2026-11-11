<!--
Template of the CHANGELOG entry for the PROVISIONAL pre-release helixconstitution-v73.4.
It is NOT a CHANGELOG entry yet: putting it at the top of CHANGELOG.md is the release commit itself
(the first `## ` heading drives the Version badge and the release notes).

Fill it ONLY with scripts/release/render_release_entry.py, which substitutes every {{key}} from the
output of scripts/release/derive_release_facts.sh (plus the hand-supplied keys listed in
docs/release/README.md) and refuses while any {{...}} is left. Keys written {{MANUAL:...}} are the
ones a person (conductor or operator) must supply; every other key is mechanical.
Built from the independent review of the first v73.4 release commit (e3a55a44, NO-GO): I-1 to I-4,
m-1, m-5 (CON-023), m-9, m-10, n-1, n-3, n-4, n-6.
-->
## helixconstitution-v73.4 — {{MANUAL:cut_date}} — PROVISIONAL pre-release after v73.3: §11.4.294–§11.4.298, workable-items state columns (schema v8), full-suite runner with a clean manifest, ownership redesign waves 1 and 2, the pull-request delivery and release-gate anchors, the CM-KILLPG-PGID-GUARD regression fixed, review-landed vehicles

**Status: PROVISIONAL PRE-RELEASE (§11.4.290), release class pre-release, tag `helixconstitution-v73.4`.** Previous tag: `{{prev_tag}}` (tag object `{{prev_tag_object}}`, commit `{{prev_tag_commit}}`, {{prev_tag_date}}). Content base: `main` at `{{base}}` ({{commits_since_prev}} commits after {{prev_tag}}, {{merges_since_prev}} of them merges; `git diff --shortstat`: {{shortstat_since_prev}}). The release commit adds this entry, the README badge row it regenerates, and nothing else.

**A release that does not pass the §11.4.230(F.3) seam, cut on a recorded operator override (§11.4.271 waiver shape), stated plainly (§11.4.6).** It is a release in the sense of §11.4.230(F.1). (F.3)(1): the §11.4.40 retest (`scripts/run_full_suite.sh --include-heavy`, exit 0 = PASS-FULL) has never run on this candidate and no §11.4.185 manual-QA confirmation is recorded. (F.3)(2): entries of class (L1) (no live verdict for any PROVISIONAL item below on this fingerprint), (L6) (the §11.4.40 retest) and (L7) (no `docs/PRODUCTION_READINESS.md`, §11.4.260, so every production-readiness invariant is UNKNOWN, not green) ride open. Waiver: authoriser {{MANUAL:waiver_authoriser}} (rostered in `config/full_suite_operators.roster`, not the producer of this commit); decision: {{MANUAL:waiver_decision_and_source}} (relayed, not verbatim, unless a tracked record is cited); relaxes (F.3)(1) retest and manual QA, and (F.3)(2) for (L1), (L6), (L7); expiry: {{MANUAL:waiver_expiry}}; owed work tracked as {{MANUAL:retest_item_id}} ("§11.4.40 `--include-heavy` retest and §11.4.185 confirmation of the v73.4 candidate"). This tag promotes nothing to VERIFIED-DONE and is never re-tagged or patched.

#### Count line (§11.4.290(4))

{{count_line}} — verified = items closed in the Fixed tracker after {{prev_tag_date}}; provisional = open items carrying a `**Verification:** provisional` line ({{provisional_ids}}); overdue = those whose due date has passed or that have no due date (UNSCHEDULED, treated as OVERDUE): {{overdue_ids}}.

#### VERIFIED (command run and output seen on {{MANUAL:verified_date}}, on the release commit)

{{MANUAL:verified_block}}

`bash scripts/gates/cm_killpg_pgid_guard.sh` on this tree: {{MANUAL:killpg_summary_line}}. History, stated as it is: at v73.3 (`aa5ae0a3`) the gate printed `PASS — 23 process-group signal call site(s), all guarded`; on later `main` it regressed (4 unguarded at `90efceb8`, 7 at `fc57ad0c`; the sites came in with files added after v73.3: `scripts/fastcycle/tests/test_baseline_replay_r2_findings.sh:450`, `scripts/fastcycle/tests/test_fc_supervisor_v4r5_findings.sh:1705`, `scripts/full_suite/run_full_suite.py:2685` (a raise message the gate read as a call), `tests/test_run_full_suite.sh:241` (a saved reference to `os.killpg`), `scripts/validation/test_meta_test_verification_r1_regression.sh:368` and `:382`, `scripts/validation/enumerate_decision_mutants.py:294`). This release guards or marks each of them (vehicle `vehicle/rel734`; see its Unreleased entry). Counts are for a clone without submodules checked out.

#### PROVISIONAL (landed, verification pending; counted as done for planning only)

Items with their own recorded verification job (from the tracker): {{provisional_ids}}. Each job is the one written on the item's `**Verification:**` line, not the §11.4.40 retest.

{{MANUAL:provisional_changes_block}}

#### REOPENED

{{reopened_ids}}

#### OVERDUE

{{overdue_ids}} (no due date or a past one), plus the v73.2 and v73.3 PROVISIONAL lists, which are still waiting on the §11.4.40 retest tracked as {{MANUAL:retest_item_id}}.

#### Open items carried into the next release (§11.4.230(F.4)(2), by tracked id)

The tracker (`docs/workable_items.db` at `{{base}}`, sha256 `{{db_sha256}}`) holds {{items_total}} items, {{items_open}} open. Status: Queued {{open_status[Queued]}}, Ready for testing {{open_status[Ready for testing]}} ({{open_status_ids[Ready for testing]}}), In progress {{open_status[In progress]}} ({{open_status_ids[In progress]}}), Operator-blocked {{open_status[Operator-blocked]}} ({{open_status_ids[Operator-blocked]}}). Severity (case-folded; raw spellings {{open_severity_raw_spellings}}): high {{open_severity[high]}} ({{open_severity_ids[high]}}), medium {{open_severity[medium]}}, low {{open_severity[low]}}.

Reproduction and investigation states (§11.4.294(H), quoted from the tracker): {{open_items_with_any_state}} open items carry a state; the rest are UNSET/UNSET ({{open_states[UNSET/UNSET]}}). Per state:

{{states_block}}

Medium ids: {{open_severity_ids[medium]}}.
Low ids: {{open_severity_ids[low]}}.

Review follow-ups of the ATM-1809 audits (audit 3 M1 to M7 and N1 to N4) are {{MANUAL:followups_tracking}}.

#### Known defects (open, not fixed in this release)

{{MANUAL:known_defects_block}}

§11.4.288 debt: refs with commits not on `main`, counted per remote after `git fetch --prune` (only remotes listed were counted): 

{{unmerged_refs_block}}.

#### §11.4.297 and §11.4.298 for this release

§11.4.297: no tracked file of this repository declares pull-request delivery (no `config/delivery.conf`; no `delivery_mode` / `pr_reviewers` / `mode: pr` outside the anchor text, gates and tests), so §11.4.288 applies as written and the release commit lands on `main` by a direct fast-forward push. §11.4.298: this repository ships governance text, scripts and a tracker, declares no product and no deployable build for target hardware; the reading is that §11.4.298 does not apply, and no product is reported `RELEASABLE`. The operator may read it otherwise.

#### Installer note

`install_constitution.sh` and the updater pick the newest tag matching `helixconstitution-vN(.N)*`; this PROVISIONAL tag matches, so new installs and default updates take it (pre-existing since v73.1).

#### Next candidate (§11.4.230(F.4)(1))

{{MANUAL:next_candidate_statement}}

#### FINAL promotion preconditions (a new tag)

1. `scripts/run_full_suite.sh --include-heavy` on the candidate exits 0 (PASS-FULL), every FAIL fixed or matched to a KNOWN row.
2. A §11.4.185 manual-QA confirmation, or a §11.4.271 waiver from a rostered non-producer authoriser, recorded for the candidate.
3. A §11.4.260 production-readiness tracker exists and no (L7) entry is open.
4. The §11.4.288 refs above are landed or retired.
5. The tag name (v73.5 or v74) is an operator choice; the FINAL heading carries no `PROVISIONAL`.
