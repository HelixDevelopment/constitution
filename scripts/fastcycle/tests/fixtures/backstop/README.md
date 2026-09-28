# fixtures/backstop/ — T060 (SpecKit-004 "fast-dev-cycles", plan T-C10)

Fixtures proving `constitution/scripts/fastcycle/gates/backstop.sh` (not
yet implemented — T077, plan task T-C10) will correctly implement:

1. **DEC-17's drift rule** (research.md line 654 / plan.md T-C10 Work
   line): the full backstop lane (every gate, `--no-cache`, no
   `--affected` narrowing) is compared against the fast lane's verdicts
   for the SAME change; any gate the full lane FAILed but the fast lane
   did not also report FAIL for (whether the gate was never selected at
   all — a "selection hole" — or was selected but reported a different
   verdict) is a **drift**, a release blocker, and MUST block (exit 1).
2. **constitution SS11.4.226's guard-freshness queue**, drained
   most-reopened-first per SS11.4.189, `then stalest-first`.

## No dedicated contract exists for T-C10 (confirmed, not assumed)

`specs/004-fast-dev-cycles/contracts/common-conventions.md`'s "Tool map"
section explicitly lists `$FC/gates/backstop.sh (T-C10)` among the tools
for which "no contract is invented here ... their interface, output and
RED fixtures are fixed by the plan task text until a contract is written."
A real `ls specs/004-fast-dev-cycles/contracts/*.md` at authoring time
confirms no `backstop*.md` (or similarly-named) contract file exists.
The CLI wire format this fixture set and the RED test assume is therefore
**this file's own definition, binding-if-adopted on T-C10's implementer**,
following this project's established house precedent
(`fixtures/mutation_reuse/README.md`'s identical final section;
`test_verdict_cache_red.sh`'s header comment).

## Two closely-related, already-existing contracts this design reuses

- `affected-set-and-verdict-cache.md`'s "Output schemas" section already
  defines the `verdicts/v1` document shape
  (`{change_id, results: [{gate_id, verdict, source, evidence,
  duration_ms}], summary}`) — `bs_selection_hole/` and `bs_negctrl_equal/`
  reuse this SAME shape for both `fast_verdicts.json` and
  `full_verdicts.json`, rather than inventing a new schema for backstop.sh
  (constitution SS11.4.6 — do not invent when something adjacent already
  exists). That same contract's `VC-005 (backstop)` clause states the
  special case DEC-17 generalises: "any gate PASS in fast lane but FAIL
  in full lane is a release blocker."
- `catch-set-comparison-harness.md`'s `C-001`-family exit-code convention
  (0 clean, 1 a finding/release-blocker, 2 usage, 3 self-test/needle
  failure, 4 BLIND) is followed by the CLI contract below, matching every
  other tool in this suite (`common-conventions.md` C-001).

## Scenario fixtures

| Directory | Covers |
|---|---|
| `bs_selection_hole/` | golden-bad: a planted fast-lane selection hole → DRIFT report naming the gate → block (exit 1) |
| `bs_negctrl_equal/` | negative control: equal fast/full selections, including a real shared FAIL → NO_DRIFT (exit 0) |
| `bs_freshness_queue/` | guard-freshness queue drained most-reopened-first (then stalest-first), a fresh guard excluded despite the highest reopens_count |

## Reference computations (Section B / Section C of the RED test)

- `../lib/dec17_drift_ref.py` — this project's own from-scratch reference
  implementation of DEC-17's drift rule, used to prove
  `bs_selection_hole/` and `bs_negctrl_equal/` are non-vacuous BEFORE any
  claim is made about the absent real tool.
- `../lib/guard_freshness_ref.py` — this project's own from-scratch
  reference implementation of the SS11.4.226/SS11.4.189 freshness-queue
  ordering rule, used to prove `bs_freshness_queue/` is non-vacuous BEFORE
  any claim is made about the absent real tool.

Neither reference module is imported by, or informs the design of, T-C10's
real implementation (Producer != Verifier, constitution SS11.4.240).

## The invented CLI wire format (binding-if-adopted)

```
$FC/gates/backstop.sh run --config <cfg> --no-cache --out <full_verdicts.json>
    # Runs $FC/gates/gate_runner.sh over EVERY gate (--no-cache, no
    # --affected narrowing) -- reuses gate_runner.sh's verdicts/v1 output
    # schema unchanged. NOT exercised by this RED test (it composes
    # gate_runner.sh + a real gate corpus, neither of which this
    # fixture-driven RED test constructs; T077's own implementer-task
    # job, Producer != Verifier SS11.4.240).

$FC/gates/backstop.sh compare --fast <fast_verdicts.json> --full <full_verdicts.json> --out <drift.json> [--apply --map <gate_map.json>]
    # DEC-17 drift = a gate_id whose FULL verdict is FAIL and whose FAST
    # verdict is anything other than FAIL (absent -- selection hole -- or
    # PASS/SKIP/BLIND -- stale/wrong verdict). Exit 0: no drift found
    # (stdout first line "NO_DRIFT"). Exit 1: >=1 drift found (stdout one
    # "DRIFT gate=<id> fast=<verdict|ABSENT> full=FAIL" line per drifting
    # gate, sorted by gate_id, then "DRIFT_COUNT=<n>") -- exit 1 IS the
    # block (C-001: code 1 = "a finding ... release blocker"; DEC-17:
    # "a drift ... is a release blocker"). --out writes a
    # backstop_drift/v1 document (schema, body_hash, drift[], drift_count,
    # run_meta per C-002). The optional --apply --map <gate_map.json>
    # pair (C-006: writes are behind an explicit --apply flag) marks each
    # drifting gate's affected-set map entry `force-full` per DEC-17/
    # AS-010a -- NOT exercised by this RED test's fixtures (it crosses
    # into T-C03's own map format; this file's scope is DEC-17's
    # detect-and-block rule alone, Producer != Verifier SS11.4.240).

$FC/gates/backstop.sh freshness-queue --registry <registry.json> --fingerprint <fp> --out <queue.json>
    # Drains the SS11.4.226 guard-freshness queue. A guard is STALE
    # (queued) iff its stored last_verdict_fingerprint != <fp> (including
    # never-executed -- absent/empty fingerprint, maximally stale); a
    # guard whose stored fingerprint MATCHES <fp> is FRESH and excluded
    # from the queue regardless of reopens_count. Queue order:
    # reopens_count descending (SS11.4.189 most-reopened-first) PRIMARY,
    # staleness descending (older/absent last_verdict_at first, "then
    # stalest-first" per SS11.4.226) SECONDARY tie-break only. Exit 0
    # always (an ordering emission, not a pass/fail judgement). stdout:
    # one "QUEUE <rank> guard=<id> reopens=<n>" line per queued guard IN
    # DRAIN ORDER, then "FRESH_COUNT=<n>" "STALE_COUNT=<m>". Exit 2 usage
    # error.
```

## What this RED test does NOT cover

- The `run` subcommand's actual full-corpus execution (composes
  `gate_runner.sh` + a real gate/mutation corpus, neither constructed by
  this fixture-driven RED test — T077's own implementer-task job).
- The `--apply --map <gate_map.json>` write-back that marks a drifting
  gate's map entry `force-full` (AS-010a) — that crosses into T-C03's own
  map format and is that contract's/test's scope
  (`test_affected_set_red.sh`), not T-C10's (Producer != Verifier
  SS11.4.240).
- The release-tag-time / nightly-on-`main` / gate-engine-change scheduling
  triggers DEC-17 names for WHEN the full lane runs — this RED test
  covers only the COMPARISON + BLOCK behaviour and the freshness-queue
  drain order, both of which are agnostic to what triggered the run.
- The CLI wire format above is UNCONFIRMED by any `contracts/*.md` file
  (none exists for T-C10 at the time this file was written — confirmed by
  a real directory listing and `common-conventions.md`'s own explicit
  "open gap" listing, not assumed) and is DEFINED here,
  binding-if-adopted, per this project's established house precedent.
