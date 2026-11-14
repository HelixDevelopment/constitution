# Independent review: fix227 vehicle (CON-234), round 10

| Field | Value |
|---|---|
| Reviewer | fresh independent reviewer subagent, Opus 5.5 (claude-opus-5-5). Effort could not be set or read on this dispatch path (§11.4.231(F.2)), so no effort level is claimed |
| Subject | bundle `fix227_r10.bundle`, sha256 `85ae835594936d15de2f7f1877ac42e858de155e2d4ec2316847034b9b172ca7`, head `3fe216bdcacf0f3a88d2cea2cca82a0cf1b80908` (`vehicle/fix227-r9`), one new commit on `9d2171e4`, range `02c10935..HEAD` (23 commits) |
| Work tree | my own scratch clones under `rev_fix227_r10.G0OC/` (`base`, `r1` = head, `mut` = mutant clone). I did not touch the live checkout and pushed nothing |
| Hermeticity | every suite ran under `env -i` with a curated PATH (`hbin`: no gh, glab, llmctl or claude-providers), a fake HOME and a fake git identity, `nice -n 10`, inside `systemd-run --user --scope -p TasksMax=3000`. The leak probes used only fabricated `ZZFAKE-*` values and a scratch sshd on 127.0.0.1 |
| Verdict | **NO-GO** |

## 1. Verdict and why

**NO-GO.** The round-10 fix for R9-1 (do not let `RELEASE_ENV_KEEP` pass a name that ssh sends with `SendEnv`) still has
off-host leak paths. **Thirteen configurations each sent an opted-in canary value to a real sshd, measured LIVE**
with the real `tag_and_release.sh --dry-run` at `3fe216bd` (R10-1). Seven of them are not in the round's own
honest-limits list. A second probe shows the value reaches a server that does not accept the name, so any forge's
sshd receives it.

The suites cannot catch this. **13 of my 22 reviewer mutants survived all six suites** (R10-2). Each survivor
weakens the new fail-closed code, and each is shown non-equivalent: at library level it exports a name that the
unmutated code refuses. Among them is the removal of the whole `./.git/config` check (R06).

This is a credential-leak surface. §11.4.276(G.2) excludes security surfaces from the minor class, so none of these
findings can be a follow-up.

The rest of the round-10 claims are reproduced:
- **Counts.** Every count matches, run twice; the verdict sets are identical.
- **RED.** The RED is 321/44, the same as committed.
- **Checks.** shellcheck rc 0, verify-manifest OK, ledger 394/394.
- **Mutant set.** The author's 245 mutants apply to the committed tree (STALE_ONLY).
- **Trailers.** All 23 commits carry a real `Roadmap-Item:` trailer.

## 2. Counts measured in this session (§11.4.5)

| Suite | Run 1 | Run 2 | Committed green | Note |
|---|---|---|---|---|
| test_redact_cut.sh | 365/0 | 365/0 | 365/0 | verdict-set sha256 identical in both runs |
| test_channel_census.sh | 39/0 | 39/0 | 39/0 | identical |
| test_derive_release_facts.sh | 104/0 | 104/0 | 104/0 | identical once the per-run ENVCENSUS record counts are removed |
| test_publish_gitea.sh | 146/0 | 146/0 | 146/0 | identical |
| test_tag_and_release.sh | 300/0 | 300/0 | 300/0 | runs 3 and 4, with a fake git identity in the hermetic HOME. Without one: 241/59 twice (nit N-3) |
| test_render_release_entry.sh | 19/0 | 19/0 | 19/0 | 1 honest SKIP (RRE_FACTS unset), as committed |
| RED: round-10 tests, `RC_LIB` = 9d2171e4 library | 321/44 | | 321/44 | matches `red_redact_cut.txt` |
| shellcheck 0.11.0 `-S warning`, the 13 changed `.sh` files of the range | rc 0 | | rc 0 | |
| `run_full_suite.sh --verify-manifest` | MANIFEST-OK, total=908 | | same | |
| `cm_gate_ledger_ratchet.sh` | unimplemented=394 baseline=394 fails=0 | | same | |
| mutation harness `STALE_ONLY=1` on the committed tree | 245 "applies", stale=0 | | | the full harness (9786 s) was not re-run; see UNCONFIRMED |
| Roadmap-Item trailers in `02c10935..HEAD` | 23 of 23 commits carry one; HEAD: `Roadmap-Item: CON-234` (a real id, not a placeholder) | | | |

## 3. Findings

### R10-1: `_rc_env_sendenv` fails open, so an opted-in value leaves the host (important, security surface; not minor-class)

**Where.** The R9-1 refusal relies on `_rc_env_sendenv` and `_rc_env_sendenv_read`
(`scripts/release/redact_cut.sh:186-240`). They decide which names ssh will send by re-parsing ssh's configuration
language, git's configuration and the shell word-splitting of `GIT_SSH_COMMAND` in bash. Whatever they cannot parse is
treated as absent, because a file that cannot be read is skipped.

**The false premise.** The skip rule is justified in the doc comment (`:176-177`): "A file that cannot be read is
skipped (ssh, as the same user, cannot read it either)." That premise is false for every case below. ssh **can**
read the file; only the reader cannot, because the shell expands it, the flag is clustered, or the text is quoted.
For `-F`, ssh aborts if it cannot open the file, so a connection that happened proves that ssh read it. This also
contradicts `round10/threat_model.md` §2: "Every uncertainty it can detect turns into a refusal".

**Repro (LIVE, §11.4.289 class LIVE).** The setup:
- Probe scripts: `rev_fix227_r10.G0OC/probe/leak_probe{,2,3,4,5,6}.sh REPO OUT`, outputs in `out/leak_probe*.txt`.
- Server: a scratch sshd on 127.0.0.1 with its own host key, `AcceptEnv ... ZZ*` and LogLevel DEBUG3.
- Client: the real OpenSSH_10.2p1 client and the real `tag_and_release.sh --dry-run` of `3fe216bd`.
- Run: `RELEASE_ENV_KEEP="KEEPME ZZLEAK..."`, each canary `ZZLEAKx=ZZFAKE-x-leak`.
- Evidence: a `debug2: Setting env 0: ZZLEAKx=ZZFAKE-x-leak` line in the sshd log, from the fetch step. The script
  then stops at its own CHANGELOG precondition, after the fetch.

| Case | How the SendEnv is reached | Canary at the server | In the author's limits list? |
|---|---|---|---|
| C1 | `GIT_SSH_COMMAND='ssh -F ~/c1.cfg'` (git runs it through the shell, which expands `~`) | **sent** | no |
| C2 | `GIT_SSH_COMMAND='ssh -F "$HOME"/c2.cfg'` | **sent** | no |
| C3 | `GIT_SSH_COMMAND='ssh -qF /abs/c3.cfg'` (clustered flags; ssh's getopt accepts them) | **sent** | no |
| C4w | `core.sshCommand = ssh -F … -o SendEnv=ZZLEAKD` in a **linked worktree**, where `./.git` is a file and `./.git/config` cannot be read. This is the same shape as **a submodule checkout**, which is how consumers vendor the constitution | **sent** | no (the threat model says this case fails closed) |
| C4s | the same `core.sshCommand`, in the main checkout, script run **from a subdirectory** (the script never changes directory) | **sent** | no |
| C5 | `Include "/a dir/inc5.conf"` (a quoted Include path with a blank) | **sent** | yes ("an Include path holding a blank") |
| C9 | `GIT_SSH=/abs/wrap.sh`, a wrapper that runs `ssh -F … -o SendEnv=ZZLEAKI "$@"` | **sent** | yes |
| C10 | `include.path` in `./.git/config` names a file holding `core.sshCommand … -o SendEnv=ZZLEAKJ` | **sent** | yes |
| C12 | `ProxyCommand ssh -F inner.cfg -o SendEnv=ZZLEAKG zzinner nc %h %p` (session-type jump host) | **sent** (to the jump host) | no |
| C13 | `ProxyCommand ssh -F innerH.cfg zzinner nc %h %p`, with `SendEnv ZZLEAKH` in innerH.cfg | **sent** (to the jump host) | no |
| C14 | `Send"Env" ZZLEAKG` (ssh's argv_split strips quotes inside a token; `ssh -G` prints `sendenv ZZQTWO`) | **sent** | no |
| C15 | `"SendEnv" ZZLEAKH` (a quoted keyword) | **sent** | no |
| C16 | `GIT_SSH_COMMAND="ssh -F '/abs/a dir/c9.cfg'"` (a quoted path with a blank) | **sent** | no |

**Controls.** Each probe carries a positive and a negative control (§11.4.273):
- **C6** (a separate absolute `-F` that the reader parses, `SendEnv ZZLEAKF`): **not sent**, because the name was refused.
- **C4m** (core.sshCommand with SendEnv in the main checkout, run from the root): **not sent**, because it fails
  closed.
- **C11** (a plain `-F` with no SendEnv): **not sent**.
- **Refuted hypothesis.** `ProxyCommand ssh … -W %h:%p` (C7, C8) sent nothing. `-W` opens a direct-tcpip channel,
  not a session, so the hypothesis does not apply.

**Server that refuses the name.** `leak_probe6.sh` runs an sshd whose AcceptEnv does not include `ZZ*`. Its log shows
`debug2: Ignoring env request ZZLEAKA: disallowed name` for C1. The client sent the env request anyway, and an RFC
4254 §6.4 "env" request carries the value, so the value reaches every remote sshd (GitHub, GitLab, Gitea), whatever
that server's AcceptEnv. I measured only that the request arrives; that the value travels inside it is a protocol
fact from RFC 4254, not something this probe captured.

**Library-level members (the real `rc_env_lockdown`, no network):**
- `"SendEnv" X` and `Send"Env" X` give BLIND=0 and the names are exported (`ssh -G` confirms that ssh reads both as
  SendEnv).
- `GIT_SSH_COMMAND` with `Send''Env` or `Send\Env`, `-F '${HOME}/x'`, or `-F '/a dir/x'` fails open.
- `core.sshCommand` read from a subdirectory: BLIND=0 at `/sub`, BLIND=1 at the root.

**By reading (UNCONFIRMED live):**
- An account that exists only in NSS (no `/etc/passwd` line, for example LDAP or SSSD) gets `ph=""`
  (`_rc_env_pwhome`, `:190`). ssh reads `pw_dir/.ssh/config`, so if HOME is not pw_dir that file is never read and
  nothing goes blind.
- `Include ~otheruser/…` is resolved as a relative name, so the file is skipped.

**Severity.** The rating is important, and it is a security finding:
- **The channel.** These are real credential leaks off the host. The value of a variable the operator opted in,
  meant for the tests, reaches a remote server.
- **The preconditions.** It needs the operator to opt in a name and to have an ssh or git configuration that sends
  it.
- **Why the preconditions do not lower it.** The round exists to make exactly that combination safe. The most common
  spellings (`~`, `$HOME`, `-qF`) defeat it, and so does the standard way consumers run the tooling (a submodule
  checkout, C4w).
- **No downgrade path.** §11.4.276(G.2) excludes security surfaces from the minor class, so this cannot be a
  follow-up.

**Class fix (the parser cannot be made complete; invert the default).** I recommend one of:
1. **Structural.** Never give `RELEASE_ENV_KEEP` extras to network children: git fetch/push/ls-remote, ssh, curl and
   any forge CLI. Strip the extras from the environment of every network leg. The tests need the extras only for the
   fake tools they inject.
2. **Fail closed on anything the reader cannot model:**
   - Shell metacharacters (`~ $ ' " \` and backtick) in `GIT_SSH_COMMAND` or `core.sshCommand`.
   - Any flag cluster containing `F`.
   - A `-F` file the reader cannot open (ssh would have aborted).
   - `GIT_SSH` set to anything other than a plain `ssh`.
   - Any git config that holds `sshcommand`, `include` or `includeif`.
   - `./.git` not a directory, or cwd not the top level: resolve `git rev-parse --git-common-dir --show-toplevel`
     or go blind.
   - A quote anywhere in an ssh config keyword or Include argument.
   - A `ProxyCommand`, `ProxyJump` with its own options, or `Match exec` line.
   - An empty passwd home.

   Option 1 closes the whole class. Option 2 closes the members known today.

### R10-2: reviewer mutants on the new fail-closed code survive every suite (important, security surface; §11.4.194(6)(d), §11.4.235(D))

**Survivors.** These mutants survived redact_cut 365/365 and the five other suites. Full rows are in §4:
- R01 attached `-Ffile`
- R02 Include depth
- R03 and R11 Include holding `%` or `$`
- R04 `~/` Include
- R05 a quoted `-F`
- R06 `./.git/config`
- R07 XDG git config
- R08 system git config
- R09 `set -f` in the nested reader
- R10 the kind of a relative Include in a `-F` file
- R13 a `:` in the locale codeset
- R20 the 64-byte locale cap

**Non-equivalence.** I proved each one non-equivalent by running the real `rc_env_lockdown` from both libraries on the
same input. In every case except R04 the mutant exports a canary that the unmutated library refuses. R04 is
non-equivalent by construction, but proving it needs a file under the real passwd home, which I did not write.

**Severity.** R01-R11 are important: they are untested fail-closed branches of a credential channel. R13 and R20 are
minor, but on the security surface, so they are not follow-up eligible.

Each surviving mutant removes or weakens a branch that the round-10 text says protects against a leak, and no test
fails. Under §11.4.235(D), a surviving reviewer mutant against this batch's own proving tests means the source is not
proven correct. Under §11.4.194(6)(d), each survivor is a finding. All of them must get a killing test before GO.

### R10-3: the round-10 security claims are false as written (minor, but on the security surface, so not follow-up eligible)

| Where | Claim | What is measured |
|---|---|---|
| `scripts/release/redact_cut.sh:176-177` | "A file that cannot be read is skipped (ssh, as the same user, cannot read it either)" | false for `-F` paths written with `~`, `$HOME`, quotes or clustered flags (C1, C2, C3, C16): ssh reads them |
| `round10/threat_model.md` §2 | "Every uncertainty it can detect turns into a refusal of every `RELEASE_ENV_KEEP` name (fail closed)" | the C4w, C4s, C9, C10, C14 and C15 conditions are all detectable (`.git` is a file, cwd is not the top level, `GIT_SSH` is set, a git config holds `include`, a keyword has a quote) and fail open |
| `round10/threat_model.md` §2 | "a `-F` file named inside `core.sshCommand` (it does see the word `sendenv` there and fails closed)" | false in a linked worktree or submodule (C4w), from a subdirectory (C4s), and through `include.path` (C10) |

These must be corrected in the same change as R10-1 (§11.4.6).

### R10-4: the credential-word list misses common secret names (minor, security surface)

`redact_cut.sh:248` refuses `TOK SECRET PASS PWD KEY CRED AUTH COOKIE SESSION JWT PROXY`. These names are kept. I
measured it: the real `rc_env_lockdown`, with fake values and all eight names in `RELEASE_ENV_KEEP`, exported every
one of them:
- `GITEA_PAT`, `NPM_PAT`
- `DATABASE_DSN` (a DSN usually carries a password)
- `SLACK_WEBHOOK` (a webhook URL with a secret path; `*_URL` is refused, but `*_WEBHOOK` is not)
- `X_PRIVATE`
- `CLIENT_CERT`
- `SIGNING_SALT`, `HMAC`, `OTP`

Today these reach same-user children only, unless R10-1 applies. Severity: minor; it is defence in depth.

### Nits

- **N-1.** The locale grammar (`:138`) admits a 32-character `[A-Za-z0-9-]` codeset and a 32-character `[a-z0-9]`
  modifier. So `en.<32 hex>@<8 hex>` (40 hex characters, 44 bytes, under the 64-byte cap) is kept and is sent off-host
  by the default `SendEnv LC_*`. Measured: `_rc_env_shape_ok LC_TIME` keeps it. Narrowing the codeset to a list of known codesets would close this. It is
  theoretical: no accidental credential has this shape.
- **N-2.** Under a client `SendEnv *` or `SendEnv GIT_*`, base-list values such as `GIT_SSH_COMMAND` (only the common
  checks: `sshpass -p …` passes), `PWD` and `DBUS_SESSION_BUS_ADDRESS` leave the host. This is not introduced by the
  round (ssh would send them without the tooling too), but the threat model does not state it.
- **N-3.** `tests/release/test_tag_and_release.sh` depends on an ambient git identity. In a hermetic HOME without
  `user.email` it fails 59/300 ("fatal: unable to auto-detect email address"), twice in a row. It should set
  `GIT_AUTHOR_*` and `GIT_COMMITTER_*`, or a local `user.*`, itself.
- **N-4.** `threat_model.md` §3 labels several rows "LIVE on the library". That is not one of the §11.4.289 classes.
  The rows drive the real `rc_env_lockdown` with prepared configuration files, which is LIVE code on fixture inputs,
  so say exactly that.

## 4. Reviewer mutant table (§11.4.194(6)(d))

**How they ran.** `mutants.py` applies each mutant by exact-once replacement in a separate clone at `3fe216bd`.
`run_mutants.sh` runs redact → channel → derive → publish → tag → render, stops at the first failing suite, and
restores the tree after each mutant; the clone was clean afterwards (0 changed files). The non-equivalence column comes
from the real `rc_env_lockdown` with an input built for the mutant, comparing how many canaries are exported
(unmutated, then mutant).

**Overlap with the author's set.** Mutants marked "≈ author X" overlap the author's own set. They act as controls
that prove the runner kills what it should. The other 15 are new.

| Id | Mutation | Result | First killing test, or semantic proof |
|---|---|---|---|
| R01 | the `-F?*` branch dropped (`-F/abs` attached form not read) | **SURVIVED** | canaries exported 1→2 (`GIT_SSH_COMMAND=ssh -F/abs/a.cfg`) |
| R02 | Include depth > 8 returns without setting BLIND | **SURVIVED** | 0→2 (an 11-level Include chain) |
| R03 | an Include holding `%` or `$` is skipped without BLIND | **SURVIVED** | 0→2 (`Include ${HOME}/inc3.conf`) |
| R04 | the `~/` Include base set to `/nonexistent` | **SURVIVED** | non-equivalent by construction (ssh expands `~` to pw_dir); not run, because it needs a file in the real home |
| R05 | a separate `-F` path: quotes not stripped | **SURVIVED** | 1→2 (`-F '/abs/b.cfg'`) |
| R06 | `./.git/config` dropped from the git config list | **SURVIVED** | 0→2 (repo-local `core.sshCommand ssh -o SendEnv=ZZM`) |
| R07 | `$XDG_CONFIG_HOME/git/config` dropped | **SURVIVED** | 0→2 |
| R08 | `$GIT_CONFIG_SYSTEM` / `/etc/gitconfig` dropped | **SURVIVED** | 0→2 |
| R09 | `set -f` dropped in `_rc_env_sendenv_read` (an included `SendEnv ZZ*` is glob-expanded against cwd, which holds `ZZfoo`) | **SURVIVED** | 0→2 |
| R10 | `-F` file kind `U:` → `S:` (its relative Include is resolved in `/etc/ssh`, not `~/.ssh`) | **SURVIVED** | 1→2 |
| R11 | the Include check tests only `%`, not `$` | **SURVIVED** | 0→2 |
| R12 | the publisher's `HELP=0` line removed | EQUIVALENT | probe: with `HELP=1` in the caller, the mutant prints `--tag is required`, not the help, because `rc_env_clean` drops the caller's HELP. Control: the unmutated `-h` prints the help |
| R13 | the locale codeset class admits `:` | **SURVIVED** | `_rc_env_shape_ok LANG en_US.ab:cd`: drop→keep |
| R14 | the passwd-home config line dropped (≈ author K14) | killed | `FAIL K10 R9-1 passwd home's ssh config not read` |
| R15 | a non-plain SendEnv argument no longer sets BLIND (≈ author K13) | killed | `FAIL K10 R9-1 fail closed (GIT_SSH_COMMAND ssh -F …)` |
| R16 | the `*sendenv*` check of GIT_SSH_COMMAND removed (≈ K11) | killed | `FAIL K10 R9-1 fail closed (… -o SendEnv=ZZSENDF10)` |
| R17 | descriptors 10-19 not closed | killed | `FAIL K10 R9-4 descriptors reach a child: childfds=10 … 19` |
| R18 | PROXY not a credential word (≈ CW10) | killed | `FAIL K10 R9-4 … passes on: ZW_PROXY` |
| R19 | only the first LANGUAGE element checked (≈ L3) | killed | `FAIL K8 N1 class table` |
| R20 | the locale length cap 64 → 4096 | **SURVIVED** | a 69-byte `en_US.<32a>@<30b>`: drop→keep |
| R21 | COLORTERM and NO_COLOR dropped from the static class (≈ K3/K4) | killed | `FAIL K10 R9-1 static class … COLORTERM` |
| R22 | git config files no longer scanned for `sendenv` (≈ K12) | killed | `FAIL K10 R9-1 fail closed (GIT_CONFIG_GLOBAL …)` |

**Totals.** Of 22 mutants: 8 killed, 13 survived (all non-equivalent), 1 equivalent with probe evidence.

## 5. Evidence-class check (§11.4.289)

- **sshd probe.** The author's sshd probe is correctly LIVE: a real sshd and the real client.
- **Static-class case.** The UNIT stub case is correctly UNIT.
- **Mutation harness.** It is correctly gate-logic.
- **"LIVE on the library" rows.** See N-4.
- **Counts.** No row claims more than its class allows. The round's PASS counts are real, but they do not cover the
  R10-1 configurations.

## 6. UNCONFIRMED

- That the committed tree is byte-identical to the "round-10 working tree on 9d2171e4" the harness ran on. What I
  measured is consistent with it: STALE_ONLY shows all 245 author mutants apply exactly once to the committed tree,
  and every suite count matches the committed green files. The full 9786 s harness was not re-run.
- The NSS-only-account path and `Include ~user/`: by reading only.
- Whether a real forge (GitHub, GitLab, Gitea) logs or keeps the value of a refused env request. Measured: a stock
  sshd receives the request (probe6). Not measured: what a forge does with it.
- The `"SendEnv"` and `Send"Env"` keyword forms on OpenSSH versions other than 10.2p1.

## 7. Artefacts (all under `rev_fix227_r10.G0OC/`)

- **Suite runs.**
  - `out/run1/`, `out/run2/`: six suites. The tag suite fails here for lack of an identity.
  - `out/tag_run1.txt`, `out/tag_run2.txt`: the tag suite with the identity.
  - `out/red_r9lib.txt`: the RED re-run.
- **Leak probes.** `out/leak_probe.txt`, `leak_probe2.txt` to `leak_probe6.txt`; scripts in `probe/`.
- **Checks.** `out/stale_only.txt`, `out/verify_manifest.txt`, `out/ledger.txt`.
- **Mutants.**
  - `mutants.py`: 22 mutants, exact-once replacement.
  - `run_mutants.sh`: the runner.
  - `out/mut/table.txt` and `out/mut/<id>.<suite>.txt`: the results.
  - `tmp/semdiff.*/`: the inputs for the non-equivalence checks, with per-mutant library copies under `m/<id>/`.
