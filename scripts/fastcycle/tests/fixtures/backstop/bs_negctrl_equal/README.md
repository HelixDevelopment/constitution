# bs_negctrl_equal — negative control: equal fast/full selections (T060)

`full_verdicts.json` and `fast_verdicts.json` select the SAME 3 gates for
change `CH-BS-EQUAL-001` and agree on every verdict — including `GATE-B`,
which genuinely FAILs in BOTH documents. This last point is deliberate:
a drift detector that (bug) always reports "no drift" whenever nothing
FAILed anywhere would pass a fixture with zero FAILs trivially, for the
wrong reason. This fixture instead proves the detector correctly
recognises "the fast lane ALSO caught this FAIL" (not "no FAIL exists")
as the reason no drift is reported.

`expected`: first line `NO_DRIFT`, remaining lines an explanation.

This fixture is proven non-vacuous by `dec17_drift_ref.py` in the RED
test's Section B, BEFORE any claim is made about the absent real tool
(`gates/backstop.sh compare`) in Section D.
