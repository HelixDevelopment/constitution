# Census: a time or age field stamped from a stale clock (round 8, 2026-11-14)

Class (from review R7-A): a script reads the clock once into a global at process start and later writes that value
into an age-bearing field, or judges an age with it, after work that may take long (a slow llmctl call, a lock wait,
a probe). The field then claims a time that is already past.

## Instrument and control needles (§11.4.273)

Scope: every tracked shell or Python file under `scripts/jev/`, `scripts/lib/`, `mcp/` (17 files), then all tracked
`scripts/**/*.sh|*.py` for the capture pattern.

| Check | Command (ERE) | Result |
|---|---|---|
| Capture pattern | `grep -nE '^(readonly \|export )?[A-Z_]+="?\$\(date \+%s\)'` | 3 hits (below) |
| Python capture | `grep -nE '^[A-Z_]+ *= *(int\()?time\.time\(\)\|^[A-Z_]+ *= *datetime'` | 0 hits |
| Positive needle (known site, bootstrap.sh:134) | same ERE on `scripts/jev/bootstrap.sh` | 1 (instrument sees) |
| Negative needle (fabricated `ZZQX_` prefix) | same ERE with `ZZQX_` | 0 |
| Instrument failure found | the same needle as a BRE (`grep -c 'NOW="$(date +%s)"'`) | 0 although the line exists: the BRE form is blind; only the ERE / `-F` forms are used |

All clock reads in the Jev files (count per file): jev-place.sh 1 (`clock_now`), lib_decide.sh 2, bootstrap.sh 1,
jev-calibrate.sh 1, jev-status.sh 1.

## Classification

| Site | What the value is used for | Direction of the error | Disposition |
|---|---|---|---|
| `scripts/jev/jev-place.sh` (was line 167) | every mark / lease / health / failure / record time, every age judgement | a mark looked OLDER than it was: a live starter's mark cleared early (unsafe: a second start, a stop during a start) | FIXED in round 8: `with_lock` reads the clock after it takes the lock (P91 to P93) |
| `scripts/jev/bootstrap.sh:134` | `generated_at`, `probed_at` (endpoints, hosted), `pending_at`, `first_created` | records look older than they are after long probes; a freshness check expires them sooner (fail-closed) | not fixed (outside this item, §11.4.293); draft item `CON-PENDING-CLOCK-BOOTSTRAP` |
| `scripts/jev/jev-calibrate.sh:56` | `calibrated_at`, backup file name | the calibration looks older by the run time (fail-closed for a staleness check) | not fixed; same draft item |
| `scripts/jev/jev-status.sh:101` | read-only age of `calibrated_at` | an age read at the start of a short read-only run; nothing is written | no defect |
| `scripts/jev/lib_decide.sh:366` | `${NOW:-$(date +%s)}` as a backup file name suffix | a name, not an age | no defect |
| `scripts/jev/lib_decide.sh:489` | a local `now` read right before its use | fresh | no defect |
| `scripts/mechanical/await_condition.sh:109` | `START` for elapsed time against a deadline | the intended meaning (time since start) | no defect |
| `scripts/fastcycle/tests/test_limit_class_r7_regression.sh:181` | elapsed time of a test | the intended meaning | no defect |

Honest boundary: a text census; it finds the capture shape, not every way a stale time can be produced (for example a
time passed in from a caller). Values passed into jq as `--argjson now` were followed to their source above.
