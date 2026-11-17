# CON-456 round 6: evidence

| Field | Value |
|---|---|
| Item | CON-456 (workable-items engine id grammar and whole-item round trip) |
| Round | 6 (fixer, resumed after an API limit), after the round-5 independent review (sha256 `f3985077…7482`) |
| Engine head | `e69de2d5` (Go source) plus binary commit `35e7f0d5` |
| Evidence class | gate-logic and host-only; PROVISIONAL (§11.4.290), not independently reviewed again, nothing here is VERIFIED |
| Date | 2026-11-17 |

## 1. What changed

- Review r5 F1/M1/M2: one fence-aware definition of an item's own lines (`ownlines.go`); a fenced `**Status:**`, `**Type:**` or record line is quoted text for the parser, the Status canonicalizer, the metadata-block finder and the owned-line gate; CRLF line endings are kept. Commits d607b405, 28ffcd7e, b51cb891.
- Follow-up found while fixing F1 (`e69de2d5`): a fenced `## ID — title` heading (all four recognised forms) or a legacy pipe-table row minted a phantom item and cut the real item's block in `parseIssues`, `parseFixed` and `emitLegacyTable`. They now use the shared `fencedMask`. Tests `idgrammar_r6_doc_test.go` were written first; the legacy-row test was observed RED before the fix.
- r5 README section 7 correction (the `60b87d73` claim was false); two exemption rows in `config/git_env_class_exemptions.tsv` for the pinned r5 tools.

## 2. Tests

`go test -count=1 -json ./...` in `scripts/workable-items` at the final engine tree, run twice: rc 0 both times; 1134 pass, 0 fail, 6 skip (the six pre-existing skips); sorted verdict lists identical, sha256 `26c1945fc78f24dca091677a3716bcd44e20136fb10d7b238aafade3d06c94b8` (`gotest/`).

## 3. Mutants (incomplete, honest)

`mutants/mutants_table.tsv`, `mutants/kill_table.txt`. 39 mutants (reviewer RV1..RV10 with RV3b/RV8b, own N1..N27) plus an identity control NOOP, each run in a copy of `scripts/workable-items` only. The copy lacks the rest of the repository, so NOOP itself fails 111 tests (the formats-switch and one closure test need the repo); a mutant counts KILLED only when it fails a test that NOOP passes (`killtable.py`).

- KILLED: 28, including RV1, RV2, RV3b, RV4, RV5, RV6, RV7, RV8b, RV9, RV10 and N1..N7, N10, N13, N14, N16, N17, N21..N25, N27.
- SURVIVED: N8, N9, N15, N19, N20. N8 (drop the CR from `eolOf`) looks behaviourally equivalent (the replaced expression yields the same text), UNCONFIRMED. N9, N15, N19, N20 are NOT shown dead: either no test reaches them or the copy-run masks the test (the NOOP caveat). OWED: re-run against the full package in the repository, add tests for survivors that are real.
- NOCOMPILE as written: RV3, RV8, N11, N12, N18, N26 (an unused variable or removed declaration). OWED: re-author. N26's behaviour (a fenced legacy row) is covered by `TestCON456R6_FencedLegacyTableRowMintsNoItem`, which passes.

The brief asked for survivors to die; that is NOT achieved in this round.

The mutant definitions are kept as `mutants/own_mutants.py.txt` and `rev_mutants.py.txt` (renamed from `.py` so the full-suite census does not take them for tests; run them as `python3 -I`).

## 4. Class sweep

`tools/fencesweep.py`, `class/fencesweep_r6.json`: the fence tracker of the sweep is independent of the Go code (control needle: a synthetic fenced heading counts 1; negative control unfenced 0). The real `docs/Issues.md` and `docs/Fixed.md` hold 0 fenced item-shaped lines, so the class is 0 on the real tracker. Engine injection: a fenced heading plus Status line injected into the first item of a copy: 501 items before and after, 0 phantom items.

## 5. Real tracker

`realtracker/realtracker_r6_summary.txt`: validate, diff, three exports, two `md-to-db` cycles on a copy of the tracker: FAILS=0.

## 6. Build

`build/build_facts.txt`: two builds byte-equal, sha256 `3c70485a…d69a`, equal to both tracked binaries; `.source.sha256` recomputed with the recorded formula.

## 7. Tracker

CON-456 got a round-6 sentence through the engine (`md-to-db`, then `db-to-md`); `validate` OK, 501 items. Issues_Summary is unchanged (counts did not move).

## 8. Gates

`gates/gates.tsv`, run by `tools/gates.sh` at the head recorded in `gates/head.txt` (the commit before the evidence commit that adds `gates/`).

## 9. Owed

The mutant items of section 3; an independent review (§11.4.142); `cm_helix_deps_manifest_present` BLIND in a scratch clone (own-org submodules not checked out); `sh -n` on two anchor-wired gates (pre-existing).
