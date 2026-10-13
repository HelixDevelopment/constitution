# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-10-13 |
| Last modified | 2026-10-13 |
| Status | proposed (ATM-1217 r5 patch); rule id `shellcheck-baseline-delta/3`; OPT-IN; NOT activated for dispatch (see "Activation") |
| Tool | `review/precheck_pack.sh` -> `review/lib/precheck_pack_run.py` (check `shellcheck`); builder `review/precheck_pack_build.sh` |
| Tests | `tests/test_precheck_shellcheck_baseline_delta.sh`, `tests/test_precheck_shellcheck_delta_mutants.sh`; the round-5/6 suite `tests/test_precheck_shellcheck_red.sh` is unchanged |
| Design | `docs/qa/atm_pack_shellcheck_delta_20261013/r5/DESIGN.md` (main repository; r3, r4 in `../r3/`, `../r4/`) |

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
| `blind` | the head could not be linted whole (timeout, memory-cap kill, tool failure, size cap, parity re-lint failure); `cause` says why. The same verdict as the whole-file rule | always fails |

Every lint input is a **whole** blob: the head blob or the base blob. The
gate never lints a part of a file. (r3 and r4 linted "windows" around the
changed lines when a side could not be linted whole; two reviews in a row
found windows that meant something else than the file, so r5 removed them.)
When the **base** cannot be linted whole, it is not a baseline: the file is
judged as a new file with `new_file_reason` `base-unlintable: <cause>`, so
every blocking finding of the head fails, exactly as under the whole-file
rule. The delta rule is therefore never laxer than the whole-file rule for a
file that cannot be linted whole.

Files that cannot be linted whole on this host today (measured 2026-10-13,
shellcheck 0.11.0, all 2758 tracked `*.sh` files of the main repository
`scripts/` and `device/rockchip/` and of the constitution tree):
`device/rockchip/rk3588/tests/pre_build_verification.sh` (51,843 lines) and
`scripts/testing/meta_test_false_positive_proof.sh` (33,123 lines). Both are
over the 10,000-line size cap and both are killed at a 16 GiB memory cap.
Under either rule a batch that touches them fails until they are split
(ATM-1125). Every other measured file lints whole: the 20 files between 2,000
and 10,000 lines (largest `scripts/build.sh`, 4,755 lines) each took under 4 s
and under 1.4 GB (design record r5, section 2).

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
| `base-unlintable: <cause>` | could not be linted whole (over the size cap, timeout, memory-cap kill, tool failure, the host-wide large-file lock not obtained) |
| `dialect-changed` | had another dialect (shebang dialect or `shell=` directive) than the head, so its findings in the head's dialect were never gated |
| `untracked-at-base`, `symlink`, `gitlink` | was not a regular file at base |

A finding's identity is its rule, its message (with line references rewritten
to `line N`) and the text of its source line, compared as a multiset. A
finding that moved is not new; a second copy of an existing finding is new.

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
`review/precheck_shellcheck_delta.activation` is **committed** in the gate's
repository **at the pack's base commit**, with the lines
`decision-ref: <reference, at least 8 characters>` and
`activated-on: YYYY-MM-DD`. The verifier reads it with `git ls-tree` and
`git cat-file`, never from the working tree:

* an untracked or modified file on disk does not count;
* a record that the batch under review adds (present only at its head) does
  not count;
* a record committed as a symlink is refused (it must be a regular file);
* when the gate's repository is a submodule of the pack's repository, the
  record is read in the gate repository at the gitlink that the pack's base
  records.

The patch ships without the record. Until it is committed (one operator
decision, reviewed like any other change), only whole-file packs are
dispatch-ready; the builder still builds delta packs and its cache reuses
them.

## Cached packs

The builder's cache rebuilds a pack that was built under another rule or
another timeout; it never reuses it.

## Limits (stated)

* A directive that existed in the base also hides its codes in new code.
* Pre-existing debt is accepted by design. The base checks prove only that
  the base blob is a shell candidate at base, has no NUL byte, has no
  legacy-exception row at base and has the head's dialect. They do not prove
  that the base passed this gate; most bases predate it. Every blocking
  finding the base already has is "pre-existing", including findings in a
  base no review ever linted (an unreviewed commit inside a later batch's
  base).
* The base is linted with the host's **current** shellcheck. After a
  shellcheck upgrade, findings that only the new version reports on the base
  are "pre-existing" too (the same accepted debt). The whole-file rule would
  fail them.
* The activation record is honoured when it is committed at the pack's base,
  even if the commit that added it was never reviewed itself (the same trust
  as the base content above).
* Renames are followed only where the batch binding records them; an unbound
  run sees a renamed file as new.
