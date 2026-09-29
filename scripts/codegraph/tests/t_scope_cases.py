#!/usr/bin/env python3
# ============================================================================
# t_scope_cases.py — behavioural tests for scope_render.py + codegraph_scope_guard.py
# ============================================================================
# Purpose      Test-first (§11.4.224) golden-true / golden-false cases
#              (§11.4.201) on a REAL git fixture (t_scope_fixture.py), driving the
#              REAL runner's scanDirectory through the tools under test.
# Usage        python3 t_scope_cases.py [CASE_ID ...]
#              env SCOPE_TOOL_DIR   dir holding the tools under test (default: ..)
#                  SCOPE_RUNNER_DIST runner lib/dist (default: $CODEGRAPH_RUNNER_DIST)
#                  SCOPE_WORK        scratch dir (default: mkdtemp)
# Inputs       none beyond env
# Outputs      "RESULT <id> PASS|FAIL <desc>" lines; exit 1 on any FAIL
# Side effects fixtures under SCOPE_WORK only
# Dependencies python3 + PyYAML, node, git
# Cross-refs   t_scope_fixture.py, t_scope_mutations.py, run_scope_tests.sh
# ============================================================================
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import t_scope_fixture as fx  # noqa: E402

TOOL = os.environ.get("SCOPE_TOOL_DIR") or os.path.dirname(HERE)
DIST = os.environ.get("SCOPE_RUNNER_DIST") or os.environ.get("CODEGRAPH_RUNNER_DIST", "")
WORK = os.environ.get("SCOPE_WORK") or tempfile.mkdtemp(prefix="t_scope_")
RESULTS = []


def run(args, **kw):
    p = subprocess.run(args, capture_output=True, text=True, **kw)
    return p.returncode, p.stdout, p.stderr


def render(scope, root, *extra):
    return run([sys.executable, os.path.join(TOOL, "scope_render.py"), "--scope", scope, "--root", root, *extra])


def guard(scope, root, *extra):
    rc, out, err = run([sys.executable, os.path.join(TOOL, "codegraph_scope_guard.py"), "--scope", scope,
                        "--root", root, "--dist", DIST, "--work", os.path.join(WORK, "gwork"), *extra])
    rep = None
    m = re.search(r"^SCOPE_GUARD_REPORT (.*)$", err, re.M)
    if m:
        rep = json.loads(m.group(1))
    return rc, out, err, rep


def run_guard_with_dist(f, dist, *extra):
    rc, out, err = run([sys.executable, os.path.join(TOOL, "codegraph_scope_guard.py"), "--scope", f["scope"],
                        "--root", f["root"], "--dist", dist, "--work", os.path.join(WORK, "gwork_alt"), "--print-count", *extra])
    m = re.search(r"^SCOPE_GUARD_REPORT (.*)$", err, re.M)
    return rc, out, err, (json.loads(m.group(1)) if m else None)


def reasons(rep):
    return sorted({v["check"] for v in (rep or {}).get("violations", [])})


def check(cid, desc, ok, detail=""):
    RESULTS.append((cid, bool(ok)))
    print(f"RESULT {cid} {'PASS' if ok else 'FAIL'} {desc}")
    if not ok:
        print(f"  detail[{cid}]: {str(detail)[:1500]}")


def set_count(scope, n):
    t = open(scope).read()
    t = re.sub(r"^accepted_count: .*$", f"accepted_count: {n}", t, flags=re.M)
    open(scope, "w").write(t)


def green_fixture(name):
    """Fixture rendered + accepted: the compliant golden-false state."""
    f = fx.build(os.path.join(WORK, name))
    rc, o, e = render(f["scope"], f["root"], "--write")
    assert rc == 0, (rc, o, e)
    rc, out, err, rep = guard(f["scope"], f["root"], "--print-count")
    n = out.strip().splitlines()[-1]
    set_count(f["scope"], n)
    rc, o, e = render(f["scope"], f["root"], "--write")
    assert rc == 0, (rc, o, e)
    return f


def want(cid):
    sel = sys.argv[1:]
    return not sel or cid in sel


if want("T01"):
    f = fx.build(os.path.join(WORK, "t01"))
    a1, b1 = os.path.join(WORK, "t01_a.json"), os.path.join(WORK, "t01_a.block")
    a2, b2 = os.path.join(WORK, "t01_b.json"), os.path.join(WORK, "t01_b.block")
    r1 = render(f["scope"], f["root"], "--out-config", a1, "--out-gitignore-block", b1)
    r2 = render(f["scope"], f["root"], "--out-config", a2, "--out-gitignore-block", b2)
    ok = r1[0] == 0 and r2[0] == 0 and open(a1).read() == open(a2).read() and open(b1).read() == open(b2).read()
    cfg = json.loads(open(a1).read()) if r1[0] == 0 else {}
    ex = cfg.get("exclude", [])
    gen = cfg.get("_generated", {})
    ok = ok and "/tp_top/" in ex and "/own_sub/vendored_tp/" in ex and not any(p.rstrip("/") == "/own_sub" for p in ex)
    ok = ok and re.fullmatch(r"[0-9a-f]{64}", str(gen.get("scope_sha256", ""))) \
        and re.fullmatch(r"[0-9a-f]{64}", str(gen.get("gitmodules_sha256", "")))
    blk = open(b1).read() if r1[0] == 0 else ""
    ok = ok and blk.startswith("# BEGIN helix-codegraph-scope") and "\n!/build/\n" in blk \
        and blk.rstrip().endswith("# END helix-codegraph-scope")
    check("T01", "render deterministic; third-party roots (incl. nested) excluded; own-org not; provenance + block",
          ok, (r1, r2, ex, gen, blk))

if want("T02"):
    f = fx.build(os.path.join(WORK, "t02"))
    bad = os.path.join(WORK, "t02_bad.yaml")
    open(bad, "w").write("schema_version: 1\nown_orgs: [unclosed\n")
    rc1 = render(bad, f["root"], "--out-config", os.path.join(WORK, "t02.json"))[0]
    # gitlink without any URL in .gitmodules and no override -> refuse
    subprocess.run(["git", "config", "-f", ".gitmodules", "--unset", "submodule.tp_top.url"], cwd=f["root"], check=True)
    rc2, o2, e2 = render(f["scope"], f["root"], "--out-config", os.path.join(WORK, "t02b.json"))
    check("T02", "render fails closed (exit 3) on unparsable scope and on an unclassifiable gitlink",
          rc1 == 3 and rc2 == 3 and "tp_top" in e2, (rc1, rc2, e2))

if want("T03"):
    f = fx.build(os.path.join(WORK, "t03"), count="5")
    rc, out, err, rep = guard(f["scope"], f["root"])
    rs = reasons(rep)
    need = {"third_party_files", "forbidden_class", "negation_target_empty", "stale_render"}
    check("T03", "RED: un-scoped fixture -> guard exit 1 with third-party/secret/qa/negation/stale violations",
          rc == 1 and need.issubset(rs), (rc, rs, err[-1500:]))

if want("T04"):
    try:
        f = green_fixture("t04")
        rc, out, err, rep = guard(f["scope"], f["root"])
        en = set(open(rep["enumeration_file"]).read().split("\n")) if rep else set()
        ok = rc == 0 and not reasons(rep)
        # owned source re-included by the negation; *secret* DIRECTORY kept (files-only exclusion)
        ok = ok and rep["negation_targets"].get("/build/", 0) >= 1 and "app/secretmgr/impl.py" in en
        ok = ok and "own_sub/lib.c" in en and "own_sub/vendored_tp/tp.c" not in en and "tp_top/t.c" not in en
        check("T04", "GREEN: rendered fixture -> guard exit 0; build/ re-included; own-org in; third-party out",
              ok, (rc, reasons(rep), err[-1500:]))
    except AssertionError as e:
        check("T04", "GREEN: rendered fixture -> guard exit 0", False, e)

if want("T05"):
    f = green_fixture("t05")
    rc0 = render(f["scope"], f["root"], "--check")[0]
    cg = os.path.join(f["root"], "codegraph.json")
    orig = open(cg).read()
    open(cg, "w").write(orig.replace('"/tp_top/"', '"/tp_topX/"'))
    rc1 = render(f["scope"], f["root"], "--check")[0]
    open(cg, "w").write(orig)
    gi = os.path.join(f["root"], ".gitignore")
    gorig = open(gi).read()
    open(gi, "w").write(gorig + "build/\n")          # content after END -> block not last
    rc2 = render(f["scope"], f["root"], "--check")[0]
    open(gi, "w").write(re.sub(r"# BEGIN helix-codegraph-scope.*# END helix-codegraph-scope\n", "", gorig, flags=re.S))
    rc3 = render(f["scope"], f["root"], "--check")[0]
    check("T05", "--check: fresh=0; edited config=1; block not last=1; block missing=1",
          (rc0, rc1, rc2, rc3) == (0, 1, 1, 1), (rc0, rc1, rc2, rc3))

if want("T06"):
    f = green_fixture("t06")
    with open(f["scope"], "a") as fh:
        fh.write("# edited after render\n")
    rc, out, err, rep = guard(f["scope"], f["root"])
    check("T06", "stale render (scope.yaml edited, not re-rendered) -> guard exit 1 stale_render",
          rc == 1 and "stale_render" in reasons(rep), (rc, reasons(rep)))

if want("T07"):
    f = green_fixture("t07")
    r1 = guard(f["scope"], f["root"])
    r2 = guard(f["scope"], f["root"])
    check("T07", "golden-false: compliant unchanged fixture PASSes twice with identical report",
          r1[0] == 0 and r2[0] == 0 and r1[3] == r2[3], (r1[0], r2[0], reasons(r1[3])))

if want("T08"):
    f = green_fixture("t08")
    t = open(f["scope"]).read().replace("regex: '(^|/)qa-results/'", "regex: '(^|/)qa-resultz/'")
    open(f["scope"], "w").write(t)
    render(f["scope"], f["root"], "--write")
    rc, out, err, rep = guard(f["scope"], f["root"])
    check("T08", "blind forbidden-class regex (positive needle unmatched) -> guard exit 4",
          rc == 4 and "control_needle" in reasons(rep), (rc, reasons(rep)))

if want("T09"):
    f = green_fixture("t09")
    t = open(f["scope"]).read().replace('present: ["src/main.c"]', 'present: ["src/main.c", "src/not_there.c"]')
    open(f["scope"], "w").write(t)
    render(f["scope"], f["root"], "--write")
    rc, out, err, rep = guard(f["scope"], f["root"])
    check("T09", "enumeration control needle absent -> guard exit 4", rc == 4 and "control_needle" in reasons(rep),
          (rc, reasons(rep)))

if want("T10"):
    f = green_fixture("t10")
    t = open(f["scope"]).read().replace('project_excludes: ["/rubbish/"]', 'project_excludes: ["/rubbish/", "/own_sub/"]')
    open(f["scope"], "w").write(t)
    render(f["scope"], f["root"], "--write")
    rc, out, err, rep = guard(f["scope"], f["root"])
    check("T10", "own-org submodule excluded -> guard exit 1 own_org_empty", rc == 1 and "own_org_empty" in reasons(rep),
          (rc, reasons(rep)))

if want("T11"):
    f = green_fixture("t11")
    t = open(f["scope"]).read()
    t = re.sub(r"^accepted_count: .*$", "accepted_count: 1000", t, flags=re.M)
    open(f["scope"], "w").write(t)
    render(f["scope"], f["root"], "--write")
    rc, out, err, rep = guard(f["scope"], f["root"])
    check("T11", "enumerated count outside tolerance -> guard exit 1 count_out_of_tolerance",
          rc == 1 and "count_out_of_tolerance" in reasons(rep), (rc, reasons(rep)))

if want("T12"):
    f = green_fixture("t12")
    rc, out, err, rep = guard(f["scope"], f["root"], "--print-count")
    lines = out.strip().splitlines()
    check("T12", "--print-count prints exactly the integer count on stdout",
          rc == 0 and len(lines) == 1 and lines[0].isdigit() and int(lines[0]) == rep["count"], (rc, out))

if want("T13"):
    # contract-only needs no accepted count: build + render only, so a DRIFTED runner (mutation M3/M3b) reaches
    # the contract probe instead of crashing inside green_fixture's --print-count (which the drift exits 2 before).
    f = fx.build(os.path.join(WORK, "t13"))
    assert render(f["scope"], f["root"], "--write")[0] == 0
    rc, out, err, rep = guard(f["scope"], f["root"], "--contract-only")
    check("T13", "--contract-only on the installed runner -> exit 0 with all contract checks ok",
          rc == 0 and rep and all(c["ok"] for c in rep["contract"]["checks"] if not c.get("info")), (rc, err[-800:]))

if want("T14"):
    # exclusion voided by a later negation (last-match-wins in the engine's `ignore` matcher): the renderer must
    # REFUSE (exit 3, naming both patterns); the intended carve-out pair (`*secret*` + `!*secret*/`) alone is fine.
    def with_secrets(f, lst):
        t = open(f["scope"]).read()
        t2 = re.sub(r"^  secrets: \[.*\]$", "  secrets: " + lst, t, flags=re.M)
        assert t2 != t or lst in t
        open(f["scope"], "w").write(t2)
    f = fx.build(os.path.join(WORK, "t14"))
    with_secrets(f, '[".env", "*.env", "**/secrets/", "*secret*", "!*secret*/"]')          # BAD order
    rb, ob, eb = render(f["scope"], f["root"], "--out-config", os.path.join(WORK, "t14_bad.json"))
    with_secrets(f, '[".env", "*.env", "*secret*", "!*secret*/", "**/secrets/"]')          # GOOD order
    rg, og, eg = render(f["scope"], f["root"], "--out-config", os.path.join(WORK, "t14_good.json"))
    check("T14", "render refuses an exclusion voided by a later negation (exit 3, names both); carve-out pair in safe order renders",
          rb == 3 and "**/secrets/" in eb and "!*secret*/" in eb and rg == 0, (rb, eb[-500:], rg, eg[-300:]))

if want("T15"):
    # `include_patterns` -> codegraph.json `include`: forces source that a NESTED .gitignore hides back into the index
    # (root .gitignore negations cannot reach it); an include target that enumerates nothing is a violation.
    def with_include(f, lst):
        t = open(f["scope"]).read()
        t2 = re.sub(r"^include_patterns: .*$", "include_patterns: " + lst, t, flags=re.M)
        assert t2 != t or lst in t
        open(f["scope"], "w").write(t2)
    def enumerated(rep):
        return set(open(rep["enumeration_file"]).read().split("\n")) if rep else set()
    f = fx.build(os.path.join(WORK, "t15"))
    with_include(f, "[]")
    assert render(f["scope"], f["root"], "--write")[0] == 0
    rc0, out0, err0, rep0 = guard(f["scope"], f["root"], "--print-count")
    absent = "app/vend/gen/g.py" not in enumerated(rep0) and "app/vend/keep.py" in enumerated(rep0)
    with_include(f, '["/app/vend/gen/"]')
    assert render(f["scope"], f["root"], "--write")[0] == 0
    cfg = json.loads(open(os.path.join(f["root"], "codegraph.json")).read())
    rc1, out1, err1, rep1 = guard(f["scope"], f["root"], "--print-count")
    present = "app/vend/gen/g.py" in enumerated(rep1) and cfg.get("include") == ["/app/vend/gen/"]
    with_include(f, '["/app/vend/nothing_here/"]')
    assert render(f["scope"], f["root"], "--write")[0] == 0
    rc2, out2, err2, rep2 = guard(f["scope"], f["root"], "--print-count")
    empty = rc2 == 1 and "include_target_empty" in reasons(rep2)
    check("T15", "include_patterns: nested-.gitignore'd source absent without it, enumerated with it (config `include` rendered); empty include target -> violation",
          absent and present and empty, (absent, present, empty, rc0, rc1, rc2, cfg.get("include"), reasons(rep2)))

if want("T16"):
    # a typo'd / unknown top-level scope key must FAIL CLOSED (a silently ignored key silently drops a rule)
    f = fx.build(os.path.join(WORK, "t16"))
    with open(f["scope"], "a") as fh:
        fh.write("include_pattern: [\"/app/vend/gen/\"]\n")          # typo of include_patterns
    rc, o, e = render(f["scope"], f["root"], "--out-config", os.path.join(WORK, "t16.json"))
    check("T16", "render fails closed (exit 3) on an unknown top-level scope key, naming it",
          rc == 3 and "include_pattern" in e, (rc, e[-400:]))

if want("T17"):
    # the runner silently switches from `git ls-files` to a filesystem walk when git's listing exceeds its execFileSync
    # maxBuffer (measured on a 1.1M-file tree: 144 MB > 50 MiB -> ENOBUFS -> walk). The file set semantics differ (nested
    # .gitignore drops TRACKED files, dir symlinks alias paths), so the guard must REPORT the mode it measured.
    import shutil
    f = green_fixture("t17")
    rc, out, err, rep = guard(f["scope"], f["root"], "--print-count")
    mode_pristine = (rep or {}).get("scan_mode")
    md = os.path.join(WORK, "t17_runner")
    shutil.rmtree(md, ignore_errors=True)
    os.makedirs(md)
    shutil.copytree(DIST, os.path.join(md, "dist"), symlinks=True)
    nm = os.path.join(os.path.dirname(os.path.abspath(DIST)), "node_modules")
    if os.path.isdir(nm):
        os.symlink(nm, os.path.join(md, "node_modules"))
    ip = os.path.join(md, "dist", "extraction", "index.js")
    src = open(ip).read()
    old = "maxBuffer: 50 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true };\n    // Tracked files."
    n1 = src.count(old)
    open(ip, "w").write(src.replace(old, "maxBuffer: 16, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true };\n    // Tracked files."))
    rc2, out2, err2, rep2 = run_guard_with_dist(f, os.path.join(md, "dist"))
    mode_tiny = (rep2 or {}).get("scan_mode")
    check("T17", "scan mode is reported: git on the pristine runner, walk_fallback:ENOBUFS when git's listing overflows the runner's buffer",
          mode_pristine == "git" and n1 == 1 and str(mode_tiny).startswith("walk_fallback:") and "ENOBUFS" in str(mode_tiny),
          (mode_pristine, n1, mode_tiny, rc2, err2[-300:]))

fails = [c for c, ok in RESULTS if not ok]
print(f"SUMMARY cases={len(RESULTS)} fail={len(fails)}")
sys.exit(1 if fails else 0)
