# CON-402 audit fallout, round 5: follow-up items and honest boundaries

Status: PROVISIONAL. Every item below is a placeholder for the tracker; NO id is minted here (the lander files them
after the section 11.4.214 dedupe). Evidence class: gate-logic (hermetic tests of two censuses and a differential test
against the bash and Python interpreters), host-only, not a live product run (section 11.4.289(I)). This file
supersedes `../con402_fallout_r4/followups.md` for FU-6, FU-7 and FU-8; FU-1, FU-3, FU-4 and FU-5 stay as in round 3.

## FU-6 (carried, status corrected): the same reading class in other census-style gates

Round 4 wrote "FIXED in round 4" for the two censuses of this vehicle. The review of round 4 (R4-1 to R4-4) showed
that overstated: both had further escapes. Round 5 closes them (see README) but the wording stays "hardened", never
"fixed": the instruments are closed-world refusals, and the residual classes named in the README ("Not claimed") remain.
The other gates of the FU-6 table (instrument_trap_scan, cm_feature_directive, cm_reporting_directives,
cm_test_mock_pid_explicit_int, enumerate_decision_mutants) share the whitespace class and are untouched: outside the
CON-450 / CON-451 / CON-251 scope (section 11.4.293). Proposed item text unchanged from round 4.

## FU-7 (carried): computed program text

`bash -c $'...'` programs that hold CR/VT/NBSP only at run time are refused by the safepath census after the canonical
line but have no member in the class instrument. Proposed item text unchanged from round 4. Round 5 adds a related
boundary that is not claimed: a name built at run time (`g\it`, a backslash-newline inside the word git) and a
re-export of a scrubbed variable after the scrub are outside what a file-scope census can see.

## FU-8 (carried, pre-existing): sweep_red golden-good fixture needs a gitignored file

Unchanged: `test_custody_sweep_red.sh` fails in a fresh clone because `qa-results/` is gitignored. Not touched by this
vehicle's diff.
