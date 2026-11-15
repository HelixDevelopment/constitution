# CON-234 class, round 5 (structural): threat model, design and census

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output), with CON-227..233 touched; vehicle `vehicle/fix227` |
| Round | 5. Operator decision 2026-11-11: run until GO, every round past 5 is structural (§11.4.276(E)(3)); fresh fixer instance |
| Review answered | `scratchpad/review_fix227_r4.md` (round-4 head `1089054b`, NO-GO): J1..J7 and the surviving mutants V3, V4, V5, V8, V11, V12, V13 |
| Author | Claude Opus 5.5 subagent (fixer). Reasoning effort is not verifiable from inside the dispatch (§11.4.231(F.2)) |
| RED / GREEN | `red_*.txt` (the round-4 scripts with the round-5 tests) and `green_*.txt` (the round-5 scripts), beside this file |

## 1. Why the design changed again

Rounds 1 to 4 tried to make the PRINTED text of git and curl safe by redaction rules. Every round
found a new way the rules missed: round 4 still had J1 (the header rule ran first and removed the `@`
that the URL rule needs, so `https://user:SECab/cdtoken:LEAK@host` printed `LEAK`) and J2 (a
replacement that shrank the text moved unscanned bytes into the printed window). Adding a fifth rule
would be the heuristic tower of §11.4.250: many layers around one primitive defect. The primitive
defect is that the scripts print a message whose content they do not control. Round 5 removes it:

* the stderr of every **network** command is never printed, on any path. A failure prints the
  command's exit status and ONE word of a closed set (`rc_err_class`), or `timeout`;
* redaction (`rc_redact_cut`) stays only as **defence in depth** for text that is still printed:
  the stderr of local commands flushed at exit (git show, sqlite3, jq) and the publisher's own
  `release_publish_gitea: ` lines; J1 and J2 are fixed in it anyway (rule order R3, R4, R1, R2, R5,
  R6; every rule scans the whole line);
* every value that comes from the caller or from a server and is printed is validated against a
  strict shape first and is never echoed when it does not match.

## 2. Threat model (what can carry a secret)

| Source | Example | Can hold a credential because | Round-5 control |
|---|---|---|---|
| git fetch / push / ls-remote stderr | `fatal: unable to access 'https://u:PW@h/r'` | git 2.53 prints the configured URL verbatim, including a raw `/` or `@` in the password | never printed; `xcls` (class word); C21, C21c, C21e, C25, C25b, C28, C30, C31 |
| curl stderr (publisher) | `curl: (7) Failed to connect to 'https://u:PW@h'`, `> Authorization: token T` | curl echoes URLs and, verbosely, headers | never printed; class word; publisher cases 11, 16, 21 |
| gitea publisher stderr seen by the tag script | any line curl, git or jq wrote | the publisher runs curl and git | only lines starting `release_publish_gitea: ` (own text), redacted and cut (`own1`); C32, C32b, C32c |
| git trace switches of the caller | `GIT_TRACE_CURL=/tmp/x` | a trace holds headers and URLs | `rc_git_env` unsets every `GIT_TRACE*` and `GIT_CURL_VERBOSE`, sets `GIT_TRACE_REDACT=1`, `GIT_TERMINAL_PROMPT=0`, `GIT_TRACE2*=0`; C26, C34, publisher 19 |
| caller arguments | `--release gitea:r:https://u:PW@h:o/r`, a URL as a remote name, an unknown argument, `--sha`, `--base`, `--prev-tag`, a notes path | a caller can paste a URL with a token | strict shape checks; an invalid value is a usage error that does not echo it; C36, derive V1..V4, publisher 20 |
| server-controlled values | ls-remote object ids, the GitHub repository id, the HTTP status | a hostile or broken server can answer anything | printed only when they are object ids / numbers / three digits; C37, C37b, C38, publisher 15, 22 |
| the publisher token | `M3W_GITEA_TOKEN` | it is the credential | never in argv, never in a file (J4: `curl -K -` on stdin), never exported to a child (the holding variable is unset before the assignment; the round-4 `TOKEN=` kept the export attribute of a caller's `TOKEN`); publisher 17, 18, 19 |
| a hung network command | a server that never answers | not a leak, a stall (J5) | `timeout --foreground -k 10 RELEASE_NET_TIMEOUT` (default 600 s) on every network command, plus git's `http.lowSpeedLimit`; curl `-m 60 --connect-timeout 20`; C35, publisher 17, 21 |

## 3. Design (as built)

`scripts/release/redact_cut.sh` holds four functions: `rc_err_class` (an awk program that prints
string literals only, so no input byte can reach its output), `rc_safe_url` (scheme://host[:port] or
`<url not shown>`), `rc_git_env`, and `rc_redact_cut` (defence in depth). The tag script, the
publisher and the derive script source it and call `rc_git_env` first.

The tag script names every captured network output `x_*`; the static census case C40 asserts that
each use of an `x_*` variable is a capture, a classification (`xcls`), a decision (`case`), the
own-line filter (`own1`) or the SKIPPED-NO-TOKEN match, so a later edit that prints one fails the
suite.

## 4. Census (§11.4.273, control needles)

`census_print_sites.py` lists every print or write site of the four release scripts with the
expansions on the line; its positive needles (one known site per script) and a fabricated negative
needle are checked on every run. `census_red_head.txt` is the round-4 head (178 sites, 0 control
failures); `census_green.txt` is the round-5 tree (195 sites, 0 control failures). Classification of
every expansion that occurs on a print site of the round-5 tree:

| Class | Expansions | Why it is safe to print |
|---|---|---|
| this script's own constants and counters | `$FAILS $GAPS $DRY $n $_n $LOCAL_TAG_EXISTS $HAVE_TIMEOUT $SEG $RE_G* $NET_TIMEOUT` (validated digits) `$crc $frc $prc $mrc $trc $rc` (exit statuses) | no external text |
| validated caller values | `$TAG $SHA $r $rr $REMOTES $spec $target $BASE $PREV $REPO $BASE_URL $TOKEN_VAR` | each is checked against a strict charset before the first print (TAG, remotes, PREV: `[A-Za-z0-9][A-Za-z0-9._-]*`; SHA: hex; spec: the three spec regexes; BASE: no `:`; BASE_URL: scheme://host[:port] only) |
| git object ids and local git output | `$SHA $TAGOBJ $t $B $P $s` (via `oid`) `$TARGET $PREV_DATE` (validated date) | object ids are hex; `remote_state` passes every server id through `oid` |
| server values, validated | `$id` (digits), `$API_CODE` (3 digits), `$NEWID` (digits), `$ro` (via `oid`) | printed only after the check |
| the class word of a network failure | the output of `xcls` / `rc_err_class` | string literals of a closed set |
| the publisher's own lines | `$gmsg` (from `own1`) | this repository's own text, redacted and cut |
| repository data | `${FIRST}` (first CHANGELOG heading at SHA), tracker facts (`$VER $PROV $OVER $k $idl $due`) | committed content of the repository; a credential there is already published |
| paths of the run directory | `$RUNDIR $EXTERR $NOTES $W $DBDIR $DB $QFAIL` | created by `mktemp -d` under TMPDIR |
| deliberately never printed | `$x_fetch $x_push $x_main $x_tagpush $x_gitea $x_curl $_rpg_tok $NOTES_FILE $API_BODY` | network output, the token, a caller path, a server body: classified, matched, piped to jq or sent to curl only |

## 5. What is left (honest limits)

* The class word is chosen by fixed phrases. A password that happens to contain such a phrase can
  make the word wrong; it can never make the password print.
* The publisher's own lines are trusted text: if a future edit of the publisher prints a value it
  read from the network inside a `release_publish_gitea: ` line, only `rc_redact_cut` stands between
  it and the output. Its limits are listed in the helper header (a bare-word secret, a secret split
  over two lines, a parameter value with a raw blank), tracked as CON-271.
* `timeout(1)` absent: the tag script warns and runs the network commands unbounded (CON-275).
* SIGKILL of the tag script or the publisher leaves the run directory behind (no trap can run). After
  round 5 it holds no token (publisher case 18); it can hold the release notes and local stderr (CON-276).
* The threat model covers what the scripts print and write. It does not cover the token in the
  memory of the bash process, nor a caller who runs the scripts under `strace` or `bash -x` of their
  own (`set +x` at the top stops an inherited `-x` of the script itself).
* The census is a text inventory; its classification is by hand (this section). A new print site
  that holds an unvalidated value is caught only by review or by a test like C40.

## 6. Review items J1..J7 (where each is answered)

| Item | Answer |
|---|---|
| J1 rule order | `rc_redact_cut` runs R3 and R4 before R1; unit cases J1a-d; end to end C31 (real git 2.53, password `SECab/cdtoken:LEAKPARTRET`); mutant U12 puts R1 first again |
| J2 window shrink | no scan window, every rule scans the whole line, lines over 16384 bytes are not shown; unit cases J2a-d; mutants S15, V4 |
| J3 surviving mutants | V3, V4, V5, V8, V11, V12, V13 adopted with killing tests; the fixer adds U1..U17 (section 7) |
| J4 token file | `curl -K -` on stdin, no `curl.cfg`; publisher 17 (token on stdin, no file holds it during the run), 18 (none after SIGKILL); mutant U7 |
| J5 timeouts | `RELEASE_NET_TIMEOUT`, `nt`/`net`, curl timeouts; C35, publisher 17, 21; mutants U6, U14 |
| J6 Q12/S11 | the probe is now a committed script (`probe_trap_exit_status.py`, output `probe_trap_exit_status.txt`); round 4's "no observable difference" was wrong (143/129 vs killed by the signal); C39 and publisher 14 read the exact status; Q12 and S11 are ordinary mutants now |
| J7 unscoped pkill | `incident_j7.md` |

## 7. Mutation run

`mutations.txt` (the full harness, run once at the end with a private TMPDIR): killed=86 survived=0 equivalent=0
stale=0 control_failures=0. The 86 are the re-pointed earlier mutants, the reviewer's V3, V4, V5, V8, V11, V12, V13 (with V13b,
V13c), Q12 and S11 as ordinary mutants (J6), and the fixer's own U1..U17. A killed mutant shows only that a test notices
that edit; it does not prove the class closed (section 5).

Re-mint note (round 6, 2026-11-12): at the merge of main `66ad6efe` into vehicle/fix227 the vehicle ids CON-269 to CON-276 used in this file were re-minted as CON-300 to CON-307 in the same order (section 11.4.214; main uses CON-269 to CON-272 for other items). Map: `../round6/remint_map.txt`. The text above is kept as written.
