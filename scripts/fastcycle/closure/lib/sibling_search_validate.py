#!/usr/bin/env python3
"""sibling_search_validate.py - SiblingSearchArtefact schema validator
(spec-004 "fast-dev-cycles", plan.md T-D03; tasks.md T096; contract
closure-refusal.md CR-004; data-model.md Section 6.4; FR-011, SC-004).

Invoked by ../sibling_search_check.sh as:

    sibling_search_validate.py <artefact.json>

Validates ONE already-produced SiblingSearchArtefact JSON document (per
tests/fixtures/sibling_search_check/README.md's schema, data-model.md
section 6.4) against the DEC-20 closed disposition set and the
control-needle-before-trusting-a-null rule (constitution section
11.4.201(7)(b) / 11.4.273(f)). This module does NOT re-run search_method
itself -- it validates the artefact's own self-reported fields only.

Exit codes: see the header comment of ../sibling_search_check.sh (C-001).
"""
import json
import re
import sys

# canonicalIDRe, mirrored from
# constitution/scripts/workable-items/cmd/workable-items/crud.go:25
# (^[A-Z]{3,}-[0-9A-Za-z]+$) -- the same shape this project's own tracker
# uses for a workable-item ticket id, e.g. "ATM-953".
_ITEM_ID_RE = re.compile(r"^[A-Z]{3,}-[0-9A-Za-z]+$")
_TRACKED_AS_RE = re.compile(r"^tracked-as (.+)$")
_FIXED_DISPOSITIONS = frozenset({"fixed-here", "proven-not-an-instance"})


def _is_nonempty_str(value):
    return isinstance(value, str) and value.strip() != ""


def _valid_disposition(value):
    if not isinstance(value, str):
        return False
    if value in _FIXED_DISPOSITIONS:
        return True
    match = _TRACKED_AS_RE.match(value)
    return bool(match) and bool(_ITEM_ID_RE.match(match.group(1)))


def validate(doc):
    """Return a list of 'FINDING: ...' lines; empty => the artefact is VALID."""
    findings = []

    if not _is_nonempty_str(doc.get("class_statement")):
        findings.append("FINDING: class_statement is missing or empty")

    if not _is_nonempty_str(doc.get("search_method")):
        findings.append("FINDING: search_method is missing or empty")

    if not _is_nonempty_str(doc.get("control_needle")):
        findings.append("FINDING: control_needle is missing or empty")

    needle_found = doc.get("control_needle_found")
    if not isinstance(needle_found, bool):
        findings.append("FINDING: control_needle_found is missing or not a boolean")
    elif needle_found is False:
        findings.append(
            "FINDING: control_needle_found is false -- the search "
            "mechanism's control_needle was not confirmed present, so "
            "instances_found cannot be trusted (a null without a proven "
            "control_needle is not evidence)"
        )

    instances = doc.get("instances_found")
    if not isinstance(instances, list):
        findings.append("FINDING: instances_found is missing or not a list")
    else:
        for idx, inst in enumerate(instances):
            if not isinstance(inst, dict):
                findings.append(
                    "FINDING: instances_found[%d] is not a JSON object" % idx
                )
                continue
            if not _is_nonempty_str(inst.get("location")):
                findings.append(
                    "FINDING: instances_found[%d] is missing location" % idx
                )
            disp = inst.get("disposition")
            if not _valid_disposition(disp):
                findings.append(
                    "FINDING: instances_found[%d] has an invalid disposition "
                    "value %r -- allowed set is fixed-here / tracked-as "
                    "<ItemId> / proven-not-an-instance" % (idx, disp)
                )

    return findings


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(
            "sibling_search_validate.py: usage: sibling_search_validate.py "
            "<artefact.json>\n"
        )
        return 2

    path = argv[1]
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as exc:
        print("BLIND: cannot read artefact file: %s (%s)" % (path, exc))
        return 4

    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        print("BLIND: artefact file is not valid JSON: %s (%s)" % (path, exc))
        return 4

    if not isinstance(doc, dict):
        print(
            "FINDING: artefact root is not a JSON object (got %s)"
            % type(doc).__name__
        )
        return 1

    findings = validate(doc)
    if findings:
        for line in findings:
            print(line)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
