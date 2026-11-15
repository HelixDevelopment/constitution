# Engine created_at vehicle, round 2 (CON-339)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-14 |
| Status | PROVISIONAL; round-2 review NO-GO (R2-F1 to R2-F5); superseded by `../round3/README.md`. Revision 2 corrects the overclaims of R2-F3 in place |
| Roadmap-Item | CON-PENDING-ENGINE-CREATEDAT |
| Base | `bd0036bd`; round-1 commit `6fffb942`; round-1 review: NO-GO (F1 important, F2 to F8 minor or nit) |

Paths written as `<scratch>` stand for the session scratch directory of the run; nothing here ran against the live
checkout or the real tracker database.

## Per finding

| Finding | Status | What changed | Evidence |
|---|---|---|---|
| F1 surviving mutants | fixed | `created_at_r2_test.go`: a test for each surviving non-control mutant (RM01, RM02, RM03, RM05, RM06, RM07, RR01 to RR07, RR10, RR15); RR07 through the test-only seam `rcaBeforeWriteHook` (nil in production, called after every check and before the write transaction); RR09 is equivalent (argument plus a factored check (corrected in round 3: the check is factored, not exhaustive)) | `r2_red1_head_decls_only.raw.txt`, `r2_green1.raw.txt`, `mutation_r2_*.txt`, `rr09_equivalence.txt` |
| F2 final plan row | fixed | `apply_restore_plan.sh` reads a last row without a trailing newline | `test_apply_restore_plan.sh` case A4; `r2_red_applier.txt` (RED), `r2_green_applier.txt`; shell mutant MS01 |
| F3 evidence provenance | partly fixed, rest registered | new refusal `VALUE-BEFORE-TRACKER`: a value earlier than the tracker's first well-formed history row by more than a declared 60 s slack is refused (the round-1 review's `2000-01-01` forgery now fails); backdating inside the tracker's lifetime with a hand-built evidence file still passes and is documented; reading evidence from git is draft item CON-PENDING-EVIDENCE-PROVENANCE | tests `ValueBeforeTracker*`, `TrackerBound*`, `TrackerMinimumNotARealTimeRefused`; mutants MR01 to MR07 |
| F4 tracking | drafted | `follow_up_register.md` (five drafts, `CON-PENDING-*`); round-1 README disclosure gains the 38 description rewrites, the 3 severity nulls, the CON-243 non-uniformity and the row-by-row note | `../README.md`, `follow_up_register.md` |
| F5 dry run needs a writable DB | documented | package doc comment, usage text, README; test `DBUnreadable` pins the behaviour | `restore_created_at.go`, `main.go`, `scripts/workable-items/README.md` |
| F6 static guard checks names | documented | doc comment and README state that the static guard checks columns; the value is covered by the behaviour tests (F1) | same |
| F7 symlinked evidence dir | fixed | `--root` resolved physically; a symlinked path component or an evidence directory resolving outside `--root` is BLIND, exit 3, nothing written | cases A5, A5b, A6b; mutant MS02 (round 3 correction: none of these exercised a symlinked `--root` and MS03 survived; round 3 adds cases B1 to B4 and kills MS03, VS01, VS02, VS03, see `../round3/README.md`) |
| F8 partial application | documented | the applier's header and the round-1 README state row-by-row application; case A10 pins it | case A10 |

The decision that CON-243 is restored to `15:34:35` is unchanged.

## Class inventory

`class_inventory.md`: every writer of `items` rows, every timestamp-rewrite path, every refusal code (23) with the
test that reaches it, and the applier's refusals.

## Mutation testing

Runner: `scripts/workable-items/mutation/created_at_r2_mutation_runner.py`. The reviewer's 22 mutants are copied
verbatim; 44 own mutants cover the lower bound, the compare-and-set write, the audit row, the evidence checks, the
upper bounds, target selection, usage, close and the plan applier (shell). Each run starts with a passing control
of the go selection and of the shell suite, mutates a disposable git worktree in place, restores it byte-exact and
checks the worktree is clean at the end.

| Run | Set | KILLED | SURVIVED (equivalent) | STALE / BUILD-BROKEN | Evidence |
|---|---|---|---|---|---|
| full package, head `b81b8756` | reviewer 22 | 20 | 2: RR09 (factored check `rr09_equivalence.txt`, (corrected in round 3: the check is factored, not exhaustive)), RR13 (reviewer's control) | 0 | `mutation_r2_full.txt` |
| full package, head `b81b8756` | own 44 | 42 | 2: MS11 equivalent; MS03 survived UNTESTED, not equivalent (round 3 correction; the true round-2 tally is 62 killed / 3 equivalent / 1 untested) | 0 | same |
| targeted, first pass | 66 | 55 | 4 equivalent + 5 real (MR07, MR09, MS08 and the two above were not yet declared) | 1 stale, 3 build-broken (own anchors, fixed) | `mutation_r2_targeted.txt` |
| targeted recheck after the fixes | the 8 non-killed | 8 | 0 | 0 | same file |

Both controls (go selection and shell suite) passed in every run; the worktree was clean after every run. The
round-1 author runner (`created_at_mutation_runner.py`, 27 mutants) was not re-run in round 2.

Equivalence arguments, stated so a reviewer can check them:
- RR09: `parseStoredTime` first requires `^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$`; a factored
  check (not exhaustive, corrected in round 3: 11 sampled years with every month and day pair, and every time triple at
  one date) of 1,110,000 matching strings (`tools/rr09_equivalence.go.txt`) found 90,419 that `time.Parse` accepts and
  0 that fail the round trip; both control needles were seen.
- RR13: `evAbs + ""` is `evAbs`; the added `_ = os.Remove` never calls it.
- MS03 (round 3 correction: NOT equivalent; the check is reachable by a concurrent change and was untested; round 3
  case B4 drives it with a PATH-shim mkdir and kills it): `--root` is resolved with `pwd -P`, the evidence path is relative without `..`, and the walk refuses every
  symbolic-link component before `mkdir`, so the resolved directory is always under `--root`; only a concurrent
  change between the walk and `mkdir` could reach the second check (not exercised).
- MS11: after the removed `exit 3`, `mv -- "$tmp" "$dest" || exit 3` fails because `$tmp` was just removed; the
  script still exits 3 with nothing written; only an extra `mv` error line differs.

## Tests and gates

- `go vet ./...` exit 0; `go test -count=1 -v ./...` twice: 672 PASS / 0 FAIL / 6 SKIP (678), identical verdict
  sets (sha256 `3cf833d5...`); every one of the 642 round-1 verdicts present and unchanged, 36 new
  (`go_summary_r2.txt`, `go_verdicts_r2_run1.txt`, `go_verdicts_r2_run2.txt`).
- `test_apply_restore_plan.sh`: 20 PASS / 0 FAIL against the rebuilt tracked binary (`r2_applier_tracked_binary.txt`).
- Tracked binaries rebuilt, two builds one hash `e048a077...`, both tracked copies equal (`build_facts_r2.txt`).
- `CM-GATE-LEDGER-RATCHET`: unimplemented 394, baseline 394, PASS (`ratchet_tail_r2.txt`).
- `run_full_suite.sh --verify-manifest`: the two new census files have rows; the guide census block is synced; the
  result is still MANIFEST-MISMATCH for three `scripts/sonarqube/tests/test_registry_login*.sh` files that have no
  row on the base `bd0036bd` either (pre-existing, not part of this vehicle) (`verify_manifest_r2.txt`).
- `gofmt -l`: the same 17 pre-existing files as round 1, none of the files this vehicle changed (`gofmt_l_r2.txt`).

## UNCONFIRMED

- Byte reproducibility of the tracked binaries across hosts (built and compared on this host only).
- Evidence provenance beyond the sha256 and the lower bound (F3 rest).
- The cause of each of the 226 batch-stamped rows (register D-05).
- The compare-and-set under real concurrency is exercised only through the test seam (the round-1 reviewer's probe
  P32 saw it fire once); the MS03 path under a concurrent symlink swap is not exercised.
- The fix227 landing ids (from the round-1 README) remain UNCONFIRMED.
