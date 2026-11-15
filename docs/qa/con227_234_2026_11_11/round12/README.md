# CON-234 round 12 (structural): the network-spawn gate becomes default-deny by syntax

| Field | Value |
|---|---|
| Item | CON-234 (vehicle fix227, round 12) |
| Base | `fed933c0` (round 11, review NO-GO) |
| Date | 2026-11-13 |
| Status | PROVISIONAL (§11.4.290): the independent round-12 review is owed; the standing mutation run is PENDING (section 5) |
| Rounds | past `R_max`, under the standing operator decision of 2026-11-11 (continue until GO); fresh fixer instance |

*Correction (2026-11-13, round 13, F3 of the round-12 review):* the round-12 gate was not default-deny. Its parser read constructs it did not model without an error (here-document line joining, here-documents across `$(`, process substitution inside `[[ ]]`), and its rules for builtins, local programs and state were deny-lists: 32 reviewer fixtures in K2, K3, K4, K6 and K7 started a network program and passed it, and 8 of the reviewer's 11 narrowing mutants survived every suite (the round-12 review, F1 and F2). The message `unclassified command (default deny)` meant only that a command name outside the closed name lists is a finding. Round 13 replaces the gate with a byte pin of the reviewed scripts and a positive-shape analyser (`../round13/README.md`); this file is kept as it was, with this note. In particular, section 1 ("Every command in every context is classified", "a construct the parser does not model is a parse error") and the title are not true of the round-12 gate.

This round answers the round-11 review, a NO-GO. Its blocking finding F1: `channel_census.py netgate` was called
default-deny, but it kept only the command words `shutil.which()` found on the checking host and found command
positions with a regular expression. A quoted, escaped, path or redirection-prefixed command word, a trap string,
`coproc`, `alias`, `command -p` and every program absent on the checking host passed it. Of the reviewer's
added-line mutants, RM30b survived every suite; RM31 (`"git"`) and RM32 (a redirection before `git`) passed the gate
and the lint and were caught only by the runtime census of the tag suite on that host; RM34 (`/usr/bin/git`) passed
the tag suite. Under §11.4.276(E) the gate is replaced, not given more cases.

## 1. What changed

- **The network-spawn gate** (`tests/release/channel_census.py`, classes `Parser` and `Gate`) is a recursive-descent
  bash parser and a classifier that decide by syntax alone, with no lookup on the host. Every command in every
  context is classified; anything not on a closed list is `unclassified command (default deny)`; a construct the
  parser does not model is a parse error, and a parse error is a finding. Details: `threat_model.md` section 2.
- **Every accepted site has a class** from a closed set (`network-through-rc_net`, `-nt`, `-net`,
  `interpreter-allow-listed`, `local`, `local-checked-awk`, `-sed`, `-sort`, `-sqlite3`); `channel_census.py netgate
  --sites` prints them. The real scripts: 128 sites, 0 findings, 51 network (`spawn_sites.md`).
- **The census lint** reads the scripts with the same parser. A script it cannot read is a lint finding, and the
  lint gives the same result with an empty PATH (rounds 6 to 11 kept only the words `shutil.which()` found).
- **Two release-script changes the new gate asked for:** `derive_release_facts.sh` runs `sqlite3 -safe` (the
  dot-commands that run a program are refused; checked live on the host sqlite3 3.50.6: `.system` gives "cannot
  run .system in safe mode"); `redact_cut.sh` and the publisher use `unset -v` (a bare `unset NAME` removes a
  function when no variable has the name). `channels.tsv` follows the new argv keys.
- **138 control needles** (`tests/release/netgate_controls.jsonl`): the round-11 reviewer's 50 fixtures, byte for
  byte (checked against their SHA-256 sums), 80 bypass controls of the fixer (CI01-CI80) and 8 golden-FALSE controls
  (CP01-CP08). Part 2c of `tests/release/test_channel_census.sh` runs every one with `PATH=/nonexistent`.
- **Case C53** in the tag, derive and publish suites runs the gate over the suite's own copy of the script and the
  library, with an empty PATH, with a positive needle (the network count) and a control needle (`command -p git
  status` appended must be a finding). An added network line now dies in the suite of the script it is added to.
- **F2:** K9 R12 F2 in the redact suite: `en_US.UTF-8@zztoken11` and a 32-character lower-case modifier are dropped.
- **F3:** "private file" is corrected to "per-process file (`LOG.rec.PID`), created with the caller's umask" in
  `env_census.py`, the channel suite and the round-11 files. No mode change: the logs hold fake canaries only.
- **Round-11 record:** dated correction notes in `../round11/README.md` and `../round11/threat_model.md`.

## 2. RED and GREEN

Driver: `run_red.py` (this directory) runs the gate on the reviewer's 50 fixtures, on the four unmodified release
scripts (`REAL_SCRIPTS`, must pass) and on six added-line mutants of the tag script (RM30, RM30b, RM31, RM32, RM33,
RM34): 57 cases. Fixture directory: the `CTRL_*` and `G*` bodies of
`tests/release/netgate_controls.jsonl` (byte-identical to the reviewer's files).

| Run | Gate | PATH | Expected verdicts | Unexpected | File |
|---|---|---|---|---|---|
| RED | round 11 (`fed933c0`) | normal | 27 of 57 | 30 (26 fixtures and RM30, RM30b, RM31, RM32) | `red_r11_netgate.txt` |
| RED | round 11 | empty | 9 of 57 | 48 (both control needles among them: the result depended on the host) | `red_r11_netgate_emptypath.txt` |
| GREEN | round 12 | normal | 57 of 57 | 0 | `green_r12_netgate.txt` |
| GREEN | round 12 | empty | 57 of 57 | 0 | `green_r12_netgate_emptypath.txt` |

The lint, `red_r11_lint.txt`: on the round-11 lint a copy of the publisher ending in an unterminated quote gave rc 0
and 0 findings, and the lint with an empty PATH saw 17 invocations instead of 128 (107 findings). On round 12 the
copy is a finding (`parse error ... an unterminated double quote`) and both PATHs give 128 invocations and 0
findings.

RM34 (`/usr/bin/git`) was already a finding of the round-11 gate run directly (`red_r11_netgate.txt`); the reviewer
recorded it killed by the channel suite and passed by the tag suite (pass=307), which in `fed933c0` does not run the
gate (no `netgate` in it). Case C53 runs the gate in the tag, derive and publish suites.

## 3. Controls, host independence and the class inventory

- `class_inventory.md` (generated by `make_class_inventory.py`, which exits 1 when a control has no class or two):
  9 classes, 127 controls that must be a finding, 11 that must pass.
- Channel suite part 2c: 138 controls with an empty PATH, 127 findings with their expected reason and 11 passes; the
  SITE census is the same with the normal PATH and an empty one; golden-FALSE: 128 sites of the real scripts, every
  one in a class of the closed set, none a finding.
- The lint gives the same result with the normal PATH and an empty one (part 2 of the channel suite).
- A second look after the controls were fixed: `probe_extra.py` runs 53 more bodies (line continuation inside a
  command word, `time`, `source <(...)`, `. /dev/stdin`, `${!n}`, `g''it`, `$'git'`, `$"git"`, `nohup`, `stdbuf`,
  `{git,x}`, conditions of `while`/`until`, `PROMPT_COMMAND`, `SHELLOPTS`, `PS4`, `printf -v PATH`, `local PATH`,
  `sort --compress-program=`, `sed -f`, `awk -f`, a function named `git`, and others) with an empty PATH:
  48 findings (`probe_extra_r12.txt`). The 5 it passes start no program: `BASH_XTRACEFD=3` and `IFS=/` (xtrace
  itself and every expansion in command position are refused), `jq -n env` (jq cannot run a command),
  `sqlite3 -safe ... '.shell git fetch'` (sqlite refuses it: checked live, "cannot run .shell in safe mode"), and
  `export -f` of a function: the function's body is classified where it is defined, so what it runs in another
  process is what the gate already checked.
  *Correction (2026-11-13, round 13, F3 of the round-12 review):* "a function named `git`" was refused only
  when it was defined at the top level before its use; the same name defined after its use, in a subshell or in
  a dead branch (the reviewer's R03 to R05) passed the round-12 gate. In round 13 a function must be defined
  once, at the top level, before every call that can reach it (`../round13/class_inventory.md`, K10).

## 4. The six suites, twice

| Suite | Run 1 | Run 2 | Same verdict lines (digits normalised) |
|---|---|---|---|
| redact (`test_redact_cut.sh`) | rc 0, pass=435 fail=0 | rc 0, pass=435 fail=0 | yes |
| channel (`test_channel_census.sh`) | rc 0, pass=68 fail=0 | rc 0, pass=68 fail=0 | yes |
| derive (`test_derive_release_facts.sh`) | rc 0, pass=109 fail=0 | rc 0, pass=109 fail=0 | yes |
| publish (`test_publish_gitea.sh`) | rc 0, pass=167 fail=0 | rc 0, pass=167 fail=0 | yes |
| tag (`test_tag_and_release.sh`) | rc 0, pass=310 fail=0 | rc 0, pass=310 fail=0 | yes |
| render (`test_render_release_entry.sh`) | rc 0, pass=19 fail=0 | rc 0, pass=19 fail=0 | yes |

Outputs: `green_<suite>_run1.txt`, `green_<suite>_run2.txt`; summaries `suites_run1.tsv`, `suites_run2.tsv`. The last
column compares the sorted PASS/FAIL/SKIP lines of the two runs with every digit replaced (durations and process ids
differ between runs).

Each run is one sequential pass in a hermetic environment (`env -i`, a fixed PATH with a sqlite3 binary, a fresh
TMPDIR per suite), under `systemd-run --user --scope -p TasksMax=3000` and `nice -n 10`. The sqlite3 binary on
that PATH is the one of the host's Android SDK (3.50.6); the host has none on its standard PATH.

## 5. Mutants

The harness `tests/release/test_release_tooling_mutations.sh` has 316 mutant lines in round 12 (`STALE_ONLY=1`: 316
apply, 0 stale). The 55 mutants added or re-applied this round were run one at a time with `--only NAME` on the
round-12 tree before the commit; each is an `mp` line, so it counts as killed only when its suite fails AND a FAIL
line matches the property it targets. Every table row, with the matching FAIL line, is in `mutants.md`; the raw
results are in `mutants_targeted_r12.tsv`. GN1 to GN3 started before the last edit of `channel_census.py` (a None
check in the assignment branch, unreachable for a parsed `NAME=` word, and `__doc__ or ""`); they were run again on
the final code, 3 of 3 killed by their property (`mutants_targeted_r12_rerun_gn.tsv`). Every other mutant, the six
suites, the RED/GREEN runs and the `STALE_ONLY` run used the final code.

| Group | Mutants | Killed by its property | Other result |
|---|---|---|---|
| Round-11 gate mutants, re-applied to the round-12 gate | GN1-GN6 | 6 of 6 | none |
| Own mutants of the round-12 fixer | NR1-NR30, NR32, NR33 (32) | 32 of 32 | none |
| Mutants of the round-11 reviewer, adopted verbatim | RM2, RM9, RM10, RM12, RM19, RM20, RM21, RM25-RM28, RM30, RM30b, RM31-RM34 (17) | 17 of 17 | none |

The four the review names as must-kill, with the layer that killed them:

| Mutant | Round 11 | Round 12 |
|---|---|---|
| RM30b (`command -p git fetch`, then `hash -r`) | survived every suite | tag suite, C53: `network command outside rc_net: tag_and_release.sh:196 git (via -)` |
| RM31 (`"git" fetch`) | passed the gate and the lint; only the tag suite's runtime census (C47/C48) on that host caught it | tag suite, C53: `command word the gate cannot classify (quoted or escaped)` |
| RM32 (a redirection before `git fetch`) | passed the gate and the lint; only the tag suite's runtime census (C47/C48) on that host caught it | tag suite, C53: `network command outside rc_net: tag_and_release.sh:196 git` |
| RM34 (`/usr/bin/git fetch`) | killed by the channel suite; passed the tag suite (pass=307) | tag suite, C53: `command word the gate cannot classify (a path)` |

Not adopted: RM1, RM3 and RM22. The reviewer's run of RM1 hung in C41 for its 1500 s budget, because the edited
fetch line loses the timeout of `nt`; its property (a git outside `rc_net`) is RM33's. The reviewer abandoned RM3 and
RM22 for the same reason and replaced them with RM30/RM30b and RM34.

**The standing run: PENDING.** The full harness (316 mutants, `-j 1`) is started on this commit right after it is
made, as a transient systemd user service (`TasksMax=3000`, `nice -n 10`, `env -i`), because at the host's load it
takes hours. Its output and a summary file that a watcher keeps current (`RUNNING ...` every 60 s, then `DONE`, the
`RESULT` line and every FAIL and SKIP line) are written outside the repository, in the fixer's scratch directory;
the paths are in the hand-back to the conductor. No kill table of the standing run is claimed here.

## 6. Correction of the round-11 commit message

The commit message of `fed933c0` is not rewritten (§11.4.113); it is corrected here, dated 2026-11-13:

- "netgate (tests/release/channel_census.py). A default-deny static gate over the spawn sites" overstates it. The
  round-11 gate kept only the command words `shutil.which()` found on the checking host and found command positions
  with a regular expression, so it was neither default-deny nor independent of the host (F1 of the round-11
  review). Round 12 replaces it.
- "GREEN: 0, with a private file appended under flock": the file is per process (`LOG.rec.PID`), created with the
  caller's umask, not private by mode (F3).

## 7. Other checks

| Check | Result | File |
|---|---|---|
| LIVE loopback sshd probe (the round-11 probe, 18 configurations, two servers) | 36 cases CLEAN, 0 LEAK, 0 BLIND | `sshd_probe_green_round12.txt` |
| `shellcheck -S warning` on the four release scripts and six suites/harness | no output, rc 0 | - |
| pyright on `channel_census.py`, `env_census.py`, `make_spawn_sites.py` | 0 errors (the round-11 files had 2, both `sys.stderr.write(__doc__)`; fixed) | `pyright.txt` |
| `scripts/run_full_suite.sh --verify-manifest` | `MANIFEST-OK` | `verify_manifest.txt` |
| `scripts/gates/cm_gate_ledger_ratchet.sh` | unimplemented 394 = baseline 394, PASS | `gate_ledger_ratchet.txt` |
| harness `STALE_ONLY=1` | 316 mutants apply, 0 stale | `mutations_stale_only_round12.txt` |

## 8. UNCONFIRMED and open

- **The round-11 standing run** never finished. Its partial record (`r11_harness_partial.txt`: 8 controls PASS, 174
  killed, stopped by this fixer after 186 lines because the round-11 code is superseded) prints `FAIL V12 SURVIVED`
  and `FAIL X18 SURVIVED`, although in `fed933c0` both are `meq` lines. This is the cause the round-11 README states
  (lines 93-100 at `fed933c0`): the run was started before the commit turned the two lines into `meq`, and "The
  running harness still has the two lines as `m`, so its final summary will count them as survivors". It is not a
  new survivor. The round-12 standing run (section 5) runs both as `meq`.
- **The standing mutation run** of round 12 is PENDING at the time of the commit (section 5).
- The independent round-12 review is owed.

## 9. Files

`SHA256SUMS` lists every file of this directory except itself.
