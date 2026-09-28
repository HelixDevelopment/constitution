#!/usr/bin/env python3
"""transcript_ingest.py — real Claude Code transcript -> usage-only telemetry
ingest (SpecKit-004 "fast-dev-cycles", User Story 1, T038; plan T-A06;
FR-013, FR-001, SC-005, SC-001; guarded by
constitution/scripts/fastcycle/tests/test_token_attribution_red.sh, T020).

=============================================================================
CREDENTIAL SAFETY (§11.4.10) — READ THIS BEFORE TOUCHING THIS FILE
=============================================================================
Real Claude Code transcripts carry full conversational message CONTENT
(`message["content"]`) alongside usage/token metadata. This module extracts
and persists ONLY usage counts, model identifiers, and structural ids
(session id, agent id, message id, timestamps) — it NEVER reads
`message["content"]` (or any nested field under it, e.g. a `tool_use`
block's `input.description`) into any variable, for any purpose, anywhere
in this file — not even to hash it, log it, or check its length. Grep this
file for the literal substring `"content"` before believing that claim; it
must never appear as a dict-key access on a `message` object.

The ONE place this module reads free text at all is `toolUseResult`
(present on the tool-RESULT `user` record that follows an Agent/Task
dispatch's `tool_use` block) — a SIBLING top-level key to `message`, not
nested under it, carrying dispatch bookkeeping (`agentId`, `description`,
`resolvedModel`, `outputFile`, ...) rather than conversational content. Even
there, this module extracts ONLY the narrow, regex-matched
`item=ATM-<digits>` (or the honest `item=?`) token from `description` — the
SAME `item=(ATM-[0-9]+|\\?)` convention `tokens/dispatch_stamp.sh` (T036)
already established on this SAME field — and NEVER persists the raw
`description` string itself.

=============================================================================
SCHEMA DECISION (documented per task instruction) — a NEW table, not new
columns on the EXISTING `usage_events` table, in the SAME db FILE
=============================================================================
plan.md T-A06 states this tool "writes into the EXISTING WS1 R0 telemetry
DB under docs/research/tokens/, not a new store" (tasks.md T038 repeats
this verbatim). The R0 prototype this extends,
`docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.py`,
already ships one table, `usage_events`, whose CLI (`ingest <flat.jsonl>`)
consumes a DIFFERENT, pre-flattened record shape a caller supplies directly
(`{ts, track, alias, model, input_tokens, ...}`, all four scalar identity
columns `NOT NULL`) — proven, by running it against every real-schema
fixture this task ships (captured in this task's evidence directory), to
REJECT a genuine Claude Code transcript outright (`ts` is missing at
transcript top level) and, on its own flat schema, to silently coerce an
ABSENT token-count field to `0` with no distinguishing signal (the exact
missing-vs-zero bluff property (c) below exists to close).

Given that:
  - `usage_events`'s `track`/`alias` columns are `NOT NULL` scalar identity
    fields a flat record supplies directly; a real transcript record has
    NEITHER field (track/alias are a DIFFERENT §11.4.182 label-derivation
    concern this task's own RED test never exercises) — forcing them would
    mean inventing values never asked for (§11.4.6) or widening the column
    to nullable and polluting `usage_events`' existing NOT-NULL semantics
    (which OTHER tooling, e.g. `usage_telemetry.py report --group-by
    track|alias`, already relies on);
  - `usage_events` has no column for `session_id`/`agent_id`/`item_id`/a
    missing-vs-measured flag/`missing_instrument` — all REQUIRED by this
    task's properties (c) and (d);
  - the tool being extended is explicit that "no tool retries [/writes] a
    struct it does not understand" and that additive migration (adding,
    never dropping/renaming — matching this project's own precedent of
    additive-only schema evolution, e.g. `docs/workable_items.db`'s
    `occurred_at` column addition) is the safe path;

this module creates a SECOND table, `transcript_usage_events`, in the SAME
db FILE (same `--db` path / same `DEFAULT_DB` default as
`usage_telemetry.py`'s own `DEFAULT_DB`) — additive at the FILE level (one
store, "not a new store"), never touching, dropping, renaming, or alling
NOT-NULL-incompatible data into the pre-existing `usage_events` table. This
keeps both tables' semantics internally consistent: `usage_events` remains
exactly what `usage_telemetry.py` already understands; `transcript_usage_events`
is the real-transcript-derived table this tool owns.

=============================================================================
IDEMPOTENCY / DEDUP KEY (informed by prior real-world evidence in this SAME
project)
=============================================================================
The sibling R0 investigation `ingest_claude_transcript.py` (captured
2026-07-08, same POC directory) found, from REAL captured transcripts, that
Claude Code streams MULTIPLE JSONL lines per logical assistant turn (one
per content block), each carrying an IDENTICAL cumulative `usage` block —
so a per-LINE dedup key (line number, or a per-line `uuid`) would count one
logical turn's tokens N times over. That script's own fix was to key on
`(sessionId, requestId)` instead of per-line identity; this module's own
fixtures (and this task's README provenance capture, 2026-09-28) show every
assistant record — even a usage-absent one — carrying a stable
`message["id"]` (e.g. `msg_fixture_t020_missing_a1`), which is this
project's OWN captured evidence of a message-level (not line-level, not
content-derived) identity a caller can dedup on. This module therefore
computes `row_hash` from `message["id"]` alone when present (matching the
sibling script's documented "cross-file idempotency" finding — the SAME
msg id, whichever file it is read from, hashes to the SAME row, so a
subagent+parent overlap or a second `ingest` run of the identical file
never double-counts), falling back to `(source_file, lineno, uuid)` only
for the (unobserved in this project's own captured schema) case of an
assistant record with no `message["id"]` at all. NEVER derived from
`message["content"]`, matching the credential-safety guarantee above.
`INSERT OR IGNORE` (matching `usage_telemetry.py`'s own convention exactly)
makes a second `ingest` of the identical input a true no-op.

=============================================================================
"copy-on-ingest" (tasks.md T038 / plan.md T-A06 work item (3)) — design
judgment call, documented per task instruction
=============================================================================
tasks.md T038's literal text lists "copy-on-ingest" among this tool's scope
("... session->agent->item keying; copy-on-ingest; writes into the
existing WS1 R0 telemetry DB ..."); plan.md T-A06 work item (3) glosses it
as "copy-on-ingest so rotation no longer loses the before-sample." Read
LITERALLY as "byte-copy the raw source transcript file somewhere for
safekeeping," this would directly conflict with this file's own
credential-safety mandate above — a raw transcript copy contains the exact
`message["content"]` this module is required to never persist (the
`credential_leak/session.jsonl` fixture's planted marker lives in exactly
such a raw copy). No fixture in this task's RED set tests a raw-copy
artefact; the RED test's own credential-safety assertion (Part E) scans
ONLY the produced `--db` file. Per this module's own credential-safety
mandate above (§11.4.10 — never persist message content, whichever
reading of an ambiguous scope item risks doing so is the reading to
reject), this module implements "copy-on-ingest" as: the ingest DURABLY
PERSISTS the
extracted, credential-safe usage metrics into the SQLite DB at ingest time
— i.e. the "copy" IS the row landing in `transcript_usage_events`,
protecting the MEASURED data from the live (rotation-/compaction-prone)
transcript file's own future loss, without ever duplicating the transcript
file's raw (message-content-bearing) bytes anywhere. This is flagged as an
explicit design judgment call in this task's report, not a silent
narrowing of scope.

=============================================================================
CLI (assumed contract, per test_token_attribution_red.sh's own header note:
"If T038 lands with a different CLI, the ... probes below will fail loudly
... update this file then" — this module matches the assumed contract
verbatim)
=============================================================================
    python3 transcript_ingest.py ingest <transcript-or-dir> [--db PATH]
    python3 transcript_ingest.py report [--group-by item|agent|session|model] [--db PATH]

`<transcript-or-dir>` may be a single `.jsonl` transcript file OR a
directory (recursively walked for every `*.jsonl` file inside it,
including a nested `<parent>/subagents/agent-*.jsonl` convention) — the
"or-dir" half of the assumed CLI's own naming, needed because
session->agent->item attribution (property (d)) requires the PARENT
transcript's dispatch bookkeeping and the SUBAGENT's own transcript to be
read together; a single parent transcript file also auto-discovers a
sibling `<stem>/subagents/*.jsonl` directory beside it, so passing just the
parent file still attributes its subagents correctly when they are laid
out on disk per the real, documented convention (this task's README).

Exit codes: 0 on a successful run (including "found nothing to ingest"
under an existing, empty directory); 1 on a genuine usage/path error (the
given path does not exist at all, or an unreadable/nonexistent `--db`
directory). This module is NOT bound by contracts/common-conventions.md's
C-001 5-code table — `$FC/tokens/transcript_ingest.py` is explicitly listed
in that contract file's own "Plan tools that no contract in this directory
covers" note (T-A06 has no contract yet); this module instead matches the
simpler convention of the R0 prototype it extends (SystemExit(1)-shaped
errors, else 0), documented here as a deliberate, non-silent choice rather
than an omission.

Side-effects: writes only to the given `--db` SQLite file (created if
absent, matching `usage_telemetry.py`'s own `open_db`); never writes,
renames, or deletes the source transcript file(s) (read-only on
transcripts, matching plan.md T-A06's own "Rollback: ... the ingest is
read-only on transcripts").

Dependencies: Python stdlib only (argparse, hashlib, json, os, re, sqlite3,
sys), matching every sibling `$FC` tool's own convention.
"""
import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# DEFAULT_DB — the SAME file usage_telemetry.py's own DEFAULT_DB resolves to
# (docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.db),
# computed independently (never imports usage_telemetry.py — this module
# lives in a different directory, constitution/scripts/fastcycle/tokens/,
# four levels below the repo root) so both tools agree on the default
# without a cross-tree import.
# --------------------------------------------------------------------------
DEFAULT_DB = str(
    Path(__file__).resolve().parents[4]
    / "docs" / "research" / "tokens" / "ws1_token_waste_baseline" / "POC"
    / "usage_telemetry.db"
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS transcript_usage_events (
    row_hash TEXT PRIMARY KEY,
    source_file TEXT NOT NULL,
    lineno INTEGER NOT NULL,
    record_uuid TEXT,
    session_id TEXT,
    agent_id TEXT,
    item_id TEXT,
    ts TEXT,
    model TEXT,
    msg_id TEXT,
    usage_status TEXT NOT NULL,
    missing_instrument TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_input_tokens INTEGER,
    cache_creation_input_tokens INTEGER,
    total_tokens INTEGER
);
"""

# The 4 core usage sub-fields, in the real captured schema's own order
# (this task's README, 2026-09-28).
CORE_FIELDS = (
    "input_tokens", "output_tokens",
    "cache_creation_input_tokens", "cache_read_input_tokens",
)

# common-conventions.md's own project-wide term ("UNMEASURED — the
# first-class token for a value with no recording instrument, always with
# missing_instrument; never coerced to 0"), reused verbatim (§11.4.6 — the
# SAME literal token everywhere, not a near-synonym).
UNMEASURED = "UNMEASURED"
MEASURED = "measured"

# The same item=<ATM-nnnn>|? convention tokens/dispatch_stamp.sh (T036)
# already established on this SAME `description` field (its own ITEM_RE,
# POSIX form: '(^|[[:space:]])item=(ATM-[0-9]+|\\?)'). Reused here for
# consistency, applied ONLY to `toolUseResult.description` (never to
# `message["content"]`).
ITEM_TAG_RE = re.compile(r"(?:^|\s)item=(ATM-[0-9]+|\?)")


def open_db(path):
    conn = sqlite3.connect(path)
    conn.execute(SCHEMA)
    conn.commit()
    return conn


def find_jsonl_files(path):
    """Given a file or directory, return the sorted list of .jsonl files to
    read. A single parent-transcript file also auto-discovers a sibling
    "<stem>/subagents/*.jsonl" directory beside it (the real, documented
    on-disk convention: "<parent_session_id>.jsonl" alongside
    "<parent_session_id>/subagents/agent-<agentId>.jsonl"), so the common
    "just point me at the top-level transcript" case still attributes its
    subagents without requiring the caller to pass the parent directory
    explicitly."""
    if os.path.isdir(path):
        out = []
        for root, _dirs, names in os.walk(path):
            for name in sorted(names):
                if name.endswith(".jsonl"):
                    out.append(os.path.join(root, name))
        return sorted(out)
    if os.path.isfile(path):
        out = [path]
        stem_dir = os.path.join(
            os.path.dirname(os.path.abspath(path)),
            os.path.splitext(os.path.basename(path))[0],
        )
        subagents_dir = os.path.join(stem_dir, "subagents")
        if os.path.isdir(subagents_dir):
            for name in sorted(os.listdir(subagents_dir)):
                if name.endswith(".jsonl"):
                    out.append(os.path.join(subagents_dir, name))
        return sorted(set(out))
    return []


def iter_records(filepath):
    """Yield (lineno, record_dict) for every parseable, non-blank JSONL
    line in filepath. A malformed line is logged to stderr and skipped —
    never crashes the whole ingest over one bad line (real transcripts can
    carry a truncated tail line from an interrupted write)."""
    try:
        fh = open(filepath, "r", encoding="utf-8")
    except OSError as exc:
        print("transcript_ingest: WARNING: cannot open %s: %s" % (filepath, exc), file=sys.stderr)
        return
    with fh:
        for lineno, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                print(
                    "transcript_ingest: WARNING: %s:%d: skipping unparseable line: %s"
                    % (filepath, lineno, exc), file=sys.stderr,
                )
                continue
            if not isinstance(rec, dict):
                continue
            yield lineno, rec


def build_dispatch_map(files):
    """Pass 1 — scan every file for a `toolUseResult` object (present on
    the tool-RESULT "user" record following an Agent/Task dispatch's
    tool_use block; a SIBLING top-level key to `message`, never read from
    inside it). Returns {agent_id: {"item_id": <ATM-nnnn or None>,
    "session_id": <the dispatching record's own sessionId, or None>}}.

    Reads ONLY `toolUseResult["agentId"]` and, from `toolUseResult
    ["description"]`, the narrow regex-matched item=<ATM-nnnn>|? token —
    the raw description string itself is NEVER stored."""
    dispatch_map = {}
    for filepath in files:
        for _lineno, rec in iter_records(filepath):
            tur = rec.get("toolUseResult")
            if not isinstance(tur, dict):
                continue
            agent_id = tur.get("agentId")
            if not agent_id or not isinstance(agent_id, str):
                continue
            item_id = None
            desc = tur.get("description")
            if isinstance(desc, str):
                m = ITEM_TAG_RE.search(desc)
                if m and m.group(1) != "?":
                    item_id = m.group(1)
            session_id = rec.get("sessionId")
            entry = dispatch_map.setdefault(agent_id, {"item_id": None, "session_id": None})
            if item_id and not entry["item_id"]:
                entry["item_id"] = item_id
            if session_id and not entry["session_id"]:
                entry["session_id"] = session_id
    return dispatch_map


def _int_or_none(value):
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def build_row(filepath, lineno, rec, dispatch_map):
    """Build one transcript_usage_events row for an assistant-turn record.
    Returns None if this record is not a usage-bearing assistant turn.

    CREDENTIAL SAFETY: `rec["message"]` is read only via
    .get("model")/.get("id")/.get("usage") — `.get("content")` is NEVER
    called on it anywhere in this function or its callers."""
    if rec.get("type") != "assistant":
        return None
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return None

    model = msg.get("model")
    msg_id = msg.get("id")
    usage = msg.get("usage")

    record_uuid = rec.get("uuid")
    ts = rec.get("timestamp")
    top_agent_id = rec.get("agentId")  # present only on a SUBAGENT's own records

    if isinstance(top_agent_id, str) and top_agent_id:
        agent_id = top_agent_id
        attribution = dispatch_map.get(agent_id, {"item_id": None, "session_id": None})
        item_id = attribution["item_id"]
        # A subagent record does not carry its own sessionId in the real
        # captured schema (this task's README); prefer it if a future
        # transcript shape ever does carry one, else fall back to the
        # parent's sessionId resolved via the dispatch map.
        session_id = rec.get("sessionId") or attribution["session_id"]
    else:
        agent_id = None
        item_id = None  # this tool does not (yet) item-attribute a parent
        # session's own top-level turns — only a DISPATCHED subagent's
        # usage is attributed to an item (plan T-A06 / RED test property
        # (d): "a subagent transcript -> attributed to its parent item").
        session_id = rec.get("sessionId")

    if isinstance(usage, dict):
        usage_status = MEASURED
        missing_instrument = None
        it = _int_or_none(usage.get("input_tokens"))
        ot = _int_or_none(usage.get("output_tokens"))
        crt = _int_or_none(usage.get("cache_read_input_tokens"))
        cct = _int_or_none(usage.get("cache_creation_input_tokens"))
        total = None
        if None not in (it, ot, crt, cct):
            total = it + ot + crt + cct
    else:
        usage_status = UNMEASURED
        it = ot = crt = cct = total = None
        ref = msg_id or record_uuid or ("line %d" % lineno)
        missing_instrument = (
            'message.usage (assistant record %s in %s: no "usage" block present)'
            % (ref, filepath)
        )

    if msg_id:
        row_hash = hashlib.sha256(("msgid:" + str(msg_id)).encode("utf-8")).hexdigest()
    else:
        identity = "%s:%d:%s" % (os.path.abspath(filepath), lineno, record_uuid or "")
        row_hash = hashlib.sha256(identity.encode("utf-8")).hexdigest()

    return {
        "row_hash": row_hash,
        "source_file": filepath,
        "lineno": lineno,
        "record_uuid": record_uuid,
        "session_id": session_id,
        "agent_id": agent_id,
        "item_id": item_id,
        "ts": ts,
        "model": model,
        "msg_id": msg_id,
        "usage_status": usage_status,
        "missing_instrument": missing_instrument,
        "input_tokens": it,
        "output_tokens": ot,
        "cache_read_input_tokens": crt,
        "cache_creation_input_tokens": cct,
        "total_tokens": total,
    }


INSERT_SQL = """
INSERT OR IGNORE INTO transcript_usage_events
    (row_hash, source_file, lineno, record_uuid, session_id, agent_id,
     item_id, ts, model, msg_id, usage_status, missing_instrument,
     input_tokens, output_tokens, cache_read_input_tokens,
     cache_creation_input_tokens, total_tokens)
VALUES
    (:row_hash, :source_file, :lineno, :record_uuid, :session_id, :agent_id,
     :item_id, :ts, :model, :msg_id, :usage_status, :missing_instrument,
     :input_tokens, :output_tokens, :cache_read_input_tokens,
     :cache_creation_input_tokens, :total_tokens);
"""


_USAGE_COMPARE_COLS = (
    "usage_status", "input_tokens", "output_tokens",
    "cache_read_input_tokens", "cache_creation_input_tokens",
)


def _warn_if_duplicate_usage_differs(conn, row):
    """Review finding (T038 round-1 Opus-xhigh, IMPORTANT non-blocking):
    row_hash is derived from message["id"] ALONE (see module docstring's
    IDEMPOTENCY section) -- a deliberate, disclosed, evidenced choice, not
    a defect. But that means a genuine msg_id collision carrying GENUINELY
    DIFFERENT usage counts is silently dropped by INSERT OR IGNORE with no
    signal at all. This is NOT a behavior change (the existing, first-seen
    row is still kept, exactly as before) -- it only makes a genuine
    divergence AUDIBLE via a stderr WARNING, so a caller investigating an
    unexpected total has somewhere to look. The common, benign case (a
    real transcript streaming multiple JSONL lines per logical turn, each
    carrying an IDENTICAL cumulative usage block for the same msg_id --
    see the module docstring's own cited prior investigation) never
    triggers this: identical values print nothing."""
    existing = conn.execute(
        "SELECT %s FROM transcript_usage_events WHERE row_hash = ?"
        % ", ".join(_USAGE_COMPARE_COLS),
        (row["row_hash"],),
    ).fetchone()
    if existing is None:
        return  # should not happen (we just observed a duplicate insert), but never crash over it
    new_values = tuple(row[col] for col in _USAGE_COMPARE_COLS)
    if tuple(existing) != new_values:
        print(
            "transcript_ingest: WARNING: duplicate msg_id (%s) at %s:%d has DIFFERENT "
            "usage than the already-ingested row -- kept the first-seen row, this one "
            "was skipped (existing=%s new=%s)"
            % (row["msg_id"], row["source_file"], row["lineno"], dict(zip(_USAGE_COMPARE_COLS, existing)), dict(zip(_USAGE_COMPARE_COLS, new_values))),
            file=sys.stderr,
        )


def cmd_ingest(args):
    if not os.path.exists(args.path):
        print("transcript_ingest: path does not exist: %s" % args.path, file=sys.stderr)
        return 1
    files = find_jsonl_files(args.path)
    if not files:
        print("transcript_ingest: no .jsonl files found under %s" % args.path)
        return 0

    try:
        conn = open_db(args.db)
    except sqlite3.Error as exc:
        print("transcript_ingest: cannot open --db %s: %s" % (args.db, exc), file=sys.stderr)
        return 1

    dispatch_map = build_dispatch_map(files)

    n_assistant_turns = n_new = n_dup = n_measured = n_unmeasured = 0
    for filepath in files:
        for lineno, rec in iter_records(filepath):
            row = build_row(filepath, lineno, rec, dispatch_map)
            if row is None:
                continue
            n_assistant_turns += 1
            cur = conn.execute(INSERT_SQL, row)
            if cur.rowcount == 1:
                n_new += 1
                if row["usage_status"] == MEASURED:
                    n_measured += 1
                else:
                    n_unmeasured += 1
            else:
                n_dup += 1
                _warn_if_duplicate_usage_differs(conn, row)
    conn.commit()
    print(
        "transcript_ingest: files=%d assistant_turns_read=%d new=%d "
        "measured=%d unmeasured=%d duplicate_skipped=%d db=%s"
        % (len(files), n_assistant_turns, n_new, n_measured, n_unmeasured, n_dup, args.db)
    )
    return 0


GROUP_COLS = {"item": "item_id", "agent": "agent_id", "session": "session_id", "model": "model"}


def cmd_report(args):
    """Optional convenience command (not required by the RED test; added
    for parity with usage_telemetry.py's own `report` subcommand and to
    make manual verification of ingested counts straightforward without
    hand-written SQL each time)."""
    try:
        conn = open_db(args.db)
    except sqlite3.Error as exc:
        print("transcript_ingest: cannot open --db %s: %s" % (args.db, exc), file=sys.stderr)
        return 1
    group_col = GROUP_COLS[args.group_by]
    rows = conn.execute(
        "SELECT %s AS grp, usage_status, input_tokens, output_tokens, "
        "cache_read_input_tokens, cache_creation_input_tokens, total_tokens "
        "FROM transcript_usage_events ORDER BY %s" % (group_col, group_col)
    ).fetchall()
    if not rows:
        print("transcript_ingest: report: no transcript_usage_events rows ingested yet")
        return 0
    groups = {}
    for grp, status, it, ot, crt, cct, total in rows:
        groups.setdefault(grp, []).append(
            dict(status=status, input=it, output=ot, cache_read=crt,
                 cache_creation=cct, total=total)
        )
    print("# transcript_ingest usage report — grouped by %s" % args.group_by)
    print("# db=%s  rows=%d  groups=%d" % (args.db, len(rows), len(groups)))
    print()
    for grp, recs in sorted(groups.items(), key=lambda kv: (kv[0] is None, kv[0])):
        measured = [r for r in recs if r["status"] == MEASURED]
        unmeasured_n = len(recs) - len(measured)
        label = grp if grp is not None else "(unattributed)"
        print("## %s=%s  (n=%d, measured=%d, unmeasured=%d)" % (args.group_by, label, len(recs), len(measured), unmeasured_n))
        for field, key in (
            ("input_tokens", "input"), ("output_tokens", "output"),
            ("cache_read_input_tokens", "cache_read"),
            ("cache_creation_input_tokens", "cache_creation"),
            ("total_tokens", "total"),
        ):
            vals = [r[key] for r in measured if r[key] is not None]
            s = sum(vals) if vals else 0
            print("  %s: sum=%d (n_measured_and_present=%d)" % (field, s, len(vals)))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_ingest = sub.add_parser("ingest")
    p_ingest.add_argument("path", help="transcript file OR a directory to walk recursively")
    p_ingest.add_argument("--db", default=DEFAULT_DB)
    p_ingest.set_defaults(func=cmd_ingest)

    p_report = sub.add_parser("report")
    p_report.add_argument("--group-by", choices=sorted(GROUP_COLS), default="item")
    p_report.add_argument("--db", default=DEFAULT_DB)
    p_report.set_defaults(func=cmd_report)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
