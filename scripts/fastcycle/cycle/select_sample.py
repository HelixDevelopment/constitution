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
(1) "Bug >=5 (21 available)" -- per-type SELECTION size. A stratum with
    MORE than --min-per-type candidates selects the --min-per-type MOST
    RECENT candidates ranked by closure_recency_key() (the as-of latest
    closure event's created_at, then its row id, then atm_id as the last
    tie-breaker -- NEVER the atm_id string alone: the N2 fix, see that
    function); a stratum with FEWER selects all of them. `below_required`
    is computed on the USABLE count (`n_usable` = selected rows NOT
    excluded_from_duration), never on `n_available` (R5 B2, T048 restart
    round 1: a stratum of 5 selected rows of which 4 are bulk-import rows
    has ONE usable row and is below the requirement -- "selected" is not
    "usable", S11.4.201(9)).
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
    reuses cycle_report.py's (dirname(evidence_path), on_date) key AND its
    default --bulk-threshold (10) verbatim, but NOT its clustering SCOPE:
    cycle_report.py groups clusters PER-TYPE (its full-sampling branch
    re-initialises its `clusters = {}` dict inside its per-type
    `for itype, ids in sorted(by_type.items()):` loop), while this module groups
    clusters ONCE over the CROSS-TYPE UNION `all_candidate_ids` -- a real,
    currently-undocumented-until-this-review divergence (T043 independent
    review, 2026-09-28), NOT reconciled here: verified directly against
    the live DB that a real same-dated 8-item Task cluster combines under
    this module's cross-type scoping with a same-dated 50-item Bug cluster
    into one 58-item group clearing --bulk-threshold=10, where
    cycle_report.py's per-type scoping would NOT flag that 8-item Task
    cluster alone (8 < 10). Cross-type scoping is arguably the more
    conservative choice for THIS module's purpose (it flags a superset of
    what per-type scoping would, erring toward excluding-from-duration
    rather than including a possible bulk-import row) but S11.4.6 forbids
    calling it "exact" reuse of cycle_report.py's rule when the scope
    differs; whether to align the two modules' scoping, or keep this
    module's broader one deliberately, is an open S11.4.66 design decision
    tracked as a follow-up, not settled by this docstring correction.
    Retroactive-registration reuses cycle_report.py's exact Opened-
    db_write-to-terminal-closure-db_write < 60s rule (scope-neutral: it
    runs per-candidate, not per-cluster, so no analogous divergence
    exists).
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
    regardless of any bulk/retroactive flag it may also carry.

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
        [--needle-present-id ATM-953] [--needle-fixed-event Fixed]
        [--needle-fixed-on-date 2026-07-28]
        [--needle-fabricated-id ATM-99999-NEGATIVE-CONTROL]

Exit codes (C-001's uniform 5-code table, same mapping cycle_report.py's own
docstring already uses for this exact tool family): 0 selection written
(including the C-001-consistent NO_DATA_IN_WINDOW state); 1 reserved for a
--determinism-check mismatch (C-003); 2 usage/config error; 3 needle failed
(C-004); 4 tracker DB unreadable (BLIND).

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
import fc_common  # noqa: E402  (path-inserted import, matches cycle_report.py's own convention)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "baseline-sample/v1"
ITEM_TYPES = ("Bug", "Feature", "Task")
CLOSURE_EVENTS = ("Fixed", "Implemented", "Completed")


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
        "AND ih.on_date BETWEEN ? AND ?",
        (frm, to),
    )
    return cur.fetchall()


def db_reopened_in_window(conn, frm, to):
    cur = conn.execute(
        "SELECT DISTINCT ih.atm_id, i.type "
        "FROM item_history ih JOIN items i ON i.atm_id = ih.atm_id "
        "WHERE ih.event_type = 'Reopened' AND ih.on_date BETWEEN ? AND ?",
        (frm, to),
    )
    return cur.fetchall()


def history_upto(history, as_of):
    """R5 B1 fix: the as-of cutoff. Keeps only rows whose on_date calendar
    day is <= as_of (a full-timestamp on_date is compared on its first 10
    chars, the same day-granular rule closure/reopen_rate.py's _day() uses).
    A row with no on_date is dropped (it cannot be placed before the
    cutoff; on_date is NOT NULL in the real schema, so this only guards
    malformed fixtures)."""
    return [r for r in history if r.get("on_date") and r["on_date"][:10] <= as_of]


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
    """Opened db_write -> terminal closure db_write gap in [0, 60) seconds
    (identical rule to cycle_report.py's flag_retroactive_registration)."""
    opened = next((r for r in history if r["event_type"] == "Opened"), None)
    closed = next((r for r in reversed(history) if r["event_type"] in CLOSURE_EVENTS), None)
    if not opened or not closed:
        return False
    try:
        gap = (parse_iso(closed["created_at"]) - parse_iso(opened["created_at"])).total_seconds()
    except Exception:
        return False
    return 0 <= gap < 60


# ---------------------------------------------------------------------------
# Core selection (DEC-03)
# ---------------------------------------------------------------------------
def select_sample(conn, window, min_per_type, bulk_threshold):
    frm, to = window["from"], window["to"]
    as_of = to  # the window always ends on --as-of (main() builds it so)
    closures = db_closures_in_window(conn, frm, to)
    reopens = db_reopened_in_window(conn, frm, to)

    by_type = {}
    for atm_id, itype in closures:
        by_type.setdefault(itype, set()).add(atm_id)
    reopened_ids = {atm_id for atm_id, _ in reopens}
    reopened_type = {atm_id: itype for atm_id, itype in reopens}

    all_candidate_ids = set()
    for ids in by_type.values():
        all_candidate_ids |= ids
    all_candidate_ids |= reopened_ids

    if not all_candidate_ids:
        return None  # NO_DATA_IN_WINDOW

    # N2 fix (T048 round-2 review): resolve every candidate's history ONCE,
    # up front, so both the recency-sort key below AND the per-item
    # exclusion-detection loop further down reuse it (never a stale/second
    # DB round-trip that could observe a different row set mid-selection).
    history_by_id = {atm_id: db_item_history(conn, atm_id, as_of) for atm_id in all_candidate_ids}

    bulk_flagged = detect_bulk_import_clusters(history_by_id, all_candidate_ids, bulk_threshold)

    # Exclusion reason per candidate, computed ONCE before stratification so
    # the strata's usable counts (R5 B2) and the items[] array agree by
    # construction.
    exclusion_by_id = {}
    for atm_id in all_candidate_ids:
        reason = None
        if atm_id in bulk_flagged:
            dirname, on_date = bulk_flagged[atm_id]
            reason = "bulk-import-cluster (dir=%s, on_date=%s, threshold=%d)" % (
                dirname, on_date, bulk_threshold)
        elif detect_retroactive_registration(history_by_id[atm_id]):
            reason = "retroactive-registration (Opened->closure db_write gap < 60s)"
        exclusion_by_id[atm_id] = reason

    strata = {}
    selected_by_type = {}
    for t in ITEM_TYPES:
        # N2 fix (T048 round-2 review): "most recent min_per_type" is a
        # REAL-RECENCY selection (closure_recency_key, above) -- NOT a
        # lexicographic atm_id string sort (the CT-001/DEC-03 bug this
        # fixes; see closure_recency_key's own docstring for the measured
        # ATM-1002/ATM-953 counter-example).
        ids = sorted(by_type.get(t, set()), key=lambda i: closure_recency_key(history_by_id, i))
        n_available = len(ids)
        if n_available > min_per_type:
            picked = ids[-min_per_type:]
        else:
            picked = list(ids)
        # R5 B2 fix: "selected" is not "usable" -- a selected row that is
        # excluded_from_duration (bulk import / retroactive registration)
        # contributes nothing to the duration statistics this sample exists
        # for, so the honesty flag is computed on the usable count.
        n_usable = sum(1 for i in picked if exclusion_by_id[i] is None)
        strata[t] = {
            "n_available": n_available,
            "n_selected": len(picked),
            "n_usable": n_usable,
            "below_required": n_usable < min_per_type,
        }
        selected_by_type[t] = set(picked)

    selected_ids = set()
    for t in ITEM_TYPES:
        selected_ids |= selected_by_type[t]
    selected_ids |= reopened_ids

    items = []
    for atm_id in sorted(selected_ids):
        if atm_id in reopened_ids:
            itype = reopened_type[atm_id]
            selection_reason = "reopened-in-window"
        else:
            itype = next(t for t in ITEM_TYPES if atm_id in selected_by_type[t])
            selection_reason = "sampled-%s" % itype.lower()

        exclusion_reason = exclusion_by_id[atm_id]

        items.append({
            "item_id": atm_id,
            "type": itype,
            "selection_reason": selection_reason,
            "excluded_from_duration": exclusion_reason is not None,
            "exclusion_reason": exclusion_reason,
        })

    return {
        "strata": strata,
        "reopened_in_window": sorted(reopened_ids),
        "items": items,
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
        lines.append("- %s: %d available, %d selected, %d usable%s" % (
            t, s.get("n_available", 0), s.get("n_selected", 0), s.get("n_usable", 0), flag))
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
    p.add_argument("--needle-present-id", default="ATM-953")
    p.add_argument("--needle-fixed-event", default="Fixed")
    p.add_argument("--needle-fixed-on-date", default="2026-07-28")
    p.add_argument("--needle-fabricated-id", default="ATM-99999-NEGATIVE-CONTROL")
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

    ok, detail = run_needle(conn, args.needle_present_id, args.needle_fixed_event,
                             args.needle_fixed_on_date, args.needle_fabricated_id)
    print("select_sample: %s" % detail, file=sys.stderr)
    if not ok:
        return 3

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}

    window = {
        "from": (datetime.date.fromisoformat(args.as_of) - datetime.timedelta(days=args.window_days)).isoformat(),
        "to": args.as_of,
    }

    result = select_sample(conn, window, args.min_per_type, args.bulk_threshold)

    if result is None:
        body = {
            "as_of": args.as_of, "window": window, "window_days": args.window_days,
            "min_per_type": args.min_per_type, "bulk_threshold": args.bulk_threshold,
            "state": "NO_DATA_IN_WINDOW",
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
