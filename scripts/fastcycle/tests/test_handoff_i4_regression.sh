#!/bin/bash
# Purpose : T140 Round 1 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) finding I4 regression guard --
#           EXTENDED by T140 Round 2's I2 + I3 fixes, Round 3's R3-I1 fix,
#           Round 4's R4-I1 fix, and Round 5's R5-I1 + R5-I2 fixes (this
#           file's own header documents all five rounds so the guard's own
#           history is legible from the file alone).
#
# I4 (verbatim from the Round 1 review, recorded in docs/CONTINUATION.md
# ADDENDUM 78):
# "`handoff.py resume-check` fails OPEN (non-git-tree deps and a missing
# `ground_truth_effects.json` are silently skipped, reporting
# `safe_to_resume_without_reverification: true` with no skip recorded -- a
# section 11.4.201(6) false-null)."
#
# Fixed in orchestration/handoff.py's cmd_resume_check (commit cf0242a) by:
#   (a) an external_deps entry whose `kind` is anything OTHER than the only
#       re-hashable kind, "git-tree", is now recorded as its own
#       "unverifiable-external-dependency" unsafe_reasons entry (with its
#       declared affects_verified ids added to facts_needing_reverification)
#       instead of being silently `continue`d past;
#   (b) a MISSING ground_truth_effects.json sibling is now recorded as its
#       own "unverifiable-ground-truth" unsafe_reasons entry WHEN the
#       record's own effects_performed is non-empty.
#
# R2-I2 (T140 Round 2 review, three sub-findings on the Round 1 I4 fix
# itself -- (C) is a genuine ARCHITECTURAL correction of the Round 1 fix's
# own design, not merely a missed case: an EMPTY effects_performed does NOT
# prove no effect occurred -- the agent could have crashed BEFORE it ever
# recorded one in its own handoff doc -- so a missing ground_truth_effects.json
# is now ALWAYS an unverifiable gap, regardless of effects_performed's own
# emptiness):
#   (C) missing ground_truth_effects.json with an EMPTY effects_performed
#       used to give safe=true with no skip recorded -- now ALWAYS an
#       "unverifiable-ground-truth" finding (the empty-vs-non-empty cases
#       stay honestly DISTINGUISHED in the detail text, both now unsafe).
#   (D) a malformed/unreadable ground_truth_effects.json (parse error, or a
#       valid-JSON-but-non-list top-level value) used to be silently
#       coerced to `[]` (read as "no ground truth effects exist") -- now its
#       own distinct "unreadable-ground-truth" finding, never silently
#       absorbed.
#   (F) a non-dict external_deps entry, or a dict entry whose `kind` field
#       is itself missing/malformed, used to be silently `continue`d past
#       (DEC-34 requires EVERY dependency be re-hashed) -- now its own
#       distinct "malformed-external-dependency" finding, never silently
#       skipped.
# Fixed in orchestration/handoff.py's cmd_resume_check (this file's own
# accompanying source commit).
#
# R2-I3 (T140 Round 2 review, a regression THIS test file itself had):
# "test_handoff_i4_regression.sh now fails every run. Its guard-viability
# step uses `git show HEAD:scripts/fastcycle/orchestration/handoff.py` as
# the 'pre-fix' version. Since commit cf0242a, HEAD *is* the fixed version.
# ... The pre-fix copy should be pinned (a fixture file or an explicit
# commit such as d677f0c), never HEAD."
#
# R2-I3 fix (this file, this edit): `d677f0c` was VERIFIED (via `git log
# --oneline -- scripts/fastcycle/orchestration/handoff.py`) to be the WRONG
# commit -- it is T140 Round 1 finding I5's *limit_class.py* half, a
# different file entirely, never touching handoff.py. The genuinely correct
# pre-I4-fix commit for handoff.py is `64daa96` (the last commit that
# touched this file before cf0242a landed the I4 fix), confirmed by:
#   git log --oneline -- scripts/fastcycle/orchestration/handoff.py
#     cf0242a  <- I3+I4+I5(handoff.py half) fix
#     64daa96  <- T134: resume/resume-check FIRST implemented (pre-I4-fix)
#     f2a11de  <- T133: write/validate implemented
# Rather than a commit-hash pin (which the R2-I3 finding itself proves is a
# footgun -- a wrong hash silently resolves to a DIFFERENT, unrelated file's
# history with no error), this fix uses the MORE ROBUST of the two options
# the task text offers: a CHECKED-IN FIXTURE COPY of each pre-fix file's
# EXACT byte content, immune to any future history rewrite, branch move, or
# HEAD advance -- `fixtures/resume_revalidate/_pinned/handoff_pre_i4_fix.py`
# (commit 64daa96, the TRUE pre-I4-fix content) and
# `fixtures/resume_revalidate/_pinned/handoff_pre_r2i2_fix.py` (this
# submodule's HEAD immediately BEFORE the R2-I2 fix landed -- i.e. the
# I4-fixed-but-still-R2-I2-broken content, used to prove the THREE new R2-I2
# fixtures below genuinely catch a revert of THAT fix). Both pinned copies
# were extracted via `git show <verified-commit>:...` ONCE, at authoring
# time, and are themselves ordinary tracked files from this point on -- this
# script never invokes `git show` against a moving ref again.
#
# R3-I1 fix (T140 Round 3 review, a sibling gap of Round 2's I2 in this SAME
# function -- cmd_resume_check -- that fix did not reach; source-file commit
# alongside this edit): THREE sub-findings, all fixed in
# orchestration/handoff.py's cmd_resume_check:
#   (a) a non-dict `ground_truth_effects.json` entry (check (4)) was
#       silently `continue`d past -- now its own distinct
#       "malformed-ground-truth-entry" finding.
#   (b) a non-dict `pending` entry (check (3)) was silently `continue`d past
#       -- now its own distinct "malformed-pending-step" finding. (The
#       reviewer's own repro confirmed this ALSO passes `cmd_write`'s
#       write-time check, since `_json_list_arg` -- shared verbatim across
#       --pending-json/--external-deps-json/--effects-performed-json, three
#       fields with three different required shapes -- validates only
#       top-level list-ness, never per-entry shape; hardening it generically
#       would need a per-field shape contract it does not carry, so per the
#       ALREADY-ESTABLISHED check-(2) precedent -- a non-dict external_deps
#       entry is likewise caught here, in resume-check, never at write --
#       resume-check remains the right and only place this is caught.)
#   (c) a `None in {None}` id-matching bug: an `effects_performed` entry
#       missing its `id` field used to contribute the literal `None` to the
#       match-key set, so an UNRELATED ground-truth entry that also happened
#       to lack an `id` would wrongly test as "already recorded" -- fixed by
#       excluding `None`/missing ids from the match-key set entirely, so an
#       id-less ground-truth entry is now correctly UNMATCHABLE (always
#       falls through to the pre-existing "unrecorded-external-effect"
#       finding, never a silent match).
# Investigated and confirmed NOT present, per the reviewer's own explicit
# request to state so honestly rather than invent a fix: the SAME
# silently-skip-a-malformed-entry pattern in checks (1) and (5) (both guard
# `if not isinstance(v, dict)` on `verified` entries). Unlike (a)/(b) above,
# a non-dict `verified` entry is the DOCUMENTED, INTENDED shape
# `cmd_write`'s own `--verified` interface produces (bare ref-id strings --
# see the module docstring's own "e.g. the bare id strings `cmd_write`
# itself produces"), not caller-supplied malformed input DEC-34 requires be
# inspectable; skipping it discards no established_at/phase signal that
# genuinely existed. Check (5) skipping such an entry is additionally the
# SAFE direction, not a fail-open one: excluding it from `verified_phases`
# can only LOWER (never raise) `last_verified_phase`, which makes
# `inconsistent-transition` MORE likely to fire, never less -- the opposite
# of (a)/(b)'s fail-open bug. `fixtures/resume_revalidate/_pinned/
# handoff_pre_r3i1_fix.py` (this submodule's HEAD immediately BEFORE this
# fix landed) is the fourth pinned pre-fix copy, extracted the same way.
#
# R4-I1 fix (T140 Round 4 review, a FOURTH sibling gap in cmd_resume_check --
# after Round 1's I4, Round 2's R2-I2, and Round 3's R3-I1, all in this SAME
# function -- source-file commit alongside this edit): R3-I1 fixed non-dict
# entries; it did NOT cover a dict entry whose OWN fields have the WRONG
# TYPE. Those used to crash with an UNCAUGHT Python TypeError (never a clean,
# named finding) instead of failing closed -- and, critically, on crash NO
# `--out` document is written at all, so a STALE prior `--out` file (from an
# earlier, genuinely-SAFE run) survives UNCHANGED, byte-identical, silently
# fed to any caller that reads the `--out` FILE rather than checking the
# exit code (both confirmed live before fixing: a pre-seeded stale
# `safe_to_resume_without_reverification: true` file's md5 was IDENTICAL
# before and after the crashing invocation). FIVE sub-cases, ALL reproduced
# live per the reviewer's exact repro against the pinned pre-R4-I1-fix copy
# before fixing (confirmed rc=1 via the Python interpreter's own
# unhandled-exception exit, indistinguishable from a genuine UNSAFE verdict
# by exit code ALONE -- exactly the crash-into-FAIL hazard this fix closes),
# then fixed by TYPE-CHECKING each field before use and routing every
# mismatch to a NAMED, distinct unsafe_reasons class -- no abort path was
# needed for any of the five (every mismatch has a genuinely meaningful
# named finding to record):
#   (a) `pending` entry's `step`/`precondition` field is a non-string JSON
#       value (e.g. an int) -- the ALREADY-EXISTING "malformed-pending-step"
#       class (R3-I1's own non-dict-entry class) is EXTENDED with a second,
#       distinct detail variant ("dict, but field X has the wrong type"),
#       never a new class.
#   (b) `ground_truth_effects.json` entry's own `id` field is an unhashable
#       JSON array/object -- the ALREADY-EXISTING "malformed-ground-truth-
#       entry" class (R3-I1's own non-dict-entry class) is EXTENDED with a
#       second, distinct detail variant, never a new class.
#   (c) `effects_performed` entry's own `id` field is an unhashable JSON
#       array/object (crashing while BUILDING the `recorded_ids` match-key
#       set, a DIFFERENT crash site from (b)'s membership-test site) -- this
#       field had NO malformed-entry class at all before; NEW distinct
#       "malformed-effects-performed-entry" class.
#   (d) `verified` entry's own `established_at` field is a non-string JSON
#       value (e.g. an int) -- check (1) had NO malformed-entry class at all
#       before (R3-I1 explicitly investigated and confirmed a non-dict
#       `verified` entry needs no fix there, since it is cmd_write's own
#       documented, intended bare-ref-id shape and genuinely carries no
#       established_at to discard); a DICT entry that DOES set
#       `established_at` to a malformed value is a GENUINELY DIFFERENT,
#       unsafe-to-skip situation -- the field is PRESENT, so it represents
#       an attempt to record real causal information that turned out
#       corrupted, not an absence of information. NEW distinct
#       "malformed-verified-entry" class.
#   (e) `external_deps` entry's own `locator` field (kind="git-tree") is a
#       non-string JSON value (e.g. an int) -- the ALREADY-EXISTING
#       "malformed-external-dependency" class (I4/R2-I2's own non-dict/
#       missing-kind/unrecognized-kind classes) is EXTENDED with a FOURTH,
#       distinct detail variant, never a new class.
# `fixtures/resume_revalidate/_pinned/handoff_pre_r4i1_fix.py` (this
# submodule's HEAD immediately BEFORE this fix landed, i.e. the
# R3-I1-fixed-but-still-R4-I1-broken content) is the FIFTH pinned pre-fix
# copy, extracted the same way. Because this bug class is CRASH-into-FAIL
# rather than fail-open-to-safe, its own guard-viability proof below is
# NECESSARILY DIFFERENT from I4/R2-I2/R3-I1's own MISMATCH-based check: the
# pinned pre-R4-I1-fix copy is expected to CRASH (non-zero exit, NO `--out`
# document written at all, a Python "Traceback"+"TypeError" in stderr) on
# every R4-I1 fixture below -- proving each fixture genuinely triggers the
# pre-fix uncaught crash, never merely a wrong verdict.
#
# R5-I1 + R5-I2 fix (T140 Round 5 review, source-file commit alongside this
# edit): R4-I1 fixed FIVE dict-field-wrong-type crash sites in
# cmd_resume_check ONE AT A TIME as review kept finding a new one -- the
# EXACT heuristic-tower anti-pattern section 11.4.250 names ("when N
# heuristic layers stack to compensate, the primitive is broken"). R5-I1's
# review found TEN MORE distinct crash sites (all reproduced live against
# the pinned pre-R5-I1-fix copy per the reviewer's exact repro inputs,
# BEFORE fixing -- section 11.4.199) plus ONE silent FAIL-OPEN (a bare-
# string `effects_performed` iterated character-by-character by Python,
# each character silently dropped by the existing `isinstance(e, dict)`
# guard, producing a wrongly-SAFE verdict with NO trace anywhere that
# anything was malformed):
#   (1)  `written_at` a non-string JSON value (int), combined with a
#        `verified` entry that DOES set `established_at` -- crashed
#        `'>' not supported between instances of 'str' and 'int'`.
#   (2)  `verified` not a JSON list (a bare int) -- crashed
#        `'int' object is not iterable`.
#   (3)  `external_deps` not a JSON list -- same crash class as (2).
#   (4)  `pending` not a JSON list -- same crash class as (2).
#   (5)  `effects_performed` not a JSON list, `ground_truth_effects.json`
#        PRESENT -- same crash class as (2) (a DIFFERENT crash site from
#        (6), inside the ground-truth-present branch).
#   (6)  `effects_performed` not a JSON list, `ground_truth_effects.json`
#        ABSENT -- crashed `object of type 'int' has no len()` (a
#        DIFFERENT crash site from (5), inside the missing-sibling
#        branch).
#   (7)  `phase` a JSON list (not a string) -- crashed
#        `unhashable type: 'list'` testing `phase in TERMINAL_PHASES`
#        (TERMINAL_PHASES is a Python `set`).
#   (8)  an `external_deps` entry's own `affects_verified` field not a
#        JSON list (a bare int) -- same crash class as (2), reached via
#        the unrecognized-`kind` branch's own `reverify.add()` loop.
#   (9)  an `external_deps` entry's own `affects_verified` list containing
#        a JSON object element -- crashed `unhashable type: 'dict'` at
#        `reverify.add()` (a `set` cannot contain an unhashable value).
#   (10) an `external_deps` entry's own `affects_verified` list containing
#        MIXED hashable-but-mutually-incomparable scalar types (int AND
#        str) -- crashed `'<' not supported between instances of 'str'
#        and 'int'` at `sorted(reverify)`, the FINAL body-construction
#        step, genuinely OUTSIDE the defense-in-depth try/except this fix
#        also adds (see below) -- this is a DIFFERENT bug shape from (1)-
#        (9): every individual `affects_verified` entry is independently
#        hashable (so the up-front shape check's own per-item
#        `_hashable_scalar` test correctly finds nothing wrong), but two
#        entries of DIFFERENT types accumulated into the SAME `reverify`
#        set are not mutually `<`-comparable. Fixed at the OPERATION
#        itself (never by trying to enumerate every possible cross-entry
#        type-mismatch up front): `sorted(reverify, key=_typed_id_key)`
#        sorts by a `(type name, value)` tuple, so Python only ever
#        compares same-typed values against each other.
#   FAIL-OPEN: `effects_performed` a bare JSON STRING (e.g. `"abc"`),
#        `ground_truth_effects.json` present -- pre-fix, this wrongly
#        reported `safe_to_resume_without_reverification: true` with an
#        EMPTY `unsafe_reasons` (confirmed live against the pinned
#        pre-R5-I1-fix copy: rc=0, `effects_not_to_repeat: []`) -- string
#        iteration is a Python-specific hazard raw type-checking-by-
#        `isinstance` alone never surfaces, since a string IS iterable
#        (just not usefully, for this tool's purposes).
# Fixed with TWO cooperating layers, both in cmd_resume_check
# (`_validate_resume_check_top_level_shape` + `_hashable_scalar` +
# `_typed_id_key`, defined immediately above it):
#   (A) an up-front, SINGLE shape-validation pass run BEFORE any of checks
#       (1)-(5), closing (1)-(9) and the FAIL-OPEN case by construction --
#       the moment ANY top-level field (`written_at`/`phase` as a string;
#       `verified`/`external_deps`/`pending`/`effects_performed` as a
#       list; `affects_verified` -- top-level AND nested in every
#       `external_deps` entry -- as a list of hashable scalars) has the
#       wrong shape, a single new "malformed-handoff-field" reason is
#       emitted and checks (1)-(5) never run.
#   (B) a DEFENSE-IN-DEPTH `try`/`except (TypeError, ValueError)` wrapping
#       checks (1)-(5) and their own `effects_not_to_repeat` computation
#       (never claimed to make (A) exhaustive, section 11.4.6): any
#       genuinely unanticipated malformed-shape case still fails CLOSED
#       with a new "resume-check-internal-error" reason (naming the real
#       exception) rather than crashing uncaught.
#   Case (10) is closed by neither (A) nor (B) -- its crash site
#   (`sorted(reverify)`) sits in the function's FINAL body-construction
#   step, structurally AFTER the try/except (B) closes, on the SAFE path
#   where no unsafe_reasons finding exists yet to explain why the sort
#   would need guarding -- fixed instead at the sort OPERATION itself
#   (the `key=_typed_id_key` change described above).
# R5-I2 (a BEHAVIOUR fix, not a new crash or class, fixed in the SAME
# commit): the id-based match between `effects_performed` and
# `ground_truth_effects.json` entries (check (4)) used to key `recorded_ids`
# by the BARE `id` value. Python's `True == 1` (and hashes identically to
# it -- `1.0` behaves the same way), so `id=1` (int, in `effects_performed`)
# wrongly matched `id=True` (bool, in `ground_truth_effects.json`) as "the
# same effect" -- a GENUINELY DIFFERENT effect, confirmed live against the
# pinned pre-R5-I1-fix copy: `safe_to_resume_without_reverification: true`
# with an empty `unsafe_reasons`, silently missing the real
# "unrecorded-external-effect" finding. Fixed by keying BOTH sides of every
# id comparison in check (4) with `_typed_id_key` (`(type(id).__name__,
# id)`) instead of the bare id -- `('int', 1)` and `('bool', True)` are now
# genuinely distinct.
# `fixtures/resume_revalidate/_pinned/handoff_pre_r5i1_fix.py` (this
# submodule's HEAD -- commit 862be3782af74b7a5f2834baabbb1154d28d0803 --
# immediately BEFORE this fix landed) is the SIXTH pinned pre-fix copy,
# extracted the same way, and covers BOTH R5-I1 and R5-I2's own guard-
# viability proofs (a single commit landed both fixes together). Ten of
# the eleven new fixtures below (cases (1)-(10)) use the SAME
# CRASH-detection guard-viability style R4-I1 established (pinned copy
# MUST crash uncaught, NO `--out` written, a genuine Python
# "Traceback"+"TypeError" in stderr); the FAIL-OPEN case uses the
# MISMATCH-based style I4/R2-I2/R3-I1 established (pinned copy's verdict
# must NOT match the fixed verdict) since it does not crash pre-fix, it
# silently reports the wrong (safe) verdict.
#
# This file is a SELF-CONTAINED regression guard -- it does NOT import,
# source, or otherwise couple to test_resume_revalidate_red.sh's own
# derive_resume_check() oracle (Producer != Verifier, section 11.4.240): its
# own comparison logic below is written fresh, directly against each
# fixture's own checked-in expected_verdict.json document.
#
# Twenty-five fixtures total under fixtures/resume_revalidate/ (NONE added
# to the pre-existing, closed T126 RED test's own fixed $SCENARIOS list --
# that file is a completed historical deliverable and is left untouched;
# every fixture below is exercised ONLY by this file):
#   rr_unverifiable_external_dependency_kind/   -- I4 case (a)
#   rr_unverifiable_ground_truth/                -- I4 case (b)
#   rr_missing_ground_truth_empty_effects/       -- R2-I2 case (C)
#   rr_malformed_ground_truth_file/              -- R2-I2 case (D)
#   rr_malformed_external_dep/                   -- R2-I2 case (F), two
#                                                    malformed entries in one
#                                                    fixture (non-dict AND
#                                                    dict-missing-kind)
#   rr_malformed_ground_truth_entry/             -- R3-I1 case (a)
#   rr_malformed_pending_step/                    -- R3-I1 case (b)
#   rr_id_collision_none/                        -- R3-I1 case (c)
#   rr_malformed_pending_step_wrong_type/        -- R4-I1 case (a)
#   rr_malformed_ground_truth_entry_wrong_type/  -- R4-I1 case (b)
#   rr_malformed_effects_performed_entry/        -- R4-I1 case (c)
#   rr_malformed_verified_entry/                 -- R4-I1 case (d)
#   rr_malformed_external_dep_wrong_type/        -- R4-I1 case (e)
#   rr_shape_written_at_not_string/              -- R5-I1 case (1)
#   rr_shape_verified_not_list/                  -- R5-I1 case (2)
#   rr_shape_external_deps_not_list/             -- R5-I1 case (3)
#   rr_shape_pending_not_list/                   -- R5-I1 case (4)
#   rr_shape_effects_performed_not_list_gt_present/ -- R5-I1 case (5)
#   rr_shape_effects_performed_not_list_gt_absent/  -- R5-I1 case (6)
#   rr_shape_phase_not_string/                   -- R5-I1 case (7)
#   rr_shape_affects_verified_not_list/          -- R5-I1 case (8)
#   rr_shape_affects_verified_contains_dict/     -- R5-I1 case (9)
#   rr_shape_affects_verified_mixed_types/       -- R5-I1 case (10)
#   rr_shape_effects_performed_string_fail_open/ -- R5-I1 FAIL-OPEN case
#   rr_id_type_collision_bool_int/               -- R5-I2 (behaviour fix)
#
# Guard-viability proof (section 11.4.115(F), the canonical §1.1 mutation
# for a landed fix being the fix-commit's own revert): this file re-runs
# EVERY fixture above against its own matching PINNED pre-fix copy (never a
# moving ref) and asserts the pinned copy's output does NOT match that
# fixture's own expected_verdict.json -- proving each fixture genuinely
# catches its own regression if the corresponding fix is ever reverted. This
# is a STRICTER check than "wrongly reports safe=true" (which R1's own
# version used): the rr_malformed_external_dep fixture's PRE-R2-I2-fix
# behaviour is NOT "wrongly safe" (the I4 fix already makes the
# dict-missing-kind entry unsafe via a DIFFERENT class,
# "unverifiable-external-dependency", while silently skipping the non-dict
# entry entirely) -- a naive safe==true check would have MISSED that this
# fixture still genuinely catches the R2-I2 regression via its full-verdict
# mismatch (wrong class name + one missing reason), so this file compares
# the COMPLETE verdict shape, not merely the boolean safe flag.
#
# R4-I1's own guard-viability proof is STRUCTURALLY DIFFERENT from the
# MISMATCH-based check above (see the R4-I1 header section for why): the
# pinned pre-R4-I1-fix copy does not produce a WRONG verdict on an R4-I1
# fixture -- it CRASHES uncaught before it ever reaches the point where it
# would write one. Guard-viability there is therefore proven by asserting
# the pinned copy's invocation writes NO `--out` document at all AND its
# stderr contains a genuine Python "Traceback"/"TypeError" (never merely a
# non-zero exit code alone, since an uncaught crash and a genuine UNSAFE
# verdict share the SAME rc=1 -- exactly the ambiguity R4-I1 itself reports).
#
# R5-I1's TEN new fixtures (cases (1)-(10)) reuse this SAME CRASH-detection
# style verbatim (they are the same bug class as R4-I1 -- a wrong-shape
# field crashing uncaught -- just ten MORE distinct crash sites the R4-I1
# fix did not reach); R5-I1's ELEVENTH new fixture (the FAIL-OPEN case)
# instead reuses the I4/R2-I2/R3-I1 MISMATCH-based style, since it does not
# crash pre-fix -- it silently produces the WRONG (safe) verdict, exactly
# like those three findings' own bug shape.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/handoff.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
# scenario -> which pinned pre-fix copy proves its guard-viability
I4_FIXTURES="rr_unverifiable_external_dependency_kind rr_unverifiable_ground_truth"
R2I2_FIXTURES="rr_missing_ground_truth_empty_effects rr_malformed_ground_truth_file rr_malformed_external_dep"
R3I1_FIXTURES="rr_malformed_ground_truth_entry rr_malformed_pending_step rr_id_collision_none"
R4I1_FIXTURES="rr_malformed_pending_step_wrong_type rr_malformed_ground_truth_entry_wrong_type rr_malformed_effects_performed_entry rr_malformed_verified_entry rr_malformed_external_dep_wrong_type"
R5I1_CRASH_FIXTURES="rr_shape_written_at_not_string rr_shape_verified_not_list rr_shape_external_deps_not_list rr_shape_pending_not_list rr_shape_effects_performed_not_list_gt_present rr_shape_effects_performed_not_list_gt_absent rr_shape_phase_not_string rr_shape_affects_verified_not_list rr_shape_affects_verified_contains_dict rr_shape_affects_verified_mixed_types"
R5I1_MISMATCH_FIXTURES="rr_shape_effects_performed_string_fail_open"
R5I2_FIXTURES="rr_id_type_collision_bool_int"
ALL_FIXTURES="$I4_FIXTURES $R2I2_FIXTURES $R3I1_FIXTURES $R4I1_FIXTURES $R5I1_CRASH_FIXTURES $R5I1_MISMATCH_FIXTURES $R5I2_FIXTURES"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== I4+R2-I2+R3-I1+R4-I1+R5-I1 regression guard: control needle -- fixtures + the fixed tool + pinned copies all exist ==="
if [ ! -f "$IMPL" ]; then
  echo "NOT ok control needle FAILED: $IMPL not found"
  failx
else
  echo "ok control needle: $IMPL resolves"
fi
for scen in $ALL_FIXTURES; do
  if [ ! -f "$FIXDIR/$scen/handoff.json" ] || [ ! -f "$FIXDIR/$scen/expected_verdict.json" ]; then
    echo "NOT ok control needle FAILED: $scen missing handoff.json or expected_verdict.json"
    failx
  fi
done
PINNED_COPIES="handoff_pre_i4_fix.py handoff_pre_r2i2_fix.py handoff_pre_r3i1_fix.py handoff_pre_r4i1_fix.py handoff_pre_r5i1_fix.py"
for pinned in $PINNED_COPIES; do
  if [ ! -f "$PINDIR/$pinned" ]; then
    echo "NOT ok control needle FAILED: pinned pre-fix copy $PINDIR/$pinned not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: all $(echo $ALL_FIXTURES | wc -w) fixtures carry handoff.json + expected_verdict.json, all $(echo $PINNED_COPIES | wc -w) pinned pre-fix copies present"
fi

# --- own, from-scratch comparison (never imported from test_resume_revalidate_red.sh) ---
compare_outcome() {
  local derived_path="$1" expected_path="$2"
  python3 -c "
import json
d = json.load(open('$derived_path'))
e = json.load(open('$expected_path'))
def norm_reasons(r):
    return sorted(((x['class'], x['detail']) for x in r))
# T140 Round 5 review finding R5-I1 case (10)'s own regression, found live
# authoring the rr_shape_affects_verified_mixed_types fixture: THIS
# comparison helper's own bare sorted() crashed the identical way the
# pre-fix tool did ('<' not supported between instances of 'str' and
# 'int') the moment a fixture's facts_needing_reverification genuinely
# contains mixed hashable-but-mutually-incomparable scalar types --
# section 11.4.201(6): a test oracle indexing into the SAME kind of
# unconstrained field its own subject-under-test does inherits that
# subject's own fragility unless independently hardened. Fixed the SAME
# way as orchestration/handoff.py's own sorted(reverify, key=_typed_id_key)
# fix: sort by a (type name, value) key so Python only ever compares
# same-typed values, never raw cross-type values against each other.
def typed_key(v):
    return (type(v).__name__, v)
ok = (d.get('handoff_id') == e.get('handoff_id')
      and d['safe_to_resume_without_reverification'] == e['safe_to_resume_without_reverification']
      and norm_reasons(d['unsafe_reasons']) == norm_reasons(e['unsafe_reasons'])
      and sorted(d['facts_needing_reverification'], key=typed_key) == sorted(e['facts_needing_reverification'], key=typed_key)
      and sorted(d['effects_not_to_repeat'], key=typed_key) == sorted(e['effects_not_to_repeat'], key=typed_key))
print('MATCH' if ok else 'MISMATCH derived=%s expected=%s' % (json.dumps(d, sort_keys=True), json.dumps(e, sort_keys=True)))
"
}

echo
echo "=== Real-tool invocation (FIXED handoff.py): every fixture reports UNSAFE, matching its own expected_verdict.json ==="
for scen in $ALL_FIXTURES; do
  SDIR="$FIXDIR/$scen"
  ACTUAL="$TMP/${scen}.actual.json"
  ERR="$TMP/${scen}.err"
  python3 "$IMPL" resume-check --handoff "$SDIR/handoff.json" --out "$ACTUAL" >"$ERR" 2>&1
  RC=$?
  if [ ! -f "$ACTUAL" ]; then
    echo "NOT ok $scen: real resume-check invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi
  RESULT=$(compare_outcome "$ACTUAL" "$SDIR/expected_verdict.json")
  if [ "$RC" = "1" ] && [ "$RESULT" = "MATCH" ]; then
    echo "ok $scen: real (fixed) handoff.py resume-check exited 1 (UNSAFE) as"
    echo "   expected and its outcome matches expected_verdict.json"
  else
    echo "NOT ok $scen: real (fixed) resume-check invocation rc=$RC (wanted 1), $RESULT"
    failx
  fi
done

# --- Guard-viability (section 11.4.115(F)): each fixture's matching PINNED
# pre-fix copy must NOT reproduce the fixed tool's expected verdict ---
run_against_pinned() {
  # $1 = pinned copy basename (under $PINDIR), $2 = scenario, $3 = out path.
  # Layout MUST stay exactly ONE level deep ($TMP/orchestration_scratch/
  # handoff.py, sibling of $TMP/lib/fc_common.py) -- the pinned script
  # itself computes its own _LIB_DIR as dirname(__file__)/../lib, so an
  # extra nested directory level (e.g. naming a dir after $pinned) breaks
  # that relative resolution.
  local pinned="$1" scen="$2" out="$3"
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINDIR/$pinned" "$TMP/orchestration_scratch/handoff.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  cp "$EXLIB" "$TMP/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 "$TMP/orchestration_scratch/handoff.py" resume-check \
    --handoff "$FIXDIR/$scen/handoff.json" --out "$out" >"$TMP/${scen}.${pinned}.mut.err" 2>&1
}

echo
echo "=== Guard-viability: each fixture's PINNED pre-fix copy does NOT reproduce the fixed verdict (checked-in, never HEAD-relative) ==="
for scen in $I4_FIXTURES; do
  MUT_OUT="$TMP/${scen}.i4pin.mut.json"
  run_against_pinned "handoff_pre_i4_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-I4-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_i4_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-I4-fix handoff.py's verdict"
    echo "   does NOT match this fixture's expected_verdict.json ($MUT_RESULT) --"
    echo "   proving this fixture genuinely catches the I4 fail-open regression"
    echo "   if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-I4-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the I4 fix and needs revising"
    failx
  fi
done
for scen in $R2I2_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r2i2pin.mut.json"
  run_against_pinned "handoff_pre_r2i2_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-R2-I2-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_r2i2_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-R2-I2-fix handoff.py's"
    echo "   verdict does NOT match this fixture's expected_verdict.json"
    echo "   ($MUT_RESULT) -- proving this fixture genuinely catches the R2-I2"
    echo "   fail-open regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R2-I2-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the R2-I2 fix and needs revising"
    failx
  fi
done
for scen in $R3I1_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r3i1pin.mut.json"
  run_against_pinned "handoff_pre_r3i1_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-R3-I1-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_r3i1_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-R3-I1-fix handoff.py's"
    echo "   verdict does NOT match this fixture's expected_verdict.json"
    echo "   ($MUT_RESULT) -- proving this fixture genuinely catches the R3-I1"
    echo "   fail-open regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R3-I1-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the R3-I1 fix and needs revising"
    failx
  fi
done

# --- R4-I1 guard-viability (section 11.4.115(F)): CRASH-detection, not
# verdict-mismatch -- see this file's own R4-I1 header section + the
# "R4-I1's own guard-viability proof is STRUCTURALLY DIFFERENT" paragraph
# above for why. Each fixture's pinned pre-R4-I1-fix copy MUST crash
# uncaught (non-zero exit, NO --out document written, a genuine Python
# "Traceback"/"TypeError" in stderr) -- proving the fixture genuinely
# triggers the pre-fix crash-into-FAIL if the fix is ever reverted. ---
for scen in $R4I1_FIXTURES; do
  # $MUT_OUT is a path under mktemp -d's $TMP -- never itself pre-created
  # (unlike e.g. `mktemp` on a bare file, which would make a subsequent
  # `[ -f "$MUT_OUT" ]` check spuriously pass even when the crash wrote
  # nothing into it) -- so its post-invocation existence genuinely reflects
  # whether run_against_pinned()'s invocation reached write_report_atomic().
  MUT_OUT="$TMP/${scen}.r4i1pin.mut.json"
  rm -f "$MUT_OUT"
  run_against_pinned "handoff_pre_r4i1_fix.py" "$scen" "$MUT_OUT"
  MUT_ERR="$TMP/${scen}.handoff_pre_r4i1_fix.py.mut.err"
  if [ -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R4-I1-fix copy"
    echo "     WROTE an --out document instead of crashing -- this fixture would NOT"
    echo "     catch a revert of the R4-I1 fix and needs revising"
    failx
    continue
  fi
  if grep -q "^Traceback" "$MUT_ERR" 2>/dev/null && grep -q "^TypeError" "$MUT_ERR" 2>/dev/null; then
    echo "ok guard-viability ($scen): the PINNED pre-R4-I1-fix handoff.py CRASHED"
    echo "   uncaught (Traceback + TypeError in stderr, NO --out document written) --"
    echo "   proving this fixture genuinely catches the R4-I1 crash-into-FAIL"
    echo "   regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) BLIND: the pinned pre-R4-I1-fix copy wrote"
    echo "     no --out document but its stderr does not show the expected"
    echo "     Traceback+TypeError crash signature -- $(cat "$MUT_ERR" 2>/dev/null)"
    failx
  fi
done

# --- R5-I1 guard-viability (section 11.4.115(F)): CRASH-detection for the
# TEN crash-class fixtures -- the SAME style as R4-I1 immediately above
# (this file's own R5-I1 header section explains why cases (1)-(10) are
# the SAME bug shape as R4-I1, just ten MORE distinct crash sites). ---
for scen in $R5I1_CRASH_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r5i1pin.mut.json"
  rm -f "$MUT_OUT"
  run_against_pinned "handoff_pre_r5i1_fix.py" "$scen" "$MUT_OUT"
  MUT_ERR="$TMP/${scen}.handoff_pre_r5i1_fix.py.mut.err"
  if [ -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R5-I1-fix copy"
    echo "     WROTE an --out document instead of crashing -- this fixture would NOT"
    echo "     catch a revert of the R5-I1 fix and needs revising"
    failx
    continue
  fi
  if grep -q "^Traceback" "$MUT_ERR" 2>/dev/null && grep -q "^TypeError" "$MUT_ERR" 2>/dev/null; then
    echo "ok guard-viability ($scen): the PINNED pre-R5-I1-fix handoff.py CRASHED"
    echo "   uncaught (Traceback + TypeError in stderr, NO --out document written) --"
    echo "   proving this fixture genuinely catches the R5-I1 crash-into-FAIL"
    echo "   regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) BLIND: the pinned pre-R5-I1-fix copy wrote"
    echo "     no --out document but its stderr does not show the expected"
    echo "     Traceback+TypeError crash signature -- $(cat "$MUT_ERR" 2>/dev/null)"
    failx
  fi
done

# --- R5-I1 guard-viability, MISMATCH style, for the ONE FAIL-OPEN fixture
# (the SAME style as I4/R2-I2/R3-I1 above -- this fixture does not crash
# pre-fix, it silently produces the wrong verdict). ---
for scen in $R5I1_MISMATCH_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r5i1pin.mut.json"
  run_against_pinned "handoff_pre_r5i1_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-R5-I1-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_r5i1_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-R5-I1-fix handoff.py's verdict"
    echo "   does NOT match this fixture's expected_verdict.json ($MUT_RESULT) --"
    echo "   proving this fixture genuinely catches the R5-I1 fail-open regression"
    echo "   if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R5-I1-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the R5-I1 fix and needs revising"
    failx
  fi
done

# --- R5-I2 guard-viability, MISMATCH style (a BEHAVIOUR fix landed in the
# SAME commit as R5-I1, so the SAME pinned pre-fix copy proves it too):
# effects_performed id=1 (int) and ground_truth_effects.json id=True
# (bool) used to wrongly collide as "the same effect" -- proving this
# fixture genuinely catches a revert of the _typed_id_key fix. ---
for scen in $R5I2_FIXTURES; do
  MUT_OUT="$TMP/${scen}.r5i1pin.mut.json"
  run_against_pinned "handoff_pre_r5i1_fix.py" "$scen" "$MUT_OUT"
  if [ ! -f "$MUT_OUT" ]; then
    echo "NOT ok guard-viability $scen BLIND: pinned pre-R5-I1-fix copy wrote no --out document -- $(cat "$TMP/${scen}.handoff_pre_r5i1_fix.py.mut.err" 2>/dev/null)"
    failx
    continue
  fi
  MUT_RESULT=$(compare_outcome "$MUT_OUT" "$FIXDIR/$scen/expected_verdict.json")
  if [ "$MUT_RESULT" != "MATCH" ]; then
    echo "ok guard-viability ($scen): the PINNED pre-R5-I1-fix handoff.py's verdict"
    echo "   does NOT match this fixture's expected_verdict.json ($MUT_RESULT) --"
    echo "   proving this fixture genuinely catches the R5-I2 id-type-collision"
    echo "   regression if the fix is ever reverted"
  else
    echo "NOT ok guard-viability ($scen) FAILED: the pinned pre-R5-I1-fix copy"
    echo "     ALREADY matches the fixed verdict -- this fixture would NOT catch"
    echo "     a revert of the R5-I2 fix and needs revising"
    failx
  fi
done

echo
if [ "$fail" = 0 ]; then
  echo "=== I4+R2-I2+R3-I1+R4-I1+R5-I1+R5-I2 REGRESSION GUARD: ALL CHECKS PASS -- the"
  echo "    fixed handoff.py correctly fails CLOSED on every fixture, and every"
  echo "    fixture's own pinned pre-fix copy is independently confirmed to NOT"
  echo "    reproduce that verdict (I4/R2-I2/R3-I1/R5-I1-fail-open/R5-I2) or to crash"
  echo "    uncaught exactly as pre-fix (R4-I1/R5-I1-crash-cases) -- every guard here"
  echo "    is load-bearing. ==="
else
  echo "=== I4+R2-I2+R3-I1+R4-I1+R5-I1+R5-I2 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit $fail
