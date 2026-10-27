#!/usr/bin/env python3
"""helix_deps_manifest.py - canonical engine behind verify_helix_deps_manifests.sh (constitution 11.4.31).

Purpose
    Verify that every own-org repository of a project carries a well-formed, tracked
    ``helix-deps.yaml`` at its root, and generate a correct skeleton for a repository that has none.
    Walk order: the project root, every submodule the root declares in .gitmodules (incl. the
    ``constitution`` hub), every submodule the hub declares, and any checked-out repository found
    under <root>/submodules/* or <root>/constitution/submodules/* that .gitmodules does not declare.

Own-org determination
    The organisation of a repository's remote URL (the .gitmodules URL; the checkout's origin remote
    as a fallback) matched case-insensitively against the own-org list: --own-orgs, else the env var
    HELIX_OWN_ORGS, else "vasic-digital,HelixDevelopment". The project root is ALWAYS required to carry
    a manifest, whatever its organisation.

Verdicts (one line each: STATUS<TAB>path<TAB>role<TAB>detail)
    PASS                own-org repository with a tracked, well-formed manifest
    FAIL                manifest missing, untracked, malformed, incomplete, or an own-org nesting violation
    SKIP(third_party)   third-party repository: not required, never reported as PASS
    KNOWN               leaf nests an own-org repository and its parent entry carries recursive_init: false;
                        that debt is owned by CM-HUB-ENGINE-NO-OWNORG-NESTING, not hidden here
    BLIND               cannot determine (own-org repository not checked out, unreadable root, broken instrument)

Exit codes
    0 PASS (no FAIL, no BLIND) / 1 FAIL / 2 BLIND (no FAIL, at least one BLIND, or the instrument failed its
    own control needles) / 64 usage error.  --scaffold: 0 printed or written / 1 refused (file exists) /
    2 directory unreadable / 64 usage.  --validate-file: 0 / 1 / 2 (unreadable).  --selftest: 0 / 1.

Dependencies: python3 (stdlib) + PyYAML, git. No network. Read-only except --scaffold --write.
Classification: universal (11.4.17); no project literal (11.4.28 / 11.4.177): the project root is an argument.
"""
import os
import re
import subprocess
import sys
import tempfile

try:
    import yaml
except Exception:  # pragma: no cover - reported as BLIND by the caller
    yaml = None

EXIT_PASS, EXIT_FAIL, EXIT_BLIND, EXIT_USAGE = 0, 1, 2, 64
DEFAULT_ORGS = "vasic-digital,HelixDevelopment"
SSH_RE = re.compile(r"^git@[A-Za-z0-9.-]+:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
TOP_REQUIRED = ("schema_version", "deps", "transitive_handling", "language_specific_subtree")
TOP_OPTIONAL = ("name", "ssh_url", "mirrors", "language", "project_agnostic", "carve_out", "third_party_manifest")
DEP_REQUIRED = ("name", "ssh_url", "ref", "why", "layout")
DEP_OPTIONAL = ("path", "recursive_init", "third_party", "licence")
TH_KEYS = ("recursive", "conflict_resolution")
LAYOUTS = ("flat", "grouped", "hub")
BOOLS = ("true", "false")
PLACEHOLDER_RE = re.compile(r"^\s*(UNKNOWN|TODO|TBD|FIXME)\b", re.I)
HUB_NAME_RE = re.compile(r"^(helixconstitution|constitution)$", re.I)
USAGE = """usage:
  verify_helix_deps_manifests.sh --root <project-root> [--own-orgs org1,org2]
  verify_helix_deps_manifests.sh --validate-file <helix-deps.yaml> [--own-orgs ...]
  verify_helix_deps_manifests.sh --scaffold <repo-dir> [--write] [--own-orgs ...]
  verify_helix_deps_manifests.sh --selftest
  verify_helix_deps_manifests.sh --help"""


# ----------------------------------------------------------------------------- YAML (strict, all-strings)
if yaml is not None:
    class StrictLoader(yaml.BaseLoader):
        """BaseLoader keeps every scalar a string (no octal/float surprises in refs) and this subclass
        refuses duplicate keys, which PyYAML otherwise resolves silently by keeping the last one."""

        def construct_mapping(self, node, deep=False):
            seen = []
            for key_node, _ in node.value:
                key = self.construct_object(key_node, deep=True)
                if key in seen:
                    raise yaml.constructor.ConstructorError(
                        "while constructing a mapping", node.start_mark,
                        "found duplicate key %r" % (key,), key_node.start_mark)
                seen.append(key)
            return yaml.BaseLoader.construct_mapping(self, node, deep=deep)


def load_manifest_text(text):
    """-> (doc, error-or-None)"""
    try:
        return yaml.load(text, Loader=StrictLoader), None
    except yaml.YAMLError as exc:
        msg = str(exc).replace("\n", " ")
        if "duplicate key" in msg:
            return None, "duplicate key: " + msg
        return None, "unparseable YAML: " + msg


# ----------------------------------------------------------------------------- URL helpers
def url_parts(url):
    """https://h/Org/Repo(.git) | ssh://[user@]h[:port]/Org/Repo.git | git@h:Org/Repo.git | scp-style user@h:Org/Repo
    -> (host, org, repo) or None (truly unparseable: other schemes, no host, no path, whitespace, '..' segments).
    The org is the FIRST path segment and the repo the LAST (nested GitLab-style groups keep the top group as org).
    A single-segment path (https://go.googlesource.com/go) has no org: the HOST stands in as the org, so it is
    third-party unless the host itself is in the own-org list."""
    if not url:
        return None
    url = url.strip()
    m = re.match(r"^(?:[A-Za-z0-9._-]+@)?([A-Za-z0-9.-]+):(?!//)([^\s?#:]+)$", url) \
        or re.match(r"^(?:https?|ssh|git)://(?:[^@/\s]+@)?([A-Za-z0-9.-]+)(?::\d+)?/([^\s?#]+)$", url)
    if not m:
        return None
    segs = [x for x in m.group(2).strip("/").split("/")]
    if not segs or any(x in ("", ".", "..") for x in segs):
        return None
    repo = re.sub(r"\.git$", "", segs[-1])
    if not repo:
        return None
    host = m.group(1)
    return (host, segs[0] if len(segs) > 1 else host, repo)


def is_relative_url(url):
    u = (url or "").strip()
    return u.startswith("./") or u.startswith("../")


def resolve_url(url, base):
    """git semantics for a superproject-relative submodule URL: ./x and ../x are relative to the URL of the
    repository whose .gitmodules declares them; each ../ drops one path segment of that base URL.
    -> the absolute URL, the URL unchanged when it is not relative, or None when it cannot be resolved
    (no parseable base, a relative base, or more ../ than the base has segments)."""
    if not is_relative_url(url):
        return url
    b = (base or "").strip()
    if not b or is_relative_url(b):
        return None
    m = re.match(r"^((?:[A-Za-z0-9._-]+@)?[A-Za-z0-9.-]+:)(?!//)([^\s?#:]+)$", b) \
        or re.match(r"^((?:https?|ssh|git)://(?:[^@/\s]+@)?[A-Za-z0-9.-]+(?::\d+)?/)([^\s?#]+)$", b)
    if not m:
        return None
    segs = [x for x in m.group(2).strip("/").split("/") if x]
    for part in url.strip().split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not segs:
                return None
            segs.pop()
        else:
            segs.append(part)
    return m.group(1) + "/".join(segs) if segs else None


def norm_key(url):
    p = url_parts(url)
    return ("%s/%s" % (p[1], p[2])).lower() if p else None


def to_ssh(url):
    p = url_parts(url)
    return "git@%s:%s/%s.git" % p if p else None


def is_own(org, own_orgs):
    return bool(org) and org.lower() in own_orgs


def is_hub_name(url):
    p = url_parts(url)
    return bool(p) and bool(HUB_NAME_RE.match(p[2]))


# ----------------------------------------------------------------------------- manifest schema
def validate_doc(doc, own_orgs):
    """-> list of human-readable defects (empty = well-formed)"""
    errs = []
    if not isinstance(doc, dict):
        return ["top level is not a mapping"]
    for k in doc:
        if k not in TOP_REQUIRED and k not in TOP_OPTIONAL:
            errs.append("unknown key '%s' at top level" % k)
    for k in TOP_REQUIRED:
        if k not in doc:
            errs.append("missing required top-level key '%s'" % k)
    if "schema_version" in doc and doc["schema_version"] != "1":
        errs.append("schema_version must be 1 (got %r)" % (doc["schema_version"],))
    if "language_specific_subtree" in doc and doc["language_specific_subtree"] not in BOOLS:
        errs.append("language_specific_subtree must be true|false")
    if "ssh_url" in doc and not (isinstance(doc["ssh_url"], str) and SSH_RE.match(doc["ssh_url"])):
        errs.append("top-level ssh_url is not git@host:org/repo.git")
    if "name" in doc and not (isinstance(doc["name"], str) and NAME_RE.match(doc["name"])):
        errs.append("top-level name is not a plain identifier")
    th = doc.get("transitive_handling")
    if "transitive_handling" in doc:
        if not isinstance(th, dict):
            errs.append("transitive_handling must be a mapping")
        else:
            for k in th:
                if k not in TH_KEYS:
                    errs.append("unknown key '%s' in transitive_handling" % k)
            if th.get("recursive") not in BOOLS:
                errs.append("transitive_handling.recursive must be true|false")
            if th.get("conflict_resolution") != "operator-required":
                errs.append("transitive_handling.conflict_resolution must be operator-required (11.4.6: never silently merged)")
    deps = doc.get("deps")
    if "deps" in doc:
        if not isinstance(deps, list):
            errs.append("deps must be a list (write 'deps: []' when there are none)")
        else:
            names, urls = set(), set()
            for i, e in enumerate(deps):
                tag = "deps[%d]" % i
                if not isinstance(e, dict):
                    errs.append("%s is not a mapping" % tag)
                    continue
                if isinstance(e.get("name"), str):
                    tag = "deps[%d] (%s)" % (i, e["name"])
                for k in e:
                    if k not in DEP_REQUIRED and k not in DEP_OPTIONAL:
                        errs.append("%s: unknown key '%s'" % (tag, k))
                for k in DEP_REQUIRED:
                    v = e.get(k)
                    if not isinstance(v, str) or not v.strip():
                        errs.append("%s: missing or empty '%s'" % (tag, k))
                name, url = e.get("name"), e.get("ssh_url")
                if isinstance(name, str) and name.strip():
                    if not NAME_RE.match(name):
                        errs.append("%s: name is not a plain identifier" % tag)
                    if name.lower() in names:
                        errs.append("%s: duplicate name" % tag)
                    names.add(name.lower())
                if isinstance(url, str) and url.strip():
                    if not SSH_RE.match(url):
                        errs.append("%s: ssh_url must be git@host:org/repo.git (SSH only, got %s)" % (tag, url))
                    else:
                        key = norm_key(url)
                        if key in urls:
                            errs.append("%s: duplicate ssh_url" % tag)
                        urls.add(key)
                ref = e.get("ref")
                if isinstance(ref, str) and ref.strip():
                    if re.search(r"\s", ref.strip()):
                        errs.append("%s: ref contains whitespace" % tag)
                    if PLACEHOLDER_RE.match(ref):
                        errs.append("%s: placeholder ref '%s' (pin a real tag or commit)" % (tag, ref))
                why = e.get("why")
                if isinstance(why, str) and PLACEHOLDER_RE.match(why):
                    errs.append("%s: placeholder why '%s' (write the real reason, 11.4.6)" % (tag, why.strip()))
                lay = e.get("layout")
                if isinstance(lay, str) and lay.strip() and lay not in LAYOUTS:
                    errs.append("%s: layout must be one of %s (got %s)" % (tag, "|".join(LAYOUTS), lay))
                for b in ("recursive_init", "third_party"):
                    if b in e and e[b] not in BOOLS:
                        errs.append("%s: %s must be true|false" % (tag, b))
                if "path" in e:
                    pv = e["path"]
                    if not isinstance(pv, str) or not pv.strip() or pv.startswith("/") or ".." in pv.split("/"):
                        errs.append("%s: path must be a relative path inside the repository" % tag)
                third = e.get("third_party") == "true"
                p = url_parts(url) if isinstance(url, str) else None
                if p and SSH_RE.match(url):
                    own = is_own(p[1], own_orgs)
                    if own and third:
                        errs.append("%s: third_party: true contradicts own-org ssh_url (%s)" % (tag, p[1]))
                    if not own and not third:
                        errs.append("%s: ssh_url org '%s' is not own-org; mark the entry third_party: true (with licence)" % (tag, p[1]))
                if third and not (isinstance(e.get("licence"), str) and e["licence"].strip()):
                    errs.append("%s: third_party: true requires a licence" % tag)
    return errs


def validate_text(text, own_orgs):
    doc, err = load_manifest_text(text)
    if err:
        return None, [err]
    return doc, validate_doc(doc, own_orgs)


# ----------------------------------------------------------------------------- git helpers
def git(args, cwd=None):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return r.returncode, r.stdout
    except OSError:
        return 127, ""


def gitmodules(repo):
    """-> (entries [(name, path, url)], blind_reason-or-None). Positive control: the number of
    [submodule "..."] headers must equal the number of parsed path entries, else the parser is blind."""
    f = os.path.join(repo, ".gitmodules")
    if not os.path.exists(f):
        return [], None
    try:
        raw = open(f, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        return [], "cannot read %s: %s" % (f, exc)
    headers = len(re.findall(r'^\s*\[submodule\s+"', raw, re.M))
    rc, out = git(["config", "-f", f, "--get-regexp", r"^submodule\..*\.(path|url)$"])
    if rc not in (0, 1):
        return [], "git cannot parse %s" % f
    paths, urls = {}, {}
    for line in out.splitlines():
        m = re.match(r"^submodule\.(.*)\.(path|url) (.*)$", line)
        if m:
            (paths if m.group(2) == "path" else urls)[m.group(1)] = m.group(3).strip()
    if len(paths) != headers:
        return [], "%s: %d [submodule] headers but %d parsed paths (parser blind)" % (f, headers, len(paths))
    return [(n, paths[n], urls.get(n, "")) for n in paths], None


def is_checkout(d):
    if not os.path.isdir(d) or not os.path.exists(os.path.join(d, ".git")):
        return False
    rc, out = git(["rev-parse", "--show-toplevel"], cwd=d)
    return rc == 0 and os.path.realpath(out.strip()) == os.path.realpath(d)


def origin_url(d):
    rc, out = git(["remote", "get-url", "origin"], cwd=d)
    return out.strip() if rc == 0 else ""


def is_tracked(d, rel):
    rc, _ = git(["ls-files", "--error-unmatch", "--", rel], cwd=d)
    return rc == 0


# ----------------------------------------------------------------------------- verify
class Report:
    def __init__(self, out):
        self.out = out
        self.counts = {"PASS": 0, "FAIL": 0, "BLIND": 0, "SKIP(third_party)": 0, "KNOWN": 0}

    def add(self, status, label, role, detail):
        self.counts[status] += 1
        self.out.write("%s\t%s\t%s\t%s\n" % (status, label, role, detail))

    def verdict(self):
        c = self.counts
        if c["FAIL"]:
            v, rc = "FAIL", EXIT_FAIL
        elif c["BLIND"]:
            v, rc = "BLIND", EXIT_BLIND
        else:
            v, rc = "PASS", EXIT_PASS
        self.out.write("VERDICT: %s (pass=%d fail=%d blind=%d skip_third_party=%d known=%d)\n" % (
            v, c["PASS"], c["FAIL"], c["BLIND"], c["SKIP(third_party)"], c["KNOWN"]))
        return rc


def entry_matches(dep, url, path):
    if not isinstance(dep, dict):
        return False
    du = dep.get("ssh_url")
    if isinstance(du, str) and url and norm_key(du) and norm_key(du) == norm_key(url):
        return True
    nm = dep.get("name")
    base = os.path.basename(path.rstrip("/"))
    canon = lambda s: s.lower().replace("-", "_")
    return isinstance(nm, str) and canon(nm) == canon(base)


def parent_marks_nonrecursive(parent_doc, url, path):
    if not isinstance(parent_doc, dict) or not isinstance(parent_doc.get("deps"), list):
        return False
    return any(entry_matches(d, url, path) and d.get("recursive_init") == "false" for d in parent_doc["deps"])


def collect(root):
    """-> (list of repo records, list of blind notes). A record: dict(label, dir, role, url, parent)."""
    recs, notes = [], []
    recs.append(dict(label=".", dir=root, role="root", url="", parent=None))
    hubs = [(".", root, None)]
    ents, blind = gitmodules(root)
    if blind:
        notes.append((".", blind))
    seen = set()
    for _, path, url in ents:
        role = "hub" if path.strip("/") == "constitution" else "leaf"
        recs.append(dict(label=path, dir=os.path.join(root, path), role=role, url=url, parent="."))
        seen.add(os.path.normpath(path))
        if role == "hub":
            hubs.append((path, os.path.join(root, path), "."))
    if os.path.normpath("constitution") not in seen and is_checkout(os.path.join(root, "constitution")):
        recs.append(dict(label="constitution", dir=os.path.join(root, "constitution"), role="hub",
                         url=origin_url(os.path.join(root, "constitution")), parent="."))
        seen.add("constitution")
        hubs.append(("constitution", os.path.join(root, "constitution"), "."))
    for hlabel, hdir, _ in hubs[1:]:
        if not is_checkout(hdir):
            continue
        hents, hblind = gitmodules(hdir)
        if hblind:
            notes.append((hlabel, hblind))
        for _, path, url in hents:
            lab = os.path.normpath(os.path.join(hlabel, path))
            recs.append(dict(label=lab, dir=os.path.join(hdir, path), role="leaf", url=url, parent=hlabel))
            seen.add(lab)
    for base in ("submodules", os.path.join("constitution", "submodules")):
        bdir = os.path.join(root, base)
        if not os.path.isdir(bdir):
            continue
        for nm in sorted(os.listdir(bdir)):
            lab = os.path.normpath(os.path.join(base, nm))
            d = os.path.join(bdir, nm)
            if lab in seen or not is_checkout(d):
                continue
            parent = "constitution" if base.startswith("constitution") else "."
            recs.append(dict(label=lab, dir=d, role="leaf", url=origin_url(d), parent=parent, undeclared=True))
    return recs, notes


def verify(root, own_orgs, out):
    rep = Report(out)
    if not root or not os.path.isdir(root):
        rep.add("BLIND", root or "?", "root", "project root is not a readable directory")
        return rep.verdict()
    root = os.path.realpath(root)
    recs, notes = collect(root)
    for lab, why in notes:
        rep.add("BLIND", lab, "gitmodules", why)
    docs = {}
    # first pass: parse every readable manifest so leaves can consult their parent's entry
    for r in recs:
        mf = os.path.join(r["dir"], "helix-deps.yaml")
        if os.path.isfile(mf):
            try:
                docs[r["label"]] = load_manifest_text(open(mf, encoding="utf-8").read())[0]
            except (OSError, UnicodeDecodeError):
                docs[r["label"]] = None
    resolved = {}  # label -> absolute remote URL, the base for that repository's own relative .gitmodules URLs
    for r in recs:
        lab, d, role = r["label"], r["dir"], r["role"]
        raw = r["url"] or (origin_url(d) if is_checkout(d) else "")
        url = resolve_url(raw, resolved.get(r.get("parent"), ""))
        resolved[lab] = url or ""
        p = url_parts(url)
        if role != "root":
            if url is None:
                rep.add("BLIND", lab, role, "relative submodule URL %r cannot be resolved: the parent repository has no "
                        "parseable remote URL to resolve it against; cannot decide own-org vs third-party" % raw)
                continue
            if not p:
                rep.add("BLIND", lab, role, "remote URL unknown or unparseable (%r); cannot decide own-org vs third-party" % url)
                continue
            if not is_own(p[1], own_orgs) and not is_hub_name(url):
                rep.add("SKIP(third_party)", lab, role, "%s/%s is not in the own-org list; no manifest required" % (p[1], p[2]))
                continue
        if not is_checkout(d):
            rep.add("BLIND", lab, role, "own-org repository not checked out (git submodule update --init -- %s); cannot verify" % lab)
            continue
        reasons = []
        mf = os.path.join(d, "helix-deps.yaml")
        doc = None
        if not os.path.isfile(mf):
            reasons.append("helix-deps.yaml missing at the repository root (generate a skeleton with --scaffold %s)" % lab)
        else:
            if not is_tracked(d, "helix-deps.yaml"):
                reasons.append("helix-deps.yaml present but not tracked by git (git add it; 11.4.215)")
            try:
                doc, errs = validate_text(open(mf, encoding="utf-8").read(), own_orgs)
            except (OSError, UnicodeDecodeError) as exc:
                doc, errs = None, ["cannot read helix-deps.yaml: %s" % exc]
            reasons += errs
        ents, blind = gitmodules(d)
        if blind:
            reasons.append(blind)
        unresolved = [(pth, u) for _, pth, u in ents if resolve_url(u, url) is None]
        ents = [(n, pth, resolve_url(u, url)) for n, pth, u in ents if resolve_url(u, url) is not None]
        if unresolved and role != "root":
            rep.add("BLIND", lab, role, "relative nested submodule URL(s) %s cannot be resolved against %r; cannot "
                    "decide own-org vs third-party" % (", ".join("%s (%s)" % x for x in unresolved), url))
        own_ents = [(n, pth, u) for n, pth, u in ents if (url_parts(u) and is_own(url_parts(u)[1], own_orgs)) or is_hub_name(u)]
        known = []
        if role in ("root", "hub"):
            deps = doc.get("deps") if isinstance(doc, dict) and isinstance(doc.get("deps"), list) else []
            for _, pth, u in own_ents:
                if role == "root" and pth.strip("/") == "constitution":
                    continue  # the hub is inherited by reference, never listed as a dependency
                if not any(isinstance(x, dict) and isinstance(x.get("ssh_url"), str) and norm_key(x["ssh_url"]) == norm_key(u)
                           for x in deps):
                    reasons.append("undeclared own-org submodule %s (%s): add a deps entry for it" % (pth, u))
        elif own_ents:
            nested = ", ".join("%s (%s)" % (pth, u) for _, pth, u in own_ents)
            if parent_marks_nonrecursive(docs.get(r.get("parent")), url, lab):
                known.append("nests own-org/hub submodule(s) %s; the parent entry carries recursive_init: false, "
                              "debt tracked by CM-HUB-ENGINE-NO-OWNORG-NESTING (11.4.28(C))" % nested)
            else:
                reasons.append("nests own-org/hub submodule(s) %s; forbidden by 11.4.28(C) (resolve them via the hub instead)" % nested)
        if reasons:
            rep.add("FAIL", lab, role, "; ".join(reasons))
        else:
            extra = " (checked-out directory not declared in .gitmodules)" if r.get("undeclared") else ""
            rep.add("PASS", lab, role, "tracked, well-formed helix-deps.yaml%s" % extra)
            for k in known:
                rep.add("KNOWN", lab, role, k)
    return rep.verdict()


# ----------------------------------------------------------------------------- scaffold
def snake(s):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_").lower()


def own_tokens(own_orgs):
    toks = set()
    for o in own_orgs:
        first = re.split(r"[-_]", snake(o))[0]
        if len(first) >= 4:
            toks.add(first)
    return toks


def scaffold_text(d, own_orgs):
    entries, comments, keys = [], [], set()

    def add(name, url, ref, layout, source):
        key = norm_key(url)
        if not key or key in keys:
            return
        keys.add(key)
        entries.append((name, to_ssh(url), ref, layout, source))

    ents, blind = gitmodules(d)
    if blind:
        comments.append("# NOTE: %s" % blind)
    base = origin_url(d)
    for _, path, raw in ents:
        url = resolve_url(raw, base)
        p = url_parts(url)
        if not p:
            comments.append("# NOTE: .gitmodules entry %s has an unparseable or unresolvable URL %r - add it manually if own-org"
                            % (path, raw))
            continue
        if path.strip("/") == "constitution" or is_hub_name(url):
            comments.append("# NOTE: %s is the constitution hub - inherited by reference, never listed here" % path)
            continue
        if not is_own(p[1], own_orgs):
            continue
        rc, out = git(["ls-files", "-s", "--", path], cwd=d)
        m = re.match(r"^160000 ([0-9a-f]{7,40}) ", out) if rc == 0 else None
        ref = m.group(1)[:7] if m else "UNKNOWN-pin-me"
        add(snake(os.path.basename(path.rstrip("/"))), url, ref,
            "grouped" if path.startswith("submodules/") else "flat", ".gitmodules %s" % path)
    toks = own_tokens(own_orgs)
    gomod = os.path.join(d, "go.mod")
    if os.path.isfile(gomod):
        for line in open(gomod, encoding="utf-8", errors="replace"):
            m = re.match(r"^\s*(?:require\s+)?([A-Za-z0-9._~/-]+)\s+(v[0-9][^\s]*)", line)
            if not m or m.group(1) in ("module", "go"):
                continue
            mod, ver = m.group(1), m.group(2)
            g = re.match(r"^github\.com/([^/]+)/([^/]+)", mod)
            if g and is_own(g.group(1), own_orgs):
                add(snake(g.group(2)), "git@github.com:%s/%s.git" % (g.group(1), g.group(2)), ver, "grouped", "go.mod %s" % mod)
            elif not g and any(t in mod.lower() for t in toks):
                comments.append("# NOTE: go.mod requires %s %s - not mappable to a repository URL; "
                                "add its entry by hand if it is an own-org dependency (UNKNOWN)" % (mod, ver))
    pkg = os.path.join(d, "package.json")
    if os.path.isfile(pkg):
        import json
        try:
            pj = json.load(open(pkg, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            pj = {}
            comments.append("# NOTE: package.json unreadable (%s)" % exc)
        for sec in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
            for nm, spec in (pj.get(sec) or {}).items():
                spec = str(spec)
                m = (re.match(r"^github:([^/#]+)/([^#]+?)(?:\.git)?(?:#(.+))?$", spec)
                     or re.match(r"^(?:git\+)?(?:ssh://git@|https://|git@)github\.com[:/]([^/]+)/([^#]+?)(?:\.git)?(?:#(.+))?$", spec)
                     or re.match(r"^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:#(.+))?$", spec))
                if m and is_own(m.group(1), own_orgs):
                    add(snake(m.group(2)), "git@github.com:%s/%s.git" % (m.group(1), m.group(2)), m.group(3) or "UNKNOWN-pin-me",
                        "grouped", "package.json %s %s" % (sec, nm))
                elif nm.startswith("@") and any(t in nm.lower() for t in toks):
                    comments.append("# NOTE: package.json %s %s@%s is a registry package; add its repository by hand "
                                    "if it is an own-org dependency (UNKNOWN)" % (sec, nm, spec))
    lines = ["# helix-deps.yaml - constitution 11.4.31 Submodule-Dependency Manifest",
             "# GENERATED SKELETON by verify_helix_deps_manifests.sh --scaffold. Every 'why' (and any",
             "# UNKNOWN-pin-me ref) is a placeholder the verifier REJECTS until a human writes the real value",
             "# (11.4.6: never guess). Then run: verify_helix_deps_manifests.sh --validate-file helix-deps.yaml",
             "# Guide: constitution/docs/guides/dependency_manifest_user_guide.md"]
    lines += comments
    lines += ["", "schema_version: 1", ""]
    if not entries:
        lines.append("deps: []")
    else:
        lines.append("deps:")
        for name, url, ref, layout, source in entries:
            lines += ["  - name: %s" % name,
                      "    ssh_url: %s" % url,
                      "    ref: %s" % ref,
                      '    why: "UNKNOWN: describe why this repository depends on %s (found in %s)"' % (name, source),
                      "    layout: %s" % layout,
                      ""]
    lines += ["", "transitive_handling:", "  recursive: true", "  conflict_resolution: operator-required",
              "", "language_specific_subtree: false", ""]
    return "\n".join(lines)


def scaffold(d, write, own_orgs, out, err):
    if not os.path.isdir(d):
        err.write("BLIND: %s is not a readable directory\n" % d)
        return EXIT_BLIND
    target = os.path.join(d, "helix-deps.yaml")
    if write and os.path.exists(target):
        err.write("REFUSED: %s already exists; --scaffold never overwrites (edit it, or validate it with --validate-file)\n" % target)
        return EXIT_FAIL
    text = scaffold_text(d, own_orgs)
    if not write:
        out.write(text)
        return EXIT_PASS
    fd, tmpf = tempfile.mkstemp(dir=d, prefix=".helix-deps.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    if os.path.exists(target):  # lost a race: still never overwrite
        os.unlink(tmpf)
        err.write("REFUSED: %s appeared while writing; not overwritten\n" % target)
        return EXIT_FAIL
    os.rename(tmpf, target)
    out.write("wrote %s (untracked: fill every placeholder, validate, then git add it)\n" % target)
    return EXIT_PASS


# ----------------------------------------------------------------------------- control needles + selftest
NEEDLE_GOOD = ("schema_version: 1\ndeps:\n  - name: a\n    ssh_url: git@github.com:vasic-digital/a.git\n    ref: 0123456\n"
               "    why: \"needed\"\n    layout: grouped\ntransitive_handling:\n  recursive: true\n"
               "  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n")
NEEDLE_BAD = NEEDLE_GOOD.replace("git@github.com:vasic-digital/a.git", "https://github.com/vasic-digital/a.git")
NEEDLE_DUP = NEEDLE_GOOD.replace("    layout: grouped\n", "    layout: grouped\n    layout: flat\n")


def needles_ok(own_orgs):
    """The schema validator must accept the golden-good manifest and reject the golden-bad ones; the ref
    '0123456' must survive as the string '0123456' (a lossy YAML loader would read an octal number)."""
    doc, e_good = validate_text(NEEDLE_GOOD, own_orgs)
    _, e_bad = validate_text(NEEDLE_BAD, own_orgs)
    _, e_dup = validate_text(NEEDLE_DUP, own_orgs)
    ref_ok = isinstance(doc, dict) and doc["deps"][0]["ref"] == "0123456"
    return (not e_good) and bool(e_bad) and bool(e_dup) and ref_ok


def selftest(out):
    import io
    own = {"vasic-digital", "helixdevelopment"}
    results = []
    results.append(("needles", needles_ok(own)))
    url_cases = [("https://go.googlesource.com/go", ("go.googlesource.com", "go.googlesource.com", "go")),
                 ("https://github.com/vasic-digital/a.git", ("github.com", "vasic-digital", "a")),
                 ("ssh://git@h:2222/Org/r.git", ("h", "Org", "r")), ("git@h:Org/r.git", ("h", "Org", "r")),
                 ("https://gitlab.com/g/s/r.git", ("gitlab.com", "g", "r")), ("ftp://h/o/r", None),
                 ("https://h/", None), ("https://h/a/../b", None), ("", None)]
    results.append(("url-forms", all(url_parts(u) == want for u, want in url_cases)))
    rel_cases = [("../c.git", "git@github.com:vasic-digital/e.git", "git@github.com:vasic-digital/c.git"),
                 ("../../o/r.git", "https://github.com/vasic-digital/e.git", "https://github.com/o/r.git"),
                 ("./sub", "ssh://git@h:2222/Org/e", "ssh://git@h:2222/Org/e/sub"),
                 ("git@h:o/r.git", "", "git@h:o/r.git"), ("../../../x.git", "git@h:o/e.git", None),
                 ("../x.git", "", None), ("../x.git", "../rel.git", None)]
    results.append(("relative-urls", all(resolve_url(u, b) == want for u, b, want in rel_cases)))
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

    def g(args, cwd):
        subprocess.run(["git"] + args, cwd=cwd, env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def repo(d, manifest):
        os.makedirs(d, exist_ok=True)
        g(["init", "-q"], d)
        if manifest is not None:
            open(os.path.join(d, "helix-deps.yaml"), "w").write(manifest)
            g(["add", "helix-deps.yaml"], d)
        open(os.path.join(d, "f"), "w").write("x")
        g(["add", "f"], d)
        g(["commit", "-q", "-m", "i"], d)

    empty = NEEDLE_GOOD.replace("deps:\n  - name: a\n    ssh_url: git@github.com:vasic-digital/a.git\n    ref: 0123456\n"
                                "    why: \"needed\"\n    layout: grouped\n", "deps: []\n")
    with tempfile.TemporaryDirectory() as t:
        def tree(name, leaf_manifest, extra_own=False):
            r = os.path.join(t, name)
            repo(os.path.join(r, "submodules", "a"), leaf_manifest)
            repo(os.path.join(r, "submodules", "tp"), None)
            root_manifest = NEEDLE_GOOD
            if extra_own:
                root_manifest = NEEDLE_GOOD.replace("deps:\n", "deps:\n  - name: b\n    ssh_url: git@github.com:vasic-digital/b.git\n"
                                                    "    ref: main\n    why: \"needed\"\n    layout: grouped\n", 1)
            repo(r, root_manifest)
            mods = ('[submodule "submodules/a"]\n\tpath = submodules/a\n\turl = git@github.com:vasic-digital/a.git\n'
                    '[submodule "submodules/tp"]\n\tpath = submodules/tp\n\turl = git@github.com:someone/tp.git\n')
            if extra_own:
                mods += '[submodule "submodules/b"]\n\tpath = submodules/b\n\turl = git@github.com:vasic-digital/b.git\n'
            open(os.path.join(r, ".gitmodules"), "w").write(mods)
            return r

        cases = [("golden-good", tree("good", empty), EXIT_PASS, "SKIP(third_party)\tsubmodules/tp"),
                 ("golden-bad-missing-leaf", tree("bad", None), EXIT_FAIL, "FAIL\tsubmodules/a"),
                 ("negative-control-uninit", tree("uninit", empty, extra_own=True), EXIT_BLIND, "BLIND\tsubmodules/b")]
        for label, r, want_rc, want_line in cases:
            buf = io.StringIO()
            rc = verify(r, own, buf)
            ok = rc == want_rc and want_line in buf.getvalue() and "PASS\tsubmodules/tp" not in buf.getvalue()
            results.append((label, ok))
    for label, ok in results:
        out.write("%s\t%s\n" % ("ok " if ok else "BAD", label))
    passed = sum(1 for _, ok in results if ok)
    out.write("SELFTEST %s (%d/%d)\n" % ("PASS" if passed == len(results) else "FAIL", passed, len(results)))
    return EXIT_PASS if passed == len(results) else EXIT_FAIL


# ----------------------------------------------------------------------------- CLI
def main(argv):
    out, err = sys.stdout, sys.stderr
    if yaml is None:
        out.write("BLIND\t.\tinstrument\tPyYAML is not importable by python3; nothing was verified\n")
        out.write("VERDICT: BLIND\n")
        return EXIT_BLIND
    mode, root, target, write = None, None, None, False
    orgs = os.environ.get("HELIX_OWN_ORGS") or DEFAULT_ORGS
    i = 0
    try:
        while i < len(argv):
            a = argv[i]
            if a == "--root":
                mode, root = mode or "verify", argv[i + 1]; i += 2
            elif a == "--own-orgs":
                orgs = argv[i + 1]; i += 2
            elif a == "--validate-file":
                mode, target = "validate", argv[i + 1]; i += 2
            elif a == "--scaffold":
                mode, target = "scaffold", argv[i + 1]; i += 2
            elif a == "--write":
                write = True; i += 1
            elif a == "--selftest":
                mode = "selftest"; i += 1
            elif a in ("-h", "--help"):
                out.write(__doc__ + "\n" + USAGE + "\n"); return EXIT_PASS
            else:
                err.write("unknown argument %r\n%s\n" % (a, USAGE)); return EXIT_USAGE
    except IndexError:
        err.write("missing value for %s\n%s\n" % (argv[i], USAGE)); return EXIT_USAGE
    own = {o.strip().lower() for o in orgs.split(",") if o.strip()}
    if mode is None:
        err.write("no mode given (usage: --root <project-root> is required)\n%s\n" % USAGE); return EXIT_USAGE
    if write and mode != "scaffold":
        err.write("--write is only valid with --scaffold\n%s\n" % USAGE); return EXIT_USAGE
    if not own and mode != "selftest":
        err.write("empty own-org list\n"); return EXIT_USAGE
    if mode == "selftest":
        return selftest(out)
    if not needles_ok(own or {"vasic-digital"}):
        out.write("BLIND\t.\tinstrument\tschema validator failed its control needles (golden-good rejected, "
                  "golden-bad accepted, or refs not kept as strings); no result can be trusted\nVERDICT: BLIND\n")
        return EXIT_BLIND
    if mode == "scaffold":
        return scaffold(target, write, own, out, err)
    if mode == "validate":
        try:
            text = open(target, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError) as exc:
            out.write("BLIND\t%s\tfile\tunreadable: %s\n" % (target, exc)); return EXIT_BLIND
        _, errs = validate_text(text, own)
        if errs:
            out.write("FAIL\t%s\tfile\t%s\n" % (target, "; ".join(errs))); return EXIT_FAIL
        out.write("PASS\t%s\tfile\twell-formed helix-deps.yaml\n" % target); return EXIT_PASS
    return verify(root, own, out)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
