# CON-423 r3 mutant table (gate-logic, PROVISIONAL)

## Reviewer mutants (review r2, bin/mutants.py, sha256 5077d92d...c692c4), run against the r3 tree copy

Source: logs/reviewer_mutants_on_r3.txt.

| Mutant | Result on r3 | Note |
|---|---|---|
| X1 fence closed by the other fence character | KILLED |  |
| X2 fence closed by an opening line with an info string | KILLED |  |
| X3 4-space-indented ``` opens a fence | KILLED |  |
| X4 XXX inside a value no longer refused | STALE | the r2 code it edits was replaced; ported in tests/release/test_provisional_verification_lines.sh P11 (X4-port, X5-port, X6-port), all caught |
| X5 TBA inside a value no longer refused | STALE | the r2 code it edits was replaced; ported in tests/release/test_provisional_verification_lines.sh P11 (X4-port, X5-port, X6-port), all caught |
| X6 single-word job needs no digit or punctuation | STALE | the r2 code it edits was replaced; ported in tests/release/test_provisional_verification_lines.sh P11 (X4-port, X5-port, X6-port), all caught |
| X7 template ${...} no longer refused | KILLED |  |
| X8 render: TODO after an underscore accepted (MY_TODO) | KILLED |  |
| X9 render: DRAFT preceded by a digit accepted (2DRAFT) | KILLED |  |
| X10 repo_key host not case-folded | KILLED |  |
| X11 repo_key doubled slash folded to nothing | KILLED |  |
| X12 token shape outside the C locale | KILLED |  |

X1, X2, X3 and X7 are also adopted verbatim inside the PVL suite (P11); X8 and X9 verbatim inside the render suite.

## The fixer's own mutants (not the reviewer's)

- PVL suite P8: one paired mutant per rule of the rebuilt checker (gmut, every one must make the grid report a mismatch):
  - empty-check
  - pv2-strip
  - punctuation-check
  - strong-lead
  - unconfirmed-word
  - lorem-word
  - weak-lead
  - weak-lead-checks
  - none-of-exception
  - not-no-lead
  - checks-not-list
  - be-phrase
  - compound-alone
  - compound-anywhere
  - punct-led
  - inside
  - split-letter-digit
  - digit-read
  - single-run-inside
  - single-run-lead
  - confusables
  - combining-marks
  - template
  - nfkc
  - format-chars
  - job-shape
  - job-shape-reads-folded
  - job-id
  - job-path
  - job-command
  - checks-shape
  - target-shape
  - target-words
  - target-reads-folded
  - layer-shape
  - artifact-shape
  - artifact-reads-folded
  - due-not-date
  - due-calendar
  - due-year-range
  - due-time
  - fence-ignored
  - fence-close-length
  - colonless-form
  - prefix-boundary
  - comment-skipped
  - comment-close
  - comment-one-line
- Render suite: R1-no-confusables, R2-no-mark-strip, R3-cyrillic-T-dropped, R4-greek-A-dropped (each: the real script refuses with rc 3, the mutant accepts).

All of them are caught in logs/run2 and logs/run3 (the suites end with fail=0; a surviving mutant is a FAIL line).
