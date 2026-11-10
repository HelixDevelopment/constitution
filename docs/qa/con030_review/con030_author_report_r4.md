# CON-030 round 4: author report (structural round, review r3 H1 to H6)

| Field | Value |
|---|---|
| Item | CON-030 (parent of CON-070, CON-108, CON-109) |
| Round | 4, structural (section 11.4.276(E)(3)), fresh fixer instance |
| Base | origin main bdc3ac43, merged with the round-3 bundle head 34f62dbf (merge adfd96fa) |
| Commits | 87cd467e (engine, tests, guide, wrapper header), 6a645831 (tracker); this report and the widened class sweep were left uncommitted at the end of round 4 and were committed at the start of round 5 |
| Author | Claude Opus 5.5 subagent; effort not settable or readable on this dispatch path (section 11.4.231(F.2)) |

## What changed, by finding

- **H2 (lines split on NEL, LS, CR and others).** One reader, `gov_lines()`, now reads every governance file
  (manifest, known-failures table, excluded lock, operator roster, and the guide check). It splits on LF only,
  removes one trailing CR (CRLF is tolerated), and refuses any other C0/C1 control character, DEL, U+2028 or
  U+2029, naming it (`U+0085 (NEL)`). The old `crlf_line()` and every `splitlines()` on these files are gone.
  An AST lint in the self-test (`fsr_io_lint`) classifies every `open`/`splitlines`/`readline` call in the
  engine with an `# io: gov|write|not-gov` marker and fails on an unclassed call or on a governance reader
  that does not go through `gov_lines()`; its control needles prove it catches both.
- **H1 (joined unit id collided).** A unit's identity is the structured key `(path, tuple(args))` end to end:
  `plan()` stores it, `rec_key()`/`rec_matches()` compare records by it, and `plan()` refuses two units with
  one key and two different units with one display id (rc 3, both named). `id` is display only.
- **H3 (raw CR forged output lines).** Every output line goes through `esc_out()` (CR, LF, other control and
  line-separator characters escaped, TAB kept, surrogates as `\xNN`), in `out()`, `err()` and `summary.txt`;
  the census also refuses file names with such characters.
- **H4** is outside the class (coverage of ignored files inside submodules): registered as **CON-108**; the
  guide line 139 now says the ignored-file hash covers the root only.
- **H5 (tracker nits).** CON-070 re-added with `--created-by`; the engine has no parent flag, so the parent
  is stated in each description (recorded, not fixed here).
- **H6 / RW3 RW4 RW6.** RW3 (unreadable index) and RW6 (cross-mode resume) adopted with killing tests; RW4
  resolved by a direct `hrec()` test showing `None`, `b""` and no record give three distinct hashes.

## RED and GREEN (round-4 self-test against three engines)

The round-4 `tests/test_run_full_suite.sh` was run unchanged against three engines (FSR_RUNNER):

| Engine | Result | Log (sha256) |
|---|---|---|
| this head (87cd467e) | passed=343 failed=0, 0 SKIP | logs/selftest_r4tests_on_head.log (0c6a0215...) |
| round 3 (34f62dbf) | passed=315 failed=28 (every failure is a round-4 H1/H2/H3/lint check) | logs/selftest_r4tests_on_r3.log (c3f871e9...) |
| main (bdc3ac43) | passed=282 failed=61 | logs/selftest_r4tests_on_main.log (7c0fb57c...) |

Real tree: `--verify-manifest` output is byte-identical to main's (sha256 f9a3be00... for both); `--list`
and `--list --include-heavy` plans are byte-identical to main's (634c735a... and 5dacdad6...).

## Mutation runs

Two full runs of `tests/test_run_full_suite_mutations.sh` on 87cd467e, each in four shards with the
harness's unmutated baseline first (`ok   baseline: unmutated copy passes the self-test` in every shard):

| Run | Shards (mutants) | Killed | Survivors | Not applicable |
|---|---|---|---|---|
| 1 | 38 + 38 + 37 + 37 = 150 | 150 | 0 | 0 |
| 2 | 38 + 38 + 37 + 37 = 150 | 150 | 0 | 0 |

Shard logs (sha256, first 16 hex; the two runs produced byte-identical shard logs): shard_00 2e55ae3b62735a60,
shard_01 f786274130d62e1e, shard_02 226fa6d2ab26acce, shard_03 35f3401c7f9668dd. The 150 killed ids equal the
150 ids of the table (sha256 1d51ba806c554609 for the killed lists of both runs and for the table's id list, as
measured by the round-4 reviewer). Filled in during round 5 from the author's own logs (the round-4 hand-back was
lost in a host reboot, finding K7 of review r4); the round-4 reviewer added eight further mutants, four of which
survived (RX1, RX2, RX5, RX6), handled in round 5.

## Class inventory (section 11.4.276(C), section 11.4.273)

`docs/qa/con030_review/con030_class_sweep_r4.py` lists every site of the three bug shapes in the engine, with
a positive and a negative control needle per shape. Result on 87cd467e: `SITES A=33 B=12 C=61 controls=ok`
(logs/class_sweep_r4.txt). The sweep was widened once (text built and then `.encode()`d), which added three
B sites; all twelve B sites are classified:

| Line | Site | Class |
|---|---|---|
| 1668, 1802, 1822, 1966 | `"/fixtures/" in "/" + f` | benign: a containment test on a path, not an identity |
| 2048 | `excl_set_hash`: `"%s\t%s\n"` over (path, note hash) | benign: a path has no TAB or LF (TAB is the field separator, `gov_lines()` refuses LF-class), the note hash is hex, so the framing is injective |
| 2052 | `acc_chain`: `prev|ts|who|seth|rows` | benign: on lines the engine writes, no field holds `|` (hex, strftime, WHO_RE, digits), so the join is injective; the chain is unkeyed (tamper evidence against edits, not forgery), so a hand-made line gains nothing from the delimiter |
| 2330 | `tree_ident` subs hash over `git submodule status` split with `splitlines()` | class member at a not-gov site; no verdict effect: registered as CON-109 |
| 2345 | `tree_ident` dirty hash over `git status --porcelain` split with `splitlines()` | class member at a not-gov site (collides only with core.quotePath=false); no verdict effect, because a dirty start ends rc 10 and content changes are caught by `tree_state` and the quick identity: CON-109 |
| 2455 | `uid = path + " " + args` | display only since H1 (the key is the tuple) |
| 2558 | `CLASS_OF[_w[:-2] + "s"]` | benign: a constant table built at import |
| 3130, 3132 | `hrec()` framing (`tag-;`, `tag<len>:`) | the length framing itself (injective by construction) |

Shape A (readers): every governance read goes through `gov_lines()`; the remaining `splitlines()` calls read git
or child-process output and carry an `# io: not-gov` marker (two of them are the CON-109 sites). Shape C
(output): `out()`/`err()`/`summary.txt` escape; the other writes (manifest, lock, guide, logs, results)
receive only inputs already refused or escaped upstream (census names, WHO_RE ids, JSON records).

## Honest limits

- The lint and the sweep see the engine only (`scripts/full_suite/run_full_suite.py`); the wrapper and the
  other tools are CON-070's scope.
- CON-109's "no verdict effect" is reasoned from the code, not measured.
- The parent link of CON-070/CON-108/CON-109 is prose, because the engine has no parent flag (H5).
