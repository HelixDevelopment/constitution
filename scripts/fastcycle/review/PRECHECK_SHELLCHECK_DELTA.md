# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-13 |
| Last modified | 2026-10-13 |
| Status | proposed (ATM-1217 r4 patch); rule id `shellcheck-baseline-delta/2`; OPT-IN; NOT activated for dispatch (see "Activation") |
| Tool | `review/precheck_pack.sh` -> `review/lib/precheck_pack_run.py` (check `shellcheck`); builder `review/precheck_pack_build.sh` |
| Tests | `tests/test_precheck_shellcheck_baseline_delta.sh`, `tests/test_precheck_shellcheck_delta_mutants.sh`; the round-5/6 suite `tests/test_precheck_shellcheck_red.sh` is unchanged |
| Design | `docs/qa/atm_pack_shellcheck_delta_20261013/r4/DESIGN.md` (main repository; r3 in `../r3/`) |

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
| `unchanged` | byte-identical to a base blob that was itself gated (for example a mode-only change); not linted; its directives are still policed | only through a D1-D4 directive |
| `new-file` | no regular base blob, or a base blob that was never under this gate (`new_file_reason`, below); every blocking finding is new | yes |
| `full` | head and base linted whole; only new blocking findings fail; old ones are in `baseline_findings` | yes |
| `window` | one side could not be linted whole (timeout, memory-cap kill, tool failure, size cap); the changed hunks were linted in enclosing-function windows on both sides | yes; see the caveat |
| `unresolved` | no window could bound the change; `window_fallback` says why | always fails |

### When the base counts as a baseline

A base blob is compared against only when it was itself under this gate at
base. Otherwise the file is judged as a new file, and `new_file_reason` says
why:

| `new_file_reason` | the base blob ... |
|---|---|
| `base-not-shell` | had no shell extension on its BASE path and no shell shebang in its BASE bytes (the gate's own selection test). Examples: an extension-less file that gains a shebang; `notes.txt` renamed to `notes.sh` (even byte-identical); `x.SH` renamed to `x.sh` (extensions are case-sensitive) |
| `base-nul` | carried a NUL byte (the gate refuses such a script) |
| `base-exception-row` | was a legacy-exception row at base (its findings were pinned debt; dropping the row needs the whole-file verdict) |
| `base-ledger-unknown` | the base exception ledger could not be read |
| `dialect-changed` | had another dialect (shebang dialect or `shell=` directive) than the head, so its findings in the head's dialect were never gated |
| `untracked-at-base`, `symlink`, `gitlink` | was not a regular file at base |

A finding's identity is its rule, its message (with line references rewritten
to `line N`) and the text of its source line, compared as a multiset. A
finding that moved is not new; a second copy of an existing finding is new.

`window` proves only that no new blocking finding appears **inside** the
windows. It does not prove the file is clean.

Every window boundary must be proven to lie outside a quoted string, a
heredoc body and a backslash-newline continuation. A cut inside a multi-line
string re-pairs the quotes and turns new code into string text without any
parse error, so the gate moves an unproven boundary outward to the nearest
proven one. The proof comes from a small lexer that models shell quoting. When
it meets something it does not model (for example `case` inside `$(...)`, a
heredoc delimiter it cannot read, an escaped backtick inside backticks), every
later boundary is unproven and the file is `unresolved`. A finding on the
file's first line (the shebang that prefixes each window) is reported at line 1,
once per side.

## Directives

* `disable=all`, ranges, `extended-analysis=false`, unknown keys (D1 to D4):
  always fail, even when they were already in the base, and also in an
  `unchanged` file.
* An unjustified `disable=` (D5) that was already in the base is listed in
  `directive_violations_baseline` and does not fail. A new one fails.
* A parity breach always fails.

## Legacy-exception rows

A file listed in `config/shellcheck_legacy_exceptions.tsv` keeps its per-rule
ratchet against the pin. The delta rule does not apply to it.

## Activation (dispatch)

The dispatch verifier (`precheck_pack_build_run.py verify`) accepts a
`baseline-delta` pack only when the operator's activation record
`review/precheck_shellcheck_delta.activation` exists in the verifying checkout,
with the lines `decision-ref: <reference, at least 8 characters>` and
`activated-on: YYYY-MM-DD`. The patch ships without it. Until it exists, a
producer cannot opt its own batch into the laxer rule for dispatch; the
builder still builds delta packs (and its cache reuses them).

## Cached packs

The builder's cache rebuilds a pack that was built under another rule or
another timeout; it never reuses it.

## Limits (stated)

* A directive that existed in the base also hides its codes in new code.
* Window snippets lack the rest of the file. Findings that depend on context
  outside the window (an assignment, a file-scope directive, a `shell=`
  directive) can be over-reported. A finding located outside the windows that a
  change inside them causes is not seen: this is the one way `window` can miss
  a new finding.
* The boundary proof is a lexer model of shell quoting, not shellcheck's own
  parser. Constructs it does not model make it refuse; a mismatch it does not
  detect is a residual. Cuts inside `if`, `case` or function bodies are caught
  by the standalone-parse refusal (SC1xxx).
* Renames are followed only where the batch binding records them; an unbound
  run sees a renamed file as new.
* The rule trusts that a base blob that passes the checks above was gated when
  it entered the base. An unreviewed commit inside a later batch's base is
  trusted; the whole-file rule would re-lint it. A base over the size cap is
  handled by the window fallback rather than refused.
