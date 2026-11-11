# CON-030 independent review, round 6 (sections 11.4.142 / 11.4.209 / 11.4.194(6))

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner), round 6; vehicle items CON-070, CON-192..CON-195 |
| Bundle | `con030_r6/con030_r6.bundle`, sha256 3d04d890434214837fc7fd3c0af225bd942ab4d79b00e5ab52454ede38e6e3d4 (checked); `git bundle verify` OK once the prerequisite 64ac151d was fetched from the github remote (it was not in /home/milosvasic/Projects/constitution); head 10ad4e05bcb20ce1767ba66635b546aebcb35df9, 27 commits over main 64ac151d (ancestor checked) |
| Round | 6, past R_max under the standing operator decision recorded in CON-030 ("Keep running rounds until GO is reached!") |
| Reviewer | a fresh independent subagent running on Opus 5.5 (claude-opus-5-5), not the author. The dispatch path does not report effort to me, so I claim no effort level (section 11.4.231(F.2)) |
| Sandbox | `74ce2b36-.../scratchpad/rev_con030_r6/` (clone in `constitution/`), git isolated with `GIT_CONFIG_GLOBAL=<sandbox>/home/gitconfig GIT_CONFIG_NOSYSTEM=1`, `TMPDIR` inside the sandbox. HOME not reassigned. Nothing pushed, nothing outside the sandbox changed. No process I did not start was touched |
| Verdict | **NO-GO**: 2 important, 1 important (evidence, carried), 2 minor, 2 nit |

## Verdict in one paragraph

The round-6 code does what the author claims for the members it tests: self-test 539/0 and the Go suite 80/0 reproduce on the head, the 65-case guide matrix passes, MX7/MX10 RED evidence is consistent, K5 replays (RED traceback on main 2e8cfb90's engine, GREEN fingerprint on the head), F8's probe and F7's duplicate-path proof are in the self-test, and the tracker re-mint is clean. But three of my four own mutants on the round-6 code SURVIVE the whole self-test, and two of them have measured, reachable bad effects on the exact class this structural round declares closed: with RV6f, `--sync-guide` deletes guide prose and exits 0 where the head refuses; with RV6a, `--verify-manifest` says MANIFEST-OK on a stale block hidden behind U+2060 or U+00AD. The matrix pins near-markers only on the begin line in a way that separates them from "begin alone", and pins Cf only through two code points. Beyond that, the round's own docstring ("an invisible leading character can never hide a block") is refuted by default-ignorable characters that are not category Cf. The F4 obligation (whole mutation table on the merged head) is still open by the author's own statement.

## Findings

| Id | Severity | finding_layer | Where | What, measured |
|---|---|---|---|---|
| G1 (RV6f) | important (proof-of-batch: a reviewer mutant surviving on this batch's proving guard, sections 11.4.194(6)(d), 11.4.235(D)) | source-defect (test gap) | `guide_parse` near list; matrix in self-test 2b | Mutant: near detection for the END marker reduced to white space only (`startswith((GUIDE_BEGIN, GUIDE_END))` -> `startswith(GUIDE_BEGIN) or l.strip() == GUIDE_END`). Survives 539/0. Cause: every `near:*:end` case is `[B, S, f(E)]`, whose outcome (class "marker", rc 3, unchanged) is the same as "begin alone"; the `outside` cases put the near shape on the begin marker only. Effect, measured (probe2): guide `B / stale / "<!-- census:end --> (old)" / IMPORTANT PROSE / E`: head verify rc 3, sync rc 3, prose kept; mutant sync rc 0 and the prose line is DELETED. Fix: add cases where an end near-marker sits outside a block or between a block and a later real end, with a byte-identity check; adopt RV6f verbatim |
| G2 (RV6a) | important (same reason as G1) | source-defect (test gap) | `marker_lead` | Mutant: `unicodedata.category(l[i]) == "Cf"` -> `l[i] in "​﻿"`. Survives 539/0: the matrix only uses U+200B and U+FEFF. Effect, measured: U+2060 (word joiner) or U+00AD (soft hyphen) in front of both markers of a stale block: head verify rc 3, mutant rc 0 MANIFEST-OK. Fix: add at least one other Cf code point (U+2060) to the NEAR set; adopt RV6a verbatim |
| G3 | minor (minor-class: a guide census-sync check, not a critical-invariant / security / data-safety surface; a reappearing member of r5 F3, section 11.4.276(C)/(E)(2)) | source-defect | `marker_lead` / `guide_parse` docstring and guide line 34 | The rule strips white space and category Cf only. Measured on the head (probe_head.txt, sha256 86a2c918...): a stale block whose two markers start with U+034F (combining grapheme joiner, Mn), U+FE0F (variation selector, Mn), U+3164 (Hangul filler, Lo) or a non-UTF-8 byte (read as U+FFFD), or carry U+200B INSIDE the marker, gives `--verify-manifest` rc 0 MANIFEST-OK. U+034F/U+FE0F/U+3164 are Default_Ignorable_Code_Point and render as nothing, so the docstring claim "an invisible leading character can never hide a block from the reader" is false, and the matrix pins `text:inner_zwsp:both` as a deliberate pass of a visually exact marker. Also, deleting the block entirely passes (by design, guide line 34). Proposed tracked follow-up: normalise a line by removing every Default_Ignorable code point (and treat U+FFFD as a near signal) anywhere in the line before the near test, or record an operator decision (section 11.4.66) that the repository's own guide must carry a block. Either keeps backticked / prose quotes legal |
| G4 (RV6b) | minor (the F9 nit's own guard; reachable but low impact) | source-defect (test gap) | `replace_lines` mode keep; self-test 2c | Mutant: `mode = stat.S_IMODE(os.lstat(p).st_mode)` -> `mode = 0o600`. Survives 539/0: the only mode case uses 600. Effect, measured: a 644 guide becomes 600 after `--sync-guide` on the mutant, 644 on the head. Fix: assert a second mode (644 or 640) in 2c; adopt RV6b |
| G5 (= r5 F4, carried) | important (evidence for landing) | test-instrumentation | mutation table | Author states the 186-row run on the merged head is in progress, 9 rows done. Not complete, so not evidence. Must be complete and all killed (plus G1, G2, G4 rows) before GO |
| G6 | nit | process-doc | CON-195 (flake) | Registered, UNREPRODUCED, acceptance criterion defined: acceptable as a tracked item; it stays open. Observation for it: several `rfs_selftest.*` directories coexist under one TMPDIR when runs are parallel (mine did), so the "shared TMPDIR cleanup" candidate is plausible but UNCONFIRMED |
| G7 | nit | process-doc | `con030_r6_k5_nonutf8_red_green.sh` | Uses `rm -rf -- "${w:?}"` behind a TMPDIR prefix check rather than `safe_rm_rf` (section 11.4.287(B)); guarded, acceptable, prefer the helper. The class sweep r5 now reports D=103 on the head (was 101); not re-classified in round 6 (r5 F6 not addressed; still minor/process-doc) |

## Prior findings (review r5), checked on the head

| r5 | Status | Evidence |
|---|---|---|
| F1 MX7 | closed | row in table; matrix `block:end_only` kills it per author RED file; my baseline self-test 539/0 includes it |
| F2 MX10 | closed | matrix `block:extra_after/extra_before`; same |
| F3 | partly closed: trailing text, NBSP, leading ZWSP/BOM, leading U+2060/U+00AD refused (measured); other invisibles and inner ZWSP still pass (G3), and the guard does not pin the general rule (G1, G2) |
| F4 | open (G5) |
| F5 | registered as CON-195 (G6) |
| F6 | not addressed in round 6 (G7) |
| F7 MX2 | recorded EQUIVALENT in the table header, with the duplicate-path check (`ok CON-030 r6 F7` x2 in my log) |
| F8 MX5 | adopted; `ok CON-030 r6 F8: esc_out escapes a lone high surrogate as text` |
| F9 | symlink refusal pinned (link kept, target unchanged); mode keep pinned for 600 only (G4) |
| F10 | replay script runs: RED `UnicodeEncodeError ... surrogates not allowed` on main 2e8cfb90's engine, GREEN `GENERATED_SETS has actions/generated: True` plus a fingerprint on the head |
| F11 | noted in the CON-030 description |

## Runs on the head (10ad4e05)

- `bash tests/test_run_full_suite.sh`: `passed=539 failed=0` (6 min 25 s), log sha256 da378968ea4ab4c598af2536fe3132fa6445f31336d76b2cc25bc291894223ad; 67 `guide matrix` ok lines, 0 `FAIL `.
- `bash tests/test_run_full_suite_go.sh`: `SUMMARY pass=80 fail=0`, log sha256 172345ac3a797cbfdfe263847d2b064bb2a6babfad6339ff1ffbf35a848d2230.
- `bash tests/test_run_full_suite_go_mutations.sh` (main's, on the merged engine): rc 0, `SUMMARY mutants=18 killed=18 survivors=0 not_applicable=0` after `baseline: unmutated copy passes the whole Go test file (SUMMARY pass=80 fail=0)`, log sha256 96893ed2c0fc3ee813f821818452101efad7e77f42cbc3f33684229c3e1f2078 (three Python DeprecationWarning lines about invalid escape sequences in the harness's mutation strings; harmless today, a nit for main)
- Tracker: built `workable-items` from the head; `validate`: `OK — 194 items, all invariants satisfied`; `diff --issues --fixed`: `in sync (compared 194 ... 194)`. Against main 64ac151d (189 items): only CON-030 changed (status, description appended — main text is a prefix of the head text — reproduction/investigation fields); new: CON-070, CON-192..CON-195, each with its full chain of "Id history" paragraphs (CON-108 -> 116 -> 146 -> 163 -> 186 -> 192 and so on), no blanket replace; main's CON-149, CON-166, CON-186, CON-189, CON-191 keep main's titles.

## My mutants (section 11.4.194(6)(d)), none written by the author

Each applied as an exact single-occurrence replacement to a copy of the head engine, then the head's whole self-test run against the copy (`FSR_RUNNER`). Baseline copy: `BASE rc=0 failing_checks=0 last=passed=539 failed=0`.

```
RV6a rc=0 failing_checks=0 last=passed=539 failed=0     # Cf narrowed to U+200B/U+FEFF        SURVIVED
RV6b rc=0 failing_checks=0 last=passed=539 failed=0     # kept mode hard-coded to 0o600       SURVIVED
RV6c rc=1 failing_checks=7 last=passed=532 failed=7     # marker_lead strips one char only    killed (7)
RV6f rc=0 failing_checks=0 last=passed=539 failed=0     # end near-marker = white space only  SURVIVED
```

Rows (TAB separated: id, old, new) in `rev_con030_r6/mut/rows.tsv`; runner `mut/runmine.sh`; logs and diffs `mut/<id>.log`, `mut/<id>.diff`.

Effects of the survivors (probe2, sha256 7ec736667402e9d4c89ab15c3d8a1033d098192db7007e9e8a25960ff021bb95):

```
== BASE
RV6f-probe verify rc=3 ok=False; sync rc=3; prose kept=True
RV6a-probe (U+2060 both) verify rc=3 ok=False
RV6a-probe (U+00AD both) verify rc=3 ok=False
RV6b-probe sync rc=0 mode after=644
== RV6f
RV6f-probe verify rc=3 ok=False; sync rc=0; prose kept=False
== RV6a
RV6a-probe (U+2060 both) verify rc=0 ok=True
RV6a-probe (U+00AD both) verify rc=0 ok=True
== RV6b
RV6b-probe sync rc=0 mode after=600
```

Residual class members on the unmutated head (probe, sha256 86a2c918507bfe11b5e99fc93c4e7c22776a96c8a0f910e283b082f1c5ac34d3):

```
control_stale_exact verify rc=3 ok=False stale=True
inner_zwsp_both verify rc=0 ok=True stale=False
lead_ff_byte_both verify rc=0 ok=True stale=False
lead_cgj_U034F_both verify rc=0 ok=True stale=False
lead_hangul_filler_U3164_both verify rc=0 ok=True stale=False
lead_VS16_UFE0F_both verify rc=0 ok=True stale=False
lead_wordjoiner_U2060_both verify rc=3 ok=False stale=False
lead_softhyphen_U00AD_both verify rc=3 ok=False stale=False
fullwidth_lt_both verify rc=0 ok=True stale=False      (visible: prose, not a finding)
block_deleted verify rc=0 ok=True stale=False          (by design, guide line 34)
```

## Needed for GO

1. G1, G2: add the missing matrix cases, observe RV6f and RV6a fail the suite, adopt them verbatim (and RV6b with a second mode case, G4).
2. G5: complete the whole mutation table on the merged head, all killed.
3. G3: either widen the near rule to default-ignorable characters anywhere in the line (with cases), or register it as a tracked follow-up with a proposed fix, or record an operator decision that the block may be absent / hidden as prose. As minor-class it may ride as a follow-up under section 11.4.276(G.2) once G1, G2, G5 are closed.
4. G6, G7 may stay tracked follow-ups.
