#!/usr/bin/env bash
# Purpose : T048 restart regression suite for
#           constitution/scripts/fastcycle/cycle/select_sample.py -- round 1
#           (docs/qa/t048_restart_round1_20261008/R5_cycle_report_sampling.md)
#           and round 2 (docs/qa/t048_restart_round2_20261008/V2_sampling.md).
#           Every check drives the REAL select_sample.py through its real CLI
#           (python3 select_sample.py ...) against a synthetic tracker DB built
#           by tests/fixtures/cycle_report/build_asof_scenario.py, plus live-DB
#           checks on read-only .backup snapshots (the live DB is never written).
#
# Findings guarded:
#   R5 B1  the --as-of cutoff leaked future events (S1, S3; boundary rows S2).
#   R5 B2 / V2-1  "selected" was not "usable": below_required counted
#          excluded rows, and (V2-1) bulk/retroactive rows consumed the
#          per-type quota while usable rows of the same type existed further
#          back. Rule now (OPERATOR-DECISION-RECORDED in select_sample.py,
#          EXCLUDED_ROWS_COUNT_TOWARD_N = False): exclude first, then take the
#          most-recent N USABLE rows; every excluded row walked past is LISTED
#          (DEC-03 "excluded from duration statistics but listed"). S2 (exact
#          fixture), S5 (live: n_usable == min(N, usable available)).
#   R5 M2  oldest-N survived; S2 pins the exact sampled set.
#   R5 M10 --determinism-check never wrote --out (S4).
#   V2-4   no as-of boundary rows: the fixture now has a closure ON the as-of
#          day (ATM-310), a Reopened row ON window.from (ATM-300), a negative
#          Opened->closure gap (ATM-504) and a closure row whose created_at and
#          row id disagree on recency (ATM-1003) -- all pinned by S2.
#   V2-8   the default CT-009 needle is a row dated 2026-07-28; for an earlier
#          --as-of it is a FUTURE row. S6: with no needle overrides the needle
#          is derived from the DB at the as-of (fixture and live snapshot).
#   V2-2 (class) the retroactive rule is ONE function shared with
#          cycle_report.py; S7 cross-checks the one remaining out-of-scope copy
#          (closure/reopen_rate.py) on a boundary corpus so a drift is caught.
#   V2-6   paired mutants are built in $TMP (a copy of lib/ closure/ cycle/),
#          never inside the source tree.
#   Round 3 (docs/qa/t048_restart_round3_20261008/V2_sampling.md):
#   V3-1/V3-8 (class: an inclusive bound, or a first-vs-latest choice, with
#          no row on it -- patched one instance at a time in rounds 1 and 2):
#          S9 runs the GENERATED boundary matrix (build_asof_scenario.py
#          matrix-full|matrix-cut) against an independent in-test oracle, with
#          a meta-check that fails on any cell without an assertion. Every
#          surviving round-3 mutation is a paired mutation below.
#   V3-6   S7b: reopen_rate.py's closed/reopened-in-window and retroactive
#          rules cross-checked against select_sample on every matrix history;
#          collect_baseline.py's SQL copies are measured and REPORTED only.
#   V3-3   S10: the recorded operator decision's other setting is specified.
#   V3-4   S11: a missing/broken lib/fc_common.py is BLIND (exit 4).
#
# Hand-derived expectation (fixture docstring lists every row; as_of
# 2026-08-23, window 60d => [2026-06-24, 2026-08-23], min_per_type 2,
# bulk_threshold 3; only rows with on_date <= as_of count):
#   Bug candidates (latest as-of closure created_at): ATM-1003 06-25 (row id
#     HIGHEST -- written last), ATM-300 06-30, ATM-953 07-01, ATM-1002 07-10,
#     ATM-800 07-25, ATM-277 08-20, ATM-310 08-23 (ON the as-of day).
#     None excluded => most-recent 2 usable = {ATM-310, ATM-277}; nothing
#     listed. n_available 7, n_usable_available 7, n_selected 2, n_usable 2.
#     (SS_N1 drops the as-of day => ATM-310 loses its closure; SS_N4 ranks by
#     row id => ATM-1003 becomes "most recent".)
#   Task candidates walked most-recent-first: ATM-603/602/601 (07-20, one
#     shared dir => bulk cluster of 3) are LISTED, then ATM-504 (07-06 09:59;
#     Opened row 60 s LATER -> negative gap, NOT retroactive) and ATM-503
#     (07-05 12:00) are TAKEN. n_available 7, n_usable_available 4,
#     n_selected 2, n_usable 2, n_listed_excluded 3, below_required false.
#     (Round-1 rule: picked {602, 603}, both bulk, n_usable 0 -- the V2-1
#     starvation; SS_N3 makes ATM-504 retroactive.)
#   Feature: ATM-700 only, retroactive (20 s) => listed, n_selected 0,
#     n_usable 0, below_required true.
#   Reopened in window: ATM-300 (06-24 = window.from) and ATM-800 (07-15).
#
# Usage   : bash test_select_sample_r5_regression.sh
#           Exit 0 = every check (and every paired mutation, unless
#           FC_R5_MUTANT=1 is set because this IS a mutation run) held.
#           SELECT_SAMPLE_UNDER_TEST=<path> runs the checks against another
#           copy of the tool (used by the paired-mutation harness below).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
REAL_TOOL="$FC/cycle/select_sample.py"
TOOL="${SELECT_SAMPLE_UNDER_TEST:-$REAL_TOOL}"
# ASOF_BUILDER_UNDER_TEST: a drifted copy of the builder (the round-4 builder-drift
# paired mutations, V4-2) -- the placement self-check must catch it.
# The reopen_rate.py copy BESIDE the tool under test: a paired mutation of
# closure/reopen_rate.py (round 4, B3) reaches S7/S7b through the mutant tree.
RR_UNDER_TEST="$(cd "$(dirname "$TOOL")/.." && pwd)/closure/reopen_rate.py"
BUILDER="${ASOF_BUILDER_UNDER_TEST:-$FC/tests/fixtures/cycle_report/build_asof_scenario.py}"
DB="$ROOT/docs/workable_items.db"

fail=0
ok()  { echo "ok $*"; }
bad() { echo "NOT ok $*"; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The independent reference oracle (round 4): ONE stdlib-only module for this
# file, used by S9 (the generated matrix) and S13 (the live snapshot). It is
# written from this heredoc -- it is not shared with, and imports nothing from,
# the tools or tests/test_cycle_report_red.sh (that file carries its own).
ORACLE_DIR="$TMP/oracle"
mkdir -p "$ORACLE_DIR"
cat >"$ORACLE_DIR/ss_oracle.py" <<'ORACLE_EOF'
"""Independent reference oracle for select_sample.py (T048 restart round 4).
Stdlib only; imports nothing from the tools. A deliberately plain re-statement
of the DEC-03 rules, PARAMETRISED so the test can also evaluate each rule with
one input field swapped for its sibling (the discrimination table below): a
field whose swap changes no outcome on the corpus has no disagreement cell,
and the matrix meta-check fails (round 4, V4-1: the dimension list is derived
from the fields the tool reads, never from memory)."""
import ast
import datetime
import os
import re
import sqlite3

UTC = datetime.timezone.utc
CLOSE = ("Fixed", "Implemented", "Completed")
DEFAULT_NEEDLE = ("ATM-953", "Fixed", "2026-07-28")
TYPES = ("Bug", "Feature", "Task")

BASE = {
    "cut_field": "on_date",           # as-of cutoff keys on this field's day
    "closure_field": "on_date",       # closed-in-window keys on this field's day
    "reopen_field": "on_date",        # reopened-in-window keys on this field's day
    "day_fn": "local",                # local = first 10 chars; utc = UTC date; raw = whole string
    "closure_events": CLOSE,
    "recency": ("created_at", "seq", "atm_id"),
    "needle": "day_seq_desc",
    "bulk_key": "dirname_raw",        # (dirname(evidence), raw on_date) of the LAST closure
    "bulk_closure": "last",
    "retro_closure": "last",
    "bulk_ge": True,                  # cluster size >= threshold
    "precedence": "bulk_first",
    "retro_lo_incl": True,            # 0 <= gap
    "retro_hi_incl": False,           # gap < 60
    "type_strata": True,
    "from_shift": 0,                  # window.from = as_of - window_days + from_shift
}


def inst(s):
    """created_at "YYYY-MM-DD HH:MM:SS" (UTC) or an ISO instant (offset or Z)."""
    s = (s or "").strip().replace("Z", "+00:00")
    if len(s) == 10:
        s += "T00:00:00"
    if "T" not in s:
        s = s.replace(" ", "T", 1)
    dt = datetime.datetime.fromisoformat(s)
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


def day(row, field, P):
    v = row.get(field) or ""
    if P["day_fn"] == "raw":
        return v
    if P["day_fn"] == "utc" and v:
        return inst(v).astimezone(UTC).date().isoformat()
    return v[:10]


def evaluate(rows_by_item, type_of, as_of, window_days, n, threshold, P=None):
    """rows_by_item: {atm_id: [row dicts with event_type, on_date, created_at,
    evidence_path, seq]} (seq = item_history.id order). Returns the
    normalised outcome {items, strata, reopened, needle}."""
    P = dict(BASE, **(P or {}))
    frm = (datetime.date.fromisoformat(as_of) - datetime.timedelta(days=window_days - P["from_shift"])).isoformat()
    cut = {i: sorted((r for r in rows if day(r, P["cut_field"], P) <= as_of), key=lambda r: r["seq"])
           for i, rows in rows_by_item.items() if i in type_of}  # the tracker JOINs items: no type, no candidate

    def in_win(r, field, events):
        return r["event_type"] in events and frm <= day(r, field, P) <= as_of

    closed = {i for i, rs in cut.items() if any(in_win(r, P["closure_field"], P["closure_events"]) for r in rs)}
    reopened = {i for i, rs in cut.items() if any(in_win(r, P["reopen_field"], ("Reopened",)) for r in rs)}
    cands = sorted(closed | reopened)

    def closure(i, which):
        cl = [r for r in cut[i] if r["event_type"] in P["closure_events"]]
        return (cl[-1] if which == "last" else cl[0]) if cl else None

    def retro(i):
        op = next((r for r in cut[i] if r["event_type"] == "Opened"), None)
        cl = closure(i, P["retro_closure"])
        if not op or not cl:
            return False
        try:
            gap = (inst(cl["created_at"]) - inst(op["created_at"])).total_seconds()
        except ValueError:
            return False
        lo = gap >= 0 if P["retro_lo_incl"] else gap > 0
        hi = gap <= 60 if P["retro_hi_incl"] else gap < 60
        return lo and hi

    groups = {}
    for i in cands:
        cl = closure(i, P["bulk_closure"])
        if cl and cl.get("evidence_path"):
            ev = cl["evidence_path"]
            key = {"dirname_raw": (os.path.dirname(ev), cl["on_date"]),
                   "dirname_day": (os.path.dirname(ev), cl["on_date"][:10]),
                   "fullpath_raw": (ev, cl["on_date"])}[P["bulk_key"]]
            groups.setdefault(key, []).append(i)
    bulk = {i for g in groups.values() if (len(g) >= threshold if P["bulk_ge"] else len(g) > threshold) for i in g}

    def excl(i):
        b, r = i in bulk, retro(i)
        if P["precedence"] == "bulk_first":
            return "bulk" if b else ("retro" if r else None)
        return "retro" if r else ("bulk" if b else None)

    exclusion = {i: excl(i) for i in cands}

    def recency(i):
        cl = closure(i, "last")
        key = []
        for f in P["recency"]:
            if f == "created_at":
                key.append(inst(cl["created_at"]) if cl else datetime.datetime.min.replace(tzinfo=UTC))
            elif f == "seq":
                key.append(cl["seq"] if cl else -1)
            else:
                key.append(i)
        return tuple(key)

    reason, strata = {}, {}
    pools = [(t, [t]) for t in TYPES] if P["type_strata"] else [("*", list(TYPES))]
    picked_by, listed_by = {}, {}
    for label, ts in pools:
        ids = sorted((i for i in cands if i in closed and type_of[i] in ts), key=recency)
        picked, listed = [], []
        for i in reversed(ids):
            if len(picked) >= n:
                break
            (picked if exclusion[i] is None else listed).append(i)
        picked_by[label], listed_by[label] = picked, listed
    for t in TYPES:
        if P["type_strata"]:
            picked, listed = picked_by[t], listed_by[t]
        else:
            picked = [i for i in picked_by["*"] if type_of[i] == t]
            listed = [i for i in listed_by["*"] if type_of[i] == t]
        avail = [i for i in cands if i in closed and type_of[i] == t]
        strata[t] = {"n_available": len(avail),
                     "n_usable_available": sum(1 for i in avail if exclusion[i] is None),
                     "n_selected": len(picked), "n_usable": len(picked),
                     "n_listed_excluded": len(listed), "below_required": len(picked) < n}
        for i in listed:
            reason[i] = "listed-excluded-" + t.lower()
        for i in picked:
            reason[i] = "sampled-" + t.lower()
    for i in reopened:
        reason[i] = "reopened-in-window"

    d_id, d_ev, d_date = DEFAULT_NEEDLE
    if d_date <= as_of:
        needle = ("default", d_id, d_ev, d_date)
    else:
        pool = [(r["on_date"][:10], r["seq"], r["created_at"], i, r) for i, rows in rows_by_item.items()
                for r in rows if r["event_type"] in CLOSE and r["on_date"][:10] <= as_of]
        if not pool:
            needle = ("default-postdates-as-of", d_id, d_ev, d_date)
        else:
            if P["needle"] == "day_seq_desc":
                best = max(pool, key=lambda x: (x[0], x[1]))
            elif P["needle"] == "day_seq_asc":
                top = max(x[0] for x in pool)
                best = min((x for x in pool if x[0] == top), key=lambda x: x[1])
            else:  # created_desc
                best = max(pool, key=lambda x: (x[0], inst(x[2])))
            needle = ("derived-at-as-of", best[3], best[4]["event_type"], best[4]["on_date"])
    return {"items": {i: (reason[i], exclusion[i]) for i in sorted(reason)}, "strata": strata,
            "reopened": sorted(reopened), "needle": needle}


def tool_outcome(doc):
    """select_sample's report in the oracle's normalised shape."""
    def kind(it):
        if not it["excluded_from_duration"]:
            return None
        r = it.get("exclusion_reason") or ""
        return "bulk" if r.startswith("bulk-import-cluster") else "retro" if r.startswith("retroactive") else "other:" + r
    n = (doc.get("run_meta") or {}).get("needle") or {}
    return {"items": {it["item_id"]: (it["selection_reason"], kind(it)) for it in doc.get("items", [])},
            "strata": {t: {k: (doc.get("strata") or {}).get(t, {}).get(k)
                           for k in ("n_available", "n_usable_available", "n_selected", "n_usable",
                                     "n_listed_excluded", "below_required")} for t in TYPES},
            "reopened": sorted(doc.get("reopened_in_window", [])),
            "needle": (n.get("source"), n.get("present_id"), n.get("present_event"), n.get("present_on_date"))}


def diff(tool, oracle, label):
    p = []
    ti, oi = tool["items"], oracle["items"]
    for i in sorted(set(ti) | set(oi)):
        if ti.get(i) != oi.get(i):
            p.append("%s %s tool=%s oracle=%s" % (label, i, ti.get(i), oi.get(i)))
    for k in ("strata", "reopened", "needle"):
        if tool[k] != oracle[k]:
            p.append("%s %s tool=%s oracle=%s" % (label, k, tool[k], oracle[k]))
    return p


# ---- corpora -----------------------------------------------------------------
def matrix_corpus(man):
    rows, types = {}, {}
    for c in man["cells"]:
        for it in c["items"]:
            rows[it["atm_id"]] = [dict(r) for r in it["rows"]]
            types[it["atm_id"]] = it["type"]
    return rows, types


def db_corpus(path):
    conn = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    rows, types = {}, dict(conn.execute("SELECT atm_id, type FROM items").fetchall())
    for rid, aid, ev, od, evp, ca in conn.execute(
            "SELECT id, atm_id, event_type, on_date, evidence_path, created_at FROM item_history ORDER BY id"):
        rows.setdefault(aid, []).append({"seq": rid, "event_type": ev, "on_date": od, "evidence_path": evp,
                                         "created_at": ca})
    conn.close()
    return rows, types


def db_columns(paths):
    cols = set()
    for path in paths:
        conn = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        for table in ("item_history", "items"):
            cols |= {r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)}
        conn.close()
    return cols


# ---- field inventory (round 4: the dimension list, derived mechanically) -----
def fields_read(path, universe):
    """Every record field the tool's source reads: string subscripts r["f"],
    .get("f") calls, and identifiers inside SQL string literals -- intersected
    with the record universe (tracker DB columns + commit/review keys)."""
    tree = ast.parse(open(path, encoding="utf-8").read())
    found = {}
    for node in ast.walk(tree):
        keys = []
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant) \
                and isinstance(node.slice.value, str):
            keys.append(node.slice.value)
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "get" \
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
            keys.append(node.args[0].value)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and re.search(r"\b(SELECT|WHERE|ORDER BY)\b", node.value):
            keys += re.findall(r"[a-z_]+", node.value)
        for k in keys:
            if k in universe:
                found.setdefault(k, set()).add(node.lineno)
    return found


# Every field select_sample's rules read has alternatives that MUST change an
# outcome on the matrix (else the matrix has no disagreement cell for it).
FIELD_ALTS = {
    "on_date": [("closure window keyed on created_at", {"closure_field": "created_at"}),
                ("reopened window keyed on created_at", {"reopen_field": "created_at"}),
                ("as-of cutoff keyed on created_at", {"cut_field": "created_at"}),
                ("day = UTC date of the on_date instant", {"day_fn": "utc"}),
                ("day = raw on_date string", {"day_fn": "raw"}),
                ("bulk key day-only on_date", {"bulk_key": "dirname_day"})],
    "created_at": [("closure window keyed on created_at", {"closure_field": "created_at"}),
                   ("reopened window keyed on created_at", {"reopen_field": "created_at"}),
                   ("recency without created_at", {"recency": ("seq", "atm_id")}),
                   ("needle ordered by created_at", {"needle": "created_desc"}),
                   ("retroactive gap <= 60 s", {"retro_hi_incl": True}),
                   ("retroactive gap > 0 s", {"retro_lo_incl": False})],
    "id": [("recency tie broken by atm_id", {"recency": ("created_at", "atm_id")}),
           ("needle ordered by created_at", {"needle": "created_desc"}),
           ("needle tie on lowest id", {"needle": "day_seq_asc"})],
    "event_type": [("Implemented not a closure", {"closure_events": ("Fixed", "Completed")}),
                   ("Updated/Obsolete counted as closures", {"closure_events": CLOSE + ("Updated", "Obsolete")})],
    "evidence_path": [("bulk key on the full evidence path", {"bulk_key": "fullpath_raw"}),
                      ("bulk on the FIRST closure", {"bulk_closure": "first"})],
    "type": [("one stratum for every type", {"type_strata": False})],
    "atm_id": [("recency by atm_id text", {"recency": ("atm_id",)})],
}
# Rule choices that are not a field: each MUST also change an outcome.
RULE_ALTS = [("retroactive before bulk (precedence)", {"precedence": "retro_first"}),
             ("retroactive on the FIRST closure", {"retro_closure": "first"}),
             ("bulk cluster size > threshold", {"bulk_ge": False}),
             ("window.from one day later", {"from_shift": 1}),
             ("window.from one day earlier", {"from_shift": -1})]


def discrimination(rows, types, as_of, days, threshold, ns, alts):
    """[(name, discriminates?)] -- an alt discriminates when it changes the
    outcome for at least one of the sample sizes `ns`."""
    base = [evaluate(rows, types, as_of, days, n, threshold) for n in ns]
    return [(name, [evaluate(rows, types, as_of, days, n, threshold, P) for n in ns] != base)
            for name, P in alts]


# ---- placement self-check (V4-2) ---------------------------------------------
def on_date_of(day_s, fmt):
    return {"date": day_s, "datetime": day_s + " 12:00:00", "iso_t": day_s + "T12:00:00",
            "iso_offset": day_s + "T23:30:00-05:00"}[fmt]


def window_placement(man):
    """Recompute every window cell's event row from its DECLARED dims (never
    from the builder's arithmetic) and compare. Returns (problems, n_in,
    n_out, in_by_dims) where in_by_dims maps atm_id -> expected membership."""
    as_of = man["as_of"]
    frm = (datetime.date.fromisoformat(as_of) - datetime.timedelta(days=man["window_days"])).isoformat()
    p, n_in, n_out, in_by_dims = [], 0, 0, {}
    for c in man["cells"]:
        if c["kind"] != "window":
            continue
        d = c["dims"]
        base = frm if d["bound"] == "from" else as_of
        dd = (datetime.date.fromisoformat(base) + datetime.timedelta(days=d["offset_days"])).isoformat()
        want_on = on_date_of(dd, d["on_date_format"])
        want_created = (datetime.date.fromisoformat(dd)
                        + datetime.timedelta(days=d["created_shift_days"])).isoformat() + " 10:00:00"
        want_ev = d["closure_event"] if d["event"] == "closure" else "Reopened"
        (it,) = c["items"]
        row = it["rows"][-1]
        got = (row["event_type"], row["on_date"], row["created_at"])
        if got != (want_ev, want_on, want_created):
            p.append("placement %s %s row=%s dims say %s" % (c["cell_id"], it["atm_id"], got,
                                                             (want_ev, want_on, want_created)))
        inside = (d["bound"] == "from" and d["offset_days"] >= 0) or (d["bound"] == "to" and d["offset_days"] <= 0)
        in_by_dims[it["atm_id"]] = inside
        n_in += inside
        n_out += not inside
    return p, n_in, n_out, in_by_dims
ORACLE_EOF

if [ ! -f "$TOOL" ] || [ ! -f "$BUILDER" ]; then
  bad "tool ($TOOL) or fixture builder ($BUILDER) missing -- nothing below can run"
  exit 1
fi

NEEDLE=(--needle-present-id ATM-953 --needle-fixed-event Fixed --needle-fixed-on-date 2026-07-01)
COMMON=(--as-of 2026-08-23 --window-days 60 --min-per-type 2 --bulk-threshold 3)

for mode in full cut; do
  if ! python3 "$BUILDER" "$TMP/$mode" "$mode" >"$TMP/build_$mode.err" 2>&1; then
    bad "fixture build ($mode) failed: $(cat "$TMP/build_$mode.err")"
    exit 1
  fi
  python3 "$TOOL" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/$mode/db.sqlite" \
    --out "$TMP/ss_$mode.json" >"$TMP/ss_$mode.err" 2>&1
  rc=$?
  if [ "$rc" != 0 ] || [ ! -f "$TMP/ss_$mode.json" ]; then
    bad "select_sample ($mode scenario) rc=$rc -- $(tail -3 "$TMP/ss_$mode.err")"
  fi
done

jhash() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$1" 2>/dev/null; }

echo "=== S1 (R5 B1): as-of freeze -- full DB and cut DB give the identical body ==="
if [ -f "$TMP/ss_full.json" ] && [ -f "$TMP/ss_cut.json" ]; then
  verdict="$(python3 - "$TMP/ss_full.json" "$TMP/ss_cut.json" <<'PY'
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
if a["body_hash"] == b["body_hash"]:
    print("SAME")
else:
    ia = sorted(i["item_id"] for i in a.get("items", []))
    ib = sorted(i["item_id"] for i in b.get("items", []))
    print("DIFF full=%s/%s cut=%s/%s" % (a["body_hash"][:8], ia, b["body_hash"][:8], ib))
PY
)"
  if [ "$verdict" = "SAME" ]; then
    ok "S1 full-vs-cut body_hash identical: rows dated after --as-of change nothing"
  else
    bad "S1 future rows leak into the as-of selection: $verdict"
  fi
else
  bad "S1 prerequisite outputs missing"
fi

echo "=== S2 (R5 B1/B2/M2 + V2-1 + V2-4): exact hand-derived selection, strata and listing ==="
if [ -f "$TMP/ss_full.json" ]; then
  verdict="$(python3 - "$TMP/ss_full.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
expected_strata = {
    "Bug": {"n_available": 7, "n_usable_available": 7, "n_selected": 2, "n_usable": 2,
            "n_listed_excluded": 0, "below_required": False},
    "Task": {"n_available": 7, "n_usable_available": 4, "n_selected": 2, "n_usable": 2,
             "n_listed_excluded": 3, "below_required": False},
    "Feature": {"n_available": 1, "n_usable_available": 0, "n_selected": 0, "n_usable": 0,
                "n_listed_excluded": 1, "below_required": True},
}
expected_items = {
    "ATM-277": ("Bug", "sampled-bug", False),
    "ATM-310": ("Bug", "sampled-bug", False),
    "ATM-300": ("Bug", "reopened-in-window", False),
    "ATM-800": ("Bug", "reopened-in-window", False),
    "ATM-503": ("Task", "sampled-task", False),
    "ATM-504": ("Task", "sampled-task", False),
    "ATM-601": ("Task", "listed-excluded-task", True),
    "ATM-602": ("Task", "listed-excluded-task", True),
    "ATM-603": ("Task", "listed-excluded-task", True),
    "ATM-700": ("Feature", "listed-excluded-feature", True),
}
problems = []
for t, exp in expected_strata.items():
    got = {k: d.get("strata", {}).get(t, {}).get(k) for k in exp}
    if got != exp:
        problems.append("strata[%s]=%s expected %s" % (t, got, exp))
got_items = {i["item_id"]: (i["type"], i["selection_reason"], i["excluded_from_duration"])
             for i in d.get("items", [])}
if got_items != expected_items:
    problems.append("items=%s expected %s" % (got_items, expected_items))
reasons = {i["item_id"]: i["exclusion_reason"] or "" for i in d.get("items", [])}
if "realbulk" not in reasons.get("ATM-602", "") or "retroactive" not in reasons.get("ATM-700", ""):
    problems.append("exclusion reasons wrong: %s" % reasons)
if d.get("reopened_in_window") != ["ATM-300", "ATM-800"]:
    problems.append("reopened_in_window=%s" % d.get("reopened_in_window"))
if d.get("selection_rule", {}).get("excluded_rows_count_toward_n") is not False:
    problems.append("selection_rule=%s (the recorded operator decision is not stated in the output)"
                    % d.get("selection_rule"))
print("PASS" if not problems else "; ".join(problems))
PY
)"
  if [ "$verdict" = "PASS" ]; then
    ok "S2 exclude-first then most-recent-2 USABLE per type; walked-past excluded rows listed; boundary rows (as-of day, window.from, negative gap, row-id/created_at disagreement) counted correctly"
  else
    bad "S2 $verdict"
  fi
fi

echo "=== S3 (R5 B1, reviewer experiment): live DB snapshot vs the same snapshot with every row after 2026-08-23 deleted ==="
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  sqlite3 -readonly "$DB" ".backup '$TMP/live_full.db'" 2>"$TMP/backup.err"
  cp "$TMP/live_full.db" "$TMP/live_cut.db" 2>/dev/null
  deleted="$(sqlite3 "$TMP/live_cut.db" "DELETE FROM item_history WHERE on_date > '2026-08-23'; SELECT changes();" 2>&1)"
  for v in full cut; do
    python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --db-path "$TMP/live_$v.db" \
      --out "$TMP/live_ss_$v.json" >"$TMP/live_ss_$v.err" 2>&1 || true
  done
  if [ -f "$TMP/live_ss_full.json" ] && [ -f "$TMP/live_ss_cut.json" ]; then
    h_full="$(jhash "$TMP/live_ss_full.json")"
    h_cut="$(jhash "$TMP/live_ss_cut.json")"
    case "$deleted" in
      ''|*[!0-9]*) bad "S3 could not count deleted rows: '$deleted'" ;;
      0) bad "S3 control: the live snapshot has NO rows after 2026-08-23, so this experiment proves nothing (needle failed)" ;;
      *) if [ "$h_full" = "$h_cut" ]; then
           ok "S3 live experiment: deleted $deleted future rows, selection body_hash unchanged (${h_full:0:8})"
         else
           bad "S3 live experiment: deleting $deleted future rows changed the selection (${h_full:0:8} vs ${h_cut:0:8})"
         fi ;;
    esac
  else
    bad "S3 live runs failed -- $(tail -2 "$TMP/live_ss_full.err" "$TMP/live_ss_cut.err" 2>/dev/null)"
  fi
else
  bad "S3 sqlite3 or live tracker DB unavailable -- cannot run the reviewer experiment"
fi

echo "=== S4 (R5 M10): --determinism-check writes --out (and the result equals a plain run) ==="
python3 "$TOOL" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
  --determinism-check --out "$TMP/dc.json" >"$TMP/dc.out" 2>&1
dc_rc=$?
if [ "$dc_rc" = 0 ] && [ -f "$TMP/dc.json" ] && [ -f "$TMP/ss_full.json" ] && \
   [ "$(jhash "$TMP/dc.json")" = "$(jhash "$TMP/ss_full.json")" ]; then
  ok "S4 --determinism-check rc=0 and wrote --out with the same body_hash as a plain run"
else
  bad "S4 --determinism-check rc=$dc_rc, --out present=$([ -f "$TMP/dc.json" ] && echo yes || echo no) -- $(tail -2 "$TMP/dc.out")"
fi

echo "=== S5 (V2-1, live): the per-type quota is filled with USABLE rows whenever they exist ==="
# Ground truth from the SAME tool with a quota no stratum can reach
# (--min-per-type 1000 => every candidate taken, n_usable = usable available);
# then the real N=5 run must take min(5, usable available) usable rows.
if [ -f "$TMP/live_full.db" ]; then
  python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --min-per-type 1000 --db-path "$TMP/live_full.db" \
    --out "$TMP/live_all.json" >"$TMP/live_all.err" 2>&1
  python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --min-per-type 5 --db-path "$TMP/live_full.db" \
    --out "$TMP/live_n5.json" >"$TMP/live_n5.err" 2>&1
  verdict="$(python3 - "$TMP/live_all.json" "$TMP/live_n5.json" <<'PY'
import json, sys
try:
    a, b = (json.load(open(p)) for p in sys.argv[1:3])
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
p, seen = [], []
for t in ("Bug", "Feature", "Task"):
    avail = a["strata"][t]["n_usable"]
    s = b["strata"][t]
    if s["n_usable_available"] != avail:
        p.append("%s n_usable_available=%s but the all-rows run found %s" % (t, s["n_usable_available"], avail))
    if s["n_usable"] != min(5, avail):
        p.append("%s n_usable=%s expected min(5, %s)" % (t, s["n_usable"], avail))
    if s["below_required"] != (min(5, avail) < 5):
        p.append("%s below_required=%s with %s usable available" % (t, s["below_required"], avail))
    seen.append("%s %s/%s" % (t, s["n_usable"], avail))
# control needle: the experiment must contain a stratum where the round-1 rule
# starved the quota (an excluded row among the most-recent rows) -- else it
# proves nothing about V2-1.
if not any(b["strata"][t]["n_listed_excluded"] > 0 and b["strata"][t]["n_usable"] == 5
           for t in ("Bug", "Feature", "Task")):
    p.append("control: no stratum both listed excluded rows and still filled 5 usable -- experiment inert")
print("PASS " + ", ".join(seen) if not p else "; ".join(p))
PY
)"
  case "$verdict" in
    PASS*) ok "S5 live as-of 2026-08-23: usable taken/available ${verdict#PASS }" ;;
    *) bad "S5 $verdict" ;;
  esac
else
  bad "S5 live snapshot unavailable"
fi

echo "=== S6 (V2-8): with no needle overrides, an as-of before the default needle's date derives the needle at the as-of ==="
python3 "$TOOL" --as-of 2026-07-20 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd.json" >"$TMP/nd.err" 2>&1
nd_rc=$?
python3 "$TOOL" --as-of 2026-08-23 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd_default.json" >"$TMP/nd_default.err" 2>&1
nd_default_rc=$?
nd_live_rc=skip
if [ -f "$TMP/live_full.db" ]; then
  cp "$TMP/live_full.db" "$TMP/live_0710.db"
  sqlite3 "$TMP/live_0710.db" "DELETE FROM item_history WHERE on_date > '2026-07-10';"
  python3 "$TOOL" --as-of 2026-07-10 --window-days 60 --db-path "$TMP/live_0710.db" \
    --out "$TMP/nd_live.json" >"$TMP/nd_live.err" 2>&1
  nd_live_rc=$?
fi
nd_src="$(python3 -c "
import json, sys
n = json.load(open(sys.argv[1]))['run_meta']['needle']
print('%s|%s|%s' % (n['source'], n['present_id'], n['present_on_date']))
" "$TMP/nd.json" 2>&1)"
IFS='|' read -r nd_source nd_id nd_date <<<"$nd_src"
if [ "$nd_rc" = 0 ] && [ "$nd_source" = "derived-at-as-of" ] && [ -n "$nd_id" ] && [[ "$nd_date" < "2026-07-21" ]] \
   && [ "$nd_default_rc" = 3 ] && grep -q 'NOT FOUND' "$TMP/nd_default.err" && [ "$nd_live_rc" = 0 ]; then
  ok "S6 as-of 07-20 derives the needle ($nd_id on $nd_date); as-of 08-23 keeps the default and still fails closed (exit 3) when that row is absent; live snapshot cut at 07-10 replays with defaults"
else
  bad "S6 rc=$nd_rc needle=$nd_src default_rc=$nd_default_rc live_rc=$nd_live_rc -- $(tail -2 "$TMP/nd.err") / $(tail -1 "$TMP/nd_live.err" 2>/dev/null)"
fi

echo "=== S7 (V2-2 class): the retroactive rule's one out-of-scope copy (closure/reopen_rate.py) agrees on a boundary corpus ==="
verdict="$(python3 - "$TOOL" "$RR_UNDER_TEST" <<'PY'
import importlib.util, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
ss, rr = load("ss_ut", sys.argv[1]), load("rr_ut", sys.argv[2])
def h(o, c):
    rows = []
    if o is not None:
        rows.append({"event_type": "Opened", "created_at": o})
    if c is not None:
        rows.append({"event_type": "Fixed", "created_at": c})
    return rows
corpus = [h("2026-08-01 10:00:00", "2026-08-01 10:00:00"), h("2026-08-01 10:00:00", "2026-08-01 10:00:59"),
          h("2026-08-01 10:00:00", "2026-08-01 10:01:00"), h("2026-08-01 10:00:00", "2026-08-01 09:59:00"),
          h("2026-08-01T10:00:00+05:00", "2026-08-01T05:00:30Z"), h(None, "2026-08-01 10:00:00"),
          h("2026-08-01 10:00:00", None), h("garbage", "2026-08-01 10:00:00")]
want = [True, True, False, False, True, False, False, False]
got_ss = [ss.detect_retroactive_registration(c) for c in corpus]
got_rr = [rr.is_retroactive_registration(c) for c in corpus]
print("PASS" if got_ss == want and got_rr == want else "select_sample=%s reopen_rate=%s want=%s" % (got_ss, got_rr, want))
PY
)"
if [ "$verdict" = "PASS" ]; then
  ok "S7 select_sample's rule and reopen_rate.py's copy agree on 8 boundary cases (gap 0, 59, 60, -60, offset-aware, missing rows, unparseable)"
else
  bad "S7 $verdict"
fi

echo "=== S8 (R5 B2): below_required is computed on USABLE rows -- a stratum with enough rows but none usable is below ==="
# --min-per-type 1: Feature has 1 row available (>= 1) but 0 usable (ATM-700
# is a retroactive registration) => below_required true; an available-count
# rule would say false. Bug/Task each take their single most recent usable row.
python3 "$TOOL" --as-of 2026-08-23 --window-days 60 --min-per-type 1 --bulk-threshold 3 "${NEEDLE[@]}" \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/ss_min1.json" >"$TMP/ss_min1.err" 2>&1
verdict="$(python3 -c "
import json, sys
st = json.load(open(sys.argv[1]))['strata']
print(' '.join('%s:%s/%s/%s' % (t, st[t]['n_available'], st[t]['n_usable'], st[t]['below_required'])
               for t in ('Bug', 'Feature', 'Task')))
" "$TMP/ss_min1.json" 2>&1)"
if [ "$verdict" = "Bug:7/1/False Feature:1/0/True Task:7/1/False" ]; then
  ok "S8 min 1: Feature 1 available / 0 usable -> below_required true (Bug, Task 1 usable each -> false)"
else
  bad "S8 got '$verdict', want 'Bug:7/1/False Feature:1/0/True Task:7/1/False'"
fi

echo "=== S9 (V3-1 -> V4-1 class, rounds 3-4): GENERATED boundary matrix -- every cell vs an independent oracle ==="
# Round 4 (V4-1/V4-2/V4-3): the matrix's DIMENSIONS are derived from the
# fields select_sample READS. The oracle module ($ORACLE_DIR/ss_oracle.py,
# written above; stdlib only, imports nothing from the tools) is parametrised:
# every field the tool's source reads (AST inventory: subscripts, .get(),
# identifiers in SQL literals, intersected with the tracker columns and the
# commit/review keys) must either be EXEMPT with a stated reason or have
# alternatives -- the rule with that field swapped for its sibling (on_date ->
# created_at, created_at/id -> another recency key, ...) -- that each CHANGE
# an outcome on the matrix. A field with no such alternative has no
# disagreement cell, and the check fails (the round-2..4 "missing cell ->
# missing cells -> missing dimension" class). Cell PLACEMENT is self-verified:
# every window cell's event row is recomputed from its declared dims and
# compared, and the in/out totals are asserted, not printed (V4-2). The tool
# is checked against the oracle at two sample sizes (1000 = take all, 2 = the
# recency walk) on the full and the as-of-cut DB.
MX="$TMP/mx"
mx_ok=1
for mode in matrix-full matrix-cut; do
  if ! python3 "$BUILDER" "$MX/$mode" "$mode" >"$TMP/mx_build_$mode.err" 2>&1; then
    bad "S9 matrix build ($mode) failed: $(tail -2 "$TMP/mx_build_$mode.err")"; mx_ok=0
  fi
done
if [ "$mx_ok" = 1 ]; then
  for n in 1000 2; do
    for mode in matrix-full matrix-cut; do
      python3 "$TOOL" --as-of 2026-05-20 --window-days 30 --min-per-type "$n" --bulk-threshold 3 \
        --db-path "$MX/$mode/db.sqlite" --out "$TMP/mx_ss_${mode}_$n.json" >"$TMP/mx_ss_${mode}_$n.err" 2>&1 \
        || bad "S9 select_sample on $mode N=$n rc=$? -- $(tail -2 "$TMP/mx_ss_${mode}_$n.err")"
    done
  done
  verdict="$(python3 - "$ORACLE_DIR" "$MX" "$TMP" "$TOOL" "$TMP/live_full.db" <<'PY'
import copy, glob, json, os, sys
sys.path.insert(0, sys.argv[1])
import ss_oracle as O
MX, T, TOOL, LIVE = sys.argv[2:6]

def load(p):
    try:
        return json.load(open(p))
    except Exception as e:
        print("missing output %s: %s" % (p, e))
        raise SystemExit

man = load(os.path.join(MX, "matrix-full", "manifest.json"))
AS_OF, DAYS, TH = man["as_of"], man["window_days"], man["bulk_threshold"]
rows, types = O.matrix_corpus(man)
problems = []

# -- 1. tool vs oracle: N in {1000, 2}, full and cut, whole outcome ------------
outcomes = {}
for n in (1000, 2):
    want = O.evaluate(rows, types, AS_OF, DAYS, n, TH)
    for mode in ("matrix-full", "matrix-cut"):
        doc = load(os.path.join(T, "mx_ss_%s_%d.json" % (mode, n)))
        outcomes[(mode, n)] = doc
        problems += O.diff(O.tool_outcome(doc), want, "%s N=%d" % (mode, n))
    if outcomes[("matrix-full", n)].get("body_hash") != outcomes[("matrix-cut", n)].get("body_hash"):
        problems.append("N=%d matrix full vs cut body_hash differ (future rows leak)" % n)

# -- 2. per-cell bookkeeping: every cell asserted, cell set independently known --
def assert_cells(cells, doc, n):
    got, want = O.tool_outcome(doc), O.evaluate(rows, types, AS_OF, DAYS, n, TH)
    asserted, p = set(), []
    for c in cells:
        cid = c["cell_id"]
        if cid in ("rule/needle_derived", "rule/needle_seq_vs_created"):
            if got["needle"] != want["needle"]:
                p.append("%s needle tool=%s oracle=%s" % (cid, got["needle"], want["needle"]))
            if cid == "rule/needle_seq_vs_created" and want["needle"][1] != c["items"][0]["atm_id"]:
                p.append("%s: the cell's late row is not the needle (%s) -- cell inert" % (cid, want["needle"]))
            asserted.add(cid)
        if not c["items"]:
            continue
        for it in c["items"]:
            i = it["atm_id"]
            if got["items"].get(i) != want["items"].get(i):
                p.append("%s %s tool=%s oracle=%s" % (cid, i, got["items"].get(i), want["items"].get(i)))
        asserted.add(cid)
    return asserted, p

def want_ids():
    w = {"window/%s/%s/%+d/%s/created%+d" % (e, b, o, f, s) for e in ("closure", "reopened")
         for b in ("from", "to") for o in (-1, 0, 1) for f in ("date", "datetime", "iso_t", "iso_offset")
         for s in (-1, 0, 1)}
    w |= {"commit/%s/%+ds/%s" % (k, o, z) for k in ("author", "committer") for o in (-1, 0, 1)
          for z in ("Z", "+05:00", "-04:00", "+05:30")}
    w |= {"review/%s/%+ds/%s" % (k, o, z) for k in ("end", "start") for o in (-1, 0, 1)
          for z in ("Z", "+05:00", "-04:00")} | {"review/straddle/%s" % z for z in ("Z", "+05:00", "-04:00")}
    w |= {"rule/" + r for r in ("retro_terminal_not_first", "retro_terminal_is_retro", "bulk_latest_shared",
                                "bulk_first_shared", "pop_retro_reopen_only", "pop_bulk_reopen_only",
                                "needle_derived", "precedence_bulk_and_retro", "bulk_key_raw_on_date",
                                "order_created_vs_seq", "needle_seq_vs_created", "event_noise",
                                "retro_gap_boundaries", "reopen_block_created_axis", "dedup_key_by_reason")}
    return w

def meta(cells, asserted):
    ids = [c["cell_id"] for c in cells]
    p = []
    if len(ids) != len(set(ids)):
        p.append("duplicate cell ids")
    if set(ids) != want_ids():
        p.append("manifest cells != expected matrix: missing %s extra %s"
                 % (sorted(want_ids() - set(ids))[:5], sorted(set(ids) - want_ids())[:5]))
    if set(ids) - asserted:
        p.append("cells with NO assertion: %s" % sorted(set(ids) - asserted)[:5])
    return p

for (mode, n), doc in sorted(outcomes.items()):
    a, p = assert_cells(man["cells"], doc, n)
    problems += ["%s N=%d: %s" % (mode, n, x) for x in p + meta(man["cells"], a)]

# -- 3. placement self-check (V4-2): recomputed from dims, totals ASSERTED ------
place, n_in, n_out, in_by_dims = O.window_placement(man)
problems += place
if (n_in, n_out) != (96, 48):
    problems.append("window cells in/out by dims = %d/%d, the matrix declares 96/48" % (n_in, n_out))
want_all = O.evaluate(rows, types, AS_OF, DAYS, 1000, TH)["items"]
for i, inside in in_by_dims.items():
    if (i in want_all) != inside:
        problems.append("window cell %s: oracle membership %s but its dims say %s" % (i, i in want_all, inside))
if sum(1 for c in man["cells"] for _ in c["items"]) != 219 or len(man["cells"]) != 204:
    problems.append("matrix size %d cells / %d items, expected 204 / 219"
                    % (len(man["cells"]), sum(1 for c in man["cells"] for _ in c["items"])))

# -- 4. field inventory: every field the tool reads has a disagreement axis ------
EXEMPT = {"by": "copied into the history dict, read by no select_sample rule",
          "reason": "copied into the history dict, read by no select_sample rule",
          "item_id": "the report's own output key (render_md)",
          "schema": "the report's own schema tag (write_report)"}
universe = O.db_columns([p for p in (os.path.join(MX, "matrix-full", "db.sqlite"), LIVE) if os.path.isfile(p)])
universe |= {k for c in man["cells"] for it in c["items"] for x in it["commits"] + it["rounds"] for k in x}
rr = sorted(glob.glob(os.path.join(MX, "matrix-full", "repo", "review_records", "*", "*.json")))
universe |= set(load(rr[0])) if rr else set()

def inventory_problems(read, field_alts, rule_alts, rws, tps):
    p = []
    for f in sorted(read):
        if f in EXEMPT:
            continue
        if f not in field_alts:
            p.append("field %r is read by the tool (lines %s) but has NO disagreement axis and no exemption"
                     % (f, sorted(read[f])[:4]))
    names = [(f, a) for f in sorted(read) if f in field_alts for a in field_alts[f]]
    names += [("rule", a) for a in rule_alts]
    res = O.discrimination(rws, tps, AS_OF, DAYS, TH, (1000, 2), [a for _, a in names])
    for (f, a), (nm, ok) in zip(names, res):
        if not ok:
            p.append("%s alternative %r changes NO outcome on the matrix -- no disagreement cell" % (f, nm))
    return p

read = O.fields_read(TOOL, universe)
problems += inventory_problems(read, O.FIELD_ALTS, O.RULE_ALTS, rows, types)
for must in ("on_date", "created_at", "id", "event_type", "evidence_path", "type"):
    if must not in read:
        problems.append("control: the inventory did not find %r in the tool -- the instrument is blind" % must)

# -- 5. controls: each check SEES its own failure mode --------------------------
ph = dict(read, zzz_phantom={1})
if not any("zzz_phantom" in x for x in inventory_problems(ph, O.FIELD_ALTS, [], rows, types)):
    problems.append("control: a field with no axis was not reported")
flat = copy.deepcopy(rows)   # the round-3 matrix: created_at always on the on_date day
for rs in flat.values():
    for r in rs:
        r["created_at"] = r["on_date"][:10] + " 10:00:00"
if not any("reopened window keyed on created_at" in x for x in
           inventory_problems({"created_at": {1}}, O.FIELD_ALTS, [], flat, types)):
    problems.append("control: a matrix without the created_at axis was not reported")
drift = copy.deepcopy(man)
for c in drift["cells"]:
    if c["kind"] == "window" and c["dims"]["bound"] == "from":
        r = c["items"][0]["rows"][-1]
        r["on_date"] = "2026-04-15" + r["on_date"][10:]   # the builder drifting window.from by 5 days
if not O.window_placement(drift)[0]:
    problems.append("control: placement self-check accepted a 5-day window.from drift")
bad_doc = dict(outcomes[("matrix-full", 1000)])
bad_doc["items"] = [dict(it, selection_reason="x") for it in bad_doc.get("items", [])]
if not assert_cells(man["cells"], bad_doc, 1000)[1]:
    problems.append("control: per-cell comparison accepted a corrupted report")
phantom = man["cells"] + [{"cell_id": "phantom/x", "kind": "phantom", "dims": {}, "items": []}]
if not any("NO assertion" in x for x in meta(phantom, assert_cells(phantom, outcomes[("matrix-full", 1000)], 1000)[0])):
    problems.append("control: meta-check did not report a cell with no assertion")
n_alts = sum(len(O.FIELD_ALTS[f]) for f in read if f in O.FIELD_ALTS) + len(O.RULE_ALTS)
print("PASS %d cells, %d items (%d in / %d out by dims); %d fields read (%d exempt), %d alternatives all discriminate"
      % (len(man["cells"]), len(rows), n_in, n_out, len(read), len(set(read) & set(EXEMPT)), n_alts)
      if not problems else " | ".join(problems[:12]) + (" | ... %d more" % (len(problems) - 12) if len(problems) > 12 else ""))
PY
)"
  case "$verdict" in
    PASS*) ok "S9 boundary matrix: ${verdict#PASS } -- tool == oracle at N=1000 and N=2, full and cut; placement and every control fire" ;;
    *) bad "S9 $verdict" ;;
  esac
fi

echo "=== S13 (V4-1/V4-3, round 4): REAL-DATA oracle pass -- live snapshot, 16 fixed as-of/window pairs ==="
# The same independent oracle over a sqlite3 .backup of docs/workable_items.db
# (taken in S3; the live DB is never opened for write). Real data already
# carries the dimensions a synthetic table can forget (11 Reopened rows written
# on a different day than their on_date; items both bulk and retroactive), so
# the selection must equal the oracle on every pair. Control: on the snapshot,
# the reopened-on-created_at and the retro-before-bulk alternatives each
# change at least one pair -- else this pass could not kill those mutants.
if [ -f "$TMP/live_full.db" ]; then
  s13=""
  for d in 2026-06-10 2026-07-10 2026-07-28 2026-08-10 2026-08-23 2026-09-20 2026-09-28 2026-10-08; do
    for w in 60 90; do
      python3 "$TOOL" --as-of "$d" --window-days "$w" --db-path "$TMP/live_full.db" \
        --out "$TMP/real_$d.$w.json" >"$TMP/real_$d.$w.err" 2>&1 || s13="$s13 [$d/$w rc=$?: $(tail -1 "$TMP/real_$d.$w.err")]"
    done
  done
  verdict="$(python3 - "$ORACLE_DIR" "$TMP" "$TMP/live_full.db" <<'PY'
import glob, json, os, sys
sys.path.insert(0, sys.argv[1])
import ss_oracle as O
T, DB = sys.argv[2], sys.argv[3]
rows, types = O.db_corpus(DB)
PAIRS = [(d, w) for d in ("2026-06-10", "2026-07-10", "2026-07-28", "2026-08-10", "2026-08-23", "2026-09-20",
                          "2026-09-28", "2026-10-08") for w in (60, 90)]
p, disc = [], {"reopened window keyed on created_at": 0, "retroactive before bulk (precedence)": 0}
alts = [("reopened window keyed on created_at", {"reopen_field": "created_at"}),
        ("retroactive before bulk (precedence)", {"precedence": "retro_first"})]
for d, w in PAIRS:
    f = os.path.join(T, "real_%s.%d.json" % (d, w))
    try:
        doc = json.load(open(f))
    except Exception as e:
        p.append("%s/%d no output (%s)" % (d, w, e)); continue
    p += O.diff(O.tool_outcome(doc), O.evaluate(rows, types, d, w, 5, 10), "%s/%d" % (d, w))
    for name, ok in O.discrimination(rows, types, d, w, 10, (5,), alts):
        disc[name] += ok
for name, k in disc.items():
    if k == 0:
        p.append("control: %r changes no live pair -- the real-data pass is inert for it" % name)
print("PASS %d pairs; discriminating pairs: %s" % (len(PAIRS), ", ".join("%s %d" % kv for kv in disc.items()))
      if not p else " | ".join(p[:8]))
PY
)"
  case "$s13|$verdict" in
    "|PASS"*) ok "S13 live snapshot: select_sample == oracle on ${verdict#PASS }" ;;
    *) bad "S13 runs:${s13:- ok} verdict: $verdict" ;;
  esac
else
  bad "S13 live snapshot unavailable"
fi

echo "=== S7b (V3-6, round 3): reopen_rate.py's window functions agree with select_sample's on the matrix ==="
# Every matrix item's history (full AND as-of cut) through both tools' own
# closed_in_window / reopened_in_window and retroactive rules. collect_baseline.
# py's SQL copies are measured too but only REPORTED (owned by another area:
# its raw `on_date BETWEEN` lacks the day rule -- a '# note' line, not a check).
if [ -f "$MX/matrix-full/manifest.json" ]; then
  verdict="$(python3 - "$TOOL" "$RR_UNDER_TEST" "$MX/matrix-full/manifest.json" <<'PY'
import datetime, importlib.util, json, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
ss, rr = load("ss_ut7", sys.argv[1]), load("rr_ut7", sys.argv[2])
man = json.load(open(sys.argv[3]))
AS_OF = man["as_of"]
FROM = (datetime.date.fromisoformat(AS_OF) - datetime.timedelta(days=man["window_days"])).isoformat()
div, n = [], 0
for c in man["cells"]:
    for it in c["items"]:
        for label, h in (("full", it["rows"]), ("cut", [r for r in it["rows"] if r["on_date"][:10] <= AS_OF])):
            n += 1
            a = (ss.closed_in_window(h, FROM, AS_OF), ss.reopened_in_window(h, {"from": FROM, "to": AS_OF}),
                 ss.detect_retroactive_registration(h))
            b = (rr.closed_in_window(h, FROM, AS_OF), rr.reopened_in_window(h, FROM, AS_OF),
                 rr.is_retroactive_registration(h))
            if a != b:
                div.append("%s %s %s select_sample=%s reopen_rate=%s" % (c["cell_id"], it["atm_id"], label, a, b))
print("PASS %d histories" % n if not div else "DIVERGE " + " | ".join(div))
PY
)"
  case "$verdict" in
    PASS*) ok "S7b reopen_rate closed/reopened-in-window + retroactive == select_sample on ${verdict#PASS } (every matrix cell, full and cut)" ;;
    *) bad "S7b $verdict" ;;
  esac
  cb_note="$(python3 - "$FC/cycle/collect_baseline.py" "$TOOL" "$MX/matrix-full/db.sqlite" <<'PY' 2>&1
import importlib.util, sqlite3, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
cb, ss = load("cb_ut7", sys.argv[1]), load("ss_ut7b", sys.argv[2])
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[3], uri=True)
out = []
for fn in ("db_closures_in_window", "db_reopened_in_window"):
    a = set(getattr(ss, fn)(conn, "2026-04-20", "2026-05-20"))
    b = set(getattr(cb, fn)(conn, "2026-04-20", "2026-05-20"))
    if a != b:
        out.append("%s: select_sample-only %s collect_baseline-only %s" % (fn, sorted(a - b), sorted(b - a)))
print("; ".join(out) or "no divergence")
PY
)"
  echo "# note S7b (not a check, collect_baseline.py is out of this area): $cb_note"
else
  bad "S7b matrix manifest unavailable"
fi

echo "=== S10 (V3-3): the recorded operator decision's OTHER setting (EXCLUDED_ROWS_COUNT_TOWARD_N = True) is positively specified ==="
# A VARIANT tree (not a mutant: this is the documented 'one constant away'
# alternative) is run through the real CLI on the hand-derived fixture.
# Expected (min 2): Bug unchanged {310, 277}; Task takes the most-recent 2 rows
# usable or not = {603, 602}, both bulk -> n_selected 2, n_usable 0, nothing
# listed, below_required true; Feature takes ATM-700 (retroactive) -> n_usable
# 0; ATM-601/503/504 are not in the sample; excluded rows carry
# excluded_from_duration and selection_reason sampled-*; the output states the
# rule it applied.
VAR_SRC="$(cd "$(dirname "$TOOL")/.." && pwd)"   # the tree under test (a mutant run builds its variant from the mutant)
VT="$TMP/variant_true/constitution/scripts/fastcycle"
mkdir -p "$VT" && cp -r "$VAR_SRC/lib" "$VAR_SRC/cycle" "$VAR_SRC/closure" "$VT/" 2>/dev/null
if python3 - "$VT/cycle/select_sample.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "EXCLUDED_ROWS_COUNT_TOWARD_N = False"
if t.count(old) != 1:
    raise SystemExit("anchor count %d" % t.count(old))
open(p, "w").write(t.replace(old, "EXCLUDED_ROWS_COUNT_TOWARD_N = True"))
PY
then
  python3 "$VT/cycle/select_sample.py" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
    --out "$TMP/ss_true.json" >"$TMP/ss_true.err" 2>&1
  verdict="$(python3 - "$TMP/ss_true.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no output: %s" % e); raise SystemExit
p = []
want_strata = {
    "Bug": {"n_available": 7, "n_usable_available": 7, "n_selected": 2, "n_usable": 2, "n_listed_excluded": 0, "below_required": False},
    "Task": {"n_available": 7, "n_usable_available": 4, "n_selected": 2, "n_usable": 0, "n_listed_excluded": 0, "below_required": True},
    "Feature": {"n_available": 1, "n_usable_available": 0, "n_selected": 1, "n_usable": 0, "n_listed_excluded": 0, "below_required": True}}
for t, w in want_strata.items():
    g = {k: d["strata"][t].get(k) for k in w}
    if g != w:
        p.append("strata[%s]=%s want %s" % (t, g, w))
want_items = {"ATM-277": ("sampled-bug", False), "ATM-310": ("sampled-bug", False),
              "ATM-300": ("reopened-in-window", False), "ATM-800": ("reopened-in-window", False),
              "ATM-602": ("sampled-task", True), "ATM-603": ("sampled-task", True),
              "ATM-700": ("sampled-feature", True)}
got = {i["item_id"]: (i["selection_reason"], i["excluded_from_duration"]) for i in d.get("items", [])}
if got != want_items:
    p.append("items=%s want %s" % (got, want_items))
if d.get("selection_rule", {}).get("excluded_rows_count_toward_n") is not True:
    p.append("selection_rule=%s" % d.get("selection_rule"))
print("PASS" if not p else " | ".join(p))
PY
)"
  if [ "$verdict" = PASS ]; then
    ok "S10 EXCLUDED_ROWS_COUNT_TOWARD_N=True: most-recent N rows usable or not; Task 2 selected / 0 usable / below_required; excluded rows sampled and flagged"
  else
    bad "S10 $verdict -- $(tail -2 "$TMP/ss_true.err")"
  fi
else
  bad "S10 could not build the True variant (anchor drifted)"
fi

echo "=== S11 (V3-4 + V4-4): a broken, missing or API-less sibling module is BLIND (exit 4), never exit 1 -- plain and --determinism-check ==="
# V4-4 (round 4): a sibling that LOADS but lacks the API (a renamed or removed
# function -- the realistic refactor-drift case) used to exit 1 with an
# AttributeError, colliding with C-001's determinism-mismatch code.
s11=""
for breakage in missing syntax apiless partial; do
  BT="$TMP/broken_$breakage/constitution/scripts/fastcycle"
  mkdir -p "$BT" && cp -r "$(cd "$(dirname "$TOOL")/.." && pwd)/lib" "$(cd "$(dirname "$TOOL")/.." && pwd)/cycle" "$BT/"
  case "$breakage" in
    missing) rm -f "${BT:?}/lib/fc_common.py" ;;
    syntax) printf 'def broken(:\n' > "$BT/lib/fc_common.py" ;;
    apiless) printf 'API_REMOVED = True\n' > "$BT/lib/fc_common.py" ;;
    partial) python3 -c "import sys; p=sys.argv[1]; t=open(p).read(); open(p,'w').write(t.replace('def body_hash_of(', 'def body_hash_of_renamed('))" "$BT/lib/fc_common.py" ;;
  esac
  rm -rf "${BT:?}/lib/__pycache__"
  for dc in "" --determinism-check; do
    rm -f "$TMP/s11.json"
    python3 "$BT/cycle/select_sample.py" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" $dc \
      --out "$TMP/s11.json" >"$TMP/s11.err" 2>&1
    rc=$?
    if [ "$rc" != 4 ] || [ -f "$TMP/s11.json" ] || ! grep -q 'BLIND' "$TMP/s11.err"; then
      s11="$s11 fc_common-$breakage${dc:+ $dc}: rc=$rc out=$([ -f "$TMP/s11.json" ] && echo yes || echo no) $(tail -1 "$TMP/s11.err")"
    fi
  done
done
if [ -z "$s11" ]; then
  ok "S11 fc_common.py missing / SyntaxError / no API / one function renamed: select_sample exits 4 with a BLIND message and writes no --out (plain and --determinism-check, 8 runs)"
else
  bad "S11$s11"
fi

echo "=== S12 (bound class, round 3): an --as-of EQUAL to the default needle's date keeps the default needle ==="
# The default row (ATM-953 Fixed 2026-07-28) is not in the fixture: at as-of
# 07-28 the default is NOT postdating (<=), so it is used and the run fails
# closed (exit 3, NOT FOUND); a strict '<' would derive a needle and exit 0.
python3 "$TOOL" --as-of 2026-07-28 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd_eq.json" >"$TMP/nd_eq.err" 2>&1
nd_eq_rc=$?
if [ "$nd_eq_rc" = 3 ] && grep -q 'NOT FOUND' "$TMP/nd_eq.err" && [ ! -f "$TMP/nd_eq.json" ]; then
  ok "S12 as-of 2026-07-28 (= default needle date) uses the default needle and fails closed (exit 3)"
else
  bad "S12 as-of = default needle date: rc=$nd_eq_rc -- $(tail -1 "$TMP/nd_eq.err")"
fi

echo "=== S14 (round 4): window_days 0 / negative and min_per_type 0 are usage errors (exit 2, nothing written) ==="
s14=""
for bad_args in "--window-days 0" "--window-days -1" "--window-days 30 --min-per-type 0"; do
  rm -f "$TMP/s14.json"
  # shellcheck disable=SC2086  # word-splitting of the flag pair is intended
  python3 "$TOOL" --as-of 2026-08-23 $bad_args "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
    --out "$TMP/s14.json" >"$TMP/s14.err" 2>&1
  rc=$?
  if [ "$rc" != 2 ] || [ -f "$TMP/s14.json" ]; then s14="$s14 [$bad_args: rc=$rc]"; fi
done
python3 "$TOOL" --as-of 2026-08-23 --window-days 1 "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
  --out "$TMP/s14_one.json" >"$TMP/s14_one.err" 2>&1 || s14="$s14 [--window-days 1 rc=$?]"
one="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['window'], sorted(i['item_id'] for i in d['items']))" "$TMP/s14_one.json" 2>&1)"
[ "$one" = "{'from': '2026-08-22', 'to': '2026-08-23'} ['ATM-310']" ] || s14="$s14 [--window-days 1 window/items: $one]"
if [ -z "$s14" ]; then
  ok "S14 --window-days 0/-1 and --min-per-type 0 exit 2 and write nothing; --window-days 1 = [08-22, 08-23] -> ATM-310 only"
else
  bad "S14$s14"
fi

# ---------------------------------------------------------------------------
# Paired mutations (§1.1). Each mutant is built in a COPY of lib/ closure/
# cycle/ under $TMP (V2-6: never inside the source tree -- the tool's sibling
# imports are __file__-relative, so the copy is self-contained), with ONE
# textual change; this whole suite is re-run against it and MUST exit non-zero.
# ---------------------------------------------------------------------------
if [ "${FC_R5_MUTANT:-0}" != 1 ]; then
  echo "=== paired mutations ==="
  # The mutant tree mirrors the repository layout under $TMP so the tools'
  # __file__-relative defaults (repo root = 4 levels up -> docs/
  # workable_items.db and git log) resolve to THIS repository through two
  # symlinks; a bare copy would read no DB at all, and every mutant would be
  # "killed" by an unreadable DB instead of by the mutation (a bluff kill).
  mk_mutant_tree() {  # $1 root dir; prints the fastcycle dir inside it
    local fcd="$1/constitution/scripts/fastcycle"
    mkdir -p "$fcd"
    cp -r "$FC/lib" "$FC/closure" "$FC/cycle" "$fcd/"
    ln -s "$ROOT/docs" "$1/docs"
    ln -s "$ROOT/.git" "$1/.git"
    echo "$fcd"
  }
  run_mutant() {  # name, file relative to $FC, python-literal old, python-literal new
    local name="$1" rel="$2" root="$TMP/mut_$1" tree
    tree="$(mk_mutant_tree "$root")"
    if ! python3 - "$tree/$rel" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("mutation anchor found %d times (need exactly 1): %r" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    then
      bad "mutation $name could not be applied (anchor drifted)"
      return
    fi
    if SELECT_SAMPLE_UNDER_TEST="$tree/cycle/select_sample.py" FC_R5_MUTANT=1 bash "$0" >"$TMP/mut_$name.out" 2>&1; then
      bad "mutation $name SURVIVED (suite still exits 0)"
    else
      ok "mutation $name killed ($(grep -c '^NOT ok' "$TMP/mut_$name.out") failing check(s))"
    fi
    rm -rf "$root"
  }
  SS=cycle/select_sample.py
  # R5 M2 (reviewer, re-anchored on the exclude-first walk): oldest-N instead of most-recent-N.
  run_mutant M2_oldest_n "$SS" 'for atm_id in reversed(ids):' 'for atm_id in ids:'
  # V2 new mutants (reviewer, verbatim effect).
  run_mutant SS_N1_asof_day_dropped "$SS" 'r["on_date"][:10] <= as_of]' 'r["on_date"][:10] < as_of]'
  run_mutant SS_N3_negative_gap_retroactive "$SS" 'return 0 <= gap < 60' 'return gap < 60'
  run_mutant SS_N4_recency_row_id_only "$SS" 'return (created_at, hist_id, atm_id)' 'return (hist_id, atm_id)'
  # Own: the recorded operator decision flipped (excluded rows consume the quota = round-1 V2-1 bug).
  run_mutant excluded_count_toward_n "$SS" 'EXCLUDED_ROWS_COUNT_TOWARD_N = False' 'EXCLUDED_ROWS_COUNT_TOWARD_N = True'
  # Own: the shared classifier bypassed (nothing ever excluded).
  run_mutant classifier_bypassed "$SS" '        exclusion_by_id[atm_id] = reason' '        exclusion_by_id[atm_id] = None'
  # Own: re-open the as-of leak by dropping the history cutoff.
  run_mutant asof_cutoff_dropped "$SS" 'return history_upto(rows, as_of)' 'return rows'
  # Own: B2 regression -- below_required on the available count.
  run_mutant b2_available "$SS" '"below_required": n_usable < min_per_type' '"below_required": n_available < min_per_type'
  # Own: lexicographic atm_id ranking (the N2 bug class).
  run_mutant atm_id_ranking "$SS" 'key=lambda i: closure_recency_key(history_by_id, i))' 'key=lambda i: i)'
  # Own: V2-8 regression -- the default needle used even when it postdates --as-of.
  run_mutant needle_never_derived "$SS" 'if default_date <= as_of:' 'if True:'
  # Round 3 reviewer mutations (V2_sampling.md round 3, verbatim diffs from the
  # reviewer's own mutant trees) -- the window-boundary / first-vs-latest /
  # classifier-population / derived-needle class, killed by S9 (the generated
  # boundary matrix + its independent oracle).
  run_mutant R3_closed_from_exclusive "$SS" 'return any(r["event_type"] in CLOSURE_EVENTS and frm <= (r.get("on_date") or "")[:10] <= to' 'return any(r["event_type"] in CLOSURE_EVENTS and frm < (r.get("on_date") or "")[:10] <= to'
  run_mutant R3_sql_discovery_from_strict "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND substr(ih.on_date, 1, 10) > ? AND substr(ih.on_date, 1, 10) <= ?",'
  run_mutant R3_reopen_to_exclusive "$SS" 'window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]' 'window["from"] <= (r.get("on_date") or "")[:10] < window["to"]'
  run_mutant R3_sql_reopen_to_strict "$SS" "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\"," "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) >= ? AND substr(ih.on_date, 1, 10) < ?\","
  run_mutant R3_retro_first_closure "$SS" 'closed = next((r for r in reversed(history) if r["event_type"] in CLOSURE_EVENTS), None)' 'closed = next((r for r in history if r["event_type"] in CLOSURE_EVENTS), None)'
  run_mutant R3_bulk_uses_first_closure "$SS" 'closure = latest_closure_event(hist)' 'closure = next((r for r in hist if r["event_type"] in CLOSURE_EVENTS), None)'
  run_mutant R3_exclusion_per_candidate_only_closed "$SS" 'exclusion_by_id = classify_exclusions(history_by_id, set(type_of), bulk_threshold)' 'exclusion_by_id = classify_exclusions(history_by_id, set().union(*by_type.values()) if by_type else set(), bulk_threshold); exclusion_by_id.update({i: None for i in type_of if i not in exclusion_by_id})'
  run_mutant R3_needle_derived_strict "$SS" "AND substr(on_date, 1, 10) <= ? \"" "AND substr(on_date, 1, 10) < ? \""
  # Own (round 3): the rest of the bound class, and the V3-4 guard.
  run_mutant R3_sql_closure_to_strict "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND substr(ih.on_date, 1, 10) >= ? AND substr(ih.on_date, 1, 10) < ?",'
  run_mutant R3_closed_to_exclusive "$SS" 'frm <= (r.get("on_date") or "")[:10] <= to' 'frm <= (r.get("on_date") or "")[:10] < to'
  run_mutant R3_sql_reopen_from_strict "$SS" "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\"," "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) > ? AND substr(ih.on_date, 1, 10) <= ?\","
  run_mutant R3_sql_closure_raw_on_date "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND ih.on_date BETWEEN ? AND ?",'
  run_mutant R3_sql_reopen_raw_on_date "$SS" "AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\",
        (frm, to),
    )
    return cur.fetchall()


def window_for" "AND ih.on_date BETWEEN ? AND ?\",
        (frm, to),
    )
    return cur.fetchall()


def window_for"
  run_mutant R3_cutoff_raw_on_date "$SS" 'r["on_date"][:10] <= as_of]' 'r["on_date"] <= as_of]'
  run_mutant R3_bulk_threshold_strict "$SS" 'if ekey is not None and len(members) >= bulk_threshold:' 'if ekey is not None and len(members) > bulk_threshold:'
  run_mutant R3_window_from_off_by_one "$SS" 'datetime.timedelta(days=window_days)).isoformat(),' 'datetime.timedelta(days=window_days - 1)).isoformat(),'
  run_mutant R3_needle_default_strict "$SS" 'if default_date <= as_of:' 'if default_date < as_of:'
  run_mutant R3_blind_guard_import_error_only "$SS" 'except Exception as _exc:  # noqa: BLE001 -- any load failure (ImportError, SyntaxError, AttributeError ...) is BLIND' 'except ImportError as _exc:  # mutant'
  # Round 4 reviewer mutations (docs/qa/t048_restart_round4_20261008/V2_sampling.md,
  # verbatim from the reviewer's runmuts.sh / bm/ trees) -- the missing-DIMENSION
  # class (V4-1, V4-3) killed by S9's derived-dimension matrix and S13's real-data
  # pass, and the V4-4 API-less sibling.
  run_mutant R4_reopen_window_on_created_at "$SS" 'window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]' 'window["from"] <= (r.get("created_at") or "")[:10] <= window["to"]'
  run_mutant R4_sql_reopen_on_created_at "$SS" "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\"," "\"WHERE ih.event_type = 'Reopened' AND substr(ih.created_at, 1, 10) BETWEEN ? AND ?\","
  run_mutant R4_window_on_created_at "$SS" 'frm <= (r.get("on_date") or "")[:10] <= to' 'frm <= (r.get("created_at") or "")[:10] <= to'
  run_mutant R4_retro_before_bulk "$SS" '        if atm_id in bulk_flagged:' '        if detect_retroactive_registration(history_by_id.get(atm_id, [])):
            reason = RETROACTIVE_REASON
        elif atm_id in bulk_flagged:'
  run_mutant R4_bulk_key_day "$SS" 'ekey = (os.path.dirname(closure["evidence_path"]), closure.get("on_date"))' 'ekey = (os.path.dirname(closure["evidence_path"]), (closure.get("on_date") or "")[:10])'
  run_mutant R4_retro_gap_le60 "$SS" 'return 0 <= gap < 60' 'return 0 <= gap <= 60'
  run_mutant R4_retro_gap_gt0 "$SS" 'return 0 <= gap < 60' 'return 0 < gap < 60'
  run_mutant R4_needle_tiebreak_asc "$SS" 'id DESC LIMIT 1' 'id ASC LIMIT 1'
  run_mutant R4_ss_blind_exit1 "$SS" '        sys.exit(4)
    raise' '        sys.exit(1)
    raise'
  run_mutant R4_sql_drop_implemented "$SS" "\"WHERE ih.event_type IN ('Fixed','Implemented','Completed') \"" "\"WHERE ih.event_type IN ('Fixed','Completed') \""
  # B3 (reviewer, verbatim): closure/reopen_rate.py's reopened_in_window keyed on created_at.
  run_mutant R4_B3_reopen_rate_on_created_at closure/reopen_rate.py 'r.get("event_type") == "Reopened" and frm <= _day(r.get("on_date")) <= to' 'r.get("event_type") == "Reopened" and frm <= _day(r.get("created_at")) <= to'
  # Own (round 4): the rest of the created_at / insert-order / day-shape class.
  run_mutant R4_cut_on_created_at "$SS" 'return [r for r in history if r.get("on_date") and r["on_date"][:10] <= as_of]' 'return [r for r in history if r.get("created_at") and r["created_at"][:10] <= as_of]'
  run_mutant R4_sql_closure_on_created_at "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND substr(ih.created_at, 1, 10) BETWEEN ? AND ?",'
  run_mutant R4_needle_on_created_at "$SS" 'ORDER BY substr(on_date, 1, 10) DESC, id DESC LIMIT 1' 'ORDER BY substr(on_date, 1, 10) DESC, created_at DESC LIMIT 1'
  run_mutant R4_recency_no_row_id "$SS" 'return (created_at, hist_id, atm_id)' 'return (created_at, atm_id)'
  run_mutant R4_reopen_day_utc "$SS" 'window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]' 'window["from"] <= (parse_iso(r["on_date"]).astimezone(datetime.timezone.utc).date().isoformat() if "T" in (r.get("on_date") or "") else (r.get("on_date") or "")[:10]) <= window["to"]'
  run_mutant R4_bulk_full_evidence_path "$SS" 'ekey = (os.path.dirname(closure["evidence_path"]), closure.get("on_date"))' 'ekey = (closure["evidence_path"], closure.get("on_date"))'
  run_mutant R4_window_days_zero_allowed "$SS" 'if args.window_days <= 0:' 'if args.window_days < 0:'
  run_mutant R4_min_per_type_zero_allowed "$SS" 'if args.min_per_type <= 0:' 'if args.min_per_type < 0:'
  run_mutant R4_api_attr_resolved_lazily "$SS" '    body_hash_of = fc_common.body_hash_of  # V4-4' '    body_hash_of = getattr(fc_common, "body_hash_of", None)  # V4-4'

  # Builder-drift paired mutations (V4-2, reviewer B1 verbatim + own): a drifted
  # COPY of the matrix builder, alone and with the bound mutant whose cell it
  # moves -- the placement self-check / the derived-dimension check must fail.
  run_builder_mutant() {  # name, builder old, builder new [, tool file rel, tool old, tool new]
    local name="$1" root="$TMP/bmut_$1" tree="" bld
    mkdir -p "$root"
    bld="$root/build_asof_scenario.py"
    cp "$BUILDER" "$bld"
    if ! python3 - "$bld" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("builder mutation anchor found %d times: %r" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    then
      bad "builder mutation $name could not be applied (anchor drifted)"; return
    fi
    local tool="$TOOL"
    if [ $# -ge 6 ]; then
      tree="$(mk_mutant_tree "$root/tree")"
      if ! python3 - "$tree/$4" "$5" "$6" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("anchor found %d times: %r" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
      then
        bad "builder mutation $name: tool anchor drifted"; return
      fi
      tool="$tree/cycle/select_sample.py"
    fi
    if ASOF_BUILDER_UNDER_TEST="$bld" SELECT_SAMPLE_UNDER_TEST="$tool" FC_R5_MUTANT=1 bash "$0" >"$TMP/bmut_$name.out" 2>&1; then
      bad "builder mutation $name SURVIVED (suite still exits 0)"
    else
      ok "builder mutation $name killed ($(grep -c '^NOT ok' "$TMP/bmut_$name.out") failing check(s))"
    fi
    rm -rf "$root"
  }
  run_builder_mutant B1_from_drift_alone '    from_day = _iso_day(M_AS_OF, -M_WINDOW_DAYS)' '    from_day = _iso_day(M_AS_OF, -M_WINDOW_DAYS - 5)'
  run_builder_mutant B1_from_drift_plus_closed_from_exclusive '    from_day = _iso_day(M_AS_OF, -M_WINDOW_DAYS)' '    from_day = _iso_day(M_AS_OF, -M_WINDOW_DAYS - 5)' \
    "$SS" 'return any(r["event_type"] in CLOSURE_EVENTS and frm <= (r.get("on_date") or "")[:10] <= to' 'return any(r["event_type"] in CLOSURE_EVENTS and frm < (r.get("on_date") or "")[:10] <= to'
  run_builder_mutant B_created_axis_collapsed_plus_reopen_on_created_at '                        created = _iso_day(day, shift) + " 10:00:00"' '                        created = day + " 10:00:00"' \
    "$SS" 'window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]' 'window["from"] <= (r.get("created_at") or "")[:10] <= window["to"]'
fi

exit $fail
