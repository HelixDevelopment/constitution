# bb_negctrl_attribute_to_all

Negative control proving task T056's own named paired-mutation clause is
genuinely caught: "attribute the batch verdict to every member -> the
attribution fixture FAILs."

This fixture reuses bb_bad_one_culprit's batch (chg-A, chg-B clean;
chg-C the culprit). A NAIVE, non-bisecting "attribution" implementation
-- one that just copies the single batch-level verdict (FAIL) onto every
member instead of genuinely isolating the culprit -- would report
{chg-A: FAIL, chg-B: FAIL, chg-C: FAIL}. This file's `naive_attribution`
JSON is that WRONG output, computed explicitly (not merely asserted) by
this fixture's own tiny reference function in the RED test's Section E,
and the RED test asserts it does NOT equal bb_bad_one_culprit's real
expected per-change map -- proving a hypothetical batch_bisect.py that
took this shortcut would be caught by comparing against the golden
fixture, exactly as task T056 requires.
