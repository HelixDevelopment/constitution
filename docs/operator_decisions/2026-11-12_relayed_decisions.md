# Relayed operator decisions, 2026-11-12 (night)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T11:40:00Z |
| Status | active |
| Source | relayed operator decisions, 2026-11-12 about 23:30 CET, and one reminder of 2026-11-13 00:34: the operator answered interactive questions; the conductor relayed the answers (operator memory file `project_operator_decisions_2026_11_12_night.md`). Not verbatim. |
| Recorded by | tracker-intake vehicle, round 2 fixer (Opus 5.5), scratch clone on base 02c10935 |
| Items changed | CON-046 (decision appended), CON-299, CON-300, CON-331, CON-332, CON-333 (record cited) |
| Items created | CON-334 (decision 4) |

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

## Reminder, 2026-11-13 00:34

Regularly fetch and pull the latest `main` from all upstreams, so work from other projects that use
the constitution is not missed; check through a scratch clone, never the live checkout. Disposition:
CON-300 (it cites this record). The first check found `origin/main` moved from 02c10935 to bd0036bd;
every vehicle on base 02c10935, this one included, merges the latest `main` before it lands.
