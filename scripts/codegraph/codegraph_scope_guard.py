#!/usr/bin/env python3
# ============================================================================
# codegraph_scope_guard.py — proves the CodeGraph index SCOPE is the mandated one
# ============================================================================
# Purpose      Measure, with the ENGINE'S OWN file discovery (scope_enumerate.js ->
#              the installed runner's scanDirectory), which files a CodeGraph
#              (>= 1.6) index would contain for a project, and FAIL when that set
#              violates the mandated scope (constitution §11.4.79 third-party
#              submodules out / own-org in; §11.4.78 first-party source — AOSP
#              included — indexable, secret / bulk classes out; §11.4.10 secrets).
#              Every "zero" it reports is control-needled (§11.4.273): a blind
#              instrument exits 4, never a clean pass.
# Usage        codegraph_scope_guard.py --scope <scope.yaml> --root <project root>
#                  [--dist <runner lib/dist>] [--work <scratch dir>]
#                  [--print-count]          measure: print the enumerated count on
#                                           stdout (count acceptance is skipped)
#                  [--contract-only]        run only the runner-contract probe
#                  [--dry-run-dir <dir>]    render scope -> <dir> and enumerate with
#                                           the rendered files OVERLAID: nothing is
#                                           written to <root>, stale_render is n/a
#                  [--explain]              (with --dry-run-dir) also census the
#                                           tracked source still dropped by built-in
#                                           skips -> <dir>/explain_dropped.tsv
#                  [--report-out <file>]    also write the report JSON to <file>
#              codegraph_scope_guard.py --resolve-dist [--dist D] [--scope S]
# Inputs       scope.yaml (schema: scope.example.yaml); the project git tree; the
#              runner dist (resolution: --dist, scope runner.dist_dir,
#              $CODEGRAPH_RUNNER_DIST, then the `codegraph` executable on PATH).
# Outputs      stderr: one "SCOPE_GUARD_REPORT <json>" line (deterministic: sorted
#              keys, no timestamps/durations) + a human summary; stdout: only the
#              count (--print-count) or the dist path (--resolve-dist).
# Side effects reads only. Writes ONLY under --work / --dry-run-dir, both of which
#              are REFUSED (exit 3) when inside <root>. Never opens a .codegraph
#              database or lock; never runs codegraph init/index/sync.
# Exit codes   0 scope proven | 1 violations | 2 runner contract drift (the engine
#              no longer behaves as this tooling assumes) | 3 fail-closed (unparsable
#              scope, unloadable runner, unclassifiable gitlink, usage, unsafe path)
#              | 4 control needle blind (an instrument cannot see; result void)
# Violation checks   third_party_files, forbidden_class, negation_target_empty, include_target_empty,
#              stale_render, own_org_empty, count_out_of_tolerance, control_needle,
#              runner_contract, render_nondeterministic
# Dependencies python3 (+PyYAML via scope_render.py), node >= 18, git
# Cross-refs   scope_render.py, scope_enumerate.js, scope.example.yaml,
#              tests/run_scope_tests.sh, docs/scripts/codegraph_scope_guard.md,
#              constitution §11.4.10 / §11.4.78 / §11.4.79 / §11.4.201 / §11.4.273
# ============================================================================
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scope_render as sr  # noqa: E402  (sibling module; mutation copies keep both in one dir)

ENUM_JS = os.path.join(HERE, "scope_enumerate.js")
NEEDLE_CHECK = True  # §1.1-anchor:control_needle
SAMPLE = 5


class GuardError(Exception):
    """Fail-closed condition -> exit 3."""


# ---- runner resolution -------------------------------------------------------------
def dist_ok(d):
    return bool(d) and os.path.isfile(os.path.join(d, "extraction", "index.js")) \
        and os.path.isfile(os.path.join(d, "project-config.js"))


def resolve_dist(explicit, scope):
    """First usable of: --dist, scope runner.dist_dir, $CODEGRAPH_RUNNER_DIST, PATH `codegraph`.
    An EXPLICIT choice that is unusable is an error — it never falls through silently."""
    for label, cand in (("--dist", explicit), ("scope runner.dist_dir", ((scope or {}).get("runner") or {}).get("dist_dir")),
                        ("$CODEGRAPH_RUNNER_DIST", os.environ.get("CODEGRAPH_RUNNER_DIST"))):
        if cand:
            if dist_ok(cand):
                return os.path.abspath(cand)
            raise GuardError("%s=%r is not a runner lib/dist (needs extraction/index.js + project-config.js)" % (label, cand))
    exe = shutil.which("codegraph")
    if exe:
        base = os.path.dirname(os.path.realpath(exe))
        pats = [os.path.join(base, "node_modules", "@colbymchenry", "codegraph-*", "lib", "dist"),
                os.path.join(base, "lib", "dist"), os.path.join(base, "..", "lib", "dist")]
        for pat in pats:
            for cand in sorted(glob.glob(pat)):
                if dist_ok(cand):
                    return os.path.abspath(cand)
    raise GuardError("runner lib/dist not found: pass --dist, set runner.dist_dir or $CODEGRAPH_RUNNER_DIST")


# ---- node bridge ---------------------------------------------------------------------
def node_bridge(args):
    node = os.environ.get("SCOPE_NODE") or shutil.which("node")
    if not node:
        raise GuardError("node not found on PATH")
    p = subprocess.run([node, ENUM_JS] + args, capture_output=True, text=True)
    last = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else ""
    try:
        j = json.loads(last)
    except ValueError:
        j = None
    return p.returncode, j, p.stderr


# ---- path matching ---------------------------------------------------------------------
gitignore_to_regex = sr.gitignore_to_regex   # single implementation (scope_render.py)


def under_counts(files, roots):
    """{root: number of files with root as ANY ancestor directory}."""
    rs = set(roots)
    cnt = {r: 0 for r in roots}
    for f in files:
        parts = f.split("/")
        for i in range(1, len(parts)):
            r = "/".join(parts[:i])
            if r in rs:
                cnt[r] += 1
    return cnt


def third_party_hits(files, tp_roots):
    """{third-party root: [enumerated files under it]} (outermost matching root)."""
    hits = {}
    tp = set(tp_roots)
    for f in files:
        parts = f.split("/")
        for i in range(1, len(parts)):
            root = "/".join(parts[:i])
            if root in tp:
                hits.setdefault(root, []).append(f)  # §1.1-anchor:third_party_check
                break
    return hits


def inside(root, path):
    r, p = os.path.realpath(root), os.path.realpath(path)
    return p == r or p.startswith(r + os.sep)


# ---- scope sections the renderer does not validate --------------------------------------
def load_guard_sections(scope):
    fcs = scope.get("forbidden_classes")
    if not isinstance(fcs, list) or not fcs:
        raise GuardError("scope forbidden_classes missing/empty: the §11.4.78 must-exclude classes cannot be verified")
    classes = []
    for c in fcs:
        if not isinstance(c, dict) or not all(isinstance(c.get(k), str) and c.get(k) for k in ("name", "regex", "positive", "negative")):
            raise GuardError("forbidden_classes entries need name/regex/positive/negative strings: %r" % (c,))
        try:
            rx = re.compile(c["regex"])
        except re.error as e:
            raise GuardError("forbidden class %s: bad regex: %s" % (c["name"], e))
        classes.append((c["name"], rx, c["positive"], c["negative"]))
    ctl = scope.get("enumeration_controls") or {}
    present = list(ctl.get("present") or [])
    fabricated = list(ctl.get("fabricated") or [])
    acc = scope.get("accepted_count", 0)
    tol = scope.get("tolerance_pct", 0)
    if not isinstance(acc, int) or isinstance(acc, bool) or acc < 0 or not isinstance(tol, (int, float)) or tol < 0:
        raise GuardError("accepted_count must be an int >= 0 and tolerance_pct a number >= 0")
    return classes, present, fabricated, acc, tol


# ---- the evaluation ---------------------------------------------------------------------
def evaluate(a, scope, d, cfg_name, cfg_text, block, dist, work, report):
    violations = report["violations"]
    classes, present, fabricated, accepted, tol = load_guard_sections(scope)
    root = os.path.abspath(a.root)
    enum_file = os.path.join(work, "enumerated.txt")
    if os.path.exists(enum_file):
        os.remove(enum_file)                 # never let a stale file stand in for this run's evidence
    roots = sorted(set(d["own"]) | set(d["third_party"]))
    roots_file = os.path.join(work, "roots.json")
    with open(roots_file, "w") as f:
        json.dump(roots, f)
    args = ["enumerate", "--dist", dist, "--root", root, "--out", enum_file, "--config-filename", cfg_name,
            "--roots-file", roots_file]
    if a.dry_run_dir:
        args += ["--overlay-config", os.path.join(a.dry_run_dir, cfg_name),
                 "--overlay-gitignore", os.path.join(a.dry_run_dir, "gitignore.overlay")]
    rc, j, err = node_bridge(args)
    if rc != 0 or not j or not j.get("ok") or not os.path.isfile(enum_file):
        raise GuardError("enumeration failed (rc=%s): %s" % (rc, (j or {}).get("error") or err[-300:]))
    with open(enum_file, encoding="utf-8") as f:
        files = [ln for ln in f.read().split("\n") if ln]
    report["count"] = len(files)
    report["enumeration_file"] = enum_file
    report["runner"] = {"version": j.get("runner_version"), "config_filename": j.get("runner_config_filename")}
    report["scan_mode"] = j.get("scan_mode")     # "git" | "walk_fallback:<reason>" (informational: file-set semantics differ)
    census = j.get("root_census") or {}

    # --- control needles (§11.4.273): the instrument must be able to see before a zero counts ---
    controls = report["controls"]
    if NEEDLE_CHECK:
        for name, rx, pos, neg in classes:
            ok = bool(rx.search(pos)) and not rx.search(neg)
            controls.append({"name": "forbidden_class:%s" % name, "ok": ok})
            if not ok:
                violations.append({"check": "control_needle", "what": "forbidden_class:%s" % name,
                                   "detail": "positive needle %r must match and negative needle %r must not" % (pos, neg)})
        fset = set(files)
        if not files:
            violations.append({"check": "control_needle", "what": "enumeration_empty",
                               "detail": "the runner enumerated zero files: the instrument is blind, every zero below is void"})
        for p in present:
            ok = p in fset
            controls.append({"name": "present:%s" % p, "ok": ok})
            if not ok:
                violations.append({"check": "control_needle", "what": "present:%s" % p,
                                   "detail": "control path is not enumerated"})
        for p in fabricated:
            ok = p not in fset
            controls.append({"name": "fabricated:%s" % p, "ok": ok})
            if not ok:
                violations.append({"check": "control_needle", "what": "fabricated:%s" % p,
                                   "detail": "a fabricated path was enumerated: the instrument invents files"})

    # --- stale render (on-disk files != the render of the current scope + .gitmodules) ---
    if a.dry_run_dir:
        report["stale_render"] = "not_applicable_dry_run"
    else:
        reasons = sr.check_on_disk(root, cfg_name, cfg_text, block)
        if reasons:
            violations.append({"check": "stale_render", "reasons": sorted(reasons)})

    # --- third-party files enumerated (§11.4.79) ---
    hits = third_party_hits(files, d["third_party"])
    report["third_party"] = {"roots": len(d["third_party"]), "files_enumerated": sum(len(v) for v in hits.values())}
    if hits:
        violations.append({"check": "third_party_files", "roots": {r: len(v) for r, v in sorted(hits.items())},
                           "sample": sorted(f for v in hits.values() for f in v)[:SAMPLE]})
    proven, vacuous = [], []
    for r in d["third_party"]:
        c = census.get(r) or {}
        (proven if (c.get("checked_out") and c.get("tracked_source", 0) > 0) else vacuous).append(r)
    report["third_party"]["exclusion_proven_on_roots"] = len(proven)      # tracked source present AND zero enumerated
    report["third_party"]["vacuous_roots"] = sorted(vacuous)              # nothing to exclude: zero proves nothing

    # --- forbidden classes (§11.4.10 / §11.4.78) ---
    for name, rx, _pos, _neg in classes:
        bad = sorted(f for f in files if rx.search(f))
        if bad:
            violations.append({"check": "forbidden_class", "class": name, "count": len(bad), "sample": bad[:SAMPLE]})

    # --- negation targets must enumerate something (the negation actually worked) ---
    negs = list(scope.get("reinclude_negations") or [])
    report["negation_targets"] = {}
    for pat in negs:
        rx = gitignore_to_regex(pat)
        n = sum(1 for f in files if rx.match(f))
        report["negation_targets"][pat] = n
        if n == 0:
            violations.append({"check": "negation_target_empty", "pattern": pat})

    # --- include targets must enumerate something (the forced-in source really arrived) ---
    report["include_targets"] = {}
    for pat in list(scope.get("include_patterns") or []):
        rx = gitignore_to_regex(pat)
        n = sum(1 for f in files if rx.match(f))
        report["include_targets"][pat] = n
        if n == 0:
            violations.append({"check": "include_target_empty", "pattern": pat})

    # --- own-org roots must contribute (§11.4.79) ---
    own_counts = under_counts(files, d["own"])
    report["own_org"] = {"roots": len(d["own"]), "files_enumerated": {r: own_counts[r] for r in sorted(own_counts)},
                         "not_checked_out": sorted(r for r in d["own"] if not (census.get(r) or {}).get("checked_out"))}
    for r in d["own"]:
        c = census.get(r) or {}
        if c.get("checked_out") and c.get("tracked_source", 0) > 0 and own_counts[r] == 0:
            violations.append({"check": "own_org_empty", "root": r, "tracked_source": c["tracked_source"]})

    # --- accepted count ---
    if not a.print_count:
        if accepted <= 0:
            violations.append({"check": "count_out_of_tolerance", "count": len(files), "accepted": accepted,
                               "detail": "accepted_count not set (0): measure with --print-count, review, then set it"})
        elif abs(len(files) - accepted) * 100.0 > tol * accepted:
            violations.append({"check": "count_out_of_tolerance", "count": len(files), "accepted": accepted,
                               "tolerance_pct": tol})
    return files, roots


def dry_run_prepare(a, scope, cfg_text, block, cfg_name, root, d):
    """Render into --dry-run-dir; prove determinism; return nothing (overlay files are the product)."""
    dd = os.path.abspath(a.dry_run_dir)
    os.makedirs(dd, exist_ok=True)
    with open(os.path.join(dd, cfg_name), "w", encoding="utf-8") as f:
        f.write(cfg_text)
    with open(os.path.join(dd, "gitignore.block"), "w", encoding="utf-8") as f:
        f.write(block)
    gp = os.path.join(root, ".gitignore")
    existing = open(gp, encoding="utf-8").read() if os.path.exists(gp) else ""
    with open(os.path.join(dd, "gitignore.overlay"), "w", encoding="utf-8") as f:
        f.write(sr.splice_gitignore(existing, block))
    return dd


def untracked_ignored_under(root, negations):
    """Info only: files git itself IGNORES under literal anchored negation dirs — the ones a real
    application of the block could add on top of the overlay dry run (git reads the on-disk .gitignore)."""
    out = {}
    for pat in negations:
        if not (pat.startswith("/") and pat.endswith("/") and not re.search(r"[*?\[]", pat)):
            out[pat] = "unmeasured_non_literal_pattern"
            continue
        p = subprocess.run(["git", "-C", root, "ls-files", "-z", "-o", "-i", "--exclude-standard", "--", pat.strip("/")],
                           capture_output=True)
        out[pat] = len([x for x in p.stdout.split(b"\0") if x]) if p.returncode == 0 else "git_error"
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="CodeGraph index scope guard")
    ap.add_argument("--scope")
    ap.add_argument("--root")
    ap.add_argument("--dist")
    ap.add_argument("--work")
    ap.add_argument("--print-count", action="store_true")
    ap.add_argument("--contract-only", action="store_true")
    ap.add_argument("--resolve-dist", action="store_true")
    ap.add_argument("--dry-run-dir")
    ap.add_argument("--explain", action="store_true")
    ap.add_argument("--report-out")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 3 if e.code else 0

    report = {"tool": "codegraph_scope_guard", "violations": [], "controls": [], "contract": {"ok": None, "checks": []}}

    def finish(rc):
        report["exit_code"] = rc
        report["verdict"] = "PASS" if rc == 0 else "FAIL"
        line = json.dumps(report, sort_keys=True)
        print("SCOPE_GUARD_REPORT " + line, file=sys.stderr)
        if a.report_out:
            sr.atomic_write(a.report_out, line + "\n")
        return rc

    try:
        scope_for_dist, scope_err = None, None
        if a.scope:
            try:
                scope_for_dist = sr.load_scope(a.scope)[0]
            except sr.ScopeError as e:
                scope_err = e
        dist = resolve_dist(a.dist, scope_for_dist)
        if a.resolve_dist:
            print(dist)
            return 0
        if scope_err is not None:
            raise scope_err                    # unparsable scope: fail closed before any measuring
        if not a.scope or not a.root:
            raise GuardError("--scope and --root are required")
        root = os.path.abspath(a.root)
        if not os.path.isdir(root):
            raise GuardError("root is not a directory: %s" % root)
        work = os.path.abspath(a.work) if a.work else tempfile.mkdtemp(prefix="scope_guard_")
        for label, path in (("--work", work), ("--dry-run-dir", a.dry_run_dir)):
            if path and inside(root, path):
                raise GuardError("%s %s is inside the project root %s: the guard never writes into the project" % (label, path, root))
        os.makedirs(work, exist_ok=True)
        report["mode"] = "contract_only" if a.contract_only else ("dry_run" if a.dry_run_dir else "check")
        report["root"] = root

        # -- runner contract first: if the engine drifted, nothing measured after is trustworthy --
        cfg_name_early = ((scope_for_dist or {}).get("runner") or {}).get("config_filename") or "codegraph.json"
        cdir = os.path.join(work, "contract")
        shutil.rmtree(cdir, ignore_errors=True)
        os.makedirs(cdir)
        rc, cj, cerr = node_bridge(["contract", "--dist", dist, "--work", cdir, "--config-filename", cfg_name_early])
        if cj is None or "checks" not in cj:
            raise GuardError("runner contract probe failed to run (rc=%s): %s" % (rc, cerr[-300:]))
        report["contract"] = {"ok": bool(cj.get("ok")), "checks": cj["checks"],
                              "runner_version": cj.get("runner_version")}
        if rc != 0 or not cj.get("ok"):
            for c in cj["checks"]:
                if not c.get("ok"):
                    report["violations"].append({"check": "runner_contract", "id": c.get("id"), "detail": c.get("detail")})
            return finish(2)
        if a.contract_only:
            return finish(0)

        cfg_text, block, summary, scope, d = sr.render(a.scope, root)
        cfg_name = summary["config_filename"]
        report["scope_summary"] = summary
        if a.dry_run_dir:
            cfg2, block2, _s, _sc, _d = sr.render(a.scope, root)          # determinism: second render must be identical
            if (cfg2, block2) != (cfg_text, block):
                report["violations"].append({"check": "render_nondeterministic"})
            a.dry_run_dir = dry_run_prepare(a, scope, cfg_text, block, cfg_name, root, d)
        files, roots = evaluate(a, scope, d, cfg_name, cfg_text, block, dist, work, report)
        if a.dry_run_dir:
            report["reinclude_untracked_ignored"] = untracked_ignored_under(root, list(scope.get("reinclude_negations") or []))
            if a.explain:
                ex_out = os.path.join(a.dry_run_dir, "explain_dropped.tsv")
                rc, xj, xerr = node_bridge(["explain", "--dist", dist, "--root", root, "--enumerated", report["enumeration_file"],
                                            "--out", ex_out, "--config-filename", cfg_name,
                                            "--overlay-config", os.path.join(a.dry_run_dir, cfg_name),
                                            "--overlay-gitignore", os.path.join(a.dry_run_dir, "gitignore.overlay")])
                if rc != 0 or not xj or not xj.get("ok"):
                    raise GuardError("explain failed (rc=%s): %s" % (rc, (xj or {}).get("error") or xerr[-300:]))
                report["explain"] = {"tracked_source": xj["tracked_source"], "dropped": xj["dropped"], "groups": xj["groups"],
                                     "file": ex_out}
    except (GuardError, sr.ScopeError) as e:
        print("scope_guard: FAIL-CLOSED: %s" % e, file=sys.stderr)
        report["error"] = str(e)
        return finish(3)

    checks = sorted({v["check"] for v in report["violations"]})
    if a.print_count:
        print(report["count"])
    if "control_needle" in checks:
        rc = 4
    elif report["violations"]:
        rc = 1
    else:
        rc = 0
    print("scope_guard: %s count=%d violations=%s" % ("PASS" if rc == 0 else "FAIL(rc=%d)" % rc, report["count"], checks or "none"),
          file=sys.stderr)
    return finish(rc)


if __name__ == "__main__":
    sys.exit(main())
