# CON-423 r3: follow-ups and operator questions (nothing here is filed; section 11.4.214 dedupe first)

## I1 (review r2 info): forge/lib/credentials.sh token shape without LC_ALL=C

The reviewer measured that the token-shape check in `forge/lib/credentials.sh` has no `LC_ALL=C`, so in a UTF-8
locale it accepts tokens with accented letters. It is CON-412 code, out of scope for CON-423. Proposed follow-up
(Type Bug, not filed by this round): set `LC_ALL=C` in the check, as `rc_gitea_token_shape_ok` of
`scripts/release/redact_cut.sh` already does (reviewer mutant X12 guards that one). The lander runs the
section 11.4.214 dedupe before minting.

## F1 (review r2 process): Ready-for-testing items that say "no scheduler entry exists" (OPERATOR QUESTION)

Section 11.4.290(C): a provisional marking without a scheduled job "is refused and the item stays In progress".
Measured in r3 on `docs/workable_items.db` (read-only query, sqlite3): the description of **28 Ready-for-testing
items** contains the phrase "no scheduler entry exists" (CON-015, 016, 023, 043, 144, 159-162, 183-186, 189-191, 211,
216-220, 222-224, 235, 236, 265); a 29th hit is CON-424 itself (Queued, it quotes the phrase). The reviewer counted
the 24 items migrated by r2; the other 4 hits contain the phrase as well and were not separated here.
r3 did not create this condition and does not decide it. Operator decision needed, two options:

1. **Schedule the jobs**: create a real scheduler entry per item (the job named on its verification line), then
   rewrite the line to name the entry. The items stay Ready for testing.
2. **Demote**: move the items to In progress (section 11.4.290(C) as written) until a job exists.

CON-424 does NOT cover this: it covers past due dates, not missing jobs. Nothing is filed by r3; whoever files it
runs the section 11.4.214 dedupe first (CON-424 is the nearest candidate and is a different defect).

## Id collision with the Jev r12 bundle

The Jev r12 bundle also mints CON-423 to CON-428. r3 mints no new id: all r3 work is under CON-423 (a placeholder
from the lander's point of view). The job migration of CON-159 to CON-162 changes existing items only. The lander
re-mints through the engine if the ids collide on landing.
