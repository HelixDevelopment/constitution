# Release cut procedure (scripts/release/)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-11 |
| Status | active, PROVISIONAL (scripts tested on host fixtures only; no release has been cut with them yet) |

This page is the §11.4.18 companion of the three release scripts and the procedure that uses them.
The cut is mechanical (§11.4.274): every number and id list in the CHANGELOG entry comes from a
script reading committed data; a person supplies only the decisions listed under "Manual keys".

## The scripts

| Script | What it does | Exit codes | Test |
|---|---|---|---|
| `scripts/release/derive_release_facts.sh --base C --prev-tag T [--remotes "R..."] [--today D]` | Prints KEY=VALUE facts: commit and diff counts since the previous tag, tracker counts by status, severity and reproduction/investigation state (§11.4.294(H)), the §11.4.290(4) count line, §11.4.288 refs not on `main` per remote. Reads `git show C:docs/workable_items.db` from a temp copy opened read-only; never fetches. | 0 facts, 2 usage, 3 data missing | `tests/release/test_derive_release_facts.sh` |
| `scripts/release/render_release_entry.py TEMPLATE FACTS MANUAL` | Fills `{{key}}` from FACTS and `{{MANUAL:name}}` from MANUAL (`@@name` blocks), builds `states_block` and `unmerged_refs_block`, drops the template's leading comment. Refuses a left-over placeholder, an empty or TODO/TBD manual value, and an unused manual block. | 0 rendered, 2 usage, 3 refused (nothing on stdout) | `tests/release/test_render_release_entry.sh` |
| `scripts/release/tag_and_release.sh --tag T --sha S --remotes "R..." [--release SPEC]... [--prerelease] [--dry-run]` | Preflight on every remote before any write (fetch main, ancestor of S, clean tree at S, CHANGELOG first heading = T, badge check, tag identity), then `git push --atomic` of `main` and the tag per remote, ls-remote read-back, platform releases only for remotes read back OK. Never forces; a re-run resumes and skips remotes already OK. | 0 OK, 1 FAIL, 2 usage, 5 OK with release GAPs | `tests/release/test_tag_and_release.sh` |

`--release` specs: `github:REMOTE:OWNER/REPO`, `gitlab:REMOTE:OWNER/REPO`, `gitea:REMOTE:BASE_URL:OWNER/REPO`.
The last line of `tag_and_release.sh` is `RESULT: ...`; a caller reads it and the exit code, never the
platform tool's own success message (§11.4.200(2)).

## Manual keys of the v73.4 template

`cut_date`, `waiver_authoriser`, `waiver_decision_and_source`, `waiver_expiry`, `retest_item_id`,
`verified_date`, `verified_block`, `killpg_summary_line`, `provisional_changes_block`,
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
   then the same without `--dry-run`. On exit 1 fix the cause and re-run (it resumes); on exit 5
   record each GAP as a tracked item.

## Honest boundary (§11.4.6)

The scripts are tested with real git, real sqlite3 and local bare remotes; `gh` and `glab` are stubs
in the tests (unit class, §11.4.289(C)), so no real platform release has been proven by them. A
server that refuses `--atomic` makes the push two steps (main, then the tag only after main reads
back), which narrows but does not remove the window between them.
