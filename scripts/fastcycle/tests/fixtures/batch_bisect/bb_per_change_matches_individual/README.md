# bb_per_change_matches_individual

Proves task T056's "per-change verdicts equal individual runs" clause: for
EACH change in bb_bad_one_culprit's 3-member batch, running that ONE
change alone (an individually-sized batch of 1) against the gate must
produce the IDENTICAL verdict the bisector assigned it inside the batch.

Three individual-run batches are defined here (chg-A alone, chg-B alone,
chg-C alone); this fixture's expected.json's `individual` map MUST be
byte-identical to bb_bad_one_culprit/expected.json's `per_change` map --
the RED test asserts this equality directly (never merely by construction)
so a bisector that gets the RIGHT culprit but a WRONG per-change verdict
value (e.g. reports chg-A as FAIL because it shared a batch with the real
culprit) is caught.
