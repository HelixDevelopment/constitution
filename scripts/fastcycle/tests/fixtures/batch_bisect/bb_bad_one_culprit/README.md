# bb_bad_one_culprit

Golden-bad-in-batch / bisection-must-name-it. A batch of 3 changes
(chg-A, chg-B clean; chg-C the seeded culprit, targeting `widget_c.sh`,
its real runtime output contains BROKEN). The batch gate run must FAIL.

Bisection must name EXACTLY chg-C as the culprit -- chg-A and chg-B must
each resolve to PASS, never swept into the FAIL by a naive
"attribute-the-batch-verdict-to-every-member" implementation (the specific
anti-pattern task T056's own paired-mutation clause names: "attribute the
batch verdict to every member -> the attribution fixture FAILs"). See
bb_negctrl_attribute_to_all/ for that anti-pattern proven explicitly wrong
against this exact fixture's expected.json.
