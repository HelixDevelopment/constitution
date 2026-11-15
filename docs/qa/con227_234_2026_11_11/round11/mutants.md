# CON-234 round 11: mutant table

Where the results come from: `tests/release/test_release_tooling_mutations.sh`, the partial full run in
`mutations_full_partial.txt` (this directory; the run was still going at commit time, see §5). The harness applies each mutant to a scratch copy of the tree and runs
the suite that owns the mutated file:

- a `scripts/release/redact_cut.sh` mutant runs the redact suite first, then the tag suite;
- a `tests/release/channel_census.py` mutant runs `test_channel_census.sh`.

Line types:

- `mp NAME PATTERN`: the mutant must be killed BY a failure line that matches PATTERN, so it is killed by the
  property it names and not by an unrelated failure.
- `m`: the mutant must be killed by any failure.
- `meq`: the mutant is recorded as equivalent, and the reason is written on its line.

Evidence class (§11.4.289): this whole table is UNIT/fixture-class. It shows that the suites detect each
mutation. It does not show that a real ssh server receives nothing; only `sshd_probe_*.txt` shows that.

## 1. The reviewer's round-10 mutants R01-R22

The source is `review_fix227_r10.md` (this directory), the round-10 independent review.

- R01-R11, R14-R16 and R22 mutated the SendEnv reader. Round 11 removes that reader
  (`_rc_env_sendenv`, `_rc_env_sendenv_read`, `_rc_env_pwhome`; see `threat_model.md` §4), so their target code
  no longer exists and they are marked N/A.
- The leak class each N/A mutant opened is not left untested. The property ("no caller name reaches an ssh
  child") is now held by `rc_net`. It is killed by the NN mutants below and shown LIVE by the probe case named
  in the table.
- The table's last column is the verdict on the round-11 tree.

| Reviewer | What it changed (round 10) | Round 10 verdict | Round 11 | LIVE case of the same class |
|---|---|---|---|---|
| R01 | `-F?*` attached form not read | survived | N/A (reader removed) | C3 (`-qF /abs`) |
| R02 | Include depth > 8 not BLIND | survived | N/A | C5 (an Include in a `-F` file) |
| R03 | Include holding `%`/`$` skipped | survived | N/A | C5 |
| R04 | `~/` Include base | survived | N/A | C1 (`-F ~/x`) |
| R05 | quoted separate `-F` not stripped | survived | N/A | C16 (`-F '/a dir/x'`) |
| R06 | `./.git/config` dropped | survived | N/A | C4m, C4w, C4s (core.sshCommand) |
| R07 | XDG git config dropped | survived | N/A | C10 (include.path) |
| R08 | system git config dropped | survived | N/A | C10 |
| R09 | `set -f` in the nested reader | survived | N/A | C14, C15 (quoted keyword) |
| R10 | `-F` file kind U to S | survived | N/A | C1, C2 |
| R11 | Include check `%` only | survived | N/A | C5 |
| R12 | publisher `HELP=0` removed | equivalent | `meq RT12` (equivalent, same probe) | none |
| R13 | `:` in the locale codeset | survived | `mp RT13` on the closed codeset list | none (value grammar) |
| R14 | passwd-home config line dropped | killed | N/A | C1, C2 |
| R15 | non-plain SendEnv not BLIND | killed | N/A | C12, C13 |
| R16 | `*sendenv*` GIT_SSH_COMMAND check removed | killed | N/A | C12 |
| R17 | descriptors 10-19 not closed | killed | `mp RT17` | none |
| R18 | PROXY not a credential word | killed | `mp RT18` | none |
| R19 | only the first LANGUAGE element checked | killed | `mp RT19` | none |
| R20 | locale length cap 64 to 4096 | survived | `meq RT20` (see below) | none |
| R21 | COLORTERM / NO_COLOR dropped | killed | `mp RT21` | none |
| R22 | git config files not scanned | killed | N/A | C10 |

Why RT20 is equivalent: round 11 replaced the length-capped class with the closed grammar of
`_rc_env_locale_ok`. That grammar is a 2-3 letter language, an optional `_` plus a 2-letter or 3-digit territory, an
optional `.codeset` from a closed list (the longest is `ansi_x3.4-1968`, 14 bytes), and an optional
`@modifier` from a closed list (the longest is `ijekavianlatin`, 14 bytes). The longest accepted value is
therefore 3+1+3+1+14+1+14 = 37 bytes, so the 64-byte cap no longer selects anything. The round-10 69-byte
witness, `en_US.<32a>@<30b>`, is now refused by the grammar itself, as test "K11 R11" shows. The same test keeps
the longest accepted value, so the bound is checked from both sides. This is why RT20 is `meq` and not `mp`.

## 2. Round-10 mutants K7-K15, retired

They mutated the removed reader. Each is mapped to the round-11 mutant that kills the same property.

| Retired | What it guarded | Round 11 |
|---|---|---|
| K7 | run-time SendEnv patterns applied | NN2, NN3 (the allow-list itself; no pattern matching is needed) |
| K8 | an unreadable configuration refused | NN1, NN4 (nothing outside the list reaches the child, so nothing must be read) |
| K9 | Include lines followed | NN1 + LIVE C5 |
| K10 | the `-F` file of GIT_SSH_COMMAND read | NN1 + LIVE C1, C2, C3, C16 |
| K11 | SendEnv on the GIT_SSH_COMMAND line refused | NN1 + LIVE C12 |
| K12 | SendEnv in a git config file refused | NN1 + LIVE C10, C4w, C4s |
| K13 | an unreadable SendEnv pattern refused | NN4 |
| K14 | the passwd home's ssh config read | NN1 + LIVE C1 |
| K15 | `/etc/ssh/ssh_config` read | NN1 (the system config cannot add a name the child does not hold) |

## 3. Re-applied mutants

Their target line changed in round 11 and they are applied to the new line:

- T3, T4, T6, U7, X8, X9b, Y6 and Z6: each line now says `rc_net`.
- Z1: the lockdown list.
- B5 and RR10: the codeset check of the locale grammar.

B5 and RR10 survived on the first round-11 run (`targeted_first_run.txt`). The fix was three new values in the test
"R11 not a locale": a word, a `:` and a `/` after a known codeset. Both mutants are now `mp` and are killed by
that test.

## 4. The fixer's own mutants of the new mechanism

There are 24 own mutants: NN1-NN16, GN1-GN6, EC1 and EC2.

| Name | Mutation | Must be killed by |
|---|---|---|
| NN1 | `rc_net` runs the command with the caller's environment | K11 |
| NN2 | the network allow-list widened (LANG USER TERM KEEPME) | K11 |
| NN3 | no value check on the network list | K11 shape |
| NN4 | the second census no longer refuses | K11 export disabled |
| NN5 | the rc_env_clean precondition dropped | K11 not rebuilt / precondition |
| NN6 | the caller's IFS splits the name lists | K11 IFS |
| NN7 | a function named `export` replaces the builtin | K11 shadow |
| NN8 | `git tag -a` outside rc_net (tag script) | C48 netgate |
| NN9 | `nt` (the timeout helper) without rc_net | C48 netgate |
| NN10 | the publisher's curl outside rc_net | 29c |
| NN11 | the badge computer outside rc_net | C52 |
| NN12 | the codeset list widened to a 40-hex value (N-1) | R11 / N-1 |
| NN13 | a derive `git show` outside rc_net | L2 netgate |
| NN14 | the publisher's `git rev-list` outside rc_net | 29c |
| NN15 | exported functions reach the network child | K11 an exported function |
| NN16 | the `LC_ALL=C` constant dropped | K11 LC_ALL |
| GN1 | backticks not read as code | netgate |
| GN2 | git not a network command | netgate |
| GN3 | `nt` and `net` trusted without reading their definitions | netgate |
| GN4 | a command held in a variable not reported | netgate |
| GN5 | default deny dropped | netgate |
| GN6 | every interpreter and exec wrapper allowed | netgate |
| EC1 | the runtime recorder (`env_census.py`) restored to its round-10 form: the block appended to the shared log in several writes | R11 RACE |
| EC2 | the recorder writes its header line outside its private file | R11 RACE |

EC1 and EC2 guard the recorder fix of this round (`README.md` §4). The harness passes the mutated copy of
`env_census.py` to the redact suite as `ENV_CENSUS_PY`. The channel-census suite builds its recorder inside the
test file, so the harness has no seam to mutate it. Its RED and GREEN are recorded by hand:
`race/channel_recorder_red_green.txt` (91, then 0 misattributed).

NN15 at first was killed, but by an unrelated failure line. Its pattern was corrected to
`K11 an exported function`, and the mutant is now killed by that property.

## 5. Result of the full run

PENDING. See section 3 of `README.md`.

- At commit time 107 of 267 mutants had run: 104 killed, X12 equivalent, and V12 and X18 survived.
- V12 and X18 are now `meq`; the evidence is in `race/v12_x18_equivalence.txt`.
- The partial output is `mutations_full_partial.txt`.
- The final kill table follows as an addendum.
