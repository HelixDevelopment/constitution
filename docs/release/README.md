# Release cut procedure (scripts/release/)

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-11 |
| Status | active, PROVISIONAL (scripts tested on host fixtures only; no release has been cut with them yet) |

This page is the §11.4.18 companion of the three release scripts and the procedure that uses them.
The cut is mechanical (§11.4.274): every number and id list in the CHANGELOG entry comes from a
script reading committed data; a person supplies only the decisions listed under "Manual keys".

## The scripts

| Script | What it does | Exit codes | Test |
|---|---|---|---|
| `scripts/release/derive_release_facts.sh --base C --prev-tag T [--remotes "R..."] [--today D]` | Prints KEY=VALUE facts: commit and diff counts since the previous tag, tracker counts by status, severity and reproduction/investigation state (§11.4.294(H)), the §11.4.290(4) count line, §11.4.288 refs not on `main` per remote. Reads `git show C:docs/workable_items.db` from a temp copy opened read-only; never fetches. Output is buffered: when any tracker query fails (for example a missing column) nothing is printed. An item closed on the previous tag's date is not counted as verified since it (the tag date has day granularity). | 0 facts, 2 usage, 3 data missing or a query failed (stdout empty) | `tests/release/test_derive_release_facts.sh` |
| `scripts/release/render_release_entry.py [--draft] TEMPLATE FACTS MANUAL` | Fills `{{key}}` from FACTS and `{{MANUAL:name}}` from MANUAL (`@@name` blocks), builds `states_block` and `unmerged_refs_block`, drops the template's leading comment. Refuses a left-over placeholder, an empty or TODO/TBD manual value, an unused manual block, and an `open_status[...]` / `open_severity[...]` fact the template does not render (a status or severity value new at cut time; extend the template). Refuses a manual value that still says `DRAFT` (whole word) unless `--draft` is given; `--draft` prints a notice on stderr and puts a marker line first, so a draft rendering cannot pass for an entry. `cut_date` must be a bare date `YYYY-MM-DD` (CON-423). | 0 rendered, 2 usage, 3 refused (nothing on stdout) | `tests/release/test_render_release_entry.sh` |
| `scripts/release/tag_and_release.sh --tag T --sha S --remotes "R..." [--release SPEC]... [--prerelease] [--gitlab-released-at ISO8601] [--dry-run]` | Preflight on every remote before any write (fetch main, ancestor of S, clean tree at S, CHANGELOG first heading = T, badge check, tag identity), then `git push --atomic` of `main` and the tag per remote, ls-remote read-back, platform releases only for remotes read back OK. Never forces; a re-run resumes and skips remotes already OK. | 0 OK, 1 FAIL, 2 usage, 5 OK with release GAPs (a gitea publisher exit 3 is a GAP only with its `SKIPPED-NO-TOKEN` line; any other exit 3 is a FAIL). `--dry-run` writes nothing, prints a plan line per leg with its `prerelease=` value and read-only probes (gitea: token shape only, never the value); exit 0 no problem, 1 a probe says the real run would fail, 5 it would leave a gap. One remote per distinct repository: a repeated name or two remotes pushing to the same repository abort (CON-423) | `tests/release/test_tag_and_release.sh` |

`--release` specs: `github:REMOTE:OWNER/REPO`, `gitlab:REMOTE:OWNER/REPO`, `gitea:REMOTE:BASE_URL:OWNER/REPO`.
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

`cut_date` (a bare date `YYYY-MM-DD`), `waiver_authoriser`, `waiver_decision_and_source`, `waiver_expiry`, `retest_item_id`,
`retest_statement` (revision 4, CON-417: the §11.4.40 retest sentence of the entry; it must start
with `PASS-FULL`, `PARTIAL-TOPOLOGY`, `FAIL` or `NOT RUN`, followed by the base, tier and log, and the
renderer refuses any other start with exit 3, so the entry never implies a pass; the renderer checks the
token only, not the base, tier or log that follow it), `verified_date`, `verified_block`, `killpg_summary_line`, `provisional_changes_block`,
`followups_tracking`, `known_defects_block`, `next_candidate_statement`. Every other key is mechanical.

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
5. `python3 -I scripts/release/render_release_entry.py docs/release/helixconstitution-v73.4_entry.template.md facts.txt manual.txt > entry.md`;
   put `entry.md` above every other entry of `CHANGELOG.md`.
6. `bash scripts/badges/compute_badges.sh --print`, put the row into README, then `--check`.
7. Commit (the release commit adds the entry and the badge row only), and obtain the independent
   review GO (§11.4.209) for that exact commit id.
8. `scripts/release/tag_and_release.sh --tag helixconstitution-v73.4 --sha <release commit> --remotes "<all>" --prerelease --release ... --dry-run`,
   then the same without `--dry-run`. A dry run that exits 1 shows a leg that would fail: fix it first;
   exit 5 shows a leg that would be a gap. On exit 1 of the real run fix the cause and re-run (it resumes); on exit 5
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
