# Canon self-scan triage: dangerous-combination and oracle-strategy gates

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Status | triage record; no gate edited, no defect fixed; linked from README (design plans list) |
| Last modified | 2026-10-31 |
| Source | commit 39ad2ce (scanner gates scan the canon itself by default) |
| Base | main at 7c0bcc9 |

Evidence logs (all under `/home/milosvasic/.cache/claude-tmp/`): `dcfc_first_party.log`, `oracle_first_party.log`, `oracle_default.log`. "PROVEN" means measured in this session with the command shown. Anything else is marked UNCONFIRMED.

## 1. How the gates were scoped (no gate edited)

Both gates take their prune list from an environment variable, so no wrapper was needed:

```
DANGEROUS_COMBO_EXCLUDE=".git node_modules vendor .venv __pycache__ scripts/gates out build dist submodules" \
  nice -n 15 scripts/gates/cm_dangerous_combination_fail_closed.sh --root .
ORACLE_GUARD_EXCLUDE="<same list>" \
  nice -n 15 scripts/gates/cm_oracle_strategy_named_and_independent.sh --root .
```

The only addition to the default list is `submodules` (every submodule here is third-party or a hub engine). `scripts/gates` is excluded by the gates' own default, so the gates are never scanned by themselves. No other vendored directory exists outside `submodules/` (a find for `third_party`, `vendor`, `node_modules` returned nothing). Run time: dangerous-combination 33.7 s, oracle 0.4 s.

## 2. CM-DANGEROUS-COMBINATION-FAIL-CLOSED on first-party source

Result: exit 1, 152 hits, all in Python (88 "silent default return", 64 "swallowed exception"). 173 `.py` files are in scope. Zero hits lie under `submodules/`.

Control needles (PROVEN, scratch root): a file with `except Exception: pass` is flagged; a file with `except Exception as e: raise ... from e` is not; a JS `catch (e) { }` is flagged. So the instrument sees both shapes and does not flag a clean handler. Non-Python findings are zero, and the JS needle shows the zero is not blindness for that shape.

Where the hits are (file counts from the log): `scripts/fastcycle` 83, `scripts/codegraph` 23, `scripts/decisions` 12, `scripts/constitution_ext` 10, `scripts/credscan` 7, `scripts/label-sync` 5, `scripts/hooks` 5, `scripts/catalog-engine` 4, `scripts/anchors` 2, `tests/extensions` 1, `progressive/validate_tokens.py` 1.

### Classification

Exception type: 135 narrow (OSError 63, ValueError 8, `(OSError, ValueError)` 8, subprocess timeout shapes 9, ProcessLookupError 6, FileNotFoundError 6, sqlite3.Error 6, others) and 17 broad (`Exception` 16, `BaseException` 1). All 17 broad ones were read in context.

Bucket counts (heuristic bucketing by try-body keywords; the five bucket counts sum to 152):

| Bucket | Count | Verdict |
|---|---|---|
| A. test code (`except X: pass` after `assert False`, test cleanup) | 5 | false positive (see below) |
| B. best-effort reporting of an error that was already surfaced (`write_doc`/`write_report_atomic` of an internal-error report, `flush`, stderr emit) | 10 | acceptable with reason |
| C. idempotent cleanup / liveness (`unlink`, `rmdir`, `close`, `killpg` ProcessLookupError, `waitid` ChildProcessError) | 34 | acceptable with reason |
| D. read or probe helper returning a sentinel (`None`, `[]`, `{}`, `False`, a reason string) | 80 | acceptable with reason, with a caller check (below) |
| E. optional read where failure leaves a default (`pass`) | 23 | acceptable with reason |
| TRUE defects | 0 | none confirmed |

Why the gate fires although nothing is wrong:

- The gate's own header says it implements only the literal shape half of §11.4.252 and "CANNOT honestly claim" to prove that a path combines two dangerous capabilities. It therefore flags a handler even in a pure parse or probe helper that has no mutation, credential or side effect. Most of the 152 are such helpers (`open` → `OSError` → `None`).
- Test idiom (A): `try: f(); assert False; except ExpectedError: pass` is how the expected exception is asserted (`scripts/anchors/tests/test_anchor_lib.py:29,374`). Nothing is swallowed, because the `assert False` raises if the exception does not occur.
- Sentinel returns (D) hand the caller a distinguishable value. Where the direction matters, the sentinel is the safe one. Examples read in context: `ext_engine.py` lstat failure → `False` for "is a safe directory/nonce/marker" checks (fail-closed); `custody_sweep.py:405-409` PermissionError → "group exists" (documented as the safe default); `cycle_report.py:443` unparseable instant → `True` ("cannot be shown to precede the cutoff", documented); `guard-destructive-paths.py:2769` → `True`, `:3740` → `2` (block); `validate_tokens.py:31` tiktoken missing → `None`, and the caller prints `UNCONFIRMED` and sets failure (fail-closed, visible); `codegraph_mcp_health.py:607` import failure → `src=None`, and the report then says "installed schema unknown".
- Best-effort cleanup after the real work (C) must not mask the primary result. `ProcessLookupError` on `killpg` means the group is already gone, which is the goal.

Items worth a reviewer's second look (not defects; UNCONFIRMED risk, none fixed here):

1. `scripts/fastcycle/closure/reopen_rate.py:141` and `scripts/fastcycle/cycle/select_sample.py:489`: `except Exception: return False` around a timestamp subtraction. A malformed `created_at` silently makes a pair "not a reopen pair", which can undercount a metric. Narrowing to `(KeyError, ValueError, TypeError)` and counting the skips would be the repair. No dangerous capability is involved, so it is a measurement-honesty nit (§11.4.201(6)), not §11.4.252.
2. `scripts/decisions/decisions_engine.py:503` `is_locked()` returns `False` for a key `spec_for` refuses. Callers at lines 510 and 583 validate the key shape first, so the effect is not shown to matter. UNCONFIRMED whether an unknown but well-formed key can reach a store.
3. `scripts/hooks/guard-destructive-paths.py:1983,1990`: `except Exception: return None` around `os.path.realpath`, meaning "no extra resolution". `realpath` effectively raises only `ValueError` (embedded NUL). The direction is the guard's cautious one, but a guard is the place where a silent default deserves a comment. No change made.

### Suggested gate repair (a separate work item, not done)

- Do not flag `except X: pass` inside a `try` that contains `assert False` or `pytest.raises`-style expectations (golden-FALSE carrier).
- Report narrow-exception sentinel returns as a lower class unless the enclosing function also contains a mutation, credential or exec call; this is the "combination" half the header says it cannot do. A cheap proxy is a function-level capability scan.
- Add `submodules` (or the `third_party: true` paths from `helix-deps.yaml`) to the default prune list; today the default run descends into every third-party tree and takes more than 15 minutes.
- Consider scanning `scripts/gates` with the gate itself, or state why not.

Fixed in this pass: nothing. No finding was both a confirmed defect and small enough to change safely.

## 3. CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT

Result with default scope (cwd = canon, scanning the canon plus every submodule): exit 1, 6759 unannotated test functions. With third-party removed: 414.

| Tree | Unannotated | Class |
|---|---|---|
| `submodules/llmctl` | 3122 | third-party hub engine |
| `submodules/watch-skill` | 1603 | third-party |
| `submodules/repo-qa` | 922 | third-party |
| `submodules/verify` | 299 | third-party |
| `submodules/claude-video` | 188 | third-party |
| `submodules/agentic-validation` | 129 | third-party |
| `submodules/donespec` | 54 | third-party |
| `submodules/containers` | 20 | third-party |
| `submodules/open_design` | 6 | third-party |
| `submodules/claude_toolkit` | 2 | third-party |
| subtotal submodules | 6345 | |
| `tests/extensions/test_unit.py` | 213 | first party |
| `scripts/credscan/tests/test_credscan.py` | 67 | first party |
| `scripts/codegraph/tests/*` (3 files: `test_fk_cascade_probe.py` 42, `test_scope_exceptions.py` 13, `test_owed_report.py` 12) | 67 | first party |
| `scripts/anchors/tests/*` (11 files; largest `test_anchor_lib.py` 21) | 67 | first party |
| subtotal first party | 414 | |
| total | 6759 | |

6345 + 414 = 6759, so the breakdown is complete. Of the 6759, 6756 are "no annotation" and 3 are "strategy not in the closed set" (`RAW`, `THE`, `DEEPSEEK_V`).

First-party annotation coverage is 0 of 414 (`grep -ci 'oracle:'` over the four first-party test trees finds one prose comment, in `test_query_us2.py:208`, and no valid annotation).

### Is the annotation grammar realistic?

- Python only: the gate globs `*test*.py`. The canon's own tests are largely shell: 553 `test_*.sh`/`*_test.sh`/`*mutation_test.sh` files outside `submodules/` against 30 Python test files. So a green result would cover a small share of first-party tests. (Counts from `find`; the Python figure counts files named `test_*`/`*_test.py`.)
- The grammar is a per-function comment within 3 lines of the `def` or a docstring line `oracle: <STRATEGY>`. For one function that is cheap. For 414 existing functions it needs a human judgement per test, because the strategy is a claim about independence of the expected value, not a label.
- False-positive in the matcher: any prose `oracle: <word>` is read as an annotation with a strategy. `scripts/anchors/tests/test_query_us2.py:182` ("Independent oracle: raw grep") reports `RAW` as an unknown strategy, and the two submodule hits are the same shape. So three of the failures are wrongly worded matches, not unannotated tests.
- It checks presence and closed-set membership only; independence (the real point of §11.4.245) stays reviewer territory, as the gate header states. Adding 414 annotations by hand would make the number green without improving oracle quality, which is exactly the "annotation theatre" risk.

### Staged adoption plan (ratchet, per §11.4.224(E) / §11.4.135 style)

The repo already has the pattern: `scripts/gates/cm_zero_findings_monotone_ratchet.sh` (snapshot ceiling, `<=` check, new class implicitly 0), `escape_ratchet_baseline.txt` and `gate_ledger_baseline.txt`. The initial ceiling value is an operator decision (§11.4.66); the escape-ratchet baseline file already documents why an agent must not invent it.

1. Scope first. Default-exclude third-party paths (via `helix-deps.yaml` `third_party: true`, or `submodules`). That removes 6345 of 6759 and is not a loosening: the canon does not own those tests. Each owning repository adopts the gate itself.
2. Fix the matcher: require the annotation form `oracle: <TOKEN>` where the token is a single word followed by end of line or `#`, or anchor to a leading comment/docstring line. Add golden-FALSE fixtures for the prose carrier (`Independent oracle: raw grep`).
3. Ratchet baseline of 414 (first-party) as the checked-in ceiling, recorded per file so a new unannotated test in an already-counted file still fails (per-file ceiling, not only a total). New test files start at 0. A decrease lowers the ceiling.
4. Rule for new and modified tests only: any test function added or changed after the baseline must carry a valid annotation (diff-scoped check). This stops the count growing without a mass edit.
5. Burn down by risk, not alphabetically: start with the gate and hook tests that guard safety paths, then `scripts/anchors/tests` (67), then `scripts/credscan/tests` and `scripts/codegraph/tests`, last `tests/extensions/test_unit.py` (213, one file). A sensible pace is per file, each annotation reviewed for an independent source (spec, reference implementation, invariant) rather than copied from the code.
6. Decide separately whether the 553 shell tests are in scope; that needs a shell-aware extractor and its own control needles. Until then the gate's PASS must be reported as "Python tests only".

## 4. Honest boundaries

- Bucketing in section 2 is by keyword on the try-body text; the split between B, C, D and E could differ by a few items under a stricter reading. The totals (152; 135 narrow, 17 broad) are exact counts from the gate log. The verdict "no confirmed defect" rests on reading the 17 broad handlers and a sample of narrow ones in context, not on reading all 135 narrow handlers' callers. UNCONFIRMED: that no caller of a sentinel-returning helper mishandles `None`.
- The scoped runs excluded `scripts/gates`, so the gates and their mutation tests were not scanned.
- Nothing was committed or pushed. The working tree already contained unrelated modifications by other sessions; this pass touched only this file and one README link.

## 5. Follow-up: the three "reviewer's second look" items, investigated (2026-10-31)

Each was reproduced on the real code first, then decided from the evidence.

1. `reopen_rate.py:141` and `select_sample.py:489` (`except Exception: return False` around the Opened-to-closure `created_at` subtraction): **TRUE DEFECT (silent metric distortion)**. RED: with NB-001's closure `created_at` set to `not-a-timestamp` in the negative-control fixture, `reopen_rate.py` exited 0 with no message and reported Bug `closed` 3 / rate 0.333333 instead of `closed` 2 / 0.0 (the retroactive item is silently counted as an ordinary closure). Fix: a tri-state `retroactive_state()` (`retroactive` / `normal` / `unparseable`) in both tools, exception narrowed to `(KeyError, ValueError, TypeError, AttributeError)`; the boolean functions keep their signature and meaning (parity test S7 still holds). `reopen_rate.py` still counts the item (retroactivity cannot be proven) but lists it under `unparseable_timestamps` (per type and overall) and warns on stderr; `select_sample.classify_exclusions` excludes it with the explicit reason `unparseable-timestamp (...)` because a duration sample cannot rest on a corrupt timestamp. A well-formed export produces byte-identical output (no new key). Tests: `scripts/fastcycle/tests/test_unparseable_timestamp_regression.sh`. The mutant anchor in `test_select_sample_r5_regression.sh` (SS_N3) was moved to the new line. Separate finding, not fixed: a list or dict `created_at` crashes `reopen_rate.py` earlier, in `dedup_history` (`TypeError: unhashable`), with a traceback and non-zero exit (loud, so not silent).
2. `decisions_engine.py` `is_locked()` False for a refused key: **ACCEPTABLE**. Evidence: `drop_locked({'bogus.key':1})` keeps the key, but every input to it was validated first (`validate_map`, `check_key`), and `dump_file` with an unknown key raises `Refused` through its round-trip parse, writing nothing. Returning `True` would instead make `drop_locked` silently discard invalid input, the worse direction. No behaviour change; a comment records the reason and `tests/decisions/test_is_locked_contract.sh` pins it (with a mutation that removes the guards and is detected).
3. `guard-destructive-paths.py` `except Exception: return None` around `realpath`: **TRUE DEFECT, in a neighbouring place; the handler itself was benign**. The `ValueError` it swallowed comes from an embedded NUL, and the guard never analysed NUL-bearing text the way a shell reads it. Measured: `printf 'echo ho\0me' | bash` prints `home` (bash drops NUL on stdin), and the guard returned 0 for `rm -rf /ho\u0000me` in a Bash payload and in a Write of a script (should block, class P). Fix: `run()` analyses the original text and the NUL-stripped text; the two `realpath` handlers are narrowed to `(ValueError, OSError)` so any other exception reaches `main()`'s fail-closed block. Tests: `scripts/hooks/test_guard_nul_regression.sh` (block cases, benign NUL allowed, injected fault fails closed, two paired mutations). Honest limit: the Bash tool itself cannot carry a NUL in argv; the reachable paths are script content (Write/Edit, heredoc) later fed to a shell on stdin.
