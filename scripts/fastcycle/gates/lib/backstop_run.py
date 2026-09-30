#!/usr/bin/env python3
"""backstop_run.py -- T-C10 full backstop lane: runs EVERY gate named in
--manifest with NO caching and NO --affected narrowing, producing a fresh
`verdicts/v1` document (SpecKit-004 "fast-dev-cycles", User Story 2;
plan.md T-C10; tasks.md T077; FR-006, FR-022, SC-003).

NOT exercised by constitution/scripts/fastcycle/tests/test_backstop_red.sh
(T060) -- fixtures/backstop/README.md's own "What this RED test does NOT
cover" section: "The `run` subcommand's actual full-corpus execution
(composes gate_runner.sh + a real gate/mutation corpus, neither
constructed by this fixture-driven RED test -- T077's own implementer-
task job)." This file IS that implementer-task job, genuinely functional,
just not RED-fixture-verified end to end.

Output schema reused unchanged from affected-set-and-verdict-cache.md's
"Output schemas" section (`verdicts/v1`:
`{change_id, results: [{gate_id, verdict, source, evidence, duration_ms}],
summary}`), the SAME document `backstop_compare.py`'s `--full` argument
consumes (constitution SS11.4.6 -- do not invent a new schema when one
already exists). Every result's `source` is always "RUN" (this subcommand
never reads verdict_cache.py at all, so "no cache" is a structural
property of the code path, not merely an accepted flag).

HONEST GAP (constitution SS11.4.6, matching this project's own house
precedent -- affected_set.py's / catchset_compare.py's own "HONEST GAP"
docstring sections): fixtures/backstop/README.md's wire format for `run`
names only `--config --no-cache --out`. No existing config key under
config/fastcycle/fastcycle.yaml enumerates individual GATE scripts --
only config/fastcycle/gate_sites.yaml's 4 coarse SEAM entries (a
different concept: a seam is a FILE that may contain MANY named gates,
not a single-gate manifest). This implementation therefore ADDS a
required `--manifest <gates.json>` flag, reusing catchset_compare.py's
OWN existing gate-manifest schema `{"gates":[{"id":..,"script":..}]}`
verbatim (the only "enumerate every gate" schema already present in this
codebase) rather than inventing a third one.

COMPOSES $FC/gates/gate_runner.sh (plan.md T-C10's Work line: "runs the
full gate set ... with --no-cache and no selection") -- gate_runner.sh
(T-C04/T-C05, tasks.md T070/T071) landed in this checkout during this
same session (confirmed present by a real file check immediately before
this composition was written, constitution SS11.4.6 -- absent at THIS
file's own authoring start, present a short time later as a sibling
subagent's concurrent work landed; re-checked live rather than assumed
stale either way). This subcommand therefore PREFERS composing
gate_runner.sh's default ("verdicts") mode: it synthesises the two
documents that mode's own documented `--config`/`--affected` CLI requires
(gate_runner_order.py's own header comment: `--config` YAML top-level key
`gate_sites: {gate_id: <script path>}`; `--affected` an Affected-Set
document whose `members` array gate_runner_order.py consumes) --
`members` = EVERY gate in --manifest (never a real affected-set narrowing;
"full gate set ... no selection" is satisfied by construction: nothing is
EVER left out of `members`), `determinable: true`, `skipped: []` -- and
invokes `gate_runner.sh --config <synthetic> --affected <synthetic>
--no-cache --out <a.out>` directly, adopting its `--out` document (already
`verdicts/v1`-shaped, plus its own additive `execution_order` field) and
its exit code UNCHANGED (Producer != Verifier, SS11.4.240 -- this file
does not re-implement gate_runner.sh's own ordering/execution logic; both
JSON documents are written as JSON, which IS valid YAML per YAML 1.2 being
a JSON superset -- avoiding a needless extra dependency on the `yaml`
package inside THIS file for a two-key mapping gate_runner_order.py's own
`yaml.safe_load` already parses correctly either way).

FALLBACK (gate_runner.sh absent, or its own invocation could not even
start -- e.g. missing PyYAML on this host, a gate_runner.sh-internal usage
error the synthetic config's own shape could not have caused): this
subcommand runs each manifest gate script DIRECTLY (`sh <script>`),
bounded by --jobs (host-clamped via host_guard.sh, SS12.6/SS12.11/SS12.12,
falling back to N=1 -- fully serial -- if host_guard.sh itself cannot be
found or run, an honest degrade never a guessed cap). This already
satisfies the FULL functional requirement (every gate, uncached,
unconditionally) independently of gate_runner.sh's own availability.

CLI:
    backstop_run.py --config <cfg> --manifest <gates.json> --no-cache
        --out <full_verdicts.json> [--jobs N] [--host-guard <path>]
        [--gate-runner <path>] [--no-compose-gate-runner]

--gate-runner <path>: override the gate_runner.sh location (default:
constitution/scripts/fastcycle/gates/gate_runner.sh, resolved relative to
this file). --no-compose-gate-runner: force the direct-execution fallback
even when gate_runner.sh is present (useful for a caller that wants this
subcommand's own execution mechanics regardless).

--determinism-check is deliberately NOT accepted by this subcommand: real
gate execution is not, in general, hermetic (common-conventions.md /
data-model.md Section 3's own `hermetic: YES | NO(<reason>)` field --
device-state or network-dependent gates key their verdicts on the target
fingerprint precisely because they are NOT byte-for-byte reproducible
runs); offering a flag that could never genuinely pass for a real corpus
would itself be a bluff. C-003 determinism is meaningfully enforced on
`compare` and `freshness-queue` (both pure functions of fixed input
files) instead.

Exit codes (C-001): when composing gate_runner.sh, its own exit code is
adopted UNCHANGED (0 all PASS, 1 any FAIL, 4 any BLIND, 2 usage/config --
gate_runner_order.py's own documented table). In the direct-execution
fallback: 0 = every gate PASS; 1 = >=1 gate FAIL (a finding); 2 = usage/
config error (missing --config, unreadable/malformed --manifest); 4 =
BLIND (--manifest names zero gates, or >=1 gate could not be executed --
no honest verdict is possible over nothing / over a gap).
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys
import time

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_BLIND = 4

SCHEMA = "verdicts/v1"

GATE_TIMEOUT_S = 3600  # a single gate's own runaway bound; never silently hangs forever


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def load_manifest(path):
    """Reads catchset_compare.py's own `{"gates":[{"id":..,"script":..}]}`
    manifest schema, script paths resolved relative to the manifest
    file's own directory (matching catchset_compare.py's
    `load_gate_manifest`)."""
    with open(path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    base = os.path.dirname(os.path.abspath(path))
    gates = []
    for g in manifest.get("gates", []):
        gid = g["id"]
        script = os.path.normpath(os.path.join(base, g["script"]))
        gates.append((gid, script))
    return manifest.get("change_id"), sorted(gates, key=lambda t: t[0])


# ---------------------------------------------------------------------------
# gate_runner.sh composition (preferred path)
# ---------------------------------------------------------------------------

def default_gate_runner_path():
    return os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gate_runner.sh")
    )


def compose_gate_runner(gate_runner_path, gates, change_id, out_path, workdir):
    """Synthesises gate_runner.sh's own required --config/--affected
    documents (gate_sites: {gate_id: script}; an Affected-Set doc whose
    `members` is EVERY gate -- "no selection" by construction) and invokes
    it directly, adopting its --out document + exit code unchanged.
    Written as plain JSON (a valid YAML 1.2 subset), avoiding a needless
    `yaml` import in THIS file for a flat string-to-string mapping.
    Returns (True, exit_code) on a genuine gate_runner.sh invocation, or
    (False, None) if gate_runner.sh could not even be started (fallback
    to direct execution is then this caller's job)."""
    cfg_path = os.path.join(workdir, "gate_runner_config.json")
    with open(cfg_path, "w", encoding="utf-8") as fh:
        json.dump({"gate_sites": {gid: script for gid, script in gates}}, fh)

    affected_path = os.path.join(workdir, "affected.json")
    affected_doc = {
        "determinable": True,
        "members": sorted(gid for gid, _ in gates),
        "skipped": [],
        "fallback_reason": None,
    }
    if change_id is not None:
        affected_doc["change_id"] = change_id
    with open(affected_path, "w", encoding="utf-8") as fh:
        json.dump(affected_doc, fh)

    cmd = ["sh", gate_runner_path, "--config", cfg_path, "--affected", affected_path,
           "--no-cache", "--out", out_path]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=None)
    except OSError as exc:
        sys.stderr.write("backstop_run: could not invoke gate_runner.sh (%s) -- falling back to direct execution\n" % exc)
        return False, None

    if proc.stdout:
        sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    return True, proc.returncode


# ---------------------------------------------------------------------------
# direct-execution fallback
# ---------------------------------------------------------------------------

def clamp_jobs(requested, host_guard_path):
    """Calls host_guard.sh to clamp the requested parallelism to what the
    live host genuinely has headroom for (SS12.6/SS12.11/SS12.12); never
    raises the caller's own request. Falls back to 1 (fully serial) if
    host_guard.sh cannot be found or run -- an honest degrade, never a
    guessed cap (SS11.4.6). Returns (clamped_n, reason)."""
    if not host_guard_path or not os.path.isfile(host_guard_path):
        return 1, "host_guard.sh not found at %s -- serialising (safest default)" % host_guard_path
    try:
        proc = subprocess.run(
            ["sh", host_guard_path, str(requested), "--kind", "jobs"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "host_guard.sh could not run (%s) -- serialising (safest default)" % exc

    n = None
    reason = None
    for line in proc.stdout.splitlines():
        if line.startswith("N="):
            n = line[len("N="):].strip()
        elif line.startswith("REASON="):
            reason = line[len("REASON="):].strip()
    if n is None or not n.isdigit():
        return 1, "host_guard.sh produced no parseable N= line -- serialising (safest default)"
    return max(1, int(n)), (reason or "none")


def run_gate(gid, script, evidence_dir):
    start = time.monotonic()
    if not os.path.isfile(script):
        return {
            "gate_id": gid,
            "verdict": "BLIND",
            "source": "RUN",
            "evidence": None,
            "duration_ms": 0,
        }
    try:
        proc = subprocess.run(
            ["sh", script], capture_output=True, text=True, timeout=GATE_TIMEOUT_S
        )
        rc = proc.returncode
        captured = (proc.stdout or "") + (proc.stderr or "")
    except (OSError, subprocess.TimeoutExpired) as exc:
        rc = None
        captured = "backstop_run: could not execute %s: %s\n" % (script, exc)
    duration_ms = int((time.monotonic() - start) * 1000)

    if rc is None:
        verdict = "BLIND"
    elif rc == 0:
        verdict = "PASS"
    else:
        verdict = "FAIL"

    evidence_rel = "%s.log" % gid
    evidence_path = os.path.join(evidence_dir, evidence_rel)
    with open(evidence_path, "w", encoding="utf-8") as fh:
        fh.write(captured)

    return {
        "gate_id": gid,
        "verdict": verdict,
        "source": "RUN",
        "evidence": evidence_rel,
        "duration_ms": duration_ms,
    }


def run_direct(gates, change_id, out_path, jobs, host_guard_path):
    out_dir = os.path.dirname(os.path.abspath(out_path))
    evidence_dir = os.path.join(out_dir or ".", os.path.basename(out_path) + ".evidence")
    os.makedirs(evidence_dir, exist_ok=True)

    clamped_jobs, guard_reason = clamp_jobs(max(1, jobs), host_guard_path)

    results = [None] * len(gates)
    with concurrent.futures.ThreadPoolExecutor(max_workers=clamped_jobs) as pool:
        futs = {
            pool.submit(run_gate, gid, script, evidence_dir): i
            for i, (gid, script) in enumerate(gates)
        }
        for fut in concurrent.futures.as_completed(futs):
            results[futs[fut]] = fut.result()
    results.sort(key=lambda r: r["gate_id"])

    total = len(results)
    passed = sum(1 for r in results if r["verdict"] == "PASS")
    failed = sum(1 for r in results if r["verdict"] == "FAIL")
    blind = sum(1 for r in results if r["verdict"] == "BLIND")

    doc = {
        "schema": SCHEMA,
        "change_id": change_id,
        "results": results,
        "summary": {"total": total, "pass": passed, "fail": failed, "blind": blind},
    }
    doc["body_hash"] = body_hash({k: v for k, v in doc.items() if k != "run_meta"})
    doc["run_meta"] = {"jobs": clamped_jobs, "host_guard_reason": guard_reason, "evidence_dir": evidence_dir}

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(doc))
        fh.write("\n")

    print(
        "run (direct execution): %d gate(s) (jobs=%d, host_guard=%s) -- %d PASS, "
        "%d FAIL, %d BLIND -- %s written" % (total, clamped_jobs, guard_reason, passed, failed, blind, out_path)
    )

    if blind:
        return EXIT_BLIND
    return EXIT_FINDING if failed else EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="backstop_run.py")
    p.add_argument("--config", required=True)
    p.add_argument("--manifest", required=True)
    p.add_argument("--no-cache", action="store_true")
    p.add_argument("--out", required=True)
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument(
        "--host-guard",
        default=None,
        help="path to host_guard.sh; default: constitution/scripts/fastcycle/"
             "lib/host_guard.sh, resolved relative to this file",
    )
    p.add_argument(
        "--gate-runner",
        default=None,
        help="path to gate_runner.sh; default: constitution/scripts/fastcycle/"
             "gates/gate_runner.sh, resolved relative to this file",
    )
    p.add_argument("--no-compose-gate-runner", action="store_true")
    return p


def main(argv):
    a = build_parser().parse_args(argv[1:])

    if not os.path.isfile(a.config):
        sys.stderr.write("backstop_run: --config not found: %s\n" % a.config)
        return EXIT_USAGE
    if not os.path.isfile(a.manifest):
        sys.stderr.write("backstop_run: --manifest not found: %s\n" % a.manifest)
        return EXIT_USAGE

    try:
        change_id, gates = load_manifest(a.manifest)
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        sys.stderr.write("backstop_run: cannot read/parse --manifest: %s\n" % exc)
        return EXIT_USAGE

    if not gates:
        sys.stderr.write(
            "backstop_run: --manifest %s names zero gates -- no honest verdict "
            "is possible over nothing\n" % a.manifest
        )
        return EXIT_BLIND

    out_dir = os.path.dirname(os.path.abspath(a.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    gate_runner_path = a.gate_runner or default_gate_runner_path()
    if not a.no_compose_gate_runner and os.path.isfile(gate_runner_path):
        import tempfile
        with tempfile.TemporaryDirectory(prefix="backstop_run.") as workdir:
            started, rc = compose_gate_runner(gate_runner_path, gates, change_id, a.out, workdir)
        if started:
            return rc
        # else: fall through to direct execution (compose_gate_runner already
        # reported why on stderr).

    host_guard_default = os.path.normpath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib", "host_guard.sh")
    )
    host_guard_path = a.host_guard or host_guard_default
    return run_direct(gates, change_id, a.out, a.jobs, host_guard_path)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
