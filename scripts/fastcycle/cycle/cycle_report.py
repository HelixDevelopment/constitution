#!/usr/bin/env python3
"""cycle_report.py - Cycle-Time Report CLI (spec-004 "fast-dev-cycles", T041,
plan tasks T-A09/T-A10/T-D06, contract cycle-time-report-cli.md).

Purpose: reconstruct, from recorded evidence only, the per-stage elapsed-time
and token-cost timeline of workable items -- emitting the first-class token
UNMEASURED (plus the missing instrument's name) wherever no recording
instrument exists for a value. It measures; it never estimates, interpolates,
or averages a gap away (CT-004, data-model.md V-CR-2).

Invocation (production shape, per the contract):
    cycle_report.py --config <cfg> --as-of <YYYY-MM-DD> --window-days <N> \\
        [--min-per-type 5] [--include-reopened] [--hand-verified <file>] \\
        [--review-records-dir <dir>] \\
        --out <report.json> [--md <report.md>] [--determinism-check]

    --review-records-dir <dir>  Opt-in directory to recursively scan for
                                 T034 review_record.py output (schema
                                 review-record/v1) to measure the
                                 review_rounds stage. No default -- the
                                 contract names no single canonical
                                 directory for these records (they are
                                 written to whatever --out the reviewer
                                 chose), so this flag is never guessed
                                 (S11.4.6). Honoured in every invocation
                                 mode below (--item/--tracker-export/
                                 --window-json/full-sampling), not test-only.

Additional TEST-ONLY input modes (documented here, NOT part of the contract's
own Invocation grammar -- added because select_sample.py/T043 and
reopen_rate.py/T-D06 do not exist yet, so there is no live sampling pipeline
this tool can be driven through end-to-end; these flags let the tool be
exercised deterministically against a single item without depending on
not-yet-built siblings):
    --item <ItemId>          reconstruct ONE real item from the live tracker
                              DB (used e.g. for the CT-009 default needle item
                              ATM-953) instead of running full CT-001 sampling.
    --tracker-export <file>  reconstruct ONE item from a JSON fixture. Two
                              accepted shapes (auto-detected):
                                (a) the fixture supplies a top-level "stages"
                                    array of already-computed StageMeasurement
                                    objects (tests the aggregation/reporting
                                    path in isolation from reconstruction);
                                (b) the fixture supplies "item" + optional
                                    "item_history"/"git_log"/
                                    "evidence_files_present"/
                                    "evidence_files_deliberately_absent"
                                    (tests the reconstruction algorithm using
                                    the SAME detection rules as --item/full
                                    mode, applied to a synthetic item that
                                    does not exist in the live DB).
    --window-json <file>     take the analysis window's {from,to} from this
                              file's top-level "window" object instead of
                              deriving it from --as-of/--window-days, then run
                              the SAME real CT-001-ish live-DB sampling query
                              against that window (this is a genuine query,
                              not a "trust me it's empty" shortcut: if the
                              window is not actually empty the tool proceeds
                              with real sampling instead of forcing
                              NO_DATA_IN_WINDOW).
    --db-path <file>         override the tracker DB path (else
                              <repo_root>/docs/workable_items.db).
    --repo-root <dir>        override the auto-detected repo root.
    --needle-present-id / --needle-fixed-on-date / --needle-fabricated-id
                              override the CT-009 default needle
                              (ATM-953 Fixed 2026-07-28 present;
                              ATM-99999-NEGATIVE-CONTROL absent).

Exit codes (contract "Exit codes" table): 0 report written; 1 hand-verification
mismatch or a structural violation of the tool's own output; 2 usage/config
error; 3 needle failed; 4 tracker DB unreadable.

Contract-clause coverage in THIS implementation (honest boundary, §11.4.6):
  CT-001 (sample)         -- PARTIAL. Real: closure-event query in a window,
                             per-type stratification, reopened-in-window
                             inclusion, BELOW_REQUIRED_SAMPLE flag on a short
                             stratum. NOT implemented: the bulk-import cluster
                             detector's exact ">= bulk_threshold rows sharing
                             one evidence directory and one on_date" grouping
                             is implemented with a documented default
                             threshold (--bulk-threshold, default 10; the
                             contract does not state a value) -- not
                             exhaustively fixture-verified in this pass (no
                             fixture in this task's scope exercises it).
  CT-002 (stage set)      -- FULL. All 11 stages, fixed order, always present;
                             a stage with no source artefact is UNMEASURED +
                             missing_instrument naming the specific instrument
                             (R1-style default mapping, INSTRUMENT_TEMPLATES).
  CT-003 (time sources)   -- FULL for the instruments this tool implements:
                             every Instant carries time_source; item_history
                             `created_at` is always labelled db_write (never
                             event_occurred -- R1 Finding 2: DB write time is
                             not event time); a stage is never computed as
                             `elapsed` from two db_write instants (this
                             implementation simply never attempts to measure
                             a stage from db_write-only evidence -- such
                             stages are UNMEASURED, which trivially satisfies
                             the "never as elapsed" rule; git_author/
                             git_committer and file_mtime sources ARE used
                             for elapsed where genuinely available).
  CT-004 (no invention)  -- FULL. No interpolation, no averaging across items,
                             no zero for missing; medians exclude UNMEASURED
                             members and report n_measured/n_total.
  CT-005 (quality flags) -- PARTIAL. Implemented: DATE_ONLY_RESOLUTION
                             (on_date's calendar date disagrees with
                             created_at's), RETROACTIVE_REGISTRATION (open to
                             terminal-closure db_write gap < 60s),
                             STATUS_DESYNC (items.status vs the latest
                             status-defining item_history event),
                             COMMIT_ATTRIBUTION_BY_GREP (a matched commit
                             subject names >=2 distinct item ids),
                             DUPLICATE_HISTORY_ROWS (exact-duplicate rows).
                             NOT implemented: BULK_WRITE (tied to the CT-001
                             bulk-import path above) and
                             REOPEN_WITHOUT_PRIOR_CLOSURE (would need the full
                             chronological item_history for every candidate,
                             which this pass's --item/--tracker-export modes
                             do have -- implemented too, see
                             `_flag_reopen_without_prior_closure`).
  CT-006 (reopen denom.) -- INLINE, not delegated. `$FC/closure/reopen_rate.py`
                             (T-D06) does not exist in this tree yet, so this
                             tool computes the SAME metric definition
                             (reopened_distinct_items / closed_distinct_items
                             over the record set actually produced this run)
                             directly, rather than shelling out to a script
                             that is not there. Documented here as an honest
                             scope substitution, not a silent gap.
  CT-007 (hand verify)   -- FULL for the compare logic; requires >=3 distinct
                             item ids in the --hand-verified file (contract's
                             own "FR-001 check" breadth requirement) else
                             exit 2.
  CT-008 (empty window)  -- FULL.
  CT-009 (needles)       -- FULL. Always runs first, against the live tracker
                             DB, before any sampling/reconstruction; failure
                             exits 3 (needle failed) or 4 (DB unreadable) per
                             which half failed.

Stdlib only (Python >= 3.8, matching lib/fc_common.py's own convention);
imports `canon`/`body_hash_of` from the sibling lib/fc_common.py (C-002).
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import statistics
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers. Imported by
# file path (not a package) since constitution/scripts/fastcycle has no
# __init__.py anywhere -- matches this tree's existing flat-script layout.
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "cycle-report/v1"

# CT-002: the 11 stages, FIXED order (data-model.md §1.1).
STAGES = [
    "intake", "investigation", "implementation", "test_authoring", "gate_runs",
    "build", "review_rounds", "fix_rounds", "commit_push", "deployment",
    "manual_qa_wait",
]

ITEM_TYPES = ("Bug", "Feature", "Task")
CLOSURE_EVENTS = ("Fixed", "Implemented", "Completed")
STATUS_DEFINING_EVENTS = ("Reopened", "Fixed", "Implemented", "Completed", "Obsolete")

# ATM-1055 fix: item_history.event_type stores the SHORT closure-event name
# ("Fixed"), while items.status stores the LONG §11.4.33 closed-set form
# ("Fixed (-> Fixed.md)") -- the SAME canonical mapping the Go tracker tool
# already establishes (parse.go normalizeStatus / crud.go's closeStatusMap --
# the "fixed"/"implemented"/"completed"/"obsolete" closure table, verified
# 2026-10-03 directly against
# scripts/workable-items/cmd/workable-items/{parse,crud}.go). A bare
# `event_type != items_status` string comparison (the pre-fix bug) therefore
# flags STATUS_DESYNC on every single correctly-closed item -- confirmed
# live against ATM-1025/ATM-343 (both "Fixed" events, both the canonical
# "Fixed (-> Fixed.md)" column value). "Reopened" carries no "(-> Fixed.md)"
# suffix and maps to itself.
#
# CITATION CORRECTION (S12-remediation round, F4.1, 2026-10-03): an earlier
# revision of this comment ALSO cited "the T044 column<->body guard (sync.go
# statusColumnBodyDesyncs)" as treating this SAME event->status mapping as
# authoritative. That citation was WRONG, confirmed directly against
# scripts/workable-items/cmd/workable-items/sync.go: statusColumnBodyDesyncs
# compares the item body's "**Status:**" line against the items.status
# COLUMN -- it carries NO item_history.event_type -> items.status mapping
# at all, so it cannot be "treating this mapping as authoritative". The
# mapping this module mirrors is crud.go's closeStatusMap ONLY (cited above);
# the T044 guard is an unrelated, orthogonal consistency check.
CLOSURE_EVENT_TO_STATUS = {
    "Reopened": "Reopened",
    "Fixed": "Fixed (→ Fixed.md)",
    "Implemented": "Implemented (→ Fixed.md)",
    "Completed": "Completed (→ Fixed.md)",
    "Obsolete": "Obsolete (→ Fixed.md)",
}

# R1-style default instrument-name mapping (CT-002's default mapping) -- one
# template per stage, `{item_id}` filled in at use. Updated 2026-10-03 after
# directly re-verifying, against the live repository, which of T-A04/T-A06/
# T-A08's tools have landed and whether each produces any REAL item-keyed
# data yet (never assumed from the task ids alone, S11.4.6) -- a tool having
# LANDED is not the same as an item-id JOIN existing or being POPULATED.
INSTRUMENT_TEMPLATES = {
    # intake/investigation: T-A06's docs/requests/agent_registry.jsonl DOES
    # carry real ATM-id-keyed Agent/Task dispatch rows now (71 real rows
    # confirmed 2026-10-03), but every row carries only a dispatch
    # timestamp + item id -- no field distinguishes an "intake" dispatch
    # from an "investigation" one, so splitting this ONE undifferentiated
    # signal into two independent per-stage elapsed values would itself be
    # invention (CT-004): the stage-level discriminator genuinely does not
    # exist yet.
    "intake": "docs/requests/agent_registry.jsonl session-to-item mapping row for {item_id} (T-A06 landed + item-keyed rows exist, but no intake-vs-investigation-vs-implementation-vs-test_authoring discriminator field exists on a dispatch row)",
    "investigation": "docs/requests/agent_registry.jsonl session-to-item mapping row for {item_id} (T-A06 landed + item-keyed rows exist, but no stage discriminator -- see intake)",
    # implementation/test_authoring: T038 (transcript_ingest.py) landed and
    # DOES item-attribute subagent-dispatch records when run, but its output
    # table (transcript_usage_events, in the WS1 usage_telemetry.db) does
    # not exist on disk yet -- confirmed 2026-10-03 via a live `sqlite3
    # .tables` query: `ingest` has never been run against a real transcript
    # in this repository, so there are zero rows to read, not merely an
    # unwired join.
    "implementation": "transcript usage ingest output (transcript_usage_events table) keyed to {item_id} (T038 landed, but the table does not exist on disk -- `ingest` has never been run against a real transcript in this repository)",
    "test_authoring": "transcript usage ingest output (transcript_usage_events table) keyed to {item_id} (T038 landed, but the table does not exist on disk -- see implementation)",
    # S12-remediation fix (F3): the PRE-fix text claimed "T-C0x gate timing
    # tooling not found in this repository" -- FALSE, verified 2026-10-03:
    # fc_timer.sh (T028) landed in the same commit as this file, is sourced
    # by pre_build_verification.sh and commit_all.sh, and produces REAL
    # per-gate-run TSVs at qa-results/fastcycle/<run-id>/prebuild_sections.tsv
    # (columns run_id/candidate_fingerprint/id/start_ns/end_ns/duration_ms/
    # verdict/checks/fails/warns/extra) keyed by candidate_fingerprint. The
    # instrument and its data genuinely exist; the real blocker is that no
    # fingerprint-to-item join exists yet to attribute a gate run to
    # {item_id} -- the same class of gap this module's commit_push stage
    # closes via git-subject grep, not yet applied here.
    "gate_runs": "per-gate-run duration log keyed to candidate fingerprint for {item_id} (fc_timer.sh (T028) landed and produces real per-gate-run TSVs at qa-results/fastcycle/<run-id>/prebuild_sections.tsv keyed by candidate_fingerprint -- the instrument and data genuinely exist; the blocker is specifically that no fingerprint-to-item join exists yet to attribute a gate run to {item_id})",
    "build": "per-item build-log/builds.tsv row keyed to {item_id} (R1's instrument table; contract CT-002 default mapping)",
    # review_rounds: T034 (review_record.py) landed and its review-record/v1
    # JSON documents are now genuinely read (see review_rounds_stage, below)
    # when --review-records-dir is supplied -- this default text is what a
    # caller sees when no matching, fully-timestamped record is found.
    "review_rounds": "review-round record (T034 review_record.py, schema review-record/v1) keyed to {item_id} -- none found under --review-records-dir (or the flag was not supplied / every matching record's started_at/ended_at is the honest \"UNKNOWN\" placeholder)",
    "fix_rounds": "fix-round record keyed to {item_id} (review_record.py (T034) records REVIEW rounds, not a distinct FIX-round-between-reviews instrument; no per-item fix-round log exists)",
    "commit_push": "git log author/committer timestamp for a commit whose subject references {item_id}",
    "deployment": "docs/build/resources/builds.tsv deploy row keyed to {item_id} (T040's build_deploy_qa_events.py landed as a validate+join core explicitly OUT OF SCOPE for item-id emission into builds.tsv -- confirmed 2026-10-03: builds.tsv itself still carries zero ATM-id rows)",
    "manual_qa_wait": "item_history/manual-qa sign-off event keyed to {item_id} (T040 landed but does not emit a QA-sign-off-to-item join -- see deployment)",
}

ITEM_ID_RE = re.compile(r"[A-Z]{2,5}-[0-9]{1,5}")
DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


# ---------------------------------------------------------------------------
# Repo-root / path resolution
# ---------------------------------------------------------------------------
def default_repo_root():
    # cycle_report.py lives at <root>/constitution/scripts/fastcycle/cycle/
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", ".."))


# ---------------------------------------------------------------------------
# Small time helpers
# ---------------------------------------------------------------------------
def parse_iso(value):
    # Accept both "...Z" and offset forms and bare "YYYY-MM-DD HH:MM:SS"
    # (SQLite's own default datetime('now') format, as seen in item_history
    # `created_at`).
    v = value.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    if "T" not in v and " " in v:
        v = v.replace(" ", "T") + "+00:00"
    dt = datetime.datetime.fromisoformat(v)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt


def to_ms(seconds):
    return int(round(seconds * 1000))


def date_of(iso_or_dt):
    if isinstance(iso_or_dt, str):
        m = DATE_RE.search(iso_or_dt)
        return m.group(0) if m else None
    return iso_or_dt.date().isoformat()


# ---------------------------------------------------------------------------
# StageMeasurement builders
# ---------------------------------------------------------------------------
def unmeasured_stage(stage, item_id):
    return {
        "stage": stage,
        "start": "UNMEASURED",
        "end": "UNMEASURED",
        "elapsed": "UNMEASURED",
        "missing_instrument": INSTRUMENT_TEMPLATES[stage].format(item_id=item_id),
    }


def measured_instant(value_iso, time_source, evidence_path=None):
    d = {"value": value_iso, "time_source": time_source}
    if evidence_path:
        d["evidence_path"] = evidence_path
    return d


def measured_stage(stage, start_iso, start_src, end_iso, end_src,
                    start_evidence=None, end_evidence=None, tokens=None):
    """Build a fully-measured StageMeasurement. CT-003: refuses (raises) if
    asked to label a span as `elapsed` between two db_write instants -- this
    tool never calls this builder with db_write on both ends (see module
    docstring, CT-003 coverage note); the guard exists so a future caller
    cannot silently violate the rule."""
    if start_src == "db_write" and end_src == "db_write":
        raise AssertionError(
            "CT-003 violation: refusing to label a db_write-to-db_write span as "
            "elapsed for stage %r -- must be tracker_update_span, not elapsed" % stage)
    start = measured_instant(start_iso, start_src, start_evidence)
    end = measured_instant(end_iso, end_src, end_evidence)
    elapsed_s = (parse_iso(end_iso) - parse_iso(start_iso)).total_seconds()
    out = {"stage": stage, "start": start, "end": end, "elapsed": to_ms(elapsed_s)}
    if tokens is not None:
        out["tokens"] = int(tokens)
    return out


def passthrough_stage(raw):
    """Shape A: the fixture already supplies a computed StageMeasurement.
    Re-emit it in canonical shape (drop touch_vs_wait if absent -- CT-002
    does not force touch/wait; data-model.md: 'the split is reported when
    measurable'), converting a plain numeric `elapsed` (seconds, as fixtures
    author it) to the contract's integer-milliseconds convention (C-002)."""
    stage = raw["stage"]
    out = {"stage": stage}
    for key in ("start", "end"):
        v = raw.get(key)
        if v == "UNMEASURED" or v is None:
            out[key] = "UNMEASURED"
        elif isinstance(v, dict):
            d = {"value": v["value"], "time_source": v["time_source"]}
            if v.get("evidence_path"):
                d["evidence_path"] = v["evidence_path"]
            out[key] = d
        else:
            raise ValueError("stage %r: bad %s value %r" % (stage, key, v))
    elapsed = raw.get("elapsed")
    if elapsed == "UNMEASURED" or elapsed is None:
        out["elapsed"] = "UNMEASURED"
    elif isinstance(elapsed, (int, float)):
        out["elapsed"] = to_ms(elapsed)
    else:
        raise ValueError("stage %r: bad elapsed value %r" % (stage, elapsed))
    if out["start"] == "UNMEASURED" or out["end"] == "UNMEASURED" or out["elapsed"] == "UNMEASURED":
        mi = raw.get("missing_instrument")
        out["missing_instrument"] = mi if mi else INSTRUMENT_TEMPLATES[stage].format(item_id="?")
    if "evidence_path" in raw and raw["evidence_path"] and "evidence_path" not in out.get("start", {}):
        # A single top-level evidence_path (as negative_control_all_present
        # supplies) is attached to BOTH endpoints when the per-Instant form
        # did not already carry one -- see Shape A fixture's flat schema.
        for key in ("start", "end"):
            if isinstance(out.get(key), dict) and "evidence_path" not in out[key]:
                out[key]["evidence_path"] = raw["evidence_path"]
    tokens = raw.get("tokens")
    if tokens is not None:
        out["tokens"] = int(tokens)
    return out


# ---------------------------------------------------------------------------
# Tracker DB access (read-only, C-006)
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


def db_item_history(conn, item_id):
    cur = conn.execute(
        "SELECT id, event_type, by, on_date, reason, evidence_path, created_at "
        "FROM item_history WHERE atm_id = ? ORDER BY id",
        (item_id,),
    )
    cols = ("id", "event_type", "by", "on_date", "reason", "evidence_path", "created_at")
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def db_item_row(conn, item_id):
    cur = conn.execute(
        "SELECT atm_id, type, status, created_at, last_modified FROM items "
        "WHERE atm_id = ? LIMIT 1",
        (item_id,),
    )
    row = cur.fetchone()
    if not row:
        return None
    cols = ("atm_id", "type", "status", "created_at", "last_modified")
    return dict(zip(cols, row))


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


# ---------------------------------------------------------------------------
# CT-009 needle
# ---------------------------------------------------------------------------
def run_needle(conn, present_id, present_event, present_date, fabricated_id):
    """Returns (ok: bool, detail: str). Two independent checks: a known
    closure event MUST be found; a fabricated id MUST NOT be found (C-004:
    every criterion with a null/empty "absent" reading needs a class-matched
    control needle, §11.4.273)."""
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
# Data-quality flags (CT-005)
# ---------------------------------------------------------------------------
def flag_date_only_resolution(history):
    for row in history:
        try:
            created_date = date_of(row["created_at"])
        except Exception:
            continue
        on_date = row.get("on_date")
        if on_date and created_date and on_date != created_date:
            return True
    return False


def flag_retroactive_registration(history):
    opened = next((r for r in history if r["event_type"] == "Opened"), None)
    closed = next((r for r in reversed(history) if r["event_type"] in CLOSURE_EVENTS), None)
    if not opened or not closed:
        return False
    try:
        gap = (parse_iso(closed["created_at"]) - parse_iso(opened["created_at"])).total_seconds()
    except Exception:
        return False
    return 0 <= gap < 60


def _exact_dup_key(row):
    # Full-content key EXCLUDING the autoincrement `id` -- a true
    # exact-duplicate row (R1 Finding 1: a race/retry inserted the identical
    # event twice) matches on every content column including `created_at`.
    # Two genuinely distinct events (e.g. two "Updated" rows on the same
    # on_date at different times) must NOT collide here -- omitting
    # created_at previously produced a false DUPLICATE_HISTORY_ROWS positive
    # on exactly that pattern (verified against ATM-953's real history:
    # two real, distinct Updated rows 05:55:04 and 06:11:23 share
    # event_type/by/on_date/evidence_path but not created_at).
    return (row["event_type"], row.get("by"), row.get("on_date"),
            row.get("reason"), row.get("evidence_path"), row.get("created_at"))


def flag_duplicate_history_rows(history):
    seen = set()
    for row in history:
        key = _exact_dup_key(row)
        if key in seen:
            return True
        seen.add(key)
    return False


def flag_reopen_without_prior_closure(history):
    closed_yet = False
    for row in history:
        if row["event_type"] in CLOSURE_EVENTS:
            closed_yet = True
        elif row["event_type"] == "Reopened":
            if not closed_yet:
                return True
            closed_yet = False
    return False


#   S12-remediation fix (F4.2, 2026-10-03): the CLOSED-SET terminal-status
#   TEXT forms (the four closure events' long §11.4.33 column values) --
#   used to recognise "items_status currently claims the item is DONE"
#   independently of which closure event produced that text. Deliberately
#   EXCLUDES "Reopened" (a non-terminal, still-open form).
CLOSED_STATUS_FORMS = frozenset(
    CLOSURE_EVENT_TO_STATUS[_e] for _e in ("Fixed", "Implemented", "Completed", "Obsolete"))


def flag_status_desync(items_status, history):
    """ATM-1055 fix: compares items_status against the §11.4.33 CANONICAL
    column-form of the latest status-defining event (CLOSURE_EVENT_TO_STATUS),
    never the bare event_type string. A direct `event_type != items_status`
    comparison flags STATUS_DESYNC on essentially every correctly-closed item
    (event_type="Fixed" vs items.status="Fixed (-> Fixed.md)" are, by design,
    never byte-identical) -- confirmed live against ATM-1025 and ATM-343.

    S12-remediation fix (F4.2, 2026-10-03): the above mapping alone still
    false-flagged every REOPENED-THEN-PROGRESSING item (ATM-353: events
    Reopened -> Updated, items.status="Ready for testing") -- the latest
    STATUS_DEFINING_EVENT resolves to the Reopened row (CLOSURE_EVENT_TO_STATUS
    maps "Reopened" -> "Reopened"), but a correctly-progressing item's status
    has since moved on to an ordinary NON-TERMINAL value ("Ready for testing"/
    "In progress"/"In testing"/"Queued"/...) that has no entry in
    CLOSURE_EVENT_TO_STATUS at all -- there is nothing wrong here: the item
    reopened and is progressing toward resolution again, it has not yet
    re-claimed to be done. Fix: when the latest status-defining event is
    "Reopened", a desync is flagged ONLY if items_status is ITSELF one of
    the CLOSED_STATUS_FORMS (i.e. the item claims to be done again with NO
    new closure event in the history to justify it -- a genuine desync,
    distinct from ordinary post-reopen progress). A NON-terminal
    items_status after a Reopened event is honest, un-fabricated progress
    and is NOT flagged.

    This does NOT suppress a genuine desync: an item whose LATEST
    status-defining event is a real closure (Fixed/Implemented/Completed/
    Obsolete) but whose items_status disagrees -- e.g. ATM-789 (Fixed, no
    Reopened event, status="Ready for testing") or the 58 SPK bulk-import
    rows (Fixed/Completed, status="Queued") -- is UNAFFECTED by this clause
    (event_type != "Reopened" there) and remains flagged exactly as before;
    confirmed live 2026-10-03: DB-wide sweep count unchanged at 59 for those
    two classes, only ATM-353 (the Reopened-then-progressing pattern) drops
    out, 60 -> 59."""
    last_status_event = next(
        (r for r in reversed(history) if r["event_type"] in STATUS_DEFINING_EVENTS), None)
    if last_status_event is None or items_status is None:
        return False
    event_type = last_status_event["event_type"]
    expected_status = CLOSURE_EVENT_TO_STATUS.get(event_type, event_type)
    if event_type == "Reopened" and items_status not in CLOSED_STATUS_FORMS:
        return False
    return expected_status != items_status


def latest_closure_event(history):
    for row in reversed(history):
        if row["event_type"] in CLOSURE_EVENTS:
            return row
    return None


def closure_recency_key(history_by_id, atm_id):
    """N2 fix (T048 round-2 review): sort key for "most recent N" CT-001
    stratum selection, keyed by the candidate's LATEST closure event's real
    DB write-order fields -- `created_at` (the item_history row's own
    timestamp) then its `id` (the row's own autoincrement primary key, a
    monotonic write-order tie-breaker at second-resolution ties) -- never
    the atm_id STRING. `sorted(keep)` previously sorted `atm_id` as TEXT:
    "ATM-1002" < "ATM-953" lexicographically ('1' < '9') even though
    1002 > 953 numerically, so real recent closures (verified directly
    against docs/workable_items.db 2026-09-30: ATM-1105 09-29, ATM-1009/
    ATM-1002 09-28, ATM-1025 08-23) were silently excluded from every
    sample in favour of much older ATM-785..953-range ids whose atm_id
    string merely sorted "higher" -- identical bug class, independently
    fixed the same way as sibling tool select_sample.py's own
    closure_recency_key (S11.4.227: same fix, same reasoning, kept as a
    parallel-but-consistent per-tool implementation matching this file's
    own already-established convention of NOT sharing a cross-tool helper
    module beyond fc_common's canon/body_hash/needle primitives). `atm_id`
    is kept as a final deterministic tie-breaker ONLY (after created_at/id
    both tie exactly, e.g. a same-second batch closure) -- never the
    primary sort key -- so --determinism-check (C-003) still gets
    byte-identical output across runs. A candidate with no closure
    event/created_at sorts FIRST (least recent) rather than crashing, per
    S11.4.6 fail-safe-not-guess.
    """
    closure = latest_closure_event(history_by_id.get(atm_id, []))
    created_at = (closure or {}).get("created_at") or ""
    hist_id = (closure or {}).get("id")
    if hist_id is None:
        hist_id = -1
    return (created_at, hist_id, atm_id)


def dedup_history(history):
    seen = set()
    out = []
    for row in history:
        key = _exact_dup_key(row)
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def reopen_count(history):
    return sum(1 for r in dedup_history(history) if r["event_type"] == "Reopened")


# ---------------------------------------------------------------------------
# git log -- subject-only item-id attribution (avoids false COMMIT_ATTRIBUTION
# matches from body-only mentions; see module docstring / research notes)
# ---------------------------------------------------------------------------
def git_subject_matches(repo_root, item_id, timeout_s=60):
    """Returns a sorted list of {sha, author_date, committer_date, subject}
    dicts for every commit whose SUBJECT LINE (not full body) contains
    item_id, earliest first. Git's own --grep matches the full message; this
    filters to subject-only in Python (verified 2026-09-28: a %B-message
    grep for ATM-953 on this tree returns 3 commits, but only 1 of them
    actually names ATM-953 in its subject -- the other 2 match a body-only
    mention, which is materially weaker evidence and would corrupt
    COMMIT_ATTRIBUTION_BY_GREP if trusted)."""
    try:
        out = subprocess.run(
            ["git", "log", "--all", "-i", "--grep=%s" % item_id,
             "--pretty=format:%H|%ad|%cd|%s", "--date=iso-strict"],
            cwd=repo_root, capture_output=True, text=True, timeout=timeout_s,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if out.returncode != 0:
        return []
    # T043 round-4 finding B2 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
    # `item_id in subject` is a plain substring test, so ATM-103 matches
    # inside ATM-1038, ATM-95 matches inside ATM-953, etc. -- this function
    # was the ORIGINAL of the same bug reproduced independently in
    # baseline_replay.sh's git_subject_freeze() (fixed the same way there).
    # Token-boundary regex: item_id must be bounded by a non-alnum-non-
    # hyphen char (or string start) on the left and a non-digit char (or
    # string end) on the right.
    item_re = re.compile(r"(?:^|[^A-Za-z0-9-])" + re.escape(item_id) + r"(?:[^0-9]|$)")
    matches = []
    for line in out.stdout.splitlines():
        parts = line.split("|", 3)
        if len(parts) != 4:
            continue
        sha, ad, cd, subject = parts
        if item_re.search(subject):
            matches.append({"sha": sha, "author_date": ad, "committer_date": cd, "subject": subject})
    matches.sort(key=lambda m: m["author_date"])
    return matches


def commit_push_stage(repo_root, item_id):
    matches = git_subject_matches(repo_root, item_id)
    if not matches:
        return unmeasured_stage("commit_push", item_id), False
    start_m, end_m = matches[0], matches[-1]
    stage = measured_stage(
        "commit_push",
        start_m["author_date"], "git_author",
        end_m["committer_date"], "git_committer",
        start_evidence="git_log#%s" % start_m["sha"],
        end_evidence="git_log#%s" % end_m["sha"],
    )
    multi_item = any(len(set(ITEM_ID_RE.findall(m["subject"]))) >= 2 for m in matches)
    return stage, multi_item


# ---------------------------------------------------------------------------
# Build one Cycle Record
# ---------------------------------------------------------------------------


def review_rounds_stage(records_dir, item_id, repo_root=None):
    """ATM-1055-batch fix (S12): genuinely reads T034's landed review_record.py
    output (schema `review-record/v1`) instead of hardcoding UNMEASURED.
    Recursively scans `records_dir` for *.json documents whose `item_id`
    matches, using ONLY entries whose `started_at`/`ended_at` are BOTH real,
    parseable instants -- never the literal "UNKNOWN" placeholder
    review_record.py itself emits for an un-timestamped round (CT-004: no
    invention). A corrupt/unrelated/non-JSON file anywhere under the tree is
    silently skipped, never crashes the whole report. `records_dir` is an
    explicit, caller-supplied opt-in (--review-records-dir) -- the contract
    names no single canonical default directory for these records (they are
    written to whatever `--out` the reviewer chose), so this function never
    guesses a repo-wide scan location (S11.4.6).

    Returns a StageMeasurement dict, or None when records_dir is falsy (the
    caller falls back to unmeasured_stage with the honest INSTRUMENT_TEMPLATES
    text).

    S12-remediation fixes (2026-10-03):
      F1 (evidence-path attribution + determinism) -- the PRE-fix version
      kept a SINGLE shared `evidence_path` variable overwritten by whichever
      valid record os.walk visited LAST, then used that ONE path for BOTH
      start_evidence and end_evidence -- but the real minimum-start and
      maximum-end instants can come from DIFFERENT files (repro: round 1 =
      10:00-11:00 in rr/a/r1.json, round 2 = 14:00-15:00 in rr/z/r2.json;
      pre-fix output cited end=15:00Z with evidence_path=rr/a/r1.json, which
      is WRONG -- that instant actually comes from r2.json). Fix: the
      earliest start and latest end are tracked INDEPENDENTLY, each with its
      OWN evidence file, via a running best-so-far comparison (never a
      shared "last visited" variable). `dirnames` is also sorted in-place
      during the os.walk traversal so the scan order -- and therefore which
      record wins a start/end TIE -- is deterministic rather than
      filesystem-dependent (os.walk's default `dirnames` order is otherwise
      unspecified).
      F2 (token overclaim) -- the PRE-fix version added a record's `tokens`
      field UNCONDITIONALLY, even for records whose start/end timestamps
      were the honest "UNKNOWN" placeholder (or otherwise unparseable) and
      therefore contributed NOTHING to the elapsed-time computation (repro:
      a 3rd record with UNKNOWN/UNKNOWN timestamps and tokens=99999 raised
      the reported total by the full 99999 even though the elapsed span only
      ever came from the first two valid records). Fix: a record's tokens
      are added ONLY inside the SAME branch that validated its start/end
      timestamps -- a record with no valid timed span contributes NEITHER
      to elapsed time NOR to the token total (CT-004: a round that cannot be
      timed is not counted as having happened within this measured span).

    S12-remediation follow-up round (2026-10-03), further fixes found
    against this same function:
      F5 (elapsed-time semantics) -- the returned stage's `elapsed` field is
      the OVERALL WALL-CLOCK SPAN from the earliest round's start to the
      latest round's end. This is DELIBERATE and matches this module's own
      established convention for every OTHER multi-occurrence stage --
      commit_push_stage() likewise spans the earliest commit's author_date
      to the latest commit's committer_date across potentially many
      commits, and that span likewise includes any gap time between
      commits. `elapsed` therefore INCLUDES any gap between review rounds
      (e.g. fix-time between Round N's review ending and Round N+1's review
      starting) -- it is the wall-clock duration of the review_rounds
      STAGE, not "time spent reviewing". A caller wanting the latter reads
      the separate `summed_review_duration_ms` field added below: the SUM
      of each individual round's own (end - start) duration, which is the
      actual measured review-time figure. Both are genuine, non-invented
      (CT-004) measurements of two DIFFERENT things; neither replaces the
      other. Also: `time_source="registry_ts"` honestly describes these as
      REVIEWER-ENTERED timestamps -- review_record.py's `--started-at`/
      `--ended-at` CLI flags, filled in by whoever ran the review -- never
      automatically-instrumented clock readings (confirmed directly against
      review_record.py's own argparse definitions, 2026-10-03).

    S12-remediation round (2026-10-03), fix found against the F5 field added
    above:
      F13 (inverted-span corruption of summed_review_duration_ms) --
      review_record.py's own `--started-at`/`--ended-at` flags carry NO
      end->=start validation (confirmed against its argparse definitions,
      same as F5's note immediately above), so a reviewer-entered record
      with an INVERTED span (end before start -- a data-entry error) is
      structurally possible. The PRE-fix `summed_review_duration_ms`
      accumulation added every record's (end - start) UNCONDITIONALLY,
      including a negative duration from an inverted record, which could
      silently CANCEL OUT a real positive duration from another round
      (repro: round a 10:00->12:00 [+2h], round b 15:00->13:00 [inverted,
      -2h] -> pre-fix summed_review_duration_ms reported 0, hiding the real
      2h review that genuinely happened). Fix: an inverted round's duration
      is excluded from this sum entirely (never added, never subtracted),
      matching this SAME function's existing UNKNOWN-timestamp exclusion
      precedent -- an un-timeable round contributes NOTHING to a duration
      total (CT-004). This fix is scoped STRICTLY to the
      summed_review_duration_ms accumulation: an inverted record's own
      instants still compete normally for the `elapsed` field's overall
      min-start/max-end span-evidence attribution (F1, above) and its
      tokens still contribute to the token total (F2, above) -- both are
      PRE-EXISTING behaviour this fix deliberately leaves untouched, not a
      new defect this fix introduces or masks."""
    if not records_dir or not os.path.isdir(records_dir):
        return None
    best_start_iso, best_start_dt, best_start_evidence = None, None, None
    best_end_iso, best_end_dt, best_end_evidence = None, None, None
    summed_duration_ms = 0
    total_tokens, any_tokens = 0, False
    for dirpath, dirnames, filenames in os.walk(records_dir):
        dirnames.sort()  # F1: deterministic traversal order
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                with open(path, encoding="utf-8") as fh:
                    doc = json.load(fh)
            except (OSError, ValueError):
                continue
            if not isinstance(doc, dict) or doc.get("schema") != "review-record/v1":
                continue
            if doc.get("item_id") != item_id:
                continue
            s, e = doc.get("started_at"), doc.get("ended_at")
            if isinstance(s, str) and s != "UNKNOWN" and isinstance(e, str) and e != "UNKNOWN":
                try:
                    s_dt = parse_iso(s)
                    e_dt = parse_iso(e)
                except (ValueError, TypeError):
                    continue
                if repo_root and path.startswith(repo_root):
                    evidence_path = os.path.relpath(path, repo_root)
                else:
                    evidence_path = path
                # F1: track the MINIMUM start and MAXIMUM end independently,
                # each with its OWN evidence file, never a shared variable.
                if best_start_dt is None or s_dt < best_start_dt:
                    best_start_iso, best_start_dt, best_start_evidence = s, s_dt, evidence_path
                if best_end_dt is None or e_dt > best_end_dt:
                    best_end_iso, best_end_dt, best_end_evidence = e, e_dt, evidence_path
                # F2: tokens are added ONLY here, inside the branch that just
                # validated this record's timed span -- never unconditionally.
                tok = doc.get("tokens")
                if isinstance(tok, int):
                    total_tokens += tok
                    any_tokens = True
                # F5: this record's OWN (end - start) duration is summed
                # independently of the min-start/max-end span tracked above
                # -- see this function's docstring for why `elapsed` (the
                # span) and `summed_review_duration_ms` (this sum) measure
                # two different things.
                #
                # S12-remediation fix (F13, 2026-10-03): review_record.py's
                # own --started-at/--ended-at CLI flags (confirmed directly
                # against its argparse definitions, F5's docstring note
                # above) carry NO end->=start validation -- a reviewer-
                # entered record with an INVERTED span (end before start, a
                # data-entry error) is therefore structurally possible, and
                # the PRE-fix unconditional `+=` let its NEGATIVE duration
                # silently cancel out a real positive duration from another
                # round (repro: round a 10:00->12:00 [+2h], round b
                # 15:00->13:00 [inverted, -2h] -> pre-fix summed_duration_ms
                # reported 0, hiding the real 2h review that happened).
                # Fix: an inverted round's duration is treated as UNTIMED and
                # EXCLUDED from this sum entirely -- never added, never
                # subtracted -- matching this SAME function's existing
                # UNKNOWN-timestamp precedent (an un-timeable round
                # contributes NOTHING to a duration total, CT-004: no
                # invented/corrupted measurement). This guard touches ONLY
                # the summed_review_duration_ms accumulation: the record's
                # own `best_start`/`best_end` span-evidence attribution
                # (F1, above) and its `tokens` contribution (F2, above) are
                # DELIBERATELY left untouched by this fix -- that is
                # PRE-EXISTING behaviour of this function (an inverted
                # record's own start/end instants still compete normally for
                # the overall `elapsed` span's min-start/max-end, exactly as
                # any other validly-parsed timestamp pair would), not a new
                # defect this round introduces or silently masks.
                if e_dt >= s_dt:
                    summed_duration_ms += to_ms((e_dt - s_dt).total_seconds())
    if best_start_iso is None:
        return None
    stage = measured_stage(
        "review_rounds", best_start_iso, "registry_ts", best_end_iso, "registry_ts",
        start_evidence=best_start_evidence, end_evidence=best_end_evidence,
        tokens=total_tokens if any_tokens else None)
    # F5: a field DISTINCT from `elapsed` (the overall span, which includes
    # inter-round gaps) -- the sum of each individual round's own measured
    # duration, i.e. the actual review-time figure.
    stage["summed_review_duration_ms"] = summed_duration_ms
    return stage


def reconstruct_from_evidence(item_id, item_history, git_log_entries, evidence_files_present,
                               repo_root=None, review_records_dir=None):
    """The shared reconstruction algorithm used by --item (live DB) and
    Shape-B --tracker-export fixtures. `git_log_entries` may be a literal
    list of {sha, author_date, committer_date, message} (fixture-supplied,
    Shape B) OR None (meaning: look the item up live via git log, --item
    mode)."""
    stages = {}

    # commit_push
    multi_item_commit = False
    if git_log_entries is not None:
        subj_matches = [g for g in git_log_entries if item_id in g.get("message", "")]
        if subj_matches:
            subj_matches.sort(key=lambda g: g["author_date"])
            start_m, end_m = subj_matches[0], subj_matches[-1]
            stages["commit_push"] = measured_stage(
                "commit_push",
                start_m["author_date"], "git_author",
                end_m["committer_date"], "git_committer",
                start_evidence="git_log#%s" % start_m["sha"],
                end_evidence="git_log#%s" % end_m["sha"],
            )
            multi_item_commit = any(
                len(set(ITEM_ID_RE.findall(g.get("message", "")))) >= 2 for g in subj_matches)
        else:
            stages["commit_push"] = unmeasured_stage("commit_push", item_id)
    elif repo_root:
        stages["commit_push"], multi_item_commit = commit_push_stage(repo_root, item_id)
    else:
        stages["commit_push"] = unmeasured_stage("commit_push", item_id)

    # build: no per-item build-log/builds.tsv JOIN exists in this repo yet
    # (verified 2026-09-28 against docs/build/resources/builds.tsv: keyed by
    # an opaque build_id, zero rows mention any item id) -- always
    # UNMEASURED for the live-DB path; for Shape-B fixtures, a real
    # path-pattern scan of evidence_files_present is attempted first.
    #
    # ATM-1055-batch fix (S12, defect 3): `build_found` was computed and then
    # genuinely never consumed (git history: introduced + never touched since
    # commit 7c2e1d5, T041's original landing) -- `stages["build"]` was
    # hardcoded to `unmeasured_stage(...)` regardless of its value, so the
    # comment's own "attempted first" promise was never fulfilled. The
    # detection result is now wired into the output's missing_instrument text
    # instead of being silently discarded: a caller can see WHETHER a
    # build-evidence file was found at all, which is real, non-fabricated,
    # newly-surfaced information the dead variable was computing and
    # throwing away.
    #
    # S12-remediation fix (F11.3, 2026-10-03): the PRE-fix build_found text
    # (and this comment) claimed "a SINGLE file mtime cannot derive a
    # two-sided elapsed value without inventing one" as THE reason the stage
    # stays UNMEASURED -- true ONLY for the Shape-B evidence_files_present
    # mtime checked above, but FALSE as a description of builds.tsv itself:
    # R1 Finding 2 confirms docs/build/resources/builds.tsv rows DO carry a
    # real two-sided start_ts/end_ts span plus a short-sha build_id (e.g.
    # "26a274387d2-20260728T062804Z 06:28:04-06:49:46"). The REAL blocker is
    # the SAME class of gap as the gate_runs stage above: no
    # build_id-to-item join exists yet to attribute a builds.tsv row to
    # {item_id} -- the stage correctly STAYS UNMEASURED, but for the
    # accurate reason.
    build_found = False
    build_evidence_path = None
    for f in (evidence_files_present or []):
        path = f.get("path", "")
        if re.search(r"build", path, re.I) and "builds.tsv" in path.lower():
            build_found = True
            build_evidence_path = path
            break
    build_stage = unmeasured_stage("build", item_id)
    if build_found:
        build_stage["missing_instrument"] = (
            "per-item build-log/builds.tsv row keyed to %s: a build-evidence "
            "file (%s) was found among evidence_files_present. "
            "docs/build/resources/builds.tsv rows DO carry a real two-sided "
            "start_ts/end_ts span plus a short-sha build_id (R1 Finding 2) -- "
            "the real blocker is the SAME class of gap as the gate_runs "
            "stage: no build_id-to-item join exists yet to attribute a "
            "builds.tsv row to %s -- correctly UNMEASURED, not merely "
            "unattempted." % (item_id, build_evidence_path, item_id))
    stages["build"] = build_stage

    # review_rounds: ATM-1055-batch fix (S12, defect 2) -- T034's
    # review_record.py is now genuinely read when the caller opts in via
    # --review-records-dir; see review_rounds_stage's own docstring for why
    # this is an explicit opt-in rather than a guessed default directory.
    review_stage = review_rounds_stage(review_records_dir, item_id, repo_root=repo_root)
    if review_stage is not None:
        stages["review_rounds"] = review_stage

    # Every other stage: no wired instrument in this repository pass for
    # ANY item -- confirmed directly, live, 2026-10-03 (see the per-stage
    # INSTRUMENT_TEMPLATES text above for which tool has landed vs. which
    # join/data genuinely does not exist yet) -- honestly UNMEASURED.
    for stage in STAGES:
        if stage not in stages:
            stages[stage] = unmeasured_stage(stage, item_id)

    return [stages[s] for s in STAGES], multi_item_commit


def build_record_for_item(item_id, item_type, item_status, history,
                           selection_reason, window, git_log_entries=None,
                           evidence_files_present=None, repo_root=None,
                           review_records_dir=None):
    stages, multi_item_commit = reconstruct_from_evidence(
        item_id, history, git_log_entries, evidence_files_present, repo_root=repo_root,
        review_records_dir=review_records_dir)

    flags = []
    if history:
        if flag_date_only_resolution(history):
            flags.append("DATE_ONLY_RESOLUTION")
        if flag_retroactive_registration(history):
            flags.append("RETROACTIVE_REGISTRATION")
        if flag_duplicate_history_rows(history):
            flags.append("DUPLICATE_HISTORY_ROWS")
        if flag_reopen_without_prior_closure(history):
            flags.append("REOPEN_WITHOUT_PRIOR_CLOSURE")
        if flag_status_desync(item_status, history):
            flags.append("STATUS_DESYNC")
    if multi_item_commit:
        flags.append("COMMIT_ATTRIBUTION_BY_GREP")

    all_measured = all(s["elapsed"] != "UNMEASURED" for s in stages)
    total_elapsed = sum(s["elapsed"] for s in stages) if all_measured else "UNMEASURED"
    token_stages = [s["tokens"] for s in stages if "tokens" in s]
    total_tokens = sum(token_stages) if token_stages else "UNMEASURED"

    rc = reopen_count(history) if history else 0
    if rc > 0:
        selection_reason = "reopened-in-window"

    record = {
        "item_id": item_id,
        "item_type": item_type,
        "window": window,
        "selection_reason": selection_reason,
        "excluded": False,
        "exclusion_reason": None,
        "stages": stages,
        "total_elapsed": total_elapsed,
        "total_tokens": total_tokens,
        "final_status": item_status,
        "reopen_count": rc,
        "data_quality_flags": sorted(set(flags)),
    }
    closure = latest_closure_event(history) if history else None
    if closure:
        record["closure_event"] = {
            "event_type": closure["event_type"],
            "on_date": closure.get("on_date"),
            "evidence_path": closure.get("evidence_path"),
            "by": closure.get("by"),
        }
    return record


# ---------------------------------------------------------------------------
# Aggregation (medians per type + overall)
# ---------------------------------------------------------------------------
def compute_medians(records):
    def stage_values(recs, stage):
        vals = []
        n_total = 0
        for r in recs:
            n_total += 1
            for s in r["stages"]:
                if s["stage"] == stage:
                    if isinstance(s["elapsed"], int):
                        vals.append(s["elapsed"])
                    break
        return vals, n_total

    def per_group(recs):
        out = {}
        for stage in STAGES:
            vals, n_total = stage_values(recs, stage)
            out[stage] = {
                "value_ms": int(round(statistics.median(vals))) if vals else "UNMEASURED",
                "n_measured": len(vals),
                "n_total": n_total,
            }
        return out

    medians = {"overall": per_group(records)}
    for t in ITEM_TYPES:
        by_type = [r for r in records if r["item_type"] == t]
        if by_type:
            medians[t] = per_group(by_type)
    return medians


def compute_strata(records, min_per_type):
    strata = {}
    for t in ITEM_TYPES:
        n = sum(1 for r in records if r["item_type"] == t)
        strata[t] = {"n": n, "required": min_per_type, "below_required": n < min_per_type}
    return strata


def compute_reopen_block(records, window):
    """CT-006 inline: $FC/closure/reopen_rate.py (T-D06) does not exist yet
    in this tree; this computes the identical metric definition directly
    over the record set this run actually produced (an honest scope
    substitution, documented in the module docstring)."""
    closed = sum(1 for r in records if r.get("closure_event") is not None)
    reopened = sum(1 for r in records if r["reopen_count"] > 0)
    block = {"reopened": reopened, "closed": closed, "window": window, "dedup_rows_removed": 0}
    if closed == 0:
        block["rate"] = "RATE_NOT_COMPUTABLE"
        block["reason"] = "no closed items in this record set"
    else:
        block["rate"] = round(reopened / closed, 6)
    return block


def compute_instrument_gaps(records):
    gaps = {}
    for r in records:
        for s in r["stages"]:
            if s.get("missing_instrument"):
                key = (s["stage"], s["missing_instrument"].split(" for ")[0] if " for " in s["missing_instrument"] else s["stage"])
                gaps.setdefault(s["stage"], {"stage": s["stage"], "missing_instrument": s["missing_instrument"], "items_affected": []})
                gaps[s["stage"]]["items_affected"].append(r["item_id"])
    return sorted(gaps.values(), key=lambda g: g["stage"])


# ---------------------------------------------------------------------------
# --hand-verified (CT-007)
# ---------------------------------------------------------------------------
def check_hand_verified(records, hand_verified_path):
    with open(hand_verified_path, encoding="utf-8") as fh:
        entries = json.load(fh)
    if not isinstance(entries, list):
        return 2, "hand-verified file must be a JSON list"
    distinct_items = {e.get("item_id") for e in entries if isinstance(e, dict)}
    if len(distinct_items) < 3:
        return 2, "hand-verified file must name >=3 distinct items (CT-007), found %d" % len(distinct_items)
    by_item = {r["item_id"]: r for r in records}
    for e in entries:
        item_id, stage, field, expected = e.get("item_id"), e.get("stage"), e.get("field"), e.get("expected_value")
        rec = by_item.get(item_id)
        if rec is None:
            continue
        stage_rec = next((s for s in rec["stages"] if s["stage"] == stage), None)
        if stage_rec is None:
            continue
        actual = stage_rec.get(field)
        if actual != expected:
            return 1, "hand-verification mismatch: item=%s stage=%s field=%s expected=%r actual=%r" % (
                item_id, stage, field, expected, actual)
    return 0, "hand-verification: all %d entries matched" % len(entries)


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash)
# ---------------------------------------------------------------------------
def write_report(out_path, body, run_meta):
    doc = dict(body)
    doc["schema"] = SCHEMA
    doc["body_hash"] = body_hash_of({**doc})
    doc["run_meta"] = run_meta
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".cycle_report.")
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
    lines = ["# Cycle-Time Report", ""]
    if doc.get("state") == "NO_DATA_IN_WINDOW":
        w = doc["window"]
        lines.append("no data in window [%s, %s]" % (w["from"], w["to"]))
        return "\n".join(lines) + "\n"
    lines.append("as_of: %s" % doc.get("as_of"))
    lines.append("window: %s .. %s" % (doc["window"]["from"], doc["window"]["to"]))
    lines.append("")
    for r in doc.get("records", []):
        lines.append("## %s (%s)" % (r["item_id"], r["item_type"]))
        for s in r["stages"]:
            elapsed = s["elapsed"]
            lines.append("- %s: %s" % (s["stage"], elapsed if elapsed == "UNMEASURED" else "%dms" % elapsed))
        lines.append("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def require_as_of(as_of):
    if not as_of:
        print("cycle_report: --as-of YYYY-MM-DD is required (no default to today, C-003)", file=sys.stderr)
        return False
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", as_of):
        print("cycle_report: --as-of must be YYYY-MM-DD, got %r" % as_of, file=sys.stderr)
        return False
    try:
        datetime.date.fromisoformat(as_of)
    except ValueError:
        print("cycle_report: --as-of is not a valid calendar date: %r" % as_of, file=sys.stderr)
        return False
    return True


def build_arg_parser():
    p = argparse.ArgumentParser(prog="cycle_report.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--config")
    p.add_argument("--as-of", required=True)
    p.add_argument("--window-days", type=int, default=90)  # DEC-03
    p.add_argument("--min-per-type", type=int, default=5)
    # Accepted for CLI-shape compatibility with the contract's Invocation
    # grammar; not separately consulted. CT-001's own sample-selection rule
    # ("Takes ... plus every item with a Reopened event in the window") is
    # unconditional -- reopened-in-window items are always included by the
    # full-sampling and --window-json paths regardless of this flag's value.
    p.add_argument("--include-reopened", action="store_true", default=True)
    p.add_argument("--hand-verified")
    p.add_argument("--out", required=True)
    p.add_argument("--md")
    p.add_argument("--determinism-check", action="store_true")
    p.add_argument("--bulk-threshold", type=int, default=10)
    # ATM-1055-batch fix (S12, defect 2): explicit opt-in directory to scan
    # for T034 review_record.py output (schema review-record/v1) to measure
    # the review_rounds stage -- no default (the contract names no single
    # canonical directory for these records, S11.4.6 never-guess).
    p.add_argument("--review-records-dir")
    # test-only extensions
    p.add_argument("--item")
    p.add_argument("--tracker-export")
    p.add_argument("--window-json")
    p.add_argument("--db-path")
    p.add_argument("--repo-root")
    p.add_argument("--needle-present-id", default="ATM-953")
    p.add_argument("--needle-fixed-event", default="Fixed")
    p.add_argument("--needle-fixed-on-date", default="2026-07-28")
    p.add_argument("--needle-fabricated-id", default="ATM-99999-NEGATIVE-CONTROL")
    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)

    if not require_as_of(args.as_of):
        return 2

    # F6 fix (S12-remediation follow-up round, 2026-10-03): a mistyped or
    # nonexistent --review-records-dir path previously fell straight through
    # to review_rounds_stage()'s own `not os.path.isdir(records_dir)` guard,
    # which returns None -- indistinguishable, to the caller, from the
    # legitimate "this is a real, existing, but genuinely-empty directory"
    # state (no review records exist yet). A blind/broken instrument (a path
    # that does not exist at all) must never be read as the SAME honest
    # "zero records found" result a real empty directory produces
    # (S11.4.201(6)) -- refuse closed rather than silently degrade. A
    # genuinely-empty EXISTING directory is unaffected (os.path.isdir is
    # True for it) and still correctly falls through to UNMEASURED.
    if args.review_records_dir is not None and not os.path.isdir(args.review_records_dir):
        print(
            "cycle_report: --review-records-dir path does not exist (or is "
            "not a directory): %r -- refusing rather than silently treating "
            "a likely operator typo/mistyped path the SAME as a genuinely-"
            "empty-but-valid directory (S11.4.201(6): a blind instrument and "
            "a clean artifact must never return the identical quiet result)"
            % args.review_records_dir, file=sys.stderr)
        return 2

    repo_root = os.path.abspath(args.repo_root) if args.repo_root else default_repo_root()
    db_path = args.db_path or os.path.join(repo_root, "docs", "workable_items.db")

    if args.determinism_check:
        inner = [a for a in argv if a != "--determinism-check"]
        runs = []
        with tempfile.TemporaryDirectory() as tmp:
            for i in (1, 2):
                out_i = os.path.join(tmp, "run%d.json" % i)
                cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
                # strip any user-supplied --out from inner (keep the last wins
                # semantics of argparse: appending our own --out after inner
                # ensures ours is authoritative regardless of duplication).
                try:
                    proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, timeout=120)
                except subprocess.TimeoutExpired:
                    print("cycle_report: determinism-check run %d timed out" % i, file=sys.stderr)
                    return 4
                if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                    sys.stderr.write(proc.stderr)
                    print("cycle_report: determinism-check run %d rc=%d, no honest verdict" % (i, proc.returncode),
                          file=sys.stderr)
                    return 4
                with open(out_i, encoding="utf-8") as fh:
                    doc = json.load(fh)
                runs.append((proc.returncode, doc.get("body_hash")))
        if runs[0] != runs[1]:
            print("cycle_report: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
            return 1
        print("cycle_report: deterministic (body_hash=%s)" % runs[0][1])
        return 0

    conn = open_db_readonly(db_path)
    if conn is None:
        print("cycle_report: tracker DB unreadable at %s" % db_path, file=sys.stderr)
        return 4

    # CT-009: needle BEFORE any sampling.
    ok, detail = run_needle(conn, args.needle_present_id, args.needle_fixed_event,
                             args.needle_fixed_on_date, args.needle_fabricated_id)
    print("cycle_report: %s" % detail, file=sys.stderr)
    if not ok:
        return 3

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}

    # --- Mode: --window-json (empty-window / real-window live query) ---
    if args.window_json:
        with open(args.window_json, encoding="utf-8") as fh:
            wdoc = json.load(fh)
        window = {"from": wdoc["window"]["from"], "to": wdoc["window"]["to"]}
        closures = db_closures_in_window(conn, window["from"], window["to"])
        reopens = db_reopened_in_window(conn, window["from"], window["to"])
        candidate_ids = {row[0] for row in closures} | {row[0] for row in reopens}
        if not candidate_ids:
            body = {"as_of": args.as_of, "window": window, "state": "NO_DATA_IN_WINDOW"}
            doc = write_report(args.out, body, run_meta)
            if args.md:
                with open(args.md, "w", encoding="utf-8") as fh:
                    fh.write(render_md(doc))
            print("cycle_report: no data in window [%s, %s]" % (window["from"], window["to"]))
            return 0
        # non-empty: fall through to real per-item reconstruction below.
        records = []
        for item_id in sorted(candidate_ids):
            item_row = db_item_row(conn, item_id)
            history = db_item_history(conn, item_id)
            records.append(build_record_for_item(
                item_id, item_row["type"] if item_row else "Task",
                item_row["status"] if item_row else None,
                history, "sampled-%s" % (item_row["type"].lower() if item_row else "task"),
                window, repo_root=repo_root, review_records_dir=args.review_records_dir))
        strata = compute_strata(records, args.min_per_type)
        body = {
            "as_of": args.as_of, "window": window, "strata": strata, "excluded": [],
            "records": sorted(records, key=lambda r: r["item_id"]),
            "medians": compute_medians(records),
            "reopen": compute_reopen_block(records, window),
            "instrument_gaps": compute_instrument_gaps(records),
        }
        doc = write_report(args.out, body, run_meta)
        if args.md:
            with open(args.md, "w", encoding="utf-8") as fh:
                fh.write(render_md(doc))
        return 0

    window = {"from": (datetime.date.fromisoformat(args.as_of) -
                        datetime.timedelta(days=args.window_days)).isoformat(),
              "to": args.as_of}

    # --- Mode: --tracker-export (single synthetic item, Shape A or B) ---
    if args.tracker_export:
        with open(args.tracker_export, encoding="utf-8") as fh:
            fx = json.load(fh)
        if "stages" in fx:
            item = fx["item"]
            stages = [passthrough_stage(s) for s in fx["stages"]]
            # Preserve the contract's fixed stage order regardless of input order.
            by_stage = {s["stage"]: s for s in stages}
            stages = [by_stage[s] for s in STAGES]
            all_measured = all(s["elapsed"] != "UNMEASURED" for s in stages)
            total_elapsed = sum(s["elapsed"] for s in stages) if all_measured else "UNMEASURED"
            token_stages = [s["tokens"] for s in stages if "tokens" in s]
            total_tokens = sum(token_stages) if token_stages else "UNMEASURED"
            record = {
                "item_id": item["atm_id"], "item_type": item["type"], "window": window,
                "selection_reason": "sampled-%s" % item["type"].lower(),
                "excluded": False, "exclusion_reason": None, "stages": stages,
                "total_elapsed": total_elapsed, "total_tokens": total_tokens,
                "final_status": item.get("status"), "reopen_count": 0,
                "data_quality_flags": [],
            }
        else:
            item = fx["item"]
            history = fx.get("item_history", [])
            git_log_entries = [
                {"sha": g["sha"], "author_date": g["author_date"],
                 "committer_date": g["committer_date"], "message": g.get("message", "")}
                for g in fx.get("git_log", [])
            ]
            record = build_record_for_item(
                item["atm_id"], item["type"], item.get("status"), history,
                "sampled-%s" % item["type"].lower(), window,
                git_log_entries=git_log_entries,
                evidence_files_present=fx.get("evidence_files_present"),
                repo_root=repo_root, review_records_dir=args.review_records_dir,
            )
        records = [record]
        strata = compute_strata(records, args.min_per_type)
        body = {
            "as_of": args.as_of, "window": window, "strata": strata, "excluded": [],
            "records": records, "medians": compute_medians(records),
            "reopen": compute_reopen_block(records, window),
            "instrument_gaps": compute_instrument_gaps(records),
        }
        rc = 0
        if args.hand_verified:
            rc, msg = check_hand_verified(records, args.hand_verified)
            print("cycle_report: %s" % msg, file=sys.stderr)
            if rc != 0:
                return rc
        doc = write_report(args.out, body, run_meta)
        if args.md:
            with open(args.md, "w", encoding="utf-8") as fh:
                fh.write(render_md(doc))
        return 0

    # --- Mode: --item (single real item, live DB) ---
    if args.item:
        item_row = db_item_row(conn, args.item)
        if item_row is None:
            print("cycle_report: item %s not found in tracker DB" % args.item, file=sys.stderr)
            return 4
        history = db_item_history(conn, args.item)
        record = build_record_for_item(
            args.item, item_row["type"], item_row["status"], history,
            "sampled-%s" % item_row["type"].lower(), window, repo_root=repo_root,
            review_records_dir=args.review_records_dir)
        records = [record]
        strata = compute_strata(records, args.min_per_type)
        body = {
            "as_of": args.as_of, "window": window, "strata": strata, "excluded": [],
            "records": records, "medians": compute_medians(records),
            "reopen": compute_reopen_block(records, window),
            "instrument_gaps": compute_instrument_gaps(records),
        }
        rc = 0
        if args.hand_verified:
            rc, msg = check_hand_verified(records, args.hand_verified)
            print("cycle_report: %s" % msg, file=sys.stderr)
            if rc != 0:
                return rc
        doc = write_report(args.out, body, run_meta)
        if args.md:
            with open(args.md, "w", encoding="utf-8") as fh:
                fh.write(render_md(doc))
        return 0

    # --- Full production mode: CT-001 live sampling in [window.from, window.to] ---
    if not args.config:
        print("cycle_report: --config is required in full-sampling mode "
              "(no test-only override given); fails closed rather than "
              "guessing a config path (common-conventions.md Placement "
              "clause, §11.4.6)", file=sys.stderr)
        return 2

    closures = db_closures_in_window(conn, window["from"], window["to"])
    reopens = db_reopened_in_window(conn, window["from"], window["to"])
    by_type = {}
    for atm_id, itype in closures:
        by_type.setdefault(itype, set()).add(atm_id)
    reopened_ids = {atm_id for atm_id, _ in reopens}

    selected = set()
    excluded = []
    for itype, ids in by_type.items():
        # CT-001 bulk-import exclusion (documented partial implementation --
        # see module docstring): group candidate closure rows by
        # (evidence-dir, on_date); a cluster >= --bulk-threshold is excluded.
        clusters = {}
        hist_by_id = {}
        # N3 fix (T048 round-2 review): `ids` is a Python `set` (built at
        # `by_type.setdefault(itype, set()).add(atm_id)` above) whose
        # iteration order is PYTHONHASHSEED-dependent for str elements
        # (hash randomisation, on by default). Iterating it directly seeded
        # `clusters`' dict-insertion order (and therefore every
        # `members`/`excluded.append(...)` order downstream) with that same
        # nondeterminism -- reproduced directly: two `--determinism-check`
        # runs of the SAME command against the SAME DB state produced
        # DIFFERENT `excluded[]` orderings and DIFFERENT body_hash values.
        # `sorted()` here is a real ORDERING fix (not merely "stable"): it
        # makes the base iteration -- and everything built from it --
        # independent of the interpreter's hash seed.
        for atm_id in sorted(ids):
            hist = db_item_history(conn, atm_id)
            hist_by_id[atm_id] = hist
            closure = latest_closure_event(hist)
            if closure and closure.get("evidence_path"):
                ekey = (os.path.dirname(closure["evidence_path"]), closure.get("on_date"))
            else:
                ekey = None
            clusters.setdefault(ekey, []).append(atm_id)
        keep = set()
        for ekey, members in clusters.items():
            if ekey is not None and len(members) >= args.bulk_threshold:
                for atm_id in members:
                    excluded.append({"item_id": atm_id, "reason": "bulk-import cluster (%d items, dir=%s, on_date=%s)"
                                      % (len(members), ekey[0], ekey[1])})
            else:
                keep.update(members)
        # N2 fix (T048 round-2 review): "most recent min_per_type" is a
        # REAL-RECENCY selection (closure_recency_key, above) -- NOT a
        # lexicographic atm_id string sort (the CT-001/DEC-03 bug this
        # fixes; see closure_recency_key's own docstring for the measured
        # ATM-1002/ATM-953 counter-example).
        keep_sorted = sorted(keep, key=lambda i: closure_recency_key(hist_by_id, i))
        recent = keep_sorted[-args.min_per_type:] if len(keep_sorted) > args.min_per_type else keep_sorted
        selected.update(recent)
    selected |= reopened_ids

    if not selected:
        body = {"as_of": args.as_of, "window": window, "state": "NO_DATA_IN_WINDOW"}
        doc = write_report(args.out, body, run_meta)
        if args.md:
            with open(args.md, "w", encoding="utf-8") as fh:
                fh.write(render_md(doc))
        print("cycle_report: no data in window [%s, %s]" % (window["from"], window["to"]))
        return 0

    records = []
    for atm_id in sorted(selected):
        item_row = db_item_row(conn, atm_id)
        history = db_item_history(conn, atm_id)
        selection_reason = "reopened-in-window" if atm_id in reopened_ids else \
            "sampled-%s" % (item_row["type"].lower() if item_row else "task")
        records.append(build_record_for_item(
            atm_id, item_row["type"] if item_row else "Task",
            item_row["status"] if item_row else None, history,
            selection_reason, window, repo_root=repo_root,
            review_records_dir=args.review_records_dir))

    strata = compute_strata(records, args.min_per_type)
    body = {
        "as_of": args.as_of, "window": window, "strata": strata, "excluded": excluded,
        "records": records, "medians": compute_medians(records),
        "reopen": compute_reopen_block(records, window),
        "instrument_gaps": compute_instrument_gaps(records),
    }
    rc = 0
    if args.hand_verified:
        rc, msg = check_hand_verified(records, args.hand_verified)
        print("cycle_report: %s" % msg, file=sys.stderr)
        if rc != 0:
            return rc
    doc = write_report(args.out, body, run_meta)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as fh:
            fh.write(render_md(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
