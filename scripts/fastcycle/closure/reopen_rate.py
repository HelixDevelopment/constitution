#!/usr/bin/env python3
"""reopen_rate.py - Reopen-rate metric with matched denominators (spec-004
"fast-dev-cycles", T100, plan task T-D06, contract cycle-time-report-cli.md
CT-006; the single owner of the SC-004 metric).

Purpose: compute reopened / closed per item type per window, both counts
drawn from the SAME underlying population (items that genuinely have a
closure event -- Fixed/Implemented/Completed -- inside the window), report
the result with explicit window bounds and denominators, and REFUSE to emit
a naive ratio when the two counts are drawn from different populations (R1
Table D caveat: "so \"18 of 31 bugs\" ... is an UPPER-BOUND-style ratio with
mismatched populations ... do not quote as a rate" --
research/R1_baseline_cycle_time.md:64, cited verbatim by contract CT-006).
Linked recurrences (T-D04) are counted as reopens because they are
Reopened-event rows on the ORIGINAL item's own history, not a separate
counting mechanism this tool needs to special-case. Retroactive registrations
(an Opened -> terminal-closure created_at (db-write) gap in [0, 60) seconds
-- the identical rule cycle_report.py's flag_retroactive_registration and
select_sample.py's detect_retroactive_registration already implement) are
excluded from both the numerator and denominator and listed separately by
item id and reason; a window containing one still PASSES (exit 0) with the
correctly-adjusted rate -- this is the OPPOSITE verdict from the population-
mismatch case above, even though both look superficially like "one item out
of a small set needs special handling" (T091/CT-5 negative control).

Interim CLI (documented here, not yet a standalone contract file -- per
contracts/common-conventions.md's own convention for open-gap tools: "their
interface, output and RED fixtures are fixed by the plan task text until a
contract is written" -- tests/test_reopen_rate_red.sh (T091) IS that fixed
interface until a reopen-rate-cli.md contract exists):
    reopen_rate.py --as-of <YYYY-MM-DD> --window-days <N> \\
        --tracker-export <fixture.json> --out <report.json>

--tracker-export supplies a JSON document with top-level "items" (each
{"atm_id": ..., "type": one of Bug/Feature/Task}) and "item_history" (each
row an item_history-shaped record: atm_id, event_type, on_date, created_at,
plus optional by/reason/evidence_path). --as-of/--window-days derive the
analysis window as window.to = as_of, window.from = as_of - window_days
days (matching cycle_report.py's own DEC-03 convention); the window is NOT
read from the fixture's own "window" field, which exists only as the
fixture author's own cross-check.

Output shape (contract CT-006, "reopen" table row: "{reopened, closed,
window, dedup_rows_removed, rate or RATE_NOT_COMPUTABLE}"), written to
--out as canonical JSON (C-002, via the sibling lib/fc_common.py's
canon()/body_hash_of() -- schema="reopen-rate/v1", stdlib only, matching
this tree's established flat-script convention of each CLI tool carrying
its own copy of the shared retroactive-registration rule rather than
importing a sibling tool's module):
  OK state:
    { schema, as_of, window, state: "OK",
      by_type: { Bug: <block>, Feature: <block>, Task: <block> },
      overall: <block>, excluded_retroactive: [ {item_id, reason}, ... ],
      body_hash, run_meta }
    <block> = { reopened, closed, window, dedup_rows_removed,
                rate: <float> | "RATE_NOT_COMPUTABLE",
                [mismatched_items: [...]], [excluded_retroactive: [...]] }
  NO_DATA_IN_WINDOW state (CT-008 convention, shared verbatim with
  cycle_report.py's own empty-window handling -- a MINIMAL body, never a
  zero-valued by_type/overall statistic dressed up as a real measurement):
    { schema, as_of, window, state: "NO_DATA_IN_WINDOW", body_hash, run_meta }

Exit codes: 0 report written (including the honest NO_DATA_IN_WINDOW empty
state -- an empty window, or a window nothing at all closed or was excluded
from, is not a failure); 2 usage/input error (--as-of missing or malformed,
--window-days not a positive integer, or --tracker-export unreadable or not
valid JSON).

Honest scope boundary (§11.4.6): this tool reads ONLY a --tracker-export
JSON fixture today; it does not yet query the live tracker DB directly, and
cycle_report.py's own CT-006 handling is not yet updated to delegate to
this tool (cycle_report.py's docstring documents that as an "honest scope
substitution" pending this file's existence -- wiring cycle_report.py to
shell out here is a separate, later task, not T100's).

Producer of the T091 RED test's contract (§11.4.240 producer!=verifier):
this file is authored strictly to satisfy tests/test_reopen_rate_red.sh's
already-committed, independently-derived expected_report fixtures; it does
not import, share code with, or otherwise couple to that test's own
from-scratch derive.py oracle function.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers. Imported by
# file path (not a package) since constitution/scripts/fastcycle has no
# __init__.py anywhere -- matches this tree's existing flat-script layout
# (identical to cycle/cycle_report.py's own wiring).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "reopen-rate/v1"
ITEM_TYPES = ("Bug", "Feature", "Task")
CLOSURE_EVENTS = ("Fixed", "Implemented", "Completed")
RETROACTIVE_REASON = "retroactive-registration (Opened->closure db_write gap < 60s)"


# ---------------------------------------------------------------------------
# Small time helpers (identical parsing tolerance to cycle_report.py's own
# parse_iso -- accepts "...Z", offset forms, and SQLite's bare
# "YYYY-MM-DD HH:MM:SS" datetime('now') default shape).
# ---------------------------------------------------------------------------
def parse_iso(value):
    v = value.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    if "T" not in v and " " in v:
        v = v.replace(" ", "T") + "+00:00"
    dt = datetime.datetime.fromisoformat(v)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt


def is_retroactive_registration(history):
    """Identical rule to cycle_report.py's flag_retroactive_registration and
    select_sample.py's detect_retroactive_registration: Opened -> terminal
    closure created_at (db-write) gap in [0, 60) seconds. Reimplemented here
    (never imported) -- this tree's established convention is that each
    flat CLI tool carries its own copy of a shared rule rather than
    cross-importing another tool's module."""
    opened = next((r for r in history if r.get("event_type") == "Opened"), None)
    closed = next((r for r in reversed(history) if r.get("event_type") in CLOSURE_EVENTS), None)
    if not opened or not closed:
        return False
    try:
        gap = (parse_iso(closed["created_at"]) - parse_iso(opened["created_at"])).total_seconds()
    except Exception:
        return False
    return 0 <= gap < 60


def has_closure_ever(history):
    return any(r.get("event_type") in CLOSURE_EVENTS for r in history)


def _day(on_date):
    """Window membership is decided on the calendar DAY (the first 10 chars,
    YYYY-MM-DD). A raw string compare of a full-timestamp on_date
    ("2026-03-31T18:00:00Z") against a bare "2026-03-31" window bound sorts the
    timestamp AFTER the bound and silently drops the window's last day
    (T103 review R1-M2; the live tracker only ever stores 10-char dates, but
    --tracker-export accepts any export)."""
    return (on_date or "")[:10]


def closed_in_window(history, frm, to):
    return any(
        r.get("event_type") in CLOSURE_EVENTS and frm <= _day(r.get("on_date")) <= to
        for r in history
    )


def reopened_in_window(history, frm, to):
    return any(
        r.get("event_type") == "Reopened" and frm <= _day(r.get("on_date")) <= to
        for r in history
    )


def _exact_dup_key(row):
    # Full-content key excluding the autoincrement `id` column -- identical
    # shape to cycle_report.py's own _exact_dup_key, so a genuinely
    # duplicate row (a race/retry re-insert of the identical event) is
    # detected the same way by every tool in this tree that reads
    # item_history. Two genuinely distinct events sharing event_type/
    # on_date but differing in created_at are NOT duplicates (cycle_report.
    # py's own documented false-positive lesson, applied identically here).
    return (
        row.get("event_type"), row.get("by"), row.get("on_date"),
        row.get("reason"), row.get("evidence_path"), row.get("created_at"),
    )


def dedup_history(history):
    """Removes exact-duplicate item_history rows and returns
    (deduped_rows, removed_count). Duplicate rows never change which items
    are members of any window population (the predicates above are ANY-of-
    rows booleans, not row counts) -- this exists to make the contract's
    own `dedup_rows_removed` field an honest, genuinely-computed count
    rather than a hardcoded placeholder."""
    seen = set()
    kept = []
    removed = 0
    for row in history:
        key = _exact_dup_key(row)
        if key in seen:
            removed += 1
            continue
        seen.add(key)
        kept.append(row)
    return kept, removed


def compute_window(as_of, window_days):
    to_date = datetime.date.fromisoformat(as_of)
    from_date = to_date - datetime.timedelta(days=window_days)
    return {"from": from_date.isoformat(), "to": to_date.isoformat()}


# ---------------------------------------------------------------------------
# Core derivation (T-D06's own rule text): "reopened / closed per type per
# window, both counted from the same population (items closed within the
# window) ... reported with window bounds and denominators; retroactive
# registrations excluded and listed."
# ---------------------------------------------------------------------------
def derive_type_block(item_ids, hist_by_item, frm, to):
    excluded = []
    matched_closed = []
    dedup_removed_total = 0
    deduped_by_item = {}

    for aid in item_ids:
        rows, removed = dedup_history(hist_by_item.get(aid, []))
        deduped_by_item[aid] = rows
        dedup_removed_total += removed
        if closed_in_window(rows, frm, to):
            if is_retroactive_registration(rows):
                excluded.append(aid)
            else:
                matched_closed.append(aid)

    # A Reopened-in-window item that is NOT a member of the closed-in-
    # window (matched) population and was NOT excluded as retroactive is a
    # population mismatch (R1 Table D caveat) ONLY if it has no closure
    # event anywhere, ever -- CT-006's exact "reopened items may have been
    # closed before item_history began, or by rows not in history" case.
    mismatched = []
    for aid in item_ids:
        rows = deduped_by_item.get(aid, [])
        if (
            reopened_in_window(rows, frm, to)
            and aid not in matched_closed
            and aid not in excluded
            and not has_closure_ever(rows)
        ):
            mismatched.append(aid)

    closed_count = len(matched_closed)
    reopened_count = sum(
        1 for aid in matched_closed if reopened_in_window(deduped_by_item.get(aid, []), frm, to)
    )

    block = {
        "reopened": reopened_count,
        "closed": closed_count,
        "window": {"from": frm, "to": to},
        "dedup_rows_removed": dedup_removed_total,
    }
    if excluded:
        block["excluded_retroactive"] = [
            {"item_id": aid, "reason": RETROACTIVE_REASON} for aid in sorted(excluded)
        ]
    if mismatched:
        # NEVER divide two mismatched counts (the "18 of 31" defect) --
        # refuse and name the mismatched item(s) instead.
        block["rate"] = "RATE_NOT_COMPUTABLE"
        block["mismatched_items"] = sorted(mismatched)
    elif closed_count == 0:
        block["rate"] = "RATE_NOT_COMPUTABLE"
    else:
        block["rate"] = round(reopened_count / closed_count, 6)

    return block, excluded, mismatched


def derive_report(items, history, frm, to):
    hist_by_item = {}
    for row in history:
        hist_by_item.setdefault(row.get("atm_id"), []).append(row)
    ids_by_type = {}
    for it in items:
        ids_by_type.setdefault(it.get("type"), []).append(it.get("atm_id"))

    by_type = {}
    total_closed = 0
    total_reopened = 0
    total_dedup_removed = 0
    total_excluded = []
    total_mismatched = []

    for t in ITEM_TYPES:
        ids = ids_by_type.get(t, [])
        block, excluded, mismatched = derive_type_block(ids, hist_by_item, frm, to)
        by_type[t] = block
        total_closed += block["closed"]
        total_reopened += block["reopened"]
        total_dedup_removed += block["dedup_rows_removed"]
        total_excluded.extend(excluded)
        total_mismatched.extend(mismatched)

    overall = {
        "reopened": total_reopened,
        "closed": total_closed,
        "window": {"from": frm, "to": to},
        "dedup_rows_removed": total_dedup_removed,
    }
    if total_excluded:
        overall["excluded_retroactive"] = [
            {"item_id": aid, "reason": RETROACTIVE_REASON} for aid in sorted(total_excluded)
        ]
    if total_mismatched:
        # The Bug type's own mismatch MUST NOT be silently dropped from, nor
        # silently included in, the aggregate -- the overall rate refuses
        # too, one layer up, exactly as CT-006 requires for the per-type
        # case (a quietly-excluded or quietly-included ambiguous type would
        # itself be the same class of population-mismatch bluff).
        overall["rate"] = "RATE_NOT_COMPUTABLE"
        overall["mismatched_items"] = sorted(total_mismatched)
    elif total_closed == 0:
        overall["rate"] = "RATE_NOT_COMPUTABLE"
    else:
        overall["rate"] = round(total_reopened / total_closed, 6)

    # Honest empty state (CT-008 convention, shared verbatim with
    # cycle_report.py): NO_DATA_IN_WINDOW iff NO item has ANY closure or
    # Reopened event inside the window -- never a zero-valued by_type/overall
    # statistic presented as a real measurement. Both directions are
    # window-scoped (T103 review R1-I1): an in-window Reopened event IS data
    # even when nothing closed in-window (the mismatched_items refusal of a
    # never-closed reopened item must be REPORTED, not hidden behind "no
    # data"), and a retroactive registration that happened long BEFORE the
    # window is NOT in-window activity (it previously forced state OK on a
    # genuinely empty window). Retroactive exclusions only ever arise from an
    # in-window closure, so they are already covered by closed_in_window().
    if any(
        closed_in_window(hist_by_item.get(it.get("atm_id"), []), frm, to)
        or reopened_in_window(hist_by_item.get(it.get("atm_id"), []), frm, to)
        for it in items
    ):
        state = "OK"
    else:
        state = "NO_DATA_IN_WINDOW"

    excluded_ids_top = sorted(set(total_excluded))
    excluded_retroactive_top = [
        {"item_id": aid, "reason": RETROACTIVE_REASON} for aid in excluded_ids_top
    ]

    return state, by_type, overall, excluded_retroactive_top


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash, identical convention to
# cycle_report.py's own write_report).
# ---------------------------------------------------------------------------
def write_report(out_path, body, run_meta):
    doc = dict(body)
    doc["schema"] = SCHEMA
    doc["body_hash"] = body_hash_of({**doc})
    doc["run_meta"] = run_meta
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".reopen_rate.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def require_as_of(as_of):
    if not as_of:
        print("reopen_rate: --as-of YYYY-MM-DD is required (no default to today)", file=sys.stderr)
        return False
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", as_of):
        print("reopen_rate: --as-of must be YYYY-MM-DD, got %r" % as_of, file=sys.stderr)
        return False
    try:
        datetime.date.fromisoformat(as_of)
    except ValueError:
        print("reopen_rate: --as-of is not a valid calendar date: %r" % as_of, file=sys.stderr)
        return False
    return True


def build_arg_parser():
    p = argparse.ArgumentParser(prog="reopen_rate.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--as-of", required=True)
    p.add_argument("--window-days", type=int, default=90)  # DEC-03 convention (cycle_report.py parity)
    p.add_argument("--tracker-export", required=True)
    p.add_argument("--out", required=True)
    # US3 checkpoint gate (tasks.md "Checkpoint (US3 / Phase D gate)":
    # "`escape_classify.py` and `reopen_rate.py` pass --determinism-check";
    # T103 review R1-I10 -- T100 never added it). Identical pattern to the
    # sibling escape_classify.py / cycle_report.py: re-invoke this SAME
    # process twice as subprocesses with their own --out and compare
    # body_hash (run_meta is excluded from the hash by construction).
    p.add_argument("--determinism-check", action="store_true")
    return p


def run_determinism_check(argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    runs = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            # argparse `--out` is last-wins, so ours overrides the caller's.
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                print("reopen_rate: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode != 0 or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("reopen_rate: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        print("reopen_rate: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    print("reopen_rate: deterministic (body_hash=%s)" % runs[0])
    return 0


def main(argv):
    args = build_arg_parser().parse_args(argv)

    if args.determinism_check:
        return run_determinism_check(argv)

    if not require_as_of(args.as_of):
        return 2
    if args.window_days <= 0:
        print("reopen_rate: --window-days must be a positive integer, got %r" % args.window_days,
              file=sys.stderr)
        return 2

    try:
        with open(args.tracker_export, encoding="utf-8") as fh:
            fx = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("reopen_rate: --tracker-export %r unreadable or not valid JSON: %s"
              % (args.tracker_export, exc), file=sys.stderr)
        return 2

    window = compute_window(args.as_of, args.window_days)
    items = fx.get("items", [])
    history = fx.get("item_history", [])

    state, by_type, overall, excluded_retroactive = derive_report(
        items, history, window["from"], window["to"]
    )

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}

    if state == "NO_DATA_IN_WINDOW":
        body = {"as_of": args.as_of, "window": window, "state": "NO_DATA_IN_WINDOW"}
        write_report(args.out, body, run_meta)
        print("reopen_rate: no data in window [%s, %s]" % (window["from"], window["to"]))
        return 0

    body = {
        "as_of": args.as_of,
        "window": window,
        "state": "OK",
        "by_type": by_type,
        "overall": overall,
        "excluded_retroactive": excluded_retroactive,
    }
    write_report(args.out, body, run_meta)
    print(
        "reopen_rate: window=[%s, %s] overall reopened=%d closed=%d rate=%s"
        % (window["from"], window["to"], overall["reopened"], overall["closed"], overall.get("rate"))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
