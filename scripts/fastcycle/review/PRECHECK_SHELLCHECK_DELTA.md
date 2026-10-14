# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-10-13 |
| Last modified | 2026-10-14 |
| Status | proposed (ATM-1217 r6 patch); rule id `shellcheck-baseline-delta/4`; OPT-IN; NOT activated for dispatch (see "Activation") |
| Tool | `review/precheck_pack.sh` -> `review/lib/precheck_pack_run.py` (check `shellcheck`); builder `review/precheck_pack_build.sh` |
| Tests | `tests/test_precheck_shellcheck_baseline_delta.sh`, `tests/test_precheck_shellcheck_delta_mutants.sh`; the round-5/6 suite `tests/test_precheck_shellcheck_red.sh` is unchanged |
| Design | `docs/qa/atm_pack_shellcheck_delta_20261013/r6/DESIGN.md` (main repository; r3-r5 in `../r3/` .. `../r5/`) |

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
| `unchanged` | byte-identical to a base blob that was itself gated (for example a mode-only change) and under the size cap; not linted; its directives are still policed. Over the size cap it is `blind` instead | only through a D1-D4 directive |
| `new-file` | no regular base blob, a base blob that was never under this gate, or a head shellcheck could not parse (`new_file_reason`, below); every blocking finding is new | yes |
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

"Linted whole" is decided by shellcheck's own result, not only by its exit
status: a blob with a **parse error** (any SC1xxx finding at level `error`,
for example SC1089, SC1072, SC1073) was not analysed whole -- shellcheck
stops checking after a parse failure, so the lines after it get no SC2xxx
check at all. A head with a parse error is judged as a new file
(`new_file_reason` `head-unparsed: ...`); a base with one is no baseline
(`base-unlintable: base-unparsed: ...`). Before r6 a parse error the base
already had made every new line of the file invisible (r5 review H1).

Files that cannot be linted whole on this host today (measured 2026-10-13,
shellcheck 0.11.0, all 2758 tracked `*.sh` files of the main repository
`scripts/` and `device/rockchip/` and of the constitution tree):
`device/rockchip/rk3588/tests/pre_build_verification.sh` (51,843 lines) and
`scripts/testing/meta_test_false_positive_proof.sh` (33,123 lines). Both are
over the 10,000-line size cap and both are killed at a 16 GiB memory cap.
Under either rule a batch that touches them fails until they are split
(ATM-1125) -- since r6 also a byte-identical touch (a mode-only change or a
rename): a file over the size cap is `blind` even when it is unchanged. Every other measured file lints whole: the 20 files between 2,000
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
| `base-unlintable: <cause>` | could not be linted whole (over the size cap, timeout, memory-cap kill, tool failure, the host-wide large-file lock not obtained, or `base-unparsed`: a parse error) |
| `head-unparsed: <codes>` | (not a base problem) the HEAD has a parse error, so it was not analysed whole |
| `dialect-changed` | had another dialect (shebang dialect or `shell=` directive) than the head, so its findings in the head's dialect were never gated |
| `untracked-at-base`, `symlink`, `gitlink` | was not a regular file at base |

### Which head finding is pre-existing (r6)

The gate computes a line diff of the two whole blobs (base -> head; byte
lines, a one-to-one, order-preserving match of equal lines). A head finding
is **pre-existing** only when

1. its line is an **unchanged** line of that diff, and
2. the base reported the same rule and the same message (line references
   rewritten to `line N`) **on the base line it maps to** (counted per base
   line).

Everything else is new, in particular:

* a finding on an **added** or **changed** line, even when an identical one
  exists elsewhere in the base;
* a finding whose old occurrence was **suppressed** (a justified directive) or
  **fixed** in the same batch while an identical one was added (r5 review H3:
  the old `(rule, message, line text)` multiset let the old occurrence pay for
  the new one);
* a **moved** line: cut here, pasted there, it is an added line and its
  findings are new. This is stricter than r3-r5 on purpose; re-indenting a
  block also makes its old findings new.

Lines inserted or deleted elsewhere do not matter: an unchanged line keeps
its anchor wherever it moves to in line numbers.

## Directives

* `disable=all`, ranges, `extended-analysis=false`, unknown keys (D1 to D4):
  always fail, even when they were already in the base, and also in an
  `unchanged` file.
* An unjustified `disable=` (D5) that was already in the base **on the same
  unchanged line of the diff** is listed in `directive_violations_baseline`
  and does not fail. Any other one fails, including an identical copy added
  next to new code, and an identical one added after the old one was
  justified (r6).
* A parity breach always fails.

## Legacy-exception rows

A file listed in `config/shellcheck_legacy_exceptions.tsv` keeps its per-rule
ratchet against the pin. The delta rule does not apply to it.

## Activation (dispatch)

The dispatch verifier (`precheck_pack_build_run.py verify`) accepts a
`baseline-delta` pack only when the operator's activation record
`scripts/fastcycle/review/precheck_shellcheck_delta.activation` is committed in
the gate's repository **at an anchor the dispatcher supplies**:

```sh
python3 <gate>/scripts/fastcycle/review/lib/precheck_pack_build_run.py verify \
    --pack <precheck.json> --activation-commit <full commit sha> [--gate-repo <gate repository>]
```

The record must hold `decision-ref: <reference, at least 8 characters>` and
`activated-on: YYYY-MM-DD` on lines that are not comments. The verifier reads
everything with git, never from a working tree, and refuses the activation
unless:

* `--activation-commit` is a **full** hexadecimal commit id of the gate
  repository (a reference name or an abbreviation can be moved and is
  refused);
* that anchor is an ancestor of (or equal to) the gate commit at the pack's
  base (the base itself, or the gitlink the base records when the gate
  repository is a submodule of the pack's repository);
* the record at the anchor is a regular file (a symlink is refused);
* the record at the pack base is the **same blob**, and **no commit** between
  the anchor and the base touched it (a rewrite, or a delete and restore, in
  the batch's own lineage is refused).

Why an anchor and not the pack base (r5 review H2): the pack's base is
chosen by whoever builds the pack. A producer could commit the record one
commit before its work and build the pack with `--commit HEAD`; the record
was then "at the base". The anchor comes from the dispatcher, not from the
pack.

Where the dispatcher takes the anchor from (recommended): the **committed
gitlink** of the gate repository in the parent repository, i.e. the gate
commit that was reviewed and bumped, read from the parent's committed HEAD:

```sh
git -C <parent repository> rev-parse "HEAD:<gate submodule path>"
```

`--gate-repo` names the gate repository when the verifier runs from an
extracted copy outside any repository (the dispatch guard
`scripts/hooks/review_dispatch_guard.sh` extracts the committed verifier into
a temporary directory). Without `--gate-repo` such a verifier cannot locate the
record and refuses the activation. Until the guard passes both flags, a
`baseline-delta` pack is never dispatch-ready through the guard (fail closed;
wiring the guard is a change in the main repository, see DESIGN r6).

The patch ships without the record. Until it is committed (one operator
decision, reviewed like any other change) and the dispatcher anchors on it,
only whole-file packs are dispatch-ready; the builder still builds delta packs
and its cache reuses them.

Independence, stated honestly (11.4.240(F)): this is **instance**-tier
separation. On this single-uid host nothing mechanical stops the same user
from handing the dispatcher a self-made anchor or from moving the parent
repository's gitlink; what the anchor rule removes is the path through the
batch's own history.

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
* Activation is instance-tier only (see "Activation"): the anchor is only as
  trustworthy as the dispatcher's source for it.
* A finding is pre-existing only on an unchanged line (see above). Old debt on
  an unchanged line stays accepted even when a change elsewhere is what makes
  it dangerous now (for example a `cd` whose following line was edited); the
  whole-file rule would fail it.
* A parse error is detected through shellcheck's own SC1xxx `error` findings.
  A parse problem shellcheck does not report as such is not seen.
* Renames are followed only where the batch binding records them; an unbound
  run sees a renamed file as new.
