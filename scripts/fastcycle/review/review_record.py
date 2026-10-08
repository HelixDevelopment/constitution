#!/usr/bin/env python3
"""review_record.py - review-verdict recording for spec-004 fastcycle tools
(contracts/review-batch-and-precheck.md; contracts/common-conventions.md
C-001..C-007; data-model.md #10.1 ReviewVerdictRecord; plan.md T-A04;
FR-023, SC-009, SC-001).

Purpose: given a ReviewBatch (data-model #10.2), a PreCheckReport
         (data-model #10.3, read from the sibling `precheck.json` next to
         --batch unless --precheck overrides), and a raw --verdict-file a
         reviewer produced, classify every finding into the T-A04 closed
         class set {mechanical, judgment, false-positive} and write one
         canonical ReviewVerdictRecord JSON document per invocation.

Classifier (this tool's decision rule -- pinned by
    constitution/scripts/fastcycle/tests/test_review_record_red.sh /
    fixtures/review_record/{golden-good,golden-bad,negative-control}; any
    classifier reaching the same per-fixture verdict satisfies the contract):
    1. finding's (file, line) -- both genuinely present and non-null on the
       finding AND on a marker, line numbers compared as integers so "87"
       and 87 are the same location -- matches an entry in precheck.json's
       "already-fixed-markers" check evidence.markers
         -> "false-positive" (DEC-33 "state-temporal misalignment": the
            code was already fixed by the time the reviewer filed the
            comment)
    2. else finding carries a non-empty "rule" field (a named lint/style
       rule, e.g. verdict.json {"rule": "SC2086"})
         -> "mechanical" (findable by the machine pre-check pack, DEC-33)
    3. else
         -> "judgment" (a substantive design/architecture concern; no
            already-fixed-markers match, no lint rule)
   false-positive (1) is checked BEFORE the rule/mechanical check (2) --
   reviewed and deliberately reversed from an earlier revision that checked
   the rule first. Reasoning: "false-positive" answers a logically PRIOR
   question ("is this finding still about the code as it exists?") than
   "mechanical"/"judgment" answer ("if the finding is real, what kind of
   real finding is it?"). A finding that names a lint rule AND matches an
   already-fixed marker is a comment about code that no longer exists in
   that form -- it is stale noise, not a genuine machine-findable defect,
   and counting it "mechanical" would inflate RB-007's mechanical-share
   metric with a finding that was never a real, present-tense issue in the
   first place. None of the three original fixtures needs both signals to
   disambiguate (each triggers exactly one), so this reordering changes no
   existing fixture's classification -- it only changes the (currently
   untested) case where both a rule name and a marker match are present on
   the same finding.

Usage:   review_record.py record --batch B --round N --verdict-file V
             --tier opus --effort xhigh --out O
             [--item ITEM] [--precheck PRECHECK]
             [--started-at TS] [--ended-at TS]
             [--tokens JSON] [--reviewer-mutations JSON]
             [--substrate-evidence TEXT]
             [--producer-id ID] [--round-budget 5..7]
         review_record.py backfill --input SPEC --out O
         review_record.py gate --change SHA[,SHA...] --records DIR
             [--dispatch-ledger LEDGER.jsonl]
             [--seam ordinary|release-tag|qa-deploy|manual-qa-handoff]
             [--round-budget 5..7]

Verdict authority (T048 restart round 1, R7 B1/B2 -- defect class "the gate
        trusts unauthenticated record fields"; members enumerated: verdict,
        findings/finding_layer, round, model_tier, effort, reviewer identity,
        producer identity, same-round precedence, evidence-path base, precheck
        all_pass/schema/batch, dispatch reuse, round budget, per-slice
        verdicts, record body integrity, backfill rows, seam/independence):
        `gate` decides coverage ONLY from (1) the reviewer's own verdict file,
        archived content-addressed by `record` as <sha256>.verdict-evidence
        and re-hashed at gate time -- verdict, findings, finding_layers,
        round and the reviewer block {dispatch_id, model, effort} are
        RE-DERIVED from it and the record's copies must equal them;
        (2) a dispatch ledger (--dispatch-ledger, JSONL rows {key,
        description}) in which the reviewer's dispatch must appear with an
        11.4.182 label naming the designated model/effort, backing no other
        verdict, and differing from the record's producer identity; (3) the
        archived precheck, which must be schema precheck/v1, all_pass true,
        same batch; (4) the record's own body_hash. A same-(batch, round)
        conflict is refused (exit 4) rather than resolved by filename order;
        a multi-slice batch needs a GO verdict for every slice
        (11.4.235(D)); backfill rows are history only and never coverage.
        Each UNCOVERED line names its reason; each COVERED line names the
        independence tier ACHIEVED (11.4.240(F)) and the seam.
        Independence tier: "capability" only when every evidence file (the
        record, both archives, the ledger) is owned by another uid and is not
        writable -- nor is its directory -- by the uid running `gate`;
        otherwise "instance". High-blast seams (release-tag, qa-deploy,
        manual-qa-handoff) require "capability" (11.4.240(F)(4)).
        Honest boundary (11.4.6 / 11.4.240(F)): on a SINGLE-UID host every
        one of these sources is writable by the producer, so a determined
        producer can still forge a reviewer verdict file citing a REAL
        reviewer dispatch it did not author (only once per dispatch), or
        delete an earlier NO-GO record (deletion is undetectable without a
        tamper-evident chain, 11.4.268). That is why such a host honestly
        reports "instance" and why the high-blast seams refuse it: the
        mechanism turns one-command self-certification into a multi-artifact
        forgery at ordinary seams and blocks it outright at high-blast seams,
        but it does not -- and cannot, without an operator-provided uid
        boundary (11.4.66 / 12) -- make forgery impossible.
        Production wiring (R7 I4, honest): no production seam invokes
        `gate` yet; wiring it into the closure/tag tooling is owed one layer
        above this tool and is NOT claimed here.

Exit:    record : 0 accepted + written (tier equals the designated review
                    tier and effort equals xhigh OR the honest capability-
                    gap token "?", constitution 11.4.209 as amended
                    2026-09-26: Opus xhigh, no Fable, no fallback model;
                    11.4.231(F.2): a dispatch path that cannot report
                    effort records "?", never a fabricated "xhigh");
                  1 refused (tier mismatch, or effort neither "xhigh" nor
                    "?"; --round beyond the 11.4.276 round budget; the
                    verdict file's reviewer model/effort disagreeing with
                    --tier/--effort; --producer-id equal to the reviewer
                    dispatch id -- nothing written);
                  2 usage/configuration error (bad args, --round < 1, a
                    --verdict-file "round" that disagrees with --round, a
                    --verdict-file with no "verdict" field or a "verdict"
                    outside {GO, NO-GO}, unreadable or malformed
                    --batch/--verdict-file/--precheck/--input, malformed
                    --tokens/--reviewer-mutations JSON, a non-integer
                    verdict-file 'round', a malformed reviewer block or
                    slice verdict, a finding naming an unknown slice, an
                    overall GO contradicting a NO-GO slice, a GO slice
                    holding a source-defect/unclassified finding,
                    --round-budget outside 5..7, cannot write --out).
         backfill: 0 written; 2 usage/configuration error (missing
                    required --input key, a "round" < 1, malformed
                    finding, bad verdict, cannot write --out). There is no
                    tier/effort refusal path for backfill -- a backfilled
                    row records history, it does not gate a live review.
         gate   : 2 usage error (no change id, --round-budget outside
                    5..7, unknown --seam);
                  0 every queried change is covered (contract RB-006:
                    member of a batch whose LATEST-round record is a
                    zero-finding GO at the designated tier/effort --
                    "?" effort, the honest 11.4.231(F.2) capability-gap
                    token, NEVER satisfies gate, matching RB-004's own
                    note); 1 at least one queried change is uncovered
                    (each uncovered change_id is printed on stdout, one
                    per line -- "gate exits 1, lists changes" per the
                    contract's own "Exit codes" row); 4 --records is not a
                    readable directory, or any file under it that ends
                    ".json" fails to parse / is not a JSON object / is
                    missing a required ReviewVerdictRecord field / carries
                    a non-integer round, or two DIFFERENT records share one
                    (batch_id, round) (records unreadable or ambiguous -- no honest
                    coverage verdict is possible without knowing what
                    that file was, constitution 11.4.201(6): a null read
                    as "uncovered" here would be a false-null, not
                    evidence). A --records directory that is readable but
                    holds zero matching records is NOT records-unreadable
                    (4) -- it is a genuine, honest "nothing covers this
                    change" finding (1).
         Any other internal error: 4 (BLIND, C-001 row 4 -- no honest
         verdict is possible; never 1, which is reserved for a genuine
         review finding).

Verdict (constitution 11.4.240 producer != verifier; data-model.md #10.1
        "verdict | GO | NO-GO"): the reviewer's own conclusion, read
        VERBATIM from --verdict-file's "verdict" field -- a REQUIRED field
        from the closed set {GO, NO-GO}. This tool NEVER derives a verdict
        from the findings' severities: a review's overall GO/NO-GO call is
        the reviewer's to make, not this tool's to infer. `first_round_go`
        is a SEPARATE, derived correctness flag -- `round == 1 AND
        verdict == "GO" AND len(findings) == 0` (RB-005 / constitution
        11.4.134: "a GO is terminal only when it has zero findings of any
        severity") -- so a recorded "GO" verdict that still carries
        findings (rb_bad_go_with_nit) is stored faithfully but never counts
        as a clean first-round GO.

Output (C-002): canonical JSON (UTF-8, sorted keys, no insignificant
        whitespace, `schema: "review-record/v1"` per
        contracts/review-batch-and-precheck.md "Output schemas", `body_hash`
        = sha256 of the canonical body excluding `run_meta`). See
        data-model.md #10.1 for the full ReviewVerdictRecord field list;
        this tool additionally emits `source` (`"live"` for `record`,
        `"backfill"` for `backfill`), `effort_capability_gap` (bool: true
        iff `effort == "?"` -- constitution 11.4.231(F.2); a future `gate`
        command MUST treat this as non-satisfying regardless of `verdict`)
        and, for `record`, `precheck_used` (bool: whether a readable
        precheck.json was actually consulted).

Finding-layer (constitution 11.4.235(D), added 2026-10-03): each entry in
        `findings` MAY additionally carry `finding_layer`, one of the
        closed set {"source-defect", "test-instrumentation", "process-doc"}
        -- a DIFFERENT axis entirely from the pre-existing per-finding
        `class` {"mechanical","judgment","false-positive"} (see
        classify_finding() above); the two are computed independently and
        neither influences the other. Set it on a raw finding object (the
        same `findings` array in --verdict-file for `record`, or --input
        for `backfill` -- this tool has no separate per-finding CLI flag
        for ANY attribute, severity/rule/file/line included, so none is
        invented for finding_layer either). OPTIONAL and purely additive:
        a finding naming no "finding_layer" (every record written before
        this field existed, and every caller that has not yet adopted it)
        emits no "finding_layer" key at all and behaves EXACTLY as before.
        A value outside the closed set is a usage error (exit 2, --out NOT
        written) -- never silently coerced, dropped, or defaulted.

        Enforcement (revised 2026-10-08, R7 I3): `record` still RECORDS the
        value verbatim (an absent value stays absent in the record -- never
        rewritten). (a) Optional on the record, but where it matters --
        a GO slice verdict -- an ABSENT layer is treated as source-defect
        (11.4.235(D) conservative default) and a GO slice holding a
        source-defect or absent-layer finding is refused (exit 2). (b) WHO
        sets it: `gate` re-derives every finding_layer from the reviewer's
        own archived verdict file and refuses a record whose layers differ,
        so a producer cannot lower a layer after the reviewer wrote it; the
        single-uid boundary in "Verdict authority" above still applies to
        the verdict file itself. (c) A layer may change only in a fresh
        review round (a new reviewer-authored verdict file), never by
        editing a record.

Honesty (constitution 11.4.6): no field is ever invented. A `record`
invocation given no --item/--started-at/--ended-at/--tokens/
--reviewer-mutations/--substrate-evidence records the honest literal
"UNMEASURED" (tokens, matching data-model.md #11.1's Measured<T> convention
for values with no recording instrument) or "UNKNOWN" (every other
unsuppliable field, matching data-model.md #10.1's own "UNKNOWN on
back-filled rows" convention extended here to any unrecorded live field).
`backfill` records "UNKNOWN" for every field its --input spec does not
supply, and ALWAYS records tokens as "UNKNOWN" (data-model.md #10.1: "tokens
... UNKNOWN on back-filled rows (source=backfill)") -- a backfilled row
never claims a measured token count.

Producer != Verifier (constitution 11.4.240): this tool CLASSIFIES a
verdict a reviewer already produced; it never generates, edits, or
influences the verdict.json a reviewer wrote, and it refuses (exit 1)
rather than silently downgrade an off-tier/off-effort review into a
recorded one.

Side-effects: `record`/`backfill` write --out (atomic: temp file in the
same directory + os.replace). Python stdlib only.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import sys
import tempfile

# T085 Round 5 (R4-I1): content-hash evidence binding (see
# _evidence_hash_verified() below for the full rationale).
_HASH_RE = re.compile(r"^[0-9a-f]{64}$")

SCHEMA = "review-record/v1"  # contracts/review-batch-and-precheck.md "Output schemas" (hyphen, not underscore)
DESIGNATED_TIER = "opus"
DESIGNATED_EFFORT = "xhigh"
# Constitution 11.4.235(D) FINDING-LAYER CLASSIFIER (added 2026-10-03): an
# OPTIONAL, per-finding closed-set classification, DISTINCT from the
# pre-existing "class" field above (T-A04 mechanical|judgment|false-positive
# -- a different axis entirely; see classify_finding() below, which this
# field never touches and is never touched by). A finding carrying NO
# "finding_layer" key is unaffected (backward-compatible: every record
# authored before this field existed, and every caller that has not yet
# adopted it, behaves exactly as before -- constitution 11.4.6, "clause (D)
# applies prospectively; recorded verdicts are never rewritten or
# reclassified"). A finding carrying a "finding_layer" value outside this
# closed set is a usage error (exit 2), never silently coerced or dropped.
#
# Honest scope (constitution 11.4.6): this tool RECORDS whatever value it
# is given -- it does NOT enforce "finding_layer is mandatory", does NOT
# distinguish a reviewer-supplied value from a producer-supplied one
# (there is no "reviewer-only may set it" check at this layer), and does
# NOT apply the 11.4.235(D) "undecidable -> defaults to source-defect"
# rule on the caller's behalf (an absent value stays absent, never
# auto-promoted). Those are tracked §11.4.197 enforcement gaps owed at the
# calling review-gate seam, not claimed as shipped here.
FINDING_LAYERS = ("source-defect", "test-instrumentation", "process-doc")
# Constitution 11.4.276(A): review-round budget, consumer-declared within the
# operator ceiling 5..7; an absent declaration resolves to 5.
ROUND_BUDGET_MIN = 5
ROUND_BUDGET_MAX = 7
ROUND_BUDGET_DEFAULT = 5
# Constitution 11.4.240(F)(4): the three high-blast-radius seams at which a
# producer-writable verdict is refused regardless of anything else -- they
# require the "capability" independence tier. Every other seam is "ordinary",
# where an independent INSTANCE suffices (11.4.240(F)(5)).
HIGH_BLAST_SEAMS = ("release-tag", "qa-deploy", "manual-qa-handoff")
SEAMS = ("ordinary",) + HIGH_BLAST_SEAMS
INDEPENDENCE_TIERS = ("instance", "model", "capability")
PRECHECK_SCHEMA = "precheck/v1"
# Constitution 11.4.182 work-stream label as written into a dispatch ledger
# row's description: (T<N>/<branch> - <alias> - <model> - <effort>).
_LABEL_RE = re.compile(r"\(T[0-9?]+/[^ ()]+ - [^ ()]+ - ([^ ()]+) - ([^ ()]+)\)")
# C-002: body_hash covers the canonical doc EXCLUDING run_meta (and body_hash
# itself, which it fills in) -- mirrors constitution/scripts/fastcycle/lib/
# fc_common.py's EXCLUDED tuple (this tool does not import fc_common: it
# keeps its own tiny, self-contained copy of the two canonicalisation
# primitives so `record`/`backfill` have no cross-file runtime dependency).
_EXCLUDED = ("run_meta", "body_hash")
_BAD = object()  # sentinel: an optional --tokens/--reviewer-mutations JSON arg failed to parse


def _canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k not in _EXCLUDED}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


def _sha256_file(path):
    """sha256 of `path`'s raw bytes. Raises OSError on any read failure --
    callers are expected to treat that as "evidence unreadable", never
    silently absorbed into a fabricated hash (constitution 11.4.6)."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _write_record(body, out_path):
    doc = dict(body)
    doc["schema"] = SCHEMA
    try:
        doc["body_hash"] = _body_hash_of(doc)
        doc["run_meta"] = {"written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        data = (_canon(doc) + "\n").encode("utf-8")
    except (UnicodeEncodeError, ValueError) as exc:
        print("review_record: body not encodable: %s" % exc, file=sys.stderr)
        return 2
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    try:
        fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".review_record.")
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
            os.replace(tmp, out_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    except OSError as exc:
        print("review_record: cannot write --out: %s" % exc, file=sys.stderr)
        return 2
    return 0


def _load_json(path, label):
    """Returns (doc, None) on success, (None, error-message) on failure. Never raises.

    json.JSONDecodeError is a ValueError subclass; a non-UTF-8 file raises
    UnicodeDecodeError (also a ValueError subclass) while `open(..., encoding="utf-8")`
    is being read by json.load. Both are "malformed input file" per this tool's own
    documented contract (C-001 code 2, "unreadable or malformed"), so both are caught
    here -- previously only json.JSONDecodeError was caught, so a non-UTF-8 file
    propagated uncaught to main()'s BLIND (4) handler instead of the documented 2.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), None
    except (OSError, ValueError) as exc:
        return None, "%s: cannot read/parse %s: %s" % (label, path, exc)


def _parse_optional_json(text, name):
    """None (flag omitted) -> None. Bad JSON -> _BAD (caller must exit 2). Else the parsed value."""
    if text is None:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        print("review_record: bad JSON for %s: %s" % (name, exc), file=sys.stderr)
        return _BAD


def already_fixed_markers(precheck_doc):
    """Extract precheck.json's already-fixed-markers check evidence.markers (data-model.md #10.3).

    Returns [] on any shape mismatch (missing check, wrong types) -- absence
    of a usable markers list means "no false-positive matches possible", not
    an error: a review batch may legitimately have no already-fixed lines.
    """
    if not isinstance(precheck_doc, dict):
        return []
    for check in precheck_doc.get("checks") or []:
        if isinstance(check, dict) and check.get("check") == "already-fixed-markers":
            evidence = check.get("evidence")
            markers = evidence.get("markers") if isinstance(evidence, dict) else None
            if isinstance(markers, list):
                return [m for m in markers if isinstance(m, dict)]
    return []


def _normalize_line(value):
    """Best-effort int normalisation for a location's line number so "87" (str) and 87
    (int) compare equal (I1: a finding/marker author may write either shape for the same
    location). Returns None for anything not genuinely a line number (None, bool -- a
    bool is an int subclass in Python and must NOT silently normalise to 0/1 --, a
    non-numeric string, float, etc.). Never raises."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.lstrip("-").isdigit():
            return int(stripped)
    return None


def classify_finding(finding, markers):
    """T-A04 closed class set: mechanical | judgment | false-positive. See module docstring
    for the precedence rationale (false-positive checked BEFORE rule/mechanical)."""
    file_ = finding.get("file")
    line_ = _normalize_line(finding.get("line"))
    # I1: a match requires BOTH file and line genuinely present (non-null, non-empty
    # file, a real line number) on BOTH sides -- `None == None` must never count as a
    # location match (that reclassified a location-less BLOCKING architectural finding
    # down to false-positive against a location-less marker in the pre-fix reviewer
    # reproduction), and line numbers are compared as normalised ints so "87" and 87
    # match.
    if isinstance(file_, str) and file_ and line_ is not None:
        for marker in markers:
            marker_file = marker.get("file")
            marker_line = _normalize_line(marker.get("line"))
            if (isinstance(marker_file, str) and marker_file and marker_line is not None
                    and marker_file == file_ and marker_line == line_):
                return "false-positive"
    rule = finding.get("rule")
    if isinstance(rule, str) and rule.strip():
        return "mechanical"
    return "judgment"


def _validated_finding_layer(finding, label):
    """Constitution 11.4.235(D): read the OPTIONAL per-finding
    "finding_layer" key from a raw finding object (this tool's existing
    calling convention -- every other per-finding attribute, severity/
    rule/file/line, likewise arrives embedded on the finding object inside
    --verdict-file's/--input's "findings" array; there is no separate
    per-finding CLI flag anywhere in this tool, so none is invented for
    this field either).

    Returns (value, None) on success -- value is None when the key is
    absent or explicitly null (backward-compatible: a finding predating
    this field, or a caller that has not adopted it, is NEVER an error),
    else the validated string from the closed set FINDING_LAYERS.

    Returns (None, <error message>) when "finding_layer" is PRESENT but is
    not a member of FINDING_LAYERS -- callers MUST propagate this as a
    usage error (exit 2, never silently coerced/dropped/defaulted;
    constitution 11.4.6 -- this tool RECORDS the reviewer's classification
    verbatim, it never invents one)."""
    if not isinstance(finding, dict) or "finding_layer" not in finding:
        return None, None
    value = finding.get("finding_layer")
    if value is None:
        return None, None
    if isinstance(value, str) and value in FINDING_LAYERS:
        return value, None
    return None, (
        "%s: 'finding_layer' must be one of %s, or absent/null, got %r"
        % (label, ", ".join(FINDING_LAYERS), value)
    )


def _derive_item_id(batch):
    """No --item given: fall back to ReviewBatch's `related_by` (data-model.md #10.2), stripping
    a leading "logic_group:" prefix if present. Absent/non-string -> honest "UNKNOWN" (11.4.6:
    never invent an item id the batch does not actually carry)."""
    related = batch.get("related_by")
    if not isinstance(related, str) or not related:
        return "UNKNOWN"
    prefix = "logic_group:"
    return related[len(prefix):] if related.startswith(prefix) else related


def _extract_slice_lines(batch):
    slices = batch.get("slices")
    if not isinstance(slices, list):
        return []
    return [{"slice_id": s["slice_id"], "lines": s["lines"]}
            for s in slices if isinstance(s, dict) and "slice_id" in s and "lines" in s]


def _archive_evidence(src_path, records_root, suffix):
    """Archive `src_path` content-addressed as <sha256><suffix> inside
    `records_root` (the directory --out lands in) and return (name, sha256).

    The ONE archival primitive for every piece of evidence a live record
    pins (precheck document, reviewer verdict file) -- section 11.4.227
    reuse-not-reinvention. The suffix deliberately does NOT end in `.json`
    so `_gate_collect_records()` (which walks every `*.json`) can never
    mistake an archive for a ReviewVerdictRecord. Re-archiving identical
    content never writes a duplicate. Raises OSError on failure; callers
    turn that into exit 2."""
    sha = _sha256_file(src_path)
    name = "%s%s" % (sha, suffix)
    path = os.path.join(records_root, name)
    if not os.path.isfile(path):
        with open(src_path, "rb") as fh:
            data = fh.read()
        fd, tmp = tempfile.mkstemp(dir=records_root, prefix=".review_record_evidence.")
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
            os.replace(tmp, path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    return name, sha


def _independence_tier(paths):
    """Constitution 11.4.240(F): the independence tier ACHIEVED for a set of
    evidence paths -- never a claimed one. "capability" ONLY when every path
    is owned by a uid other than the effective uid running this process AND
    neither the path nor its parent directory is writable by this process
    (os.access) -- i.e. a genuine host access-control boundary separates the
    caller from the evidence. Anything less is "instance": the honest tier
    on a single-uid host, where ownership defeats every boundary an agent
    could set up (11.4.240(F) honest boundary). "model" is part of the
    closed vocabulary but is never computed here: this tool has no
    authenticated source for the PRODUCER's model, so it cannot prove model
    diversity and does not claim it."""
    try:
        euid = os.geteuid()
        for path in paths:
            if path is None:
                return "instance"
            st = os.stat(path)
            if st.st_uid == euid:
                return "instance"
            if os.access(path, os.W_OK):
                return "instance"
            parent = os.path.dirname(os.path.abspath(path)) or "."
            if os.access(parent, os.W_OK):
                return "instance"
    except OSError:
        return "instance"
    return "capability"


def _round_budget_error(budget):
    if budget is None:
        return None
    if not (ROUND_BUDGET_MIN <= budget <= ROUND_BUDGET_MAX):
        return ("--round-budget must be within %d..%d (constitution 11.4.276(A) operator "
                "ceiling), got %d" % (ROUND_BUDGET_MIN, ROUND_BUDGET_MAX, budget))
    return None


def _validated_reviewer(verdict_doc):
    """Returns (reviewer_dict_or_None, error). The reviewer block is the
    reviewer's OWN identity statement inside the verdict file it authored:
    {"dispatch_id": str, "model": str, "effort": str}. Absent -> (None,
    None): the record is still written (classification use), but `gate`
    will never treat it as coverage (no authenticated reviewer)."""
    if "reviewer" not in verdict_doc or verdict_doc.get("reviewer") is None:
        return None, None
    rv = verdict_doc.get("reviewer")
    if not isinstance(rv, dict):
        return None, "--verdict-file 'reviewer' must be a JSON object"
    for key in ("dispatch_id", "model", "effort"):
        val = rv.get(key)
        if not isinstance(val, str) or not val.strip():
            return None, "--verdict-file 'reviewer.%s' must be a non-empty string, got %r" % (key, val)
    return {"dispatch_id": rv["dispatch_id"].strip(), "model": rv["model"].strip(),
            "effort": rv["effort"].strip()}, None


def _validated_slice_verdicts(verdict_doc, slice_ids, verdict, raw_findings):
    """Constitution 11.4.235(D) per-slice verdicts. Returns (list_or_None,
    error). Absent -> (None, None). When present: each entry {slice_id,
    verdict} names a slice of the batch, no slice twice, verdict in
    {GO, NO-GO}; an overall GO may not contradict a NO-GO slice; and a GO
    slice may not hold a finding whose finding_layer is source-defect or
    ABSENT (11.4.235(D): an undecidable finding defaults to source-defect,
    and a slice with an open source-defect finding is not build-eligible)."""
    if "slice_verdicts" not in verdict_doc or verdict_doc.get("slice_verdicts") is None:
        return None, None
    svs = verdict_doc.get("slice_verdicts")
    if not isinstance(svs, list):
        return None, "--verdict-file 'slice_verdicts' must be a JSON list"
    seen = {}
    for sv in svs:
        if not isinstance(sv, dict):
            return None, "--verdict-file slice verdict entry must be an object, got %r" % (sv,)
        sid = sv.get("slice_id")
        sverd = sv.get("verdict")
        if not isinstance(sid, str) or sid not in slice_ids:
            return None, "--verdict-file slice verdict names unknown slice %r (batch slices: %s)" % (
                sid, ", ".join(sorted(slice_ids)) or "<none>")
        if sid in seen:
            return None, "--verdict-file slice %r has more than one slice verdict" % (sid,)
        if sverd not in ("GO", "NO-GO"):
            return None, "--verdict-file slice %r verdict must be GO or NO-GO, got %r" % (sid, sverd)
        seen[sid] = sverd
    if verdict == "GO" and any(v == "NO-GO" for v in seen.values()):
        return None, "--verdict-file overall verdict GO contradicts a NO-GO slice verdict"
    for f in raw_findings:
        sid = f.get("slice_id")
        if sid is not None and seen.get(sid) == "GO":
            layer = f.get("finding_layer")
            if layer is None or layer == "source-defect":
                return None, ("--verdict-file slice %r is GO but holds finding %r with finding_layer %r "
                              "(an absent layer defaults to source-defect, constitution 11.4.235(D))"
                              % (sid, f.get("id"), layer))
    return sorted(({"slice_id": k, "verdict": v} for k, v in seen.items()),
                  key=lambda e: e["slice_id"]), None


def cmd_record(a):
    # M1: round integrity is a usage error (2), checked before anything else.
    if a.round < 1:
        print("review_record: --round must be >= 1, got %d" % a.round, file=sys.stderr)
        return 2
    err = _round_budget_error(a.round_budget)
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2
    budget = a.round_budget if a.round_budget is not None else ROUND_BUDGET_DEFAULT
    # R7 I3 / constitution 11.4.276(A)+(E)(3): a round beyond the declared
    # budget is a STOP-and-escalate condition, never another recorded round.
    if a.round > budget:
        print("review_record: refused -- --round %d exceeds the review-round budget %d "
              "(constitution 11.4.276: stop and escalate to a recorded operator decision)"
              % (a.round, budget), file=sys.stderr)
        return 1

    # B2 / constitution 11.4.231(F.2): effort "?" is the honest capability-gap token a
    # dispatch path records when it cannot report effort at all -- it is ACCEPTED here
    # (never refused), stored verbatim, and flagged via effort_capability_gap below so
    # `gate` correctly treats it as non-satisfying. Only effort has this exception.
    effort_capability_gap = (a.effort == "?")
    if a.tier != DESIGNATED_TIER or (not effort_capability_gap and a.effort != DESIGNATED_EFFORT):
        print("review_record: refused -- tier must equal the designated review tier (%s) and "
              "effort must equal %s or the honest capability-gap token '?' "
              "(constitution 11.4.209 as amended 2026-09-26 / 11.4.231(F.2)), got %s/%s"
              % (DESIGNATED_TIER, DESIGNATED_EFFORT, a.tier, a.effort), file=sys.stderr)
        return 1

    batch, err = _load_json(a.batch, "--batch")
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2
    if not isinstance(batch, dict):
        print("review_record: --batch must be a JSON object", file=sys.stderr)
        return 2

    verdict_doc, err = _load_json(a.verdict_file, "--verdict-file")
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2
    if not isinstance(verdict_doc, dict):
        print("review_record: --verdict-file must be a JSON object", file=sys.stderr)
        return 2
    raw_findings = verdict_doc.get("findings")
    if not isinstance(raw_findings, list):
        print("review_record: --verdict-file 'findings' must be a JSON list", file=sys.stderr)
        return 2

    # B1 / constitution 11.4.240 (producer != verifier): `verdict` is the reviewer's OWN
    # conclusion, REQUIRED in --verdict-file, read verbatim -- never derived from the
    # findings and never rewritten (R7 B2-M3: a zero-finding NO-GO stays NO-GO).
    verdict = verdict_doc.get("verdict")
    if verdict not in ("GO", "NO-GO"):
        print("review_record: --verdict-file must carry a 'verdict' field of 'GO' or 'NO-GO' "
              "(the reviewer's own conclusion; never derived from findings), got %r"
              % (verdict,), file=sys.stderr)
        return 2

    # M1 + R7 M-a: the verdict file's own 'round', when present, must be a genuine
    # integer (bool is an int subclass -- `true` must never read as round 1) and must
    # equal --round; either violation is a usage error, never a silent pick.
    verdict_round = verdict_doc.get("round")
    if verdict_round is not None:
        if not isinstance(verdict_round, int) or isinstance(verdict_round, bool):
            print("review_record: --verdict-file 'round' must be an integer, got %r"
                  % (verdict_round,), file=sys.stderr)
            return 2
        if verdict_round != a.round:
            print("review_record: --round %s does not match --verdict-file's own 'round' %s -- "
                  "refusing rather than silently pick one (constitution 11.4.6)"
                  % (a.round, verdict_round), file=sys.stderr)
            return 2

    reviewer, err = _validated_reviewer(verdict_doc)
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2
    producer_id = (a.producer_id or "").strip() or "UNKNOWN"
    if reviewer is not None:
        # The reviewer's own statement of what answered must agree with the tier/effort
        # this invocation is recording -- a mismatch is refused, never reconciled.
        if reviewer["model"] != a.tier or reviewer["effort"] != a.effort:
            print("review_record: refused -- --verdict-file reviewer model/effort %s/%s disagrees "
                  "with --tier/--effort %s/%s" % (reviewer["model"], reviewer["effort"], a.tier, a.effort),
                  file=sys.stderr)
            return 1
        if producer_id == reviewer["dispatch_id"]:
            print("review_record: refused -- --producer-id equals the reviewer dispatch id %r: a "
                  "producer can never certify its own work (constitution 11.4.240)"
                  % (producer_id,), file=sys.stderr)
            return 1

    findings_out = []
    for finding in raw_findings:
        if not isinstance(finding, dict) or "id" not in finding:
            print("review_record: malformed finding entry (missing 'id'): %r" % (finding,), file=sys.stderr)
            return 2
        # 11.4.235(D): validated BEFORE classify_finding() is even called -- the two are
        # independently computed from disjoint input keys and neither influences the other.
        finding_layer, err = _validated_finding_layer(
            finding, "--verdict-file finding %r" % (finding.get("id"),))
        if err:
            print("review_record: %s" % err, file=sys.stderr)
            return 2
        out_finding = {
            "id": finding["id"],
            "severity": finding.get("severity", "UNKNOWN"),
            "class": None,  # filled once the precheck markers are known (below)
        }
        if finding_layer is not None:
            out_finding["finding_layer"] = finding_layer
        if finding.get("slice_id") is not None:
            out_finding["slice_id"] = finding.get("slice_id")
        findings_out.append((out_finding, finding))

    slice_ids = {s["slice_id"] for s in _extract_slice_lines(batch) if isinstance(s.get("slice_id"), str)}
    for out_finding, _raw in findings_out:
        sid = out_finding.get("slice_id")
        if sid is not None and sid not in slice_ids:
            print("review_record: --verdict-file finding %r names unknown slice %r"
                  % (out_finding["id"], sid), file=sys.stderr)
            return 2
    slice_verdicts, err = _validated_slice_verdicts(verdict_doc, slice_ids, verdict, raw_findings)
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2

    tokens = _parse_optional_json(a.tokens, "--tokens")
    if tokens is _BAD:
        return 2
    if tokens is None:
        tokens = "UNMEASURED"  # data-model.md #11.1 Measured<T> convention: no recording instrument ran (T-A06 absent)

    reviewer_mutations = _parse_optional_json(a.reviewer_mutations, "--reviewer-mutations")
    if reviewer_mutations is _BAD:
        return 2
    if reviewer_mutations is None:
        reviewer_mutations = "UNKNOWN"

    precheck_path = a.precheck or os.path.join(os.path.dirname(os.path.abspath(a.batch)), "precheck.json")
    precheck_doc = None
    precheck_used = False
    if os.path.exists(precheck_path):
        precheck_doc, err = _load_json(precheck_path, "--precheck")
        if err:
            print("review_record: %s" % err, file=sys.stderr)
            return 2
        precheck_used = True
    markers = already_fixed_markers(precheck_doc)
    for out_finding, raw in findings_out:
        out_finding["class"] = classify_finding(raw, markers)
    findings_list = sorted((f for f, _raw in findings_out), key=lambda f: f["id"])  # C-002

    # Every input is validated above; only now is evidence archived (nothing is
    # written for a refused or malformed invocation). T085 Round 5 (R4-I1): a live
    # record's precheck claim is trusted ONLY via the archived, content-addressed
    # precheck document; R7 B1: the same now holds for the reviewer's verdict file
    # itself, so `gate` re-derives verdict/findings/reviewer from the reviewer's own
    # archived bytes, never from this record's fields.
    records_root = os.path.dirname(os.path.abspath(a.out)) or "."
    precheck_evidence = precheck_evidence_sha256 = None
    try:
        if precheck_used:
            precheck_evidence, precheck_evidence_sha256 = _archive_evidence(
                precheck_path, records_root, ".precheck-evidence")
        verdict_evidence, verdict_evidence_sha256 = _archive_evidence(
            a.verdict_file, records_root, ".verdict-evidence")
    except OSError as exc:
        print("review_record: could not archive evidence alongside --out: %s" % exc, file=sys.stderr)
        return 2

    batch_id = batch.get("batch_id", "UNKNOWN")
    # B1: first_round_go is a DERIVED correctness flag, never the recorded verdict itself.
    first_round_go = (a.round == 1 and verdict == "GO" and len(findings_list) == 0)

    body = {
        "review_id": "REV-%s-%s" % (batch_id, a.round),
        "batch_id": batch_id,
        "round": a.round,
        "round_budget": budget,
        "model_tier": a.tier,
        "effort": a.effort,
        "effort_capability_gap": effort_capability_gap,
        "substrate_evidence": a.substrate_evidence or "cli-flag",
        "verdict": verdict,
        "findings": findings_list,
        "item_id": a.item or _derive_item_id(batch),
        "change_ids": batch.get("changes") if isinstance(batch.get("changes"), list) else "UNKNOWN",
        "slice_lines": _extract_slice_lines(batch),
        "started_at": a.started_at or "UNKNOWN",
        "ended_at": a.ended_at or "UNKNOWN",
        "tokens": tokens,
        "first_round_go": first_round_go,
        "reviewer_mutations": reviewer_mutations,
        "source": "live",
        "precheck_used": precheck_used,
        "precheck_evidence": precheck_evidence,
        "precheck_evidence_sha256": precheck_evidence_sha256,
        # R7 B1: the reviewer's own verdict file, archived content-addressed.
        "verdict_evidence": verdict_evidence,
        "verdict_evidence_sha256": verdict_evidence_sha256,
        "reviewer_dispatch_id": reviewer["dispatch_id"] if reviewer else "UNKNOWN",
        "reviewer_model": reviewer["model"] if reviewer else "UNKNOWN",
        "reviewer_effort": reviewer["effort"] if reviewer else "UNKNOWN",
        "producer_id": producer_id,
        # 11.4.240(F): the tier ACHIEVED between the reviewer's verdict file and this
        # writer -- informational only; `gate` recomputes and never trusts this field.
        "independence_tier": _independence_tier([a.verdict_file]),
    }
    if slice_verdicts is not None:
        body["slice_verdicts"] = slice_verdicts
    return _write_record(body, a.out)


def cmd_backfill(a):
    """Back-fill a ReviewVerdictRecord for a real, already-conducted historical review round that
    predates this tool (no machine-readable ReviewBatch/PreCheckReport/verdict-file exists for it
    -- only a text record). --input is a hand-authored JSON spec citing real facts extracted from
    that real record; every field this tool cannot verify from --input is recorded "UNKNOWN"
    (data-model.md #10.1). `source_evidence` is REQUIRED and MUST name the real document this row
    was reconstructed from -- there is no field-omission path that lets a backfilled row exist
    without citing where it came from (constitution 11.4.6: never fabricate a historical
    sequence).

    T085 Round 5 (R4-I1): `source_evidence` is now ALSO independently
    hash-checked HERE, at authoring time -- but `backfill` itself
    REMAINS a non-refusing producer (constitution 11.4.240 producer !=
    verifier: a prior round's own explicit, tested design decision --
    "backfill itself is legal, the GATE consultation is what must
    refuse it" -- preserved unchanged by this fix). When `source_evidence`
    resolves (against `--records-root`, default: `--out`'s own
    containing directory) to a REAL, readable, non-empty, in-tree,
    non-self-citing file, its CURRENT content sha256 is captured and
    stored as `source_evidence_sha256` -- a content-hash PIN that
    `review_record gate`'s own independent verifier
    (_evidence_hash_verified()) re-derives and re-compares every time it
    later re-checks this record, so a later COVERED verdict cannot be
    satisfied by silently swapping the cited file's content out from
    under it. When the citation does NOT resolve this way (missing,
    out-of-tree, self-citing, unreadable, or a free-text placeholder),
    `source_evidence_sha256` is honestly recorded as "UNKNOWN" and the
    record is STILL WRITTEN (never refused here) -- `gate`'s own
    _evidence_hash_verified() then correctly, deterministically, never
    qualifies such a record as coverage (an "UNKNOWN" hash never matches
    the required 64-lowercase-hex-char shape), which is exactly how the
    T085 Round 2 I-R2-8 / Round 3 R3-I4 forgery-refusal behaviour is
    achieved, entirely at the VERIFIER layer, never by making the
    producer self-police its own acceptance."""
    spec, err = _load_json(a.input, "--input")
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2
    if not isinstance(spec, dict):
        print("review_record: --input must be a JSON object", file=sys.stderr)
        return 2

    required = ("review_id", "batch_id", "round", "verdict", "source_evidence")
    missing = [k for k in required if k not in spec]
    if missing:
        print("review_record: --input missing required key(s): %s" % ", ".join(missing), file=sys.stderr)
        return 2

    source_evidence_raw = spec["source_evidence"]
    if not isinstance(source_evidence_raw, str) or not source_evidence_raw.strip():
        print("review_record: --input 'source_evidence' must be a non-empty string", file=sys.stderr)
        return 2
    source_evidence = source_evidence_raw.strip()

    # Best-effort, NEVER-refusing hash capture (see this function's own
    # docstring for why a failure here is honestly recorded, not fatal).
    source_evidence_sha256 = "UNKNOWN"
    records_root = a.records_root or os.path.dirname(os.path.abspath(a.out)) or "."
    out_real = os.path.realpath(os.path.abspath(a.out))
    root_real = os.path.realpath(records_root)
    resolved = source_evidence if os.path.isabs(source_evidence) else os.path.join(root_real, source_evidence)
    resolved_real = os.path.realpath(resolved)
    try:
        common = os.path.commonpath([root_real, resolved_real])
    except ValueError:
        common = None
    if (
        common == root_real
        and resolved_real != out_real
        and os.path.isfile(resolved_real)
    ):
        try:
            if os.path.getsize(resolved_real) > 0:
                source_evidence_sha256 = _sha256_file(resolved_real)
        except OSError:
            pass  # stays "UNKNOWN" -- an unreadable citation never qualifies at gate time

    verdict = spec["verdict"]
    if verdict not in ("GO", "NO-GO"):
        print("review_record: --input 'verdict' must be 'GO' or 'NO-GO', got %r" % (verdict,), file=sys.stderr)
        return 2

    round_n = spec["round"]
    # M1, extended here to backfill for consistency: data-model.md #10.1 states the SAME
    # ReviewVerdictRecord invariant "round int >=1" for a backfilled row as for a live
    # one; `bool` is an `int` subclass in Python and must not slip through as a round
    # number.
    if not isinstance(round_n, int) or isinstance(round_n, bool) or round_n < 1:
        print("review_record: --input 'round' must be an integer >= 1, got %r" % (round_n,), file=sys.stderr)
        return 2

    findings_out = []
    for finding in spec.get("findings") or []:
        if not isinstance(finding, dict) or "id" not in finding:
            print("review_record: malformed backfill finding entry (missing 'id'): %r" % (finding,), file=sys.stderr)
            return 2
        # 11.4.235(D): same optional, validated, independent field as
        # cmd_record() above -- a backfilled row's "finding_layer" is
        # whatever --input's author could genuinely establish (absent is
        # never an error) or an invalid value refused outright.
        #
        # Retroactivity boundary (M1, non-enforced -- documentation only,
        # no behavioural change): per constitution 11.4.235(D), "clause
        # (D) applies prospectively; recorded verdicts are never rewritten
        # or reclassified". A backfilled "finding_layer" value MUST come
        # from that historical review round's OWN genuinely-recorded
        # evidence (a real finding classification the reviewer actually
        # made at the time), and MUST NOT be assigned, after the fact, to
        # a round that predates 11.4.235(D)'s 2026-10-03 landing date --
        # doing so would be a retroactive reclassification the clause
        # forbids, not an honest backfill of what was already decided.
        # This tool has no mechanism to check a round's date against the
        # clause's landing date, so this boundary is the --input author's
        # obligation, not one this function enforces.
        finding_layer, err = _validated_finding_layer(
            finding, "--input finding %r" % (finding.get("id"),))
        if err:
            print("review_record: %s" % err, file=sys.stderr)
            return 2
        out_finding = {
            "id": finding["id"],
            "severity": finding.get("severity", "UNKNOWN"),
            # Never re-run the live classifier here: no machine ReviewBatch/PreCheckReport/
            # verdict-file input exists for a backfilled historical round, so "class" is
            # whatever --input's author could genuinely establish, or "UNKNOWN" (11.4.6).
            "class": finding.get("class", "UNKNOWN"),
        }
        if finding_layer is not None:
            out_finding["finding_layer"] = finding_layer
        findings_out.append(out_finding)
    findings_out.sort(key=lambda f: f["id"])

    def opt(key):
        val = spec.get(key)
        return val if val not in (None, "") else "UNKNOWN"

    effort_val = opt("effort")
    body = {
        "review_id": spec["review_id"],
        "batch_id": spec["batch_id"],
        "round": round_n,
        "model_tier": opt("model_tier"),
        "effort": effort_val,
        # Schema consistency with cmd_record (B2): computed the same way regardless of
        # `source`, so a downstream report/gate reads one uniform flag whether the record
        # is live or backfilled.
        "effort_capability_gap": (effort_val == "?"),
        "substrate_evidence": opt("substrate_evidence"),
        "verdict": verdict,
        "findings": findings_out,
        "item_id": opt("item_id"),
        "change_ids": spec.get("change_ids") if isinstance(spec.get("change_ids"), list) else "UNKNOWN",
        "slice_lines": spec.get("slice_lines") if isinstance(spec.get("slice_lines"), list) else "UNKNOWN",
        "started_at": opt("started_at"),
        "ended_at": opt("ended_at"),
        # data-model.md #10.1: "tokens ... UNKNOWN on back-filled rows (source=backfill)" -- always,
        # never a caller-supplied value: a backfilled row never claims a measured token count.
        "tokens": "UNKNOWN",
        # B1, applied consistently here too: first_round_go requires zero findings as well
        # as round==1 and verdict=="GO" (RB-005 / 11.4.134) -- the same corrected formula
        # as cmd_record, since backfill constructs the identical ReviewVerdictRecord field.
        "first_round_go": (round_n == 1 and verdict == "GO" and len(findings_out) == 0),
        "reviewer_mutations": spec.get("reviewer_mutations") if isinstance(spec.get("reviewer_mutations"), list) else "UNKNOWN",
        "source": "backfill",
        "source_evidence": source_evidence,
        # T085 Round 5 (R4-I1): content-hash pin, captured at authoring
        # time (see this function's own docstring); independently
        # re-verified by _evidence_hash_verified() every time
        # `review_record gate` later re-checks this record.
        "source_evidence_sha256": source_evidence_sha256,
    }
    return _write_record(body, a.out)


# ---------------------------------------------------------------------------
# `gate` (contract review-batch-and-precheck.md RB-006; T-C11/T078). Producer
# != Verifier (constitution 11.4.240): this subcommand READS the
# ReviewVerdictRecord files `record`/`backfill` already wrote -- it never
# writes, edits, or influences any of them.
# ---------------------------------------------------------------------------
_GATE_REQUIRED_FIELDS = ("batch_id", "round", "verdict", "findings", "model_tier", "effort", "change_ids")


def _gate_collect_records(records_dir):
    """Walks --records recursively for every *.json file, parses each as a
    ReviewVerdictRecord, and returns a list of (doc, path) pairs -- `path`
    (T085 Round 5 R4-I1) is now tracked alongside each parsed `doc` so a
    LATER self-citation check (a record naming ITS OWN file as its proof
    of evidence) can compare an evidence citation against the record's
    own real, on-disk identity; previously only `doc` was kept and a
    record's own path was discarded the instant it was parsed, making a
    self-citing row structurally undetectable.

    Returns None (caller exits 4) on the FIRST file that fails to parse /
    is not an object / is missing a required field / carries a non-integer
    round -- a corrupt record file means no honest coverage verdict is
    possible, never a silent skip (module docstring, C-001)."""
    records = []
    for dirpath, _dirnames, filenames in sorted(os.walk(records_dir)):
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(dirpath, fn)
            doc, err = _load_json(path, "--records/%s" % os.path.relpath(path, records_dir))
            if err:
                print("review_record: gate refused -- %s" % err, file=sys.stderr)
                return None
            if not isinstance(doc, dict):
                print("review_record: gate refused -- %s is not a JSON object" % path, file=sys.stderr)
                return None
            missing = [k for k in _GATE_REQUIRED_FIELDS if k not in doc]
            if missing:
                print("review_record: gate refused -- %s missing required field(s): %s"
                      % (path, ", ".join(missing)), file=sys.stderr)
                return None
            rnd = doc["round"]
            if not isinstance(rnd, int) or isinstance(rnd, bool):
                print("review_record: gate refused -- %s has a non-integer round %r" % (path, rnd),
                      file=sys.stderr)
                return None
            records.append((doc, path))
    return records


def _gate_latest_per_batch(records):
    """RB-006 "that batch's ... latest record": groups by batch_id and keeps
    the highest-round (doc, path) pair per batch. Same-round duplicates never
    reach here: `_gate_same_round_conflicts()` refuses a genuine conflict and
    collapses byte-identical copies first (R7 I1 -- a verdict must never
    depend on filename sort order)."""
    latest = {}
    for rec, path in records:
        bid = rec["batch_id"]
        cur = latest.get(bid)
        if cur is None or rec["round"] > cur[0]["round"]:
            latest[bid] = (rec, path)
    return latest


def _record_identity(rec):
    """Content identity of a record for duplicate/conflict detection: the
    canonical body excluding run_meta/body_hash (C-002)."""
    return _body_hash_of(rec)


def _gate_same_round_conflicts(records):
    """R7 I1: returns (deduped_records, conflicts). Records sharing
    (batch_id, round) with byte-identical bodies collapse to one; records
    sharing (batch_id, round) with DIFFERENT bodies are a conflict -- an
    ambiguous verdict that `gate` refuses outright (exit 4) instead of
    resolving it by filename order (C-003)."""
    groups = {}
    for rec, path in records:
        groups.setdefault((str(rec["batch_id"]), rec["round"]), []).append((rec, path))
    deduped, conflicts = [], []
    for key in sorted(groups):
        members = sorted(groups[key], key=lambda rp: rp[1])
        idents = {_record_identity(r) for r, _p in members}
        if len(idents) > 1:
            conflicts.append((key, [p for _r, p in members]))
        deduped.append(members[0])
    return deduped, conflicts


def _load_ledger(path):
    """Dispatch ledger: JSONL, one row per dispatch event, each with a string
    `key` (the dispatch id) and a `description` carrying the 11.4.182 label.
    Returns ({key: [description, ...]}, None) or (None, reason). A line that
    does not parse is ignored (it can never authenticate anything)."""
    if not path:
        return None, "no --dispatch-ledger given: no reviewer dispatch can be authenticated"
    rows = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict) and isinstance(row.get("key"), str):
                    rows.setdefault(row["key"], []).append(str(row.get("description", "")))
    except (OSError, ValueError) as exc:
        return None, "dispatch ledger unreadable: %s" % exc
    return rows, None


def _dispatch_reuse(records):
    """{reviewer_dispatch_id: set of (batch_id, round)} across every live
    record -- one reviewer dispatch backs exactly one verdict (R7 B1 probe B:
    a producer re-using an earlier reviewer's dispatch for a forged later
    round)."""
    used = {}
    for rec, _path in records:
        did = rec.get("reviewer_dispatch_id")
        if rec.get("source") == "live" and isinstance(did, str) and did not in ("", "UNKNOWN"):
            used.setdefault(did, set()).add((str(rec["batch_id"]), rec["round"]))
    return used


def _verified_evidence_doc(rec, name_key, sha_key, record_path, records_root):
    """Hash-verify the evidence a record cites and parse it. Returns
    (doc, real_path, reason)."""
    base_dir = os.path.dirname(os.path.abspath(record_path))
    if not _evidence_hash_verified(rec.get(name_key), rec.get(sha_key), record_path,
                                   records_root, base_dir):
        return None, None, "%s missing or not hash-verifiable" % name_key
    real = os.path.realpath(os.path.join(base_dir, rec[name_key].strip()))
    doc, err = _load_json(real, name_key)
    if err or not isinstance(doc, dict):
        return None, None, "%s does not parse as a JSON object" % name_key
    return doc, real, None


def _gate_batch_qualifies(rec, record_path, records_root, ctx):
    """RB-006 "a zero-finding GO at the designated tier and effort", decided
    ONLY from sources the record's author cannot silently rewrite after the
    reviewer wrote them (R7 B1 class "the gate trusts unauthenticated record
    fields"). Returns (True, tier) or (False, reason). Every check names its
    reason so a refusal is diagnosable in one step (11.4.201(5)):
      - backfill rows record history and are never coverage (module
        docstring: "a backfilled row records history, it does not gate");
      - source must be "live"; round within the round budget (11.4.276);
      - the record's body_hash must match its body (post-write edits);
      - verdict / findings / reviewer identity are RE-DERIVED from the
        reviewer's own archived, hash-verified verdict file; the record's
        copies must equal them (an edited record that also recomputes
        body_hash is still refused);
      - the reviewer's dispatch must exist in the dispatch ledger with an
        11.4.182 label naming the designated model and effort, must back no
        other verdict, and must differ from the producer identity;
      - the archived precheck must be hash-verified, schema precheck/v1,
        all_pass true, for the same batch;
      - a multi-slice batch needs a GO verdict for every slice (11.4.235(D));
      - the ACHIEVED independence tier is computed from the real evidence
        files; a high-blast seam requires "capability" (11.4.240(F)(4))."""
    source = rec.get("source")
    if source == "backfill":
        return False, "backfill rows record history only and are never gate coverage"
    if source != "live":
        return False, "unrecognised record source %r" % (source,)
    if rec["round"] > ctx["round_budget"]:
        return False, "round %s exceeds the review-round budget %s (11.4.276)" % (rec["round"], ctx["round_budget"])
    if rec.get("body_hash") != _body_hash_of(rec):
        return False, "record body_hash does not match its body (edited after writing)"

    ev, ev_real, reason = _verified_evidence_doc(rec, "verdict_evidence", "verdict_evidence_sha256",
                                                 record_path, records_root)
    if ev is None:
        return False, reason
    verdict = ev.get("verdict")
    findings = ev.get("findings")
    if verdict not in ("GO", "NO-GO") or not isinstance(findings, list):
        return False, "verdict evidence carries no well-formed verdict/findings"
    ev_round = ev.get("round")
    if ev_round is not None and (isinstance(ev_round, bool) or ev_round != rec["round"]):
        return False, "verdict evidence round %r disagrees with the record" % (ev_round,)
    reviewer, err = _validated_reviewer(ev)
    if err or reviewer is None:
        return False, "verdict evidence names no reviewer identity (producer self-certification)"
    rec_layers = {str(f.get("id")): f.get("finding_layer") for f in rec.get("findings") or [] if isinstance(f, dict)}
    ev_layers = {str(f.get("id")): f.get("finding_layer") for f in findings if isinstance(f, dict)}
    if (rec.get("verdict") != verdict or rec_layers != ev_layers
            or rec.get("reviewer_dispatch_id") != reviewer["dispatch_id"]
            or rec.get("model_tier") != reviewer["model"] or rec.get("effort") != reviewer["effort"]):
        return False, "record fields disagree with the reviewer's archived verdict evidence"

    if not (verdict == "GO" and len(findings) == 0):
        return False, "reviewer verdict is not a zero-finding GO"
    if not (reviewer["model"] == DESIGNATED_TIER and reviewer["effort"] == DESIGNATED_EFFORT):
        return False, "reviewer tier/effort %s/%s is not %s/%s" % (
            reviewer["model"], reviewer["effort"], DESIGNATED_TIER, DESIGNATED_EFFORT)

    producer = rec.get("producer_id")
    if not isinstance(producer, str) or producer.strip() in ("", "UNKNOWN"):
        return False, "record names no producer identity"
    if producer == reviewer["dispatch_id"]:
        return False, "producer identity equals the reviewer dispatch (self-certification)"
    if ctx["ledger"] is None:
        return False, ctx["ledger_reason"]
    labels = ctx["ledger"].get(reviewer["dispatch_id"])
    if not labels:
        return False, "reviewer dispatch %r has no dispatch-ledger row" % reviewer["dispatch_id"]
    label_ok = False
    for desc in labels:
        m = _LABEL_RE.search(desc)
        if m and m.group(1) == reviewer["model"] and m.group(2) == reviewer["effort"]:
            label_ok = True
    if not label_ok:
        return False, "dispatch-ledger label for %r does not name %s - %s" % (
            reviewer["dispatch_id"], reviewer["model"], reviewer["effort"])
    if len(ctx["dispatch_use"].get(reviewer["dispatch_id"], ())) > 1:
        return False, "reviewer dispatch %r reused for more than one verdict" % reviewer["dispatch_id"]

    if rec.get("precheck_used") is not True:
        return False, "no precheck was consulted"
    pre, pre_real, reason = _verified_evidence_doc(rec, "precheck_evidence", "precheck_evidence_sha256",
                                                   record_path, records_root)
    if pre is None:
        return False, reason
    if pre.get("schema") != PRECHECK_SCHEMA:
        return False, "archived precheck schema %r is not %s" % (pre.get("schema"), PRECHECK_SCHEMA)
    if pre.get("all_pass") is not True:
        return False, "archived precheck all_pass is not true"
    if pre.get("batch_id") != rec.get("batch_id"):
        return False, "archived precheck belongs to batch %r" % (pre.get("batch_id"),)

    slices = rec.get("slice_lines")
    if isinstance(slices, list) and len(slices) > 1:
        wanted = {s.get("slice_id") for s in slices if isinstance(s, dict)}
        svs = ev.get("slice_verdicts")
        got = {}
        if isinstance(svs, list):
            got = {sv.get("slice_id"): sv.get("verdict") for sv in svs if isinstance(sv, dict)}
        if set(got) != wanted or any(v != "GO" for v in got.values()):
            return False, "multi-slice batch lacks a GO slice verdict for every slice (11.4.235(D))"

    tier = _independence_tier([record_path, ev_real, pre_real, ctx["ledger_path"]])
    if ctx["seam"] in HIGH_BLAST_SEAMS and tier != "capability":
        return False, "seam %s requires capability independence, achieved %s (11.4.240(F))" % (ctx["seam"], tier)
    return True, tier


def cmd_gate(a):
    targets = [c.strip() for c in a.change.split(",") if c.strip()]
    if not targets:
        print("review_record: --change must name at least one change id", file=sys.stderr)
        return 2
    err = _round_budget_error(a.round_budget)
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2

    if not os.path.isdir(a.records):
        print("review_record: gate refused -- --records is not a readable directory: %s" % a.records,
              file=sys.stderr)
        return 4

    records = _gate_collect_records(a.records)
    if records is None:
        return 4
    records, conflicts = _gate_same_round_conflicts(records)
    if conflicts:
        for (bid, rnd), paths in conflicts:
            print("review_record: gate refused -- conflicting records for batch %s round %s: %s"
                  % (bid, rnd, ", ".join(paths)), file=sys.stderr)
        return 4

    ledger, ledger_reason = _load_ledger(a.dispatch_ledger)
    ctx = {
        "seam": a.seam,
        "round_budget": a.round_budget if a.round_budget is not None else ROUND_BUDGET_DEFAULT,
        "ledger": ledger,
        "ledger_reason": ledger_reason,
        "ledger_path": a.dispatch_ledger,
        "dispatch_use": _dispatch_reuse(records),
    }
    latest_by_batch = _gate_latest_per_batch(records)

    uncovered = []
    for change in targets:
        covered_by = None
        reasons = []
        for bid, (rec, record_path) in sorted(latest_by_batch.items()):
            change_ids = rec.get("change_ids")
            if not (isinstance(change_ids, list) and change in change_ids):
                continue
            ok, detail = _gate_batch_qualifies(rec, record_path, a.records, ctx)
            if ok:
                covered_by = (bid, rec.get("round"), detail)
                break
            reasons.append("%s: %s" % (bid, detail))
        if covered_by is None:
            uncovered.append(change)
            print("UNCOVERED %s reason=%s" % (change, "; ".join(reasons) or "no record lists this change"))
        else:
            print("COVERED %s batch=%s round=%s independence=%s seam=%s"
                  % (change, covered_by[0], covered_by[1], covered_by[2], a.seam))

    return 1 if uncovered else 0


def _evidence_hash_verified(evidence, evidence_sha256, record_own_path, records_root, base_dir=None):
    """T085 Round 5 (R4-I1, BLOCKING+IMPORTANT): the ONE shared evidence-
    citation verifier for BOTH a backfill record's `source_evidence` and
    a live record's `precheck_evidence` (section 11.4.227 reuse-not-
    reinvention -- previously this logic existed only for backfill rows,
    and lived inline in _backfill_source_evidence_traceable()).

    T085 Round 4 independent review reproduced THREE concrete forgeries
    the T085 Round 2/3 version of this check (the prior
    _backfill_source_evidence_traceable(), realpath-containment only, no
    content hash, no self-citation check) could not catch, all against
    the committed code:
      (a) a SYMLINK inside --records pointing at /etc/hostname --
          `os.path.abspath()` never follows symlinks, so the (correct)
          containment check only ever saw the symlink's OWN in-tree
          path, never where it actually resolves to.
      (b) a SYMLINKED DIRECTORY inside --records (e.g. pointing at
          /etc) -- the identical gap, one level up: an ancestor
          directory component being a symlink was likewise invisible to
          abspath-only containment.
      (c) a backfill row that cites ITS OWN record file as its evidence
          -- trivially "real, non-empty, in-tree", yet proves nothing
          (circular: the record is its own only witness).
    Fixed, together, below:
      - containment now resolves via `os.path.realpath()` on BOTH the
        evidence path and `records_root` (never `os.path.abspath()`
        alone) -- realpath follows EVERY symlink at EVERY path
        component, so a symlink (file or an ancestor directory) that
        ultimately resolves outside records_root is caught regardless
        of how many levels of indirection it hides behind. Closes (a)
        and (b) with ONE fix (the containment check becomes "is the
        REAL final target inside the REAL root", not merely "does the
        in-tree-looking path string look contained").
      - `record_own_path` (now threaded through from
        _gate_collect_records(), see that function's own docstring) is
        realpath-resolved and compared against the evidence's own
        resolved realpath -- a record whose evidence resolves to ITSELF
        is refused outright. Closes (c).
      - CONTENT-HASH BINDING (the Round 4 reviewer's own explicit "before
        Round 5" recommendation (3), beyond what Round 2/3 ever
        attempted): `evidence_sha256` -- a 64-lowercase-hex-char field
        recorded AT THE TIME the citing record was authored (see
        cmd_backfill()'s new validation, and cmd_record()'s new
        precheck-archival step, both below) -- MUST be present,
        well-formed, and MUST match the CITED FILE'S CURRENT content
        hash, independently recomputed HERE, every time this function
        runs. This closes a FOURTH forgery class neither Round 2 nor
        Round 3 nor the plain realpath-containment fix above addresses
        on its own: a citation that was genuinely valid WHEN AUTHORED
        (a real, in-tree, non-self-citing file) whose content is LATER
        swapped out from under it -- the containment+self-citation
        checks alone would still pass such a record forever, silently
        trusting whatever bytes now happen to live at that path.
    A record with NO `evidence_sha256` at all (every pre-T085-Round-5
    record in this project's own corpus, authored before this field
    existed) is REFUSED -- a deliberate, STRICTER-than-before posture
    (the Round 4 reviewer's own recommended default: "refuse them unless
    explicitly flagged"), never a silent grandfather-and-trust. Existing
    records must be RE-AUTHORED (re-run through the now-hash-capturing
    cmd_backfill/cmd_record) to qualify again."""
    if not isinstance(evidence, str) or not evidence.strip():
        return False
    if evidence.strip().upper() in ("UNKNOWN", "N/A", "TBD"):
        return False
    evidence = evidence.strip()
    if not isinstance(evidence_sha256, str) or not _HASH_RE.fullmatch(evidence_sha256):
        return False

    # R7 I2: a relative citation resolves against the CITING RECORD's own
    # directory (where `record` archived it), never against whichever
    # --records ancestor `gate` happened to be pointed at -- the same record
    # must reach the same verdict from any ancestor. Containment is still
    # checked against the realpath of --records.
    root_real = os.path.realpath(records_root)
    base_real = os.path.realpath(base_dir) if base_dir else root_real
    resolved = evidence if os.path.isabs(evidence) else os.path.join(base_real, evidence)
    resolved_real = os.path.realpath(resolved)

    try:
        common = os.path.commonpath([root_real, resolved_real])
    except ValueError:
        # Different drives/roots (e.g. on a platform where this can
        # happen) -- structurally cannot be contained.
        return False
    if common != root_real:
        return False

    if record_own_path is not None:
        try:
            own_real = os.path.realpath(record_own_path)
        except OSError:
            own_real = None
        if own_real is not None and own_real == resolved_real:
            return False  # self-citation refused

    if not os.path.isfile(resolved_real):
        return False
    try:
        if os.path.getsize(resolved_real) == 0:
            return False
        actual_sha256 = _sha256_file(resolved_real)
    except OSError:
        return False
    return actual_sha256 == evidence_sha256


def main(argv):
    p = argparse.ArgumentParser(prog="review_record")
    sub = p.add_subparsers(dest="cmd_name", required=True)

    r = sub.add_parser("record")
    r.add_argument("--batch", required=True)
    r.add_argument("--round", required=True, type=int)
    r.add_argument("--verdict-file", required=True)
    r.add_argument("--tier", required=True)
    r.add_argument("--effort", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--item")
    r.add_argument("--precheck")
    r.add_argument("--started-at")
    r.add_argument("--ended-at")
    r.add_argument("--tokens")
    r.add_argument("--reviewer-mutations")
    r.add_argument("--substrate-evidence")
    r.add_argument("--producer-id",
                   help="identity of the change's producer (dispatch/session id); must differ from "
                        "the reviewer dispatch id named in --verdict-file (constitution 11.4.240)")
    r.add_argument("--round-budget", type=int,
                   help="constitution 11.4.276 review-round budget, 5..7 (default 5)")

    b = sub.add_parser("backfill")
    b.add_argument("--input", required=True)
    b.add_argument("--out", required=True)
    b.add_argument(
        "--records-root",
        help=(
            "T085 Round 5 (R4-I1): directory 'source_evidence' is resolved "
            "and containment-checked against (default: --out's own "
            "containing directory, the one place-of-record this command "
            "genuinely knows about)."
        ),
    )

    g = sub.add_parser("gate")
    g.add_argument("--change", required=True)
    g.add_argument("--records", required=True)
    g.add_argument("--dispatch-ledger",
                   help="JSONL dispatch ledger (rows with 'key' + 'description' carrying the "
                        "11.4.182 label); without it no reviewer can be authenticated")
    g.add_argument("--seam", choices=SEAMS, default="ordinary",
                   help="ordinary (default) or a high-blast seam requiring capability independence")
    g.add_argument("--round-budget", type=int,
                   help="constitution 11.4.276 review-round budget, 5..7 (default 5)")

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    table = {"record": cmd_record, "backfill": cmd_backfill, "gate": cmd_gate}
    try:
        return table[a.cmd_name](a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("review_record: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
