# Release cut procedure (scripts/release/)

| Field | Value |
|---|---|
| Revision | 7 |
| Created | 2026-11-11 |
| Status | active, PROVISIONAL (scripts tested on host fixtures only; no release has been cut with them yet) |

This page is the §11.4.18 companion of the three release scripts and the procedure that uses them.
The cut is mechanical (§11.4.274): every number and id list in the CHANGELOG entry comes from a
script reading committed data; a person supplies only the decisions listed under "Manual keys".

## The scripts

| Script | What it does | Exit codes | Test |
|---|---|---|---|
| `scripts/release/derive_release_facts.sh --base C --prev-tag T [--remotes "R..."] [--today D]` | Prints KEY=VALUE facts: commit and diff counts since the previous tag, tracker counts by status, severity and reproduction/investigation state (§11.4.294(H)), the §11.4.290(4) count line, §11.4.288 refs not on `main` per remote. Reads `git show C:docs/workable_items.db` from a temp copy opened read-only; never fetches. Output is buffered: when any tracker query fails (for example a missing column) nothing is printed. An item closed on the previous tag's date is not counted as verified since it (the tag date has day granularity). | 0 facts, 2 usage, 3 data missing or a query failed (stdout empty) | `tests/release/test_derive_release_facts.sh` |
| `scripts/release/render_release_entry.py [--draft] TEMPLATE FACTS MANUAL` | Fills `{{key}}` from FACTS and `{{MANUAL:name}}` from MANUAL (`@@name` blocks), builds `states_block` and `unmerged_refs_block`, drops the template's leading comment. Refuses a left-over placeholder, an empty or TODO/TBD manual value, an unused manual block, and an `open_status[...]` / `open_severity[...]` fact the template does not render (a status or severity value new at cut time; extend the template). Revision 6 (B-M4 of the v73.4 dry run): also refuses a manual value that is still a placeholder (see "Placeholders and --draft" below) unless `--draft` is given; a `--draft` render carries a fixed marker line that `tag_and_release.sh` refuses. | 0 rendered, 2 usage, 3 refused (nothing on stdout) | `tests/release/test_render_release_entry.sh` |
| `scripts/release/tag_and_release.sh --tag T --sha S --remotes "R..." [--release SPEC]... [--prerelease] [--gitlab-released-at ISO8601] [--dry-run]` | Preflight on every remote before any write (fetch main, ancestor of S, clean tree at S, CHANGELOG first heading = T, badge check, tag identity), then `git push --atomic` of `main` and the tag per remote, ls-remote read-back, platform releases only for remotes read back OK. Never forces; a re-run resumes and skips remotes already OK. | 0 OK, 1 FAIL, 2 usage, 5 OK with release GAPs (a gitea publisher exit 3 is a GAP only with its `SKIPPED-NO-TOKEN` line; any other exit 3 is a FAIL) | `tests/release/test_tag_and_release.sh` |

`--release` specs: `github:REMOTE:OWNER/REPO`, `gitlab:REMOTE:OWNER/REPO`, `gitea:REMOTE:BASE_URL:OWNER/REPO:TOKEN_VAR`.
Revision 7 (B-M2 of the v73.4 dry run): a gitea spec names the variable that holds its token (fifth field), and
the pair (BASE_URL, TOKEN_VAR) must be bound in `config/forge/hosts.tsv`: a row with provider `gitea` whose
`api_base` is `BASE_URL/api/v1` lists TOKEN_VAR (today `https://git.m3w.org` with `M3W_GITEA_TOKEN`,
`https://codeberg.org` with `CODEBERG_GITEA_TOKEN` or `CODEBERG_TOKEN`; a loopback test URL takes
`GITEA_LOOPBACK_TEST_TOKEN` only). An unbound pair, an unknown host, a port the table does not name, an
unreadable table or the old four-field spec is a usage error (exit 2) before anything is fetched or written,
also on `--dry-run`. The publisher is called with `--token-var TOKEN_VAR` and gets that variable only;
`scripts/release_publish_gitea.sh` no longer has a default token variable and refuses (exit 2) without
`--token-var` or with an unbound pair, before any network call. Before B-M2 the gitea leg passed no
`--token-var` and the publisher fell back to `M3W_GITEA_TOKEN`, so a codeberg spec would have sent the m3w
token to codeberg. The check is `scripts/release/redact_cut.sh` `rc_gitea_binding` (pure bash; the table is
read relative to the helper, two directories up). Honest limit: the binding is only as good as the table;
an operator who adds a wrong row binds a wrong pair, and the table is edited by recorded operator decision
only (its own header says so). Tests: `tests/release/test_tag_and_release.sh` C56, `test_publish_gitea.sh`
B-M2 block (a stub server records every Authorization header; a curl shim counts calls), mutants BM2A-BM2K.
The last line of `tag_and_release.sh` is `RESULT: ...`; a caller reads it and the exit code, never the
platform tool's own success message (§11.4.200(2)). A `--release` spec is not cross-checked against the
remote's URL (`github:r1:other/repo` is accepted; review n-3): GitHub legs are de-duplicated by
repository id because one repository can have several names, so an owner/name match would refuse
legitimate aliases. The guards are `--verify-tag` (GitHub) and `--ref SHA` (GitLab), so a release can
only be made for the tag that the read-back proved; check the spec list by eye in the `--dry-run` plan.
Every external-command message the release scripts print (git fetch and push failures, the gitea
publisher's refusal, curl failures, and the stderr of every other command, flushed once at exit) goes
through ONE helper, `scripts/release/redact_cut.sh`, which redacts first and cuts second, whatever git's or
curl's own redaction does (review n-4, rounds 1-4). It redacts, line by line: URL userinfo of any scheme
from the first `://` to the LAST `@` of the line (so a password holding a raw `/`, `@`, `?`, `#`, quote,
space or an invalid byte is covered; a later path `@` or a second URL's host is over-redacted, by
design); a scheme-less `user:password@host`; the value of every query, fragment or form parameter whose
name ends in token, secret, password, key, sig, auth, credential, session, jwt (and similar, any case);
the rest of a header line such as `Authorization:`, `PRIVATE-TOKEN:`, `X-...-Token:`, `Cookie:`; a bare
`Bearer` token; and the `ghp_`/`github_pat_`/`glpat-` token shapes. Its documented limits (in the
helper's header) are: a parameter value holding a raw blank or `&`, `#`, `;`, quote, `<`, `>` prints the
tail after that character; a credential split over two lines; a secret printed in none of these shapes.
The scripts write their temp files only inside one private (0700) run directory, removed at exit and on
SIGHUP, SIGINT and SIGTERM; only SIGKILL leaves it behind. Threat model and census:
`docs/qa/con227_234_2026_11_11/round4/threat_model.md`.

GitLab pre-release (revision 3, CON-416): GitLab's Releases API has no pre-release attribute
(<https://docs.gitlab.com/api/releases/>, read 2026-11-12) and `glab release create` (1.129.0, its
`--help`) has no `--prerelease` option, so with `--prerelease` the GitLab leg marks the release itself:
the name gets the prefix `PROVISIONAL pre-release: ` (unless the title already says PROVISIONAL), the
description starts with one fixed PROVISIONAL line, and `glab` gets `--no-update` (for a final release
too: an existing release is never edited). The release, new or kept on a re-run, is read back with
`glab api --hostname H projects/GROUP%2FREPO/releases/TAG` (H is `GITLAB_HOST` without its scheme, else
`gitlab.com`; the call goes through the same `RELEASE_NET_TIMEOUT` bound as every other network call): a
missing mark or an answer that is not a release object is a FAIL, a failed or timed-out read-back a GAP.
`--gitlab-released-at` (a future ISO 8601 time, `Z` or `+HH:MM`, only with `--prerelease` and a gitlab
spec; GNU `date` parses it, so on a BSD or macOS `date` every value is refused) is passed as
`--released-at`, so GitLab shows its "Upcoming Release" badge until that time; the read-back must show
`upcoming_release=true` and the same instant, otherwise the leg is a GAP marked UNCONFIRMED. The badge
ends by itself at that time and only the marks stay. A final release gets no mark and no date. A final
run over a release kept from an earlier `--prerelease` run keeps it as it is, marks included: there is
no promotion path (edit the release by hand). The future check runs when the arguments are read, so a
time only minutes away can be in the past when the release is created; the read-back then reports it.

## Manual keys of the v73.4 template

`cut_date`, `waiver_authoriser`, `waiver_decision_and_source`, `waiver_expiry`, `retest_item_id`,
`retest_statement` (revision 4, CON-417; revision 5, B-M1 of the v73.4 dry run: the §11.4.40 retest
sentence of the entry; it must start with a verdict word, followed by the base, tier and log, and the
renderer refuses any other start with exit 3, so the entry never implies a pass. The verdict words are the
runner's own: `RETEST_RESULTS` in `scripts/full_suite/run_full_suite.py` (one source, read with
`ast.literal_eval`; missing or malformed = exit 3), the eleven words `scripts/run_full_suite.sh` ends a run
with, plus `NOT RUN`. `PASS-FULL`, `FAIL` and `NOT RUN` render as written; `PASS-FULL-WITH-KNOWN` and every
`PARTIAL-*` word render with the note `[gap: not a section 11.4.40 full retest; (L6) stays open]` after the
word, `MANIFEST-MISMATCH` and `REFUSED-TOPOLOGY` with `[gap: nothing was run; not a section 11.4.40 retest;
(L6) stays open]`, so a gap is never written as a pass. `MANIFEST-OK` (a `--verify-manifest` result) is not a
run verdict and is refused. The renderer checks the word only, not the base, tier or log that follow it, and
not that `PASS-FULL` came from an `--include-heavy` run (CON-421 stays open for a machine verdict)), `verified_date`, `verified_block`, `killpg_summary_line`, `provisional_changes_block`,
`followups_tracking`, `known_defects_block`, `next_candidate_statement`. Every other key is mechanical.

### Placeholders and --draft (revision 6, B-M4 of the v73.4 dry run)

The dry run rendered an entry with `cut_date` = `DRAFT`, `retest_item_id` = `` `<CON-NNN>` ``,
`waiver_expiry` = `` `<recorded date + 30 days>` `` and `killpg_summary_line` = `` `<paste ...>` ``, all
with exit 0, so a rehearsal render and a cut render could not be told apart. Without `--draft` the
renderer now refuses (exit 3) a manual value that holds an angle-bracket token other than an autolink
`<https://...>` or a plain lower-case HTML tag (`<details>`, `<br/>`, `<a href="x">`; every attribute
written `name="value"`), the upper-case word `DRAFT`, the token `UNCONFIRMED-CUT-DATE`, or a `cut_date`
that is not a real calendar date `YYYY-MM-DD`. `--draft` renders such values (a rehearsal) and puts the
line `> **DRAFT RENDER — not a release entry.** ...` right after the first `## ` heading; a real
`tag_and_release.sh` run aborts before any write when the release notes hold that line, and `--dry-run`
prints `PLAN refuse ...` and says so in its RESULT line. `--draft` relaxes only this check: a missing
value, TODO/TBD, an unused block and an unrendered fact still refuse. Known limits: a lower-case one-word
angle token such as `<sha>` reads as an HTML tag and passes; a bare `CON-NNN` (no brackets) is not
refused, because a real entry may name the notation; deleting the marker line by hand defeats the
tag-side check (the renderer-side refusal still applies to a re-render).

## Cut steps

1. Fetch every remote; merge the final `main` into the vehicle (merge, never rebase) and land it on
   `main` fast-forward (§11.4.288). The base of the release is that `main` commit.
2. On `main`, register in the tracker the owed §11.4.40 retest and §11.4.185 confirmation item
   (its id is `retest_item_id`) and the review follow-ups; commit. The tracker is a binary database,
   so this is done on the final `main`, not in the vehicle.
3. `scripts/release/derive_release_facts.sh --base <main> --prev-tag helixconstitution-v73.3 --remotes "<all>" > facts.txt`
   (after `git fetch --prune` of every remote).
4. Re-run `bash scripts/gates/cm_killpg_pgid_guard.sh` and every command quoted under VERIFIED; paste
   their real output lines into the manual file.
5. `python3 -I scripts/release/render_release_entry.py docs/release/helixconstitution-v73.4_entry.template.md facts.txt manual.txt > entry.md`
   (never `--draft` for the cut; a rehearsal uses `--draft` and is refused by step 8);
   put `entry.md` above every other entry of `CHANGELOG.md`.
6. `bash scripts/badges/compute_badges.sh --print`, put the row into README, then `--check`.
7. Commit (the release commit adds the entry and the badge row only), and obtain the independent
   review GO (§11.4.209) for that exact commit id.
8. `scripts/release/tag_and_release.sh --tag helixconstitution-v73.4 --sha <release commit> --remotes "<all>" --prerelease --release ... --dry-run`,
   then the same without `--dry-run`. On exit 1 fix the cause and re-run (it resumes); on exit 5
   record each GAP as a tracked item.

## Manual QA and the FINAL tag

The template's FINAL precondition 2 asks for a recorded §11.4.185 manual-QA confirmation. A §11.4.271
waiver may stand in for it only as a tracked record naming the rostered non-producer authoriser, an
unelapsed expiry and the tracked item that owes the human QA, and the FINAL entry then says the
confirmation is waived, not given. The operator relayed on 2026-11-11 (not verbatim) that the FINAL QA
is an agent-roster QA under such a waiver, 30 days; until that waiver exists as a tracked record it is a
relayed decision and does not meet precondition 2.

## Honest boundary (§11.4.6)

The scripts are tested with real git, real sqlite3 and local bare remotes; `gh` and `glab` are stubs
in the tests (unit class, §11.4.289(C)), so no real platform release has been proven by them. A
server that refuses `--atomic` makes the push two steps (main, then the tag only after main reads
back), which narrows but does not remove the window between them. GitLab's own handling of a future
`released_at` (the Upcoming Release badge, the `upcoming_release` field, and whether such a release is
listed first or chosen as "latest") has not been observed on gitlab.com by these tests; it is taken from
the GitLab documentation and is UNCONFIRMED until a real release is read back. `glab release create`
resolves its host itself (`-R GROUP/REPO`), while the read-back names its host; when they differ (a
self-hosted GitLab without `GITLAB_HOST`) the read-back fails and the leg is a GAP, never a false MARKED.
