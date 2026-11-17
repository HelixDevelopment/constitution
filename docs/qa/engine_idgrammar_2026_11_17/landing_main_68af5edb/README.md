# CON-456 round 6 (PR #18, head 41f7fa0a) landing on main 68af5edb (lander, 2026-11-17; PROVISIONAL)

The pull request's head 94c95d83 was NOT landed (its review reproduced body loss in block and
update --description). The round-6 head 41f7fa0a (bundle READY_con456r6, sha256 checked) was pushed to
the branch fast-forward; it builds on round 5, which the round-5 review says closes that class.

Tracker. The vehicle's database differs from its base 33b33d26 in 289 descriptions and 17 parent
links. They came from one `sync md-to-db` run with the round-6 engine (commit 26eec8ed) that re-parsed
every item, not from authored edits. In two items (CON-263, CON-456) a line is in neither the new
description nor the body. That is a data-loss finding about md-to-db re-parsing and is filed as a
follow-up. That side effect was NOT replayed. The vehicle's one intended write is CON-456's status
(Queued -> In progress), reproduction (reproduced-live) and investigation
(root-cause-found-with-evidence). The lander built a scratch vehicle copy equal to the base plus only
those CON-456 fields and the body lines the engine writes for them, planned it against main, and
replayed it through the engine.
- remint_plan.txt: PLAN own=0, one base change (CON-456), 3 steps, 0 conflicts, 0 refusals.
- remint_verify.txt: PASS items=1 mismatches=0. Engine validate: OK, 549 items.
- body_probe.txt: on a copy of the merged tracker with this branch's engine, block CON-015/CON-016 and
  update --description CON-023 (same text) keep every body byte (bodies grow by the block detail lines;
  the update leaves the length unchanged). The copy was discarded.

Evidence class: gate-logic only (section 11.4.289).
