# bb_good_all_pass

Golden-good. A batch of 2 changes (chg-A, chg-B), both clean (targeting
distinct files `widget_a.sh` and `widget_b.sh`). The batch gate run must
PASS, and EVERY member's per-change verdict must be PASS -- no culprit.

Proves: a batch with no bad change is not spuriously flagged, and the
per-change verdict machinery does not invent a FAIL where none exists.
