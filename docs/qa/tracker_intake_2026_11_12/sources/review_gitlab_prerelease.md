# Independent review: GitLab pre-release leg of scripts/release/tag_and_release.sh (bundle head ed50c71e)

Reviewer: Claude Opus 5.5 (subagent). I did not write this change. Effort: UNCONFIRMED (the dispatch path does not report it, §11.4.231(F.2)).
Date: 2026-11-12. Bundle sha256 2cf628684ef269b98ac76cd5d699b8da7b5c4d37ff05d8945db89c471c49e35e: matches. One commit, ed50c71e, on base 02c10935.
Prerequisite objects came read-only through alternates from scratch clones. The live checkout was not touched. Nothing was pushed, nothing was written to a forge, and no live call was made.

## Verdict: GO-with-follow-ups (§11.4.276(G)), for ed50c71e on base 02c10935

The change is correct and honest on its own base, and every open finding is minor-class. Re-applying it on top of the fix227 vehicle (4c80482c) is a different change with real semantic conflicts (section 5). That re-application needs its own review. It must not be landed as a mechanical merge.

## 1. What the change does with --prerelease on GitLab

It does both things: a description marker and an optional upcoming date.
- The name gets the prefix `PROVISIONAL pre-release: `, unless the title already contains PROVISIONAL.
- The description starts with a fixed GL_MARK line saying that GitLab has no pre-release flag.
- glab gets `--no-update`. This also applies to final releases, which is harmless because the script checks whether the release exists first.
- The new option `--gitlab-released-at ISO8601` is passed as `--released-at`. It is accepted only together with --prerelease, must match `YYYY-MM-DDTHH:MM:SS(Z|±HH:MM)`, must be parseable by GNU `date -u -d`, and must be in the future when the arguments are parsed. Anything else is a usage error (exit 2) before any write.
- After a create, and on a resumed run when the release already exists, the script reads the release back with `glab api projects/<enc>/releases/<tag>` and checks the result in python3 -I:
  - Name lacks PROVISIONAL, or the first description line is not GL_MARK: FAIL.
  - Upcoming date requested but `upcoming_release` is not read back as true: GAP, marked UNCONFIRMED.
  - API read fails, or python3 is absent: GAP.
  - JSON cannot be parsed: FAIL.
- A final release gets no mark and no date.
- Dry run prints `prerelease=marked-by-title-and-description upcoming=...` and exits before any release work.

Honesty: no native flag is claimed anywhere (script header, verdict lines, docs). The PRERELEASE output line states "native pre-release flag: none on GitLab". The docs mark gitlab.com handling of a future released_at as UNCONFIRMED.

glab 1.129.0 on this host lists `--no-update`, `-D/--released-at` and `glab api --hostname` in its `--help` output (help text only, no network call). The live Upcoming Release behaviour on gitlab.com is UNCONFIRMED, as is the `upcoming_release` field value.

## 2. Tests run (nice -n 10, one at a time)

- tests/release/test_tag_and_release.sh: pass=73 fail=0 (21 s).
- shellcheck on the script: clean. On the test file: info-level only (SC1091, SC2016, SC2015 on the ok/bad idiom). Exit 1 comes from the info notes; none is a warning or an error.
- `scripts/run_full_suite.sh --verify-manifest`: MANIFEST-OK (total=901).
- `bash -n`: OK.
- Test class: the glab and gh stubs are UNIT/gate-logic class (§11.4.289(C)) and the test header says so. Git, the bare remotes and the hooks are real. This is not live proof against GitLab.

## 3. Own mutants: 21 written, 13 killed, 8 survived

Results file: review_gitlab_prerelease_mutants.txt.

KILLED: M01 released-at dropped, M02 future check removed, M04 ISO regex removed, M05 date allowed without --prerelease, M07 marks on a final release, M08 body marker removed, M09 read-back always OK, M10 name OR description check, M12 upcoming check always true, M14 token value printed, M16 --no-update dropped, M17 no read-back on a kept release, M21 missing-mark FAIL turned into a GAP.

SURVIVED:
- M03: the timezone-offset alternative removed from the regex. No test uses a `±HH:MM` input.
- M06: the "title already says PROVISIONAL" guard broken, giving a double prefix. No test covers it.
- M11: a `glab api` read failure reported as MARKED. This is a fail-open path with no test. The code itself is correct (it gives a GAP).
- M13: the dry run runs `glab release create`. No test checks that the stub log is empty for a dry run with a --release spec. C10 has no --release and C21 checks only the PLAN line.
- M15: the dry-run PLAN marking line printed for every forge, not only GitLab. No test.
- M18: unparsable JSON treated as marked. No test. The code itself is correct (it gives a FAIL).
- M19: GitHub title altered. This is the pre-existing GitHub leg, outside the scope of this change.
- M20: glab not authenticated turned into "CREATED". SKIPPED-NO-TOKEN has no test. This mapping predates the change.

Prerelease detection from the tag name is not a feature: prerelease comes only from the --prerelease flag, so a tag-name mutant is not applicable. The "wrong forge" class was covered by M15 and M19.

## 4. Findings

| Id | Severity | finding_layer | Finding |
|---|---|---|---|
| F1 | minor | source-defect | The read-back host is not pinned. `glab api` defaults to gitlab.com or to the authenticated host of the current git directory, and gets no `--hostname`. The create uses `-R OWNER/REPO`. These normally agree, but a self-hosted target would be read from the wrong host. The tag in the API path is not URL-encoded, which only matters for tags containing `/` or `+`. |
| F2 | minor | source-defect | If mktemp fails for GL_NOTES, `abort` runs after the pushes and prints "aborted before any write", which is false. Exit 1 is correct; the text is not. |
| F3 | minor | source-defect | The released_at value read back from the server is printed raw (unvalidated, and could contain a newline) and is never compared with the requested time. A kept upcoming release with a different date still passes. |
| F4 | minor | source-defect | A final (non --prerelease) run over an existing PROVISIONAL-marked GitLab release says "kept" and reports OK, with no notice that GitLab still shows PROVISIONAL. There is no promotion path, and the docs do not say so. |
| F5 | minor | source-defect | `--gitlab-released-at` with no gitlab spec is accepted silently and does nothing. The future check runs at argument-parse time, so a date that is near can be in the past by the time the release is created. That outcome is reported honestly as a GAP. |
| F6 | minor | source-defect | The date handling needs GNU `date -d`. On a BSD or macOS date every value is refused as "not a valid time" (§11.4.81). This fails safe. |
| F7 | minor | test-instrumentation | The survivors M03, M06, M11, M13, M15, M18 and M20 are uncovered paths. M11 and M18 are the fail-open read-back branches, and M13 is the dry-run no-write promise for release specs. |
| F8 | nit | process-doc | GL_MARK says "this line and the release title are its only marking". With `--released-at` there is also the upcoming badge. |
| F9 | nit | source-defect | GL_NOTES is created whenever --prerelease is given, even when no gitlab spec is requested. |

Trailers and identity: the author is Милош Васић <i@mvasic.ru>, matching the configured identity. `Roadmap-Item: CON-PENDING-GITLAB-PRERELEASE` is a placeholder, which is a lander item and not a defect. Co-Authored-By names Sonnet 5.5. The commit's claim of six killed mutants is consistent with my M01, M07, M05, M17, M14 and M12. No force-push: the C12 static check passes and no force flag was added. The tests write only to local bare repositories and stubs; no forge write occurs.

## 5. Re-application on fix227 (4c80482c; round 9 still in progress)

`git merge-tree` reports conflicts in all three files:
- tag_and_release.sh: 2 hunks, the usage/lockdown block and the gitlab case.
- README.md: 1 hunk, the table rows.
- test_tag_and_release.sh: 1 hunk, the appended tail.

The textual conflicts are easy to resolve. Keep fix227's lockdown block and awk-based `usage()`. Add `[--gitlab-released-at ISO8601]` to fix227's longer table row. Concatenate the test tails. The semantic conflicts are the real work (each classed important for the re-application change):
- S1, trap clobber: `trap 'rm -f -- "$NOTES" "$GL_NOTES"' EXIT` replaces fix227's `trap finish EXIT`. That loses the EXTERR redact-and-print step, the RUNDIR removal and the signal design. Use `GL_NOTES="$RUNDIR/glnotes"`, add it to `finish()`, and drop both the mktemp and the trap.
- S2, unbounded network call: `glab api` and every glab call must go through `nt` (fix227 wraps view, create and auth status). The new call has no timeout.
- S3, channel census: the new invocations must get rows in tests/release/channels.tsv: `glab api`, `python3`, `date` (twice), `grep -Eq`, `cut` (twice), `mktemp`, `cat`. Otherwise the census and L1 lint fail. `date` and `grep` in argument validation run after rc_env_clean, so the order is fine.
- S4, redaction: server-derived text (`${res}`, released_at) is printed without fix227's helpers (own1 / withheld / rc_redact_cut). Validate released_at against the ISO shape before printing, or print only fixed words.
- S5, environment: under rc_env_clean, glab sees only allow-listed variables. GITLAB_HOST and GLAB_CONFIG_DIR are on the list, so the host resolution of F1 keeps working. Passing `--hostname` explicitly is still the fix.
- S6, mutation catalogue: fix227's test_release_tooling_mutations.sh catalogue (round 7: 156 killed) has no GitLab pre-release mutants. Add the kill set above, and tests for the survivors.

Recommendation: re-apply by hand on the final fix227 head after round 9 is done, as a new commit (never a rebase of anything already pushed, §11.4.113). Then review it again.
