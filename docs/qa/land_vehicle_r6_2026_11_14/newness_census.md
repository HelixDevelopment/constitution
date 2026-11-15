# land_vehicle.sh round 6: tracker-id newness (class B, R5-B, R5-A2, R5-A1)

Status: PROVISIONAL. Evidence class: gate logic only (§11.4.289 clause C(2)).

## The finding

Round 5 checked that a freshly minted id is new in two places only: the tracker files at
main, and `Roadmap-Item:` lines in commit messages, matched case-sensitively. The review
(R5-B, R5-A2) showed that an id already in the vehicle's own tracker files, or in a folded,
lower-case, re-spaced or plain-text mention, passed as new.

## The class

Where can an id that is "already used" live, so that the merge or the history would
contain it twice? The members:

| # | Member | Round 5 | Round 6 | Tests (RED on r5 / GREEN on r6) |
|---|---|---|---|---|
| B1 | tracker file at main, same case | refused | refused | round 3-5 tests (green in both) |
| B2 | tracker file at main, other case (`con-777`) | passed | refused | R6-B case at main (FAIL / PASS) |
| B3 | tracker file in the vehicle tip | passed | refused | R6-B tip (FAIL / PASS) |
| B4 | tracker file in an earlier vehicle commit, removed later | passed | refused | R6-B removed (FAIL / PASS) |
| B5 | tracker file in the vehicle, other case and leading zeros (`con-0777`) | passed | refused | R6-B case (FAIL / PASS) |
| B6 | folded (continued) trailer value in a vehicle commit | passed | refused | R6-A2 folded (FAIL / PASS) |
| B7 | lower-case key and value (`roadmap-item: con-777`) | refused, wrong reason | refused | R6-A2 case (FAIL on the message / PASS) |
| B8 | extra spaces and leading zeros (`Roadmap-Item  :   CON-0777`) | refused, wrong reason | refused | R6-A2 spacing (FAIL on the message / PASS) |
| B9 | a plain mention in a subject or body (`see CON-777`) | passed | refused | R6-A2 mention (FAIL / PASS) |
| B10 | tracker files of OLDER main commits (an id once in the tracker, since removed on main) | not checked | not checked, scoped out | none |

Controls (must stay accepted, so the check is not "refuse everything"):
R6-A2 control (the same vehicle, CON-778 is new) and R6-B control (the vehicle tracker
holds CON-776 only, CON-777 is new, the vehicle file lands). Both PASS on r5 and on r6.

Why B10 is scoped out: the tracker engine never reuses an id (§11.4.54 ids are stable and
never reused), so an id removed from the tracker on main is still known to the engine and is
not minted again; checking every older tree of main would read the whole history on every
mint. This is a stated limit, not a proof: an engine that does reuse ids is not protected by
this check.

The folded trailer is also refused as a trailer shape at prepare and at publish
(R6-A1-emptykey, R6-A1-continued, R6-A1p; R5-A1): a folded `Roadmap-Item` value is never
kept and never treated as a real trailer.

## Mechanism (step 3, `mint()` in scripts/release/land_vehicle.sh)

* Members B1-B5: for main before the mint and for every commit in
  `git rev-list <vehicle head> --not <main>`, every blob at a path matching
  `LANDER_TRACKER_PATHS` is read once (de-duplicated by blob id) and searched with
  `grep -aiE` for `<KEY>-0*<NUM>` (any letter case, any leading zeros).
* Members B6-B9: every commit object reachable from main or the vehicle
  (`git rev-list <main> <vehicle head> | git cat-file --batch`) is searched with
  `grep -aiE "<KEY>-0*<NUM>([^0-9]|$)"`, a substring search over message and headers.
* Both fail closed: an unrelated mention (for example `XCON-777` in prose) also refuses.

## Census of the search sites (control-needled)

`grep -n 'already appears in' scripts/release/land_vehicle.sh` finds the two refusal sites
(lines 805 and 811 of the round-6 file): one for tracker files (members B1-B5, the `where`
text says "before the mint" or "in vehicle commit <sha>") and one for commit objects
(members B6-B9). The helper `id_seen_in_file` occurs 3 times (comment, definition, the one
call). Control needles: `id_seen_in_file` found (3), the fabricated `ZZNOTAFUNC` not found (0).

## Mutants that guard this class

M05 (folded_ri always false), M06 (commit-object grep case-sensitive), M07 (commit-object
check only on Roadmap-Item lines, the r5 form), M08 (main only, vehicle commits dropped),
M09 (tracker check case-sensitive), M14 (the de-duplication skips every blob). Results are
in `mutant_table.md`.
