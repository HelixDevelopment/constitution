#!/usr/bin/env python3
"""evidence_ref.py - Evidence Reference create/consume/reverify (spec-004
"fast-dev-cycles", User Story 4, T117, plan task T-E05, contract
contracts/evidence-reference-reverify.md ER-000..ER-005, data-model.md §8
"Evidence Reference", research.md DEC-29).

Purpose: let a later step (or a resumed agent) consume a fact an earlier
step verified, re-verifying only when something that fact depends on
actually changed -- the Bazel action-digest model applied to agent evidence
(R5 rec. 3). The reference store is the EXISTING §11.4.268 evidence chain /
§11.4.207 content-addressed store (DEC-29) -- this file does not invent a
new store, only the record shape traveling through it.

Invocation (contract "Invocation" section, verbatim flag names):
    evidence_ref.py create  --fact "<one sentence>" --verifier <id> \\
        --inputs <paths...> [--target <serial>] --verdict PASS|FAIL \\
        --evidence <path> --out <ref.json>
    evidence_ref.py consume --ref <ref.json> [--target <serial>] \\
        --out <consume.json>     # REUSED | REVERIFY_REQUIRED | STALE_EVIDENCE
    evidence_ref.py reverify --ref <ref.json> --out <newref.json>
                                  # runs the verifier, supersedes the ref

Path resolution (UNCONFIRMED by the contract -- DEFINED here, matching the
established fixtures/evidence_ref/README.md convention, binding-if-adopted):
every path this tool reads or hashes (`--inputs`/`--verifier`/`--evidence`
for `create`; every `inputs.paths[]`/`verifier_id`/`evidence.path` a
`ref.json` declares, for `consume` and `reverify`) is resolved relative to
the DIRECTORY THAT HOLDS THE REFERENCE -- for `create` that is the current
working directory the caller invokes this tool from (the directory `--out`
is written into, matching the fixture convention where every declared path
sits beside `ref.json` itself); for `consume`/`reverify` it is
`dirname(--ref)`, computed fresh from the CLI-supplied `--ref` path, never
guessed and never a separate `--scenario-dir` flag the contract's own
Invocation grammar does not carry.

Wire format (UNCONFIRMED by the contract itself -- DEFINED here,
binding-if-adopted, per the established fixtures/evidence_ref/README.md
precedent -- read that file for the full rationale; the summary):
  - `--verifier <id>` IS the verifier script's own repo-relative path;
    `verifier_version` = `content_address(that path's bytes at create/
    reverify time)`.
  - `ref.json` (schema `evref/v1`) carries BOTH the Merkle root AND the
    declared path list (`inputs: {paths: [...], root: "sha256:..."}`) plus
    the individual `(path, content_address)` pairs (`inputs.pairs`) so a
    per-path diff can name exactly what changed -- the aggregate root alone
    cannot.
  - Content addresses and Merkle roots are `"sha256:<64 hex>"`-prefixed
    (data-model.md §0's `ContentAddress`/`MerkleRoot` format); `body_hash`
    is the established `fc_common.py` C-002 convention's BARE 64-hex string
    (no prefix) -- two different, independently-real established formats,
    each used exactly where its own convention already defines it.
  - `changed_components` is the closed vocabulary DEFINED in
    fixtures/evidence_ref/README.md: `"inputs:<path>"`, `"verifier_version"`,
    `"target_fingerprint"`, `"target_fingerprint_unobserved"` (ER-005).
  - Merkle-root canonicalization reuses `fc_common.py`'s own `canon()`
    convention (never a bespoke serialization scheme, §11.4.227); pairs
    sort by the path string's raw UTF-8 bytes (data-model.md §0 "sorted
    bytewise by path"), never a locale-dependent string sort (C-003).
  - `ref.json` carries NO `run_meta` key -- matching the established fixture
    convention exactly (none of the six RED fixtures' `ref.json` documents
    carries one): a reference is a content-addressed FACT, reproducibly
    re-derivable from its own declared inputs, not a report of "this run's"
    own wall-clock/host (which is precisely the non-reproducible metadata
    C-002 designed `run_meta` to quarantine OUT of a hashed body in the
    first place -- a reference has nothing for `run_meta` to hold).
    `consume.json` (schema `evref-consume/v1`), by contrast, IS a report of
    a run of this tool and DOES carry `run_meta` (host), matching the
    established `write_out` convention every other fastcycle report tool
    already follows (cycle_report.py, escape_classify.py, reopen_rate.py).
  - `ref_id` has NO CLI flag in the contract's `create` Invocation line (nor
    does data-model.md §8 name one) -- §11.4.205(4) "a record written by a
    machine, never hand-typed" -- so it is TOOL-GENERATED here, content-
    addressed (consistent with DEC-29's own "Bazel action-digest model"
    framing): `"evref:" + sha256(canon(<every other create-time field>))
    [:24]`, computed BEFORE `ref_id` itself is inserted into the document
    (so it can never be circular), and DISTINCT from `body_hash` (which
    hashes the FULL document, `ref_id` included, per the established C-002
    convention every fastcycle tool already follows).
  - `established_at`/`established_by` likewise have no `create` CLI flags in
    the contract; `established_at` is tool-stamped (current UTC instant,
    §11.4.205(4)); `established_by` defaults to a tool-derived value
    (`evidence_ref.py:create@<hostname>`) unless the caller supplies the
    additive, non-contract, documented `--established-by` override.
  - `reverify`'s newref.json additionally carries `supersedes: <old ref_id>`
    (DEC-29/data-model.md §8: "re-verify... and supersede the reference") --
    an additive field beyond `create`'s own minimal shape, present ONLY on
    a reverify-produced reference.

ER-004 ("a ref whose verifier is an unrecorded LLM judgment is refused at
create") is enforced structurally, not by pattern-matching for "LLM-ness":
since this wire format's `verifier_version` is ALWAYS a content address of
REAL bytes at a REAL path (never an opaque string a caller merely asserts),
a `--verifier` value that does not resolve to an existing regular file
cannot produce that address at all -- exactly the class of thing ER-004
forbids (a verdict recorded against no fixed, replayable artefact). `create`
refuses (exit 1) in that case, citing ER-004.

Exit codes (contract "Exit codes" line, verbatim): `create` 0/1 (ER-004
refusal)/2 (usage); `consume` 0 REUSED, 1 REVERIFY_REQUIRED or
STALE_EVIDENCE, 4 target unreadable; `reverify` 0 new ref written (verdict
inside), 4 verifier failed to run (no verdict -- BLIND per C-001). A
malformed/unreadable `--ref`/`--verifier`/`--evidence`/`--inputs` path is a
usage error (exit 2, the universal C-001 row 2 convention every fastcycle
tool shares) in every subcommand, since the contract's own exit-code line
does not reserve 2 for a documented verdict class in any of the three.

Producer != Verifier (constitution §11.4.240): this file is T117's
implementation of the contract T108's RED test (a SEPARATE, EARLIER task)
independently derives from the SAME contract text; T108's own
`derive_consume()` oracle is never imported by, shared with, nor coupled to
this file (see test_evidence_ref_red.sh's own module docstring) -- the two
were authored independently against the same specification and are expected
to agree because both correctly implement it, not because one delegates to
the other.

Reuse, not reinvention (§11.4.227): `canon`/`body_hash_of` are imported
from the already-landed sibling `lib/fc_common.py` (C-002), the same
import-by-path pattern every other fastcycle tool in this tree uses
(escape_classify.py, reopen_rate.py, cycle_report.py, anchor_citations.py);
never reimplemented here.

`consume` NEVER invokes the verifier (ER-002: "recomputes every component
from current bytes / the live target" -- it re-hashes the verifier
SCRIPT'S OWN bytes to detect a changed `verifier_version`, it does not run
it; T108's task text: "assert via a verifier stub that records
invocations"). Only `reverify` runs the verifier, deliberately, to produce a
fresh verdict.

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
# import-by-path pattern to escape_classify.py / cycle_report.py / T039's own
# anchor_citations.py -- constitution/scripts/fastcycle has no __init__.py
# anywhere, matching this tree's existing flat-script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA_REF = "evref/v1"
SCHEMA_CONSUME = "evref-consume/v1"

EXIT_OK = 0
EXIT_FINDING = 1        # create: ER-004 refusal / consume: REVERIFY_REQUIRED or STALE_EVIDENCE
EXIT_USAGE = 2
EXIT_TARGET_UNREADABLE = 4  # consume (ER-005-adjacent; see cmd_consume)
EXIT_BLIND = 4              # reverify: verifier failed to run, no honest verdict (C-001 row 4)


# ---------------------------------------------------------------------------
# Shared primitives (data-model.md §0 ContentAddress / MerkleRoot).
# ---------------------------------------------------------------------------
def content_address(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def merkle_root(pairs):
    """data-model.md §0 MerkleRoot: 'sha256: over the sorted list of (path,
    ContentAddress) pairs ... sorted bytewise by path'. Reuses
    fc_common.canon() (constitution §11.4.227) per
    fixtures/evidence_ref/README.md's own 'Merkle root canonicalization'
    section -- never a bespoke serialization scheme."""
    sorted_pairs = sorted(pairs, key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in sorted_pairs]
    return "sha256:" + hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def compute_input_pairs(base_dir, declared_paths):
    """Recomputes (path, ContentAddress) for every declared path, resolved
    relative to base_dir. Raises FileNotFoundError for a missing path --
    callers decide how to classify that (create/reverify refuse; consume
    treats it as a changed input, see cmd_consume)."""
    pairs = []
    for p in declared_paths:
        full = os.path.join(base_dir, p)
        pairs.append((p, content_address(full)))
    return pairs


def _now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _hostname():
    return os.uname().nodename if hasattr(os, "uname") else "unknown"


def write_doc_atomic(out_path, body, schema, include_run_meta):
    """Write-temp-then-rename (§11.4.205(6)), identical pattern to the
    already-landed sibling escape_classify.py's write_out / cycle_report.py.
    C-002 body_hash covers the full doc (schema + every body field,
    EXCLUDING run_meta/body_hash themselves per fc_common.EXCLUDED)."""
    doc = dict(body)
    doc["schema"] = schema
    doc["body_hash"] = body_hash_of(doc)
    if include_run_meta:
        doc["run_meta"] = {"host": _hostname()}
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".evidence_ref.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


def _load_ref(ref_path):
    """Returns the parsed ref.json dict, or None with a printed diagnostic
    on any read/parse/shape failure (usage error, exit 2 -- see module
    docstring)."""
    if not os.path.isfile(ref_path):
        print("evidence_ref: --ref not found: %s" % ref_path, file=sys.stderr)
        return None
    try:
        with open(ref_path, encoding="utf-8") as fh:
            ref = json.load(fh)
    except (OSError, ValueError) as exc:
        print("evidence_ref: cannot read --ref: %s" % exc, file=sys.stderr)
        return None
    if not isinstance(ref, dict) or ref.get("schema") != SCHEMA_REF:
        print("evidence_ref: --ref is not a valid %s document" % SCHEMA_REF, file=sys.stderr)
        return None
    return ref


# ---------------------------------------------------------------------------
# create
# ---------------------------------------------------------------------------
def cmd_create(a):
    if not os.path.isfile(a.verifier):
        # ER-004: no real, content-addressable verifier artefact behind this
        # id -- this IS the "unrecorded LLM judgment" case DEC-29/ER-004
        # forbids: a verdict with no fixed bytes we can hash and replay
        # (see module docstring "ER-004 ... enforced structurally").
        print("evidence_ref: refused (ER-004) -- --verifier %r does not resolve to a real, "
              "content-addressable file; a reference's verifier MUST be non-LLM code or a "
              "recorded, hash-referenced LLM output -- never an unrecorded judgment"
              % a.verifier, file=sys.stderr)
        return EXIT_FINDING
    verifier_version = content_address(a.verifier)

    if not os.path.isfile(a.evidence):
        print("evidence_ref: --evidence path does not exist: %s" % a.evidence, file=sys.stderr)
        return EXIT_USAGE
    evidence_ca = content_address(a.evidence)

    missing_inputs = [p for p in a.inputs if not os.path.isfile(p)]
    if missing_inputs:
        print("evidence_ref: --inputs path(s) do not exist: %s" % ", ".join(missing_inputs),
              file=sys.stderr)
        return EXIT_USAGE

    pairs = compute_input_pairs(".", a.inputs)
    root = merkle_root(pairs)

    target_fingerprint = a.target if a.target else "hermetic"
    established_at = _now_iso()
    established_by = a.established_by or ("evidence_ref.py:create@%s" % _hostname())

    pre = {
        "fact": a.fact,
        "verifier_id": a.verifier,
        "verifier_version": verifier_version,
        "inputs": {
            "paths": list(a.inputs),
            "pairs": [{"path": p, "content_address": c} for p, c in pairs],
            "root": root,
        },
        "target_fingerprint": target_fingerprint,
        "verdict": a.verdict,
        "evidence": {"path": a.evidence, "content_address": evidence_ca},
        "established_by": established_by,
        "established_at": established_at,
    }
    ref_id = "evref:" + hashlib.sha256(canon(pre).encode("utf-8")).hexdigest()[:24]
    body = dict(pre)
    body["ref_id"] = ref_id

    write_doc_atomic(a.out, body, SCHEMA_REF, include_run_meta=False)
    print("evidence_ref: create wrote %s (ref_id=%s, verdict=%s)" % (a.out, ref_id, a.verdict))
    return EXIT_OK


# ---------------------------------------------------------------------------
# consume (ER-002, ER-003, ER-005) -- the T108 RED-tested subcommand.
# ---------------------------------------------------------------------------
def cmd_consume(a):
    ref = _load_ref(a.ref)
    if ref is None:
        return EXIT_USAGE

    # exit-4 "target unreadable": an explicitly-supplied --target this tool
    # cannot trust as a real observation (empty string) -- DISTINCT from an
    # OMITTED --target (ER-005's own REVERIFY_REQUIRED "no reuse on an
    # unobserved target" case, exit 1, changed_components:
    # target_fingerprint_unobserved) and from a --target that WAS read but
    # simply differs from the recorded one (also exit 1, changed_components:
    # target_fingerprint). UNCONFIRMED by the contract (T108's own RED
    # fixtures never exercise this specific path) -- DEFINED here, matching
    # the fixture set's own "UNCONFIRMED... DEFINED here" house convention.
    if a.target is not None and a.target.strip() == "":
        print("evidence_ref: consume refused -- --target was given but is empty/unreadable",
              file=sys.stderr)
        return EXIT_TARGET_UNREADABLE

    base_dir = os.path.dirname(os.path.abspath(a.ref))
    changed = []

    # 1. inputs (ER-002: recompute every component from current bytes).
    declared_paths = ref.get("inputs", {}).get("paths", []) or []
    recorded_pairs = {pr["path"]: pr["content_address"]
                       for pr in ref.get("inputs", {}).get("pairs", []) or []}
    recorded_root = ref.get("inputs", {}).get("root")
    live_pairs = []
    missing_inputs = []
    for p in declared_paths:
        full = os.path.join(base_dir, p)
        if not os.path.isfile(full):
            missing_inputs.append(p)
            continue
        live_pairs.append((p, content_address(full)))
    for p in missing_inputs:
        # A declared input that no longer exists at all is, per ER-002, a
        # changed input -- there is no current content address to compare.
        changed.append("inputs:%s" % p)
    if not missing_inputs:
        live_root = merkle_root(live_pairs)
        if live_root != recorded_root:
            live_map = dict(live_pairs)
            named_any = False
            for p in declared_paths:
                if recorded_pairs.get(p) != live_map.get(p):
                    changed.append("inputs:%s" % p)
                    named_any = True
            if not named_any:
                # Root differs but no single declared pair differs (e.g. a
                # non-canonical stored root) -- report the divergence
                # honestly rather than silently naming nothing.
                changed.append("inputs:<root-mismatch, no single path named>")

    # 2. verifier_version (ER-001: content address of the verifier script).
    verifier_id = ref.get("verifier_id")
    verifier_full = os.path.join(base_dir, verifier_id) if verifier_id else None
    if not verifier_full or not os.path.isfile(verifier_full):
        changed.append("verifier_version")
    else:
        live_vv = content_address(verifier_full)
        if live_vv != ref.get("verifier_version"):
            changed.append("verifier_version")

    # 3. target_fingerprint (ER-002 direct comparison; ER-005 absent-target).
    recorded_target = ref.get("target_fingerprint")
    if recorded_target != "hermetic":
        if a.target is None:
            changed.append("target_fingerprint_unobserved")
        elif a.target != recorded_target:
            changed.append("target_fingerprint")

    # 4. evidence (STALE_EVIDENCE takes priority over REVERIFY_REQUIRED --
    #    ER-002 lists it as its own distinct outcome, not merely another
    #    changed component: a caller must never be told "just re-verify"
    #    when the very evidence backing the OLD verdict has been altered).
    evidence_info = ref.get("evidence", {}) or {}
    evidence_path = evidence_info.get("path")
    evidence_full = os.path.join(base_dir, evidence_path) if evidence_path else None
    if not evidence_full or not os.path.isfile(evidence_full):
        evidence_hash_ok = False
    else:
        evidence_hash_ok = (content_address(evidence_full) == evidence_info.get("content_address"))

    if not evidence_hash_ok:
        outcome = "STALE_EVIDENCE"
        changed_components = ["evidence"]
    elif changed:
        outcome = "REVERIFY_REQUIRED"
        changed_components = changed
    else:
        outcome = "REUSED"
        changed_components = []

    body = {
        "ref_id": ref.get("ref_id"),
        "outcome": outcome,
        "changed_components": changed_components,
        "evidence_hash_ok": evidence_hash_ok,
    }
    # ER-003 "no silent reuse": the old verdict is present iff, and only
    # if, the outcome is REUSED -- never carried forward on
    # REVERIFY_REQUIRED/STALE_EVIDENCE.
    if outcome == "REUSED":
        body["verdict"] = ref.get("verdict")

    write_doc_atomic(a.out, body, SCHEMA_CONSUME, include_run_meta=True)

    if outcome == "REUSED":
        print("evidence_ref: consume REUSED %s (verifier never invoked)" % ref.get("ref_id"))
        return EXIT_OK
    print("evidence_ref: consume %s %s -- changed: %s"
          % (outcome, ref.get("ref_id"), ", ".join(changed_components)), file=sys.stderr)
    return EXIT_FINDING


# ---------------------------------------------------------------------------
# reverify -- runs the verifier for real, writes a NEW reference that
# supersedes the old one. NOT exercised by T108's RED test (explicit,
# documented scope exclusion -- see fixtures/evidence_ref/README.md "What
# this RED test does NOT cover" and test_evidence_ref_red.sh's own header);
# implemented per the contract's 2-line Invocation + ER-002/DEC-29's
# "re-verify... and supersede the reference" language, with every
# underspecified corner explicitly flagged UNCONFIRMED-by-the-contract /
# DEFINED-here below, exactly as create's own gaps are.
# ---------------------------------------------------------------------------
def _run_verifier(verifier_full, cwd):
    """Runs the verifier script, tolerating a missing +x bit (this tree's
    own fixture verifier.sh stubs are checked in WITHOUT the executable bit
    set -- git does not reliably preserve it across every clone/filesystem
    combination) by falling back to an explicit `/bin/sh <path>` invocation,
    matching the `#!/bin/sh` shebang every verifier stub in this fixture set
    already declares. Returns the subprocess' returncode, or None if the
    verifier could not be started at all (ENOENT/OSError)."""
    cmd = [verifier_full] if os.access(verifier_full, os.X_OK) else ["/bin/sh", verifier_full]
    try:
        proc = subprocess.run(cmd, cwd=cwd)
    except OSError as exc:
        print("evidence_ref: reverify BLIND -- could not run verifier %r: %s"
              % (verifier_full, exc), file=sys.stderr)
        return None
    return proc.returncode


def cmd_reverify(a):
    old_ref = _load_ref(a.ref)
    if old_ref is None:
        return EXIT_USAGE

    base_dir = os.path.dirname(os.path.abspath(a.ref))
    verifier_id = old_ref.get("verifier_id")
    verifier_full = os.path.join(base_dir, verifier_id) if verifier_id else None
    if not verifier_full or not os.path.isfile(verifier_full):
        print("evidence_ref: reverify BLIND -- verifier %r not found, cannot run it"
              % verifier_id, file=sys.stderr)
        return EXIT_BLIND

    rc = _run_verifier(verifier_full, base_dir)
    if rc is None:
        return EXIT_BLIND
    # Verifier exit-code -> verdict convention (UNCONFIRMED by the contract
    # -- DEFINED here): 0 = PASS, 1 = FAIL (matching this fixture set's own
    # trivial verifier.sh stubs, C-001's own 0/1 verdict-code convention,
    # and fc_common.py's determinism-check treatment of rc in (0, 1) as the
    # two honest verdict codes). Any OTHER exit (crash, signal death, usage
    # error inside the verifier) is never a verdict -- BLIND, exit 4, no
    # new ref written (contract: "verifier failed to run (no verdict --
    # BLIND per C-001)").
    if rc == 0:
        verdict = "PASS"
    elif rc == 1:
        verdict = "FAIL"
    else:
        print("evidence_ref: reverify BLIND -- verifier exited %d (only 0=PASS/1=FAIL are "
              "honest verdicts here)" % rc, file=sys.stderr)
        return EXIT_BLIND

    declared_paths = old_ref.get("inputs", {}).get("paths", []) or []
    missing = [p for p in declared_paths if not os.path.isfile(os.path.join(base_dir, p))]
    if missing:
        print("evidence_ref: reverify BLIND -- declared input(s) no longer exist: %s"
              % ", ".join(missing), file=sys.stderr)
        return EXIT_BLIND
    pairs = compute_input_pairs(base_dir, declared_paths)
    root = merkle_root(pairs)
    verifier_version = content_address(verifier_full)

    # target_fingerprint: the contract's own `reverify` Invocation line
    # carries no `--target` flag at all, yet ER-005's non-hermetic
    # semantics need SOME way to observe the target at reverify time too --
    # UNCONFIRMED by the contract, DEFINED here as an additive, OPTIONAL
    # `--target` on this subcommand (never required, so a purely-hermetic
    # caller matching the contract's literal 2-flag grammar still works
    # unmodified). Omitted for a non-hermetic old ref -> the STALE recorded
    # target_fingerprint is carried forward honestly (never silently
    # dropped to "hermetic", never fabricated as fresh).
    target_fingerprint = old_ref.get("target_fingerprint")
    if target_fingerprint != "hermetic" and a.target:
        target_fingerprint = a.target

    evidence_info = old_ref.get("evidence", {}) or {}
    evidence_path = evidence_info.get("path")
    evidence_full = os.path.join(base_dir, evidence_path) if evidence_path else None
    if not evidence_full or not os.path.isfile(evidence_full):
        print("evidence_ref: reverify BLIND -- evidence path %r not found after running the "
              "verifier" % evidence_path, file=sys.stderr)
        return EXIT_BLIND
    evidence_ca = content_address(evidence_full)

    established_at = _now_iso()
    established_by = "evidence_ref.py:reverify@%s" % _hostname()

    pre = {
        "fact": old_ref.get("fact"),
        "verifier_id": verifier_id,
        "verifier_version": verifier_version,
        "inputs": {
            "paths": list(declared_paths),
            "pairs": [{"path": p, "content_address": c} for p, c in pairs],
            "root": root,
        },
        "target_fingerprint": target_fingerprint,
        "verdict": verdict,
        "evidence": {"path": evidence_path, "content_address": evidence_ca},
        "established_by": established_by,
        "established_at": established_at,
        # DEC-29/data-model.md §8: "re-verify... and supersede the
        # reference" -- an additive lineage field beyond create's own
        # minimal shape, present ONLY on a reverify-produced reference.
        "supersedes": old_ref.get("ref_id"),
    }
    ref_id = "evref:" + hashlib.sha256(canon(pre).encode("utf-8")).hexdigest()[:24]
    body = dict(pre)
    body["ref_id"] = ref_id

    write_doc_atomic(a.out, body, SCHEMA_REF, include_run_meta=False)
    print("evidence_ref: reverify wrote %s (ref_id=%s, verdict=%s, supersedes=%s)"
          % (a.out, ref_id, verdict, old_ref.get("ref_id")))
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="evidence_ref.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd_name", required=True)

    c = sub.add_parser("create")
    c.add_argument("--fact", required=True)
    c.add_argument("--verifier", required=True)
    c.add_argument("--inputs", required=True, nargs="+")
    c.add_argument("--target")
    c.add_argument("--verdict", required=True, choices=("PASS", "FAIL"))
    c.add_argument("--evidence", required=True)
    c.add_argument("--out", required=True)
    # Additive, non-contract flag (see module docstring "established_at/
    # established_by" section) -- optional, never required.
    c.add_argument("--established-by")

    u = sub.add_parser("consume")
    u.add_argument("--ref", required=True)
    u.add_argument("--target")
    u.add_argument("--out", required=True)

    r = sub.add_parser("reverify")
    r.add_argument("--ref", required=True)
    r.add_argument("--out", required=True)
    # Additive, non-contract flag (see cmd_reverify's own docstring note) --
    # optional, never required.
    r.add_argument("--target")

    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)
    table = {"create": cmd_create, "consume": cmd_consume, "reverify": cmd_reverify}
    return table[args.cmd_name](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
