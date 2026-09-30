#!/usr/bin/env python3
"""gate_determinism_sweep.py -- sweeps `lib/fc_common.py determinism-check` across an
arbitrary set of configured gate commands and aggregates one PASS/FAIL-shaped verdict
per gate (SpecKit-004 "fast-dev-cycles", User Story 7; plan.md T-G07; tasks.md T160
[this tool] -- guarded by T155's RED test tests/test_gate_determinism_red.sh).

Plan.md T-G07 ("Determinism of the verifier and of every new gate"), verbatim Work
line: "run the verifier and every new gate twice on the same state; compare SHA-256
of outputs; LLM-produced artefacts inside pipelines are replayed from their recorded
outputs (DEC-16)." FR-021: "Given the same repository state, the recursive
verification and every gate MUST return byte-identical output on two consecutive
runs." tasks.md T160 (this tool's real scope, a SEPARATE, larger follow-on activity
not attempted here -- see the "Scope" paragraph below): "Run repo_verify.py and
every new gate from US1-US6 twice on the same state; compare body_hash; any embedded
timestamp is moved out of the canonical body and re-run; LLM-produced artefacts
replayed from recorded outputs (DEC-16); results under
qa-results/fastcycle/us7/determinism/ until T155 is GREEN."

Reuse-not-reinvention (section 11.4.227): this tool does NOT reimplement the
double-run / body_hash-compare / process-management / timeout / reaping logic that
`lib/fc_common.py`'s ALREADY-LANDED, already-regression-tested (test_fc_common_red.sh)
`determinism-check -- CMD...` subcommand already performs -- it SHELLS OUT to that
exact subcommand once per configured gate (exactly as test_gate_determinism_red.sh's
own Section B invokes it directly, for real, as its reference computation) and folds
each invocation's already-honest 0/1/3/4 exit-code taxonomy into this tool's own
three-value `verdict` vocabulary and aggregate report.

CLI contract (UNCONFIRMED by any landed contracts/*.md file -- neither
contracts/common-conventions.md's "Tool map" table nor
contracts/recursive-verification.md, which governs ONLY repo_verify.py's own
`--determinism-check` self-check RV-007, cover a cross-gate sweep tool; per
common-conventions.md's own "Plan tools that no contract in this directory covers"
convention, this tool's interface/output/RED-fixtures are fixed by
tests/test_gate_determinism_red.sh -- the sibling test_gate_order_red.sh's own
EXEC_ORDER_KEY treatment of its equally-unconfirmed field is the house precedent for
this situation -- until a contract is written):

Usage:   gate_determinism_sweep.py --config <gates.yaml> --out <report.json>

gates.yaml (loaded via PyYAML, matching gates/gate_audit.py's load_yaml_config
convention -- an unparseable/missing config, or a config missing the required
top-level 'gates' key, fails closed at exit 2 rather than guessing, section 11.4.6):

    schema: fastcycle-gate-determinism-sweep-config/v1   # informational, not enforced
    gates:
      - id: <str, non-empty, unique>
        cmd: [<argv...>]                                 # non-empty list of non-empty strings

report.json (written via `lib/fc_common.py`'s shared `cmd_emit` -- canonical JSON,
atomic write, `body_hash` excluding `run_meta`, same wiring pattern as
verify/repo_verify.py and verify/plan_struct_check.py, section 11.4.227):

    {schema, results: [{gate_id, verdict, exit_code, detail}, ...], summary, run_meta}

`verdict` is drawn from {DETERMINISTIC, NONDETERMINISTIC, BLIND} per gate, mirroring
`fc_common.py determinism-check`'s own exit-code taxonomy one-for-one: fc_common exit
0 (stable) -> DETERMINISTIC; exit 1 (body_hash/rc mismatch) -> NONDETERMINISTIC;
exit 3 (command self-test failed) or exit 4 (no honest verdict possible) -> BLIND
(no other fc_common exit code is a defined verdict per contracts/common-conventions.md
C-001, so any other value is conservatively folded into BLIND too, section 11.4.201 --
never silently read as a clean DETERMINISTIC). `exit_code` is fc_common's own raw
per-gate exit code (null if the subprocess itself could not be started at all).
`detail` is the last non-blank line of that invocation's stderr, or "" if none --
purely diagnostic, never load-bearing for the verdict.

Exit codes (mirrors contracts/common-conventions.md C-001, folding fc_common's
per-gate 3-vs-4 distinction into one aggregate BLIND bucket -- no gate-level
self-test failure is distinguishable from a gate-level BLIND at the SWEEP's own
overall exit, matching this tool's documented three-value verdict vocabulary):
    0  every gate DETERMINISTIC (report written)
    1  >=1 gate NONDETERMINISTIC, none BLIND (report written -- the finding IS the
       output, C-001 row 1)
    2  usage/config error: --config missing/unparseable/malformed, PyYAML absent,
       or this tool's own sibling lib/fc_common.py does not resolve (no report
       written, matching C-001 row 2's "error message only")
    4  >=1 gate BLIND (self-test-failed or no-honest-verdict) (report written,
       flagged BLIND, C-001 row 4 -- "partial output ... never read as 0")
A gate list of zero entries is vacuously DETERMINISTIC (exit 0) -- there is no
finding to report and no gate that failed to yield a verdict.

Producer != Verifier (section 11.4.240): this tool never invents a verdict for a
gate whose command could not even be launched (OSError from subprocess.Popen, e.g.
python3 itself missing) -- that gate is BLIND with exit_code=null and a detail
string naming the failure, exactly like fc_common's own "no honest verdict" cases.

Stdlib + PyYAML only (matches lib/fc_common.py's own stdlib-only convention plus the
same PyYAML dependency gates/gate_audit.py already takes for --config parsing);
imports body_hash / canon / cmd_emit from the sibling lib/fc_common.py (C-002), same
wiring pattern as verify/repo_verify.py and verify/plan_struct_check.py.
"""
import argparse
import json
import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / atomic-emit helper. Imported by file
# path (not a package) -- constitution/scripts/fastcycle has no __init__.py anywhere
# (matches this tree's existing flat-script layout, verify/repo_verify.py's own
# _LIB_DIR convention).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

SCHEMA = "gate-determinism-sweep/v1"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_BLIND = 4

# fc_common.py determinism-check's own documented exit-code taxonomy (see this
# file's module docstring): 0 stable, 1 body_hash/rc mismatch, 3 command self-test
# failed, 4 no honest verdict. Folded here into this tool's own three-value
# `verdict` vocabulary; any fc_common exit code OUTSIDE this table (there is none
# documented, but a future fc_common change or an unexpected environment could
# still produce one) is conservatively treated as BLIND via .get()'s default
# below, never silently read as a clean DETERMINISTIC (section 11.4.201 --
# a false-positive "it's fine" is exactly the false-null this table refuses).
VERDICT_BY_FC_EXIT = {0: "DETERMINISTIC", 1: "NONDETERMINISTIC", 3: "BLIND", 4: "BLIND"}

VERDICT_TO_EXIT = {"DETERMINISTIC": EXIT_OK, "NONDETERMINISTIC": EXIT_FINDING, "BLIND": EXIT_BLIND}


def load_config(path):
    """Load + validate --config; returns a list of {"id": str, "cmd": [str, ...]}
    gate dicts (config order preserved) on success, or None (having already
    printed the reason to stderr) on any usage/config error -- section 11.4.6,
    never guesses a malformed config into something runnable."""
    if not path or not os.path.isfile(path):
        print("gate_determinism_sweep: config file not found: %s" % path, file=sys.stderr)
        return None
    try:
        import yaml
    except ImportError:
        print("gate_determinism_sweep: PyYAML is required to parse --config (pip install pyyaml)", file=sys.stderr)
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
    except yaml.YAMLError as exc:
        print("gate_determinism_sweep: cannot parse --config as YAML: %s" % exc, file=sys.stderr)
        return None
    except OSError as exc:
        print("gate_determinism_sweep: cannot read --config: %s" % exc, file=sys.stderr)
        return None
    if not isinstance(cfg, dict) or "gates" not in cfg:
        print("gate_determinism_sweep: %s missing required top-level key 'gates'" % path, file=sys.stderr)
        return None
    gates = cfg["gates"]
    if not isinstance(gates, list):
        print("gate_determinism_sweep: 'gates' must be a list, got %s" % type(gates).__name__, file=sys.stderr)
        return None
    seen_ids = set()
    parsed = []
    for i, g in enumerate(gates):
        if not isinstance(g, dict):
            print("gate_determinism_sweep: gates[%d] must be a mapping, got %s" % (i, type(g).__name__), file=sys.stderr)
            return None
        gid = g.get("id")
        if not isinstance(gid, str) or not gid:
            print("gate_determinism_sweep: gates[%d].id must be a non-empty string" % i, file=sys.stderr)
            return None
        if gid in seen_ids:
            print("gate_determinism_sweep: duplicate gate id %r (gates[%d])" % (gid, i), file=sys.stderr)
            return None
        cmd = g.get("cmd")
        if not isinstance(cmd, list) or not cmd or not all(isinstance(c, str) and c for c in cmd):
            print("gate_determinism_sweep: gates[%d].cmd must be a non-empty list of non-empty strings" % i, file=sys.stderr)
            return None
        seen_ids.add(gid)
        parsed.append({"id": gid, "cmd": list(cmd)})
    return parsed


def _last_nonblank_line(text):
    lines = [ln for ln in (text or "").splitlines() if ln.strip()]
    return lines[-1] if lines else ""


def run_gate(fccommon_path, gate):
    """Invoke `python3 <fccommon_path> determinism-check -- <gate cmd...>` for real
    (never simulated) and classify its exit code into this tool's own verdict
    vocabulary. Reuses fc_common.py's own double-run/body_hash/reaping machinery
    wholesale (section 11.4.227) -- this function's only job is the subprocess
    launch and the exit-code -> verdict fold documented in VERDICT_BY_FC_EXIT."""
    argv = [sys.executable, fccommon_path, "determinism-check", "--"] + gate["cmd"]
    try:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except OSError as exc:
        # The determinism-check subprocess itself could not even be launched (e.g.
        # the resolved python3 interpreter vanished mid-run) -- no honest verdict
        # is possible for this gate; never fabricated as a clean DETERMINISTIC.
        return {"gate_id": gate["id"], "verdict": "BLIND", "exit_code": None,
                "detail": "cannot invoke fc_common.py determinism-check: %s" % exc}
    rc = proc.returncode
    verdict = VERDICT_BY_FC_EXIT.get(rc, "BLIND")
    return {"gate_id": gate["id"], "verdict": verdict, "exit_code": rc,
            "detail": _last_nonblank_line(proc.stderr)}


def main(argv):
    p = argparse.ArgumentParser(prog="gate_determinism_sweep.py")
    p.add_argument("--config", required=True)
    p.add_argument("--out", required=True)
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return EXIT_USAGE if se.code else EXIT_OK

    gates = load_config(a.config)
    if gates is None:
        return EXIT_USAGE

    fccommon_path = os.path.join(_LIB_DIR, "fc_common.py")
    if not os.path.isfile(fccommon_path):
        print("gate_determinism_sweep: cannot resolve sibling lib/fc_common.py at %s" % fccommon_path, file=sys.stderr)
        return EXIT_USAGE

    results = []
    for gate in gates:
        result = run_gate(fccommon_path, gate)
        results.append(result)
        print("gate_determinism_sweep: %s -> %s (fc_common exit=%s)"
              % (result["gate_id"], result["verdict"], result["exit_code"]), file=sys.stderr)

    counts = {"DETERMINISTIC": 0, "NONDETERMINISTIC": 0, "BLIND": 0}
    for r in results:
        counts[r["verdict"]] += 1
    if counts["BLIND"]:
        overall = "BLIND"
    elif counts["NONDETERMINISTIC"]:
        overall = "NONDETERMINISTIC"
    else:
        overall = "DETERMINISTIC"
    overall_exit = VERDICT_TO_EXIT[overall]

    summary = {
        "gate_count": len(results),
        "deterministic_count": counts["DETERMINISTIC"],
        "nondeterministic_count": counts["NONDETERMINISTIC"],
        "blind_count": counts["BLIND"],
        "overall_verdict": overall,
    }
    report = {"results": results, "summary": summary}

    out_dir = os.path.dirname(os.path.abspath(a.out))
    if out_dir:
        try:
            os.makedirs(out_dir, exist_ok=True)
        except OSError as exc:
            print("gate_determinism_sweep: cannot create --out directory %s: %s" % (out_dir, exc), file=sys.stderr)
            return EXIT_USAGE

    ns = argparse.Namespace(schema=SCHEMA, body_json=json.dumps(report), run_meta_json=None,
                             out=a.out, code=overall_exit)
    write_rc = fc_common.cmd_emit(ns)
    if write_rc != ns.code:
        # fc_common.cmd_emit only ever diverges from the requested code on a
        # write/encode error (returns 2) -- surface that honestly rather than
        # claim the verdict this tool computed was actually written to disk.
        return write_rc
    return overall_exit


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
