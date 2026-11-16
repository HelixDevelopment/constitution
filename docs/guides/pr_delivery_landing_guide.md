# Pull-Request Delivery Landing Guide

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16T18:00:00Z |
| Status | draft |
| Status summary | How an agent lands a task by pull request in this repository under §11.4.297, using `config/delivery.conf`. PROVISIONAL: no delivery tool exists; the commands below are run by hand and have not yet been run end to end under this guide. The reviewer configuration as recorded cannot meet §11.4.297(D)(2); by the recorded operator decision OPD-2026-11-16-PR-DELIVERY-R2 the delivery reports that, ends non-zero, and the agent still merges when every other condition holds (a consumer departure, open as CON-425; see "Reviewers" below). Merge window: none. |
| Authority | §11.4.297 (pull-request delivery), §11.4.288 (all work on `main`), §11.4.113 (no force), §11.4.209 (independent review substrate). No new rule; where this guide and the canon differ, the canon governs. |
| Scope | Agents delivering changes to this repository and to its own submodules (`own_repositories` in `config/delivery.conf`). |
| Issues | Reviewer list holds only the author account; platform merge-method settings and branch protection could not be read with the current token (HTTP 403); see `docs/qa/pr_delivery_decision_20261116/` and tracker items CON-423 and CON-425. |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

## Recorded operator decisions (2026-11-16, second round)

Decision id `OPD-2026-11-16-PR-DELIVERY-R2`, relayed by the conductor; the wording below paraphrases it and is not the operator's verbatim text.

1. Every pull request is created, self-reviewed and merged by the agent, and assigned to the main repository owner's account (`pr_assignees`). If the platform refuses the agent's own review or a reviewer request, the refusal is reported (§11.4.297(D)), never dropped and never replaced by another account. The delivery then ends non-zero on that point, and the agent still merges when every other merge condition holds, citing this decision (`author_only_reviewer_policy=report-and-merge`). This is a departure recorded by this repository as a consumer; `Constitution.md` is not amended. Whether to keep it, amend the anchor or add a second account is open: tracker item CON-425.
2. Merge window: none (`merge_window_hours=none`). A pull request is merged as soon as every merge condition holds.
3. The account-name gate reads `config/delivery.conf` at the repository root by default and leaves it out of `--changed-since` (CON-424).
4. The extra keys `pr_repository`, `pr_assignees`, `decision_date` and `own_repositories` stay.
5. The remaining open items were answered conservatively by the agent (GO record as a pull-request comment, a wider `shared_single_files` list, `direct_push_guard=off`, no `tool_written_paths`, every own submodule in `pr` mode with this file's values). Each is marked `UNCONFIRMED` in `config/delivery.conf` and listed in CON-423.

## Where the settings live

Every value this guide uses comes from `config/delivery.conf` (DATA, §11.4.35). Read it, never retype it. Account names appear only in that file; this guide and every rule file name none (gate `CM-PR-DELIVERY-ACCOUNT-NAME-FREE`). The shell below reads the values like this:

```bash
conf() { awk -F= -v k="$1" '{sub(/#.*/,"")} $1==k{print $2}' config/delivery.conf; }
REMOTE="$(conf pr_remote)"          # GitHub-only remote, never the fan-out 'origin'
REPO="$(conf pr_repository)"
BASE="$(conf base)"
PREFIX="$(conf branch_prefix)"
FORM="$(conf landing_form)"         # merge-commit
[ "$(conf mode)" = pr ] || { echo "mode is not pr: §11.4.288 applies as written"; exit 1; }
```

`origin` in this repository pushes to every mirror (see `install_upstreams.sh`). Push a task branch only to `$REMOTE`, so the branch exists in one place and is retired in one place.

## 1. One task, one branch

The task id is the workable-item id (for example `CON-095`). The branch is `<prefix>/<id>-<slug>`, the same name in every repository the task touches (§11.4.181).

```bash
ID=CON-095; SLUG=short-kebab-name; B="$PREFIX/$ID-$SLUG"
git fetch "$REMOTE" --prune
# reuse the task's existing branch; refuse if two exist
n="$(git ls-remote --heads "$REMOTE" "$PREFIX/$ID-*" | wc -l)"
[ "$n" -le 1 ] || { echo "two branches for $ID: refuse"; exit 1; }
if [ "$n" -eq 1 ]; then B="$(git ls-remote --heads "$REMOTE" "$PREFIX/$ID-*" | sed 's|.*refs/heads/||')"; git switch "$B";
else git switch -c "$B" "$REMOTE/$BASE"; fi
```

Never start a task branch from a `HEAD` that holds commits the remote base lacks (they would ride into this pull request), and never from a detached `HEAD`.

## 2. Commit

Every commit carries a plain trailer value (ids only), then the out-of-scope trailers if any, then the attribution:

```text
Roadmap-Item: CON-095
Out-of-scope: <path> — <reason> — <justification>
Co-Authored-By: <agent attribution line>
```

A commit naming two ids needs a `Multi-Task-Reason:` trailer. Annotations inside the `Roadmap-Item:` value are refused.

## 3. Push and read back

```bash
git push "$REMOTE" "$B"                 # fast-forward only: no --force, no --delete, no tags
test "$(git ls-remote "$REMOTE" "refs/heads/$B" | cut -f1)" = "$(git rev-parse HEAD)" \
  || { echo "remote tip differs from local tip: stop"; exit 1; }
```

The exit status of `git push` is not evidence; the `ls-remote` comparison is.

## 4. Open or update the pull request (idempotent)

```bash
PR="$(gh pr list -R "$REPO" --head "$B" --state open --json number --jq '.[0].number')"
if [ -z "$PR" ]; then
  gh pr create -R "$REPO" --base "$BASE" --head "$B" --title "$ID: <subject>" --body-file /path/to/body.md
  PR="$(gh pr list -R "$REPO" --head "$B" --state open --json number --jq '.[0].number')"
fi
```

The body names the task id, the evidence paths (repository-relative, with sha256, §11.4.297(E)), and, for a pin bump, the parity table of step 10. The source-correctness GO record (`go_record_location=pr-comment`) is a pull-request comment that names the reviewed head sha, the review substrate and the verdict; it is never committed into the task branch, because a commit would move the reviewed head. Read it back before the merge.

## 5. Reviewers: request and read back

```bash
AUTHOR="$(gh api user --jq .login)"
for a in $(conf pr_reviewers | tr ',' ' '); do
  if [ "$a" = "$AUTHOR" ]; then echo "note: $a is the author and is skipped (§11.4.297(D)(2))"; continue; fi
  gh pr edit "$PR" -R "$REPO" --add-reviewer "$a" || echo "REFUSED reviewer $a (report the platform text, §11.4.297(D)(4))"
done
gh pr view "$PR" -R "$REPO" --json reviewRequests,latestReviews   # an assignment counts only if shown here
```

Measured on 2026-11-16: the configured list holds one account and it is the account `gh` is logged in as. Under §11.4.297(D)(2) that account is skipped, no reviewer is possible, and the delivery reports it and ends non-zero. Assign the pull request to the owner account:

```bash
for a in $(conf pr_assignees | tr ',' ' '); do
  gh pr edit "$PR" -R "$REPO" --add-assignee "$a" || echo "REFUSED assignee $a (report the platform text)"
done
gh pr view "$PR" -R "$REPO" --json assignees   # read back
```

By decision 1 above (`author_only_reviewer_policy=report-and-merge`), the report of "no reviewer possible" and any platform refusal is written into the pull request (a comment that quotes the platform's text) and into the delivery output, the delivery keeps a non-zero exit status, and step 7 may still merge when every other condition holds, citing `OPD-2026-11-16-PR-DELIVERY-R2`. This is a consumer departure from §11.4.297(C)/(D), not an exception in the anchor; it is open as tracker item CON-425.

## 6. Self-review on the platform

GitHub refuses an approval by the author, so the self-review is a COMMENT review (§11.4.297(C)(1)). It names the head it read, what was checked and where the GO record is; every finding is a line comment.

```bash
HEAD_SHA="$(git rev-parse HEAD)"
gh api "repos/$REPO/pulls/$PR/reviews" -X POST \
  -f commit_id="$HEAD_SHA" -f event=COMMENT \
  -f body="Self-review of $HEAD_SHA: files read: <list>; evidence resolved: <paths+sha256>; gates/tests: <results>; GO record: <path>." \
  -F 'comments[][path]=<file>' -F 'comments[][line]=<n>' -F 'comments[][side]=RIGHT' -F 'comments[][body]=<finding>'
gh api "repos/$REPO/pulls/$PR/reviews" --jq '.[] | {id, commit_id, state, body}'   # read back
gh api "repos/$REPO/pulls/$PR/comments"  --jq '.[] | {path, line, body}'          # read back
```

Answer every finding with a follow-up commit (reviewed again) or a reply. The self-review is never the source-correctness GO; that stays the independent review of §11.4.142 / §11.4.209.

## 7. Merge conditions, then merge

Read each back right before the merge:

```bash
git fetch "$REMOTE" --prune
PLATFORM_HEAD="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid)"
[ "$PLATFORM_HEAD" = "$HEAD_SHA" ] || { echo "head moved: review again"; exit 1; }                       # (d)
git merge-base --is-ancestor "$REMOTE/$BASE" "$HEAD_SHA" || { echo "stale base: merge base into branch, review again"; exit 1; }  # (g)
# (a) GO record for exactly $HEAD_SHA exists and is readable; (b) self-review of $HEAD_SHA read back;
# (c) reviewer requests shown or refusal reported (author-only list: "no reviewer possible" reported in the PR,
#     delivery exit status stays non-zero, merge allowed by OPD-2026-11-16-PR-DELIVERY-R2 only when every other
#     condition here holds); (e) serial order of shared_single_files; (f) required approvals.
# No merge window (merge_window_hours=none): merge as soon as all of the above hold.
gh pr merge "$PR" -R "$REPO" --merge --match-head-commit "$HEAD_SHA"
```

Only `--merge` (a merge commit) is used, matching `landing_form=merge-commit`. `--squash` and `--rebase` are forbidden (§11.4.297(A.3)). Do not use `--delete-branch` here: this repository has more than one declared upstream.

## 8. Read back the landing

```bash
git fetch "$REMOTE" --prune
gh pr view "$PR" -R "$REPO" --json state,mergeCommit,headRefOid
MC="$(gh pr view "$PR" -R "$REPO" --json mergeCommit --jq .mergeCommit.oid)"
[ "$(git rev-parse "$MC^2")" = "$HEAD_SHA" ] || echo "FORM CHECK FAILED: squash or rebase; keep the branch, file an item (§11.4.297(C)(3))"
git merge-base --is-ancestor "$HEAD_SHA" "$REMOTE/$BASE" && echo "reviewed head is on $BASE"
```

Report "landed" only after this read-back.

## 9. Mirrors, then retirement

The platform merge moves `main` on GitHub only. Bring local `main` to the merged tip and push it fast-forward to every declared upstream through the fan-out remote (no force), then read each upstream back:

```bash
git switch "$BASE" && git merge --ff-only "$REMOTE/$BASE"
git push origin "$BASE"                                     # fan-out to every upstream; fast-forward only
for r in $(git remote | grep -v '^origin$'); do
  tip="$(git ls-remote "$r" "refs/heads/$BASE" | cut -f1)"
  if [ -z "$tip" ]; then echo "$r UNREACHABLE"; elif git merge-base --is-ancestor "$HEAD_SHA" "$tip" 2>/dev/null; then echo "$r PRESENT"; else echo "$r MIRROR-LAG $tip"; fi
done
```

`git merge-base` needs the upstream tip locally; fetch that remote first if it reports an unknown object. Retire the task branch only when every upstream reads `PRESENT`:

```bash
git push "$REMOTE" --delete "$B" && git branch -d "$B" && git fetch --all --prune
```

## 10. Submodule changes and the pin bump

1. The submodule change is its own pull request in the submodule repository (its row in `own_repositories`), on a branch with the same name `$B`, under steps 1 to 8 with that repository's values.
2. It lands first, as a merge commit. Keep its task branch until the parent pull request that records it has landed.
3. Push the submodule's merged `main` to every upstream of the submodule and read each back (step 9 run inside the submodule).
4. Only then, in the parent, move the gitlink to the submodule's merge commit and open or update the parent pull request. Its body carries the parity table:

```text
| Upstream | main tip | State |
|---|---|---|
| <remote> | <sha> | PRESENT / MIRROR-LAG <tip> / UNREACHABLE |
```

The pin bump is ready to land only when every row is `PRESENT`.
5. After the parent pull request has landed and been read back, retire the submodule task branch and the parent task branch.

## Enforcement words

Everything in this guide is `PROVISIONAL`: there is no delivery tool, no local direct-push guard (`direct_push_guard=off`), and the measured GitHub ruleset on `main` (2026-11-16) only forbids deletion and non-fast-forward pushes; it does not require pull requests and does not restrict the merge method. No text may call `main` protected beyond that read-back. The own submodule repositories had no rulesets at the same time.
