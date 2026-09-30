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
       handoff's own `effects_performed` is flagged. Absence of the sibling
       file is an honest skip of this one check (section 11.4.3), never a
       fabricated finding -- the other four checks still run.
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

    base_dir = os.path.dirname(os.path.abspath(a.handoff)) or "."
    reasons = []
    reverify = set()

    # (1) INCONSISTENT INTERNAL STATE: a verified fact's own established_at
    # is causally AFTER the handoff's own written_at (the record could not
    # have known about a fact from its own future), OR the phase is declared
    # terminal while pending work remains outstanding.
    written_at = doc.get("written_at")
    for v in (doc.get("verified") or []):
        if not isinstance(v, dict):
            continue
        established_at = v.get("established_at")
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
    for dep in (doc.get("external_deps") or []):
        if not isinstance(dep, dict):
            continue
        kind = dep.get("kind")
        if kind == "git-tree":
            current_dir = os.path.join(base_dir, "tree_current", dep.get("locator") or "")
            live_hash = _merkle_over_dir(current_dir)
            recorded = dep.get("content_address")
            if live_hash != recorded:
                reasons.append({
                    "class": "stale-external-dependency",
                    "detail": "external dep %s content_address changed: recorded=%s live=%s" % (
                        dep.get("locator"), recorded, live_hash),
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
    for step in (doc.get("pending") or []):
        if not isinstance(step, dict):
            continue
        text = ((step.get("step") or "") + " " + (step.get("precondition") or "")).lower()
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
    # actually needed. That is now narrowed: absence of the sibling file is
    # an honest, this-check-genuinely-does-not-apply skip ONLY when
    # `effects_performed` is empty (nothing in the record claims an effect
    # occurred, so there is nothing this check could have cross-verified
    # either way); when `effects_performed` is non-empty, a missing sibling
    # means this tool has NO independent way to confirm the record's own
    # effect claims are complete -- fail CLOSED (section 11.4.101) with an
    # explicit reason, never silently absorbed as safe.
    effects_performed = doc.get("effects_performed") or []
    gt_path = os.path.join(base_dir, "ground_truth_effects.json")
    if os.path.isfile(gt_path):
        try:
            with open(gt_path, encoding="utf-8") as fh:
                ground_truth = json.load(fh)
        except (OSError, ValueError):
            ground_truth = []
        recorded_ids = {e.get("id") for e in effects_performed if isinstance(e, dict)}
        for e in (ground_truth or []):
            if not isinstance(e, dict):
                continue
            if e.get("id") not in recorded_ids:
                reasons.append({
                    "class": "unrecorded-external-effect",
                    "detail": ("effect %s:%s genuinely occurred but is absent from "
                               "effects_performed -- resume must not risk repeating it") % (
                                   e.get("kind"), e.get("id")),
                })
    elif effects_performed:
        reasons.append({
            "class": "unverifiable-ground-truth",
            "detail": ("ground_truth_effects.json missing while effects_performed lists %d "
                       "effect(s) -- this tool has no independent source to confirm those are "
                       "ALL the effects that genuinely occurred; treat as unsafe until an "
                       "independent ground-truth source is supplied") % len(effects_performed),
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

    safe = (len(reasons) == 0)
    body = {
        "handoff_id": doc.get("handoff_id"),
        "safe_to_resume_without_reverification": safe,
        "unsafe_reasons": reasons,
        "facts_needing_reverification": sorted(reverify),
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
