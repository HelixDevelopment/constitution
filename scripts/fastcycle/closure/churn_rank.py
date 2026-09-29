#!/usr/bin/env python3
"""churn_rank.py - component age/churn ranking for the risk order (T099; plan.md T-D05; SC-004).

Computes per-component age and churn from git so the top decile feeds the §11.4.132/§11.4.189
risk-ordered validation queue (T-D05's Work line: "compute per-component age and churn from git;
the top decile feeds the ... risk ordering: closures there additionally require the backstop run
(T-C10) on the closing artifact" -- the T-C10 wiring itself is a separate, later task, not this
tool's own output-correctness contract).

Contract source: no `contracts/*.md` file names this tool (common-conventions.md's own tool-map
table lists it under "Plan tools that no contract in this directory covers ... their interface,
output and RED fixtures are fixed by the plan task text until a contract is written"). The binding
fixing this file implements is `tests/fixtures/churn_rank/README.md` (authored alongside T090's
RED test, `tests/test_churn_rank_red.sh`) -- this tool's own docstring restates that contract for
readers who land here first, following the house precedent set by anchor_citations.py.

Invocation:
    python3 churn_rank.py --as-of <YYYY-MM-DD> --components-file <path> \
        --repo-roots <path> --out <path> [--determinism-check]

--as-of <YYYY-MM-DD> (required, C-003: "No tool reads the current time into the body; time-
    windowed tools take --as-of <YYYY-MM-DD> and require it") bounds every measured path's commit
    history to commits with commit-date on or before --as-of, in every named repo.

--components-file <path> (required): canonical JSON
    {"components": [
      {"id": "<component-id>",
       "paths": [{"repo": "<repo-alias>", "path": "<repo-relative-path>"}, ...]}
    ]}
    A component MAY bundle paths across different git repositories (main monorepo + submodules,
    e.g. "presenter", "constitution") under distinct `repo` aliases -- a real component this
    project tracks (e.g. ATM-277's stale-frame handling) can legitimately span a submodule file
    and a parent-repo file.

--repo-roots <path> (required): canonical JSON `{"<alias>": "<absolute git-root path>", ...}`
    mapping every `repo` alias used above to an absolute git working tree. An alias referenced by
    --components-file but absent from --repo-roots is a usage error (exit 2, C-001 row 2) -- the
    caller's own two input files are internally inconsistent, never guessed at. A mapped root that
    exists but is not a readable git working tree (per `git -C <root> rev-parse
    --is-inside-work-tree`, the same probe anchor_citations.py's validate_repo() uses) is BLIND
    (exit 4, C-001 row 4) -- a required input could not be read, no honest verdict possible.

--out <path> (required): canonical JSON result (C-002: sorted keys, `schema` field, `run_meta`
    excluded from `body_hash`, both via fc_common.py's shared emit path).

--determinism-check (C-003's stated harness convention): runs the whole per-path measurement +
    ranking pipeline twice in-process against the identical, already-validated inputs and compares
    the canonical body (run_meta excluded); mismatch -> exit 1 with a unified diff on stderr and no
    result file written (nondeterminism is itself a finding, never a self-test failure); a match
    writes the (first) result normally, using whatever exit code that single computation itself
    implies (0 clean or 1 a genuine missing-path finding -- determinism-check verifies STABILITY of
    the result, it does not force exit 0 regardless of the result's own content).

Per-path measurement (fixtures/churn_rank/README.md "Per-path measurement"): for each
{repo, path} entry, `commits` = the count, and `first_commit_date` the oldest, of commit dates at
or before --as-of for that path's full logical history (rename-tracking via `--follow` is
load-bearing -- T090's own Section B negative control proves a naive `git log -- path` [no
--follow] under-counts a renamed file, which would silently drop an old, frequently-renamed,
genuinely high-churn component out of the top decile). A path resolving to zero such commits is
NEVER silently reported as `commits: 0` -- it is flagged
`"missing_instrument": "path_not_found_in_repo:<alias>:<path>"` (C-001/C-004: "no tool maps 'could
not measure' to 0"); its per-path output carries that field in place of `commits`/
`first_commit_date`.

DESIGN DECISION (deliberate deviation from the README's literal illustrative git-invocation
`--until='<as-of> 23:59:59'`, documented per this project's own honest-boundary convention,
§11.4.6): this tool does NOT pass `--until` to git at all. `git --until=<date-without-explicit-
offset>` is parsed as LOCAL time OF THE INVOKING PROCESS (host TZ / $TZ), which would make the
as-of boundary depend on the machine running the tool -- a real determinism hazard C-003 forbids
("no ... locale-dependent ... no $HOME-dependent paths in the body", the same class of environment-
dependence). Instead every commit's date is read via `git log --date=short --format=%cd` (which,
WITHOUT a `-local` suffix, renders each commit's date in THAT COMMIT'S OWN RECORDED OFFSET, never
the invoking host's -- measured directly on this host, §11.4.201(7)(b): a commit authored
"2020-01-01 23:30:00 +0000" on a host whose local TZ is +05:00 rendered as "2020-01-01", not the
host-local "2020-01-02"), and the resulting `YYYY-MM-DD` strings are filtered `<= as_of` in Python
(a plain string compare, valid because ISO-8601 calendar dates sort lexically identically to
chronologically). This is both more robust (removes the host-TZ-dependence hazard entirely) and,
for every scenario this tool is actually exercised against, behaviourally equivalent to the
README's illustrative form -- the README itself frames its assumed contract as refinable ("the
implementer may refine it", of the closely-related ranking-formula note in the same file).

Per-component aggregation: `churn_commits` = sum of its resolvable paths' `commits` (a component
with ALL paths missing is itself UNMEASURED -- `churn_commits`/`age_days` are the literal string
"UNMEASURED", never the number 0 -- and the WHOLE RUN exits 1, a finding, per C-001; a component
with only SOME paths missing still aggregates over its resolvable paths, and the run still exits 1
because at least one missing_instrument finding exists somewhere in the output -- "never silently
0" binds at the per-path layer regardless of whether the owning component as a whole could still be
partially measured); `age_days` = `as_of` minus the oldest `first_commit_date` across its
resolvable paths. Every component whose sole path (or every path) is missing carries a
component-level `missing_instrument` field literally naming the missing path(s)
(semicolon-joined for a multi-path component).

Ranking: components with a genuine numeric `churn_commits` are sorted descending by `churn_commits`
(primary), then `age_days` descending (secondary tie-break -- an older component among equal-churn
ones is scrutinised first, per T-D05's "old, high-churn components" framing), then `component_id`
ascending (final deterministic tie-break, C-003 -- never left to Python dict/set iteration order).
Every UNMEASURED component sorts after every measured one (by `component_id`) and is NEVER flagged
`in_top_decile` regardless of its numeric rank position -- ranking something "high priority" on the
strength of an absence would itself be exactly the false-null C-001/§11.4.201(6) forbids. `rank` is
the resulting 1-indexed position across ALL components (measured, then unmeasured).
`in_top_decile` = `rank <= ceil(n_components / 10)` (this exact combination rule is the fixtures
README's own invented default -- "the implementer may refine it"; SC-004's downstream
§11.4.132/§11.4.189 wiring, T101/T102 territory, is a separate later concern this tool's own
output-correctness contract does not cover).

Self-check (C-004 class-matched control needle, run once per invocation before any real
component is measured, over the SAME `_commit_dates()` code path every real path uses): builds a
throwaway one-commit git repository fresh in a tempdir; a known-present file MUST resolve to
exactly 1 commit; a fabricated, never-committed filename MUST resolve to zero commits (i.e. the
"missing" outcome, never silently absorbed as a present-but-empty answer). A needle failure means
the counting mechanism itself is not trustworthy this run -> exit 3, no result file written
(C-001 row 3), distinct from a genuine git-subprocess fault mid-run, which is BLIND (exit 4).

Exit codes (C-001): 0 success, no missing paths anywhere in the output; 1 a finding -- at least one
path resolved to zero commits at/before --as-of (missing_instrument), OR --determinism-check found
the two in-process runs disagree; 2 usage/configuration error (bad --as-of, unparseable
--components-file/--repo-roots, an alias --components-file references that --repo-roots does not
declare); 3 self-test failed (the git-log-counting control needle did not behave as expected -- no
result file written); 4 BLIND (a declared repo root is not a readable git working tree, or a git
invocation itself failed for a reason other than "the path is genuinely absent" -- no honest
verdict possible; partial diagnostic on stderr, no result file written for this tool, matching
anchor_citations.py's own validate_repo()-failure precedent of writing nothing before any real
component processing begins).

Side-effects: writes --out via fc_common.py's atomic emit path (C-002). Read-only otherwise
(C-006) -- issues only `git log`/`git rev-parse` against caller-supplied repo roots, never a
mutating git command. Python stdlib only.
"""
import argparse
import datetime
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_FC_DIR = os.path.dirname(_HERE)  # constitution/scripts/fastcycle
sys.path.insert(0, os.path.join(_FC_DIR, "lib"))
import fc_common  # noqa: E402  (sibling module; shared C-001..C-004 conventions)

SCHEMA = "churn_rank/v1"
GIT_TIMEOUT_S = 60  # generous bound; a --follow log on this project's real repos measures well under 1s
_AS_OF_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def _run_git(repo_root, args, timeout_s=GIT_TIMEOUT_S):
    """Returns the CompletedProcess, or None on any subprocess-level fault (missing git binary,
    timeout, output undecodable under the process locale) -- distinct from a clean rc!=0, which
    the caller classifies on its own terms (git log against a genuinely-never-tracked path still
    exits 0 with empty output; `git rev-parse --is-inside-work-tree` against a non-repo exits
    nonzero cleanly -- neither of those is a subprocess-level fault)."""
    try:
        return subprocess.run(["git", "-C", repo_root] + args, capture_output=True, text=True,
                               timeout=timeout_s)
    except (OSError, subprocess.TimeoutExpired, UnicodeDecodeError, ValueError):
        return None


def _validate_repo_root(repo_root):
    if not os.path.isdir(repo_root):
        return False
    result = _run_git(repo_root, ["rev-parse", "--is-inside-work-tree"], timeout_s=15)
    return result is not None and result.returncode == 0 and result.stdout.strip() == "true"


def _commit_dates(repo_root, path, as_of):
    """Per-path measurement's real mechanism (see the module docstring's DESIGN DECISION note for
    why this filters in Python instead of passing --until to git). Returns (kind, payload):
    kind "ok" -> payload = sorted list[str] of YYYY-MM-DD commit dates at/before as_of (possibly
    empty -- an HONEST zero, the caller decides what that means); kind "blind" -> payload = a
    diagnostic string (the git invocation itself could not be trusted -- never conflated with a
    genuine, honest empty result)."""
    result = _run_git(repo_root, ["log", "--follow", "--date=short", "--format=%cd", "--", path])
    if result is None:
        return "blind", "git log invocation failed for %s" % path
    if result.returncode != 0:
        return "blind", "git log exited %d for %s: %s" % (result.returncode, path, result.stderr.strip())
    all_dates = [ln for ln in result.stdout.splitlines() if ln]
    return "ok", sorted(d for d in all_dates if d <= as_of)


def _self_check():
    """C-004 class-matched control needle on the git-log-counting mechanism itself, over the SAME
    _commit_dates() code path every real component's path uses: a known-present file in a fresh,
    throwaway one-commit repo MUST resolve to exactly 1 commit; a fabricated, never-committed
    filename in that SAME repo MUST resolve to zero commits (the honest "missing" outcome the
    real per-path measurement below relies on). Returns None on success, else a diagnostic string
    (C-001 exit 3)."""
    try:
        with tempfile.TemporaryDirectory(prefix="churn_rank_selfcheck_") as tmp:
            r = subprocess.run(["git", "init", "-q", "."], cwd=tmp, capture_output=True, text=True)
            if r.returncode != 0:
                return "self-check: git init failed: %s" % r.stderr.strip()
            for key, val in (("user.name", "Churn Rank Selfcheck"),
                              ("user.email", "selfcheck@churn_rank.invalid"),
                              ("commit.gpgsign", "false")):
                subprocess.run(["git", "config", key, val], cwd=tmp, capture_output=True, text=True)
            present_name = "present_needle.txt"
            with open(os.path.join(tmp, present_name), "w", encoding="utf-8") as fh:
                fh.write("needle\n")
            subprocess.run(["git", "add", present_name], cwd=tmp, capture_output=True, text=True)
            env = dict(os.environ, GIT_AUTHOR_DATE="2020-01-01 12:00:00 +0000",
                       GIT_COMMITTER_DATE="2020-01-01 12:00:00 +0000")
            r = subprocess.run(["git", "commit", "-q", "-m", "self-check: present needle"], cwd=tmp,
                                env=env, capture_output=True, text=True)
            if r.returncode != 0:
                return "self-check: git commit failed: %s" % r.stderr.strip()
            kind, dates = _commit_dates(tmp, present_name, "2099-12-31")
            if kind != "ok" or len(dates) != 1:
                return ("self-check FAILED: known-present needle %r expected exactly 1 commit, "
                         "got kind=%s dates=%s" % (present_name, kind, dates))
            fabricated_name = "ABSENT_FABRICATED_needle_9f2c1a.txt"
            kind2, dates2 = _commit_dates(tmp, fabricated_name, "2099-12-31")
            if kind2 != "ok" or dates2:
                return ("self-check FAILED: fabricated decoy %r resolved to kind=%s dates=%s "
                         "(must be kind=ok, empty)" % (fabricated_name, kind2, dates2))
    except OSError as exc:
        return "self-check: git unavailable or unusable on this host: %s" % exc
    return None


def _load_json(path, label):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), None
    except (OSError, ValueError) as exc:
        return None, "cannot read %s %s: %s" % (label, path, exc)


def _validate_components(doc):
    if not isinstance(doc, dict) or not isinstance(doc.get("components"), list):
        return None, "--components-file must be a JSON object with a 'components' array"
    comps = []
    seen_ids = set()
    for i, c in enumerate(doc["components"]):
        if not isinstance(c, dict) or not isinstance(c.get("id"), str) or not c["id"]:
            return None, "components[%d] must be an object with a non-empty string 'id'" % i
        if c["id"] in seen_ids:
            return None, "duplicate component id %r" % c["id"]
        seen_ids.add(c["id"])
        paths = c.get("paths")
        if not isinstance(paths, list) or not paths:
            return None, "component %r must have a non-empty 'paths' array" % c["id"]
        clean_paths = []
        for j, p in enumerate(paths):
            if (not isinstance(p, dict) or not isinstance(p.get("repo"), str) or not p["repo"]
                    or not isinstance(p.get("path"), str) or not p["path"]):
                return None, "component %r paths[%d] must be {'repo': str, 'path': str}" % (c["id"], j)
            clean_paths.append({"repo": p["repo"], "path": p["path"]})
        comps.append({"id": c["id"], "paths": clean_paths})
    return comps, None


def _ceil_div(a, b):
    return -(-a // b)


def compute_body(comps, repo_roots, as_of):
    """Returns (body: dict|None, exit_code: int, blind_diag: str|None). exit_code 4 <=> body is
    None and blind_diag names the git-level fault; otherwise blind_diag is None and exit_code is
    0 (clean) or 1 (>=1 missing_instrument finding somewhere in the output, C-001)."""
    out_components = []
    any_missing = False
    for comp in comps:
        per_path = []
        resolvable = []
        for p in comp["paths"]:
            alias = p["repo"]
            path = p["path"]
            root = repo_roots[alias]
            kind, payload = _commit_dates(root, path, as_of)
            if kind == "blind":
                return None, 4, ("component %r path %r (repo %r): %s"
                                  % (comp["id"], path, alias, payload))
            dates = payload
            if not dates:
                missing = "path_not_found_in_repo:%s:%s" % (alias, path)
                per_path.append({"repo": alias, "path": path, "missing_instrument": missing})
                any_missing = True
            else:
                commits = len(dates)
                oldest = dates[0]
                per_path.append({"repo": alias, "path": path, "commits": commits,
                                  "first_commit_date": oldest})
                resolvable.append({"commits": commits, "first_commit_date": oldest})
        entry = {"component_id": comp["id"], "paths": per_path}
        if resolvable:
            entry["churn_commits"] = sum(m["commits"] for m in resolvable)
            oldest_overall = min(m["first_commit_date"] for m in resolvable)
            entry["age_days"] = (datetime.date.fromisoformat(as_of)
                                  - datetime.date.fromisoformat(oldest_overall)).days
        else:
            entry["churn_commits"] = "UNMEASURED"
            entry["age_days"] = "UNMEASURED"
            entry["missing_instrument"] = "; ".join(
                pp["missing_instrument"] for pp in per_path if "missing_instrument" in pp)
        out_components.append(entry)

    n = len(out_components)
    top_decile_count = _ceil_div(n, 10) if n else 0
    measured = sorted(
        (c for c in out_components if isinstance(c["churn_commits"], int)),
        key=lambda c: (-c["churn_commits"], -c["age_days"], c["component_id"]),
    )
    unmeasured = sorted(
        (c for c in out_components if not isinstance(c["churn_commits"], int)),
        key=lambda c: c["component_id"],
    )
    ordered = measured + unmeasured
    for i, c in enumerate(ordered, start=1):
        c["rank"] = i
        c["in_top_decile"] = bool(isinstance(c["churn_commits"], int) and i <= top_decile_count)

    body = {"as_of": as_of, "n_components": n, "components": ordered}
    return body, (1 if any_missing else 0), None


def _emit(body, run_meta, out_path, code):
    ns = argparse.Namespace(
        schema=SCHEMA,
        body_json=json.dumps(body),
        run_meta_json=json.dumps(run_meta) if run_meta else None,
        out=out_path,
        code=code,
    )
    return fc_common.cmd_emit(ns)


def _main_impl(argv):
    p = argparse.ArgumentParser(prog="churn_rank.py")
    p.add_argument("--as-of", required=True)
    p.add_argument("--components-file", required=True)
    p.add_argument("--repo-roots", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--determinism-check", action="store_true")
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    if not _AS_OF_RE.fullmatch(a.as_of):
        print("churn_rank: --as-of must be YYYY-MM-DD, got %r" % a.as_of, file=sys.stderr)
        return 2
    try:
        datetime.date.fromisoformat(a.as_of)
    except ValueError:
        print("churn_rank: --as-of is not a real calendar date: %r" % a.as_of, file=sys.stderr)
        return 2

    comps_doc, err = _load_json(a.components_file, "--components-file")
    if err:
        print("churn_rank: %s" % err, file=sys.stderr)
        return 2
    comps, err = _validate_components(comps_doc)
    if err:
        print("churn_rank: %s" % err, file=sys.stderr)
        return 2

    roots_doc, err = _load_json(a.repo_roots, "--repo-roots")
    if err:
        print("churn_rank: %s" % err, file=sys.stderr)
        return 2
    if not isinstance(roots_doc, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in roots_doc.items()):
        print("churn_rank: --repo-roots must be a JSON object mapping string alias -> string path",
              file=sys.stderr)
        return 2

    used_aliases = sorted({p["repo"] for c in comps for p in c["paths"]})
    missing_aliases = [alias for alias in used_aliases if alias not in roots_doc]
    if missing_aliases:
        print("churn_rank: --repo-roots is missing alias(es) referenced by --components-file: %s"
              % ", ".join(missing_aliases), file=sys.stderr)
        return 2

    repo_roots = {alias: roots_doc[alias] for alias in used_aliases}
    unreadable = [alias for alias, root in repo_roots.items() if not _validate_repo_root(root)]
    if unreadable:
        print("churn_rank: BLIND -- repo root(s) not a readable git working tree: %s"
              % ", ".join("%s=%s" % (alias, repo_roots[alias]) for alias in unreadable),
              file=sys.stderr)
        return 4

    self_check_err = _self_check()
    if self_check_err:
        print("churn_rank: %s" % self_check_err, file=sys.stderr)
        return 3

    run_meta = {
        "tool": "churn_rank.py",
        "as_of": a.as_of,
        "repo_roots": {alias: os.path.abspath(root) for alias, root in repo_roots.items()},
    }

    if a.determinism_check:
        body1, code1, diag1 = compute_body(comps, repo_roots, a.as_of)
        body2, code2, diag2 = compute_body(comps, repo_roots, a.as_of)
        if code1 == 4 or code2 == 4:
            print("churn_rank: BLIND during determinism-check: %s" % (diag1 or diag2), file=sys.stderr)
            return 4
        canon1 = fc_common.canon(body1).encode("utf-8")
        canon2 = fc_common.canon(body2).encode("utf-8")
        if canon1 != canon2 or code1 != code2:
            print("churn_rank: nondeterministic across two in-process runs", file=sys.stderr)
            diff = list(difflib.unified_diff(
                canon1.decode("utf-8", "replace").splitlines(),
                canon2.decode("utf-8", "replace").splitlines(),
                "run1", "run2", lineterm="", n=1))
            for line in diff[:40]:
                print(line, file=sys.stderr)
            return 1
        body, code = body1, code1
    else:
        body, code, diag = compute_body(comps, repo_roots, a.as_of)
        if code == 4:
            print("churn_rank: BLIND -- %s" % diag, file=sys.stderr)
            return 4

    return _emit(body, run_meta, a.out, code=code)


def main(argv):
    """The whole body is guarded here (mirrors anchor_citations.py's own main()): an internal
    failure this tool does not classify more specifically resolves to BLIND (4) with a diagnostic
    on stderr -- never a raw unhandled traceback surfacing under the reserved-for-nondeterminism
    exit 1."""
    try:
        return _main_impl(argv)
    except (OSError, UnicodeDecodeError, ValueError, RuntimeError) as exc:
        print("churn_rank: BLIND -- internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
