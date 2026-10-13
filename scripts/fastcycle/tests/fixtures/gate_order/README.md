# gate_order fixtures (T054, plan T-C04, contract AS-013)

RED-test fixtures for `constitution/scripts/fastcycle/tests/test_gate_order_red.sh`,
covering ONLY the fail-fast ORDERING half of `gates/gate_runner.sh`
(AS-013). The sibling BOUNDED-SHARDING half (AS-014, plan T-C05) is out of
scope here — see `test_gate_shard_red.sh` (T055) for that.

## `_shared/` — the common toy corpus

- `gates/` — 4 tiny real shell "gate" scripts (`gate_a_reliable.sh` always
  PASS, `gate_b_moderate.sh` always PASS but historically 1/5 FAIL,
  `gate_c_planted_fail.sh` genuinely FAILs on every invocation (the planted
  defect), `gate_d_new.sh` always PASS with zero history rows).
- `history/prebuild_sections.tsv` — a real T-A01-schema (`fc_timer.sh`
  header, see `constitution/scripts/fastcycle/timing/fc_timer.sh`) log with
  5 historical runs each for gates a/b/c establishing their
  `historical_fail_rate / mean_cost`: a=0.0, b=0.0004, c=0.008 (highest).
  Gate d has no rows (tests DEC-10's median-rate default).
- `affected.json` — an Affected-Set entity (data-model.md §4) declaring all
  4 gates as `members` in SECTION/DECLARED order `a, b, d, c` — the
  planted-failing gate `c` is declared **last**.
- `config.yaml` — the `--config` fixture (gate-site paths + history-log
  path).

## Scenarios

| Directory | Kind | Proves |
|---|---|---|
| `go_ordered_planted_fail_first/` | golden | `--order history-cost` executes/reports the planted-fail gate FIRST despite it being declared last (the literal task-text claim). |
| `go_negctrl_already_first/` | negative control | When the ranked-first gate is ALREADY declared first, ordering is a correct no-op, not a vacuous behaviour. |
| `go_determinism_identical_results/` | determinism | The final `results` verdict set (sorted by `gate_id`) is byte-identical whether `--order history-cost` is given or omitted — ordering changes only run/report SEQUENCE, never the substantive outcome. |
| `go_new_gate_median_rate/` | control needle | A gate with no historical entry (`gate_d_new`) ranks at the MEDIAN rate — neither 0 (would tie it with the lowest gate) nor the maximum (would rank it above the genuinely worst gate) — per contract DEC-10. |

## What this RED test does NOT cover

- AS-014 bounded sharding (`--order`'s sibling flag/mode for parallel
  execution) — T055's `test_gate_shard_red.sh` scope, not this file's.
- The `--no-cache` flag and verdict-cache interaction (T-C01, covered by
  T051's `test_verdict_cache_red.sh`).
- `affected_set.py`'s own selection/skip-list logic (T-C03, covered by
  T053's `test_affected_set_red.sh`).
- `io_trace.sh`'s observed-input tracing (T-C02, covered by T052's
  `test_io_trace_red.sh`).

See `PAIRED_MUTATION_NOTE.md` for the C-005 mutation obligation this
fixture set hands to T070 (the real implementation task), not this RED
test itself.
