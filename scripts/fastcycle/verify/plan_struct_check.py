#!/usr/bin/env python3
"""plan_struct_check.py - structural checks over research.md / plan.md / tasks.md and the
constitution landing (spec-004 "fast-dev-cycles", plan T-H08 / T-A11 re-run; contract
contracts/plan-research-structural-check.md; contracts/common-conventions.md C-001..C-004;
data-model.md #2 Root Cause, #14; FR-002, FR-003, FR-004, FR-019, FR-022; SC-001, SC-007, SC-008).

THIS FILE (T046) implements ONLY the `causes` subcommand (SC-C-001, FR-002), against
research.md's own §2.1 register table + §2.2 register-counts table, per tasks.md's T046 line:
"Implement ... plan_struct_check.py causes per contract plan-research-structural-check until
T025 is GREEN (the research, plan, landing and rule-diff subcommands land in T159 and T179)".
The subparser structure below is built so those four subcommands can be added later, each as
its own `sub.add_parser(...)` + handler, without restructuring `main()`.

Usage:   plan_struct_check.py causes --doc <research.md> --out <causes.json>
             [--post-a11] [--operator-causes O1,O2,...]

Exit codes (contract "Exit codes" table): 0 all checks pass; 1 any structural violation
(listing each, by RC id, CLASS:stated=N,actual=M, or a `malformed_row` finding naming the row's
best-effort-recovered id or its raw line number + text -- see "Row parsing" below); 2 usage
error; 3 needle (this tool's OWN orphan-cause detector, run against a synthetic in-memory
fixture BEFORE --doc is ever read, did not behave as expected -- no honest verdict on the real
--doc is possible until the detector itself is proven -- constitution 11.4.201/11.4.273; nothing
is written); 4 document unreadable (--doc cannot be opened/decoded, OR it decodes but contains
ZERO lines starting with `| RC-` at all -- a line that starts with `| RC-` but fails to split
into a genuine data row still counts as "a row was found": it is reported as a `malformed_row`
structural violation under exit 1, never folded into this BLIND case. Only the true
zero-`| RC-`-lines-anywhere case is treated the same as anchor_citations.py's "--anchor-index has
zero parseable entries" case: a document with no honest register to check is BLIND, not a silent
0-violation pass -- nothing is written).

Row parsing (§2.1 Register table): a data row is any line starting with "| RC-" whose "|"-split
has exactly 11 parts (9 data cells plus the two empty strings either side of the leading/
trailing "|") -- this is the SAME column shape research.md's own real 9-column table uses today
(RC | Cause | Origin | Class | Measured magnitude | Share of total cycle | Evidence | Settling
evidence / what remains | Removed / measured by), and the SAME shape/index convention as this
task's own RED test (T025, test_plan_struct_causes_red.sh)'s independent `register_audit` Python
instrument -- re-implemented here independently (Producer != Verifier, constitution 11.4.240:
the RED test's audit function validates the FIXTURES encode their designed defects; this tool is
the thing under test, and reuses none of that instrument's code, only the same column contract).
Class cells are read via the first `**BOLD**` token (`^\\*\\*([A-Z]+)\\*\\*`) -- a row's real class
is its FIRST-stated verdict even when the cell carries a split verdict such as
"**CONFIRMED** (mechanism) / rate UNDETERMINED" (research.md's own §2.2 stated convention for
RC-22/RC-23, confirmed against the live document 2026-09-28).

A `| RC-` line whose "|"-split does NOT yield exactly 11 parts (most realistically: an unescaped
"|" inside a free-text Cause/Evidence/Settling cell, shifting every later column) is NEVER
silently skipped without a trace. It is reported as violation code `malformed_row`, naming the
row's best-effort-recovered RC id (via a regex anchored on the same "| RC-" precondition this
loop already requires -- in practice always recoverable, since the id token itself precedes
whatever later "|" made the split malformed) or, on the defensive fallback path, the raw
1-indexed line number + line text; the row is excluded from `rows`/`causes` either way. A
malformed row that vanished silently instead would defeat clauses (a) class-membership,
(b) orphan-cause, and (c) count-equality simultaneously: it is counted toward none of them, and a
§2.2 total that happens to already match the post-drop tally would then report a clean
0-violation pass over a register that was never fully audited -- exactly the class of silent
failure path indistinguishable from genuinely-nothing-found that constitution 11.4.201/11.4.273
treat as a release-blocking defect regardless of how green the exit code looks.

Contract-clause coverage in THIS implementation (honest boundary, constitution 11.4.6 -- every
gap named explicitly, never silently assumed covered):
  (a) class membership (class in {CONFIRMED, REFUTED, UNDETERMINED})     -- FULL. A blank Class
      cell, or one whose first bold token is not one of the three, is a violation naming the row.
  (b) orphan cause (no task in "Removed / measured by")                 -- FULL, register-level
      only (research.md's own §2 preamble: "no orphan cause ... checked mechanically by T-H08").
      This is the SHALLOWER check the RED test's own header explicitly distinguishes from
      SC-C-003's deeper bipartite cross-check against plan.md's real task blocks (a separate,
      later subcommand's job -- `plan`, T159/T179) -- this file does NOT read plan.md at all.
  (c) class counts equal research.md §2.2                                -- FULL. An independent
      re-tally over every row's first-bold-token class is compared against §2.2's own stated
      per-class "Rows" figure; a class named in the doc's own list with no §2.2 entry is silently
      skipped from the comparison (nothing to disagree with), matching the RED test's own
      register_audit instrument's identical behaviour for cross-fixture consistency.
  (d) settling_evidence required for UNDETERMINED                       -- PARTIAL. Implemented
      as a direct, low-risk reading of the contract's own words ("settling_evidence required for
      UNDETERMINED") against research.md's real "Settling evidence / what remains" column
      (non-blank required for every UNDETERMINED row); verified by hand against all four T025
      fixtures + the live document (every UNDETERMINED row in all five documents already carries
      non-blank text there) -- no DEDICATED RED fixture exists for this clause yet
      (`sc_bad_undetermined_no_settling` is named in the contract's own RED-fixtures table as a
      SEPARATE fixture from this task's four; T025's own file explicitly disclaims it as
      "OUT OF SCOPE for T025"), so this clause is implemented-but-not-fixture-verified.
  (e) EvidencePath (>=1 that exists) for every cause                    -- NOT IMPLEMENTED.
      data-model.md #1 defines EvidencePath as "Repo-relative path ... the file must exist and
      hash-match at validation time" -- but research.md's REAL §2.1 "Evidence" column carries
      free-text citations into earlier research passes (e.g. "R2:47-48; registry rows
      2026-09-26T13:24:22Z", "memory card session-delta-20260924b; R6:46-47"), NOT
      filesystem-path-shaped strings. Implementing a literal file-existence check against that
      column would flag EVERY one of the live document's 46 real rows (there is no row whose
      Evidence cell is a real repo-relative path today) -- silently trusting a fabricated
      path-extraction heuristic to bridge that gap would be exactly the guessing constitution
      11.4.6 forbids, and T025's own RED test explicitly names this clause
      (`sc_bad_cause_no_evidence`) as "OUT OF SCOPE for T025's four named bullets ... NOT covered
      by this file". Left unimplemented, honestly, pending whatever later task defines how
      research.md's prose citations map to real EvidencePath entries.
  (f) measured_share required for CONFIRMED once T-A11 has run          -- PARTIAL, opt-in. The
      contract's own literal Invocation line for `causes` (`--doc <research.md> --out
      <causes.json>`) names no flag for "has T-A11 run"; today (Phase 0, confirmed against the
      live research.md's own §2.2 closing text: "0 of 46 rows carry a measured share ... every
      share is UNMEASURED until T-A11/T049") this clause is INACTIVE by construction, so no flag
      is needed to pass T025. An optional `--post-a11` boolean is added as a forward-compatible
      extension (never on by default, so every current invocation -- T025's included -- is
      unaffected): when passed, a CONFIRMED row whose "Share of total cycle" cell is UNMEASURED
      or blank is a violation. The contract's further exemption ("unless recorded as a named
      permanent gap") names no concrete marker syntax anywhere in the contract or research.md,
      so no such exemption is recognised here -- an honest, deliberately narrower reading than
      the full future clause, to be corrected by whichever task actually re-runs this checker
      after T-A11 lands (T-A11's own task line: "Protecting tests: T-H08's structural check
      re-run").
  (g) the six operator-listed causes must all be present ("configured list") -- PARTIAL, opt-in.
      The contract's own parenthetical "(configured list)" means this is caller-supplied data,
      not a value this generic tool may hardcode from one project's own research.md preamble
      (constitution 11.4.28 decoupling). An optional `--operator-causes` (comma-separated Origin
      tokens, e.g. "O1,O2,O3,O4,O5,O6") is added: when supplied, every listed token must appear
      in at least one row's Origin cell, else a violation names the missing token(s); when
      omitted (every current invocation, T025's included), this check is honestly SKIPPED --
      never silently assumed satisfied.

Malformed-row integrity note: clauses (a)/(b)/(c) above are genuinely FULL -- not merely FULL
over whichever rows happened to parse -- precisely because a line that fails to even split into a
genuine row is never silently omitted from consideration; it surfaces as its own `malformed_row`
violation (see "Row parsing" above) instead of vanishing from `rows` without a trace.

Output (C-002): canonical JSON via fc_common.py's shared conventions, schema
"plan-struct-causes/v1". Body: {"doc": <--doc path as given>, "causes": [{"id", "class",
"evidence_paths" (the raw §2.1 Evidence-cell text, wrapped as a single-element list -- see (e)
above: NOT validated as real filesystem paths in this pass), "measured_share" (the raw "Share of
total cycle" cell text), "settling_evidence" (the raw "Settling evidence / what remains" cell
text, or null if blank), "removed_or_measured_by" (the raw last-cell text, or null if blank)},
...], "class_counts": {"stated": {...}, "actual": {...}}, "violations": [{"code", ...fields}]}.
Written on exit 0 AND exit 1 (a finding is still a real, inspectable verdict -- fc_common.py's
own `emit --code 1` convention); NOT written on exit 2/3/4 (no honest verdict, C-001).

Producer != Verifier (constitution 11.4.240): this tool CHECKS research.md's own register; it
never edits research.md, plan.md, or tasks.md, and its own orphan-cause detector's correctness
is proven, every run, by a self-contained synthetic control-needle check (see `self_check()`)
BEFORE the real --doc is ever read -- independent of, and never delegating to, the RED test's own
separate `register_audit` fixture-validation instrument.

Side-effects: `causes` writes --out via fc_common.py's atomic emit path (except on exit 2/3/4).
Stdlib only (matches lib/fc_common.py's own convention); imports canon/body_hash_of/cmd_emit
from the sibling lib/fc_common.py (C-002), same wiring pattern as cycle_report.py.
"""
import argparse
import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash / atomic-emit helpers. Imported by file
# path (not a package) -- constitution/scripts/fastcycle has no __init__.py anywhere (matches
# this tree's existing flat-script layout, e.g. cycle_report.py / anchor_citations.py).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

SCHEMA = "plan-struct-causes/v1"
CLASS_MEMBERS = ("CONFIRMED", "REFUTED", "UNDETERMINED")

# §2.1 Register table column indices after `line.split("|")` (parts[0] and parts[10] are the
# empty strings either side of the leading/trailing "|" -- 11 parts total for a genuine 9-cell
# data row). Same convention as this task's own RED test's `register_audit` instrument.
_COL_RC = 1
_COL_CAUSE = 2
_COL_ORIGIN = 3
_COL_CLASS = 4
_COL_MAGNITUDE = 5
_COL_SHARE = 6
_COL_EVIDENCE = 7
_COL_SETTLING = 8
_COL_LAST = 9
_ROW_PARTS = 11

_CLASS_TOKEN_RE = re.compile(r"^\*\*([A-Z]+)\*\*")
_UNMEASURED_RE = re.compile(r"^UNMEASURED\b", re.IGNORECASE)

# Best-effort recovery of a malformed row's RC identifier. The line has already satisfied
# `line.startswith("| RC-")` by construction (see parse_register_rows) before this is ever
# matched, so in practice this always recovers at least the literal "RC-" token, and typically
# the row's FULL id (e.g. "RC-02") -- the id token itself precedes whatever later "|" (an
# unescaped pipe inside a free-text cell) made the split malformed. Kept as a real regex match
# rather than a hardcoded slice so it degrades gracefully (empty capture -> None, see
# parse_register_rows) rather than raising on a pathological line.
_MALFORMED_ROW_ID_RE = re.compile(r"^\|\s*(RC-[^\s|]*)")


def _class_token(cell):
    """First bold token of a §2.1 Class cell, or "" if the cell has none (blank, or no bold
    markup at all). Matches split verdicts such as "**CONFIRMED** (mechanism) / rate
    UNDETERMINED" by taking only the FIRST bold token -- research.md's own §2.2 stated
    convention for RC-22/RC-23."""
    m = _CLASS_TOKEN_RE.match(cell.strip())
    return m.group(1) if m else ""


def parse_register_rows(text):
    """Parse every `| RC-...` row of a §2.1-shaped register table out of `text`.

    Returns (rows, malformed):
      - `rows` is a list of row dicts in document order: {"id", "cause", "origin", "class",
        "magnitude", "share", "evidence", "settling", "last"}.
      - `malformed` is a list of {"code": "malformed_row", "row", "line_no", "line", "parts"}
        violation dicts, one per line starting with "| RC-" whose "|"-split does NOT yield
        exactly _ROW_PARTS parts (a genuine 9-cell data row's shape) -- most realistically an
        unescaped "|" inside a free-text Cause/Evidence/Settling cell shifting every later
        column. Such a line is NEVER silently dropped without a trace (constitution
        11.4.201/11.4.273: a malformed row vanishing unnoticed would defeat clauses (a)/(b)/(c)
        simultaneously and silently -- it is counted toward none of them, and a §2.2 total that
        happens to already match the post-drop tally would then report a clean 0-violation pass
        over a register that was never fully audited). `row` names the row's best-effort-
        recovered RC id via _MALFORMED_ROW_ID_RE (in practice always recoverable given the
        `line.startswith("| RC-")` precondition below), or is None on the defensive fallback
        path when even that cannot be recovered; `line_no` (1-indexed) and `line` (the raw,
        newline-stripped line text) are always populated regardless, so a malformed row is
        fully traceable either way.

    A line that genuinely parses is never also reported as malformed -- the two outcomes are
    mutually exclusive per line.
    """
    rows = []
    malformed = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line.startswith("| RC-"):
            continue
        raw = line.rstrip("\n")
        parts = raw.split("|")
        if len(parts) != _ROW_PARTS:
            m = _MALFORMED_ROW_ID_RE.match(raw)
            recovered_id = m.group(1).strip() if m and m.group(1).strip() else None
            malformed.append({
                "code": "malformed_row",
                "row": recovered_id,
                "line_no": line_no,
                "line": raw,
                "parts": len(parts),
            })
            continue
        rows.append({
            "id": parts[_COL_RC].strip(),
            "cause": parts[_COL_CAUSE].strip(),
            "origin": parts[_COL_ORIGIN].strip(),
            "class": _class_token(parts[_COL_CLASS]),
            "magnitude": parts[_COL_MAGNITUDE].strip(),
            "share": parts[_COL_SHARE].strip(),
            "evidence": parts[_COL_EVIDENCE].strip(),
            "settling": parts[_COL_SETTLING].strip(),
            "last": parts[_COL_LAST].strip(),
        })
    return rows, malformed


def parse_register_counts(text):
    """Parse the §2.2 "Register counts" table's stated per-class Rows figure out of `text`.

    Returns {class_name: int} for whichever of {CONFIRMED, REFUTED, UNDETERMINED} the table
    states a row for (a class the table omits is simply absent from the returned dict -- no
    entry to compare against, matching the RED test's own register_audit instrument). Section
    boundaries: starts at a line beginning "### 2.2", ends at the next line beginning "### 2."
    that is not itself "### 2.2" (i.e. "### 2.3" etc.) -- identical convention to register_audit.
    """
    stated = {}
    in_22 = False
    for line in text.splitlines():
        if line.startswith("### 2.2"):
            in_22 = True
            continue
        if in_22 and line.startswith("### 2.") and not line.startswith("### 2.2"):
            break
        if in_22 and line.startswith("|"):
            parts = line.rstrip("\n").split("|")
            if len(parts) >= 3:
                key = parts[1].strip()
                val = parts[2].strip().strip("*")
                if key in CLASS_MEMBERS:
                    try:
                        stated[key] = int(val)
                    except ValueError:
                        pass  # non-numeric "Rows" cell: leave this class absent from `stated`
    return stated


def actual_counts(rows):
    counts = {}
    for row in rows:
        if row["class"]:
            counts[row["class"]] = counts.get(row["class"], 0) + 1
    return counts


def check_causes(rows, stated, post_a11, operator_causes):
    """Run every SC-C-001 check this file implements (see module docstring's Contract-clause
    coverage section) over already-parsed rows/§2.2 counts. Returns (causes_out, violations)."""
    causes_out = []
    violations = []

    for row in rows:
        rid = row["id"]

        # (a) class membership
        if row["class"] not in CLASS_MEMBERS:
            violations.append({"code": "no_class", "row": rid, "found": row["class"] or None})

        # (b) orphan cause: register-level only (no cross-reference into plan.md -- see docstring)
        if not row["last"]:
            violations.append({"code": "orphan_cause", "row": rid})

        # (d) settling_evidence required for UNDETERMINED (PARTIAL -- see docstring)
        if row["class"] == "UNDETERMINED" and not row["settling"]:
            violations.append({"code": "undetermined_no_settling", "row": rid})

        # (f) measured_share required for CONFIRMED once T-A11 has run (PARTIAL, opt-in --
        # see docstring; inactive unless --post-a11 was passed)
        if post_a11 and row["class"] == "CONFIRMED":
            share = row["share"]
            if not share or _UNMEASURED_RE.match(share):
                violations.append({"code": "measured_share_missing", "row": rid})

        causes_out.append({
            "id": rid,
            "class": row["class"] or None,
            "evidence_paths": [row["evidence"]] if row["evidence"] else [],
            "measured_share": row["share"] or None,
            "settling_evidence": row["settling"] or None,
            "removed_or_measured_by": row["last"] or None,
        })

    # (c) class counts equal research.md §2.2
    actual = actual_counts(rows)
    for cls in CLASS_MEMBERS:
        s = stated.get(cls)
        a = actual.get(cls, 0)
        if s is not None and s != a:
            violations.append({"code": "count_mismatch", "class": cls, "stated": s, "actual": a})

    # (g) the six operator-listed causes must all be present ("configured list", PARTIAL, opt-in)
    if operator_causes:
        origins_seen = " ".join(row["origin"] for row in rows)
        missing = [tok for tok in operator_causes if not re.search(r"\b%s\b" % re.escape(tok), origins_seen)]
        if missing:
            violations.append({"code": "operator_causes_missing", "tokens": sorted(missing)})

    causes_out.sort(key=lambda c: c["id"])  # C-002: arrays sorted by identity field
    return causes_out, violations


def _violation_stderr_line(v):
    code = v["code"]
    if code == "malformed_row":
        who = v["row"] if v["row"] else ("line %d: %s" % (v["line_no"], v["line"]))
        return "malformed row (expected %d '|'-separated parts, found %d): %s" % (
            _ROW_PARTS, v["parts"], who)
    if code == "no_class":
        return "no class: %s" % v["row"]
    if code == "orphan_cause":
        return "orphan cause (no task in 'Removed / measured by'): %s" % v["row"]
    if code == "undetermined_no_settling":
        return "UNDETERMINED row has no settling_evidence: %s" % v["row"]
    if code == "measured_share_missing":
        return "CONFIRMED row has no measured_share after --post-a11: %s" % v["row"]
    if code == "count_mismatch":
        return "%s:stated=%d,actual=%d" % (v["class"], v["stated"], v["actual"])
    if code == "operator_causes_missing":
        return "operator-listed cause(s) not found in any row's Origin cell: %s" % ",".join(v["tokens"])
    return str(v)  # pragma: no cover - defensive, every emitted code is one of the above


# ---------------------------------------------------------------------------
# §11.4.201/§11.4.273 self-check (control needle): proves THIS tool's own orphan-cause
# detector -- the exact mechanism the contract's exit code 3 names ("needle: a fixture with a
# known orphan cause not detected") -- genuinely flags a known-orphan row and does NOT
# false-positive on a known-non-orphan row, using a synthetic, self-contained §2-shaped
# fixture built in-process (never touching disk, never the RED test's own on-disk fixtures --
# Producer != Verifier, constitution 11.4.240). Run BEFORE the real --doc is ever read.
# ---------------------------------------------------------------------------
_SELF_CHECK_DOC = (
    "## 2. Root-cause register\n\n"
    "### 2.1 Register table\n\n"
    "| RC | Cause | Origin | Class | Measured magnitude (named denominator) | Share of total cycle | Evidence | Settling evidence / what remains | Removed / measured by |\n"
    "|---|---|---|---|---|---|---|---|---|\n"
    "| RC-NEEDLE-GOOD | control-needle cause (non-orphan) | O1 | **CONFIRMED** | m | UNMEASURED | e | s | T-NEEDLE |\n"
    "| RC-NEEDLE-BAD | control-needle cause (deliberately orphan) | O1 | **CONFIRMED** | m | UNMEASURED | e | s |  |\n"
    "\n### 2.2 Register counts (machine count over the Class column of §2.1)\n\n"
    "| Class | Rows | Row ids |\n"
    "|---|---|---|\n"
    "| CONFIRMED | 2 | RC-NEEDLE-GOOD, RC-NEEDLE-BAD |\n"
    "| **Total** | **2** | |\n"
)


def self_check():
    """Returns None on success, else a diagnostic string (caller exits 3)."""
    rows, malformed = parse_register_rows(_SELF_CHECK_DOC)
    if malformed:
        return ("self-check FAILED: the synthetic control-needle fixture itself produced "
                 "unexpected malformed_row finding(s) -- it must parse cleanly: %r" % malformed)
    by_id = {r["id"]: r for r in rows}
    good = by_id.get("RC-NEEDLE-GOOD")
    bad = by_id.get("RC-NEEDLE-BAD")
    if good is None or bad is None:
        return "self-check FAILED: could not even parse the synthetic control-needle rows (%d rows found, expected 2)" % len(rows)
    if bad["last"]:
        return "self-check FAILED: the synthetic control-needle parser did not read RC-NEEDLE-BAD's last cell as blank (got %r)" % bad["last"]
    if not good["last"]:
        return "self-check FAILED: the synthetic control-needle parser wrongly read RC-NEEDLE-GOOD's last cell as blank"
    _, violations = check_causes(rows, parse_register_counts(_SELF_CHECK_DOC), post_a11=False, operator_causes=None)
    bad_flagged = any(v["code"] == "orphan_cause" and v["row"] == "RC-NEEDLE-BAD" for v in violations)
    good_flagged = any(v["code"] == "orphan_cause" and v["row"] == "RC-NEEDLE-GOOD" for v in violations)
    if not bad_flagged:
        return "self-check FAILED: known-orphan RC-NEEDLE-BAD was NOT flagged as orphan_cause"
    if good_flagged:
        return "self-check FAILED: known-non-orphan RC-NEEDLE-GOOD was WRONGLY flagged as orphan_cause (false positive, constitution 11.4.201(1))"
    return None


def _read_doc(path):
    """Returns (text, None) on success, (None, error-message) on failure. Never raises."""
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read(), None
    except (OSError, UnicodeDecodeError) as exc:
        return None, "cannot read --doc %s: %s" % (path, exc)


def cmd_causes(a):
    self_check_err = self_check()
    if self_check_err:
        print("plan_struct_check: %s" % self_check_err, file=sys.stderr)
        return 3

    operator_causes = None
    if a.operator_causes:
        operator_causes = [t.strip() for t in a.operator_causes.split(",") if t.strip()]

    text, err = _read_doc(a.doc)
    if err:
        print("plan_struct_check: BLIND -- %s" % err, file=sys.stderr)
        return 4

    rows, malformed = parse_register_rows(text)
    if not rows and not malformed:
        print("plan_struct_check: BLIND -- --doc %s has zero parseable '| RC-' register rows "
              "(no honest register to check)" % a.doc, file=sys.stderr)
        return 4

    stated = parse_register_counts(text)
    causes_out, violations = check_causes(rows, stated, post_a11=a.post_a11, operator_causes=operator_causes)
    # Malformed rows are a structural violation in their own right (see parse_register_rows /
    # module docstring "Row parsing") -- never silently dropped, and reported ahead of the
    # semantic per-row checks below since a parse failure precedes them in the pipeline.
    violations = malformed + violations

    for v in violations:
        print("plan_struct_check: %s" % _violation_stderr_line(v), file=sys.stderr)

    body = {
        "doc": a.doc,
        "causes": causes_out,
        "class_counts": {"stated": stated, "actual": actual_counts(rows)},
        "violations": violations,
    }
    rc = 1 if violations else 0
    ns = argparse.Namespace(
        schema=SCHEMA,
        body_json=json.dumps(body),
        run_meta_json=None,
        out=a.out,
        code=rc,
    )
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != rc:
        # fc_common.cmd_emit only ever fails (returns 2) on a write/encode error, in which case
        # its own diagnostic is already on stderr -- surface that failure honestly rather than
        # claim the causes verdict this tool computed.
        return write_rc
    return rc


def main(argv):
    p = argparse.ArgumentParser(prog="plan_struct_check.py")
    sub = p.add_subparsers(dest="cmd_name", required=True)
    # T046 scope: `causes` only. `research` (T159), `plan`/`landing`/`rule-diff` (T159/T179) are
    # added here later, each as its own `sub.add_parser(...)` + handler -- no restructuring needed.

    c = sub.add_parser("causes")
    c.add_argument("--doc", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--post-a11", action="store_true",
                    help="opt-in: enforce measured_share for CONFIRMED rows (clause (f); "
                         "see module docstring). Never on by default.")
    c.add_argument("--operator-causes",
                    help="opt-in: comma-separated Origin tokens (e.g. O1,O2,O3,O4,O5,O6) that "
                         "must each appear in >=1 row's Origin cell (clause (g), 'configured "
                         "list'). Omitted by default -- never silently assumed satisfied.")

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    table = {"causes": cmd_causes}
    try:
        return table[a.cmd_name](a)
    except Exception as exc:  # C-001: an internal error is never a finding (1) -- BLIND (4)
        print("plan_struct_check: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
