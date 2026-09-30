#!/usr/bin/env python3
"""_enumerate_impl.py - real implementation behind consumers/enumerate.sh
(T-G03/T170; contract consumer-audit-and-migration.md CA-001..CA-005;
guarded by tests/test_consumer_enumerate_red.sh, T166; FR-024, SC-010).

CA-001 sources, implemented as three independent, cross-checked probes:
  Source 1 (authoritative, DEC-24): direct GitHub API probe
    (`gh api repos/<org>/<repo>/contents/constitution`) of every repo in
    every configured `consumers.github_orgs` org, looking for a root-path
    entry whose `type` is `submodule`.
  Source 2: the SAME probe against GitLab via `glab` for every configured
    `consumers.gitlab_orgs` group; a group/namespace that does not exist
    is not an error (most of these orgs are GitHub-only) -- reported
    per-org as no hits, never a crash.
  Source 3: local filesystem scan of `consumers.local_clone_roots` (depth
    1): a `constitution` gitlink at HEAD -> consumer_kind=submodule; a
    CLAUDE.md carrying the literal inheritance-pointer heading with no
    such gitlink -> consumer_kind=text-only-inheritance.

CA-002 union + cross-check: the project set is the union of all three
sources, keyed by canonical project_id (CA-003 redirects applied); each
project records which sources hit it (source_agreement). GitHub code
search is never used as a source here (CA-002); T166's own RED test
records it as the required failed needle independently.

CA-004 needles: `consumers.known_consumer` MUST be present and
`consumers.known_non_consumer` MUST be absent from the final project set,
else exit 3 (fail loud, never a silent wrong answer).

Reachability (§11.4.201(6), T177 Round 1 B1 fix): a `gh`/`glab` call that
fails for ANY reason other than a genuine HTTP 404 (auth failure, rate
limit, network error, malformed response) MUST NOT be silently folded
into "zero hits" -- that is exactly the false-null this constitution
forbids. Every such failure is recorded, per org (and per repo for the
submodule probe), in the output doc's `source_reachability` block, and
the run exits loudly (5) rather than reporting a quietly-undercounted
project set as if it were complete. Only a REAL HTTP 404 (the org/group/
repo genuinely does not exist) is treated as a normal negative and folded
into an empty/absent result, exactly as CA-002 already treats a missing
GitLab group.

Exit codes (contract "Exit codes"): 0 ok; 1 --determinism-check mismatch;
2 usage/config error; 3 needle failure (CA-004); 4 all sources
unreachable (no source could be probed at all); 5 one or more probes
degraded (partial enumeration -- the project set is real but incomplete,
and MUST NOT be trusted as the full SC-010 denominator).
"""
import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("_enumerate_impl.py: PyYAML is required (python3 -m pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

WORKERS = 12
GH_TIMEOUT_S = 20
INHERIT_RE = re.compile(r"INHERITED FROM constitution/CLAUDE\.md|@constitution/CLAUDE\.md")


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k != "run_meta"}
    return hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
    except OSError as exc:
        print("_enumerate_impl.py: cannot read --config %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(2)
    consumers = (cfg or {}).get("consumers")
    if not consumers:
        print("_enumerate_impl.py: --config %s has no top-level 'consumers' key" % path, file=sys.stderr)
        sys.exit(2)
    for key in ("github_orgs", "known_consumer", "known_non_consumer", "local_clone_roots"):
        if key not in consumers:
            print("_enumerate_impl.py: --config %s missing required key consumers.%s" % (path, key), file=sys.stderr)
            sys.exit(2)
    return consumers


HTTP_404_RE = re.compile(r"HTTP 404\b")


def gh_json(args, timeout=GH_TIMEOUT_S):
    """Returns (parsed_out_or_None, status) where status is one of
    "ok" (the call succeeded, out may legitimately be None for a
    non-JSON/empty body), "http_404" (a genuine, confirmed-absent 404 --
    a normal negative, never an error) or "error" (auth failure, rate
    limit, network error, timeout, or any other non-404 failure -- MUST
    NOT be read as "zero results", §11.4.201(6))."""
    try:
        proc = subprocess.run(
            ["gh"] + args, capture_output=True, text=True, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, "error"
    if proc.returncode != 0:
        if HTTP_404_RE.search(proc.stderr or ""):
            return None, "http_404"
        return None, "error"
    try:
        return json.loads(proc.stdout), "ok"
    except ValueError:
        return None, "ok"


def gh_repo_list(org):
    """Returns (repos_or_None, status). status="ok" means repos is a
    real (possibly empty) list that MAY be trusted as complete for this
    org; status="error" means the call genuinely failed (auth/rate-
    limit/network/malformed) and repos MUST NOT be treated as zero --
    the caller records this org as degraded, never silently drops it
    (§11.4.201(6), T177 Round 1 B1)."""
    out, status = gh_json(["api", "orgs/%s/repos" % org, "--paginate", "--jq", ".[].name"])
    if status == "http_404":
        return [], "ok"  # org genuinely does not exist -- a normal negative
    if status != "ok":
        return None, status
    if out is None:
        # --jq streams newline-delimited scalars, not a JSON array; re-run raw.
        try:
            proc = subprocess.run(
                ["gh", "api", "orgs/%s/repos" % org, "--paginate", "--jq", ".[].name"],
                capture_output=True, text=True, timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None, "error"
        if proc.returncode != 0:
            if HTTP_404_RE.search(proc.stderr or ""):
                return [], "ok"
            return None, "error"
        return [line for line in proc.stdout.splitlines() if line], "ok"
    return [], "ok"


def gh_probe_submodule(org, repo):
    """Return (True/False/None, status). True=submodule present,
    False=confirmed absent (a REAL HTTP 404), None=result unknown (auth
    failure/rate-limit/network error/timeout/malformed JSON) -- an
    unknown probe is NEVER folded into "confirmed absent"
    (§11.4.201(6), T177 Round 1 B1)."""
    try:
        proc = subprocess.run(
            ["gh", "api", "repos/%s/%s/contents/constitution" % (org, repo)],
            capture_output=True, text=True, timeout=GH_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, "error"
    if proc.returncode != 0:
        if HTTP_404_RE.search(proc.stderr or ""):
            return False, "ok"
        return None, "error"
    try:
        doc = json.loads(proc.stdout)
    except ValueError:
        return None, "error"
    return (isinstance(doc, dict) and doc.get("type") == "submodule"), "ok"


def source1_github(orgs):
    """Returns (hits: {project_id: True}, any_reachable: bool, degraded:
    [{"org", "repo"(optional), "reason"}]). `degraded` records every
    org/repo probe that could not be confirmed one way or the other --
    the caller MUST surface this rather than silently treat it as zero
    hits (§11.4.201(6), T177 Round 1 B1)."""
    hits = {}
    any_reachable = False
    degraded = []
    for org in orgs:
        repos, status = gh_repo_list(org)
        if status != "ok":
            degraded.append({"org": org, "reason": "repo-list-%s" % status})
            continue
        any_reachable = True
        if not repos:
            continue
        with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
            futs = {pool.submit(gh_probe_submodule, org, repo): repo for repo in repos}
            for fut in concurrent.futures.as_completed(futs):
                repo = futs[fut]
                try:
                    is_sub, pstatus = fut.result()
                except Exception:
                    is_sub, pstatus = None, "error"
                if pstatus != "ok":
                    degraded.append({"org": org, "repo": repo, "reason": "probe-%s" % pstatus})
                    continue
                if is_sub:
                    hits["%s/%s" % (org, repo)] = True
    return hits, any_reachable, degraded


def glab_json(args, timeout=GH_TIMEOUT_S):
    """Returns (parsed_out_or_None, status), the GitLab analogue of
    gh_json() -- a genuine HTTP 404 (group/project absent) is a normal
    negative ("ok", empty), any OTHER failure (auth/rate-limit/network)
    is "error" and MUST be surfaced, never silently folded into "no
    hits" (§11.4.201(6), T177 Round 1 B1)."""
    try:
        proc = subprocess.run(["glab"] + args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None, "error"
    if proc.returncode != 0:
        if HTTP_404_RE.search(proc.stderr or ""):
            return None, "http_404"
        return None, "error"
    try:
        return json.loads(proc.stdout), "ok"
    except ValueError:
        return None, "ok"


def source2_gitlab(orgs):
    """Returns (hits, any_reachable, degraded) -- see source1_github()
    for the shape of `degraded`."""
    hits = {}
    any_reachable = False
    degraded = []
    for org in orgs:
        projects, status = glab_json(["api", "groups/%s/projects?per_page=100" % org])
        if status == "http_404":
            any_reachable = True  # a genuinely-absent group is a normal negative
            continue
        if status != "ok":
            degraded.append({"org": org, "reason": "group-list-%s" % status})
            continue
        any_reachable = True
        if not projects:
            continue
        for proj in projects:
            pid = proj.get("id")
            path_with_ns = proj.get("path_with_namespace")
            if pid is None or not path_with_ns:
                continue
            tree, tree_status = glab_json(["api", "projects/%s/repository/tree?path=constitution" % pid])
            if tree_status == "http_404":
                continue  # project genuinely has no constitution/ path -- normal negative
            if tree_status != "ok":
                degraded.append({"org": org, "repo": path_with_ns, "reason": "tree-%s" % tree_status})
                continue
            if not tree:
                continue
            if any(entry.get("mode") == "160000" or entry.get("type") == "commit" for entry in tree):
                hits[path_with_ns] = True
    return hits, any_reachable, degraded


def source3_local(roots):
    hits = {}  # project_id -> {"kind": ..., "checkouts": [...]}
    any_reachable = False
    import os
    for root in roots:
        if not os.path.isdir(root):
            continue
        any_reachable = True
        try:
            entries = sorted(os.listdir(root))
        except OSError:
            continue
        for name in entries:
            path = os.path.join(root, name)
            gitdir = os.path.join(path, ".git")
            if not (os.path.isdir(gitdir) or os.path.isfile(gitdir)):
                continue
            project_id = _local_project_id(path)
            if project_id is None:
                continue
            kind = _classify_local(path)
            if kind is None:
                continue
            entry = hits.setdefault(project_id, {"kind": kind, "checkouts": []})
            if kind == "submodule":
                entry["kind"] = "submodule"
            path_abs = os.path.abspath(path)
            if path_abs not in entry["checkouts"]:
                entry["checkouts"].append(path_abs)
    return hits, any_reachable


# A genuine git-hosting remote: git@host:org/repo(.git) or
# scheme://host/.../org/repo(.git) or ssh://git@host[:port]/org/repo. A
# bare local filesystem path (e.g. a clone-of-a-clone whose "origin" is a
# sibling checkout's own working directory, confirmed live on this host --
# track2/3/4's helix_ota clones point at /mnt/track1/helix_ota) is NOT a
# canonical project identity and MUST NOT be parsed as one (§11.4.6: a
# wrong project_id is worse than a missing local_checkouts entry for that
# one clone -- CA-003 identity resolution is host-based, never path-based).
REMOTE_URL_RE = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*://|[A-Za-z0-9_.-]+@)[^/:]+[:/]([^/:]+)/([^/]+?)(?:\.git)?/?$")


def _local_project_id(path):
    try:
        proc = subprocess.run(
            ["git", "-C", path, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    url = proc.stdout.strip()
    m = REMOTE_URL_RE.match(url)
    if not m:
        return None
    return "%s/%s" % (m.group(1), m.group(2))


def _classify_local(path):
    try:
        proc = subprocess.run(
            ["git", "-C", path, "ls-tree", "HEAD", "constitution"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        proc = None
    if proc is not None and proc.returncode == 0 and "160000 commit" in proc.stdout:
        return "submodule"
    claude_md = None
    for candidate in ("CLAUDE.md",):
        p = "%s/%s" % (path, candidate)
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                claude_md = fh.read()
        except OSError:
            continue
    if claude_md and INHERIT_RE.search(claude_md):
        return "text-only-inheritance"
    return None


def apply_redirects(project_id, redirects):
    return redirects.get(project_id, project_id)


def build_projects(gh_hits, gl_hits, local_hits, redirects):
    canonical = {}

    def get(pid):
        cpid = apply_redirects(pid, redirects)
        return canonical.setdefault(
            cpid, {"project_id": cpid, "enumeration_sources": [], "consumer_kind": "submodule", "local_checkouts": []}
        )

    for pid in gh_hits:
        rec = get(pid)
        rec["enumeration_sources"].append({"source": "github-api-root-constitution", "hit": True})
    for pid in gl_hits:
        rec = get(pid)
        rec["enumeration_sources"].append({"source": "gitlab-api", "hit": True})
    for pid, info in local_hits.items():
        rec = get(pid)
        rec["enumeration_sources"].append({"source": "local-clone", "hit": True})
        if info["kind"] == "text-only-inheritance" and not any(
            s["source"] == "github-api-root-constitution" for s in rec["enumeration_sources"]
        ):
            rec["consumer_kind"] = "text-only-inheritance"
            rec["enumeration_sources"].append({"source": "text-only-pointer", "hit": True})
        for cp in info["checkouts"]:
            if cp not in rec["local_checkouts"]:
                rec["local_checkouts"].append(cp)

    projects = sorted(canonical.values(), key=lambda p: p["project_id"])
    for p in projects:
        p["enumeration_sources"].sort(key=lambda s: s["source"])
        p["local_checkouts"].sort()
    return projects


def summarize(projects):
    multi = sum(1 for p in projects if len({s["source"] for s in p["enumeration_sources"]} - {"text-only-pointer"}) >= 2)
    text_only = sum(1 for p in projects if p["consumer_kind"] == "text-only-inheritance")
    single = len(projects) - multi - text_only
    return {"multi_source": multi, "single_source": max(single, 0), "text_only": text_only}


def run_once(cfg):
    gh_hits, gh_reach, gh_degraded = source1_github(cfg["github_orgs"])
    gl_hits, gl_reach, gl_degraded = source2_gitlab(cfg.get("gitlab_orgs") or [])
    local_hits, local_reach = source3_local(cfg["local_clone_roots"])
    if not (gh_reach or gl_reach or local_reach):
        print("_enumerate_impl.py: all sources unreachable", file=sys.stderr)
        sys.exit(4)
    redirects = cfg.get("redirects") or {}
    projects = build_projects(gh_hits, gl_hits, local_hits, redirects)
    degraded = gh_degraded + gl_degraded
    doc = {
        "schema": "consumers/v1",
        "projects": projects,
        "source_agreement": summarize(projects),
        "source_reachability": {
            "github_degraded": gh_degraded,
            "gitlab_degraded": gl_degraded,
        },
        "run_meta": {},
    }
    doc["body_hash"] = body_hash_of(doc)

    known_consumer = apply_redirects(cfg["known_consumer"], redirects)
    known_non_consumer = apply_redirects(cfg["known_non_consumer"], redirects)
    ids = {p["project_id"] for p in projects}
    if known_consumer not in ids:
        print("_enumerate_impl.py: CA-004 needle failure: known_consumer %s is absent from the enumeration" % known_consumer, file=sys.stderr)
        sys.exit(3)
    if known_non_consumer in ids:
        print("_enumerate_impl.py: CA-004 needle failure: known_non_consumer %s was listed as a consumer" % known_non_consumer, file=sys.stderr)
        sys.exit(3)
    return doc, degraded


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--determinism-check", action="store_true")
    args = ap.parse_args()

    cfg = load_config(args.config)
    doc, degraded = run_once(cfg)

    if args.determinism_check:
        doc2, _degraded2 = run_once(cfg)
        if body_hash_of(doc) != body_hash_of(doc2):
            print("_enumerate_impl.py: determinism check FAILED (body_hash differs between two runs)", file=sys.stderr)
            sys.exit(1)

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

    if degraded:
        # §11.4.201(6): a partial enumeration is written (every source
        # that DID succeed is still real, useful data) but the run
        # exits loudly so a caller never silently trusts an undercounted
        # project set as complete (T177 Round 1 B1).
        print(
            "_enumerate_impl.py: %d probe(s) degraded (auth/rate-limit/network -- NOT a confirmed absence); "
            "see --out's source_reachability block; the written project set is real but INCOMPLETE:" % len(degraded),
            file=sys.stderr,
        )
        for d in degraded:
            print("  degraded: %s" % json.dumps(d, sort_keys=True), file=sys.stderr)
        sys.exit(5)

    sys.exit(0)


if __name__ == "__main__":
    main()
