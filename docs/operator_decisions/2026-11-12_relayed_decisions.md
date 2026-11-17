# Relayed operator decisions, 2026-11-12 (night)

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T17:00:00Z |
| Status | active |
| Source | relayed operator decisions, 2026-11-12 about 23:30 CET, and one reminder of 2026-11-13 00:34: the operator answered interactive questions; the conductor relayed the answers (operator memory file `project_operator_decisions_2026_11_12_night.md`). Not verbatim. |
| Recorded by | tracker-intake vehicle, round 2 fixer (Opus 5.5), scratch clone on base 02c10935 |
| Items changed | CON-046 (decision appended), CON-299, CON-300, CON-331, CON-332, CON-333 (record cited); revision 2: CON-243 and CON-308 (closed duplicate-of CON-262 under decision 8), CON-262 (canonical head; context and acceptance carried) |
| Items created | CON-334 (decision 4) |
| Revision 2 | round 3 fixer (Opus 5.5): decision 8 (2026-11-13) recorded; question O-1 of section "Owed decisions" answered by it; CON-243 and CON-308 closed duplicate-of CON-262 through the engine; decisions 1 to 7 unchanged |
| Revision 3 | round 4 fixer (Opus 5.5), answering round-3 review M-10: the "Items changed" row now lists the items revision 2 changed; the O-1 "why it is open" text states the relationship the round-2 review found (CON-308 closed onto CON-262, CON-262 recording CON-243 as its UNDECIDED candidate), re-checked against the database at 63f80e52 (`docs/qa/tracker_intake_2026_11_12_v4/decision_record_facts.txt`); no decision changed |

This record is the section 11.4.66 decision record for the answers below. The operator gave them in
an interactive session and the conductor relayed them; they are not quoted verbatim. Where this
record maps an answer to an item, the mapping is the recorder's. Every item id here was minted on
base 02c10935 and may be re-minted by the lander (section 11.4.214); the embedded-id table in
`docs/qa/tracker_intake_2026_11_12_v2/README.md` lists every place an id is written.

## Decisions

| # | Decision (relayed) | Disposition |
|---|---|---|
| 1 | Identity guard, round 4: accept the strict stated-identity model (58% more refusals, documented); agents state their identity in every commit command. | CON-331 (the identity-guard vehicle's own item id is UNKNOWN; the lander appends this decision to it). |
| 2 | CON-046: let the third full screen finish, then rerun all three screens on one calendar day (the run crosses midnight); restore the full CON-046 description through the engine (main's cut to the title was not intended). | CON-046: description restored by the tracker-intake vehicle (round 1); the rerun decision is appended to its description (round 2). The rerun itself is not done by this record. |
| 3 | Security scripts: apply after independent review GO, with read-back, authorised scope only; the Codeberg force-block stays UNCONFIRMED; no force test leg. | CON-332. |
| 4 | Jev endpoint: the operator exports `CMA_JEV_PREFER=jev-typesafe` until the claude_toolkit failover fix lands. | CON-334 (the failover fix is owed work; it had no item). |
| 5 | Orphans: agents may reap the 12 `jev_server.py` processes (one parent) after checking each pid by command line and parent, then run `llmctl daemon-reload`. | One-off authorisation, no item (nothing is owed). Whether it was carried out: UNCONFIRMED here. |
| 6 | Disk: agents may free space, their own scratchpad included (with the safe remover), and prune container and build caches (reversible). | One-off authorisation, no item. Whether it was carried out: UNCONFIRMED here. |
| 7 | Secrets in other repositories: report only (paths and key kinds, no values); the operator rotates; the two huge Android repositories stay skipped and recorded. | CON-333. Where the operator keeps the per-file report is an open decision (CON-333 acceptance). |
| 8 | (2026-11-13, an interactive answer, relayed by the conductor through the coordinating agent to the round-3 fixer; not verbatim) CON-243 and CON-262 are one defect: link them as duplicates, the canonical head chosen by the section 11.4.214 rule, and close CON-308 duplicate-of that single head. | Head: CON-262 (older: created 2026-11-06 against 2026-11-11; open; it carries the measured census and the acceptance). CON-243 closed Obsolete duplicate-of CON-262, its tier-awareness part carried into the acceptance of CON-262; CON-308 closed Obsolete duplicate-of CON-262. All through the engine: docs/qa/tracker_intake_2026_11_12_v3/apply_v3b.log. The fixer did not hear the operator; the wording above is the coordinator's relay. |

## Reminder, 2026-11-13 00:34

Regularly fetch and pull the latest `main` from all upstreams, so work from other projects that use
the constitution is not missed; check through a scratch clone, never the live checkout. Disposition:
CON-300 (it cites this record). The first check found `origin/main` moved from 02c10935 to bd0036bd;
every vehicle on base 02c10935, this one included, merges the latest `main` before it lands.

## Owed decisions

These are questions for the operator, not decisions. Each stays open until the operator answers it
in a section 11.4.66 record; an answered question keeps its row, marked ANSWERED with the decision.

| # | Question | Why it is open | Where it is tracked |
|---|---|---|---|
| O-1 | ANSWERED by decision 8 (2026-11-13). CON-308 (run_all.sh counts rc 77 as FAIL): is it the same defect as CON-243, as CON-262, or neither? Are CON-243 and CON-262 themselves one item? | The round-2 review (R2-1) found that CON-262, the head CON-308 had been closed onto, records CON-243 as an open UNDECIDED candidate; with two open heads, section 11.4.214(0) makes the verdict UNDECIDED. Round 3 reopened CON-308 with the verdict UNDECIDED and both candidates named (mint-with-link). | CON-308, CON-243, CON-262 (closed and linked under decision 8). |
