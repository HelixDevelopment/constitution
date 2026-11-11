# Independent review: follow-up bundle fu_b (CON-184, CON-185, CON-183, CON-102 M6 partial)

Reviewer: fresh subagent, model Claude Opus 5.5 (claude-opus-5-5). Effort: not verifiable from inside the dispatch (§11.4.231(F.2)).
Date: 2026-11-11. Scratch clone: `.../74ce2b36-.../scratchpad/rev_fu_b/constitution` (live checkout untouched; no push, no tag).

## Overall verdict: GO-with-follow-ups

0 critical, 0 important, 2 minor (test-instrumentation), 2 nit. All open findings are minor-class under §11.4.276(G.2)
(test-instrumentation / process-doc; no source-defect: the helper `scripts/fastcycle/tests/lib/consumer_required.sh`
is byte-unchanged by the bundle). Follow-ups proposed below.

| Item | Verdict |
|---|---|
| CON-184 (AtM-5, A_B-1 in S7b; CON184-M3) | GO |
| CON-185 (L29 SKIP-with-reason) | GO-with-follow-ups (F1, F2) |
| CON-183 (Part 3b symlinked canon; CON183-M4; bound) | GO (bound statement accurate; F3 nit outside scope) |
| CON-102 M6 partial (spaced-path legs; CON102-M6) | GO (item correctly stays Queued) |

## Input verification

```
sha256 24ffdd05b86710561730affdb6f0bd074cf2a3d50b6d86718ccde222edc0050c  fu_b.bundle   (matches)
git bundle verify: "../../fu_b/fu_b.bundle is okay"; requires fc57ad0c69197d47febf020744701ffd04016cad
list-heads: 96702413e4d346188aa7e904b9644e5fe378ebe5 refs/heads/fu-b
fc57ad0c..fub: c69f0b06 (CON-184), 8d98d4fb (CON-185), 0ca66af7 (CON-183), 96702413 (CON-102 partial)
git diff --quiet fc57ad0c fub -- scripts/fastcycle/tests/lib/consumer_required.sh  -> helper-unchanged
```
Note: fc57ad0c is not in the live checkout (`main` there is 90efceb8); it was fetched from the conductor scratch clone.
The bundle ref is `fu-b`, not `main` (N2).

## Reproduction (RED at base, GREEN at bundle head), mutation harness, bash + dash legs

RED = worktree at fc57ad0c (helper test as on main) with the bundle's mutation script (rows) copied in.
GREEN = bundle head 96702413. Same command: `bash scripts/fastcycle/tests/test_consumer_required_mutations.sh CON184-M3 CON183-M4 CON102-M6 RV-A RV-B RV-C RV-D`
(RV-* are my own mutants, added to the hand table in my scratch copy only).

RED (fc57ad0c test):
```
ok   baseline: the unmutated helper copy passes (SUMMARY: 338 pass / 0 fail)
SURVIVED CON184-M3 (rc 0, 0 NOT ok lines)
SURVIVED CON183-M4 (rc 0, 0 NOT ok lines)
SURVIVED CON102-M6 (rc 0, 0 NOT ok lines)
SURVIVED RV-A / RV-B / RV-C / RV-D (rc 0, 0 NOT ok lines)
SUMMARY mutants=7 killed=0 survivors=7
```
GREEN (bundle head):
```
ok   baseline: the unmutated helper copy passes (SUMMARY: 352 pass / 0 fail)
killed CON184-M3 (2 failing check(s): [bash] S7b usage message for [AtM-5]: rc 0 ...;[dash] ... [AtM-5] ...)
killed CON183-M4 (6 failing check(s): [bash] symlinked canon: the consumer data under the logical root is found ...)
killed CON102-M6 (4 failing check(s): [bash] a path argument with a space is passed whole ...)
killed RV-A (2 failing check(s): [bash] S7b usage message for [A_B-1]: rc 77 ...;[dash] ...)
killed RV-B (2 failing check(s): [bash] S7b usage message for [AtM-5]: rc 0 ...;[dash] ...)
SURVIVED RV-C (rc 0, 0 NOT ok lines)
killed RV-D (4 failing check(s): [bash] a path argument with a space is passed whole ...)
SUMMARY mutants=7 killed=6 survivors=1
```
Full helper suite on the real host (bundle head): `SUMMARY: 365 pass / 0 fail`, rc 0, 0 `NOT ok`; 168 `[dash]` legs run
(the suite is `#!/bin/bash` and drives both shells through `$SHELLS="bash dash"`; `dash -n` of the test and helper both 0).
L29 on the real host still asserts for real: `ok L29 locales ...: C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8` plus 8 per-shell
`L29 LC_ALL=... A-umlaut prefix is a usage error (exit 2)` checks.

Author claims re-checked: CON-184 RED survived -> GREEN killed (bash+dash) REPRODUCED; CON-183 M4 RED survived -> killed
REPRODUCED; CON-102 M6 RED survived -> killed REPRODUCED; simulated no-locale run REPRODUCED (count differs only by head:
`FC_L29_CANDIDATES=zz_ZZ.UTF-8` at 96702413 gives `SUMMARY: 356 pass / 0 fail`, rc 0, plus the SKIP line; author's 347
was at 8d98d4fb). `workable-items validate`: `OK — 191 items`; `diff`: `DB and Markdown are in sync (191/191)`.
DB: CON-183/184/185 `Ready for testing`, `reproduced-host-fixture` / `root-cause-found-with-evidence`; CON-102 `Queued`.
NOT re-checked by me: "MANIFEST-OK" (tool not named in the brief) — UNCONFIRMED.

## My own mutants (§11.4.194(6)(d))

| Id | Edit | Base | Head |
|---|---|---|---|
| RV-A | helper `\|*[!A-Z0-9]*)` -> `\|*[!A-Z0-9_]*)` (underscore allowed in prefix) | survived | killed (A_B-1 leg) |
| RV-B | helper `\|*[!A-Z0-9]*)` -> `\|*[!A-Za-z0-9]*)` (lowercase allowed) | survived | killed (AtM-5 leg) |
| RV-C | helper `&& pwd)` -> `&& pwd -P)` in root resolution | survived | SURVIVED (also survives the real-helper full suite incl. Part 4: 365/0 rc 0) -> F3 |
| RV-D | helper `for _fcr_p in "$@"` -> `for _fcr_p in $@` | survived | killed (spaced-path legs) |
| RV-E | test: L29 dispatch `SKIP*) echo "$_l29_line"` -> `SKIP*) ok "$_l29_line"` (SKIP counted as PASS), run with `FC_L29_CANDIDATES=zz_ZZ.UTF-8` | n/a | SURVIVED: `ok   SKIP: L29 ...`, `SUMMARY: 357 pass / 0 fail`, rc 0 -> F1 |
| RV-F | test: same dispatch -> `SKIP*) : ;;` (SKIP line dropped), same env | n/a | SURVIVED: no SKIP line, `SUMMARY: 356 pass / 0 fail`, rc 0 -> F1 |

## Findings

**F1 — minor (test-instrumentation), CON-185.** The L29 SKIP is honest in wording (closed reason `topology_unsupported`,
§11.4.69 set; not passed through `ok()`), but it is invisible to the suite's verdict: the run still ends
`SUMMARY: N pass / 0 fail` and exit 0, with no skip count, whereas the same script exits 77 when dash is absent
(lines 673-676). A host lacking the locale therefore reports a fully green rc 0 with a leg not run, discoverable only by
grepping stdout (§11.4.266(D)/§11.4.201(6) false-null at the aggregate). The branch proof covers only `l29_verdict`'s
output, not the dispatch: RV-E (SKIP counted as a PASS) and RV-F (SKIP line silently dropped) both survive rc 0.
Follow-up: when L29 skips, set a skip flag and exit 77 (or emit a counted `skip=` in SUMMARY like the s12 pattern), and
add a leg/mutant that runs the dispatch under the simulated topology and asserts the SKIP line and the non-zero skip
outcome (kills RV-E/RV-F).

**F2 — minor (test-instrumentation), CON-185.** `FC_L29_CANDIDATES` is test-only (it lives in the test file; the
production helper is untouched, so it cannot weaken production behaviour), but it is honoured unconditionally from the
ambient environment: a whitespace or bogus value (`${FC_L29_CANDIDATES:-...}` unquoted; `" "` expands to empty) turns a
real host's L29 into a SKIP with rc 0, with no note that an override was in effect. Combined with F1 this is a silent
weakening switch for the test. Follow-up: print `note: FC_L29_CANDIDATES override in effect` when set, and make the
override-driven SKIP non-zero per F1.

**F3 — nit (pre-existing gap, outside the bundle).** RV-C (`pwd -P` after a logical cd) survives both the mutation
harness and the real-helper full suite including Part 4. It differs from M4 only when the consumer root itself is reached
through a symlink (then the SKIP message names the physical root). The CON-183 bound ("only the symlinked-canon property
of Part 4 is replayed; a mutant only the real suites kill is reported survived") is accurate and matches what is killed;
RV-C is a coverage gap of both, not a mis-stated bound. Follow-up: a leg with a consumer root under a symlinked parent that
asserts the SKIP names the logical root, or record RV-C as equivalent-for-behaviour.

**N2 — nit (process-doc).** Bundle head ref is `fu-b`, not `main` as the brief says; base fc57ad0c is not on the live
`main` (90efceb8) — landing needs the fc57ad0c base first. CON-183's evidence file cites "2 failing check(s)" for M4 at
0ca66af7; at 96702413 it is 6 (the spaced-path legs added later also fail) — consistent, not wrong.

## Per-item notes

- CON-184: both new ids assert exit 2 and the exact message in bash and dash; M3, RV-A, RV-B all killed. Acceptance met.
- CON-185: acceptance (SKIP-with-reason instead of FAIL) met; F1/F2 are follow-ups on how the SKIP reaches the verdict.
- CON-183: Part 3b builds the symlinked-canon layout around `$HELPER` (the copy under test) and runs under
  `FC_HELPER_UNDER_TEST`; M4 killed; bound printed at Part 4 and in the mutation script header. 21 registered sweep
  equivalents not re-run here (author also states "unrun") — UNCONFIRMED by me.
- CON-102: only M1G/M6 closed; M1A, M2A, M2C, M2D untouched; item stays Queued. Correct.

Cleanup: my RV-* rows exist only in the scratch clone's mutation script (uncommitted); the RED worktree was removed; the
temporary helper edit for the RV-C real-suite run was restored (`git diff --quiet` confirmed).

## Landing note (2026-11-11)

Follow-ups registered at landing as Queued Task/Low items (section 11.4.276(G.2)): CON-222 (F1), CON-223 (F2), CON-224 (F3), CON-225 (N2).
