#!/usr/bin/env python3
"""collect_baseline.py - T045 baseline collection + freeze orchestrator
(spec-004 "fast-dev-cycles", User Story 1, T045; plan.md T-A10; research.md
DEC-03, DEC-36; contracts/common-conventions.md C-001..C-007). Guarded by
constitution/scripts/fastcycle/tests/test_collect_baseline_red.sh (added T048
restart round 1, R6-F14: until then this module had no test at all, which is
how F9/F12/F21/F22 below stayed open).

Purpose: run the DEC-03 stratified sample selection, freeze every sample
item's commit/tree (all items, cheap, read-only git log), run the DEC-36
gate-window replay via baseline_replay.sh on an explicitly-documented,
REDUCED subset (see REDUCED-SCOPE DECISION below -- the full >=10 cold +
>=10 warm protocol on every duration-eligible item was measured infeasible
for a single dispatch, ~19 min/run x 9 items x 20 runs = ~57h), compute the
reopen baseline with matched denominators (same window, same universe, for
both numerator (Reopened) and denominator (Fixed/Implemented/Completed)),
and report the token baseline honestly from RECORDED usage (which is
UNMEASURED for every 2026-09-29 sample item -- see TOKEN BASELINE below),
freezing the whole assembly to a single 'baseline/v1' doc under
qa-results/fastcycle/baseline/<freeze-id>/baseline.json (untracked evidence,
S11.4.11; a curated summary is committed as baseline.md per this tool's own
--md output).

=============================================================================
REDUCED-SCOPE DECISION (S11.4.6 -- documented per task instruction, never
silently truncated)
=============================================================================
DEC-36's own text: "replaying each sample change's gate phase... >=10 times
before and >=10 times after". Measured directly against THIS repo before
choosing a reduced number: a live, ad hoc `pre_build_verification.sh` run on
2026-09-28 (qa-results/fastcycle/t029_full_20260928T124322Z/
prebuild_sections.tsv, 183 sections) spans 1133.78s = 18.9 minutes wall-clock
from its first section's start_ns to its last section's end_ns. The DEC-03
sample as of 2026-09-29 (90-day window, min-per-type=5) has 20 items, of
which 9 are NOT excluded_from_duration (bulk-import/retroactive rows are
"listed... but excluded from duration statistics" per DEC-03's own text,
reused verbatim from select_sample.py's own excluded_from_duration flag):
Bug=5 (ATM-277/627/799/895/953), Task=3 (ATM-610/611/SPK-609),
Feature=1 (ATM-899). A literal >=10 cold + >=10 warm run of the ~19-minute
gate suite across all 9 duration-eligible items costs 9 items * 20 runs *
~19 min ~= 57 HOURS of pure sequential wall-clock -- infeasible for a single
subagent dispatch (and a real host-safety concern under S12.6/S11.4.225 to
monopolise a shared 64-core host for that long without explicit operator
authorisation for a run of that scale).

This tool's own DEFAULT is therefore --cold-runs 1 --warm-runs 1 (n=1 per
phase, per item) across ALL 9 duration-eligible items -- 9 items * 2 runs *
~19 min ~= 342 minutes ~= 5.7 hours, bounded and completable within one
extended background dispatch (S11.4.89: backgrounded, polled). This is a
REAL, DOCUMENTED, HONEST reduction from DEC-36's >=10/>=10 mandate, not a
silent truncation (S11.4.6/DEC-03's own "never silently dropped" language):
every emitted per-type median is labelled with its true n (runs actually
executed, pooled across the items of that type), the >=10/>=10-compliant
full run's real extrapolated cost is recorded in this doc's own
`full_protocol_note` field, and the gap is tracked as a follow-up (recorded
in this task's own tasks.md evidence block, never silently absorbed as full
DEC-36 compliance). A caller wanting a different (larger or smaller) run
count passes --cold-runs/--warm-runs explicitly; this tool never invents a
number the caller did not ask for.

Per-type medians are computed by POOLING every RAW per-run duration_ms OF A
PASS RUN (T048 restart round 1, R6-F9: a FAIL may be a crash part-way -- the
F9 forensic in baseline_replay.sh records 14 runs that all crashed with exit 2
after 4-263 s, and the 60 s plausibility floor below cannot tell such a crash
from a completion; UNMEASURED/HARNESS_ERROR runs never completed at all; the
excluded runs are counted per type as n_excluded_non_pass, never hidden)
across every replayed item of that type (cold and warm kept separate) and
taking ONE median over the pooled set -- a design judgment call (DEC-36's
own text does not spell out item-median-then-aggregate vs pooled-raw;
pooled-raw makes better use of the few real data points this reduced
protocol can afford, and generalises cleanly to n>1 without a fragile
median-of-medians step) -- documented here, never invented silently.

=============================================================================
TOKEN BASELINE (S11.4.6 -- measured, not guessed)
=============================================================================
Plan text: "two runs per sample item from recorded usage where transcripts
exist; otherwise UNMEASURED... plus one stated fresh re-execution of a
representative item". Measured directly 2026-09-29: T038's
transcript_ingest.py keys item attribution on an `item=<ATM-nnnn>` token in
an Agent/Task dispatch's own `description` field (the SAME convention T036's
dispatch_stamp.sh established) -- and that convention was wired into
scripts/hooks/agent_registry_writer.sh only at T037, itself LATER than every
one of these 20 sample items' own historical (Bug/Task/Feature) work. A
direct grep of the FULL shared transcript corpus
(~/.claude-shared/projects/-mnt-track1-atmosphere-t1/, the single canonical
store every claude1..5 alias project dir symlinks to -- confirmed via
`readlink -f` + matching inode, 2026-09-29) for `item=(<any of the 20 sample
IDs>)` returned ZERO matches. This tool therefore reports every sample
item's recorded-usage token baseline as UNMEASURED with the instrument
named (the item=-stamp convention postdates the item's own historical
work), per the plan's own explicit fallback -- never a fabricated or
estimated figure. The "one stated fresh re-execution of a representative
sample item" is a SEPARATE, one-time manual step (a real Agent-tool dispatch
carrying `item=<ID>` in its own description, ingested via
transcript_ingest.py after it completes) that this tool cannot perform on
its own (it has no Agent-dispatch capability) -- its result is folded in
via --fresh-execution-json after the fact (see --help), never left as a
silent gap in the frozen doc: absent --fresh-execution-json, the field is
written as {"status": "NOT_YET_RECORDED", ...} naming the exact follow-up
action, never silently omitted.

=============================================================================
REOPEN BASELINE, matched denominators (S11.4.6; research.md U-29: "the raw
ratio is not a rate")
=============================================================================
Per type: reopen_rate = |items closed (Fixed/Implemented/Completed) in
[as_of - window_days, as_of] AND reopened LATER within that same window| /
|items closed in that window| -- the numerator is a SUBSET of the denominator,
so the rate is a true fraction in [0, 1]. T048 restart round 1 (R6-F22): the
numerator used to be every item reopened in the window, including items whose
closure lay BEFORE the window (and so were never in the denominator); the rate
could exceed 1 while the doc claimed matched_denominator=true. The raw count of
items reopened in the window regardless of when they closed is still reported
(reopened_in_window_any). Same window, same universe, for both numerator and
denominator (a design
judgment call this task's own text does not spell out numerically; this is
the reading research.md U-29 and DEC-36's own "matched denominators" phrase
most directly support: an UNMATCHED reading would divide a windowed
numerator by an all-time denominator or vice versa, which is exactly the
"raw ratio is not a rate" mistake U-29 warns against). Reuses
select_sample.py's own already-reviewed db_closures_in_window /
db_reopened_in_window query shapes verbatim (S11.4.227 -- no divergent
re-derivation of a settled pattern) for the denominator; the matched numerator
is computed from the same item_history rows ordered by (on_date, id). A type
with zero closures in the
window reports its rate as UNMEASURED (division by zero is a real "no
denominator" condition, never coerced to 0 or 1, S11.4.201(6)).

Dependencies: bash (baseline_replay.sh's own subprocess), python3 (stdlib
only), git, sqlite3 (via python3's built-in sqlite3 module -- same
open_db_readonly access pattern as select_sample.py).
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

_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA = "fastcycle-baseline/v1"
# CRITICAL FIX (S11.4.4/S11.4.102/S11.4.201/S11.4.273, discovered live 2026-09-29
# on the very first real replayed item, ATM-277, BEFORE any invalid data was
# accepted): the script is git-tracked at mode 100644 (no +x bit; confirmed
# identical in the live tree AND in every sample item's frozen commit tree via
# `git ls-tree`) -- this project's OWN canonical invocation convention (this
# project's CLAUDE.md, "Pre-build verification" section) is
# `bash device/rockchip/rk3588/tests/pre_build_verification.sh`, never a
# direct exec of the bare path. A bare-path --gate-cmd word-splits to a
# single-token argv whose argv[0] is a non-executable-but-existing file --
# the shell reports exit 126 (EACCES) in single-digit MILLISECONDS, a
# fabricated "gate ran and FAILed" verdict that never actually invoked the
# ~19-minute gate suite at all. Caught because this module's own control
# discipline (S11.4.6/S11.4.273) treats every real-looking number as
# suspect until cross-checked: a 6ms "gate run" duration for a script whose
# OWN measured wall-clock (this module's MEASURED_PER_RUN_S) is ~1134s is a
# four-orders-of-magnitude discrepancy that must never be silently accepted
# as valid replay data.
DEFAULT_GATE_CMD = "bash device/rockchip/rk3588/tests/pre_build_verification.sh"
REPLAY_FULL_RUNS = 10  # DEC-36: >=10 cold and >=10 warm per item
DEFAULT_COLD_RUNS = 1
DEFAULT_WARM_RUNS = 1
MEASURED_PER_RUN_S = 1133.78  # 2026-09-28 t029_full ad hoc measurement, see module docstring


def default_repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", ".."))


def atomic_write_json(doc, out_path):
    out_dir = os.path.dirname(os.path.abspath(out_path))
    os.makedirs(out_dir, exist_ok=True)
    data = (canon(doc) + "\n").encode("utf-8")
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".collect_baseline.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def child_env():
    """Environment for every child tool. T048 restart round 1 (R6-F12): FC_OUT is
    the fc_common.py determinism-check redirect for ONE command's own --out; if
    this script runs under it, a child that honours FC_OUT (select_sample.py,
    baseline_replay.sh) would write its document there instead of the path this
    script passed, and every freeze/replay was then recorded as UNMEASURED with
    exit 0. It is removed for the children."""
    env = dict(os.environ)
    env.pop("FC_OUT", None)
    return env


def run_select_sample(select_sample_bin, as_of, window_days, min_per_type, db_path, repo_root, out_json, out_md):
    cmd = [
        sys.executable, select_sample_bin,
        "--as-of", as_of, "--window-days", str(window_days),
        "--min-per-type", str(min_per_type),
        "--db-path", db_path, "--repo-root", repo_root,
        "--out", out_json, "--md", out_md,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, env=child_env())
    if proc.returncode != 0:
        print("collect_baseline: select_sample.py failed rc=%d\n%s" % (proc.returncode, proc.stderr), file=sys.stderr)
        return None
    with open(out_json) as fh:
        return json.load(fh)


def run_freeze(baseline_replay_bin, item_id, repo_root, db_path, out_path):
    """Returns the freeze doc. A harness failure (non-zero rc, no doc, or a doc
    whose commit was resolved without a tree) is marked harness_error=True with
    the reason -- never confused with an honest 'no subject match' UNMEASURED
    (T048 restart round 1, R6-F3/F12 class)."""
    cmd = [baseline_replay_bin, "freeze", "--item", item_id, "--repo-root", repo_root,
           "--db-path", db_path, "--out", out_path]
    proc = subprocess.run(cmd, capture_output=True, text=True, env=child_env())
    if proc.returncode != 0 or not os.path.isfile(out_path):
        return {"item_id": item_id, "commit": "UNMEASURED", "tree": "UNMEASURED", "harness_error": True,
                "reason": "freeze harness error rc=%d: %s" % (proc.returncode, proc.stderr.strip()[-1000:]),
                "freeze_harness_rc": proc.returncode}
    with open(out_path) as fh:
        doc = json.load(fh)
    commit, tree = doc.get("commit"), doc.get("tree")
    if commit and commit != "UNMEASURED" and (not tree or tree == "UNMEASURED"):
        doc["harness_error"] = True
        doc["reason"] = "freeze harness error: commit %s resolved but its tree did not" % commit
    else:
        doc["harness_error"] = False
        doc["reason"] = (doc.get("missing_instrument") or "") if commit == "UNMEASURED" else ""
    return doc


def run_replay(baseline_replay_bin, commit, tree, gate_cmd, cold_runs, warm_runs, repo_root, worktree_root,
               timeout_s, out_path, min_free_kb=None):
    cmd = [baseline_replay_bin, "replay", "--commit", commit, "--tree", tree,
           "--gate-cmd", gate_cmd, "--cold-runs", str(cold_runs), "--warm-runs", str(warm_runs),
           "--repo-root", repo_root, "--out", out_path]
    if worktree_root:
        cmd += ["--worktree-root", worktree_root]
    if timeout_s:
        cmd += ["--timeout-s", str(timeout_s)]
    if min_free_kb is not None:
        cmd += ["--min-free-kb", str(min_free_kb)]
    # A single replay run can genuinely take hours (cold_runs+warm_runs *
    # ~19 min each); no subprocess-level timeout is imposed here beyond
    # baseline_replay.sh's own --timeout-s PER GATE INVOCATION -- an
    # overall Python-side timeout would just re-introduce the exact
    # "silent truncation" this module's whole design exists to avoid.
    proc = subprocess.run(cmd, capture_output=True, text=True, env=child_env())
    if proc.returncode != 0 or not os.path.isfile(out_path):
        # baseline_replay.sh exit 4 = BLIND (worktree/submodule failure, or a gate
        # that could not even be started -- HARNESS_ERROR). Any non-zero exit
        # means this item was NOT measured.
        return {"skipped": True, "harness_error": True, "skip_reason": "replay harness error rc=%d: %s" % (
            proc.returncode, proc.stderr.strip()[-2000:])}
    with open(out_path) as fh:
        doc = json.load(fh)
    doc["skipped"] = False
    return doc


# --- reopen baseline, reused verbatim from select_sample.py's own already-reviewed query shape ---
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


def db_reopened_after_closure_in_window(conn, frm, to):
    """Items with a closure event in [frm, to] followed (in (on_date, id) order)
    by a Reopened event that is also in [frm, to] -- the numerator matched to the
    db_closures_in_window denominator (R6-F22)."""
    cur = conn.execute(
        "SELECT ih.atm_id, i.type, ih.event_type FROM item_history ih "
        "JOIN items i ON i.atm_id = ih.atm_id "
        "WHERE ih.event_type IN ('Fixed','Implemented','Completed','Reopened') "
        "AND ih.on_date BETWEEN ? AND ? ORDER BY ih.atm_id, ih.on_date, ih.id",
        (frm, to),
    )
    closed_seen, out = set(), set()
    for atm_id, itype, ev in cur.fetchall():
        if ev == "Reopened":
            if atm_id in closed_seen:
                out.add((atm_id, itype))
        else:
            closed_seen.add(atm_id)
    return sorted(out)


def reopen_baseline(db_path, as_of, window_days):
    conn = open_db_readonly(db_path)
    if conn is None:
        return {"status": "UNMEASURED", "reason": "tracker DB unreadable at %s" % db_path}
    to_date = datetime.date.fromisoformat(as_of)
    frm_date = to_date - datetime.timedelta(days=window_days)
    frm, to = frm_date.isoformat(), to_date.isoformat()
    closures = db_closures_in_window(conn, frm, to)
    reopens_any = db_reopened_in_window(conn, frm, to)
    matched = db_reopened_after_closure_in_window(conn, frm, to)
    conn.close()
    from collections import Counter
    closures_by_type = Counter(t for _id, t in closures)
    any_by_type = Counter(t for _id, t in reopens_any)
    matched_by_type = Counter(t for _id, t in matched)
    out = {"window": {"from": frm, "to": to, "days": window_days}, "by_type": {}, "matched_denominator": True,
           "numerator_definition": "closed in the window AND reopened later within the same window"}
    for itype in ("Bug", "Feature", "Task"):
        n_closed = closures_by_type.get(itype, 0)
        n_reopened = matched_by_type.get(itype, 0)
        if n_closed == 0:
            rate = "UNMEASURED"
            reason = "zero closures of type %s in the window -- no denominator" % itype
        else:
            rate = round(n_reopened / n_closed, 6)
            reason = None
        out["by_type"][itype] = {
            "closed_in_window": n_closed, "reopened_in_window": n_reopened,
            "reopened_in_window_any": any_by_type.get(itype, 0),
            "reopen_rate": rate, "reason": reason,
        }
    total_closed = sum(closures_by_type.values())
    total_reopened = sum(matched_by_type.values())
    out["overall"] = {
        "closed_in_window": total_closed, "reopened_in_window": total_reopened,
        "reopened_in_window_any": sum(any_by_type.values()),
        "reopen_rate": round(total_reopened / total_closed, 6) if total_closed else "UNMEASURED",
    }
    return out


def token_baseline(sample_items, fresh_execution_json):
    per_item = []
    for it in sample_items:
        per_item.append({
            "item_id": it["item_id"], "type": it["type"],
            "recorded_usage_runs": "UNMEASURED",
            "reason": ("item=<ATM-nnnn> dispatch-stamp convention (T036/T037) postdates this item's "
                       "historical work; zero attributable transcript records found by direct corpus "
                       "search of ~/.claude-shared/projects/-mnt-track1-atmosphere-t1/ (2026-09-29)"),
        })
    if fresh_execution_json and os.path.isfile(fresh_execution_json):
        with open(fresh_execution_json) as fh:
            fresh = json.load(fh)
    else:
        fresh = {
            "status": "NOT_YET_RECORDED",
            "reason": ("plan.md T-A10's fallback ('a fresh re-execution of a representative sample item "
                       "is recorded instead') requires a real Agent-tool dispatch carrying item=<ID> in "
                       "its own description, which this script cannot itself perform; run one manually, "
                       "ingest its transcript via transcript_ingest.py, then re-invoke this script with "
                       "--fresh-execution-json pointing at the recorded result"),
        }
    return {"per_item": per_item, "fresh_reexecution": fresh}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--as-of", required=True)
    ap.add_argument("--window-days", type=int, default=90)
    ap.add_argument("--min-per-type", type=int, default=5)
    ap.add_argument("--repo-root", default=default_repo_root())
    ap.add_argument("--db-path")
    ap.add_argument("--out-dir", required=True, help="qa-results/fastcycle/baseline/<freeze-id>/")
    ap.add_argument("--gate-cmd", default=DEFAULT_GATE_CMD)
    ap.add_argument("--cold-runs", type=int, default=DEFAULT_COLD_RUNS)
    ap.add_argument("--warm-runs", type=int, default=DEFAULT_WARM_RUNS)
    ap.add_argument("--replay-item-ids", default=None,
                     help="comma-separated item ids to gate-replay; default = every "
                          "duration-eligible (excluded_from_duration==false) sample item")
    ap.add_argument("--skip-gate-replay", action="store_true",
                     help="freeze + reopen + token baseline only, no replay (fast dry run)")
    ap.add_argument("--worktree-root", default=None)
    ap.add_argument("--timeout-s", type=int, default=1800)
    ap.add_argument("--min-free-kb", type=int, default=None,
                     help="passed through to baseline_replay.sh replay (default: its own floor, sized "
                          "for a full checkout of this project)")
    ap.add_argument("--plausible-floor-ms", type=int, default=60000,
                     help="a run duration below this is EXCLUDED from per-type medians and reported "
                          "as implausible rather than silently pooled (default 60000ms = 1 min, an "
                          "order of magnitude below the measured ~1134s real gate-suite run)")
    ap.add_argument("--fresh-execution-json", default=None)
    ap.add_argument("--select-sample-bin", default=None)
    ap.add_argument("--baseline-replay-bin", default=None)
    a = ap.parse_args(argv)
    # T048 restart round 1 (R6 class A, absence read as a valid result): a
    # --fresh-execution-json path that does not exist used to be recorded silently
    # as NOT_YET_RECORDED, hiding a typo'd path behind an honest-looking status.
    if a.fresh_execution_json and not os.path.isfile(a.fresh_execution_json):
        print("collect_baseline: --fresh-execution-json file not found: %s" % a.fresh_execution_json,
              file=sys.stderr)
        return 2

    repo_root = os.path.abspath(a.repo_root)
    db_path = a.db_path or os.path.join(repo_root, "docs", "workable_items.db")
    fc_dir = os.path.join(repo_root, "constitution", "scripts", "fastcycle")
    select_sample_bin = a.select_sample_bin or os.path.join(fc_dir, "cycle", "select_sample.py")
    baseline_replay_bin = a.baseline_replay_bin or os.path.join(fc_dir, "cycle", "baseline_replay.sh")

    os.makedirs(a.out_dir, exist_ok=True)
    sample_json_path = os.path.join(a.out_dir, "sample.json")
    sample_md_path = os.path.join(a.out_dir, "sample.md")
    sample = run_select_sample(select_sample_bin, a.as_of, a.window_days, a.min_per_type,
                                db_path, repo_root, sample_json_path, sample_md_path)
    if sample is None:
        return 4
    items = sample.get("items", [])
    if sample.get("state") != "OK" or not items:
        # Recorded in the doc (sample.state) and said aloud: a baseline over zero
        # items is not silently presented as a measured one.
        print("collect_baseline: WARNING: the sample has state=%r with %d item(s) -- the baseline below "
              "measures nothing" % (sample.get("state"), len(items)), file=sys.stderr)

    # --- freeze every item (cheap, always full DEC-03 compliance) ---
    freeze_dir = os.path.join(a.out_dir, "freeze")
    os.makedirs(freeze_dir, exist_ok=True)
    freezes = {}
    harness_errors = []
    for it in items:
        iid = it["item_id"]
        fpath = os.path.join(freeze_dir, "%s.json" % iid)
        freezes[iid] = run_freeze(baseline_replay_bin, iid, repo_root, db_path, fpath)
        if freezes[iid].get("harness_error"):
            harness_errors.append({"item_id": iid, "stage": "freeze", "reason": freezes[iid]["reason"]})

    # --- gate-window replay, reduced-scope subset (see module docstring) ---
    eligible_ids = [it["item_id"] for it in items if not it.get("excluded_from_duration")]
    if a.replay_item_ids:
        replay_ids = [s.strip() for s in a.replay_item_ids.split(",") if s.strip()]
        # T048 restart round 1 (R6-F21): an id that is not in this sample used to be
        # dropped silently while still counted as "duration-eligible" in the note.
        sample_ids = {it["item_id"] for it in items}
        unknown = [i for i in replay_ids if i not in sample_ids]
        if unknown:
            print("collect_baseline: --replay-item-ids names id(s) not in this sample: %s" % ",".join(unknown),
                  file=sys.stderr)
            return 2
    else:
        replay_ids = list(eligible_ids)

    replay_dir = os.path.join(a.out_dir, "replay")
    os.makedirs(replay_dir, exist_ok=True)
    by_type_pool = {}  # type -> phase -> [duration_ms,...]
    per_item_replay = []
    for it in items:
        iid = it["item_id"]
        itype = it["type"]
        if iid not in replay_ids:
            per_item_replay.append({"item_id": iid, "type": itype, "replayed": False,
                                     "reason": "not in the reduced-scope replay subset for this run "
                                               "(excluded_from_duration=%r, or not selected by "
                                               "--replay-item-ids)" % it.get("excluded_from_duration", False)})
            continue
        fz = freezes.get(iid, {})
        commit, tree = fz.get("commit"), fz.get("tree")
        if a.skip_gate_replay:
            per_item_replay.append({"item_id": iid, "type": itype, "replayed": False,
                                     "reason": "--skip-gate-replay"})
            continue
        if fz.get("harness_error"):
            per_item_replay.append({"item_id": iid, "type": itype, "replayed": False,
                                     "reason": fz.get("reason")})
            continue
        if not commit or commit == "UNMEASURED":
            per_item_replay.append({"item_id": iid, "type": itype, "replayed": False,
                                     "reason": "freeze UNMEASURED, no resolvable commit to replay"})
            continue
        rpath = os.path.join(replay_dir, "%s.json" % iid)
        rdoc = run_replay(baseline_replay_bin, commit, tree, a.gate_cmd, a.cold_runs, a.warm_runs,
                           repo_root, a.worktree_root, a.timeout_s, rpath, a.min_free_kb)
        if rdoc.get("skipped"):
            per_item_replay.append({"item_id": iid, "type": itype, "replayed": False,
                                     "reason": rdoc.get("skip_reason")})
            if rdoc.get("harness_error"):
                harness_errors.append({"item_id": iid, "stage": "replay", "reason": rdoc.get("skip_reason")})
            continue
        # PLAUSIBILITY CONTROL NEEDLE (S11.4.201/S11.4.273, added after the live
        # 2026-09-29 ATM-277 EACCES discovery documented above DEFAULT_GATE_CMD):
        # a run whose duration is far below any plausible real gate-suite
        # execution is EXCLUDED from the per-type median pool and reported
        # explicitly, never silently pooled as if it were a real measurement.
        # The floor is deliberately generous (an order of magnitude below the
        # measured ~1134s real run) so a genuinely fast future gate (once
        # US2's affected-set selection lands) is never falsely flagged.
        implausible_runs = [r for r in rdoc.get("runs", []) if r.get("duration_ms", 0) < a.plausible_floor_ms]
        per_item_replay.append({
            "item_id": iid, "type": itype, "replayed": True,
            "commit": commit, "tree": tree,
            # baseline_replay.sh's own median_ms is over PASS runs only (R6-F9)
            "median_ms": rdoc.get("median_ms"), "verdict_set": rdoc.get("verdict_set"),
            "implausible_run_count": len(implausible_runs),
            "implausible_runs": implausible_runs if implausible_runs else None,
        })
        pool = by_type_pool.setdefault(itype, {"cold": [], "warm": [], "excluded": {"cold": 0, "warm": 0}})
        for run in rdoc.get("runs", []):
            # R6-F9: only a PASS run that is also plausibly long is a gate-speed
            # measurement; every other run is counted as excluded, never pooled.
            if run.get("verdict") == "PASS" and run.get("duration_ms", 0) >= a.plausible_floor_ms:
                pool[run["phase"]].append(run["duration_ms"])
            else:
                pool["excluded"][run["phase"]] += 1

    per_type_medians = {}
    overall_pool = {"cold": [], "warm": []}
    for itype, pool in by_type_pool.items():
        entry = {}
        for phase in ("cold", "warm"):
            vals = pool[phase]
            overall_pool[phase].extend(vals)
            entry[phase] = {"median_ms": int(round(statistics.median(vals))) if vals else "UNMEASURED",
                             "n_runs": len(vals), "n_excluded_non_pass": pool["excluded"][phase]}
        per_type_medians[itype] = entry
    overall_medians = {}
    for phase in ("cold", "warm"):
        vals = overall_pool[phase]
        overall_medians[phase] = {"median_ms": int(round(statistics.median(vals))) if vals else "UNMEASURED",
                                   "n_runs": len(vals)}

    reopen = reopen_baseline(db_path, a.as_of, a.window_days)
    tokens = token_baseline(items, a.fresh_execution_json)

    # R6-F21: the denominator is the sample's duration-eligible items (never the
    # caller's --replay-item-ids list), and "owed follow-up" is said only when this
    # run genuinely fell short of DEC-36 (fewer than 10/10 runs, or not every
    # eligible item actually replayed).
    n_replayed = len([r for r in per_item_replay if r.get("replayed")])
    eligible_replayed = len([r for r in per_item_replay if r.get("replayed") and r["item_id"] in eligible_ids])
    reduced = (a.cold_runs < REPLAY_FULL_RUNS or a.warm_runs < REPLAY_FULL_RUNS
               or eligible_replayed < len(eligible_ids))
    if reduced:
        full_protocol_note = (
            "DEC-36 mandates >=10 cold + >=10 warm gate-window replays per sample item. This run used "
            "--cold-runs %d --warm-runs %d and replayed %d of %d duration-eligible items (measured per-run "
            "cost ~%.1f min, %s). A full-compliance run (>=10/>=10 across all %d duration-eligible items) "
            "is extrapolated to cost ~%.1f hours and is TRACKED AS AN OWED FOLLOW-UP, never silently "
            "treated as already satisfied." % (
                a.cold_runs, a.warm_runs, eligible_replayed, len(eligible_ids),
                MEASURED_PER_RUN_S / 60.0, a.gate_cmd, len(eligible_ids),
                (len(eligible_ids) * 2 * REPLAY_FULL_RUNS * MEASURED_PER_RUN_S) / 3600.0,
            )
        )
    else:
        full_protocol_note = (
            "DEC-36 protocol met: --cold-runs %d --warm-runs %d, every one of the %d duration-eligible "
            "items replayed (%d items replayed in total)." % (
                a.cold_runs, a.warm_runs, len(eligible_ids), n_replayed)
        )

    doc = {
        "as_of": a.as_of, "window_days": a.window_days, "min_per_type": a.min_per_type,
        "gate_cmd": a.gate_cmd, "cold_runs_per_item": a.cold_runs, "warm_runs_per_item": a.warm_runs,
        "measured_full_run_seconds": MEASURED_PER_RUN_S,
        "sample": {"total_items": len(items), "state": sample.get("state"), "strata": sample.get("strata", {}),
                   "sample_doc_path": sample_json_path},
        "freeze": {iid: {"commit": fz.get("commit"), "tree": fz.get("tree"),
                         "harness_error": bool(fz.get("harness_error")), "reason": fz.get("reason", "")}
                   for iid, fz in freezes.items()},
        "harness_errors": harness_errors,
        "gate_window_replay": {
            "per_item": per_item_replay, "per_type_medians": per_type_medians,
            "overall_medians": overall_medians, "full_protocol_note": full_protocol_note,
        },
        "reopen_baseline": reopen,
        "token_baseline": tokens,
    }
    doc["schema"] = SCHEMA
    doc["body_hash"] = body_hash_of(doc)
    doc["run_meta"] = {"tool": "collect_baseline.py", "generated_at": datetime.datetime.now(
        datetime.timezone.utc).isoformat()}

    out_path = os.path.join(a.out_dir, "baseline.json")
    atomic_write_json(doc, out_path)

    md_lines = [
        "# Fast-Dev-Cycles Frozen Baseline (T045)", "",
        "as_of=%s window_days=%d gate_cmd=%s" % (a.as_of, a.window_days, a.gate_cmd), "",
        "## Sample: %d items (%s)" % (len(items), sample.get("strata", {})), "",
        "## Gate-window replay (cold/warm medians, ms)", "",
        "| type | cold n | cold median | warm n | warm median |",
        "|---|---|---|---|---|",
    ]
    for itype, entry in sorted(per_type_medians.items()):
        md_lines.append("| %s | %d | %s | %d | %s |" % (
            itype, entry["cold"]["n_runs"], entry["cold"]["median_ms"],
            entry["warm"]["n_runs"], entry["warm"]["median_ms"]))
    md_lines += ["", full_protocol_note, "", "## Reopen baseline (matched denominators)", ""]
    md_lines.append("| type | closed | reopened | rate |")
    md_lines.append("|---|---|---|---|")
    for itype, e in sorted(reopen.get("by_type", {}).items()):
        md_lines.append("| %s | %d | %d | %s |" % (itype, e["closed_in_window"], e["reopened_in_window"], e["reopen_rate"]))
    with open(os.path.join(a.out_dir, "baseline.md"), "w") as fh:
        fh.write("\n".join(md_lines) + "\n")

    print(json.dumps({"out": out_path, "schema": SCHEMA, "body_hash": doc["body_hash"]}))
    # A run in which any item could not be measured because the HARNESS failed is
    # BLIND (exit 4, C-001), even though the baseline doc is written as evidence.
    if harness_errors:
        print("collect_baseline: BLIND: %d harness error(s): %s" % (
            len(harness_errors), "; ".join("%s %s" % (h["item_id"], h["stage"]) for h in harness_errors)),
            file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
