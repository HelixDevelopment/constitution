#!/usr/bin/env python3
# ============================================================================
# t_scope_mutations.py — paired §1.1 mutations for the CodeGraph scope tooling
# ============================================================================
# Purpose      Prove every load-bearing check of scope_render.py /
#              codegraph_scope_guard.py is FALSIFIABLE: each mutation disables
#              one mechanism in a SCRATCH COPY (tools or runner) and the named
#              behavioural case from t_scope_cases.py MUST then FAIL. A mutation
#              whose anchor is not found FAILs (a blind mutation proves nothing,
#              §11.4.273). The golden-false control runs the same case on the
#              unmutated tools and MUST PASS (§11.4.201).
# Usage        python3 t_scope_mutations.py [MUT_ID ...]
#              env SCOPE_TOOL_DIR, SCOPE_RUNNER_DIST, SCOPE_WORK (as t_scope_cases.py)
# Inputs       the tools under test (read only) and the runner dist (read only)
# Outputs      "RESULT <id> PASS|FAIL <desc>" lines; exit 1 on any FAIL
# Side effects scratch copies under SCOPE_WORK only; never edits the real tools
#              or the real runner.
# Dependencies python3 + PyYAML, node, git
# Cross-refs   t_scope_cases.py, run_scope_tests.sh, constitution §1.1 / §11.4.201
# ============================================================================
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.environ.get("SCOPE_TOOL_DIR") or os.path.dirname(HERE)
DIST = os.environ.get("SCOPE_RUNNER_DIST") or os.environ.get("CODEGRAPH_RUNNER_DIST", "")
WORK = os.environ.get("SCOPE_WORK") or tempfile.mkdtemp(prefix="t_scope_mut_")
os.makedirs(WORK, exist_ok=True)
RESULTS = []
TOOL_FILES = ["scope_render.py", "codegraph_scope_guard.py", "scope_enumerate.js"]


def check(mid, desc, ok, detail=""):
    RESULTS.append((mid, bool(ok)))
    print(f"RESULT {mid} {'PASS' if ok else 'FAIL'} {desc}")
    if not ok:
        print(f"  detail[{mid}]: {str(detail)[:1500]}")


def mutated_tools(name, fname, old, new):
    """Scratch copy of the tool dir with ONE exact-text substitution in `fname`."""
    d = os.path.join(WORK, "tools_" + name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for f in TOOL_FILES:
        shutil.copy2(os.path.join(TOOL, f), os.path.join(d, f))
    p = os.path.join(d, fname)
    src = open(p).read()
    n = src.count(old)
    if n == 1:
        open(p, "w").write(src.replace(old, new))
    return d, n


def mutated_runner(name, rel, old, new):
    """Scratch copy of the runner lib/dist (node_modules symlinked) with ONE substitution."""
    base = os.path.join(WORK, "runner_" + name, "lib")
    shutil.rmtree(os.path.dirname(base), ignore_errors=True)
    os.makedirs(base)
    shutil.copytree(DIST, os.path.join(base, "dist"), symlinks=True)
    nm = os.path.join(os.path.dirname(os.path.abspath(DIST)), "node_modules")
    if os.path.isdir(nm):
        os.symlink(nm, os.path.join(base, "node_modules"))
    p = os.path.join(base, "dist", rel)
    src = open(p).read()
    n = src.count(old)
    if n == 1:
        open(p, "w").write(src.replace(old, new))
    return os.path.join(base, "dist"), n


def run_case(case, tool_dir=TOOL, dist=DIST, tag="x"):
    env = dict(os.environ, SCOPE_TOOL_DIR=tool_dir, SCOPE_RUNNER_DIST=dist,
               SCOPE_WORK=os.path.join(WORK, "cases_" + tag))
    p = subprocess.run([sys.executable, os.path.join(HERE, "t_scope_cases.py"), case],
                       capture_output=True, text=True, env=env)
    line = next((ln for ln in p.stdout.splitlines() if ln.startswith(f"RESULT {case} ")), "")
    return p.returncode, line, p.stdout[-1200:] + p.stderr[-600:]


def want(mid):
    sel = sys.argv[1:]
    return not sel or mid in sel


# golden-false control: unmutated tools, compliant fixture -> the cases PASS
if want("M0"):
    # every mutant below is judged on cases that MUST already PASS unmutated (else a "kill" is a vacuous FAIL)
    res0 = [run_case(c, tag="m0_" + c.lower()) for c in ("T03", "T04", "T06", "T07", "T08", "T10", "T11", "T13", "T14", "T15", "T16", "T17")]
    check("M0", "golden-false: unmutated tools -> T03/T04/T06/T07/T08/T10/T11/T13/T14/T15/T16/T17 (the cases the mutants rely on) all PASS",
          all(rc == 0 and " PASS " in line for rc, line, _t in res0), [(ln or t) for _rc, ln, t in res0 if " PASS " not in ln])

if want("M1"):
    d, n = mutated_tools("m1", "scope_render.py",
                         "third_party.append(rel)  # §1.1-anchor:third_party_derivation",
                         "pass  # mutated: third-party derivation removed")
    rc, line, tail = run_case("T04", tool_dir=d, tag="m1") if n == 1 else (0, "", "anchor count=%d" % n)
    # the guard's own third-party derivation must also be killable -> T03 must fail
    check("M1", "remove third-party derivation in the renderer -> T04 (GREEN) FAILs", n == 1 and rc != 0
          and " FAIL " in line, tail)

if want("M1g"):
    d, n = mutated_tools("m1g", "codegraph_scope_guard.py",
                         "hits.setdefault(root, []).append(f)  # §1.1-anchor:third_party_check",
                         "pass  # mutated: third-party check removed")
    rc, line, tail = run_case("T03", tool_dir=d, tag="m1g") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M1g", "remove the guard's third-party-files check -> T03 (RED detection) FAILs",
          n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M2"):
    d, n = mutated_tools("m2", "scope_render.py",
                         "body = [\"!\" + p for p in negations]  # §1.1-anchor:negation_emit",
                         "body = []  # mutated: negation block emptied")
    rc, line, tail = run_case("T04", tool_dir=d, tag="m2") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M2", "drop the .gitignore negation lines -> T04 re-include check FAILs",
          n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M3"):
    rd, n = mutated_runner("m3", "project-config.js", "exports.PROJECT_CONFIG_FILENAME = 'codegraph.json';",
                           "exports.PROJECT_CONFIG_FILENAME = 'codegraph.jsonc';")
    rc, line, tail = run_case("T13", dist=rd, tag="m3") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M3", "runner copy reads a different config filename -> T13 contract drift detected (T13 FAILs)",
          n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M3b"):
    rd, n = mutated_runner("m3b", "project-config.js", "const exclude = extractExclude(parsed, file);",
                           "const exclude = [];")
    rc, line, tail = run_case("T13", dist=rd, tag="m3b") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M3b", "runner copy ignores the `exclude` key -> T13 contract drift detected (T13 FAILs)",
          n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M4"):
    d, n = mutated_tools("m4", "codegraph_scope_guard.py",
                         "NEEDLE_CHECK = True  # §1.1-anchor:control_needle",
                         "NEEDLE_CHECK = False  # mutated: control needle stripped")
    rc, line, tail = run_case("T08", tool_dir=d, tag="m4") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M4", "strip the control needle -> T08 (blind regex) FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M5"):
    d, n = mutated_tools("m5", "codegraph_scope_guard.py",
                         "violations.append({\"check\": \"stale_render\"",
                         "(lambda *a, **k: None)({\"check\": \"stale_render\"")
    rc, line, tail = run_case("T06", tool_dir=d, tag="m5") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M5", "remove the stale-render check -> T06 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M6"):
    d, n = mutated_tools("m6", "scope_render.py",
                         "unprobed = check_exclusion_order(exclude)  # §1.1-anchor:order_lint_call",
                         "unprobed = 0  # mutated: exclusion-order lint removed")
    rc, line, tail = run_case("T14", tool_dir=d, tag="m6") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M6", "remove the exclusion-order lint call -> T14 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M7"):
    d, n = mutated_tools("m7", "scope_render.py",
                         "reasserted = any(not q.startswith(\"!\")",
                         "reasserted = True or any(not q.startswith(\"!\")")
    rc, line, tail = run_case("T14", tool_dir=d, tag="m7") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M7", "lint treats every voided exclusion as re-asserted -> T14 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M8"):
    d, n = mutated_tools("m8", "codegraph_scope_guard.py",
                         "violations.append({\"check\": \"forbidden_class\"",
                         "(lambda *a, **k: None)({\"check\": \"forbidden_class\"")
    rc, line, tail = run_case("T03", tool_dir=d, tag="m8") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M8", "remove the guard's forbidden-class check -> T03 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M9"):
    d, n = mutated_tools("m9", "codegraph_scope_guard.py",
                         "violations.append({\"check\": \"negation_target_empty\"",
                         "(lambda *a, **k: None)({\"check\": \"negation_target_empty\"")
    rc, line, tail = run_case("T03", tool_dir=d, tag="m9") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M9", "remove the negation-target-empty check -> T03 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M10"):
    d, n = mutated_tools("m10", "codegraph_scope_guard.py",
                         "violations.append({\"check\": \"own_org_empty\"",
                         "(lambda *a, **k: None)({\"check\": \"own_org_empty\"")
    rc, line, tail = run_case("T10", tool_dir=d, tag="m10") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M10", "remove the own-org-empty check -> T10 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M11"):
    d, n = mutated_tools("m11", "codegraph_scope_guard.py",
                         "elif abs(len(files) - accepted) * 100.0 > tol * accepted:",
                         "elif False:  # mutated: tolerance check removed")
    rc, line, tail = run_case("T11", tool_dir=d, tag="m11") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M11", "remove the count-tolerance check -> T11 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M12"):
    d, n = mutated_tools("m12", "scope_render.py",
                         "cfg[\"include\"] = include      # §1.1-anchor:include_emit",
                         "pass      # mutated: include not rendered")
    rc, line, tail = run_case("T15", tool_dir=d, tag="m12") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M12", "stop rendering the include patterns -> T15 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M13"):
    d, n = mutated_tools("m13", "scope_render.py",
                         "    if unknown:\n        raise ScopeError(\"unknown top-level scope key(s)",
                         "    if False:\n        raise ScopeError(\"unknown top-level scope key(s)")
    rc, line, tail = run_case("T16", tool_dir=d, tag="m13") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M13", "accept unknown top-level scope keys -> T16 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M14"):
    d, n = mutated_tools("m14", "codegraph_scope_guard.py",
                         "violations.append({\"check\": \"include_target_empty\"",
                         "(lambda *a, **k: None)({\"check\": \"include_target_empty\"")
    rc, line, tail = run_case("T15", tool_dir=d, tag="m14") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M14", "remove the include-target-empty check -> T15 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

if want("M15"):
    d, n = mutated_tools("m15", "scope_enumerate.js",
                         "a === 'ls-files -z -s --recurse-submodules'",
                         "a === 'ls-files-mutated-never-matches'")
    rc, line, tail = run_case("T17", tool_dir=d, tag="m15") if n == 1 else (0, "", "anchor count=%d" % n)
    check("M15", "scan-mode probe never sees the listing throw -> T17 FAILs", n == 1 and rc != 0 and " FAIL " in line, tail)

fails = [m for m, ok in RESULTS if not ok]
print(f"SUMMARY mutations={len(RESULTS)} fail={len(fails)}")
sys.exit(1 if fails else 0)
