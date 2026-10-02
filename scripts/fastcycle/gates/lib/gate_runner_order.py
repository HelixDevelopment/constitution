#!/usr/bin/env python3
"""gate_runner_order.py -- fail-fast history-cost gate ordering + sequential
execution for gate_runner.sh's default ("verdicts") mode (SpecKit-004
"fast-dev-cycles", User Story 2; plan.md T-C04; tasks.md T070; contract
specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
AS-013). Guarded by
constitution/scripts/fastcycle/tests/test_gate_order_red.sh (T054) and its
fixtures under tests/fixtures/gate_order/.

Invoked ONLY by ../gate_runner.sh's default mode -- not a standalone CLI
contract of its own (mirrors the gates/io_trace.sh -> gates/lib/
io_trace_parse.py split already established in this tool family).

CLI (mirrors gate_runner.sh's own default-mode flags 1:1):
    gate_runner_order.py --config <cfg> --affected <affected.json>
        --out <verdicts.json> [--order history-cost] [--no-cache]

--config <cfg>: YAML, top-level keys
    gate_sites:  {gate_id: <path to the gate script, RELATIVE TO THIS
                  FILE's own directory>, ...}
    history_log: <path to a T-A01-schema TSV (fc_timer.sh header), RELATIVE
                  TO THIS FILE's own directory>, optional
  This is a DELIBERATELY SIMPLER schema than the project's own top-level
  config/fastcycle/fastcycle.yaml (whose paths are project-root-relative
  under a `paths:` key, consumed by gates/catchset_compare.py and
  gates/gate_audit.py's load_yaml_config) -- test_gate_order_red.sh's own
  fixture config.yaml is the binding contract here (its own header
  comment: "Paths below are relative to this file's own directory"), and
  no contracts/*.md file pins a different schema for gate_runner.sh's own
  --config, so this loader targets exactly what the RED fixture ships.

--affected <affected.json>: an Affected-Set entity (data-model.md §4);
  only the `members` array (declared/section order) and `change_id` are
  consumed by this tool.

--order history-cost (AS-013 / research.md DEC-10): sorts `members` by
  historical_fail_rate / mean_cost, DESCENDING, both measured over EVERY
  row in --config's history_log for a gate (never limited to the gates
  present in the CURRENT run's members -- confirmed as one of two
  contract-compatible population choices by test_gate_order_red.sh's own
  Section B reference computation, and the ONLY one this implementation
  adopts, documented here per §11.4.6). A gate absent from the history log
  (a genuinely new gate, or a gate this run declares that the log has
  never recorded) defaults to the MEDIAN ratio across every gate that DOES
  have history (DEC-10 "new gates at the median rate"); with zero
  historical gates at all, the median is 0.0 (no evidence either way,
  never a fabricated non-zero default, §11.4.6). Ties are broken by
  gate_id ascending -- C-002/C-003 determinism (never Python dict/hash-map
  iteration order, never wall-clock, never a random seed).

Absent --order (the plain declared-order call): execution_order is simply
`members` as declared in --affected, unmodified.

AS-013's "ordering never removes a member and the final verdict set is
identical with and without ordering": this tool ALWAYS executes and
reports EVERY declared member regardless of --order, in BOTH calls
--out's `results` array (sorted by gate_id, C-002) is therefore identical
whether --order is given or not; only the SEQUENCE gates run in, and the
NEW `execution_order` field (see below), differ. AS-013's "the fast lane
stops at the first FAIL and reports": satisfied by an IMMEDIATE stdout
notice ("FAST-LANE FAIL: ...") the moment the highest-ranked
(--order history-cost) gate produces a FAIL -- a human-visible early
signal, never a truncation of the completed --out document (the ONLY
reading fully consistent with T054's own Section 3
go_determinism_identical_results scenario, which requires the FULL
4-member results set from BOTH the ordered and the unordered call of the
SAME shared fixture -- a literal early-stop-and-truncate reading of "stops
at the first FAIL" is falsified by that scenario). This tool's own "pre-
merge run completes every selected gate" clause is therefore always true
of THIS CLI's --out output: there is no separate CLI flag in the contract
(specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
"Components and invocations") distinguishing a fast-lane-that-truncates
from a pre-merge-run-that-completes; a caller wanting fast local feedback
watches the stdout notice, a caller wanting the full CI-grade record reads
--out, and both needs are served by ONE completed run.

Output schema `verdicts/v1` (per the contract, plus the RED test's own
"UNCONFIRMED by the contract... DEFINED here, binding-if-adopted"
`execution_order` field -- see test_gate_order_red.sh's header comment):
    {
      "schema": "verdicts/v1",
      "change_id": <affected.json's own change_id, pass-through>,
      "results": [{"gate_id", "verdict" in {PASS,FAIL,BLIND},
                   "source": "RUN", "evidence", "duration_ms"}, ...]
                 sorted by gate_id (C-002),
      "execution_order": [gate_id, ...],   # the ACTUAL run sequence
      "summary": {"total","pass","fail","skip","blind"}
    }

HONEST SCOPE GAP (§11.4.6, producer != contract-author per §11.4.240): this
tool's T070 scope is ordering only. `--no-cache` is ACCEPTED (a genuine
usage error is never raised for it) but is currently a NO-OP: verdict-
cache integration (T-C01's gates/verdict_cache.py) is NOT wired into
gate_runner.sh by this task -- every `source` field is therefore always
"RUN", never "CACHE". This is a real, stated scope boundary, not a silent
omission: wiring the cache is a separate, not-yet-scheduled unit of work
on top of this file.

Exit codes (contract's own override of common-conventions.md C-001, per
the contract's "Exit codes" section): 0 all PASS, 1 any FAIL, 4 any BLIND
(a gate script that could not be found/executed). 2 usage/config error.
"""
import argparse
import csv
import json
import os
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# T085 Round 5 (R4-I2): wiring to the shared fc_common.run_gate_reaped()
# primitive.
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_BLIND = 4

GATE_TIMEOUT_SECONDS = 300  # §11.4.89: a single synchronous op stays under
                             # the ~5min no-progress watchdog budget.


def _die_usage(msg):
    sys.stderr.write("gate_runner_order: %s\n" % msg)
    sys.exit(EXIT_USAGE)


def load_config(path):
    """Returns (gate_sites: {id: absolute script path}, history_log:
    absolute path or None). C-001: missing file/key => exit 2, never a
    guessed default path (§11.4.6)."""
    if not path or not os.path.isfile(path):
        _die_usage("--config file not found: %s" % path)
    try:
        import yaml
    except ImportError:
        _die_usage("PyYAML is required to parse --config (pip install pyyaml)")
    with open(path, "r", encoding="utf-8") as fh:
        try:
            cfg = yaml.safe_load(fh)
        except Exception as exc:  # noqa: BLE001 -- any parse failure is a usage error
            _die_usage("cannot parse --config %s: %s" % (path, exc))
    if not isinstance(cfg, dict) or "gate_sites" not in cfg:
        _die_usage("%s missing required top-level key 'gate_sites'" % path)
    gate_sites = cfg["gate_sites"]
    if not isinstance(gate_sites, dict) or not gate_sites:
        _die_usage("%s 'gate_sites' must be a non-empty mapping" % path)
    cfg_dir = os.path.dirname(os.path.abspath(path))
    resolved_sites = {}
    for gid, rel in gate_sites.items():
        resolved_sites[gid] = os.path.normpath(os.path.join(cfg_dir, rel))
    history_log = cfg.get("history_log")
    resolved_history = os.path.normpath(os.path.join(cfg_dir, history_log)) if history_log else None
    return resolved_sites, resolved_history


def load_affected(path):
    """Returns (the full affected doc, its `members` list). C-001: missing
    file / empty members => exit 2 (this tool's own precondition, never
    guessed)."""
    if not os.path.isfile(path):
        _die_usage("--affected file not found: %s" % path)
    with open(path, "r", encoding="utf-8") as fh:
        try:
            aff = json.load(fh)
        except json.JSONDecodeError as exc:
            _die_usage("cannot parse --affected %s: %s" % (path, exc))
    members = aff.get("members")
    if not isinstance(members, list) or not members:
        _die_usage("%s has no non-empty 'members' array" % path)
    return aff, members


def load_history_ratios(history_log):
    """Returns {gate_id: fail_rate/mean_cost} computed over EVERY row for
    that gate in the T-A01-schema TSV (fc_timer.sh header: run_id,
    candidate_fingerprint, id, start_ns, end_ns, duration_ms, verdict,
    checks, fails, warns, extra). A missing/absent history_log yields an
    empty map (every member then defaults to the 0.0 floor in
    compute_order -- no history anywhere means no evidence either way)."""
    ratios = {}
    if not history_log or not os.path.isfile(history_log):
        return ratios
    runs = {}
    with open(history_log, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            gid = row.get("id")
            if not gid:
                continue
            try:
                duration_ms = int(row.get("duration_ms", "0") or 0)
            except ValueError:
                duration_ms = 0
            runs.setdefault(gid, []).append((row.get("verdict"), duration_ms))
    for gid, rows in runs.items():
        n = len(rows)
        if n == 0:
            continue
        fails = sum(1 for v, _ in rows if v == "FAIL")
        fail_rate = fails / n
        mean_cost = sum(d for _, d in rows) / n
        # T085 Round 2 MINOR: a zero-duration gate that has NEVER failed
        # (fail_rate==0, mean_cost==0) previously fell into the `else`
        # branch by the mean_cost==0 falsy check alone and got `inf` --
        # a pure division-by-zero ARTIFACT, not a genuine "run me first"
        # signal, and it always sorted ahead of every gate with REAL
        # fail-catching history. `inf` is now reserved for a genuinely
        # informative case (zero-cost AND it DOES sometimes fail --
        # maximal value, free to run, catches real defects); a
        # zero-cost gate with ZERO fail history carries no signal and
        # gets the neutral 0.0 floor instead (the SAME floor a
        # no-history gate already gets via compute_order()'s median
        # default), so it no longer wins a false tie-break over gates
        # with genuine evidence.
        if mean_cost:
            ratios[gid] = fail_rate / mean_cost
        elif fail_rate > 0:
            ratios[gid] = float("inf")
        else:
            ratios[gid] = 0.0
    return ratios


def compute_order(members, ratios):
    """AS-013 / DEC-10: descending fail_rate/mean_cost; a member absent
    from `ratios` (no history) defaults to the MEDIAN of every gate that
    DOES have history in the log (not limited to current `members` --
    matches test_gate_order_red.sh's own Section B reference computation;
    the fixture is deliberately built so this choice is indistinguishable
    from the narrower "median over current members only" reading for
    every given scenario, per that RED test's own header comment). Ties
    are broken by gate_id ascending -- never Python dict/hash-map
    iteration order (C-002/C-003 determinism)."""
    known = sorted(ratios.values())
    if known:
        mid = len(known) // 2
        median = known[mid] if len(known) % 2 == 1 else (known[mid - 1] + known[mid]) / 2
    else:
        median = 0.0
    effective = {gid: ratios.get(gid, median) for gid in members}
    return sorted(members, key=lambda g: (-effective[g], g))


def run_gate(gate_id, script_path, evidence_dir):
    """Runs one gate script to completion and returns its verdicts/v1
    result entry. A missing/unreadable script, or a run the tool itself
    could not complete (timeout, OSError), is BLIND (C-001: no tool maps
    'could not run' to a fabricated PASS/FAIL)."""
    if not os.path.isfile(script_path):
        return {
            "gate_id": gate_id,
            "verdict": "BLIND",
            "source": "RUN",
            "evidence": None,
            "duration_ms": 0,
        }
    os.makedirs(evidence_dir, exist_ok=True)
    evidence_path = os.path.join(evidence_dir, "%s.log" % gate_id)
    start = time.monotonic()
    rc = None
    out = ""
    # T085 Round 5 (R4-I2): via the shared reaped runner.
    result = fc_common.run_gate_reaped(["sh", script_path], timeout_s=GATE_TIMEOUT_SECONDS)
    if result.timed_out:
        out = "gate_runner_order: %s timed out after %ss\n" % (script_path, GATE_TIMEOUT_SECONDS)
    elif result.error is not None:
        out = "gate_runner_order: could not execute %s: %s\n" % (script_path, result.error)
    else:
        rc = result.returncode
        out = (result.stdout or "") + (result.stderr or "")
    duration_ms = int((time.monotonic() - start) * 1000)
    with open(evidence_path, "w", encoding="utf-8") as fh:
        fh.write(out)
    if rc is None:
        verdict = "BLIND"
    elif rc == 0:
        verdict = "PASS"
    else:
        verdict = "FAIL"
    return {
        "gate_id": gate_id,
        "verdict": verdict,
        "source": "RUN",
        "evidence": evidence_path,
        "duration_ms": duration_ms,
    }


def main(argv):
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--config", required=True)
    p.add_argument("--affected", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--order", default=None)
    p.add_argument("--no-cache", action="store_true")
    try:
        a = p.parse_args(argv)
    except SystemExit:
        sys.exit(EXIT_USAGE)

    if a.order not in (None, "history-cost"):
        _die_usage("--order must be 'history-cost': %s" % a.order)

    gate_sites, history_log = load_config(a.config)
    affected, members = load_affected(a.affected)

    unknown = sorted(set(members) - set(gate_sites))
    if unknown:
        _die_usage(
            "%s declares gate(s) not present in --config gate_sites: %s"
            % (a.affected, ", ".join(unknown))
        )

    if a.order == "history-cost":
        ratios = load_history_ratios(history_log)
        execution_order = compute_order(members, ratios)
    else:
        execution_order = list(members)

    out_dir = os.path.dirname(os.path.abspath(a.out)) or "."
    evidence_dir = os.path.join(out_dir, "evidence")

    results_by_id = {}
    first_fail_reported = False
    for gid in execution_order:
        r = run_gate(gid, gate_sites[gid], evidence_dir)
        results_by_id[gid] = r
        if r["verdict"] == "FAIL" and not first_fail_reported and a.order == "history-cost":
            # AS-013 "the fast lane stops at the first FAIL and reports":
            # an immediate, human-visible notice the moment the highest-
            # ranked gate fails -- see this file's own header comment for
            # why this is the ONLY reading consistent with the RED test's
            # determinism scenario (--out always carries every member).
            # T085 Round 2 MINOR: the printed rank is now the gate's REAL
            # 1-based position in execution_order, not a hardcoded "1" --
            # a gate that fails after one or more earlier-ranked gates
            # PASSed/were BLIND is genuinely NOT rank 1, and the old
            # hardcoded text misreported that for every such run.
            real_rank = execution_order.index(gid) + 1
            print("FAST-LANE FAIL: %s (rank %d by --order history-cost, evidence: %s)"
                  % (gid, real_rank, r["evidence"]))
            first_fail_reported = True

    results = []
    any_fail = False
    any_blind = False
    for gid in sorted(results_by_id):
        r = results_by_id[gid]
        results.append({
            "gate_id": r["gate_id"],
            "verdict": r["verdict"],
            "source": r["source"],
            "evidence": r["evidence"],
            "duration_ms": r["duration_ms"],
        })
        if r["verdict"] == "FAIL":
            any_fail = True
        elif r["verdict"] == "BLIND":
            any_blind = True

    summary = {
        "total": len(results),
        "pass": sum(1 for r in results if r["verdict"] == "PASS"),
        "fail": sum(1 for r in results if r["verdict"] == "FAIL"),
        "skip": sum(1 for r in results if r["verdict"] == "SKIP"),
        "blind": sum(1 for r in results if r["verdict"] == "BLIND"),
    }

    doc = {
        "schema": "verdicts/v1",
        "change_id": affected.get("change_id"),
        "results": results,
        "execution_order": execution_order,
        "summary": summary,
    }
    try:
        with open(a.out, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, sort_keys=True, indent=2, ensure_ascii=False)
            fh.write("\n")
    except OSError as exc:
        _die_usage("cannot write --out %s: %s" % (a.out, exc))

    if any_blind:
        sys.exit(EXIT_BLIND)
    if any_fail:
        sys.exit(EXIT_FINDING)
    sys.exit(EXIT_OK)


if __name__ == "__main__":
    main(sys.argv[1:])
