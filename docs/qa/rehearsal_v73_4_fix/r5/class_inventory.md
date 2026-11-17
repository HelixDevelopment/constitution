# CON-423 r5: class definition, the closed grammar, and the member inventory

| Field | Value |
|---|---|
| Item | CON-423 of the r4 bundle; on this vehicle CON-PENDING-rehearsal (main took CON-423 to CON-442 meanwhile; the lander re-mints) |
| Answers | review round 4 of CON-423 (NO-GO: C1 a strong word split into pieces of several letters, C2 to C8, L1 and L4 a line model that is not CommonMark's, P4 inventory floors tied to one Unicode version, survivors N02 N04 N06 N07 N08 N10 N14 N17 N18, equivalence of N03 and N22 unproven, tracked SQLite sidecars) |
| Rule | section 11.4.276(C) name the class and enumerate every member; (E)(3) the class recurred in four rounds, so this round replaces the PRIMITIVE, not a rule; section 11.4.250 a tower of heuristics signals a primitive defect |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290) |
| Order of work | this document was written BEFORE any code of round 5 (the operator's order for this round); the code follows it, and any later difference is recorded in section "Changes after the code" at the end |

## 1. The class

**A verification-line field value that names no real, checkable thing of its kind, yet the checker accepts it.**

Rounds 1 to 4 described the class by its BAD members: placeholder words, then their split, folded, glued, look-alike
and invisible forms, each round a longer list (r1 the words; r2 word boundaries and look-alikes; r3 single-letter
runs; r4 one scan, a skeleton map, declared scripts). Every review found new members because the complement of a
blacklist is infinite: `TO DO`, `FIX_ME`, `TB.D`, `🆃🅱🅳`, `T8D`, `host to be determined` (review r4 C1 to C5). The
primitive was wrong: "accept unless a bad form is recognised".

Round 5 inverts it. **A value is accepted only when it is a sentence of a small closed grammar whose every
reference resolves to something real under `--root` (or in the tracker database).** Everything else is refused by
construction; a new evasion is refused because it is not in the grammar, not because a rule was added for it.

## 2. The grammar (ASCII; one U+0020 space where a space is written)

```
LINE     = "**Verification:** provisional" [ " (section 11.4.290)" ]
           SEP JOB SEP CHECKS SEP LAYER SEP TARGET SEP ARTIFACT SEP DUE [ SEP NOTE ]
SEP      = " -- " | " " U+2014 " "                    (the only non-ASCII character outside NOTE)
<field>  = NAME ( ": " | " " ) VALUE                    (the canon's colon-less form and this project's colon form)

JOB      = TRACKERREF | INVOCATION *( "; " INVOCATION )
TRACKERREF = ID                                         an item of the same database, not the item itself, whose
                                                        Status is Queued, In progress or Operator-blocked (an open
                                                        tracked job); ID = KEY "-" DIGITS, KEY = [A-Z][A-Z0-9]{1,15}
INVOCATION = *( ENV " " ) RUNNER " " SCRIPT *( " " ARG )
RUNNER   = "bash" | "sh" | "python3" | "python3 -I"     (bash, sh: SCRIPT ends .sh or .bash; python3: .py)
SCRIPT   = a relative path of parts [A-Za-z0-9_.+-]+ joined by "/", no "." or ".." part, that is a REGULAR FILE
           under the real --root (its real path inside the real root)
ARG      = OPTION | PATHARG | SELECTOR | INT
OPTION   = ( "-" [A-Za-z] | "--" [a-z][a-z0-9-]* ) [ "=" VAL ]   the option text (before "=") occurs in SCRIPT
PATHARG  = "." | a path as SCRIPT's parts that exists under --root (file or directory)
SELECTOR = [A-Za-z][A-Za-z0-9_.-]{0,63} holding a digit, that occurs in SCRIPT as a whole word
INT      = "0" | [1-9][0-9]{0,9}
ENV      = [A-Z_][A-Z0-9_]{0,63} "=" VAL, the name occurs in SCRIPT
VAL      = INT | PATHARG | a word [A-Za-z0-9_.:/+-]{1,64} that occurs in SCRIPT as a whole word

CHECKS   = RESULT *( "; " RESULT )
RESULT   = SUBJECT 1*( " " TERM )                        each KEY at most once per RESULT, at least one COUNT key
SUBJECT  = a SCRIPT or a SELECTOR written in JOB (so every result names a real test of the job)
TERM     = COUNT "=" INT | "rc=" INT(0..255) | "verdict=" ( "PASS" | "FAIL" | "BLIND" | "SKIP" )
COUNT    = "pass" | "fail" | "skip" | "killed" | "survived"

LAYER    = LWORD *( " plus " LWORD ), no word twice
LWORD    = "user-visible" | "runtime" | "artifact" | "source" | "host-only" | "live-target" | "gate-logic"

TARGET   = TTERM *( ", " TTERM ), no term twice
TTERM    = "host" | "repo checkout" | "scratch clone" | "remote " RNAME | KIND " " TID
RNAME    = a name N with upstreams/N.sh a regular file under --root
KIND     = "board" | "device" | "container" | "vm" | "runner"; TID listed for that KIND in the target registry
           (--targets FILE, default config/verification_targets.tsv under --root; absent registry => refused)

ARTIFACT = ATERM *( ", " ATERM ), no term twice
ATERM    = "main" | "main@" HEX | "commit " HEX | "merge " HEX | "tag " TAG
HEX      = [0-9a-f]{7,64}; TAG = [A-Za-z0-9][A-Za-z0-9._-]{0,63} holding a digit

DUE      = DATE [ "T" HH ":" MM [ ":" SS ] [ "Z" | ( "+" | "-" ) HH ":" MM ] ]
           a real calendar date with  created_date(item) <= DATE <= today + window  (--today, --due-window-days,
           default window 60 days); no created_at in the database => refused (the window cannot be checked)
NOTE     = NAME "note", then any printable ASCII to the end of the line; it is never read as evidence
```

The line is at most 4096 characters. Field names, their order and their count are fixed; a seventh part that is not a
NOTE is refused.

## 3. Members of the complement, by construction (what is refused, and why no list is needed)

| Id | Member class | Refused because |
|---|---|---|
| G01 | every placeholder word or phrase in any spelling (TBD, TO DO, FIX_ME, T.BD, to be determined, pending, ...) | not a sentence of the field grammar: no field accepts free words |
| G02 | every non-ASCII code point in JOB to DUE (look-alikes, enclosed and negative-squared letters, regional indicators, invisible and format characters, other scripts, full-width forms) | the field alphabets are ASCII; the only non-ASCII character outside NOTE is the em dash of SEP |
| G03 | every non-ASCII or control code point in NOTE | NOTE is printable ASCII |
| G04 | a path, option, selector, env name or value that does not resolve under --root | resolution is part of the grammar, not a shape |
| G05 | a directory or a non-runnable file as SCRIPT (scripts/, README.md, docs/Issues.md) | SCRIPT is a regular file with the runner's extension |
| G06 | a command that runs no script (git -x, go test, make) | RUNNER is a closed list and takes a SCRIPT |
| G07 | a checks text with no observed count, or naming no test of the job | CHECKS is RESULT terms over the job's own scripts and selectors |
| G08 | a target word that names nothing (board target, host or whichever) | TARGET terms are closed; a board needs a registered id |
| G09 | an artifact word (build, image) or prose | ARTIFACT terms are closed |
| G10 | a sentinel or far date (2099-12-31, 2000-01-01), an event, a vague date | DUE window against created_at and today |
| G11 | anything after DUE that is not a NOTE (". Not VERIFIED-DONE ...") | the line ends after DUE or NOTE |
| G12 | a second, missing, out-of-order or unknown field | fixed field sequence |

## 4. Line model (CommonMark 0.31, checked against pandoc 3.x where pandoc is installed)

| Id | Case | Model |
|---|---|---|
| M01 | line breaks | the body is split on LF only; one trailing CR of a line is removed (CRLF); U+001C, U+2028, U+0085 and every other character stay inside the line (review r4 L1, L2) |
| M02 | fenced code | an opening fence is up to 3 spaces, then 3 or more backticks or tildes; a BACKTICK fence whose info string holds a backtick is not a fence (review r4 L4); a fence closes on up to 3 spaces, the same character at least as many times, then only spaces or tabs; an unclosed fence runs to the end |
| M03 | HTML blocks | the seven start conditions of CommonMark 4.6 (script/pre/style/textarea, comment, processing instruction, declaration, CDATA, block tag names, any complete tag alone on its line) with their end conditions; a comment block ends on the first line, the start line included, that holds `-->` (so `<!-->` and `<!--->` end at once, review r3 L3) |
| M04 | lazy continuation | a column-0 line that continues the paragraph of a block quote or of a list item is inside it, not a line of its own |
| M06 | paragraph start | a line counts only when it STARTS a top-level paragraph (after a blank line, a heading, a thematic break, a closed fence or HTML block, or the start of the body); a heading or thematic break also ends the paragraph of a block quote or list item |
| M07 | two readings | each body is also read the pre-0.31 way (the end text of an HTML block of kinds 2 to 5 is looked for only after its opener); a body whose two readings count different lines is refused |
| M05 | indentation | only a line that starts at column 0 with the prefix counts |

## 5. Mapping of every reviewer case to this design

* probe_r3, probe_r3b, probe_r4: every REJ expectation is kept. OK (golden-FALSE) expectations whose value is free text
  are changed to REJ by design and listed one by one in tests/release/pvl_reviewer/changes.tsv (33 rows: 18 of
  probe_r3, 15 of probe_r4) with the reason "free text is not in the closed grammar" or "no created date in a
  field-only call" (for example `checks: none of the mutants survives`, `target: host checkout`, `job: JOB-42` when no
  such open item exists). This is a deliberate narrowing, not a loosening.
* mutants N01 to N22 (r4), R1 to R22 (r3), X1 to X7 (r2): each one names a mechanism. Where the mechanism exists in
  the round-5 code (separator, realpath, due lookahead, line length, comment close, fence rules, field order, more
  than one line, timing limit, inventory judgement) an equivalent mutant of the new code runs in the suite. Where the
  mechanism was removed (word lists, digraph and small-letter folds, single-letter runs, look-alike map as a reader)
  the mutant cannot apply; the suite runs the reviewer's mutant text against the new file and records NOT-APPLICABLE
  with the case that covers the removed class.

## 6. Honest limits (stated before the code)

* A value inside the grammar can still be false: a real script that is not the right job, counts that will not be
  observed, a commit id that is not the fix (commit and tag ids are shape-checked; the checker runs no process).
* A SELECTOR, option or env value is accepted when the script merely mentions it.
* Device-class targets need a registry; none exists in this repository, so every board, device, container, vm and
  runner target is refused until one is added.
* The real tracker database: every Ready-for-testing line was written as English prose and most say "no scheduler
  entry exists"; the grammar refuses them. Section 11.4.290(1) says such items stay In progress. This round lists
  them and does not rewrite or demote them; that is an operator decision.

## Changes after the code

* M06 (paragraph start) was added while the line model was compared with pandoc: a line that continues a paragraph is
  invisible as a line of its own, and counting it let a code span or an inline comment of an earlier line reach it.
* M07 (two readings) was added because pandoc 3.11 does not end a comment block at `<!-->`, `<!--->` or `<?>` while
  CommonMark 0.31 does; instead of picking one reader the checker refuses a body the two read differently.
* check_line checks the prefix itself (the property test found 699 accepted lines with a glued or changed prefix when
  check_line was called directly; check_body had already filtered them).
* SEP is exactly " -- " or " — " (one space each side); the em dash is the only non-ASCII character outside NOTE.
* The lazy-continuation branch of the line model was removed (own mutant O25 survived, and two new line-model cases,
  confirmed with pandoc, showed the branch hid a valid line after `> quote` then `# h`, or `- item` then `***`). A
  line that does not start a paragraph is not counted, which already covers lazy continuation.
* Own mutant O05 survived (a directory as SCRIPT): the fixture gained a directory named tests/dir.sh and class G05 its
  case. O18 survived (the item itself as JOB was refused only by the open-status rule): the mutation harness checks
  the reason. Both are now killed.
* G01: a placeholder alone is refused outright; before or after a value the oracle decides. One member is accepted:
  `job: bash tests/t.sh -k case12; python3 -I tests/p.py .` (`.` is a path argument, the root). The suite needles it.
* The reviewer's mutants: 56 in all (R1 to R22, X1 to X12, N01 to N22). 5 apply verbatim to this suite's files and are
  killed (R15, R19, R21, N15, N16); 7 apply to release tooling and run in that tooling's suites (X8 to X12, R17,
  R18); 44 cannot apply because their mechanism was removed, each mapped to its covering cases in
  tests/release/pvl_reviewer/mutants_map.tsv. N03 and N22 were questioned as equivalent in review r4; both are now
  NOT-APPLICABLE (the digraph fold and the comment-close test they mutated no longer exist), so no equivalence claim
  is made for them.
* The reviewer files are stored as `.py.txt` (tests/release/pvl_reviewer/probe_r3.py.txt and the five others; same
  bytes, sha256 in SHA256SUMS): as `.py` the full-suite census took the three mutant tables for test entry points.
  python3 runs them by path, so they still run verbatim.
* P0 (new): tests/release/pvl_fixture.py and tests/release/pvl_oracle.py check themselves before any harness uses
  them (`--selftest`): the fixture its shape, the oracle that the golden line is accepted and each of 13 golden-bad
  lines refused. A mutated oracle that accepts everything reports `wrong=13` and fails.
