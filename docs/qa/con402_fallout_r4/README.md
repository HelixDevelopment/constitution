# CON-402 audit fallout, round 4: evidence

| Field | Value |
|---|---|
| Items | CON-450 (F1 safepath census and, review R3-5, the git-env census: structural round 4), CON-451 (r15 layer check, R3-4), CON-251 (history note, R3-6) |
| Base | pull request #14 head e48ca38f (contains main 33b33d26; no merge needed) |
| Review answered | REVIEW.md of round 3 (R3-1 to R3-7) |
| Evidence class | gate-logic (hermetic tests of two censuses and of a test layer), host-only, PROVISIONAL |
| Oracle | GNU bash 5.3.9 |
| Created | 2026-11-17 |

Host paths in copied logs are normalised to `<P>` (this fixer's work directory), `<S>` (other scratch paths) and
`<P-truncated>` (a path cut by the instrument's 240-character output cap). `SHA256SUMS` covers every file in this
directory.

## CON-450 (R3-1, R3-2, R3-5): the censuses read a shell file as bash does, from a closed allow-list

Class (review round 3, section 5): "code runs before the canonical loop and the census does not see it". Rounds 1
to 3 each added a rule against one more spelling. The cause of every escape was the same: both censuses decided
"blank", "comment" and "line" with Python's semantics (universal newlines turn a lone CR into a line break;
`str.lstrip()`, `strip()`, `isspace()` and `\s` strip CR, VT, FF, FS..US, NEL, NBSP and the Unicode spaces), while
bash knows only SPACE and TAB as blanks and LF as the line end. Round 4 changes how the file is read, not the rule
list:

1. `check_safepath_census.py` `_sh_read_as_bash`: the file is read as bytes, decoded strictly as UTF-8 and split on
   LF only. Line 1, when it starts with `#!`, must be exactly one of `#!/bin/bash`, `#!/usr/bin/env bash`. Every
   character must be TAB or printable ASCII, except that a full-line comment may also carry non-ASCII letters,
   marks, numbers, punctuation and symbols (Unicode categories L, M, N, P, S). Anything else (CR, a CRLF file, NUL,
   VT, FF, the C0 controls, DEL, NEL, NBSP, every Unicode space, zero-width and bidi characters, invalid UTF-8) is a
   VIOLATION and nothing of the file is censused (fail-closed). Inside that set Python's whitespace operations
   remove only SPACE and TAB, so every later reader (`_blank_heredocs`, `_heredoc_bodies`, `_git_env_scrub_sh`,
   `tag_at`, `_sh_text_lines`, `sh_commands`) agrees with bash. The real `baseline_replay.sh` is pure ASCII plus
   `§` in 9 full-line comments.
2. `git_env_class_census.py` `reading_problem` (R3-5, the same defect in the CON-402 census): for shell, line 1
   `#!` must be one of `#!/usr/bin/env bash`, `#!/bin/bash`, `#!/bin/sh`, `#!/system/bin/sh` (the four forms the
   tree uses); a C0 control other than TAB, or DEL, anywhere is UNSCRUBBED; in the preamble (up to the canonical
   line) every character must be in the same allow-list as above; on every line the first character after the
   SPACE/TAB run must be in it. The tree carries Unicode in test data after the scrub (measured: invalid UTF-8 in 3
   shell files, U+2028 in one, Unicode spaces and bidi characters inside strings), so the git-env census does not
   refuse non-ASCII code after the canonical line. For Python a CR anywhere, for JavaScript CR, U+2028 and U+2029,
   are refused. The comment rule now uses `[ \t]*#` and the scrub-line neighbour check `strip(" \t")`.

Measurements:

- `f1/class_r4_census_run1.txt`, `run2.txt` (R3-7): the class instrument `f1/r4_class.py.txt`, 72 members. These
  are the reviewer's B01 to B25 verbatim (including the git-env-only B02 to B07 and B09), 42 invented members
  (N01 to N42: 12 more leading characters, shadow-unset and hidden-op variants for CR, VT, FF, NBSP, NEL and FS, CR
  inside the canonical line, a CRLF file, a BASH_ENV shebang, shebang argument / space / CR / BOM, NUL, invalid
  UTF-8, non-ASCII after the line) and 5 golden-false members. The oracle is bash itself: a program built from each
  member reports whether GIT_DIR / GIT_INDEX_FILE survive the canonical line (scrub defeat, the condition rounds 1
  to 3 could not see, R3-7), whether the proved `wt_path` changed, whether `_fc_safe` is gone or a PATH program ran,
  and whether a hidden `mkdir` ran. Each member also runs the safepath census on the real `baseline_replay.sh` and
  the git-env census through its real `main()` on a small git repository. Control needles K0 to K4 (unmodified
  file, a plain `declare -l` before the line, `true` before the line, a plain hidden operation after it, `:` after
  it) must give their known verdicts, otherwise the run is BLIND. Result: escapes 0, controls correct, golden-false
  accepted, run 1 and run 2 byte-identical. 14 members are refused although bash shows no effect (or cannot run
  the file at all: a CRLF file, a bad shebang); the refusal is the conservative direction and is listed as such.
- `f1/class_round3_census.txt`: the same instrument against the round-3 censuses (head e48ca38f): escapes 27
  (8 against the safepath census, 25 against the git-env census), among them every reviewer member B01 to B10, B12,
  B13 and 15 invented members. This is the RED that shows the instrument sees the class.
- `f1/f1_red_round3_census.txt`: the F1 suite with the round-3 safepath census (sha256 in
  `f1/census_round3.sha256.txt`): 51 new behaviour rows and 8 new mutant anchors fail (pass=123 fail=59).
  `f1/f1_green_dev_run.txt`: pass=182 fail=0 on the round-4 census. The double runs on the committed tree are in
  the hand-back and `runs/`.

New F1 rows (`test_fc_safepath_gitenv_scrub.sh`): lone-CR rows (B01, B08, B10, B12), a CRLF file, a CR hiding an
operation after the line, a CR before a trailing canonical line; for VT, FF, FS, GS, RS, US, DEL, NUL, NEL, NBSP,
EMSP, IDSP, LSEP, PSEP, ZWSP, RLO, LRI and BOM a leading row and an in-comment row; FF and TAB+FF "blank" lines;
non-ASCII and NBSP code after the line; invalid UTF-8; shebangs `env -S` (B13), with an argument, with a space;
golden-false rows (a Unicode full-line comment, a TAB-led comment, a SPACE/TAB blank line, `#!/usr/bin/env bash`,
no shebang).

## Mutants (R3-3)

Adopted verbatim from the review's `mk_rvm.py` and each killed by a behaviour row (not by an anchor-drift row):
RV3M1 by `GE-sh-pre-code-then-comment`, RV3M2 by `GE-sh-pre-set-option`, RV3M3 by `GE-sh-post-helper-loop`, RV3M4
by `GE-sh-post-helper-defined-twice`, RV3M5 by `GE-sh-post-redefine-trusted`, RV3M6 by
`GE-sh-post-command-file-func`, RV3M7 by `GE-sh-post-dash-c-func`, RV3M8 by `GE-sh-post-unset-other-func`.
Round-4 census mutants, each killed: `GE-mut-r4-no-gate`, `-universal-newline`, `-any-shebang`,
`-shebang-prefix`, `-comment-any-char`, `-code-nonascii-ok`, `-c0-ok`, `-utf8-lenient`. Equivalent mutants (no
behaviour can tell them apart, recorded and not counted): reading the comment rule with `lstrip()` instead of
`[ \t]*#` (every character `lstrip()` would also strip is already refused by the allow-list), dropping
`and not ch.isspace()` (no character of category L, M, N, P or S is `isspace()`, measured over all of Unicode).
In the git-env census, removing `reading_problem` turns 21 needles red; the CR-led cases are still caught by the
separate comment rule, a redundant layer.

## CON-451 (R3-4): the vector is checked in the process that runs the case

`test_custody_sweep_r15_regression.sh`: when `RC_VECTOR_REC` is set, `run_case` starts the tool through
`sh -c 'printenv GIT_INDEX_FILE >"$1" || : >"$1"; shift; exec python3 "$@"'`, so the record is written by the very
process that becomes the python child. Both ME1 layer checks read that record. A control leg exports the vector,
unsets it before `run_case`, and must see it missing (`ok layer check control: ...`). Run:
`r451/r15_dev_run.txt` (51 ok).

## CON-251 (R3-6): history note, no history rewrite

- The R2-3 renames (20 files) are in `cc8a63b7`, labelled `CON-450`; `66fb5655`, labelled `CON-251` and titled as
  the rename, only updates `SHA256SUMS` and `followups.md`.
- The evidence commit `652dd9af` covers CON-450, CON-451 and CON-251 but is labelled `CON-450` only.
- `62362649` is a git-env-RED intermediate state on the landed history.
- `88935fd4` (labelled `CON-402`) belongs to CON-450 and `6952c6da` (labelled `CON-402`) to CON-451; the item
  bodies now say so (section 11.4.214 link).
- The subject of `88fcff75` ("assert it in the child") overstated the round-3 check; R3-4 above is the fix.

## Class sweep (task brief, section 11.4.276(C))

Every reader of shell text in both censuses sits behind the new gate (list in `followups.md`, FU-6). `py_census`
keeps universal newlines on purpose: Python's own parser treats a lone CR as a line break. Other census-style gates
that drop comment lines with the same wrong whitespace semantics are listed in FU-6 and not fixed here.

## Other runs

`runs/sweep_red_on_base_e48ca38f.txt`: `test_custody_sweep_red.sh` fails in a fresh clone on the base too
(FU-8, pre-existing, a gitignored fixture input). `runs/fu7_program_text_probe.txt`: FU-7.

## Follow-ups

`followups.md` (supersedes round 3).
