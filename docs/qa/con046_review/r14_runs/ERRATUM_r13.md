# CON-046 round 14: erratum to the round-13 evidence (append-only)

Review r13 finding R13-8 asked for corrections to be appended rather than edited in place (§11.4.268). This round
follows that: no file under `r13_runs/` or an earlier `rN_runs/` is changed. Each correction below names the round-13
statement, what was wrong with it, and where the round-14 evidence is.

| # | Round-13 statement (where) | Correction | Round-14 evidence |
|---|---|---|---|
| E1 | AUTHCF / AUTHCO / AUTHCN prove the category-C check (`r13_runs/README.md` item 4) | They place the character inside the name, never at position 0 or at the end. The reviewer mutant RVR13-04 (`for c in a` becomes `for c in a[1:]`) survived and waived `<U+E000>release-mgr` (R13-1). | AUTHPOS14 fixtures (12 code points: Cc, Cf, Co, Cn, at the start, middle and end); `catpos/catpos_new.txt` (22 per-position and off-by-one variants, all killed by AUTHPOS14 alone; `a.strip()` is equivalent and proven) |
| E2 | The caseless skeleton refuses every confusable spelling of the producer (gate header, round 13) | `AIex` (capital I) is not refused for `Alex`: casefold makes `I` into `i` before the table can map it to `l`. 165 single-code-point skeleton classes were split by the caseless form alone (R13-2). | The case-preserving skeleton e is compared beside f (union); `caseconf14.txt` (0 split classes), `falseref14.txt` (+12 refusals of 38781 distinct name pairs, 0.0309%); fixtures CASE14, QNFD14, FTWIN14 |
| E3 | An authoriser whose skeleton is empty (267 non-C code points) is refused (gate header, round 13) | U+2800 BRAILLE PATTERN BLANK (So) renders blank but had a non-empty skeleton, so `milos` + U+2800 was waived and an authoriser of U+2800 alone was accepted (R13-3). | The gate maps U+2800 to nothing and refuses a whitespace-only skeleton; `catpos/blank_census.txt` (268 code points); fixture BRAILLE14. Other visible-blank glyphs are an OPEN operator question (gate header). |
| E4 | A HEAD that is not a commit is unborn, so the base is the empty tree (gate, round 13) | A HEAD detached at a missing object, or naming an existing ref that is not a commit, was treated as unborn (R13-4). | It is BLIND (rc 2) now; fixture UNBORNBAD14 (loose, packed, detached, tree) |
| E5 | `norm_census.py` covers every normalisation line (`r13_runs/`) | With the table missing it raised a traceback (rc 1) instead of reporting BLIND (R13-7). | `r14_runs/norm_census.py` exits 2 with BLIND; RED transcript of the round-13 copy kept beside it |
| E6 | Census needles of the git-env census (round 13) | No needle exercised `git merge x-base` (R13-6). | `census/` RED and GREEN transcripts |
| E7 | `g=k(map(k(s)))` with the outer NFD dropped is proven equal (`r13_runs/README.md` item 5) | Correct, but the outer k of the map line was not proven; it is now a recorded equivalence (`outer-k-dropped`, probe `pr_outerk14`, control = the RVR13-12 sed, which the probe kills). | test proof `outer-k-dropped` |
| E8 | The R12-4 fix edited round-11 text in place (round 13) | Acceptable per the reviewer, but not append-only. From round 14 on, corrections are made only through a file like this one. | this file |

Nothing in this file is a new finding: every row restates a review-r13 finding and points at its fix.
