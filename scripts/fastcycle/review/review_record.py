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
         review_record.py backfill --input SPEC --out O
         review_record.py gate --change SHA[,SHA...] --records DIR

Exit:    record : 0 accepted + written (tier equals the designated review
                    tier and effort equals xhigh OR the honest capability-
                    gap token "?", constitution 11.4.209 as amended
                    2026-09-26: Opus xhigh, no Fable, no fallback model;
                    11.4.231(F.2): a dispatch path that cannot report
                    effort records "?", never a fabricated "xhigh");
                  1 refused (tier mismatch, or effort neither "xhigh" nor
                    "?" -- nothing written);
                  2 usage/configuration error (bad args, --round < 1, a
                    --verdict-file "round" that disagrees with --round, a
                    --verdict-file with no "verdict" field or a "verdict"
                    outside {GO, NO-GO}, unreadable or malformed
                    --batch/--verdict-file/--precheck/--input, malformed
                    --tokens/--reviewer-mutations JSON, cannot write
                    --out).
         backfill: 0 written; 2 usage/configuration error (missing
                    required --input key, a "round" < 1, malformed
                    finding, bad verdict, cannot write --out). There is no
                    tier/effort refusal path for backfill -- a backfilled
                    row records history, it does not gate a live review.
         gate   : 0 every queried change is covered (contract RB-006:
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
                    a non-integer round (records unreadable -- no honest
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
import sys
import tempfile

SCHEMA = "review-record/v1"  # contracts/review-batch-and-precheck.md "Output schemas" (hyphen, not underscore)
DESIGNATED_TIER = "opus"
DESIGNATED_EFFORT = "xhigh"
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


def cmd_record(a):
    # M1: round integrity is a usage error (2), checked before anything else.
    if a.round < 1:
        print("review_record: --round must be >= 1, got %d" % a.round, file=sys.stderr)
        return 2

    # B2 / constitution 11.4.231(F.2): effort "?" is the honest capability-gap token a
    # dispatch path records when it cannot report effort at all -- it is ACCEPTED here
    # (never refused), stored verbatim, and flagged via effort_capability_gap below so a
    # future `gate`/`report` consumer can correctly treat it as non-satisfying. Only
    # effort has this exception (data-model.md #10.1's `?` note is specifically about
    # effort, never tier -- the dispatch mechanism always knows which model answered).
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
    # conclusion, REQUIRED in --verdict-file, read verbatim -- this tool never derives it
    # from findings' severities (a review's GO/NO-GO call belongs to the reviewer, not to
    # this recorder). A missing or out-of-closed-set value is a malformed --verdict-file,
    # exit 2 -- not silently invented (constitution 11.4.6).
    verdict = verdict_doc.get("verdict")
    if verdict not in ("GO", "NO-GO"):
        print("review_record: --verdict-file must carry a 'verdict' field of 'GO' or 'NO-GO' "
              "(the reviewer's own conclusion; never derived from findings), got %r"
              % (verdict,), file=sys.stderr)
        return 2

    # M1: a round mismatch between --round and the verdict-file's own 'round' is a hard
    # usage error (2), not a warning -- RB-005's round-chaining discipline (and
    # first_round_go below) depends on the round number being correct, and silently
    # "picking one" over the other is exactly the guess constitution 11.4.6 forbids.
    verdict_round = verdict_doc.get("round")
    if verdict_round is not None and verdict_round != a.round:
        print("review_record: --round %s does not match --verdict-file's own 'round' %s -- "
              "refusing rather than silently pick one (constitution 11.4.6)"
              % (a.round, verdict_round), file=sys.stderr)
        return 2

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

    findings_out = []
    for finding in raw_findings:
        if not isinstance(finding, dict) or "id" not in finding:
            print("review_record: malformed finding entry (missing 'id'): %r" % (finding,), file=sys.stderr)
            return 2
        findings_out.append({
            "id": finding["id"],
            "severity": finding.get("severity", "UNKNOWN"),
            "class": classify_finding(finding, markers),
        })
    findings_out.sort(key=lambda f: f["id"])  # C-002: arrays sorted by identity field

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

    batch_id = batch.get("batch_id", "UNKNOWN")
    # B1: first_round_go is a DERIVED correctness flag, never the recorded verdict itself
    # -- a "GO" that still carries findings of any severity (rb_bad_go_with_nit) is
    # recorded faithfully but is NOT a clean first-round GO (RB-005 / 11.4.134: "a GO is
    # terminal only when it has zero findings of any severity").
    first_round_go = (a.round == 1 and verdict == "GO" and len(findings_out) == 0)

    body = {
        "review_id": "REV-%s-%s" % (batch_id, a.round),
        "batch_id": batch_id,
        "round": a.round,
        "model_tier": a.tier,
        "effort": a.effort,
        "effort_capability_gap": effort_capability_gap,
        "substrate_evidence": a.substrate_evidence or "cli-flag",
        "verdict": verdict,
        "findings": findings_out,
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
    }
    return _write_record(body, a.out)


def cmd_backfill(a):
    """Back-fill a ReviewVerdictRecord for a real, already-conducted historical review round that
    predates this tool (no machine-readable ReviewBatch/PreCheckReport/verdict-file exists for it
    -- only a text record). --input is a hand-authored JSON spec citing real facts extracted from
    that real record; every field this tool cannot verify from --input is recorded "UNKNOWN"
    (data-model.md #10.1). `source_evidence` is REQUIRED and MUST name the real document this row
    was reconstructed from -- there is no field-omission path that lets a backfilled row exist
    without citing where it came from (constitution 11.4.6: never fabricate a historical
    sequence)."""
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
        findings_out.append({
            "id": finding["id"],
            "severity": finding.get("severity", "UNKNOWN"),
            # Never re-run the live classifier here: no machine ReviewBatch/PreCheckReport/
            # verdict-file input exists for a backfilled historical round, so "class" is
            # whatever --input's author could genuinely establish, or "UNKNOWN" (11.4.6).
            "class": finding.get("class", "UNKNOWN"),
        })
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
        "source_evidence": spec["source_evidence"],
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
    ReviewVerdictRecord, and returns the list. Returns None (caller exits 4) on
    the FIRST file that fails to parse / is not an object / is missing a required
    field / carries a non-integer round -- a corrupt record file means no honest
    coverage verdict is possible, never a silent skip (module docstring, C-001)."""
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
            records.append(doc)
    return records


def _gate_latest_per_batch(records):
    """RB-006 "that batch's ... latest record": groups by batch_id, keeps the
    highest-round record per batch; a genuine round tie (malformed input --
    review_id/round should be unique per batch) breaks deterministically on the
    lexically-greatest review_id (C-003: never dict/insertion-order-dependent)."""
    latest = {}
    for rec in records:
        bid = rec["batch_id"]
        cur = latest.get(bid)
        if cur is None or rec["round"] > cur["round"] or (
                rec["round"] == cur["round"]
                and str(rec.get("review_id", "")) > str(cur.get("review_id", ""))):
            latest[bid] = rec
    return latest


def _gate_batch_qualifies(rec):
    """RB-006 "a zero-finding GO at the designated tier and effort" -- re-derived
    from the record's OWN verdict/findings/model_tier/effort fields, never from a
    stored derived flag (mirrors B1's own reasoning for first_round_go: a summary
    flag can be stale or absent on an older record; the raw fields are the source
    of truth). effort=="?" (the honest 11.4.231(F.2) capability-gap token) never
    equals DESIGNATED_EFFORT, so it never qualifies, matching RB-004's own note."""
    findings = rec.get("findings")
    return (
        rec.get("verdict") == "GO"
        and isinstance(findings, list) and len(findings) == 0
        and rec.get("model_tier") == DESIGNATED_TIER
        and rec.get("effort") == DESIGNATED_EFFORT
    )


def cmd_gate(a):
    targets = [c.strip() for c in a.change.split(",") if c.strip()]
    if not targets:
        print("review_record: --change must name at least one change id", file=sys.stderr)
        return 2

    if not os.path.isdir(a.records):
        print("review_record: gate refused -- --records is not a readable directory: %s" % a.records,
              file=sys.stderr)
        return 4

    records = _gate_collect_records(a.records)
    if records is None:
        return 4

    latest_by_batch = _gate_latest_per_batch(records)

    uncovered = []
    for change in targets:
        covered_by = None
        for bid, rec in sorted(latest_by_batch.items()):
            change_ids = rec.get("change_ids")
            if isinstance(change_ids, list) and change in change_ids and _gate_batch_qualifies(rec):
                covered_by = (bid, rec.get("round"))
                break
        if covered_by is None:
            uncovered.append(change)
            print("UNCOVERED %s" % change)
        else:
            print("COVERED %s batch=%s round=%s" % (change, covered_by[0], covered_by[1]))

    return 1 if uncovered else 0


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

    b = sub.add_parser("backfill")
    b.add_argument("--input", required=True)
    b.add_argument("--out", required=True)

    g = sub.add_parser("gate")
    g.add_argument("--change", required=True)
    g.add_argument("--records", required=True)

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
