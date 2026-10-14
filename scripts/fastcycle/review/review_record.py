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
             [--round-budget 5..7] [--producer-uid UID]

Verdict authority (T048 restart rounds 1-3, R7 B1/B2 + V3 F1-F4 + V3
        round-3 R3-F1/R3-F2 -- defect class "the gate trusts record-supplied
        fields"; round 3 REPLACED the decision structure, constitution
        11.4.276(E)). `gate` runs in two phases:
        (1) ADMISSION -- RECORD AS POINTER. Before ANY selection, EVERY
            *.json record under --records must be admitted, and every
            archived reviewer verdict (*.verdict-evidence) must be the
            evidence of an admitted record; any failure -> exit 4, naming
            EVERY failing record/archive. A live record is admitted only
            when its body_hash matches AND each field that selects or
            decides -- batch_id, change_ids, round, review_base,
            review_head, verdict, finding layers, reviewer dispatch, model,
            effort -- equals the value re-derived from the reviewer's own
            verdict file, archived content-addressed by `record` as
            <sha256>.verdict-evidence, read ONCE, parsed from the bytes it
            hashes, duplicate JSON keys refused (the reviewer's REVIEW
            BINDING {batch_id, change_ids, round, review_base, review_head}
            says what it reviewed; a verdict lacking it is inadmissible). A
            backfill row is admitted only with an intact body and NONE of
            the live-only fields (a relabelled live record is refused, and
            dropping those fields orphans the live record's archive). A
            record whose real path lies outside --records is refused.
        (2) DECISION, from evidence-derived fields ONLY. A same-(batch,
            round) conflict between different bodies is refused (exit 4);
            byte-identical copies merge into one verdict (all their paths
            kept -- nothing depends on filename order). Coverage is a
            function of EVERY batch that ever listed a change (per the
            reviewers' change sets): the latest round of each must qualify,
            so an open reviewer NO-GO in ANY batch blocks the change and a
            change dropped after an unresolved round keeps blocking. A live
            unit qualifies only as a zero-finding GO at the designated
            tier/effort whose reviewer dispatch is in the dispatch ledger
            (--dispatch-ledger, JSONL rows {key, event, description}) with a
            "dispatched" row, a LATEST row "complete", no event outside
            dispatched/in-flight/complete, exactly one 11.4.182 label per
            row naming the designated model/effort, backing no other
            verdict, different from the record's producer identity; with an
            archived precheck (schema precheck/v1, all_pass true, same
            batch) for every copy; and, for a multi-slice batch, a GO for
            every slice (11.4.235(D)). Backfill rows are history only and
            never coverage. Each UNCOVERED line names its reasons; each
            COVERED line names the WEAKEST independence tier ACHIEVED
            (11.4.240(F)) and the seam.
        Independence tier (R3-F1): "capability" needs THREE principals --
        the declared producer uid (--producer-uid), the uid running `gate`,
        and the evidence owner. It is reported only when the producer uid is
        a known non-root uid different from the runner, and NEITHER of them
        owns, can write, or can replace any evidence file (record copies,
        verdict and precheck archives, ledger): the file, every directory on
        its symlink-by-symlink resolution chain, and every directory holding
        a chain entry (mode bits, supplementary groups, unknown-group
        conservatism, POSIX ACLs, sticky bits). --producer-uid is a CLAIM: an
        unknown or foreign uid can never raise the tier above what real file
        ownership supports. High-blast seams (release-tag, qa-deploy,
        manual-qa-handoff) require "capability" (11.4.240(F)(4)).
        Honest boundary (11.4.6 / 11.4.240(F)), measured after round 3:
        - On a SINGLE-UID host the uid running `gate` owns every evidence
          file, so the tier is ALWAYS "instance" whatever --producer-uid
          says, and every high-blast seam refuses. "capability" is reachable
          only with an operator-provided uid boundary (11.4.66 / 12) -- a
          release runner and evidence owner distinct from the producer.
        - Ordinary seams remain forgeable on a single-uid host: every input
          is producer-writable, so a producer can author a verdict file
          under an invented reviewer identity, append matching
          dispatched/complete ledger rows (the ledger path is
          caller-supplied), and record it (P2: a multi-artifact forgery).
        - Editing a recorded verdict, re-pointing it, relabelling it as
          backfill, or deleting the record while its archive remains is
          DETECTED (exit 4). Deleting a record AND its archive leaves no
          trace -- undetectable without a 11.4.268 tamper-evident chain.
        - The slice SET and the producer identity are producer-declared by
          nature (from the batch / --producer-id); the producer != reviewer
          checks bind only an honest caller; dispatch reuse is detected only
          within one --records tree; review_base/review_head are compared
          record-vs-evidence-vs-batch but not resolved against the
          repository.
        - A ledger "complete" row proves only that the registry RECORDED a
          completion, not that the review ran to completion: the real agent
          registry marks agents complete at launch (ATM-858 D1).
        Production wiring (R7 I4, honest): no production seam invokes `gate`
        yet; wiring it into the closure/tag tooling -- and fixing the
        registry-completion semantics it would rely on -- is tracked as
        ATM-1127 and is NOT claimed here.

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
                    dispatch id; a reviewer verdict bound to a different
                    batch / change set, or to a review_base/review_head the
                    batch declares differently -- nothing written);
                  2 usage/configuration error (bad args, --round < 1, a
                    --verdict-file "round" that disagrees with --round, a
                    --verdict-file with no "verdict" field or a "verdict"
                    outside {GO, NO-GO}, unreadable or malformed
                    --batch/--verdict-file/--precheck/--input, malformed
                    --tokens/--reviewer-mutations JSON, a missing or
                    non-integer verdict-file 'round', a reviewer-identified
                    verdict file with a missing/malformed review binding
                    {batch_id, change_ids, round, review_base, review_head},
                    a malformed reviewer block or
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
                    ".json" fails to parse (duplicate keys included) / is
                    not a JSON object / is missing a required
                    ReviewVerdictRecord field / carries a non-integer round
                    / lies (by real path) outside --records / is not
                    ADMISSIBLE (see "Verdict authority" phase 1), or an
                    archived *.verdict-evidence is orphaned, or two
                    DIFFERENT records share one (batch_id, round), every
                    offender named on stderr (records unreadable, tampered
                    or ambiguous -- no honest
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
        sets it: coverage is decided from the reviewer's own archived
        verdict file (whose findings make any NO-GO or non-empty GO
        non-coverage regardless of layer); `gate` additionally refuses a
        record whose layers, model or effort differ from that evidence -- a
        CONSISTENCY check on the record's informational copies, so an
        edited record is named as such rather than silently ignored; the
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
import grp
import pwd
import re
import stat
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
# itself distinguish a reviewer-supplied value from a producer-supplied one
# at record time, and does NOT rewrite an absent value (it stays absent in the record, never
# auto-promoted). The 11.4.235(D) "undecidable -> source-defect" default IS
# applied where it decides something -- a GO slice verdict (see
# _validated_slice_verdicts) -- and the reviewer-vs-producer question is
# answered by `gate` reading the reviewer's archived verdict file.
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
# Constitution 11.4.147 closed agent-registry event set. Only a dispatch whose
# rows are all in LEDGER_PASS_EVENTS, that has a "dispatched" row, and whose
# LATEST row is "complete" authenticates a reviewer (V3 m4: a crashed, failed,
# respawned or still-running dispatch never backs a verdict).
LEDGER_PASS_EVENTS = ("dispatched", "in-flight", "complete")
# A git commit id (abbreviated or full; sha1 or sha256 object format).
_COMMIT_RE = re.compile(r"^[0-9a-f]{7,64}$")
# V3 F1: the reviewer's own binding of WHAT it reviewed, carried inside the
# reviewer-authored verdict file and verified at record AND gate time.
BINDING_FIELDS = ("batch_id", "change_ids", "round", "review_base", "review_head")
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


class _DuplicateKeyError(ValueError):
    """A JSON object repeats a key (V3 round 3 m2)."""


def _strict_object(pairs):
    """json object_pairs_hook refusing duplicate keys: a document reading
    "verdict":"NO-GO" ... "verdict":"GO" is ambiguous (a human and a
    first-wins parser see NO-GO, Python's json sees GO), so it is never
    resolved silently -- it is malformed input (V3 round 3 m2)."""
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise _DuplicateKeyError("duplicate JSON key %r" % (key,))
        obj[key] = value
    return obj


def _load_json(path, label):
    """Returns (doc, None) on success, (None, error-message) on failure. Never raises.
    A duplicate key in any JSON object is a parse failure (V3 round 3 m2).

    json.JSONDecodeError is a ValueError subclass; a non-UTF-8 file raises
    UnicodeDecodeError (also a ValueError subclass) while `open(..., encoding="utf-8")`
    is being read by json.load. Both are "malformed input file" per this tool's own
    documented contract (C-001 code 2, "unreadable or malformed"), so both are caught
    here -- previously only json.JSONDecodeError was caught, so a non-UTF-8 file
    propagated uncaught to main()'s BLIND (4) handler instead of the documented 2.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh, object_pairs_hook=_strict_object), None
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


def _uid_gids(uid):
    """Group ids `uid` belongs to, or None when the account is unknown
    (callers then treat any group-write bit as producer-writable)."""
    try:
        pw = pwd.getpwuid(uid)
    except (KeyError, OverflowError):
        return None
    # guard: G-T-SUPP-GROUPS
    gids = {pw.pw_gid}
    try:
        for g in grp.getgrall():
            if pw.pw_name in g.gr_mem:
                gids.add(g.gr_gid)
    except OSError:
        return None
    return gids


def _has_acl(path):
    """True when the inode carries a POSIX ACL (which can grant write access
    the mode bits do not show); unreadable/unsupported -> False."""
    if not hasattr(os, "listxattr"):
        return False
    try:
        return "system.posix_acl_access" in os.listxattr(path, follow_symlinks=False)
    except OSError:
        return False


def _writable_by(st, path, uid, gids):
    """Conservative over-approximation of "can `uid` write this inode":
    the owner, group (or unknown group membership) and other write bits are
    OR-ed, and any POSIX ACL counts as writable."""
    # guard: G-T-ROOT
    if uid == 0:
        return True
    mode = st.st_mode
    # guard: G-T-OWNER-BIT
    if st.st_uid == uid and mode & stat.S_IWUSR:
        return True
    # guard: G-T-GROUP-BIT
    if mode & stat.S_IWGRP and (gids is None or st.st_gid in gids):
        return True
    # guard: G-T-OTHER-BIT
    if mode & stat.S_IWOTH:
        return True
    return _has_acl(path)


def _resolution_chain(path):
    """Resolve `path` one component at a time WITHOUT trusting realpath, so
    every inode an attacker could use to redirect the path is seen (V3
    round-3 m3: realpath alone hides the directory that HOLDS a symlink).
    Returns (leaf_path, leaf_lstat, dirs, edges): `dirs` maps every directory
    traversed (real paths, root included) to its stat; `edges` lists
    (directory, child_lstat) for every entry looked up -- symlinks
    included, so the directory holding each link is checked against the
    link's own owner. Raises OSError (callers degrade to "instance") on a
    missing component, a loop, or a path ending in a directory."""
    pending = [c for c in os.path.abspath(path).split("/") if c]
    cur = "/"
    dirs = {"/": os.stat("/")}
    edges = []
    hops = 0
    while pending:
        comp = pending.pop(0)
        if comp == ".":
            continue
        if comp == "..":
            cur = os.path.dirname(cur) or "/"
            dirs.setdefault(cur, os.stat(cur))
            continue
        child = os.path.join(cur, comp)
        st = os.lstat(child)
        # guard: G-T-LINK-EDGE
        edges.append((cur, st))
        if stat.S_ISLNK(st.st_mode):
            hops += 1
            if hops > 40:
                raise OSError("too many levels of symbolic links: %s" % path)
            target = os.readlink(child)
            if target.startswith("/"):
                cur = "/"
            pending = [c for c in target.split("/") if c] + pending
            continue
        if not pending:
            if not stat.S_ISREG(st.st_mode):
                raise OSError("evidence path is not a regular file: %s" % path)
            return child, st, dirs, edges
        if not stat.S_ISDIR(st.st_mode):
            raise OSError("not a directory: %s" % child)
        cur = child
        dirs[cur] = st
    raise OSError("evidence path resolves to a directory: %s" % path)


def _principal_can_replace(chain, uid, gids):
    """True when `uid` could have written or replaced the resolved evidence:
    it owns or can write the file; it owns ANY directory on the resolution
    chain (an owner can always chmod it); or it can write a directory that
    holds a chain entry (file, directory or symlink) -- a sticky directory
    protecting only entries `uid` does not own."""
    leaf, leaf_st, dirs, edges = chain
    # guard: G-T-LEAF-OWNER
    if leaf_st.st_uid == uid:
        return True
    # guard: G-T-LEAF-WRITABLE
    if _writable_by(leaf_st, leaf, uid, gids):
        return True
    for _dpath, dst in dirs.items():
        # guard: G-T-DIR-OWNER
        if dst.st_uid == uid:
            return True
    for dpath, child_st in edges:
        dst = dirs[dpath]
        # guard: G-T-DIR-WRITABLE
        if _writable_by(dst, dpath, uid, gids) and not (dst.st_mode & stat.S_ISVTX and child_st.st_uid != uid):
            return True
    return False


def _independence_tier(paths, producer_uid, runner_uid=None):
    """Constitution 11.4.240(F): the independence tier ACHIEVED for a set of
    evidence paths -- computed, never claimed (V3 round 3, R3-F1).

    "capability" needs THREE distinct principals: the declared producer
    (`producer_uid`), the uid running this check (`runner_uid`, default the
    effective uid), and whoever owns the evidence. It is returned ONLY when
    the producer uid is a known (passwd-resolvable) non-root uid different
    from the runner, and NEITHER of them owns, can write, or can replace any
    evidence path -- the file, every directory on its symlink-by-symlink
    resolution chain, and every directory holding a chain entry
    (_principal_can_replace). A declared uid is a CLAIM by the caller: an
    unknown or foreign uid can never raise the tier above what the files'
    real ownership supports, because the runner must be unable to write the
    evidence too. On a single-uid host the runner owns every file it wrote,
    so the answer there is ALWAYS "instance", whatever --producer-uid says.
    A root runner can write everything, so it is "instance" too. "model" is
    part of the closed vocabulary but never computed here: no authenticated
    source for the producer's model exists."""
    if runner_uid is None:
        runner_uid = os.geteuid()
    # guard: G-T-PRODUCER-DECLARED
    if (producer_uid is None or isinstance(producer_uid, bool)
            or not isinstance(producer_uid, int) or producer_uid <= 0):
        return "instance"
    # guard: G-T-PRODUCER-IS-RUNNER
    if producer_uid == runner_uid:
        return "instance"
    producer_gids = _uid_gids(producer_uid)
    # guard: G-T-PRODUCER-KNOWN
    if producer_gids is None:
        return "instance"
    # guard: G-T-RUNNER-PRINCIPAL
    principals = ((producer_uid, producer_gids), (runner_uid, _uid_gids(runner_uid)))
    try:
        for path in paths:
            # guard: G-T-PATH-PRESENT
            if path is None:
                return "instance"
            chain = _resolution_chain(path)
            for uid, gids in principals:
                # guard: G-T-PRINCIPAL-CAN-REPLACE
                if _principal_can_replace(chain, uid, gids):
                    return "instance"
    except OSError:
        return "instance"
    return "capability"


def _aggregate_tier(tiers):
    """The tier a COVERED line reports: the WEAKEST achieved across every
    covering batch (11.4.240(F): what was achieved, never the best case)."""
    # guard: G-AG-WEAKEST
    tier = "capability" if all(t == "capability" for t in tiers) else "instance"
    return tier


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
    # not-a-guard: absence is reported to the caller; gate refuses coverage (G-Q-REVIEWER)
    if "reviewer" not in verdict_doc or verdict_doc.get("reviewer") is None:
        return None, None
    rv = verdict_doc.get("reviewer")
    # guard: G-RV-OBJECT
    if not isinstance(rv, dict):
        return None, "--verdict-file 'reviewer' must be a JSON object"
    for key in ("dispatch_id", "model", "effort"):
        val = rv.get(key)
        # guard: G-RV-FIELDS
        if not isinstance(val, str) or not val.strip():
            return None, "--verdict-file 'reviewer.%s' must be a non-empty string, got %r" % (key, val)
    return {"dispatch_id": rv["dispatch_id"].strip(), "model": rv["model"].strip(),
            "effort": rv["effort"].strip()}, None


def _validated_binding(doc):
    """V3 F1: the reviewer's own statement of WHAT it reviewed, carried in
    the verdict file it authored. Returns (binding, None) with change_ids
    sorted, or (None, reason). All of BINDING_FIELDS are required:
    batch_id a non-empty string; change_ids a non-empty list of distinct
    non-empty strings; round an integer >= 1 (never a bool); review_base and
    review_head commit-shaped. A verdict that does not say what it covers
    can never be attached to anything (it is not coverage evidence)."""
    missing = [k for k in BINDING_FIELDS if k not in doc]
    # guard: G-BD-PRESENT
    if missing:
        return None, "review binding missing field(s): %s" % ", ".join(missing)
    bid = doc.get("batch_id")
    # guard: G-BD-BATCH-SHAPE
    if not isinstance(bid, str) or not bid.strip() or bid != bid.strip():
        return None, "review binding batch_id must be a non-empty, unpadded string, got %r" % (bid,)
    cids = doc.get("change_ids")
    # guard: G-BD-CHANGES-SHAPE
    if (not isinstance(cids, list) or not cids
            or any(not isinstance(c, str) or not c.strip() or c != c.strip() for c in cids)):
        return None, "review binding change_ids must be a non-empty list of non-empty strings, got %r" % (cids,)
    # guard: G-BD-CHANGES-DISTINCT
    if len(set(cids)) != len(cids):
        return None, "review binding change_ids lists a change twice: %r" % (cids,)
    rnd = doc.get("round")
    # guard: G-BD-ROUND
    if not isinstance(rnd, int) or isinstance(rnd, bool) or rnd < 1:
        return None, "review binding round must be an integer >= 1, got %r" % (rnd,)
    for key in ("review_base", "review_head"):
        val = doc.get(key)
        # guard: G-BD-COMMIT-SHAPE
        if not isinstance(val, str) or not _COMMIT_RE.fullmatch(val):
            return None, "review binding %s must be a commit id (7-64 lowercase hex), got %r" % (key, val)
    return {"batch_id": bid, "change_ids": sorted(cids), "round": rnd,
            "review_base": doc["review_base"], "review_head": doc["review_head"]}, None


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
    # guard: G-R-ROUND-BUDGET
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
    # guard: G-R-DESIGNATED-TIER
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

    # M1 + R7 M-a + V3 m1: the verdict file's own 'round' is MANDATORY, must be a
    # genuine integer (bool is an int subclass -- `true` must never read as round 1)
    # and must equal --round; any violation is a usage error, never a silent pick.
    verdict_round = verdict_doc.get("round")
    if verdict_round is None:
        print("review_record: --verdict-file must carry the reviewer's own 'round' "
              "(a verdict that does not say which round it closes is not evidence)", file=sys.stderr)
        return 2
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
    binding = None
    if reviewer is not None:
        # The reviewer's own statement of what answered must agree with the tier/effort
        # this invocation is recording -- a mismatch is refused, never reconciled.
        # guard: G-R-REVIEWER-MATCHES-CLI
        if reviewer["model"] != a.tier or reviewer["effort"] != a.effort:
            print("review_record: refused -- --verdict-file reviewer model/effort %s/%s disagrees "
                  "with --tier/--effort %s/%s" % (reviewer["model"], reviewer["effort"], a.tier, a.effort),
                  file=sys.stderr)
            return 1
        # guard: G-R-PRODUCER-NOT-REVIEWER
        if producer_id == reviewer["dispatch_id"]:
            print("review_record: refused -- --producer-id equals the reviewer dispatch id %r: a "
                  "producer can never certify its own work (constitution 11.4.240)"
                  % (producer_id,), file=sys.stderr)
            return 1
    # V3 F1: a reviewer verdict states WHAT it reviewed; it can be recorded only
    # against exactly that batch, change set and (when the batch declares them)
    # commit range -- never replayed onto another batch or a wider change set.
    # The binding is REQUIRED when the verdict names a reviewer; a reviewer-less
    # verdict that carries one is held to it too (V3 round 3: `gate` admits a
    # record only when its copies equal the archived binding, so a reviewer-less
    # verdict with NO binding is written but is inadmissible to `gate`).
    if reviewer is not None or any(k in verdict_doc for k in ("batch_id", "change_ids",
                                                              "review_base", "review_head")):
        binding, err = _validated_binding(verdict_doc)
        if err:
            print("review_record: --verdict-file %s" % err, file=sys.stderr)
            return 2
        b_changes = batch.get("changes")
        b_ok_changes = (isinstance(b_changes, list) and all(isinstance(c, str) for c in b_changes)
                        and len(set(b_changes)) == len(b_changes))
        # guard: G-R-BINDING-BATCH
        if (batch.get("batch_id") != binding["batch_id"] or not b_ok_changes
                or sorted(b_changes) != binding["change_ids"]):
            print("review_record: refused -- --verdict-file is bound to batch %r changes %s; --batch is "
                  "%r changes %r: a reviewer verdict covers only what it reviewed (constitution 11.4.240)"
                  % (binding["batch_id"], binding["change_ids"], batch.get("batch_id"), b_changes),
                  file=sys.stderr)
            return 1
        for key in ("review_base", "review_head"):
            # guard: G-R-BINDING-COMMITS
            if key in batch and batch.get(key) != binding[key]:
                print("review_record: refused -- --verdict-file %s %r differs from the batch's declared "
                      "%s %r" % (key, binding[key], key, batch.get(key)), file=sys.stderr)
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
        # V3 F1: the reviewed commit range, copied from the reviewer's binding; `gate`
        # re-derives it from the archived verdict file and requires these to equal it.
        "review_base": binding["review_base"] if binding else "UNKNOWN",
        "review_head": binding["review_head"] if binding else "UNKNOWN",
        # 11.4.240(F): informational only -- the writer stands in for BOTH producer
        # and runner here, so this is always "instance"; `gate` recomputes the tier
        # from real file ownership and never reads this field.
        "independence_tier": _independence_tier([a.verdict_file], os.geteuid()),
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
# Fields only a live `record` writes; a backfill row carrying any of them is a
# relabelled live record (V3 round 3, R3-F2), never history.
_LIVE_ONLY_FIELDS = ("verdict_evidence", "verdict_evidence_sha256", "precheck_evidence",
                     "precheck_evidence_sha256", "reviewer_dispatch_id")
_VERDICT_EVIDENCE_SUFFIX = ".verdict-evidence"


def _gate_collect_records(records_dir):
    """Walks --records recursively for every *.json file and parses each as
    a ReviewVerdictRecord. Returns (records, failures): `records` a list of
    (doc, path) pairs, `failures` a list of (path, reason) for every file
    that does not parse (duplicate JSON keys included), is not an object,
    misses a required field, carries a non-integer round, or whose REAL
    path lies outside --records (V3 round 3 m3: a record symlinked in from
    elsewhere is not part of this tree). The caller refuses the whole run
    (exit 4) when any failure exists, naming every one -- a corrupt record
    means no honest coverage verdict is possible, never a silent skip
    (module docstring, C-001)."""
    records, failures = [], []
    root_real = os.path.realpath(records_dir)
    for dirpath, _dirnames, filenames in sorted(os.walk(records_dir)):
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(dirpath, fn)
            real = os.path.realpath(path)
            # guard: G-C-CONTAINED
            if os.path.commonpath([root_real, real]) != root_real:
                failures.append((path, "real path %s lies outside --records" % real))
                continue
            doc, err = _load_json(path, "--records/%s" % os.path.relpath(path, records_dir))
            # guard: G-C-PARSE
            if err:
                failures.append((path, err))
                continue
            # guard: G-C-OBJECT
            if not isinstance(doc, dict):
                failures.append((path, "not a JSON object"))
                continue
            missing = [k for k in _GATE_REQUIRED_FIELDS if k not in doc]
            # guard: G-C-REQUIRED
            if missing:
                failures.append((path, "missing required field(s): %s" % ", ".join(missing)))
                continue
            rnd = doc["round"]
            # guard: G-C-INT-ROUND
            if not isinstance(rnd, int) or isinstance(rnd, bool):
                failures.append((path, "non-integer round %r" % (rnd,)))
                continue
            records.append((doc, path))
    return records, failures


def _batch_key(batch_id):
    """V3 m5: ONE batch identity used everywhere (conflicts, latest round,
    dispatch reuse, precheck binding) -- the canonical JSON of the value, so
    1 and "1" are two different batches in every place, never one batch in
    one place and two in another."""
    # guard: G-K-BATCH-KEY
    return _canon(batch_id)


def _admit_live(rec, path, records_root):
    """RECORD AS POINTER (V3 round 3, R3-F2 -- the third member of the class
    "the gate trusts record-supplied fields"): a live record is admitted
    only when its body is intact AND every field that selects or decides --
    batch_id, change_ids, round, review_base, review_head, verdict, finding
    layers, reviewer identity, model, effort -- equals the value re-derived
    from the reviewer's own archived verdict evidence (hash-verified, read
    once, parsed from the hashed bytes, duplicate keys refused). Returns
    (unit, None) or (None, reason). The unit carries ONLY evidence-derived
    selection fields; nothing downstream reads the record's copies."""
    # guard: G-A-BODY-HASH
    if rec.get("body_hash") != _body_hash_of(rec):
        return None, "record body_hash does not match its body (edited after writing)"
    ev, ev_real, reason = _verified_evidence_doc(rec, "verdict_evidence", "verdict_evidence_sha256",
                                                 path, records_root)
    # guard: G-A-EVIDENCE-VERIFIED
    if ev is None:
        return None, reason
    verdict = ev.get("verdict")
    findings = ev.get("findings")
    # guard: G-A-EVIDENCE-WELLFORMED
    if verdict not in ("GO", "NO-GO") or not isinstance(findings, list):
        return None, "verdict evidence carries no well-formed verdict/findings"
    binding, err = _validated_binding(ev)
    # guard: G-A-BINDING-PRESENT
    if err:
        return None, "verdict evidence %s" % err
    actual_reviewer, err = _validated_reviewer(ev)
    # guard: G-A-REVIEWER-WELLFORMED
    if err:
        return None, "verdict evidence %s" % err
    reviewer = actual_reviewer
    if reviewer is None:
        # A reviewer-less verdict: the record must say so (UNKNOWN), and its
        # tier/effort copies are the CLI's own -- admitted, never coverage.
        reviewer = {"dispatch_id": "UNKNOWN", "model": rec.get("model_tier"), "effort": rec.get("effort")}
    rec_changes = rec.get("change_ids")
    # guard: G-A-BINDING-EQUAL
    if (_batch_key(binding["batch_id"]) != _batch_key(rec["batch_id"])
            or not isinstance(rec_changes, list)
            or any(not isinstance(c, str) for c in rec_changes)
            or len(set(rec_changes)) != len(rec_changes)
            or sorted(rec_changes) != binding["change_ids"]
            or rec.get("review_base") != binding["review_base"]
            or rec.get("review_head") != binding["review_head"]):
        return None, "record batch/changes/commits disagree with the reviewer's review binding"
    # guard: G-A-ROUND-EQUAL
    if binding["round"] != rec["round"]:
        return None, "verdict evidence round %r disagrees with the record" % (binding["round"],)
    rec_layers = {str(f.get("id")): f.get("finding_layer") for f in rec.get("findings") or [] if isinstance(f, dict)}
    ev_layers = {str(f.get("id")): f.get("finding_layer") for f in findings if isinstance(f, dict)}
    # guard: G-A-FIELDS-EQUAL
    if (rec.get("verdict") != verdict or rec_layers != ev_layers
            or rec.get("reviewer_dispatch_id") != reviewer["dispatch_id"]
            or rec.get("model_tier") != reviewer["model"] or rec.get("effort") != reviewer["effort"]):
        return None, "record fields disagree with the reviewer's archived verdict evidence"
    return {"source": "live", "batch_id": binding["batch_id"], "round": binding["round"],
            "change_ids": list(binding["change_ids"]), "verdict": verdict, "findings": findings,
            "reviewer": actual_reviewer, "slice_verdicts": ev.get("slice_verdicts"),
            "rec": rec, "paths": [path], "ev_reals": [ev_real], "identity": _body_hash_of(rec)}, None


def _admit_backfill(rec, path):
    """A backfill row is history: never coverage, only a possible BLOCK. It
    has no reviewer evidence, so its fields are its own -- admitted when its
    body is intact and it carries NONE of the live-only fields (a live
    record relabelled "backfill" is refused, R3-F2). Removing those fields
    too orphans the live record's archived verdict, which cmd_gate refuses
    separately (_orphaned_evidence)."""
    # guard: G-B-BODY-HASH
    if rec.get("body_hash") != _body_hash_of(rec):
        return None, "record body_hash does not match its body (edited after writing)"
    carried = [k for k in _LIVE_ONLY_FIELDS if k in rec]
    # guard: G-B-NO-LIVE-FIELDS
    if carried:
        return None, "backfill row carries live-only field(s) %s (a relabelled live record)" % ", ".join(carried)
    cids = rec.get("change_ids")
    # guard: G-B-CHANGES-SHAPE
    if cids != "UNKNOWN" and (not isinstance(cids, list) or any(not isinstance(c, str) for c in cids)):
        return None, "backfill change_ids must be a list of strings or \"UNKNOWN\", got %r" % (cids,)
    return {"source": "backfill", "batch_id": rec["batch_id"], "round": rec["round"],
            "change_ids": cids if isinstance(cids, list) else [], "verdict": rec.get("verdict"),
            "findings": rec.get("findings"), "reviewer": None, "slice_verdicts": None,
            "rec": rec, "paths": [path], "ev_reals": [], "identity": _body_hash_of(rec)}, None


def _admit_record(rec, path, records_root):
    """Closed source set {live, backfill}; anything else is inadmissible."""
    source = rec.get("source")
    # not-a-guard: routing to the live admission (its own guards are G-A-*)
    if source == "live":
        return _admit_live(rec, path, records_root)
    # guard: G-A-SOURCE
    if source != "backfill":
        return None, "unrecognised record source %r" % (source,)
    return _admit_backfill(rec, path)


def _orphaned_evidence(records_dir, units):
    """V3 round 3 (R3-F2, strengthening the admitted deletion boundary):
    every archived reviewer verdict (*.verdict-evidence) under --records
    must be the evidence of an admitted live record. An orphan means a
    record that pointed at it was removed, relabelled or re-pointed -- the
    reviewer's statement still exists, so the gate refuses to decide
    without it (exit 4). Deleting the record AND its archive remains
    undetectable without a 11.4.268 tamper-evident chain."""
    referenced = set()
    for unit in units:
        referenced.update(unit["ev_reals"])
    orphans = []
    for dirpath, _dirnames, filenames in sorted(os.walk(records_dir)):
        for fn in sorted(filenames):
            path = os.path.join(dirpath, fn)
            # guard: G-O-ORPHAN
            if fn.endswith(_VERDICT_EVIDENCE_SUFFIX) and os.path.realpath(path) not in referenced:
                orphans.append(path)
    return orphans


def _gate_rounds_per_batch(records):
    """RB-006 "that batch's ... latest record": {batch_key: [(unit, path), ...]}
    with each batch's units in ascending round order -- the LAST entry is
    the batch's latest round. Same-round duplicates never reach here:
    `_gate_same_round_conflicts()` refuses a genuine conflict and merges
    byte-identical copies first."""
    by_batch = {}
    for rec, path in records:
        by_batch.setdefault(_batch_key(rec["batch_id"]), []).append((rec, path))
    for members in by_batch.values():
        # guard: G-V-LATEST-ROUND
        members.sort(key=lambda rp: rp[0]["round"])
    return by_batch


def _gate_same_round_conflicts(records):
    """R7 I1 / V3 round 3 m1: returns (merged, conflicts) over ADMITTED units.
    Units sharing an evidence-derived (batch_id, round) with DIFFERENT record
    bodies are a conflict (exit 4, C-003). Byte-identical bodies are one
    verdict: they merge into one unit carrying EVERY copy's record and
    evidence paths, so nothing depends on which copy sorts first (each copy
    was already admitted on its own, and the tier is computed over all of
    them)."""
    groups = {}
    for rec, path in records:
        groups.setdefault((_batch_key(rec["batch_id"]), rec["round"]), []).append((rec, path))
    deduped, conflicts = [], []
    for key in sorted(groups):
        members = sorted(groups[key], key=lambda rp: rp[1])
        idents = {r["identity"] for r, _p in members}
        # guard: G-S-CONFLICT
        if len(idents) > 1:
            conflicts.append((key, [p for _r, p in members]))
        # guard: G-S-MERGE
        deduped.append(members[0])
        merged = dict(deduped[-1][0])
        merged["paths"] = sorted({p for r, _p in members for p in r["paths"]})
        merged["ev_reals"] = sorted({e for r, _p in members for e in r["ev_reals"]})
        deduped[-1] = (merged, deduped[-1][1])
    return deduped, conflicts


def _load_ledger(path):
    """Dispatch ledger: JSONL, one row per dispatch event, each with a string
    `key` (the dispatch id), an `event` from the 11.4.147 closed set and a
    `description` carrying the 11.4.182 label. Read ONCE. Returns
    ({key: [(event, description), ...] in file order}, None) or (None,
    reason). A line that does not parse is ignored (it can never
    authenticate anything); a row with a duplicate JSON key makes the whole
    ledger unreadable (an ambiguous row must not be resolved by whichever
    key a parser keeps); a row with a missing event keeps event None, which
    never authenticates (see _ledger_authenticates)."""
    # guard: G-L-PRESENT
    if not path:
        return None, "no --dispatch-ledger given: no reviewer dispatch can be authenticated"
    rows = {}
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        for line in data.decode("utf-8").splitlines():
            try:
                row = json.loads(line, object_pairs_hook=_strict_object)
            except _DuplicateKeyError:
                raise
            except ValueError:
                continue
            if isinstance(row, dict) and isinstance(row.get("key"), str):
                # guard: G-L-EVENT-NONE
                event = row.get("event") if isinstance(row.get("event"), str) else None
                rows.setdefault(row["key"], []).append((event, str(row.get("description", ""))))
    except (OSError, ValueError) as exc:
        return None, "dispatch ledger unreadable: %s" % exc
    return rows, None


def _ledger_authenticates(rows, dispatch_id, model, effort):
    """V3 m4: None when the dispatch-ledger rows for `dispatch_id` show a
    reviewer dispatch at `model`/`effort` whose LATEST recorded event is
    "complete", else the refusal reason. Every row must carry an event in
    LEDGER_PASS_EVENTS (a crashed / failed / respawned dispatch never backs
    a verdict), there must be a "dispatched" row, the LATEST row must be
    "complete", and EVERY row's description must carry exactly one
    11.4.182 label naming model/effort (a second label is ambiguous -- the
    first-match label-injection shape).
    Honest limit (V3 round 3 m4, ATM-858 D1): this proves only that the
    registry RECORDED a completion, not that the review ran to completion
    -- the real agent registry marks an agent "complete" at launch
    (ATM-858 D1, tracked with the production wiring in ATM-1127)."""
    # guard: G-L-HAS-ROWS
    if not rows:
        return "reviewer dispatch %r has no dispatch-ledger row" % dispatch_id
    events = [ev for ev, _desc in rows]
    bad = [ev for ev in events if ev not in LEDGER_PASS_EVENTS]
    # guard: G-L-EVENTS-CLOSED
    if bad:
        return "dispatch-ledger events for %r include %r: only %s dispatches authenticate" % (
            dispatch_id, bad[0], "/".join(LEDGER_PASS_EVENTS))
    # guard: G-L-DISPATCHED
    if "dispatched" not in events:
        return "dispatch-ledger has no 'dispatched' row for %r" % dispatch_id
    # guard: G-L-LATEST-COMPLETE
    if events[-1] != "complete":
        return "dispatch-ledger latest event for %r is %r, not 'complete'" % (dispatch_id, events[-1])
    # guard: G-L-ALL-ROWS
    for _ev, desc in rows:
        labels = _LABEL_RE.findall(desc)
        # guard: G-L-ONE-LABEL
        if len(labels) != 1:
            return "dispatch-ledger row for %r carries %d 11.4.182 labels (exactly one required)" % (
                dispatch_id, len(labels))
        # guard: G-L-LABEL-MATCH
        if labels[0] != (model, effort):
            return "dispatch-ledger label for %r does not name %s - %s" % (dispatch_id, model, effort)
    return None


def _dispatch_reuse(records):
    """{reviewer_dispatch_id: set of (batch_id, round)} across every admitted
    live unit -- read from the reviewer's EVIDENCE, never the record -- one
    reviewer dispatch backs exactly one verdict (R7 B1 probe B: a producer
    re-using an earlier reviewer's dispatch for a forged later round)."""
    used = {}
    for rec, _path in records:
        reviewer = rec.get("reviewer")
        if rec.get("source") == "live" and reviewer is not None:
            used.setdefault(reviewer["dispatch_id"], set()).add((_batch_key(rec["batch_id"]), rec["round"]))
    return used


def _verified_evidence_doc(rec, name_key, sha_key, record_path, records_root):
    """Hash-verify the evidence a record cites and parse it from the SAME
    bytes that were hashed (V3 m2: no re-open between verify and use;
    V3 round 3 m2: duplicate JSON keys refused). Returns (doc, real_path,
    reason)."""
    base_dir = os.path.dirname(os.path.abspath(record_path))
    data, real = _evidence_bytes_verified(rec.get(name_key), rec.get(sha_key), record_path,
                                          records_root, base_dir)
    # not-a-guard: propagates _evidence_bytes_verified's refusals (G-E-*)
    if data is None:
        return None, None, "%s missing or not hash-verifiable" % name_key
    try:
        doc = json.loads(data.decode("utf-8"), object_pairs_hook=_strict_object)
    except ValueError as exc:
        return None, None, "%s does not parse as JSON: %s" % (name_key, exc)
    # guard: G-A-EVIDENCE-OBJECT
    if not isinstance(doc, dict):
        return None, None, "%s does not parse as a JSON object" % name_key
    return doc, real, None


def _gate_batch_qualifies(rec, record_path, records_root, ctx):
    """RB-006 "a zero-finding GO at the designated tier and effort" for one
    ADMITTED unit (`rec`: every selection field already re-derived from the
    reviewer's archived evidence by _admit_live). Returns (True, tier) or
    (False, reason); every refusal names its reason (11.4.201(5)):
      - round within the round budget (11.4.276) (backfill units never get
        here -- the caller treats them as history, never coverage);
      - the reviewer's evidence must name a reviewer, carry a zero-finding
        GO, at the designated tier/effort;
      - the record must name a producer identity different from the
        reviewer dispatch (self-declared -- binds only an honest caller);
      - the reviewer's dispatch must have a completed dispatch in the
        ledger (_ledger_authenticates) and back no other verdict;
      - EVERY copy's archived precheck must be hash-verified, schema
        precheck/v1, all_pass true, for the same batch;
      - a multi-slice batch needs a GO verdict for every slice (11.4.235(D));
      - the ACHIEVED independence tier is computed over every evidence path
        against BOTH the declared producer uid and the uid running gate; a
        high-blast seam requires "capability"."""
    # Only admitted LIVE units reach here: _admit_record() accepts exactly two
    # sources and _gate_change_verdict() routes every backfill unit away first.
    # guard: G-Q-ROUND-BUDGET
    if rec["round"] > ctx["round_budget"]:
        return False, "round %s exceeds the review-round budget %s (11.4.276)" % (rec["round"], ctx["round_budget"])
    reviewer = rec["reviewer"]
    verdict = rec["verdict"]
    findings = rec["findings"]
    # guard: G-Q-REVIEWER
    if reviewer is None:
        return False, "verdict evidence names no reviewer identity (producer self-certification)"
    # guard: G-Q-ZERO-FINDING-GO
    if not (verdict == "GO" and len(findings) == 0):
        return False, "reviewer verdict is not a zero-finding GO"
    # guard: G-Q-DESIGNATED-TIER
    if not (reviewer["model"] == DESIGNATED_TIER and reviewer["effort"] == DESIGNATED_EFFORT):
        return False, "reviewer tier/effort %s/%s is not %s/%s" % (
            reviewer["model"], reviewer["effort"], DESIGNATED_TIER, DESIGNATED_EFFORT)

    record = rec["rec"]
    producer = record.get("producer_id")
    # guard: G-Q-PRODUCER-NAMED
    if not isinstance(producer, str) or producer.strip() in ("", "UNKNOWN"):
        return False, "record names no producer identity"
    # guard: G-Q-PRODUCER-NOT-REVIEWER
    if producer == reviewer["dispatch_id"]:
        return False, "producer identity equals the reviewer dispatch (self-certification)"
    # guard: G-Q-LEDGER-READABLE
    if ctx["ledger"] is None:
        return False, ctx["ledger_reason"]
    reason = _ledger_authenticates(ctx["ledger"].get(reviewer["dispatch_id"]), reviewer["dispatch_id"],
                                   reviewer["model"], reviewer["effort"])
    # guard: G-Q-LEDGER-AUTH
    if reason:
        return False, reason
    # guard: G-Q-DISPATCH-REUSE
    if len(ctx["dispatch_use"].get(reviewer["dispatch_id"], ())) > 1:
        return False, "reviewer dispatch %r reused for more than one verdict" % reviewer["dispatch_id"]

    # guard: G-Q-PRECHECK-USED
    if record.get("precheck_used") is not True:
        return False, "no precheck was consulted"
    pre_reals = []
    for copy_path in rec["paths"]:
        pre, pre_real, reason = _verified_evidence_doc(record, "precheck_evidence", "precheck_evidence_sha256",
                                                       copy_path, records_root)
        # guard: G-Q-PRECHECK-VERIFIED
        if pre is None:
            return False, reason
        # guard: G-Q-PRECHECK-SCHEMA
        if pre.get("schema") != PRECHECK_SCHEMA:
            return False, "archived precheck schema %r is not %s" % (pre.get("schema"), PRECHECK_SCHEMA)
        # guard: G-Q-PRECHECK-ALL-PASS
        if pre.get("all_pass") is not True:
            return False, "archived precheck all_pass is not true"
        # guard: G-Q-PRECHECK-BATCH
        if _batch_key(pre.get("batch_id")) != _batch_key(rec.get("batch_id")):
            return False, "archived precheck belongs to batch %r" % (pre.get("batch_id"),)
        pre_reals.append(pre_real)

    # The slice SET is producer-declared by nature (it comes from the batch the
    # producer authored, and the reviewer's binding does not name slices) --
    # an admitted boundary; only the per-slice VERDICTS are evidence-derived.
    slices = record.get("slice_lines")
    if isinstance(slices, list) and len(slices) > 1:
        wanted = {s.get("slice_id") for s in slices if isinstance(s, dict)}
        svs = rec["slice_verdicts"]
        got = {}
        if isinstance(svs, list):
            got = {sv.get("slice_id"): sv.get("verdict") for sv in svs if isinstance(sv, dict)}
        # guard: G-Q-SLICES
        if set(got) != wanted or any(v != "GO" for v in got.values()):
            return False, "multi-slice batch lacks a GO slice verdict for every slice (11.4.235(D))"

    tier = _independence_tier(rec["paths"] + rec["ev_reals"] + pre_reals + [ctx["ledger_path"]],
                              ctx["producer_uid"])
    # guard: G-Q-SEAM-TIER
    if ctx["seam"] in HIGH_BLAST_SEAMS and tier != "capability":
        return False, "seam %s requires capability independence, achieved %s (11.4.240(F))" % (ctx["seam"], tier)
    return True, tier


def _lists(rec, change):
    cids = rec.get("change_ids")
    return isinstance(cids, list) and change in cids


def _gate_change_verdict(change, by_batch, records_root, ctx):
    """V3 F2: coverage is a function of EVERY batch that ever listed `change`
    (per the reviewers' evidence-derived change sets), never of the first
    batch that happens to qualify. For each such batch, take the latest
    round that lists the change:
      - if it is the batch's latest round, it must qualify: it covers, or its
        refusal BLOCKS (an open reviewer NO-GO in ANY batch blocks the
        change, 11.4.134 / 11.4.235(D); conservative-safe, 11.4.201(4));
      - if a later round of the batch dropped the change, the round that last
        listed it must still qualify, else it BLOCKS (an unresolved verdict on
        the change is never silently abandoned); a qualifying one is neutral
        (no coverage from this batch, no block -- 11.4.201(1) guard);
      - a backfill row is history: a zero-finding GO is neutral, anything
        else BLOCKS.
    Returns (covering [(batch_id, round, tier)], blockers [reason, ...],
    notes [why a neutral batch gives no coverage, ...])."""
    covering, blockers, notes = [], [], []
    for bkey in sorted(by_batch):
        members = by_batch[bkey]
        listing = [rp for rp in members if _lists(rp[0], change)]
        if not listing:
            continue
        # guard: G-V-LAST-LISTING
        rec, path = listing[-1]
        bid = rec["batch_id"]
        # guard: G-V-LATEST-COVERS
        is_latest = rec is members[-1][0]
        # guard: G-V-BACKFILL-HISTORY
        if rec.get("source") == "backfill":
            # guard: G-V-BACKFILL-BLOCKS
            if not (rec.get("verdict") == "GO" and not rec.get("findings")):
                blockers.append("%s: backfilled round %s is not a zero-finding GO (history, unresolved)"
                                % (bid, rec["round"]))
            else:
                notes.append("%s: backfill rows record history only and are never gate coverage" % (bid,))
            continue
        ok, detail = _gate_batch_qualifies(rec, path, records_root, ctx)
        # guard: G-V-LATEST-COVERS
        if ok and is_latest:
            covering.append((bid, rec["round"], detail))
        # guard: G-V-REFUSAL-BLOCKS
        elif not ok:
            blockers.append("%s: %s" % (bid, detail) if is_latest else
                            "%s: round %s, the last round listing this change, does not qualify (%s) "
                            "and a later round dropped it" % (bid, rec["round"], detail))
        else:
            notes.append("%s: a later round dropped this change (no coverage from this batch)" % (bid,))
    return covering, blockers, notes


def cmd_gate(a):
    targets = [c.strip() for c in a.change.split(",") if c.strip()]
    # guard: G-G-CHANGE-NAMED
    if not targets:
        print("review_record: --change must name at least one change id", file=sys.stderr)
        return 2
    err = _round_budget_error(a.round_budget)
    # guard: G-G-BUDGET-RANGE
    if err:
        print("review_record: %s" % err, file=sys.stderr)
        return 2

    # guard: G-G-RECORDS-DIR
    if not os.path.isdir(a.records):
        print("review_record: gate refused -- --records is not a readable directory: %s" % a.records,
              file=sys.stderr)
        return 4

    # Phase 1 -- ADMISSION of EVERY record, before any selection (R3-F2).
    collected, failures = _gate_collect_records(a.records)
    units = []
    for rec, path in collected:
        unit, reason = _admit_record(rec, path, a.records)
        # not-a-guard: collects each admission refusal for G-G-ADMISSION
        if unit is None:
            failures.append((path, reason))
        else:
            units.append((unit, path))
    # guard: G-G-ADMISSION
    if failures:
        for path, reason in failures:
            print("review_record: gate refused -- inadmissible record %s: %s" % (path, reason), file=sys.stderr)
        return 4
    orphans = _orphaned_evidence(a.records, [u for u, _p in units])
    # guard: G-G-ORPHANS
    if orphans:
        for path in orphans:
            print("review_record: gate refused -- orphaned reviewer evidence %s: no admitted record points "
                  "at it (a record was removed, relabelled or re-pointed)" % path, file=sys.stderr)
        return 4
    units, conflicts = _gate_same_round_conflicts(units)
    # guard: G-G-CONFLICTS
    if conflicts:
        for (bid, rnd), paths in conflicts:
            print("review_record: gate refused -- conflicting records for batch %s round %s: %s"
                  % (bid, rnd, ", ".join(paths)), file=sys.stderr)
        return 4

    # Phase 2 -- decision, from evidence-derived unit fields only.
    ledger, ledger_reason = _load_ledger(a.dispatch_ledger)
    ctx = {
        "seam": a.seam,
        "round_budget": a.round_budget if a.round_budget is not None else ROUND_BUDGET_DEFAULT,
        "ledger": ledger,
        "ledger_reason": ledger_reason,
        "ledger_path": a.dispatch_ledger,
        "dispatch_use": _dispatch_reuse(units),
        "producer_uid": a.producer_uid,
    }
    by_batch = _gate_rounds_per_batch(units)

    uncovered = []
    for change in targets:
        covering, blockers, notes = _gate_change_verdict(change, by_batch, a.records, ctx)
        # guard: G-G-UNCOVERED
        if blockers or not covering:
            uncovered.append(change)
            print("UNCOVERED %s reason=%s" % (change, "; ".join(blockers or notes) or "no record lists this change"))
        else:
            tier = _aggregate_tier([c[2] for c in covering])
            print("COVERED %s batch=%s round=%s independence=%s seam=%s"
                  % (change, ",".join(str(c[0]) for c in covering),
                     ",".join(str(c[1]) for c in covering), tier, a.seam))

    return 1 if uncovered else 0


def _evidence_bytes_verified(evidence, evidence_sha256, record_own_path, records_root, base_dir=None):
    """Returns (bytes, real_path) of the cited evidence when it verifies,
    else (None, None). The file is opened ONCE (O_NOFOLLOW on the resolved
    path) and the hash is computed over exactly the bytes returned, so the
    caller parses what was verified (V3 m2: no verify-then-reopen window).

    T085 Round 5 (R4-I1, BLOCKING+IMPORTANT): the ONE shared evidence-
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
    # guard: G-E-NAMED
    if not isinstance(evidence, str) or not evidence.strip():
        return None, None
    # guard: G-E-PLACEHOLDER
    if evidence.strip().upper() in ("UNKNOWN", "N/A", "TBD"):
        return None, None
    evidence = evidence.strip()
    # guard: G-E-HASH-SHAPE
    if not isinstance(evidence_sha256, str) or not _HASH_RE.fullmatch(evidence_sha256):
        return None, None

    # R7 I2: a relative citation resolves against the CITING RECORD's own
    # directory (where `record` archived it), never against whichever
    # --records ancestor `gate` happened to be pointed at -- the same record
    # must reach the same verdict from any ancestor. Containment is still
    # checked against the realpath of --records.
    root_real = os.path.realpath(records_root)
    # guard: G-E-BASE-DIR
    base_real = os.path.realpath(base_dir) if base_dir else root_real
    resolved = evidence if os.path.isabs(evidence) else os.path.join(base_real, evidence)
    resolved_real = os.path.realpath(resolved)

    try:
        common = os.path.commonpath([root_real, resolved_real])
    except ValueError:
        # Different drives/roots (e.g. on a platform where this can
        # happen) -- structurally cannot be contained.
        return None, None
    # guard: G-E-CONTAINED
    if common != root_real:
        return None, None

    if record_own_path is not None:
        try:
            own_real = os.path.realpath(record_own_path)
        except OSError:
            own_real = None
        # guard: G-E-SELF-CITATION
        if own_real is not None and own_real == resolved_real:
            return None, None  # self-citation refused

    try:
        # guard: G-E-NONBLOCK (a FIFO planted as evidence must not hang gate)
        fd = os.open(resolved_real, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        return None, None
    try:
        # guard: G-E-REGULAR
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None, None
        with os.fdopen(fd, "rb") as fh:
            fd = None
            data = fh.read()
    except OSError:
        return None, None
    finally:
        if fd is not None:
            os.close(fd)
    # guard: G-E-HASH-MATCH
    if not data or hashlib.sha256(data).hexdigest() != evidence_sha256:
        return None, None
    return data, resolved_real


def _evidence_hash_verified(evidence, evidence_sha256, record_own_path, records_root, base_dir=None):
    """Boolean form of _evidence_bytes_verified() (kept for existing callers)."""
    return _evidence_bytes_verified(evidence, evidence_sha256, record_own_path,
                                    records_root, base_dir)[0] is not None


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
    g.add_argument("--producer-uid", type=int,
                   help="uid of the change's producer, declared by the seam's caller (a CLAIM); "
                        "'capability' needs neither it NOR the uid running gate to own/write/"
                        "replace the evidence (11.4.240(F)) -- never on a single-uid host; "
                        "absent or unknown -> never 'capability'")

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
