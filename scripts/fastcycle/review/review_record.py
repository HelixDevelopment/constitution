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
    1. finding carries a non-empty "rule" field (a named lint/style rule,
       e.g. verdict.json {"rule": "SC2086"})
         -> "mechanical" (findable by the machine pre-check pack, DEC-33)
    2. else finding's (file, line) matches an entry in precheck.json's
       "already-fixed-markers" check evidence.markers
         -> "false-positive" (DEC-33 "state-temporal misalignment": the
            code was already fixed by the time the reviewer filed the
            comment)
    3. else
         -> "judgment" (a substantive design/architecture concern; no lint
            rule, no already-fixed-markers match)
   Rule (1) is checked before markers (2): none of the three fixtures needs
   both to disambiguate, and a mechanical (lint-findable) issue is
   classified mechanical even if its line also happens to appear in an
   already-fixed-markers entry.

Usage:   review_record.py record --batch B --round N --verdict-file V
             --tier opus --effort xhigh --out O
             [--item ITEM] [--precheck PRECHECK]
             [--started-at TS] [--ended-at TS]
             [--tokens JSON] [--reviewer-mutations JSON]
             [--substrate-evidence TEXT]
         review_record.py backfill --input SPEC --out O

Exit:    record : 0 accepted + written (tier/effort match the designated
                    review tier, constitution 11.4.209 as amended
                    2026-09-26: Opus xhigh, no Fable, no fallback model);
                  1 refused (tier/effort mismatch -- nothing written);
                  2 usage/configuration error (bad args, unreadable or
                    malformed --batch/--verdict-file/--precheck/--input,
                    malformed --tokens/--reviewer-mutations JSON, cannot
                    write --out).
         backfill: 0 written; 2 usage/configuration error (missing
                    required --input key, malformed finding, bad verdict,
                    cannot write --out). There is no tier/effort refusal
                    path for backfill -- a backfilled row records history,
                    it does not gate a live review.
         Any other internal error: 4 (BLIND, C-001 row 4 -- no honest
         verdict is possible; never 1, which is reserved for a genuine
         review finding).

Output (C-002): canonical JSON (UTF-8, sorted keys, no insignificant
        whitespace, `schema: "review_record/v1"`, `body_hash` = sha256 of
        the canonical body excluding `run_meta`). See
        data-model.md #10.1 for the full ReviewVerdictRecord field list;
        this tool additionally emits `source` (`"live"` for `record`,
        `"backfill"` for `backfill`) and, for `record`, `precheck_used`
        (bool: whether a readable precheck.json was actually consulted).

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

SCHEMA = "review_record/v1"
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
    """Returns (doc, None) on success, (None, error-message) on failure. Never raises."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), None
    except (OSError, json.JSONDecodeError) as exc:
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


def classify_finding(finding, markers):
    """T-A04 closed class set: mechanical | judgment | false-positive. See module docstring."""
    rule = finding.get("rule")
    if isinstance(rule, str) and rule.strip():
        return "mechanical"
    file_, line_ = finding.get("file"), finding.get("line")
    for marker in markers:
        if marker.get("file") == file_ and marker.get("line") == line_:
            return "false-positive"
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
    if a.tier != DESIGNATED_TIER or a.effort != DESIGNATED_EFFORT:
        print("review_record: refused -- tier/effort must equal the designated review tier "
              "(%s/%s per constitution 11.4.209 as amended 2026-09-26), got %s/%s"
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

    verdict_round = verdict_doc.get("round")
    if verdict_round is not None and verdict_round != a.round:
        print("review_record: WARNING: --round %s differs from --verdict-file's own 'round' %s "
              "(recording the CLI-supplied --round as authoritative)" % (a.round, verdict_round),
              file=sys.stderr)

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
    findings_severities = [f["severity"] for f in findings_out]
    verdict = "NO-GO" if "BLOCKING" in findings_severities else "GO"
    first_round_go = (a.round == 1 and verdict == "GO")

    body = {
        "review_id": "REV-%s-%s" % (batch_id, a.round),
        "batch_id": batch_id,
        "round": a.round,
        "model_tier": a.tier,
        "effort": a.effort,
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
    if not isinstance(round_n, int):
        print("review_record: --input 'round' must be an integer, got %r" % (round_n,), file=sys.stderr)
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

    body = {
        "review_id": spec["review_id"],
        "batch_id": spec["batch_id"],
        "round": round_n,
        "model_tier": opt("model_tier"),
        "effort": opt("effort"),
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
        "first_round_go": (round_n == 1 and verdict == "GO"),
        "reviewer_mutations": spec.get("reviewer_mutations") if isinstance(spec.get("reviewer_mutations"), list) else "UNKNOWN",
        "source": "backfill",
        "source_evidence": spec["source_evidence"],
    }
    return _write_record(body, a.out)


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

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    table = {"record": cmd_record, "backfill": cmd_backfill}
    try:
        return table[a.cmd_name](a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("review_record: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
