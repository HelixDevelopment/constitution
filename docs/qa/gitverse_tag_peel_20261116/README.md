# GitVerse annotated-tag commit: live read-only reproduction and fix evidence (2026-11-16)

Item: CON-479 (placeholder id). Finding B-M6 / Q-4 of the helixconstitution-v73.4 release rehearsal:
`forge.sh release-ensure` on the GitVerse leg ended `RESULT: UNVERIFIED-COMMIT` (exit 5) for the existing tag
`helixconstitution-v73.3`. Every call below was a read: HTTP GET or `git ls-remote`. No release, tag, push or
setting was created or changed. The token was read by variable name (`GITVERSE_TOKEN`) and is in no file here
(scanned through a pipe before commit).

Root cause (FACT, verifier defect, not a mirror lag):
- `git ls-remote gitverse refs/tags/helixconstitution-v73.3*` gives tag object `e915eef7...` and peeled commit
  `aa5ae0a3...`, the same as the local tag (`lsremote_gitverse_v733.txt`). The mirror is current.
- `providers/gitverse.sh` read the annotated tag's commit only through `GET /git/tags/{sha}`, which GitVerse
  answers `400 VALIDATION_ERROR` (`repro_tag_get.txt`), so the commit stayed unverified and release-ensure
  ended exit 5 (`repro_release_ensure_dryrun.txt`).
- `GET /repos/{o}/{r}/commits/{tag-object-sha}`, the `object.url` that the matching-refs answer itself names,
  answers 200 with `sha` = `aa5ae0a3...` (`api_commits_tagobj.txt`); unknown objects answer 422.
  Other endpoints probed: `api_alt_endpoints.txt` (probe script: `gvprobe_script.txt`).

After the fix (`live_after_*.txt`): tag-get reports `sha=aa5ae0a3...`; the release-ensure dry-run ends
`RESULT: OK` (rc 0, `ACTION: would-create`); the control with a wrong `--sha` ends `FAIL tag_sha_mismatch` (rc 1).
`red_gitverse_suite.txt`: the new suite cases G1-G3 failing on the unfixed provider (gate-logic, fixture server).

Evidence class: the `live_*` / `repro_*` / `api_*` / `lsremote_*` files are LIVE reads of the real forge
(section 11.4.289); the suite file is gate-logic. The GitVerse write path (POST /releases) stays LIVE-UNPROVEN.

Gate-logic runs (fixture server): `mutations_summary.txt` (96 mutants, 96 killed; G01-G09 and adapted M17 target the fix), `suites_run1.txt` (six forge suites, 531 assertions, 0 failed) and `suites_repeat_hashes.txt` (three runs, identical sha256).
