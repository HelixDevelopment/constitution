# Security hardening scripts - branch protection, Actions inventory, history secret scan

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T22:00:00Z |
| Status | PROVISIONAL (§11.4.290) |
| Status summary | How to run the three `scripts/security/` tools. Every write path is tested only against a loopback fixture or a fake `gh`; no apply has been run against a real forge or against GitHub. |
| Authority | Tool documentation for `scripts/security/`; no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.113 (no force push), §11.4.156 (no CI/CD), §11.4.201 / §11.4.273 (instrument honesty), §11.4.18 (script documentation) govern. |
| Scope | Universal (§11.4.17) for the scan; the target and repository lists are this repository's DATA (§11.4.35). |
| Issues | Codeberg force-push blocking is UNCONFIRMED (no read-back field). How Gitea/Forgejo order a glob rule against an exact rule is UNCONFIRMED (a glob rule is reported, exit 6). A live run of the scan with the real gitleaks binary is owed (§11.4.289). The effect of disabling Actions on Dependabot for `terminator` is UNCONFIRMED. Round 3 (2026-11-12) is not yet independently reviewed. |
| Generated twins | .html / .pdf / .docx not generated for this revision (honestly absent, §11.4.106(E)). |

## The three tools

| Script | What it does | Default mode | Writes? |
|---|---|---|---|
| `scripts/security/forge_branch_protect.sh` | Blocks force-push and deletion of one branch (default `main`) on the forges that host the constitution. Nothing else. | `plan` | only `apply`, guarded |
| `scripts/security/github_actions_inventory_disable.sh` | Inventories GitHub Actions in the own orgs; disables Actions for a pinned list of repositories. | `list` | only `apply`, guarded |
| `scripts/security/history_secret_scan.sh` | Read-only full-history secret scan of one repository across all its remotes, with control needles planted inside the scanned mirror. | scan | never to a remote |

Each script prints its full usage and exit codes in its header comment; this guide does not replace it.

## Operator decisions (2026-11-12)

- **Branch protection blocks force-push and deletion only.** No review, status-check, signature or pull-request rule is added. Fast-forward pushes keep working, so the §11.4.113 / §11.4.288 workflow is unaffected.
- **API targets for apply:** the public GitHub constitution repository (`github_hd`), m3w (`m3w`) and Codeberg (`codeberg`). This is the apply allowlist in the script.
- **GitFlic and GitVerse:** probe only; `plan` prints the manual UI step. No API write.
- **The vasic-digital private repository (`github_vd`)** cannot be protected on the GitHub Free plan: GitHub answers 403 "Upgrade to GitHub Pro" and the script reports it as BLOCKED-PLAN.
- **Actions scope:** exactly the 9 repositories in `scripts/security/actions_disable_allowlist.txt`. The same 9 are built into the script; apply refuses (exit 3) any `--repos-file` whose repository set is not exactly that list, and the confirm token is computed from the built-in list, never from the file passed in. The scope is never recomputed at apply time. A repository that gains a workflow later is reported as a difference and apply is refused. Changing the scope needs a new operator decision and an edit of both lists.

## Branch protection

```bash
bash scripts/security/forge_branch_protect.sh --list
bash scripts/security/forge_branch_protect.sh probe              # read-only GETs
bash scripts/security/forge_branch_protect.sh plan --target m3w  # what apply would send
FORGE_PROTECT_APPLY=yes bash scripts/security/forge_branch_protect.sh apply \
  --target m3w --apply-confirm m3w
```

Apply runs only when all of these hold: `FORGE_PROTECT_APPLY=yes`; exactly one `--target`; `--apply-confirm` names the same target; the target is on the apply allowlist; the target is the built-in target of that name (provider, API base, owner, repository and token variable all equal, not only the name). Otherwise it exits 3. An unknown `--apply-confirm` name is a usage error (exit 2).

With no mode the script runs `plan`, which never writes.

**Each token is bound to one host.** The gh keyring token goes only to `api.github.com`; `GITLAB_TOKEN` only to `gitlab.com`; `M3W_GITEA_TOKEN` only to `git.m3w.org`; `CODEBERG_GITEA_TOKEN` only to `codeberg.org`; `GITFLIC_TOKEN` only to `api.gitflic.ru`; `GITVERSE_TOKEN` only to `api.gitverse.ru`. All of them only over `https` and only on port 443 (no port, or `:443`). The host must equal the bound host exactly (case-insensitive): a longer host that starts or ends with it (`api.github.com.evil.example`, `evilapi.github.com`) does not count. A target (built-in or from `FORGE_PROTECT_TARGETS_FILE`) that names another variable, another host, another port, plain `http`, or a URL with user info is refused at start-up (exit 2) before any request, and every request checks the binding again. The only exception is a loopback API base (`127.0.0.1` or `[::1]`) when `FORGE_PROTECT_TEST_LOOPBACK=yes`; that is how the hermetic tests reach their fixture. Do not set it outside tests. In that mode the script refuses to start (exit 2) while any of `http_proxy`, `HTTP_PROXY`, `https_proxy`, `HTTPS_PROXY`, `all_proxy` or `ALL_PROXY` is set, because a plain-http request would hand the token to the proxy. Outside that mode a proxy only sees an https CONNECT tunnel, so the token stays inside TLS.

`curl` is called with `-q` (no `.curlrc` is read), without `-L` (a redirect is never followed, so a 3xx to another host or port cannot carry the token on) and without `-n` (no `.netrc`).

After the write, the script reads the protection back and checks the **fields**, not the HTTP status:

- **GitHub:** the ruleset has the deletion and non-fast-forward rules, enforcement `active`, target `branch`, it includes `refs/heads/<branch>` and excludes nothing, and it has a `bypass_actors` field that is present and empty. `GET /rules/branches/<branch>` must list both rule types for that ruleset id. An existing ruleset is matched by content, never by name, and it counts as ALREADY COMPLIANT only after the same `GET /rules/branches/<branch>` check: a ruleset that reads compliant but is not listed there is NOT CONFIRMED (exit 1, nothing sent). GitHub leaves out `bypass_actors` for a caller who cannot read the bypass list; such a ruleset is UNCONFIRMED (exit 1, nothing sent). A ruleset with our name but other content is reported NON-COMPLIANT and nothing is sent. The ruleset list is read as one page of 100; a full page is reported UNKNOWN (exit 1, nothing sent) instead of being guessed.
- **GitHub Free, private repository:** reported BLOCKED-PLAN with exit 7, so a caller can tell "not protectable" from "done" (exit 0). The order when several targets run is 4 > 1 > 7 > 6 > 0.
- **Gitea / Forgejo:** `enable_push` is true and the push whitelist is off. When the instance has the `enable_force_push` field, it must be false. The read-back rule must be for the branch itself. An existing rule that is not compliant is reported and is not modified. Another rule whose name is a glob (`*`, `?`, `[`) may also match the branch. Which rule wins is not checked (UNCONFIRMED), so such a rule is printed and the exit is 6.

### Codeberg: force-push blocking is UNCONFIRMED

Codeberg runs Forgejo. Its branch-protection API has no `enable_force_push` field, so a read-back cannot show that force-push is blocked. The script prints UNCONFIRMED and exits 6. The read-back still proves the rule exists with the fields the instance does expose.

### How protection is verified (no force-push leg)

The protection is never tested by force-pushing to a branch, not even to a scratch repository: §11.4.113 forbids force-push of any kind. The evidence is:

1. the read-back of the protection fields described above, and
2. the next ordinary fast-forward push (§11.4.288), which must still be accepted on every upstream.

What this leaves open is stated as it is: on Codeberg, nothing reads back that force-push is refused.

## Actions inventory and disable

```bash
bash scripts/security/github_actions_inventory_disable.sh list --org HelixDevelopment --org vasic-digital
bash scripts/security/github_actions_inventory_disable.sh plan \
  --repos-file scripts/security/actions_disable_allowlist.txt   # prints the confirm token
GH_ACTIONS_APPLY=yes bash scripts/security/github_actions_inventory_disable.sh apply \
  --repos-file scripts/security/actions_disable_allowlist.txt --apply-confirm <token>
```

- `list` prints one TSV row per repository. The Pages column comes from `GET /repos/{r}/pages` (`build_type`, or `-` on 404), so Pages deployed by a custom workflow is detected too. A repository that serves Pages is `excluded-pages` unless `--include-pages` is given.
- A row whose data could not be read shows `ERR`. Any `ERR` row makes the exit 1, and it refuses apply, because an unreadable repository might belong to the selection.
- The confirm token is the first 12 hex characters of the sha256 of the built-in allowlist, sorted in C collation, one repository per line. `plan --repos-file scripts/security/actions_disable_allowlist.txt` prints it. A `--repos-file` that is not the allowlist gets no token: `plan` says apply would be refused and exits 1, and `apply` exits 3.
- With no mode the script runs `list`, which never writes.
- The workflows of a repository are read as one page of 100. When the answer says there are more (`total_count` larger than the list), the row is `ERR`.
- Sorting and comparing use C collation. Under `en_US.UTF-8`, `comm` reported the sorted mixed-case allowlist as "not in sorted order" (found while testing round 2), so the script exports `LC_ALL=C`.
- Apply refuses (exit 3) when the live selection differs from the file. It then prints `SCOPE DIFF` lines. Repositories that are already disabled count as done.
- Every PUT is read back and must show `enabled=false`.

**UNCONFIRMED:** whether disabling Actions also stops Dependabot updates for `HelixDevelopment/terminator`. This has not been checked.

## History secret scan

```bash
SCRATCH=/abs/scratch/dir OUT=/abs/scratch/dir/report.tsv \
  bash scripts/security/history_secret_scan.sh <url1> [<url2> ...]
SCRATCH=/abs/scratch/dir bash scripts/security/history_secret_scan.sh --keys-file ~/api_keys.sh <url>
```

- All remotes are fetched into one bare mirror.
- Three control needles are planted inside that same mirror, under `refs/fetched/needle/*`, so they go through the same path, options and refs as the real history:
  - **pos:** a fabricated token added in one commit and deleted in the next. It must be found.
  - **merge:** a fabricated token that exists only in a merge commit's diff. It must be found, which proves the `-m` option is really applied.
  - **neg:** a plain file. It must not be found.
- One gitleaks run covers everything: `--redact --log-opts="--all -m"`. Only exit 0 or 1 with a consistent JSON report is accepted; anything else is SCANNER-ERROR (exit 6). A failed needle is BLIND (exit 3).
- Findings go to `$OUT` as a value-free TSV.
- `--keys-file` really performs an exact-match pass over every blob. The values travel on a pipe, never in argv. The output is `$OUT.keys.tsv`, with variable names and blob counts only. A present control and an absent control guard this pass too. Values shorter than 12 characters and placeholder values are not searched; a note names them and counts them (names only).
- The scanner's own console output (file paths, commits, rule ids) is written to a file inside the work directory, never to the script's stdout or stderr.
- Credential-carrying URLs are refused for every scheme, not only http(s): `scheme://user:password@host`.
- Nothing is downloaded at run time. Without a pre-installed gitleaks the exit is 4.

## Credentials

- Tokens are read by variable name, inside a subshell, from the keys file (default `~/api_keys.sh`). A keys file that group or others can read is refused.
- Tokens reach `curl` on stdin (`curl -K -`), never in argv, a URL, a file or a log. Xtrace is switched off around them.
- For GitHub, the scripts use the `gh` keyring token, read with `gh auth token --hostname github.com`. The Actions script calls `gh api --hostname github.com`. Both unset `GITHUB_TOKEN`, `GH_TOKEN`, `GH_HOST`, `GH_ENTERPRISE_TOKEN` and `GITHUB_ENTERPRISE_TOKEN` for the `gh` call, so a `GH_HOST` setting cannot point the token at another host.

## Tests

| Test | Cases | Tier |
|---|---|---|
| `tests/security/test_forge_branch_protect.sh` | 168 | normal (loopback fixtures `tests/security/fixtures/forge_fixture.py`, two instances) |
| `tests/security/test_github_actions_inventory_disable.sh` | 44 | normal (fake `gh`) |
| `tests/security/test_history_secret_scan.sh` | 45 | normal (fake gitleaks, real git) |
| `tests/security/test_security_scripts_mutations.sh` | 119 mutants | heavy (each mutant must make its test fail) |

All tests use fake tokens and loopback endpoints only. No test writes to a real forge. They are hermetic gate-logic tests (§11.4.289(C)(2)): they prove that the scripts decide correctly, not that a real forge accepted a rule.

Evidence from the first run of 2026-11-12 (round 1), all in `docs/qa/security_scripts_2026_11_12/` with a `SHA256SUMS` file:

- **RED against the old scripts:** forge 16/57, actions 13/33, history 12/35 passed.
- **GREEN:** 57/57, 33/33 and 35/35, three identical runs each.
- **Mutation, final run:** 49 of 49 mutants killed.
- **Mutation, first and second runs:** these left 6 and then 2 survivors. Each survivor led to a new test, recorded in `mutants_run1.txt` and `mutants_run2.txt`.
- **shellcheck:** `-S warning` reports nothing.

Round 2 (fixes after the independent review of round 1), evidence in `docs/qa/security_scripts_2026_11_12/round2/` with its own `SHA256SUMS` file:

- **RED, the new tests against the round-1 scripts:** forge 66/83, actions 24/40, history 40/42 passed.
- **GREEN:** 83/83, 40/40 and 42/42, one run each.
- **Mutation:** 79 of 79 mutants killed (the 49 of round 1 and 30 new ones). Three mutations are left out of the table as equivalent, with the reason in the test header: removing the per-request host-binding check (the start-up check already refuses), a self-referential confirm token (the token no longer depends on the file passed), and removing `LC_ALL=C` (the result depends on the locale of the machine running the test). Round 3 corrects the last claim: that mutant is not equivalent; see below.
- **shellcheck 0.11.0:** `-S warning -x` reports nothing.

Round 3 (fixes after the independent review of round 2, which found that the tests did not hold the round-2 fixes), evidence in `docs/qa/security_scripts_2026_11_12/round3/` with its own `SHA256SUMS` file:

- **New tests:** token-to-host binding for four token variables (prefix host, suffix host, user info, ports `8443`, `0443`, `80`, plain `http`, and the accepted golden-FALSE forms); apply targets that change only the owner, the repository, the token variable or the provider (exit 3, no request); exit order with two targets in both orders (4/7, 1/7, 6/7, 4/1, 6/1); a hostile `.curlrc` with a control needle that shows plain curl reads it; a 302 redirect to a second listener on another port; the six proxy variables in the loopback test mode; `gh` called with `--hostname github.com` while `GH_HOST` and the enterprise tokens are set; Gitea glob rules with `?` and `[`; the exact-match negative control of the history scan; keys files with mode 0640 and 0604; one plan and one apply case under `LC_ALL=en_US.UTF-8`.
- **RED, the new tests against the round-2 scripts:** forge 148/168, actions 42/44, history 45/45 passed. The history scanner already refused a group-readable keys file and already had the negative control; its new tests are there to kill the reviewer's mutants Z3 and Z4.
- **GREEN:** 168/168, 44/44 and 45/45.
- **Mutation:** 119 rows. The 17 reviewer mutants of round 2 (X3, X6-X15, X17, X18, Y7, Z3, Z4, Z8) verbatim, the locale mutant Y4, and 22 new ones (R3*): 40 of 40 killed. The other 79 rows, re-run against the round-3 tree: 79 of 79 killed. Total 119 of 119 (`mutants.txt`).
- **Correction:** removing `LC_ALL=C` from the Actions script is not an equivalent mutant. With `LC_ALL=en_US.UTF-8` pinned in a test, the mutant fails (row Y4).
- **shellcheck:** `-S warning -x` reports nothing.
- Still UNCONFIRMED: Codeberg force-push blocking; how Gitea/Forgejo order a glob rule against an exact rule; the Dependabot effect for `terminator`; a live run with the real gitleaks binary. No apply has been run against a real forge, and there is no force-push leg.
