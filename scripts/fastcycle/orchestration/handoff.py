#!/usr/bin/env python3
"""handoff.py - Handoff Record write/validate (spec-004 "fast-dev-cycles",
User Story 5, T133, plan task T-B04, contract
contracts/agent-registry-and-handoff.md clauses HO-001 (write) and HO-002
(preserve/re-hash), data-model.md §9.2 "Handoff Record", research.md DEC-34).

TDD-FIX target: this file turns T125's RED baseline
(`constitution/scripts/fastcycle/tests/test_handoff_red.sh`, fixtures under
`constitution/scripts/fastcycle/tests/fixtures/handoff/`) GREEN with `write`/
`validate`/`verify` (T133), and T126's RED baseline
(`constitution/scripts/fastcycle/tests/test_resume_revalidate_red.sh`,
fixtures under
`constitution/scripts/fastcycle/tests/fixtures/resume_revalidate/`) GREEN
with `resume`/`resume-check` (T134, THIS task, added in the same file after
T133 per this file's own next task line).

`resume-check` (HO-003) implements HO-003's own one stated rule -- "re-hashes
every `external_dep`; mismatches list the `verified` facts that must be
re-verified ... and the `effects_performed` that must not be repeated" --
PLUS T126's own, separate, five-class extension of the "Safe to Resume?"
framework (research.md DEC-34, arXiv 2608.29381, which "gives no
prescriptive fix, so the revalidation design [is] original", per T126's own
header): inconsistent internal state, stale external dependency,
nondeterministic replay, unrecorded external effect, inconsistent
transition. T126's RED test's own independent `derive_resume_check()` oracle
(never imported by, shared with, or otherwise coupled to this file --
Producer != Verifier, section 11.4.240) is the interim contract this file's
`cmd_resume_check` satisfies; every wire-format decision T126's own header
marks "UNCONFIRMED by the contract itself -- DEFINED here, binding-if-adopted
on T134" is adopted here VERBATIM (never re-decided), verified byte-exact
against every checked-in fixture BEFORE this file's own author wrote a
single line of `cmd_resume_check` (see "resume-check wire format" below):

Invocation (contract "Components" section names one generic line for all
three subcommands, `handoff.py write|verify|resume-check --handoff <path>
--out <result.json>`; the concrete flag set per subcommand below is
UNCONFIRMED by the contract itself -- DEFINED here, binding-if-adopted, per
the established house convention in fixtures/evidence_ref/README.md and
fixtures/handoff/README.md's own "UNCONFIRMED... DEFINED here" sections):

    handoff.py write --item-id <ItemId-or-NONE> --agent-key <key> \\
        --alias <alias> --model <model> --effort <effort> --phase <phase> \\
        [--verified <EvidenceReference-id> ...] \\
        [--pending-json <JSON list of {step, precondition}>] \\
        [--partial-artefacts <path> ...] \\
        [--external-deps-json <JSON list of {kind, locator, content_address-or-fingerprint}>] \\
        [--effects-performed-json <JSON list of {kind, id}>] \\
        --handoff <path> --out <result.json>

    handoff.py validate --handoff <path> --out <result.json>
    handoff.py verify    --handoff <path> --out <result.json>   # HO-002's own contract wording; identical to `validate` (see HONEST NOTE below)

    handoff.py resume-check --handoff <path> --out <result.json>   # contract's own Components-line wording (HO-003)
    handoff.py resume       --handoff <path> --out <result.json>   # T134's own task-line wording; identical to `resume-check` (see HONEST NOTE below)

`--handoff <path>` means the handoff RECORD ITSELF in every subcommand,
consistent across `write` (where it is the OUTPUT path this tool writes the
record to) and `validate`/`verify` (where it is the EXISTING record this
tool reads and checks) -- the one meaning the contract's single generic
Invocation line implies by using one flag name for all three subcommands.
`--out <result.json>` is always a SEPARATE report-of-this-run document
(schema `handoff-write/v1` or `handoff-validate/v1`), distinct from the
handoff record itself, matching the established `evref.json` vs
`evref-consume.json` split in the sibling `context/evidence_ref.py`.

HONEST NOTE (section 11.4.6, verbatim from T125's own RED test header):
T133's own task line calls the subcommand `validate`; the contract's
Components section, and HO-002's own clause text ("`verify` re-hashes them
and exits 1 on any difference"), name the same subcommand `verify`. Rather
than silently picking one wording and guessing the other is a synonym never
worth supporting, both are wired here as two argparse subparsers dispatching
to the IDENTICAL handler function (`cmd_validate`) -- so a caller using
either the task-line wording or the contract-clause wording gets the exact
same, real behaviour; neither name silently falls back to the other via a
lookup table (a genuinely unknown subcommand is still argparse's ordinary
usage error, exit 2).

SAME NAMING-AMBIGUITY PRECEDENT applied to T134 (T126's own RED test header,
verbatim, flags this identically): T134's own task line calls the subcommand
`resume`; the contract's Components section and HO-003's own clause text
("Before the resumed agent acts, `resume-check` re-hashes every
`external_dep`...") name it `resume-check`. Both are wired here as two
argparse subparsers dispatching to the IDENTICAL handler function
(`cmd_resume_check`) -- exactly the same two-subparsers-one-handler pattern
T133 already established for `validate`/`verify`, never a lookup-table
synonym, never a silent fallback.

Wire format (UNCONFIRMED by data-model.md §9.2/the contract -- DEFINED in
`fixtures/handoff/README.md`, binding-if-adopted, read it FIRST): the
two-pass, non-circular `handoff_id`/`body_hash` construction this file
implements is reproduced here EXACTLY as that file documents it and as
T125's own from-scratch `derive_validate()` oracle independently re-derives
it (never imported from, nor shared with, that test file -- Producer !=
Verifier, section 11.4.240 -- this file was authored independently against
the SAME contract/README text the RED test's author used, and the two are
expected to agree because both correctly implement it, exactly the relation
the sibling `context/evidence_ref.py` module docstring describes for
T108/T117):
  1. Pass 1 -- `handoff_id` (data-model's "`ContentAddress` of the record
     body"): `"sha256:" + sha256(canon(doc excluding handoff_id, body_hash,
     run_meta))`, computed with `handoff_id`/`body_hash` still ABSENT from
     the doc (`schema` and every other field ARE hashed).
  2. Pass 2 -- `body_hash`: `handoff_id` is inserted into the doc, then the
     ALREADY-LANDED `lib/fc_common.py`'s own `body_hash_of()` (C-002; the
     SAME convention every other spec-004 tool in this tree already uses,
     never a second, divergent one -- section 11.4.227) is applied over the
     doc that now DOES include `handoff_id`, excluding only
     `body_hash`/`run_meta`.
  The handoff record (`--handoff`'s own document) carries NO `run_meta` key
  at all -- it is a content-addressed FACT about real work state (its own
  `written_at`/`time_source` already capture the instant), not a report of
  "this run of this tool", matching the established `ref.json` convention in
  `context/evidence_ref.py` and every checked-in fixture `handoff.json` in
  this tree (none carries `run_meta`). The `--out` REPORT documents (for
  both `write` and `validate`/`verify`) DO carry `run_meta` (host), matching
  the established `write_out`/`evref-consume.json` convention every other
  fastcycle report tool already follows.
- **`verified`** is a bare list of `EvidenceReference` id strings
  (data-model.md §9.2: "list of `EvidenceReference` ids"; T-E05/`evidence_ref.py`
  ref ids are a DIFFERENT format -- `verified` here carries whatever a caller
  supplies, unresolved against any store by this tool; resolving them is a
  later concern, not this file's).
- **`pending`** is a list of `{step, precondition}` objects, `external_deps`
  a list of `{kind, locator, content_address-or-fingerprint}` objects, and
  `effects_performed` a list of `{kind, id}` objects -- each supplied
  pre-computed as a `--*-json` blob (this tool does not itself resolve a
  git-tree hash, a tracker-row version, or a device fingerprint; RE-hashing
  `external_deps` at resume time is HO-003/T126's own job, never this file's).
- **`partial_artefacts`** paths are supplied BARE (`--partial-artefacts
  <path> ...`, matching the sibling `evidence_ref.py create --inputs`
  convention) and this tool COMPUTES their real, live content addresses
  itself at write time (never trusts a caller-supplied hash for these --
  HO-001's "the record is itself content-addressed" and HO-002's later
  re-hash-and-compare both presuppose the recorded hash is a genuine,
  independently-checkable snapshot of real bytes, not an assertion). Every
  declared path -- for BOTH `write` and `validate`/`verify` -- is resolved
  relative to `dirname(--handoff)` (the SAME base-dir convention on both
  sides, deliberately: a record written under one CWD must still validate
  correctly from a different CWD later, exactly as the checked-in fixtures'
  own `notes.md`/`plan.json` sit beside their `handoff.json`); a missing
  declared path at `write` time refuses (exit 1, "missing field" per the
  contract's own Handoff exit-code line) rather than recording an
  unverifiable hash.
- **Content addresses** are `"sha256:<64 hex>"`-prefixed (data-model.md §0's
  own `ContentAddress` format); `body_hash` is the established
  `fc_common.py` convention's BARE 64-hex string (no prefix) -- two
  different, independently-real established formats, each used exactly
  where its own convention already defines it (identical split to
  `context/evidence_ref.py`'s own module docstring).
- **`time_source`** on `written_at` is always `"event_occurred"` (never a CLI
  flag): `fixtures/handoff/README.md` states this as a general rule, not a
  fixture-only convention -- "a phase-boundary write is, by construction,
  the moment the event it describes occurred".

resume-check wire format (UNCONFIRMED by data-model.md §9.2/the contract --
DEFINED in T126's own RED test header
(`test_resume_revalidate_red.sh`, "Wire format" section), binding-if-adopted,
read it FIRST; every value below was independently re-derived from the
checked-in fixtures under `fixtures/resume_revalidate/` and byte-verified
against them BEFORE this file's `cmd_resume_check` was written, matching
every `expected_verdict.json` exactly):
- **Result shape**: `{handoff_id, safe_to_resume_without_reverification,
  unsafe_reasons: [{class, detail}], facts_needing_reverification,
  effects_not_to_repeat}`, written as the `--out` report body (schema
  `handoff-resume-check/v1`, `run_meta` included -- the same report-doc
  convention as `write`/`validate`); `safe_to_resume_without_reverification`
  is `true` iff `unsafe_reasons` is empty.
- **Two T140 Round 5 review finding R5-I1/R5-I2 additions, layered AROUND
  the five failure-class checks below, never INSIDE their own numbering**
  (see `_validate_resume_check_top_level_shape`'s own docstring above
  `cmd_resume_check` for the full rationale -- section 11.4.250
  heuristic-tower/primitive-defect):
    - `malformed-handoff-field` -- an up-front, single check run BEFORE
      any of the five checks below, the moment ANY top-level field
      (`written_at`, `phase`, `verified`, `external_deps`, `pending`,
      `effects_performed`, or any `affects_verified` -- top-level or
      nested in an `external_deps` entry) has the wrong JSON shape;
      short-circuits straight to an unsafe verdict, never reaching checks
      1-5.
    - `resume-check-internal-error` -- a defense-in-depth catch-all
      wrapping checks 1-5 AND their own `effects_not_to_repeat`
      computation: a genuinely unanticipated malformed-shape case the
      `malformed-handoff-field` check above did not enumerate still fails
      CLOSED with this class (naming the real exception + its type)
      rather than crashing uncaught.
    - (R5-I2, a BEHAVIOUR fix, not a new class): check 4's `id`-based
      match between `effects_performed` and `ground_truth_effects.json`
      now keys both sides by `(type(id).__name__, id)` instead of the
      bare `id` -- `id=1` (int) and `id=True` (bool) are hashable-equal
      and previously collided as "the same effect"; they are now
      genuinely distinct.
- **Five failure classes** (research.md DEC-34's own citation, "Safe to
  Resume?" arXiv 2608.29381; the paper gives no prescriptive fix, so this
  file's checks are this project's own original design, adopted verbatim
  from T126's own RED-test header + its independently-DERIVED oracle, never
  imported from it -- see Producer != Verifier below):
    1. `inconsistent-internal-state` -- a `verified` entry's own
       `established_at` is causally AFTER the handoff's own `written_at`
       (impossible if the record genuinely reflects the agent's state at the
       instant it was written), OR the recorded `phase` is terminal
       (`"DONE"`) while `pending` is non-empty.
    2. `stale-external-dependency` -- for every `external_deps` entry whose
       `kind` is `"git-tree"` (the ONLY kind any checked-in fixture
       exercises; `git-ref`/`tracker-row`/`device`/`file` re-hashing is an
       honest, undecided gap this file does not attempt), re-hash
       `os.path.join(dirname(--handoff), "tree_current", <locator>)` via the
       data-model.md §0 `MerkleRoot` convention (sha256 over the sorted list
       of `(relative-path, ContentAddress)` pairs of every file under that
       directory) and compare against the recorded `content_address`; a
       mismatch also adds every id in that dep's `affects_verified` to
       `facts_needing_reverification`. (`tree_current/<locator>`, resolved
       relative to `dirname(--handoff)` -- the SAME base-dir convention
       `partial_artefacts` already uses -- is the fixture layout T126's own
       RED test ships; a real production convention for locating a live git
       tree, e.g. shelling out against an actual repo path, is future work
       this task does not attempt. Verified byte-exact against both the
       golden-bad and negative-control fixtures before writing this file's
       `_merkle_over_dir`: recomputing over
       `rr_stale_external_dependency/tree_current/dep_a` yields
       `sha256:4b91...c87602`, matching that fixture's own
       `expected_verdict.json` `live=` value character-for-character; over
       `rr_negctrl_all_unchanged/tree_current/dep_a` it yields
       `sha256:8c6c...dce66`, matching that fixture's own recorded
       `content_address` exactly, so the negative control genuinely reports
       zero mismatches rather than a false positive.)
       HONEST GAP, decided explicitly (T140 Round 11 review finding I7):
       OUTSIDE that fixture layout this check can verify NOTHING -- every
       `file`/`git-ref`/`tracker-row`/`device` dependency, and any git-tree
       dependency with no `tree_current/<locator>` beside the record, is
       reported `unverifiable-external-dependency`, and a missing
       `ground_truth_effects.json` is `unverifiable-ground-truth` -- so in
       real (non-fixture) use resume-check answers UNSAFE for essentially
       every record that declares a dependency. That is the fail-SAFE
       direction (it never wrongly says SAFE), but HO-003 ("re-hash every
       external_dep") is NOT satisfied in production; it is tracked as an
       open gap, not claimed done.
    3. `nondeterministic-replay` -- a `pending` entry's `step`+`precondition`
       text names a nondeterministic-source keyword (`llm-generate`,
       `llm-generated`, `random`, `nondeterministic`, `non-deterministic`;
       T126's own closed, interim keyword set, adopted verbatim).
    4. `unrecorded-external-effect` -- an OPTIONAL sibling
       `ground_truth_effects.json`, resolved relative to `dirname(--handoff)`
       (the SAME base-dir convention as `tree_current/`), stands in for an
       independently-observable ground-truth source (a real
       remote-tracking ref / reflog / marker file a production
       implementation would consult -- Producer != oracle, section
       11.4.245/11.4.240: this ground truth is never derived from the
       handoff record itself); every effect id in it absent from the
       handoff's own `effects_performed` is flagged.

       This check's own fail-closed surface has grown across T140 Rounds
       1-4 and is NO LONGER a single "honest skip on absence" (that framing
       was already stale by Round 2's own I2(C) fix, which made a missing
       sibling ALWAYS unsafe -- never conditioned on `effects_performed`
       happening to be empty, since an empty `effects_performed` is not
       evidence no effect occurred). It now emits FIVE distinct classes of
       its own (T140 Round 5 review finding R5-N1: an earlier revision of
       this docstring said "SIX", miscounting/misattributing
       `malformed-verified-entry` here -- that class belongs to check (1),
       not this check, as the parenthetical immediately below the bullet
       list already correctly explains; only the five bullets below are
       genuinely emitted BY THIS CHECK), depending on exactly what could
       not be confirmed:
         - `unverifiable-ground-truth` -- the sibling file is genuinely
           ABSENT (ALWAYS unsafe; the empty-vs-non-empty `effects_performed`
           cases stay honestly DISTINGUISHED in the detail text, both
           unsafe).
         - `unreadable-ground-truth` -- the sibling EXISTS but fails to
           parse as JSON, or parses to a non-list top-level value.
         - `malformed-ground-truth-entry` -- a `ground_truth_effects.json`
           list entry is not itself a JSON object (R3-I1), OR is an object
           whose own `id` field is an unhashable JSON array/object (R4-I1 --
           the SAME class extended with a second, distinct detail variant,
           never a second class).
         - `malformed-effects-performed-entry` -- an `effects_performed`
           entry's own `id` field is an unhashable JSON array/object, so it
           cannot be added to this check's internal match-key set (R4-I1,
           a NEW class -- this field carried no malformed-entry class at
           all before).
         - `unrecorded-external-effect` itself -- a genuinely-parsed,
           well-formed ground-truth entry's id is absent from
           `effects_performed`'s recorded ids.
       (A `verified` entry's own `established_at` field being the wrong
       type is a SIBLING fail-closed extension landed the SAME round, in
       check (1) below -- see its own comment there for why a NEW
       `malformed-verified-entry` class was warranted there, unlike a
       non-dict `verified` entry which remains an honest, deliberate skip;
       check (2)'s `external_deps` entries and check (3)'s `pending`
       entries similarly grew their OWN wrong-type-field detail variants
       under the ALREADY-EXISTING `malformed-external-dependency` and
       `malformed-pending-step` classes respectively -- see each check's
       own R4-I1 comment.) Section 11.4.3's honest-skip discipline still
       applies ELSEWHERE in this file (a non-dict `verified` entry in check
       (1) is silently skipped by design -- see that check's own comment),
       but NOT here: every gap THIS check can detect is fail-closed, never
       a silent pass.
    5. `inconsistent-transition` -- using T126's own interim canonical phase
       order `PLAN -> IMPLEMENT -> VERIFY -> DEPLOY -> DONE` (adopted
       verbatim, matching HO-001's phase-boundary write cadence) and reading
       an OPTIONAL `phase` tag on individual `verified` entries (NOT part of
       the canonical `EvidenceReference` schema in data-model.md §8 -- a
       genuinely necessary extension field this file accepts when present
       and silently skips for `verified` entries that lack it, e.g. the bare
       id strings `cmd_write` itself produces), the recorded `phase` jumping
       more than one step past the LATEST phase any `verified` entry
       actually confirmed is flagged, naming every skipped phase.
- **`effects_not_to_repeat`** is always exactly the handoff's own
  `effects_performed` ids (never the ground-truth source's) -- a resumer is
  told what NOT to repeat from what the record itself already claims
  happened, independent of whether the ground-truth cross-check above found
  it complete.
- Self-integrity (`handoff_id`/`body_hash` recomputation) is deliberately NOT
  re-checked here -- that is `validate`/`verify`'s (HO-002's) own job, and
  every checked-in `resume_revalidate` fixture's `handoff.json` in fact
  carries no `body_hash` field at all (by design, per T126's own fixtures),
  so re-enforcing it here would spuriously fail every fixture.

Exit codes (contract "Exit codes" line, verbatim: "Handoff: 0 ok, 1 hash
mismatch / missing field"): `write` 0 ok / 1 a declared `--partial-artefacts`
path does not exist ("missing field") / 2 usage (bad/unreadable args,
malformed `--*-json`). `validate`/`verify` 0 VALID / 1 INVALID (self-integrity
mismatch or a partial-artefact hash mismatch/missing file -- HO-002's "exits
1 on any difference") / 2 usage (`--handoff` missing/unreadable/not a JSON
object). `resume`/`resume-check` 0 safe (`safe_to_resume_without_
reverification=true`) / 1 unsafe (one or more `unsafe_reasons`) / 2 usage
(`--handoff` missing/unreadable/not a JSON object) -- matching T126's own RED
test's `want_rc` mapping (safe->0, unsafe->1) exactly. No subcommand here
produces a BLIND (4) verdict -- every input (`tree_current/<locator>`,
`ground_truth_effects.json`, `partial_artefacts`) is either locally present
or its honest absence is itself a defined outcome (a mismatch, or a skipped
check), never an unresolvable "could not look".

Reuse, not reinvention (section 11.4.227): `canon`/`body_hash_of` are
imported from the already-landed sibling `lib/fc_common.py`, the identical
import-by-path pattern every other fastcycle tool in this tree uses
(`context/evidence_ref.py`, `context/anchor_citations.py`, and others per
that file's own module docstring); never reimplemented here. `_merkle_over_dir`
reuses the ALREADY-IMPORTED `canon()` for its own canonicalization (the
data-model.md §0 `MerkleRoot` convention `context/evidence_ref.py`'s own
`merkle_root()` and T126's RED test's own `merkle_over_dir()` each
independently apply) but is its OWN small, independently-written function in
this file -- matching this file's OWN already-established convention for
`content_address()` (a small primitive independently defined in this file,
in `context/evidence_ref.py`, AND in T126's own RED-test oracle, rather than
cross-imported between `context/` and `orchestration/`), never imported from
`context/evidence_ref.py` nor from T126's own test oracle.

Producer != Verifier (section 11.4.240): this file is T133's implementation
of the SEPARATE, EARLIER T125 RED test's own independent
`derive_validate()` oracle (`test_handoff_red.sh`), and this task's (T134's)
implementation of the SEPARATE, EARLIER T126 RED test's own independent
`derive_resume_check()` oracle (`test_resume_revalidate_red.sh`); neither
oracle is imported by, shared with, nor coupled to this file, and this file
never imports from either test -- the two are authored independently against
the same contract/README/fixture text and are expected to agree because both
correctly implement it, never because one delegates to the other.

Stdlib only. Python 3.
"""
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers (identical
# import-by-path pattern to context/evidence_ref.py / escape_classify.py /
# cycle_report.py -- constitution/scripts/fastcycle has no __init__.py
# anywhere, matching this tree's existing flat-script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)
import fc_entry  # noqa: E402  (T140 Round 10 review: the ONE shared CLI-entry
# primitive -- emit_result/diag channel split, FcArgumentParser, run_cli_main,
# safe_str, scan_argv_for_out, invalidate_stale_out -- see fc_entry.py's own
# module docstring; replaces this file's own former per-tool copies of every
# one of those, section 11.4.227/11.4.251)

canon = fc_common.canon
diag = fc_entry.diag
emit_result = fc_entry.emit_result
safe_str = fc_entry.safe_str
scan_argv_for_out = fc_entry.scan_argv_for_out
invalidate_stale_out = fc_entry.invalidate_stale_out
FcArgumentParser = fc_entry.FcArgumentParser
run_cli_main = fc_entry.run_cli_main

SCHEMA_HANDOFF = "handoff/v1"
# T140 Round 11 review finding I2: the HO-001 record fields `validate`/`verify`
# require (present, with this JSON type) before any hash check runs -- exactly
# the fields `cmd_write` emits; handoff_id/body_hash are checked by the
# self-integrity step itself.
HO001_REQUIRED_FIELDS = (
    ("item_id", str), ("alias", str), ("model", str), ("effort", str), ("phase", str),
    ("verified", list), ("pending", list), ("partial_artefacts", list),
    ("external_deps", list), ("effects_performed", list),
)
SCHEMA_WRITE = "handoff-write/v1"
SCHEMA_VALIDATE = "handoff-validate/v1"
SCHEMA_RESUME_CHECK = "handoff-resume-check/v1"
# T140 Round 7 review: the top-level dispatch-boundary minimal error doc's
# own schema (see main()'s own dispatch boundary + its
# _write_dispatch_internal_error_doc helper, below).
SCHEMA_INTERNAL_ERROR = "handoff-internal-error/v1"

EXIT_OK = 0
EXIT_FINDING = 1   # write: a declared partial-artefact path is missing; validate/verify: INVALID; resume/resume-check: UNSAFE
EXIT_USAGE = 2

# ---------------------------------------------------------------------------
# T140 Round 10 independent review (docs/CONTINUATION.md ADDENDUM 114): the
# shared `_real_print`/`_safe_print`/`_safe_str`/`_scan_argv_for_out`/
# `_invalidate_stale_out` helpers this file used to define LOCALLY (Round
# 9/9b) are now imported, ONCE, from `fc_entry.py` above (`diag`/`safe_str`/
# `scan_argv_for_out`/`invalidate_stale_out` -- see that module's own
# docstring for the FULL rationale, including why the retired `_safe_print`'s
# single-emitter design was itself the ROOT of this round's own new B1
# finding, and why `_safe_print`'s own dup2-the-whole-fd-to-devnull recovery
# was itself a NEW regression, T140 Round 10 review finding M4). This file's
# own stdout/stderr success/diagnostic lines are ALL routed through `diag`
# (never `emit_result`) -- `--out` is, by this file's own module docstring,
# ALWAYS this tool's real deliverable for every one of `write`/`validate`/
# `verify`/`resume`/`resume-check`, so every stdout/stderr print in THIS
# file is genuinely informational, never the thing a caller is meant to
# consume as the invocation's actual result (contrast
# `custody_sweep.py`'s `inventory`/`propose`/`verify-proposal`, whose
# stdout verdict-dump WHEN `--out` IS OMITTED is this file's sibling's own
# `emit_result` case, T140 Round 10 review finding B1).
# ---------------------------------------------------------------------------

# T126's own interim canonical phase order (UNCONFIRMED by the contract,
# DEFINED in test_resume_revalidate_red.sh's own header, binding-if-adopted,
# adopted here VERBATIM -- see module docstring "resume-check wire format").
PHASE_ORDER = ["PLAN", "IMPLEMENT", "VERIFY", "DEPLOY", "DONE"]
TERMINAL_PHASES = {"DONE"}
# T126's own closed keyword set for detecting a nondeterministic pending step
# (interim, DEFINED there; a future design might instead carry an explicit
# `deterministic: bool` field on each pending entry -- either design must
# catch the same fixture; adopted verbatim here, never re-decided).
ND_KEYWORDS = ("llm-generate", "llm-generated", "random", "nondeterministic", "non-deterministic")


# ---------------------------------------------------------------------------
# Shared primitives (data-model.md §0 ContentAddress; fc_common.py C-002).
# ---------------------------------------------------------------------------
def content_address(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _hostname():
    return os.uname().nodename if hasattr(os, "uname") else "unknown"


def write_json_atomic(path, doc):
    """Write-temp-then-rename (section 11.4.205(6)) for the handoff RECORD
    itself (already fully assembled -- schema/handoff_id/body_hash all
    present; NO run_meta injected here, per the module docstring's "carries
    NO run_meta key at all" rule)."""
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".handoff.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_report_atomic(out_path, body, schema, include_run_meta=True):
    """Write-temp-then-rename for a REPORT-of-this-run document (`--out`):
    injects schema + body_hash (C-002; excludes run_meta/body_hash per
    fc_common.EXCLUDED) + optional run_meta -- identical pattern to the
    already-landed sibling context/evidence_ref.py's write_doc_atomic()."""
    doc = dict(body)
    doc["schema"] = schema
    doc["body_hash"] = fc_common.body_hash_of(doc)
    if include_run_meta:
        doc["run_meta"] = {"host": _hostname()}
    write_json_atomic(out_path, doc)
    return doc


def _write_report_or_usage_error(tool_label, out_path, body, schema, include_run_meta=True):
    """T140 Round 7 review finding R7-I5 (section 11.4.250 heuristic-tower/
    primitive-defect, section 11.4.227 reuse-not-reinvention): every one of
    `write`/`validate`/`verify`/`resume`/`resume-check`'s several
    `write_report_atomic(...)` call sites below used to be entirely
    UNWRAPPED -- an unwritable --out path (parent directory missing/not
    writable/a permissions error) crashed this tool uncaught with no
    honest verdict written at all, the EXACT class the sibling
    `limit_class.py`/`custody_sweep.py` write sites already close (their
    own "T140 Round 6 review finding R6-I2" fixes, which this file's own
    Round 6 pass never reached -- an earlier Round 6 commit message's own
    claim that the fix was "reused across all three sibling tools" was
    FALSE for this file, per this round's own honest correction). ONE
    shared helper closes every call site in this file at once, rather than
    patching `cmd_write`'s two calls + `cmd_validate`'s one call +
    `cmd_resume_check`'s three calls independently, one crash site at a
    time across yet another round.

    Returns None on a successful write (the caller proceeds as before); on
    a write failure, prints a diagnosable message and returns EXIT_USAGE,
    which every call site below returns immediately -- there is
    deliberately no second, distinguishable "the write itself failed after
    a real verdict was already computed" exit code (matching this file's
    own already-established EXIT_USAGE=2 "usage/config error" convention,
    and the sibling tools' own identical choice).

    T140 Round 8 review finding R8-I1(d) (fixed here): was `except
    OSError` alone -- inconsistent with `limit_class.py`'s own sibling
    write-site fix (which already caught the shared
    `fc_common.SAFE_EXCEPTIONS` tuple) and narrower than `write_report_atomic`
    itself can raise (`fc_common.body_hash_of` -> `canon` ->
    `json.dumps(..., sort_keys=True, allow_nan=False)` can raise
    `TypeError` on a mutually-incomparable-keys `body`, or `ValueError` on
    a non-finite number reaching this far). Widened to bare `Exception` --
    the SAME widening `main()`'s own top-level dispatch boundary below
    receives, so a write site this function guards can never itself raise
    a DIFFERENT, still-uncaught exception class out of an already-failing
    error path."""
    try:
        write_report_atomic(out_path, body, schema, include_run_meta=include_run_meta)
    except Exception as exc:
        diag("handoff: %s -- cannot write --out %s: %s" % (tool_label, out_path, exc), file=sys.stderr)
        return EXIT_USAGE
    return None


def _json_list_arg(text, name):
    """Parses `text` as JSON, requiring the result to be a list. Returns
    (value, None) on success or (None, error-message) on failure -- callers
    print the message and exit EXIT_USAGE, never crash on a malformed
    caller-supplied blob.

    T140 Round 6 review finding R6-I1(b) (section 11.4.250, fixed here):
    parses via `fc_common.strict_loads` (never the stdlib `json.loads`
    directly) so a caller-supplied `NaN`/`Infinity`/`-Infinity` inside this
    blob is refused HERE, at parse time, rather than being silently accepted
    into the handoff record and crashing `write_report_atomic` far later
    (`fc_common.canon`'s `allow_nan=False`) with no honest verdict written.
    This is the ONE shared parse-time point (section 11.4.227) that closes
    the whole non-finite-JSON-constant class for every caller-supplied blob
    this tool reads -- never a per-write-site patch."""
    try:
        val = fc_common.strict_loads(text)
    except ValueError as exc:
        return None, "bad JSON for %s: %s" % (name, exc)
    if not isinstance(val, list):
        return None, "%s must be a JSON list" % name
    return val, None


def _reject_non_utf8_cli_string(value, flag_name):
    """T140 Round 8 review finding R8-I1 minor (b) (section 11.4.6, fixed
    here): a `--handoff` path decoded from argv on this platform's
    filesystem encoding with the `surrogateescape` error handler (the
    standard, POSIX-mandated way Python turns a non-UTF-8-decodable
    filesystem path byte sequence into a `str` -- Linux filenames are just
    bytes, so an arbitrary byte sequence is a genuinely reachable
    `--handoff` value) round-trips fine through EVERY filesystem operation
    (`open()`/`os.replace()`/etc. re-encode a surrogate-escaped `str` back
    to its ORIGINAL bytes), but CANNOT be `.encode("utf-8")`-ed cleanly --
    a lone surrogate code point is not valid UTF-8. This tool's own report
    documents embed CLI string values (e.g. `write`'s own
    `report_body["handoff_path"] = a.handoff`) and JSON-encode them via
    `canon()` -> `.encode("utf-8")`, which RAISES on such a value.

    Round 8's own live reproduction of the resulting defect: `write`'s
    OWN `--handoff` RECORD file was previously written to disk
    SUCCESSFULLY first (`write_json_atomic(a.handoff, doc)` never embeds
    `a.handoff` itself inside `doc`'s own content, only inside the path
    argument to `open()`, which re-encodes it back to its exact original
    bytes) -- and ONLY THEN did the subsequent `--out` REPORT write
    (which DOES embed `a.handoff` as a field value) raise
    `UnicodeEncodeError` and report the whole command as FAILED (rc=2) --
    a real, durably-persisted success being reported as a failure, the
    write-then-report-failure split this tool's own established
    conventions never otherwise produce.

    Fix (per this round's own explicit direction: "refuse it UP FRONT
    before any write happens, never write-then-report-failure"): this
    tool cannot safely support a `--handoff` value that cannot itself be
    embedded in the JSON documents it produces (end-to-end support would
    require restructuring every report document's own field to carry raw
    bytes rather than a JSON string, out of scope for a defensive fix), so
    it refuses such a value BEFORE either write (the handoff record OR the
    report) is ever attempted -- never after one has already succeeded.

    Returns an error message string if `value` is not encodable, else
    `None`."""
    try:
        value.encode("utf-8")
    except UnicodeEncodeError as exc:
        return ("%s value is not valid UTF-8 (%s) -- this tool cannot safely embed a "
                "non-UTF-8-encodable string in its own JSON report documents, so it is refused "
                "up front, before any write is attempted" % (flag_name, exc))
    return None


# ---------------------------------------------------------------------------
# write (HO-001)
# ---------------------------------------------------------------------------
def cmd_write(a):
    # T140 Round 8 review finding R8-I1 minor (b) (fixed here): checked
    # BEFORE any write of any kind -- see _reject_non_utf8_cli_string's own
    # docstring immediately above for the full write-then-report-failure
    # defect this closes.
    err = _reject_non_utf8_cli_string(a.handoff, "--handoff")
    if err:
        diag("handoff: write refused -- %s" % err, file=sys.stderr)
        return EXIT_USAGE

    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."

    pending, err = _json_list_arg(a.pending_json, "--pending-json")
    if err:
        diag("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    external_deps, err = _json_list_arg(a.external_deps_json, "--external-deps-json")
    if err:
        diag("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    effects_performed, err = _json_list_arg(a.effects_performed_json, "--effects-performed-json")
    if err:
        diag("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE

    # partial_artefacts: bare declared paths, content addresses COMPUTED here
    # from real, live bytes (never trusted from the caller) -- resolved
    # relative to dirname(--handoff), the SAME base-dir convention validate/
    # verify uses (see module docstring).
    partial_artefacts = []
    for rel in a.partial_artefacts:
        full = os.path.join(base_dir, rel)
        if not os.path.isfile(full):
            diag("handoff: write refused -- declared --partial-artefacts path does not "
                  "exist: %s (resolved: %s)" % (rel, full), file=sys.stderr)
            return EXIT_FINDING
        partial_artefacts.append({"path": rel, "content_address": content_address(full)})

    pre = {
        "schema": SCHEMA_HANDOFF,
        "agent_key": a.agent_key,
        "item_id": a.item_id,
        "alias": a.alias,
        "model": a.model,
        "effort": a.effort,
        "phase": a.phase,
        "verified": list(a.verified),
        "pending": pending,
        "partial_artefacts": partial_artefacts,
        "external_deps": external_deps,
        "effects_performed": effects_performed,
        "written_at": _now_iso(),
        "time_source": "event_occurred",
    }

    # Pass 1: handoff_id over the doc EXCLUDING handoff_id/body_hash/run_meta
    # (none of which are present yet -- `pre` already excludes all three).
    handoff_id = "sha256:" + hashlib.sha256(canon(pre).encode("utf-8")).hexdigest()
    doc = dict(pre)
    doc["handoff_id"] = handoff_id
    # Pass 2: body_hash via the established fc_common.py convention, now
    # hashing a doc that DOES include handoff_id (excludes only
    # body_hash/run_meta, neither of which is present yet).
    doc["body_hash"] = fc_common.body_hash_of(doc)

    # T140 Round 7 review finding R7-I5 (fixed here): the handoff RECORD
    # write (`--handoff`, distinct from the `--out` report below) was ALSO
    # entirely unguarded -- an unwritable `--handoff` path (its own parent
    # directory missing/not writable) crashed uncaught with no honest
    # verdict written at all.
    try:
        write_json_atomic(a.handoff, doc)
    except OSError as exc:
        diag("handoff: write -- cannot write --handoff %s: %s" % (a.handoff, exc), file=sys.stderr)
        return EXIT_USAGE

    report_body = {
        "handoff_id": handoff_id,
        "handoff_path": a.handoff,
        "item_id": a.item_id,
        "agent_key": a.agent_key,
        "phase": a.phase,
        "partial_artefact_count": len(partial_artefacts),
    }
    err = _write_report_or_usage_error("write", a.out, report_body, SCHEMA_WRITE, include_run_meta=True)
    if err is not None:
        return err

    diag("handoff: write wrote %s (handoff_id=%s, item_id=%s, phase=%s)"
          % (a.handoff, handoff_id, a.item_id, a.phase))
    return EXIT_OK


# ---------------------------------------------------------------------------
# validate / verify (HO-001 self-integrity + HO-002 partial-artefact
# re-hash). Both subparsers dispatch here -- see module docstring HONEST NOTE.
# ---------------------------------------------------------------------------
def cmd_validate(a):
    if not os.path.isfile(a.handoff):
        diag("handoff: --handoff not found: %s" % a.handoff, file=sys.stderr)
        return EXIT_USAGE
    try:
        with open(a.handoff, encoding="utf-8") as fh:
            # T140 Round 6 review finding R6-I1(b): `fc_common.strict_loads`
            # (never plain `json.load`), so a non-finite JSON constant in a
            # hand-edited/corrupted --handoff record is refused HERE, at
            # parse time, rather than reaching write_report_atomic below.
            doc = fc_common.strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        diag("handoff: cannot read --handoff: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(doc, dict):
        diag("handoff: --handoff is not a JSON object", file=sys.stderr)
        return EXIT_USAGE

    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."
    mismatches = []

    # 0. T140 Round 11 review finding I2 (fixed here): HO-001 shape check,
    #    BEFORE any other check. A record holding ONLY {"schema":"whatever"}
    #    with self-consistent hashes used to come back VALID -- the two
    #    hash checks below only prove the record is internally CONSISTENT,
    #    never that it is a COMPLETE handoff record, and with no
    #    `partial_artefacts` field at all the HO-002 loop iterated nothing
    #    and "passed" without checking anything. Every HO-001 field must be
    #    present with its contract type, and `schema` must equal the one
    #    schema this tool writes; anything else is INVALID, never VALID.
    if doc.get("schema") != SCHEMA_HANDOFF:
        mismatches.append("schema:expected=%s:got=%r" % (SCHEMA_HANDOFF, doc.get("schema")))
    for field, want_type in HO001_REQUIRED_FIELDS:
        if field not in doc:
            mismatches.append("missing_required_field:%s" % field)
        elif not isinstance(doc[field], want_type):
            mismatches.append("malformed:%s:expected-%s:got-%s" % (
                field, want_type.__name__, type(doc[field]).__name__))

    # 1. Self-integrity: handoff_id and body_hash both recompute correctly
    #    from the doc's own stored fields (the SAME two-pass construction
    #    `cmd_write` performs, run in reverse to verify rather than produce).
    doc_without_id = {k: v for k, v in doc.items() if k not in ("handoff_id", "body_hash", "run_meta")}
    recomputed_handoff_id = "sha256:" + hashlib.sha256(canon(doc_without_id).encode("utf-8")).hexdigest()
    if recomputed_handoff_id != doc.get("handoff_id"):
        mismatches.append("self_integrity:handoff_id")

    recomputed_body_hash = fc_common.body_hash_of(doc)
    if recomputed_body_hash != doc.get("body_hash"):
        mismatches.append("self_integrity:body_hash")

    # 2. HO-002: "Partial artefacts are never deleted or rewritten by crash
    #    handling; verify re-hashes them and exits 1 on any difference."
    #
    # T140 Round 7 review finding R7-I5 (section 11.4.250/11.4.201(6), fixed
    # here): `doc.get("partial_artefacts") or []` used to feed straight into
    # `for art in ...:` without first confirming the field's JSON shape --
    # a non-list `partial_artefacts` value (e.g. a bare, truthy string) was
    # silently iterated CHARACTER BY CHARACTER (a JSON string is truthy, so
    # `or []` never substitutes the honest empty default; each character
    # then silently failed the `isinstance(art, dict)` guard and
    # contributed a bogus "partial_artefact:None:missing" mismatch, with no
    # trace anywhere that the FIELD ITSELF, not any individual artefact,
    # was malformed). A `path` field present but not a string (e.g. a JSON
    # int/list) used to crash `os.path.join(base_dir, path)` uncaught with
    # a bare TypeError. And `content_address(full)` had no guard at all --
    # a `path` resolving to an EXISTING-but-UNREADABLE file (e.g. a
    # permission-denied path, or an absolute `path` that escapes `base_dir`
    # entirely -- `os.path.join` discards `base_dir` whenever the second
    # argument is itself absolute) crashed uncaught (PermissionError, an
    # OSError). Every one of these now fails CLOSED per-entry (section
    # 11.4.101 -- a malformed/unreadable entry becomes its own diagnosable
    # `mismatches` entry, contributing to an honest INVALID outcome, never
    # silently skipped nor crashing the whole subcommand) while still
    # processing every OTHER, well-formed sibling entry.
    raw_partial_artefacts = doc.get("partial_artefacts")
    if raw_partial_artefacts is not None and not isinstance(raw_partial_artefacts, list):
        mismatches.append("malformed:partial_artefacts:not-a-list:%s:%r" % (
            type(raw_partial_artefacts).__name__, raw_partial_artefacts))
        raw_partial_artefacts = []
    for art in (raw_partial_artefacts or []):
        if not isinstance(art, dict):
            mismatches.append("malformed:partial_artefact-entry:not-an-object:%r" % (art,))
            continue
        path = art.get("path")
        if path is not None and not isinstance(path, str):
            mismatches.append("malformed:partial_artefact-entry:path-not-a-string:%s:%r" % (
                type(path).__name__, path))
            continue
        full = os.path.join(base_dir, path) if path else None
        if not full or not os.path.isfile(full):
            mismatches.append("partial_artefact:%s:missing" % path)
            continue
        try:
            live_ca = content_address(full)
        except OSError as exc:
            mismatches.append("partial_artefact:%s:unreadable:%s: %s" % (path, type(exc).__name__, exc))
            continue
        if live_ca != art.get("content_address"):
            mismatches.append("partial_artefact:%s" % path)

    outcome = "INVALID" if mismatches else "VALID"
    body = {"outcome": outcome, "mismatches": mismatches}
    err = _write_report_or_usage_error("validate", a.out, body, SCHEMA_VALIDATE, include_run_meta=True)
    if err is not None:
        return err

    if outcome == "VALID":
        diag("handoff: validate VALID %s" % a.handoff)
        return EXIT_OK
    diag("handoff: validate INVALID %s -- mismatches: %s"
          % (a.handoff, ", ".join(mismatches)), file=sys.stderr)
    return EXIT_FINDING


# ---------------------------------------------------------------------------
# resume / resume-check (HO-003 + T126's own five-class "Safe to Resume?"
# extension). Both subparsers dispatch here -- see module docstring HONEST
# NOTE (mirrors the write/validate `validate`/`verify` naming-ambiguity
# precedent T133 already established for this same file).
#
# `_merkle_over_dir` was this file's OWN small, independently-written
# reimplementation of the data-model.md §0 `MerkleRoot` convention until
# T140 Round 10 independent review finding I2 (docs/CONTINUATION.md
# ADDENDUM 114): that per-file copy followed a NESTED symlink with a
# plain, following `open()` deep inside its own tree walk -- live-proven a
# hash oracle for arbitrary readable files (`tree_current/d/pw ->
# /etc/passwd` hashed `/etc/passwd`'s real bytes), an unbounded-read OOM
# hazard (`tree_current/d/z -> /dev/zero`), and hung on a FIFO until
# `timeout` (rc=124) -- because its own realpath containment check
# (immediately below, in `cmd_resume_check`'s check (2)) only resolves the
# TOP-level `locator` path once, saying nothing about entries genuinely
# INSIDE that tree that are themselves symlinks.
#
# `_merkle_over_dir` is now a thin alias for the ONE shared, lstat-based,
# non-following tree hasher this round adds to `fc_common.py`
# (`fc_common.merkle_over_dir_lstat` -- see that function's OWN docstring
# for the full lstat/readlink/O_NOFOLLOW/refuse-non-regular mechanism),
# landed there rather than reimplemented here a second time (section
# 11.4.227 reuse-not-reinvention, section 11.4.250 -- "One shared,
# lstat-based, non-following tree hasher" was this round's own explicit
# recommendation). Every call site in this file below is UNCHANGED (still
# calls `_merkle_over_dir(current_dir)`) and every `except OSError`
# wrapping it is UNCHANGED too -- `merkle_over_dir_lstat` raises `OSError`
# uniformly for every one of its own failure classes (a failed `lstat`, a
# refused non-regular entry, a failed file read), matching this alias's
# own pre-existing contract exactly, so no call site needed to change.
# ---------------------------------------------------------------------------
def _merkle_over_dir(root):
    return fc_common.merkle_over_dir_lstat(root)


def _typed_id_key(v):
    """T140 Round 5 review finding R5-I2: a match key over an `id` value
    that distinguishes id=1 (int) from id=True (bool) from id=1.0 (float)
    -- Python's `1 == True == 1.0` and all three hash identically, so a
    bare-value set/membership match wrongly treats them as the same
    recorded id. Returns `(type(v).__name__, v)` -- used consistently on
    BOTH sides of every effects_performed<->ground_truth_effects.json id
    comparison below, so a comparison is a match only when the two ids
    share BOTH their real JSON type AND their value."""
    return (type(v).__name__, v)


def _hashable_scalar(v):
    """True iff `v` is a JSON scalar this tool can safely put in a Python
    `set` and `sorted()` alongside other such scalars -- str/int/float/bool
    only (section 11.4.201(6), see _validate_resume_check_top_level_shape's
    own docstring below for why this excludes list/dict/None)."""
    return isinstance(v, (str, int, float, bool))


def _validate_resume_check_top_level_shape(doc):
    """T140 Round 5 review finding R5-I1 (section 11.4.250 heuristic-tower/
    primitive-defect): checks (1)-(5) in cmd_resume_check below, PLUS its
    own effects_not_to_repeat computation, each independently index into
    this record's top-level fields field-by-field WITHOUT first confirming
    the WHOLE record's shape is well-formed -- Rounds 1-4 fixed ten
    distinct crash sites (one at a time, as review kept finding a new one)
    plus a silent fail-open (a bare-string `effects_performed` being
    iterated character-by-character by Python, each character silently
    failing the `isinstance(e, dict)` guard and being dropped, so a
    genuinely malformed field produced a wrongly-SAFE verdict with no
    trace anywhere that anything was wrong). That is the exact heuristic-
    tower anti-pattern section 11.4.250 names -- "when N heuristic layers
    stack to compensate, the primitive is broken. STOP adding layers." This
    function is the one, deliberate STOP: it runs ONCE, BEFORE any of
    (1)-(5), and fails CLOSED (section 11.4.101) with a single new
    "malformed-handoff-field" reason the moment ANY top-level field has the
    wrong JSON shape -- so checks (1)-(5) below may now safely ASSUME a
    well-formed top-level shape, and a genuinely NEW malformed-shape case
    none of Rounds 1-4 individually enumerated is caught by construction,
    never by a future Round 6 single-site patch.

    Returns a single unsafe_reasons dict (the FIRST violation found, in
    the fixed order below) if the record's top-level shape is malformed,
    or None if it is well-formed. Checks, in order (matching the R5-I1
    review's own table):
      - `written_at`, `phase`: JSON string when present (rows 1, 7).
      - `verified`, `external_deps`, `pending`, `effects_performed`: JSON
        list when present (rows 2, 3, 4, 5, 6; also closes the
        bare-string-iterated-as-a-list fail-open case, since a JSON
        string is never a JSON list).
      - `affects_verified`: a JSON list of hashable scalars
        (str/int/float/bool, never a list or dict element -- unhashable
        values crash `reverify.add()`/`sorted(reverify)` below) when
        present, checked BOTH at the handoff record's own top level
        (defense-in-depth: not part of the documented schema `cmd_write`
        emits today, but validated here in case a hand-edited or future-
        schema record carries one) AND nested inside EACH `external_deps`
        entry (its actual, documented location -- module docstring
        "mismatch also adds every id in that dep's `affects_verified`" --
        rows 8, 9, 10 of the R5-I1 review table).
    A value of `None` is treated as "field genuinely absent" throughout
    (matching every one of checks (1)-(5)'s own existing `doc.get(field)`
    conventions below), never itself a shape violation.
    """
    for field in ("written_at", "phase"):
        v = doc.get(field)
        if v is not None and not isinstance(v, str):
            return {
                "class": "malformed-handoff-field",
                "detail": ("handoff record field `%s` must be a JSON string when present "
                           "(got %s: %r) -- this tool cannot safely reason about the "
                           "record's timing/phase without a well-typed value here; treat "
                           "as unsafe until independently, manually re-verified") % (
                               field, type(v).__name__, v),
            }
    for field in ("verified", "external_deps", "pending", "effects_performed"):
        v = doc.get(field)
        if v is not None and not isinstance(v, list):
            return {
                "class": "malformed-handoff-field",
                "detail": ("handoff record field `%s` must be a JSON list when present "
                           "(got %s: %r) -- every per-entry check below assumes it can "
                           "iterate this field as a list, and Python would otherwise "
                           "either crash iterating a non-iterable value (e.g. an int) or "
                           "silently iterate a JSON string character-by-character (a "
                           "genuinely malformed field masquerading as an honestly empty "
                           "one); treat as unsafe until independently, manually "
                           "re-verified") % (field, type(v).__name__, v),
            }

    def _check_affects_verified(v, where):
        if v is None:
            return None
        if not isinstance(v, list):
            return {
                "class": "malformed-handoff-field",
                "detail": ("%s `affects_verified` must be a JSON list when present (got "
                           "%s: %r) -- this tool cannot add its entries to "
                           "facts_needing_reverification without iterating it as a list; "
                           "treat as unsafe until independently, manually re-verified") % (
                               where, type(v).__name__, v),
            }
        for item in v:
            if not _hashable_scalar(item):
                return {
                    "class": "malformed-handoff-field",
                    "detail": ("%s `affects_verified` contains an entry that is not a "
                               "hashable JSON scalar (str/int/float/bool) -- got %s: %r "
                               "-- this tool cannot add it to the "
                               "facts_needing_reverification set/sort it alongside other "
                               "entries; treat as unsafe until independently, manually "
                               "re-verified") % (where, type(item).__name__, item),
                }
        return None

    violation = _check_affects_verified(doc.get("affects_verified"),
                                         "handoff record top-level field")
    if violation is not None:
        return violation
    deps_preview = doc.get("external_deps")
    if isinstance(deps_preview, list):
        for dep in deps_preview:
            if isinstance(dep, dict):
                violation = _check_affects_verified(dep.get("affects_verified"),
                                                      "external_deps entry")
                if violation is not None:
                    return violation
    return None


def cmd_resume_check(a):
    if not os.path.isfile(a.handoff):
        diag("handoff: --handoff not found: %s" % a.handoff, file=sys.stderr)
        return EXIT_USAGE
    try:
        with open(a.handoff, encoding="utf-8") as fh:
            # T140 Round 6 review finding R6-I1(b) (section 11.4.250, fixed
            # here): `fc_common.strict_loads` -- never plain `json.load` --
            # so a NaN/Infinity/-Infinity anywhere in --handoff (e.g.
            # {"handoff_id": NaN, ...}) is refused HERE, at parse time,
            # BEFORE it can ever be copied verbatim into this function's own
            # `body` dict and crash `write_report_atomic` -> fc_common.canon
            # (allow_nan=False) at one of the THREE write sites below with
            # no honest verdict written and a stale --out left un-rewritten.
            # This is the ONE shared parse-time fix (section 11.4.227) --
            # never a per-write-site patch -- because every value this
            # function ever writes back out (handoff_id,
            # facts_needing_reverification, effects_not_to_repeat, ...) is
            # derived FROM `doc`, which can now never contain a non-finite
            # number once this single read succeeds.
            doc = fc_common.strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        diag("handoff: cannot read --handoff: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(doc, dict):
        diag("handoff: --handoff is not a JSON object", file=sys.stderr)
        return EXIT_USAGE

    # T140 Round 5 review finding R5-I1 fix (section 11.4.250, see
    # _validate_resume_check_top_level_shape's own docstring above for the
    # full rationale): the up-front, single-primitive shape check runs
    # BEFORE any of checks (1)-(5), fails closed immediately on the first
    # malformed top-level field found, and never proceeds into the
    # per-entry checks below (which now safely assume a well-formed
    # shape).
    shape_violation = _validate_resume_check_top_level_shape(doc)
    if shape_violation is not None:
        body = {
            "handoff_id": doc.get("handoff_id"),
            "safe_to_resume_without_reverification": False,
            "unsafe_reasons": [shape_violation],
            "facts_needing_reverification": [],
            "effects_not_to_repeat": [],
        }
        # T140 Round 7 review finding R7-I5 (fixed here): see
        # `_write_report_or_usage_error`'s own docstring for the full
        # rationale -- this call site was, like every other
        # `write_report_atomic(...)` call in this file, entirely unwrapped.
        err = _write_report_or_usage_error("resume-check", a.out, body, SCHEMA_RESUME_CHECK,
                                            include_run_meta=True)
        if err is not None:
            return err
        diag("handoff: resume-check UNSAFE %s -- 1 reason(s): %s"
              % (a.handoff, shape_violation["class"]), file=sys.stderr)
        return EXIT_FINDING

    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."
    reasons = []
    reverify = set()

    # T140 Round 5 review finding R5-I1(2) (section 11.4.250, DELIBERATE
    # DEFENSE IN DEPTH -- a SEPARATE, additional layer from the up-front
    # shape check above, never a substitute for it): the shape check
    # enumerates every field-shape violation this file's author could
    # identify from five rounds of live review findings; it is
    # deliberately NOT claimed exhaustive (section 11.4.6). This catch-all
    # is the safety net for "anything we did not anticipate" -- a
    # genuinely NEW malformed-shape case reaching checks (1)-(5) below
    # still fails CLOSED with an honest, diagnosable verdict (naming the
    # real exception + its type) and a genuinely fresh --out write, rather
    # than crashing uncaught and leaving a stale --out file silently
    # un-rewritten -- exactly the defect class every one of Rounds 1-4's
    # fixes closed one crash site at a time.
    try:
            # (1) INCONSISTENT INTERNAL STATE: a verified fact's own established_at
        # is causally AFTER the handoff's own written_at (the record could not
        # have known about a fact from its own future), OR the phase is declared
        # terminal while pending work remains outstanding.
        #
        # T140 Round 4 review finding R4-I1 (section 11.4.201(6) FALSE-NULL, fixed
        # here): a `verified` entry's `established_at` field being a JSON value
        # other than a string (e.g. a bare int) used to crash this tool uncaught
        # (`'>' not supported between instances of 'int' and 'str'`) at the
        # comparison below, rather than fail closed. This is a GENUINELY
        # DIFFERENT situation from a non-dict `verified` entry (R3-I1's own
        # investigated-and-confirmed-fine skip immediately above, and this same
        # test_handoff_i4_regression.sh's own header note: a bare-string
        # `verified` entry is cmd_write's own documented, intended shape and
        # genuinely carries no established_at to discard). A DICT entry that DOES
        # set `established_at` to a malformed value is unsafe-to-skip: the field
        # is PRESENT, so it represents an attempt to record real causal
        # information that turned out corrupted, not an absence of information --
        # silently skipping it would let a causally-impossible fact slip through
        # unnoticed exactly like every OTHER malformed-field case this tool
        # already fails closed on (check (2)'s malformed-external-dependency,
        # check (3)'s malformed-pending-step, check (4)'s malformed-ground-truth-
        # entry/malformed-effects-performed-entry). NEW distinct
        # "malformed-verified-entry" class -- this loop had none before, since
        # R3-I1 only needed the non-dict case investigated, never a
        # wrong-type-field-within-a-dict case.
        written_at = doc.get("written_at")
        for v in (doc.get("verified") or []):
            if not isinstance(v, dict):
                continue
            established_at = v.get("established_at")
            if established_at is not None and not isinstance(established_at, str):
                reasons.append({
                    "class": "malformed-verified-entry",
                    "detail": ("verified fact %s has an `established_at` field that is not a "
                               "string (got %r) -- this tool cannot compare a non-string value "
                               "against written_at to rule out a causally-impossible record, "
                               "and a malformed timestamp may represent genuine but corrupted "
                               "information rather than an absent one; treat as unsafe until "
                               "independently, manually re-verified") % (v.get("ref_id"), established_at),
                })
                continue
            if established_at is not None and written_at is not None and established_at > written_at:
                reasons.append({
                    "class": "inconsistent-internal-state",
                    "detail": ("verified fact %s established_at %s is AFTER the handoff's "
                               "own written_at %s (causally impossible -- the record cannot "
                               "be trusted)") % (v.get("ref_id"), established_at, written_at),
                })
        if doc.get("phase") in TERMINAL_PHASES and doc.get("pending"):
            reasons.append({
                "class": "inconsistent-internal-state",
                "detail": "phase %s is terminal but pending is non-empty" % doc.get("phase"),
            })

        # (2) STALE EXTERNAL DEPENDENCY: an external_dep's live content_address
        # (recomputed over tree_current/<locator>, resolved relative to
        # dirname(--handoff) -- see module docstring "resume-check wire format")
        # no longer matches the recorded one. Only kind=="git-tree" is
        # re-hashable here (the only kind any checked-in fixture exercises).
        #
        # T140 Round 1 review finding I4 (section 11.4.201(6) FALSE-NULL, fixed
        # here): a dep of any OTHER kind used to be silently `continue`d past --
        # reported neither as stale NOR as anything else, so
        # safe_to_resume_without_reverification stayed wrongly `true` with no
        # trace anywhere in the output that an unverifiable dependency existed.
        # Fail CLOSED instead (section 11.4.101 safe-reversible default): a dep
        # whose `kind` this tool cannot re-hash is UNVERIFIABLE, not silently
        # trusted -- record it as its own unsafe_reasons entry naming the exact
        # unrecognized kind, and (mirroring the stale-dependency branch) add any
        # declared `affects_verified` ids to facts_needing_reverification, since
        # this tool has no way to know those facts still hold either.
        #
        # T140 Round 2 review finding I2(F) (section 11.4.201(6) FALSE-NULL,
        # fixed here): a NON-DICT external_deps entry used to be silently
        # `continue`d past entirely -- DEC-34 requires EVERY dependency be
        # re-hashed, so a malformed entry (not even a dict, or a dict whose
        # `kind` field is itself missing/malformed) cannot be re-hashed and
        # therefore cannot be confirmed unchanged, exactly like an unrecognized
        # `kind` value (I4's own already-fixed case above) -- fail CLOSED with
        # its own distinct "malformed-external-dependency" reason instead.
        for dep in (doc.get("external_deps") or []):
            if not isinstance(dep, dict):
                reasons.append({
                    "class": "malformed-external-dependency",
                    "detail": ("external_deps entry is not a JSON object (got %r) -- DEC-34 "
                               "requires every dependency be re-hashed, and a non-dict entry "
                               "cannot be re-hashed or identified; treat as unsafe until "
                               "independently, manually re-verified") % (dep,),
                })
                continue
            kind = dep.get("kind")
            if not isinstance(kind, str) or not kind:
                reasons.append({
                    "class": "malformed-external-dependency",
                    "detail": ("external dep %s has a missing or malformed `kind` field (got %r) "
                               "-- DEC-34 requires every dependency be re-hashed, and this tool "
                               "cannot re-hash a dependency whose kind it cannot read; treat as "
                               "unsafe until independently, manually re-verified") % (
                                   dep.get("locator"), kind),
                })
                for ref_id in (dep.get("affects_verified") or []):
                    reverify.add(_typed_id_key(ref_id))
                continue
            if kind == "git-tree":
                # T140 Round 4 review finding R4-I1 (section 11.4.201(6)
                # FALSE-NULL, fixed here): a `locator` field that is a JSON value
                # other than a string (e.g. a bare int) used to crash this tool
                # uncaught (`os.path.join() argument must be str, not int`) at
                # the path join below. Extend the ALREADY-EXISTING
                # "malformed-external-dependency" class (rather than mint a new
                # one) with a FOURTH, distinct detail variant -- this file's own
                # established convention (see check (3)'s malformed-pending-step
                # precedent immediately below) of distinguishing "not a dict" /
                # "missing kind" / "unrecognized kind" from "dict, kind=git-tree,
                # but a field within it has the wrong type" in the detail text,
                # so all four remain honestly distinguishable.
                locator = dep.get("locator")
                if locator is not None and not isinstance(locator, str):
                    reasons.append({
                        "class": "malformed-external-dependency",
                        "detail": ("external dep has kind=git-tree but its `locator` field is "
                                   "not a string (got %r) -- DEC-34 requires every dependency "
                                   "be re-hashed, and this tool cannot resolve a filesystem "
                                   "path from a non-string locator to compute its live "
                                   "content_address; treat as unsafe until independently, "
                                   "manually re-verified") % (locator,),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(_typed_id_key(ref_id))
                    continue
                # T140 Round 8 review finding R8-I1 minor (e) (section
                # 11.4.6, fixed here): `locator` reaches this point
                # confirmed to be a genuine JSON string (the isinstance
                # check immediately above), but was NEVER sanitized before
                # being joined onto `base_dir/tree_current/` -- an
                # ABSOLUTE `locator` (e.g. `/etc/passwd`) makes
                # `os.path.join(base_dir, "tree_current", locator)`
                # silently DROP every preceding component (Python's own
                # `os.path.join` semantics: an absolute path component
                # replaces everything before it), and a `..`-containing
                # relative `locator` (e.g. `../../../../etc`) escapes
                # `tree_current/` via ordinary path traversal -- EITHER
                # way, `_merkle_over_dir` below would then walk and
                # `open()`-read ARBITRARY host filesystem paths this
                # dependency's `locator` never legitimately names, a
                # caller-controlled-input class this tool must never
                # trust blindly (found by code-reading; verified live
                # below before landing). Fix: reject BEFORE any
                # filesystem access is attempted whenever the normalized
                # target does not resolve INSIDE `base_dir/tree_current/`
                # -- `os.path.normpath` collapses `..`/`.`/redundant
                # separators, and a single containment check (target ==
                # the tree_current root, or starts with
                # `tree_current root + os.sep`) catches BOTH the absolute-
                # path case (its normalized form never starts with the
                # containment root at all) and the `..`-escape case
                # uniformly, rather than two separate ad-hoc checks.
                current_dir = os.path.join(base_dir, "tree_current", locator or "")
                containment_root = os.path.normpath(os.path.join(base_dir, "tree_current"))
                normalized_current_dir = os.path.normpath(current_dir)
                if (normalized_current_dir != containment_root
                        and not normalized_current_dir.startswith(containment_root + os.sep)):
                    reasons.append({
                        "class": "malformed-external-dependency",
                        "detail": ("external dep has kind=git-tree but its `locator` field %r "
                                   "resolves OUTSIDE its own tree_current/ scope (normalized "
                                   "target: %r, must be under: %r) -- an absolute path or a "
                                   "`..`-escaping locator would let this tool inspect ARBITRARY "
                                   "host filesystem paths; refused before any filesystem access "
                                   "is attempted, treat as unsafe until independently, manually "
                                   "re-verified") % (locator, normalized_current_dir, containment_root),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(_typed_id_key(ref_id))
                    continue
                # T140 Round 9 review finding R9-M3 (fixed here): the
                # LEXICAL (`os.path.normpath`-based) containment check
                # immediately above only inspects the PATH STRING -- it
                # never resolves symlinks, so a `locator` whose lexical
                # form stays safely inside `tree_current/` (e.g. plain
                # `lnk`) can still be a SYMLINK pointing OUTSIDE
                # tree_current/ entirely (e.g. `tree_current/lnk -> /etc`)
                # and sail straight through unchanged -- `_merkle_over_dir`
                # below then walks the symlink's REAL target (arbitrary
                # host filesystem) until it hits a filesystem error, an
                # honest-but-UNINTENDED "unverifiable-external-dependency"
                # outcome rather than a genuine, up-front REFUSAL of the
                # untrusted locator itself. Live-reproduced exactly:
                # `tree_current/lnk -> /etc` passes the check above,
                # `_merkle_over_dir` then walks `/etc` (a REAL, unrelated
                # host directory) until `PermissionError` on a file inside
                # it. Fixed by additionally resolving the target with
                # `os.path.realpath` (which DOES follow symlinks, unlike
                # `normpath`) and re-checking containment against the SAME
                # `containment_root` (also realpath'd, so a symlinked
                # `tree_current/` itself -- unlikely but possible -- is
                # never a false refusal) -- refuses BEFORE `_merkle_over_dir`
                # ever opens a single file whenever a symlink (at ANY depth
                # under `current_dir`, since `realpath` resolves the WHOLE
                # path) escapes `tree_current/`'s own scope, even though
                # the lexical check above already passed. Reuses the SAME
                # "malformed-external-dependency" class (never a new one)
                # -- a symlink escaping the declared scope is the SAME
                # untrusted-locator refusal as an absolute/`..`-escaping
                # one, just detected by a different, necessary mechanism.
                real_current_dir = os.path.realpath(current_dir)
                real_containment_root = os.path.realpath(containment_root)
                if (real_current_dir != real_containment_root
                        and not real_current_dir.startswith(real_containment_root + os.sep)):
                    reasons.append({
                        "class": "malformed-external-dependency",
                        "detail": ("external dep has kind=git-tree but its `locator` field %r "
                                   "resolves OUTSIDE its own tree_current/ scope via a SYMLINK "
                                   "(resolved target: %r, must be under: %r) -- a symlink escaping "
                                   "tree_current/ would let this tool inspect ARBITRARY host "
                                   "filesystem paths; refused before any filesystem access is "
                                   "attempted, treat as unsafe until independently, manually "
                                   "re-verified") % (locator, real_current_dir, real_containment_root),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(_typed_id_key(ref_id))
                    continue
                # T140 Round 6 review finding R6-I1(a) (section 11.4.250
                # heuristic-tower/primitive-defect, section 11.4.201(11)
                # artifact-usability, fixed here): `_merkle_over_dir` walks
                # real filesystem entries and opens each one
                # (`content_address` -> `open(path, "rb")`) -- a dangling
                # symlink or a mode-000 file under a real dependency's
                # tree_current/<locator> (both plausible at AOSP-scale on a
                # real checkout, never merely a fixture-only concern) raises
                # FileNotFoundError/PermissionError (both OSError), which
                # used to crash this tool uncaught with no honest verdict
                # written and the caller's stale --out left un-rewritten.
                # Fail CLOSED instead (section 11.4.101): this dependency
                # cannot be re-hashed, so it cannot be confirmed unchanged --
                # exactly the same "cannot inspect, therefore cannot confirm
                # safe" reasoning the "unrecognized dependency kind" branch
                # immediately below already applies, so this reuses that
                # SAME "unverifiable-external-dependency" class (never a new
                # one) with its own, distinct filesystem-error detail
                # variant, and (matching every other fail-closed branch in
                # this loop) still adds the dep's own affects_verified ids
                # to facts_needing_reverification before moving on to the
                # next dependency.
                try:
                    live_hash = _merkle_over_dir(current_dir)
                except OSError as exc:
                    reasons.append({
                        "class": "unverifiable-external-dependency",
                        "detail": ("external dep %s (kind=git-tree) could not be re-hashed: a "
                                   "filesystem error (%s: %s) under tree_current/%s prevented "
                                   "computing its live content_address -- this tool cannot "
                                   "confirm the dependency is unchanged; treat as unsafe until "
                                   "independently, manually re-verified") % (
                                       locator, type(exc).__name__, exc, locator),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(_typed_id_key(ref_id))
                    continue
                recorded = dep.get("content_address")
                if live_hash != recorded:
                    reasons.append({
                        "class": "stale-external-dependency",
                        "detail": "external dep %s content_address changed: recorded=%s live=%s" % (
                            locator, recorded, live_hash),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(_typed_id_key(ref_id))
            else:
                reasons.append({
                    "class": "unverifiable-external-dependency",
                    "detail": ("external dep %s has unrecognized dependency kind: %s -- this tool "
                               "cannot re-hash it, so it cannot be confirmed unchanged; treat as "
                               "unsafe until independently, manually re-verified") % (
                                   dep.get("locator"), kind),
                })
                for ref_id in (dep.get("affects_verified") or []):
                    reverify.add(_typed_id_key(ref_id))

        # (3) NONDETERMINISTIC REPLAY: a pending step names a source that cannot
        # be blindly re-executed and trusted to reproduce the same outcome.
        #
        # T140 Round 3 review finding R3-I1(a) (section 11.4.201(6) FALSE-NULL,
        # fixed here -- a sibling gap of Round 2's I2(F) in this SAME function
        # that fix did not reach): a non-dict `pending` entry used to be silently
        # `continue`d past entirely. `cmd_write`'s own `_json_list_arg` (see its
        # docstring above) only validates that `--pending-json` parses to a JSON
        # LIST -- it does not, and cannot, validate each entry's shape (it is
        # shared verbatim across --pending-json/--external-deps-json/
        # --effects-performed-json, three fields with three different required
        # shapes, so a single generic per-field-shape check does not belong
        # there); a non-dict pending entry therefore passes `write` unrejected
        # and lands in the handoff record exactly as the caller supplied it.
        # Because this tool cannot read a `step`/`precondition` off a non-dict
        # value, it cannot rule out a nondeterministic source for it either --
        # exactly the same "cannot re-hash/re-check, therefore cannot confirm
        # safe" reasoning check (2)'s already-fixed `malformed-external-
        # dependency` class applies to a non-dict `external_deps` entry. Fail
        # CLOSED instead (section 11.4.101) with its own distinct
        # "malformed-pending-step" reason, naming the raw malformed value.
        for step in (doc.get("pending") or []):
            if not isinstance(step, dict):
                reasons.append({
                    "class": "malformed-pending-step",
                    "detail": ("pending entry is not a JSON object (got %r) -- this tool cannot "
                               "read a step/precondition off a non-dict value, so it cannot rule "
                               "out a nondeterministic source for it; treat as unsafe until "
                               "independently, manually re-verified") % (step,),
                })
                continue
            # T140 Round 4 review finding R4-I1 (section 11.4.201(6) FALSE-NULL,
            # fixed here): a `step`/`precondition` field that is a JSON value
            # other than a string (e.g. a bare int) used to crash this tool
            # uncaught (`can only concatenate str (not "int") to str`) at the
            # text-concatenation below. Extend the ALREADY-EXISTING
            # "malformed-pending-step" class (rather than mint a new one) with a
            # SECOND, distinct detail variant that distinguishes "not a dict"
            # (above) from "dict, but field X has the wrong type" (below) so the
            # two remain honestly distinguishable, matching check (2)'s
            # malformed-external-dependency / check (4)'s
            # malformed-ground-truth-entry precedent for the same distinction.
            step_text = step.get("step")
            precondition_text = step.get("precondition")
            bad_field = None
            if step_text is not None and not isinstance(step_text, str):
                bad_field = "step"
            elif precondition_text is not None and not isinstance(precondition_text, str):
                bad_field = "precondition"
            if bad_field is not None:
                bad_value = step_text if bad_field == "step" else precondition_text
                reasons.append({
                    "class": "malformed-pending-step",
                    "detail": ("pending entry is a JSON object but its `%s` field is not a "
                               "string (got %r) -- this tool cannot read a step/precondition "
                               "off a non-string value, so it cannot rule out a "
                               "nondeterministic source for it; treat as unsafe until "
                               "independently, manually re-verified") % (bad_field, bad_value),
                })
                continue
            text = ((step_text or "") + " " + (precondition_text or "")).lower()
            if any(k in text for k in ND_KEYWORDS):
                reasons.append({
                    "class": "nondeterministic-replay",
                    "detail": ("pending step %r depends on a nondeterministic source and "
                               "must not be blindly replayed") % step.get("step"),
                })

        # (4) UNRECORDED EXTERNAL EFFECT: a real effect happened (per an
        # OPTIONAL, independently-observable ground_truth_effects.json sibling,
        # resolved relative to dirname(--handoff) -- never derived from the
        # handoff record itself, Producer != oracle, section 11.4.245/11.4.240)
        # but is absent from effects_performed.
        #
        # T140 Round 1 review finding I4 (section 11.4.201(6) FALSE-NULL, fixed
        # here): the sibling file's absence was PREVIOUSLY treated as an
        # unconditional honest skip (section 11.4.3) even when the record's own
        # `effects_performed` field claims effects genuinely happened --
        # exactly the case where an independent ground-truth cross-check is
        # actually needed.
        #
        # T140 Round 2 review finding I2(C) (section 11.4.201(6) FALSE-NULL,
        # fixed here; a further correction of the Round 1 I4 fix's own design,
        # not merely a missed case): the Round 1 fix narrowed the "missing
        # sibling" finding to fire ONLY when `effects_performed` is non-empty,
        # reasoning that an empty `effects_performed` means "nothing in the
        # record claims an effect occurred, so there is nothing this check
        # could cross-verify either way". That reasoning gets check (4)'s own
        # purpose backwards: `effects_performed` is a field INSIDE the handoff
        # record itself, written by the SAME agent whose crash this check
        # exists to guard against -- an agent that crashed BEFORE it ever got
        # to record an effect in its own handoff doc leaves `effects_performed`
        # empty regardless of whether it actually performed one. An empty
        # `effects_performed` therefore proves NOTHING about whether an effect
        # genuinely occurred; it is not evidence of absence (section 11.4.6).
        # A missing `ground_truth_effects.json` sibling is consequently ALWAYS
        # a genuine, unverifiable gap -- fail CLOSED (section 11.4.101)
        # unconditionally, never only when `effects_performed` happens to be
        # non-empty. The two cases remain honestly DISTINGUISHED in the output
        # detail text (empty vs non-empty `effects_performed`) even though both
        # now contribute to unsafe.
        #
        # T140 Round 2 review finding I2(D) (section 11.4.201(6) FALSE-NULL,
        # fixed here): a malformed or unreadable ground_truth_effects.json
        # (JSON parse error, or a valid-JSON-but-non-list top-level value) used
        # to be silently coerced to `[]` and therefore treated as "no ground
        # truth effects exist" -- a DIFFERENT, STRONGER claim than "we could
        # not read the file". Fail CLOSED instead with its own distinct
        # "unreadable-ground-truth" reason, and skip the per-effect cross-check
        # below entirely (there is no honestly-parsed ground truth to check
        # against).
        effects_performed = doc.get("effects_performed") or []
        gt_path = os.path.join(base_dir, "ground_truth_effects.json")
        if os.path.isfile(gt_path):
            ground_truth = None
            try:
                with open(gt_path, encoding="utf-8") as fh:
                    # T140 Round 6 review finding R6-I1(b): strict_loads, so
                    # a non-finite constant in this sibling file is refused
                    # here rather than silently accepted and (harmlessly, in
                    # this particular case, since only `id` values feed into
                    # facts_needing_reverification/effects_not_to_repeat --
                    # but never assumed harmless, section 11.4.6) risking a
                    # later crash.
                    parsed = fc_common.strict_loads(fh.read())
            except (OSError, ValueError) as exc:
                reasons.append({
                    "class": "unreadable-ground-truth",
                    "detail": ("ground_truth_effects.json exists but could not be read or "
                               "parsed as JSON (%s) -- this tool has no confirmed-readable "
                               "independent ground-truth source, which is a DIFFERENT, weaker "
                               "claim than 'no ground truth effects exist'; treat as unsafe "
                               "until the file is repaired or an independent source is "
                               "supplied") % (exc,),
                })
            else:
                if not isinstance(parsed, list):
                    reasons.append({
                        "class": "unreadable-ground-truth",
                        "detail": ("ground_truth_effects.json top-level value is not a JSON "
                                   "list (got %s) -- this tool cannot enumerate ground-truth "
                                   "effects from it, which is a DIFFERENT, weaker claim than "
                                   "'no ground truth effects exist'; treat as unsafe until the "
                                   "file is repaired or an independent source is supplied") % (
                                       type(parsed).__name__,),
                    })
                else:
                    ground_truth = parsed
            if ground_truth is not None:
                # T140 Round 3 review finding R3-I1(c) (a `None in {None}` id-
                # matching bug, fixed here): an `effects_performed` entry with no
                # `id` field used to contribute the literal value `None` to
                # `recorded_ids`, so ANY ground-truth entry that ALSO happened to
                # lack an `id` field -- a genuinely DIFFERENT effect that merely
                # shares the same missing-id shape -- would wrongly test
                # `None in recorded_ids` as True and be treated as "already
                # recorded", even though the two entries are unrelated. Exclude
                # `None`/missing ids from the match-key set entirely: an id-less
                # `effects_performed` entry can never satisfy a cross-check
                # (nothing else can be matched against it), so it must never be
                # treated as a valid match key.
                # T140 Round 4 review finding R4-I1 (section 11.4.201(6)
                # FALSE-NULL, fixed here): an `effects_performed` entry's own
                # `id` field being a JSON array or object (e.g. `{"a": 1}`) is
                # UNHASHABLE and used to crash this tool uncaught
                # (`TypeError: unhashable type: 'dict'`) building this set via
                # the set-comprehension this replaces. This tool cannot use an
                # unhashable id as a match key against ground_truth_effects.json
                # at all, so -- exactly the same "cannot inspect, therefore
                # cannot confirm safe" reasoning R3-I1's own
                # malformed-ground-truth-entry class already applies to a
                # non-dict ground-truth entry -- route it to its own NEW,
                # distinct "malformed-effects-performed-entry" reason (this
                # field had no malformed-entry class at all before; a non-dict
                # `effects_performed` entry was ALREADY safely filtered out by
                # `isinstance(e, dict)` below, so only the unhashable-`id`
                # sub-case is genuinely new) instead of crashing (section
                # 11.4.101 fail-closed). Per R3-I1(c)'s own already-landed fix
                # (comment above, unchanged), a `None`/missing id is STILL
                # excluded from the match-key set entirely, unaffected by this
                # extension.
                #
                # T140 Round 5 review finding R5-I2 (id-type-collision fix,
                # here): `id`-based matching used to key `recorded_ids` (and
                # the `gt_id not in recorded_ids` membership test below) by
                # the BARE `id` value. Python's `True == 1` (and hashes
                # identically to it -- `1.0` behaves the same way, since
                # `hash(1) == hash(1.0) == hash(True)`), so an
                # effects_performed entry with `id=1` (int) wrongly matched
                # a ground_truth_effects.json entry with `id=True` (bool) --
                # a GENUINELY DIFFERENT effect, merely sharing a
                # type-coercible id value, wrongly treated as "already
                # recorded" (a section 11.4.201(6) FALSE-NULL: the
                # `unrecorded-external-effect` finding this check exists to
                # raise stayed silent for a distinct, unmatched effect).
                # Fixed by keying BOTH sides of the comparison by a
                # TYPE-TAGGED value (`_typed_id_key`, `(type(v).__name__,
                # v)`) instead of the bare id -- `('int', 1)` and `('bool',
                # True)` are now genuinely distinct set members, so id=1 and
                # id=True never collide, while two entries that share BOTH
                # the same real type and the same value still correctly
                # match (the intended, un-regressed behaviour).
                recorded_ids = set()
                for e in effects_performed:
                    if not isinstance(e, dict):
                        continue
                    id_val = e.get("id")
                    if id_val is None:
                        continue
                    if isinstance(id_val, (list, dict)):
                        reasons.append({
                            "class": "malformed-effects-performed-entry",
                            "detail": ("effects_performed entry has an `id` field that is a "
                                       "JSON %s (got %r), which is unhashable and cannot be "
                                       "used as a match key against ground_truth_effects.json "
                                       "-- this tool cannot confirm this effect was genuinely "
                                       "cross-checked; treat as unsafe until independently, "
                                       "manually re-verified") % (
                                           "array" if isinstance(id_val, list) else "object",
                                           id_val),
                        })
                        continue
                    recorded_ids.add(_typed_id_key(id_val))
                # T140 Round 3 review finding R3-I1(a) (section 11.4.201(6)
                # FALSE-NULL, fixed here -- a sibling gap of Round 2's I2(F) in
                # this SAME function that fix did not reach): a non-dict
                # ground-truth entry used to be silently `continue`d past
                # entirely. DEC-34 requires every genuinely-occurred effect be
                # cross-checked against `effects_performed`; this tool cannot
                # read a `kind`/`id` off a non-dict value, so it cannot rule out
                # that entry naming an effect absent from `effects_performed` --
                # exactly the same "cannot inspect, therefore cannot confirm
                # safe" reasoning check (2)'s already-fixed `malformed-external-
                # dependency` class and this check's own `unreadable-ground-truth`
                # class apply. Fail CLOSED instead (section 11.4.101) with its
                # own distinct "malformed-ground-truth-entry" reason, naming the
                # raw malformed value.
                #
                # Per R3-I1(c) above, a ground-truth entry whose OWN `id` is
                # None/missing is UNMATCHABLE against `recorded_ids` (which now
                # never contains None) -- it therefore correctly and honestly
                # falls through to the existing `unrecorded-external-effect`
                # branch below (this tool cannot confirm an id-less effect was
                # ever recorded, so it must be treated as unrecorded), never a
                # silent match.
                for e in ground_truth:
                    if not isinstance(e, dict):
                        reasons.append({
                            "class": "malformed-ground-truth-entry",
                            "detail": ("ground_truth_effects.json entry is not a JSON object "
                                       "(got %r) -- this tool cannot read a kind/id off a non-dict "
                                       "value, so it cannot rule out that this entry names an "
                                       "effect absent from effects_performed; treat as unsafe "
                                       "until independently, manually re-verified") % (e,),
                        })
                        continue
                    gt_id = e.get("id")
                    # T140 Round 4 review finding R4-I1 (section 11.4.201(6)
                    # FALSE-NULL, fixed here): a ground-truth entry's own `id`
                    # field being a JSON array or object (e.g. `["x"]`) is
                    # UNHASHABLE and used to crash this tool uncaught
                    # (`TypeError: unhashable type: 'list'`) at the
                    # `not in recorded_ids` membership test below. Extend the
                    # ALREADY-EXISTING "malformed-ground-truth-entry" class
                    # (rather than mint a new one, since this IS still a
                    # malformed ground-truth entry -- just one that is a dict
                    # with a malformed `id`, rather than not a dict at all) with
                    # a SECOND, distinct detail variant that distinguishes
                    # "not a dict" (above) from "dict, but its `id` field has
                    # the wrong type" (below), matching check (2)'s
                    # malformed-external-dependency / check (3)'s
                    # malformed-pending-step precedent for the same
                    # not-a-dict-vs-wrong-type-field distinction.
                    if isinstance(gt_id, (list, dict)):
                        reasons.append({
                            "class": "malformed-ground-truth-entry",
                            "detail": ("ground_truth_effects.json entry is a JSON object but "
                                       "its `id` field is a JSON %s (got %r), which is "
                                       "unhashable and cannot be compared against "
                                       "effects_performed's recorded ids -- this tool cannot "
                                       "rule out that this entry names an effect absent from "
                                       "effects_performed; treat as unsafe until "
                                       "independently, manually re-verified") % (
                                           "array" if isinstance(gt_id, list) else "object",
                                           gt_id),
                        })
                        continue
                    if _typed_id_key(gt_id) not in recorded_ids:
                        reasons.append({
                            "class": "unrecorded-external-effect",
                            "detail": ("effect %s:%s genuinely occurred but is absent from "
                                       "effects_performed -- resume must not risk repeating "
                                       "it") % (e.get("kind"), gt_id),
                        })
        elif effects_performed:
            reasons.append({
                "class": "unverifiable-ground-truth",
                "detail": ("ground_truth_effects.json missing while effects_performed lists %d "
                           "effect(s) -- this tool has no independent source to confirm those are "
                           "ALL the effects that genuinely occurred; treat as unsafe until an "
                           "independent ground-truth source is supplied") % len(effects_performed),
            })
        else:
            reasons.append({
                "class": "unverifiable-ground-truth",
                "detail": ("ground_truth_effects.json missing and effects_performed is empty -- "
                           "an empty effects_performed does NOT prove no effect occurred (the "
                           "agent may have crashed before it ever recorded one in its own "
                           "handoff doc), so the absence of an independent ground-truth source "
                           "is ALWAYS an unverifiable gap, never proof there is nothing to "
                           "cross-verify; treat as unsafe until an independent ground-truth "
                           "source is supplied"),
            })

        # (5) INCONSISTENT TRANSITION: the recorded current phase is not a valid
        # next state given the phase the agent's own verified evidence last
        # actually confirmed it reached (skips more than one phase step with
        # zero verified evidence for the skipped phases).
        verified_phases = [v.get("phase") for v in (doc.get("verified") or [])
                            if isinstance(v, dict) and v.get("phase") in PHASE_ORDER]
        last_verified_phase = None
        if verified_phases:
            last_verified_phase = max(verified_phases, key=lambda p: PHASE_ORDER.index(p))
        cur_phase = doc.get("phase")
        if last_verified_phase and cur_phase in PHASE_ORDER:
            i_last = PHASE_ORDER.index(last_verified_phase)
            i_cur = PHASE_ORDER.index(cur_phase)
            if i_cur > i_last + 1:
                skipped = PHASE_ORDER[i_last + 1:i_cur]
                reasons.append({
                    "class": "inconsistent-transition",
                    "detail": "phase jumped from %s to %s, skipping %s with no verified evidence for those phases" % (
                        last_verified_phase, cur_phase, ", ".join(skipped)),
                })

        effects_not_to_repeat = [e.get("id") for e in (doc.get("effects_performed") or []) if isinstance(e, dict)]
    except fc_common.SAFE_EXCEPTIONS as exc:
        # T140 Round 5 review finding R5-I1(2) defense-in-depth catch-all
        # (see the comment immediately above the `try:` this closes for
        # the full rationale): a genuinely unanticipated malformed-shape
        # case reached here -- fail CLOSED with an honest, diagnosable
        # verdict naming the real exception + its type, and a genuinely
        # fresh --out write, rather than an uncaught crash (section
        # 11.4.101). Partial state any of checks (1)-(5) may have
        # accumulated into `reasons`/`reverify` before the exception fired
        # is deliberately DISCARDED (never merged into this verdict) --
        # once an assumption checks (1)-(5) rely on has been violated, any
        # reasons already appended were derived under that same violated
        # assumption and cannot be trusted either; this single
        # internal-error reason is the whole, honest verdict.
        #
        # T140 Round 6 review finding R6-I1 (section 11.4.250, WIDENED
        # here): was `(TypeError, ValueError)` -- too narrow, as Round 6
        # itself demonstrated (an uncaught OSError from a filesystem error
        # re-hashing a dependency tree, now ALSO closed granularly by its
        # own per-dependency fail-closed branch above, and an uncaught
        # ValueError from a non-finite JSON constant, now closed at parse
        # time above). Widened to the shared `fc_common.SAFE_EXCEPTIONS`
        # tuple (TypeError, ValueError, OSError, OverflowError) as
        # defense-in-depth for any FURTHER site inside checks (1)-(5) this
        # round's review did not individually enumerate (section 11.4.6:
        # neither the per-site fixes above nor this catch-all are claimed
        # exhaustive) -- the SAME shared tuple every sibling fastcycle
        # orchestration tool now ORs onto its own narrower except-clauses,
        # never a fourth independently-guessed one (section 11.4.227).
        body = {
            "handoff_id": doc.get("handoff_id"),
            "safe_to_resume_without_reverification": False,
            "unsafe_reasons": [{
                "class": "resume-check-internal-error",
                "detail": ("resume-check raised an uncaught %s while reasoning about this "
                           "record: %s -- this is a genuinely unanticipated malformed-shape "
                           "case the up-front shape check above did not enumerate (section "
                           "11.4.6: that check is not claimed exhaustive); treat as unsafe "
                           "until independently, manually re-verified") % (
                               type(exc).__name__, exc),
            }],
            "facts_needing_reverification": [],
            "effects_not_to_repeat": [],
        }
        # T140 Round 7 review finding R7-I5 (fixed here): this write site
        # was doubly unguarded -- it lives INSIDE this very
        # `except fc_common.SAFE_EXCEPTIONS` catch-all, so an OSError from
        # an unwritable --out here would previously have escaped even this
        # defense-in-depth branch, uncaught a second time.
        err = _write_report_or_usage_error("resume-check", a.out, body, SCHEMA_RESUME_CHECK,
                                            include_run_meta=True)
        if err is not None:
            return err
        diag("handoff: resume-check UNSAFE %s -- 1 reason(s): resume-check-internal-error "
              "(%s: %s)" % (a.handoff, type(exc).__name__, exc), file=sys.stderr)
        return EXIT_FINDING

    safe = (len(reasons) == 0)
    body = {
        "handoff_id": doc.get("handoff_id"),
        "safe_to_resume_without_reverification": safe,
        "unsafe_reasons": reasons,
        # T140 Round 5 review finding R5-I1 row 10 (section 11.4.250): the
        # up-front shape check above (`_check_affects_verified` via
        # `_hashable_scalar`) only guarantees every `affects_verified`
        # entry is a HASHABLE scalar (so `reverify.add()` never crashes) --
        # it does NOT guarantee every entry SHARES a mutually-comparable
        # type with every OTHER entry that may have been added to
        # `reverify` from a DIFFERENT external_deps entry (e.g. one dep
        # contributing the int 1, another contributing the str "a" --
        # both individually hashable, but `1 < "a"` still raises TypeError
        # under a bare `sorted()`). A per-list up-front homogeneity check
        # cannot catch this either, since the violation only exists ACROSS
        # entries once accumulated into the shared `reverify` set -- the
        # genuinely robust fix is at the OPERATION itself: sort by a
        # TYPE-TAGGED key so values are compared by `(type name, value)`
        # tuples -- Python only reaches the second tuple element when the
        # first (a string) already compares equal, so cross-type values
        # NEVER reach a raw `<` comparison against each other; the
        # resulting order is deterministic (grouped by type, then by
        # value within a type) even though it is a JSON list of mixed
        # scalar types, which `facts_needing_reverification` was never
        # otherwise guaranteed to avoid.
        #
        # T140 Round 6 review finding N1 (section 11.4.201(6) FALSE-NULL,
        # fixed here): EVERY `reverify.add(...)` call site above now stores
        # the TYPE-TAGGED `_typed_id_key(ref_id)` tuple (never the bare
        # `ref_id`) -- `reverify` was previously a `set()` of BARE values,
        # so `affects_verified: [1, true, 1.0, "1"]` silently deduped
        # `true`/`1.0` away (Python's `1 == True == 1.0` and all three hash
        # identically), producing an INCOMPLETE
        # `facts_needing_reverification` list with no trace anywhere that a
        # distinct id was ever dropped -- the SAME id-type-collision class
        # R5-I2 already fixed for the effects_performed<->
        # ground_truth_effects.json comparison, present here too in a
        # sibling code path that fix did not reach. `reverify` therefore now
        # holds `(type_name, value)` tuples throughout; sorting the tuples
        # directly (never re-wrapping an already-tuple element through
        # `_typed_id_key` a second time, which would nest it wrongly) is
        # already safe for the identical reason given above, and each
        # tuple's ORIGINAL value is unwrapped back out for the final list --
        # the output shape (a bare-scalar JSON list) is unchanged, only the
        # dedup/sort semantics are fixed.
        "facts_needing_reverification": [v for (_typ, v) in sorted(reverify)],
        "effects_not_to_repeat": effects_not_to_repeat,
    }
    # T140 Round 7 review finding R7-I5 (fixed here): the normal-path write,
    # same as the two shape-violation/internal-error write sites above.
    err = _write_report_or_usage_error("resume-check", a.out, body, SCHEMA_RESUME_CHECK, include_run_meta=True)
    if err is not None:
        return err

    if safe:
        diag("handoff: resume-check SAFE %s (handoff_id=%s)" % (a.handoff, doc.get("handoff_id")))
        return EXIT_OK
    diag("handoff: resume-check UNSAFE %s -- %d reason(s): %s"
          % (a.handoff, len(reasons), ", ".join(sorted({r["class"] for r in reasons}))), file=sys.stderr)
    return EXIT_FINDING


# ---------------------------------------------------------------------------
# --determinism-check (T140 Round 1 review finding I5, section 11.4.201(6):
# this file had NO determinism-check mechanism at all -- fixed here by
# adopting the SAME mechanism the already-landed sibling
# orchestration/custody_sweep.py implements for its own `--determinism-check`
# (C-003) -- re-invoke this SAME process as a subprocess twice with the same
# argv (minus the flag itself) and compare the resulting --out document's
# body_hash. This is this file's OWN independently-written copy of that
# pattern (never imported from custody_sweep.py -- this file has no import
# path to it, matching this file's own already-established per-file-
# primitive convention; section 11.4.227 "reuse the PATTERN, not necessarily
# the literal code, where no shared import site already exists").
#
# Exit 0 stable (both runs' body_hash match), 1 body_hash mismatch
# (nondeterministic), 4 a run produced no honest verdict (timed out, crashed,
# or wrote no --out document) -- identical exit-code contract to
# custody_sweep.py's own run_determinism_check.
#
# HONEST BOUNDARY (section 11.4.6, mirroring custody_sweep.py's own
# documented `inventory --determinism-check` boundary verbatim in spirit):
# `write`'s own `written_at` field is, BY DESIGN (module docstring:
# "time_source ... is always event_occurred ... a phase-boundary write is,
# by construction, the moment the event it describes occurred"), the REAL
# wall-clock instant of each invocation -- so `write --determinism-check` is
# EXPECTED to report nondeterministic (rc=1) across two back-to-back
# subprocess invocations whenever they do not land in the exact same wall-
# clock second, because `written_at` (and therefore `handoff_id` and the
# report's own `body_hash`) genuinely differs. This is a REAL property of
# `write`'s own documented contract, never a defect in this mechanism.
# `validate`/`verify`/`resume-check`/`resume` are pure functions of the
# already-written `--handoff` file's bytes on disk and carry no live-clock
# dependency of their own, so they are expected to report deterministic
# (rc=0) on a genuinely-static, unchanging fixture.
# ---------------------------------------------------------------------------
def run_determinism_check(argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    runs = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                diag("handoff: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (EXIT_OK, EXIT_FINDING) or not os.path.exists(out_i):
                # T140 Round 10 review finding I1(c) (fixed here): a raw
                # `sys.stderr.write(...)` bypassed the diag()/emit_result()
                # channel split entirely -- with stderr unwritable (e.g.
                # `2>/dev/full`), this line raised uncaught, escaping past
                # every boundary below and producing the SAME undocumented
                # rc=120 class this round's other findings close elsewhere.
                # The failed child's own stderr text is this tool's own
                # diagnostic explanation of WHY --determinism-check itself
                # reports "no honest verdict" (it is never a --out document
                # of its own -- `--determinism-check` writes no top-level
                # --out at all, see this function's own header comment), so
                # it belongs on the SAME diagnostic channel as the line
                # immediately below it, never the primary one. `end=""`
                # matches the retired raw `.write()` call exactly -- `diag`
                # adds no trailing newline of its own beyond what
                # `proc.stderr` already carries.
                diag(proc.stderr, end="", file=sys.stderr)
                diag("handoff: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        diag("handoff: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    diag("handoff: deterministic (body_hash=%s)" % runs[0])
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _add_handoff_out_args(sp):
    sp.add_argument("--handoff", required=True)
    sp.add_argument("--out", required=True)


def build_arg_parser():
    # T140 Round 9b review finding R9b-I1 (fixed here): `__doc__` is `None`
    # under `python -OO`/`PYTHONOPTIMIZE=2` (docstrings are stripped from
    # compiled bytecode at that optimization level) -- `__doc__.split(...)`
    # then raised an uncaught `AttributeError` HERE, before ANY of this
    # function's own argument definitions ran, escaping `main()` entirely
    # (see `main()`'s own boundary widening below, point 1 of this round's
    # prescription, for the defense-in-depth half of this same fix).
    # `(__doc__ or "")` makes this call site itself simply never crash,
    # independent of whether something else would also catch it if it did.
    #
    # T140 Round 10 review finding I1(a) (fixed here): `FcArgumentParser`
    # (not the stdlib `argparse.ArgumentParser` directly) routes argparse's
    # own `--help`/usage-error message printing through `diag()` instead of
    # a raw `file.write(...)` -- see `fc_entry.FcArgumentParser`'s own
    # docstring for the full rationale (this was the ONE remaining raw-
    # write path into argparse-owned code, previously uncovered by any
    # boundary in this file, however wide).
    p = FcArgumentParser(prog="handoff.py", description=(__doc__ or "").split("\n\n")[0])
    p.add_argument("--determinism-check", action="store_true",
                   help="re-invoke this same subcommand twice and compare body_hash (C-003)")
    sub = p.add_subparsers(dest="cmd_name", required=True)

    w = sub.add_parser("write")
    w.add_argument("--item-id", required=True)
    w.add_argument("--agent-key", required=True)
    w.add_argument("--alias", required=True)
    w.add_argument("--model", required=True)
    w.add_argument("--effort", required=True)
    w.add_argument("--phase", required=True)
    w.add_argument("--verified", nargs="*", default=[])
    w.add_argument("--pending-json", default="[]")
    w.add_argument("--partial-artefacts", nargs="*", default=[])
    w.add_argument("--external-deps-json", default="[]")
    w.add_argument("--effects-performed-json", default="[]")
    _add_handoff_out_args(w)

    v = sub.add_parser("validate")
    _add_handoff_out_args(v)

    # HO-002's own contract wording ("`verify` re-hashes them..."); identical
    # behaviour to `validate` -- see module docstring HONEST NOTE.
    vf = sub.add_parser("verify")
    _add_handoff_out_args(vf)

    # Contract's own Components-line wording ("resume-check").
    rc = sub.add_parser("resume-check")
    _add_handoff_out_args(rc)

    # T134's own task-line wording ("Implement `handoff.py resume` ..."); the
    # SAME naming-ambiguity precedent T133 already established for
    # validate/verify -- identical behaviour to `resume-check`, see module
    # docstring HONEST NOTE.
    r = sub.add_parser("resume")
    _add_handoff_out_args(r)

    return p


def _write_dispatch_internal_error_doc(out_path, subcommand, exc):
    """T140 Round 7 review (section 11.4.250 heuristic-tower/primitive-
    defect -- mirrors `custody_sweep.py`'s/`limit_class.py`'s own
    identically-purposed helper, section 11.4.227 reuse-the-SAME-
    discipline): on ANY exception escaping a subcommand handler and being
    caught by `main()`'s dispatch boundary below, this tool MUST still
    write SOME report document to --out (every one of this file's
    subcommands takes `--out`) rather than leaving a stale or entirely
    absent --out file -- the audit trail (section 11.4.5/11.4.69) is
    never silently lost regardless of what crashed. Reuses
    `write_report_atomic` (never a second writer) -- this file's own
    established report-doc convention (schema + body_hash + run_meta, per
    the module docstring). Best-effort: a write failure here is itself
    swallowed (never raised a second time out of an already-failing
    error path) -- the caller's stderr diagnostic in main() is what
    remains authoritative in that doubly-unlucky case.

    T140 Round 8 review finding R8-I1(d) (fixed here): was `except
    OSError` alone -- widened to bare `Exception`, the SAME widening
    `main()`'s own dispatch boundary below receives and
    `_write_report_or_usage_error`'s own sibling fix above receives, so
    this best-effort write can never itself escape with a different,
    still-uncaught exception class.

    T140 Round 9 review finding R9-M1 (fixed here): `str(exc)` replaced
    with `safe_str(exc)` -- see that function's own docstring."""
    if not out_path:
        return
    body = {"subcommand": subcommand, "internal_error": {"class": type(exc).__name__, "detail": safe_str(exc)}}
    try:
        write_report_atomic(out_path, body, SCHEMA_INTERNAL_ERROR, include_run_meta=True)
    except Exception:
        pass


# T140 Round 11 review finding I3 (fixed here): once argv has PARSED,
# this invocation's --out is genuinely this run's designated output --
# a stale document from an earlier run must not survive ANY handled
# exit (a rc=1 refusal / rc=2 config error that writes nothing used to
# leave the PREVIOUS run's verdict there, looking current; C-001). Done
# in the dispatch wrapper (every table entry), immediately before the
# handler runs. A pure argparse usage error (SystemExit before any
# handler) still leaves --out untouched, per Round 10 finding M3
# (guarded by test_handoff_r9_regression.sh).
def _fresh_out(handler):
    def run(a):
        invalidate_stale_out(getattr(a, "out", None))
        return handler(a)
    return run


def main(argv):
    if "--determinism-check" in argv:
        # T140 Round 8 review finding R8-I1 minor (a) (fixed here):
        # `run_determinism_check` used to run entirely OUTSIDE this
        # function's own dispatch boundary. Wrapped in the SAME bare
        # `except Exception` this function's own subcommand dispatch below
        # now uses (section 11.4.227 reuse-not-reinvention) -- no single
        # caller-level `--out` document exists to write an internal-error
        # doc to here (each subprocess run already writes its OWN --out
        # inside a throwaway temp dir, per `run_determinism_check`'s own
        # body), so this boundary is diagnostic-message-only.
        try:
            return run_determinism_check(argv)
        except Exception as exc:
            diag("handoff: --determinism-check raised an uncaught %s: %s -- this is a genuinely "
                  "unanticipated case; treat as unsafe/unverified until independently, manually "
                  "re-verified" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
            return EXIT_USAGE

    table = {
        "write": _fresh_out(cmd_write),
        "validate": _fresh_out(cmd_validate),
        "verify": _fresh_out(cmd_validate),
        "resume-check": _fresh_out(cmd_resume_check),
        "resume": _fresh_out(cmd_resume_check),
    }
    args = None
    cmd_name = None
    try:
        # T140 Round 9b review finding R9b-I1 (fixed here, point 1 of that
        # round's own prescription): argument-parser CONSTRUCTION and
        # PARSING now live INSIDE this SAME dispatch boundary, not before
        # it. A crash reaching here from `build_arg_parser()`/
        # `parse_args()` itself (live-proven: the `__doc__.split()`
        # AttributeError under `python -OO`/`PYTHONOPTIMIZE=2`,
        # independently fixed at its own source in `build_arg_parser()`
        # above via `(__doc__ or "")`, point 2) used to escape this
        # function ENTIRELY uncaught with a bare rc=1 and no
        # internal-error document at all -- widened per section 11.4.227
        # reuse-the-SAME-discipline as every other boundary widening in
        # this file's history (Round 7's bare-Exception widening, Round
        # 8's whole-`--determinism-check`-branch wrap). `SystemExit`
        # (argparse's own `--help`/usage-error path) is NOT a subclass of
        # `Exception`, so it is unaffected by this widening and still
        # propagates exactly as before.
        args = build_arg_parser().parse_args(argv)
        cmd_name = args.cmd_name
        return table[cmd_name](args)
    except Exception as exc:
        # T140 Round 7 review, the ONE top-level dispatch boundary wrapping
        # EVERY subcommand this file dispatches to (see
        # _write_dispatch_internal_error_doc's own docstring immediately
        # above): a genuinely unanticipated crash reaching here -- one none
        # of R7-I5's own specific, diagnosable fixes above enumerated --
        # still fails CLOSED with an honest, diagnosable message, a real
        # --out write, and this tool's own established EXIT_USAGE(2)
        # convention, rather than an uncaught crash landing on Python's own
        # default exit code 1 (indistinguishable from this tool's own
        # EXIT_FINDING(1) -- INVALID/UNSAFE/missing-partial-artefact).
        #
        # T140 Round 8 review finding R8-I1 (WIDENED here): was `except
        # fc_common.SAFE_EXCEPTIONS` -- Round 8's own live fuzzing (5,000
        # random-field-mutation variants, verified first against a
        # deliberately-broken script to confirm it genuinely catches
        # crashes) proved this narrower catch set
        # (TypeError/ValueError/OSError/OverflowError) still let
        # `KeyError`/`IndexError`/`AttributeError`/`RecursionError` escape
        # uncaught in this file -- proven live by injecting a `KeyError`
        # at the very TOP of `cmd_validate` (before ANY of its own
        # internal try/excepts could run). Widened to bare `Exception` --
        # deliberately NEVER `BaseException`: `SystemExit`/
        # `KeyboardInterrupt` are NOT subclasses of `Exception` (Python's
        # own exception hierarchy places both directly under
        # `BaseException`), so an operator interrupt or this process's own
        # `sys.exit()` correctly stays UNCAUGHT here, exactly as before
        # this widening. `fc_common.SAFE_EXCEPTIONS` itself is UNCHANGED
        # (still the narrower, shared floor every sibling tool's own
        # per-site except-clauses OR onto) -- only this ONE top-level
        # dispatch boundary is widened, the fix Round 8's own review
        # recommended directly: "the fix is to change what the boundary
        # catches to `Exception`, not to add one more type to the list."
        #
        # T140 Round 9/9b review (fixed here): `out_path`/`cmd_name`
        # resolve honestly even when `args` was never successfully
        # parsed (a build_arg_parser()/parse_args() crash) -- falling
        # back to the raw-argv scan / `None` respectively -- and the
        # --out document write now happens BEFORE the diagnostic print
        # (point 4), through `diag` (never able to escape and
        # trigger a SECOND, corrupting boundary re-entry -- there is only
        # ever one boundary here, but a raising print previously escaped
        # main() ENTIRELY, past this very except clause, to the
        # interpreter's own top-level uncaught-exception handler).
        #
        # T140 Round 10 review finding M3, first half (fixed here): the
        # `invalidate_stale_out(scan_argv_for_out(argv))` call this file's
        # own `main()` used to run UNCONDITIONALLY at the very top, before
        # any argument parsing was even attempted, is now made ONLY here --
        # the ONE place a genuinely unanticipated crash (never a clean
        # argparse usage error, which raises `SystemExit` and is NEVER
        # caught by this `except Exception` clause) is actually being
        # handled, immediately before this tool is about to write its own
        # fresh internal-error document to `out_path` anyway. A pure usage
        # error (e.g. a required flag genuinely missing) no longer deletes
        # a caller's pre-existing, wholly UNRELATED `--out` file merely
        # because a command line was typed -- this tool is "confident it's
        # about to genuinely attempt the operation" only at exactly this
        # point, never merely on invocation (live-reproduced:
        # `validate --out keep.txt` with no `--handoff` previously deleted
        # `keep.txt` even though `validate` never ran at all).
        out_path = getattr(args, "out", None) if args is not None else scan_argv_for_out(argv)
        invalidate_stale_out(out_path)
        _write_dispatch_internal_error_doc(out_path, cmd_name, exc)
        diag("handoff: subcommand %r raised an uncaught %s while dispatching: %s -- this is a "
              "genuinely unanticipated case no individual fix above enumerated; treat as "
              "unsafe/unverified until independently, manually re-verified"
              % (cmd_name, type(exc).__name__, safe_str(exc)), file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    # T140 Round 10 review, "Recommended root-cause work" item 1 (fixed
    # here): `run_cli_main` -- never `sys.exit(main(sys.argv[1:]))` --
    # closes T140 Round 10 review finding I1(b) (stdout block-buffering /
    # interpreter-shutdown flush corrupting a clean exit code into an
    # undocumented one) at the OUTERMOST process boundary; see
    # `fc_entry.run_cli_main`'s own docstring for the full mechanism.
    run_cli_main(main, sys.argv[1:])
