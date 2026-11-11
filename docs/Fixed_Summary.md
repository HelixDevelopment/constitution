# Fixed_Summary

Closed workable items (current_location = Fixed), regenerated from the SQLite single-source-of-truth (§11.4.53).

## Counts by Type × Status

| Type | Status | Count |
|---|---|---|
| Bug | Fixed (→ Fixed.md) | 1 |
| Task | Completed (→ Fixed.md) | 2 |
| Task | Obsolete (→ Fixed.md) | 1 |
| **TOTAL** | | **4** |

## Items

| # | Level | Status | Type | Fixed-In Tag(s) | One-line description | Reproduction | Investigation |
|---|---|---|---|---|---|---|---|
| 1 | Medium | Completed (→ Fixed.md) | Task | — | CON-083 — parse_mutation.py had no test; its full-suite excluded note named the wrong importer and a test that does not cover it | UNSET | UNSET |
| 2 | Medium | Fixed (→ Fixed.md) | Bug | — | CON-084 — capture_fc_timer_triplet.sh checks the consumer pre-build file before refusing the stand-in-only override, so test (H15) fails in a standalone clone | reproduced-host-fixture — REPRODUCED | root-cause-found-with-evidence |
| 3 | Low | Obsolete (→ Fixed.md) | Task | — | CON-172 — Operator question: should the codegraph_safe.sh writer default (fkidx1,resolve1) follow the CON-147 Option A runner default (fkidx1,resolve1,resolve2)? (review I6-2) | UNSET | UNSET |
| 4 | Low | Completed (→ Fixed.md) | Task | — | CON-213 — Link CON-172 to CON-211 (same review question I6-2) and close CON-172 once the operator decision record is confirmed (cg117 review M1) | UNSET | UNSET |
