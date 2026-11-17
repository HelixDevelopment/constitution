# CON-423 round 6: fixes for the r5 review (NO-GO), evidence

| Field | Value |
|---|---|
| Item | CON-423 (rehearsal of the v73.4 cut, D2: verification lines) |
| Round | 6 (operator decision: rounds continue until GO; fresh fixer, fresh reviewer) |
| Base | bundle fix_rehearsal_v73_4_r5.bundle, head 7967fbdf |
| Review read | review_r5_con423_udC5/out (SHA256SUMS 3cb04152...b5f479c) |
| Class | gate-logic, PROVISIONAL (sections 11.4.289(C)(2), 11.4.290); no live claim |
| Model / effort | Opus 5.5 / effort UNKNOWN |
| Results | final suite run1 and run2: `RESULT: pass=84 fail=0` both, identical after normalising timings and temp paths (`compare_run1_run2.txt` empty); render suite 96/0 twice; mutants 59 of 59 killed (43 own, 16 reviewer) |

Every fix was made test-first: the RED file was captured on the r5 checker
(`git show HEAD:scripts/validation/check_provisional_verification_lines.py`
in the r5 tree) before the change, and the same command was run again on the
fixed checker (GREEN). The files are under `red/` and `green/`.

## Findings and what changed

| Finding | RED (r5 artifact) | Fix | GREEN |
|---|---|---|---|
| I-1 lone CR is a line ending | `red/lineend_r5.txt`: danger=844 of 18720 variants; `red/linemodel_r5.txt`: 11 mismatches; `red/probe_e2e_r5.txt` | the body is split on `\r\n`, `\r` and `\n` (CommonMark 2.1); indentation in columns (a tab to the next multiple of 4); a "near" rule refuses a body when a line a reader shows carries the Verification label and is not the one counted line; thematic breaks take precedence over list items; a setext `=` underline ends a paragraph | `green/lineend_green.txt`: danger=0; P8 `LINEMODEL cases=65 mismatches=0 pandoc_mismatches=0 mdit_mismatches=0`; `probe_e2e_r6.txt` all as expected |
| I-1 second reader | pandoc drops a lone CR (blind) | `tests/release/pvl_refreader.py`: markdown-it-py 3.0.0 (commonmark preset), which normalises `\r\n?` and `\n`; pandoc kept, never used for a body with a lone CR; control needle proves pandoc's blindness (`pandoc_cr_blind=yes`) | P8b |
| I-1 class enumeration | - | `tests/release/pvl_lineend.py`: 30 members (LF CR CRLF LFCR CRCR CRCRLF NEL VT FF LS PS NUL BOM FS GS RS US DEL, and the start-of-line class found by the run: SP SP3 SP4 TAB NBSP ZWSP ZWJ WJ SHY IDSP LRM RLO), 65 line-model bodies at every LF position plus 21 shapes; acceptance computed by the real `check_body` | `LINEEND variants=19350 danger=0 pandoc_danger=0` |
| (found in r6) character reference in the label | `red/lineend_entity_red.txt`: danger=12 (`**&#86;erification:** ...` next to a counted line was accepted while markdown-it shows two lines) | `has_label` decodes character references (`html.unescape`) before it looks for the label | `green/lineend_entity_green.txt`: danger=0 |
| M-1 read-only open of a WAL database creates -wal/-shm | `red/suite_p0_p4b_r5.txt` | the database, -wal and -journal are copied as bytes into a private temp dir and the copy is opened; copy retried when a file changed (5 tries, then BLIND) | P4b: closed WAL db unchanged byte for byte; the same in a directory that cannot be written; a live writer's -wal row (CON-909) is read and its files are unchanged |
| M-2 typed values | traceback (`red/suite_p0_p4b_r5.txt`) | integer created_at and blob body refused by name; non-UTF-8 registry BLIND; any unexpected error BLIND, never a traceback | P4b CON-901, CON-902, registry case |
| M-3 hour 24 | accepted | explicit range check (hour 0..23, minute and second 0..59, offset at most 23:59) | P4b CON-905 |
| M-4 status with trailing space | item skipped | status matched as read (NFKC, look-alikes, format characters removed, white space collapsed, case folded); not written exactly => refused | P4b CON-903, CON-904; counts `provisional_status=8` |
| M-5 / RV07 | RV07 survived (reviewer `mutants_rv.log`) | linemodel case M08 (`> ````\n> ```\n> text\n` + line) | RV07 killed by linemodel |
| M-6 false refusals | - | thematic and setext fixed (checked against both readers); link reference definition and a list fence after a blank stay stated stricter refusals (docstring, Known limits) | `probe_lm_r6.txt`, `probe_lm_r6_mdit.txt` |
| N10 nit | map row named O04 | row corrected: main()'s root realpath is RV12, killed in r6 by the api `--root` symlink case | P12 |

## Reviewer mutants

All 12 r5 mutants (RV01-RV12) are vendored verbatim as
`tests/release/pvl_reviewer/mutants_r5.tsv` (sha256 in `pvl_reviewer/SHA256SUMS`,
equal to the reviewer's), with `probe_e2e_r5.py.txt` and `probe_lm_r5.py.txt`.
The four r5 survivors are killed: RV05 by grid (the refusal must name "holds
an empty word"), RV07 by linemodel (M08), RV09 by grid (`tests/rootlink`, a
symlink to the root, refused as a path argument), RV12 by api (`--root`
through a symlink must print the real ROOT).

RV04 is NOT-APPLICABLE in round 6, with its reason in `mutants_map.tsv`: it
removes the `datetime.datetime.fromisoformat` call, and that call no longer
exists. The first full run (`attempt1/`) showed RV04 SURVIVED after the r6 range
check was added: DUE_RE fixes the shape, `datetime.date` checks the date and the
explicit ranges check the time, so the call had become redundant. It was
removed, and five grid cases were added (T24:00, T10:60, +01:60, -24:00,
T23:59:60Z) next to the existing ones; own O36 removes the hour range and is
killed.

## Own mutants

O31-O43 (13 new, 43 in all) cover the r6 changes. History, stated:
- O38 (open the database in place) first SURVIVED: a read-write open of a
  closed WAL database removes its sidecars on close. A case was added (the WAL
  database in a directory that cannot be written); O38 is killed by api.
- O20 and O24 were NOT-APPLIED in `attempt1/`: the r6 line-model rewrite
  changed their target text. O20 is retargeted to the new comparison
  (`if lines != old:`). O24 then SURVIVED: the `starts` test had become
  redundant with the near rule (a continuation line with the prefix carries
  the label). `starts` was removed and O24 retargeted to the near clause's
  paragraph test; it is killed.
- O42 and O43 were reported killed by lineend in a subset run at 21:22
  (`mut_r6_subset.txt`) and SURVIVED in `attempt1/`; the current lineend does
  not kill them (reproduced). The cause of the earlier kill is UNCONFIRMED (the
  checker and lineend changed between the two runs). Two api bodies were added
  (CON-811: a label on an HTML kind 6 start line, which a reader sees as text;
  CON-812: a soft hyphen inside the word); both mutants are killed by api.

`attempt1/` is the first full run (pass=82 fail=2, its second run stopped when
these defects were found); `run1.txt` and `run2.txt` are the final runs.

## Limits (stated)

- the snapshot retry (`if _stats(db) == before`) has no deterministic test: a
  change during the copy cannot be forced without a race; no mutant claims it.
- a label split by markup the near rule does not model is a gap.
- pandoc differs from markdown-it on 68 of the shape variants (start-of-line
  members, `<!-->`); the checker refuses every one of them (`pandoc_danger=0`).
- markdown-it-py is a reference reader, not ground truth; a body both readers
  get wrong is not detected.
- the merge onto origin main 1dfbb4d1 was not done here (no fetch, by the
  brief); the change is confined to the checker, its tests and this directory.
