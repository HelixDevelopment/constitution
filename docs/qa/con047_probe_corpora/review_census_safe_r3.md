# Independent re-review, round 3: vehicle/census-safe (head 2e5f352)

| Field | Value |
|---|---|
| Reviewer | review subagent, Claude Opus 5.5 (claude-opus-5-5); effort cannot be set or read on this dispatch path (11.4.231(F.2)), so no effort is claimed |
| Date | 2026-11-05 |
| Round | 3 of R_max 5 (11.4.276(G)); answers review_census_safe_r2.md (NO-GO, N1 blocking) and census_safe_r3_report.md |
| Head | 2e5f35218ac54b367af66d75814055f16f393ba3 (c41b6c7 merge of main 8e496db, 7ed1fe7 tests + separator, 2e5f352 tracker) |
| Bundle | census_safe_r3.bundle, sha256 2dc91810f7037317..., prerequisite cb31e32, verified |
| Workspace | /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv3.pGSK (h = pristine clone of the head, cv = census variants, tools = probe and judge scripts, *.out = evidence) |
| Method | read only; every run in a throwaway copy with HOME=$(mktemp -d) and TMPDIR=$(mktemp -d); no clone of the author modified; no push |
| Verdict | **GO-with-follow-ups** (section 11); landing is conditional on the recorded operator decision of section 9 |

## 1. What was run (this session, captured output)

| Check | Variant | Result | Evidence |
|---|---|---|---|
| jq-region test, census variants swapped in a copy of the test tree | head | rc 3, `== 52 passed, 0 failed, 5 known-failure ==`, non-pass only KNOWN-FAIL K1..K5 | rv3.pGSK/n1_runs.out |
| same | oldorder (= dbe1b65 census) | rc 1, `40 passed, 17 failed`: FAIL G1..G9, S1..S3, XPASS K1..K5 | n1_runs.out |
| same | RN1 (round-2 reviewer mutant) | rc 1, FAIL G6 G7 G8 (plus XPASS K1 K3 K4) | n1_runs.out |
| same | RN7 | rc 1, FAIL G9 | n1_runs.out |
| same | main 8e496db | rc 1, 34 passed / 23 failed | n1_runs.out |
| same | nosep (head without the separator) and r2 (bc788b7) | rc 1, FAIL S1 S2 S3, XPASS K5 | n1_runs.out |
| jq-region test in the repository at the head | head | rc 3, 52/0/5 | jqr_head_inrepo.out |
| kcase signature, wrong direction | K1 expected at line 3 | `FAIL K1 ... does NOT match the CON-047 signature`, rc 1 | cv/t_wrongline.sh run |
| kcase with a broken census | crash / rc 4 after output / kind=direct | rc 1, all or most cases FAIL | cv/crash.py, rc4.py, kinddirect.py runs |
| real-tree census (absolute paths, rc captured on its own line) | head, nosep, main, oldorder, r2 | gates 187, census rc 0, 170 rows, 0 jq-env rows, 7 eval rows, identical md5 for all five; positive control CONSUMER_ROOT 22 hits, negative control 0 | rt_*.tsv, rtn_*.tsv, rtn2_*.tsv |
| S1 needle in a copy of the real tree | head / nosep / main | fires on head (line 388), quiet on nosep and main | needletree.* |
| wide corpus: every tracked shell file, two variants | nosep vs head, main vs head | 1224 files, 0 errors, 0 differing files, 2 jq-env rows each (the needle fixture and the test file itself); both class needles detected | wide_nosep_head.out |
| fuzz, 6000 random lines | nosep to head | 0 reports lost, 838 added; reversed control 838 lost | tools/fuzz_mono.py |
| fuzz | main to head | 0 lost, 852 added | tools/fuzz_mono.py |
| probe corpus, 57 shapes, real census CLI, every census rc 0 | head, nosep, main, 6 mutants | head FN 6 / FP 18; nosep FN 19 / FP 8; on the first 52 shapes main = nosep FN 16 / FP 8 | probe_corpus.out, probe_mut.out |
| runner judge and known-row matching, the runner's own functions | rc 3 log, rc 1 log | rc 3 is FAIL `rc_3`; a log-substring known row marks an rc-1 log KNOWN; a `reason:rc_3` row does not | tools/judge_probe.py |
| runner manifest check | head, c41b6c7, bc788b7, 8e496db | `MANIFEST-MISMATCH` 24 problems at the head, 25 at the other three | — |
| closure test, pristine clone | head | rc 3, `KNOWN-FAIL N3 negative ... (rc=1, signature matches CON-047)`, `== 31 passed, 0 failed, 1 known-failure ==`, 246 s | closure.out |
| allowlist gate | head | rc 0, `VERDICT: PASS ... gates=187 reads=170 guarded=54 allowlisted=116 uncovered=0 stale=0 needle=ok` | — |
| allowlist mutation test, pristine clone, background | head | see section 7 | mut.out |
| tracker engine validate / diff / export | head | `validate: OK — 47 items`; `diff: DB and Markdown are in sync`; db-to-md and export regenerate Issues.md, Fixed.md and both summaries byte-identically | trk/ |
| durability bundle | con017_evidence_94a1d28.bundle | sha256 9814832c... matches; verify OK inside a repository, complete history; fresh clone at 94a1d28, no alternates, `git fsck --full` rc 0, empty output | dur2.out |
| evidence archive | con017_rv4_opus_evidence.tar.gz | sha256 d417cbef... matches, 94 entries | — |
| secrets scan of the three commits | head | 0 hits, positive control 1 | — |
| syntax | changed shell and Python files | `bash -n` OK, Python ast.parse OK | — |
| gitlinks | head vs main | 27 unchanged | — |

A first attempt at two of these runs was wrong and was redone, not counted: `git bundle verify` outside a repository (dur.out, verify_rc 1) and a real-tree census with a relative path under `cd /` (rc 2, 0 rows; caught by the positive control).

## 2. Status of the round-2 findings

| Id | Round-2 rating | Status at 2e5f352 |
|---|---|---|
| N1 | important, source-defect, blocking | **Fixed.** G6..G9 are in the test verbatim; the old order fails G1..G9, RN1 fails G6..G8, RN7 fails G9, the head passes. The meta-test kills RN1 and RN7 as R1 and R2 (section 7). |
| N2 | minor, source-defect, latent, fail-closed | **Recorded, not fixed** (accepted). K1..K5 are KNOWN-FAIL cases with a signature check both ways; no owner rule was added. See N2-K5 below and R3-3. |
| N3 / F7 | minor, source-defect, pre-existing | **Fixed** by the one-line separator at the closing quote. S1..S3 RED before, GREEN after; real tree byte-identical; monotone against main (section 4). Two sub-properties of the separator are unpinned: R3-1, R3-2. |
| N4 | minor, process-doc | **Partly fixed.** Residual shapes and the stop rule are on CON-047; F5, F6, F7 are fixed rather than tracked. Open: the wip ref still points at dbe1b65 on every upstream; the follow-ups of this round need items (section 10). |
| N5 | nit, process-doc | **Fixed** (a), (b), (c) in the CLASS RULE comment; one new precision nit, R3-10. |
| F4 | minor, process-doc | **Fixed in substance.** Self-contained bundle and archive exist and verify. Residual: both are host-local; R3-12. |
| F5 | minor, test-instrumentation | **Fixed.** Manifest row added; the meta-test runs the jq-region test (R0 baseline + R1..R3). |
| F6 | minor, test-instrumentation | **Fixed.** Unmutated closure baseline `cbase` must exit 3. |
| F8 | nit | **Fixed** by an attribution note in the description (history rows are append-only). |

## 3. kcase: is the signature checked both ways, and can a known failure hide a new regression?

Inside the test: no fail-open found. A case is KNOWN-FAIL only when the census exits 0 and there is exactly one jq-env row of kind `indirect` at the declared line; zero rows is XPASS and counts as FAIL; any other row set, kind, line or census exit status is FAIL. Any FAIL makes the test exit 1, and only an all-known remainder exits 3. Measured: a wrong line, a crashing census, census rc 4 after output and kind=direct each give rc 1.

Two fail-open channels exist one layer out, both latent today:

- (a) The full-suite runner treats rc 3 as FAIL `rc_3`. Once its manifest stops refusing, someone will add a known-failure row for the closure test and the jq-region test. A row with a log-substring signature (for example `[tracked CON-047]`) also matches a log that carries a new real FAIL beside the known one: measured with the runner's own `judge()` and `match_known()`, an rc-1 log is marked KNOWN by such a row and is not by a `reason:rc_3` row. R3-4.
- (b) The census keeps one jq-env row per file and the allowlist matches (glob, VAR) for the whole file. Curing a K-shape false positive with an allowlist row would therefore hide every later real jq dump in that file. The cure must be a code change under CON-047, never an allowlist row. R3-5 (same family as the round-2 F3 residual).

## 4. The separator: monotonicity, real tree, and the K5 net effect

The change is `rl.append((owner, "\n"))` at the closing quote of a single-quoted region, plain or ANSI-C. It only adds text between regions, so it can only add reports; it cannot remove a report another region made. Measured: real tree identical (187 / 170 / 0 jq-env / 7 eval) on head, nosep, main, oldorder, r2; 1224 tracked shell files, 0 differing; fuzz 6000 lines, 0 reports lost; S1 needle fires on head only.

Net effect on my 57-shape corpus (contrived shapes, no prevalence estimate):

- False negatives fixed by the separator: F01..F05, F10, F14, F20, F24, F25, F27..F29 (13).
- False positives the separator introduces: Q01 (= K5), Q04, Q08, Q10, Q11, Q14, Q19, Q21, Q22, Q28 (10). This class is wider than K5's "data argument of jq": it is any quoted word that is or starts with `env` belonging to any command on a jq line, for example `jq -r '.a' f | grep -v 'env'`, `jq '.a' f; echo 'env'`, `jq -r '.k' f | tr -d 'env'`, `jq -n '$x' --arg x 'env'`. The same class already exists on main for the last region of a line (Q05, Q12, Q20, Q23..Q26 fire on main and head alike); the separator moves the other regions into it. R3-3.
- Still false negatives on the head, all quiet on main too: F08, F09, F26 (`'env'` followed by another region on the line; Python `$` is not MULTILINE, so `env\n...` mid-blob does not match), F11 (`jq -n '$ENV' | jq '.PATH'` read as a named PATH read), F13 (double-quoted program, R3-6), F16 (`[env]`).

Under the declared fail-closed policy (CON-015, 11.4.201(4)) and with zero affected real files, the net effect is positive. It is not free: a false positive blocks a commit, and its only safe cure is code (section 3(b)).

## 5. Reviewer mutants (none is in the author's set)

| Mutant | Change | Suite at head | Behaviour change | Rating |
|---|---|---|---|---|
| mD_plainonly | separator only for plain `'..'`, not `$'..'` | **survives** 52/0/5 | F27..F29 go quiet (back to main); 71 of 3000 fuzz lines differ | R3-1 |
| mM_pipe | separator `"|"` instead of `"\n"` | **survives** 52/0/5 | adds 424 of 3000 fuzz reports; Q02, Q03, Q06 fire | R3-2 |
| mL_semicolon | separator `";"` | killed (FAIL S2, XPASS K5) | — | — |
| mA_open | separator at the opening quote of the plain path | differs only for `$'..'` | — | covered by R3-1 |
| mB_space | separator `" "` | equivalent (0 of 3000 differ) | none | — |
| mO_otherowner | separator tagged with a different owner | equivalent (0 of 3000 differ) | none | — |

Ready pins, measured: F27 `jq --arg nl $'\n' -n 'env | keys'`, F28 `jq -n --arg t $'a\tb' 'env | keys'`, F29 `jq -r $'.a' f; jq -n 'env | keys'` fire on the head and are quiet on mD, nosep and main; Q02 `jq --arg src 'env' -n '$src'` is quiet on the head and fires on mM.

## 6. Tracker

- CON-047 was edited through the engine only. History: row 47 `Opened by=User` (the intake default, corrected in the description), row 48 `Updated by=AI`, reason `reproduction UNSET -> reproduced-host-fixture`. A probe on a scratch database shows that one `update` call carrying both a description and a state writes exactly one such row, so the history fits an engine edit. The reason text does not mention the description change (engine behaviour, R3-9).
- validate OK (47 items; the closure gate is not armed in this engine run, so validate proves form, not closure custody), diff in sync, the four derived documents regenerate byte-identically; no hand edits found.
- Reproduction record: `reproduced-host-fixture`, surface host-only, evidence docs/qa/con047_reproduction_2026_11_05.txt; every sha256 in that file matches 7ed1fe7. Investigation state is UNSET (R3-11).
- Ids: CON-049 and CON-050 belong to vehicle/ownership-wave2 (head 3b0f3c1), CON-048 to another wip branch; no other bundle uses CON-047 or above. No collision.
- Trial merge of both vehicles: conflicts in Issues.md (pure append), Issues_Summary.md, the guide census line and the binary DB. A union through md-to-db gives 49 items and validate OK but drops the Opened history rows of CON-049 and CON-050. Landing note L3.

## 7. Allowlist mutation test (pristine clone of the head, background)

`mut_rc=0 secs=1606`, `META PASS: CM-GATE-ENV-READS-ALLOWLISTED kills every mutant`, 39 `ok` lines. The only two lines that match FAIL are the `ok` baseline lines whose text says "KNOWN-FAIL". Among them:

```
  ok   baseline closure test unmutated rc=3 (only the tracked KNOWN-FAIL outstanding)
  ok   R0 jq-region test unmutated rc=3 (only tracked KNOWN-FAIL cases outstanding)
  ok   R1 killed: whitespace-prefixed NAME= not an assignment owner (RN1)
  ok   R2 killed: += not an assignment owner (RN7)
  ok   R3 killed: quoted regions of one line glued (no separator, F7)
```

The clone's working tree was clean afterwards (`git status --porcelain` 0 lines). The meta-test kills only the round-2 reviewer mutants and the separator removal. It holds neither R3-1's mD nor R3-2's mM, which is why both survive.

## 8. Commits

- c41b6c7 is exactly main's delta (oracle gate, its mutation test, test_gate_env_overrides_guarded.sh); clean.
- 7ed1fe7 and 2e5f352 carry `Roadmap-Item: CON-047` and an honest `Co-Authored-By: Claude Opus 5.5` (the author stated the deviation from the brief). 7ed1fe7 changes three paths outside CON-047's file-scope manifest (config/full_suite_manifest.tsv, docs/guides/full_suite_runner_guide.md, scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh) with no `Out-of-scope:` trailers (11.4.293(A)); the G6..G9 cases prove the CON-015 fix but are attributed to CON-047; the separator closes F7, which had no item. Earlier commits of the vehicle (bc788b7 and before) carry no Roadmap-Item. R3-7.
- Secrets: 0 hits. Gitlinks unchanged.

## 9. Heuristic tower (11.4.250) and the round-3 structural trigger (11.4.276(E)(1))

The trigger fires: round 2 had N1 (important) and N2 (minor) in one named class, "the census does not know which simple command and operand a quoted region belongs to". Under (E)(1) round 3 should have been a structural round, and "a structural fix recommended by a reviewer may not be deferred past this point without a recorded operator decision (§11.4.66)". The round-2 reviewer recommended that the structural rewrite go to CON-047 and not into this vehicle.

On the merits the deferral is sound: the head is monotone against main by construction and by measurement, the change is fail-closed, no owner layer was added (one line of separator, the rest tests), the stop rule is written into the census comment and onto CON-047, and the rewrite corpus is preserved and verified. A related operator decision exists (agent memory, 2026-11-03: after the second env-class NO-GO, "declare the census best-effort tripwire (undetected forms listed, like 11.4.287)"), but it was made for an earlier review loop, does not name this vehicle or CON-047, and is not recorded in the repository. I found no decision that names this deferral. **Recording one, naming vehicle/census-safe and CON-047, is a landing precondition** (L1). Without it, (E)(1) requires round 4 to be structural.

What must stay recorded on CON-047 for the rewrite:

1. The stop rule: no further regex owner rule in gate_env_census.py; every new residual becomes a case.
2. The widened false-positive class of R3-3 (other commands' quoted words on a jq line), with at least one more kcase beside K5, for example `jq -r '.a' f | grep -v 'env'`.
3. The remaining false negatives F08, F09, F26, F11, F16, and F13 or a pointer to the item that owns double-quoted programs (R3-6).
4. The rule that a false positive is never cured with an allowlist row (section 3(b)).
5. The runner known-row guidance: `reason:rc_3` for both the closure test and the jq-region test (R3-4).
6. The operator deferral decision (L1).
7. The durable location of the 94a1d28 corpus and the probe corpora, and pushing the ref (R3-12).

## 10. New findings (round 3)

Every finding carries a `finding_layer` (11.4.235(D)) and a severity (11.4.276(G.2)). None touches a 11.4.239 critical-invariant surface, a security finding, data safety (§9) or host safety (§12).

| Id | Severity, layer | Finding | Follow-up |
|---|---|---|---|
| R3-1 | minor, test-instrumentation | The separator's `$'..'` member is unpinned: mutant mD survives the whole suite and turns F27..F29 quiet. The behaviour at the head is proven by my probes this session and the mutant is no worse than main, so no batch claim (S1..S3, monotonicity, real-tree identity) is invalidated. A strict reading of 11.4.235(D) ("a proving guard whose reviewer-authored mutation survives") would make this a source-defect; I rate it test-instrumentation because the batch never claimed the `$'..'` member and the protected behaviour is proven by captured probes. | Add F27..F29 as fire cases (test-only). |
| R3-2 | minor, test-instrumentation | The separator's neutrality is unpinned: mutant mM (`"|"`) survives and adds 424 of 3000 fuzz reports. | Add Q02 as a quiet case (test-only). |
| R3-3 | minor, source-defect, latent, fail-closed | The separator widens a false-positive class that CON-047 describes too narrowly: not only "a data argument of jq" (K5) but any quoted `env` word of any command on a jq line (Q04, Q08, Q10, Q11, Q14, Q19, Q21, Q22, Q28). Zero real instances (real tree and 1224 tracked shell files). The census comment does not name the class either. | Record on CON-047 with at least one more kcase; name it in the comment. |
| R3-4 | minor, test-instrumentation | The full-suite runner reads rc 3 as FAIL `rc_3` (measured; resolves the author's UNCONFIRMED). A known-failure row with a log-substring signature would mask a new real FAIL in the same log. No row exists and the manifest refuses every run today. | Record `reason:rc_3` as the required signature for both tests. |
| R3-5 | minor, process-doc, pre-existing | File-wide allowlist rows plus one jq-env row per file mean an allowlist cure for a K-shape false positive hides later real dumps in that file. | Record the rule on CON-047. |
| R3-6 | minor, source-defect, pre-existing, untracked | Double-quoted jq dump programs (`jq -n "env | keys"`, `jq -n "\$ENV"`) are not reported on main or the head. Zero real instances found. | Check CON-036 for the same defect first (11.4.214); else a new item. |
| R3-7 | minor, process-doc | Missing `Out-of-scope:` trailers for three paths in 7ed1fe7; G6..G9 attributed to CON-047 though they prove CON-015; the separator closes the untracked F7; earlier vehicle commits have no Roadmap-Item. History cannot be rewritten (11.4.113). | State the attribution and the out-of-scope reasons on the landing merge commit. |
| R3-8 | nit, process-doc | The author report says the manifest problems went from 26 to 24; measured 25 at c41b6c7, bc788b7 and 8e496db, 24 at the head. | — |
| R3-9 | nit, process-doc (engine) | The engine's Updated reason names the state change but not the description change made in the same call. | Engine follow-up, optional. |
| R3-10 | nit, process-doc | The CLASS RULE comment lists K5 under rule (2) (assignment); K5 comes from rule (1) plus the separator. | Fix the comment with R3-3. |
| R3-11 | nit, process-doc | CON-047 is a defect item with a recorded reproduction and three rounds of investigation, yet its investigation state is UNSET ("never assessed", 11.4.294(A)). `in-progress` or `root-cause-unconfirmed` fits. | Set through the engine. |
| R3-12 | minor, process-doc | The 94a1d28 bundle, the evidence archive and the probe sources that CON-047 cites (review_census_safe*.md, probe scripts in rvcs.b2JY and rv2.DsqC/probes, and this round's rv3.pGSK/tools) all sit in the session cache directory; they vanish with it. | Push 94a1d28 to a wip ref on every upstream (no force); copy the probe corpora into the tracked tree (as cases or under docs/qa/). |

## 11. Verdict

**GO-with-follow-ups**, round 3 of 5.

N1, the only blocking round-2 finding, is fixed, and the fix is proven both ways: G6..G9 fail on the old order and on RN1/RN7, pass on the head, and are killed in the meta-test. F5, F6 and F7/N3 are fixed. All the expected runs passed in this session: jq-region 52/0/5 (rc 3), closure 31/0/1 (rc 3), allowlist gate PASS 187/170/0 with needle ok, allowlist mutation test META PASS with 39 ok. The real tree is byte-identical across five census variants, and both the wide corpus and the fuzz run show no lost report.

Every open finding is minor-class under 11.4.276(G.2): test-instrumentation, process-doc, or a minor or nit source-defect that touches no excluded surface and invalidates no evidence for this batch. This verdict is not a zero-finding GO (11.4.6).

Conditions for landing (owned by the conductor, not by another review round):

- **L1.** The 11.4.276(E)(1) structural trigger fired. Deferring the structural rewrite to CON-047 is sound on the merits, but it needs a recorded §11.4.66 operator decision that names this vehicle and CON-047. If that decision is not recorded, this verdict does not authorise landing, and round 4 must be a structural round.
- **L2.** The follow-ups of section 10 are registered as tracked items before or with the landing.

## 12. Landing notes

- L1. Record the §11.4.66 operator decision that defers the structural rewrite to CON-047 (section 9), naming vehicle/census-safe and CON-047, before landing.
- L2. Register the follow-ups as tracked items linked to their parent (11.4.276(G.2), 11.4.93): R3-1 and R3-2 (test pins, cases ready in section 5), R3-3 / R3-5 / R3-6 and the remaining false negatives on CON-047 or the item that owns them (11.4.214), R3-4, R3-12; nits optional.
- L3. When both this vehicle and vehicle/ownership-wave2 land, do not unite the trackers through md-to-db (it drops the Opened history rows of CON-049 and CON-050). Replay the engine operations of the second vehicle onto the landed database, then regenerate the documents and run the runner's `--sync-guide`.
- L4. Update CON-015 and CON-016 (still Queued) at landing through the engine, with their reproduction and verification state (11.4.290, 11.4.292, 11.4.294).
- L5. Put Roadmap-Item and Out-of-scope trailers on the landing commit (R3-7).
- L6. After landing, retire the wip ref per 11.4.288(B)(4) only once the landed commits are on every upstream; keep the 94a1d28 bundle until its ref is pushed.
