# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 8 |
| Created | 2026-10-13 |
| Last modified | 2026-11-03 |
| Status | proposed (ATM-1217 r10, structural replacement; independent review owed); rule id `shellcheck-baseline-delta/7`; OPT-IN; NOT activated for dispatch (see "Activation") |
| Tool | `review/precheck_pack.sh` -> `review/lib/precheck_pack_run.py` (check `shellcheck`); builder `review/precheck_pack_build.sh` |
| Tests | `tests/test_precheck_shellcheck_baseline_delta.sh`, `tests/test_precheck_shellcheck_delta_mutants.sh`; the round-5/6 suite `tests/test_precheck_shellcheck_red.sh` (r10: F6 SKIP exit 2, KEEP, no-pack diagnostics, a git identity for `commit-tree`) |
| Design | r10: the "Command units" and "Units helper" sections below (the r10 structural replacement); r3-r9: `docs/qa/atm_pack_shellcheck_delta_20261013/r9/DESIGN.md` (main repository; r3-r8 in `../r3/` .. `../r8/`) |

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

### Which head finding is pre-existing (r6, r7, r9, r10)

The gate computes a line diff of the two whole blobs (base -> head; byte
lines, a one-to-one, order-preserving match of equal lines). A line counts
as **unchanged** only together with its whole **command unit** -- r10: the
lines of the OUTERMOST statement it belongs to (see "Command units" below): the unit must map line for
line, consecutively, onto exactly the base unit of its base line; otherwise no
line of that unit is unchanged. A head finding is **pre-existing** only when

1. **every** line of the finding (from `line` to `endLine`) is an
   **unchanged** line of that diff, and those lines map to **consecutive**
   base lines (r7: a multi-line finding whose second line was edited is new),
   and
2. the base reported the **same finding** on the base line its first line
   maps to (counted per finding): the same rule, the same message (line
   references rewritten to `line N`), the same **column**, **endColumn** and
   number of lines, and the same **cited lines** -- a message that names
   another line (`... on line 5`) names a base line, and a cited line that was
   added or edited in the head is no base line at all (r7).

The lines are byte-identical on both sides, so the column of the same token
is the same on both sides. r6 matched on rule and message only, so a new
finding at another token of an unchanged line could be paid for by a
different, fixed finding of the same rule on that line (r6 review J1:
`rm -rf $root/$sub`, `$sub` made constant and `$root` made the caller's
`$1`, was credited). A finding that shellcheck reports without a column or an
end column is never pre-existing.

Everything else is new, in particular:

* a finding on an **added** or **changed** line, even when an identical one
  exists elsewhere in the base;
* a finding whose old occurrence was **suppressed** (a justified directive) or
  **fixed** in the same batch while an identical one was added (r5 review H3:
  the old `(rule, message, line text)` multiset let the old occurrence pay for
  the new one) -- **when the line diff pairs the added copy with an added
  line**. The rule judges file content, not the producer's intent: when the
  added copy sits where the diff can align it with the old line (for example
  the old `cd /tmp` becomes `cd /tmp || exit 1` and an identical `cd /tmp` is
  added on the next line), the result is byte-for-byte the same file as "kept
  the old line, inserted a guarded `cd` above it", and the copy is treated as
  the old line (pre-existing; r6 review J3) -- at the top level (test N3t).
  r10: inside a function or any other compound statement the same edit changes
  that statement's unit, so the copy is new (test N3, flipped by r10). A copy placed
  where the diff cannot align it (A2: thirty lines away) is new;
* a **moved** line: cut here, pasted there, it is an added line and its
  findings are new. This is stricter than r3-r5 on purpose; re-indenting a
  block also makes its old findings new.

Lines inserted or deleted elsewhere do not matter: an unchanged line keeps
its anchor wherever it moves to in line numbers.

### Command units (r10: from a real parser)

One command can span several physical lines, and a line's meaning depends on
the statement around it: `eval \` added above an unchanged `echo $a`, an
edited `if` condition above an unchanged body line, a `{ ...; }` group newly
piped into `sh`, a pipeline continued across a blank or comment line into an
unchanged sink (r8 review L1, r9 review F1/F2). r8 judged each line alone; r9
joined lines with a ~230-line lexical scanner, and every review found one more
way a command spans lines that the scanner did not join (a trailing `|` /
`&&` / `||` followed by a blank or comment line, compound arrays, `$[ ]`). Each
new lexical rule was only as complete as the generator that checked it, so r10
deletes the scanner (operator decision 2026-11-03).

r10: the units come from a **real shell parser**, `mvdan.cc/sh/v3/syntax`
(BSD-3-Clause), through a small Go helper in `units_helper/`:

* **A unit is one OUTERMOST statement** of the parse tree: an element of the
  file's top-level statement list -- a whole `if` / `while` / `for` / `case` /
  `{ }` / `( )` / function definition / pipeline / `&&`-`||` list -- from the line
  it starts on to the LAST line any node under it reaches. Here-document bodies
  and their terminator lines are included wherever the redirect sits (inside a
  pipeline, a list, a substitution, a function). Statements that share a line are
  one unit; a line outside every statement (blank, comment) is a unit of its own.
* **Coarser than r9, on purpose (stricter only).** An edit anywhere in a
  function, loop or `if` makes every finding of that whole statement new. A
  large function touched in one place loses all its credit; the whole-file rule
  would fail all of it anyway.
* **Dialect.** The helper parses in the dialect shellcheck linted the blob in:
  `sh` / `dash` -> POSIX, `bash` -> bash. **ksh is not mapped** (mvdan/sh parses
  mksh, shellcheck lints ksh88/93, and no ksh is installed on the reference host
  to compare the two): a ksh file fails closed. A `shell=` directive that
  disagrees with the linted dialect also fails closed.
* **Fail closed, every way.** No units means no credit: the helper absent, not
  buildable, timed out, crashed or killed by its memory cap; a parse error in
  that dialect (a bash array in a `#!/bin/sh` file); output that is not JSON, not
  schema `precheck-units/1`, for another dialect, with another line count, or
  not an in-order partition of the blob's lines. A head then is judged as a NEW
  file (`new_file_reason` "units-unparsed: ..."; every blocking finding fails);
  a base has no baseline ("base-unlintable: units-unparsed: ..."). Both are the
  whole-file verdict.
* **An empty here-document body** (`cat <<EOF` immediately followed by `EOF`)
  has no body word in the parse tree; the unit is extended up to the next
  top-level statement that starts on a later line (a superset, stricter only),
  and the delimiter line must be found in that range, else the helper fails
  closed.

The helper runs under the same scrubbed environment and memory cap as
shellcheck (`systemd-run` scope), with its own 60 s budget inside the batch
budget. Evidence records `tool.delta.units`: parser module and version, schema,
granularity (`outermost-statement`).

**Census (r10 evidence).** The helper's partition was compared, script by
script, with the shells' own parsers (bash 5.3.9, dash): a unit ends at the
first line `k` where `<sh> -n` accepts lines `s..k` with no warning AND rejects
lines `s..k` plus a stray `}` (a `}` is absorbed after a trailing backslash or
inside a here-document body, so it errors only after a complete statement).
Over 800 generated scripts from a 44-fragment pool (blank and comment lines after
`|` / `&&` / `||`, arrays, `declare -a`, `$[ ]`, here-documents in pipelines and
lists, nested substitutions with `case`, functions, here-strings): 799 equal
partitions, 1 difference -- an empty here-document body, where the helper's unit
is the wider one (the stated extension above, stricter). Controls: a helper that
returns one unit per line differs on 98 of 100 scripts; the r9 lexical scanner
differs on 333 of 400 (r9 units are per command, not per outermost statement, and
r9 splits the F1 shapes). The census measures agreement with bash and dash on
this pool only; it is not a proof for every script.

### Units helper and its dependency

* Source: `units_helper/main.go`, module
  `github.com/HelixDevelopment/HelixConstitution/scripts/fastcycle/review/units_helper`.
* Dependency: `mvdan.cc/sh/v3 v3.13.1`, vendored under `units_helper/vendor/`
  (only `syntax/` and `fileutil/`, byte-identical to the module zip minus test
  files) and pinned by `go.sum` (`h1:DP3TfgZhDkT7lerUdnp6PTGKyxxzz6T+cOlY/xEvfWk=`).
  Verdict row: `units_helper/DEPENDENCY_VERDICT.jsonl` (VERIFIED, SHIPPED). It is
  not a git submodule, so it has no `helix-deps.yaml` entry.
* Build: offline (`-mod=vendor`, `GOPROXY=off`, `GOTOOLCHAIN=local`,
  `CGO_ENABLED=0`), under a lock and a 4096 MiB memory cap, into
  `$PRECHECK_UNITS_CACHE_DIR` (default `$XDG_CACHE_HOME` or
  `~/.cache/fastcycle-precheck-units`) in a directory named by the sha256 of every
  helper source file; a cached binary is used only while its recorded sha256
  matches. A host without `go` and without a cached helper fails closed.
* Test mode only (`PRECHECK_TEST_MODE=1`): `PRECHECK_UNITS_HELPER` names a stub
  helper and `PRECHECK_UNITS_TIMEOUT_S` a shorter budget (the fail-closed cases).

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
wiring the guard is a change in the main repository: a ready patch, NOT
applied, is in DESIGN r7 section 5).

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
* A finding is pre-existing only on an unchanged line of an unchanged
  outermost statement (see above). Old debt on such a line stays accepted even
  when a change in ANOTHER top-level statement is what makes it dangerous now: a
  top-level `cd` whose following statement was edited, a variable whose
  top-level assignment elsewhere changed. The whole-file rule would fail it.
  Only a dependency the finding's own message cites (`on line N`) is followed
  (r7); any other dependency on another statement is not. r10 closes the
  in-statement half (an edited `if` condition, `{ ...; } | sh`, an edit
  elsewhere in the same function: tests L1n4, R10-R12a, R10-R12b).
* r10 units: ksh files and files a `shell=` directive puts in another dialect
  get no credit (fail closed); a function-heavy file loses credit for a whole
  function on any edit inside it; an empty here-document body widens its unit
  to the next statement. The units' agreement with bash and dash is measured on
  a generated pool, not proven for every script.
* The units helper's cache is trusted by a sha256 stamp written next to it in
  the same user-owned directory; a party that can write that directory can
  replace both. The `go` toolchain version is not part of the cache key.
* The `fix` suggestion shellcheck attaches to a finding is not part of its
  identity. The r8 census found one pair where only
  `fix.replacements[].precedence` differed; it was the command-unit class
  (an added line ending in `\` above an unchanged line), which r9 closes in
  code: that finding is now new (test N13, flipped by r9).
* A parse error is detected through shellcheck's own SC1xxx `error` findings.
  A parse problem shellcheck does not report as such is not seen, and neither
  is a parse error a directive suppresses (`disable=SC1072,SC1073,...`): this
  row then sees no finding at all. The pack's separate `parse` row still fails
  such a file, so the pack is not dispatch-ready (r6 review observation).
* Renames are followed only where the batch binding records them; an unbound
  run sees a renamed file as new.
