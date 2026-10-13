# bs_selection_hole — golden-bad: planted fast-lane selection hole (T060)

`full_verdicts.json` is what the full backstop lane (T-C10, `--no-cache`,
no `--affected` narrowing) genuinely produces for change `CH-BS-HOLE-001`:
4 gates, 3 PASS and one genuine FAIL (`GATE-HOLE`).

`fast_verdicts.json` is what the fast lane's affected-set narrowing
(T-C03) produced for the SAME change: only 3 of the 4 gates. `GATE-HOLE`
is **entirely absent** from its `results` array — this is the planted
selection hole (a bug in the fast-lane selection logic that should have
included `GATE-HOLE` but did not, so it never ran and its FAIL was never
observed by the fast lane).

Per DEC-17 (research.md line 654) and plan.md's T-C10 "Protecting tests"
line, comparing these two documents MUST produce a drift report naming
`GATE-HOLE` and MUST block (exit 1) — this is a release blocker.

`expected`: first line `DRIFT`, second line the offending gate id
(`GATE-HOLE`), remaining lines an explanation.

This fixture is proven non-vacuous by `dec17_drift_ref.py` (this project's
own from-scratch reference implementation of the DEC-17 rule) in the RED
test's Section B, BEFORE any claim is made about the absent real tool
(`gates/backstop.sh compare`) in Section D.
