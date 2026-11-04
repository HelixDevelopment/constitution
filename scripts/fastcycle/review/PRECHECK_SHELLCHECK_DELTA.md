# Precheck pack: the baseline-delta rule for the shellcheck row

| Field | Value |
|---|---|
| Revision | 12 |
| Created | 2026-10-13 |
| Last modified | 2026-11-04 |
| Status | proposed (ATM-1217 r13, review round 3: POSITIVE minimal subset for the units helper, gate-owned git dir for every git call of the gate and the builder, not `tower_detector_run.py`; round 5: review r4 F1-F4 closed class-wide, see "r13 round 5"; independent review owed); rule id `shellcheck-baseline-delta/9`; OPT-IN; NOT activated for dispatch (see "Activation") |
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
* **r11: the parser must agree with the shell about where a unit ends.** The
  r10 review found two places where the parse tree and the real shell disagree
  (an alias that continues a command on the next line; a here-document
  delimiter whose quoting the parser reads differently). r11 enumerates the
  whole class and closes every member it found, each with a control-needled
  test (the shell itself is run on the fragment and must show the
  disagreement or agreement the test assumes):
  * **r13 (review round 3, H1): a POSITIVE, MINIMAL credited subset
    (replaces the r12 allowlist R1-R5).** Round 3 found 247 of 609 generated
    scripts unsound under r12: bash re-reads DATA as code in the current shell
    (arithmetic on a variable's value, a name operand's subscript, `PS4` under
    `xtrace`), and bash 5.3 runs function substitution `${ cmd; }` there, so an
    alias is defined without any alias command. A deny-list cannot close a
    family it does not name, so r13 credits a file ONLY when every node of its
    parse tree is in a small subset checked node kind by node kind
    (`units_helper/main.go`, rules P1-P10); any other node kind, operator,
    builtin, option or variable name exits 5 ("outside the r13 positive
    subset"), and a node type the parser adds later fails closed (a second
    pass rejects every type not listed). In short: no arithmetic of any kind,
    no arrays or computed subscripts (only `${x[0]}` / `[@]` / `[*]` in an
    expansion), no `${!x}` / `${#x}` / slices / replacements / `${x@..}` /
    `${x:=w}`, no backquotes, no extended globs (`shopt -s extglob` is not on
    the shopt list, and an extglob node fails closed), no command word that is
    not a static literal, no builtin outside a short safe list (`read`,
    `mapfile`, `printf -v`, `eval`, `.`, `source`, `trap`, `alias`, `declare`,
    `let` ... all fail closed), no assignment to any variable bash documents
    under "Shell Variables" (112 names, plus `PATH` and every `BASH*` /
    `COMP_*` / `READLINE_*` name), and `exec` only with a static command
    (`exec 0<f`, review mutant RM6, fails closed). New in r13 (P8): when the
    script is itself read on stdin (`sh < file`, `curl | sh`), a command that
    reads stdin consumes the rest of the script; measured: `head -c 10
    >/dev/null` before a `#xxxxxxxx echo hi |` comment line makes `bash
    --posix` run `echo hi | tr ...` joined with the next line. Every external
    command except a short no-stdin list is therefore credited only where its
    stdin is not the shell's (later pipeline element, or a command whose LAST
    fd-0 redirection is a here-document / here-string / `<&-`). A background
    command is NOT stdin-away (round 5, review r4 F3; an earlier revision of
    this text said it was, which was wrong: bash opens an explicit
    `</dev/stdin` after its implicit `</dev/null`, measured).
    **Proof (stated):** the round-3 reviewer corpus (609 scripts) and a new r13
    adversarial census (932 scripts, `tests/units_r13_census.py`: stdin
    consumers in five contexts and every builtin / expansion channel with
    function-substitution, command-substitution and plain needles, run in dash
    and `bash --posix` for POSIX and bash for bash, with a stub `curl` and
    controls): r12 helper (901fa52) 247 and 259 unsound; r13 helper 0 and 0.
    This is a generated pool, not a proof for every script.
    **Mutants (r13):** the r12 deny-list mutants AL12-02..07/09..18, MR3,
    MR3b and MR8 are RETIRED (their code is deleted); R13-01..17 target each
    positive-subset rule, R13-H2a..c the gate-owned git dir. Review mutant RM7
    (`POSIXLY_CORRECT` dropped from the denied names): no case was found where
    crediting a `POSIXLY_CORRECT` assignment joins lines differently, so it is
    probably equivalent for soundness (UNCONFIRMED); it is killed only by the
    fail-closed policy cases r11-al13/al14 (mutant R13-RM7), not by a
    demonstrated unsound credit.
    **r13 round 5 (review r4 F1-F4, class-wide).** Review round 4 found three
    soundness holes, each measured with real bash (`--posix` and default):
    a NUL inside `$'..'` ends the word in bash (`[ $'-v\0' 'a[$(cmd)]' ]` is
    `test -v` and runs `cmd`; `$'eval\0z' 'cmd' <<E` runs `eval`), fd 0 can be
    copied and restored (`dd 3>&0 <<E 0>&3` reads the script after the
    here-document), and a background command with `</dev/stdin` reads the
    script (the rule "background is stdin-away" was wrong). Round 5 does not
    close these three shapes one by one; it enumerates the ways the shell can
    read the script, or a word, differently from the static parse (the
    R1-R8 table in `units_helper/main.go`) and closes each class: P8 now
    takes the LAST fd-0 redirection (left to right), background is never
    stdin-away; P9 admits only output to a file, `>&1` / `>&2` / `>&-`, `<&-`,
    and input or here-documents on fd 0 (every duplication of fd 0, input on
    another descriptor, and fd 0 opened for writing fail closed); P10 makes a
    word non-static when its decoded bytes contain a NUL or its `$'..'` uses
    `\c` (`\c?` is 0x7f in bash) or `\u` / `\U` (decoded by the locale:
    under `LC_ALL=C` bash keeps `\u00E9` as text). Stated limits (not
    refusable by a static check): an external program that opens the
    shell's descriptor by path (`/proc/$$/fd/0`) or rewrites the script file,
    and the caller's environment. The three reviewer mutants that survived
    (RV4-01 `trap` removed from the shell words, RV4-02 `cat` added to the
    no-stdin list, RV4-03 `PS4` assignable) are adopted verbatim with pinned
    refusal cases and real-shell needles (r13-trap, r13-cat, r13-ps4).
    New mutants: R13-17 is RETIRED (its rule is deleted), R13-17b (background
    treated as stdin-away again) and R13-24 (fd 0 opened for writing allowed)
    are EQUIVALENT with measured arguments (the last-redirection rule and the
    async list's /dev/null make every measured shape inert; the rules are
    kept conservative), R13-18 (NUL), R13-20 (`\c` / `\u`), R13-21 (any `>&`
    target), R13-22 (input on fd 3+), R13-23 (first fd-0 redirection wins) and
    RV4-01..03 are killed. The r13 adversarial census grew to 1006 cases (F4
    family: duplication, order, background, inherited descriptors, NUL and
    locale escapes, the three reviewer mutants); the round-4 helper (88431bf)
    is UNSOUND on 30 of them, the round-5 helper on 0.
    **Cost, measured, plainly:** over the 1150 tracked `.sh` files of this
    repository the r12 helper gave units for 471, the r13 helper for **70**
    (6 %). 1077 files exit 5: 600 because they use a builtin outside the
    subset (mostly `.` sourcing), 231 because a command may read the shell's
    stdin, 105 arithmetic, 74 a `test` with an unknown field count. With so
    little credit the baseline-delta rule saves almost nothing on this
    repository; the operator's recorded fallback (abandon baseline-delta, keep
    the whole-file rule) is the expected outcome of this review round, and
    the rule stays OPT-IN and not activated.
  * **r12 (superseded by r13): the runtime grammar was an ALLOWLIST
    (replaced the r11 alias blacklist).** dash and `bash --posix` (both can be `/bin/sh`) expand
    aliases, and an alias ending in `|` or `&&` continues the command on the
    next line, which no static parser sees. r11 refused the ways to define an
    alias one by one; review r2 measured that a trap action, `printf -v`,
    `read`, a nameref, `. /dev/stdin`, `${x@P}`, `mapfile -C` and more still
    reached `BASH_ALIASES` or ran `alias`. r12 inverts the rule: a statement is
    accepted only when the helper can see everything it does to the shell's
    grammar. The helper exits 5 ("runtime grammar: not modelled, r12
    allowlist") on the first statement that breaks one of:
    * **R1** every command word is static (quote removal and `$'..'` decoded;
      no expansion, no unquoted glob character -- a `[` with no `]` after it is
      literal -- no leading `~`). `command` / `builtin` and their options are
      skipped (`command -v` / `-V` runs nothing); the exec wrappers (`exec`,
      `env`, `nohup`, `time`, `xargs`, `nice`, `timeout`, `stdbuf`, `setsid`,
      `ionice`, `chrt`, `taskset`, `sudo`, `doas`) skip their options and
      `VAR=val`, and a computed operand under them runs in a child process.
    * **R2** code builtins: `alias`, `unalias`, `.`, `source`, `enable`, `fc`,
      `bind`, `complete`, `compgen`, `compopt`, `history` always fail closed
      (`.` / `source` run code the helper does not read; stricter than "only a
      non-literal path": a script can write a file and source it by a literal
      name). `eval` is accepted only when every argument is static, and the
      joined text is checked recursively (depth 8, then fail closed). `trap`:
      listing / resetting is accepted; a trap on EXIT only (`EXIT`, `0`,
      `SIGEXIT`) is accepted with any action (it runs after the last line was
      read); any other trap needs a static signal list and a static action,
      checked recursively. `set`: `-o` / `+o` names from an allowlist (not
      `posix`), option letters from `abeEfhkmnpPtTuvxBC`. `shopt`: names from an
      allowlist (not `expand_aliases`, not `posix`).
    * **R3** a variable name given to `printf -v`, `read`, `mapfile` /
      `readarray`, `getopts` or a `declare`-family command must be static;
      `mapfile -C` (a callback) and `declare -n` / namerefs fail closed.
    * **R4** `BASH_ALIASES`, `POSIXLY_CORRECT`, `PS0`-`PS4`, `PROMPT_COMMAND`,
      `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS` must not be assigned (plain,
      `${X:=}`, `declare` / `export` / `unset`); `BASH_ALIASES` and
      `POSIXLY_CORRECT` fail closed in any word; `${x@P}` fails closed; a
      variable set to the word `alias` / `unalias` fails closed.
    * **R5** `exec` with no command and an input redirection of fd 0 fails
      closed (the rest of the file is then read from elsewhere).
    Proof: `tests/units_runtime_grammar_census.py` generates 864 scripts (81
    channels x contexts x posix/bash, each with `p` on one line and `tr` on the
    next, where `alias p='echo hi |'` would join them) and runs each in the real
    shells (dash and `bash --posix` for posix, bash for bash). A script is
    UNSOUND when a shell prints `HI` and the helper still splits the two lines.
    Measured: the r11 helper (46fde9c) 356 unsound; the r12 helper 0 unsound,
    813 positives closed, 23 of 23 claimed-benign shapes credited, 3 shapes
    refused that are benign (`"$@"` as a command word, `. ./lib.sh`, a `PS4`
    assignment; stricter, stated). Controls inside the census: a positive
    control a shell must join and the helper must refuse, a negative control
    both must keep apart; a failed control is exit 2. The census is case
    `R12-G1` of the delta suite, run against the helper of the tree under test.
    **Cost, measured (stated):** over the 1150 tracked `.sh` files of this
    repository the r11 helper gave units for 1143, the r12 helper for 471: 672
    files now fall to the whole-file rule, 537 of them because they source a
    file (`.` / `source`), 95 because of a computed command word (`"$SC" ...`),
    19 a computed `eval`. This is fail-closed (no credit), not a bluff; a
    finer rule (units proven only up to the first such statement) is a design
    option recorded for review, not built.
  * **Here-document delimiters use the shell's quote removal.** Inside double
    quotes a backslash is removed only before `$`, `` ` ``, `"`, `\` and a
    newline (POSIX 2.2.3); outside quotes every backslash is removed; inside
    single quotes nothing is. The terminator of every here-document is
    cross-checked against that text (also for `<<-`, where leading tabs are
    stripped first). `<<"a\$b"` is a parse error in the parser and fails closed
    (stricter than the shell, which accepts it). `<<$'EOF'` and `<<$"EOF"` end at
    different lines in dash and in `bash --posix`; shellcheck itself refuses
    them (SC1044), so they reach this rule only as a head-unparsed file.
  * **POSIX files are parsed twice.** A `sh` / `dash` blob is parsed as POSIX
    AND as bash (bash can be `/bin/sh`); the units are the union (merged
    overlaps, stricter only). A blob that parses as POSIX but not as bash fails
    closed ("bash cross-parse: ..."). Bash-only syntax in a POSIX blob (`<<<`,
    `function`, `;&`, `|&`) is a POSIX parse error and fails closed; dash
    refuses it too. `[[ ... ]]` in a POSIX blob is parsed as an ordinary command
    (as dash runs it); a `||` inside it continues the unit onto the next line in
    both.
  * **A NUL byte fails closed** (exit 5): dash drops it, bash refuses the file,
    the parser keeps it.
  * **Checked** (tests pin the helper's units; for the delimiter and alias
    cases a control needle also runs dash or bash on the fragment): `<<\EOF`, `E"O"F`,
    `"E F"`, `<<-` with tabs, a backslash-newline inside a delimiter word, a
    body line that only resembles the delimiter, `coproc`, a here-document
    inside `$( )`, `case` patterns with a leading `(`, a trailing `\` at end of
    file.
  * **Scoped out, stated:** (r13: extglob patterns now fail closed, see
    above); aliases or
    `POSIXLY_CORRECT` coming from the caller (`ENV`, `BASH_ENV`, the starting
    environment); r12: a computed `eval`, `.` / `source` and a computed command
    word (`$cmd`) are no longer scoped out -- they fail closed (R1, R2);
    `((echo a) )`, which the parser refuses in bash mode while bash
    runs it (fails closed, stricter).

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
  `CGO_ENABLED=0`, `-trimpath`, `-buildvcs=false`), under a lock and a 4096 MiB
  memory cap, into `$PRECHECK_UNITS_CACHE_DIR` (default `$XDG_CACHE_HOME` or
  `~/.cache/fastcycle-precheck-units`). r11: the cache directory is named by the
  sha256 of the helper sources (`BINARY_PINS.tsv` excluded), the `go` version
  (`go env GOVERSION`), the platform (`GOOS/GOARCH`) and the build flags.
  `GOCACHE` is always the cache's own `gocache/` directory, never the caller's.
  The stamp records the binary's sha256, the source hash, the go version and the
  platform; a cached binary is used only while all four match the values
  recomputed now and the binary's sha256 matches the stamp.
* **Binary pins (r11, r12).** `units_helper/BINARY_PINS.tsv` maps (source hash, go
  version, platform) to the sha256 of the reproducible build (measured
  identical across fresh build caches). For a pinned toolchain a cached binary
  whose sha256 differs from the pin is rebuilt, and a fresh build that differs
  from the pin is refused (fail closed); this also defeats a forged
  binary-and-stamp pair. r12 (review G3): a toolchain any row names is a
  REFERENCE toolchain, and on it a source hash with no row is refused (a
  comment-only edit of `main.go` that is not re-pinned can no longer drop the
  protection silently); an absent, unreadable, empty or malformed table is
  refused. Re-pin after review with `python3 lib/units_pin_refresh.py --write`
  (two builds from empty caches with the gate's flags; refused when they
  differ). For a toolchain no row names the stamp is the only check (stated
  limit); the suite reports the pin cases there as SKIP and exits 2, never as a
  pass. `go` is required even when a cached binary exists (the cache
  key needs the go version): a host without `go` fails closed.
* Exit codes of the helper: 0 units, 2 usage, 3 parse error, 4 inconsistency,
  5 unmodelled construct (r11: NUL byte; r12: any R1-R5 runtime-grammar rule). Every non-zero exit is
  the whole-file verdict.
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
* The units helper's cache: for a toolchain listed in `BINARY_PINS.tsv` a
  replaced binary is rebuilt even with a matching forged stamp; for an unlisted
  toolchain the stamp in the same user-owned directory is the only check, so a
  party that can write that directory can replace both. The pin itself lives in
  the repository and is only as trustworthy as the checkout.
* r13 units: aliases, `POSIXLY_CORRECT`, exported functions, an inherited
  `PATH` or a non-UTF-8 locale from OUTSIDE the file (`ENV` / `BASH_ENV` of the
  caller, the environment the script starts with) and a script that rewrites
  its own file while it runs are not modelled; the helper cannot see them. An
  alias can only be defined inside the file through a node the subset refuses,
  so aliases defined in the file are closed by construction, not by a list.
  The no-stdin list of external programs is a claim about the usual GNU /
  busybox programs. Inside the file the subset fails closed on every channel
  the two censuses enumerate; the censuses are generated pools, not a proof.
  A file outside the subset gets no credit at all: 1080 of this repository's
  1150 shell files (see "Command units").
* git (r13, review round 3 H2): no git call of the gate or the builder reads
  the reviewed repository's git dir as a repository. `lib/precheck_common.py`
  copies the DATA git needs (HEAD, refs, packed-refs, shallow, the index and
  split-index files) into a fresh temporary directory, writes its own minimal
  config there, borrows the objects read-only through
  `objects/info/alternates`, and runs git with `GIT_DIR` / `GIT_WORK_TREE`
  pointing at it from an environment built from nothing (`env -i`, `PATH`
  only, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, the empty tree
  as attribute source, the r12 pins kept as a belt). The builder's worktree is
  added from that directory, so the reviewed repository gets no worktree
  registration either. The repository's config (and its include files),
  hooks, `info/attributes`, `info/exclude` and `config.worktree` are never
  opened by git. The one write is `snapshot`: it writes its new objects into
  the reviewed repository's object store (`GIT_OBJECT_DIRECTORY`), as r12 did.
  Fail closed: an unknown repository extension (other than `objectFormat`,
  `worktreeConfig`, `preciousObjects`, `noop`) or a reftable repository stops
  the build. Test `tests/test_precheck_gate_git_isolation.sh`: a hostile
  fixture names a marker program for fsmonitor, smudge / clean / process
  filters (in `info/attributes` and tracked `.gitattributes`), textconv,
  `diff.external`, `gpg.program` with `log.showSignature` on signed commits,
  pager, credential helper (also in an include file), `core.sshCommand`,
  `core.alternateRefsCommand` and hooks; positive controls show plain git runs
  each (pager and alternateRefsCommand have no control: git pages only a tty,
  and alternateRefsCommand needs an alternate with refs); the builder on a
  commit and on a snapshot runs zero; three paired mutants re-open the hole
  and each runs at least one marker. RED on 901fa52: smudge, filter.process
  and gpg ran. Not covered: `tower_detector_run.py` (not part of the gate or
  the builder) still runs `git -C`.
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
