#!/usr/bin/env python3
"""plan_struct_check.py - structural checks over research.md / plan.md / tasks.md and the
constitution landing (spec-004 "fast-dev-cycles", plan T-H08 / T-A11 re-run; contract
contracts/plan-research-structural-check.md; contracts/common-conventions.md C-001..C-004;
data-model.md #2 Root Cause, #14; FR-002, FR-003, FR-004, FR-019, FR-022; SC-001, SC-007, SC-008).

THIS FILE originally (T046) implemented ONLY the `causes` subcommand (SC-C-001, FR-002),
against research.md's own §2.1 register table + §2.2 register-counts table, per tasks.md's
T046 line: "Implement ... plan_struct_check.py causes per contract
plan-research-structural-check until T025 is GREEN (the research, plan, landing and rule-diff
subcommands land in T159 and T179)". T159 added the `landing` (SC-C-004, FR-019) and
`rule-diff` (SC-C-005, FR-022) subcommands, per plan.md's T-G01/T-G02. T179 (THIS commit) adds
the two remaining subcommands, `research` (SC-C-002, FR-003) and `plan` (SC-C-003, FR-004,
FR-002's post-T-A11 half), per contract plan-research-structural-check.md and RED test
test_plan_struct_full_red.sh (T178), until that RED test is GREEN.

Usage:   plan_struct_check.py causes --doc <research.md> --out <causes.json>
             [--post-a11] [--operator-causes O1,O2,...]
         plan_struct_check.py research --log <research.md> --plan <plan.md> --out <research.json>
         plan_struct_check.py plan --plan <plan.md> [--tasks <tasks.md>] --causes <causes.json>
             --out <plan.json>
         plan_struct_check.py landing --constitution <dir> --anchors <11.4.N[,11.4.M...]>
             --out <landing.json>
         plan_struct_check.py rule-diff --constitution <dir> --base <sha> --out <rule_diff.json>
             [--operator-decisions 11.4.N=DEC-ref[,11.4.M=DEC-ref...]]
         plan_struct_check.py triple --plan <plan.md> --tasks <tasks.md> --contracts <dir>
             --out <triple.json> [--root <dir>]

`research` (SC-C-002, FR-003, T178 fixtures 4/5): reads research.md's §3 decision log (every
`### DEC-NN` entry's own `- **Source:**` field, scanned by heading shape alone -- never assuming
a `## 3.` section wrapper, since a minimal fixture may omit one) and its §6 research-pass log
(every `| <digits> | ... |` row). Checks: (i) every decision genuinely REFERENCED as a "plan
recommendation" -- i.e. named in some `--plan` task's own `- **Origin:**` field, the operative
reading of the contract's "every PLAN recommendation cites a source" (a DEC- entry research.md
carries but no task ever adopted is not, on this reading, a "plan recommendation", and is
honestly left unchecked) -- must be CITED: see `is_cited`'s own docstring for the full, current
placeholder/circular-self-reference discrimination (review round 1, I1, expanded from the
original five-token exact-match-only set) -- `uncited_recommendation`; (ii) a plan `- **Origin:**`
field naming a DEC- id that does NOT exist anywhere in research.md's own decision log at all is
itself a violation (review round 1, I2) -- `dangling_decision_reference`, never silently ignored
just because the per-decision loop only ever iterates over decisions that genuinely exist; (iii)
when decisions genuinely exist but ZERO `- **Origin:**` fields anywhere reference ANY of them by
id (including a wholly EMPTY `--plan` document) -- review round 1, I2 -- the citation-quality
checks (i)/(ii) have literally nothing to examine, and this is honestly reported BLIND (exit 4),
never a false PASS; (iv) the pass log has >= 3 rows (FR-003's own floor) -- `insufficient_
research_passes`. NOT implemented (honestly disclosed, matching this file's established
convention for partial coverage -- see `causes`'s own docstring clauses (d)/(e)/(f) for
precedent): the SEVEN FR-003 topics each covered by >= 1 pass, and each pass's own queries/
sources/negative-findings/plan_changes fields (no T178 fixture exercises either); resolving/
verifying that a citation's TARGET genuinely exists (e.g. a real-but-external research-pass
reference like "R99:1-2" that was never actually logged) -- `is_cited` checks Source-field CONTENT
for non-emptiness/non-placeholder-shape/non-circularity, never whether the cited target itself is
real (review round 1, I1's own disclosed limitation).

`plan` (SC-C-003, FR-004, FR-002's post-T-A11 half, T178 fixtures 1/2/3/6/7): reads every
`#### T-<id>` task block in `--plan` (and `--tasks`, if given -- real tasks.md carries none of
its own, per its own different tracker-item format; `--tasks`'s real, verified role is only to
add its own word count into the size-floor check below, "plan + supporting documents", never to
supply additional task blocks), the optional `--spec` (spec.md, review round 1 B2/P7), and
`--causes` (the `causes` subcommand's own JSON output), and checks -- see `compute_plan_violations`
for the exact, current per-clause implementation and its own honest coverage disclosure -- (a)
every task's own `- **Rollback:**` / `- **Removes / measures:**` / `- **Serves:**` / `- **Expected
saving...:**` / `- **Protecting tests:**` fields are present with non-blank content, PLUS every
RC- id a Removes/measures field names is cross-checked against the real cause universe
(`--causes`'s own `id` values), and a non-blank Removes/measures field naming NO `RC-...` id at
all is flagged too (review round 2, Minor-7) -- `no_rollback` / `no_removes_cause` /
`removes_cause_names_no_id` / `removes_cause_unknown_id` / `no_serves_field` /
`no_expected_saving` / `no_protecting_tests`; (b) bipartite orphan-cause: every
cause in `--causes` whose class is CONFIRMED or UNDETERMINED genuinely appears, by id, in SOME
task's own `- **Removes / measures:**` field text -- deeper than `causes`'s own register-level-only
clause (b), which only checks `causes.json`'s `removed_or_measured_by` cell is non-blank, never
that the NAMED task's own text actually mentions the cause -- `orphan_cause`; (c) bipartite
orphan-requirement, THREE independent discovery paths (review round 1, B2/P7 added the third),
each firing only on its own structural signal (never guessed where absent, constitution 11.4.6):
PATH 1 reads an existing `| Requirement | Tasks |`-headed table (real plan.md's own "Traceability
matrices" -> "Requirements -> tasks" section, generated by a separate mechanism this file only
VERIFIES, never regenerates) and flags any row whose Tasks cell is blank, placeholder-shaped
(review round 1, I4), or names only a task that either does not exist or does not genuinely Serve
the row (review round 1, I4 -- see `_row_is_covered`); a row-shaped-but-unparseable table line
(review round 1, I4 -- bold-wrapped/comma-joined cells are now correctly parsed instead, see
`parse_requirements_table`) is reported as `table_row_unparseable`, never silently skipped or
mistaken for the table's own end; PATH 2 reads a line matching `**Scope...**: implements <ID
list>` (the shape a minimal fixture with no traceability table uses to declare its own covered-id
universe) and cross-checks each declared id against every task's own `- **Serves:**` field text;
PATH 3 (review round 1, B2/P7, opt-in via `--spec`) cross-checks every FR-/SC- id spec.md ITSELF
DEFINES (its own `- **FR-NNN**:`/`- **SC-NNN**:` bold-header lines) against every task's own
`- **Serves:**` field text, independent of whichever subset the PLAN document happens to declare
covering -- omitted by default (never silently assumed satisfied), matching `causes`'s own
`--post-a11`/`--operator-causes` convention. Path 2's trigger phrase is DELIBERATELY narrow --
anchored to a leading `**Scope...**:` label, never a bare `implements` substring scan -- because a
bare scan over `--tasks` genuinely false-positives on this project's own real evidence prose
("Implements `put`/`get`/`check-duplicate` ...", tasks.md T068/T073/T080), confirmed live before
choosing this design (constitution 11.4.201(7)(a): match structure, not substring) --
`orphan_requirement`; (d) size floor: `len(text.split())` over `--plan` plus `--tasks` (when
given) is >= 15000 (30 pages-equivalent * 500 words/page, per the contract's own arithmetic) --
`below_size_threshold`; (e) FR-002's post-T-A11 half: for every CONFIRMED cause in `--causes`
whose `measured_share` is blank or matches `_UNMEASURED_RE`, a violation UNLESS THAT SPECIFIC
cause has its OWN genuine, explicitly-linked permanent-gap marker line anywhere in the combined
`--plan`/`--tasks` text -- `permanent gap: RC-<id> -- <reason>` (see `permanent_gap_cause_ids`'s
own header comment for the full review round 1 (B1) rationale and the concrete false-excuse/
false-positive reproductions this scoping fixes) -- `confirmed_unmeasured_no_permanent_gap`. A
`measured_share` that is present but NOT a string (e.g. a JSON number) is reported as its own
named `measured_share_not_string` finding rather than crashing (review round 1, M3). Unlike
`causes`'s own `--post-a11` OPT-IN flag for this same contract clause, `plan`'s version of this
check is always active (no flag) -- tasks.md's own T179 line assigns "checks every CONFIRMED
share" to this task, and T178's own fixture 7 invokes `plan` with no such flag at all; this means
`plan` against the REAL, live Phase-0 documents (T-A11 has not yet run, and the live plan.md's own
mentions of the phrase "permanent gap" are all rule-description PROSE, never a genuine per-cause
marker for any of the 27 real CONFIRMED-but-UNMEASURED rows -- confirmed live, never guessed)
NOW genuinely reports 27 `confirmed_unmeasured_no_permanent_gap` findings (rc=1) -- an HONEST,
accurate result the review round 1 (B1) fix correctly surfaces (the pre-fix document-wide bare-
phrase match happened to silently excuse all 27 at once by matching that same rule-description
prose instead of a genuine per-cause note; see `test_plan_struct_full_red.sh`'s own negative-
control section 9 for the full, verified rationale). Fixing the real corpus itself (adding real
per-cause markers, or running T-A11) is OUT OF SCOPE for this file.

REVIEW ROUND 1 REMEDIATION (2026-10-01, independent §11.4.209 Opus-xhigh review of T179's initial
landing): B1 (permanent-gap scoping, above) + B2 (removes_cause/no_serves_field/spec-fixed-set
coverage, above) + I1 (`is_cited`'s expanded placeholder vocabulary + circular-self-reference
detection) + I2 (`research`'s dangling-decision-reference detection + honest BLIND-on-nothing-
referenced) + I3 (`compute_plan_violations` restructuring so `self_check_plan` exercises the REAL
production violation-generating code path, never a parallel reimplementation) + I4
(`parse_requirements_table`'s bold/comma-joined-cell parsing + never-silently-skip-a-malformed-row
+ task-existence-and-Serves verification, above) + M3 (non-string `measured_share` type-safety) +
M4 (`_read_doc`'s error message now names the ACTUAL failing flag) all fixed and independently
re-proven; M1 (orphan-cause matching edge cases: hyphen-adjacent ids, negated mentions, range
notation) and M2 (regex-widening false negatives on compound identifiers / en-dash ranges) are
HONESTLY DISCLOSED, NOT implemented in this round (judgment call, constitution 11.4.6 -- no
concrete reproduction was given for either and both are lower-severity than the fixed items); the
CT-5 self-validation-triple check named by tasks.md's own T179 line (every ANALYZER task's own
golden-good/golden-bad/negative-control triple) is ALSO honestly disclosed as NOT implemented --
it is a substantially larger, separate feature (a whole-plan scan identifying which tasks are
"analyzer" tasks and verifying each ships its own full triple) genuinely out of scope for a
review-remediation round, matching this file's own established convention (see clauses (d)/(e)/(f)
below for `causes`'s own precedent of disclosing partial coverage rather than silently claiming
more than is implemented).

*** KNOWN, TRACKED GAP -- CT-5 IS NOT YET BUILT (review round 2, per that round's own reviewer's
explicit note: "T179 cannot be closed as fully done without CT-5; it needs a tracked item." --
review round 3, M-6: that tracked item now genuinely EXISTS, ATM-1109, filed via this project's own
canonical `constitution/scripts/workable-items/bin/workable-items add` mechanism, §11.4.93 DB +
Issues.md/Issues.html/Issues.pdf/Issues.docx all confirmed in sync via `workable-items diff`) ***
Tasks.md's own T179 line NAMES CT-5 (the ANALYZER-task golden-good/golden-bad/negative-control
self-validation-triple check) as part of THIS task's own scope -- it is not an optional nicety
this file is choosing to skip, it is a REQUIREMENT this file's own governing task text sets that
remains, honestly, wholly unimplemented across all THREE review rounds so far. Until CT-5 lands
(identifying which task blocks in `--plan`/`--tasks` are "analyzer" tasks and verifying each one
genuinely ships its own golden-good/golden-bad/negative-control triple), T179 MUST NOT be reported
or tracked as fully, completely done -- ATM-1109 (see immediately above) is the SEPARATE, later,
dedicated tracked item required to design and land CT-5 before T179's own governing task line is
genuinely satisfied in full (constitution 11.4.197: a started requirement is never silently left
un-wired in the backlog).

REVIEW ROUND 2 REMEDIATION (2026-10-01, independent §11.4.209 Opus-xhigh review round 2 of T179's
review-round-1 landing, SCOPED to `research`/`plan` only -- `landing`/`rule-diff` are T159's own
separate, concurrent review scope): I-A (`self_check_plan`'s own self-check gained a genuine
`orphan_cause` positive/negative needle across CONFIRMED/UNDETERMINED/REFUTED classes, a
`removes_cause_unknown_id` negative control for a KNOWN-good cause id, and direct-call needles for
`below_size_threshold`'s both polarities -- all four of the round-1 reviewer's own concrete
mutations that previously survived the self-check untouched are now caught) + I-B
(`test_plan_struct_full_red.sh`'s negative control against the real, live corpus now accepts
EITHER rc=0, a corpus that has become genuinely clean, OR rc=1 with ONLY
`confirmed_unmeasured_no_permanent_gap` findings, rather than assuming the corpus stays "dirty"
forever) + I-C (`_is_placeholder_text`/`is_cited` gained a genuine MINIMUM-CONTENT FLOOR --
`_has_real_content` -- closing the whole class of trivially-short-or-filler-only Source text at
once, plus applying that SAME discrimination to a circular self-reference's own residual text --
FIXED in round 2, but, per review round 3's own finding I-1, NOT independently re-proven by ANY
self-check needle until round 3: see REVIEW ROUND 3 REMEDIATION below for the actual re-proof) +
Borderline-Important (`parse_requirements_table`'s header/row shapes are now tolerant of an EXTRA
trailing table column, and the scan no longer stops at the first table's own end -- a SECOND
"| Requirement | Tasks |"-headed table later in the same document is now discovered too) + Minor-1
(the genuinely DEAD, mutation-proven-inert first copy of `_normalized_core`/`_is_placeholder_text`/
`_PLACEHOLDER_CORE_EXACT`/`_PLACEHOLDER_CORE_PREFIX` is removed) + Minor-7 (a Removes/measures
field that is non-blank but names NO `RC-...` id at all is now its own `removes_cause_names_no_id`
finding) all fixed; I-A/I-B/Borderline-Important/Minor-1/Minor-7 independently re-proven in round 2
ITSELF (I-C's own fix landed in round 2 but its re-proof did not -- see immediately above). Minor-2
(dangling/negated/unspaced gap-marker edge cases), Minor-3 (BLIND-on-zero-decisions regardless of
pass-row count), Minor-4 (`count_research_passes`'s scoping to the real §6 section only), Minor-5
(the generic id-cell scan's false positives on shapes like "UTF-8" or inside an HTML comment), and
Minor-6 (hyphen-as-word-boundary in the Serves-field coverage check) are HONESTLY DISCLOSED, NOT
fixed in this round (judgment call, constitution 11.4.6 -- none is a false-positive-on-real-data
regression the way I-A/I-B/I-C/Borderline are, and the reviewer's own review explicitly flagged
only Minor-1 and Minor-7 as "please fix"); CT-5 (see the standalone disclosure immediately above)
remains explicitly out of scope for this round and tracked as owed, separate work.

REVIEW ROUND 3 REMEDIATION (2026-10-01, independent §11.4.209 Opus-xhigh review round 3 of T179's
review-round-2 landing, SCOPED to `research`/`plan` only, same scoping convention as round 2 above):
I-1 (the round-2 I-C fix above had ZERO regression protection -- THREE of the round-3 reviewer's
own concrete mutations, `_is_placeholder_text`'s body replaced with a bare `return False`, `is_
cited`'s circular-residual check `if not residual or _is_placeholder_text(residual):` weakened to
`if not residual:`, and dropping "SEE" from `_FILLER_WORDS`, ALL previously survived `self_check_
research()` AND the full RED-test suite untouched -- `self_check_research` now independently
re-proves EVERY ONE of round 2's own 12 non-citation reproductions directly against `is_cited()`,
PLUS the "see DEC-01" circular-self-reference needle and its "see DEC-01 and R3:12-14" positive
control, closing all three mutations) + I-2 (`compute_plan_violations`'s per-cause permanent-gap
logic is restructured from the original fragile `(not raw_share) or bool(_UNMEASURED_RE.match(raw_
share))` one-line expression -- whose correctness for `None`/`""` depended entirely on Python's
left-to-right `or` short-circuit ordering never evaluating the regex match against a non-string
value -- into one explicit, named branch that treats `None`/`""`/whitespace-only alike as
"unmeasured", PLUS direct-call needles pinning the real 30.0-page-equivalent THRESHOLD VALUE and
the `<`-not-`<=` BOUNDARY OPERATOR, neither of which had any needle before round 3) + I-3
(`_FILLER_WORDS` gains 14 further concrete near-equivalent placeholder words -- "DO"/"TODOS"/
"CITATION"/"NEEDED"/"NO"/"SOURCE"/"MISSING"/"NOT"/"YET"/"REF"/"PER"/"T"/"B"/"D" -- a generalised
repeated-"X" token check, and a small, deliberately narrow Cyrillic/Latin homoglyph-normalization
table (`_normalize_homoglyphs`), PLUS `is_cited`'s circularity check generalised from "names its own
id EXACTLY ONCE" to "every DEC- id token named is the SAME one id" -- closing "ref DEC-01"/
"per DEC-01"/"DEC-01 DEC-01"; the module's own `_is_placeholder_text` docstring HONESTLY discloses
the near-equivalents this bounded expansion still does NOT catch) + M-1 (`_TABLE_SEP_ROW_RE` widened
to accept the standard GFM column-alignment separator syntax, ":---"/"---:"/":---:" , which the
original `[-` + whitespace + `|]` character class rejected as `table_row_unparseable` on a well-formed
document) + M-3 (`self_check_research`'s own dangling-decision-reference detection is restructured,
via a NEW shared `compute_research_violations` function, to exercise the SAME production code path
`cmd_research` itself calls -- exactly mirroring the `compute_plan_violations`/`self_check_plan`
restructuring review round 1 (I3) already applied to `plan` -- rather than a parallel
reimplementation that could silently drift out of sync with it) + M-5 (a whitespace-only
`measured_share` is now also treated as "unmeasured", alongside I-2's fix) + M-7 (`cmd_plan`'s own
cross-document plan-vs-tasks traceability-table merge is changed from first-occurrence-wins
(`setdefault`) to last-occurrence-wins, aligning it with `parse_requirements_table`'s own documented
single-document multi-table merge convention -- see that function's own docstring) all fixed and
independently re-proven. M-6 (CT-5, see the standalone disclosure above, now has a genuine tracked
item, ATM-1109) is done. M-2 (several requirement-table header variants -- reversed columns, a
leading "#" column, "Requirement ID" instead of "Requirement", a bold header, an indented table --
remain silently invisible with no diagnostic) and M-4 (the `rc=0` "clean" branch of the I-B
negative-control fix has no independent cross-check that the live corpus genuinely has zero
CONFIRMED+UNMEASURED-without-gap-marker rows, as opposed to some other bug suppressing the finding)
are HONESTLY DISCLOSED, NOT fixed in this round (judgment call, constitution 11.4.6 -- the reviewer
itself flagged both as "use your judgment given remaining time", lower priority than the mandatory
I-1/I-2/I-3/M-1/M-3/M-6 findings this round prioritised).

FIX ROUND 4 (2026-10-01, independent §11.4.209 Opus-xhigh review round 4 of T179's review-round-3
landing, SCOPED to `research`/`plan` only, same scoping convention as rounds 2/3 above): IMP-1
(`insufficient_research_passes`'s own `pass_count < 3` threshold gains direct-call boundary needles
at pass_count=3/2 -- neither the real corpus, whose pass count is always far from 3, nor the
fixture's own always-exactly-2 pass count, ever exercised the boundary itself, so a mutated `< 3`
-> `< 4`, or `<` -> `<=`, previously survived untouched) + IMP-2 (the words-to-pages-equivalent
CONVERSION -- previously computed independently, via the SAME literal `words / 500.0` expression,
in BOTH `cmd_plan` and `self_check_plan`'s own fixture setup -- is centralised into one shared
`_words_to_pages_equivalent` function both callers now use, closing the "parallel reimplementation
of the CONVERSION step" gap the comparison step itself already closed in review round 1 (I3); gains
its own direct WORD-count boundary needles at 14999/15000 words, through the shared function, since
the existing pages_equivalent-level needles bypass the conversion entirely) + IMP-3 (`_has_real_
content`'s minimum-content floor closes THREE further bypass classes: (1) hyphen/underscore-JOINED
filler words, e.g. "to-be-determined"/"citation-needed"/"fill_in_later"/"none-yet"/"not-yet"/
"no-source", which previously concatenated into one alphanumeric blob that trivially cleared the
length floor -- see `_is_all_filler_compound`'s own docstring; (2) the circular-self-reference id
match (`is_cited`, clause (3)) is now case-INSENSITIVE via a new `_DEC_ID_RE_CI` sibling regex,
scoped to exactly that check, so "see dec-01" (lowercase) on DEC-01's own field is now caught
exactly as its uppercase spelling already was; (3) "CF"/"VIA"/"VIDE"/"QV" join the already-listed
"REF"/"PER" "see"-synonym filler words, closing "cf. DEC-01"/"via DEC-01" as circular self-
references; PLUS the absolute minimum content floor is raised to structurally exclude a bare
non-digit 2-character word ("ok") while still admitting a genuine compact letter+digit reference
("R1") on the SAME footing as an ordinary length->=3 token -- see `_has_real_content`'s own
docstring for the exact floor rules -- and a genuine section/paragraph-reference mark ("§"/"¶") is
now recognised as real content on its own, fixing a genuine REGRESSION the round-3 REF/PER additions
introduced: "per §3"/"ref §2"/"see §4" had silently become UNCITED once "per"/"ref"/"see" became
filler words, since "§" carries no alphanumeric character for the length floor to count) all fixed
and independently re-proven (`self_check_research`/`self_check_plan` gain direct needles for every
one of the reviewer's own concrete reproductions, PLUS this round's own additional adversarial
variations tried beyond those exact reproductions, PLUS positive controls proving "R1"/"RFC" and
"per §3"/"ref §2"/"see §4" all still survive as genuinely cited). Minor-1 (T/B/D individual-letter
needles), Minor-3 (`cmd_plan`'s own plan-vs-tasks traceability-table merge, extracted into a new
shared `_merge_req_tables` function, changed from last-occurrence-wins to either-document-orphan-
wins, the conservative direction), Minor-4 (`parse_requirements_table`'s
separator-row match now strips the line before matching, closing the trailing-whitespace/leading-
indentation gap M-1 (round 3) left), and Minor-5 (`measured_share`'s unmeasured check now strips the
raw value before matching `_UNMEASURED_RE`, AND treats a value satisfying `_is_placeholder_text` as
unmeasured too, reusing that existing helper) all fixed and independently re-proven. The remaining
overclaiming "closes the whole class"/"closes the entire class" language this round's own reviewer
flagged is replaced with accurate, bounded language throughout `is_cited`/`_FILLER_WORDS`/`_has_
real_content`/`_is_placeholder_text`'s own docstrings, each now naming its own currently-known
residual gaps rather than claiming exhaustive coverage.

`landing` (SC-C-004, FR-019, plan T-G01/T-G02): for each anchor named in `--anchors`, extracts
that anchor's own block (a line-anchored `**§11.4.N -- ` bold-paragraph or `### §11.4.N` H3
heading -- see `_ANCHOR_BLOCK_START_RE`'s own header for the measured, review-round-1-remediated
(B1) discrimination against mid-body citation bullets and sub-clause/topic paragraphs naming
another anchor from inside a DIFFERENT anchor's own body; used here for block BOUNDARY extraction
only -- never for the correctness DECISION itself) out of `<constitution>/Constitution.md`, then
checks two things, BOTH via the EXISTING mechanisms this contract clause names ("the existing
propagation and block-integrity checks are invoked, not reimplemented") -- never a hand-rolled
re-derivation of either:
  (i)  every `CM-*` gate token named inside that anchor's own block is IMPLEMENTED or DEFERRED
       per the real, already-shipped `constitution/scripts/gates/gate_ledger.sh generate`
       (§11.4.227(A)) run against the REAL implementation tree (`<constitution>/scripts`) and
       the REAL checked-in deferrals registry
       (`<constitution>/scripts/gates/gate_ledger_deferrals.tsv`) -- an UNIMPLEMENTED token is a
       violation naming the anchor and the gate;
  (ii) when that anchor has a REGISTERED `CM-COVENANT-114-<N>-PROPAGATION` wrapper in
       `<constitution>/scripts/gates/covenant_propagation_anchors.tsv`, that wrapper is invoked
       directly (`cm_covenant_114_<N>_propagation.sh --root <consumer-root> --quiet`) and a
       non-zero exit is a violation -- this genuinely reuses the SAME §11.4.227(B) block-start /
       exactly-once / lockstep-content-hash-equality engine every other anchor's propagation
       gate already uses, rather than re-deriving mirror discovery or hashing here. An anchor
       with NO registered wrapper (a brand-new anchor not yet run through
       `covenant_propagation_wrappers_generate.sh`) is a REAL, REPORTED violation --
       `propagation_gate_not_registered` (review round 1, B3) -- never a silent PASS: an anchor
       this check has never actually run a propagation gate against MUST NOT be able to exit 0
       purely because nothing was wired for it yet (constitution 11.4.6: an absent check is not
       evidence of compliance; a false PASS here is exactly as forbidden as a false FAIL,
       constitution 11.4.201(1)). If EVERY violation found across the whole `--anchors` request is
       a propagation wrapper that could not be RUN AT ALL (`propagation_gate_blind` -- its own
       process failed/timed out, this tool's own instrument observed nothing decided), the overall
       verdict is honestly BLIND (exit 4, `--out` still written with `BLIND: true` per
       `fc_common.cmd_emit`'s own convention) rather than folded into a generic FAIL (exit 1) --
       any OTHER, actually-decided violation code present alongside a blind one still exits 1 (a
       real finding is never swallowed by a blind one).

`rule-diff` (SC-C-005, FR-022, plan T-G01): reads `<constitution>/Constitution.md` at `--base
<sha>` (via `git show <sha>:Constitution.md`, run inside `<constitution>`) as "before" and the
CURRENT on-disk `<constitution>/Constitution.md` as "after"; for every anchor number present in
BOTH texts whose block body differs, classifies the change via `classify_diff()` (see its own
docstring for the exact STRUCTURAL/ADDITIVE/SUBSTANTIVE/UNCHANGED discipline and its honestly
disclosed limits): `SUBSTANTIVE` (an existing line's wording was removed/reworded, ignoring
pure-whitespace differences), `STRUCTURAL` (every difference between before/after is
whitespace-only -- trailing/internal-whitespace reflow with byte-identical content once
normalized; heading-reformatting and line-MOVE detection are honestly NOT implemented, review
round-1 (I3) narrows this from the original "not implemented at all" disclosure to exactly this
whitespace-only slice), `ADDITIVE` (only new material inserted, nothing existing removed or
reworded -- see `classify_diff()`'s own docstring for why an ADDITIVE verdict still warrants
review: it is a purely STRUCTURAL/opcode-based classification that cannot detect a semantic
override embedded in the NEW text), or `UNCHANGED` (identical bodies; not reported as a hunk at
all). A `SUBSTANTIVE` hunk is a violation UNLESS its anchor is named in the `--operator-decisions`
list, which (review round-1, I4) takes `<anchor>=<decision-record-reference>` pairs -- a bare
anchor number with no referenced decision record is a usage error (exit 2), never silently
accepted -- and every exempted hunk's own JSON entry carries the `exempted` field naming the
decision reference used (a non-exempted hunk carries `"exempted": null`), so the audit trail is
always inspectable in `--out`, never merely implied by the hunk's absence from `violations`. An
anchor present only in "after" (brand new) is reported informationally in `new_anchors` and never
classified/gated. An anchor present only in "before" (REMOVED, or renumbered -- which this
set-difference sees as remove+new) is, per review round-1 (B2), a REAL violation --
`anchor_removed` -- exactly like a SUBSTANTIVE hunk (FR-022's own words, "MUST NOT change the
substance of an existing rule": deleting the WHOLE anchor is the most substantive possible change
to it), UNLESS ITS anchor is likewise named in `--operator-decisions`; each `removed_anchors`
entry is an object `{"anchor": ..., "exempted": <decision-record-reference-or-null>}`, the same
audit-trail shape as a `hunks` entry.

REVIEW ROUND 3 REMEDIATION (NB1, independent §11.4.209 Opus-xhigh review round 2): anchor keys
are now the anchor's FULL DOTTED identifier (e.g. "10.A" for the real §11.4.10.A, genuinely
distinct from its own parent "10" -- see `_ANCHOR_BLOCK_START_RE`'s own header), and every
GENUINE occurrence of a shared key is compared by index, not merely the first -- so a change to
(or deletion of) a SECOND real occurrence of the same anchor number is no longer invisible. A
CHANGE IN THE NUMBER OF OCCURRENCES itself (a duplicate block appearing or disappearing) is its
own violation, `anchor_occurrence_count_changed`, carrying `before_count`/`after_count` and
exempt-able via the SAME `--operator-decisions` mechanism; a hunk/violation for a NON-first
occurrence additionally carries an `occurrence` (0-indexed) field -- omitted entirely on the
ordinary, overwhelmingly common single-occurrence-on-both-sides case, so this remediation adds no
new field to any already-passing single-occurrence assertion.

FIX ROUND 4 (independent §11.4.209 Opus-xhigh review round 4): (I-R4-1) every occurrence-count
change is now recorded in a dedicated `occurrence_count_changes` list -- `{"anchor",
"before_count", "after_count", "removed_occurrences", "added_occurrences", "exempted":
<decision-record-reference-or-null>}`, the same audit-trail shape as `removed_anchors` -- whether
or not it is exempted (an exempted one was previously discarded with no trace at all); (M-R4-1)
occurrences are paired BY CONTENT (difflib over the occurrence bodies), never by raw index, so an
untouched occurrence is never mis-reported because a sibling occurrence was added/removed, and a
hunk's `occurrence` is the AFTER-side index; (I-R4-2 / I-R4-3) `classify_diff()` was redesigned
from whole-paragraph flattening to a LOGICAL-UNIT model (list items, table rows, headings, fence
and code lines, prose runs -- nesting depth / code indent part of each unit's identity), see its
own docstring; (M-R4-2) `### §11.4.10A` letter-suffix headings are keyed as their own anchor and
an H3 sub-clause heading `### §11.4.N(X) ...` is neither a block-start nor a boundary; (M-R4-3)
`landing` extracts gate tokens from EVERY occurrence of a duplicated anchor.

FIX ROUND 5 (independent §11.4.209 Opus-xhigh review round 5 -- the FINAL fix round at this tier):
(I-R5-1) the corpus's own anchor-separator convention (101 of the real Constitution.md's 269
anchor blocks end in a standalone `---`) made the SINGLE most common real edit -- a new anchor
inserted just before an existing anchor's trailing `---` -- falsely SUBSTANTIVE on the untouched
existing anchor (real repro: commit 91aa99d, which only appends §11.4.192, reported
substantive_change on §11.4.191). FIXED two ways: parse_anchor_blocks() strips each block's
trailing blank lines plus ONE genuine trailing thematic-break separator
(_strip_trailing_separator()), and _logical_units() treats a thematic break anywhere as block
punctuation, never a unit. MEASURED (same instrument, before/after, per-commit worst verdict
over every shared anchor occurrence, the last 150 commits touching Constitution.md): SUBSTANTIVE
74 -> 28, UNCHANGED 62 -> 109, ADDITIVE 14 -> 13; the 28 survivors were spot-checked and are
genuine rewordings or the already-disclosed conservative cases (mid-unit insertion, heading-format
change). (I-R5-2) blockquote content is de-quoted and parsed by the same unit rules (quote depth
part of each unit's identity), closing the within-blockquote whole-paragraph-flattening gap -- a
FALSE-PASS-capable gap, latent on today's corpus. (M-R5-1) a multi-line HTML comment wrapping an
existing rule marks that rule hidden, so the wrap is SUBSTANTIVE, not two pure inserts. (M-R5-2)
duplicate occurrences are paired exact-multiset-first, then by greatest content similarity
(_pair_occurrences()), fixing the reorder-plus-change mis-attribution. (M-R5-3) a setext
underline directly under a paragraph turns it into a heading (SUBSTANTIVE); the unfenced
4-space-indented code block half of M-R5-3 is NOT fixed and is disclosed in classify_diff()'s
docstring as boundary (5), a latent false-PASS-capable gap with zero real-corpus instances today.

NI1 HONEST BOUNDARY (constitution 11.4.6, review round 3): BOTH `landing` and `rule-diff` are
SCOPED, TODAY, to `§11.4.N`-numbered anchors ONLY (the `_ANCHOR_BLOCK_START_RE` block-start
forms) -- `§1` through `§10` (INCLUDING `§9.2`'s own force-push-authorization language), the
`§11.4` preamble text itself, and `§12` onward are NOT currently monitored for substantive
changes by either subcommand. A rewording of, say, `§9.2`'s "MUST be authorized" to "MAY be
skipped" is invisible to `rule-diff` today -- this is a KNOWN, DELIBERATELY DISCLOSED gap, not a
silent one, tracked as a follow-up widening of `_ANCHOR_BLOCK_START_RE`'s own coverage rather than
guessed at or silently assumed closed.

Exit codes (contract "Exit codes" table): 0 all checks pass; 1 any structural violation
(listing each, by RC id, CLASS:stated=N,actual=M, or a `malformed_row` finding naming the row's
best-effort-recovered id or its raw line number + text -- see "Row parsing" below); 2 usage
error; 3 needle (this tool's OWN orphan-cause detector, run against a synthetic in-memory
fixture BEFORE --doc is ever read, did not behave as expected -- no honest verdict on the real
--doc is possible until the detector itself is proven -- constitution 11.4.201/11.4.273; nothing
is written); 4 document unreadable (--doc cannot be opened/decoded, OR it decodes but contains
ZERO lines starting with `| RC-` at all -- a line that starts with `| RC-` but fails to split
into a genuine data row still counts as "a row was found": it is reported as a `malformed_row`
structural violation under exit 1, never folded into this BLIND case. Only the true
zero-`| RC-`-lines-anywhere case is treated the same as anchor_citations.py's "--anchor-index has
zero parseable entries" case: a document with no honest register to check is BLIND, not a silent
0-violation pass -- nothing is written).

Row parsing (§2.1 Register table): a data row is any line starting with "| RC-" whose "|"-split
has exactly 11 parts (9 data cells plus the two empty strings either side of the leading/
trailing "|") -- this is the SAME column shape research.md's own real 9-column table uses today
(RC | Cause | Origin | Class | Measured magnitude | Share of total cycle | Evidence | Settling
evidence / what remains | Removed / measured by), and the SAME shape/index convention as this
task's own RED test (T025, test_plan_struct_causes_red.sh)'s independent `register_audit` Python
instrument -- re-implemented here independently (Producer != Verifier, constitution 11.4.240:
the RED test's audit function validates the FIXTURES encode their designed defects; this tool is
the thing under test, and reuses none of that instrument's code, only the same column contract).
Class cells are read via the first `**BOLD**` token (`^\\*\\*([A-Z]+)\\*\\*`) -- a row's real class
is its FIRST-stated verdict even when the cell carries a split verdict such as
"**CONFIRMED** (mechanism) / rate UNDETERMINED" (research.md's own §2.2 stated convention for
RC-22/RC-23, confirmed against the live document 2026-09-28).

A `| RC-` line whose "|"-split does NOT yield exactly 11 parts (most realistically: an unescaped
"|" inside a free-text Cause/Evidence/Settling cell, shifting every later column) is NEVER
silently skipped without a trace. It is reported as violation code `malformed_row`, naming the
row's best-effort-recovered RC id (via a regex anchored on the same "| RC-" precondition this
loop already requires -- in practice always recoverable, since the id token itself precedes
whatever later "|" made the split malformed) or, on the defensive fallback path, the raw
1-indexed line number + line text; the row is excluded from `rows`/`causes` either way. A
malformed row that vanished silently instead would defeat clauses (a) class-membership,
(b) orphan-cause, and (c) count-equality simultaneously: it is counted toward none of them, and a
§2.2 total that happens to already match the post-drop tally would then report a clean
0-violation pass over a register that was never fully audited -- exactly the class of silent
failure path indistinguishable from genuinely-nothing-found that constitution 11.4.201/11.4.273
treat as a release-blocking defect regardless of how green the exit code looks.

Contract-clause coverage in THIS implementation (honest boundary, constitution 11.4.6 -- every
gap named explicitly, never silently assumed covered):
  (a) class membership (class in {CONFIRMED, REFUTED, UNDETERMINED})     -- FULL. A blank Class
      cell, or one whose first bold token is not one of the three, is a violation naming the row.
  (b) orphan cause (no task in "Removed / measured by")                 -- FULL, register-level
      only (research.md's own §2 preamble: "no orphan cause ... checked mechanically by T-H08").
      This is the SHALLOWER check the RED test's own header explicitly distinguishes from
      SC-C-003's deeper bipartite cross-check against plan.md's real task blocks (a separate,
      later subcommand's job -- `plan`, T159/T179) -- this file does NOT read plan.md at all.
  (c) class counts equal research.md §2.2                                -- FULL. An independent
      re-tally over every row's first-bold-token class is compared against §2.2's own stated
      per-class "Rows" figure; a class named in the doc's own list with no §2.2 entry is silently
      skipped from the comparison (nothing to disagree with), matching the RED test's own
      register_audit instrument's identical behaviour for cross-fixture consistency.
  (d) settling_evidence required for UNDETERMINED                       -- PARTIAL. Implemented
      as a direct, low-risk reading of the contract's own words ("settling_evidence required for
      UNDETERMINED") against research.md's real "Settling evidence / what remains" column
      (non-blank required for every UNDETERMINED row); verified by hand against all four T025
      fixtures + the live document (every UNDETERMINED row in all five documents already carries
      non-blank text there) -- no DEDICATED RED fixture exists for this clause yet
      (`sc_bad_undetermined_no_settling` is named in the contract's own RED-fixtures table as a
      SEPARATE fixture from this task's four; T025's own file explicitly disclaims it as
      "OUT OF SCOPE for T025"), so this clause is implemented-but-not-fixture-verified.
  (e) EvidencePath (>=1 that exists) for every cause                    -- NOT IMPLEMENTED.
      data-model.md #1 defines EvidencePath as "Repo-relative path ... the file must exist and
      hash-match at validation time" -- but research.md's REAL §2.1 "Evidence" column carries
      free-text citations into earlier research passes (e.g. "R2:47-48; registry rows
      2026-09-26T13:24:22Z", "memory card session-delta-20260924b; R6:46-47"), NOT
      filesystem-path-shaped strings. Implementing a literal file-existence check against that
      column would flag EVERY one of the live document's 46 real rows (there is no row whose
      Evidence cell is a real repo-relative path today) -- silently trusting a fabricated
      path-extraction heuristic to bridge that gap would be exactly the guessing constitution
      11.4.6 forbids, and T025's own RED test explicitly names this clause
      (`sc_bad_cause_no_evidence`) as "OUT OF SCOPE for T025's four named bullets ... NOT covered
      by this file". Left unimplemented, honestly, pending whatever later task defines how
      research.md's prose citations map to real EvidencePath entries.
  (f) measured_share required for CONFIRMED once T-A11 has run          -- PARTIAL, opt-in. The
      contract's own literal Invocation line for `causes` (`--doc <research.md> --out
      <causes.json>`) names no flag for "has T-A11 run"; today (Phase 0, confirmed against the
      live research.md's own §2.2 closing text: "0 of 46 rows carry a measured share ... every
      share is UNMEASURED until T-A11/T049") this clause is INACTIVE by construction, so no flag
      is needed to pass T025. An optional `--post-a11` boolean is added as a forward-compatible
      extension (never on by default, so every current invocation -- T025's included -- is
      unaffected): when passed, a CONFIRMED row whose "Share of total cycle" cell is UNMEASURED
      or blank is a violation. The contract's further exemption ("unless recorded as a named
      permanent gap") names no concrete marker syntax anywhere in the contract or research.md,
      so no such exemption is recognised here -- an honest, deliberately narrower reading than
      the full future clause, to be corrected by whichever task actually re-runs this checker
      after T-A11 lands (T-A11's own task line: "Protecting tests: T-H08's structural check
      re-run").
  (g) the six operator-listed causes must all be present ("configured list") -- PARTIAL, opt-in.
      The contract's own parenthetical "(configured list)" means this is caller-supplied data,
      not a value this generic tool may hardcode from one project's own research.md preamble
      (constitution 11.4.28 decoupling). An optional `--operator-causes` (comma-separated Origin
      tokens, e.g. "O1,O2,O3,O4,O5,O6") is added: when supplied, every listed token must appear
      in at least one row's Origin cell, else a violation names the missing token(s); when
      omitted (every current invocation, T025's included), this check is honestly SKIPPED --
      never silently assumed satisfied.

Malformed-row integrity note: clauses (a)/(b)/(c) above are genuinely FULL -- not merely FULL
over whichever rows happened to parse -- precisely because a line that fails to even split into a
genuine row is never silently omitted from consideration; it surfaces as its own `malformed_row`
violation (see "Row parsing" above) instead of vanishing from `rows` without a trace.

Output (C-002): canonical JSON via fc_common.py's shared conventions, schema
"plan-struct-causes/v1". Body: {"doc": <--doc path as given>, "causes": [{"id", "class",
"evidence_paths" (the raw §2.1 Evidence-cell text, wrapped as a single-element list -- see (e)
above: NOT validated as real filesystem paths in this pass), "measured_share" (the raw "Share of
total cycle" cell text), "settling_evidence" (the raw "Settling evidence / what remains" cell
text, or null if blank), "removed_or_measured_by" (the raw last-cell text, or null if blank)},
...], "class_counts": {"stated": {...}, "actual": {...}}, "violations": [{"code", ...fields}]}.
Written on exit 0 AND exit 1 (a finding is still a real, inspectable verdict -- fc_common.py's
own `emit --code 1` convention); NOT written on exit 2/3/4 (no honest verdict, C-001).

Producer != Verifier (constitution 11.4.240): this tool CHECKS research.md's own register; it
never edits research.md, plan.md, or tasks.md, and its own orphan-cause detector's correctness
is proven, every run, by a self-contained synthetic control-needle check (see `self_check()`)
BEFORE the real --doc is ever read -- independent of, and never delegating to, the RED test's own
separate `register_audit` fixture-validation instrument.

Side-effects: `causes` writes --out via fc_common.py's atomic emit path (except on exit 2/3/4).
Stdlib only (matches lib/fc_common.py's own convention); imports canon/body_hash_of/cmd_emit
from the sibling lib/fc_common.py (C-002), same wiring pattern as cycle_report.py.

`triple` (CT-5, Post-Design Principle IV; common-conventions.md C-005; ATM-1109, 2026-10-01 --
the tracked follow-up T179's own module docstring named as the one thing still owed after
`research`/`plan` landed): checks that every "analyzer, oracle, judge and guard" task ships the
self-validation triple (golden-good, golden-bad, negative-control) its own RED test is supposed
to carry. "Analyzer/oracle/judge/guard task" is NOT a classification this file invents -- it is
derived MECHANICALLY from two already-present, structural sources, never a hand-picked or
hardcoded task list (constitution 11.4.6):

  (1) SCOPE comes from `--contracts`/common-conventions.md's own `### Tool map (contract -> plan
      file -> plan task)` table (parsed by `parse_tool_map`), cross-checked per contract against
      that SAME contract's own text: a contract is "self-validation-triple-scoped" (CT-5's own
      "oracle/analyzer/judge/guard" class) iff ITS OWN text genuinely demonstrates all three
      triple classes somewhere (a RED-fixtures table, per C-005) -- `_svt_classes_present`,
      reused identically for this scope decision and for the per-test-file completeness check
      below. A contract this tool cannot confirm ships its own triple (common-conventions.md
      itself, and the "Plan tools that no contract...covers" footnote list, both correctly fail
      this test) is left OUT OF SCOPE, never silently assumed in -- verified live against the
      real corpus (2026-10-01) before choosing this design: this yields exactly the 12 real tool
      contracts (affected-set-and-verdict-cache, agent-registry-and-handoff,
      catch-set-comparison-harness, closure-refusal, consumer-audit-and-migration,
      cycle-time-report-cli, evidence-reference-reverify, governance-subset-selector,
      host-resource-attribution, plan-research-structural-check, recursive-verification,
      review-batch-and-precheck) and 43 of the 68 real plan tasks -- a strict superset of CT-5's
      own 13 named examples (the 10 "cache, selector, compare tool, ... enumerator and verifier"
      items plus the 3 originally-incomplete ones), all 13 of which land inside this 43-task
      scope, confirming the mechanical derivation agrees with CT-5's own worked examples rather
      than merely approximating them.
  (2) COMPLETENESS, per in-scope task, comes from `--tasks`/tasks.md's own "RED test `<path>`
      ... (plan T-...)" lines (parsed by `parse_red_test_task_map`, the SAME line shape this
      project's own T052/T091/T125/T126 use, verified against all four real lines before choosing
      it): the task's own RED-test file content is scanned (`_svt_classes_present`) for the THREE
      self-validation-triple classes -- `golden-good`/`golden good`/`golden_good` OR `control
      needle` (T052's and T126's own RED tests satisfy this member EXCLUSIVELY via "control
      needle", never spelling out "golden-good" at all -- confirmed by direct inspection before
      choosing this fallback, constitution 11.4.201(7)(a): match the vocabulary this project's
      OWN files actually use, not a guess); `golden-bad`/`golden bad`/`golden_bad`; `negative
      control`/`negative-control`/`negative_control`/`negctrl`. A missing class, a task with zero
      RED-test entries at all, an unreadable RED-test file, a Tool-map-named contract whose own
      `.md` file cannot be read, or a Tool-map-named task id absent from `--plan` are each their
      own named violation (`triple_incomplete` / `triple_test_file_missing` /
      `triple_test_file_unreadable` / `contract_file_missing` / `tool_map_task_unknown`).

HONESTLY DISCLOSED, NOT caught (matching this file's own established convention for partial
coverage -- see `causes`'s docstring clauses (d)/(e)/(f) and `research`'s own SEVEN-topics
disclosure for precedent): (i) a fixture-class member represented ONLY by an abbreviated
directory-naming convention with no descriptive prose ever spelling out one of the phrases above
(a REAL, confirmed case in this corpus: T-C03's `test_affected_set_red.sh` names `as_bad_*`
fixtures but never once writes "golden-bad" anywhere in its own text -- correctly, honestly
flagged `triple_incomplete` by this design, in the CONSERVATIVE direction constitution
11.4.201(4) prefers: a missed-but-real triple member under-reports completeness, never
over-reports it); (ii) a RED-establishing task line phrased with a verb other than "RED test"
(a REAL, confirmed case: T-B01's own line reads "Write and run the reproduction probe `...`; RED
= ...", never the literal phrase "RED test", so `parse_red_test_task_map` does not find it and
T-B01 is honestly reported `triple_test_file_missing` even though its own RED establishment
genuinely exists under different wording). Verified live against the real corpus (2026-10-01,
before this feature's own `self_check_triple` was written): of the 43 in-scope tasks, 21 are
genuinely complete (including all 4 of T-C02/T-B04/T-B05/T-D06, the tasks CT-5's own box text
named as needing the negative-control fix T052/T091/T125/T126 supplied), 8 have zero recognised
RED-test entry at all, and 14 are missing exactly one named class from an otherwise-present RED
test -- a real, actionable finding set this check's whole purpose is to surface honestly, not
paper over with a narrower, hand-picked scope that would have stopped at the 4 tasks CT-5's own
box text happened to already name.

Output (C-002): schema "plan-struct-triple/v1". Body: {"plan", "tasks", "contracts",
"in_scope_tasks" (sorted list of every plan task id this run held to the CT-5 bar),
"in_scope_task_count", "violations": [{"code", ...fields}]}.
"""
import argparse
import bisect
import difflib
import json
import os
import re
import string
import subprocess
import sys

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash / atomic-emit helpers. Imported by file
# path (not a package) -- constitution/scripts/fastcycle has no __init__.py anywhere (matches
# this tree's existing flat-script layout, e.g. cycle_report.py / anchor_citations.py).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

SCHEMA = "plan-struct-causes/v1"
SCHEMA_LANDING = "plan-struct-landing/v1"
SCHEMA_RULE_DIFF = "plan-struct-rule-diff/v1"
SCHEMA_RESEARCH = "plan-struct-research/v1"
SCHEMA_PLAN = "plan-struct-plan/v1"
SCHEMA_TRIPLE = "plan-struct-triple/v1"
CLASS_MEMBERS = ("CONFIRMED", "REFUTED", "UNDETERMINED")

# §2.1 Register table column indices after `line.split("|")` (parts[0] and parts[10] are the
# empty strings either side of the leading/trailing "|" -- 11 parts total for a genuine 9-cell
# data row). Same convention as this task's own RED test's `register_audit` instrument.
_COL_RC = 1
_COL_CAUSE = 2
_COL_ORIGIN = 3
_COL_CLASS = 4
_COL_MAGNITUDE = 5
_COL_SHARE = 6
_COL_EVIDENCE = 7
_COL_SETTLING = 8
_COL_LAST = 9
_ROW_PARTS = 11

_CLASS_TOKEN_RE = re.compile(r"^\*\*([A-Z]+)\*\*")
_UNMEASURED_RE = re.compile(r"^UNMEASURED\b", re.IGNORECASE)

# Best-effort recovery of a malformed row's RC identifier. The line has already satisfied
# `line.startswith("| RC-")` by construction (see parse_register_rows) before this is ever
# matched, so in practice this always recovers at least the literal "RC-" token, and typically
# the row's FULL id (e.g. "RC-02") -- the id token itself precedes whatever later "|" (an
# unescaped pipe inside a free-text cell) made the split malformed. Kept as a real regex match
# rather than a hardcoded slice so it degrades gracefully (empty capture -> None, see
# parse_register_rows) rather than raising on a pathological line.
_MALFORMED_ROW_ID_RE = re.compile(r"^\|\s*(RC-[^\s|]*)")


def _class_token(cell):
    """First bold token of a §2.1 Class cell, or "" if the cell has none (blank, or no bold
    markup at all). Matches split verdicts such as "**CONFIRMED** (mechanism) / rate
    UNDETERMINED" by taking only the FIRST bold token -- research.md's own §2.2 stated
    convention for RC-22/RC-23."""
    m = _CLASS_TOKEN_RE.match(cell.strip())
    return m.group(1) if m else ""


def parse_register_rows(text):
    """Parse every `| RC-...` row of a §2.1-shaped register table out of `text`.

    Returns (rows, malformed):
      - `rows` is a list of row dicts in document order: {"id", "cause", "origin", "class",
        "magnitude", "share", "evidence", "settling", "last"}.
      - `malformed` is a list of {"code": "malformed_row", "row", "line_no", "line", "parts"}
        violation dicts, one per line starting with "| RC-" whose "|"-split does NOT yield
        exactly _ROW_PARTS parts (a genuine 9-cell data row's shape) -- most realistically an
        unescaped "|" inside a free-text Cause/Evidence/Settling cell shifting every later
        column. Such a line is NEVER silently dropped without a trace (constitution
        11.4.201/11.4.273: a malformed row vanishing unnoticed would defeat clauses (a)/(b)/(c)
        simultaneously and silently -- it is counted toward none of them, and a §2.2 total that
        happens to already match the post-drop tally would then report a clean 0-violation pass
        over a register that was never fully audited). `row` names the row's best-effort-
        recovered RC id via _MALFORMED_ROW_ID_RE (in practice always recoverable given the
        `line.startswith("| RC-")` precondition below), or is None on the defensive fallback
        path when even that cannot be recovered; `line_no` (1-indexed) and `line` (the raw,
        newline-stripped line text) are always populated regardless, so a malformed row is
        fully traceable either way.

    A line that genuinely parses is never also reported as malformed -- the two outcomes are
    mutually exclusive per line.
    """
    rows = []
    malformed = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line.startswith("| RC-"):
            continue
        raw = line.rstrip("\n")
        parts = raw.split("|")
        if len(parts) != _ROW_PARTS:
            m = _MALFORMED_ROW_ID_RE.match(raw)
            recovered_id = m.group(1).strip() if m and m.group(1).strip() else None
            malformed.append({
                "code": "malformed_row",
                "row": recovered_id,
                "line_no": line_no,
                "line": raw,
                "parts": len(parts),
            })
            continue
        rows.append({
            "id": parts[_COL_RC].strip(),
            "cause": parts[_COL_CAUSE].strip(),
            "origin": parts[_COL_ORIGIN].strip(),
            "class": _class_token(parts[_COL_CLASS]),
            "magnitude": parts[_COL_MAGNITUDE].strip(),
            "share": parts[_COL_SHARE].strip(),
            "evidence": parts[_COL_EVIDENCE].strip(),
            "settling": parts[_COL_SETTLING].strip(),
            "last": parts[_COL_LAST].strip(),
        })
    return rows, malformed


def parse_register_counts(text):
    """Parse the §2.2 "Register counts" table's stated per-class Rows figure out of `text`.

    Returns {class_name: int} for whichever of {CONFIRMED, REFUTED, UNDETERMINED} the table
    states a row for (a class the table omits is simply absent from the returned dict -- no
    entry to compare against, matching the RED test's own register_audit instrument). Section
    boundaries: starts at a line beginning "### 2.2", ends at the next line beginning "### 2."
    that is not itself "### 2.2" (i.e. "### 2.3" etc.) -- identical convention to register_audit.
    """
    stated = {}
    in_22 = False
    for line in text.splitlines():
        if line.startswith("### 2.2"):
            in_22 = True
            continue
        if in_22 and line.startswith("### 2.") and not line.startswith("### 2.2"):
            break
        if in_22 and line.startswith("|"):
            parts = line.rstrip("\n").split("|")
            if len(parts) >= 3:
                key = parts[1].strip()
                val = parts[2].strip().strip("*")
                if key in CLASS_MEMBERS:
                    try:
                        stated[key] = int(val)
                    except ValueError:
                        pass  # non-numeric "Rows" cell: leave this class absent from `stated`
    return stated


def actual_counts(rows):
    counts = {}
    for row in rows:
        if row["class"]:
            counts[row["class"]] = counts.get(row["class"], 0) + 1
    return counts


def check_causes(rows, stated, post_a11, operator_causes):
    """Run every SC-C-001 check this file implements (see module docstring's Contract-clause
    coverage section) over already-parsed rows/§2.2 counts. Returns (causes_out, violations)."""
    causes_out = []
    violations = []

    for row in rows:
        rid = row["id"]

        # (a) class membership
        if row["class"] not in CLASS_MEMBERS:
            violations.append({"code": "no_class", "row": rid, "found": row["class"] or None})

        # (b) orphan cause: register-level only (no cross-reference into plan.md -- see docstring)
        if not row["last"]:
            violations.append({"code": "orphan_cause", "row": rid})

        # (d) settling_evidence required for UNDETERMINED (PARTIAL -- see docstring)
        if row["class"] == "UNDETERMINED" and not row["settling"]:
            violations.append({"code": "undetermined_no_settling", "row": rid})

        # (f) measured_share required for CONFIRMED once T-A11 has run (PARTIAL, opt-in --
        # see docstring; inactive unless --post-a11 was passed)
        if post_a11 and row["class"] == "CONFIRMED":
            share = row["share"]
            if not share or _UNMEASURED_RE.match(share):
                violations.append({"code": "measured_share_missing", "row": rid})

        causes_out.append({
            "id": rid,
            "class": row["class"] or None,
            "evidence_paths": [row["evidence"]] if row["evidence"] else [],
            "measured_share": row["share"] or None,
            "settling_evidence": row["settling"] or None,
            "removed_or_measured_by": row["last"] or None,
        })

    # (c) class counts equal research.md §2.2
    actual = actual_counts(rows)
    for cls in CLASS_MEMBERS:
        s = stated.get(cls)
        a = actual.get(cls, 0)
        if s is not None and s != a:
            violations.append({"code": "count_mismatch", "class": cls, "stated": s, "actual": a})

    # (g) the six operator-listed causes must all be present ("configured list", PARTIAL, opt-in)
    if operator_causes:
        origins_seen = " ".join(row["origin"] for row in rows)
        missing = [tok for tok in operator_causes if not re.search(r"\b%s\b" % re.escape(tok), origins_seen)]
        if missing:
            violations.append({"code": "operator_causes_missing", "tokens": sorted(missing)})

    causes_out.sort(key=lambda c: c["id"])  # C-002: arrays sorted by identity field
    return causes_out, violations


def _violation_stderr_line(v):
    code = v["code"]
    if code == "malformed_row":
        who = v["row"] if v["row"] else ("line %d: %s" % (v["line_no"], v["line"]))
        return "malformed row (expected %d '|'-separated parts, found %d): %s" % (
            _ROW_PARTS, v["parts"], who)
    if code == "no_class":
        return "no class: %s" % v["row"]
    if code == "orphan_cause":
        return "orphan cause (no task in 'Removed / measured by'): %s" % v["row"]
    if code == "undetermined_no_settling":
        return "UNDETERMINED row has no settling_evidence: %s" % v["row"]
    if code == "measured_share_missing":
        return "CONFIRMED row has no measured_share after --post-a11: %s" % v["row"]
    if code == "count_mismatch":
        return "%s:stated=%d,actual=%d" % (v["class"], v["stated"], v["actual"])
    if code == "operator_causes_missing":
        return "operator-listed cause(s) not found in any row's Origin cell: %s" % ",".join(v["tokens"])
    return str(v)  # pragma: no cover - defensive, every emitted code is one of the above


# ---------------------------------------------------------------------------
# §11.4.201/§11.4.273 self-check (control needle): proves THIS tool's own orphan-cause
# detector -- the exact mechanism the contract's exit code 3 names ("needle: a fixture with a
# known orphan cause not detected") -- genuinely flags a known-orphan row and does NOT
# false-positive on a known-non-orphan row, using a synthetic, self-contained §2-shaped
# fixture built in-process (never touching disk, never the RED test's own on-disk fixtures --
# Producer != Verifier, constitution 11.4.240). Run BEFORE the real --doc is ever read.
# ---------------------------------------------------------------------------
_SELF_CHECK_DOC = (
    "## 2. Root-cause register\n\n"
    "### 2.1 Register table\n\n"
    "| RC | Cause | Origin | Class | Measured magnitude (named denominator) | Share of total cycle | Evidence | Settling evidence / what remains | Removed / measured by |\n"
    "|---|---|---|---|---|---|---|---|---|\n"
    "| RC-NEEDLE-GOOD | control-needle cause (non-orphan) | O1 | **CONFIRMED** | m | UNMEASURED | e | s | T-NEEDLE |\n"
    "| RC-NEEDLE-BAD | control-needle cause (deliberately orphan) | O1 | **CONFIRMED** | m | UNMEASURED | e | s |  |\n"
    "\n### 2.2 Register counts (machine count over the Class column of §2.1)\n\n"
    "| Class | Rows | Row ids |\n"
    "|---|---|---|\n"
    "| CONFIRMED | 2 | RC-NEEDLE-GOOD, RC-NEEDLE-BAD |\n"
    "| **Total** | **2** | |\n"
)


def self_check():
    """Returns None on success, else a diagnostic string (caller exits 3)."""
    rows, malformed = parse_register_rows(_SELF_CHECK_DOC)
    if malformed:
        return ("self-check FAILED: the synthetic control-needle fixture itself produced "
                 "unexpected malformed_row finding(s) -- it must parse cleanly: %r" % malformed)
    by_id = {r["id"]: r for r in rows}
    good = by_id.get("RC-NEEDLE-GOOD")
    bad = by_id.get("RC-NEEDLE-BAD")
    if good is None or bad is None:
        return "self-check FAILED: could not even parse the synthetic control-needle rows (%d rows found, expected 2)" % len(rows)
    if bad["last"]:
        return "self-check FAILED: the synthetic control-needle parser did not read RC-NEEDLE-BAD's last cell as blank (got %r)" % bad["last"]
    if not good["last"]:
        return "self-check FAILED: the synthetic control-needle parser wrongly read RC-NEEDLE-GOOD's last cell as blank"
    _, violations = check_causes(rows, parse_register_counts(_SELF_CHECK_DOC), post_a11=False, operator_causes=None)
    bad_flagged = any(v["code"] == "orphan_cause" and v["row"] == "RC-NEEDLE-BAD" for v in violations)
    good_flagged = any(v["code"] == "orphan_cause" and v["row"] == "RC-NEEDLE-GOOD" for v in violations)
    if not bad_flagged:
        return "self-check FAILED: known-orphan RC-NEEDLE-BAD was NOT flagged as orphan_cause"
    if good_flagged:
        return "self-check FAILED: known-non-orphan RC-NEEDLE-GOOD was WRONGLY flagged as orphan_cause (false positive, constitution 11.4.201(1))"
    return None


def _read_doc(path, flag="--doc"):
    """Returns (text, None) on success, (None, error-message) on failure. Never raises. `flag`
    names the ACTUAL command-line flag whose path failed to read (review round 1, M4: every
    caller previously got a hardcoded "cannot read --doc ..." message even when the failing flag
    was `--log`/`--plan`/`--tasks`/`--causes`/`--spec` -- misleading when diagnosing which
    argument actually pointed at a bad path)."""
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read(), None
    except (OSError, UnicodeDecodeError) as exc:
        return None, "cannot read %s %s: %s" % (flag, path, exc)


def cmd_causes(a):
    self_check_err = self_check()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    operator_causes = None
    if a.operator_causes:
        operator_causes = [t.strip() for t in a.operator_causes.split(",") if t.strip()]

    text, err = _read_doc(a.doc, "--doc")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4

    rows, malformed = parse_register_rows(text)
    if not rows and not malformed:
        print("plan_struct_check: BLIND -- --doc %s has zero parseable '| RC-' register rows "
              "(no honest register to check)" % a.doc, file=sys.stderr)
        return 4

    stated = parse_register_counts(text)
    causes_out, violations = check_causes(rows, stated, post_a11=a.post_a11, operator_causes=operator_causes)
    # Malformed rows are a structural violation in their own right (see parse_register_rows /
    # module docstring "Row parsing") -- never silently dropped, and reported ahead of the
    # semantic per-row checks below since a parse failure precedes them in the pipeline.
    violations = malformed + violations

    for v in violations:
        print("plan_struct_check: %s" % _violation_stderr_line(v), file=sys.stderr)

    body = {
        "doc": a.doc,
        "causes": causes_out,
        "class_counts": {"stated": stated, "actual": actual_counts(rows)},
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        # fc_common.cmd_emit only ever fails (returns 2) on a write/encode error, in which case
        # its own diagnostic is already on stderr -- surface that failure honestly rather than
        # claim the causes verdict this tool computed.
        return write_rc
    return rc


# ---------------------------------------------------------------------------
# T159: `landing` (SC-C-004, FR-019) and `rule-diff` (SC-C-005, FR-022) -- see module docstring
# for the full contract-clause coverage. Shared plumbing (anchor-block extraction, CM-* token
# extraction) is used by BOTH subcommands; the actual correctness DECISIONS are delegated to the
# real, already-shipped `gate_ledger.sh` and `cm_covenant_114_<N>_propagation.sh` mechanisms
# (landing) or computed via the SAME narrow difflib-opcode discipline this task's own RED test
# already proved independently (rule-diff) -- never re-derived from scratch.
# ---------------------------------------------------------------------------

# Line-anchored anchor block-start conventions.
#
# REVIEW-ROUND-1 REMEDIATION (B1, independent §11.4.209 Opus-xhigh review of T159): the FIRST
# version of this regex followed constitution/scripts/gates/lib/covenant_propagation_engine.sh's
# own documented three-form list (bold-paragraph / H3-heading / bullet compact-summary) literally
# -- but that engine's BLOCK_RE is applied ONLY to the four MIRROR carrier files (CLAUDE.md /
# AGENTS.md / QWEN.md / GEMINI.md; see that file's own header, "Carriers are discovered by name
# (CLAUDE.md / AGENTS.md / QWEN.md / GEMINI.md)"), never to Constitution.md itself, which this
# file's own `landing`/`rule-diff` subcommands always read. Measured DIRECTLY against the real
# `Constitution.md` before writing this fix (constitution 11.4.6 -- never guessed blind):
#   * EVERY ONE of the 101 lines in the real corpus matching `^- §11\.4\.[0-9]+` is a mid-body
#     CITATION bullet inside some OTHER anchor's own composes-list (e.g. "- §11.4.57 -- README.md
#     doc-link refresh at Stage 5." living inside §11.4.58's own block) -- NEVER a genuine
#     top-level heading; that engine's own header even calls the bullet form "older anchors",
#     while its OWN comment for the H3 form says "Constitution.md's own style" -- the bullet form
#     was never Constitution.md's own convention to begin with. The bullet alternative is
#     therefore DROPPED entirely for this file's own parsing of Constitution.md (a mid-body
#     citation bullet MUST NOT be mistaken for a block-start, constitution 11.4.201(7)(a):
#     structure, not substring).
#   * The bold-paragraph form genuinely IS used for real Constitution.md headings (e.g.
#     "**§11.4.202 -- Reporting directives: ...**"), but the SAME `**§11.4.<N>` prefix also
#     opens SUB-CLAUSE / mid-body-topic paragraphs that talk ABOUT another anchor from inside a
#     DIFFERENT anchor's own block -- e.g. "**§11.4.184(I) -- HawkScan ..." (a sub-clause of
#     §11.4.184, not its own top-level anchor) and "**§11.4.202 precedence (stated explicitly ...
#     " (a topic paragraph living inside §11.4.214's own block, discussing §11.4.202) and
#     "**§11.4.30 carve-out." / "**§11.4.93 amendment." (topic paragraphs inside §11.4.95's own
#     block). Measured directly: EVERY genuine bold-form heading in the real corpus is followed
#     IMMEDIATELY by the literal sequence " — " (space, the REAL Unicode em-dash U+2014, space) --
#     m1 REMEDIATION (independent §11.4.209 Opus-xhigh review round 2, review round 3): earlier
#     drafts of this very comment (and its sibling note just below) wrote the two-ASCII-HYPHEN
#     sequence "--" here while parenthetically -- and self-contradictorily -- calling it
#     "em-dash"; two ASCII hyphens are NOT an em-dash. The code itself has always required the
#     real em-dash character (see the regex literal below); only this comment's own WORDING was
#     wrong, and is corrected here. Every one of the four false-positive shapes above is followed
#     by something else first ("(I) -- ", " precedence", " carve-out.", " amendment."). The bold
#     alternative below therefore requires that exact " — " (real em-dash) boundary, closing this
#     class without guessing (a citation-bullet DECOY and a sub-clause-heading DECOY are exercised in
#     self_check_landing() below, proving this discrimination rather than merely asserting it).
#   * The H3 form (`### §11.4.<N>`) is unaffected by either false-positive class above -- it is
#     Constitution.md's OWN canonical heading marker (confirmed: 243 real occurrences, zero
#     mid-body citation/sub-clause collisions found) -- and its LINE-MATCHING condition (does this
#     line start "### §11.4." followed by a digit run) is kept unchanged; only its CAPTURE shape
#     is widened, see NB1 immediately below.
#
# NB1 REMEDIATION (independent §11.4.209 Opus-xhigh review round 2, review round 3): the ORIGINAL
# `(?P<n2>[0-9]+)` (H3 form) / `(?P<n1>[0-9]+)` (bold form) capture groups stopped at the FIRST
# run of bare digits, so a genuine SUB-NUMBERED / dotted anchor heading such as
# "### §11.4.10.A -- Pre-store credential leak audit (User mandate, 2026-05-17)" (a REAL anchor
# in this corpus, distinct from plain "§11.4.10") matched with n2="10" -- the `(?!\d)` boundary
# check only refused a FOLLOWING DIGIT (correctly distinguishing "10" from "100"), it never
# refused a following "." + letter/digit suffix. The dotted child anchor's own block therefore
# keyed to the SAME bare number as its parent, and because `parse_anchor_blocks()` below only ever
# compares `occ[0]` (this task's own NB1 fix, see cmd_rule_diff), whichever of the two entries
# landed first silently absorbed the other -- a genuine change to (or outright deletion of) the
# SECOND heading with that shared key was invisible to `rule-diff`, reproduced live and confirmed
# BEFORE this fix (constitution 11.4.6): rewording "§11.4.10.A" from MUST to MAY, and deleting it
# outright, both wrongly reported rc=0 (no change detected). Fixed by widening EACH capture group
# to the FULL dotted identifier `[0-9]+(?:\.[A-Za-z0-9]+)*` (e.g. "10", "10.A", "184.I") and
# tightening the boundary check to `(?![0-9A-Za-z])` (refuse a following digit OR letter, so
# "10.A" is never confused with a hypothetical "10.AB", and "10" is never confused with "10.A" or
# "100") -- constitution 11.4.227(B) itself requires capturing the FULL dotted anchor id for
# exactly this reason. This does NOT change which LINES match (the line-matching condition above
# is unchanged) -- only what numeric KEY a matching line is filed under.
#
# Used here ONLY to find a block's own START LINE + extent (for CM-* token scoping and
# before/after body comparison) -- never as the correctness check itself, which this file always
# delegates to the real gate_ledger.sh / propagation-gate mechanisms (landing) or its own
# self-contained, self-checked difflib classifier (rule-diff).
#
# M-R4-2 REMEDIATION (independent §11.4.209 Opus-xhigh review round 4, fix round 4): two latent
# heading shapes (measured: ZERO occurrences of either in the real corpus today, grep-verified --
# so this changes no real-corpus parse; a before/after key+body-hash snapshot of all 269 real
# blocks is byte-identical) were mishandled: (a) a LETTER suffix with NO dot (`### §11.4.10A`)
# matched neither a block-start (the trailing letter failed the `(?![0-9A-Za-z])` boundary) nor
# stayed inside the preceding block (it DID match the generic non-anchor `### §` boundary), so its
# whole body was orphaned -- invisible to both subcommands. FIXED by admitting an optional
# letter run directly after the leading digit run (`[0-9]+[A-Za-z]*`), keying it as its own
# distinct anchor ("10A", never merged into "10"). (b) an H3-form SUB-CLAUSE heading
# (`### §11.4.990(I) — ...`) matched as a genuine block-start (the H3 alternative, unlike the bold
# one, had no terminator requirement), creating a FALSE duplicate of anchor 990. FIXED by
# refusing an immediately-following "(" on the H3 alternative too (exactly as the bold form's
# mandatory " — " already implies) AND by treating such a line as NEITHER a block-start NOR a
# boundary (see _H3_SUBCLAUSE_RE / parse_anchor_blocks()), so its content stays inside its own
# parent anchor's block, just as a bold-form sub-clause heading already does.
_ANCHOR_NUM_FRAGMENT = r"[0-9]+[A-Za-z]*(?:\.[A-Za-z0-9]+)*"
_ANCHOR_BLOCK_START_RE = re.compile(
    r"^(?:\*\*§11\.4\.(?P<n1>" + _ANCHOR_NUM_FRAGMENT + r")(?![0-9A-Za-z]) — "
    r"|### §11\.4\.(?P<n2>" + _ANCHOR_NUM_FRAGMENT + r")(?![0-9A-Za-z(]))"
)
_H3_SUBCLAUSE_RE = re.compile(r"^### §11\.4\." + _ANCHOR_NUM_FRAGMENT + r"\(")

# NB2 REMEDIATION (independent §11.4.209 Opus-xhigh review round 2, review round 3): a block's own
# END must ALSO stop at any top-level `## ` section heading (e.g. "## §12. Host-session safety
# ...", "## Appendix A -- ...") and at any `### §` heading whose own number is NOT itself a valid
# `§11.4.N` form (e.g. "### §12.1 Forbidden operations", "### §9.2 Force-push requires ...") --
# NEVER only the next §11.4.N anchor's own start, however far away that is. Reproduced live on the
# REAL corpus BEFORE this fix (constitution 11.4.6): §11.4.170's own block (the LAST §11.4.N
# anchor before "## §12. Host-session safety" begins) absorbed the ENTIRE §12 section PLUS
# Appendices A and B, because nothing between §11.4.170's own heading and the next REAL §11.4.N
# heading (there is none -- §11.4.170 is the corpus's last one) stopped it early; `landing
# --anchors 170` wrongly reported 4 of its 6 `gate_unimplemented` violations against gates that
# actually belong to §12 (`CM-COVENANT-12-11-PROPAGATION`, `CM-COVENANT-12-12-PROPAGATION`,
# `CM-MAXRES-DYNAMIC-BUILD`, `CM-NPROC-HEADROOM-CHECK`) -- a real gate-to-anchor misattribution on
# live production data. Every top-level `## ` heading in the real corpus already sits BEFORE any
# non-§11.4.N `### §` heading it introduces (e.g. "## §12. ..." at line 10045 precedes its own
# "### §12.1 ..." sub-heading at line 10051) -- confirmed live, grep-verified -- so the `## `
# boundary alone already closes THIS corpus's own bug; the non-anchor `### §` boundary is added
# ADDITIONALLY, per this task's own explicit instruction, so a future corpus whose §12-shaped
# sub-heading is not preceded by its own `## ` parent (or any other numbered non-§11.4 `### §`
# heading sandwiched directly between two §11.4.N anchors with no intervening `## `) is caught the
# same way, never relying on the real corpus's own current, but not guaranteed-forever, layout.
_TOP_LEVEL_SECTION_RE = re.compile(r"^## ")
_H3_SECTION_ANY_RE = re.compile(r"^### §")

# Same CM-* token shape + trailing-punctuation-stripping convention as gate_ledger.sh's own
# `extract_names()` (module docstring "Row parsing" section references this file's general
# independent-reimplementation-of-conventions-not-logic policy; here it is the SAME shape
# because both tools must agree on what counts as a gate-token spelling for their outputs to be
# comparable at all -- a producer/verifier agreeing on a SHAPE is not the same as agreeing on a
# DECISION, constitution 11.4.240).
_CM_TOKEN_RE = re.compile(r"CM-[A-Z0-9][A-Z0-9-]*")
_CM_TOKEN_TRAIL_RE = re.compile(r"[-.,:;)]+$")


def parse_anchor_blocks(text):
    """Returns {dotted_anchor_number: [block_body, ...]} -- one entry per LINE-ANCHORED
    block-start found in `text` (see _ANCHOR_BLOCK_START_RE), keyed by the anchor's own FULL
    dotted numeric suffix (e.g. "230" for §11.4.230, "10.A" for the REAL sub-numbered §11.4.10.A --
    NB1, review round 3: previously truncated to the bare leading digit run, silently colliding
    a dotted child anchor with its own parent's key), each block body spanning from its own
    heading line (inclusive) to the line BEFORE whichever of the following comes first: the NEXT
    block-start of ANY §11.4.N anchor, the NEXT top-level `## ` section heading, the NEXT `### §`
    heading whose own number is NOT itself a valid §11.4.N form (NB2, review round 3 -- see
    _TOP_LEVEL_SECTION_RE / _H3_SECTION_ANY_RE's own header for the measured real-corpus
    §11.4.170-absorbs-all-of-§12 evidence this closes), or EOF.

    A mid-sentence/mid-body CITATION of an anchor (e.g. "... per §11.4.230(A) ..." or
    "- §11.4.230 -- short gloss." inside a DIFFERENT anchor's own composes-list) is never
    line-anchored against _ANCHOR_BLOCK_START_RE's own tightened forms and therefore never mistaken
    for a block-start (structure, not substring -- constitution 11.4.201(7)(a)); likewise a
    SUB-CLAUSE / topic paragraph naming an anchor from inside another anchor's own body (e.g.
    "**§11.4.184(I) -- ..." or "**§11.4.202 precedence (...") never matches -- see
    _ANCHOR_BLOCK_START_RE's own header for the measured evidence this discrimination is built on
    (B1, review round 1). More than one genuine block-start for the SAME anchor number within
    `text` is preserved as multiple list entries (never silently merged or overwritten) -- the
    caller decides what a >1 count means for its own check (cmd_landing's own
    `duplicate_block_in_corpus`; cmd_rule_diff's own NB1 per-occurrence comparison, review
    round 3)."""
    lines = text.splitlines()
    starts = []
    boundaries = []  # every line index that terminates SOME block, sorted ascending by construction
    for i, line in enumerate(lines):
        m = _ANCHOR_BLOCK_START_RE.match(line)
        if m:
            num = m.group("n1") or m.group("n2")
            starts.append((i, num))
            boundaries.append(i)
            continue
        if _H3_SUBCLAUSE_RE.match(line):
            continue  # M-R4-2: an H3 sub-clause heading is neither a block-start nor a boundary
        if _TOP_LEVEL_SECTION_RE.match(line) or (
                _H3_SECTION_ANY_RE.match(line) and not _ANCHOR_BLOCK_START_RE.match(line)):
            boundaries.append(i)
    blocks = {}
    for line_idx, num in starts:
        # First boundary strictly AFTER this block's own start line -- bisect over the
        # already-ascending `boundaries` list (NB2, review round 3: previously always the next
        # entry in `starts`, i.e. the next §11.4.N anchor ONLY, however far away that was).
        pos = bisect.bisect_right(boundaries, line_idx)
        end = boundaries[pos] if pos < len(boundaries) else len(lines)
        end = _strip_trailing_separator(lines, line_idx, end)
        blocks.setdefault(num, []).append("\n".join(lines[line_idx:end]))
    return blocks


# FIX ROUND 5 (I-R5-1): the corpus's OWN anchor-separator convention -- measured 2026-10-01, 101 of
# the real Constitution.md's 269 anchor blocks end in a standalone `---` line -- makes that line
# block-boundary punctuation, not rule content. When a NEW anchor is inserted between an existing
# anchor's text and its trailing `---`, the separator physically moves into the new block; before
# this fix the existing anchor then "lost" a unit and was falsely SUBSTANTIVE (real repro: commit
# 91aa99d, which only appends §11.4.192, reported substantive_change on the untouched §11.4.191).
_BLOCK_THEMATIC_BREAK_RE = re.compile(r"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$")
_BLOCK_FENCE_RE = re.compile(r"^\s*(?:```|~~~)")


def _strip_trailing_separator(lines, start, end):
    """Returns the new exclusive END index of the block lines[start:end] with its trailing blank
    lines removed, then -- only if the last remaining line is a GENUINE standalone thematic break
    (preceded by a blank line, so never a setext heading underline, and not inside an unclosed
    code fence) -- that one separator line and the blank lines before it removed too. Never
    strips the heading line itself, and never touches anything but blank lines and ONE trailing
    separator: rule text is never removed."""
    e = end
    while e > start + 1 and not lines[e - 1].strip():
        e -= 1
    if (e > start + 2 and _BLOCK_THEMATIC_BREAK_RE.match(lines[e - 1].expandtabs(4))
            and not lines[e - 2].strip()):
        fence_toggles = sum(1 for l in lines[start:e - 1] if _BLOCK_FENCE_RE.match(l))
        if fence_toggles % 2 == 0:
            e -= 1
            while e > start + 1 and not lines[e - 1].strip():
                e -= 1
    return e


def extract_cm_tokens(text):
    """Returns a sorted, de-duplicated list of every CM-* gate token named in `text`, trailing
    prose punctuation stripped (matches gate_ledger.sh's own extract_names() token shape)."""
    seen = set()
    out = []
    for m in _CM_TOKEN_RE.finditer(text):
        tok = _CM_TOKEN_TRAIL_RE.sub("", m.group(0))
        if tok and tok not in seen:
            seen.add(tok)
            out.append(tok)
    return sorted(out)


def _bare_anchor_num(anchor):
    return anchor[len("11.4."):] if anchor.startswith("11.4.") else anchor


def _full_anchor(anchor):
    return anchor if anchor.startswith("11.4.") else ("11.4." + anchor)


def load_anchor_to_gate(path):
    """Parses covenant_propagation_anchors.tsv's own `<gate-name>\\t<anchor-number>` data-pack
    format (comment/blank lines ignored, matching covenant_propagation_engine.sh's own
    `covenant_propagation_anchor_for()` awk logic) into {anchor_number: gate_name}. Returns an
    empty dict, honestly, when the data pack does not exist -- every anchor is then reported
    `propagation_gate_not_registered` rather than this function raising (constitution 11.4.6: an
    absent OPTIONAL data pack is a real, reportable state, not an internal error)."""
    mapping = {}
    if not os.path.isfile(path):
        return mapping
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 2 and parts[0].strip() and parts[1].strip():
                    mapping[parts[1].strip()] = parts[0].strip()
    except OSError:
        return {}
    return mapping


def _wrapper_filename_for_gate(gate_name):
    return gate_name.lower().replace("-", "_") + ".sh"


def run_gate_ledger(gate_ledger_path, impl_dir, deferrals_tsv, corpus_files):
    """Invokes the REAL, already-shipped `gate_ledger.sh generate` (§11.4.227(A)) as a
    subprocess -- genuinely reused, never reimplemented. Returns (status_by_gate, None) on
    success, where status_by_gate is {gate: {"status": ..., "evidence": ...}} parsed from its
    own documented `<gate>\\t<STATUS>\\t<evidence>` TSV output; or (None, diagnostic) on any
    failure (process error, timeout, or gate_ledger.sh's own BLIND exit 2) -- the caller treats
    that as this tool's own BLIND (exit 4), never a silently-empty ledger."""
    cmd = ["bash", gate_ledger_path, "generate", impl_dir, deferrals_tsv] + list(corpus_files)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "cannot run gate_ledger.sh generate: %s: %s" % (type(exc).__name__, exc)
    if proc.returncode != 0:
        return None, "gate_ledger.sh generate exited %d (BLIND) -- stderr: %s" % (
            proc.returncode, proc.stderr.strip())
    status = {}
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            status[parts[0]] = {"status": parts[1], "evidence": parts[2] if len(parts) > 2 else None}
    return status, None


def run_propagation_gate(wrapper_path, consumer_root):
    """Invokes the REAL, already-shipped per-anchor `cm_covenant_114_<N>_propagation.sh`
    wrapper -- genuinely reusing the shared §11.4.227(B) block-start/exactly-once/lockstep
    content-hash-equality engine, never re-derived here. Returns (rc, None) on a real invocation
    (rc per that wrapper's own documented exit codes: 0 PASS, 1 FAIL, 2 environment
    error/BLIND), or (None, diagnostic) if the process itself could not be run/timed out."""
    try:
        proc = subprocess.run(["bash", wrapper_path, "--root", consumer_root, "--quiet"],
                               capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "cannot run %s: %s: %s" % (wrapper_path, type(exc).__name__, exc)
    return proc.returncode, None


def self_check_landing():
    """§11.4.201/§11.4.273 control needle for THIS tool's OWN anchor-block-extraction +
    CM-token-extraction (the code this file itself owns and is responsible for) -- run against a
    synthetic, self-contained, in-memory fixture BEFORE --constitution is ever read, exactly
    matching the `causes` subcommand's own self_check() convention. Never exercises
    gate_ledger.sh or a propagation-gate wrapper here (Producer != Verifier, constitution
    11.4.240): those are SEPARATE, already-independently-tested mechanisms this tool invokes,
    not this tool's own logic to self-certify.

    REVIEW-ROUND-1 REMEDIATION (B1): the fixture below now additionally embeds, INSIDE anchor
    900's own block body, a mid-body CITATION BULLET naming its sibling anchor 901
    ("- §11.4.901 -- ...") and a SUB-CLAUSE HEADING naming anchor 900 itself
    ("**§11.4.900(Z) -- ..."), plus a leading NUMERIC-PREFIX DECOY anchor 90 -- proving three
    distinct false-positive classes this tool's own history got wrong are genuinely NOT treated
    as new block-starts (constitution 11.4.201(1)/(7)(a); see _ANCHOR_BLOCK_START_RE's own header
    for the measured real-corpus evidence this fix is built on).

    REVIEW ROUND 3 REMEDIATION (NB1/NB2, independent §11.4.209 Opus-xhigh review round 2): the
    fixture below additionally embeds (a) a DOTTED sub-anchor "901.A" immediately after its own
    parent anchor "901", proving it is keyed as a genuinely DISTINCT "901.A" entry, never merged
    into -- nor silently overwriting -- its parent's own "901" entry (NB1); (b) an anchor "902"
    immediately followed by a NON-ANCHOR numbered "### §9.9" heading with no intervening
    top-level heading, proving its own block stops there rather than absorbing that unrelated
    section (NB2); (c) an anchor "903" immediately followed by a top-level "## " section heading,
    proving its own block stops there too, independently of (b) (NB2) -- see
    _TOP_LEVEL_SECTION_RE / _H3_SECTION_ANY_RE's own header for the measured real-corpus
    §11.4.170-absorbs-§12-and-both-Appendices evidence these two needles are built on. Returns
    None on success, else a diagnostic string (caller exits 3)."""
    doc = (
        "### §11.4.90 -- numeric-prefix decoy anchor (must never be confused with anchor 900's\n"
        "needle via a bare digit-run prefix match; constitution 11.4.201(7)(a)).\n"
        "\n"
        "### §11.4.900 -- landing self-check needle anchor (never a real anchor; synthetic)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-LANDING-NEEDLE` MUST hold.\n"
        "\n"
        "- §11.4.901 -- a mid-body CITATION BULLET, living INSIDE anchor 900's own block,\n"
        "  naming the SIBLING anchor 901 (structure, not substring, constitution\n"
        "  11.4.201(7)(a)) -- MUST NOT be mistaken for anchor 901's own block-start.\n"
        "\n"
        "**§11.4.900(Z) — a SUB-CLAUSE heading naming THIS SAME anchor from inside its own\n"
        "block (never a second top-level block-start for 900; constitution 11.4.201(7)(a)) --\n"
        "NI3(d), review round 3: strengthened to use the REAL Unicode em-dash right after\n"
        "'(Z)' (matching the ACTUAL real-corpus false-positive shape, e.g. real "
        "'**§11.4.184(I) — ...'), never the weaker plain-ASCII '--' an earlier draft used.**\n"
        "\n"
        "### §11.4.901 -- landing self-check sibling anchor (synthetic)\n"
        "\n"
        "Nothing relevant to the needle token lives in this block.\n"
        "\n"
        "### §11.4.901.A -- landing self-check DOTTED sub-anchor (NB1 needle; synthetic, never a\n"
        "real anchor -- distinct from its own parent anchor 901)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-DOTTED-NEEDLE` MUST hold (NB1, review round 3: this\n"
        "dotted anchor's own key must be '901.A', genuinely distinct from its parent '901',\n"
        "never merged into it nor overwriting it).\n"
        "\n"
        "### §11.4.902 -- landing self-check NB2 H3-non-anchor-boundary anchor (synthetic)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-NB2-H3-NEEDLE` MUST hold.\n"
        "\n"
        "### §9.9 a NON-ANCHOR numbered H3 heading (NB2 needle; never a valid §11.4.N form) --\n"
        "anchor 902's own block MUST end here, with no intervening top-level heading.\n"
        "\n"
        "Gate `CM-SELFCHECK-NB2-H3-LEAKED` MUST NEVER be found inside anchor 902's own body.\n"
        "\n"
        "### §11.4.903 -- landing self-check NB2 top-level-section-boundary anchor (synthetic)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-NB2-TOPLEVEL-NEEDLE` MUST hold.\n"
        "\n"
        "## Synthetic top-level section (NB2 needle; anchor 903's own block MUST end here)\n"
        "\n"
        "Gate `CM-SELFCHECK-NB2-TOPLEVEL-LEAKED` MUST NEVER be found inside anchor 903's body.\n"
        "\n"
        "**§11.4.904 — landing self-check GENUINE BOLD-FORM heading needle anchor (NI3(a),\n"
        "review round 3: a REAL bold-paragraph block-start, never merely the H3 form every\n"
        "OTHER needle above exercises -- proving the bold-form alternative of\n"
        "_ANCHOR_BLOCK_START_RE is itself genuinely recognised, not merely its DECOY\n"
        "rejections).**\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-BOLD-FORM-NEEDLE` MUST hold.\n"
        "\n"
        "### §11.4.905 -- landing self-check M-R4-2 parent anchor (synthetic)\n"
        "\n"
        "### §11.4.905(I) — an H3-form SUB-CLAUSE heading inside anchor 905 (M-R4-2 needle:\n"
        "never a new block-start, never a block boundary)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-H3-SUBCLAUSE-NEEDLE` MUST hold.\n"
        "\n"
        "### §11.4.905A -- landing self-check LETTER-suffix anchor (M-R4-2 needle; synthetic)\n"
        "\n"
        "Recommended gate `CM-SELFCHECK-LETTER-SUFFIX-NEEDLE` MUST hold.\n"
    )
    blocks = parse_anchor_blocks(doc)
    prefix_decoy_blocks = blocks.get("90")
    needle_blocks = blocks.get("900")
    sibling_blocks = blocks.get("901")
    dotted_blocks = blocks.get("901.A")
    h3_boundary_blocks = blocks.get("902")
    toplevel_boundary_blocks = blocks.get("903")
    bold_form_blocks = blocks.get("904")
    if not prefix_decoy_blocks or len(prefix_decoy_blocks) != 1:
        return ("self-check FAILED: landing anchor-block extractor did not find exactly one "
                 "block for the numeric-prefix decoy anchor 90 (got %r) -- a digit-run "
                 "prefix-match bug would either merge it into 900 or drop it entirely"
                 % blocks.get("90"))
    if not needle_blocks or len(needle_blocks) != 1:
        return ("self-check FAILED: landing anchor-block extractor did not find exactly one "
                 "block for the synthetic needle anchor 900 (got %r) -- the embedded citation-"
                 "bullet and sub-clause-heading DECOYS may have wrongly split anchor 900's own "
                 "block (B1, constitution 11.4.201(7)(a))" % blocks.get("900"))
    if not sibling_blocks or len(sibling_blocks) != 1:
        return ("self-check FAILED: landing anchor-block extractor did not find exactly one "
                 "block for the synthetic sibling anchor 901 (got %r) -- the mid-body citation "
                 "bullet naming 901 from inside anchor 900's own block may have been wrongly "
                 "treated as anchor 901's real block-start (B1, constitution 11.4.201(7)(a)), or "
                 "(NB1, review round 3) its own dotted child 901.A may have been wrongly merged "
                 "into this same key" % blocks.get("901"))
    if not dotted_blocks or len(dotted_blocks) != 1:
        return ("self-check FAILED (NB1, review round 3): landing anchor-block extractor did "
                 "not find exactly one block for the DOTTED sub-anchor 901.A (got %r) -- a "
                 "dotted anchor's own capture group must include its full suffix, never "
                 "truncate to the bare parent number" % blocks.get("901.A"))
    if not h3_boundary_blocks or len(h3_boundary_blocks) != 1:
        return ("self-check FAILED (NB2, review round 3): landing anchor-block extractor did "
                 "not find exactly one block for the H3-non-anchor-boundary needle anchor 902 "
                 "(got %r)" % blocks.get("902"))
    if not toplevel_boundary_blocks or len(toplevel_boundary_blocks) != 1:
        return ("self-check FAILED (NB2, review round 3): landing anchor-block extractor did "
                 "not find exactly one block for the top-level-section-boundary needle anchor "
                 "903 (got %r)" % blocks.get("903"))
    if not bold_form_blocks or len(bold_form_blocks) != 1:
        return ("self-check FAILED (NI3(a), review round 3): landing anchor-block extractor "
                 "did not find exactly one block for the GENUINE bold-paragraph-form needle "
                 "anchor 904 (got %r) -- every OTHER needle in this fixture exercises the H3 "
                 "form only; this needle proves the bold-form alternative of "
                 "_ANCHOR_BLOCK_START_RE is itself genuinely recognised" % blocks.get("904"))
    if "CM-SELFCHECK-LANDING-NEEDLE" not in extract_cm_tokens(needle_blocks[0]):
        return ("self-check FAILED: landing CM-token extractor did not find the known-present "
                 "needle token inside the synthetic anchor 900's own block")
    if "CM-SELFCHECK-LANDING-NEEDLE" in extract_cm_tokens(sibling_blocks[0]):
        return ("self-check FAILED: landing CM-token extractor wrongly found anchor 900's "
                 "needle token inside the SIBLING anchor 901's block -- the block-boundary "
                 "extraction is broken (false positive, constitution 11.4.201(1))")
    if "CM-SELFCHECK-LANDING-NEEDLE" in extract_cm_tokens(prefix_decoy_blocks[0]):
        return ("self-check FAILED: landing CM-token extractor wrongly found anchor 900's "
                 "needle token inside the NUMERIC-PREFIX DECOY anchor 90's block -- a digit-run "
                 "prefix-match bug (constitution 11.4.201(1))")
    if "a mid-body CITATION BULLET" not in needle_blocks[0]:
        return ("self-check FAILED: the citation-bullet decoy's own text (naming sibling anchor "
                 "901 from inside anchor 900's own block) is missing from anchor 900's own "
                 "extracted body -- the block boundary extraction dropped or mis-split real "
                 "content (B1)")
    if "a SUB-CLAUSE heading naming THIS SAME anchor" not in needle_blocks[0]:
        return ("self-check FAILED: the sub-clause-heading decoy's own text (naming anchor 900 "
                 "again from inside its own block) is missing from anchor 900's own extracted "
                 "body -- the block boundary extraction dropped or mis-split real content (B1)")
    if "a mid-body CITATION BULLET" in sibling_blocks[0]:
        return ("self-check FAILED: the citation-bullet decoy's own text (which names sibling "
                 "anchor 901 but structurally lives INSIDE anchor 900's block) leaked into "
                 "anchor 901's own extracted body -- the citation bullet was wrongly treated as "
                 "anchor 901's real block-start (B1, false positive, constitution 11.4.201(1))")
    if "CM-SELFCHECK-DOTTED-NEEDLE" not in extract_cm_tokens(dotted_blocks[0]):
        return ("self-check FAILED (NB1, review round 3): landing CM-token extractor did not "
                 "find the known-present needle token inside the synthetic DOTTED sub-anchor "
                 "901.A's own block")
    if "CM-SELFCHECK-DOTTED-NEEDLE" in extract_cm_tokens(sibling_blocks[0]):
        return ("self-check FAILED (NB1, review round 3): the dotted child anchor 901.A's "
                 "needle token leaked into its own PARENT anchor 901's extracted body -- the "
                 "dotted anchor was wrongly merged into its parent's key (false positive, "
                 "constitution 11.4.201(1))")
    if "CM-SELFCHECK-NB2-H3-NEEDLE" not in extract_cm_tokens(h3_boundary_blocks[0]):
        return ("self-check FAILED (NB2, review round 3): landing CM-token extractor did not "
                 "find the known-present needle token inside anchor 902's own block")
    if "CM-SELFCHECK-NB2-H3-LEAKED" in extract_cm_tokens(h3_boundary_blocks[0]):
        return ("self-check FAILED (NB2, review round 3): anchor 902's own block did NOT stop "
                 "at the following NON-ANCHOR numbered '### §9.9' heading -- it absorbed content "
                 "belonging to a different, unrelated numbered section (the exact "
                 "§11.4.170-absorbs-§12 defect class this fix closes)")
    if "CM-SELFCHECK-NB2-TOPLEVEL-NEEDLE" not in extract_cm_tokens(toplevel_boundary_blocks[0]):
        return ("self-check FAILED (NB2, review round 3): landing CM-token extractor did not "
                 "find the known-present needle token inside anchor 903's own block")
    if "CM-SELFCHECK-NB2-TOPLEVEL-LEAKED" in extract_cm_tokens(toplevel_boundary_blocks[0]):
        return ("self-check FAILED (NB2, review round 3): anchor 903's own block did NOT stop "
                 "at the following top-level '## ' section heading -- it absorbed content "
                 "belonging to a different, unrelated top-level section (the exact "
                 "§11.4.170-absorbs-§12-and-Appendices defect class this fix closes)")
    if "CM-SELFCHECK-BOLD-FORM-NEEDLE" not in extract_cm_tokens(bold_form_blocks[0]):
        return ("self-check FAILED (NI3(a), review round 3): landing CM-token extractor did "
                 "not find the known-present needle token inside the GENUINE bold-paragraph-"
                 "form anchor 904's own block")
    subclause_parent = blocks.get("905")
    letter_blocks = blocks.get("905A")
    if (not subclause_parent or len(subclause_parent) != 1
            or "CM-SELFCHECK-H3-SUBCLAUSE-NEEDLE" not in extract_cm_tokens(subclause_parent[0])):
        return ("self-check FAILED (M-R4-2, fix round 4): an H3-form sub-clause heading "
                "'### §11.4.905(I) — ...' was treated as a new block-start or a block boundary "
                "(got %r) -- its content must stay inside parent anchor 905's single block"
                % subclause_parent)
    if (not letter_blocks or len(letter_blocks) != 1
            or "CM-SELFCHECK-LETTER-SUFFIX-NEEDLE" not in extract_cm_tokens(letter_blocks[0])
            or "CM-SELFCHECK-LETTER-SUFFIX-NEEDLE" in extract_cm_tokens(subclause_parent[0])):
        return ("self-check FAILED (M-R4-2, fix round 4): a letter-suffixed heading "
                "'### §11.4.905A' was not keyed as its own distinct anchor '905A' (got %r)"
                % letter_blocks)
    return None


def cmd_landing(a):
    self_check_err = self_check_landing()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    anchors = [t.strip() for t in a.anchors.split(",") if t.strip()]
    if not anchors:
        print("plan_struct_check: usage error -- --anchors must name at least one anchor",
              file=sys.stderr)
        return 2

    constitution_dir = a.constitution.rstrip("/") or "/"
    corpus_path = os.path.join(constitution_dir, "Constitution.md")
    text, err = _read_doc(corpus_path)
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4

    blocks = parse_anchor_blocks(text)
    if not blocks:
        print("plan_struct_check: BLIND -- %s has zero parseable anchor blocks (no honest "
              "corpus to check)" % corpus_path, file=sys.stderr)
        return 4

    gate_ledger_path = os.path.join(constitution_dir, "scripts", "gates", "gate_ledger.sh")
    if not os.path.isfile(gate_ledger_path):
        print("plan_struct_check: BLIND -- gate_ledger.sh not found at %s (the existing "
              "§11.4.227(A) mechanism this check invokes, never reimplements)" % gate_ledger_path,
              file=sys.stderr)
        return 4
    impl_dir = os.path.join(constitution_dir, "scripts")
    deferrals_tsv = os.path.join(constitution_dir, "scripts", "gates", "gate_ledger_deferrals.tsv")

    ledger, ledger_err = run_gate_ledger(gate_ledger_path, impl_dir, deferrals_tsv, [corpus_path])
    if ledger_err:
        print("plan_struct_check: BLIND -- %s" % ledger_err, file=sys.stderr)
        return 4

    anchors_pack = os.path.join(constitution_dir, "scripts", "gates", "covenant_propagation_anchors.tsv")
    gate_for_anchor = load_anchor_to_gate(anchors_pack)
    consumer_root = os.path.dirname(os.path.abspath(constitution_dir))

    violations = []
    anchor_results = []
    for requested in anchors:
        n = _bare_anchor_num(requested)
        full = _full_anchor(requested)
        occ = blocks.get(n)
        if not occ:
            violations.append({"code": "anchor_not_found", "anchor": requested})
            anchor_results.append({"anchor": requested, "found": False, "gates": [], "propagation": None})
            continue
        if len(occ) > 1:
            violations.append({"code": "duplicate_block_in_corpus", "anchor": requested, "count": len(occ)})
        # M-R4-3 REMEDIATION (independent review round 4, fix round 4): gate tokens are now
        # extracted from EVERY genuine occurrence of the requested anchor, never only occ[0] -- a
        # gate named ONLY in a later duplicate block was previously never checked at all (the
        # duplication itself was flagged, but those specific gates silently vanished from the
        # report). The duplicate_block_in_corpus violation above is unchanged.
        tokens = extract_cm_tokens("\n".join(occ))
        gate_infos = []
        for tok in tokens:
            info = ledger.get(tok)
            status = info["status"] if info else "UNKNOWN"
            gate_infos.append({"gate": tok, "status": status,
                                "evidence": info.get("evidence") if info else None})
            if status == "UNIMPLEMENTED":
                violations.append({"code": "gate_unimplemented", "anchor": requested, "gate": tok})
            elif status == "UNKNOWN":
                violations.append({"code": "gate_status_unknown", "anchor": requested, "gate": tok})

        gate_name = gate_for_anchor.get(full)
        if gate_name:
            wrapper = os.path.join(constitution_dir, "scripts", "gates",
                                    _wrapper_filename_for_gate(gate_name))
            if os.path.isfile(wrapper):
                rc, run_err = run_propagation_gate(wrapper, consumer_root)
                if run_err:
                    violations.append({"code": "propagation_gate_blind", "anchor": requested,
                                        "gate": gate_name, "detail": run_err})
                    prop_result = {"gate": gate_name, "registered": True, "rc": None, "blind": True}
                else:
                    prop_result = {"gate": gate_name, "registered": True, "rc": rc}
                    if rc == 1:
                        violations.append({"code": "propagation_gate_failed", "anchor": requested,
                                            "gate": gate_name, "rc": rc})
                    elif rc != 0:
                        violations.append({"code": "propagation_gate_blind", "anchor": requested,
                                            "gate": gate_name, "rc": rc})
            else:
                prop_result = {"gate": gate_name, "registered": True, "wrapper_missing": True}
                violations.append({"code": "propagation_gate_wrapper_missing", "anchor": requested,
                                    "gate": gate_name})
        else:
            # B3 remediation (independent review round 1): a brand-new anchor with NO registered
            # CM-COVENANT-114-<N>-PROPAGATION wrapper is a REAL, REPORTED violation --
            # `propagation_gate_not_registered` -- never a silent PASS. SC-C-004 requires
            # "propagation gate passes" for each requested anchor; an anchor this check has never
            # actually invoked a propagation gate against MUST NOT be able to exit clean purely
            # because nothing has been wired for it yet (constitution 11.4.6: an absent check is
            # not evidence of compliance -- the exact "brand new anchor with no propagation
            # wrapper yet" case T-G01 exists to catch). See module docstring clause (ii).
            prop_result = {"gate": None, "registered": False}
            violations.append({"code": "propagation_gate_not_registered", "anchor": requested})

        anchor_results.append({"anchor": requested, "found": True, "gates": gate_infos,
                                "propagation": prop_result})

    for v in violations:
        print("plan_struct_check: landing: %s" % v, file=sys.stderr)

    body = {
        "constitution": a.constitution,
        "anchors": anchor_results,
        "violations": violations,
    }
    # MINOR remediation (independent review round 1): a propagation wrapper that could not be RUN
    # AT ALL (`propagation_gate_blind` -- its own process failed or timed out) is this tool's own
    # instrument observing NOTHING decided about that anchor, never a decided FAIL -- if EVERY
    # violation found is of that class, the honest overall verdict is BLIND (exit 4), matching
    # fc_common.cmd_emit's own documented exit-4/`BLIND: true` convention, `--out` still written.
    # Any OTHER, genuinely decided violation code present alongside a blind one still exits 1 (a
    # real finding must never be swallowed by a blind one).
    if violations and all(v["code"] == "propagation_gate_blind" for v in violations):
        rc = 4
    else:
        rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA_LANDING,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        return write_rc
    return rc


_DIFF_WS_RUN_RE = re.compile(r"[ \t]+")


def _normalize_line_ws(line):
    """Strips trailing whitespace and collapses internal whitespace runs to a single space --
    used SOLELY by classify_diff() below to decide the STRUCTURAL-vs-SUBSTANTIVE/ADDITIVE
    boundary (I3, review round 1). Never used to decide what text actually landed: the RAW,
    un-normalized before/after bodies are still what every other check in this file reads,
    hashes, or reports back to the operator."""
    return _DIFF_WS_RUN_RE.sub(" ", line.rstrip())


def _join_paragraph_lines(lines):
    """Joins hard-wrapped RAW lines into ONE logical, whitespace-collapsed string: each line's own
    leading/trailing whitespace is stripped, the lines are joined with a single space, and every
    remaining whitespace run is collapsed to a single space. Used SOLELY by _split_paragraphs()
    below; the round-4 classifier joins only the CONTINUATION lines of one logical unit (see
    _logical_units()), never a whole paragraph."""
    return _DIFF_WS_RUN_RE.sub(" ", " ".join(l.strip() for l in lines)).strip()


def _split_paragraphs(text):
    """Returns the list of paragraph strings of `text` (a paragraph = a maximal run of NON-blank
    lines, its hard-wrapped lines joined via _join_paragraph_lines()).

    FIX ROUND 4 (I-R4-2 / I-R4-3): classify_diff() NO LONGER diffs at this granularity. Joining
    a WHOLE paragraph into one string (review round 3's NI2 fix) threw away every line-break,
    indentation and list-item/table-row boundary, which (I-R4-2) hid real structural edits
    (un-nesting a qualifier bullet, dedenting YAML inside a fence, merging two list items into one
    run-on item -- all normalized to the identical joined string, so falsely STRUCTURAL) and
    (I-R4-3) turned every pure append INSIDE an existing paragraph (a new table row, a new list
    item, a new sentence directly under an existing one) into a `replace` of that one joined
    string, so falsely SUBSTANTIVE. Kept only as a small, documented helper; see
    _logical_units() for the unit-level model that replaced it."""
    paragraphs = []
    current = []
    for line in text.splitlines():
        if line.strip() == "":
            if current:
                paragraphs.append(_join_paragraph_lines(current))
                current = []
        else:
            current.append(line)
    if current:
        paragraphs.append(_join_paragraph_lines(current))
    return paragraphs


# FIX ROUND 4 (I-R4-2 / I-R4-3) -- the LOGICAL-UNIT model. Each unit is one Markdown block
# element whose BOUNDARIES are part of its identity: a list item (its own marker line PLUS any
# lazy hard-wrapped continuation lines), a table row, a heading line, a code-fence delimiter
# line, a single line INSIDE a code fence, or a prose run (a line PLUS its hard-wrapped
# continuation lines, up to the next blank line / list item / row / heading / fence). Every unit
# is a hashable tuple (kind, level, marker, text):
#   * kind   -- "prose" | "li" | "row" | "heading" | "fence" | "code"
#   * level  -- for code lines: the RAW leading indent (YAML/code nesting is literal); for every
#               other kind: the NESTING DEPTH computed from leading indent via an indent stack
#               (so a consistent 2->4-space re-indent of a nested list keeps its depth and stays
#               STRUCTURAL, while un-nesting a child bullet changes its depth -- I-R4-2 case 1)
#   * marker -- "bullet" | "ordered" for list items (the literal "-"/"*"/"+" glyph and the
#               ordinal number are deliberately NOT part of identity: re-bulleting or renumbering
#               is formatting), "" otherwise
#   * text   -- whitespace-collapsed words for every kind except code (code keeps its internal
#               spacing, trailing whitespace stripped); table rows are normalized cell-by-cell so
#               cell padding is formatting
# Hard-wrap reflow WITHIN a unit is invisible (continuation lines are joined), which is what keeps
# NI2's pure-rewrap case STRUCTURAL; a word inserted MID-unit changes that unit's text, which is
# what keeps NI2's mid-sentence-insertion case SUBSTANTIVE.
_UNIT_LIST_ITEM_RE = re.compile(r"^(?P<m>[-*+]|[0-9]+[.)])(?:\s+|$)")
_UNIT_HEADING_RE = re.compile(r"^#{1,6}(?:\s|$)")
_UNIT_FENCE_RE = re.compile(r"^(?P<f>```|~~~)")
# A unit whose existing last word ends a sentence ("." "!" "?", optionally followed by closing
# punctuation/emphasis) may have NEW words appended after it and that is an ADDITIVE tail-append;
# an UNFINISHED existing sentence ("The gate MUST refuse a claim" + "unless it is a test.")
# CONTINUES that sentence, which can qualify it, so it is SUBSTANTIVE.
_UNIT_SENTENCE_END_RE = re.compile(r"[.!?][)\]\"'*`_]*$")


# FIX ROUND 5 (I-R5-1 / I-R5-2 / M-R5-1 / M-R5-3): three more line shapes get their own rule.
#   * A THEMATIC BREAK (`---`, `***`, `___`, spaced forms like `- - -`, <= 3 leading spaces) is
#     block punctuation, NOT rule content -- it is not a unit at all (I-R5-1). It is checked BEFORE
#     the list-item rule so `- - -` / `* * *` are never read as bullets. EXCEPTION (M-R5-3): a
#     `---` or `===` line DIRECTLY under an open prose unit (no blank line between) is a SETEXT
#     heading underline in CommonMark -- it retroactively turns that paragraph into a heading, so
#     the prose unit's KIND becomes "heading" (a real rendered-meaning change, never a no-op).
#     Measured 2026-10-01 against the real Constitution.md: 117 thematic-break lines, ZERO setext
#     underlines (no `---`/`===` directly under a non-blank, non-table line outside a fence), so the
#     setext branch changes no real-corpus parse; it exists only so adding such a line is caught.
#   * A BLOCKQUOTE run (consecutive lines starting with `>` after <= 3 spaces) is de-quoted one
#     level (the `>` plus one optional space) and RE-PARSED by the SAME rules (I-R5-2) -- so a
#     list / table / fence / prose run inside a quote gets exactly the fine-grained treatment it
#     would get outside one, instead of every quoted line collapsing into one prose unit. Nested
#     quotes recurse. The quote depth is part of every resulting unit's identity (the 5th tuple
#     element, `ctx`, gains one ">" per level), so `> x` and `> > x` are never conflated.
#   * A multi-line HTML COMMENT (a line opening `<!--` with no `-->` after that opening, through
#     the line that closes it) hides its content from rendered output (M-R5-1): every unit parsed
#     inside it carries "!" in `ctx`, so wrapping an existing rule in `<!--` ... `-->` changes that
#     rule's unit identity (a `replace`, SUBSTANTIVE) instead of reading as two pure inserts.
#     Single-line comments (`<!-- x -->` on one line, the ONLY shape the real corpus uses today --
#     measured: 5 lines, all self-closing) hide nothing else and are ordinary text.
# Every unit is now a 5-tuple (kind, level, marker, text, ctx); ctx is "" for ordinary content.
_THEMATIC_BREAK_RE = re.compile(r"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$")
_SETEXT_EQ_RE = re.compile(r"^ {0,3}=+[ \t]*$")
_BLOCKQUOTE_RE = re.compile(r"^ {0,3}>")


def _dequote(line):
    """Removes ONE blockquote level (`>` plus one optional following space) from `line`."""
    s = line.lstrip()[1:]
    return s[1:] if s.startswith(" ") else s


def _parse_units(lines):
    """Single pass over raw `lines` -> ordered 5-tuple units (see _logical_units())."""
    raw_units = []  # [kind, indent, marker, text, ctx] -- mutable while continuation lines accrue
    in_fence = False
    fence_tok = None
    hidden = False  # inside a multi-line HTML comment (M-R5-1)
    open_unit = None  # the prose/li unit that a following plain line continues, if any
    i = 0
    while i < len(lines):
        line = lines[i].expandtabs(4).rstrip()
        i += 1
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if in_fence:
            ctx = "!" if hidden else ""
            if stripped.startswith(fence_tok):
                raw_units.append(["fence", indent, "", stripped, ctx])
                in_fence = False
            elif stripped:
                raw_units.append(["code", indent, "", stripped, ctx])
            open_unit = None
            continue
        if not stripped:
            open_unit = None
            continue
        if _BLOCKQUOTE_RE.match(line):
            quoted = [_dequote(line)]
            while i < len(lines) and _BLOCKQUOTE_RE.match(lines[i].expandtabs(4)):
                quoted.append(_dequote(lines[i].expandtabs(4)))
                i += 1
            for u in _parse_units(quoted):
                inner_ctx = ">" + u[4]
                if hidden and "!" not in inner_ctx:
                    inner_ctx += "!"
                raw_units.append(["__done__", (u[0], u[1], u[2], u[3], inner_ctx)])
            open_unit = None
            continue
        opens = "<!--" in stripped and "-->" not in stripped[stripped.rfind("<!--"):]
        line_hidden = hidden or opens
        if hidden and "-->" in stripped:
            # closed on this line -- re-opened only if a LATER `<!--` on it is left unclosed
            rest = stripped[stripped.find("-->") + 3:]
            hidden = "<!--" in rest and "-->" not in rest[rest.rfind("<!--"):]
        elif opens:
            hidden = True
        ctx = "!" if line_hidden else ""
        fm = _UNIT_FENCE_RE.match(stripped)
        if fm:
            in_fence = True
            fence_tok = fm.group("f")
            raw_units.append(["fence", indent, "", stripped, ctx])
            open_unit = None
            continue
        if _THEMATIC_BREAK_RE.match(line) or _SETEXT_EQ_RE.match(line):
            if open_unit is not None and open_unit[0] == "prose" and open_unit[4] == ctx:
                open_unit[0] = "heading"  # M-R5-3: setext underline -- the paragraph IS a heading
                open_unit = None
                continue
            if _THEMATIC_BREAK_RE.match(line):
                open_unit = None  # I-R5-1: block punctuation, not a unit
                continue
        if _UNIT_HEADING_RE.match(stripped):
            raw_units.append(["heading", indent, "", stripped, ctx])
            open_unit = None
            continue
        if stripped.startswith("|"):
            cells = [" ".join(c.split()) for c in stripped.strip("|").split("|")]
            raw_units.append(["row", indent, "", " | ".join(cells), ctx])
            open_unit = None
            continue
        lm = _UNIT_LIST_ITEM_RE.match(stripped)
        if lm:
            marker = "ordered" if lm.group("m")[0].isdigit() else "bullet"
            unit = ["li", indent, marker, stripped[lm.end():], ctx]
            raw_units.append(unit)
            open_unit = unit
            continue
        if open_unit is not None and open_unit[4] == ctx:
            open_unit[3] = open_unit[3] + " " + stripped  # hard-wrapped continuation line
            continue
        unit = ["prose", indent, "", stripped, ctx]
        raw_units.append(unit)
        open_unit = unit

    units = []
    stack = []  # indents of the currently-open nesting levels (non-code, unquoted units only)
    for entry in raw_units:
        if entry[0] == "__done__":
            units.append(entry[1])  # an already-finished quoted unit (own internal depth)
            continue
        kind, indent, marker, txt, ctx = entry
        if kind == "code":
            units.append((kind, indent, marker, txt, ctx))
            continue
        if kind in ("heading", "fence"):
            stack = []
            units.append((kind, 0, marker, " ".join(txt.split()), ctx))
            continue
        while stack and stack[-1] > indent:
            stack.pop()
        if not stack or stack[-1] < indent:
            stack.append(indent)
        units.append((kind, len(stack) - 1, marker, " ".join(txt.split()), ctx))
    return units


def _logical_units(text):
    """Parses `text` into the ordered list of logical-unit tuples described above
    (kind, level, marker, text, ctx). Blank lines separate units but are not units themselves (so
    a loose-vs-tight list, or a blank line added/removed between two list items, is formatting);
    thematic breaks are not units either (fix round 5, I-R5-1)."""
    return _parse_units(text.splitlines())


def _unit_skeleton(units):
    """Merges every run of CONSECUTIVE prose units at the SAME depth into one unit (their words
    joined) -- the ONLY boundary change this classifier treats as pure reflow: a blank line
    inserted or removed between two otherwise-unchanged prose paragraphs (NI2 review round 3's own
    second named example). List items, table rows, headings and code lines are NEVER merged, so
    merging two list items into one run-on item (I-R4-2 case 3) or un-nesting a bullet (I-R4-2
    case 1) can no longer masquerade as reflow the way review round 3's whole-document
    _full_normalized_text() comparison let it."""
    out = []
    for u in units:
        if (out and u[0] == "prose" and out[-1][0] == "prose" and out[-1][1] == u[1]
                and out[-1][4] == u[4]):
            prev = out[-1]
            out[-1] = (prev[0], prev[1], prev[2], (prev[3] + " " + u[3]).strip(), prev[4])
        else:
            out.append(u)
    return out


def _full_normalized_text(text):
    """FIX ROUND 4: retained ONLY as a thin compatibility helper returning the skeleton's joined
    text; classify_diff() no longer uses a whole-document word-stream comparison for its
    STRUCTURAL tier (that comparison is exactly what hid I-R4-2's un-nest / dedent / merge
    cases), it compares _unit_skeleton() tuples instead, which keep kind/depth/indent."""
    return " ".join(u[3] for u in _unit_skeleton(_logical_units(text)))


def _is_tail_append(before_unit, after_unit):
    """True iff `after_unit` is `before_unit` with NEW words appended strictly AFTER a completed
    sentence (I-R4-3 case 3: a new sentence directly under an existing one, no blank line) --
    same kind / depth / marker, the before-unit's words an exact PREFIX of the after-unit's, and
    the before-unit's last word ending a sentence (or the before-unit empty). Only prose and list
    items qualify; appending to a heading, table row (i.e. adding a column) or code line is never
    treated as additive."""
    if before_unit[0] != after_unit[0] or before_unit[0] not in ("prose", "li"):
        return False
    if (before_unit[1] != after_unit[1] or before_unit[2] != after_unit[2]
            or before_unit[4] != after_unit[4]):
        return False
    bw = before_unit[3].split()
    aw = after_unit[3].split()
    if len(aw) <= len(bw) or aw[:len(bw)] != bw:
        return False
    return not bw or bool(_UNIT_SENTENCE_END_RE.search(bw[-1]))


def _is_clean_insert(after_units, j1, j2):
    """True iff inserting after_units[j1:j2] does NOT re-parent the existing unit that follows
    the insertion point. An existing unit U at depth d is a child of the nearest preceding unit
    of smaller depth; if ANY inserted unit (same family -- code vs non-code, whose levels are not
    comparable) has a depth smaller than U's, U now hangs under that NEW unit instead of its old
    parent (e.g. a new top-level bullet inserted between "- (A) rule" and its nested "  - exception
    applies ONLY in test" silently transfers the exception to the new rule) -- a real structural
    change, so it is NOT a clean additive insert.

    I-R5F-1 (T159 final adjudicated fix): an inserted unit of a DIFFERENT context family (a
    blockquote `ctx=">"`, a multi-line HTML comment `ctx="!"`, or vice versa) placed directly before
    a NESTED following unit (depth > 0) is ALSO not clean -- in rendered Markdown a column-0 quote
    or HTML block terminates the enclosing list, so the formerly-nested child becomes a free-
    standing item (a real scope transfer the same-family depth comparison above cannot see, since
    levels across families are not comparable). Accepted side-effect, the SAFE direction: a quote
    genuinely indented INSIDE a list item is also treated conservatively (a possible false
    SUBSTANTIVE, never a false pass)."""
    if j2 >= len(after_units):
        return True
    nxt = after_units[j2]
    nxt_family = (nxt[0] == "code", nxt[4])  # levels are only comparable within one family
    for u in after_units[j1:j2]:
        if (u[0] == "code", u[4]) == nxt_family and u[1] < nxt[1]:
            return False
        if nxt[0] != "code" and nxt[1] > 0 and u[4] != nxt[4]:
            return False  # I-R5F-1: cross-context insert at a scope-sensitive boundary
    return True


def classify_diff(before_text, after_text):
    """SC-C-005 hunk classifier -- FIX ROUND 4 (I-R4-2 / I-R4-3) LOGICAL-UNIT design.

    Both texts are parsed into ordered logical units (see _logical_units(): list items, table
    rows, headings, fence lines, individual code lines, and prose runs -- each unit's own
    hard-wrapped continuation lines joined, its nesting depth / code indent part of its identity).
    Then:
      * raw lines identical                                   => UNCHANGED
      * unit sequences identical                              => STRUCTURAL (whitespace, hard-wrap
        reflow inside a unit, consistent re-indent of a nested list, bullet-glyph/ordinal change,
        table cell padding, blank lines between units)
      * _unit_skeleton() sequences identical                  => STRUCTURAL (additionally: a blank
        line added/removed between two prose paragraphs at the same depth)
      * otherwise a unit-level difflib pass decides SUBSTANTIVE vs ADDITIVE:
          - `delete` of any existing unit                                    => SUBSTANTIVE
          - `insert` of new units that does not re-parent the following
            existing unit (_is_clean_insert())                               => additive
          - `replace` of n existing units by m >= n units where each existing
            unit is, pairwise in order, extended ONLY by a tail-append after
            a completed sentence (_is_tail_append()), and the m-n extra units
            are a clean insert                                               => additive
          - any other `replace` (a word changed/inserted/removed INSIDE an
            existing unit, a depth/indent/kind change, two units merged,
            one split)                                                       => SUBSTANTIVE
        ADDITIVE only if every opcode is equal or additive.

    Measured results (constitution 11.4.6 -- every case reproduced against the pre-round-4 code
    FIRST, then against this design; see self_check_rule_diff() and the CLI tests): NI2's
    mid-sentence "NOT" insertion => SUBSTANTIVE (it lands INSIDE the unit's word list, not at its
    tail); NI2's pure rewrap => STRUCTURAL; NI2's blank-line boundary reflow => STRUCTURAL;
    I-R4-2's un-nest / YAML dedent inside a fence / two items merged => SUBSTANTIVE (each was
    falsely STRUCTURAL under round 3's whole-paragraph join); I-R4-3's appended table row /
    appended list item / appended sentence => ADDITIVE (each was falsely SUBSTANTIVE under round
    3); round 4's confirmed-good rewrap-plus-real-change => SUBSTANTIVE.

    HONEST BOUNDARIES (constitution 11.4.6): (1) heading-FORMAT changes (`###` -> `**...**`) and
    true line MOVES across non-adjacent units still classify SUBSTANTIVE/ADDITIVE like any other
    content change -- a deliberately narrower STRUCTURAL tier than SC-C-005's full definition.
    (2) CONSERVATIVE by design: a new sentence inserted BETWEEN two existing sentences of the
    SAME paragraph (rather than appended after its last one), or new words appended to an
    UNFINISHED sentence, classify SUBSTANTIVE -- the classifier cannot tell such text apart from a
    qualification of the surrounding rule. A new paragraph / list item / row / code line placed
    between existing ones is ADDITIVE unless it re-parents a nested unit. (3) Unit detection is
    line-shape based: a hard-wrapped prose line that happens to begin with a list-item marker
    ("- ", "* ", "+ ", "12. ") or "|" is read as a new item/row; reflow that moves such a token to
    a line start therefore reads as a structural change (a false SUBSTANTIVE, never a false
    pass). (4) PURELY MECHANICAL (I2, review round 1): ADDITIVE means only "no existing unit was
    removed, reworded, re-nested, or had words inserted inside it"; new text that OVERRIDES an
    existing rule ("Notwithstanding the above, clause (A) is optional.") still classifies
    ADDITIVE. An ADDITIVE verdict never means "needs no human/reviewer attention".

    FIX ROUND 5 additions (see the header above _THEMATIC_BREAK_RE): thematic breaks are not units
    (and parse_anchor_blocks() strips an anchor's own trailing `---` separator), so a separator
    moving between blocks or being added/removed between paragraphs is never SUBSTANTIVE (I-R5-1;
    measured on the last 150 real Constitution.md commits, see the module docstring); blockquote
    content is de-quoted and parsed with the same rules, quote depth part of identity (I-R5-2); a
    multi-line HTML comment marks its content hidden (M-R5-1); a setext underline turns its
    paragraph into a heading (M-R5-3).

    REMAINING HONEST BOUNDARIES after fix round 5 (constitution 11.4.6), classified by RISK
    CLASS -- the distinction matters and is NOT blurred: (5) FALSE-PASS-CAPABLE, latent: an
    UNFENCED 4-space-indented code block (the older Markdown convention) is not modeled as code
    -- its lines read as prose/list continuation, whose indent only feeds a nesting depth, so a
    DEDENT inside such a block can classify STRUCTURAL where SUBSTANTIVE is correct (M-R5-3's first
    half, NOT fixed this round). Measured 2026-10-01: the real corpus has no such blocks (its
    4+-space lines are all list-continuation paragraphs, already handled), so there is no
    real-corpus impact today; a future corpus that adopts the convention would need this closed.
    (6) FALSE-PASS-CAPABLE, latent: a blockquote "lazy continuation" line (a paragraph line
    continuing a quote WITHOUT its own leading `>`) is parsed as ordinary unquoted text, so it is
    not grouped with the quote -- measured: the real corpus's 593 quote lines are all explicitly
    prefixed. (7) BY DESIGN, not a gap: adding or removing a thematic break
    between otherwise-unchanged content is STRUCTURAL -- a rendered horizontal rule carries no
    rule semantics; any wording change around it still surfaces normally. (8) REFUSAL-ONLY:
    `===` directly under a list item is read as lazy continuation text of that item (CommonMark
    agrees -- a setext underline cannot be a lazy continuation), so adding one changes the item's
    words and reads SUBSTANTIVE."""
    b_raw = before_text.splitlines()
    a_raw = after_text.splitlines()
    if a_raw == b_raw:
        return "UNCHANGED"
    b_units = _logical_units(before_text)
    a_units = _logical_units(after_text)
    if a_units == b_units:
        return "STRUCTURAL"
    if _unit_skeleton(a_units) == _unit_skeleton(b_units):
        return "STRUCTURAL"
    sm = difflib.SequenceMatcher(a=b_units, b=a_units, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        if tag == "delete":
            return "SUBSTANTIVE"
        if tag == "insert":
            if not _is_clean_insert(a_units, j1, j2):
                return "SUBSTANTIVE"
            continue
        # replace
        n = i2 - i1
        if (j2 - j1) < n:
            return "SUBSTANTIVE"
        for k in range(n):
            if not _is_tail_append(b_units[i1 + k], a_units[j1 + k]):
                return "SUBSTANTIVE"
        if (j2 - j1) > n and not _is_clean_insert(a_units, j1 + n, j2):
            return "SUBSTANTIVE"
    return "ADDITIVE"


def self_check_rule_diff():
    """§11.4.201/§11.4.273 control needle for THIS tool's OWN classify_diff(), run against a
    synthetic, self-contained, in-memory fixture set BEFORE --base is ever read -- a reworded
    sentence must classify SUBSTANTIVE, a pure append must classify ADDITIVE, a pure
    trailing-whitespace reflow must classify STRUCTURAL (I3, review round 1), and an identical
    pair must classify UNCHANGED (the false-positive guard, constitution 11.4.201(1)).

    NI2 REMEDIATION (independent §11.4.209 Opus-xhigh review round 2, review round 3): three
    additional needles reproduce the reviewer's OWN exact repro cases against classify_diff()'s
    new paragraph-level tier (see its own docstring): (i) a single "NOT" line inserted BETWEEN the
    two existing lines of a hard-wrapped sentence, inverting its meaning, must classify SUBSTANTIVE
    -- NEVER the false-negative ADDITIVE the old line-only scheme produced; (ii) the SAME
    paragraph purely RE-WRAPPED (identical words, different line-break point, nothing else
    changed) must classify STRUCTURAL -- NEVER the false-positive SUBSTANTIVE the old scheme
    produced; (iii) (bonus, same defect class) a blank line REMOVED between two otherwise-unchanged
    paragraphs (merging them into one, no wording changed) must ALSO classify STRUCTURAL.

    FIX ROUND 4 / FIX ROUND 5 needles reproduce each later review round's own exact repro shapes
    (round 5: a trailing `---` separator that moved into a newly-inserted following anchor, run
    end-to-end through parse_anchor_blocks(), must be UNCHANGED; a removed mid-body thematic break
    STRUCTURAL; un-nesting / YAML-dedent INSIDE a blockquote SUBSTANTIVE, appending inside one
    ADDITIVE; an HTML-comment wrap and a setext underline SUBSTANTIVE). Returns None on success,
    else a diagnostic string (caller exits 3)."""
    before = ("### §11.4.901 -- rule-diff self-check needle anchor (synthetic)\n"
              "\n"
              "The gate MUST refuse a claim whose only support is an uncited signal.\n")
    after_sub = before.replace("MUST refuse", "SHOULD refuse")
    after_add = before + "\nExtension (synthetic): the gate additionally logs the refusal.\n"
    after_ws = before.replace(
        "The gate MUST refuse a claim whose only support is an uncited signal.\n",
        "The gate MUST refuse a claim whose only support is an uncited signal.   \n")
    if classify_diff(before, after_sub) != "SUBSTANTIVE":
        return ("self-check FAILED: rule-diff classifier did not classify a reworded existing "
                 "sentence (MUST -> SHOULD) as SUBSTANTIVE")
    if classify_diff(before, after_add) != "ADDITIVE":
        return ("self-check FAILED: rule-diff classifier did not classify a pure-append "
                 "extension (existing sentence untouched) as ADDITIVE")
    if classify_diff(before, after_ws) != "STRUCTURAL":
        return ("self-check FAILED: rule-diff classifier did not classify a pure "
                 "trailing-whitespace reflow (no wording changed) as STRUCTURAL (I3, review "
                 "round 1) -- got %r" % classify_diff(before, after_ws))
    if classify_diff(before, before) != "UNCHANGED":
        return ("self-check FAILED: rule-diff classifier wrongly classified an identical "
                 "before/after pair as changed (false positive, constitution 11.4.201(1))")

    # NI2 needle (i): mid-sentence "NOT" insertion, splitting an existing hard-wrapped sentence
    # across an extra line -- a REAL meaning-inverting content change, never a pure line insert.
    wrap_before = ("### §11.4.902 -- rule-diff self-check NI2 wrap needle anchor (synthetic)\n"
                   "\n"
                   "The system MUST always validate every input\n"
                   "before it is processed by any downstream consumer.\n")
    wrap_notinsert = wrap_before.replace(
        "The system MUST always validate every input\n"
        "before it is processed by any downstream consumer.\n",
        "The system MUST always validate every input\n"
        "NOT\n"
        "before it is processed by any downstream consumer.\n")
    if classify_diff(wrap_before, wrap_notinsert) != "SUBSTANTIVE":
        return ("self-check FAILED (NI2, review round 3): rule-diff classifier did not classify "
                 "a single 'NOT' line inserted BETWEEN the two existing lines of a hard-wrapped "
                 "sentence (inverting its meaning) as SUBSTANTIVE -- got %r (a false-negative "
                 "ADDITIVE here would mean a meaning-inverting rule change goes undetected)"
                 % classify_diff(wrap_before, wrap_notinsert))

    # NI2 needle (ii): the SAME paragraph purely re-wrapped -- identical words, a different
    # line-break point, nothing else changed -- must be STRUCTURAL, never a false-positive
    # SUBSTANTIVE.
    wrap_rewrapped = wrap_before.replace(
        "The system MUST always validate every input\n"
        "before it is processed by any downstream consumer.\n",
        "The system MUST always validate every input before it is\n"
        "processed by any downstream consumer.\n")
    if classify_diff(wrap_before, wrap_rewrapped) != "STRUCTURAL":
        return ("self-check FAILED (NI2, review round 3): rule-diff classifier did not classify "
                 "a pure paragraph RE-WRAP (identical words, different line-break point) as "
                 "STRUCTURAL -- got %r (a false-positive SUBSTANTIVE here would flag ordinary "
                 "reflow as a rule-substance change)" % classify_diff(wrap_before, wrap_rewrapped))

    # NI2 needle (iii), bonus (same defect class): a blank line REMOVED between two otherwise-
    # unchanged paragraphs (merging them, no wording changed) must ALSO be STRUCTURAL.
    boundary_before = ("### §11.4.903 -- rule-diff self-check NI2 boundary needle anchor "
                        "(synthetic)\n"
                        "\n"
                        "Paragraph one, unchanged.\n"
                        "\n"
                        "Paragraph two, unchanged.\n")
    boundary_merged = boundary_before.replace(
        "Paragraph one, unchanged.\n"
        "\n"
        "Paragraph two, unchanged.\n",
        "Paragraph one, unchanged.\n"
        "Paragraph two, unchanged.\n")
    if classify_diff(boundary_before, boundary_merged) != "STRUCTURAL":
        return ("self-check FAILED (NI2, review round 3): rule-diff classifier did not classify "
                 "a blank line REMOVED between two otherwise-unchanged paragraphs (a "
                 "paragraph-boundary reflow, no wording changed) as STRUCTURAL -- got %r"
                 % classify_diff(boundary_before, boundary_merged))

    # FIX ROUND 4 needles -- the independent review round 4's OWN exact repro shapes. I-R4-2: a
    # real structural edit that ALSO involves whitespace must NOT be absorbed as STRUCTURAL.
    # I-R4-3: a pure append inside an existing paragraph must NOT be refused as SUBSTANTIVE.
    head = "### §11.4.904 -- rule-diff self-check fix-round-4 needle anchor (synthetic)\n\n"
    r4_needles = (
        ("I-R4-2", "un-nesting a qualifier bullet (the exception no longer qualifies rule (A))",
         head + "- (A) rule\n  - exception applies ONLY in test\n",
         head + "- (A) rule\n- exception applies ONLY in test\n", "SUBSTANTIVE"),
        ("I-R4-2", "dedenting YAML content inside a code fence",
         head + "```yaml\nparent:\n  child: 1\n```\n",
         head + "```yaml\nparent:\nchild: 1\n```\n", "SUBSTANTIVE"),
        ("I-R4-2", "merging two list items into one run-on item",
         head + "- MUST do X\n- NOT Y\n",
         head + "- MUST do X - NOT Y\n", "SUBSTANTIVE"),
        ("I-R4-3", "appending a new row to an existing table",
         head + "| a | b |\n|---|---|\n| 1 | 2 |\n",
         head + "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n", "ADDITIVE"),
        ("I-R4-3", "appending a new item to an existing list",
         head + "- (A) must X\n- (B) must Y\n",
         head + "- (A) must X\n- (B) must Y\n- (C) must Z\n", "ADDITIVE"),
        ("I-R4-3", "appending a new sentence directly under an existing paragraph",
         head + "The gate MUST refuse a claim.\n",
         head + "The gate MUST refuse a claim.\nIt additionally logs the refusal.\n", "ADDITIVE"),
    )
    for finding, what, nb, na, want in r4_needles:
        got = classify_diff(nb, na)
        if got != want:
            return ("self-check FAILED (%s, fix round 4): rule-diff classifier classified %s "
                    "as %r, expected %r" % (finding, what, got, want))

    # FIX ROUND 5 needles. I-R5-1 (end-to-end through parse_anchor_blocks(), so BOTH halves of
    # the fix are exercised): a new anchor inserted between an existing anchor's text and its own
    # trailing `---` separator leaves that anchor UNCHANGED (real repro: commit 91aa99d).
    sep_before = ("### §11.4.905 -- rule-diff self-check separator needle (synthetic)\n\n"
                  "The 905 rule MUST hold.\n\n---\n\n"
                  "### §11.4.906 -- following anchor (synthetic)\n\nThe 906 rule MUST hold.\n")
    sep_after = sep_before.replace(
        "The 905 rule MUST hold.\n\n---\n",
        "The 905 rule MUST hold.\n\n### §11.4.907 -- new anchor (synthetic)\n\n"
        "The 907 rule MUST hold.\n\n---\n")
    got = classify_diff(parse_anchor_blocks(sep_before)["905"][0],
                        parse_anchor_blocks(sep_after)["905"][0])
    if got != "UNCHANGED":
        return ("self-check FAILED (I-R5-1, fix round 5): an anchor whose trailing '---' "
                "separator moved into a newly-inserted following anchor (its own text byte-"
                "unchanged) classified %r, expected 'UNCHANGED'" % got)
    head5 = "### §11.4.908 -- rule-diff self-check fix-round-5 needle anchor (synthetic)\n\n"
    r5_needles = (
        ("I-R5-1", "removing a mid-body thematic break between two unchanged paragraphs",
         head5 + "Para one MUST hold.\n\n---\n\nPara two MUST hold.\n",
         head5 + "Para one MUST hold.\n\nPara two MUST hold.\n", "STRUCTURAL"),
        ("I-R5-2", "un-nesting a qualifier bullet INSIDE a blockquote",
         head5 + "> - (A) rule\n>   - exception applies ONLY in test\n",
         head5 + "> - (A) rule\n> - exception applies ONLY in test\n", "SUBSTANTIVE"),
        ("I-R5-2", "dedenting YAML inside a code fence INSIDE a blockquote",
         head5 + "> ```yaml\n> parent:\n>   child: 1\n> ```\n",
         head5 + "> ```yaml\n> parent:\n> child: 1\n> ```\n", "SUBSTANTIVE"),
        ("I-R5-2", "appending a new item to a list INSIDE a blockquote",
         head5 + "> - (A) must X\n",
         head5 + "> - (A) must X\n> - (B) must Y\n", "ADDITIVE"),
        ("M-R5-1", "wrapping an existing rule in a multi-line HTML comment",
         head5 + "The rule MUST hold.\n",
         head5 + "<!--\n\nThe rule MUST hold.\n\n-->\n", "SUBSTANTIVE"),
        ("M-R5-3", "adding a setext underline directly under an existing paragraph",
         head5 + "The rule MUST hold.\n",
         head5 + "The rule MUST hold.\n---\n", "SUBSTANTIVE"),
        ("I-R5F-1", "inserting a column-0 blockquote between a parent bullet and its nested "
         "child (the quote terminates the list, so the child is no longer nested)",
         head5 + "- (A) Gates MUST refuse unverified claims.\n"
                 "  - Exception: applies ONLY in test fixtures.\n",
         head5 + "- (A) Gates MUST refuse unverified claims.\n\n> Note: see elsewhere.\n\n"
                 "  - Exception: applies ONLY in test fixtures.\n", "SUBSTANTIVE"),
    )
    for finding, what, nb, na, want in r5_needles:
        got = classify_diff(nb, na)
        if got != want:
            return ("self-check FAILED (%s, fix round 5): rule-diff classifier classified %s "
                    "as %r, expected %r" % (finding, what, got, want))
    return None


def _pair_occurrences(b_list, a_list):
    """Pairs the before/after occurrences of ONE anchor key -> (pairs, removed, added), where
    `pairs` is a list of (before_index, after_index) and `removed` / `added` are the before-side /
    after-side indices left over when the counts differ.

    FIX ROUND 5 (M-R5-2): (1) every BYTE-IDENTICAL occurrence is paired with an identical twin
    first, as a multiset, regardless of position (so reordering unchanged duplicates is never
    reported as a change); (2) the remaining occurrences are paired GREEDILY by highest content
    similarity (difflib ratio over lines, ties broken by lowest after- then before-index), never
    positionally inside a difflib `replace` run as round 4 did -- the reviewer's [A, B, G] ->
    [B, A, G + " Extra."] repro now pairs A-A, B-B, G-G' and reports ONE ADDITIVE hunk at the
    right after-index, instead of two SUBSTANTIVE hunks at the wrong ones; (3) whatever is left on
    the longer side is attributed to the count change. Round 4's M-R4-1 guarantee is preserved:
    deleting one of two distinct occurrences never mis-pairs the untouched survivor."""
    pairs = []
    free_b = list(range(len(b_list)))
    free_a = list(range(len(a_list)))
    for j in list(free_a):
        for i in free_b:
            if b_list[i] == a_list[j]:
                pairs.append((i, j))
                free_b.remove(i)
                free_a.remove(j)
                break
    scored = []
    for i in free_b:
        bl = b_list[i].splitlines()
        for j in free_a:
            ratio = difflib.SequenceMatcher(a=bl, b=a_list[j].splitlines(), autojunk=False).ratio()
            scored.append((-ratio, j, i))
    scored.sort()
    used_b, used_a = set(), set()
    for _neg, j, i in scored:
        if i in used_b or j in used_a:
            continue
        pairs.append((i, j))
        used_b.add(i)
        used_a.add(j)
    removed = [i for i in free_b if i not in used_b]
    added = [j for j in free_a if j not in used_a]
    return pairs, removed, added


def cmd_rule_diff(a):
    self_check_err = self_check_rule_diff()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    constitution_dir = a.constitution.rstrip("/") or "/"
    corpus_path = os.path.join(constitution_dir, "Constitution.md")
    after_text, after_err = _read_doc(corpus_path)
    if after_err:
        print("plan_struct_check: BLIND -- %s" % after_err, file=sys.stderr)
        return 4

    try:
        # MINOR remediation (independent review round 1): "<sha>:./Constitution.md" (a
        # repo-root-relative pathspec anchored at cwd, `git help revisions`'s own documented
        # form) rather than a bare "<sha>:Constitution.md" (a top-level-only tree path) -- robust
        # to `constitution_dir` being a sub-directory of the repository `git -C` actually
        # resolves to, rather than assuming it is always the repo's own top level.
        proc = subprocess.run(
            ["git", "-C", constitution_dir, "show", "%s:./Constitution.md" % a.base],
            capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        print("plan_struct_check: BLIND -- cannot run git show: %s: %s" % (type(exc).__name__, exc),
              file=sys.stderr)
        return 4
    if proc.returncode != 0:
        print("plan_struct_check: BLIND -- git show %s:Constitution.md failed (rc=%d) -- "
              "stderr: %s" % (a.base, proc.returncode, proc.stderr.strip()), file=sys.stderr)
        return 4
    before_text = proc.stdout

    before_blocks = parse_anchor_blocks(before_text)
    after_blocks = parse_anchor_blocks(after_text)
    if not before_blocks and not after_blocks:
        print("plan_struct_check: BLIND -- zero parseable anchor blocks in both --base %s and "
              "the current %s (no honest corpus to diff)" % (a.base, corpus_path), file=sys.stderr)
        return 4

    # I4 remediation (independent review round 1): SC-C-005 requires exemption to be backed by "a
    # referenced operator decision record", never a bare anchor number -- each entry MUST be
    # `<anchor>=<decision-record-reference>` (comma-separated pairs), and the reference used is
    # echoed back on the exempted hunk/removed-anchor's own --out JSON entry (the `exempted`
    # field) so the audit trail is inspectable, never merely implied by a violation's absence.
    operator_decisions = {}
    if a.operator_decisions:
        for tok in a.operator_decisions.split(","):
            tok = tok.strip()
            if not tok:
                continue
            if "=" not in tok:
                print("plan_struct_check: usage error -- --operator-decisions entry %r is not "
                      "in '<anchor>=<decision-record-reference>' form (SC-C-005 requires a "
                      "referenced operator decision record, never a bare anchor number)" % tok,
                      file=sys.stderr)
                return 2
            anchor_part, _, ref_part = tok.partition("=")
            anchor_part = anchor_part.strip()
            ref_part = ref_part.strip()
            if not anchor_part or not ref_part:
                print("plan_struct_check: usage error -- --operator-decisions entry %r must "
                      "name both a non-empty anchor and a non-empty decision-record reference"
                      % tok, file=sys.stderr)
                return 2
            operator_decisions[_bare_anchor_num(anchor_part)] = ref_part

    hunks = []
    violations = []
    occurrence_count_changes = []
    common = sorted(set(before_blocks) & set(after_blocks), key=lambda n: (len(n), n))
    for n in common:
        # NB1 remediation (independent §11.4.209 Opus-xhigh review round 2, review round 3): the
        # ORIGINAL code below compared ONLY `before_blocks[n][0]` / `after_blocks[n][0]` -- the
        # FIRST occurrence of each key -- so a change to (or outright deletion of) a SECOND
        # genuine occurrence of the SAME dotted anchor key (a real duplicate; see
        # parse_anchor_blocks()'s own "More than one genuine block-start for the SAME anchor
        # number ... is preserved as multiple list entries" convention) was invisible. Every
        # occurrence is now compared, by index; a MISMATCHED occurrence count between before/after
        # (a duplicate appearing or disappearing) is itself flagged as its own violation
        # (`anchor_occurrence_count_changed`), exempt-able via the SAME --operator-decisions
        # mechanism as any other change to this anchor. The single-occurrence case (before == 1
        # AND after == 1 occurrences, the overwhelming common case and every existing test's own
        # fixture shape) is UNCHANGED in its own JSON shape -- no new "occurrence" field is added
        # to a hunk/violation entry unless >1 occurrence genuinely exists on either side -- so this
        # remediation is additive-only for every already-passing single-occurrence assertion.
        full = _full_anchor(n)
        b_list = before_blocks[n]
        a_list = after_blocks[n]
        multi = len(b_list) > 1 or len(a_list) > 1
        # M-R4-1 REMEDIATION (independent review round 4, fix round 4): occurrences are now
        # PAIRED BY CONTENT, never by raw positional index -- a difflib pass over the occurrence
        # bodies themselves pairs every byte-identical occurrence with its own before-side twin
        # (so deleting the FIRST of two occurrences "Alpha"/"Beta" no longer mis-reports the
        # untouched surviving "Beta" as a substantive_change at occurrence 0), pairs changed
        # occurrences positionally only WITHIN a `replace` run, and attributes every unpaired
        # occurrence to the count change itself (`removed_occurrences` / `added_occurrences`,
        # before-side / after-side 0-based indices). `occurrence` on a hunk/violation is the
        # AFTER-side index (unchanged meaning for the common same-position case). FIX ROUND 5
        # (M-R5-2): the positional-within-replace step is replaced by exact-multiset-then-greedy-
        # similarity pairing -- see _pair_occurrences().
        pairs, removed_occ, added_occ = _pair_occurrences(b_list, a_list)
        if len(b_list) != len(a_list):
            # I-R4-1 REMEDIATION (independent review round 4, fix round 4): EVERY occurrence
            # count change is now recorded in --out (`occurrence_count_changes`), exempted or
            # not -- mirroring `removed_anchors`' own audit-trail pattern exactly: the entry
            # always carries `exempted: <decision-record-reference-or-null>`, and it is ALSO a
            # violation when unexempted. Previously an EXEMPTED count change was built as a dict
            # and then silently discarded, leaving NO trace (not even the decision reference) in
            # the output -- contradicting this tool's own I4 contract that every exemption names
            # the decision reference used, never implied by omission.
            decision_ref = operator_decisions.get(n)
            occurrence_count_changes.append({
                "anchor": full, "before_count": len(b_list), "after_count": len(a_list),
                "removed_occurrences": removed_occ, "added_occurrences": added_occ,
                "exempted": decision_ref})
            if decision_ref is None:
                violations.append({"code": "anchor_occurrence_count_changed", "anchor": full,
                                   "before_count": len(b_list), "after_count": len(a_list)})
        for i, j in sorted(pairs, key=lambda p: p[1]):
            cls = classify_diff(b_list[i], a_list[j])
            if cls == "UNCHANGED":
                continue
            hunk = {"anchor": full, "classification": cls, "exempted": None}
            if multi:
                hunk["occurrence"] = j
            if cls == "SUBSTANTIVE":
                decision_ref = operator_decisions.get(n)
                if decision_ref is None:
                    v = {"code": "substantive_change", "anchor": full}
                    if multi:
                        v["occurrence"] = j
                    violations.append(v)
                else:
                    hunk["exempted"] = decision_ref
            hunks.append(hunk)

    new_anchors = sorted(set(after_blocks) - set(before_blocks), key=lambda n: (len(n), n))
    removed_anchors = sorted(set(before_blocks) - set(after_blocks), key=lambda n: (len(n), n))

    # B2 remediation (independent review round 1): FR-022 requires a change "MUST NOT change the
    # substance of an existing rule" -- deleting (or renumbering, which this set-difference sees
    # as remove+new) a WHOLE anchor is the most substantive possible change to it, so it is a real
    # violation exactly like a SUBSTANTIVE hunk, exempt-able via the SAME --operator-decisions
    # mechanism (never a silent, purely-informational pass).
    removed_anchor_results = []
    for n in removed_anchors:
        full = _full_anchor(n)
        decision_ref = operator_decisions.get(n)
        removed_anchor_results.append({"anchor": full, "exempted": decision_ref})
        if decision_ref is None:
            violations.append({"code": "anchor_removed", "anchor": full})

    for v in violations:
        print("plan_struct_check: rule-diff: %s" % v, file=sys.stderr)

    body = {
        "constitution": a.constitution,
        "base": a.base,
        "hunks": hunks,
        "new_anchors": [_full_anchor(n) for n in new_anchors],
        "removed_anchors": removed_anchor_results,
        "occurrence_count_changes": occurrence_count_changes,
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA_RULE_DIFF,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        return write_rc
    return rc


# ---------------------------------------------------------------------------
# T179: `research` (SC-C-002, FR-003) and `plan` (SC-C-003, FR-004, FR-002's post-T-A11 half) --
# see module docstring for the full contract-clause coverage and the design rationale for each
# discovery mechanism below. Shared regex/parsing plumbing lives here; each parsing/classification
# function is independently self-checked (self_check_research / self_check_plan) against a
# synthetic, self-contained, in-memory fixture BEFORE any real --log/--plan/--tasks/--causes file
# is ever read -- the same §11.4.201/§11.4.273 control-needle discipline every earlier subcommand
# in this file already uses.
# ---------------------------------------------------------------------------

_DEC_HEADER_RE = re.compile(r"^### (DEC-[A-Za-z0-9-]+)\b")
_SOURCE_FIELD_RE = re.compile(r"^- \*\*Source:\*\*\s*(.*)$")
_ORIGIN_FIELD_RE = re.compile(r"^- \*\*Origin:\*\*\s*(.*)$")
_DEC_ID_RE = re.compile(r"\bDEC-[A-Za-z0-9-]+\b")
# FIX ROUND 4 (IMP-3, item 2): a case-INSENSITIVE sibling of `_DEC_ID_RE`, used ONLY inside
# `is_cited`'s own circular-self-reference detection below -- NEVER by `parse_plan_recommendation_
# ids` (which deliberately stays case-sensitive, matching real research.md/plan.md's own always-
# uppercase "DEC-NN" convention: widening THAT regex's case sensitivity would instead risk a
# genuinely lowercase-spelled cited decision id silently mismatching the (always-uppercase)
# `decisions` dict key it is later checked against, wrongly reporting it `dangling_decision_
# reference` -- a DIFFERENT and worse bug than the one this fix closes). "see dec-01" written on
# DEC-01's own Source field (lowercase, never matched by the original case-sensitive regex at all
# -- the field's ENTIRE circularity check was silently skipped whenever the citing decision's own
# id merely appeared in a different case) is now recognised as the same circular self-reference its
# uppercase spelling already was.
_DEC_ID_RE_CI = re.compile(r"\bDEC-[A-Za-z0-9-]+\b", re.IGNORECASE)
_PASS_ROW_RE = re.compile(r"^\|\s*[0-9]+\s*\|")

# REVIEW-ROUND-2 REMEDIATION (Minor-1, independent §11.4.209 Opus-xhigh review round 2 of T179):
# this file previously defined `_PLACEHOLDER_CORE_EXACT` / `_PLACEHOLDER_CORE_PREFIX` /
# `_normalized_core` / `_is_placeholder_text` TWICE (here, and again further below immediately
# before `parse_task_blocks`) -- a mutation-proven, genuinely DEAD duplicate: Python's module-level
# execution rebinds each of those four global names when the SECOND definition runs, so by the
# time any call site (including `is_cited` below, textually BETWEEN the two copies) is ever
# actually invoked, the module has finished loading and every one of those names resolves to the
# SECOND copy regardless of which copy `is_cited` was textually written next to -- editing this
# first copy had ZERO effect on real behaviour (the reviewer's own mutation proof), directly
# contradicting a since-removed inline comment that claimed the two definitions "never
# independently drift" (they were not even both live). The single, real, live implementation now
# lives ONLY once in this file -- see `_normalized_core` / `_is_placeholder_text` immediately
# above `parse_task_blocks` below -- shared, as before, by BOTH `is_cited` (Source fields) and
# `_tasks_cell_is_orphan` (Tasks-cell orphan-requirement check).


def parse_decision_log(text):
    """Returns {dec_id: source_text_or_None} for every `### DEC-<id>` entry found ANYWHERE in
    `text`, scanned by the heading's own shape alone -- deliberately never assuming a `## 3.
    Decision log` section wrapper exists first, since a minimal fixture (T178's own fixture 4/5)
    may declare a `### DEC-` entry with no such wrapper at all. Each entry's own `- **Source:**`
    field is captured from that label's own line through to (but not including) the entry's next
    `### ` heading, its next `- **` field, or the first blank line -- research.md's own Form
    ("Decision / Rationale / Alternatives considered / Source") places Source LAST, and several
    real entries wrap it across >1 physical line (e.g. DEC-02's own text), so a single-line-only
    capture would silently truncate those -- verified live against all 39 of the real document's
    own entries before choosing this design (constitution 11.4.6). `None` (not "") is returned for
    an entry with no `- **Source:**` field found at all, distinguishing "field present but blank"
    from "field wholly absent" for `is_cited()` below (both classify as uncited, but the raw value
    stays honest in the emitted JSON)."""
    lines = text.splitlines()
    starts = [(i, m.group(1)) for i, l in enumerate(lines) for m in [_DEC_HEADER_RE.match(l)] if m]
    out = {}
    for idx, (line_idx, dec_id) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        body = lines[line_idx:end]
        src_start = next((i for i, l in enumerate(body) if _SOURCE_FIELD_RE.match(l)), None)
        if src_start is None:
            out[dec_id] = None
            continue
        src_lines = [_SOURCE_FIELD_RE.match(body[src_start]).group(1)]
        j = src_start + 1
        while j < len(body) and body[j].strip() != "" and not body[j].startswith("### ") \
                and not body[j].startswith("- **"):
            src_lines.append(body[j].strip())
            j += 1
        out[dec_id] = " ".join(s for s in src_lines if s).strip()
    return out


# `_normalized_core` / `_PLACEHOLDER_CORE_EXACT` / `_PLACEHOLDER_CORE_PREFIX` / `_is_placeholder_
# text` / `_has_real_content` -- the SINGLE, live, shared placeholder/minimum-content-floor
# implementation `is_cited` (below) actually resolves against at call time -- are defined once,
# just above `parse_task_blocks` further down this file (review round 2, Minor-1: this used to be
# a genuinely dead SECOND copy here; see that block's own header comment for the full mutation-
# proof rationale for why it was removed rather than kept "in sync").


def is_cited(source_text, dec_id=None):
    """A `- **Source:**` field counts as CITED (SC-C-002/FR-003: "cites a source URL or the
    literal ... original work") when it carries any non-blank, non-placeholder, non-circular
    prose -- NOT only a URL/backtick-path/literal-marker shape (module docstring's own
    honest-boundary note: several of research.md's real §3 entries cite internal governance/spec
    references in a shape none of those three narrower forms recognise, e.g. DEC-38's
    "constitution §11.4.227; spec FR-019." -- a stricter path-shaped classifier would misclassify
    every one of those as uncited, exactly the guessing constitution 11.4.6 forbids).

    What IS recognised as UNCITED, narrowly:
      (1) the field is blank (None, or empty/whitespace-only after stripping);
      (2) the field's normalized core is one of the closed-set PLACEHOLDER markers, a TBD/TODO-
          prefixed phrase, or carries no MINIMUM-CONTENT FLOOR of real content at all
          (`_is_placeholder_text` -- review round 1, I1, expanded from the original exact-match-
          only five-token set to also reject "see above", a bare em-dash/hyphen, "none", "unknown",
          "TBD - to be filled", "TODO: find source", "N.A.", "tbd?"; review round 2, I-C, further
          expanded via a genuine minimum-content floor -- see `_has_real_content`'s own docstring --
          to ALSO reject "see below"/"TBA"/"TBC"/"to be determined"/"WIP"/"XXX"/"placeholder"/
          "fill in later"/"N/A (todo)", a bare run of underscores "___", and a single character
          such as "x" or "1" -- rather than growing the exact-match blocklist one reproduction at
          a time; fix round 4, IMP-3, further closes the hyphen/underscore-JOINED variant of this
          same class ("to-be-determined", "citation-needed", "fill_in_later") and raises the
          absolute floor to structurally exclude a bare non-digit 2-character word ("ok") while
          still admitting a genuine compact letter+digit reference ("R1") -- see `_has_real_
          content`'s own docstring for the exact rules, and `_is_placeholder_text`'s own docstring
          for the currently-known residual gaps this does NOT close);
      (3) CIRCULAR SELF-REFERENCE (review round 1, I1; review round 2, I-C; review round 3, I-3):
          when `dec_id` is supplied and EVERY `DEC-...` token the field names is the SAME decision
          citing itself as its own source (e.g. DEC-01's own Source field reading literally
          "DEC-01", OR "DEC-01 DEC-01" naming that same id twice over -- review round 3, I-3: the
          ORIGINAL check only ever matched a field naming its own id EXACTLY ONCE, so a field
          repeating its own id two or more times, with no OTHER decision's id ever appearing, was
          never even considered for circularity at all), AND the RESIDUAL text left once every one
          of those self-referencing `DEC-...` tokens is stripped back out is EITHER empty OR
          itself carries no real content once known FILLER WORDS are stripped from it (review
          round 2, I-C: "see DEC-01" written on DEC-01's own Source field is, in substance, a bare
          filler word "see" wrapped around a circular self-reference -- the SAME `_is_placeholder_
          text`/minimum-content-floor discrimination clause (2) already applies is now applied to
          the residual too, instead of only checking whether the residual is the empty string;
          review round 3, I-3: "ref DEC-01" and "per DEC-01" are the SAME pattern using two
          further synonyms for "see" -- `_FILLER_WORDS` now also names "REF" and "PER" so their
          own residuals are likewise recognised as filler-only rather than as genuine additional
          content; fix round 4, IMP-3, items 2/3: "cf. DEC-01"/"via DEC-01" are the SAME pattern
          using two FURTHER synonyms -- `_FILLER_WORDS` now also names "CF"/"VIA"/"VIDE"/"QV" --
          and "see dec-01" (lowercase) on DEC-01's own field is now ALSO recognised as this same
          circular self-reference: the id-token match this clause uses is case-INSENSITIVE, see
          `_DEC_ID_RE_CI`'s own header comment for why that case-insensitivity is scoped to
          exactly this check) -- a decision cannot be its own evidence. This is deliberately narrow: a field
          that cites its own id ALONGSIDE genuine additional content (e.g. "see DEC-01 and
          R3:12-14") is not flagged by this clause (the residual "and R3:12-14" clears the
          minimum-content floor), only a field whose SOLE content, once filler words are stripped,
          is the self-reference; a field naming its own id ALONGSIDE a genuinely DIFFERENT
          decision's id (e.g. "DEC-01, DEC-02") is likewise never flagged by this clause (the ids
          named are not ALL the same id), matching the contract's own "cites a source" reading --
          citing a DIFFERENT decision as one's own evidence is not circular, whatever else is true
          of it.

    HONESTLY NOT implemented (review round 1, I1's own disclosed limitation): a reference to a
    real-but-EXTERNAL identifier that resolves to nothing verifiable in this repo (e.g. "R99:1-2",
    naming a research-pass id that was never actually logged) is NOT rejected -- this field is
    checked for non-emptiness / non-placeholder-shape / non-circularity, never for whether its
    cited target genuinely EXISTS; resolving/verifying a citation target is a harder problem this
    file does not attempt, honestly disclosed rather than silently guessed at (constitution
    11.4.6)."""
    if source_text is None:
        return False
    stripped = source_text.strip().rstrip(".").strip()
    if not stripped:
        return False
    if dec_id is not None:
        # FIX ROUND 4 (IMP-3, item 2): `_DEC_ID_RE_CI` (case-insensitive) rather than `_DEC_ID_RE`
        # -- see that regex's own header comment for why the case-insensitivity is scoped to
        # exactly this circularity check.
        ids_in_source = _DEC_ID_RE_CI.findall(stripped)
        # review round 3 (I-3): generalised from "names its own id EXACTLY ONCE" to "every DEC-
        # id token the field names, however many times, is the SAME one id" -- a field repeating
        # its own citing decision's id two or more times (e.g. "DEC-01 DEC-01") names no OTHER
        # decision at all and is exactly as circular in substance as naming it once.
        if ids_in_source and {i.upper() for i in ids_in_source} == {dec_id.upper()}:
            residual = _DEC_ID_RE_CI.sub("", stripped).strip(" .;:-—")
            # review round 2 (I-C): a residual that is EMPTY, OR that is itself placeholder-shaped
            # / filler-only once the SAME minimum-content-floor discrimination applies to it, is
            # STILL a circular self-reference in substance -- "see DEC-01" on DEC-01's own field
            # names no real additional content beyond the filler word "see".
            if not residual or _is_placeholder_text(residual):
                return False  # circular: the field names ONLY its own citing decision's id
    return not _is_placeholder_text(stripped)


def parse_plan_recommendation_ids(text):
    """Returns the set of every DEC-id token appearing in ANY `- **Origin:**` field anywhere in a
    plan/tasks text -- the "plan recommendations" this file's citation check treats as needing a
    source (module docstring's own note: a §3 decision research.md carries but that no task ever
    actually adopted is, on this reading, not a "plan recommendation", and is honestly left
    unchecked)."""
    ids = set()
    for line in text.splitlines():
        m = _ORIGIN_FIELD_RE.match(line)
        if m:
            for idm in _DEC_ID_RE.finditer(m.group(1)):
                ids.add(idm.group(0))
    return ids


def count_research_passes(text):
    """Counts every `| <digits> | ...` row anywhere in `text` -- research.md's own §6 pass-log
    row shape, matching (independently re-implemented, never imported -- Producer != Verifier,
    constitution 11.4.240) the RED test's own self-check regex. Verified live against the real
    document to confirm no OTHER numbered table anywhere in research.md accidentally shares this
    shape (constitution 11.4.201(7): a control needle before trusting a count)."""
    return sum(1 for l in text.splitlines() if _PASS_ROW_RE.match(l))


def compute_research_violations(decisions, recommendation_ids, pass_count):
    """Runs every SC-C-002/FR-003 check `research` implements over already-parsed decision-log /
    plan-recommendation-id / research-pass-count data, and returns `(violations, decisions_out,
    dangling_ids)` -- review round 3 (M-3): the SINGLE, PRODUCTION code path BOTH `cmd_research`
    (the real run, over real documents) and `self_check_research` (over a synthetic control-needle
    fixture) now share, mirroring the EXACT `compute_plan_violations`/`self_check_plan` pattern
    review round 1 (I3) already established for `plan` (see that function's own docstring for the
    full rationale). Before this restructuring, `self_check_research` independently RE-IMPLEMENTED
    its own separate one-line expression for dangling-decision-reference detection (`sorted(rid
    for rid in rec_ids if rid not in decisions)`) rather than exercising `cmd_research`'s own
    production expression -- so a mutation to `cmd_research`'s OWN dangling-detection loop, or to
    its `insufficient_research_passes` threshold check, would have survived `self_check_research`
    untouched (though the slower, full RED-test suite would still have caught it): the fast,
    always-run self-check was NOT actually exercising the production violation-GENERATING code at
    all, only a parallel reimplementation that could silently drift out of sync with it
    (constitution 11.4.240, Producer != Verifier: the VERIFICATION must exercise the real
    production code path, never a hand-written duplicate of its logic).

    Per-clause coverage (contract SC-C-002/FR-003):
      - `uncited_recommendation` -- every decision genuinely REFERENCED by `recommendation_ids`
        whose own Source field `is_cited()` classifies as uncited (see `is_cited`'s own docstring
        for the full placeholder/circular-self-reference discrimination this delegates to).
      - `dangling_decision_reference` -- every id in `recommendation_ids` that does NOT exist in
        `decisions` at all (review round 1, I2) -- never silently ignored just because the
        per-decision loop above only ever iterates over decisions that genuinely exist.
      - `insufficient_research_passes` -- fewer than 3 recorded research-pass-log rows."""
    violations = []
    decisions_out = []
    for dec_id in sorted(decisions):
        source = decisions[dec_id]
        cited = is_cited(source, dec_id=dec_id)
        referenced = dec_id in recommendation_ids
        if referenced and not cited:
            violations.append({"code": "uncited_recommendation", "decision": dec_id,
                                "source": source})
        decisions_out.append({"id": dec_id, "source": source, "cited": cited,
                               "referenced_by_plan": referenced})

    # review round 1 (I2): a plan `- **Origin:**` field naming a DEC- id that does NOT exist
    # anywhere in --log's own decision log is itself a violation -- a dangling reference, never
    # silently ignored just because the loop above only ever iterates over decisions that DO
    # exist.
    dangling_ids = sorted(rid for rid in recommendation_ids if rid not in decisions)
    for rid in dangling_ids:
        violations.append({"code": "dangling_decision_reference", "decision": rid})

    if pass_count < 3:
        violations.append({"code": "insufficient_research_passes", "count": pass_count,
                            "required": 3})

    return violations, decisions_out, dangling_ids


_SELF_CHECK_RESEARCH_DOC = (
    "## 3. Decision log\n\n"
    "### DEC-NEEDLE-CITED -- self-check needle (has a real, non-placeholder citation)\n\n"
    "- **Decision:** d.\n"
    "- **Rationale:** r.\n"
    "- **Alternatives considered:** a.\n"
    "- **Source:** R1:1-2; constitution §1.1.\n"
    "\n"
    "### DEC-NEEDLE-UNCITED -- self-check needle (uncited placeholder)\n\n"
    "- **Decision:** d.\n"
    "- **Rationale:** r.\n"
    "- **Alternatives considered:** a.\n"
    "- **Source:** TBD\n"
    "\n"
    "### DEC-NEEDLE-SELFREF -- self-check needle (circular self-reference, review round 1 I1)\n\n"
    "- **Decision:** d.\n"
    "- **Rationale:** r.\n"
    "- **Alternatives considered:** a.\n"
    "- **Source:** DEC-NEEDLE-SELFREF\n"
    "\n"
    "## 6. Research pass log (FR-003)\n\n"
    "| Pass | Stream | Topic | What the pass changed |\n"
    "|---|---|---|---|\n"
    "| 1 | R1 | t | c |\n"
    "| 2 | R1 | t | c |\n"
)
# `DEC-NEEDLE-DANGLING` is DELIBERATELY not defined anywhere in `_SELF_CHECK_RESEARCH_DOC` above --
# review round 1 (I2): a real, self-contained control needle for the new dangling-decision-
# reference detector must reference an id that genuinely does not exist in the decision log.
_SELF_CHECK_RESEARCH_PLAN = (
    "#### T-NEEDLE -- self-check needle task\n\n"
    "- **Origin:** DEC-NEEDLE-CITED, DEC-NEEDLE-UNCITED, DEC-NEEDLE-SELFREF, "
    "DEC-NEEDLE-DANGLING.\n"
)


def self_check_research():
    """Returns None on success, else a diagnostic string (caller exits 3). Review round 3 (M-3):
    every check below still independently proves its own underlying PARSING/CLASSIFICATION
    function behaves on the synthetic fixture (unchanged discipline, matching `self_check_plan`'s
    own established layering), AND (the new part) feeds that SAME fixture through
    `compute_research_violations` -- the identical function `cmd_research` itself calls -- so a
    mutation to the real dangling-reference-detection or pass-count-threshold logic is caught here
    exactly as it would be by a real invocation, mirroring the EXACT restructuring review round 1
    (I3) already applied to `self_check_plan`/`compute_plan_violations` (see that function's own
    docstring for the full rationale)."""
    decisions = parse_decision_log(_SELF_CHECK_RESEARCH_DOC)
    expected_dec_ids = {"DEC-NEEDLE-CITED", "DEC-NEEDLE-UNCITED", "DEC-NEEDLE-SELFREF"}
    if set(decisions) != expected_dec_ids:
        return ("self-check FAILED: decision-log parser did not find exactly the 3 synthetic "
                 "control-needle entries (got %r)" % sorted(decisions))
    if not is_cited(decisions["DEC-NEEDLE-CITED"], dec_id="DEC-NEEDLE-CITED"):
        return ("self-check FAILED: known-cited synthetic Source line was WRONGLY classified as "
                 "uncited")
    if is_cited(decisions["DEC-NEEDLE-UNCITED"], dec_id="DEC-NEEDLE-UNCITED"):
        return ("self-check FAILED: known-uncited (TBD) synthetic Source line was WRONGLY "
                 "classified as cited (false negative, constitution 11.4.201(1))")
    if is_cited(decisions["DEC-NEEDLE-SELFREF"], dec_id="DEC-NEEDLE-SELFREF"):
        return ("self-check FAILED: a decision whose ENTIRE Source field is its own citing "
                 "decision's id (circular self-reference) was WRONGLY classified as cited "
                 "(review round 1, I1, false negative, constitution 11.4.201(1))")
    # I1 review-round-1 placeholder-vocabulary expansion, PLUS review round 3 (I-1)'s own
    # extension to every one of review round 2's own 12 non-citation reproductions ("see below",
    # "TBA", "TBC", "to be determined", "WIP", "XXX", "placeholder", "fill in later",
    # "N/A (todo)", a bare run of underscores "___", and a single character "x"/"1") -- NONE of
    # which had EVER been independently re-proven against `is_cited()` in this self-check before
    # round 3, despite having been fixed (via `_has_real_content`'s minimum-content floor) back in
    # round 2 -- every one of the reviewer's own reproductions, from EITHER round, is now
    # independently re-proven here directly against `is_cited()`, never merely assumed from having
    # edited the code.
    for bad in ("see above", "—", "-", "none", "unknown", "TBD - to be filled",
                "TODO: find source", "N.A.", "tbd?",
                # review round 2's own 12 non-citation reproductions (I-1, review round 3):
                "see below", "TBA", "TBC", "to be determined", "WIP", "XXX", "placeholder",
                "fill in later", "N/A (todo)", "___", "x", "1",
                # review round 3 (I-3): a further batch of concrete near-equivalent placeholder
                # phrases the round-3 reviewer's own reproductions surfaced.
                "to do", "TODOs", "citation needed", "[citation needed]", "no source", "missing",
                "not yet", "none yet", "xxxxxx", "T B D", "ТBD",
                # fix round 4 (IMP-3, item 1): the HYPHEN/UNDERSCORE-JOINED variant of several
                # already-known filler phrases -- previously bypassed the floor entirely because
                # joining concatenated the individually-filler words into one alphanumeric blob
                # (e.g. "to-be-determined" -> "tobedetermined", 14 characters) that trivially
                # cleared the length->=3 floor; see `_is_all_filler_compound`'s own docstring.
                "to-be-determined", "[citation-needed]", "to_be_determined", "fill_in_later",
                "none-yet", "not-yet", "no-source",
                # fix round 4: this round's OWN further adversarial variations on the same
                # hyphen/underscore-joining bypass class, beyond the reviewer's exact reproductions
                # -- a MIXED hyphen+underscore join, an all-underscore-joined synonym compound, and
                # a hyphenated form of an already-space-tested phrase.
                "to_be-determined", "citation_needed", "see-below",
                # fix round 4 (IMP-3, item 4): a bare, non-digit 2-character word -- previously
                # cleared the absolute minimum-content floor via the unconditional 2-character sum
                # fallback (any 2 alphanumeric characters, filler or not, summed to >=2); the floor
                # is now structurally digit-shaped for a 2-character token (see `_has_real_content`
                # own docstring) -- "ok" is the reviewer's own exact reproduction.
                "ok",
                # fix round 4: this round's OWN further adversarial variations beyond "ok" -- other
                # ordinary short, purely-alphabetic, NON-filler-listed English words that must
                # likewise fail to clear the raised floor on their own (deliberately distinct from
                # any word already individually listed in `_FILLER_WORDS`, so this genuinely
                # exercises the digit-shape floor rule rather than the ordinary filler-word check).
                "hi", "go"):
        if is_cited(bad):
            return ("self-check FAILED: known-uncited placeholder variant %r was WRONGLY "
                     "classified as cited (false negative, constitution 11.4.201(1))" % bad)
    # ... and the positive control: a real internal-governance-style citation (the SAME shape as
    # DEC-38's own real Source text, this module's long-standing example) must still be
    # recognised as genuinely cited -- proving the expanded vocabulary does not over-reject.
    if not is_cited("constitution §11.4.227; spec FR-019."):
        return ("self-check FAILED: a real, non-placeholder internal-citation shape was WRONGLY "
                 "classified as uncited by the review-round-1 placeholder-vocabulary expansion "
                 "(false positive over-rejection)")
    # review round 3 (I-1): the CIRCULAR-self-reference needle set -- "see DEC-01" written on
    # DEC-01's own Source field (a filler-word-wrapped circular self-reference) never had an
    # exercising needle anywhere before round 3, despite review round 2 (I-C) having explicitly
    # fixed exactly this case; "ref DEC-01"/"per DEC-01" (review round 3, I-3's own two further
    # "see"-synonym reproductions) and "DEC-01 DEC-01" (I-3's own repeated-same-id reproduction)
    # are likewise independently re-proven here directly against `is_cited()`.
    for bad_circular in (
            "see DEC-01", "ref DEC-01", "per DEC-01", "DEC-01 DEC-01",
            # fix round 4 (IMP-3, items 2/3): "cf."/"via" are two FURTHER "see"-synonyms (the
            # reviewer's own exact reproductions), and "see dec-01" (lowercase) is the SAME
            # circular self-reference the original case-sensitive id match never even recognised
            # as naming DEC-01 at all.
            "cf. DEC-01", "via DEC-01", "see dec-01",
            # fix round 4: this round's OWN further adversarial variations beyond the reviewer's
            # exact reproductions -- "vide"/"qv" (the two further synonyms added alongside cf/via),
            # and a MIXED-CASE self-reference id ("Dec-01") to prove the case-insensitivity is not
            # merely an all-lowercase special case.
            "vide DEC-01", "qv DEC-01", "see Dec-01"):
        if is_cited(bad_circular, dec_id="DEC-01"):
            return ("self-check FAILED: %r on DEC-01's own Source field (a circular "
                     "self-reference) was WRONGLY classified as cited (false negative, "
                     "constitution 11.4.201(1))" % bad_circular)
    # ... and its own positive control (review round 3, I-1): a field citing its own id ALONGSIDE
    # genuine additional content must still be recognised as genuinely cited -- proving the
    # circular-self-reference detection does not over-reject a real citation merely because it
    # also happens to mention its own decision's id.
    if not is_cited("see DEC-01 and R3:12-14", dec_id="DEC-01"):
        return ("self-check FAILED: 'see DEC-01 and R3:12-14' -- a self-reference ALONGSIDE "
                 "genuine additional content -- was WRONGLY classified as uncited (review round "
                 "3, I-1 positive control, false positive over-rejection)")

    # FIX ROUND 4 (Minor-1): individual load-bearing needles for "T"/"B"/"D" in `_FILLER_WORDS` --
    # the existing "T B D" bad-placeholder needle above does NOT individually distinguish any ONE
    # of the three letters (removing any single one from `_FILLER_WORDS` still leaves the OTHER two
    # skipped as filler and the lone survivor too short to reach the floor on its own either way, so
    # the overall "T B D" verdict never changes). Each letter is instead paired, via a hyphen, with
    # the already-independently-proven filler word "see" -- "see-T" is an ALL-filler hyphenated
    # compound (skipped entirely by `_is_all_filler_compound`) ONLY while "T" itself remains filler;
    # remove "T" from `_FILLER_WORDS` and the compound check finds a non-filler part, falls through
    # to the ordinary merged-alphanumeric path ("seeT", 4 characters), and WRONGLY clears the
    # length->=3 floor -- genuinely flipping `is_cited`'s own verdict, unlike the original combined
    # needle.
    for letter, compound in (("T", "see-T"), ("B", "see-B"), ("D", "see-D")):
        if is_cited(compound):
            return ("self-check FAILED: %r (an all-filler hyphenated compound pairing the "
                     "already-proven filler word 'see' with the letter %r) was WRONGLY classified "
                     "as cited -- this is the individual load-bearing needle for %r in "
                     "`_FILLER_WORDS` (fix round 4, Minor-1, false negative, constitution "
                     "11.4.201(1))" % (compound, letter, letter))

    # FIX ROUND 4 (IMP-3, item 4): the raised, digit-shaped 2-character floor must NOT over-reject
    # a genuinely short-but-valid reference -- "R1" (the reviewer's own exact reproduction, a
    # compact letter+digit citation) and "RFC" (a real, length->=3 abbreviation the ORIGINAL,
    # unraised floor already let through unconditionally, but which had no explicit self-check
    # needle proving it before this round) must both still be recognised as genuinely cited.
    if not is_cited("R1"):
        return ("self-check FAILED: 'R1' -- a genuine compact letter+digit reference, the exact "
                 "shape the raised 2-character floor is designed to still admit -- was WRONGLY "
                 "classified as uncited (fix round 4, IMP-3 item 4 positive control, false "
                 "positive over-rejection)")
    if not is_cited("RFC"):
        return ("self-check FAILED: 'RFC' -- a real, length->=3 short-but-valid reference -- was "
                 "WRONGLY classified as uncited (fix round 4, IMP-3 item 4 positive control, false "
                 "positive over-rejection)")

    # FIX ROUND 4 (Minor-6): the round-3 REF/PER filler-word additions must NOT regress a genuine
    # short section/paragraph-reference citation -- "per §3"/"ref §2"/"see §4" (the reviewer's own
    # exact reproductions) must all still be recognised as genuinely cited.
    for good_section_ref in ("per §3", "ref §2", "see §4"):
        if not is_cited(good_section_ref):
            return ("self-check FAILED: %r -- a genuine short section/paragraph-reference citation "
                     "-- was WRONGLY classified as uncited (fix round 4, Minor-6 positive control, "
                     "false positive over-rejection, a regression the round-3 REF/PER filler-word "
                     "additions introduced)" % good_section_ref)

    # FIX (T179 fix-loop, IMPORTANT-2, review round 5): a BARE section/paragraph mark with NOTHING
    # resembling an actual reference following it must NOT, by itself, satisfy the minimum-content
    # floor -- the previous per-token check returned "real content" the instant ANY "§"/"¶" byte
    # appeared anywhere in the field, regardless of what (if anything) followed it, so an obviously
    # placeholder-shaped field slipped through as genuinely "cited" purely because it happened to
    # contain a stray mark character.
    for bad_bare_mark in (
            "see § TBD", "per § TODO", "§ citation needed", "see ¶ tbd", "see §tbd",
            "§ to be determined", "see §"):
        if is_cited(bad_bare_mark):
            return ("self-check FAILED: %r -- a section/paragraph mark with NO real reference "
                     "following it -- was WRONGLY classified as cited (T179 fix-loop IMPORTANT-2, "
                     "false negative, constitution 11.4.201(1))" % bad_bare_mark)
    # ... and re-assert the positive controls directly alongside the new negative controls: a real
    # reference digit immediately following the mark must still be recognised as genuinely cited,
    # proving the fix narrows the bare-mark bypass without regressing the case it was built for.
    for good_section_ref_2 in ("per §3", "ref §2", "see §4"):
        if not is_cited(good_section_ref_2):
            return ("self-check FAILED: %r -- a genuine short section/paragraph-reference citation "
                     "-- was WRONGLY classified as uncited (T179 fix-loop IMPORTANT-2 positive "
                     "control, false positive over-rejection)" % good_section_ref_2)

    rec_ids = parse_plan_recommendation_ids(_SELF_CHECK_RESEARCH_PLAN)
    expected_rec_ids = expected_dec_ids | {"DEC-NEEDLE-DANGLING"}
    if rec_ids != expected_rec_ids:
        return ("self-check FAILED: plan-recommendation-id extractor did not find all 4 synthetic "
                 "DEC ids (3 real + 1 dangling) in the synthetic Origin field (got %r)"
                 % sorted(rec_ids))
    pass_count = count_research_passes(_SELF_CHECK_RESEARCH_DOC)
    if pass_count != 2:
        return ("self-check FAILED: research-pass-log counter miscounted the synthetic 2-row "
                 "table (got %d, expected 2)" % pass_count)

    # review round 3 (M-3): feed the SAME synthetic fixture through the REAL production violation
    # function, never a parallel reimplementation -- asserting the exact violation set (including
    # dangling-reference detection and the pass-count threshold) a mutation-proof self-check
    # requires, exactly mirroring `self_check_plan`'s own established (review round 1, I3) layering.
    violations, decisions_out, dangling_ids = compute_research_violations(
        decisions, rec_ids, pass_count)

    if dangling_ids != ["DEC-NEEDLE-DANGLING"]:
        return ("self-check FAILED: dangling-decision-reference detection (via the SAME production "
                 "function `cmd_research` itself calls) did not find exactly the one synthetic "
                 "dangling id planted above (got %r) -- review round 1, I2" % dangling_ids)

    def _has_research(code, decision):
        return any(v["code"] == code and v.get("decision") == decision for v in violations)

    research_checks = [
        (_has_research("uncited_recommendation", "DEC-NEEDLE-UNCITED"), True,
         "a referenced decision with a known-uncited (TBD) Source did NOT produce "
         "uncited_recommendation via the production violation function (review round 3, M-3)"),
        (_has_research("uncited_recommendation", "DEC-NEEDLE-CITED"), False,
         "a referenced decision with a known-cited Source WRONGLY produced uncited_recommendation "
         "via the production violation function (review round 3, M-3, false positive, "
         "constitution 11.4.201(1))"),
        (_has_research("uncited_recommendation", "DEC-NEEDLE-SELFREF"), True,
         "a referenced decision whose ENTIRE Source is its own circular self-reference did NOT "
         "produce uncited_recommendation via the production violation function (review round 3, "
         "M-3)"),
        (_has_research("dangling_decision_reference", "DEC-NEEDLE-DANGLING"), True,
         "the synthetic dangling id planted above did NOT produce dangling_decision_reference via "
         "the production violation function (review round 3, M-3)"),
        (any(v["code"] == "insufficient_research_passes" and v.get("count") == 2
             for v in violations), True,
         "the synthetic 2-row (< 3) research-pass-log table did NOT produce "
         "insufficient_research_passes via the production violation function (review round 3, "
         "M-3) -- catches a mutated `if pass_count < 3:` threshold check that a parallel "
         "reimplementation in the self-check itself would never exercise"),
    ]
    for actual, expected, msg in research_checks:
        if actual != expected:
            return "self-check FAILED: %s" % msg

    if {d["id"] for d in decisions_out} != expected_dec_ids:
        return ("self-check FAILED: the production violation function's own `decisions_out` "
                 "field did not report all 3 synthetic decision ids (got %r) -- review round 3, "
                 "M-3" % sorted(d["id"] for d in decisions_out))

    # FIX ROUND 4 (IMP-1): the `pass_count < 3` threshold itself had NO boundary needle anywhere
    # in this self-check -- the fixture's own real pass_count is always exactly 2 (comfortably
    # below any plausible threshold), so relying on that alone never proves the check's exact
    # VALUE or its `<`-not-`<=` OPERATOR are genuinely wired: a mutated `if pass_count < 3:` ->
    # `if pass_count < 4:` (a wrong threshold VALUE) or `<=` in place of `<` (a wrong boundary
    # OPERATOR) both previously survived untouched, since neither is ever exercised AT the real
    # boundary itself. Direct-call both polarities, at the boundary, against the SAME production
    # function `cmd_research` itself calls (never a parallel reimplementation, constitution
    # 11.4.240).
    v_passes_at_3, _, _ = compute_research_violations({}, set(), 3)
    if any(v["code"] == "insufficient_research_passes" for v in v_passes_at_3):
        return ("self-check FAILED: pass_count=3 (the contract's own '>= 3 passes' floor, exactly "
                 "met) WRONGLY produced insufficient_research_passes -- catches a wrong boundary "
                 "operator `<=` in place of `<` (fix round 4, IMP-1, false positive, constitution "
                 "11.4.201(1))")
    v_passes_at_2, _, _ = compute_research_violations({}, set(), 2)
    if not any(v["code"] == "insufficient_research_passes" for v in v_passes_at_2):
        return ("self-check FAILED: pass_count=2 (one below the required floor) did NOT produce "
                 "insufficient_research_passes -- catches a wrong threshold VALUE such as `< 4` "
                 "(fix round 4, IMP-1)")
    return None


def cmd_research(a):
    self_check_err = self_check_research()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    log_text, err = _read_doc(a.log, "--log")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4
    plan_text, err = _read_doc(a.plan, "--plan")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4

    decisions = parse_decision_log(log_text)
    pass_count = count_research_passes(log_text)
    if not decisions and pass_count == 0:
        print("plan_struct_check: BLIND -- --log %s has zero parseable decision-log entries and "
              "zero research-pass-log rows (no honest research document to check)" % a.log,
              file=sys.stderr)
        return 4

    recommendation_ids = parse_plan_recommendation_ids(plan_text)
    if decisions and not recommendation_ids:
        # review round 1 (I2): decisions genuinely exist, but --plan's own Origin fields cite NONE
        # of them by id at all -- the per-decision citation-quality loop below has literally
        # nothing to examine (every decision's own Source could be a bare placeholder and this
        # check would silently find zero violations, a FALSE PASS rather than an honest verdict:
        # constitution 11.4.201(6), a quiet zero here is a false-null, not evidence the citations
        # are fine). This mirrors, and extends, the "zero decisions and zero pass-log rows" BLIND
        # case immediately above to the symmetric "decisions exist but nothing references them"
        # case -- an EMPTY `--plan` document (or one with no `- **Origin:**` field naming any
        # DEC- id) falls into this SAME branch.
        print("plan_struct_check: BLIND -- --plan %s has zero '- **Origin:**' fields referencing "
              "any of --log %s's %d decision(s) by id (nothing to check for citation quality)"
              % (a.plan, a.log, len(decisions)), file=sys.stderr)
        return 4

    # review round 3 (M-3): the SINGLE, PRODUCTION violation-generating function, shared verbatim
    # with `self_check_research`'s own synthetic-fixture proof -- see `compute_research_violations`
    # own docstring for the full rationale.
    violations, decisions_out, dangling_ids = compute_research_violations(
        decisions, recommendation_ids, pass_count)

    for v in violations:
        print("plan_struct_check: research: %s" % v, file=sys.stderr)

    body = {
        "log": a.log,
        "plan": a.plan,
        "decisions": decisions_out,
        "dangling_decision_references": dangling_ids,
        "passes": {"count": pass_count, "required": 3},
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA_RESEARCH,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        return write_rc
    return rc


# --- `plan` plumbing ---------------------------------------------------------------------------

_TASK_BLOCK_START_RE = re.compile(r"^#### (T-\S+)")
_ROLLBACK_FIELD_RE = re.compile(r"^- \*\*Rollback:\*\*\s*(.*)$")
_REMOVES_FIELD_RE = re.compile(r"^- \*\*Removes / measures:\*\*\s*(.*)$")
_SERVES_FIELD_RE = re.compile(r"^- \*\*Serves:\*\*\s*(.*)$")
# review round 1 (B2, P1/P2): field regexes for the two remaining SC-C-003 per-task fields this
# file did not previously parse at all -- `Expected saving -> measurement:` (real plan.md's own
# label uses the Unicode arrow "->"; T178's own fixtures use the ASCII "->"; `[^*]*` matches
# either, and any other non-"*" text between the two words and the closing "**", without matching
# past the field's own closing bold marker) and `Protecting tests:`.
_EXPECTED_SAVING_FIELD_RE = re.compile(r"^- \*\*Expected saving[^*]*:\*\*\s*(.*)$", re.IGNORECASE)
_PROTECTING_TESTS_FIELD_RE = re.compile(r"^- \*\*Protecting tests:\*\*\s*(.*)$")
# review round 2 (Borderline-Important): the trailing `\s*$` anchor below ORIGINALLY required the
# header row to end immediately after the "Tasks" column -- a table declaring one EXTRA trailing
# column (e.g. "| Requirement | Tasks | Notes |", a real 3-column shape) never matched this regex
# AT ALL, so PATH 1 silently treated the whole table as absent and none of its rows -- including a
# genuinely orphaned one -- were ever checked. Dropping the trailing anchor makes the match
# tolerant of any additional trailing columns while still requiring the mandatory
# "| Requirement | Tasks |" PREFIX shape (matched via `.match()`, which never requires the WHOLE
# line to match, only that it start this way).
_REQ_TABLE_HEADER_RE = re.compile(r"^\|\s*Requirement\s*\|\s*Tasks\s*\|", re.IGNORECASE)
# review round 3 (M-1): the ORIGINAL character class `[-\s|]` did not include `:` -- a standard,
# extremely common GitHub-Flavored-Markdown column-alignment separator row (e.g.
# "|:---|:---:|", real GFM syntax for left/center/right-aligned columns) therefore never matched
# this regex at all, so `parse_requirements_table`'s own row loop fell through to the ordinary
# `_TABLE_ROW_GENERIC_RE` row match below and reported the separator row itself as
# `table_row_unparseable` -- a spuriously-reported finding against a perfectly well-formed,
# standard-syntax document. Widening the character class to also accept `:` fixes this without
# weakening the check: a genuine data row's first cell always names an `[A-Z]+-id` token (matched
# by `_REQ_ID_CELL_ID_RE` further down), which a `:`/`-`/`|`/whitespace-only separator row never
# does, so the two shapes remain unambiguous.
_TABLE_SEP_ROW_RE = re.compile(r"^\|[-\s|:]+\|$")
# review round 1 (I4): the original `_TABLE_ROW_RE` required the WHOLE first cell to be exactly
# one bare id (`^\|\s*([A-Z]+-[A-Za-z0-9-]+)\s*\|...`) -- a bold-wrapped id ("**FR-001**") or a
# comma-joined multi-id cell ("FR-001, FR-003") never matched it at all, and a non-matching line
# was silently treated as "the table ended" (a `break`), permanently hiding every genuinely
# orphaned row AFTER it too. `_TABLE_ROW_GENERIC_RE` now only carves the line into its two raw
# `|`-delimited cells (no assumption about the first cell's own shape); `_REQ_ID_CELL_ID_RE` is
# then run over that whole raw cell text via `findall` (never `match`), so it finds every
# `[A-Z]+-id` token inside it regardless of surrounding `**`/`,` decoration -- one table row can
# now genuinely declare >1 requirement id, and a bold-wrapped single id is found exactly as
# a bare one would be. A row-shaped line (starts with "|", not the separator row) whose first
# cell names NO such id at all is reported as `table_row_unparseable` rather than silently
# skipped or (worse) mistaken for the table's own end.
# review round 2 (Borderline-Important): the trailing `\s*$` ORIGINALLY required a row to end
# immediately after its second (Tasks) cell -- a row under a 3-column ("| Requirement | Tasks |
# Notes |") table never matched at all, so its Requirement/Tasks cells were reported as
# `table_row_unparseable` even though they were perfectly well-formed. Dropping the trailing
# anchor makes this match tolerant of any trailing columns after the Tasks cell (the two captured
# groups are always the FIRST two `|`-delimited cells, via the same lazy `.*?` carving as before --
# whatever follows the second cell's own closing "|" is simply not consumed); a genuinely
# malformed row (e.g. missing a closing "|" entirely) still fails to match at all, exactly as
# before, since `.match()` still requires the mandatory `|cell|cell|` PREFIX shape to be present.
_TABLE_ROW_GENERIC_RE = re.compile(r"^\|\s*(.*?)\s*\|\s*(.*?)\s*\|")
_REQ_ID_CELL_ID_RE = re.compile(r"\b([A-Z]+-[A-Za-z0-9-]+)\b")
# review round 1 (I4): task ids named inside a Tasks cell (e.g. "T-A01, T-A02" or "`T-B04`") --
# used to verify a cited task both EXISTS and genuinely claims (via its own Serves field) to
# cover the row, never merely that its id string appears somewhere in the cell's own text.
_CELL_TASK_ID_RE = re.compile(r"\bT-[A-Za-z0-9-]+\b")
_SCOPE_DECLARATION_RE = re.compile(r"^\*\*Scope[^*]*\*\*:\s*implements\b(.*)$", re.IGNORECASE)
_REQ_ID_RE = re.compile(r"\b(?:FR|SC)-[A-Za-z0-9-]+\b")
# review round 1 (B2, P2): an RC- id token appearing anywhere in a task's own Removes/measures
# field text -- cross-checked against the real cause universe (`--causes`'s own `id` values) so a
# task naming a cause that does not actually exist in the register (a typo, or a cause that was
# never classified) is caught, rather than silently accepted just because the cell is non-blank.
_RC_ID_IN_TEXT_RE = re.compile(r"\bRC-[A-Za-z0-9-]+\b")
_PERMANENT_GAP_RE = re.compile(r"permanent gap", re.IGNORECASE)
# review round 1 (B1): the ORIGINAL escape-hatch check matched the bare PHRASE "permanent gap"
# ANYWHERE in the combined --plan/--tasks text -- document-wide, never scoped to any one cause --
# so a single mention of the phrase in plan.md's own RULE-DESCRIPTION prose (explaining what the
# escape hatch IS, e.g. "... a named permanent gap ...", real plan.md's own Phase-A exit-criteria
# row and its own T-A11 task block) silently excused EVERY CONFIRMED-but-UNMEASURED row in the
# WHOLE document at once, regardless of whether that specific row had ever been given a genuine,
# individually-linked gap note. Two concrete reproductions from the reviewer, both now fixed by
# scoping the match PER-CAUSE via `_PERMANENT_GAP_MARKER_RE` below: (a) two different CONFIRMED/
# UNMEASURED rows where only ONE carries a genuine per-row gap note -- previously BOTH were
# excused, now only the one actually named is; (b) a document containing the NEGATION "There is no
# permanent gap recorded." -- the bare-phrase regex still matched (case-insensitively) and excused
# everything; the new marker shape requires a specific cause id AND a dash-introduced reason
# immediately after "permanent gap:", which a negation sentence never carries, so it now correctly
# excuses nothing. The new, real per-cause marker SYNTAX this file recognises (a project-level
# decision this fix introduces, since neither the contract nor research.md/plan.md previously
# defined any concrete marker shape at all -- module docstring's own honest disclosure, clause
# (f), already flagged this as an open question "to be corrected by whichever task actually
# re-runs this checker after T-A11 lands"): a line containing `permanent gap: RC-<id> -- <reason>`
# (case-insensitive on the phrase; the id and a following dash-introduced reason are REQUIRED --
# a bare mention of the phrase with no id+dash shape immediately after the colon names no cause
# and excuses nothing).
_PERMANENT_GAP_MARKER_RE = re.compile(
    r"permanent gap\s*:\s*(RC-[A-Za-z0-9-]+)\s*[-–—]+\s*\S", re.IGNORECASE)
# review round 1 (B2, P7): spec.md's own `- **FR-NNN**:` / `- **SC-NNN**:` bold-header lines (its
# real, verified shape, spec.md:178-202/228-255) name the FIXED, canonical FR-001..FR-025/
# SC-001..SC-010 universe SC-C-003's full bipartite check requires ("every FR-001..FR-025 and
# SC-001..SC-010 has >=1 task") -- independent of whichever subset the PLAN document itself
# happens to declare covering via its own traceability table or scope preamble (paths 1/2 below).
_SPEC_REQ_HEADER_RE = re.compile(r"^- \*\*((?:FR|SC)-[A-Za-z0-9-]+)\*\*:")

_WORDS_PER_PAGE_EQUIVALENT = 500.0


def _words_to_pages_equivalent(words):
    """Single, shared conversion of a raw word count into the contract's own pages-equivalent unit
    (`below_size_threshold`'s own floor, module docstring (d): 30 pages-equivalent * 500 words/
    page). FIX ROUND 4 (IMP-2): previously computed INDEPENDENTLY, via the SAME literal `words /
    500.0` expression, in BOTH `cmd_plan` (the real run) and `self_check_plan`'s own fixture setup
    -- a parallel reimplementation of the CONVERSION step, precisely the class review round 1
    (I3) / review round 3 (M-3) already closed for the violation-GENERATING logic itself
    (constitution 11.4.240, Producer != Verifier), just one step earlier in the pipeline: a
    mutation to the REAL `cmd_plan` divisor (e.g. `/ 100.0`, silently turning the documented
    "30-page floor" into a 3,000-word floor, or `/ 3000.0`, silently turning it into a 180,000-word
    floor) was previously INVISIBLE to `self_check_plan`, which recomputed its own separate copy of
    the division rather than exercising this function -- see `self_check_plan`'s own word-count
    boundary needles (14999/15000 words) for the direct-call proof this function is genuinely
    wired into both callers."""
    return words / _WORDS_PER_PAGE_EQUIVALENT


def _normalized_core(text):
    """Normalizes `text` for placeholder-SHAPE matching (review round 1, I1/I4): every non-word
    character (hyphens, dashes incl. the Unicode em-dash, slashes, periods, question marks,
    colons, whitespace) becomes a single space, runs of whitespace collapse to one, and the
    result is upper-cased and stripped. Returns "" for text carrying no word character at all
    (e.g. a bare "-" or "—" or "?")."""
    core = re.sub(r"[^\w]+", " ", text, flags=re.UNICODE)
    return re.sub(r"\s+", " ", core).strip().upper()


# Shared, closed placeholder vocabulary (review round 1, I1/I4) -- used by BOTH `is_cited`
# (research.md Source fields) and `_tasks_cell_is_orphan` (plan.md/tasks.md Tasks cells) so the
# two never independently drift on what counts as "not really a value". EXACT-match tokens are
# typically used as a bare marker on their own ("none", "unknown"); TBD/TODO are ADDITIONALLY
# matched as a PREFIX because real-world usage often carries trailing prose while remaining, in
# substance, an unfilled placeholder ("TBD - to be filled", "TODO: find source") -- the other
# tokens are deliberately NOT prefix-matched, so a genuine sentence merely starting with one of
# those English words (e.g. "None of the found packages fit; ...") is never misclassified.
_PLACEHOLDER_CORE_EXACT = frozenset((
    "TBD", "TODO", "N A", "NA", "PENDING", "NONE", "UNKNOWN", "SEE ABOVE",
))
_PLACEHOLDER_CORE_PREFIX = ("TBD", "TODO")

# REVIEW-ROUND-2 REMEDIATION (I-C, independent §11.4.209 Opus-xhigh review round 2 of T179): the
# whole-field EXACT-match vocabulary above still let a whole CLASS of trivially-short-or-filler-
# only text wrongly pass as "cited"/"not orphan" -- the reviewer's own concrete reproductions:
# "see below" (only "see above" was ever listed), "TBA", "TBC", "to be determined", "WIP", "XXX",
# "placeholder", "fill in later", "N/A (todo)", a bare run of underscores "___", and a single
# character such as "x" or "1". Rather than keep growing `_PLACEHOLDER_CORE_EXACT` one
# reproduction at a time, `_FILLER_WORDS` names individual WORDS (not whole-field phrases) that
# never count as real content even mixed with each other, and `_has_real_content()` below applies
# a genuine MINIMUM-CONTENT FLOOR over them -- closing this BROAD, but not exhaustive, class of
# known bypasses at once (constitution 11.4.201(7)(a): match structure, not one more literal
# string) -- see `_has_real_content`'s own docstring for the exact set of floor rules this applies,
# and `_is_placeholder_text`'s own docstring for the currently-known residual gaps this does NOT
# close.
#
# REVIEW-ROUND-3 REMEDIATION (I-3, independent §11.4.209 Opus-xhigh review round 3 of T179): the
# round-2 vocabulary STILL let a further batch of concrete near-equivalents slip through as
# genuinely "cited"/"not orphan" -- the round-3 reviewer's own reproductions "to do" ("TO" alone
# was already filler, "DO" was not), "TODOs" (the plural/suffixed form of the already-listed exact
# "TODO"), "citation needed"/"[citation needed]", "no source", "missing", "not yet"/"none yet"
# ("NONE" alone was already filler, "YET" was not), and the two circular-self-reference SYNONYMS
# for the already-listed filler word "SEE" -- "ref DEC-01" and "per DEC-01" (see `is_cited`'s own
# updated docstring, clause (3), for why a residual of bare "ref"/"per" must be treated exactly
# like a residual of bare "see"). Per the round-3 reviewer's own explicit guidance, this is a
# DELIBERATELY BOUNDED, concrete-reproduction-driven expansion -- see `_is_placeholder_text`'s own
# docstring for the honestly-disclosed remaining gaps this expansion does NOT close.
#
# FIX ROUND 4 (IMP-3, item 3, independent §11.4.209 Opus-xhigh review round 4 of T179): "CF"/"VIA"/
# "VIDE"/"QV" -- four further common academic/legal "see also" abbreviations, the SAME class as the
# already-listed "REF"/"PER" -- close "cf. DEC-01"/"via DEC-01" (direct siblings of the already-
# fixed "ref DEC-01"/"per DEC-01") as circular self-references, and (paired with the Minor-6 fix in
# `_has_real_content` below) prevent a legitimate short section reference such as "per §3" from
# being wrongly swept up now that "per" itself is filler-stripped.
_FILLER_WORDS = frozenset((
    "SEE", "ABOVE", "BELOW", "TBD", "TODO", "TBA", "TBC", "TO", "BE", "DETERMINED", "WIP", "XXX",
    "PLACEHOLDER", "FILL", "IN", "LATER", "N", "A", "NA", "PENDING", "NONE", "UNKNOWN",
    # review round 3 (I-3) additions -- see the header comment immediately above for the concrete
    # reproduction each one closes.
    "DO", "TODOS", "CITATION", "NEEDED", "NO", "SOURCE", "MISSING", "NOT", "YET", "REF", "PER",
    "T", "B", "D",
    # fix round 4 (IMP-3, item 3) additions -- see the header comment immediately above.
    "CF", "VIA", "VIDE", "QV",
))

# review round 3 (I-3): a small, DELIBERATELY NARROW table of Cyrillic letters that are visually
# IDENTICAL to a Latin look-alike -- the well-known "homoglyph" confusable set real phishing/
# spoofing content actually uses (e.g. a Cyrillic "а" (U+0430) substituted for a Latin "a" in
# "аpple.com"). The reviewer's own concrete reproduction is a placeholder marker spelled "ТBD"
# where the leading "Т" is Cyrillic capital TE (U+0422), not Latin "T" (U+0054) -- byte-for-byte
# distinct from the exact-match/prefix vocabulary above, so it silently passed as genuinely cited
# before this normalization. Deliberately narrow: only the classic, universally-recognised
# confusable pairs are mapped (constitution 11.4.6 -- a broader transliteration table risks
# mangling genuine non-Latin-script content, e.g. real Cyrillic prose, in ways this file has not
# verified are safe); genuinely non-Latin-script CONTENT (as opposed to a Latin-lookalike
# placeholder spelled in the wrong script) remains a SEPARATE, already- and still-honestly-
# disclosed limitation (see `_has_real_content`'s own docstring, the ASCII-only alnum count).
_HOMOGLYPH_TRANSLATION = str.maketrans({
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H",
    "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y",
    "х": "x",
})


def _normalize_homoglyphs(text):
    """Translates the small, closed set of Cyrillic/Latin look-alike characters `_HOMOGLYPH_
    TRANSLATION` names into their Latin equivalent (review round 3, I-3) -- applied once, up
    front, inside `_is_placeholder_text` below, so a placeholder marker spelled using a Cyrillic
    look-alike letter (e.g. "ТBD" with a Cyrillic "Т") is recognised by the SAME exact-match/
    minimum-content-floor machinery that already recognises its genuine-Latin-script spelling,
    rather than needing its own separate, growing blocklist entry."""
    return text.translate(_HOMOGLYPH_TRANSLATION)


_WORD_SPLIT_RE = re.compile(r"[-_]+")
# FIX ROUND 4 (IMP-3, item 1): matches a genuine formal section/paragraph-reference MARK -- the
# CLASS a real, legitimate short citation ("per §3", "ref §2", "see §4") uses, distinct from an
# ordinary English word -- see `_has_real_content`'s own docstring, the Minor-6 fix, for the full
# rationale.
_SECTION_MARK_RE = re.compile(r"[§¶]")
# FIX (T179 fix-loop, IMPORTANT-2, review round 5): a BARE section/paragraph mark with NOTHING
# resembling an actual reference following it (a raw "§"/"¶" byte inside placeholder-shaped text
# such as "see § TBD", "per § TODO", "§ citation needed", "see §tbd", "§ to be determined", or a
# lone trailing "see §") must NOT, by itself, satisfy the minimum-content floor -- only a mark
# IMMEDIATELY FOLLOWED (allowing a single intervening space, matching how a human actually writes
# "§ 3" as well as "§3") by a DIGIT is a genuine section/paragraph-NUMBER reference. A following
# ALPHABETIC character is deliberately excluded here (unlike a bare alphanumeric-class match) --
# "§tbd" must still fall through to the ordinary filler-word check below (where "TBD" is already a
# known `_FILLER_WORDS` entry) rather than being waved through purely because a letter happens to
# sit next to the mark; every one of this module's own real positive-control examples ("per §3",
# "ref §2", "see §4") is a mark directly followed by a digit, so this is not a narrowing of any
# genuine, already-proven-real usage.
_SECTION_MARK_REF_RE = re.compile(r"[§¶]\s?[0-9]")


def _is_all_filler_compound(tok):
    """True iff `tok` is hyphen/underscore-JOINED into >=2 parts and EVERY one of those parts is,
    on its own, a known `_FILLER_WORDS` entry (fix round 4, IMP-3, item 1). Closes the HYPHEN/
    UNDERSCORE-JOINING bypass class: `_has_real_content` below strips ALL non-alphanumeric
    characters (including internal hyphens/underscores) from a token BEFORE measuring its length,
    so "to-be-determined" previously concatenated into the single blob "tobedetermined" (14
    alphanumeric characters) and trivially cleared the length floor -- even though every one of its
    three constituent WORDS ("to", "be", "determined") is, individually, already a known filler
    word. Splitting FIRST, and checking each resulting part against the SAME closed vocabulary,
    catches "to-be-determined"/"citation-needed"/"[citation-needed]"/"to_be_determined"/
    "fill_in_later"/"none-yet"/"not-yet"/"no-source" as one structural class, rather than adding a
    whole-blob exact-match entry per hyphenated variant.

    Deliberately does NOT also apply the repeated-"X"-run rule (`set(upper) == {"X"}`, used
    elsewhere for a whole placeholder marker like "xxxxxx") to an individual compound PART: a real
    task/requirement id fragment such as the literal single letter "X" appearing as one hyphen-
    separated component of an otherwise-genuine identifier is never, by itself, evidence the WHOLE
    hyphenated token is a filler compound -- only an EXACT `_FILLER_WORDS` membership match on a
    part counts here, the same discrimination already used for an ordinary bare filler word.

    A token with NO internal hyphen/underscore at all (fewer than 2 non-empty parts) is never
    "all-filler-compound" by this function -- an ordinary single filler word (e.g. "see") is
    already caught by `_has_real_content`'s own per-token check further down, unaffected by this
    function."""
    parts = [p for p in _WORD_SPLIT_RE.split(tok) if p]
    if len(parts) < 2:
        return False
    saw_any_alnum_part = False
    for part in parts:
        alnum = re.sub(r"[^A-Za-z0-9]", "", part)
        if not alnum:
            continue
        saw_any_alnum_part = True
        if alnum.upper() not in _FILLER_WORDS:
            return False
    return saw_any_alnum_part


def _has_real_content(text):
    """True iff `text` carries at least a minimum floor of real, non-filler content (review round
    2, I-C). Tokenized on WHITESPACE only (deliberately NEVER fully punctuation-split the way
    `_normalized_core` is, so a compound reference shape like "R3:12-14" or "DEC-38" is judged as
    ONE token and never fragmented into separate short pieces that would each fall under the
    length floor on their own -- preserving `is_cited`'s own documented "see DEC-01 and R3:12-14"
    example, where "R3:12-14" alone must still count as real content). Each whitespace-token is
    stripped of LEADING/TRAILING punctuation only (`string.punctuation`; a token consisting
    ENTIRELY of punctuation, e.g. a bare run of underscores "___", therefore strips down to nothing
    and is silently skipped, never counted).

    FIX ROUND 4 (IMP-3, item 1): before anything else, a token that is hyphen/underscore-JOINED
    into >=2 parts where EVERY part is, on its own, a known filler word (`_is_all_filler_compound`
    above) contributes NOTHING toward the floor -- closing the class of filler words concatenated
    across a hyphen/underscore that previously merged into one long alphanumeric blob and trivially
    cleared the length floor (see that function's own docstring for the full rationale and worked
    examples).

    FIX ROUND 4 (Minor-6): a token carrying a genuine section/paragraph-reference MARK ("§"/"¶")
    contributes real content on its own, regardless of how few alphanumeric characters follow the
    mark -- closes a regression the round-3 (I-3) "REF"/"PER" filler-word additions introduced:
    once "per"/"ref"/"see" became filler words, a real, legitimate short citation such as "per §3"/
    "ref §2"/"see §4" was wrongly reclassified UNCITED, because "§" itself carries no alphanumeric
    character for the length floor to count and the trailing digit alone (e.g. "3") is too short.

    Otherwise, the remaining alphanumeric characters of a surviving token are compared, case-
    insensitively, against the closed `_FILLER_WORDS` vocabulary -- an EXACT match contributes
    NOTHING toward the floor. The floor is met when: (a) >=1 surviving token has >=3 alphanumeric
    characters on its own; OR (b) FIX ROUND 4 (IMP-3, item 4) a surviving token has EXACTLY 2
    alphanumeric characters AND is STRUCTURALLY reference-shaped -- it either contains >=1 digit (a
    compact letter+digit reference, e.g. "R1", "T1") OR it still carries INTERNAL non-alphanumeric
    punctuation once its own leading/trailing punctuation has already been stripped (e.g. "T-X", a
    hyphenated id fragment merging to the bare 2-character blob "TX" -- `_is_all_filler_compound`
    above already rejects a GENUINELY all-filler hyphenated compound, so a token that reaches this
    far and still carries internal punctuation is one where at least one hyphen/underscore-
    separated part was a real, non-filler word) -- STRUCTURALLY distinct from an ordinary short,
    unstructured, purely-alphabetic English word (e.g. "ok", "no", "hi") -- raising the floor
    against a bare 2-letter word while explicit, independently-proven positive controls (see
    `self_check_research`/`self_check_plan`) confirm both genuinely reference-shaped 2-character
    forms still survive; OR (c) the surviving tokens' alphanumeric character counts, counting ONLY
    tokens that are themselves structurally reference-shaped by the SAME rule as (b), sum to >=2 (a
    NARROWER version of the original, unconditional sum -- a purely-alphabetic, unstructured short
    token, such as a bare 1-character "z", no longer contributes toward this fallback sum at all,
    matching the same reference-shaped rationale as (b)).

    REVIEW ROUND 3 (I-3) addition, UNCHANGED by this round: a token whose alphanumeric characters
    are ENTIRELY a repeated run of the single letter "x"/"X" (any length -- "xxxxxx" and "XXXX"
    alike, generalising the fixed-length exact "XXX" already in `_FILLER_WORDS`) also contributes
    NOTHING toward the floor, on the same closed-vocabulary-of-known-placeholder-shapes basis as
    every other entry here -- never a generic "any repeated character" rule, which would risk
    silently discarding genuine short repeated-letter content (constitution 11.4.6).

    FIX (T179 fix-loop, IMPORTANT-2, review round 5): the section/paragraph-mark check is now
    `_SECTION_MARK_REF_RE` (mark IMMEDIATELY followed, allowing a single space, by a DIGIT) applied
    ONCE against the WHOLE `text` up front -- never a bare per-token `_SECTION_MARK_RE` match
    returning True the instant ANY "§"/"¶" byte appears anywhere, regardless of what (if anything)
    follows it. The previous bare-mark check wrongly treated "see § TBD"/"per § TODO"/
    "§ citation needed"/"see ¶ tbd"/"see §tbd"/"§ to be determined"/a lone trailing "see §" as
    carrying real content purely because a mark byte was present -- letting an obviously
    placeholder-shaped field pass `is_cited`/`_is_placeholder_text` purely on the strength of a
    stray "§"/"¶". Checking the WHOLE text (not each whitespace-split token in isolation) is what
    lets the "allowing a single space" clause actually mean something ("§ 3" as well as "§3"),
    since `text.split()` below would otherwise have already separated a mark from a same-line digit
    across a space into two independent tokens neither of which, alone, carries both characters. A
    mark that is NOT immediately followed by a digit (a bare mark, or one followed by a letter/
    placeholder word) is never treated as real content here on that basis alone -- it falls through
    to the ordinary per-token filler-word/length-floor path below like any other character, so
    "§tbd" is still correctly rejected via the already-known "TBD" filler-word entry rather than
    being waved through a second, independent short-circuit."""
    if _SECTION_MARK_REF_RE.search(text):
        return True
    total_alnum = 0
    for raw_tok in text.split():
        tok = raw_tok.strip(string.punctuation)
        if not tok:
            continue
        if _is_all_filler_compound(tok):
            continue
        alnum_only = re.sub(r"[^A-Za-z0-9]", "", tok)
        if not alnum_only:
            continue
        upper = alnum_only.upper()
        if upper in _FILLER_WORDS or set(upper) == {"X"}:
            continue
        n = len(alnum_only)
        has_digit = any(ch.isdigit() for ch in alnum_only)
        # FIX ROUND 4 (IMP-3, item 4, follow-up correctness fix): a token is treated as
        # STRUCTURALLY reference-shaped (never an ordinary short dictionary word) when it carries a
        # digit OR when it still carries INTERNAL non-alphanumeric punctuation once its own leading/
        # trailing punctuation has already been stripped (`tok != alnum_only` -- e.g. "T-X", a
        # hyphenated task-id fragment merging to the bare 2-character blob "TX"). Gating on
        # has_digit ALONE would wrongly reject a genuine hyphen-structured id/reference merely
        # because it happens to carry no digit, exactly the false-positive class a real Tasks-cell
        # value like "T-X" would otherwise fall into (`_is_all_filler_compound` above already
        # rejects "T-X" as an all-filler compound -- "X" alone is not a filler word -- so it
        # reaches this merged-alphanumeric path, where only has_digit would have wrongly failed it).
        has_structure = has_digit or (tok != alnum_only)
        if n >= 3:
            return True
        if n == 2 and has_structure:
            return True
        if has_structure:
            total_alnum += n
    return total_alnum >= 2


def _is_placeholder_text(text):
    """True when `text`'s normalized core (see `_normalized_core`) is empty, or is exactly one of
    the closed-set known placeholder markers, or STARTS WITH `TBD`/`TODO` followed by a word
    boundary, or (review round 2, I-C) fails the `_has_real_content` minimum-content floor once
    those first three, cheaper, whole-field-shaped checks have all found nothing. `text` is FIRST
    run through `_normalize_homoglyphs` (review round 3, I-3) so a placeholder spelled using a
    Cyrillic look-alike letter (e.g. "ТBD" with a Cyrillic "Т") is caught by the SAME exact-match
    tier as its genuine-Latin-script spelling.

    This is a heuristic floor over a DELIBERATELY BOUNDED, concrete-reproduction-driven set of
    known placeholder/filler shapes (constitution 11.4.6) -- not a claim of catching every
    conceivable paraphrase of "no citation yet". HONESTLY NOT CAUGHT, as of fix round 4: a genuine
    SENTENCE that happens to mention a filler word alongside other real prose (e.g. "we still need
    to find a source for this" -- "still"/"find" alone already clear the minimum-content floor,
    exactly as intended, since this reads as real content ABOUT a gap rather than a bare
    placeholder marker); a repeated-character placeholder spelled with a letter OTHER than "x"/"X"
    (e.g. a bare run of "zzzzzz"); any homoglyph confusable OUTSIDE the small, deliberately narrow
    Cyrillic set `_HOMOGLYPH_TRANSLATION` names (e.g. Greek look-alikes, fullwidth Unicode forms, or
    other scripts); a hyphen/underscore-joined compound where only SOME, not ALL, of its parts are
    filler words (deliberately narrow, `_is_all_filler_compound`'s own docstring); and a section-
    reference mark OTHER than "§"/"¶" (`_SECTION_MARK_RE`'s own closed set)."""
    text = _normalize_homoglyphs(text)
    core = _normalized_core(text)
    if not core:
        return True
    if core in _PLACEHOLDER_CORE_EXACT:
        return True
    for tok in _PLACEHOLDER_CORE_PREFIX:
        if core == tok or core.startswith(tok + " "):
            return True
    return not _has_real_content(text)


def parse_task_blocks(text):
    """Returns a list of {"id", "removes", "serves", "has_rollback", "has_expected_saving",
    "has_protecting_tests"} for every `#### T-<id>` block found in `text` (plan.md's own
    phased-task-block shape; real tasks.md carries none of these -- its own tracker-item format
    is a different concern this file does not parse for task-block fields). `removes`/`serves`
    are the concatenation of every matching field LINE's own text (single-line capture only --
    verified live against real plan.md's own 68 task blocks before choosing this design: every
    one of the real document's 46 RC ids is already found this way, so no observed real field
    wraps across >1 physical line, constitution 11.4.6). `has_rollback`/`has_expected_saving`/
    `has_protecting_tests` are True only when their own field is present WITH non-blank content
    (T178 fixture 1's own defect is the Rollback field wholly ABSENT; review round 1's own P1
    reproduction -- a task with ONLY a Rollback field and nothing else -- is exactly what
    `has_expected_saving`/`has_protecting_tests`, plus `no_serves_field`/`no_removes_cause` in
    `compute_plan_violations` below, now catch; a present-and-blank field is treated the same
    way as wholly absent, defensively)."""
    lines = text.splitlines()
    starts = [(i, m.group(1)) for i, l in enumerate(lines) for m in [_TASK_BLOCK_START_RE.match(l)] if m]
    blocks = []
    for idx, (line_idx, tid) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        body = lines[line_idx:end]
        removes = ""
        serves = ""
        has_rollback = False
        has_expected_saving = False
        has_protecting_tests = False
        for l in body:
            m = _REMOVES_FIELD_RE.match(l)
            if m:
                removes += " " + m.group(1)
            m = _SERVES_FIELD_RE.match(l)
            if m:
                serves += " " + m.group(1)
            m = _ROLLBACK_FIELD_RE.match(l)
            if m and m.group(1).strip():
                has_rollback = True
            m = _EXPECTED_SAVING_FIELD_RE.match(l)
            if m and m.group(1).strip():
                has_expected_saving = True
            m = _PROTECTING_TESTS_FIELD_RE.match(l)
            if m and m.group(1).strip():
                has_protecting_tests = True
        blocks.append({"id": tid, "removes": removes, "serves": serves,
                        "has_rollback": has_rollback,
                        "has_expected_saving": has_expected_saving,
                        "has_protecting_tests": has_protecting_tests})
    return blocks


def parse_requirements_table(text):
    """PATH 1 of the orphan-requirement bipartite check: parses an EXISTING `| Requirement |
    Tasks |`-headed table (real plan.md's own "Traceability matrices" -> "Requirements -> tasks"
    section; this file only VERIFIES that table's own Tasks cells are non-blank and genuinely
    covered, it never regenerates the table itself, matching the module docstring's own "invoked,
    not reimplemented" convention for mechanisms this file checks rather than owns).

    Returns `(out, unparseable)`:
      - `out` is {id: tasks_cell_text}. A comma-joined multi-id cell (e.g. "| FR-001, FR-003 |
        T-01 |") contributes the SAME Tasks-cell text to EVERY id found in the first cell; a
        bold-wrapped id cell (e.g. "| **FR-001** | ... |") is matched exactly as a bare one would
        be (review round 1, I4 -- see `_TABLE_ROW_GENERIC_RE`'s own header comment).
      - `unparseable` is a list of raw line strings: every row-SHAPED line (starts with "|",
        inside the table, not the `|---|---|` separator row) whose first cell names NO
        recognisable `[A-Z]+-id` token at all. Such a line is NEVER silently dropped (review
        round 1, I4) -- the caller raises `table_row_unparseable` for each -- and, critically, it
        does NOT stop the scan: every row that follows a malformed one is still examined (the
        ORIGINAL implementation `break`-ed on the first non-matching line, silently hiding every
        genuinely orphaned row after it, with no warning and no honest BLIND -- exactly the
        "quiet zero reads as absence" false-null constitution 11.4.201(6) forbids).

    A document with no `| Requirement | Tasks |` header at all (e.g. a minimal fixture) yields an
    empty `out` and an empty `unparseable` -- honestly absent, never guessed -- and PATH 2
    (`parse_scope_declared_ids`) is this file's OTHER, independent discovery mechanism for exactly
    that case. A single occurrence of the table is considered to have ENDED only when a line, once
    inside it, does not even START with "|" (a blank line, or the next section's own prose/
    heading) -- never merely "the row regex failed to match", which is what let a malformed row
    silently truncate the scan before the review round 1 (I4) fix. The header/row shapes are ALSO
    (review round 2, Borderline-Important) tolerant of an EXTRA trailing column (e.g.
    "| Requirement | Tasks | Notes |" -- see `_REQ_TABLE_HEADER_RE`/`_TABLE_ROW_GENERIC_RE`'s own
    header comments), and the scan does NOT stop after the FIRST table's own end: a SECOND
    "| Requirement | Tasks |"-headed table appearing anywhere LATER in the same document is
    likewise discovered and merged into the SAME `out`/`unparseable` result (a later table's row
    for an id already seen overwrites the earlier one -- last-encountered-wins, matching this
    file's own general convention elsewhere of never silently preferring the first of two
    conflicting real signals over the other). The ORIGINAL implementation `break`-ed the WHOLE scan
    the moment any one table ended, so a document declaring more than one such table had every row
    of every table after the first permanently invisible, with no warning and no honest BLIND --
    exactly the "quiet zero reads as absence" false-null constitution 11.4.201(6) forbids."""
    lines = text.splitlines()
    out = {}
    unparseable = []
    in_table = False
    for l in lines:
        if _REQ_TABLE_HEADER_RE.match(l):
            in_table = True
            continue
        if not in_table:
            continue
        if not l.strip().startswith("|"):
            # review round 2 (Borderline-Important): THIS occurrence of the table has ended (a
            # blank line, or the next section's own prose/heading) -- but the scan keeps going,
            # never `break`s, so a later, SECOND "| Requirement | Tasks |" header further down the
            # SAME document is still found and its own rows are still merged in.
            in_table = False
            continue
        # FIX ROUND 4 (Minor-4): matched against the STRIPPED line -- consistent with the
        # `not l.strip().startswith("|")` table-continuation check immediately above -- so trailing
        # whitespace ("|---|---| ") or leading indentation ("  |:---|---:|") on an otherwise
        # well-formed separator row no longer causes it to be wrongly reported as
        # `table_row_unparseable` (the ORIGINAL `.match(l)` against the raw, unstripped line
        # required the row's own leading "|" to be the line's literal first character and its own
        # trailing "|" to be the line's literal last character).
        if _TABLE_SEP_ROW_RE.match(l.strip()):
            continue
        m = _TABLE_ROW_GENERIC_RE.match(l)
        if not m:
            unparseable.append(l)
            continue
        id_cell, tasks_cell = m.group(1), m.group(2)
        ids = _REQ_ID_CELL_ID_RE.findall(id_cell)
        if not ids:
            unparseable.append(l)
            continue
        for rid in ids:
            out[rid] = tasks_cell.strip()
    return out, unparseable


def _tasks_cell_is_orphan(cell):
    """True when a traceability-table Tasks cell is blank OR carries only a placeholder marker
    (e.g. "—"/"TBD"/"n/a"/"none") that names no real task at all (review round 1, I4: a
    placeholder-shaped cell was previously counted as "covered" just because it was non-empty
    text)."""
    stripped = cell.strip(" *`")
    if not stripped:
        return True
    return _is_placeholder_text(stripped)


def _row_is_covered(rid, cell, tasks_by_id):
    """True iff `cell` names >=1 task id that BOTH (a) actually EXISTS as a real `#### T-` block
    in the document, AND (b) that task's own Serves field genuinely lists `rid` (review round 1,
    I4): a cell naming a task id that merely APPEARS in its own text is not, by itself, coverage
    -- the named task must genuinely exist and genuinely claim, via its own Serves field, to
    serve this specific requirement. A task id in the cell that does not exist at all is silently
    skipped here (never counted toward coverage) rather than raising -- the surrounding orphan-
    requirement check already reports the row as orphan when NO cell-named task qualifies."""
    for tid in _CELL_TASK_ID_RE.findall(cell):
        tb = tasks_by_id.get(tid)
        if tb is None:
            continue
        if re.search(r"\b%s\b" % re.escape(rid), tb["serves"]):
            return True
    return False


def _req_table_row_is_effectively_orphan(rid, cell, tasks_by_id):
    """True iff `cell` (ONE document's own Tasks-cell text for requirement `rid`) is, on its own,
    orphan by EITHER discrimination `compute_plan_violations` itself later applies to a merged
    `req_table` entry -- register-SHAPE (`_tasks_cell_is_orphan`: blank or placeholder-shaped) OR
    genuine-COVERAGE (`_row_is_covered`: names no task that actually exists and actually Serves this
    id). FIX ROUND 4 (Minor-3): used ONLY by `_merge_req_tables` below, to decide, for an id
    appearing in BOTH `--plan` and `--tasks`, which document's own row to keep."""
    if _tasks_cell_is_orphan(cell):
        return True
    return not _row_is_covered(rid, cell, tasks_by_id)


def _merge_req_tables(plan_req_table, tasks_req_table, tasks_by_id):
    """Merges `tasks_req_table` (a `--tasks` document's own traceability-table rows, as returned by
    `parse_requirements_table`) into a COPY of `plan_req_table` (a `--plan` document's own rows) --
    FIX ROUND 4 (Minor-3): an id present in BOTH tables is orphan if EITHER document's row is orphan
    for it (the CONSERVATIVE/safe direction) -- rather than review round 3 (M-7)'s own plain LAST-
    occurrence-wins overwrite, which could silently let a COVERED `--tasks` row for an id MASK a
    genuinely ORPHANED `--plan` row for that SAME id (or vice versa) -- precisely INVERTING M-7's
    own stated intent ("never silently preferring one signal over another"). `--plan`'s own row is
    kept ONLY when it is itself orphan AND `--tasks`' own row is NOT; every other combination (both
    orphan, both covered, or only `--tasks` orphan) keeps `--tasks`' own row, preserving the
    ORIGINAL last-occurrence-wins behaviour whenever the two documents' own signals AGREE. Returns a
    NEW dict; neither input argument is mutated -- this is the SINGLE, shared merge function BOTH
    `cmd_plan` (the real run) and `self_check_plan` (over a synthetic fixture) use, matching this
    file's own established Producer != Verifier discipline (constitution 11.4.240)."""
    merged = dict(plan_req_table)
    for k, v in tasks_req_table.items():
        if k in merged \
                and _req_table_row_is_effectively_orphan(k, merged[k], tasks_by_id) \
                and not _req_table_row_is_effectively_orphan(k, v, tasks_by_id):
            continue  # --plan's own orphan signal for this id must not be masked by --tasks
        merged[k] = v
    return merged


def parse_scope_declared_ids(text):
    """PATH 2 of the orphan-requirement bipartite check: a line matching `**Scope...**: implements
    <ID list>` declares the FR-/SC- id universe a minimal document (no traceability table) commits
    to covering. Deliberately narrow -- anchored to a LEADING `**Scope...**:` label, never a bare
    `implements` substring scan -- because a bare scan over real tasks.md genuinely false-positives
    on this project's own real evidence prose ("Implements `put`/`get`/`check-duplicate` ...",
    T068/T073/T080's own EVIDENCE blocks), confirmed live before choosing this design (constitution
    11.4.201(7)(a): match structure, not substring -- a document is never scanned for a bare
    keyword when a narrower, line-anchored shape distinguishes a genuine scope declaration from an
    ordinary sentence merely using the same English verb)."""
    ids = set()
    for line in text.splitlines():
        m = _SCOPE_DECLARATION_RE.match(line.strip())
        if m:
            for idm in _REQ_ID_RE.finditer(m.group(1)):
                ids.add(idm.group(0))
    return ids


def parse_spec_requirement_ids(text):
    """PATH 3 of the orphan-requirement bipartite check (review round 1, B2, P7): every FR-/SC- id
    spec.md itself DEFINES via its own `- **FR-NNN**:` / `- **SC-NNN**:` bold-header lines (its
    real, verified shape) -- the FIXED, canonical universe every task's own Serves/scope-declared
    coverage is cross-referenced against, independent of whichever subset the PLAN document
    happens to declare covering (the reviewer's own concrete reproduction: an FR id spec.md
    defines but that plan.md/tasks.md never mentions at all was previously invisible to this
    file's two discovery paths, both of which only ever look at what the PLAN itself declares --
    never at the actual fixed FR/SC set the SPEC defines). Returns a set; a document with no such
    header line yields an empty set, honestly absent, never guessed."""
    return {m.group(1) for l in text.splitlines() for m in [_SPEC_REQ_HEADER_RE.match(l)] if m}


def has_permanent_gap_marker(text):
    """Backward-compatible boolean form: True iff >=1 genuine per-cause permanent-gap marker
    exists ANYWHERE in `text` (see `permanent_gap_cause_ids` for the real, per-cause-scoped
    detector review round 1 (B1) introduces; kept only for `self_check_plan()`'s own
    document-shape assertions below, which need a plain existence check)."""
    return bool(permanent_gap_cause_ids(text))


def permanent_gap_cause_ids(text):
    """Returns the SET of cause ids (RC-...) that carry a genuine, explicitly-linked permanent-gap
    marker line anywhere in `text` -- `permanent gap: RC-<id> -- <reason>` (see
    `_PERMANENT_GAP_MARKER_RE`'s own header comment for the full review round 1 (B1) rationale).
    Scoped PER-CAUSE by construction: a bare mention of the phrase "permanent gap" with no
    following id+dash shape (including inside a negation sentence, e.g. "There is no permanent
    gap recorded.") contributes NOTHING to this set."""
    ids = set()
    for line in text.splitlines():
        m = _PERMANENT_GAP_MARKER_RE.search(line)
        if m:
            ids.add(m.group(1))
    return ids


def compute_plan_violations(task_blocks, causes_list, req_table, unparseable_rows, declared_ids,
                             spec_ids, gap_ids, words, pages_equivalent):
    """Runs every SC-C-003 check this file implements over already-parsed plan/tasks/causes data,
    and returns the resulting list of violation dicts (in the SAME order `cmd_plan`'s own pipeline
    has always computed them). This is the SINGLE, PRODUCTION code path exercised by BOTH
    `cmd_plan` (the real run, over real documents) and `self_check_plan` (over a synthetic
    control-needle fixture) -- review round 1 (I3): the ORIGINAL `self_check_plan` only
    re-checked the underlying PARSING functions' own output fields directly (e.g. reading
    `by_id["T-NEEDLE-GOOD"]["has_rollback"]`), never actually exercising the violation-GENERATING
    loop bodies that lived inline inside `cmd_plan` -- so a mutation to one of those loop bodies
    (the reviewer's own concrete reproductions: `if not tb["has_rollback"]:` mutated to
    `if False:`, or the Rollback-blank check `if m and m.group(1).strip():` mutated to `if m:`)
    passed the self-check untouched while silently breaking the real violation logic (constitution
    11.4.240, Producer != Verifier: the VERIFICATION must exercise the real production code path,
    not a parallel reimplementation that can drift out of sync with it). Feeding the synthetic
    fixture through this SAME function, from BOTH callers, closes that gap structurally: any
    future mutation to the logic below is caught by `self_check_plan()` for the identical reason
    it would be caught by a real invocation.

    Per-clause coverage (contract SC-C-003, honest boundary constitution 11.4.6):
      - `no_rollback` / `no_removes_cause` / `removes_cause_names_no_id` / `removes_cause_
        unknown_id` / `no_serves_field` / `no_expected_saving` / `no_protecting_tests` -- FULL
        field-presence coverage for all five of the contract's named per-task fields
        (`removes_cause`, `Serves`, `expected_saving`, `rollback`, `protecting_tests`), PLUS
        cross-checking every RC- id a task's own Removes/measures field names against the REAL
        cause universe (`--causes`'s own `id` values) -- review round 1, B2/P2's own concrete
        reproduction (a Removes field naming a nonexistent `RC-99`) is exactly this check --
        AND (review round 2, Minor-7) flagging a Removes/measures field that is non-blank but
        names NO `RC-...` id at all (arbitrary prose with zero recognisable cause reference) as
        its own `removes_cause_names_no_id` finding, distinct from `no_removes_cause` (field
        wholly blank) -- a Removes field carrying only prose previously passed this check
        silently just because it was non-empty, never actually naming which cause the task
        claims to remove/measure. NOT verified: the CONTENT quality of `expected_saving` (a
        genuine confirming measurement vs. merely non-blank prose) or `protecting_tests` (a
        genuine test reference vs. merely non-blank prose) -- honestly disclosed, matching this
        file's own established convention for partial coverage (see `causes`'s own docstring
        clauses (d)/(e)/(f)).
      - `orphan_cause` -- FULL, unchanged from the original implementation (every CONFIRMED/
        UNDETERMINED cause genuinely named, by id, in some task's Removes/measures text).
      - `orphan_requirement` -- THREE independent discovery paths (see `parse_requirements_table`
        docstring for path 1, `parse_scope_declared_ids` for path 2, `parse_spec_requirement_ids`
        for path 3 -- review round 1, B2/P7): a requirement id is orphan when it is named by
        NEITHER a genuinely-covering Tasks-table cell (path 1: task exists AND its own Serves
        genuinely lists the id -- review round 1, I4) NOR a scope-preamble-declared id actually
        served by some task (path 2) NOR (when `spec_ids` is supplied) one of spec.md's own fixed
        FR-001..FR-025/SC-001..SC-010 ids actually served by some task (path 3). `spec_ids` is
        OPTIONAL (an empty set when the caller has no `--spec`) -- when empty, path 3 contributes
        nothing, matching this file's own established `--post-a11`/`--operator-causes` convention
        for an opt-in check that is never silently assumed satisfied when omitted.
      - `table_row_unparseable` -- every row-shaped-but-unparseable line `parse_requirements_table`
        found is surfaced by name here, never silently absorbed.
      - `below_size_threshold` -- FULL, unchanged (words / 500 >= 30 pages-equivalent).
      - `confirmed_unmeasured_no_permanent_gap` -- review round 1 (B1): now scoped PER-CAUSE via
        `gap_ids` (the set `permanent_gap_cause_ids()` returns), never document-wide. A CONFIRMED
        cause whose `measured_share` is a NON-STRING value (review round 1, M3) is reported as
        `measured_share_not_string` instead of raising an unhandled TypeError from the old
        `_UNMEASURED_RE.match(share)` call (a real fixture value that happens to be a JSON number
        or object, rather than a string, previously crashed the whole tool to a generic internal
        error, exit 4, instead of a clean, named, exit-1 finding).
      - `no_removes_cause`/`removes_cause_names_no_id`/`removes_cause_unknown_id`/
        `no_serves_field`/`no_expected_saving`/`no_protecting_tests`/
        `confirmed_unmeasured_no_permanent_gap`: an EMPTY `causes_list` (the
        `--causes` document's own `causes` array has zero entries) is treated as a genuinely valid
        state -- zero causes to check the cause-dependent clauses against -- rather than BLIND
        (review round 1, M3's own second, deliberately judgment-based point): real early-phase
        plan review legitimately precedes any cause classification at all, and T178's own
        fixtures 1/3/6 rely on exactly this (`{"causes": []}`) to isolate the OTHER SC-C-003
        checks (rollback/orphan-requirement/size-floor) from the cause-dependent ones. Making an
        empty `causes` array BLIND would defeat those fixtures' own design and would incorrectly
        treat "no causes classified yet" the same as "the --causes document itself is unreadable
        or malformed" (an entirely different, already-handled failure mode in `cmd_plan`)."""
    violations = []
    known_cause_ids = {c.get("id") for c in causes_list if isinstance(c, dict) and c.get("id")}
    removes_all = " ".join(tb["removes"] for tb in task_blocks)
    serves_all = " ".join(tb["serves"] for tb in task_blocks)
    tasks_by_id = {tb["id"]: tb for tb in task_blocks}

    # (a) every task's own Rollback/Removes-measures/Serves/Expected-saving/Protecting-tests
    # field is present with non-blank content, PLUS every RC- id a Removes/measures field names
    # is cross-checked against the real cause universe.
    for tb in task_blocks:
        if not tb["has_rollback"]:
            violations.append({"code": "no_rollback", "task": tb["id"]})
        if not tb["removes"].strip():
            violations.append({"code": "no_removes_cause", "task": tb["id"]})
        else:
            rc_ids_found = sorted(set(_RC_ID_IN_TEXT_RE.findall(tb["removes"])))
            if not rc_ids_found:
                # review round 2 (Minor-7): the field is present and non-blank, but names NO
                # `RC-...` id at all -- arbitrary prose that never actually identifies WHICH cause
                # this task claims to remove/measure. Distinct from `no_removes_cause` (field
                # wholly blank) above; previously this passed silently as long as the cell was
                # non-empty text.
                violations.append({"code": "removes_cause_names_no_id", "task": tb["id"]})
            for rc_id in rc_ids_found:
                if rc_id not in known_cause_ids:
                    violations.append({"code": "removes_cause_unknown_id", "task": tb["id"],
                                        "row": rc_id})
        if not tb["serves"].strip():
            violations.append({"code": "no_serves_field", "task": tb["id"]})
        if not tb.get("has_expected_saving"):
            violations.append({"code": "no_expected_saving", "task": tb["id"]})
        if not tb.get("has_protecting_tests"):
            violations.append({"code": "no_protecting_tests", "task": tb["id"]})

    # (b) bipartite orphan-cause: every CONFIRMED/UNDETERMINED cause genuinely appears, by id, in
    # SOME task's own Removes/measures field text (deeper than `causes`'s own register-level-only
    # clause (b) -- see module docstring)
    for cause in causes_list:
        if not isinstance(cause, dict):
            continue
        if cause.get("class") in ("CONFIRMED", "UNDETERMINED"):
            rid = cause.get("id")
            if rid and not re.search(r"\b%s\b" % re.escape(rid), removes_all):
                violations.append({"code": "orphan_cause", "row": rid})

    # (c) bipartite orphan-requirement -- THREE independent discovery paths (see module docstring
    # / parse_requirements_table / parse_scope_declared_ids / parse_spec_requirement_ids)
    for rid, cell in sorted(req_table.items()):
        if _tasks_cell_is_orphan(cell):
            violations.append({"code": "orphan_requirement", "id": rid, "source": "table"})
        elif not _row_is_covered(rid, cell, tasks_by_id):
            violations.append({"code": "orphan_requirement", "id": rid, "source": "table"})

    for line in unparseable_rows:
        violations.append({"code": "table_row_unparseable", "line": line})

    for rid in sorted(declared_ids):
        if rid in req_table:
            continue  # already adjudicated by path 1 above -- avoid double-reporting one id
        if not re.search(r"\b%s\b" % re.escape(rid), serves_all):
            violations.append({"code": "orphan_requirement", "id": rid, "source": "scope_preamble"})

    for rid in sorted(spec_ids):
        if rid in req_table or rid in declared_ids:
            continue  # already adjudicated by path 1/2 above -- avoid double-reporting one id
        if not re.search(r"\b%s\b" % re.escape(rid), serves_all):
            violations.append({"code": "orphan_requirement", "id": rid, "source": "spec_fixed_set"})

    # (d) size floor: plan + supporting documents >= 30 pages-equivalent (words / 500)
    if pages_equivalent < 30.0:
        violations.append({"code": "below_size_threshold", "words": words,
                            "pages_equivalent": pages_equivalent})

    # (e) FR-002's post-T-A11 half: CONFIRMED + still-UNMEASURED needs its OWN named permanent
    # gap (review round 1, B1 -- per-cause `gap_ids`, never document-wide)
    for cause in causes_list:
        if not isinstance(cause, dict):
            continue
        if cause.get("class") != "CONFIRMED":
            continue
        rid = cause.get("id")
        raw_share = cause.get("measured_share")
        if raw_share is not None and not isinstance(raw_share, str):
            # review round 1 (M3): a non-string measured_share (e.g. a JSON number) previously
            # crashed `_UNMEASURED_RE.match(share)` with an unhandled TypeError -- reported now as
            # its own named, exit-1 finding instead of a generic exit-4 internal error.
            violations.append({"code": "measured_share_not_string", "row": rid,
                                "type": type(raw_share).__name__})
            continue
        # review round 3 (I-2/M-5): `raw_share` being ABSENT entirely (`None` -- the key is either
        # missing from the JSON object or present as JSON `null`), the EMPTY string `""`, or a
        # WHITESPACE-ONLY string (`" "`) are all, in substance, "not measured" -- EXACTLY as
        # `UNMEASURED` itself is -- and are all now handled by ONE explicit, named branch rather
        # than the original bare `(not raw_share) or ...` expression, whose correctness for the
        # `None`/`""` cases depended entirely on Python's left-to-right `or` short-circuit NEVER
        # evaluating `_UNMEASURED_RE.match(raw_share)` against a non-string value -- a fragile
        # reliance a single review-round-3 reviewer's own reproduction mutation (`(not raw_share)`
        # changed to the literal `False`) breaks immediately, turning a `None` `measured_share`
        # into an unhandled `TypeError` crash (`_UNMEASURED_RE.match(None)`) rather than the clean,
        # named `confirmed_unmeasured_no_permanent_gap` finding this branch now guarantees
        # regardless of how the surrounding expression is later edited. A whitespace-only string
        # (M-5's own second reproduction) was, before this fix, silently treated as "measured" --
        # `_UNMEASURED_RE.match(" ")` does not match, and `not " "` is False since a non-empty
        # string (even one of pure whitespace) is truthy in Python -- WRONGLY letting a CONFIRMED
        # cause whose only "measurement" is a blank string skip the permanent-gap requirement.
        if raw_share is None or not raw_share.strip():
            unmeasured = True
        else:
            # FIX ROUND 4 (Minor-5): matched against the STRIPPED value -- a leading/trailing-
            # whitespace value such as " UNMEASURED" previously never matched `_UNMEASURED_RE` at
            # all (the regex is start-anchored, `^UNMEASURED\b`, so a leading space made it fail to
            # match at position 0), silently treating a genuinely unmeasured cause as "measured".
            # ALSO now treats a value satisfying the SAME `_is_placeholder_text` helper `is_cited`
            # already uses (never a second, independently-reimplemented placeholder check,
            # constitution 11.4.240) as unmeasured too -- a common placeholder value ("TBD", "—",
            # "n/a", "?") previously counted as a genuine measurement just because it was non-blank
            # and did not literally start with the word "UNMEASURED".
            #
            # FIX (T179 fix-loop, IMPORTANT-1, review round 5): `_is_placeholder_text`'s own
            # minimum-content floor (`_has_real_content`) requires a bare, unstructured short
            # token's alphanumeric-character count to reach >=2 before it counts as real content --
            # a genuine SINGLE-DIGIT measured share ("5%", "7", "1", "9 %") reduces to exactly ONE
            # counted alphanumeric character and therefore WRONGLY fails that floor, making
            # `_is_placeholder_text` return True for a real, non-placeholder measurement. Gating the
            # placeholder-text branch on "the stripped value contains NO digit at all" fixes this
            # precisely: a placeholder genuinely carries no digit ("TBD", "—", "n/a", "?") and stays
            # correctly caught here, while ANY value containing a digit -- however short -- is a
            # real measurement and is never routed through the placeholder check at all.
            stripped_share = raw_share.strip()
            unmeasured = bool(_UNMEASURED_RE.match(stripped_share)) \
                or (_is_placeholder_text(stripped_share) and not re.search(r"\d", stripped_share))
        if unmeasured and rid not in gap_ids:
            violations.append({"code": "confirmed_unmeasured_no_permanent_gap", "row": rid})

    return violations


_SELF_CHECK_PLAN_DOC = (
    "**Scope of this self-check plan**: implements FR-NEEDLE-ORPHAN, FR-NEEDLE-COVERED.\n"
    "\n"
    "| Requirement | Tasks |\n"
    "|---|---|\n"
    "| SC-NEEDLE-ORPHAN |  |\n"
    "| SC-NEEDLE-COVERED | T-NEEDLE-GOOD |\n"
    "| SC-NEEDLE-PLACEHOLDER | — |\n"
    "| SC-NEEDLE-GHOST-TASK | T-NEEDLE-DOES-NOT-EXIST |\n"
    "| SC-NEEDLE-MISMATCH | T-NEEDLE-BAD |\n"
    "| **SC-NEEDLE-BOLD** | T-NEEDLE-GOOD |\n"
    "| FR-NEEDLE-MULTI-A, FR-NEEDLE-MULTI-B | T-NEEDLE-GOOD |\n"
    "| SC-NEEDLE-MALFORMED-ROW-NO-CLOSING-PIPE\n"
    "| SC-NEEDLE-AFTER-MALFORMED |  |\n"
    "\n"
    "#### T-NEEDLE-GOOD -- self-check needle task (has rollback, mentions the covered cause, "
    "full field set)\n"
    "\n"
    "- **Removes / measures:** measures RC-NEEDLE-GOOD.\n"
    "- **Serves:** FR-NEEDLE-COVERED, SC-NEEDLE-COVERED, SC-NEEDLE-BOLD, FR-NEEDLE-MULTI-A, "
    "FR-NEEDLE-MULTI-B, FR-NEEDLE-SPEC-COVERED.\n"
    "- **Expected saving -> measurement:** none directly (instrument).\n"
    "- **Rollback:** additive.\n"
    "- **Protecting tests:** RED self-check fixture.\n"
    "\n"
    "#### T-NEEDLE-BAD -- self-check needle task (no rollback, mentions an unrelated + an "
    "unknown-to-causes cause)\n"
    "\n"
    "- **Removes / measures:** measures RC-NEEDLE-UNRELATED, RC-NEEDLE-UNKNOWN.\n"
    "- **Serves:** FR-NEEDLE-COVERED.\n"
    "- **Expected saving -> measurement:** none directly (instrument).\n"
    "- **Protecting tests:** RED self-check fixture.\n"
    "\n"
    "#### T-NEEDLE-NOFIELDS -- self-check needle task (ONLY a Rollback field, nothing else -- "
    "review round 1, P1)\n"
    "\n"
    "- **Rollback:** additive.\n"
    "\n"
    "#### T-NEEDLE-BLANKROLLBACK -- self-check needle task (Rollback field PRESENT but BLANK -- "
    "review round 1, I3's second mutation)\n"
    "\n"
    "- **Removes / measures:** measures RC-NEEDLE-GOOD.\n"
    "- **Serves:** FR-NEEDLE-COVERED.\n"
    "- **Expected saving -> measurement:** none directly (instrument).\n"
    "- **Rollback:**\n"
    "- **Protecting tests:** RED self-check fixture.\n"
    "\n"
    "#### T-NEEDLE-GAPPED -- self-check needle task for the per-cause permanent-gap marker\n"
    "\n"
    "- **Removes / measures:** measures RC-NEEDLE-GAPPED, RC-NEEDLE-NOGAP.\n"
    "- **Serves:** FR-NEEDLE-COVERED.\n"
    "- **Expected saving -> measurement:** none directly (instrument).\n"
    "- **Rollback:** additive.\n"
    "- **Protecting tests:** RED self-check fixture.\n"
    "\n"
    "permanent gap: RC-NEEDLE-GAPPED -- settling task scheduled, no earlier measurement "
    "possible.\n"
    "\n"
    "#### T-NEEDLE-PROSEONLY -- self-check needle task (Removes/measures field non-blank but "
    "names NO RC- id at all -- review round 2, Minor-7)\n"
    "\n"
    "- **Removes / measures:** general implementation quality work, no specific cause named.\n"
    "- **Serves:** FR-NEEDLE-COVERED.\n"
    "- **Expected saving -> measurement:** none directly (instrument).\n"
    "- **Rollback:** additive.\n"
    "- **Protecting tests:** RED self-check fixture.\n"
)
_SELF_CHECK_PLAN_DOC_WITH_GAP = _SELF_CHECK_PLAN_DOC + "\nA named permanent gap is recorded.\n"
_SELF_CHECK_PLAN_NEGATION_DOC = "There is no permanent gap recorded.\n"
# review round 2 (I-A): `_SELF_CHECK_PLAN_CAUSES` gains THREE deliberately-orphaned causes -- one
# per class the orphan-cause check's own closed tuple (CONFIRMED, UNDETERMINED) distinguishes from
# the class it deliberately excludes (REFUTED) -- none of the three ids below is planted ANYWHERE
# in `_SELF_CHECK_PLAN_DOC`'s own Removes/measures text, so each is a genuine needle for whether
# `compute_plan_violations`'s own `orphan_cause` loop still fires on the RIGHT two classes and
# stays silent on the third. RC-NEEDLE-ORPHAN-UNDETERMINED is the CRITICAL needle here: the round-1
# reviewer's own concrete mutation dropping "UNDETERMINED" from that closed tuple previously
# survived this self-check untouched (no UNDETERMINED-class cause existed anywhere in the fixture
# set at all).
_SELF_CHECK_PLAN_CAUSES = [
    {"id": "RC-NEEDLE-GOOD", "class": "CONFIRMED", "measured_share": "12%"},
    {"id": "RC-NEEDLE-GAPPED", "class": "CONFIRMED", "measured_share": "UNMEASURED"},
    {"id": "RC-NEEDLE-NOGAP", "class": "CONFIRMED", "measured_share": "UNMEASURED"},
    {"id": "RC-NEEDLE-ORPHAN-CONFIRMED", "class": "CONFIRMED", "measured_share": "5%"},
    {"id": "RC-NEEDLE-ORPHAN-UNDETERMINED", "class": "UNDETERMINED"},
    {"id": "RC-NEEDLE-ORPHAN-REFUTED", "class": "REFUTED"},
]
_SELF_CHECK_PLAN_SPEC_DOC = (
    "- **FR-NEEDLE-SPEC-COVERED**: something. *Checked by*: x.\n"
    "- **FR-NEEDLE-SPEC-ORPHAN**: something else. *Checked by*: y.\n"
)
# review round 2 (Borderline-Important): a standalone fixture for `parse_requirements_table`,
# exercised directly (never through the full `compute_plan_violations` pipeline, to keep the
# already-large `_SELF_CHECK_PLAN_DOC` fixture focused) -- one table declaring an EXTRA trailing
# "Notes" column (proving the header/row regexes tolerate it), followed by a SECOND, ordinary
# 2-column "| Requirement | Tasks |" table later in the SAME document (proving the scan does not
# stop at the first table's own end).
_SELF_CHECK_PLAN_EXTRA_COLUMN_TABLE = (
    "| Requirement | Tasks | Notes |\n"
    "|---|---|---|\n"
    "| SC-NEEDLE-EXTRACOL-COVERED | T-X | some note |\n"
    "| SC-NEEDLE-EXTRACOL-ORPHAN |  | another note |\n"
    "\n"
    "| Requirement | Tasks |\n"
    "|---|---|\n"
    "| SC-NEEDLE-SECOND-TABLE-ROW | T-Y |\n"
)
# review round 3 (M-1): a standalone fixture for the GFM column-alignment separator-row shape
# (":---"/"---:"/":---:" -- real, standard GitHub-Flavored-Markdown syntax for left/right/center-
# aligned columns), exercised directly, mirroring the Borderline-Important extra-column-table
# fixture's own convention of keeping this narrow reproduction out of the already-large main
# `_SELF_CHECK_PLAN_DOC` fixture.
_SELF_CHECK_PLAN_GFM_ALIGNED_SEP_TABLE = (
    "| Requirement | Tasks |\n"
    "|:---|:---:|\n"
    "| SC-NEEDLE-GFMALIGN-COVERED | T-Z |\n"
)
# FIX ROUND 4 (Minor-4): a standalone fixture for the WHITESPACE-around-the-separator-row shape --
# a genuinely well-formed separator row carrying TRAILING whitespace after its own closing "|", and
# a SECOND, genuinely well-formed separator row carrying LEADING indentation before its own opening
# "|" -- exercised directly, mirroring the review-round-3 (M-1) GFM-aligned-separator fixture's own
# convention of keeping this narrow reproduction out of the already-large main
# `_SELF_CHECK_PLAN_DOC` fixture. The ORIGINAL `_TABLE_SEP_ROW_RE.match(l)` (against the raw,
# unstripped line) required its own leading "|" to be the line's literal first character and its
# own trailing "|" to be the line's literal last character, so EITHER variant below fell through to
# `_TABLE_ROW_GENERIC_RE` and was wrongly reported as `table_row_unparseable`.
_SELF_CHECK_PLAN_WHITESPACE_SEP_TABLE = (
    "| Requirement | Tasks |\n"
    "|---|---| \n"
    "| SC-NEEDLE-TRAILINGWS-COVERED | T-W1 |\n"
)
_SELF_CHECK_PLAN_INDENTED_SEP_TABLE = (
    "| Requirement | Tasks |\n"
    "  |:---|:---:|\n"
    "| SC-NEEDLE-INDENTEDSEP-COVERED | T-W2 |\n"
)
# FIX ROUND 4 (Minor-3): a standalone task-block fixture for `_merge_req_tables`'s own direct-call
# needles below -- a single real, genuinely-covering task, exercised against three synthetic
# `--plan`/`--tasks` cell-text combinations (isolating the merge function from the already-large
# main `_SELF_CHECK_PLAN_DOC` fixture, matching this file's own established convention for a
# narrower reproduction).
_SELF_CHECK_PLAN_MERGE_TASK_DOC = (
    "#### T-NEEDLE-MERGE-GOOD -- self-check needle task for the req-table merge (fix round 4, "
    "Minor-3)\n"
    "\n"
    "- **Serves:** SC-NEEDLE-MERGE-A, SC-NEEDLE-MERGE-B, SC-NEEDLE-MERGE-C.\n"
)


def self_check_plan():
    """Returns None on success, else a diagnostic string (caller exits 3). Review round 1 (I3):
    every check below still independently proves its own underlying PARSING function behaves on
    the synthetic fixture (unchanged discipline), AND (the new part) feeds that SAME fixture
    through `compute_plan_violations` -- the identical function `cmd_plan` itself calls -- so a
    mutation to the real violation-generating logic is caught here exactly as it would be by a
    real invocation (see `compute_plan_violations`'s own docstring for the full rationale and the
    reviewer's two concrete reproductions this restructuring closes)."""
    blocks = parse_task_blocks(_SELF_CHECK_PLAN_DOC)
    by_id = {b["id"]: b for b in blocks}
    expected_task_ids = {"T-NEEDLE-GOOD", "T-NEEDLE-BAD", "T-NEEDLE-NOFIELDS",
                          "T-NEEDLE-BLANKROLLBACK", "T-NEEDLE-GAPPED", "T-NEEDLE-PROSEONLY"}
    if set(by_id) != expected_task_ids:
        return ("self-check FAILED: task-block parser did not find exactly the 6 synthetic "
                 "needle task blocks (got %r)" % sorted(by_id))
    if not by_id["T-NEEDLE-GOOD"]["has_rollback"]:
        return ("self-check FAILED: known-present Rollback field on T-NEEDLE-GOOD was WRONGLY "
                 "read as absent")
    if by_id["T-NEEDLE-BAD"]["has_rollback"]:
        return ("self-check FAILED: known-absent Rollback field on T-NEEDLE-BAD was WRONGLY read "
                 "as present (false positive, constitution 11.4.201(1))")
    if by_id["T-NEEDLE-BLANKROLLBACK"]["has_rollback"]:
        return ("self-check FAILED: a Rollback field PRESENT but with BLANK content on "
                 "T-NEEDLE-BLANKROLLBACK was WRONGLY read as present (review round 1, I3's "
                 "second mutation reproduction -- `if m and m.group(1).strip():` mutated to "
                 "`if m:` -- false positive, constitution 11.4.201(1))")
    if by_id["T-NEEDLE-NOFIELDS"]["removes"].strip() or by_id["T-NEEDLE-NOFIELDS"]["serves"].strip() \
            or by_id["T-NEEDLE-NOFIELDS"]["has_expected_saving"] \
            or by_id["T-NEEDLE-NOFIELDS"]["has_protecting_tests"]:
        return ("self-check FAILED: T-NEEDLE-NOFIELDS's known-all-absent Removes/Serves/Expected-"
                 "saving/Protecting-tests fields were WRONGLY read as present on >=1 of them")

    removes_all = " ".join(b["removes"] for b in blocks)
    if not re.search(r"\bRC-NEEDLE-GOOD\b", removes_all):
        return ("self-check FAILED: known-present RC-NEEDLE-GOOD was not found in the synthetic "
                 "Removes/measures text")
    if re.search(r"\bRC-NEEDLE-BAD\b", removes_all):
        return ("self-check FAILED: RC-NEEDLE-BAD (never planted) was WRONGLY found in the "
                 "synthetic Removes/measures text -- the fixture itself is broken")

    req_table, unparseable = parse_requirements_table(_SELF_CHECK_PLAN_DOC)
    if req_table.get("SC-NEEDLE-ORPHAN") != "":
        return ("self-check FAILED: requirements-table parser did not read SC-NEEDLE-ORPHAN's "
                 "Tasks cell as blank (got %r)" % req_table.get("SC-NEEDLE-ORPHAN", "MISSING"))
    if not req_table.get("SC-NEEDLE-COVERED"):
        return ("self-check FAILED: requirements-table parser did not read SC-NEEDLE-COVERED's "
                 "Tasks cell as non-blank (false positive on the orphan check, constitution "
                 "11.4.201(1))")
    if req_table.get("SC-NEEDLE-BOLD") != "T-NEEDLE-GOOD":
        return ("self-check FAILED: a bold-wrapped id cell ('**SC-NEEDLE-BOLD**') was NOT "
                 "correctly unwrapped/extracted (review round 1, I4) (got %r)"
                 % req_table.get("SC-NEEDLE-BOLD", "MISSING"))
    if req_table.get("FR-NEEDLE-MULTI-A") != "T-NEEDLE-GOOD" \
            or req_table.get("FR-NEEDLE-MULTI-B") != "T-NEEDLE-GOOD":
        return ("self-check FAILED: a comma-joined multi-id cell ('FR-NEEDLE-MULTI-A, "
                 "FR-NEEDLE-MULTI-B') did NOT contribute BOTH ids to the parsed table (review "
                 "round 1, I4) (got A=%r B=%r)" % (req_table.get("FR-NEEDLE-MULTI-A"),
                                                     req_table.get("FR-NEEDLE-MULTI-B")))
    if len(unparseable) != 1 or "SC-NEEDLE-MALFORMED-ROW-NO-CLOSING-PIPE" not in unparseable[0]:
        return ("self-check FAILED: the deliberately malformed row (no closing '|') was not "
                 "reported as exactly one `unparseable` entry (review round 1, I4) (got %r)"
                 % unparseable)
    if "SC-NEEDLE-AFTER-MALFORMED" not in req_table:
        return ("self-check FAILED: the genuine table row placed AFTER the malformed row was "
                 "NOT found at all -- the parser silently stopped scanning at the malformed row "
                 "(review round 1, I4's own core reproduction: a malformed row must never hide "
                 "every row that follows it)")

    serves_all = " ".join(b["serves"] for b in blocks)
    declared = parse_scope_declared_ids(_SELF_CHECK_PLAN_DOC)
    if declared != {"FR-NEEDLE-ORPHAN", "FR-NEEDLE-COVERED"}:
        return ("self-check FAILED: scope-declaration-line parser did not find both synthetic FR "
                 "ids (got %r)" % sorted(declared))
    if re.search(r"\bFR-NEEDLE-ORPHAN\b", serves_all):
        return ("self-check FAILED: FR-NEEDLE-ORPHAN unexpectedly found in Serves text -- the "
                 "synthetic fixture itself is broken")
    if not re.search(r"\bFR-NEEDLE-COVERED\b", serves_all):
        return ("self-check FAILED: FR-NEEDLE-COVERED (the non-orphan control) was NOT found in "
                 "Serves text -- this fixture's own discrimination is broken")

    spec_ids = parse_spec_requirement_ids(_SELF_CHECK_PLAN_SPEC_DOC)
    if spec_ids != {"FR-NEEDLE-SPEC-COVERED", "FR-NEEDLE-SPEC-ORPHAN"}:
        return ("self-check FAILED: spec.md-header id extractor did not find both synthetic FR "
                 "ids (review round 1, B2/P7) (got %r)" % sorted(spec_ids))

    # review round 1 (B1): per-cause gap-marker scoping, including the negation control. (Note:
    # `has_permanent_gap_marker(_SELF_CHECK_PLAN_DOC)` is expected to be TRUE here -- the fixture
    # DOES plant one genuine marker, for RC-NEEDLE-GAPPED -- so the real B1 proof is the per-cause
    # `gap_ids` set-equality assertion immediately below, not a bare existence check.)
    gap_ids = permanent_gap_cause_ids(_SELF_CHECK_PLAN_DOC)
    if gap_ids != {"RC-NEEDLE-GAPPED"}:
        return ("self-check FAILED: per-cause permanent-gap-marker detector did not find EXACTLY "
                 "{RC-NEEDLE-GAPPED} (review round 1, B1 -- reproduction (a): two CONFIRMED/"
                 "UNMEASURED causes, only one with a genuine per-row note) (got %r)" % gap_ids)
    if permanent_gap_cause_ids(_SELF_CHECK_PLAN_NEGATION_DOC):
        return ("self-check FAILED: a NEGATION sentence ('There is no permanent gap recorded.') "
                 "was WRONGLY read as a genuine per-cause marker (review round 1, B1 -- "
                 "reproduction (b), false positive, constitution 11.4.201(1))")
    if not has_permanent_gap_marker(_SELF_CHECK_PLAN_DOC_WITH_GAP):
        return ("self-check FAILED: the synthetic WITH-gap-marker fixture's known-present "
                 "per-cause marker was NOT detected")

    words = len(_SELF_CHECK_PLAN_DOC.split())
    if words == 0:
        return "self-check FAILED: word-count over a non-empty synthetic document returned 0"
    # FIX ROUND 4 (IMP-2): via the SAME shared conversion function `cmd_plan` itself calls -- see
    # that function's own docstring for the full rationale.
    pages_equivalent = _words_to_pages_equivalent(words)

    # review round 1 (I3): feed the SAME synthetic fixture through the REAL production violation
    # function, never a parallel reimplementation -- asserting the exact violation set a
    # mutation-proof self-check requires.
    violations = compute_plan_violations(blocks, _SELF_CHECK_PLAN_CAUSES, req_table, unparseable,
                                          declared, spec_ids, gap_ids, words, pages_equivalent)

    def _has(code, key):
        return any(v["code"] == code and key in (v.get("task"), v.get("id"), v.get("row"))
                   for v in violations)

    checks = [
        (_has("no_rollback", "T-NEEDLE-BAD"), True,
         "known-missing Rollback on T-NEEDLE-BAD did not produce no_rollback"),
        (_has("no_rollback", "T-NEEDLE-GOOD"), False,
         "known-present Rollback on T-NEEDLE-GOOD WRONGLY produced no_rollback"),
        (_has("no_rollback", "T-NEEDLE-BLANKROLLBACK"), True,
         "a Rollback field PRESENT but BLANK (review round 1, I3's second mutation) did NOT "
         "produce no_rollback"),
        (_has("removes_cause_unknown_id", "RC-NEEDLE-UNKNOWN"), True,
         "a Removes field naming a cause id absent from the causes list (review round 1, B2/P2) "
         "did NOT produce removes_cause_unknown_id"),
        (_has("no_removes_cause", "T-NEEDLE-NOFIELDS"), True,
         "a task with a wholly-blank Removes/measures field did NOT produce no_removes_cause"),
        (_has("no_serves_field", "T-NEEDLE-NOFIELDS"), True,
         "a task with ONLY a Rollback field (review round 1, B2/P1) did NOT produce "
         "no_serves_field"),
        (_has("no_expected_saving", "T-NEEDLE-NOFIELDS"), True,
         "a task with no Expected-saving field did NOT produce no_expected_saving"),
        (_has("no_protecting_tests", "T-NEEDLE-NOFIELDS"), True,
         "a task with no Protecting-tests field did NOT produce no_protecting_tests"),
        (_has("orphan_requirement", "SC-NEEDLE-ORPHAN"), True,
         "a blank Tasks cell did NOT produce orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-PLACEHOLDER"), True,
         "a placeholder-shaped Tasks cell (review round 1, I4) did NOT produce orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-GHOST-TASK"), True,
         "a Tasks cell naming a NONEXISTENT task id (review round 1, I4) did NOT produce "
         "orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-MISMATCH"), True,
         "a Tasks cell naming a real task that does NOT actually Serve this requirement (review "
         "round 1, I4) did NOT produce orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-COVERED"), False,
         "a genuinely-covered row WRONGLY produced orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-BOLD"), False,
         "a genuinely-covered bold-wrapped-id row WRONGLY produced orphan_requirement"),
        (_has("orphan_requirement", "FR-NEEDLE-MULTI-A"), False,
         "a genuinely-covered comma-joined-cell id WRONGLY produced orphan_requirement"),
        (_has("orphan_requirement", "SC-NEEDLE-AFTER-MALFORMED"), True,
         "the genuine orphan row placed AFTER the malformed row (review round 1, I4's own core "
         "reproduction) did NOT produce orphan_requirement -- a later row was silently dropped"),
        (any(v["code"] == "table_row_unparseable" for v in violations), True,
         "the deliberately malformed table row did NOT produce table_row_unparseable"),
        (_has("orphan_requirement", "FR-NEEDLE-ORPHAN"), True,
         "a scope-declared-but-unserved FR id did NOT produce orphan_requirement"),
        (_has("orphan_requirement", "FR-NEEDLE-SPEC-ORPHAN"), True,
         "a spec.md-fixed-set FR id with no covering task anywhere (review round 1, B2/P7) did "
         "NOT produce orphan_requirement"),
        (_has("orphan_requirement", "FR-NEEDLE-SPEC-COVERED"), False,
         "a genuinely-served spec.md-fixed-set FR id WRONGLY produced orphan_requirement"),
        (_has("confirmed_unmeasured_no_permanent_gap", "RC-NEEDLE-NOGAP"), True,
         "a CONFIRMED/UNMEASURED cause with NO per-cause gap marker (review round 1, B1) did NOT "
         "produce confirmed_unmeasured_no_permanent_gap"),
        (_has("confirmed_unmeasured_no_permanent_gap", "RC-NEEDLE-GAPPED"), False,
         "a CONFIRMED/UNMEASURED cause WITH its own genuine per-cause gap marker (review round 1, "
         "B1) WRONGLY produced confirmed_unmeasured_no_permanent_gap"),
        (_has("confirmed_unmeasured_no_permanent_gap", "RC-NEEDLE-GOOD"), False,
         "a genuinely-measured CONFIRMED cause WRONGLY produced confirmed_unmeasured_no_"
         "permanent_gap"),
        # review round 2 (I-A): the orphan-cause check's own closed class tuple (CONFIRMED,
        # UNDETERMINED) previously had NO needle in either direction anywhere in this self-check --
        # RC-NEEDLE-ORPHAN-UNDETERMINED below is the CRITICAL one, catching the round-1 reviewer's
        # own reproduction of dropping "UNDETERMINED" from that tuple, which otherwise survives
        # both this self-check AND the full test suite untouched.
        (_has("orphan_cause", "RC-NEEDLE-ORPHAN-CONFIRMED"), True,
         "a CONFIRMED cause named nowhere in any task's Removes/measures field did NOT produce "
         "orphan_cause (review round 2, I-A)"),
        (_has("orphan_cause", "RC-NEEDLE-ORPHAN-UNDETERMINED"), True,
         "an UNDETERMINED cause named nowhere in any task's Removes/measures field did NOT "
         "produce orphan_cause -- this is the exact needle that catches dropping 'UNDETERMINED' "
         "from the orphan-cause class tuple (review round 2, I-A, the critical previously-"
         "unguarded mutation)"),
        (_has("orphan_cause", "RC-NEEDLE-ORPHAN-REFUTED"), False,
         "a REFUTED cause named nowhere in any task's Removes/measures field WRONGLY produced "
         "orphan_cause -- REFUTED causes are deliberately out of scope for this check (review "
         "round 2, I-A negative control, false positive, constitution 11.4.201(1))"),
        (_has("orphan_cause", "RC-NEEDLE-GOOD"), False,
         "a genuinely-mentioned CONFIRMED cause WRONGLY produced orphan_cause (review round 2, "
         "I-A positive-coverage control)"),
        # review round 2 (I-A): `removes_cause_unknown_id` previously had ONLY a positive
        # (known-bad-id) needle -- a real, KNOWN-good cause id in a Removes field must NOT ALSO
        # fire it (this is the exact needle that catches `if rc_id not in known_cause_ids:`
        # mutated to `if True:`, which previously survived untouched).
        (_has("removes_cause_unknown_id", "RC-NEEDLE-GOOD"), False,
         "a real, known cause id present in a task's Removes/measures field WRONGLY produced "
         "removes_cause_unknown_id (review round 2, I-A, false positive, constitution "
         "11.4.201(1))"),
        # review round 2 (Minor-7): a non-blank Removes/measures field naming NO RC- id at all.
        (_has("removes_cause_names_no_id", "T-NEEDLE-PROSEONLY"), True,
         "a non-blank Removes/measures field naming NO RC- id at all did NOT produce "
         "removes_cause_names_no_id (review round 2, Minor-7)"),
        (_has("removes_cause_names_no_id", "T-NEEDLE-GOOD"), False,
         "a Removes/measures field that DOES name a real RC- id WRONGLY produced "
         "removes_cause_names_no_id"),
        (_has("no_removes_cause", "T-NEEDLE-PROSEONLY"), False,
         "a Removes/measures field that is non-blank (prose-only) WRONGLY produced "
         "no_removes_cause"),
    ]
    for actual, expected, msg in checks:
        if actual != expected:
            return "self-check FAILED: %s (constitution 11.4.201(1) if a false positive)" % msg

    # M3: a non-string measured_share must be a clean, named finding, never an unhandled crash.
    bad_type_causes = [{"id": "RC-NEEDLE-BADTYPE", "class": "CONFIRMED", "measured_share": 12}]
    v2 = compute_plan_violations([], bad_type_causes, {}, [], set(), set(), set(), 100, 1.0)
    if not any(v["code"] == "measured_share_not_string" and v.get("row") == "RC-NEEDLE-BADTYPE"
               for v in v2):
        return ("self-check FAILED: a non-string measured_share value did NOT produce "
                 "measured_share_not_string (review round 1, M3)")

    # review round 3 (I-2): a CONFIRMED cause whose `measured_share` is the EMPTY string, `None`
    # (JSON `null`, or the key absent entirely -- `dict.get` returns `None` either way), or a
    # WHITESPACE-ONLY string (M-5's own companion reproduction) must ALL still produce
    # confirmed_unmeasured_no_permanent_gap -- NONE of these three had an exercising needle
    # anywhere in this self-check before round 3, so the reviewer's own concrete mutation
    # (`(not raw_share) or ...` changed to the literal `False or ...`) previously survived
    # untouched: under that mutation an EMPTY-string share silently stops firing this finding at
    # all, and a `None` share crashes `_UNMEASURED_RE.match(None)` with an unhandled TypeError
    # instead of ever reaching this self-check's own return value.
    for bad_share in ("", None, "   "):
        v_share = compute_plan_violations(
            [], [{"id": "RC-NEEDLE-EMPTYSHARE", "class": "CONFIRMED", "measured_share": bad_share}],
            {}, [], set(), set(), set(), 100, 1.0)
        if not any(v["code"] == "confirmed_unmeasured_no_permanent_gap"
                   and v.get("row") == "RC-NEEDLE-EMPTYSHARE" for v in v_share):
            return ("self-check FAILED: a CONFIRMED cause with measured_share=%r did NOT produce "
                     "confirmed_unmeasured_no_permanent_gap (review round 3, I-2/M-5, false "
                     "negative, constitution 11.4.201(1))" % (bad_share,))

    # FIX ROUND 4 (Minor-5): a LEADING-whitespace "UNMEASURED" value, and a common placeholder
    # value that never literally starts with the word "UNMEASURED", must BOTH still produce
    # confirmed_unmeasured_no_permanent_gap -- neither had an exercising needle before this round.
    for bad_share_2 in (" UNMEASURED", "TBD", "—", "n/a", "?"):
        v_share_2 = compute_plan_violations(
            [], [{"id": "RC-NEEDLE-BADSHARE2", "class": "CONFIRMED", "measured_share": bad_share_2}],
            {}, [], set(), set(), set(), 100, 1.0)
        if not any(v["code"] == "confirmed_unmeasured_no_permanent_gap"
                   and v.get("row") == "RC-NEEDLE-BADSHARE2" for v in v_share_2):
            return ("self-check FAILED: a CONFIRMED cause with measured_share=%r did NOT produce "
                     "confirmed_unmeasured_no_permanent_gap (fix round 4, Minor-5, false negative, "
                     "constitution 11.4.201(1))" % (bad_share_2,))
    # ... and its own positive control: a genuine, non-placeholder measured_share value must NOT be
    # swept up by the newly-added `_is_placeholder_text` branch -- proving it does not over-reject.
    v_share_good = compute_plan_violations(
        [], [{"id": "RC-NEEDLE-GOODSHARE", "class": "CONFIRMED", "measured_share": "12%"}],
        {}, [], set(), set(), set(), 100, 1.0)
    if any(v["code"] == "confirmed_unmeasured_no_permanent_gap"
           and v.get("row") == "RC-NEEDLE-GOODSHARE" for v in v_share_good):
        return ("self-check FAILED: a CONFIRMED cause with a genuine measured_share='12%' WRONGLY "
                 "produced confirmed_unmeasured_no_permanent_gap (fix round 4, Minor-5, false "
                 "positive, constitution 11.4.201(1))")

    # FIX (T179 fix-loop, IMPORTANT-1, review round 5): a genuine SINGLE-DIGIT measured share
    # ("5%", "7", "1", "9 %") must NOT be swept up as "unmeasured" -- `_is_placeholder_text`'s own
    # minimum-content floor previously required >=2 counted alphanumeric characters for a bare,
    # unstructured short token, so a one-digit share reduced to exactly 1 counted character and
    # WRONGLY failed that floor, making the value look like a placeholder. This is currently latent
    # against the real corpus (every real cause's own `measured_share` today literally reads the
    # string "UNMEASURED"), but it would silently start firing on T-A11's real single-digit
    # percentages the moment they land.
    for good_digit_share in ("5%", "7", "1", "9 %"):
        v_share_digit = compute_plan_violations(
            [], [{"id": "RC-NEEDLE-DIGITSHARE", "class": "CONFIRMED",
                  "measured_share": good_digit_share}],
            {}, [], set(), set(), set(), 100, 1.0)
        if any(v["code"] == "confirmed_unmeasured_no_permanent_gap"
               and v.get("row") == "RC-NEEDLE-DIGITSHARE" for v in v_share_digit):
            return ("self-check FAILED: a CONFIRMED cause with a genuine single-digit "
                     "measured_share=%r WRONGLY produced confirmed_unmeasured_no_permanent_gap "
                     "(T179 fix-loop IMPORTANT-1, false positive, constitution 11.4.201(1))"
                     % (good_digit_share,))
    # ... and the negative control: a genuine no-digit placeholder must STILL fire the finding --
    # proving the digit gate narrows the placeholder branch precisely, without disabling it
    # entirely for values that carry no digit at all (the existing "TBD"/"—"/"n/a"/"?" loop above
    # already covers this, re-asserted here directly alongside the digit needles for locality).
    for bad_no_digit_share in ("TBD", "—", "n/a", "?"):
        v_share_nodigit = compute_plan_violations(
            [], [{"id": "RC-NEEDLE-NODIGITSHARE", "class": "CONFIRMED",
                  "measured_share": bad_no_digit_share}],
            {}, [], set(), set(), set(), 100, 1.0)
        if not any(v["code"] == "confirmed_unmeasured_no_permanent_gap"
                   and v.get("row") == "RC-NEEDLE-NODIGITSHARE" for v in v_share_nodigit):
            return ("self-check FAILED: a CONFIRMED cause with a genuine no-digit placeholder "
                     "measured_share=%r did NOT produce confirmed_unmeasured_no_permanent_gap "
                     "(T179 fix-loop IMPORTANT-1 negative control, false negative, constitution "
                     "11.4.201(1))" % (bad_no_digit_share,))

    # review round 2 (I-A): `below_size_threshold` had NO exercising needle anywhere in this
    # self-check -- the fixture's own real word count is always far below the 15000-word/30-page-
    # equivalent floor, so relying on that alone never proves the check is genuinely WIRED (a
    # mutated `if pages_equivalent < 30.0:` -> `if False:` would pass unnoticed). Direct-call both
    # polarities against the real production function.
    v3_over = compute_plan_violations([], [], {}, [], set(), set(), set(), 100, 40.0)
    if any(v["code"] == "below_size_threshold" for v in v3_over):
        return ("self-check FAILED: an over-threshold pages_equivalent (40.0 >= 30.0) WRONGLY "
                 "produced below_size_threshold (review round 2, I-A, false positive, "
                 "constitution 11.4.201(1))")
    v3_under = compute_plan_violations([], [], {}, [], set(), set(), set(), 100, 10.0)
    if not any(v["code"] == "below_size_threshold" for v in v3_under):
        return ("self-check FAILED: an under-threshold pages_equivalent (10.0 < 30.0) did NOT "
                 "produce below_size_threshold (review round 2, I-A)")

    # review round 3 (I-2): the ACTUAL 30.0-page-equivalent THRESHOLD VALUE, and the `<` (not
    # `<=`) BOUNDARY, had no needle pinning either -- the round-2 needles immediately above only
    # ever probe 40.0 and 10.0, both far from the real boundary, so a mutated `< 30.0` -> `< 20.0`
    # (a genuinely wrong threshold VALUE) and a mutated `<` -> `<=` (a genuinely wrong boundary
    # OPERATOR, wrongly failing an exactly-30.0-pages-equivalent document that the contract's own
    # ">= 30 pages" wording says must PASS) both previously survived untouched.
    v3_just_under = compute_plan_violations([], [], {}, [], set(), set(), set(), 100, 29.9)
    if not any(v["code"] == "below_size_threshold" for v in v3_just_under):
        return ("self-check FAILED: a just-under-threshold pages_equivalent (29.9 < 30.0) did NOT "
                 "produce below_size_threshold -- catches a wrong threshold VALUE such as `< "
                 "20.0` (review round 3, I-2)")
    v3_exactly_at = compute_plan_violations([], [], {}, [], set(), set(), set(), 100, 30.0)
    if any(v["code"] == "below_size_threshold" for v in v3_exactly_at):
        return ("self-check FAILED: an EXACTLY-30.0 pages_equivalent WRONGLY produced "
                 "below_size_threshold -- the contract's own '>= 30 pages' wording requires "
                 "exactly-30.0 to PASS; catches the wrong boundary operator `<=` in place of `<` "
                 "(review round 3, I-2, false positive, constitution 11.4.201(1))")

    # FIX ROUND 4 (IMP-2): the needles above pin `pages_equivalent`'s own comparison boundary, but
    # NEVER exercise the shared `_words_to_pages_equivalent` CONVERSION function itself -- every
    # `compute_plan_violations` call above passes a hand-computed `pages_equivalent` directly,
    # bypassing the conversion entirely. Direct-call the real, current WORD-count boundary (14999
    # words is just under the documented 15000-word/30-page-equivalent floor; exactly 15000 words
    # is exactly at it) THROUGH the shared function, at BOTH call sites this fix wires it into
    # (`cmd_plan` and this self-check) -- catches a mutated divisor (e.g. `/ 100.0` or `/ 3000.0`)
    # in the real, shared conversion path, which the pages_equivalent-level needles above cannot
    # see since they bypass that function's own arithmetic altogether.
    v_words_under = compute_plan_violations([], [], {}, [], set(), set(), set(), 14999,
                                             _words_to_pages_equivalent(14999))
    if not any(v["code"] == "below_size_threshold" for v in v_words_under):
        return ("self-check FAILED: 14999 words (just under the documented 15000-word/30-page-"
                 "equivalent floor) did NOT produce below_size_threshold via the shared "
                 "`_words_to_pages_equivalent` conversion function (fix round 4, IMP-2)")
    v_words_at = compute_plan_violations([], [], {}, [], set(), set(), set(), 15000,
                                          _words_to_pages_equivalent(15000))
    if any(v["code"] == "below_size_threshold" for v in v_words_at):
        return ("self-check FAILED: exactly 15000 words WRONGLY produced below_size_threshold via "
                 "the shared `_words_to_pages_equivalent` conversion function (fix round 4, IMP-2, "
                 "false positive, constitution 11.4.201(1))")

    # review round 2 (Borderline-Important): `parse_requirements_table`'s header/row shapes must
    # tolerate an EXTRA trailing table column, and must discover a SECOND "| Requirement | Tasks |"
    # table appearing later in the SAME document rather than stopping at the first table's own end.
    extra_table, extra_unparseable = parse_requirements_table(_SELF_CHECK_PLAN_EXTRA_COLUMN_TABLE)
    if extra_table.get("SC-NEEDLE-EXTRACOL-COVERED") != "T-X":
        return ("self-check FAILED: a traceability table header carrying an EXTRA trailing "
                 "column ('| Requirement | Tasks | Notes |') was not recognised as a genuine "
                 "requirements table at all -- a real row under it (SC-NEEDLE-EXTRACOL-COVERED) "
                 "was invisible (review round 2, Borderline-Important) (got %r)"
                 % extra_table.get("SC-NEEDLE-EXTRACOL-COVERED", "MISSING"))
    if extra_table.get("SC-NEEDLE-EXTRACOL-ORPHAN") != "":
        return ("self-check FAILED: an orphan row (blank Tasks cell) under an extra-column table "
                 "header was not correctly read as blank (review round 2, Borderline-Important) "
                 "(got %r)" % extra_table.get("SC-NEEDLE-EXTRACOL-ORPHAN", "MISSING"))
    if "SC-NEEDLE-SECOND-TABLE-ROW" not in extra_table:
        return ("self-check FAILED: a SECOND '| Requirement | Tasks |' table appearing later in "
                 "the SAME document was never discovered at all -- the parser's early `break` on "
                 "the first table's own end previously hid every table that follows it (review "
                 "round 2, Borderline-Important)")
    if extra_unparseable:
        return ("self-check FAILED: the extra-column/multi-table fixture's own genuinely "
                 "well-formed rows were WRONGLY reported as unparseable (got %r)"
                 % extra_unparseable)

    # review round 3 (M-1): a standard GFM column-alignment separator row (":---|:---:") must be
    # recognised as the table's OWN separator row, never mistaken for a malformed data row.
    gfm_table, gfm_unparseable = parse_requirements_table(_SELF_CHECK_PLAN_GFM_ALIGNED_SEP_TABLE)
    if gfm_table.get("SC-NEEDLE-GFMALIGN-COVERED") != "T-Z":
        return ("self-check FAILED: a genuine data row following a GFM column-alignment "
                 "separator row (':---|:---:') was not found in the parsed table (review round 3, "
                 "M-1) (got %r)" % gfm_table.get("SC-NEEDLE-GFMALIGN-COVERED", "MISSING"))
    if gfm_unparseable:
        return ("self-check FAILED: a standard GFM column-alignment separator row (':---|:---:') "
                 "was WRONGLY reported as table_row_unparseable (review round 3, M-1, false "
                 "positive, constitution 11.4.201(1)) (got %r)" % gfm_unparseable)

    # FIX ROUND 4 (Minor-4): a separator row carrying TRAILING whitespace after its own closing "|"
    # must be recognised as the table's own separator, never mistaken for a malformed data row.
    ws_table, ws_unparseable = parse_requirements_table(_SELF_CHECK_PLAN_WHITESPACE_SEP_TABLE)
    if ws_table.get("SC-NEEDLE-TRAILINGWS-COVERED") != "T-W1":
        return ("self-check FAILED: a genuine data row following a separator row with TRAILING "
                 "whitespace ('|---|---| ') was not found in the parsed table (fix round 4, "
                 "Minor-4) (got %r)" % ws_table.get("SC-NEEDLE-TRAILINGWS-COVERED", "MISSING"))
    if ws_unparseable:
        return ("self-check FAILED: a separator row with TRAILING whitespace ('|---|---| ') was "
                 "WRONGLY reported as table_row_unparseable (fix round 4, Minor-4, false positive, "
                 "constitution 11.4.201(1)) (got %r)" % ws_unparseable)

    # FIX ROUND 4 (Minor-4): a separator row carrying LEADING indentation before its own opening
    # "|" must likewise be recognised as the table's own separator.
    indent_table, indent_unparseable = parse_requirements_table(_SELF_CHECK_PLAN_INDENTED_SEP_TABLE)
    if indent_table.get("SC-NEEDLE-INDENTEDSEP-COVERED") != "T-W2":
        return ("self-check FAILED: a genuine data row following a separator row with LEADING "
                 "indentation ('  |:---|:---:|') was not found in the parsed table (fix round 4, "
                 "Minor-4) (got %r)" % indent_table.get("SC-NEEDLE-INDENTEDSEP-COVERED", "MISSING"))
    if indent_unparseable:
        return ("self-check FAILED: a separator row with LEADING indentation ('  |:---|:---:|') "
                 "was WRONGLY reported as table_row_unparseable (fix round 4, Minor-4, false "
                 "positive, constitution 11.4.201(1)) (got %r)" % indent_unparseable)

    # FIX ROUND 4 (Minor-3): `_merge_req_tables` -- via the SAME production function `cmd_plan`
    # itself calls -- must be orphan-if-EITHER-side-orphan, never last-occurrence-wins.
    merge_tasks_by_id = {tb["id"]: tb for tb in parse_task_blocks(_SELF_CHECK_PLAN_MERGE_TASK_DOC)}
    if "T-NEEDLE-MERGE-GOOD" not in merge_tasks_by_id:
        return ("self-check FAILED: the req-table-merge fixture's own real task "
                 "'T-NEEDLE-MERGE-GOOD' was not parsed at all -- the fixture itself is broken "
                 "(fix round 4, Minor-3)")
    # (a) --plan's own row is BLANK (orphan) for an id, --tasks' own row for the SAME id genuinely
    # covers it -- the merged result must STILL be orphan (the --plan signal must not be masked).
    merged_a = _merge_req_tables(
        {"SC-NEEDLE-MERGE-A": ""}, {"SC-NEEDLE-MERGE-A": "T-NEEDLE-MERGE-GOOD"}, merge_tasks_by_id)
    if not _tasks_cell_is_orphan(merged_a.get("SC-NEEDLE-MERGE-A", "T-NEEDLE-MERGE-GOOD")):
        return ("self-check FAILED: `_merge_req_tables` let a genuinely-covering `--tasks` row "
                 "silently MASK a blank/orphan `--plan` row for the SAME id (fix round 4, Minor-3, "
                 "false negative, constitution 11.4.201(1)) (got %r)"
                 % merged_a.get("SC-NEEDLE-MERGE-A"))
    # (b) the REVERSE -- --plan's own row genuinely covers the id, --tasks' own row for the SAME id
    # is BLANK (orphan) -- the merged result must STILL be orphan.
    merged_b = _merge_req_tables(
        {"SC-NEEDLE-MERGE-B": "T-NEEDLE-MERGE-GOOD"}, {"SC-NEEDLE-MERGE-B": ""}, merge_tasks_by_id)
    if not _tasks_cell_is_orphan(merged_b.get("SC-NEEDLE-MERGE-B", "T-NEEDLE-MERGE-GOOD")):
        return ("self-check FAILED: `_merge_req_tables` did NOT treat an id as orphan when "
                 "`--tasks`' own row for it was blank, even though `--plan`'s own row genuinely "
                 "covered it (fix round 4, Minor-3, false negative, constitution 11.4.201(1)) "
                 "(got %r)" % merged_b.get("SC-NEEDLE-MERGE-B"))
    # ... and its own positive control: when BOTH documents' own rows genuinely cover the SAME id,
    # the merged result must NOT be orphan.
    merged_c = _merge_req_tables(
        {"SC-NEEDLE-MERGE-C": "T-NEEDLE-MERGE-GOOD"},
        {"SC-NEEDLE-MERGE-C": "T-NEEDLE-MERGE-GOOD"}, merge_tasks_by_id)
    if _tasks_cell_is_orphan(merged_c.get("SC-NEEDLE-MERGE-C", "")) \
            or not _row_is_covered("SC-NEEDLE-MERGE-C", merged_c.get("SC-NEEDLE-MERGE-C", ""),
                                    merge_tasks_by_id):
        return ("self-check FAILED: `_merge_req_tables` WRONGLY treated an id as orphan when BOTH "
                 "`--plan` and `--tasks` genuinely covered it (fix round 4, Minor-3 positive "
                 "control, false positive, constitution 11.4.201(1)) (got %r)"
                 % merged_c.get("SC-NEEDLE-MERGE-C"))

    return None


def cmd_plan(a):
    self_check_err = self_check_plan()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    plan_text, err = _read_doc(a.plan, "--plan")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4
    tasks_text = None
    if a.tasks:
        tasks_text, err = _read_doc(a.tasks, "--tasks")
        if err:
            print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
            return 4
    causes_text, err = _read_doc(a.causes, "--causes")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4
    try:
        causes_doc = json.loads(causes_text)
    except ValueError as exc:
        print("plan_struct_check: BLIND -- --causes %s is not valid JSON: %s" % (a.causes, exc),
              file=sys.stderr)
        return 4
    causes_list = causes_doc.get("causes") if isinstance(causes_doc, dict) else None
    if not isinstance(causes_list, list):
        print("plan_struct_check: BLIND -- --causes %s has no top-level 'causes' array (not a "
              "real plan_struct_check.py causes output)" % a.causes, file=sys.stderr)
        return 4

    spec_text = None
    if getattr(a, "spec", None):
        spec_text, err = _read_doc(a.spec, "--spec")
        if err:
            print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
            return 4

    combined_text = plan_text + ("\n" + tasks_text if tasks_text else "")
    task_blocks = parse_task_blocks(plan_text)
    if tasks_text:
        task_blocks += parse_task_blocks(tasks_text)
    if not task_blocks:
        print("plan_struct_check: BLIND -- --plan %s (and --tasks, if given) has zero parseable "
              "'#### T-' task blocks (no honest plan to check)" % a.plan, file=sys.stderr)
        return 4

    req_table, unparseable = parse_requirements_table(plan_text)
    if tasks_text:
        tasks_req_table, tasks_unparseable = parse_requirements_table(tasks_text)
        # FIX ROUND 4 (Minor-3): via the shared `_merge_req_tables` function -- see its own
        # docstring for the full rationale, and `self_check_plan`'s own direct-call needles for the
        # mutation-proof re-check against the SAME production function.
        tasks_by_id_for_merge = {tb["id"]: tb for tb in task_blocks}
        req_table = _merge_req_tables(req_table, tasks_req_table, tasks_by_id_for_merge)
        unparseable += tasks_unparseable

    declared_ids = parse_scope_declared_ids(plan_text)
    if tasks_text:
        declared_ids |= parse_scope_declared_ids(tasks_text)

    spec_ids = parse_spec_requirement_ids(spec_text) if spec_text else set()

    gap_ids = permanent_gap_cause_ids(combined_text)

    words = len(combined_text.split())
    # FIX ROUND 4 (IMP-2): via the shared `_words_to_pages_equivalent` function, never an inline
    # re-derivation -- see that function's own docstring for the full rationale.
    pages_equivalent = _words_to_pages_equivalent(words)

    violations = compute_plan_violations(task_blocks, causes_list, req_table, unparseable,
                                          declared_ids, spec_ids, gap_ids, words, pages_equivalent)

    for v in violations:
        print("plan_struct_check: plan: %s" % v, file=sys.stderr)

    body = {
        "plan": a.plan,
        "tasks": a.tasks,
        "causes": a.causes,
        "spec": getattr(a, "spec", None),
        "task_count": len(task_blocks),
        "size": {"words": words, "pages_equivalent": pages_equivalent},
        "permanent_gap_marker_present": bool(gap_ids),
        "permanent_gap_marker_cause_ids": sorted(gap_ids),
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA_PLAN,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        return write_rc
    return rc


# ---------------------------------------------------------------------------
# `triple` (CT-5, Post-Design Principle IV; common-conventions.md C-005; ATM-1109, 2026-10-01).
# See this module's own top-of-file docstring, "`triple` (CT-5, ...)" section, for the full
# rationale of how "analyzer/oracle/judge/guard" scope and per-task completeness are each
# mechanically derived (never hand-picked) from common-conventions.md's own Tool map table and
# tasks.md's own "RED test `<path>` ... (plan T-...)" lines.
# ---------------------------------------------------------------------------

# The closed, literal self-validation-triple (C-005) vocabulary this project's own contracts and
# RED-test files actually use -- verified against the real corpus (every one of the 12 real tool
# contracts; T052/T091/T125/T126's own real test files) before choosing this set, constitution
# 11.4.6/11.4.201(7)(a), never guessed. "control needle" is accepted as an ADDITIONAL golden-good-
# class marker alongside the literal "golden-good"/"golden good"/"golden_good" phrases: T052's
# `test_io_trace_red.sh` and T126's `test_resume_revalidate_red.sh` both satisfy their own
# golden-good member EXCLUSIVELY via "control needle" language and never once write "golden-good"
# anywhere in their own text -- confirmed by direct inspection of both files before this fallback
# was added; without it, this check would wrongly report BOTH of CT-5's own two hardest-named
# "incomplete" tasks as still missing their golden-good member even after their own negative-
# control fix landed, which is not what tasks.md's own T052/T126 evidence blocks claim is true.
_SVT_GOOD_RE = re.compile(r"golden[-_ ]good|control needle", re.IGNORECASE)
_SVT_BAD_RE = re.compile(r"golden[-_ ]bad", re.IGNORECASE)
_SVT_NEG_RE = re.compile(r"negative[-_ ]control|negctrl", re.IGNORECASE)
_SVT_ALL_CLASSES = frozenset(("golden-good", "golden-bad", "negative-control"))


def _svt_classes_present(text):
    """Returns the subset of `_SVT_ALL_CLASSES` this `text`'s own content genuinely demonstrates,
    via the closed, literal self-validation-triple vocabulary above. HONESTLY DISCLOSED, NOT
    caught (matching this file's own established convention for partial coverage -- see this
    module's own top-of-file docstring, `triple` section, for the two REAL, confirmed gaps this
    bounded vocabulary does not close): a fixture-class member represented ONLY by an abbreviated
    directory-naming convention with no descriptive prose spelling out one of the phrases above
    (e.g. a tool whose own test exclusively names fixtures `<prefix>_bad_*`/`<prefix>_good_*`/
    `<prefix>_negctrl_*` without ever writing "golden"/"negative control" anywhere in its own
    text); never a guess at a broader, unverified vocabulary (constitution 11.4.6)."""
    found = set()
    if _SVT_GOOD_RE.search(text):
        found.add("golden-good")
    if _SVT_BAD_RE.search(text):
        found.add("golden-bad")
    if _SVT_NEG_RE.search(text):
        found.add("negative-control")
    return found


_TOOL_MAP_HEADING_RE = re.compile(r"^### Tool map\b")
_TOOL_MAP_HEADER_ROW_RE = re.compile(r"^\|\s*Contract\s*\|", re.IGNORECASE)
# The one range-notation shape common-conventions.md's own Tool map table uses today
# (host-resource-attribution's "T-F01..T-F05" cell) -- a plain comma-separated id list (every
# OTHER row) never matches this at all and is left untouched by `_expand_task_id_cell` below.
_TASK_ID_RANGE_RE = re.compile(r"\bT-([A-Za-z]+)(\d+)\.\.(?:T-[A-Za-z]+)?(\d+)\b")


def _expand_task_id_cell(cell):
    """Returns the list of plan task ids a Tool-map "Plan tasks" cell names, expanding the one
    range-notation shape this project's own table uses ("T-F01..T-F05") into every individual id
    it denotes, zero-padded to the SAME width as its own start number (never assuming a fixed
    width, constitution 11.4.6). A plain comma-separated cell (no range) round-trips unchanged."""
    def _expand(m):
        prefix, start, end = m.group(1), m.group(2), m.group(3)
        width = len(start)
        ids = ["T-%s%0*d" % (prefix, width, n) for n in range(int(start), int(end) + 1)]
        return ", ".join(ids)
    expanded = _TASK_ID_RANGE_RE.sub(_expand, cell)
    return [tok.strip().strip("`*") for tok in expanded.split(",") if tok.strip().strip("`*")]


def parse_tool_map(text):
    """Parses common-conventions.md's own "### Tool map (contract -> plan file -> plan task)"
    table -- the structural, already-present mapping this file reuses rather than inventing its
    own classification of which plan tasks are "analyzer/oracle/judge/guard" tasks (see this
    module's own top-of-file docstring, `triple` section, for the full rationale). Returns a list
    of {"contract", "tool", "tasks"} dicts, one per data row, in table order, stopping at the
    first non-table-row line (the real document's own footnote paragraph, "Plan tools that no
    contract ... covers", is correctly excluded this way -- it does not start with "|"). Returns
    [] when no "### Tool map" heading, or no header row naming "Contract" after it before the
    next heading, is found at all -- the caller treats this as BLIND, never a silent empty-scope
    PASS (constitution 11.4.201(6))."""
    lines = text.splitlines()
    heading_idx = None
    for i, l in enumerate(lines):
        if _TOOL_MAP_HEADING_RE.match(l):
            heading_idx = i
            break
    if heading_idx is None:
        return []
    i = heading_idx + 1
    header_idx = None
    while i < len(lines):
        if _TOOL_MAP_HEADER_ROW_RE.match(lines[i].strip()):
            header_idx = i
            break
        if lines[i].startswith("## ") or lines[i].startswith("### "):
            break  # a later section started before any header row was found
        i += 1
    if header_idx is None:
        return []
    i = header_idx + 1
    if i < len(lines) and _TABLE_SEP_ROW_RE.match(lines[i].strip()):
        i += 1
    rows = []
    while i < len(lines):
        line = lines[i].strip()
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) == 3:
            rows.append({"contract": cells[0].strip("`"), "tool": cells[1],
                         "tasks": _expand_task_id_cell(cells[2])})
        i += 1
    return rows


# Matches this project's own real tasks.md convention (T052/T091/T125/T126's own real lines,
# verified before choosing this shape, constitution 11.4.6): a line naming a RED test file via
# the literal phrase "RED test(s) `<path>`" (singular or plural, case-insensitive). HONESTLY
# DISCLOSED, NOT recognised (see this module's own top-of-file docstring, `triple` section): a
# RED-establishing task line phrased with a verb other than "RED test" (a REAL, confirmed case:
# T-B01's own line reads "Write and run the reproduction probe `...`; RED = ...").
_RED_TEST_LINE_RE = re.compile(r"RED tests?\s*`([^`]+)`", re.IGNORECASE)
_PLAN_REF_PAREN_RE = re.compile(r"\(plan\s+([^)]+)\)", re.IGNORECASE)


def parse_red_test_task_map(text):
    """Scans `text` (tasks.md) for every line naming a RED test file via `_RED_TEST_LINE_RE`
    with an accompanying "(plan T-...)" annotation on the SAME line, and returns
    {plan_task_id: [test_file_path, ...]} -- a task can be named by more than one RED-test line
    (a comma-joined "(plan T-X, T-Y)" annotation maps BOTH ids to the same path); every path
    found is kept in first-seen order, deduplicated, never only the first."""
    out = {}
    for line in text.splitlines():
        m = _RED_TEST_LINE_RE.search(line)
        if not m:
            continue
        path = m.group(1)
        for pm in _PLAN_REF_PAREN_RE.finditer(line):
            for tid in _CELL_TASK_ID_RE.findall(pm.group(1)):
                out.setdefault(tid, [])
                if path not in out[tid]:
                    out[tid].append(path)
    return out


def compute_triple_violations(tool_map_rows, contract_classes, contract_present, known_task_ids,
                               red_test_map, test_file_classes):
    """Single, shared, I/O-free violation-generating function for the `triple` subcommand (CT-5)
    -- exercised by BOTH `cmd_triple` (the real run, over real files already read by its own
    caller) and `self_check_triple` (over a synthetic in-memory fixture), matching this file's
    own established review-round-1 (I3) Producer != Verifier discipline (`compute_plan_
    violations`'s own docstring documents the identical rationale for `plan`): a mutation to the
    logic below is caught identically whether exercised via a real run or the self-check, since
    both call this SAME function.

    `tool_map_rows`: common-conventions.md's own Tool map table, already parsed by
    `parse_tool_map` -- [{"contract", "tool", "tasks"}, ...].
    `contract_classes`: {contract_name: set_of_classes_found_in_that_contracts_own_text} --
    already computed via `_svt_classes_present` on each contract file's REAL content.
    `contract_present`: {contract_name: bool} -- whether that contract's own .md file could be
    read at all; a contract the Tool map names but whose file is missing/unreadable is itself a
    violation, `contract_file_missing`, never silently skipped.
    `known_task_ids`: the set of plan task ids that genuinely exist in --plan (`parse_task_
    blocks`'s own "id" field) -- a Tool-map-named task id NOT in this set is `tool_map_task_
    unknown`.
    `red_test_map`: {plan_task_id: [test_file_path, ...]} -- already parsed by `parse_red_test_
    task_map` from the real tasks.md text.
    `test_file_classes`: {test_file_path: (classes_found_set_or_None, readable_bool)} -- already
    read + classified by the caller; `classes_found_set_or_None` is None when `readable_bool` is
    False (the path could not be opened at all -- `triple_test_file_unreadable`).

    A contract whose OWN text does not genuinely demonstrate ALL THREE self-validation-triple
    classes is OUT OF SCOPE for this check entirely -- never silently assumed in-scope just
    because the Tool map names it (this is why `contract_classes`, not a fixed task-id list,
    decides scope: CT-5's own box text names representative examples, never an exhaustive,
    hand-maintained list this file would otherwise have to keep in sync by hand, constitution
    11.4.6 -- see this module's own top-of-file docstring for the full derivation).

    Returns (violations, in_scope_task_ids) -- the latter for the body's own "in_scope_tasks"
    reporting field, so a consumer can see exactly which plan tasks this run held to the CT-5
    bar without re-deriving it."""
    violations = []
    in_scope_task_ids = set()
    for row in tool_map_rows:
        contract = row["contract"]
        if not contract_present.get(contract, False):
            violations.append({"code": "contract_file_missing", "contract": contract})
            continue
        classes = contract_classes.get(contract, set())
        if classes != _SVT_ALL_CLASSES:
            # Out of scope: this contract's own text does not demonstrate it ships all three
            # self-validation-triple classes itself -- never assumed in-scope (see docstring).
            continue
        for tid in row["tasks"]:
            if tid not in known_task_ids:
                violations.append({"code": "tool_map_task_unknown", "contract": contract,
                                    "task": tid})
                continue
            in_scope_task_ids.add(tid)

    for tid in sorted(in_scope_task_ids):
        paths = red_test_map.get(tid, [])
        if not paths:
            violations.append({"code": "triple_test_file_missing", "task": tid})
            continue
        found = set()
        any_readable = False
        unreadable = []
        for path in paths:
            classes, readable = test_file_classes.get(path, (None, False))
            if readable:
                any_readable = True
                found |= classes
            else:
                unreadable.append(path)
        for path in unreadable:
            violations.append({"code": "triple_test_file_unreadable", "task": tid, "file": path})
        if any_readable:
            missing = sorted(_SVT_ALL_CLASSES - found)
            if missing:
                violations.append({"code": "triple_incomplete", "task": tid,
                                    "missing": missing, "files": sorted(paths)})
    return violations, in_scope_task_ids


def self_check_triple():
    """§11.4.201/§11.4.115(F) control needle for `compute_triple_violations` AND its own upstream
    parsers (`_svt_classes_present`, `_expand_task_id_cell`, `parse_tool_map`, `parse_red_test_
    task_map`), run against synthetic, in-memory fixtures (never real files, matching `self_check_
    plan`'s own convention). Returns None on success, else a diagnostic string (caller exits 3)."""
    # --- parsing-helper needles (independent of the violation logic below) ---
    range_expanded = _expand_task_id_cell("T-F01..T-F05")
    if range_expanded != ["T-F01", "T-F02", "T-F03", "T-F04", "T-F05"]:
        return ("self-check FAILED: _expand_task_id_cell('T-F01..T-F05') did not expand to the "
                 "5 individual ids (got %r)" % (range_expanded,))
    plain = _expand_task_id_cell("T-A09, T-A10, T-D06")
    if plain != ["T-A09", "T-A10", "T-D06"]:
        return ("self-check FAILED: _expand_task_id_cell on a plain comma-separated cell did not "
                 "round-trip (got %r)" % (plain,))

    tm_doc = ("### Tool map (contract -> plan file -> plan task)\n\n"
              "| Contract | Tool | Plan tasks |\n"
              "|---|---|---|\n"
              "| needle-contract | `$FC/x.py` | T-X01, T-X02 |\n"
              "\n"
              "Plan tools that no contract covers: ...\n")
    tm_rows = parse_tool_map(tm_doc)
    if tm_rows != [{"contract": "needle-contract", "tool": "`$FC/x.py`",
                    "tasks": ["T-X01", "T-X02"]}]:
        return "self-check FAILED: parse_tool_map misparsed the synthetic needle table (got %r)" % (tm_rows,)
    if parse_tool_map("no tool map heading here at all") != []:
        return "self-check FAILED: parse_tool_map did not return [] when no heading is present"

    red_doc = ("- [x] T999 [TDD] RED test `tests/test_needle_red.sh` (plan T-X01; FR-001)\n"
               "- [x] T998 [TDD] RED tests `tests/test_needle2_red.sh` (plan T-X02, T-X03; FR-002)\n"
               "- [x] T997 [SUBAGENT] Implement the thing (plan T-X01; FR-001)\n")
    red_map = parse_red_test_task_map(red_doc)
    if red_map.get("T-X01") != ["tests/test_needle_red.sh"]:
        return ("self-check FAILED: parse_red_test_task_map did not map T-X01 to its singular "
                 "RED test (got %r)" % (red_map.get("T-X01"),))
    if (red_map.get("T-X02") != ["tests/test_needle2_red.sh"]
            or red_map.get("T-X03") != ["tests/test_needle2_red.sh"]):
        return ("self-check FAILED: parse_red_test_task_map did not map a plural 'RED tests' "
                 "line naming 2 plan tasks to BOTH of them (got %r)" % (red_map,))

    if _svt_classes_present("a golden-GOOD run; GOLDEN_BAD case; NEGCTRL check") != _SVT_ALL_CLASSES:
        return "self-check FAILED: _svt_classes_present is not case/separator-insensitive over all 3 classes"
    if _svt_classes_present("just a control needle, nothing else") != {"golden-good"}:
        return "self-check FAILED: _svt_classes_present did not accept 'control needle' as the golden-good class"
    if _svt_classes_present("ordinary prose with no triple vocabulary at all") != set():
        return "self-check FAILED: _svt_classes_present found triple vocabulary in ordinary prose (false positive, constitution 11.4.201(1))"

    # --- compute_triple_violations needles (one per violation code, plus the scope-exclusion
    # false-positive guard) ---
    tool_map_rows = [
        {"contract": "needle-complete", "tool": "`$FC/x.py`", "tasks": ["T-NEEDLE-GOOD"]},
        {"contract": "needle-incomplete", "tool": "`$FC/y.py`", "tasks": ["T-NEEDLE-BAD"]},
        {"contract": "needle-no-test", "tool": "`$FC/z.py`", "tasks": ["T-NEEDLE-NOTEST"]},
        {"contract": "needle-unreadable", "tool": "`$FC/w.py`", "tasks": ["T-NEEDLE-ORPHAN"]},
        {"contract": "needle-missing-file", "tool": "`$FC/q.py`",
         "tasks": ["T-NEEDLE-MISSINGCONTRACT"]},
        {"contract": "needle-not-in-scope", "tool": "`$FC/v.py`", "tasks": ["T-NEEDLE-UNSCOPED"]},
        {"contract": "needle-unknown-task", "tool": "`$FC/u.py`", "tasks": ["T-NEEDLE-GHOST"]},
    ]
    contract_present = {
        "needle-complete": True, "needle-incomplete": True, "needle-no-test": True,
        "needle-unreadable": True, "needle-missing-file": False,
        "needle-not-in-scope": True, "needle-unknown-task": True,
    }
    contract_classes = {
        "needle-complete": set(_SVT_ALL_CLASSES),
        "needle-incomplete": set(_SVT_ALL_CLASSES),
        "needle-no-test": set(_SVT_ALL_CLASSES),
        "needle-unreadable": set(_SVT_ALL_CLASSES),
        "needle-missing-file": set(),
        "needle-not-in-scope": {"golden-good", "golden-bad"},  # missing negative-control itself
        "needle-unknown-task": set(_SVT_ALL_CLASSES),
    }
    known_task_ids = {"T-NEEDLE-GOOD", "T-NEEDLE-BAD", "T-NEEDLE-NOTEST", "T-NEEDLE-ORPHAN",
                       "T-NEEDLE-UNSCOPED"}  # T-NEEDLE-GHOST, T-NEEDLE-MISSINGCONTRACT absent
    red_test_map = {
        "T-NEEDLE-GOOD": ["fixtures/needle_good_red.sh"],
        "T-NEEDLE-BAD": ["fixtures/needle_bad_red.sh"],
        "T-NEEDLE-ORPHAN": ["fixtures/needle_missing_red.sh"],
        # T-NEEDLE-NOTEST and T-NEEDLE-UNSCOPED intentionally absent.
    }
    test_file_classes = {
        "fixtures/needle_good_red.sh": (set(_SVT_ALL_CLASSES), True),
        "fixtures/needle_bad_red.sh": ({"golden-good", "golden-bad"}, True),
        "fixtures/needle_missing_red.sh": (None, False),
    }

    violations, in_scope = compute_triple_violations(
        tool_map_rows, contract_classes, contract_present, known_task_ids, red_test_map,
        test_file_classes)

    if "T-NEEDLE-UNSCOPED" in in_scope:
        return ("self-check FAILED: a contract missing negative-control in its OWN text "
                 "(needle-not-in-scope) was wrongly treated as in-scope for CT-5")
    if any(v.get("task") == "T-NEEDLE-GOOD" for v in violations):
        return "self-check FAILED: a genuinely-complete triple (T-NEEDLE-GOOD) was wrongly flagged (false positive, constitution 11.4.201(1))"
    bad_v = [v for v in violations if v.get("task") == "T-NEEDLE-BAD"]
    if not (len(bad_v) == 1 and bad_v[0]["code"] == "triple_incomplete"
            and bad_v[0]["missing"] == ["negative-control"]):
        return ("self-check FAILED: a triple missing exactly its negative-control member "
                 "(T-NEEDLE-BAD) was not flagged triple_incomplete with missing=['negative-control'] "
                 "(got %r)" % (bad_v,))
    if not any(v["code"] == "triple_test_file_missing" and v["task"] == "T-NEEDLE-NOTEST"
               for v in violations):
        return "self-check FAILED: a task with ZERO red-test entries (T-NEEDLE-NOTEST) was not flagged triple_test_file_missing"
    if not any(v["code"] == "triple_test_file_unreadable" and v["task"] == "T-NEEDLE-ORPHAN"
               for v in violations):
        return "self-check FAILED: a task whose test file cannot be read (T-NEEDLE-ORPHAN) was not flagged triple_test_file_unreadable"
    if not any(v["code"] == "contract_file_missing" and v["contract"] == "needle-missing-file"
               for v in violations):
        return "self-check FAILED: a Tool-map contract with no real file (needle-missing-file) was not flagged contract_file_missing"
    if not any(v["code"] == "tool_map_task_unknown" and v["task"] == "T-NEEDLE-GHOST"
               for v in violations):
        return "self-check FAILED: a Tool-map task id absent from --plan (T-NEEDLE-GHOST) was not flagged tool_map_task_unknown"
    if any(v.get("task") == "T-NEEDLE-UNSCOPED" for v in violations):
        return ("self-check FAILED: a task belonging ONLY to an out-of-scope contract "
                 "(T-NEEDLE-UNSCOPED, which has no red-test entry at all) was wrongly given its "
                 "own violation -- scope exclusion must suppress this entirely")
    return None


def cmd_triple(a):
    self_check_err = self_check_triple()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    plan_text, err = _read_doc(a.plan, "--plan")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4
    tasks_text, err = _read_doc(a.tasks, "--tasks")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4
    cc_path = os.path.join(a.contracts, "common-conventions.md")
    cc_text, err = _read_doc(cc_path, "--contracts")
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4

    known_task_ids = {tb["id"] for tb in parse_task_blocks(plan_text)}
    if not known_task_ids:
        print("plan_struct_check: BLIND -- --plan %s has zero parseable '#### T-' task blocks "
              "(no honest plan to check)" % a.plan, file=sys.stderr)
        return 4

    tool_map_rows = parse_tool_map(cc_text)
    if not tool_map_rows:
        print("plan_struct_check: BLIND -- %s has no parseable '### Tool map' table (cannot "
              "decide CT-5 scope)" % cc_path, file=sys.stderr)
        return 4

    red_test_map = parse_red_test_task_map(tasks_text)

    contract_present = {}
    contract_classes = {}
    for row in tool_map_rows:
        contract = row["contract"]
        if contract in contract_present:
            continue
        path = os.path.join(a.contracts, contract + ".md")
        text, err = _read_doc(path, "--contracts")
        contract_present[contract] = err is None
        contract_classes[contract] = _svt_classes_present(text) if err is None else set()

    all_paths = sorted({p for paths in red_test_map.values() for p in paths})
    test_file_classes = {}
    for path in all_paths:
        full = os.path.join(a.root, path) if getattr(a, "root", None) else path
        text, err = _read_doc(full, "--tasks (RED test path)")
        if err is None:
            test_file_classes[path] = (_svt_classes_present(text), True)
        else:
            test_file_classes[path] = (None, False)

    violations, in_scope = compute_triple_violations(
        tool_map_rows, contract_classes, contract_present, known_task_ids, red_test_map,
        test_file_classes)

    for v in violations:
        print("plan_struct_check: triple: %s" % v, file=sys.stderr)

    body = {
        "plan": a.plan,
        "tasks": a.tasks,
        "contracts": a.contracts,
        "in_scope_tasks": sorted(in_scope),
        "in_scope_task_count": len(in_scope),
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA_TRIPLE,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        return write_rc
    return rc


def main(argv):
    p = argparse.ArgumentParser(prog="plan_struct_check.py")
    sub = p.add_subparsers(dest="cmd_name", required=True)
    # T046 scope: `causes`. T159 scope: `landing`, `rule-diff`. T179 scope (this commit):
    # `research`, `plan`.

    c = sub.add_parser("causes")
    c.add_argument("--doc", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--post-a11", action="store_true",
                    help="opt-in: enforce measured_share for CONFIRMED rows (clause (f); "
                         "see module docstring). Never on by default.")
    c.add_argument("--operator-causes",
                    help="opt-in: comma-separated Origin tokens (e.g. O1,O2,O3,O4,O5,O6) that "
                         "must each appear in >=1 row's Origin cell (clause (g), 'configured "
                         "list'). Omitted by default -- never silently assumed satisfied.")

    r = sub.add_parser("research")
    r.add_argument("--log", required=True,
                    help="research.md path (its own §3 decision log + §6 research-pass log).")
    r.add_argument("--plan", required=True,
                    help="plan.md path (its tasks' own Origin fields decide which decisions are "
                         "'plan recommendations' needing a citation; see module docstring).")
    r.add_argument("--out", required=True)

    l = sub.add_parser("landing")
    l.add_argument("--constitution", required=True,
                    help="constitution submodule root (contains Constitution.md and scripts/).")
    l.add_argument("--anchors", required=True,
                    help="comma-separated anchor numbers (e.g. 11.4.230,11.4.231 or bare "
                         "230,231) to check per SC-C-004.")
    l.add_argument("--out", required=True)

    rd = sub.add_parser("rule-diff")
    rd.add_argument("--constitution", required=True,
                     help="constitution submodule root (contains Constitution.md, a git repo).")
    rd.add_argument("--base", required=True,
                     help="git ref (sha/tag/branch) to diff the current Constitution.md against.")
    rd.add_argument("--out", required=True)
    rd.add_argument("--operator-decisions",
                     help="opt-in: comma-separated <anchor>=<decision-record-reference> pairs "
                          "(e.g. 11.4.230=DEC-1234,231=DEC-1235) exempting a SUBSTANTIVE hunk or "
                          "a removed anchor from failing (SC-C-005's own exemption clause -- a "
                          "bare anchor number with no referenced record is a usage error, never "
                          "silently accepted). Omitted by default -- never silently assumed "
                          "exempt.")

    pl = sub.add_parser("plan")
    pl.add_argument("--plan", required=True, help="plan.md path (its own '#### T-' task blocks).")
    pl.add_argument("--tasks",
                     help="optional tasks.md path -- real tasks.md carries no '#### T-' blocks of "
                          "its own; its only role here is contributing its own word count to the "
                          "size-floor check ('plan + supporting documents'). Omitted by default.")
    pl.add_argument("--causes", required=True,
                     help="causes.json path (this tool's own `causes` subcommand output).")
    pl.add_argument("--spec",
                     help="opt-in: spec.md path -- when given, cross-checks every task's own "
                          "Serves/scope-declared coverage against the FIXED FR-001..FR-025/"
                          "SC-001..SC-010 universe spec.md itself defines (SC-C-003's full "
                          "bipartite check, review round 1 B2/P7), independent of whichever "
                          "subset the PLAN document happens to declare covering. Omitted by "
                          "default -- never silently assumed satisfied (matching `causes`'s own "
                          "--post-a11/--operator-causes convention).")
    pl.add_argument("--out", required=True)

    tr = sub.add_parser("triple")
    tr.add_argument("--plan", required=True,
                     help="plan.md path (source of truth for which plan task ids genuinely "
                          "exist, via the same `#### T-' task blocks `plan` reads).")
    tr.add_argument("--tasks", required=True,
                     help="tasks.md path (its own 'RED test `<path>` ... (plan T-...)' lines).")
    tr.add_argument("--contracts", required=True,
                     help="contracts directory holding common-conventions.md (its own '### Tool "
                          "map' table) and the per-tool contract .md files it names.")
    tr.add_argument("--root",
                     help="optional prefix directory each discovered RED-test path is resolved "
                          "against. Omitted by default -- every path is opened exactly as named "
                          "in --tasks, relative to the current working directory.")
    tr.add_argument("--out", required=True)

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    table = {"causes": cmd_causes, "landing": cmd_landing, "rule-diff": cmd_rule_diff,
             "research": cmd_research, "plan": cmd_plan, "triple": cmd_triple}
    try:
        return table[a.cmd_name](a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("plan_struct_check: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
