# CON-234 class, round 13: the network-spawn gate as a byte pin plus a positive-shape analyser

| Field | Value |
|---|---|
| Round | 13, past `R_max` under the standing operator decision of 2026-11-11 (continue until GO; each round past 5 structural, with a fresh fixer and a fresh reviewer) |
| Review answered | the round-12 review (NO-GO; F1 critical source-defect, F2 important test-instrumentation, F3 important process-doc; observations O1 to O3), reviewer scratch file `review_fix227_r12.md`, sha256 `18876cf4e1b27c29af188aaf8083e1cc66f604863332650e025367db9e12c2ac` |
| Base | `dd095a3f` (round 12) |
| Status | PROVISIONAL (§11.4.290): the independent round-13 review is owed |
| Evidence class | gate logic and UNIT/fixture (§11.4.289(C)(2)); the oracle runs real bash 5.3, gawk and sqlite3 in a sandbox where every network program is a local recorder; the loopback sshd probe of round 11 is the only LIVE item |

## 1. What is protected, and against what

**Goal.** The four release files (`scripts/release/redact_cut.sh`, `derive_release_facts.sh`, `tag_and_release.sh`,
`scripts/release_publish_gitea.sh`) start every network program through `rc_net`, whose child gets only the fixed
network allow-list of environment names, and no credential reaches a program by another channel.

**Failure model.** The realistic threat is an edit to a release file, by a person or an agent, that is careless or
that "fixes" a failing check: a new network call outside `rc_net`, a credential in an argument, a change of `PATH` or
another name that changes what a command runs, or a local program (awk, sed, sort, sqlite3) used to start a process.
A second threat is a change to the gate itself or to its table that makes the gate accept such an edit.

**Out of scope, stated.** A person with commit rights who changes the scripts, the pin, the gate and its tests
together and gets the change past review; a compromised `git`, `ssh`, `awk` or `sqlite3` binary on the host; the
caller's environment before `rc_env_clean` runs (the library clears it; what bash does with `PATH`, `CDPATH` or
`BASH_ENV` before that first line is the caller's); the network at the kernel level (section 4).

## 2. Why the structure changed

Round 11 used regular expressions, round 12 a parser whose decisions were deny-lists (`BUILTIN_SAFE` with rules for
14 of 43 builtins, text searches in awk and sqlite3 programs, an assignment check for enumerated forms only). Both
failed review on the same class: a deny-list over an open language misses members, and each review found more
(round 12: 32 oracle-confirmed bypasses). Under §11.4.250 and §11.4.276(E)(3) round 13 does not add list entries. It
changes what the gate decides:

| Layer | What it decides | What it proves | What it does not prove |
|---|---|---|---|
| 1. Byte pin (`tests/release/netgate_pin.tsv`, `netgate --pin`) | the bytes of every release file equal the reviewed bytes: file sha256 and line count (F), every line's normalised key and exact-byte sha16 (L), every invocation site with its class (S), every awk and sed program text (P), every name a script writes (N) | an unreviewed change to a release file is a finding, whatever it is (a trailing space included); this is the only layer that is default-deny in the literal sense | that the reviewed bytes are safe; that the reviewer read the pin-diff |
| 2. Positive-shape analyser (`Parser`, `Gate`) | every construct is inside the closed feature set the release files use, and every command is one of a closed set of shapes (section 3) | the pin cannot be regenerated over a file the analyser refuses (`pin-regen` refuses on any finding, on a name of `DANGER_NAMES` other than `IFS`, and on no invocation); a fixture outside the shapes is a finding with an empty PATH and with a normal PATH alike | that bash reads every accepted construct the way the parser reads it (the controls are a finite set, §11.4.118); anything that arrives as run-time data (section 5) |
| 3. Runtime recorders (`test_channel_census.sh` part 3, the C48/L2/29 cases of the suites) | every program a test run starts is recorded with its arguments and environment | on the paths the tests execute, no child outside the allow-list gets a credential or an unlisted name | anything on a path no test executes |

The pin is regenerated only by `channel_census.py pin-regen`; part 2d of the channel suite checks that the committed
table is exactly what `pin-regen` writes for the committed files (in either argument order, with an empty PATH), so
a hand edit of the table that `pin-regen` would not write fails. The reviewer of a regeneration reads
`channel_census.py pin-diff TABLE FILE...`, which prints the added and removed rows (line keys, sites, programs,
names) and never the script text; it exits 1 when there is a difference.

## 3. The positive shapes (layer 2)

The analyser accepts only what the release files use. Every rule below names what is allowed; everything else is a
finding. The class inventory (`class_inventory.md`) lists, per class, the controls found so far and the rule that
refuses them.

- **Constructs** (class `Parser`, `refuse()`): a closed feature set. Refused, among others: `&`, `|&`, `coproc`,
  `select`, `until`, `time`, the `function` keyword, `for ((`, backticks, process substitution in any position but a plain redirection operand, `<<` here-
  documents (the files use `<<<` only), `[[ ]]` outside the closed `cond_check` grammar, `${ cmd; }` and `${| cmd; }`
  (bash 5.3), `${!name}` outside `INDIRECT_OK`, parameter operators outside `PARAM_OPS` (so `${NAME:=}` and
  `${NAME=}`), arithmetic outside the `arith_check` grammar (no assignment operator, no `++`/`--`, no shift, no
  subscript, no substitution).
- **Command words**: a literal word matching `CMDNAME_RE` after quote removal; an expansion in command position only
  at the exact parsed words of `DYN_SITES` (ten sites, all in the library or the publisher, each with the reason its
  value is validated).
- **Builtins**: `BUILTIN_ALLOWED`, the 25 builtins the files use, each with its own option grammar in
  `Gate.builtin` (for example `command -v NAME` only, `read` with `-r` and `-d ARG` only, `printf` with no option (`--` is
  allowed) except at the one `DYN_SITES` entry, `set` with `+x -u -f +f` only, `shopt -s execfail` only, `trap` with a static
  action and EXIT, HUP, INT or TERM only, `unset -v NAME...` or `unset 'NAME[SUBSCRIPT]'` only). Every other builtin (`jobs`, `wait`, `let`, `getopts`,
  `mapfile`, `alias`, `hash`, `enable` and the rest) is a finding.
- **Interpreters and exec wrappers**: only when the parsed words, from the program word on, equal an entry of
  `ALLOW_EXEC` (three entries). Round 12 matched a substring of the line (R06, R07).
- **`source`**: only the exact raw words of `SOURCE_OK` (three entries). Round 12 matched a base name (R22).
- **Local programs**: `LOCAL_SIMPLE` (14 programs with no way to start a process); awk and sed only when the
  sha256 of the program text is on the P list of the pin and the checker passes; awk takes `-F` and `-v` only, with
  no `inet` and no escape in a value and no operand that is a `/inet` name or an assignment; `sort -V` only; sqlite3
  only with `-safe` as the first argument and the options of `SQLITE_OPTS` after it.
- **Network programs**: `NETCMDS` only through `rc_net` or a wrapper the gate trusts by reading its body (`nt`,
  `net`).
- **Functions**: defined once, at the top level, before every call that can reach them (a trap action counts as a
  call where the trap is set), with a name that is not a builtin, a reserved word, a network program, a wrapper or a
  local program.
- **Writes**: every name a script writes, in any form the parser records (assignment, prefix, `local`, `declare`,
  `read`, loop variable, `export`), goes through `check_writes`: a name of `DANGER_NAMES` or with the prefix `LD_` or
  `GCONV_` is a finding (`IFS` only with a value of `IFS_VALUES`), and a name off the N list of the pin is a finding.
- **Redirections**: operators of `REDIR_OK`, file descriptors of `REDIR_FDS`, no `{name}` form, no target under
  `/dev/` other than `/dev/null`.

## 4. The runtime layer: what was considered

A network namespace would let a test prove that no connection is opened at all. It is not available here: `unshare
-rn true` as this user on the reference host gives `unshare: write failed /proc/self/uid_map: Operation not
permitted` (measured 2026-11-13). The existing recorders (layer 3) stay; no claim is made about the kernel.

## 5. Residuals (§11.4.6)

- **Run-time data.** An awk or sed operand, a sqlite3 argument, a redirection target or a value of a `DYN_SITES` word
  that arrives as data is not seen by a reader of text. The scripts validate the dynamic values they use (the
  reasons are on the `DYN_SITES`, `INDIRECT_OK` and `A6_DATA` comments); the gate does not prove those validations.
- **The caller's environment** before `rc_env_clean`, and a `~/.sqliterc` of the caller (sqlite3 reads it unless
  `-init` is given; whether `-safe` also covers the dot-commands of that file was not tested: UNCONFIRMED).
- **A reviewer who does not read the pin-diff.** The pin makes a change visible; it cannot make anyone read it.
- **Bash semantics.** The analyser's model of bash is checked by 274 controls and the oracle runs, not by a proof.
  A construct the parser accepts and reads differently from bash would be a gap in layer 2; layer 1 still refuses
  it until a regeneration is reviewed.
- **Paths no test executes** are outside layer 3.
- **Script text in the output.** A netgate finding, a lint finding and `pin-diff` name a line by its census key (8
  hex digits of the sha256 of the normalised line), never by its text (O2 of the round-12 review), so a whole refused
  line is not copied into evidence. The message still names the offending word, option or construct, and for a few
  classes quotes at most 20 to 40 characters of it (a parameter expansion, a command word the gate cannot classify, an
  awk operand, a static value, an arithmetic operator), so a literal written inside that very construct would be
  printed in part. `netgate --sites` prints script, line, program, wrapper and class only. `channel_census.py list`
  still prints the first 120 characters of each line it lists (a maintenance view of the invocations and secret lines;
  the channel suite reads only its line, command and marker columns and prints none of its text), run on the four
  reviewed scripts, which hold no literal secret today (the lint's 13 secret lines are variable references); its
  output must not be pasted for a script that does.

## 6. Evidence classes (§11.4.289)

Gate-logic and UNIT/fixture: the controls, the oracle runs (real bash, gawk and sqlite3 against local recorders and
a loopback listener; no network), the six suites and the mutation harness. LIVE: the loopback sshd probe of round 11,
re-run on the round-13 tree (`README.md` section 7).
