# Multiforge round 4: independent spot-check review

| Field | Value |
|---|---|
| Scope | Spot-check of the round-4 commit only (1243455c..380ad64a), under the operator's §11.4.276(E)(3) decision (spot-check, then land) |
| Reviewer | Independent subagent on Opus. The dispatch path did not report the effort level, so none is claimed. |
| Artifact | `mf_r4_bundle.6mLoJd/multiforge_r4.bundle`, sha256 7e966d6273d953774ea5969cd9d4e5230fcce7a58ab361ab26ccb3b928289c83 (checked). HEAD is 380ad64a. |
| Workspace | A fresh `--no-local` clone of `mf_r3.WCVq/constitution` with the bundle fetched into it, under `rev_mf_r4.N94d/`. `/home/milosvasic/Projects/constitution` was not touched. Nothing was written to a forge and nothing was pushed. |
| Verdict | **GO-with-follow-ups** |

## Runs (sequential, under nice 10, this session)

| Run | Result |
|---|---|
| credentials | 222 passed, 0 failed (41 s) |
| detect | 48 passed, 0 failed |
| gitea | 95 passed, 0 failed |
| gitflic | 28 passed, 0 failed |
| github_gitlab | 56 passed, 0 failed |
| gitverse | 62 passed, 0 failed |
| `shellcheck -x` on `scripts/forge`, `lib` and `tests/forge` | rc 0 |
| `scripts/run_full_suite.sh --verify-manifest` | MANIFEST-OK, census total 911 |
| The mutants I was asked to check (W01, W02, W03, W04, W05, W11, W12, W14, W15, W19), run through the commit's own harness with only these 10 kept | Baselines PASS (credentials, github_gitlab). 10 killed, 0 survived, 0 errors. |

Which test killed each mutant:

| Mutant | Killed by |
|---|---|
| W03 | Z5 (8-character token) |
| W04 | Z6 (8-character token, long notes) |
| W11 | Z6 (8-character token, long notes) |
| W15 | Z5 (8-character token) |
| W01 | U1 |
| W02 | U2 |
| W05 | Z5 (12-character token) |
| W12 | LP4 |
| W14 | L3d |
| W19 | U3 (line 2) |

U3 was RED before the fix, as the commit says: on 1243455c, `fg_scrub` of the three-line text returned only `first unsafe x` (lines 2 and 3 were lost).

## The m6 source change (`fg_scrub` scrubs a multi-line text line by line)

The text is split with `mapfile` and each line is scrubbed recursively. I ran these probes by hand:

| Probe | Result |
|---|---|
| Trailing newline | Kept |
| Leading and middle blank lines | Kept |
| A secret next to a tab or a dash | The whole word is replaced |
| CR at the end of a line | Handled |
| A line of more than 4096 bytes in a multi-line text (grep path) | Window piece scrubbed, `k=unsafe` |
| A multi-line text with no secret | Returned unchanged |

I found no leak. A window cannot span a line break, because a token does not contain a newline. Lines without a secret are printed exactly as they were. Lines with a secret have their runs of spaces collapsed. That behaviour existed before this change and drops no information that matters.

I wrote three reviewer mutants of `fg_scrub` and ran the credentials suite against each:

| Mutant | Change | Result |
|---|---|---|
| V1 | Each line is printed without being scrubbed | KILLED by U3 |
| V2 | Lines are joined with a space instead of a newline | **SURVIVED** |
| V3 | Blank lines are dropped | **SURVIVED** |

V2 and V3 do not leak anything. But they break the property m6 claims ("every line is kept"): U3 checks substrings, not the exact output, and its text has no blank line.

## Documentation (revision 4)

- The window boundary is stated correctly and consistently in the guide, the manual and the FAQ:
  - a value of 8 to 11 characters is matched whole;
  - otherwise, any contiguous piece of 12 or more characters is matched;
  - a token split into pieces shorter than 12 characters is not caught, and neither is an 11-character prefix (W18);
  - `live_probe.sh` has the same boundary.
- The claim "never the value" about the sanitiser has been removed. The one remaining "(never the value)" in the manual is about the hosts-map error message, which is a different and correct claim.
- Values shorter than 8 characters are covered by the placeholder rule in the guide.

## Findings

1. **MINOR, class test-instrumentation (§11.4.235(D)); does not block.** U3 does not pin the line structure, so V2 and V3 survive.
   - Fix direction: compare U3 with the exact expected text, newlines included. Add a blank line and a trailing newline to the input.
   - Track this as a follow-up item.
2. **NIT, class process-doc.** All three docs move "Last modified" backwards, from `23:30:00Z` (revision 3) to `17:49:00Z` (revision 4). The revision 3 time was probably set in the future. The lander should check the timestamp is correct and that it increases with each revision.
3. Already accepted, carried as before: the m7 manifest wording. The trailers, and the e-mail address in the commit body, are for the lander. Note that the commit trailer reads "Claude Sonnet 5.5"; the lander should check that the attribution is correct.

## Verdict

**GO-with-follow-ups.** The round-3 findings R3-I1, m2, m3, m5 and m6 are closed, each with a test that kills its mutant. The m6 change adds no leak and no over-scrub regression. The one new gap (finding 1) is a minor test-strength follow-up, and finding 2 is a documentation nit.

The scratch clone was removed after this review.
