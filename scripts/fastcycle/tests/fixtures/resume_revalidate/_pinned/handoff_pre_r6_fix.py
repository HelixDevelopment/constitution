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

canon = fc_common.canon

SCHEMA_HANDOFF = "handoff/v1"
SCHEMA_WRITE = "handoff-write/v1"
SCHEMA_VALIDATE = "handoff-validate/v1"
SCHEMA_RESUME_CHECK = "handoff-resume-check/v1"

EXIT_OK = 0
EXIT_FINDING = 1   # write: a declared partial-artefact path is missing; validate/verify: INVALID; resume/resume-check: UNSAFE
EXIT_USAGE = 2

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


def _json_list_arg(text, name):
    """Parses `text` as JSON, requiring the result to be a list. Returns
    (value, None) on success or (None, error-message) on failure -- callers
    print the message and exit EXIT_USAGE, never crash on a malformed
    caller-supplied blob."""
    try:
        val = json.loads(text)
    except ValueError as exc:
        return None, "bad JSON for %s: %s" % (name, exc)
    if not isinstance(val, list):
        return None, "%s must be a JSON list" % name
    return val, None


# ---------------------------------------------------------------------------
# write (HO-001)
# ---------------------------------------------------------------------------
def cmd_write(a):
    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."

    pending, err = _json_list_arg(a.pending_json, "--pending-json")
    if err:
        print("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    external_deps, err = _json_list_arg(a.external_deps_json, "--external-deps-json")
    if err:
        print("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    effects_performed, err = _json_list_arg(a.effects_performed_json, "--effects-performed-json")
    if err:
        print("handoff: %s" % err, file=sys.stderr)
        return EXIT_USAGE

    # partial_artefacts: bare declared paths, content addresses COMPUTED here
    # from real, live bytes (never trusted from the caller) -- resolved
    # relative to dirname(--handoff), the SAME base-dir convention validate/
    # verify uses (see module docstring).
    partial_artefacts = []
    for rel in a.partial_artefacts:
        full = os.path.join(base_dir, rel)
        if not os.path.isfile(full):
            print("handoff: write refused -- declared --partial-artefacts path does not "
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

    write_json_atomic(a.handoff, doc)

    report_body = {
        "handoff_id": handoff_id,
        "handoff_path": a.handoff,
        "item_id": a.item_id,
        "agent_key": a.agent_key,
        "phase": a.phase,
        "partial_artefact_count": len(partial_artefacts),
    }
    write_report_atomic(a.out, report_body, SCHEMA_WRITE, include_run_meta=True)

    print("handoff: write wrote %s (handoff_id=%s, item_id=%s, phase=%s)"
          % (a.handoff, handoff_id, a.item_id, a.phase))
    return EXIT_OK


# ---------------------------------------------------------------------------
# validate / verify (HO-001 self-integrity + HO-002 partial-artefact
# re-hash). Both subparsers dispatch here -- see module docstring HONEST NOTE.
# ---------------------------------------------------------------------------
def cmd_validate(a):
    if not os.path.isfile(a.handoff):
        print("handoff: --handoff not found: %s" % a.handoff, file=sys.stderr)
        return EXIT_USAGE
    try:
        with open(a.handoff, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("handoff: cannot read --handoff: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(doc, dict):
        print("handoff: --handoff is not a JSON object", file=sys.stderr)
        return EXIT_USAGE

    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."
    mismatches = []

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
    for art in (doc.get("partial_artefacts") or []):
        path = art.get("path") if isinstance(art, dict) else None
        full = os.path.join(base_dir, path) if path else None
        if not full or not os.path.isfile(full):
            mismatches.append("partial_artefact:%s:missing" % path)
            continue
        live_ca = content_address(full)
        if live_ca != art.get("content_address"):
            mismatches.append("partial_artefact:%s" % path)

    outcome = "INVALID" if mismatches else "VALID"
    body = {"outcome": outcome, "mismatches": mismatches}
    write_report_atomic(a.out, body, SCHEMA_VALIDATE, include_run_meta=True)

    if outcome == "VALID":
        print("handoff: validate VALID %s" % a.handoff)
        return EXIT_OK
    print("handoff: validate INVALID %s -- mismatches: %s"
          % (a.handoff, ", ".join(mismatches)), file=sys.stderr)
    return EXIT_FINDING


# ---------------------------------------------------------------------------
# resume / resume-check (HO-003 + T126's own five-class "Safe to Resume?"
# extension). Both subparsers dispatch here -- see module docstring HONEST
# NOTE (mirrors the write/validate `validate`/`verify` naming-ambiguity
# precedent T133 already established for this same file).
#
# `_merkle_over_dir` is this file's OWN small, independently-written
# reimplementation of the data-model.md §0 `MerkleRoot` convention
# (Reuse, not reinvention, section 11.4.227 -- see module docstring): it
# reuses the ALREADY-IMPORTED `canon()` for its own canonicalization step,
# the same convention `context/evidence_ref.py`'s own `merkle_root()` and
# T126's own RED-test oracle each independently apply, but is never imported
# from either of those two files (Producer != Verifier, section 11.4.240,
# for the test oracle; this file's own already-established per-file-primitive
# convention -- see `content_address()` above -- for `evidence_ref.py`).
# ---------------------------------------------------------------------------
def _merkle_over_dir(root):
    """sha256: over the sorted list of (relative-path, ContentAddress) pairs
    of every file under `root` (data-model.md §0 MerkleRoot; "pairs sorted
    bytewise by path; empty set is a distinct, valid root"). A non-existent
    `root` yields the empty-set root -- an honest, real ContentAddress that
    will (correctly) mismatch any non-empty recorded one, never a crash."""
    pairs = []
    if os.path.isdir(root):
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                pairs.append((rel.replace(os.sep, "/"), content_address(full)))
    pairs.sort(key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in pairs]
    return "sha256:" + hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


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
        print("handoff: --handoff not found: %s" % a.handoff, file=sys.stderr)
        return EXIT_USAGE
    try:
        with open(a.handoff, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("handoff: cannot read --handoff: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(doc, dict):
        print("handoff: --handoff is not a JSON object", file=sys.stderr)
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
        write_report_atomic(a.out, body, SCHEMA_RESUME_CHECK, include_run_meta=True)
        print("handoff: resume-check UNSAFE %s -- 1 reason(s): %s"
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
                    reverify.add(ref_id)
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
                        reverify.add(ref_id)
                    continue
                current_dir = os.path.join(base_dir, "tree_current", locator or "")
                live_hash = _merkle_over_dir(current_dir)
                recorded = dep.get("content_address")
                if live_hash != recorded:
                    reasons.append({
                        "class": "stale-external-dependency",
                        "detail": "external dep %s content_address changed: recorded=%s live=%s" % (
                            locator, recorded, live_hash),
                    })
                    for ref_id in (dep.get("affects_verified") or []):
                        reverify.add(ref_id)
            else:
                reasons.append({
                    "class": "unverifiable-external-dependency",
                    "detail": ("external dep %s has unrecognized dependency kind: %s -- this tool "
                               "cannot re-hash it, so it cannot be confirmed unchanged; treat as "
                               "unsafe until independently, manually re-verified") % (
                                   dep.get("locator"), kind),
                })
                for ref_id in (dep.get("affects_verified") or []):
                    reverify.add(ref_id)

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
                    parsed = json.load(fh)
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
    except (TypeError, ValueError) as exc:
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
        write_report_atomic(a.out, body, SCHEMA_RESUME_CHECK, include_run_meta=True)
        print("handoff: resume-check UNSAFE %s -- 1 reason(s): resume-check-internal-error "
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
        # TYPE-TAGGED key (`_typed_id_key`, the SAME helper R5-I2 uses for
        # id matching) so values are compared by `(type name, value)`
        # tuples -- Python only reaches the second tuple element when the
        # first (a string) already compares equal, so cross-type values
        # NEVER reach a raw `<` comparison against each other; the
        # resulting order is deterministic (grouped by type, then by
        # value within a type) even though it is a JSON list of mixed
        # scalar types, which `facts_needing_reverification` was never
        # otherwise guaranteed to avoid.
        "facts_needing_reverification": sorted(reverify, key=_typed_id_key),
        "effects_not_to_repeat": effects_not_to_repeat,
    }
    write_report_atomic(a.out, body, SCHEMA_RESUME_CHECK, include_run_meta=True)

    if safe:
        print("handoff: resume-check SAFE %s (handoff_id=%s)" % (a.handoff, doc.get("handoff_id")))
        return EXIT_OK
    print("handoff: resume-check UNSAFE %s -- %d reason(s): %s"
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
                print("handoff: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (EXIT_OK, EXIT_FINDING) or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("handoff: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        print("handoff: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    print("handoff: deterministic (body_hash=%s)" % runs[0])
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _add_handoff_out_args(sp):
    sp.add_argument("--handoff", required=True)
    sp.add_argument("--out", required=True)


def build_arg_parser():
    p = argparse.ArgumentParser(prog="handoff.py", description=__doc__.split("\n\n")[0])
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


def main(argv):
    if "--determinism-check" in argv:
        return run_determinism_check(argv)
    args = build_arg_parser().parse_args(argv)
    table = {
        "write": cmd_write,
        "validate": cmd_validate,
        "verify": cmd_validate,
        "resume-check": cmd_resume_check,
        "resume": cmd_resume_check,
    }
    return table[args.cmd_name](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
