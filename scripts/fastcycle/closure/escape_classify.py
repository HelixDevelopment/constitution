#!/usr/bin/env python3
"""escape_classify.py - Escape Mechanism classifier (spec-004 "fast-dev-
cycles", User Story 3, T094, plan task T-D01, contract
contracts/closure-refusal.md EC-001..EC-003, data-model.md §6.1-6.2).

Purpose: VALIDATE an analyst-authored escape classification (`input.yaml`)
against the reopen events the live tracker DB actually records in a window,
and against the DEC-19 closed-list contract (data-model.md §6.1: exactly one
`primary` per reopened item, from E1..E9; optional `contributing`; a
§11.4.34 `detection_channel`; >=1 hash-matched `EvidencePath` for every
non-E9 entry). This tool does NOT derive a classification from keywords --
"input.yaml is the analyst-authored classification ... the tool validates
it -- it does not generate classes by keyword" (contract "Invocations"
section) -- it only checks the analyst's supplied classification is
COMPLETE (one entry per distinct reopened item in the window, no missing,
no extra -- EC-001), VALID (closed-set membership, hash-matched evidence --
EC-002), and emits the per-primary / per-item-type distribution (EC-003).

Invocation (contract "Invocations" line, verbatim flag names):
    escape_classify.py --config <cfg> --as-of <YYYY-MM-DD> \\
        --window-days <N> --classifications <input.yaml> --out <escape.json>

Window: window.from = as_of - window_days, window.to = as_of, inclusive
BETWEEN (the already-landed sibling cycle_report.py's own convention, cited
rather than re-guessed).

Exit codes (contract "Exit codes" line, verbatim): 0 valid + complete,
1 missing/extra/invalid entries, 3 needle failure (a known reopened item --
default ATM-953, reopen event 2026-07-28 -- not enumerated), 4 DB
unreadable.

The needle (exit 3) is a control-needle self-check of the DB-query
mechanism itself (constitution §11.4.273/§11.4.201(7)(b)), matching the
already-landed sibling cycle_report.py's CT-009 needle pattern: it ALWAYS
runs, unconditionally of the caller's requested window, against a fixed,
independently-known-present row (ATM-953's real `item_history` Reopened
event on 2026-07-28) plus a fixed, independently-known-fabricated id
(`ATM-99999-NEGATIVE-CONTROL`) that must NOT be found -- proving the
enumeration query genuinely sees the tracker DB before it is trusted for
the caller's own window. This is DISTINCT from EC-001's exit-1
"missing/extra entries" case, which is about the CALLER's classification
file being incomplete for the CALLER's requested window, not about the
query mechanism itself being broken.

Stdlib + PyYAML only (matching the sibling gates/catchset_compare.py and
gates/gate_audit.py tools' own `import yaml` convention for --config and,
here, --classifications parsing); imports `canon`/`body_hash_of` from the
sibling lib/fc_common.py (C-002), matching cycle_report.py's own import
pattern.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers (identical
# import-by-path pattern to cycle_report.py -- constitution/scripts/fastcycle
# has no __init__.py anywhere, matching this tree's existing flat-script
# layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "escape-classify/v1"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_NEEDLE = 3
EXIT_DB_UNREADABLE = 4

# data-model.md §6.1 DEC-19 closed list -- exactly this set, in this order
# (adding a member is a governance change; never invented here).
ESCAPE_CODES = (
    "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9",
)

# §11.4.34 reason vocabulary (data-model.md §6.2 `detection_channel`).
DETECTION_CHANNELS = (
    "test-failed",
    "manual-testing-detected",
    "captured-evidence-contradicts",
    "end-user-report",
    "cycle-re-discovered",
    "design-reconsidered",
)

# The CT-009-style self-test needle this tool ALWAYS runs first (see module
# docstring). Fixed, never CLI-overridable -- the contract's own "Exit
# codes" line names ATM-953 / 2026-07-28 as THE default, and this tool's
# Invocation grammar (contract "Invocations" section) carries no
# --needle-* flags the way cycle_report.py's test-only extensions do.
NEEDLE_PRESENT_ID = "ATM-953"
NEEDLE_PRESENT_EVENT = "Reopened"
NEEDLE_PRESENT_ON_DATE = "2026-07-28"
NEEDLE_FABRICATED_ID = "ATM-99999-NEGATIVE-CONTROL"

CONTENT_ADDRESS_RE = re.compile(r"sha256:([0-9a-f]{64})")


# ---------------------------------------------------------------------------
# --config loading (identical pattern to gates/catchset_compare.py /
# gates/gate_audit.py's own load_yaml_config/project_root_of/cfg_path --
# reused rather than re-invented, constitution §11.4.227).
# ---------------------------------------------------------------------------
def load_yaml_config(path):
    if not path or not os.path.isfile(path):
        print("escape_classify: config file not found: %s" % path, file=sys.stderr)
        sys.exit(EXIT_USAGE)
    try:
        import yaml
    except ImportError:
        print("escape_classify: PyYAML is required to parse --config (pip install pyyaml)",
              file=sys.stderr)
        sys.exit(EXIT_USAGE)
    with open(path, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    if not isinstance(cfg, dict) or "paths" not in cfg:
        print("escape_classify: %s missing required top-level key 'paths'" % path, file=sys.stderr)
        sys.exit(EXIT_USAGE)
    return cfg


def project_root_of(config_path):
    """The project root is two directories above config/fastcycle/<file>.yaml
    (config/fastcycle/fastcycle.yaml -> project root). Never guessed from
    argv[0] or cwd (constitution §11.4.6)."""
    cfg_dir = os.path.dirname(os.path.abspath(config_path))
    return os.path.dirname(os.path.dirname(cfg_dir))


def cfg_path(cfg, root, key):
    rel = cfg.get("paths", {}).get(key)
    if not rel:
        print("escape_classify: config missing required paths.%s" % key, file=sys.stderr)
        sys.exit(EXIT_USAGE)
    return os.path.join(root, rel)


# ---------------------------------------------------------------------------
# Tracker DB access (read-only, C-006 -- identical pattern to
# cycle_report.py's open_db_readonly).
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


def db_reopened_in_window(conn, frm, to):
    """EC-001: enumerate reopen events from item_history in the window.
    Returns raw rows (id, atm_id, event_type, by, on_date, reason,
    evidence_path, created_at), earliest id first."""
    cur = conn.execute(
        "SELECT id, atm_id, event_type, by, on_date, reason, evidence_path, created_at "
        "FROM item_history WHERE event_type = 'Reopened' AND on_date BETWEEN ? AND ? "
        "ORDER BY id",
        (frm, to),
    )
    cols = ("id", "atm_id", "event_type", "by", "on_date", "reason", "evidence_path", "created_at")
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def db_item_type(conn, item_id):
    cur = conn.execute("SELECT type FROM items WHERE atm_id = ? LIMIT 1", (item_id,))
    row = cur.fetchone()
    return row[0] if row else "Unknown"


# ---------------------------------------------------------------------------
# CT-009-style self-test needle (see module docstring). ALWAYS runs,
# regardless of the caller's requested window -- proves the enumeration
# mechanism (db_reopened_in_window) genuinely sees the live tracker DB
# before it is trusted for the caller's own window (constitution
# §11.4.273/§11.4.201(7)(b)).
# ---------------------------------------------------------------------------
def run_needle(conn):
    """Returns (ok: bool, detail: str)."""
    rows = db_reopened_in_window(conn, NEEDLE_PRESENT_ON_DATE, NEEDLE_PRESENT_ON_DATE)
    found_present = any(r["atm_id"] == NEEDLE_PRESENT_ID for r in rows)
    found_fabricated = any(r["atm_id"] == NEEDLE_FABRICATED_ID for r in rows)
    if found_present and not found_fabricated:
        return True, "needle ok: %s %s/%s enumerated, %s not enumerated" % (
            NEEDLE_PRESENT_ID, NEEDLE_PRESENT_EVENT, NEEDLE_PRESENT_ON_DATE, NEEDLE_FABRICATED_ID)
    problems = []
    if not found_present:
        problems.append("known reopened item %s %s/%s NOT enumerated" % (
            NEEDLE_PRESENT_ID, NEEDLE_PRESENT_EVENT, NEEDLE_PRESENT_ON_DATE))
    if found_fabricated:
        problems.append("fabricated id %s WAS enumerated (false match)" % NEEDLE_FABRICATED_ID)
    return False, "needle FAILED: " + "; ".join(problems)


# ---------------------------------------------------------------------------
# Exact-duplicate row removal (EC-001: "removes exact-duplicate rows
# (reports how many; T-A12 removes them at the source)"). Same content-key
# shape as cycle_report.py's own `_exact_dup_key`, extended with atm_id
# since this enumeration spans every item in the window, not one item's own
# history.
# ---------------------------------------------------------------------------
def _exact_dup_key(row):
    return (row["atm_id"], row["event_type"], row.get("by"), row.get("on_date"),
            row.get("reason"), row.get("evidence_path"), row.get("created_at"))


def dedup_rows(rows):
    seen = set()
    out = []
    removed = 0
    for row in rows:
        key = _exact_dup_key(row)
        if key in seen:
            removed += 1
            continue
        seen.add(key)
        out.append(row)
    return out, removed


def group_by_item(rows):
    """{atm_id: sorted [item_history id, ...]}."""
    grouped = {}
    for row in rows:
        grouped.setdefault(row["atm_id"], []).append(row["id"])
    for atm_id in grouped:
        grouped[atm_id] = sorted(grouped[atm_id])
    return grouped


# ---------------------------------------------------------------------------
# --classifications (input.yaml) loading -- EscapeClassification fields per
# data-model.md line 184 verbatim: {item_id, reopen_events, primary,
# contributing (optional), detection_channel, evidence: [EvidencePath >=1]}.
# EvidencePath shape per data-model.md line 27: {path, content_address}.
# ---------------------------------------------------------------------------
def load_classifications(path):
    try:
        import yaml
    except ImportError:
        print("escape_classify: PyYAML is required to parse --classifications (pip install pyyaml)",
              file=sys.stderr)
        sys.exit(EXIT_USAGE)
    if not os.path.isfile(path):
        print("escape_classify: --classifications file not found: %s" % path, file=sys.stderr)
        sys.exit(EXIT_USAGE)
    with open(path, "r", encoding="utf-8") as fh:
        try:
            doc = yaml.safe_load(fh)
        except Exception as exc:  # PyYAML raises its own exception types
            print("escape_classify: --classifications is not valid YAML: %s" % exc, file=sys.stderr)
            sys.exit(EXIT_USAGE)
    if not isinstance(doc, dict) or not isinstance(doc.get("entries"), list):
        print("escape_classify: --classifications must be a YAML mapping with a top-level "
              "'entries' list", file=sys.stderr)
        sys.exit(EXIT_USAGE)
    return doc["entries"]


# ---------------------------------------------------------------------------
# EC-002 per-entry validation. Returns a (problems: [str]) list -- empty
# means the entry is valid. `root` is the repo root every EvidencePath is
# resolved relative to.
# ---------------------------------------------------------------------------
def validate_entry(entry, root):
    problems = []
    item_id = entry.get("item_id") or "<missing item_id>"

    primary = entry.get("primary")
    if primary not in ESCAPE_CODES:
        problems.append(
            "%s: primary %r is not one of the DEC-19 closed-list codes %s"
            % (item_id, primary, ESCAPE_CODES))

    contributing = entry.get("contributing") or []
    if not isinstance(contributing, list):
        problems.append("%s: contributing must be a list" % item_id)
        contributing = []
    for code in contributing:
        if code not in ESCAPE_CODES:
            problems.append(
                "%s: contributing code %r is not one of the DEC-19 closed-list codes %s"
                % (item_id, code, ESCAPE_CODES))
        if code == primary:
            problems.append("%s: contributing code %r duplicates primary" % (item_id, code))

    detection_channel = entry.get("detection_channel")
    if detection_channel not in DETECTION_CHANNELS:
        problems.append(
            "%s: detection_channel %r is not one of the §11.4.34 vocabulary %s"
            % (item_id, detection_channel, DETECTION_CHANNELS))

    evidence = entry.get("evidence") or []
    if not isinstance(evidence, list):
        problems.append("%s: evidence must be a list" % item_id)
        evidence = []

    if primary == "E9":
        settling_evidence = entry.get("settling_evidence")
        if not settling_evidence or not isinstance(settling_evidence, str):
            problems.append(
                "%s: E9 unclassifiable requires a non-empty settling_evidence naming the "
                "missing evidence" % item_id)
    else:
        if len(evidence) < 1:
            problems.append(
                "%s: evidence list is empty -- EC-002 requires >=1 EvidencePath that exists "
                "and hash-matches for any non-E9 entry" % item_id)

    for ev in evidence:
        if not isinstance(ev, dict) or "path" not in ev or "content_address" not in ev:
            problems.append("%s: evidence entry %r is not a {path, content_address} EvidencePath"
                             % (item_id, ev))
            continue
        rel_path = ev["path"]
        content_address = ev["content_address"]
        abs_path = os.path.join(root, rel_path)
        if not os.path.isfile(abs_path):
            problems.append("%s: evidence path does not exist: %s" % (item_id, rel_path))
            continue
        m = CONTENT_ADDRESS_RE.fullmatch(content_address or "")
        if not m:
            problems.append(
                "%s: evidence content_address for %s is not sha256:<64 hex>: %r"
                % (item_id, rel_path, content_address))
            continue
        with open(abs_path, "rb") as fh:
            actual = hashlib.sha256(fh.read()).hexdigest()
        if actual != m.group(1):
            problems.append(
                "%s: evidence hash mismatch for %s (declared %s, actual sha256:%s) -- "
                "STALE_EVIDENCE" % (item_id, rel_path, content_address, actual))

    return problems


# ---------------------------------------------------------------------------
# EC-003: distribution per primary class and per item type.
# ---------------------------------------------------------------------------
def compute_distribution(entries, conn):
    by_primary = {code: 0 for code in ESCAPE_CODES}
    by_item_type = {}
    for entry in entries:
        primary = entry["primary"]
        by_primary[primary] = by_primary.get(primary, 0) + 1
        item_type = db_item_type(conn, entry["item_id"])
        by_item_type[item_type] = by_item_type.get(item_type, 0) + 1
    return {
        "by_primary": by_primary,
        "by_item_type": by_item_type,
        "sum": sum(by_primary.values()),
    }


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash, identical pattern to
# cycle_report.py's write_report -- write-temp-then-rename, constitution
# §11.4.205(6)).
# ---------------------------------------------------------------------------
def write_out(out_path, body, run_meta):
    doc = dict(body)
    doc["schema"] = SCHEMA
    doc["body_hash"] = body_hash_of({**doc})
    doc["run_meta"] = run_meta
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".escape_classify.")
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
        print("escape_classify: --as-of YYYY-MM-DD is required", file=sys.stderr)
        return False
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", as_of):
        print("escape_classify: --as-of must be YYYY-MM-DD, got %r" % as_of, file=sys.stderr)
        return False
    try:
        datetime.date.fromisoformat(as_of)
    except ValueError:
        print("escape_classify: --as-of is not a valid calendar date: %r" % as_of, file=sys.stderr)
        return False
    return True


def build_arg_parser():
    p = argparse.ArgumentParser(prog="escape_classify.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--config", required=True)
    p.add_argument("--as-of", required=True)
    p.add_argument("--window-days", type=int, required=True)
    p.add_argument("--classifications", required=True)
    p.add_argument("--out", required=True)
    # Phase D checkpoint gate (tasks.md line 298: "escape_classify.py and
    # reopen_rate.py pass --determinism-check"). Identical pattern to the
    # already-landed sibling cycle_report.py's own --determinism-check:
    # re-invokes this SAME process twice as a subprocess with its own
    # --out, compares body_hash (C-002 -- run_meta, e.g. hostname, is
    # deliberately excluded from the hash so it can never cause a false
    # nondeterminism finding).
    p.add_argument("--determinism-check", action="store_true")
    return p


def run_determinism_check(argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    runs = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            # argparse's `--out` is "last wins" for a repeated flag, so
            # appending our own --out after `inner` (which may itself
            # carry a caller-supplied --out) makes ours authoritative
            # regardless of duplication -- identical to cycle_report.py's
            # own determinism-check wiring.
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                print("escape_classify: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or (proc.returncode == 0 and not os.path.exists(out_i)):
                sys.stderr.write(proc.stderr)
                print("escape_classify: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            body_hash = None
            if proc.returncode == 0:
                with open(out_i, encoding="utf-8") as fh:
                    body_hash = json.load(fh).get("body_hash")
            runs.append((proc.returncode, body_hash))
    if runs[0] != runs[1]:
        print("escape_classify: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    print("escape_classify: deterministic (rc=%s, body_hash=%s)" % runs[0])
    return 0


def main(argv):
    args = build_arg_parser().parse_args(argv)

    if args.determinism_check:
        return run_determinism_check(argv)

    if not require_as_of(args.as_of):
        return EXIT_USAGE
    if args.window_days < 0:
        print("escape_classify: --window-days must be >= 0, got %d" % args.window_days, file=sys.stderr)
        return EXIT_USAGE

    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)
    db_path = cfg_path(cfg, root, "workable_items_db")

    conn = open_db_readonly(db_path)
    if conn is None:
        print("escape_classify: tracker DB unreadable at %s" % db_path, file=sys.stderr)
        return EXIT_DB_UNREADABLE

    # Needle: ALWAYS runs first, before any window-specific work (see module
    # docstring; matches sibling cycle_report.py's CT-009 ordering).
    ok, detail = run_needle(conn)
    print("escape_classify: %s" % detail, file=sys.stderr)
    if not ok:
        return EXIT_NEEDLE

    window = {
        "from": (datetime.date.fromisoformat(args.as_of) -
                  datetime.timedelta(days=args.window_days)).isoformat(),
        "to": args.as_of,
    }

    raw_rows = db_reopened_in_window(conn, window["from"], window["to"])
    rows, duplicates_removed = dedup_rows(raw_rows)
    db_grouped = group_by_item(rows)  # {atm_id: [item_history id, ...]}

    entries = load_classifications(args.classifications)

    # EC-001: exactly one classification entry per distinct reopened item;
    # missing or extra entries => exit 1 listing them.
    entries_by_item = {}
    dup_input_ids = []
    for entry in entries:
        eid = entry.get("item_id")
        if eid in entries_by_item:
            dup_input_ids.append(eid)
        entries_by_item[eid] = entry

    db_ids = set(db_grouped.keys())
    entry_ids = set(entries_by_item.keys())
    missing = sorted(db_ids - entry_ids)
    extra = sorted(entry_ids - db_ids)

    problems = []
    if dup_input_ids:
        problems.append("duplicate --classifications entries for item(s): %s"
                         % ", ".join(sorted(set(dup_input_ids))))
    if missing:
        problems.append("missing classification entries (item_id enumerated by the tracker "
                         "in window [%s, %s] but absent from --classifications): %s"
                         % (window["from"], window["to"], ", ".join(missing)))
    if extra:
        problems.append("extra classification entries (item_id in --classifications but not "
                         "enumerated by the tracker in window [%s, %s]): %s"
                         % (window["from"], window["to"], ", ".join(extra)))

    # EC-001 (cont.): each matched entry's reopen_events must equal the
    # tracker's own enumerated item_history ids for that item in this
    # window (never invented, never trusted blindly -- constitution
    # §11.4.6).
    matched_ids = sorted(db_ids & entry_ids)
    for item_id in matched_ids:
        entry = entries_by_item[item_id]
        declared = entry.get("reopen_events")
        if not isinstance(declared, list):
            problems.append("%s: reopen_events must be a list" % item_id)
            continue
        declared_set = set(declared)
        expected_set = set(db_grouped[item_id])
        if declared_set != expected_set:
            problems.append(
                "%s: reopen_events %s does not match the tracker's own enumerated "
                "item_history ids %s for window [%s, %s]"
                % (item_id, sorted(declared_set), sorted(expected_set), window["from"], window["to"]))

    # EC-002: per-entry validity for every matched entry.
    for item_id in matched_ids:
        problems.extend(validate_entry(entries_by_item[item_id], root))

    if problems:
        print("escape_classify: refused -- %d finding(s):" % len(problems), file=sys.stderr)
        for p in problems:
            print("  - %s" % p, file=sys.stderr)
        return EXIT_FINDING

    # Everything is valid + complete: build the output entries (EC-003).
    out_entries = []
    for item_id in matched_ids:
        entry = entries_by_item[item_id]
        out_entry = {
            "item_id": item_id,
            "item_type": db_item_type(conn, item_id),
            "reopen_events": sorted(entry["reopen_events"]),
            "primary": entry["primary"],
            "contributing": sorted(entry.get("contributing") or []),
            "detection_channel": entry["detection_channel"],
            "evidence": [
                {"path": ev["path"], "content_address": ev["content_address"]}
                for ev in (entry.get("evidence") or [])
            ],
            "classified_by": "escape_classify.py",
            "reviewed_by": None,
        }
        if entry.get("primary") == "E9":
            out_entry["settling_evidence"] = entry.get("settling_evidence")
        out_entries.append(out_entry)
    out_entries.sort(key=lambda e: e["item_id"])

    distribution = compute_distribution(out_entries, conn)

    run_meta = {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}
    body = {
        "as_of": args.as_of,
        "window": window,
        "duplicates_removed": duplicates_removed,
        "entries": out_entries,
        "distribution": distribution,
    }
    write_out(args.out, body, run_meta)
    print("escape_classify: wrote %d entries to %s (distribution sum=%d)"
          % (len(out_entries), args.out, distribution["sum"]))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
