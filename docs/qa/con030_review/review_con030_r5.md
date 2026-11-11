# CON-030 independent review, round 5 (section 11.4.142 / 11.4.209)

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner), round 5; follow-up items CON-070, CON-146, CON-147, CON-148 |
| Bundle | `con030_r5/con030_r5.bundle`, sha256 4af01eaaa976b317da8d9e30f0acc33a3b9da0b236172de9cac8faefb2180164 (checked), head dc12760730c3cd59eef9f2520d6748e0549425bc, range 2e8cfb90..dc127607 (21 commits) |
| Round | 5. It runs past R_max because of the relayed operator decision recorded in the CON-030 description ("Keep running rounds until GO is reached!") |
| Reviewer | independent subagent on Opus 5.5, not the author. The dispatch path does not report effort to the agent, so I claim no effort level (section 11.4.231(F.2)) |
| Sandbox | my own scratchpad `74ce2b36-.../scratchpad/rev/`: a fresh clone, the bundle fetched into it, git isolated with `GIT_CONFIG_GLOBAL=<sandbox>/home/gitconfig GIT_CONFIG_NOSYSTEM=1`, `TMPDIR` inside the sandbox. HOME was not reassigned. `/home/milosvasic/Projects/constitution` was not touched, apart from reading its origin URL. Nothing was pushed or tagged |
| Verdict | **NO-GO**: 2 important, 3 minor, 6 nit (11 findings) |

## Verdict in one paragraph

Most of round 5 is right and measured. K1's whole-line markers and byte-exact rewrite hold: a CRLF guide with 0xff and 0xfe bytes outside the block is rewritten with every outside byte kept, and an end marker before the begin marker is refused with rc 3. K2 and K12 now exit 3 with a RESULT line and write nothing. K3 decodes before it escapes. The merge port of `QuickIdent.gen` and `gen_fingerprint` (bytes names, `hrec` framing, `None` when unknown) is correct. M27 is really dead on main 2e8cfb90: its anchor occurs 0 times in main's engine, and the re-anchored row is killed. The tracker re-mint is clean (see the tracker section). The self-test passes 461/0 on the head.

Two of my seven own mutants survive, and they sit in the K1 code this batch added (MX7, MX10). Each has a measured effect: `--verify-manifest` says **MANIFEST-OK** rc 0 on a guide whose census block is stale or broken, where the head says rc 3. A third gap (R1) is not a mutant but a regression against round 4 and main. If the marker lines carry trailing text, the head no longer sees the block and says MANIFEST-OK on a stale block, while round 4 and main both say MISMATCH rc 3. Under section 11.4.235(D) and 11.4.276(D), a reviewer mutant that survives on a proving guard of this batch is proof-of-batch, not minor-class. That blocks GO. The fixes are small. Separately, the 31-row mutation subset is not enough evidence for the merged head (F4).

## Findings

| Id | Severity | finding_layer | Where | What, measured |
|---|---|---|---|---|
| F1 (MX7) | important (proof-of-batch, not minor-class) | source-defect | `guide_parse`: `if not begins and not ends: return lines, None, None, None` | My mutant `if not begins:` survives the whole self-test (461/0). Effect: a guide with an end marker and no begin marker (the begin line was deleted) gives MANIFEST-OK rc 0 on the mutant and rc 3 on the head. The author report says a missing end marker is refused, and that case is tested. A missing begin with an end present has no test. Fix: add a fixture with an end marker only, expect rc 3 with the reason text, and adopt MX7 verbatim |
| F2 (MX10) | important (proof-of-batch, not minor-class) | source-defect | `guide_check`: `if [l for n, l in lines if a < n < b] == want` | My mutant `[...][:1] == want` survives (461/0). Effect: a block that holds the correct census line plus one extra stale line `census: stale total=99` gives MANIFEST-OK rc 0 on the mutant and "census block is stale" rc 3 on the head. No test has more than one line inside the block. Fix: add that fixture and adopt MX10 |
| F3 (R1) | minor (minor-class) | source-defect: a new member of the declared marker class, introduced by the K1 fix (a fail-open, section 11.4.201(6)) | `guide_parse` whole-line match plus "no block means nothing to check" | Fixture: `<!-- census:begin --> (generated)` / a stale line / `<!-- census:end --> (generated)`. The head gives `--verify-manifest` MANIFEST-OK rc 0 and `--sync-guide` "has no census block; nothing was written" rc 0. Round-4 engine 6a645831: "census block is stale" rc 3. Main 2e8cfb90: the same rc 3. A ZWSP (U+200B) in front of both markers also gives MANIFEST-OK on the head. The near-marker rule covers only white space. Fix options: refuse a line that starts (after white space) with a marker but is not exactly a marker, or treat the block as required when the guide exists. Either needs a decision that keeps quoted markers in prose legal (the point of K1) |
| F4 | important (evidence for landing) | test-instrumentation | mutation table, author report section "Mutation run" | Only 31 of 177 rows ran, and 6 of those ran before the 2e8cfb90 merge. The merges rewrote existing checks: the "IDENTITY CHANGED before unit ..." and "at the end of the run" assertions became "after unit ..." (WIT-C02 after-unit check), and the `#` and NEL census fixtures were rebuilt for K12. Rows whose killing tests changed (I1, I2, I3, RW3, Z7) were not re-run by the author. I re-ran those five on the head and all were killed (7, 2, 15, 3 and 2 failing checks), so I found no dead row. That is still 36 of 177 rows, not the whole table that the r4 landing plan step 5 required. The subset is not enough for a GO claim on the merged head. Run the whole table after the F1 and F2 fixes (parallel shards, each with its own baseline) |
| F5 | minor | test-instrumentation (sections 11.4.248, 11.4.197) | author report RED/GREEN | The first post-merge self-test run had 8 failures because the self-test's own mktemp tree lost files ("cannot change to .../good"). The cause is recorded as UNKNOWN, a re-run passed, and no tracked item was registered (I searched docs/Issues.md). A flake of unknown cause in the proving suite needs its own item |
| F6 | minor | process-doc | `con030_class_sweep_r5.py` result in the author report | The report says "this head D=100". On the head (dc127607, and on baacd4fc) the sweep prints D=101 and C=77; D=100 and C=67 were at c74e3554, before the 2e8cfb90 merge. The merge added the unclassified D site `need_tracked = code.endswith("+tracked")` (main's CON-047). By my reading it is benign: a suffix of a field that is already TAB-split, and F47a guards it. The sweep was not re-run after the second merge |
| F7 (MX2) | nit | test-instrumentation (reasoned equivalent) | `--verify-manifest`: `for hv in (False, True)` | My mutant `(False,)` survives. I reason it is equivalent: in full mode every unit has args `()`, and its key is unique unless the manifest repeats a path, which `read_manifest` refuses ("duplicate path", rc 3, measured). Record it as reasoned EQUIVALENT in the table header, as K2m is |
| F8 (MX5) | nit | source-defect (unreachable by reading) | `esc_out` fallback branch | My mutant (fallback replaced by `pass`) survives. A probe gives head `'a\\ud800b\\udcc2\\udc85'` and mutant raw surrogates. A lone surrogate outside U+DC80..U+DCFF never comes from `os.fsdecode`. I found no reachable source except a hand-edited JSON record. Record it as equivalent, or add the unit probe |
| F9 | nit | source-defect (pre-existing since round 4) | `replace_lines` | `--sync-guide` replaces a symlinked guide with a regular file and keeps the link target unchanged (it says success). It also does not keep the file mode (600 became 664 under the umask). The docstring's "every other byte is copied unchanged" is true for the content only. State this in the guide, or stat and copy the mode |
| F10 | nit | process-doc | `con030_r5_k5_nonutf8_red_green.txt` | The RED half holds only the last two traceback lines, without the command or the input. The sha256 matches the report (0d91f0ee...) |
| F11 | nit | process-doc | tracker history | Vehicle commit ede6686e holds a tracker in which CON-116, CON-117 and CON-118 are the CON-030 items, while on main those ids are other items. With no rewrite (section 11.4.113) this is correct and documented. Name it in the landing PR text so a reader of the history is not misled |

## Claimed fixes checked

| Claim | Result | How |
|---|---|---|
| K1 whole-line markers | holds for the cases tested; F1, F2 and F3 are gaps | probes e, c, t, z, z2, e7, e10 (`r1_probe.txt` sha256 a42092b4..., `survivor_probe.txt` ed3870c7...) |
| K1 byte-preserving rewrite | holds for content (CRLF, 0xff, 0xfe kept, measured with `od -c`); mode and symlink not kept (F9) | probe c |
| K2 / K12 exit 3 | holds; MX3 (`if cprobs and write:`) killed with 2 failing checks | own mutant |
| K3 decode-then-escape | holds (`\udcc2\udc85` → `\\x85` text, never a raw NEL) | unit probe |
| K9 | holds; the full-mode half is equivalent (F7) | MX2 + duplicate-path probe |
| merge port (QuickIdent.gen, non-UTF-8 name) | correct by reading: `hrec` framing, `os.fsencode` names, `None` on OSError, `ident_unknown` checks gen; G1-G4, GU, GN, GC killed in the author's runs | code read |
| M27 re-anchor | justified: the anchor occurs 0 times in main 2e8cfb90's engine; the new row is killed | `git show 2e8cfb90:...` grep |
| near-marker rule | MX1 (`strip` → `lstrip`) killed with 1 failing check | own mutant |
| end-before-begin refusal | MX4 killed with 2 failing checks | own mutant |
| tracker re-mint | correct: items other than CON-030/070/146/147/148 byte-identical to main 2e8cfb90 (143 → 147 items); CON-116..118 keep main's items; CON-146..148 carry "Id history"; CON-147 is a Bug; `workable-items validate` OK (147 items); `diff --issues --fixed` in sync | built the engine from the head and ran it |
| real tree | `--verify-manifest` on the head tree rc 0 MANIFEST-OK, census total=869, the same as the author's line | run |

## Mutants (section 11.4.194(6)(d)), mine

I ran each mutant against the head's own self-test on a copy of the engine. The baseline unmutated copy passed 461/0.

| Row | Mutation | Result |
|---|---|---|
| MX1 | near check `l.strip()` → `l.lstrip()` | killed (1) |
| MX2 | verify plan loop `(False, True)` → `(False,)` | SURVIVED, reasoned equivalent (F7) |
| MX3 | `if cprobs:` → `if cprobs and write:` | killed (2) |
| MX4 | drop `ends[0] < begins[0]` | killed (2) |
| MX5 | `esc_out` fallback → `pass` | SURVIVED, unreachable by reading (F8) |
| MX7 | `if not begins and not ends` → `if not begins` | **SURVIVED, reachable false MANIFEST-OK (F1)** |
| MX10 | block compare `[...]` → `[...][:1]` | **SURVIVED, reachable false MANIFEST-OK (F2)** |

I also re-ran the author's rows whose killing tests changed in the merges: I1 killed (7), I2 (2), I3 (15), RW3 (3), Z7 (2).

## Is the 31-row subset sufficient?

No, not for GO (F4). The subset covers the rows that mutate code changed in round 5. It does not cover rows whose killing TESTS changed in the two merges, and the merge did change such tests. The five I re-ran still die, so no dead row is known, but 141 rows remain unmeasured on the merged head. The anchor-count check the author ran ("177 rows occur exactly once") shows a row can apply; it does not show the row is killed.

## Needed for round 6

1. Fix or test F1 and F2: add the fixtures and adopt MX7 and MX10 verbatim. Each must be observed failing the suite before the fix-side test lands.
2. Decide F3 and implement it (or record an operator decision that the block is optional), with a fixture.
3. Run the whole mutation table on the merged head (F4), and register the flake (F5).
4. Re-run the class sweep on the head and classify the new site (F6). Record F7 and F8 as equivalent.
5. The nits (F9, F10, F11) may become follow-ups.

## Evidence (my sandbox `74ce2b36-.../scratchpad/rev/`)

- `mymut.tsv` (my rows), `authrows.tsv`, `runmine.sh` (runner), `mymut_results.txt`, `auth_results.txt`, `mut/*.log`, `mut2/*.log`
- `r1_probe.txt` (sha256 a42092b4fe49752abbe269431d4b056c9d351d88574096247f3052781a7891bb): F3, F9
- `survivor_probe.txt` (sha256 ed3870c74a1a66dc2742c43b48a9267dea539dcde74ecdc989c69e04ede9e75f): F1, F2, F8
- `probe/` fixtures; `e_<commit>.py` engine copies for the sweep counts
