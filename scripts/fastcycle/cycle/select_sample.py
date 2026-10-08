#!/usr/bin/env python3
"""select_sample.py - stratified baseline sample selection (spec-004
"fast-dev-cycles", User Story 1, T043; plan.md T-A10; research.md DEC-03,
DEC-36; contracts/common-conventions.md C-001..C-007). Guarded by
constitution/scripts/fastcycle/tests/test_baseline_replay_red.sh (T024).

Purpose: select the DEC-03 stratified baseline sample -- items with a
closure event (Fixed/Implemented/Completed) in a [--as-of - --window-days,
--as-of] window, stratified by type (Bug/Task/Feature), plus every item
reopened in the window -- from the LIVE docs/workable_items.db, read-only,
measuring never inventing (C-004). This is an OPEN-GAP tool: no contract
file covers it (contracts/common-conventions.md's own "Tool map" note lists
"$FC/cycle/select_sample.py (T-A10)" among the tools "no contract in this
directory covers... their interface, output and RED fixtures are fixed by
the plan task text until a contract is written") -- this module follows
plan.md T-A10's own text plus the C-001..C-007 conventions every sibling
$FC tool already follows, and reuses `$FC/cycle/cycle_report.py`'s (T041,
already-reviewed) exact DB-access + git-log-subject-match + write_report
conventions wherever this task's own scope overlaps with that tool's, for
consistency across the fastcycle family -- never a parallel, divergent
re-implementation of an already-settled pattern (S11.4.227).

=============================================================================
DEC-03 SELECTION ALGORITHM (this module's own design judgment calls,
documented per task instruction -- DEC-03's own text leaves three concrete
mechanics unstated; each is resolved below citing the nearest settled
precedent in THIS tree, never invented from nothing per S11.4.6)
=============================================================================
(1) "Bug >=5 (21 available)" -- per-type SELECTION size, in USABLE rows.
    OPERATOR-DECISION-RECORDED (T048 restart round 2, V2-1): DEC-03 /
    research.md is silent on whether a row "excluded from duration
    statistics but listed" counts toward the >=5 quota. Clarification Q3
    asks for >=5 items per type whose durations can be measured, and a
    quota consumed by unusable rows starves the baseline (measured live,
    as-of 2026-08-23 / 90 d / N=5 under the round-1 rule: Bug 1 usable of 5
    selected while 27 usable existed; Task 0 of 5 while 22 existed), so the
    rule implemented is: EXCLUDE FIRST, then take the most-recent N USABLE
    rows. Candidates of a type are walked most-recent-first by
    closure_recency_key() (the as-of latest closure event's created_at, then
    its row id, then atm_id as the last tie-breaker -- never the atm_id
    string alone: the N2 fix); a usable row is TAKEN until N are taken, an
    excluded row encountered on the way is LISTED (it would have consumed
    a slot under the other reading, so it stays visible); the walk stops at
    the N-th usable row. The other reading is ONE constant away:
    EXCLUDED_ROWS_COUNT_TOWARD_N = True restores "most-recent N rows, usable
    or not". The chosen rule is echoed in every report
    (`selection_rule`). `below_required` is computed on the USABLE count
    (`n_usable`), never on `n_available` (R5 B2: "selected" is not "usable",
    S11.4.201(9)). The SAME classifier (classify_exclusions) and the SAME
    walk (select_from_histories) are imported by cycle_report.py -- one
    implementation of "usable", never two copies (V2-2).
(2) "Bulk-import rows (P-04) and retroactive registrations... are excluded
    from duration statistics but listed" -- UNLIKE cycle_report.py's own
    CT-001 (which drops bulk rows from `selected` entirely into a separate
    `excluded` array -- its own docstring calls that "PARTIAL... not
    exhaustively fixture-verified", i.e. NOT a settled cross-tool
    precedent), DEC-03's literal wording for THIS task is "listed", not
    "dropped". This module therefore keeps every stratum-selected or
    reopened-in-window item in the SAME `items` array and marks
    bulk/retroactive rows with `excluded_from_duration: true` +
    `exclusion_reason` on the item itself -- nothing is ever removed from
    `items` (S11.4.6: DEC-03's own words govern over a same-repo sibling
    tool's partial, differently-scoped convention). Bulk-import clustering
    groups candidates by the (dirname(evidence_path), on_date) key of their
    latest as-of closure with a default --bulk-threshold of 10, ONCE over the
    CROSS-TYPE union of every window candidate (the contract's own wording,
    "closure rows sharing one evidence directory and one on_date", names no
    type). OPERATOR-DECISION-RECORDED (T048 restart round 2, V2-2): until
    round 2 cycle_report.py clustered PER-TYPE with its own copy of this
    code, so the two tools could disagree about which rows are usable
    (measured live: a same-dated 8-item Task cluster joins a 50-item Bug
    cluster cross-type but not per-type). There is now ONE classifier,
    classify_exclusions() below, imported by cycle_report.py; the
    cross-type scope was kept because it is the literal contract reading
    and flags a superset (it errs toward excluding a possible bulk-import
    row from duration statistics). The per-type reading is a one-line
    change at classify_exclusions' call sites (pass one type's ids at a
    time). The retroactive-registration rule (Opened db_write to terminal
    closure db_write in [0, 60) s) is detect_retroactive_registration(),
    also imported by cycle_report.py; closure/reopen_rate.py keeps its own
    copy (another area's file) and is cross-checked against this one by
    tests/test_select_sample_r5_regression.sh S7.
(4) AS-OF CUTOFF (R5 B1, T048 restart round 1). Every item_history read
    is cut at --as-of: rows whose on_date (calendar day) is AFTER --as-of
    are invisible to ranking, bulk clustering and the retroactive rule
    (history_upto()). The selection is therefore frozen: rows written to
    the DB after the as-of date never change an as-of report (proved by the
    delete-the-future-rows experiment in
    tests/test_select_sample_r5_regression.sh). Honest boundary (S11.4.6):
    the cutoff keys on on_date -- the same field the window query keys on;
    a row BACKDATED after the fact (written later with an on_date <= as-of)
    is still visible, because the tracker keeps no immutable ingestion log
    to reconstruct "what the DB held on day X" by write time.
(3) Reopened-in-window inclusion is UNCONDITIONAL (DEC-03: "plus every item
    reopened in the window") -- a reopened item is added to `items`
    regardless of whether its type-stratum already filled its N slots and
    regardless of any bulk/retroactive flag it may also carry. "Reopened in
    the window" is decided by reopened_in_window() on the as-of history
    (one definition, also used by cycle_report.py); the window SQL query is
    only the candidate-discovery step.
(5) CURRENT-STATE INPUT (V2-7): items.type is read as it is TODAY. The
    tracker keeps no history of an item's type (`workable-items update
    --type` writes only a generic 'Updated' row), so a retype after the
    as-of date moves an item between strata and is not frozen by --as-of.
    Every report states this under `current_state_inputs`.
(6) CT-009 NEEDLE AT THE AS-OF (V2-8): the default needle row (ATM-953
    Fixed 2026-07-28) is a FUTURE row for any --as-of before 2026-07-28.
    When no --needle-* flag is given and the default's date is after
    --as-of, the needle is derived from the DB at the as-of: the most
    recent closure row dated <= --as-of (resolve_needle()). If NO row at all
    is dated <= --as-of (a window before the tracker began), the default row
    is used as given (source "default-postdates-as-of": it proves the reader
    sees the table and never feeds the report); if it is absent too the
    needle fails and the tool exits 3. Explicit overrides are always
    honoured as given. The needle actually used is recorded in
    run_meta.needle.

=============================================================================
LIVE-DB VERIFICATION AGAINST research.md's CITED FIGURES (S11.4.6: verified
directly against docs/workable_items.db 2026-09-28, NOT assumed)
=============================================================================
research.md P-15 / DEC-03 cite, for SOME unstated as-of date: 90-day window
Bug=21/Task=16/Feature=1(ever=2); 60-day window Bug=5/Task=2/Feature=0.
Querying the LIVE DB directly (`item_history` JOIN `items`, event_type IN
('Fixed','Implemented','Completed'), on_date BETWEEN window bounds) at
as_of=2026-08-23 (the DB's own max(on_date) -- the latest possible as-of a
production run could use today) gives, for the SAME 90-day window shape:
Bug=81, Feature=2, Task=34; for the 60-day shape: Bug=71, Feature=1,
Task=24 -- NONE of these match research.md's cited figures, and the
discrepancy is large (81 vs 21 Bugs; 71 vs 5 Bugs), not a rounding drift.
A per-date breakdown of Bug closures shows a 51-item cluster landing on a
single on_date (2026-08-15) and a 10-item cluster on 2026-06-23 -- the
10-item cluster's evidence_path values were checked directly and are all
DISTINCT directories, so it does NOT match the bulk-import-cluster
detector's own (evidence_dir, on_date) grouping rule; it is real, if
coincidentally same-dated, closure activity, not a detectable bulk-import
batch. research.md's own cited counts are traceable only to an untracked,
ephemeral research artifact (R1:19-21 -- confirmed absent from this repo's
tracked files) from an EARLIER point in this DB's growth, before these
later closure batches landed; §11.4.6 forbids reconciling that gap by
guessing which earlier as-of date would reproduce the cited numbers, and
tasks.md's own T024 RED-test stub 3/3 explicitly anticipates and permits
this exact outcome ("If the live count differs from research.md's cited 5,
that is itself a finding to surface, not silently reconcile"). This module
therefore takes --as-of/--window-days as REQUIRED, non-defaulted CLI
parameters (never hardcoding research.md's stale figures) and reports
whatever the LIVE DB actually holds for the caller's chosen window --
reconciling research.md's own text against the live count (or performing
the full DEC-03 production run) is T-A11 / T045's job, explicitly out of
this task's scope.

=============================================================================
CLI
=============================================================================
    select_sample.py --as-of YYYY-MM-DD --window-days N [--min-per-type 5]
        [--bulk-threshold 10] [--db-path PATH] [--repo-root DIR] --out PATH
        [--md PATH] [--determinism-check]
        [--needle-present-id ID] [--needle-fixed-event EVENT]
        [--needle-fixed-on-date YYYY-MM-DD] [--needle-fabricated-id ID]
        (defaults: ATM-953 Fixed 2026-07-28 / ATM-99999-NEGATIVE-CONTROL;
        derived at the as-of when the default postdates it -- point 6)

Exit codes (C-001's uniform 5-code table, same mapping cycle_report.py's own
docstring already uses for this exact tool family): 0 selection written
(including the C-001-consistent NO_DATA_IN_WINDOW state); 1 reserved for a
--determinism-check mismatch (C-003); 2 usage/config error; 3 needle failed
(C-004); 4 BLIND -- the tracker DB is unreadable, the sibling lib/fc_common.py
cannot be loaded (V3-4), or a --determinism-check run timed out.

Side-effects: read-only on docs/workable_items.db (C-006); writes only
--out (and --md if given). No git operations at all (unlike
cycle_report.py, this tool never touches git log -- item-to-commit
resolution is baseline_replay.sh's job).

Dependencies: Python stdlib only (argparse, datetime, json, os, re,
sqlite3, subprocess, sys, tempfile), matching every sibling $FC tool.
Imports canon/body_hash_of from the sibling lib/fc_common.py (C-002).
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile

_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
# V3-4 (T048 restart round 3): a missing/unreadable/broken sibling module is
# BLIND (C-001 exit 4: no honest output is possible), never the uncaught
# exception's exit 1 -- which C-001 reserves for a determinism mismatch. Run as
# a script, this exits 4; loaded by cycle_report.py, the exception is re-raised
# so cycle_report.py reports its own BLIND exit.
try:
    import fc_common  # noqa: E402  (path-inserted import, matches cycle_report.py's own convention)
except Exception as _exc:  # noqa: BLE001 -- any load failure (ImportError, SyntaxError, ...) is BLIND
    if __name__ == "__main__":
        print("select_sample: BLIND: could not load lib/fc_common.py (%s: %s) -- no honest selection "
              "is possible (C-001 exit 4)" % (type(_exc).__name__, _exc), file=sys.stderr)
        sys.exit(4)
    raise

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "baseline-sample/v1"
ITEM_TYPES = ("Bug", "Feature", "Task")
CLOSURE_EVENTS = ("Fixed", "Implemented", "Completed")

# OPERATOR-DECISION-RECORDED (T048 restart round 2, V2-1; module docstring
# point 1): False = exclude first, then take the most-recent N USABLE rows
# (excluded rows walked past are listed). True = the other DEC-03 reading,
# "most-recent N rows, usable or not". Change this one line to switch.
EXCLUDED_ROWS_COUNT_TOWARD_N = False

# CT-009 default needle (module docstring point 6).
DEFAULT_NEEDLE = ("ATM-953", "Fixed", "2026-07-28")
DEFAULT_FABRICATED_ID = "ATM-99999-NEGATIVE-CONTROL"

# V2-7: inputs read as they are TODAY, not as of --as-of (point 5).
CURRENT_STATE_INPUTS = [{
    "field": "items.type",
    "used_for": "stratum assignment (strata keys, items[].type)",
    "frozen_by_as_of": False,
    "reason": "the tracker keeps no type history: `workable-items update --type` writes only a "
              "generic 'Updated' row, so a retype after the as-of date moves an item between strata",
}]


def default_repo_root():
    # select_sample.py lives at <root>/constitution/scripts/fastcycle/cycle/
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", ".."))


def require_as_of(as_of):
    if not as_of:
        print("select_sample: --as-of YYYY-MM-DD is required (no default to today, C-003)", file=sys.stderr)
        return False
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", as_of):
        print("select_sample: --as-of must be YYYY-MM-DD, got %r" % as_of, file=sys.stderr)
        return False
    try:
        datetime.date.fromisoformat(as_of)
    except ValueError:
        print("select_sample: --as-of is not a valid calendar date: %r" % as_of, file=sys.stderr)
        return False
    return True


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


# ---------------------------------------------------------------------------
# Tracker DB access (read-only, C-006) -- same query shape as
# cycle_report.py's db_closures_in_window / db_reopened_in_window (T041,
# already reviewed) for cross-tool consistency (S11.4.227: reuse the
# settled pattern, never a divergent re-derivation).
# ---------------------------------------------------------------------------
def open_db_readonly(path):
    if not os.path.isfile(path):
        return None
    try:
        uri = "file:%s?mode=ro" % path
        conn = sqlite3.connect(uri, uri=True)
        conn.execute("SELECT 1").fetchone()
        return conn
    except sqlite3.Error:
        return None


def db_closures_in_window(conn, frm, to):
    cur = conn.execute(
        "SELECT DISTINCT ih.atm_id, i.type "
        "FROM item_history ih JOIN items i ON i.atm_id = ih.atm_id "
        "WHERE ih.event_type IN ('Fixed','Implemented','Completed') "
        "AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",
        (frm, to),
    )
    return cur.fetchall()


def db_reopened_in_window(conn, frm, to):
    cur = conn.execute(
        "SELECT DISTINCT ih.atm_id, i.type "
        "FROM item_history ih JOIN items i ON i.atm_id = ih.atm_id "
        "WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",
        (frm, to),
    )
    return cur.fetchall()


def window_for(as_of, window_days):
    """THE analysis window, both tools (round 3: cycle_report.py carried its own
    copy of this arithmetic): [as_of - window_days, as_of], calendar days,
    both ends inclusive."""
    return {"from": (datetime.date.fromisoformat(as_of) - datetime.timedelta(days=window_days)).isoformat(),
            "to": as_of}


def history_upto(history, as_of):
    """R5 B1 fix: the as-of cutoff -- THE one implementation, also used by
    cycle_report.py. Keeps only rows whose on_date calendar day is <= as_of
    (a full-timestamp on_date is compared on its first 10 chars, the same
    day-granular rule closure/reopen_rate.py's _day() and the window SQL
    queries above use). A row dated ON the as-of day is kept (V2-4). A row
    with no on_date is dropped (it cannot be placed before the cutoff;
    on_date is NOT NULL in the real schema, so this only guards malformed
    fixtures)."""
    return [r for r in history if r.get("on_date") and r["on_date"][:10] <= as_of]


def closed_in_window(history, frm, to):
    """THE "closed in the window" rule: a closure event whose on_date calendar
    day lies in [frm, to], both ends inclusive."""
    return any(r["event_type"] in CLOSURE_EVENTS and frm <= (r.get("on_date") or "")[:10] <= to
               for r in history)


def reopened_in_window(history, window):
    """THE "reopened in the window" rule (both tools): a Reopened row whose
    on_date calendar day lies in [window.from, window.to], both ends
    inclusive (V2-4: a row ON window.from counts)."""
    return any(r["event_type"] == "Reopened" and window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]
               for r in history)


def db_item_history(conn, item_id, as_of):
    """Every caller passes the as-of date: there is deliberately no
    un-cut variant in this module (R5 B1 -- a frozen baseline must never
    see an event dated after its own as-of)."""
    cur = conn.execute(
        "SELECT id, event_type, by, on_date, reason, evidence_path, created_at "
        "FROM item_history WHERE atm_id = ? ORDER BY id",
        (item_id,),
    )
    cols = ("id", "event_type", "by", "on_date", "reason", "evidence_path", "created_at")
    rows = [dict(zip(cols, row)) for row in cur.fetchall()]
    return history_upto(rows, as_of)


def latest_closure_event(history):
    for row in reversed(history):
        if row["event_type"] in CLOSURE_EVENTS:
            return row
    return None


def closure_recency_key(history_by_id, atm_id):
    """N2 fix (T048 round-2 review): sort key for "most recent N" stratum
    selection, keyed by the candidate's LATEST closure event's real DB
    write-order fields -- `created_at` (the item_history row's own
    timestamp) then its `id` (the row's own autoincrement primary key, a
    monotonic write-order tie-breaker at second-resolution ties) -- never
    the atm_id STRING. The previous `sorted(ids)` sorted `atm_id` as TEXT:
    "ATM-1002" < "ATM-953" lexicographically ('1' < '9') even though
    1002 > 953 numerically, so real recent closures (verified directly
    against docs/workable_items.db 2026-09-30: ATM-1105 09-29, ATM-1009/
    ATM-1002 09-28, ATM-1025 08-23) were silently excluded from every
    sample in favour of much older ATM-785..953-range ids whose atm_id
    string merely sorted "higher". `atm_id` is kept as a final
    deterministic tie-breaker ONLY (after created_at/id both tie exactly,
    e.g. a same-second batch closure) -- never the primary sort key --
    so --determinism-check (C-003) still gets byte-identical output
    across runs. A candidate with no closure event/created_at sorts FIRST
    (least recent) rather than crashing, per S11.4.6 fail-safe-not-guess.
    """
    closure = latest_closure_event(history_by_id.get(atm_id, []))
    created_at = (closure or {}).get("created_at") or ""
    hist_id = (closure or {}).get("id")
    if hist_id is None:
        hist_id = -1
    return (created_at, hist_id, atm_id)


# ---------------------------------------------------------------------------
# CT-009-style needle (C-004) -- same two-check shape as cycle_report.py's
# run_needle: a known-present closure event MUST be found, a fabricated id
# MUST NOT.
# ---------------------------------------------------------------------------
def resolve_needle(conn, present_id, present_event, present_date, fabricated_id, as_of):
    """V2-8 (module docstring point 6). Returns the needle to run. The CLI
    passes None for every --needle-* flag the caller did not give."""
    if any(v is not None for v in (present_id, present_event, present_date)):
        d_id, d_ev, d_date = DEFAULT_NEEDLE
        return {"source": "override", "present_id": present_id or d_id,
                "present_event": present_event or d_ev, "present_on_date": present_date or d_date,
                "fabricated_id": fabricated_id or DEFAULT_FABRICATED_ID}
    d_id, d_ev, default_date = DEFAULT_NEEDLE
    if default_date <= as_of:
        return {"source": "default", "present_id": d_id, "present_event": d_ev,
                "present_on_date": default_date,
                "fabricated_id": fabricated_id or DEFAULT_FABRICATED_ID}
    row = conn.execute(
        "SELECT atm_id, event_type, on_date FROM item_history "
        "WHERE event_type IN ('Fixed','Implemented','Completed') AND substr(on_date, 1, 10) <= ? "
        "ORDER BY substr(on_date, 1, 10) DESC, id DESC LIMIT 1", (as_of,)).fetchone()
    if row is None:
        # Nothing at all is dated <= as-of (e.g. an empty window long before
        # the tracker began): no as-of row can prove the reader sees data, so
        # the default row is used as given -- it proves the reader sees the
        # table, never contributes to the report, and run_needle() still fails
        # closed (exit 3) if it is absent too.
        return {"source": "default-postdates-as-of", "present_id": d_id, "present_event": d_ev,
                "present_on_date": default_date,
                "fabricated_id": fabricated_id or DEFAULT_FABRICATED_ID,
                "why": "no closure row is dated <= --as-of %s to derive a needle from" % as_of}
    return {"source": "derived-at-as-of", "present_id": row[0], "present_event": row[1],
            "present_on_date": row[2], "fabricated_id": fabricated_id or DEFAULT_FABRICATED_ID,
            "why": "default needle row %s %s/%s postdates --as-of %s" % (d_id, d_ev, default_date, as_of)}


def run_needle(conn, present_id, present_event, present_date, fabricated_id):
    cur = conn.execute(
        "SELECT event_type, on_date FROM item_history WHERE atm_id = ? "
        "AND event_type = ? AND on_date = ?",
        (present_id, present_event, present_date),
    )
    found_present = cur.fetchone() is not None
    cur = conn.execute("SELECT atm_id FROM items WHERE atm_id = ?", (fabricated_id,))
    found_fabricated = cur.fetchone() is not None
    if found_present and not found_fabricated:
        return True, "needle ok: %s %s/%s present, %s absent" % (
            present_id, present_event, present_date, fabricated_id)
    problems = []
    if not found_present:
        problems.append("known-present %s %s/%s NOT FOUND" % (present_id, present_event, present_date))
    if found_fabricated:
        problems.append("fabricated id %s WAS FOUND (false match)" % fabricated_id)
    return False, "needle FAILED: " + "; ".join(problems)


# ---------------------------------------------------------------------------
# Bulk-import + retroactive-registration detection (DEC-03 clause;
# cycle_report.py's CT-001 clustering KEY + default threshold reused, but
# scoped cross-type here (this module) vs per-type there -- see module
# docstring point (2) for the full divergence + why this module keeps
# rather than drops flagged rows).
# ---------------------------------------------------------------------------
def detect_bulk_import_clusters(history_by_id, candidate_ids, bulk_threshold):
    """Group candidates by (dirname(closure evidence_path), on_date) of
    their LATEST AS-OF closure event (matches cycle_report.py's own
    latest_closure_event convention). A cluster >= bulk_threshold flags
    every member. Returns {atm_id: (dirname, on_date)} for flagged ids.
    R5 B1 fix: reads the caller's already as-of-cut `history_by_id` -- the
    pre-fix version re-queried the DB un-cut, so a FUTURE re-closure that
    happened to share a directory/date clustered in-window items into a
    fake bulk cluster."""
    clusters = {}
    for atm_id in sorted(candidate_ids):
        hist = history_by_id.get(atm_id, [])
        closure = latest_closure_event(hist)
        if closure and closure.get("evidence_path"):
            ekey = (os.path.dirname(closure["evidence_path"]), closure.get("on_date"))
        else:
            ekey = None
        clusters.setdefault(ekey, []).append(atm_id)
    flagged = {}
    for ekey, members in clusters.items():
        if ekey is not None and len(members) >= bulk_threshold:
            for atm_id in members:
                flagged[atm_id] = ekey
    return flagged


def detect_retroactive_registration(history):
    """Opened db_write -> terminal closure db_write gap in [0, 60) seconds.
    THE one implementation in the cycle tools (cycle_report.py imports it as
    its RETROACTIVE_REGISTRATION flag); a negative gap (closure row written
    before the Opened row) is NOT a retroactive registration (V2-4)."""
    opened = next((r for r in history if r["event_type"] == "Opened"), None)
    closed = next((r for r in reversed(history) if r["event_type"] in CLOSURE_EVENTS), None)
    if not opened or not closed:
        return False
    try:
        gap = (parse_iso(closed["created_at"]) - parse_iso(opened["created_at"])).total_seconds()
    except Exception:
        return False
    return 0 <= gap < 60


RETROACTIVE_REASON = "retroactive-registration (Opened->closure db_write gap < 60s)"


def classify_exclusions(history_by_id, candidate_ids, bulk_threshold):
    """THE usable/excluded classifier (V2-2: imported by cycle_report.py,
    never copied). `history_by_id` must already be cut at the as-of.
    Returns {atm_id: exclusion_reason or None}; None = usable for duration
    statistics."""
    bulk_flagged = detect_bulk_import_clusters(history_by_id, candidate_ids, bulk_threshold)
    exclusion_by_id = {}
    for atm_id in sorted(candidate_ids):
        reason = None
        if atm_id in bulk_flagged:
            dirname, on_date = bulk_flagged[atm_id]
            reason = "bulk-import-cluster (dir=%s, on_date=%s, threshold=%d)" % (
                dirname, on_date, bulk_threshold)
        elif detect_retroactive_registration(history_by_id.get(atm_id, [])):
            reason = RETROACTIVE_REASON
        exclusion_by_id[atm_id] = reason
    return exclusion_by_id


def select_from_histories(by_type, history_by_id, exclusion_by_id, min_per_type, take_all=False):
    """THE per-type selection walk and stratum count (V2-1/V2-2: imported by
    cycle_report.py). `by_type` maps type -> ids with a closure event in the
    window. Returns (strata, picked_by_type, listed_by_type).

    take_all=False: module docstring point 1 (exclude first, most-recent N
    usable, excluded rows walked past are listed; or the other reading when
    EXCLUDED_ROWS_COUNT_TOWARD_N). take_all=True: every candidate is taken
    (cycle_report.py's single-item and --window-json modes) and only the
    counts are shared.

    Every stratum count the two tools report comes from here:
      n_available        candidates of the type with a closure in the window
      n_usable_available of those, not excluded
      n_selected         taken into the sample
      n_usable           taken AND usable -- the honesty count
      n_listed_excluded  excluded rows listed (not taken)
      below_required     n_usable < min_per_type"""
    strata, picked_by_type, listed_by_type = {}, {}, {}
    for t in ITEM_TYPES:
        # N2 fix: REAL-RECENCY order (closure_recency_key), never atm_id text.
        ids = sorted(by_type.get(t, set()), key=lambda i: closure_recency_key(history_by_id, i))
        n_available = len(ids)
        picked, listed = [], []
        if take_all:
            picked = list(ids)
        elif EXCLUDED_ROWS_COUNT_TOWARD_N:
            picked = ids[-min_per_type:] if n_available > min_per_type else list(ids)
        else:
            for atm_id in reversed(ids):
                if len(picked) >= min_per_type:
                    break
                if exclusion_by_id[atm_id] is None:
                    picked.append(atm_id)
                else:
                    listed.append(atm_id)
        n_usable = sum(1 for i in picked if exclusion_by_id[i] is None)
        strata[t] = {
            "n_available": n_available,
            "n_usable_available": sum(1 for i in ids if exclusion_by_id[i] is None),
            "n_selected": len(picked),
            "n_usable": n_usable,
            "n_listed_excluded": len(listed),
            "below_required": n_usable < min_per_type,
        }
        picked_by_type[t] = picked
        listed_by_type[t] = listed
    return strata, picked_by_type, listed_by_type


def selection_rule(take_all=False):
    """The rule actually applied, echoed into every report (point 1)."""
    if take_all:
        return {"mode": "take-all-candidates", "excluded_rows_count_toward_n": None}
    return {"mode": "most-recent-n-per-type",
            "excluded_rows_count_toward_n": EXCLUDED_ROWS_COUNT_TOWARD_N,
            "decision": "OPERATOR-DECISION-RECORDED (T048 restart round 2, V2-1): DEC-03 is silent; "
                        "a quota eaten by unusable rows starves the baseline, so excluded rows are "
                        "listed but do not count toward N"}


# ---------------------------------------------------------------------------
# Core selection (DEC-03)
# ---------------------------------------------------------------------------
def select_sample(conn, window, min_per_type, bulk_threshold):
    frm, to = window["from"], window["to"]
    as_of = to  # the window always ends on --as-of (main() builds it so)
    closures = db_closures_in_window(conn, frm, to)
    reopens = db_reopened_in_window(conn, frm, to)

    type_of = {atm_id: itype for atm_id, itype in list(closures) + list(reopens)}
    if not type_of:
        return None  # NO_DATA_IN_WINDOW
    # Every candidate's history is resolved ONCE, cut at the as-of, and every
    # decision below (window membership, ranking, exclusion) reads only it.
    history_by_id = {atm_id: db_item_history(conn, atm_id, as_of) for atm_id in type_of}
    return select_population(type_of, history_by_id, window, min_per_type, bulk_threshold)


def select_population(type_of, history_by_id, window, min_per_type, bulk_threshold, take_all=False):
    """THE DEC-03 selection over a candidate population (V2-2: cycle_report.py
    calls this same function in every mode, so both tools report the same
    items, exclusions and stratum counts for the same window).

    type_of: {atm_id: type} -- every candidate (the window SQL queries are
    only the DISCOVERY step); history_by_id: {atm_id: history cut at the
    as-of}. Window membership is re-decided on the cut history by the same
    day-granular rules (closed_in_window / reopened_in_window).

    Returns {strata, reopened_in_window, items, exclusion_by_id}."""
    frm, to = window["from"], window["to"]
    by_type = {}
    for atm_id in sorted(type_of):
        if closed_in_window(history_by_id.get(atm_id, []), frm, to):
            by_type.setdefault(type_of[atm_id], set()).add(atm_id)
    reopened_ids = {atm_id for atm_id in type_of
                    if reopened_in_window(history_by_id.get(atm_id, []), window)}

    exclusion_by_id = classify_exclusions(history_by_id, set(type_of), bulk_threshold)
    strata, picked_by_type, listed_by_type = select_from_histories(
        by_type, history_by_id, exclusion_by_id, min_per_type, take_all=take_all)

    reason_by_id = {}
    for t in ITEM_TYPES:
        for atm_id in listed_by_type[t]:
            reason_by_id[atm_id] = "listed-excluded-%s" % t.lower()
        for atm_id in picked_by_type[t]:
            reason_by_id[atm_id] = "sampled-%s" % t.lower()
    for atm_id in reopened_ids:
        reason_by_id[atm_id] = "reopened-in-window"
    if take_all:
        # every candidate is in the report, closure-in-window or not
        for atm_id in type_of:
            reason_by_id.setdefault(atm_id, "sampled-%s" % type_of[atm_id].lower())

    items = []
    for atm_id in sorted(reason_by_id):
        exclusion_reason = exclusion_by_id[atm_id]
        items.append({
            "item_id": atm_id,
            "type": type_of[atm_id],
            "selection_reason": reason_by_id[atm_id],
            "excluded_from_duration": exclusion_reason is not None,
            "exclusion_reason": exclusion_reason,
        })

    return {
        "strata": strata,
        "reopened_in_window": sorted(reopened_ids),
        "items": items,
        "exclusion_by_id": exclusion_by_id,
    }




# ---------------------------------------------------------------------------
# Output assembly (C-002)
# ---------------------------------------------------------------------------
def write_report(out_path, body, run_meta):
    doc = dict(body)
    doc["schema"] = SCHEMA
    doc["body_hash"] = body_hash_of({**doc})
    doc["run_meta"] = run_meta
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".select_sample.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


def render_md(doc):
    lines = ["# Baseline Sample Selection", ""]
    if doc.get("state") == "NO_DATA_IN_WINDOW":
        w = doc["window"]
        lines.append("no data in window [%s, %s]" % (w["from"], w["to"]))
        return "\n".join(lines) + "\n"
    lines.append("as_of: %s" % doc.get("as_of"))
    lines.append("window: %s .. %s (%d days)" % (doc["window"]["from"], doc["window"]["to"], doc["window_days"]))
    lines.append("")
    for t in ITEM_TYPES:
        s = doc["strata"].get(t, {})
        flag = " (BELOW REQUIRED)" if s.get("below_required") else ""
        lines.append("- %s: %d available (%d usable), %d selected, %d usable, %d excluded listed%s" % (
            t, s.get("n_available", 0), s.get("n_usable_available", 0), s.get("n_selected", 0),
            s.get("n_usable", 0), s.get("n_listed_excluded", 0), flag))
    lines.append("- reopened-in-window: %d" % len(doc.get("reopened_in_window", [])))
    lines.append("")
    for it in doc.get("items", []):
        excl = " [EXCLUDED FROM DURATION: %s]" % it["exclusion_reason"] if it["excluded_from_duration"] else ""
        lines.append("- %s (%s) %s%s" % (it["item_id"], it["type"], it["selection_reason"], excl))
    return "\n".join(lines) + "\n"


def build_arg_parser():
    p = argparse.ArgumentParser(prog="select_sample.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--as-of", required=True)
    p.add_argument("--window-days", type=int, required=True)
    p.add_argument("--min-per-type", type=int, default=5)
    p.add_argument("--bulk-threshold", type=int, default=10)
    p.add_argument("--db-path")
    p.add_argument("--repo-root")
    p.add_argument("--out", required=True)
    p.add_argument("--md")
    p.add_argument("--determinism-check", action="store_true")
    # None = not given: resolve_needle() applies the default, or derives the
    # needle at the as-of when the default postdates it (V2-8).
    p.add_argument("--needle-present-id")
    p.add_argument("--needle-fixed-event")
    p.add_argument("--needle-fixed-on-date")
    p.add_argument("--needle-fabricated-id")
    return p


def _strip_flag_with_value(argv, flag):
    """Remove `flag VALUE` and `flag=VALUE` occurrences from argv."""
    out, skip = [], False
    for a in argv:
        if skip:
            skip = False
            continue
        if a == flag:
            skip = True
            continue
        if a.startswith(flag + "="):
            continue
        out.append(a)
    return out


def run_determinism_check(argv, args, repo_root):
    """C-003: run the tool twice in fresh subprocesses and compare body_hash.
    R5 M10 fixes: the caller's --out/--md are stripped from the inner runs
    (previously --md was written twice, by both runs, and --out was never
    written at all); on a deterministic verdict run 1's document is written
    to the caller's --out (and --md rendered once). A child that exits 2/3/4
    has its OWN code propagated (a usage error or a failed needle is not a
    determinism finding); a timeout is BLIND (exit 4, C-001: no honest
    verdict is possible) and says so -- it is not reported as an unreadable
    DB."""
    inner = _strip_flag_with_value(_strip_flag_with_value(
        [a for a in argv if a != "--determinism-check"], "--out"), "--md")
    runs, docs = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, timeout=120)
            except subprocess.TimeoutExpired:
                print("select_sample: BLIND: determinism-check run %d timed out after 120s -- "
                      "no determinism verdict is possible (C-001 exit 4)" % i, file=sys.stderr)
                return 4
            if proc.returncode != 0 or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("select_sample: determinism-check run %d exited %d -- propagating it "
                      "(no determinism verdict)" % (i, proc.returncode), file=sys.stderr)
                return proc.returncode if proc.returncode in (2, 3, 4) else 4
            with open(out_i, encoding="utf-8") as fh:
                doc = json.load(fh)
            runs.append(doc.get("body_hash"))
            docs.append(doc)
    if runs[0] is None or runs[0] != runs[1]:
        print("select_sample: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    body = {k: v for k, v in docs[0].items() if k not in ("schema", "body_hash", "run_meta")}
    doc = write_report(args.out, body, docs[0].get("run_meta", {}))
    if args.md:
        with open(args.md, "w", encoding="utf-8") as fh:
            fh.write(render_md(doc))
    print("select_sample: deterministic (body_hash=%s)" % runs[0])
    return 0


def main(argv):
    args = build_arg_parser().parse_args(argv)

    if not require_as_of(args.as_of):
        return 2
    if args.window_days <= 0:
        print("select_sample: --window-days must be a positive integer, got %r" % args.window_days, file=sys.stderr)
        return 2
    if args.min_per_type <= 0:
        print("select_sample: --min-per-type must be a positive integer, got %r" % args.min_per_type, file=sys.stderr)
        return 2

    repo_root = os.path.abspath(args.repo_root) if args.repo_root else default_repo_root()
    db_path = args.db_path or os.path.join(repo_root, "docs", "workable_items.db")

    if args.determinism_check:
        return run_determinism_check(argv, args, repo_root)

    conn = open_db_readonly(db_path)
    if conn is None:
        print("select_sample: tracker DB unreadable at %s" % db_path, file=sys.stderr)
        return 4

    needle = resolve_needle(conn, args.needle_present_id, args.needle_fixed_event,
                            args.needle_fixed_on_date, args.needle_fabricated_id, args.as_of)
    ok, detail = run_needle(conn, needle["present_id"], needle["present_event"],
                            needle["present_on_date"], needle["fabricated_id"])
    print("select_sample: %s (needle source: %s)" % (detail, needle["source"]), file=sys.stderr)
    if not ok:
        return 3

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown", "needle": needle}

    window = window_for(args.as_of, args.window_days)

    result = select_sample(conn, window, args.min_per_type, args.bulk_threshold)

    if result is None:
        body = {
            "as_of": args.as_of, "window": window, "window_days": args.window_days,
            "min_per_type": args.min_per_type, "bulk_threshold": args.bulk_threshold,
            "state": "NO_DATA_IN_WINDOW",
            "selection_rule": selection_rule(), "current_state_inputs": CURRENT_STATE_INPUTS,
        }
        doc = write_report(args.out, body, run_meta)
        if args.md:
            with open(args.md, "w", encoding="utf-8") as fh:
                fh.write(render_md(doc))
        print("select_sample: no data in window [%s, %s]" % (window["from"], window["to"]))
        return 0

    body = {
        "as_of": args.as_of, "window": window, "window_days": args.window_days,
        "min_per_type": args.min_per_type, "bulk_threshold": args.bulk_threshold,
        "state": "OK",
        "selection_rule": selection_rule(), "current_state_inputs": CURRENT_STATE_INPUTS,
        "strata": result["strata"],
        "reopened_in_window": result["reopened_in_window"],
        "items": result["items"],
    }
    doc = write_report(args.out, body, run_meta)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as fh:
            fh.write(render_md(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
