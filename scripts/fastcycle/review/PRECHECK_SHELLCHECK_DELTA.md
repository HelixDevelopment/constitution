# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-13 |
| Last modified | 2026-10-13 |
| Status | proposed (ATM-1217 r3 patch); rule id `shellcheck-baseline-delta/2`; OPT-IN |
| Tool | `review/precheck_pack.sh` -> `review/lib/precheck_pack_run.py` (check `shellcheck`); builder `review/precheck_pack_build.sh` |
| Tests | `tests/test_precheck_shellcheck_baseline_delta.sh`, `tests/test_precheck_shellcheck_delta_mutants.sh`; the round-5/6 suite `tests/test_precheck_shellcheck_red.sh` is unchanged |
| Design | `docs/qa/atm_pack_shellcheck_delta_20261013/r3/DESIGN.md` (main repository) |

## What it is

The shellcheck row has two rules:

| rule | selected by | a blocking finding in a touched file fails when ... |
|---|---|---|
| `whole-file` (default) | nothing, or `--shellcheck-rule whole-file` | it exists ("touch a file, own its findings") |
| `baseline-delta` | `--shellcheck-rule baseline-delta` | it is **new** compared with the file's base blob |

Everything else is shared and unchanged: the severity floor (error and warning,
plus the info rules SC2086 SC2030 SC2031 SC2162 SC2059), the hard
`systemd-run` memory cap, the size cap, the per-batch time budget, the
host-wide lock for large files, the batch binding, directive policing with the
parity oracle, and the legacy-exception ratchet.

## How to use it

```sh
# one commit, delta rule
sh scripts/fastcycle/review/precheck_pack_build.sh --commit <sha> --shellcheck-rule baseline-delta
# a range
sh scripts/fastcycle/review/precheck_pack_build.sh --commit <base>..<head> --shellcheck-rule baseline-delta
```

The base is always the explicit batch base the builder binds
(`--baseline-repo` / `--baseline-ref`). It is never guessed. With no base at
all, the delta rule gives the whole-file verdict and says so in
`evidence.delta.caveat`.

The per-lint timeout default under the delta rule is **120 s**
(`--shellcheck-timeout`, at most 600 s; a larger value or a non-number exits
2). Under the whole-file rule it stays 60 s.

## What the evidence says (`evidence.delta.files[].state`)

| state | meaning | can fail? |
|---|---|---|
| `unchanged` | byte-identical to the base blob (for example a mode-only change); not linted | no |
| `new-file` | no regular base blob; every blocking finding is new | yes |
| `full` | head and base linted whole; only new blocking findings fail; old ones are in `baseline_findings` | yes |
| `window` | one side could not be linted whole (timeout, memory-cap kill, tool failure, size cap); the changed hunks were linted in enclosing-function windows on both sides | yes; see the caveat |
| `unresolved` | no window could bound the change; `window_fallback` says why | always fails |

A finding's identity is its rule, its message (with line references rewritten
to `line N`) and the text of its source line, compared as a multiset. A
finding that moved is not new; a second copy of an existing finding is new.

`window` proves only that no new blocking finding appears **inside** the
windows. It does not prove the file is clean.

## Directives

* `disable=all`, ranges, `extended-analysis=false`, unknown keys (D1 to D4):
  always fail, even when they were already in the base.
* An unjustified `disable=` (D5) that was already in the base is listed in
  `directive_violations_baseline` and does not fail. A new one fails.
* A parity breach always fails.

## Legacy-exception rows

A file listed in `config/shellcheck_legacy_exceptions.tsv` keeps its per-rule
ratchet against the pin. The delta rule does not apply to it.

## Cached packs

The builder's cache rebuilds a pack that was built under another rule or
another timeout; it never reuses it.

## Limits (stated)

* A directive that existed in the base also hides its codes in new code.
* Window snippets lack the rest of the file. Findings that depend on context
  outside the window can be over-reported. A finding caused outside the windows
  by a change inside them is not seen.
* Renames are followed only where the batch binding records them; an unbound
  run sees a renamed file as new.
