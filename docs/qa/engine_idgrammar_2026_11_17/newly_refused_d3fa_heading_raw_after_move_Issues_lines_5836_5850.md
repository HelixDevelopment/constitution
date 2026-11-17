- D3: tag_and_release.sh --dry-run returned before any platform check, so a would-be SKIPPED-NO-TOKEN, an inaccessible repository or a GitHub repository-id dedup appeared only in the real run, after the tags were pushed.
- D4: the dry-run plan lines of GitHub (and gitea) release legs did not say whether the pre-release flag is passed; only GitLab lines did.
- D5: render_release_entry.py refused TODO/TBD but accepted DRAFT, so an entry full of DRAFT values rendered with exit 0.
- D9: the template appended "." after the last ref of the unmerged-refs block, and the heading takes MANUAL:cut_date whole with no check that it is a bare date.
- D10: --remotes accepted two remotes that push to one repository (the live checkout's origin pushes to gitflic; the scratch clone's origin is the same GitHub repository as github), and a repeated remote name.
Acceptance (test-first, section 11.4.224): RED tests on the unfixed tools, then GREEN; paired mutants killed; a checker refuses every Ready-for-testing or In-testing item without a complete verification line, run on the real database; the six items carry complete lines written through the engine. Follow-ups of the same rehearsal: D1 (CON-379), D6 (CON-381, CON-382), D7, D8 and D11 (filed separately).

Related: CON-513 (D5, D9), CON-517 (D3, D4), CON-516 (D10 is a neighbour), CON-379 (D1), CON-381 and CON-382 (D6).

## Notes
more words here to pass the floor ok

