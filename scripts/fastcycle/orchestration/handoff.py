#!/usr/bin/env python3
"""handoff.py - Handoff Record write/validate (spec-004 "fast-dev-cycles",
User Story 5, T133, plan task T-B04, contract
contracts/agent-registry-and-handoff.md clauses HO-001 (write) and HO-002
(preserve/re-hash), data-model.md §9.2 "Handoff Record", research.md DEC-34).

TDD-FIX target: this file turns T125's RED baseline
(`constitution/scripts/fastcycle/tests/test_handoff_red.sh`, fixtures under
`constitution/scripts/fastcycle/tests/fixtures/handoff/`) GREEN. It does NOT
implement `resume-check`/HO-003 (re-hashing `external_deps`, invalidating
dependent `verified` facts, the five "Safe to Resume?" failure modes) --
that is T126/T-B05's own, separate, later task against its own RED test
(`test_resume_revalidate_red.sh`), never duplicated or pre-empted here
(fixtures/handoff/README.md's own "What this RED test does NOT cover"
section, and T125's own header, both say the same). Calling
`handoff.py resume-check ...` today is therefore an ordinary argparse usage
error (exit 2, "invalid choice") -- an honest gap, not a fake stub.

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

Exit codes (contract "Exit codes" line, verbatim: "Handoff: 0 ok, 1 hash
mismatch / missing field"): `write` 0 ok / 1 a declared `--partial-artefacts`
path does not exist ("missing field") / 2 usage (bad/unreadable args,
malformed `--*-json`). `validate`/`verify` 0 VALID / 1 INVALID (self-integrity
mismatch or a partial-artefact hash mismatch/missing file -- HO-002's "exits
1 on any difference") / 2 usage (`--handoff` missing/unreadable/not a JSON
object). Neither subcommand here can produce a BLIND (4) verdict -- both
operate entirely on locally-supplied, already-resolved inputs, unlike
`resume-check`'s (T126's) re-hash of external state which genuinely can be
unreachable.

Reuse, not reinvention (section 11.4.227): `canon`/`body_hash_of` are
imported from the already-landed sibling `lib/fc_common.py`, the identical
import-by-path pattern every other fastcycle tool in this tree uses
(`context/evidence_ref.py`, `context/anchor_citations.py`, and others per
that file's own module docstring); never reimplemented here.

Producer != Verifier (section 11.4.240): this file is T133's implementation
of the SEPARATE, EARLIER T125 RED test's own independent
`derive_validate()` oracle (`test_handoff_red.sh`); that oracle is never
imported by, shared with, nor coupled to this file, and this file never
imports from that test -- the two are authored independently against the
same contract/README text and are expected to agree because both correctly
implement it, never because one delegates to the other.

Stdlib only. Python 3.
"""
import argparse
import datetime
import hashlib
import json
import os
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

EXIT_OK = 0
EXIT_FINDING = 1   # write: a declared partial-artefact path is missing; validate/verify: INVALID
EXIT_USAGE = 2


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
# CLI
# ---------------------------------------------------------------------------
def _add_handoff_out_args(sp):
    sp.add_argument("--handoff", required=True)
    sp.add_argument("--out", required=True)


def build_arg_parser():
    p = argparse.ArgumentParser(prog="handoff.py", description=__doc__.split("\n\n")[0])
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

    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)
    table = {"write": cmd_write, "validate": cmd_validate, "verify": cmd_validate}
    return table[args.cmd_name](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
