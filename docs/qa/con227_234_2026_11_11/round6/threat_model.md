# CON-234 class, round 6 (structural): channel census, threat model and design

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output), with CON-227..233 touched; vehicle `vehicle/fix227` |
| Round | 6. Operator decision 2026-11-11: run review rounds until GO; every round past 5 is structural (§11.4.276(E)(3)); fresh fixer instance; class-exhaustive (§11.4.276(C)) |
| Review answered | `scratchpad/review_fix227_r5.md` (round-5 head `9cd1539a`, NO-GO): K1..K4, N1 and the surviving mutants X6, X7, X9, X10, X12, X13, X14, X15, X17 |
| Author | Claude Opus 5.5 subagent (fixer). Reasoning effort is not verifiable from inside the dispatch (§11.4.231(F.2)) |
| RED / GREEN | `red_*.txt` (the round-5 scripts with the round-6 tests) and `green_*.txt` (the round-6 scripts), beside this file |
| Round-5 text | `../round5/threat_model.md` stays as the record of round 5; this file replaces its sections 2 and 5 |

## 1. Why the census is per channel now

Round 5 closed the PRINT class: no network stderr is printed, every printed value is validated.
The round-5 review found three defects outside that class, all on a channel the round-5 census did
not look at:

* K2 (time bound): `timeout --foreground` signals only its direct child; git's transport helpers
  are reparented, keep the capture pipe open and run on (60 to 300 s measured against a hanging
  server). The test double (`exec sleep 30`, no grandchild) could not show it.
* K1 (argv): a remote URL with a user name or password is in the argv of `git-remote-https`, so it
  is in `/proc/PID/cmdline`, readable by every local user, for as long as the helper runs.
* K3 (environment): `M3W_GITEA_TOKEN` (and any other exported caller variable) reached the
  environment of git, timeout, gh and glab, also readable in `/proc/PID/environ` of the owner's
  processes and inherited by every grandchild.

The round-5 census listed print sites only. The class-exhaustive question (§11.4.276(C)) is: through
which channels does data reach each external command, and which of them can carry a secret? So
round 6 lists every external command invocation once, with each channel:

| Channel | What reaches the child | Closed vocabulary (`tests/release/channels.tsv`) |
|---|---|---|
| argv | the command line, visible in `/proc/PID/cmdline` | `fixed`, `validated-data`, `url-validated`, `caller-path` |
| environment | the exported variables, visible in `/proc/PID/environ` (owner and root) | `lockdown` (allow-list only), `lockdown+token` (the publisher's bash only) |
| stdin | piped or redirected input | `none`, `pipe-local`, `pipe-network-text`, `token-config` (curl only), `file-local` |
| cwd | the repository the script runs in | every row: the caller's working directory (no row changes it) |
| files written | what the command creates or changes | `none`, `rundir`, `repo-refs`, `repo-tags`, `temp-create`, `temp-remove` |
| signals and time bound | how the command is ended | `local` (no network), `nt-timeout` (process-group timeout), `curl-m60`, `publisher` (the publisher's own bounds) |

## 2. The instrument and the lint

`tests/release/channel_census.py` finds the invocations statically (quotes blanked, command
substitutions kept as code, also nested inside double quotes; comments, case patterns, function
definitions and assignments are not invocations; the wrapper functions `nt` and `net` are followed
to the command they run). Each invocation is keyed by script, command and the first 8 hex digits of
sha256 of the normalised line, so a row goes stale when its line changes.

`channel_census.py lint` fails (exit 1) on: an invocation with no row; a row whose invocation is
gone; a value outside the vocabulary; a secret channel (`token-config`, `lockdown+token`) on any row
but the two allowed ones; a line naming a secret variable with no row; an external command before
`rc_env_lockdown`; a script that loads `redact_cut.sh` without calling it. An empty table, or no
invocation found, is BLIND (exit 2), never clean. Measured on the round-6 tree (`census_lint.txt`): 127 invocations, 123 rows, 11 secret lines, 0 findings.
On the round-5 scripts (`red_census_lint.txt`): 133 invocations, 21 findings.

The instrument was control-needled on a fixture with known invocations (both directions,
`test_channel_census.sh` part 1). The needles found five blind spots in the first version, each
fixed before the table was built: a double-quoted span holding `$(...)`, an assignment prefix that
swallowed `x="$(net ...)"`, a keyword (`then`, `do`) that consumed the next command, a case-pattern
rule that hid `$(uname)`, and a function definition counted twice. A sixth was found after the
table was built, while fixing K6 below: a command after a case-arm pattern (`-h|--help) sed ...`)
was not seen (`census_case_arm_red.txt`); `case_arms` fixes it and the fixture holds a needle for it.
The fixed instrument found two rows the first table lacked (the publisher's help `sed`, the derive
script's help `awk`).

`test_channel_census.sh` part 3 builds a recorder for every command the table names and every command
the instrument finds in the scripts (the recorder writes argv and environment, then runs the real
command) and runs the publisher against a local stub server: every command seen at run time is in the
table, and no argv and no environment of any child holds the token or a caller `*TOKEN*` variable.
The first version built recorders from the table only, so a command with no row ran unrecorded (the
K5 reproduction below showed it); it now takes the union.

The tag, publisher and derive suites each run the lint on the script under test (case L1, with a
control and a needle) and count only the order findings (`external command before rc_env_lockdown`,
`never calls rc_env_lockdown`), because those do not depend on the table rows. That makes the K5
class killable by the mutation harness, which runs these suites against mutated copies (Y22..Y25).

## 3. What the census found

* K5 (new, found by the runtime census, fixed): `dirname` in the library-load line of the three
  scripts, and `date` in the derive script, ran BEFORE `rc_env_lockdown`, so they got the caller's
  whole environment. Captured line of the recorder before the fix:
  `== dirname: E M3W_GITEA_TOKEN=CENSUSTOKEN123456`; `k5_evidence.txt` re-runs it on a copy of the
  round-6 publisher with only the old load line put back (census part 3: 4 FAIL; publisher L1: FAIL). Fix: the script directory is
  taken with a parameter expansion (`_rc_d`), `date` moved after the lockdown, and the lint refuses
  any external command before `rc_env_lockdown` (so does case L1 of each suite, mutants Y22..Y25).
* K6 (new, found while adopting mutant X11, fixed): `--token-var` may name a variable that is on the
  `rc_env_lockdown` allow-list (`GH_HOST`, say), which the lockdown leaves exported. The publisher
  read and unset it only after its first `grep` (and after `sed` for `--help`), so those children got
  the token (publisher case 28 failed with `== grep`). Fix: the token is read and the variable unset
  right after the argument loop, before any external command, `--token-var` is checked with a bash
  regex, and `--help` is printed after the unset. Case 28 records every command of the channel table.
  Mutants X11, Y19, Y20.
* X12 class: `RELEASE_ENV_KEEP` refused names with `TOKEN` but not `_rpg_tok` (the publisher's holding
  variable); it now refuses any name with `TOK` (redact case `K3 _rpg_tok`, mutant Y21).
* K1, K2, K3 as reviewed (section 4).
* No row other than the publisher's curl (token on stdin, `curl -K -`) and the tag script's
  publisher run (`bash`, the only child that gets `M3W_GITEA_TOKEN` exported) carries the token.

## 4. Threat model, round 6 (replaces round-5 section 2)

| Source or channel | Can carry a credential because | Round-6 control | Tests |
|---|---|---|---|
| network stderr (git, curl) | git and curl echo URLs and headers | never printed; class word (round 5) | C21..C31, publisher 11, 16, 21 |
| argv of git and its helpers (K1) | a remote URL with userinfo, or an `insteadOf` rewrite that adds it | the tag script reads every fetch and push URL (`git remote get-url --all`, `--push --all`, which apply `insteadOf`) and aborts before any network command when one has a password, or a user name on http(s) (`rc_url_has_userinfo`); the URL is not shown; `user@` on ssh / scp-style is accepted (no secret) | C42 (11 cases, 34 checks), redact `K1 *` (16 checks), mutants Y5, Y6, Y16, Y17 |
| environment of every child (K3, K5) | an exported caller variable | `rc_env_lockdown` un-exports every variable not on the allow-list (PATH, HOME, locale, terminal, TMPDIR, the git variables `rc_git_env` sets, and names in `RELEASE_ENV_KEEP` that do not look like a credential, `TOK` included) and every exported function; the publisher drops the variable `--token-var` names before its first external command (K6); the shell keeps the values; the token is exported only to the publisher's bash (`pub`) | C43, C44, publisher 25, 28, derive K3, redact K3, census part 3, L1 in three suites, mutants Y2..Y4, Y7..Y9, Y15, Y19..Y25, X11, X12b |
| base URL of the publisher (K4) | a base URL with userinfo | `rc_safe_url` is the check (`rc_safe_url "$BASE_URL"` must equal the URL); userinfo is refused | publisher base-URL cases, mutants Y13, Y18 |
| the time bound (K2) | a hung server keeps the helper running with the URL in its argv | `timeout -k 10 RELEASE_NET_TIMEOUT` without `--foreground`: timeout runs the command in its own process group and signals the whole group; git's low-speed limit stays | C41 (real git, real `git-remote-http(s)`, a hanging local listener), mutants Y1, U6, X7 |
| server-chosen ids (X6 class) | a server answers any text | one line of 1..20 digits (`[[ =~ ]]`), else refused without echo; GET and POST ids | publisher 23, 27, mutants X6, Y14 |
| xtrace (X14, X15) | an inherited `bash -x` / `SHELLOPTS=xtrace` | `set +x` is the first line of each script | publisher 24, C45, mutants X14, X15 |
| the run directory (X13) | a predictable name can be pre-created by another user | `mktemp -d` only | publisher 26, mutant X13 |
| awk backup redaction (N1) | text still printed (local stderr, the publisher's own lines) | three more shapes: `name%3D...`, `NAME = value`, JSON `"name": "value"`; unreachable for network output, which is never printed | redact N1a..f, mutants Y10..Y12 |

## 5. What is left (honest limits)

* The census is a static instrument. It does not see a command assembled at run time (`eval`,
  `"$cmd"`), a command run by another program (git runs its helpers, curl runs nothing), or a
  command in a file the scripts do not list. The runtime half (part 3) runs only the publisher;
  the tag script's children are covered at run time by C43 and C44 (real git under the probe), not
  by recorders for every row. Tracked as CON-308.
* `rc_env_lockdown` stops the export to children. It does not stop a process that reads the
  scripts' memory (`/proc/PID/mem` of the owner), nor the start environment of the scripts' own
  bash (`/proc/PID/environ` shows the environment the script was started with, so a caller who
  exports the token has already exposed it to their own other processes).
* Proxy variables (`http_proxy`, `HTTPS_PROXY`, `ALL_PROXY`, ...) are not on the allow-list and are refused in
  `RELEASE_ENV_KEEP` (a proxy URL can hold a password), so the scripts cannot reach a remote through a proxy
  (CON-309).
* A user name on ssh or scp-style URLs is accepted (it is not a secret). A password in an ssh
  config or a credential helper is outside the scripts.
* `timeout(1)` absent: the tag script warns and runs the network commands unbounded (CON-306, was
  CON-275; its round-5 premise that the bound held with `--foreground` was wrong, section 1).
* SIGKILL leaves the run directory (CON-307, was CON-276).
* The threat model covers what the scripts print, write and pass to children. It does not cover a
  caller who runs them under `strace`.

## 6. Review items (where each is answered)

| Item | Answer |
|---|---|
| K1 | `rc_url_has_userinfo`, tag-script URL check before any network command (section 4); C42 |
| K2 | `--foreground` dropped; C41 (real git against a hanging listener, http and https: exit 1, timeout class word, no git process left) |
| K3 | `rc_env_lockdown` and `pub`; C43, C44, publisher 25, derive K3 |
| K4 | `rc_safe_url` wired as the base-URL check |
| K5, K6 (found in round 6) | section 3 |
| N1 | three shapes added (section 4); the header of `redact_cut.sh` notes that network output never reaches it |
| X6, X7, X9, X10, X12, X13, X14, X15, X17 | adopted in the harness as `mp` lines (killed only by a FAIL line that names the property); X9 as X9b (the token in a file, curl keeps `-q` first); X11 killed by case 28 (K6); X12 recorded equivalent under the lockdown and the TOK refusal, X12b (lockdown removed too) is killed; the fixer's own mutants are Y1..Y25 |
| structural | this file, `channels.tsv`, `channel_census.py`, `test_channel_census.sh` |

## 7. Mutation run

See `mutations.txt` (the full harness, run once at the end with a private TMPDIR).
