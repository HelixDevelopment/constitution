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
        --out <report.json> [--md <report.md>] [--determinism-check]

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

# R1-style default instrument-name mapping (CT-002's default mapping) -- one
# template per stage, `{item_id}` filled in at use. The `build` stage's
# template is verified byte-for-byte against research: this repository's own
# docs/build/resources/builds.tsv is keyed by an opaque `build_id`
# (hash+timestamp), NOT by item id (confirmed 2026-09-28: zero rows mention
# any ATM-* id) -- there genuinely is no per-item build instrument yet, which
# is exactly the gap this template names.
INSTRUMENT_TEMPLATES = {
    "intake": "docs/requests/agent_registry.jsonl session-to-item mapping row for {item_id} (T-A06 intake phase, not yet wired)",
    "investigation": "docs/requests/agent_registry.jsonl session-to-item mapping row for {item_id} (T-A06 investigation phase, not yet wired)",
    "implementation": "transcript usage ingest output keyed to {item_id} (T-A06 session-to-item join, not yet wired)",
    "test_authoring": "transcript usage ingest output keyed to {item_id} (T-A06 test-authoring phase, not yet wired)",
    "gate_runs": "per-gate-run duration log keyed to candidate fingerprint for {item_id} (T-C0x gate timing, not yet wired)",
    "build": "per-item build-log/builds.tsv row keyed to {item_id} (R1's instrument table; contract CT-002 default mapping)",
    "review_rounds": "review-round record (T-A04) keyed to {item_id}",
    "fix_rounds": "fix-round record keyed to {item_id} (no per-item fix-round log wired yet)",
    "commit_push": "git log author/committer timestamp for a commit whose subject references {item_id}",
    "deployment": "docs/build/resources/builds.tsv deploy row keyed to {item_id} (T-A08 build/deploy/QA events, not yet wired)",
    "manual_qa_wait": "item_history/manual-qa sign-off event keyed to {item_id} (T-A08, not yet wired)",
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


def flag_status_desync(items_status, history):
    last_status_event = next(
        (r for r in reversed(history) if r["event_type"] in STATUS_DEFINING_EVENTS), None)
    if last_status_event is None or items_status is None:
        return False
    return last_status_event["event_type"] != items_status


def latest_closure_event(history):
    for row in reversed(history):
        if row["event_type"] in CLOSURE_EVENTS:
            return row
    return None


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


def reconstruct_from_evidence(item_id, item_history, git_log_entries, evidence_files_present, repo_root=None):
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

    # build: no per-item build-log/builds.tsv join exists in this repo yet
    # (verified 2026-09-28 against docs/build/resources/builds.tsv: keyed by
    # an opaque build_id, zero rows mention any item id) -- always
    # UNMEASURED for the live-DB path; for Shape-B fixtures, a real
    # path-pattern scan of evidence_files_present is attempted first.
    build_found = False
    for f in (evidence_files_present or []):
        path = f.get("path", "")
        if re.search(r"build", path, re.I) and "builds.tsv" in path.lower():
            build_found = True
            break
    stages["build"] = unmeasured_stage("build", item_id)

    # Every other stage: no wired instrument in this repository pass
    # (T-A04/T-A06/T-A08/T-C0x all not yet implemented) -- honestly
    # UNMEASURED. Documented per-stage in INSTRUMENT_TEMPLATES.
    for stage in STAGES:
        if stage not in stages:
            stages[stage] = unmeasured_stage(stage, item_id)

    return [stages[s] for s in STAGES], multi_item_commit


def build_record_for_item(item_id, item_type, item_status, history,
                           selection_reason, window, git_log_entries=None,
                           evidence_files_present=None, repo_root=None):
    stages, multi_item_commit = reconstruct_from_evidence(
        item_id, history, git_log_entries, evidence_files_present, repo_root=repo_root)

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
                window, repo_root=repo_root))
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
            "sampled-%s" % item_row["type"].lower(), window, repo_root=repo_root)
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
        for atm_id in ids:
            hist = db_item_history(conn, atm_id)
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
        recent = sorted(keep)[-args.min_per_type:] if len(keep) > args.min_per_type else sorted(keep)
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
            selection_reason, window, repo_root=repo_root))

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
