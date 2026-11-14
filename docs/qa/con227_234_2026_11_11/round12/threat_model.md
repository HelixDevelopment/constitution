# CON-234 class, round 12: the network-spawn gate becomes default-deny by syntax

| Field | Value |
|---|---|
| Round | 12, past `R_max` under the standing operator decision of 2026-11-11 (continue until GO); fresh fixer instance |
| Review answered | the round-11 review (NO-GO; F1 IMPORTANT, F2 minor, F3 nit), reviewer scratch file `review_fix227_r11.md` |
| Base | `fed933c0` (round 11) |
| Status | PROVISIONAL (§11.4.290): the independent round-12 review is owed |
| Evidence class | gate logic and UNIT/fixture (§11.4.289), plus the LIVE loopback sshd probe of round 11, re-run |

*Correction (2026-11-13, round 13, F3 of the round-12 review):* the round-12 gate was not default-deny. Its parser read constructs it did not model without an error (here-document line joining, here-documents across `$(`, process substitution inside `[[ ]]`), and its rules for builtins, local programs and state were deny-lists: 32 reviewer fixtures in K2, K3, K4, K6 and K7 started a network program and passed it, and 8 of the reviewer's 11 narrowing mutants survived every suite (the round-12 review, F1 and F2). The message `unclassified command (default deny)` meant only that a command name outside the closed name lists is a finding. Round 13 replaces the gate with a byte pin of the reviewed scripts and a positive-shape analyser (`../round13/README.md`); this file is kept as it was, with this note. The title, section 2 ("A construct it does not model is a parse error", rule 5, "a finding in every form", "in any arithmetic context") and the limit "A construct outside it is a parse error" in section 4 are not true of the round-12 gate.

## 1. What the round-11 review found, and the round-12 answer

| Id | Finding | Answer | Evidence |
|---|---|---|---|
| F1 | `netgate` was not default-deny. It kept only the command words `shutil.which()` found on the checking host and found command positions with a regular expression, so a quoted, escaped, path or redirection-prefixed command word, a trap string, `coproc`, `alias`, `command -p` and every program absent on the host passed; RM30b survived every suite, RM31 and RM32 passed the gate and the lint (only the tag suite's runtime census caught them), RM34 passed the tag suite | the gate is replaced by a recursive-descent bash parser and a classifier that decide by syntax alone, with no lookup on the host (section 2); the census lint uses the same parser; the class inventory (`class_inventory.md`) has 9 classes and 127 must-find controls plus 11 must-pass controls; case C53 runs the gate in the tag, derive and publish suites, so an added network line dies in the suite of the script it is added to | `red_r11_netgate*.txt`, `green_r12_netgate*.txt`, part 2c of the channel suite, the mutant tables |
| F1 (record) | the round-11 README (lines 37-38 at `fed933c0`) and threat model (lines 16 and 53 at `fed933c0`) call the round-11 gate default-deny | dated correction notes in both round-11 files; the fed933c0 commit message has the same overstatement and is corrected in `README.md` section 6 (a commit message is never rewritten, §11.4.113) | `../round11/README.md`, `../round11/threat_model.md` |
| F2 | RM20 survived: a locale modifier not on the closed list was not tested | K9 R12 F2 in the redact suite: `en_US.UTF-8@zztoken11` and a 32-character lower-case modifier must be dropped; RM20 is adopted with the pattern `R12 F2` | redact suite runs, RM20 in the mutant table |
| F3 | the recorder's "private file" is per process, not private by mode | the wording is corrected (`env_census.py`, the channel suite's recorder comment, the round-11 files); no mode change: the logs hold fake canaries only | the same files |
| harness | the round-11 full mutation run had no summary | the partial record (186 lines, stopped by this fixer because the round-11 code is superseded) is kept as `r11_harness_partial.txt`; the standing harness is re-run on the round-12 commit (README section 5) | `r11_harness_partial.txt` |

## 2. The structural change: a parser, default deny

`tests/release/channel_census.py`, class `Parser` reads the four release scripts as bash, recursively: every simple
command in every list, pipeline, compound command, function body, `$(...)`, backtick, `<(...)`, `>(...)`, heredoc
body, here-string, arithmetic context, `case`, `select`, `until`, `coproc` and `trap` string. A construct it does not
model is a parse error, and a parse error is a finding (the gate refuses what it cannot read).

Class `Gate` then classifies every command word, in this order, and the first rule that applies decides:

1. `rc_net` (the library's network wrapper) and the trusted wrappers `nt` and `net` (trusted only when their bodies
   match the expected form; `TRUST_CAND`, `GATE_WRAPPERS`).
2. A shell function of the script (its body is classified where it is defined).
3. A builtin. Builtins with rules: `command`, `builtin` and `exec` resolve the program they run; `trap` strings are
   re-parsed; `BUILTIN_DENY` refuses `alias`, `enable`, `complete`, `compopt`, `fc`, `bind`, `history`. These are
   findings: `eval` outside the dynamic sites of `DYN_OK`, `source` of a file the gate does not read, `hash` other
   than `hash -r`, `mapfile`/`readarray -C`, `compgen -C/-F/-W/-X`, `set`/`shopt` that turn on xtrace, verbose,
   posix or extdebug, `unset -f`, `declare -n`, and the other forms in `class_inventory.md` K3.
4. An external: a network program (`NETCMDS`) only through `rc_net`, `nt` or `net`; a wrapper (`EXECWRAP`) only
   through `ALLOW_EXEC`; `LOCAL_SIMPLE`; `LOCAL_PROG` (awk, sed, sort, sqlite3 with `-safe`) only when its program
   text and options pass a checker.
5. Anything else: `unclassified command (default deny)`.

A literal command word must match `CMDNAME_RE` after quote removal; a path, an expansion or any other spelling is
refused, except at the dynamic sites listed in `DYN_OK` (`rc_net`, `_rc_env_closefds`, `_rc_env_restore`, all in
the library). An assignment to a name of `DANGER_NAMES` (`PATH`, `BASH_ENV`, `BASH_CMDS`, `LD_*` and the others) is
a finding in every form, and a command substitution in any arithmetic context is a finding (`SUBST_RE`).

Every site the gate accepts carries one class of a closed set: `network-through-rc_net`, `network-through-nt`,
`network-through-net`, `interpreter-allow-listed`, `local`, `local-checked-awk`, `local-checked-sed`,
`local-checked-sort`, `local-checked-sqlite3`; anything else is `FINDING`. The real scripts: 128 sites, 0 findings,
51 network (`spawn_sites.md`).

**Host independence.** Nothing in the gate or the lint reads `PATH` or the file system beyond the scripts. Part 2c
of the channel suite runs all 138 controls with `PATH=/nonexistent` and checks that the SITE census and the lint
give the same result with the normal PATH and with an empty one. On the round-11 gate the same 57 RED cases gave 30
unexpected results with the normal PATH and 48 with an empty PATH, including both control needles
(`red_r11_netgate_emptypath.txt`).

## 3. Answers to the class question (§11.4.276(C))

`class_inventory.md` lists every class, its members and the rule that refuses them. The round-11 reviewer's 50
fixtures are all members (`CTRL_*`, G01 to G45, G05b and G05c; three of them must pass). The round-12 fixer added
80 bypass members (CI01 to CI80) and 8 golden-FALSE members (CP01 to CP08), one or more per syntax form the parser
models. Total: 138 controls, 127 that must be a finding and 11 that must pass.

## 4. Honest limits (§11.4.6)

- **The gate reads text.** It decides what the four release scripts say, not what a program they start does. A
  local program the gate allows (`LOCAL_SIMPLE`, a checked awk, sed, sort or sqlite3 program) that opens a network
  connection by itself, a git configuration of the caller (`core.sshCommand`, hooks, `url.*.insteadOf`) or a
  library that `LD_*` would load from the caller's environment is outside what it can see. The runtime census (K11,
  the second layer) checks the environment each child actually gets.
- **The parser models a subset of bash.** A construct outside it is a parse error and therefore a finding (fail
  closed). A construct the parser reads differently from bash without an error would be a gap; the controls are
  the evidence that the modelled forms are read as bash reads them, and they are a finite set (§11.4.118), not a
  proof for every form.
- **The checkers of `LOCAL_PROG` read program text.** They refuse the known ways awk, sed, sort and sqlite3 run
  commands (K4 in the inventory) and unknown options. A way to run a command that a future awk, sed, sort or
  sqlite3 adds, written in a form the checker does not refuse today, would not be seen.
- **N-2 of round 11 stays.** A value on the network allow-list reaches the network child as it is.
- **The sshd probe covers 18 configurations** on one host (OpenSSH 10.2p1); it shows the mechanism, it is not a proof
  for every configuration.

## 5. Evidence classes (§11.4.289)

| Evidence | Class | What it shows |
|---|---|---|
| `sshd_probe_green_round12.txt` | LIVE | the round-11 probe, re-run on this tree: two throwaway sshd on 127.0.0.1, 18 configurations each, 36 CLEAN, 0 LEAK, 0 BLIND |
| `suites_run1.tsv`, `suites_run2.tsv` | UNIT/fixture | the six suites, twice, with identical results |
| `red_r11_*.txt`, `green_r12_*.txt` | gate logic | the gate on the reviewer's fixtures and added-line mutants, RED on the round-11 gate, GREEN on round 12 |
| `mutants_targeted_r12.tsv`, `mutants.md` | gate logic | the 55 mutants added or re-applied this round, run one by one: 55 killed by their property; the standing run of all 316 is PENDING (README section 5) |
