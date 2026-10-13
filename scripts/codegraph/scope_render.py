#!/usr/bin/env python3
# ============================================================================
# scope_render.py — renders a project's CodeGraph index scope from scope.yaml
# ============================================================================
# Purpose      DETERMINISTIC single source of truth -> engine inputs. From a
#              declarative scope.yaml (schema: scope.example.yaml) plus the
#              project's .gitmodules (recursively, including nested checked-out
#              submodules) it renders:
#                (a) <root>/codegraph.json — the ONLY config file CodeGraph >= 1.6
#                    reads (runner lib/dist/project-config.js:73). Its `exclude`
#                    list = every THIRD-PARTY submodule root (URL org not in the
#                    own-org set, §11.4.79) + the baseline must-exclude classes
#                    (§11.4.78 / §11.4.10) + project + pathological excludes, and
#                    a `_generated` provenance key (sha256 of scope.yaml and of
#                    every .gitmodules read). The engine's parseConfig
#                    (project-config.js:119-152) only extracts the known keys
#                    extensions/includeIgnored/exclude/include/deprioritize, so
#                    `_generated` is inert — scope_enumerate.js contract check
#                    C3 re-proves that on every guard run.
#                    `include_patterns` (optional) renders as the engine's `include`
#                    key: first-party source a NESTED .gitignore hides is forced back
#                    in (a root .gitignore negation cannot reach it; `exclude` still wins).
#                (b) the root .gitignore negation block delimited
#                    "# BEGIN helix-codegraph-scope" / "# END helix-codegraph-scope",
#                    re-including OWNED source under a built-in-skipped parent
#                    (only a root .gitignore "!" negation can do that; codegraph.json
#                    `include` never can — extraction/index.js ScopeIgnore :634-670).
#              Own-org submodule paths NEVER appear in `exclude`.
# Usage        scope_render.py --scope <scope.yaml> --root <project root>
#                  [--write]                 write codegraph.json + .gitignore block
#                  [--check]                 exit 1 when the files on disk differ
#                  [--out-config F] [--out-gitignore-block F]   write elsewhere
#                  (no mode flag: print the rendered codegraph.json on stdout)
# Inputs       scope.yaml; <root>/.gitmodules and every checked-out own-org
#              submodule's .gitmodules (third-party subtrees are excluded whole,
#              so their nested submodules are not descended into).
# Outputs      files above; one "SCOPE_RENDER <json summary>" line on stderr.
# Side effects --write only: <root>/codegraph.json and <root>/.gitignore (block
#              replaced in place and moved to the end of the file). Nothing else.
# Exit codes   0 ok / fresh; 1 --check found drift; 3 fail-closed (unparsable
#              scope, missing required key/baseline class, unclassifiable gitlink,
#              unreadable .gitmodules, usage error).
# Dependencies python3, PyYAML, git (for `git config -f` parsing of .gitmodules)
# Cross-refs   scope.example.yaml, codegraph_scope_guard.py, scope_enumerate.js,
#              docs/scripts/scope_render.md, constitution §11.4.10 / §11.4.28 /
#              §11.4.35 / §11.4.78 / §11.4.79 / §11.4.201.
# ============================================================================
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

BLOCK_BEGIN = "# BEGIN helix-codegraph-scope"
BLOCK_END = "# END helix-codegraph-scope"
REQUIRED_BASELINE_CLASSES = ("build_outputs", "caches", "secrets", "qa_corpora")
REQUIRED_KEYS = ("schema_version", "own_orgs", "baseline_excludes")
KNOWN_KEYS = frozenset(("schema_version", "runner", "own_orgs", "submodule_class_overrides", "baseline_excludes",
                        "project_excludes", "pathological_excludes", "include_patterns", "reinclude_negations",
                        "forbidden_classes", "enumeration_controls", "accepted_count", "tolerance_pct"))


class ScopeError(Exception):
    """Fail-closed input error -> exit 3."""


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def load_scope(path):
    try:
        import yaml
    except ImportError as e:  # pragma: no cover
        raise ScopeError("PyYAML not importable: %s" % e)
    try:
        raw = open(path, "rb").read()
    except OSError as e:
        raise ScopeError("cannot read scope file %s: %s" % (path, e))
    try:
        data = yaml.safe_load(raw.decode("utf-8"))
    except Exception as e:  # yaml.YAMLError and decode errors
        raise ScopeError("unparsable scope file %s: %s" % (path, str(e).splitlines()[0] if str(e) else e))
    if not isinstance(data, dict):
        raise ScopeError("scope file %s is not a mapping" % path)
    for k in REQUIRED_KEYS:
        if k not in data:
            raise ScopeError("scope file missing required key: %s" % k)
    unknown = sorted(str(k) for k in data if k not in KNOWN_KEYS)  # §1.1-anchor:unknown_key_check
    if unknown:
        raise ScopeError("unknown top-level scope key(s) (a silently ignored key would silently drop a rule): "
                         + ", ".join(unknown))
    if data.get("schema_version") != 1:
        raise ScopeError("unsupported schema_version %r (expected 1)" % data.get("schema_version"))
    oo = data.get("own_orgs")
    if not isinstance(oo, dict) or not oo.get("orgs") or not oo.get("hosts"):
        raise ScopeError("own_orgs.hosts and own_orgs.orgs must be non-empty lists")
    be = data.get("baseline_excludes")
    if not isinstance(be, dict):
        raise ScopeError("baseline_excludes must be a mapping of class -> patterns")
    for c in REQUIRED_BASELINE_CLASSES:
        if not be.get(c):
            raise ScopeError("baseline class %s missing or empty (§11.4.78: a class may not be removed)" % c)
    for key in ("project_excludes", "pathological_excludes", "reinclude_negations", "include_patterns"):
        v = data.get(key) or []
        if not isinstance(v, list) or not all(isinstance(x, str) and x.strip() for x in v):
            raise ScopeError("%s must be a list of non-empty strings" % key)
    for n in data.get("reinclude_negations") or []:
        if n.startswith("!"):
            raise ScopeError("reinclude_negations entries are written WITHOUT the leading '!': %s" % n)
    for n in data.get("include_patterns") or []:
        if n.startswith("!"):
            raise ScopeError("include_patterns entries are plain patterns (no leading '!'): %s" % n)
    ov = data.get("submodule_class_overrides") or {}
    if not isinstance(ov, dict) or any(v not in ("own", "third_party") for v in ov.values()):
        raise ScopeError("submodule_class_overrides values must be 'own' or 'third_party'")
    return data, raw


# ---- ownership --------------------------------------------------------------------
URL_RES = [
    re.compile(r"^(?:ssh://)?(?:[^@/]+@)?(?P<host>[^:/]+)(?::\d+)?/(?P<org>[^/]+)/"),   # ssh://git@host[:p]/org/
    re.compile(r"^[^@/]+@(?P<host>[^:/]+):(?P<org>[^/]+)/"),                             # git@host:org/
    re.compile(r"^(?:https?|git)://(?:[^@/]+@)?(?P<host>[^:/]+)(?::\d+)?/(?P<org>[^/]+)/"),  # https://host/org/
]


def url_host_org(url):
    """Return (host, org) lower-cased, or None when the URL is local/relative/unparsable."""
    u = (url or "").strip()
    if not u or u.startswith(("./", "../", "/", "file:")):
        return None
    for rx in (URL_RES[2], URL_RES[1], URL_RES[0]):
        m = rx.match(u)
        if m and "." in m.group("host"):
            return m.group("host").lower(), m.group("org").lower()
    return None


def read_gitmodules(path):
    """[(name, path, url)] from a .gitmodules file via `git config -f` (the file's own grammar)."""
    try:
        proc = subprocess.run(["git", "config", "-f", path, "--null", "--get-regexp", r"^submodule\..*\.(path|url)$"],
                              capture_output=True, check=False)
    except OSError as e:
        raise ScopeError("git not runnable: %s" % e)
    if proc.returncode not in (0, 1):          # 1 = no match (empty file); anything else = unparsable
        raise ScopeError("unparsable %s: %s" % (path, proc.stderr.decode("utf-8", "replace").strip()[:300]))
    out = proc.stdout.decode("utf-8", "replace")
    mods = {}
    for rec in out.split("\0"):
        if not rec:
            continue
        key, _, val = rec.partition("\n")
        m = re.match(r"^submodule\.(.*)\.(path|url)$", key)
        if m:
            mods.setdefault(m.group(1), {})[m.group(2)] = val
    res = []
    for name in sorted(mods):
        p = mods[name].get("path")
        if not p:
            raise ScopeError("%s: submodule %s has no path" % (path, name))
        res.append((name, p.strip().strip("/"), mods[name].get("url")))
    return res


def derive_submodules(root, scope):
    """Walk .gitmodules recursively. Returns dict with own/third_party root lists and
    the list of (relpath, bytes) of every .gitmodules read (for provenance)."""
    hosts = {h.lower() for h in scope["own_orgs"]["hosts"]}
    orgs = {o.lower() for o in scope["own_orgs"]["orgs"]}
    overrides = {k.strip("/"): v for k, v in (scope.get("submodule_class_overrides") or {}).items()}
    own, third_party, files, unclassified = [], [], [], []

    def walk(prefix):
        gm_rel = (prefix + "/" if prefix else "") + ".gitmodules"
        gm = os.path.join(root, gm_rel)
        if not os.path.isfile(gm):
            return
        try:
            files.append((gm_rel, open(gm, "rb").read()))
        except OSError as e:
            raise ScopeError("cannot read %s: %s" % (gm_rel, e))
        for _name, p, url in read_gitmodules(gm):
            rel = (prefix + "/" if prefix else "") + p
            cls = overrides.get(rel)
            if cls is None:
                ho = url_host_org(url)
                if ho is None:
                    unclassified.append("%s (url=%r)" % (rel, url))
                    continue
                cls = "own" if (ho[0] in hosts and ho[1] in orgs) else "third_party"
            if cls == "own":
                own.append(rel)
                walk(rel)                    # nested submodules classified by THEIR OWN url
            else:
                third_party.append(rel)  # §1.1-anchor:third_party_derivation

    walk("")
    if unclassified:
        raise ScopeError("unclassifiable gitlink(s) — add submodule_class_overrides: " + ", ".join(unclassified))
    files.sort()
    return {"own": sorted(set(own)), "third_party": sorted(set(third_party)), "gitmodules_files": files}


def gitignore_to_regex(pat):
    """Anchored/unanchored, dir-only/file gitignore pattern -> compiled regex over root-relative file paths."""
    p = pat.strip()
    dir_only = p.endswith("/")
    if dir_only:
        p = p.rstrip("/")
    anchored = p.startswith("/") or ("/" in p)
    p = p.lstrip("/")
    out, i = [], 0
    while i < len(p):
        if p[i:i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
        elif p[i:i + 2] == "**":
            out.append(".*")
            i += 2
        elif p[i] == "*":
            out.append("[^/]*")
            i += 1
        elif p[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(p[i]))
            i += 1
    head = "^" if anchored else "(?:^|.*/)"
    return re.compile(head + "".join(out) + ("/.*$" if dir_only else "(?:$|/.*$)"))


def probe_path(pat):
    """A concrete root-relative path the POSITIVE gitignore pattern matches (None when none can be built).
    Deterministic; verified against the pattern's own regex by the caller."""
    p = pat.strip()
    dir_only = p.endswith("/")
    body = p.rstrip("/")
    anchored = body.startswith("/") or "/" in body
    out = []
    for c in body.lstrip("/").split("/"):
        if c == "**":
            out.append("x")
            continue
        c = re.sub(r"\[[^\]]*\]", "p", c).replace("*", "probe").replace("?", "p")
        out.append(c)
    path = "/".join(out)
    if not path:
        return None
    if not anchored:
        path = "x/" + path
    if dir_only:
        path += "/probe.c"
    return path


def check_exclusion_order(exclude):
    """Fail closed when a NEGATION entry of the rendered `exclude` list voids an EARLIER exclusion.

    The engine feeds `exclude` to the `ignore` matcher, where the LAST matching pattern decides: a later
    `!X` silently re-includes everything an earlier, different exclusion P covered (measured: `**/secrets/`
    followed by `!*secret*/` leaves scripts/secrets/x.py INDEXED). A negation's declared subject is the pattern with the same
    body (`*secret*` <- `!*secret*/`); it may carve only from its subject. Any other earlier exclusion whose probe
    path the negation matches, and that no LATER pattern re-asserts, is a defect -> ScopeError.
    Returns the number of exclusions that could not be probed (their pattern is not synthesisable)."""
    unprobed = 0
    for j, n in enumerate(exclude):
        if not n.startswith("!"):
            continue
        nbody = n[1:]
        nrx = gitignore_to_regex(nbody)
        for i, pat in enumerate(exclude[:j]):
            if pat.startswith("!") or pat.rstrip("/") == nbody.rstrip("/"):
                continue
            probe = probe_path(pat)
            if probe is None or not gitignore_to_regex(pat).match(probe):
                unprobed += 1
                continue
            if not nrx.match(probe):
                continue
            reasserted = any(not q.startswith("!") and gitignore_to_regex(q).match(probe) for q in exclude[j + 1:])  # §1.1-anchor:order_lint_reassert
            if not reasserted:
                raise ScopeError("exclusion %r (index %d) is voided by the later negation %r (index %d): the engine's "
                                 "last-match-wins matcher would index %r; write %r AFTER %r" % (pat, i, n, j, probe, pat, n))
    return unprobed


def dedupe(seq):
    seen, out = set(), []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def render(scope_path, root):
    """Pure function of (scope file bytes, .gitmodules bytes) -> (config_text, block_text, summary)."""
    scope, raw = load_scope(scope_path)
    root = os.path.abspath(root)
    d = derive_submodules(root, scope)
    gm_hash = hashlib.sha256()
    for rel, b in d["gitmodules_files"]:
        gm_hash.update(rel.encode() + b"\0" + sha256_bytes(b).encode() + b"\n")
    third = ["/" + p + "/" for p in d["third_party"]]
    baseline = []
    for cls in REQUIRED_BASELINE_CLASSES:
        baseline += scope["baseline_excludes"][cls]
    for cls, pats in scope["baseline_excludes"].items():       # project-added classes, written order
        if cls not in REQUIRED_BASELINE_CLASSES:
            baseline += pats or []
    exclude = dedupe(third + baseline + list(scope.get("project_excludes") or [])
                     + list(scope.get("pathological_excludes") or []))
    unprobed = check_exclusion_order(exclude)  # §1.1-anchor:order_lint_call
    # guardrail: an own-org ROOT must never be excluded by the derivation itself
    own_roots = {"/" + p + "/" for p in d["own"]}
    if own_roots & set(third):
        raise ScopeError("own-org root derived as third-party: %s" % sorted(own_roots & set(third)))
    cfg = {
        "_generated": {
            "by": "scope_render.py",
            "do_not_edit": "rendered from the scope file; edit it and re-run scope_render.py --write",
            "schema_version": 1,
            "scope_file": os.path.basename(scope_path),
            "scope_sha256": sha256_bytes(raw),
            "gitmodules_sha256": gm_hash.hexdigest(),
            "gitmodules_files": [rel for rel, _ in d["gitmodules_files"]],
            "own_org_roots": d["own"],
            "third_party_roots": d["third_party"],
        },
        "exclude": exclude,
    }
    include = dedupe(list(scope.get("include_patterns") or []))
    if include:
        cfg["include"] = include      # §1.1-anchor:include_emit
    cfg_text = json.dumps(cfg, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    negations = list(scope.get("reinclude_negations") or [])
    body = ["!" + p for p in negations]  # §1.1-anchor:negation_emit
    block = "\n".join([BLOCK_BEGIN + " (rendered by scope_render.py; do not edit by hand)"] + body + [BLOCK_END]) + "\n"
    summary = {"own_org_roots": len(d["own"]), "third_party_roots": len(d["third_party"]),
               "exclude_patterns": len(exclude), "include_patterns": len(include), "negations": len(negations),
               "order_lint_unprobed": unprobed,
               "gitmodules_files": len(d["gitmodules_files"]),
               "config_filename": (scope.get("runner") or {}).get("config_filename") or "codegraph.json"}
    return cfg_text, block, summary, scope, d


BLOCK_RX = re.compile(r"^" + re.escape(BLOCK_BEGIN) + r".*?^" + re.escape(BLOCK_END) + r"[^\n]*\n?", re.S | re.M)


def splice_gitignore(existing, block):
    """Remove every existing block, then append the block as the LAST content."""
    rest = BLOCK_RX.sub("", existing or "").rstrip()
    return (rest + "\n\n" if rest else "") + block


def gitignore_state(text, block):
    """(ok, reason) — ok iff exactly one block, equal to `block`, and nothing but blank lines after it."""
    found = BLOCK_RX.findall(text or "")
    if not found:
        return False, "block_missing"
    if len(found) > 1:
        return False, "block_duplicated"
    if found[0].rstrip("\n") != block.rstrip("\n"):
        return False, "block_differs"
    tail = (text or "")[BLOCK_RX.search(text).end():]
    if tail.strip():
        return False, "block_not_last"
    return True, "ok"


def check_on_disk(root, cfg_name, cfg_text, block):
    """Return list of drift reasons (empty = fresh)."""
    reasons = []
    p = os.path.join(root, cfg_name)
    try:
        if open(p, encoding="utf-8").read() != cfg_text:
            reasons.append("config_differs")
    except OSError:
        reasons.append("config_missing")
    try:
        gi = open(os.path.join(root, ".gitignore"), encoding="utf-8").read()
    except OSError:
        gi = ""
    ok, why = gitignore_state(gi, block)
    if not ok:
        reasons.append(why)
    return reasons


def atomic_write(path, text):
    tmp = path + ".scope_render.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render codegraph.json + .gitignore negation block from scope.yaml")
    ap.add_argument("--scope", required=True)
    ap.add_argument("--root", required=True)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", action="store_true")
    g.add_argument("--check", action="store_true")
    ap.add_argument("--out-config")
    ap.add_argument("--out-gitignore-block")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 3 if e.code else 0
    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        print("scope_render: root is not a directory: %s" % root, file=sys.stderr)
        return 3
    try:
        cfg_text, block, summary, _scope, _d = render(a.scope, root)
    except ScopeError as e:
        print("scope_render: FAIL-CLOSED: %s" % e, file=sys.stderr)
        return 3
    cfg_name = summary["config_filename"]
    rc = 0
    if a.out_config:
        atomic_write(a.out_config, cfg_text)
    if a.out_gitignore_block:
        atomic_write(a.out_gitignore_block, block)
    if a.write:
        atomic_write(os.path.join(root, cfg_name), cfg_text)
        gp = os.path.join(root, ".gitignore")
        existing = open(gp, encoding="utf-8").read() if os.path.exists(gp) else ""
        atomic_write(gp, splice_gitignore(existing, block))
    elif a.check:
        drift = check_on_disk(root, cfg_name, cfg_text, block)
        summary["drift"] = drift
        rc = 1 if drift else 0
    elif not (a.out_config or a.out_gitignore_block):
        sys.stdout.write(cfg_text)
    print("SCOPE_RENDER " + json.dumps(summary, sort_keys=True), file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
